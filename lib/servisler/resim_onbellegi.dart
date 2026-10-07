import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Ağdan gelen resimlerin (fotoğrafların küçük hâlleri, orijinaller,
/// avatarlar, GIF'ler) DİSK önbelleği.
///
/// ⚠️ Neden: `Image.network` yalnız BELLEKTE önbellekler. Uygulama her
/// açıldığında sohbetteki her fotoğraf yeniden indiriliyordu (mobil veri +
/// Cloudinary kotası). Artık bir kez inen dosya telefonda kalır; toplam boyut
/// [sinirBayt]'ı aşınca en uzun süredir kullanılmayanlar silinir ([budama]).
///
/// Yeni paket EKLENMEDİ (bkz. medya_indir_servisi notu): http + path_provider.
/// Önbellek, sistemin "önbellek" klasöründedir: telefonda yer azalırsa
/// Android burayı kendisi de temizleyebilir (resim yeniden iner, kayıp yok).
class ResimOnbellegi {
  ResimOnbellegi({
    Future<Directory> Function()? dizin,
    http.Client Function()? istemci,
    this.sinirBayt = 300 * 1024 * 1024,
  })  : _dizinSaglayici = dizin ?? _varsayilanDizin,
        _istemciSaglayici = istemci ?? http.Client.new;

  static final ResimOnbellegi instance = ResimOnbellegi();

  final Future<Directory> Function() _dizinSaglayici;
  final http.Client Function() _istemciSaglayici;

  /// Disk sınırı. Aşılınca [budama] en eski kullanılanları %80'e kadar siler.
  final int sinirBayt;

  static Future<Directory> _varsayilanDizin() async =>
      Directory('${(await getTemporaryDirectory()).path}/resim_onbellegi');

  Future<Directory>? _dizin;

  /// Aynı URL için süren indirmeler (eşzamanlı istekler TEK indirmede birleşir).
  final Map<String, Future<Uint8List>> _suren = {};

  Future<Directory> get _hazirDizin {
    return _dizin ??= () async {
      try {
        final d = await _dizinSaglayici();
        await d.create(recursive: true);
        return d;
      } catch (_) {
        _dizin = null; // sonraki çağrı yeniden denesin
        rethrow;
      }
    }();
  }

  /// URL → dosya adı. İki yönlü 32 bit FNV-1a (toplam 64 bit) + uzunluk:
  /// bu ölçekte çakışma olasılığı yok sayılabilir; paket gerektirmez.
  static String anahtar(String url) {
    var a = 0x811c9dc5;
    var b = 0x01000193 ^ 0x5bd1e995;
    final k = url.codeUnits;
    for (var i = 0; i < k.length; i++) {
      a = ((a ^ k[i]) * 0x01000193) & 0xFFFFFFFF;
      b = ((b ^ k[k.length - 1 - i]) * 0x01000193) & 0xFFFFFFFF;
    }
    String hex(int x) => x.toRadixString(16).padLeft(8, '0');
    return '${hex(a)}${hex(b)}_${k.length}';
  }

  /// URL'in önbellekteki dosyası (yoksa null). Galeriye kaydederken aynı
  /// dosyayı YENİDEN indirmemek için kullanılır.
  Future<File?> dosyasi(String url) async {
    try {
      final f = File('${(await _hazirDizin).path}/${anahtar(url)}');
      return await f.exists() && await f.length() > 0 ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Resmin baytları: önbellekte varsa diskten, yoksa indirip kaydederek.
  /// [ilerleme] yalnız ağdan inerken çağrılır (toplam bilinmiyorsa null).
  Future<Uint8List> getir(
    String url, {
    void Function(int alinan, int? toplam)? ilerleme,
  }) {
    final suren = _suren[url];
    if (suren != null) return suren;
    final f = _getir(url, ilerleme);
    _suren[url] = f;
    // whenComplete'in döndürdüğü future da hatayı taşır → yutulmalı, yoksa
    // "yakalanmamış hata" olarak global işleyiciye düşer (asıl hata zaten
    // çağırana [f] üzerinden gider).
    f.whenComplete(() => _suren.remove(url)).ignore();
    return f;
  }

  Future<Uint8List> _getir(
    String url,
    void Function(int, int?)? ilerleme,
  ) async {
    final dizin = await _hazirDizin;
    final dosya = File('${dizin.path}/${anahtar(url)}');
    try {
      if (await dosya.exists()) {
        final b = await dosya.readAsBytes();
        if (b.isNotEmpty) {
          unawaited(_dokun(dosya));
          return b;
        }
      }
    } catch (_) {
      // Okunamayan/bozuk dosya → aşağıda yeniden indirilir.
    }

    final istemci = _istemciSaglayici();
    try {
      final yanit = await istemci.send(http.Request('GET', Uri.parse(url)));
      if (yanit.statusCode != 200) {
        throw HttpException(
          'Resim indirilemedi (HTTP ${yanit.statusCode})',
          uri: Uri.tryParse(url),
        );
      }
      final toplam = yanit.contentLength;
      final parcalar = BytesBuilder(copy: false);
      var alinan = 0;
      await for (final p in yanit.stream) {
        parcalar.add(p);
        alinan += p.length;
        ilerleme?.call(alinan, toplam);
      }
      final baytlar = parcalar.takeBytes();
      if (baytlar.isEmpty) {
        throw HttpException('Resim boş geldi', uri: Uri.tryParse(url));
      }
      // Önce .part'a yaz, sonra adını değiştir: yarım kalan bir yazım
      // (uygulama kapandı, disk doldu) önbelleğe BOZUK resim olarak girmesin.
      try {
        final gecici = File('${dosya.path}.part');
        await gecici.writeAsBytes(baytlar, flush: true);
        await gecici.rename(dosya.path);
      } catch (e) {
        debugPrint('resim onbellege yazilamadi: $e');
      }
      return baytlar;
    } finally {
      istemci.close();
    }
  }

  // Son kullanım zamanı = dosyanın değiştirilme zamanı (LRU budama için).
  Future<void> _dokun(File f) async {
    try {
      await f.setLastModified(DateTime.now());
    } catch (_) {}
  }

  /// Toplam boyut [sinirBayt]'ı aşıyorsa en uzun süredir kullanılmayan
  /// dosyaları, toplam sınırın %80'ine inene kadar siler. Yarım kalmış
  /// (.part) eski dosyaları da temizler. Açılışta arka planda çağrılır.
  Future<void> budama() async {
    try {
      final dizin = await _hazirDizin;
      final dosyalar = <(File, FileStat)>[];
      var toplam = 0;
      final simdi = DateTime.now();
      await for (final e in dizin.list(followLinks: false)) {
        if (e is! File) continue;
        final s = await e.stat();
        if (e.path.endsWith('.part')) {
          if (simdi.difference(s.modified) > const Duration(hours: 1)) {
            try {
              await e.delete();
            } catch (_) {}
          }
          continue;
        }
        dosyalar.add((e, s));
        toplam += s.size;
      }
      if (toplam <= sinirBayt) return;
      dosyalar.sort((x, y) => x.$2.modified.compareTo(y.$2.modified));
      final hedef = sinirBayt * 0.8;
      for (final (f, s) in dosyalar) {
        if (toplam <= hedef) break;
        try {
          await f.delete();
          toplam -= s.size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('resim onbellegi budanamadi: $e');
    }
  }
}
