# Bekleyen güvenlik ve mimari işleri

Eylül 2026 denetiminde bulunan ama **büyük değişiklik gerektirdiği için henüz
yapılmayan** maddeler. Küçük/yerel olanlar aynı denetimde düzeltildi
(Firestore kural açıkları, kilit ekranı, otomatik kabul, çıkışta token vb.).

## 🔴 Kritik

### 1. Service account anahtarı APK içinde
- **Nerede:** `assets/service_account.json` (pubspec assets), kullanım `lib/servisler/bildirim_servisi.dart` → `_gonderMesaj`.
- **Sorun:** APK GitHub Releases'ta herkese açık. Dosya çıkarılıp istenen
  OAuth kapsamıyla token alınabilir. Hesap `firebase-adminsdk` ise bu,
  **Firestore kurallarını tamamen atlayan yönetici erişimi** demektir; yapılan
  bütün kural düzeltmeleri bu yoldan aşılabilir.
- **Acil hafifletme (kod gerektirmez):** Google Cloud Console → IAM'de bu
  service account'un rollerini yalnızca *Firebase Cloud Messaging API Admin*
  ile sınırla (Editor/Owner/Firebase Admin rollerini kaldır). Anahtar
  sızdığı varsayılarak döndürülmeli (yeni anahtar üret, eskisini sil).
- **Kalıcı çözüm:** Push gönderimini sunucuya taşı. Seçenekler:
  Cloud Functions (Blaze gerekir), ücretsiz bir Cloudflare Worker / benzeri
  küçük sunucu (istek Firebase ID token ile doğrulanır, alıcının gerçekten
  arkadaş olduğu kontrol edilir, sonra FCM'e gönderilir).

### 2. Agora App Certificate APK içinde
- **Nerede:** `lib/gizli.dart` → `arama_servisi.dart` `_katil()` içinde `RtcTokenBuilder.build`.
- **Sorun:** Sertifikayı çıkaran herkes her kanal için 24 saatlik token
  üretebilir; kanal adları tahmin edilebilir (`k_<milisaniye>`).
- **Çözüm:** Token üretimini (1) ile aynı sunucuya taşı; sunucu yalnız
  `aramalar/{chatId}` üyelerine, o aramanın kanalı için kısa ömürlü token
  versin. Ara adım olarak kanal adına rastgele bir bileşen eklenebilir.

## 🟠 Yüksek

### 3. Release APK debug anahtarıyla imzalanıyor
- **Nerede:** `android/app/build.gradle.kts` → `signingConfig = signingConfigs.getByName("debug")`.
- **Sorun:** (a) Debug anahtarı makineye özel; başka bilgisayardan derlenen
  güncelleme mevcut kuruluma yüklenemez. (b) Play dışı dağıtımda Play
  Integrity "tanınmayan uygulama" der → App Check'te **zorlama açılırsa tüm
  kullanıcılar kırılır**.
- **Çözüm:** Kalıcı bir release keystore oluştur (yedekle!) ve
  `key.properties` ile imzala. Play'de yayınlanmayacaksa App Check zorlamasını
  AÇMA ya da farklı bir sağlayıcı değerlendir. ⚠️ İmza değişince mevcut
  kullanıcılar uygulamayı bir kez kaldırıp yeniden kurmak zorunda kalır.

### 4. Güncelleme APK'sı doğrulanmadan kuruluyor
- **Nerede:** `lib/servisler/guncelleme_servisi.dart` → `indirVeKur`.
- **Sorun:** GitHub hesabı ele geçirilirse kötü amaçlı APK herkese dağılır.
  (Android imza uyuşmazlığında kurmayı reddeder; bu yüzden 3. madde ile birlikte
  düşünülmeli.)
- **Çözüm:** Release notuna SHA-256 ekleyip indirilen dosyayı karşılaştırmak
  ya da APK imza sertifikasını kurulumdan önce doğrulamak.

## 🟡 Orta / düşük

- **Cloudinary medyası herkese açık:** URL'yi bilen herkes fotoğraf/videoyu
  görür; silinen mesajın medyası Cloudinary'de kalır. Çözüm: imzalı yükleme
  + erişim kontrollü teslim (sunucu gerektirir).
- **`fcmToken` herkese okunur** (`users/{uid}`, kural testi T6 bilinen sınır).
  1. madde çözülünce token ayrı, yalnız sunucunun okuyabildiği bir
  koleksiyona taşınabilir.
- **Kota/istismar sınırları yok:** Bir kullanıcı sınırsız `usernames` kaydı
  (ad işgali) ve sınırsız `hatalar` raporu yazabilir. `HataServisi` her Flutter
  hatasında Firestore'a yazıyor; tekrarlayan bir çizim hatası kotayı eritebilir
  → istemcide oran sınırı / aynı hatayı tekilleştirme eklenmeli.
- **Sayfalamada kaydırma konumu:** Eski mesajlar yüklenince liste artık
  spinner'a düşmüyor, ama üste eklenen mesajlar görünür konumu kaydırıyor.
  Tam çözüm için ters (reverse) liste yapısına geçmek gerekir.
