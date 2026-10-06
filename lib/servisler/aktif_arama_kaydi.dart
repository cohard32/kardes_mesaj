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
/// yok sayılır. Görüşme sürerken AramaServisi kaydı [nabizAraligi]'nda bir
/// yeniden yazar (nabız); süreç ölürse (kaydırıp kapatma, native Agora
/// çökmesi, OOM, yeniden başlatma) bitir() hiç çalışmaz ama nabız da durur →
/// kayıt en geç [tazelik] içinde bayatlar. Ayrıca main() açılışta kaydı siler.
class AktifAramaKaydi {
  AktifAramaKaydi._();

  static const String _anahtar = 'aktifArama';

  /// ⚠️ Eskiden 3 SAATTİ ve nabız yoktu: süreç görüşme ortasında ölünce kayıt
  /// diskte kalıyor, 3 saat boyunca başka herkesin araması sessizce "meşgul"
  /// alıyordu (zil yok, cevapsız bildirimi yok). Artık kısa + nabızla taze.
  static const Duration tazelik = Duration(minutes: 3);

  /// Görüşme sürerken kaydın yenilenme aralığı. [tazelik]'in en az iki katı
  /// sığmalı: bir tik gecikse/kaçsa da süren görüşme bayat sayılmasın.
  static const Duration nabizAraligi = Duration(seconds: 60);

  /// yaz/sil bu isolate'te SIRAYLA çalışır. ⚠️ NEDEN: ikisi de async
  /// (getInstance + set/remove); sırasız bırakılırsa geç kalan bir nabız
  /// yazması, bitir()'in silmesinden SONRA diske inip kaydı geri getirebilirdi.
  /// Kuyruk sayesinde disk sırası = çağrı sırası.
  static Future<void> _sira = Future<void>.value();

  static Future<void> _sirala(Future<void> Function() islem) {
    final f = _sira.then((_) => islem());
    _sira = f.catchError((_) {});
    return f;
  }

  /// Kanala katılınca ve nabızda çağrılır.
  static Future<void> yaz(String chatId) => _sirala(() async {
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(
            _anahtar,
            '$chatId|${DateTime.now().millisecondsSinceEpoch}',
          );
        } catch (_) {}
      });

  /// Görüşme bitince ve uygulama açılışında (main) çağrılır.
  static Future<void> sil() => _sirala(() async {
        try {
          final p = await SharedPreferences.getInstance();
          await p.remove(_anahtar);
        } catch (_) {}
      });

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
