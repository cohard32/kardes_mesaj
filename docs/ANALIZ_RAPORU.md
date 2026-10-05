# ROY MESSANGER — Hata Analizi, Geliştirme ve Tema Raporu

> Kapsam: `v1.8.0+30` (commit `791d87f`) · ~12.000 satır Dart/Kotlin/Rules incelendi.
> Yöntem: kodun tamamı satır satır okundu; güvenlik bulguları **Firestore emülatöründe
> saldırı senaryosu çalıştırılarak** doğrulandı; düzeltmeler `flutter analyze`,
> `flutter test` ve 77 senaryoluk kural testiyle sınandı.

---

## 0. Özet

| # | Bulgu | Ciddiyet | Durum |
|---|---|---|---|
| G1 | Sahte arkadaşlık isteği → **onay olmadan** arkadaş olup mesaj atma | 🔴 Kritik | ✅ Düzeltildi |
| G2 | Rastgele kimlikli `friendships`/`chats` → başkalarının sohbetini işgal | 🔴 Kritik | ✅ Düzeltildi |
| G3 | Herkes, herhangi iki kişinin arasına **kalıcı engel** koyabiliyor (DoS) | 🔴 Kritik | ✅ Düzeltildi |
| G4 | Gelecek tarihli `zaman` → "60 sn içinde silme" kuralı sonsuza uzuyor | 🟠 Yüksek | ✅ Düzeltildi |
| G5 | Profilde başkasının `@kullanıcı adı`nı gösterme (kimlik taklidi) | 🟠 Yüksek | ✅ Düzeltildi |
| G6 | Katılımcı, karşı tarafı sohbetten atabiliyor / üçüncü kişi ekleyebiliyor | 🟠 Yüksek | ✅ Düzeltildi |
| G7 | Engellenen kişi istek + bildirim yağdırabiliyor | 🟡 Orta | ✅ Düzeltildi |
| A1 | `service_account.json` APK içinde (FCM/olası admin yetkisi) | 🔴 Kritik | 📋 Öneri (mimari) |
| A2 | Agora App Certificate APK içinde + tahmin edilebilir kanal adı | 🔴 Kritik | ⚙️ Kanal adı düzeltildi, sertifika öneri |
| A3 | Sürüm APK'sı **debug anahtarıyla** imzalanıyor | 🟠 Yüksek | 📋 Öneri |
| A4 | App Check (Play Integrity) + GitHub'dan dağıtım uyumsuzluğu | 🟠 Yüksek | 📋 Öneri |
| B1 | Çıkışta FCM token silinmiyor → eski hesabın mesaj/aramaları gelmeye devam | 🟠 Yüksek | ✅ Düzeltildi |
| B2 | Arka plandayken gelen mesajlar ✓✓ "görüldü" işaretleniyor | 🟠 Yüksek | ✅ Düzeltildi |
| B3 | Her yeniden çizimde `chats/{id}`'ye yazma (kota israfı) | 🟡 Orta | ✅ Düzeltildi |
| B4 | Sohbetten çıkınca kullanıcı uygulama açıkken "çevrimdışı" görünüyor | 🟡 Orta | ✅ Düzeltildi |
| B5 | Yazarken sohbetten çıkılırsa "yazıyor…" kalıcı takılıyor | 🟡 Orta | ✅ Düzeltildi |
| B6 | `arama_iptal` push'u **tüm** CallKit çağrılarını bitiriyor | 🟡 Orta | ✅ Düzeltildi |
| B7 | "Bildirimler: kapalı" uygulama kapalıyken hiçbir şey yapmıyor | 🟡 Orta | ✅ Düzeltildi |
| B8 | Güncelleme indirmesinde HTTP durumu kontrol edilmiyor | 🟡 Orta | ✅ Düzeltildi |
| B9 | İstek gönderme hatasında buton sonsuza kadar dönüyor | 🟡 Orta | ✅ Düzeltildi |
| B10 | Video açılamazsa sonsuz spinner | 🟢 Düşük | ✅ Düzeltildi |
| B11 | Türkçe büyük harf hatası (BILDIRIMLER, avatar "I"), emoji baş harf | 🟢 Düşük | ✅ Düzeltildi |
| B12 | `guncelleme_servisi.dart` çift kodlanmış (mojibake) Türkçe | 🟢 Düşük | ✅ Düzeltildi |
| P1 | Orijinal kalite fotoğraflar 220 px balonda tam çözünürlükte decode | 🟠 Yüksek | ✅ Düzeltildi |
| P2 | Sekme değişiminde Firestore dinleyicileri yeniden kuruluyor | 🟡 Orta | ✅ Düzeltildi |
| P3 | Her bildirimde yeni OAuth token isteği (+1 ağ gidiş-dönüşü) | 🟡 Orta | ✅ Düzeltildi |
| P4 | Sayfalamada spinner yanıp sönmesi + yanlış "hepsi yüklendi" | 🟡 Orta | ✅ Düzeltildi |

> ⚠️ **Yapılması gereken tek manuel adım:** yeni kurallar sunucuya gönderilmeden
> G1–G7 açıkları canlıda açık kalır:
> ```bash
> firebase deploy --only firestore:rules
> ```
> Yeni kurallar mevcut **v1.5.4 → v1.8.0** istemcilerinin yazdığı alanlarla
> geriye dönük uyumludur (alan listeleri git geçmişinden doğrulandı).

---

## 1. Hata ve Bug Analizi

### 1.1 Güvenlik kuralları (emülatörde doğrulandı, düzeltildi)

Aşağıdaki saldırıların **hepsi** eski kurallarda `izin verildi` sonucu verdi.
Düzeltmeden sonra `tool/firestore_rules_test.mjs` içindeki G‑serisi testlerle
hem saldırının reddedildiği hem de meşru akışın (kayıt, istek kabulü, sohbet
açma, mesaj, okundu, yazıyor) çalıştığı doğrulanıyor.

#### G1 — Onaysız arkadaşlık (kritik)
**Sebep:** `friend_requests` oluşturulurken doküman kimliği doğrulanmıyordu;
`friendships` kuralı ise yalnızca `friend_requests/{karşı}_{ben}` belgesinin
**varlığına** bakıyordu.

```text
Mallory → friend_requests/alice_mallory  {gonderenUid: mallory, alanUid: alice}  ✔ (kimlik sahte)
Mallory → friendships/alice_mallory      {uidler: [alice, mallory]}             ✔ (banaIstekVar = true)
Mallory → chats/... → Alice'e mesaj                                             ✔
```
**Çözüm:** `id == auth.uid + '_' + alanUid` şartı.

#### G2 — Başkalarının sohbetini işgal (kritik)
**Sebep:** `friendships/{id}` ve `chats/{id}` kimliği içindeki uid'lerden
türetilmiş mi diye bakılmıyordu. Gerçek bir istek eline geçen biri
`friendships/carol_dave` + `chats/carol_dave` belgelerini **kendi** uid'leriyle
açabiliyordu → Carol ile Dave birbirine hiç yazamaz (sohbet belgesi var ama
katılımcı değiller → `permission-denied`).
**Çözüm:** `ciftKimligiDogru(id, uidler)` yardımcı fonksiyonu.

#### G3 — Sahte engel ile DoS (kritik)
**Sebep:** `engelli(chatId)` yalnızca `engellenenler/{chatId}` varlığına bakar,
ama oluşturma kuralı kimliği doğrulamıyordu. Herkes
`engellenenler/alice_bob {uidler:[mallory, x], engelleyen: mallory}` yazıp
Alice ile Bob'un mesajlaşmasını **kalıcı** kesebiliyordu; ikisi de belgeyi
okuyamadığı/silemediği için uygulama "engel yok" gösterip mesajlar sessizce
başarısız oluyordu.
**Çözüm:** aynı `ciftKimligiDogru` şartı.

#### G4 — Silme süresinin delinmesi
**Sebep:** Silme kuralı `request.time < zaman + 60s` diyordu ama `zaman`
istemcinin yazdığı değerdi. `zaman: 2100-01-01` ile yazılan mesaj her zaman
silinebilir (ve sohbette en altta "sabit" kalır).
**Çözüm:** `request.resource.data.zaman == request.time` (istemci zaten
`FieldValue.serverTimestamp()` kullanıyor) + izinli alan listesi.

#### G5 — `@kullanıcı adı` taklidi
**Sebep:** `users/{uid}` serbestçe yazılabildiği için `kullaniciAdi: "alice"`
yazılabiliyordu; arama ve profil ekranı bu alanı gösteriyor.
**Çözüm:** Ad yalnızca `usernames/{ad}.uid == uid` ise yazılabilir
(`getAfter` ile — kayıt transaction'ı iki belgeyi birlikte yazdığı için) ve bir
kez atandıktan sonra değişmez. Eski hesapların `profilKur` akışı korunur.

#### G6 — Sohbetten atma
**Sebep:** `chats` güncellemesinde alan kısıtı yoktu.
**Çözüm:** `affectedKeys().hasOnly(['sonMesaj','sonMesajZamani','sonMesajGonderen','okunmamis','yaziyor'])`.

#### G7 — Engelliyken istek
**Çözüm:** `friend_requests` oluşturmada `!engelli(ciftId(...))`.

### 1.2 Mimari güvenlik riskleri (öneri — kod dışı karar gerektiriyor)

**A1 · `assets/service_account.json` APK'nın içinde.** `pubspec.yaml`
`assets:` altında olduğu için her APK'da düz metin olarak bulunur
(`unzip app.apk assets/flutter_assets/assets/service_account.json`).
Bu anahtarla:
- herkes her kullanıcıya **sahte bildirim ve sahte gelen arama** (CallKit) gönderebilir;
- anahtar `firebase-adminsdk` hesabına aitse **tüm Firestore kurallarını atlayan
  tam yönetici erişimi** elde edilir — yukarıdaki kural düzeltmeleri dahil her şey
  anlamsızlaşır.

Yapılacaklar (öncelik sırasıyla):
1. GCP Konsolu → IAM → bu anahtarın hesabını kontrol et. `firebase-adminsdk-*`
   ise **hemen** yalnızca `Firebase Cloud Messaging API Admin` rolü olan yeni bir
   hizmet hesabı oluştur, eski anahtarı **sil** (eski APK'lardaki anahtar böylece ölür).
2. Kalıcı çözüm: anahtarı istemciden çıkarıp küçük bir aktarıcıya taşı
   (bkz. §2.3‑D, Cloudflare Workers — kartsız, günde 100 bin istek ücretsiz).

**A2 · Agora App Certificate (`lib/gizli.dart`) APK'ya derleniyor.** `.gitignore`
depoyu korur ama APK'yı korumaz (`strings libapp.so | grep -E '^[0-9a-f]{32}$'`).
Sertifikayı ele geçiren kişi uygulamanın App ID'si için sınırsız token üretip
dakika kotasını tüketebilir. Eskiden kanal adı `k_<milisaniye>` olduğu için
görüşme saatini kabaca bilen biri kanal adını tahmin edip **görüşmeye sessizce
katılabilirdi**.
- ✅ Kanal adı artık 128 bit kriptografik rastgele (`Random.secure()`).
- 📋 Token üretimini de aktarıcıya taşıyın; Agora konsolunda ikincil sertifika
  ekleyip birincisini devre dışı bırakın.

**A3 · Sürüm derlemesi debug anahtarıyla imzalı** (`android/app/build.gradle.kts`:
`signingConfig = signingConfigs.getByName("debug")`). Debug keystore
(`~/.android/debug.keystore`) makineye özeldir; bilgisayar değişir/sıfırlanırsa
otomatik güncelleme **kurulamaz** (imza uyuşmazlığı) ve herkes uygulamayı silip
yeniden kurmak (yerel veriyi kaybetmek) zorunda kalır.

```kotlin
// android/app/build.gradle.kts
import java.util.Properties

val imza = Properties().apply {
    val f = rootProject.file("key.properties")   // .gitignore'a ekleyin!
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    signingConfigs {
        create("release") {
            storeFile = (imza["storeFile"] as String?)?.let { file(it) }
            storePassword = imza["storePassword"] as String?
            keyAlias = imza["keyAlias"] as String?
            keyPassword = imza["keyPassword"] as String?
        }
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("release") }
    }
}
```
> Geçiş notu: imza değişince mevcut kurulumlar güncellenemez. Android 9+ için
> `apksigner rotate` ile **v3 anahtar döndürme (lineage)** kullanılarak eski
> anahtardan yenisine kesintisiz geçilebilir; 7–8 sürümlü cihazlar bir kez
> yeniden kurulum gerektirir. Keystore'u ve şifresini iki ayrı yerde yedekleyin.

**A4 · App Check + GitHub dağıtımı.** Play Integrity sağlayıcısı, uygulamanın
Google Play üzerinden tanındığını (app recognition) doğrulamaya dayanır.
Uygulama GitHub Releases'ten APK olarak dağıtıldığı için doğrulanmış istek
oranı büyük olasılıkla hiçbir zaman ~%100'e ulaşmayacak; `app_check_servisi.dart`
içindeki "oran %100 olunca zorlamayı aç" planı bu durumda **tüm kullanıcıları
kilitler**. Zorlamayı açmadan önce Konsol → App Check → Metrikler'e bakın;
Play'e çıkılmayacaksa özel (custom) sağlayıcı veya zorlamasız izleme modunda
kalmak gerekir.

**Diğer gözlemler**
- README "`google-services.json` depoda yok" diyor, ama dosya **commit'li**.
  Firebase API anahtarı gizli değildir; yine de GCP → API Anahtarları'nda
  Android uygulaması (paket adı + SHA‑1) ve API kısıtı tanımlayın.
- Cloudinary **unsigned** ön ayarı: herkes hesabınıza dosya yükleyebilir ve tüm
  aile fotoğrafları URL'i bilen herkese açıktır. Ön ayarda maksimum dosya boyutu
  ve izinli formatlar tanımlayın; gizlilik gerekiyorsa `authenticated` teslim
  türü + imzalı URL'e geçin.
- `users/{uid}.fcmToken` her girişli kullanıcıya okunur (kurallarda T6 olarak
  belgelenmiş). A1'deki aktarıcıya geçince bu alan istemcilere kapatılabilir.

### 1.3 Fonksiyonel hatalar (düzeltildi)

| Kod | Dosya | Kök neden | Çözüm |
|---|---|---|---|
| B1 | `profil_ekrani.dart`, `bildirim_servisi.dart` | `signOut()` öncesi `fcmToken` silinmiyordu. Aynı telefonda başka hesap açılınca **iki hesabın** bildirim ve gelen aramaları geliyordu. | `tokenSil()`: kayıtlı token bu cihazınkiyse siler + `deleteToken()`. Başka cihazın token'ına dokunmaz. |
| B1b | `mesaj_servisi.dart` | Bildirim başlığındaki ad önbelleği uid'den bağımsızdı → hesap değişince/ad değişince eski ad gidiyordu. | Önbellek uid'ye bağlandı; profil düzenleme ve çıkışta sıfırlanıyor. |
| B2 | `sohbet_ekrani.dart` | `gorulduIsaretle` `build()` içinden çağrılıyordu; sohbet yığında açık kalınca ekran kilitliyken / uygulama arka plandayken / üstte arama ekranı varken gelen mesajlar ✓✓ oluyordu. | Yalnız `AppLifecycleState.resumed` **ve** rota en üstteyken; rota tekrar öne gelince (`ModalRoute` bağımlılığı) bekleyenler işaretlenir. |
| B3 | aynı | Her `setState` (emoji paneli, yükleme çubuğu, engel akışı) `chats/{id}`'ye `okunmamis` yazıyordu. | ✓✓ yalnız gerçekten görülmemiş gelen mesaj varken (aynı mesaj iki kez gönderilmez). Okunmamış sayacı sohbet belgesinden canlı izlenir ve yalnız `> 0` iken sıfırlanır — gönderen sayacı mesajdan **sonra** artırdığı için bu, listede sahte "1" kalmasını da önler. |
| B4 | aynı | `dispose()` → `cevrimdisiYap()`. AnaKabuk zaten yaşam döngüsünü izliyor; sohbetten geri çıkan kullanıcı uygulama açıkken "çevrimdışı" görünüyordu (ve her durum değişikliği iki kez yazılıyordu). | Varlık yönetimi yalnız AnaKabuk'ta. |
| B5 | aynı | `dispose()` "yazmayı bıraktım" zamanlayıcısını iptal ediyordu → `yaziyor: true` kalıcı. | `dispose()`'ta açıkça `false` yazılır. |
| B6 | `bildirim_servisi.dart` | `arama_iptal` → `endAllCalls()`. A ile konuşurken C arayıp "meşgul" alınca C'nin iptal push'u A ile süren görüşmenin CallKit oturumunu bitiriyordu. | `endCall(chatId)` (CallKit kimliği = chatId); eski push'lar için `endAllCalls` yedeği. |
| B7 | `bildirim_servisi.dart`, `ayarlar_ekrani.dart` | Mesaj push'u `notification` yükü taşıdığından uygulama kapalıyken bildirimi **sistem** çiziyor; ayar yalnız ön plandaki koda bakıyordu. | Kapalıyken `km_v3_kapali` (önem: NONE = engelli kanal) yayınlanır; gönderen bu kanala yollar, sistem göstermez. |
| B8 | `guncelleme_servisi.dart` | 404/403'te GitHub'ın HTML sayfası `.apk` diye kaydedilip yükleyiciye veriliyordu. | `statusCode != 200` → anlaşılır hata. |
| B9 | `profil_goruntule_ekrani.dart`, `kullanici_ara_ekrani.dart` | `istekGonder` hatası yakalanmıyordu → `_islemde` hep `true`. (G7 sonrası engelliyken bu hata **beklenen** bir durum.) | `try/catch` + kullanıcıya mesaj. |
| B10 | `sohbet_ekrani.dart` | `VideoPlayerController.initialize()` hatası yakalanmıyordu. | Hata ikonu + iz kaydı. |
| B11 | `ayarlar_ekrani.dart`, `kullanici.dart` | Dart `toUpperCase()` dil bağımsız: `i→I`. `ad[0]` emoji ile başlayan adda vekil çiftin yarısını veriyordu. | `trBuyuk()` yardımcısı + `runes.first`. |
| B12 | `guncelleme_servisi.dart` | Dosya UTF‑8 → CP1252 → UTF‑8 çift kodlanmış (BOM + `Ã¼`, `âš ï¸`). | Bayt düzeyinde geri çevrildi. |

### 1.4 Bilinen ama bu dalda düzeltilmeyen hatalar (cihazda test gerektirir)

1. **Meşgul tespiti arka plan isolate'inde çalışmıyor.** `aktifAramaVar` bir
   Dart değişkeni; FCM arka plan handler'ı **ayrı isolate**'te çalıştığı için
   orada hep `false`. Sesli görüşmede ekran kilitlenince (çok yaygın) gelen
   ikinci çağrı CallKit'i görüşmenin üstüne açar. Çözüm (§2.3‑E).
2. **Uygulama öldürülünce kullanıcı sonsuza kadar "çevrimiçi" kalır** —
   `detached` güvenilir gelmez. Çözüm: Realtime Database `onDisconnect` (§2.3‑C).
3. **Karşı taraf düşerse arama ekranı kapanmıyor.** `onUserOffline` yalnız
   `karsiUid = null` yapıyor; 45 sn zaman aşımı bağlantıda iptal edildiği için
   ekran "Bağlanıyor…"da kalır. `onUserOffline` gelince 20 sn'lik yeniden
   bağlanma zamanlayıcısı kurun.
4. **"Titreşim" anahtarı Android 8+'da etkisiz** — titreşim kanala kilitlidir;
   `enableVibration` yalnız kanal **oluşturulurken** okunur. Titreşimsiz kanal
   varyantları (`km_v3_kedi_tsz` …) veya anahtarı kaldırıp sistem ayarına
   yönlendirme gerekir.
5. **Sayfalamada görünüm zıplıyor** — eski mesajlar listenin başına eklenince
   kaydırma konumu aynı piksel kalır, içerik kayar. Kalıcı çözüm `reverse: true`
   liste (§2.1).
6. **Açılışta güncelleme onaysız indiriliyor** (kapatılamaz pencere, mobil veri,
   sürüm notları gösterilmiyor). Bkz. §2.3‑F.
7. **`galeriyeKaydet` ana (UI) iş parçacığında dosya kopyalıyor** → büyük
   videoda ANR riski. `Thread { … runOnUiThread { result.success(..) } }.start()`.
8. **`HataServisi` her `FlutterError`'da Firestore'a yazıyor** — hatalı bir
   görsel her çizimde rapor üretir (Spark: günde 20 bin yazma). Aynı hata
   10 dk'da bir kez raporlanmalı:
   ```dart
   final _sonRapor = <String, DateTime>{};
   bool _yakinZamandaBildirildi(Object hata) {
     final anahtar = hata.toString().split('\n').first;
     final simdi = DateTime.now();
     final once = _sonRapor[anahtar];
     if (once != null && simdi.difference(once) < const Duration(minutes: 10)) return true;
     _sonRapor[anahtar] = simdi;
     return false;
   }
   ```
9. `mevcutSurum` hem `pubspec.yaml` hem `guncelleme_servisi.dart`'ta —
   unutulursa güncelleme döngüsü. `MainActivity` üzerindeki mevcut
   `MethodChannel`'a `packageManager.getPackageInfo(packageName, 0).versionName`
   döndüren bir metot eklemek yeni bağımlılık gerektirmez.
10. Android 7.x'te (kanal yok) B7 düzeltmesi uygulanmaz; orada bildirim
    yine sistemce gösterilir.

### 1.5 Hata ayıklama araçları ve yöntemleri

| İhtiyaç | Araç | Not |
|---|---|---|
| Native çökme (kamera/Agora) | **Firebase Crashlytics** (+ `firebase_crashlytics`, NDK) | Spark'ta ücretsiz. Şu anki `son_adim` "adli tıp" düzeneğinin yaptığını otomatik ve sembolik yığınla yapar. |
| Bellek (foto/video) | DevTools → Memory → *Diff snapshots* | `flutter run --profile`; P1 düzeltmesinin etkisi burada ölçülür. |
| Takılma | DevTools → Performance, `debugProfileBuildsEnabled` | Gereksiz yeniden çizimleri yakalar. |
| Firestore okuma/yazma | Konsol → Kullanım; `FirebaseFirestore.setLoggingEnabled(true)` (debug) | B3 gibi "build'de yazma" hatalarını görünür kılar. |
| Kurallar | Emülatör + `tool/firestore_rules_test.mjs` | Her kural değişikliğinde zorunlu (§4). |
| Bildirim kanalları | `adb shell dumpsys notification --noredact \| grep km_` | Kanal sesi/önemi kilitlenmiş mi? |
| FCM teslimi | `adb logcat -s FirebaseMessaging FLTFireMsgService` | "Kapalıyken gelmiyor" teşhisi. |
| Doze/pil | `adb shell dumpsys deviceidle force-idle` | Kapalı ekranda arama testi. |
| Agora | Agora Console → *Call Inspector* | Kanalda kim ne zaman katıldı/düştü. |

---

## 2. Kod Geliştirme

### 2.1 Performans

**Yapılanlar**
- **P1** Sohbet balonundaki fotoğraf/GIF `cacheWidth` ile balon genişliğinde,
  avatarlar `ResizeImage(policy: fit)` ile hedefin 2 katında decode ediliyor.
  12 MP bir fotoğraf ~48 MB yerine ~1,3 MB (3x ekranda).
- **P2** Sohbet listesi ve okunmamış rozeti akışları `State`'te önbellekte.
- **P3** FCM OAuth istemcisi uygulama ömrü boyunca tek; token'ı kendisi yeniler.
- **P4** Mesaj listesi `hasData`'ya göre; sayfalama bayrakları yalnız yeni
  limitin verisi gelince güncelleniyor.

**Öneriler**

*a) Ters liste ile zıplamasız sayfalama.* En yeni mesaj en alttadır; eski
mesajlar listenin "sonuna" eklendiği için görünüm hiç kaymaz ve yeni mesajda
otomatik kaydırma kodu (`_yeniMesajKaydir`) gereksizleşir.
```dart
// mesaj_servisi.dart
Stream<List<Mesaj>> mesajlariDinle(String chatId, {int limit = 50}) =>
    _mesajlar(chatId)
        .orderBy('zaman', descending: true)   // yeni → eski
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Mesaj.firestoreDan).toList());

// sohbet_ekrani.dart
ListView.builder(
  controller: _scrollCtrl,
  reverse: true,                       // 0. öğe EN ALTTA
  itemCount: mesajlar.length,
  itemBuilder: (c, i) => _MesajBalonu(mesaj: mesajlar[i], /* ... */),
);

void _eskiMesajKontrol() {
  final p = _scrollCtrl.position;
  if (!_hepsiYuklendi && !_eskiYukleniyor &&
      p.pixels >= p.maxScrollExtent - 120) {   // "üst" artık maxScrollExtent
    _eskiYukleniyor = true;
    setState(() => _mesajLimit += _sayfaBoyu);
  }
}
```

*b) Disk önbelleği.* `Image.network` yalnız bellek önbelleği kullanır; sohbet her
açıldığında fotoğraflar yeniden indirilir. `cached_network_image` eklenmeli
(veya Cloudinary dönüşümüyle küçük önizleme:
`.../image/upload/c_limit,w_600,q_auto/...`).

*c) Videoları tembel başlat.* Her video balonu görünür olur olmaz bir native
oynatıcı açıp ağdan tamponluyor. Cloudinary uzantıyı `.jpg` yapınca ilk kareyi
verir; oynatıcı yalnız dokununca oluşturulmalı:
```dart
String videoKapak(String url) =>
    url.contains('/video/upload/') ? url.replaceFirst(RegExp(r'\.\w+$'), '.jpg') : url;
```

*d) Sesli mesajda tek oynatıcı.* Her `_SesOynatici` kendi `AudioPlayer`'ını
yaratıyor ve aynı anda birden çok ses çalabiliyor. Paylaşılan bir
`SesOynaticiServisi` (`ValueNotifier<String?> calanMesajId`) hem kaynağı azaltır
hem "biri başlayınca diğeri dursun" davranışını verir.

*e) `arkadaslar()`* her anlık görüntüde tüm arkadaş profillerini tek tek
`get()` ediyor (N okuma). `whereIn` ile 30'arlık gruplar halinde okumak veya
satır başına `profilDinle` (sohbet listesindeki gibi) maliyeti düşürür.

### 2.2 Okunabilirlik ve yapı

| Sorun | Öneri |
|---|---|
| `sohbet_ekrani.dart` 2.380 satır (ekran + 9 widget + 300 satır emoji verisi) | `lib/ekranlar/sohbet/` klasörü: `mesaj_balonu.dart`, `ses_oynatici.dart`, `video_oynatici.dart`, `yazma_alani.dart`, `emoji_paneli.dart`, `emoji_verisi.dart`. |
| Her servis `static instance` tekil → test edilemez | `Provider`/`Riverpod` ile enjeksiyon; servislerin önüne soyut arayüz (`abstract class MesajDeposu`). Widget testleri sahte depo ile Firebase'siz koşar. |
| Arama durumu dizgi sabitleri (`'cagriliyor'`, `'kabul'`, `'red'`, `'bitti'`, `'mesgul'`) 4 dosyaya dağılmış | `enum AramaDurumu { cagriliyor, kabul, red, bitti, mesgul }` + `name`/`values.byName`. |
| Ses listesi iki yerde (`ayarlar_ekrani` + `bildirim_servisi._kediSesleri`) | Tek `const List<SesSecenegi>`; iki ekran da buradan üretir. |
| `kullanicilar/` + `users/` çift yazımı ("geçiş dönemi") | Geçiş tamamlandıysa `kullanicilar` yazımları ve kuralı kaldırılmalı. |
| `analysis_options.yaml` varsayılan | `unawaited_futures`, `discarded_futures`, `use_build_context_synchronously`, `prefer_final_locals`, `always_declare_return_types` açılmalı (B9 ve B10 türü hataları derleme anında yakalar). |
| `pubspec.yaml` açıklaması "A new Flutter project." | Gerçek açıklama. |
| Yorumlarda karışık ASCII/Türkçe (`basladi` / `başladı`) | Tek biçim; iz metinleri (log) ASCII kalabilir. |

### 2.3 Yeni özellik önerileri (örnek kodlu)

#### A) Mesaja yanıt verme (alıntı)
```dart
// modeller/mesaj.dart
final String? yanitId;        // alıntılanan mesaj
final String? yanitOnizleme;  // ilk 80 karakter / "📷 Fotoğraf"

static Map<String, dynamic> yeniMesajVerisi({
  required String gonderen, required String metin, Mesaj? yanit,
}) => {
  'gonderen': gonderen,
  'metin': metin,
  'tip': 'metin',
  'zaman': FieldValue.serverTimestamp(),
  'goruldu': false,
  if (yanit != null) ...{
    'yanitId': yanit.id,
    'yanitOnizleme': yanit.metin.length > 80 ? '${yanit.metin.substring(0, 80)}…' : yanit.metin,
  },
};
```
```dart
// sohbet_ekrani.dart — uzun basma menüsüne
ListTile(
  leading: const Icon(Icons.reply_rounded, color: Renkler.neon),
  title: Text('Yanıtla', style: Yazi.isim),
  onTap: () { Navigator.pop(context); setState(() => _yanitlanan = mesaj); _odak.requestFocus(); },
),
```
Kural: `messages` izinli alan listesine `'yanitId', 'yanitOnizleme'` ekleyin
(ve `yanitOnizleme is string && size() <= 120`).

#### B) Sohbeti sessize alma
Gönderen zaten alıcının `users/{uid}` belgesini (token için) okuyor; aynı
okumada sessiz listesi de gelir — ek maliyet yok.
```dart
// alıcı: users/{me}.sessizSohbetler: ['chatId', ...]  (arrayUnion / arrayRemove)
// bildirim_servisi.dart → hedefeBildirimGonder
final sessiz = (d?['sessizSohbetler'] as List?)?.contains(ekstraData?['chatId']) ?? false;
final kanal = sessiz ? _kanalIdFor('sessiz') : _gecerliKanal(d?['bildirimKanali'] as String?);
```

#### C) Güvenilir çevrimiçi durumu (Realtime Database, Spark'ta ücretsiz)
```dart
// pubspec: firebase_database
Future<void> varligiBaslat(String uid) async {
  final db = FirebaseDatabase.instance;
  final ref = db.ref('durum/$uid');
  db.ref('.info/connected').onValue.listen((olay) async {
    if (olay.snapshot.value != true) return;
    // Bağlantı koptuğunda SUNUCU bunu yazar — uygulama öldürülse bile.
    await ref.onDisconnect().set({'cevrimici': false, 'son': ServerValue.timestamp});
    await ref.set({'cevrimici': true, 'son': ServerValue.timestamp});
  });
}
```
```json
{ "rules": { "durum": { "$uid": {
  ".read": "auth != null",
  ".write": "auth != null && auth.uid === $uid"
} } } }
```

#### D) Sunucusuz bildirim aktarıcısı (A1/A2'nin kalıcı çözümü)
Cloudflare Workers (kartsız, 100 bin istek/gün). Hizmet hesabı anahtarı
Worker'ın gizli değişkeninde durur; istemci yalnız kendi Firebase kimlik
belirtecini gönderir. Arkadaşlık kontrolü **kullanıcının kendi belirteciyle**
Firestore REST'e sorulduğu için kurallar burada da geçerlidir.
```js
// worker.js  (npm i jose)  ·  wrangler secret put SERVICE_ACCOUNT
import { jwtVerify, createRemoteJWKSet, SignJWT, importPKCS8 } from 'jose';

const PROJE = 'kardes-mesaj';
const FS = `https://firestore.googleapis.com/v1/projects/${PROJE}/databases/(default)/documents`;
const JWKS = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));

async function erisimTokeni(env) {
  const sa = JSON.parse(env.SERVICE_ACCOUNT);
  const simdi = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore',
  }).setProtectedHeader({ alg: 'RS256' })
    .setIssuer(sa.client_email).setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(simdi).setExpirationTime(simdi + 3600)
    .sign(await importPKCS8(sa.private_key, 'RS256'));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  return (await r.json()).access_token;
}

export default {
  async fetch(req, env) {
    if (req.method !== 'POST') return new Response(null, { status: 405 });
    const idToken = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
    let uid;
    try {
      ({ payload: { sub: uid } } = await jwtVerify(idToken, JWKS, {
        issuer: `https://securetoken.google.com/${PROJE}`, audience: PROJE }));
    } catch { return new Response('kimlik', { status: 401 }); }

    const { hedefUid, mesaj } = await req.json();
    const kullanici = { headers: { Authorization: `Bearer ${idToken}` } };
    const cift = [uid, hedefUid].sort().join('_');
    // Arkadaş mı, ya da bekleyen bir istek mi var? (kurallar uygulanır)
    const izinli = (await fetch(`${FS}/friendships/${cift}`, kullanici)).ok ||
                   (await fetch(`${FS}/friend_requests/${uid}_${hedefUid}`, kullanici)).ok;
    if (!izinli) return new Response('izin yok', { status: 403 });

    const erisim = await erisimTokeni(env);
    const hedef = await (await fetch(`${FS}/users/${hedefUid}`,
      { headers: { Authorization: `Bearer ${erisim}` } })).json();
    const token = hedef.fields?.fcmToken?.stringValue;
    if (!token) return new Response('token yok', { status: 404 });

    const { notification, data, android } = mesaj;   // yalnız bilinen alanlar
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJE}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${erisim}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { token, notification, data, android } }),
    });
    return new Response(null, { status: r.status });
  },
};
```
```dart
// bildirim_servisi.dart → _gonderMesaj yerine
final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
await http.post(
  Uri.parse('https://roy-bildirim.<hesap>.workers.dev'),
  headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
  body: jsonEncode({'hedefUid': hedefUid, 'mesaj': mesajAlanlari}),
);
```
Sonra: `pubspec.yaml`'dan `assets/service_account.json` kaldırılır, eski anahtar
silinir, `users/{uid}` kuralında `fcmToken` istemcilere kapatılabilir.
Agora token'ı da aynı Worker'da üretilerek sertifika APK'dan çıkarılır.

#### E) İsolate'ler arası meşgul tespiti (§1.4‑1)
```dart
// arama_servisi.dart → _katil() sonunda
final p = await SharedPreferences.getInstance();
await p.setString('aktifArama', '$kanal|${DateTime.now().millisecondsSinceEpoch}');
// bitir() içinde
await (await SharedPreferences.getInstance()).remove('aktifArama');

// bildirim_servisi.dart → aramaMesajiIsle, case 'arama' en başında
final p = await SharedPreferences.getInstance();
await p.reload();                       // diğer isolate'in yazdığını gör
final kayit = p.getString('aktifArama')?.split('|');
final taze = kayit != null &&
    DateTime.now().millisecondsSinceEpoch - int.parse(kayit[1]) < 3 * 3600 * 1000;
if (taze && kayit[0] != data['kanal']) {
  await _mesgulBildir(data['chatId']?.toString());
  return true;
}
```
(3 saatlik tazelik sınırı, görüşme sırasında uygulama çökerse bayrağın kalıcı
kalmasını önler.)

#### F) Onaylı güncelleme
```dart
final onay = await showDialog<bool>(
  context: context,
  builder: (d) => AlertDialog(
    title: Text('Yeni sürüm: v${bilgi.surum}'),
    content: SingleChildScrollView(child: Text(bilgi.notlar)),   // sürüm notları
    actions: [
      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Sonra')),
      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Güncelle')),
    ],
  ),
);
if (onay != true) return;
```
Ek güvence: sürüm notlarına APK'nın SHA‑256 özetini yazıp indirdikten sonra
`crypto` paketiyle doğrulayın (GitHub hesabı ele geçirilirse imza zaten korur,
özet ise yarım/bozuk indirmeyi yakalar).

---

## 3. Tema Geliştirme

### 3.1 Mevcut durum
- 👍 Renk/gölge/köşe/tipografi `tema.dart`'ta merkezî; organik köşe dili tutarlı.
- 👎 Tüm değerler `static const` → **çalışma anında tema değiştirilemez**;
  her widget `Renkler.neon`'a doğrudan bağlı.
- 👎 "Hiçbir ekranda sabit renk yok" iddiasına rağmen: `Uc3DDugme` kırmızı
  gradyanı (`0xFFFF7B7B`, `0xFFD93A3A`), `zeminParlama`, `neonNokta`,
  `textSelectionTheme` sabit hex içeriyor.
- 👎 Ölçülen WCAG kontrastları (AA eşiği normal metin için 4,5:1):

| Çift | Oran | Sonuç |
|---|---|---|
| `metin` / `zemin` | 17,0 | ✅ |
| `metinSoluk` / `zemin` | 4,90 | ✅ |
| `metinSoluk` / `yuzey` (kart alt yazıları, 12 px) | **4,27** | ❌ AA altı |
| `metinSoluk` / `balonGelen` (10 px zaman damgası) | **3,65** | ❌ AA altı |
| `metinKoyu` / `neonKoyu` | 11,8 | ✅ |

  `metinSoluk`'u `#86AD72` yapmak (yüzeyde 6,2, balonda 5,3) karakteri
  bozmadan sorunu çözer.

### 3.2 Önerilen mimari: `ThemeExtension`
```dart
@immutable
class RoyRenkler extends ThemeExtension<RoyRenkler> {
  const RoyRenkler({
    required this.zemin, required this.yuzey, required this.balonGelen,
    required this.metin, required this.metinSoluk,
    required this.vurgu, required this.vurguUstu, required this.tehlike,
  });
  final Color zemin, yuzey, balonGelen, metin, metinSoluk, vurgu, vurguUstu, tehlike;

  static const neonLime = RoyRenkler(
    zemin: Color(0xFF071A10), yuzey: Color(0xFF0D2818), balonGelen: Color(0xFF16351F),
    metin: Color(0xFFEAFFD8), metinSoluk: Color(0xFF86AD72),
    vurgu: Color(0xFFB4FF3C), vurguUstu: Color(0xFF06170D), tehlike: Color(0xFFFF5A5A),
  );
  // amoled, gunIsigi, yuksekKontrast, lavanta ... (tablo 3.3)

  @override
  RoyRenkler copyWith({Color? zemin, Color? vurgu /* ... */}) => RoyRenkler(
    zemin: zemin ?? this.zemin, yuzey: yuzey, balonGelen: balonGelen, metin: metin,
    metinSoluk: metinSoluk, vurgu: vurgu ?? this.vurgu, vurguUstu: vurguUstu, tehlike: tehlike,
  );

  @override
  RoyRenkler lerp(RoyRenkler? o, double t) => o == null ? this : RoyRenkler(
    zemin: Color.lerp(zemin, o.zemin, t)!, yuzey: Color.lerp(yuzey, o.yuzey, t)!,
    balonGelen: Color.lerp(balonGelen, o.balonGelen, t)!, metin: Color.lerp(metin, o.metin, t)!,
    metinSoluk: Color.lerp(metinSoluk, o.metinSoluk, t)!, vurgu: Color.lerp(vurgu, o.vurgu, t)!,
    vurguUstu: Color.lerp(vurguUstu, o.vurguUstu, t)!, tehlike: Color.lerp(tehlike, o.tehlike, t)!,
  );
}

extension RoyTema on BuildContext {
  RoyRenkler get renk => Theme.of(this).extension<RoyRenkler>()!;
}

// Kullanım:  color: context.renk.vurgu   (Renkler.neon yerine)
```
```dart
// main.dart — seçim AyarServisi'nde kalıcı (SharedPreferences)
ValueListenableBuilder<String>(
  valueListenable: AyarServisi.instance.tema,
  builder: (_, ad, _) => MaterialApp(
    theme: AppTema.olustur(RoyTemalar.bul(ad)),   // ThemeData + extensions: [renkler]
    // ...
  ),
);
```
Türetilmiş tonlar (kenar %14, sis %12, glow %25) sabit hex yerine
`vurgu.withValues(alpha: .14)` gibi hesaplanır; böylece yeni tema = 8 renk.

### 3.3 Tema önerileri (kontrastlar hesaplandı)

| Tema | Zemin / Yüzey / Balon | Metin / Soluk | Vurgu / Üstü | metin·zemin | soluk·yüzey | soluk·balon | Kimin için |
|---|---|---|---|---|---|---|---|
| **Neon Lime** (mevcut, düzeltilmiş) | `#071A10` `#0D2818` `#16351F` | `#EAFFD8` `#86AD72` | `#B4FF3C` `#06170D` | 17,0 | 6,2 | 5,3 | Varsayılan kimlik |
| **AMOLED Gece** | `#000000` `#0B0F0C` `#141A16` | `#E8F5E0` `#8FA888` | `#B4FF3C` `#06170D` | 18,6 | 7,5 | 6,8 | OLED ekranda pil tasarrufu, gece |
| **Gün Işığı** (açık) | `#F6FAF2` `#FFFFFF` `#E6F0DF` | `#0F2416` `#4F6B45` | `#3F7A10` `#FFFFFF` | 15,5 | 6,0 | 5,1 | Dış mekân, güneş altında okunabilirlik |
| **Yüksek Kontrast** | `#000000` `#0A0A0A` `#1A1A1A` | `#FFFFFF` `#C8D6C2` | `#D4FF5C` `#000000` | 21,0 | 13,1 | 11,5 | Yaşlı aile üyeleri, az gören kullanıcılar |
| **Lavanta Gece** | `#120F1C` `#1C1830` `#262040` | `#F1ECFF` `#A79BC9` | `#C9A7FF` `#1A0F33` | 16,4 | 6,7 | 6,0 | Kişiselleştirme / farklı aile üyelerine farklı renk |

Hepsi AA'yı (4,5:1) tüm metin çiftlerinde geçer. Gün Işığı'nda vurgu/üstü
5,2 — buton yazısı kalın (w800) olduğu için yeterli.

**Kullanıcı deneyimine katkısı**
- *Erişilebilirlik:* Yüksek Kontrast + sistem yazı ölçeğine (`MediaQuery.textScaler`)
  saygı. Aile uygulamasında yaşlı kullanıcılar için en yüksek etkili tema.
- *Göz yorgunluğu:* Ayarlar'a "Neon parıltısını azalt" anahtarı
  (`Golgeler.*Glow` → boş liste). Mevcut kod zaten balon glow'unu bu sebeple azaltmış.
- *Pil:* AMOLED'de siyah pikseller kapalıdır; uzun sohbetlerde ölçülebilir fark.
- *Kişilik:* Sohbet başına vurgu rengi (WhatsApp'taki gibi) — `chats/{id}`'ye değil,
  yerel `SharedPreferences`'a `tema_<chatId>` olarak; sunucu maliyeti yok.
- *Dinamik renk (Android 12+):* `dynamic_color` paketiyle duvar kağıdından
  türetilen bir "Sistem" teması isteğe bağlı eklenebilir.

### 3.4 Uygulanabilirlik ve entegrasyon

| Adım | İş | Risk |
|---|---|---|
| 1 | `RoyRenkler` + `AppTema.olustur(renkler)`; mevcut `Renkler` sabitleri `neonLime`'a eşlenir | Yok — görünüm birebir aynı kalır |
| 2 | Ekranlarda `Renkler.x` → `context.renk.x` (≈ 200 kullanım, mekanik; `const` kaldırılması gereken yerler var) | Düşük; `flutter analyze` yakalar |
| 3 | Ayarlar'a tema seçici + `AyarServisi.tema` | Düşük |
| 4 | **Native katmanlar:** CallKit renkleri (`TemaHex`) arka plan isolate'inde okunur → seçili tema `SharedPreferences`'tan alınmalı (zil ayarının okunduğu `aramaZiliDiskten()` deseni) | Orta — gelen arama ekranı cihazda test edilmeli |
| 5 | Açılış ekranı (`launch_background.xml`, `values-night/styles.xml`) ve `SystemUiOverlayStyle` açık tema için `Brightness.dark` ikonlar | Düşük |
| 6 | Bildirim ikonu rengi (`AndroidNotificationDetails.color`) temaya bağlanabilir | Düşük |

Tahmini efor: 1–3. adımlar ~1 gün, 4–6. adımlar cihaz testleriyle ~1 gün.

---

## 4. Geliştirme Süreci

### 4.1 En iyi uygulamalar
1. **Kural değişikliği = test değişikliği.** Bu dalda bulunan 7 açığın ortak
   noktası: kurallar "olumlu" senaryoyla test edilmiş, **kimlik/alan sahteciliği**
   denenmemiş. Her `match` bloğu için en az bir "kimlik uyuşmazlığı" ve bir
   "beklenmeyen alan" negatif testi yazın.
2. **`build()` içinde yan etki yok** (ağ yazma, akış oluşturma). B2/B3/P2 hep bu.
   İnceleme kontrol listesinin ilk maddesi olmalı.
3. **Sırlar istemcide durmaz.** `.gitignore` depoyu korur, APK'yı korumaz.
4. **Tek sürüm kaynağı:** `pubspec.yaml`; Dart tarafı `--dart-define` veya
   native kanal ile okur.
5. **Dal stratejisi:** `main` her zaman yayınlanabilir; iş `ozellik/…`, `duzeltme/…`
   dallarında; commit mesajları mevcut stilde ama kapsam önekiyle
   (`kurallar:`, `arama:`, `sohbet:`).
6. **Aşamalı yayın:** kurallar önce emülatörde, sonra canlıya; istemci değişikliği
   gerektiren kural sıkılaştırmalarında önce istemci yayınlanır, eski sürüm oranı
   düşünce kural sıkılaştırılır (bu daldaki kurallar buna gerek duymaz — eski
   istemcilerle uyumlu).

### 4.2 Kod gözden geçirme kontrol listesi
- [ ] Yeni Firestore yazımı varsa kural izinli alan listesi güncellendi mi, testi var mı?
- [ ] `await` sonrası `mounted` / `context.mounted` kontrolü var mı?
- [ ] `setState` / `build` içinde ağ çağrısı var mı?
- [ ] Hata yolunda yükleme durumu (`_islemde`, spinner) sıfırlanıyor mu?
- [ ] `dispose()`'ta zamanlayıcı/abonelik/denetleyici kapatılıyor mu; kapatılan
      zamanlayıcının yapacağı iş (B5) başka yerden yapılıyor mu?
- [ ] Arka plan isolate'inde çalışacak kod bellek içi duruma güveniyor mu? (§1.4‑1)
- [ ] Kullanıcıya görünen metin Türkçe kurallara uygun mu (`trBuyuk`)?
- [ ] Yeni sır/anahtar APK'ya giriyor mu?

### 4.3 Test stratejisi

| Katman | Şimdi | Hedef |
|---|---|---|
| Kurallar | 77 senaryo (emülatör) | Her PR'da CI'da |
| Saf mantık | `test/yardimci_test.dart` (Türkçe harf, çift kimliği) | Sürüm karşılaştırma, kanal seçimi, silinebilirlik — bunları private'dan çıkarıp test edin |
| Widget | Giriş ekranı | Servis arayüzleri enjekte edilince sohbet ekranı (görüldü mantığı, engel şeridi, sayfalama) |
| Entegrasyon | Yok | `integration_test` + Firebase Emulator Suite (Auth+Firestore) ile kayıt → istek → kabul → mesaj |
| Cihaz | Elle | Arama matrisi: {Android 11, 14} × {açık, arka plan, öldürülmüş, kilit ekranı} × {sesli, görüntülü} + meşgul senaryosu |

### 4.4 Örnek CI (GitHub Actions)
```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]
jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      # Depoda olmayan sır dosyaları için yer tutucular (yalnız analiz/test)
      - run: |
          echo "const String agoraSertifika = '';" > lib/gizli.dart
          echo '{}' > assets/service_account.json
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
  kurallar:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21' }
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: |
          mkdir -p /tmp/k && cp firestore.rules tool/firestore_rules_test.mjs /tmp/k && cd /tmp/k
          npm init -y >/dev/null && npm pkg set type=module
          npm i @firebase/rules-unit-testing firebase firebase-tools
          echo '{"firestore":{"rules":"firestore.rules"},"emulators":{"firestore":{"port":8080}}}' > firebase.json
          npx firebase emulators:exec --only firestore --project demo-x "node firestore_rules_test.mjs"
```

---

## 5. Bu dalda değişen dosyalar

| Dosya | Değişiklik |
|---|---|
| `firestore.rules` | G1–G7 düzeltmeleri (`ciftId`, `ciftKimligiDogru`, `adBenim`) |
| `tool/firestore_rules_test.mjs` | 51 → 77 senaryo; mesaj testleri istemci gibi `serverTimestamp()` yazıyor |
| `lib/servisler/bildirim_servisi.dart` | `tokenSil` (B1), `endCall` (B6), kapalı kanal (B7), FCM istemci önbelleği (P3) |
| `lib/servisler/mesaj_servisi.dart` | uid'ye bağlı ad önbelleği (B1b) |
| `lib/servisler/arama_servisi.dart` | Kriptografik rastgele kanal adı (A2) |
| `lib/servisler/guncelleme_servisi.dart` | Kodlama onarımı (B12), HTTP durum kontrolü (B8) |
| `lib/ekranlar/sohbet_ekrani.dart` | B2–B5, B10, P1, P4 |
| `lib/ekranlar/sohbet_listesi_ekrani.dart`, `ana_kabuk.dart` | Akış önbelleği (P2) |
| `lib/ekranlar/profil_ekrani.dart` | Çıkışta token temizliği, ad önbelleği sıfırlama |
| `lib/ekranlar/profil_goruntule_ekrani.dart`, `kullanici_ara_ekrani.dart` | B9 |
| `lib/ekranlar/ayarlar_ekrani.dart` | B7 anahtarı, B11 |
| `lib/parcalar/kullanici_avatar.dart` | Küçültülmüş avatar decode (P1) |
| `lib/modeller/kullanici.dart`, `lib/yardimcilar/tr_metin.dart` | B11 |
| `test/yardimci_test.dart` | 7 yeni birim testi |
| `README.md` | Kural testi sayısı |

**Doğrulama:** `flutter analyze` → 0 sorun · `flutter test` → 8/8 · kural testi →
77/77 (yeni testler eski kurallarda 15 başarısızlık vererek açıkları gösteriyor).
Arama/bildirim değişiklikleri (B6, B7, P3) cihaz gerektirir; §4.3'teki matrisle
doğrulanmalıdır.
