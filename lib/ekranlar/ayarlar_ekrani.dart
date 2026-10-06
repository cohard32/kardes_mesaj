import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parcalar/guncelleme_akisi.dart';
import '../servisler/ayar_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/guncelleme_servisi.dart';
import '../servisler/hata_servisi.dart';
import '../servisler/ses_secenekleri.dart';
import '../tema.dart';
import '../yardimcilar/tr_metin.dart';

/// Ayarlar ekranı: görünüm (tema paleti, neon parıltısı), bildirim aç/kapa,
/// titreşim, bildirim sesi (varsayılan / sessiz / yavru kedi / çıngırak /
/// telefondan özel ses), arama zili.
class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key});

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  final _ayar = AyarServisi.instance;
  final _onizleyici = AudioPlayer();

  // Özel ses seçimi için native kanal (sistem zil sesi seçici).
  static const _sesKanali = MethodChannel('kardes_mesaj/sesler');

  @override
  void dispose() {
    _onizleyici.dispose();
    super.dispose();
  }

  Future<void> _sesSec(String deger) async {
    await _ayar.bildirimSesiAyarla(deger);
    await BildirimServisi.instance.sesGuncelle();
  }

  /// Anahtar karşı tarafa da duyurulur (yayınlanan kanal değişir) →
  /// uygulama kapalıyken gelen push'lar da ayara uyar.
  Future<void> _bildirimAcikDegistir(bool acik) async {
    await _ayar.bildirimAcikAyarla(acik);
    try {
      await BildirimServisi.instance.kanalYayinla();
    } catch (_) {}
  }

  /// Titreşim de KANALA kilitli (Android 8+) → anahtar, yayınlanan kanalı
  /// titreşimsiz varyanta (`_tsz`) çevirir; karşı taraf push'u ona gönderir.
  /// ⚠️ Eskiden yalnız yerel ayar değişiyordu → uygulama kapalıyken gelen
  /// bildirimler (sistemin çizdiği) titremeye devam ediyordu.
  Future<void> _titresimDegistir(bool acik) async {
    await _ayar.titresimAcikAyarla(acik);
    try {
      await BildirimServisi.instance.kanalYayinla();
    } catch (_) {}
  }

  Future<void> _onizle(String asset) async {
    try {
      await _onizleyici.stop();
      await _onizleyici.play(AssetSource(asset));
    } catch (_) {}
  }

  Future<void> _telefondanSec() async {
    try {
      final r = await _sesKanali.invokeMethod<dynamic>(
        'sesSec',
        {'mevcut': _ayar.ozelSesUri.value},
      );
      if (r is Map) {
        final uri = r['uri'] as String?;
        final ad = (r['ad'] as String?) ?? 'Özel ses';
        if (uri != null) {
          await _ayar.ozelSesAyarla(uri, ad);
          await _sesSec(ozelSesAnahtari);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ses seçilemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Zemin(
        child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // GÖRÜNÜM en üstte: tema değişince ekran (bu ekran dahil) yerinde
          // yeniden çizilir; gezinme yığını korunur (main.dart).
          const _BolumBaslik('Görünüm'),

          ValueListenableBuilder<String>(
            valueListenable: _ayar.tema,
            builder: (context, secili, _) => Column(
              children: [
                for (final p in RoyPalet.hepsi)
                  _temaKarti(p, aktif: secili == p.ad),
              ],
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.parilti,
            builder: (context, pariltiAcik, _) => _Kart(
              child: SwitchListTile(
                activeThumbColor: Renkler.neon,
                title: Text('Neon parıltısını azalt', style: Yazi.isim),
                subtitle: Text(
                    'Düğme, balon ve noktalardaki ışımayı kapatır '
                    '(göz yorgunluğu)',
                    style: Yazi.kucuk),
                // Anahtar "azalt" → ayarın (parıltı AÇIK) tersi.
                value: !pariltiAcik,
                onChanged: (azalt) => _ayar.pariltiAyarla(!azalt),
              ),
            ),
          ),

          const _BolumBaslik('Bildirimler'),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.bildirimAcik,
            builder: (context, acik, _) => _Kart(
              child: SwitchListTile(
                activeThumbColor: Renkler.neon,
                title: Text('Bildirimler', style: Yazi.isim),
                subtitle: Text('Yeni mesaj geldiğinde bildirim göster',
                    style: Yazi.kucuk),
                value: acik,
                onChanged: _bildirimAcikDegistir,
              ),
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.titresimAcik,
            builder: (context, acik, _) => _Kart(
              child: SwitchListTile(
                activeThumbColor: Renkler.neon,
                title: Text('Titreşim', style: Yazi.isim),
                subtitle: Text('Mesaj bildiriminde titreşim',
                    style: Yazi.kucuk),
                value: acik,
                onChanged: _titresimDegistir,
              ),
            ),
          ),

          const _BolumBaslik('Bildirim Sesi'),

          // Hazır sesler TEK KAYNAKTAN (kanalları da buradan kurulur).
          for (final s in sesSecenekleri)
            _sesTile(
              deger: s.anahtar,
              baslik: s.ad,
              onizlemeAsset: s.onizlemeAsset,
            ),

          // Telefondan özel ses
          ValueListenableBuilder<String?>(
            valueListenable: _ayar.ozelSesAdi,
            builder: (context, ad, _) => ValueListenableBuilder<String>(
              valueListenable: _ayar.bildirimSesi,
              builder: (context, secili, _) {
                final aktif = secili == ozelSesAnahtari;
                final var_ = _ayar.ozelSesUri.value != null;
                return _Kart(
                  secili: aktif,
                  child: ListTile(
                    leading: _SecimIsareti(aktif: aktif),
                    title: Text('Telefondan özel ses', style: Yazi.isim),
                    subtitle: Text(
                      var_ ? (ad ?? 'Özel ses') : 'Telefondaki bir sesi seç',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Yazi.kucuk,
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.folder_open, color: Renkler.neon),
                      tooltip: 'Ses seç',
                      onPressed: _telefondanSec,
                    ),
                    onTap: var_
                        ? () => _sesSec(ozelSesAnahtari)
                        : _telefondanSec,
                  ),
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Önizlemek için ▶ düğmesine dokun. "Telefondan özel ses" ile '
              'cihazındaki herhangi bir bildirim sesini seçebilirsin. Seçtiğin '
              'ses, sana mesaj/arama geldiğinde çalar (uygulama kapalıyken bile).',
              style: Yazi.zaman,
            ),
          ),

          const _BolumBaslik('Arama Zil Sesi'),

          _zilTile(
            deger: AyarServisi.zilTelefon,
            baslik: 'Telefon zil sesi 📱',
            altYazi: 'Telefonunun kendi zil sesi (önerilen)',
          ),
          _zilTile(
            deger: AyarServisi.zilVarsayilan,
            baslik: 'Uygulama zili 🔔',
            altYazi: 'ROY MESSANGER varsayılan zili',
          ),
          // Zil değeri = res/raw kaynak adı (CallKit ringtonePath).
          for (final s in zilSecenekleri)
            _zilTile(
              deger: s.rawKaynak!,
              baslik: s.ad,
              onizlemeAsset: s.onizlemeAsset,
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Seçtiğin zil, biri seni aradığında çalar (uygulama kapalıyken '
              'bile). Telefonun sessiz/titreşim modundaysa Android zili çalmaz — '
              'bu uygulamanın değil, telefonun ayarıdır. Yukarıdaki "Titreşim" '
              'anahtarı yalnız mesaj bildirimlerine uygulanır. Gelen arama, '
              'telefon sessiz modda değilse her zaman titrer — arama '
              'titreşimi uygulamadan kapatılamıyor.',
              style: Yazi.zaman,
            ),
          ),

          const _BolumBaslik('Uygulama'),

          _Kart(
            child: ListTile(
              leading: Icon(Icons.system_update, color: Renkler.neon),
              title: Text('Güncellemeleri kontrol et', style: Yazi.isim),
              subtitle: Text('Yüklü sürüm: v${GuncellemeServisi.mevcutSurum}',
                  style: Yazi.kucuk),
              trailing:
                  Icon(Icons.chevron_right, color: Renkler.metinSoluk),
              onTap: () => guncellemeAkisi(context, sessiz: false),
            ),
          ),

          _Kart(
            child: ListTile(
              leading: Icon(Icons.bug_report_outlined,
                  color: Renkler.neon),
              title: Text('Sorun bildir', style: Yazi.isim),
              subtitle: Text(
                'Son işlemlerin kaydını geliştiriciye gönderir '
                '(arama/mesaj sorunlarını çözmek için)',
                style: Yazi.kucuk,
              ),
              trailing:
                  Icon(Icons.chevron_right, color: Renkler.metinSoluk),
              onTap: () async {
                final ok = await HataServisi.instance.manuelBildir(
                  'Kullanıcı sorun bildirdi',
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Rapor gönderildi ✓ Teşekkürler!'
                        : 'Rapor gönderilemedi (bağlantı yok)'),
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Tema kartı: seçim işareti + ad + kısa açıklama + palet renk örnekleri.
  /// ⚠️ Örnekler ETKİN paletten değil kartın kendi paletinden çizilir
  /// (kullanıcı seçmeden önce nasıl görüneceğini görsün).
  Widget _temaKarti(RoyPalet p, {required bool aktif}) {
    return _Kart(
      secili: aktif,
      child: ListTile(
        leading: _SecimIsareti(aktif: aktif),
        title: Text(p.gorunenAd, style: Yazi.isim),
        subtitle: Text(_temaAciklamasi(p), style: Yazi.kucuk),
        trailing: _RenkOrnekleri(palet: p),
        onTap: aktif ? null : () => _ayar.temaAyarla(p.ad),
      ),
    );
  }

  static String _temaAciklamasi(RoyPalet p) => switch (p.ad) {
        'neonLime' => 'Varsayılan neon-yeşil',
        'amoled' => 'Saf siyah — OLED ekranda pil dostu',
        'gunIsigi' => 'Açık tema — güneş altında okunaklı',
        'yuksekKontrast' => 'En okunaklı — az gören gözler için',
        'lavanta' => 'Mor tonlu gece teması',
        _ => p.acikMi ? 'Açık tema' : 'Koyu tema',
      };

  /// ARAMA ZİLİ satırı (bildirim sesinden ayrı ayar: `AyarServisi.aramaZili`).
  /// Önizleme, gerçek zilin çalacağı yoldan (CallKit/res-raw) değil assets'ten
  /// çalar — ses dosyası aynıdır, amaç kullanıcının sesi duymasıdır.
  Widget _zilTile({
    required String deger,
    required String baslik,
    String? altYazi,
    String? onizlemeAsset,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: _ayar.aramaZili,
      builder: (context, secili, _) {
        final aktif = secili == deger;
        return _Kart(
          secili: aktif,
          child: ListTile(
            leading: _SecimIsareti(aktif: aktif),
            title: Text(baslik, style: Yazi.isim),
            subtitle: altYazi == null ? null : Text(altYazi, style: Yazi.kucuk),
            trailing: onizlemeAsset == null
                ? null
                : IconButton(
                    icon: Icon(Icons.play_circle_outline,
                        color: Renkler.neon),
                    tooltip: 'Önizle',
                    onPressed: () => _onizle(onizlemeAsset),
                  ),
            onTap: () => _ayar.aramaZiliAyarla(deger),
          ),
        );
      },
    );
  }

  Widget _sesTile({
    required String deger,
    required String baslik,
    String? onizlemeAsset,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: _ayar.bildirimSesi,
      builder: (context, secili, _) {
        final aktif = secili == deger;
        return _Kart(
          secili: aktif,
          child: ListTile(
            leading: _SecimIsareti(aktif: aktif),
            title: Text(baslik, style: Yazi.isim),
            trailing: onizlemeAsset == null
                ? null
                : IconButton(
                    icon: Icon(Icons.play_circle_outline,
                        color: Renkler.neon),
                    tooltip: 'Önizle',
                    onPressed: () => _onizle(onizlemeAsset),
                  ),
            onTap: () => _sesSec(deger),
          ),
        );
      },
    );
  }
}

/// Seçili satırın neon işareti (radyo yerine tasarım dilinde nokta).
class _SecimIsareti extends StatelessWidget {
  final bool aktif;
  const _SecimIsareti({required this.aktif});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: aktif ? null : Renkler.zeminDerin,
        gradient: aktif ? Gradyanlar.accent : null,
        shape: BoxShape.circle,
        border: Border.all(
          color: aktif ? Colors.transparent : Renkler.kenarGuclu,
        ),
        boxShadow: aktif ? Golgeler.neonGlow : null,
      ),
      child: aktif
          ? Icon(Icons.check, size: 14, color: Renkler.metinKoyu)
          : null,
    );
  }
}

/// Bir paletin zemin / yüzey / vurgu renk örnekleri (üç küçük daire).
class _RenkOrnekleri extends StatelessWidget {
  final RoyPalet palet;
  const _RenkOrnekleri({required this.palet});

  @override
  Widget build(BuildContext context) {
    Widget daire(Color renk) => Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: renk,
            shape: BoxShape.circle,
            // Kenarlık etkin paletin soluk metninden: açık bir örnek açık
            // kartta, siyah örnek siyah kartta da seçilebilsin.
            border: Border.all(
              color: Renkler.metinSoluk.withValues(alpha: 0.6),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          daire(palet.zemin),
          daire(palet.yuzey),
          daire(palet.neon),
        ],
      ),
    );
  }
}

/// Ayarlar satır kartı — organik köşe, seçiliyken neon kenar.
class _Kart extends StatelessWidget {
  final Widget child;
  final bool secili;
  const _Kart({required this.child, this.secili = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: Gradyanlar.yuzey,
          borderRadius: Kose.kartKose,
          border: Border.all(
            color: secili ? Renkler.neon.withValues(alpha: 0.45) : Renkler.kenar,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        // ⚠️ Şeffaf Material: ListTile mürekkebini en yakın Material'e çizer;
        // o da renkli Zemin'in ARKASINDA kalıyordu (dokunma dalgası
        // görünmüyordu, debug'da "ListTile ... ink splashes may be
        // invisible" doğrulaması atıyordu).
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _BolumBaslik extends StatelessWidget {
  final String yazi;
  const _BolumBaslik(this.yazi);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Text(
        trBuyuk(yazi),
        style: Yazi.stil(12, FontWeight.w800, Renkler.neon, aralik: 0.8),
      ),
    );
  }
}
