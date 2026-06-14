import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../modeller/mesaj.dart';

/// Medya (foto/video/ses) yükleme — KARTSIZ.
/// Cloudinary "unsigned upload" kullanır: gizli API anahtarı GEREKMEZ,
/// sadece cloud adı + unsigned upload preset yeterli. Firebase Storage
/// (Blaze/kart) yerine ücretsiz Cloudinary katmanı.
///
/// ⚠️ KULLANICI AYARI: cloudinary.com'da ücretsiz hesap aç →
/// Settings > Upload > "Add upload preset" → Signing Mode: **Unsigned** →
/// preset adını ve Dashboard'daki "Cloud name"i aşağıya yaz.
class MedyaServisi {
  MedyaServisi._();
  static final MedyaServisi instance = MedyaServisi._();

  // Cloudinary bilgileri (unsigned upload — gizli anahtar gerekmez)
  static const String _cloudName = 'diifisaog';
  static const String _uploadPreset = 'kardes_mesaj';

  bool get ayarliMi => _cloudName != 'CLOUD_NAME';

  /// Dosyayı Cloudinary'ye yükler, başarılıysa erişilebilir URL döner.
  /// [tip] resim/video/ses olabilir.
  Future<String?> yukle(File dosya, MesajTipi tip) async {
    if (!ayarliMi) {
      debugPrint('Cloudinary ayarlanmadı (cloud name/preset).');
      return null;
    }
    try {
      // Cloudinary kaynak türü: resim → image, video & ses → video
      final kaynak = tip == MesajTipi.resim ? 'image' : 'video';
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$kaynak/upload',
      );

      final istek = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', dosya.path));

      final yanit = await istek.send();
      final govde = await yanit.stream.bytesToString();
      if (yanit.statusCode == 200) {
        return jsonDecode(govde)['secure_url'] as String?;
      }
      debugPrint('Cloudinary hata ${yanit.statusCode}: $govde');
      return null;
    } catch (e) {
      debugPrint('Medya yükleme hatası: $e');
      return null;
    }
  }
}
