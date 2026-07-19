import 'package:flutter/material.dart';

import '../servisler/guncelleme_servisi.dart';
import '../tema.dart';

/// Güncelleme kontrol + indirme akışı (tek yerden — hem açılış hem Ayarlar).
///
/// [sessiz] = true  → AÇILIŞTA (AnaKabuk): güncelse hiçbir şey gösterme,
///                    sadece yeni sürüm varsa indirme penceresini aç.
/// [sessiz] = false → MANUEL (Ayarlar butonu): "kontrol ediliyor",
///                    "en güncelsin" ve hata mesajlarını da göster.
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

  // Yeni sürüm var → indirme penceresi (ilerleme çubuğu).
  final ilerleme = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text('Güncelleme indiriliyor (v${bilgi!.surum})',
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
  );

  try {
    await GuncellemeServisi.instance.indirVeKur(
      bilgi.apkUrl,
      (y) => ilerleme.value = y,
    );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Güncelleme indirilemedi: $e')),
      );
    }
  }
}
