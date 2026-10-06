import 'package:shared_preferences/shared_preferences.dart';

/// "Şu an bir görüşmedeyim" kaydı — İSOLATE'LER ARASI.
///
/// ⚠️ NEDEN: Eskiden meşgul tespiti yalnız bellekteki `aktifAramaVar`
/// değişkenine bakıyordu. FCM arka plan handler'ı AYRI bir isolate'te
/// çalıştığı için orada bu değişken HEP false idi → sesli görüşmede ekran
/// kilitlenince (çok yaygın) gelen ikinci çağrı CallKit'i görüşmenin üstüne
/// açıyordu. SharedPreferences diskte olduğu için iki isolate da görür.
///
/// Kayıt `chatId|milisaniye` biçimindedir. [tazelik] süresinden eski kayıt
/// yok sayılır: görüşme sırasında uygulama çökerse bayrak kalıcı kalıp sonraki
/// tüm aramaları "meşgul" yapmasın.
class AktifAramaKaydi {
  AktifAramaKaydi._();

  static const String _anahtar = 'aktifArama';
  static const Duration tazelik = Duration(hours: 3);

  /// Kanala katılınca çağrılır.
  static Future<void> yaz(String chatId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _anahtar,
        '$chatId|${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {}
  }

  /// Görüşme bitince çağrılır.
  static Future<void> sil() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_anahtar);
    } catch (_) {}
  }

  /// Taze bir aktif görüşme varsa onun chatId'si, yoksa null.
  /// `reload()`: başka isolate'in yazdığı değer önbellekte değil diskte.
  static Future<String?> oku() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return cozumle(p.getString(_anahtar), DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Saf ayrıştırma (birim testi için ayrı).
  static String? cozumle(String? kayit, DateTime simdi) {
    if (kayit == null) return null;
    final i = kayit.lastIndexOf('|');
    if (i <= 0) return null;
    final ms = int.tryParse(kayit.substring(i + 1));
    if (ms == null) return null;
    final yas = simdi.difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (yas.isNegative || yas > tazelik) return null;
    return kayit.substring(0, i);
  }
}
