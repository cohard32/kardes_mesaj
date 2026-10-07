import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'hata_servisi.dart';
import 'resim_onbellegi.dart';

/// Seçilen yerel dosya (yerel dosya seçiciden).
class SecilenDosya {
  final String yol;
  final String ad;
  final int boyut;
  final String mime;
  const SecilenDosya({
    required this.yol,
    required this.ad,
    required this.boyut,
    required this.mime,
  });
}

/// Dosya/PDF mesajları: telefondan dosya seçme, indirip uygun uygulamayla
/// açma, telefonun "İndirilenler" klasörüne kaydetme.
///
/// ⚠️ Yeni paket EKLENMEDİ: seçici ve İndirilenler'e kaydetme mevcut
/// MethodChannel üzerinden (MainActivity.kt → dosyaSec / galeriyeKaydet),
/// açma zaten var olan open_filex ile.
class DosyaServisi {
  DosyaServisi._();
  static final DosyaServisi instance = DosyaServisi._();

  static const _native = MethodChannel('kardes_mesaj/sesler');

  /// Cloudinary ücretsiz planında "raw" (belge) dosya sınırı.
  static const int azamiBoyut = 10 * 1024 * 1024;

  /// Telefondan dosya seçtirir (sistem dosya seçicisi). Vazgeçilirse null.
  Future<SecilenDosya?> sec() async {
    final r = await _native.invokeMethod<Map<Object?, Object?>>('dosyaSec');
    if (r == null) return null;
    final yol = r['yol'];
    if (yol is! String) return null;
    final ad = r['ad'];
    final boyut = r['boyut'];
    final mime = r['mime'];
    return SecilenDosya(
      yol: yol,
      ad: ad is String && ad.isNotEmpty ? ad : 'dosya',
      boyut: boyut is int ? boyut : await File(yol).length(),
      mime: mime is String && mime.isNotEmpty ? mime : mimeTahmin('$ad'),
    );
  }

  // Aynı dosya aynı anda iki kez indirilmesin.
  final Map<String, Future<File>> _suren = {};

  /// Dosyayı (bir kez) telefona indirir; sonraki açılışlar diskten.
  Future<File> indir(
    String url,
    String ad, {
    void Function(double)? ilerleme,
  }) {
    return _suren[url] ??= _indir(url, ad, ilerleme)
      ..whenComplete(() => _suren.remove(url)).ignore();
  }

  Future<File> _indir(
    String url,
    String ad,
    void Function(double)? ilerleme,
  ) async {
    final kok = await getApplicationSupportDirectory();
    final dizin = Directory('${kok.path}/dosyalar');
    await dizin.create(recursive: true);
    final hedef =
        File('${dizin.path}/${ResimOnbellegi.anahtar(url)}_${guvenliAd(ad)}');
    if (await hedef.exists() && await hedef.length() > 0) return hedef;

    final gecici = File('${hedef.path}.part');
    final istemci = http.Client();
    try {
      final yanit = await istemci.send(http.Request('GET', Uri.parse(url)));
      if (yanit.statusCode != 200) {
        throw HttpException('Dosya indirilemedi (HTTP ${yanit.statusCode})');
      }
      final toplam = yanit.contentLength ?? 0;
      final sink = gecici.openWrite();
      var alinan = 0;
      try {
        await for (final p in yanit.stream) {
          sink.add(p);
          alinan += p.length;
          if (toplam > 0) ilerleme?.call(alinan / toplam);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      await gecici.rename(hedef.path);
      return hedef;
    } finally {
      istemci.close();
      try {
        if (await gecici.exists()) await gecici.delete();
      } catch (_) {}
    }
  }

  /// İndirip telefondaki uygun uygulamayla (PDF okuyucu, Word…) açar.
  /// Hata metni döner; açıldıysa null.
  Future<String?> ac(
    String url,
    String ad, {
    void Function(double)? ilerleme,
  }) async {
    try {
      final f = await indir(url, ad, ilerleme: ilerleme);
      final r = await OpenFilex.open(f.path, type: mimeTahmin(ad));
      return switch (r.type) {
        ResultType.done => null,
        ResultType.noAppToOpen =>
          'Bu dosyayı açacak uygulama yok. "Telefona kaydet" ile indirebilirsin.',
        _ => 'Dosya açılamadı.',
      };
    } catch (e) {
      HataServisi.instance.iz('DOSYA acilamadi: $e');
      return 'Dosya indirilemedi. İnternet bağlantını kontrol et.';
    }
  }

  /// Telefonun İndirilenler/ROY MESSANGER klasörüne kaydeder.
  Future<bool> telefonaKaydet(
    String url,
    String ad, {
    void Function(double)? ilerleme,
  }) async {
    try {
      final f = await indir(url, ad, ilerleme: ilerleme);
      final ok = await _native.invokeMethod<bool>('galeriyeKaydet', {
        'yol': f.path,
        'ad': guvenliAd(ad),
        'mime': mimeTahmin(ad),
      });
      return ok ?? false;
    } catch (e) {
      HataServisi.instance.iz('DOSYA kaydedilemedi: $e');
      return false;
    }
  }
}

/// "1,2 MB" gibi Türkçe boyut metni.
String boyutMetni(int bayt) {
  if (bayt < 1024) return '$bayt B';
  const birimler = ['KB', 'MB', 'GB'];
  var deger = bayt / 1024;
  var i = 0;
  while (deger >= 1024 && i < birimler.length - 1) {
    deger /= 1024;
    i++;
  }
  final metin = deger >= 10 || deger == deger.roundToDouble()
      ? deger.round().toString()
      : deger.toStringAsFixed(1).replaceAll('.', ',');
  return '$metin ${birimler[i]}';
}

/// Dosya adının uzantısı, büyük harf ("PDF"); yoksa "DOSYA".
String uzantiEtiketi(String ad) {
  final nokta = ad.lastIndexOf('.');
  if (nokta <= 0 || nokta == ad.length - 1) return 'DOSYA';
  final u = ad.substring(nokta + 1);
  return u.length > 5 ? 'DOSYA' : u.toUpperCase();
}

/// Uzantıdan MIME tahmini (açma ve İndirilenler'e kaydetme için).
String mimeTahmin(String ad) {
  return switch (uzantiEtiketi(ad)) {
    'PDF' => 'application/pdf',
    'DOC' => 'application/msword',
    'DOCX' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'XLS' => 'application/vnd.ms-excel',
    'XLSX' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'PPT' => 'application/vnd.ms-powerpoint',
    'PPTX' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'TXT' => 'text/plain',
    'CSV' => 'text/csv',
    'ZIP' => 'application/zip',
    'RAR' => 'application/vnd.rar',
    'APK' => 'application/vnd.android.package-archive',
    'JPG' || 'JPEG' => 'image/jpeg',
    'PNG' => 'image/png',
    'MP3' => 'audio/mpeg',
    'MP4' => 'video/mp4',
    _ => 'application/octet-stream',
  };
}

/// Dosya sistemi için güvenli ad: yol ayırıcı ve denetim karakterleri
/// çıkarılır, en fazla 100 karakter (uzantı korunur).
String guvenliAd(String ad) {
  var t = ad.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  if (t.isEmpty || t == '.' || t == '..') t = 'dosya';
  if (t.length <= 100) return t;
  final nokta = t.lastIndexOf('.');
  final uzanti = nokta > 0 && t.length - nokta <= 8 ? t.substring(nokta) : '';
  return t.substring(0, 100 - uzanti.length) + uzanti;
}
