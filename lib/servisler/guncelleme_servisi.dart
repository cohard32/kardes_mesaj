import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Releases üzerinden uygulama içi otomatik güncelleme.
/// Ücretsiz: APK + sürüm bilgisi GitHub Releases'e yüklenir, uygulama
/// her açılışta son sürümü kontrol eder.
///
/// ⚠️ KULLANICI AYARI: Aşağıdaki repo bilgisini kendi GitHub reponla değiştir.
/// Release tag'i sürüm olmalı (örn. "v1.2.0") ve release'e .apk dosyası eklenmeli.
class GuncellemeServisi {
  GuncellemeServisi._();
  static final GuncellemeServisi instance = GuncellemeServisi._();

  // GitHub repo bilgisi (otomatik güncelleme buradan release çeker)
  static const String _repoOwner = 'cohard32';
  static const String _repoName = 'kardes_mesaj';

  /// Repo bilgisi henüz ayarlanmadıysa kontrolü atla.
  bool get _ayarliMi => _repoOwner != 'KULLANICI_ADI';

  /// Yeni sürüm var mı kontrol eder. Varsa bilgi döner, yoksa null.
  Future<GuncellemeBilgisi?> kontrolEt() async {
    if (!_ayarliMi) return null;
    try {
      final mevcut = (await PackageInfo.fromPlatform()).version;
      final url = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final yanit = await http.get(
        url,
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (yanit.statusCode != 200) return null;

      final json = jsonDecode(yanit.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').replaceAll('v', '');
      if (tag.isEmpty || !_yeniMi(mevcut, tag)) return null;

      // .apk uzantılı ilk asset'i bul
      final assets = json['assets'] as List<dynamic>? ?? [];
      String? apkUrl;
      for (final a in assets) {
        final ad = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (ad.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      return GuncellemeBilgisi(
        surum: tag,
        apkUrl: apkUrl,
        notlar: json['body'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('Güncelleme kontrol hatası: $e');
      return null;
    }
  }

  /// Yeni sürüm mevcuttan büyük mü? (basit semver karşılaştırması)
  bool _yeniMi(String mevcut, String yeni) {
    final m = mevcut.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final y = yeni.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < m.length ? m[i] : 0;
      final b = i < y.length ? y[i] : 0;
      if (b > a) return true;
      if (b < a) return false;
    }
    return false;
  }

  /// APK'yı indirir (ilerleme bildirir) ve kurulumu başlatır.
  Future<void> indirVeKur(
    String apkUrl,
    void Function(double yuzde) ilerleme,
  ) async {
    final istek = http.Request('GET', Uri.parse(apkUrl));
    final yanit = await http.Client().send(istek);
    final toplam = yanit.contentLength ?? 0;

    final bytes = <int>[];
    var indirilen = 0;
    await for (final parca in yanit.stream) {
      bytes.addAll(parca);
      indirilen += parca.length;
      if (toplam > 0) ilerleme(indirilen / toplam);
    }

    final dizin = await getTemporaryDirectory();
    final dosya = File('${dizin.path}/kardes_mesaj_guncelleme.apk');
    await dosya.writeAsBytes(bytes);

    // Android paket yükleyiciyi açar (REQUEST_INSTALL_PACKAGES izni gerekir)
    await OpenFilex.open(dosya.path);
  }
}

class GuncellemeBilgisi {
  final String surum;
  final String apkUrl;
  final String notlar;

  GuncellemeBilgisi({
    required this.surum,
    required this.apkUrl,
    required this.notlar,
  });
}
