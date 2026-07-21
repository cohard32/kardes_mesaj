import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../modeller/mesaj.dart';
import 'hata_servisi.dart';

/// Sohbetteki foto/video/GIF'i TELEFON GALERİSİNE indirir.
///
/// Akış: URL → geçici dosyaya AKITARAK indir → native `galeriyeKaydet`
/// (MediaStore) ile galeriye kopyala → geçici dosyayı sil.
///
/// ⚠️ Bellek: dosya RAM'de biriktirilmez, doğrudan diske akıtılır. (Büyük
/// videoda "out of memory" hatası bu projede daha önce yaşanmıştı — APK
/// güncellemesinde; aynı hataya düşmemek için aynı desen kullanılır.)
///
/// ⚠️ Yeni paket EKLENMEDİ: galeriye yazma, zaten var olan MethodChannel
/// üzerinden MediaStore ile yapılır (Android 10+ izin gerektirmez). Bu
/// projede yeni bağımlılıklar toolchain'i kırma riski taşıdığı için tercih
/// edilen yol budur.
class MedyaIndirServisi {
  MedyaIndirServisi._();
  static final MedyaIndirServisi instance = MedyaIndirServisi._();

  static const _native = MethodChannel('kardes_mesaj/sesler');

  /// Mesaj tipinden MIME + dosya uzantısı üretir.
  ({String mime, String uzanti}) _tur(MesajTipi tip, String url) {
    final yol = Uri.tryParse(url)?.path ?? '';
    final nokta = yol.lastIndexOf('.');
    final urlUzanti =
        (nokta > 0 && yol.length - nokta <= 5) ? yol.substring(nokta + 1) : '';
    switch (tip) {
      case MesajTipi.video:
        return (mime: 'video/mp4', uzanti: urlUzanti.isEmpty ? 'mp4' : urlUzanti);
      case MesajTipi.gif:
        return (mime: 'image/gif', uzanti: 'gif');
      default:
        final u = urlUzanti.isEmpty ? 'jpg' : urlUzanti;
        final m = u.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg';
        return (mime: m, uzanti: u);
    }
  }

  /// [url]'deki medyayı galeriye kaydeder. Başarılıysa true.
  /// [ilerleme] 0..1 arası indirme yüzdesi bildirir (bilinmiyorsa çağrılmaz).
  Future<bool> galeriyeIndir(
    String url,
    MesajTipi tip, {
    void Function(double)? ilerleme,
  }) async {
    File? gecici;
    try {
      final t = _tur(tip, url);
      final ad = 'ROY_${DateTime.now().millisecondsSinceEpoch}.${t.uzanti}';
      final dizin = await getTemporaryDirectory();
      gecici = File('${dizin.path}/$ad');

      final istemci = http.Client();
      try {
        final yanit = await istemci.send(http.Request('GET', Uri.parse(url)));
        if (yanit.statusCode != 200) {
          HataServisi.instance.iz('INDIRME HTTP ${yanit.statusCode}');
          return false;
        }
        final toplam = yanit.contentLength ?? 0;
        final sink = gecici.openWrite();
        var alinan = 0;
        try {
          await for (final parca in yanit.stream) {
            sink.add(parca);
            alinan += parca.length;
            if (toplam > 0) ilerleme?.call(alinan / toplam);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      } finally {
        istemci.close();
      }

      final ok = await _native.invokeMethod<bool>('galeriyeKaydet', {
        'yol': gecici.path,
        'ad': ad,
        'mime': t.mime,
      });
      HataServisi.instance.iz('MEDYA galeriye kaydedildi=$ok');
      return ok ?? false;
    } catch (e) {
      HataServisi.instance.iz('INDIRME HATA: $e');
      return false;
    } finally {
      // Geçici kopyayı her hâlükârda temizle.
      try {
        if (gecici != null && await gecici.exists()) await gecici.delete();
      } catch (_) {}
    }
  }
}
