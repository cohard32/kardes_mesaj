import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../servisler/guncelleme_servisi.dart';
import '../tema.dart';

/// "Bu sürümü atla" ile atlanan sürümün tutulduğu SharedPreferences anahtarı.
const String atlananSurumAnahtari = 'guncellemeAtlananSurum';

/// Kullanıcının yeni sürüm penceresinde seçtiği yanıt.
enum GuncellemeKarari { sonra, guncelle, atla }

/// SAF karar: [yeniSurum] için onay penceresi gösterilmeli mi?
///
/// Açılış (sessiz) kontrolünde kullanıcının atladığı sürüm bir daha sorulmaz.
/// Manuel kontrol (Ayarlar) atlamayı YOK SAYAR — kullanıcı bilerek "kontrol
/// et"e bastıysa atladığı sürümü de görebilmeli. Daha yeni bir sürüm çıkınca
/// ([atlanan] != [yeniSurum]) yine sorulur.
bool guncellemeSorulmali({
  required String yeniSurum,
  required String? atlanan,
  required bool sessiz,
}) =>
    !sessiz || atlanan != yeniSurum;

/// Güncelleme kontrol + indirme akışı (tek yerden — hem açılış hem Ayarlar).
///
/// [sessiz] = true  → AÇILIŞTA (AnaKabuk): güncelse hiçbir şey gösterme,
///                    yeni sürüm varsa ÖNCE onay penceresi (atlanmadıysa).
/// [sessiz] = false → MANUEL (Ayarlar butonu): "kontrol ediliyor",
///                    "en güncelsin" ve hata mesajlarını da göster.
///
/// ⚠️ Eskiden yeni sürüm bulununca açılışta ONAYSIZ indirme başlıyordu:
/// kapatılamaz pencere, mobil veride habersiz onlarca MB, sürüm notları hiç
/// görünmüyordu. Artık indirme yalnız kullanıcı "Güncelle" deyince başlar.
Future<void> guncellemeAkisi(BuildContext context, {bool sessiz = true}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!sessiz) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Güncellemeler kontrol ediliyor…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  GuncellemeBilgisi? bilgi;
  try {
    bilgi = await GuncellemeServisi.instance.kontrolEt();
  } catch (e) {
    if (!sessiz && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Kontrol edilemedi: $e')),
      );
    }
    return;
  }
  if (!context.mounted) return;

  if (bilgi == null) {
    if (!sessiz) {
      messenger.showSnackBar(
        const SnackBar(content: Text('En güncel sürümü kullanıyorsun ✓')),
      );
    }
    return;
  }

  // Atlanan sürüm yalnız sessiz yolda önemli; prefs hatası akışı bozmasın.
  SharedPreferences? prefs;
  String? atlanan;
  try {
    prefs = await SharedPreferences.getInstance();
    atlanan = prefs.getString(atlananSurumAnahtari);
  } catch (_) {}
  if (!guncellemeSorulmali(
      yeniSurum: bilgi.surum, atlanan: atlanan, sessiz: sessiz)) {
    return;
  }
  if (!context.mounted) return;

  final karar = await _onaySor(context, bilgi, atlaGoster: sessiz);
  if (karar == GuncellemeKarari.atla) {
    try {
      await prefs?.setString(atlananSurumAnahtari, bilgi.surum);
    } catch (_) {}
    return;
  }
  if (karar != GuncellemeKarari.guncelle) return; // "Sonra" / dışarı dokunma
  if (!context.mounted) return;

  await _indir(context, messenger, bilgi);
}

/// Yeni sürüm penceresi: başlık + kaydırılabilir sürüm notları + düğmeler.
/// Dışarı dokunup kapatmak (null) "Sonra" sayılır.
Future<GuncellemeKarari?> _onaySor(
  BuildContext context,
  GuncellemeBilgisi bilgi, {
  required bool atlaGoster,
}) {
  final notlar = bilgi.notlar.trim();
  return showDialog<GuncellemeKarari>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Yeni sürüm: v${bilgi.surum}', style: Yazi.baslikOrta),
      // ⚠️ Uzun sürüm notları pencereyi ekrandan taşırıyordu → yükseklik
      // sınırlı + kaydırılabilir.
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(d).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Text(
            notlar.isEmpty ? 'Sürüm notu yok.' : notlar,
            style: Yazi.govde,
          ),
        ),
      ),
      actions: [
        if (atlaGoster)
          TextButton(
            onPressed: () => Navigator.pop(d, GuncellemeKarari.atla),
            child: const Text('Bu sürümü atla'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(d, GuncellemeKarari.sonra),
          child: const Text('Sonra'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(d, GuncellemeKarari.guncelle),
          child: const Text('Güncelle'),
        ),
      ],
    ),
  );
}

/// İndirme penceresi (ilerleme çubuğu) + indir ve kur.
Future<void> _indir(
  BuildContext context,
  ScaffoldMessengerState messenger,
  GuncellemeBilgisi bilgi,
) async {
  final ilerleme = ValueNotifier<double>(0);
  // ⚠️ Geri tuşu pencereyi kapatabilir (indirme arka planda sürer, bitince
  // yükleyici yine açılır). Eskiden indirme bitince KOŞULSUZ pop() yapılıyordu
  // → pencere zaten kapalıysa ALTTAKİ ekran (AnaKabuk/Ayarlar) kapanıyordu.
  // Artık yalnız pencere hâlâ açıksa kapatılır. (Geri tuşunu tamamen
  // engellemek yerine bu: ağ takılırsa kullanıcı pencerede hapsolmasın.)
  var pencereAcik = true;
  // await'SİZ (bilinçli): pencere açıkken indirme aşağıda başlar; Future
  // yalnızca pencere kapanınca biter (bkz. whenComplete).
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text('Güncelleme indiriliyor (v${bilgi.surum})',
          style: Yazi.baslikOrta),
      content: ValueListenableBuilder<double>(
        valueListenable: ilerleme,
        builder: (_, yuzde, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: yuzde > 0 ? yuzde : null,
                minHeight: 8,
                color: Renkler.neon,
                backgroundColor: Renkler.zeminDerin,
              ),
            ),
            const SizedBox(height: 12),
            Text('%${(yuzde * 100).toStringAsFixed(0)}', style: Yazi.etiket),
          ],
        ),
      ),
    ),
  ).whenComplete(() => pencereAcik = false));

  void pencereyiKapat() {
    if (pencereAcik && context.mounted) {
      pencereAcik = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  try {
    await GuncellemeServisi.instance.indirVeKur(
      bilgi.apkUrl,
      (y) => ilerleme.value = y,
    );
    pencereyiKapat();
  } catch (e) {
    pencereyiKapat();
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Güncelleme indirilemedi: $e')),
      );
    }
  } finally {
    // ⚠️ Eskiden hiç dispose edilmiyordu (sızıntı). Kapanış animasyonundaki
    // ValueListenableBuilder'ın sonradan removeListener çağırması, dispose
    // edilmiş notifier'da güvenlidir (ChangeNotifier bunu açıkça destekler).
    ilerleme.dispose();
  }
}
