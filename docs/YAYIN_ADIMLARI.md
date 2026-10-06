# Yayın Adımları — sizin yapmanız gerekenler

Bu dalda yapılan her şey kodda hazır ve test edildi. Aşağıdakiler **hesap /
kimlik bilgisi gerektirdiği için** Claude'un çalıştığı ortamdan yapılamadı.
Sıra önemlidir; adımları yukarıdan aşağıya uygulayın.

> Kısa yol: yalnız **1. ve 2. adımlar** zorunludur. Uygulama, aktarıcı (4. adım)
> kurulmadan da eskisi gibi çalışır; aktarıcı APK'daki gizli anahtarları
> çıkarmak içindir ve sonra yapılabilir.

---

## 1. Güvenlik kurallarını yayınlayın (zorunlu, ilk iş)

Kurallar 7 kritik/yüksek açığı kapatır (onaysız arkadaşlık, sahte engel,
başkasının sohbetini işgal…). Yayınlanmadan bu açıklar canlıda açıktır.
Yeni kurallar **mevcut v1.8.0 uygulamalarıyla uyumludur** — önce kural, sonra
uygulama sırası güvenlidir. (Yeni uygulama kurallardan önce çıkarsa yanıtlı
mesajlar reddedilir.)

**Seçenek A — bir kerelik, elle:**
```bash
npm i -g firebase-tools
firebase login
firebase deploy --only firestore:rules,firestore:indexes --project kardes-mesaj
```

**Seçenek B — otomatik (önerilen):** GitHub Actions her `main` push'unda
testleri çalıştırır ve geçerse kuralları kendisi yayınlar. Bir kez secret ekleyin:
1. GCP Konsolu → IAM → Hizmet Hesapları → `kardes-mesaj` → *Hizmet hesabı oluştur*
   (ör. `ci-kurallar`). Roller: **Firebase Rules Admin**, **Cloud Datastore Index
   Admin**, **Service Usage Consumer**. (Deploy yetki hatası verirse geçici olarak
   *Firebase Admin* rolüyle deneyin.)
2. *Anahtarlar → Anahtar ekle → JSON* → dosyayı indirin.
3. GitHub → depo → *Settings → Secrets and variables → Actions → New repository
   secret*: ad `FIREBASE_SERVICE_ACCOUNT`, değer: JSON dosyasının **tüm içeriği**.
4. Bu dalı `main`'e birleştirin. *Actions* sekmesinde `kurallari-yayinla` işi
   yeşil olmalı. Secret yoksa iş hata vermez, yalnız "atlandı" notu düşer.

Doğrulama: Firebase Konsolu → Firestore → *Kurallar* sekmesinde metnin başında
`ciftKimligiDogru` fonksiyonunu görmelisiniz.

## 2. İmza anahtarını güvenceye alın (zorunlu, 5 dakika)

Şu an sürüm APK'sı bilgisayarınızdaki **debug** anahtarıyla imzalanıyor
(`~/.android/debug.keystore`). Bu dosya kaybolursa (bilgisayar değişir /
sıfırlanır) hiçbir kullanıcı güncelleme **kuramaz**. En az riskli yol: **aynı**
anahtarı yedekleyip resmî sürüm anahtarı yapmak. Böylece mevcut kurulumlar
kesintisiz güncellenmeye devam eder.

```bash
# 1) Yedekle (bu dosyayı ayrıca USB'ye / parola yöneticisine koyun)
cp ~/.android/debug.keystore android/app/roy-yayin.keystore

# 2) android/key.properties oluştur (git'e GİRMEZ, .gitignore'da)
cat > android/key.properties <<'EOF'
storeFile=roy-yayin.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
EOF

# 3) Artık key.properties olmadan sürüm derlenmesin
sed -i 's/royImzaZorunlu=false/royImzaZorunlu=true/' android/gradle.properties
```
Derlerken artık "UYARI: … DEBUG anahtariyla" satırı **görünmemeli**.

> İleri seviye (isteğe bağlı): güçlü parolalı **yeni** bir anahtara geçmek için
> APK İmza Şeması v3 anahtar döndürme (`apksigner rotate` + `--lineage`)
> gerekir. Android 7–8 cihazlar bu geçişi desteklemez ve uygulamayı bir kez
> silip kurmak zorunda kalır. Bunu yalnız önce bir yedek telefonda deneyerek yapın.

## 3. Yeni sürümü yayınlayın

```bash
# pubspec.yaml: version: 1.9.0+31  ve  lib/servisler/guncelleme_servisi.dart:
# mevcutSurum = '1.9.0'  (ikisi farklıysa test/surum_test.dart CI'da kırılır)
flutter build apk --release --target-platform android-arm64
```
GitHub Releases'e `v1.9.0` etiketiyle yükleyin. Uygulamalar açılışta artık
**sürüm notlarını gösterip onay ister** ("Sonra" / "Bu sürümü atla" / "Güncelle").

## 4. Aktarıcı — APK'daki gizli anahtarları çıkarın (önerilen, sonra)

Ayrıntılı rehber: [`sunucu/aktarici/README.md`](../sunucu/aktarici/README.md).
Özet sıra:
1. 1. adım (yeni kurallar) yayında olmalı — aktarıcı token'ı yeni gizli belgeden okur.
2. GCP'de **yeni** hizmet hesabı: yalnız *Firebase Cloud Messaging API Admin* +
   *Cloud Datastore Viewer*.
3. `cd sunucu/aktarici && npm i && npx wrangler login`
   `npx wrangler secret put SERVICE_ACCOUNT < anahtar.json`
   `npx wrangler secret put AGORA_APP_CERTIFICATE`  (Agora konsolundaki sertifika)
   `npx wrangler deploy` → çıktıdaki `https://roy-aktarici.<hesap>.workers.dev` adresini not edin.
4. Uygulamayı aktarıcıyla derleyin:
   `flutter build apk --release --dart-define=AKTARICI_URL=https://roy-aktarici.<hesap>.workers.dev`
5. **Ailedeki herkes bu sürüme geçmeli** (aktarıcılı sürüm public token
   yazmaz; eski sürümdeki biri ona bildirim gönderemez). İki telefonda deneyin:
   mesaj, arkadaşlık isteği, istek kabulü, sesli/görüntülü arama, arama iptali,
   sohbeti sessize alma. Günlükler: `npx wrangler tail`.
6. Herkes geçtikten sonra:
   - `pubspec.yaml` → `assets:` altından `assets/service_account.json` satırını silin.
   - GCP'de **eski** hizmet hesabı anahtarını silin (eski APK'lardaki anahtar ölür).
   - Agora konsolunda sertifikayı yenileyin (ikincil sertifika ekle → eskiyi kapat),
     yenisini `wrangler secret put AGORA_APP_CERTIFICATE` ile girin.
   - İsteğe bağlı: `firestore.rules`'taki yorum hâlindeki "public fcmToken yasağı"
     satırlarını açıp yayınlayın.

> Sessize alma özelliği gizlilik gereği yalnız aktarıcılı derlemede görünür
> (liste artık yalnız sahibinin okuyabildiği bir belgede; kararı aktarıcı verir).

## 5. Konsol ayarları (5 dakika)

- **Firebase API anahtarı:** GCP → *API'ler ve Hizmetler → Kimlik bilgileri* →
  `AIzaSyCt…` anahtarı → *Uygulama kısıtlaması: Android uygulamaları* (paket
  `com.welat.kardes_mesaj` + imza SHA‑1'i; `keytool -list -v -keystore
  android/app/roy-yayin.keystore -storepass android` ile görülür).
- **App Check:** *İzleme* modunda bırakın, **zorlamayı açmayın.** Uygulama
  Google Play dışından (GitHub) dağıtıldığı için Play Integrity doğrulaması
  büyük olasılıkla hiç %100'e çıkmaz; zorlama tüm kullanıcıları kilitleyebilir.
- **Cloudinary:** *Settings → Upload → kardes_mesaj* ön ayarında maksimum dosya
  boyutu (ör. 100 MB) ve izinli biçimler (jpg, png, gif, webp, mp4, m4a) tanımlayın.

## 6. Telefonda kontrol listesi

Bu dalın arama/bildirim değişiklikleri gerçek cihaz gerektirir:

- [ ] Uygulama kapalıyken gelen sesli ve görüntülü arama çalıyor, kabul edilince bağlanıyor
- [ ] A ile görüşürken (ekran kilitli) C arayınca C "Meşgul" görüyor, A ile görüşme sürüyor
- [ ] Görüşme ortasında uygulamayı kaydırıp kapatın → hemen tekrar aranabiliyorsunuz (yanlış "meşgul" yok)
- [ ] Karşı taraf interneti kesince ~20 sn sonra "Bağlantı koptu" ile kapanıyor
- [ ] Ayarlar → Titreşim kapalı → bildirim titreşmiyor; Bildirimler kapalı → uygulama kapalıyken bildirim gelmiyor
- [ ] Çıkış yapınca o hesabın mesaj/aramaları artık bu telefona gelmiyor
- [ ] Geçmişi okurken yeni mesaj gelince görünüm kaymıyor; yukarı kaydırınca eski mesajlar yükleniyor
- [ ] Mesaja yanıt veriliyor, alıntı görünüyor
- [ ] Ayarlar → Görünüm'de 5 tema arasında geçiş anında oluyor, açık ekranlar kapanmıyor
- [ ] Büyük bir videoyu galeriye indirirken uygulama donmuyor
