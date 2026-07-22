import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'hata_servisi.dart';

/// FIREBASE APP CHECK — "isteği gerçekten BENİM uygulamam mı gönderiyor?"
///
/// NEDEN GEREKLİ: Firestore kuralları "bu kullanıcı ne yapabilir"i belirler,
/// ama isteğin nereden geldiğini belirlemez. App Check olmadan biri
/// `google-services.json` içindeki API anahtarıyla (APK'dan çıkarılabilir)
/// kendi betiğini yazıp hesap açabilir, kuralların izin verdiği her okumayı
/// otomatik yapabilir (kullanıcı numaralandırma, kota tüketme).
/// App Check ile istek, Google Play'in imzaladığı bir bütünlük belirteci
/// taşımak zorunda kalır → sahte istemci elenir.
///
/// ⚠️ SPARK (KARTSIZ) PLAN: App Check ücretsizdir, kart istemez.
///
/// ⚠️ İKİ AŞAMALI AÇILIŞ — ZORUNLU SIRA:
///   1. Bu sürüm yayınlanır. Konsolda mod "İZLEME (monitoring)" kalır →
///      belirteç göndermeyen istekler YİNE ÇALIŞIR. Hiçbir kullanıcı kırılmaz.
///   2. Konsol > App Check > Metrikler'de "doğrulanmış" oranı ~%100 olunca
///      (yani eski sürümdeki kullanıcılar güncelledikten sonra) ZORLAMA
///      (enforcement) açılır.
///   ZORLAMAYI 1. ADIMDA AÇMAK, HENÜZ GÜNCELLEMEMİŞ HERKESİN UYGULAMASINI
///   ANINDA KIRAR (tüm Firestore istekleri reddedilir).
///
/// ⚠️ Hata ASLA uygulamayı düşürmez: aktivasyon başarısız olsa bile
/// (Play Services yok, ağ yok, cihaz sertifikasyonsuz) uygulama izleme
/// modunda normal çalışmaya devam eder.
class AppCheckServisi {
  AppCheckServisi._();

  static bool _basladi = false;

  /// App Check'i etkinleştirir. Hem ana isolate'ten hem de ARKA PLAN FCM
  /// isolate'inden çağrılabilir (ikisi ayrı süreç durumudur; arka planda
  /// aktive edilmezse zorlama açıldığında çağrı bildirimi Firestore'a
  /// yazamaz → teşhis ve "meşgul" sinyali kaybolur).
  /// ⚠️ ZAMAN AŞIMI ŞART: bu çağrı `runApp`'ten ÖNCE yapılıyor (belge ilk
  /// Firestore isteğinden önce hazır olsun diye). Bu projede tam olarak bu
  /// desen daha önce başımızı yakmıştı — arama kabul akışı `runApp` öncesinde
  /// await ediliyordu ve uygulama açılışta saniyelerce DONUK görünüyordu
  /// (bkz. main.dart'taki `_oldurulmuskenKabulEdileniAc` yorumu).
  /// `activate()` normalde yerel ve hızlıdır, ama garanti edilemez → 3 saniyede
  /// dönmezse BEKLENMEZ. İzleme modunda geç aktive olmanın hiçbir zararı yok:
  /// belgesiz giden ilk istekler zaten kabul ediliyor.
  static const _sure = Duration(seconds: 3);

  static Future<void> baslat() async {
    if (_basladi) return;
    _basladi = true;
    try {
      await FirebaseAppCheck.instance
          .activate(
            // Sürüm derlemesinde Play Integrity (Google Play imzası doğrular).
            // Hata ayıklamada debug sağlayıcı: konsola bir debug token basılır,
            // Firebase Konsolu > App Check > Uygulama > "Debug token" olarak
            // eklenmelidir, yoksa geliştirme cihazı doğrulanmamış sayılır.
            providerAndroid: kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
          )
          .timeout(_sure);
      HataServisi.instance.iz('APPCHECK aktif (${kDebugMode ? "debug" : "playIntegrity"})');
    } catch (e) {
      // Yutulur: izleme modunda uygulama çalışmaya devam etmeli.
      // (TimeoutException dahil — açılışı hiçbir koşulda bloklamaz.)
      _basladi = false; // sonraki denemeye izin ver
      HataServisi.instance.iz('APPCHECK aktiflestirilemedi: $e');
    }
  }
}
