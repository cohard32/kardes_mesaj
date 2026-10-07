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
uygulama sırası güvenlidir.

> ⚠️ **v1.9.0 APK'sını dağıtmadan ÖNCE kurallar VE dizinler yayında olmalı**
> (aşağıdaki komut ikisini birlikte yayınlar). Eski kurallarla yeni uygulamada
> şunlar **reddedilir**: yanıtlı mesaj, link içeren mesaj, mesaj düzenleme,
> tepkiler (❤️ vb.), dosya/PDF gönderme, cevapsız arama kaydı. Dizinler
> (`firestore.indexes.json`) olmadan **Medya galerisi** sekmeleri açılmaz.
> Dizinlerin kurulması birkaç dakika sürebilir (Firebase Konsolu → Firestore →
> *Dizinler* sekmesinde "Etkin" olunca hazırdır).

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

```
`android/gradle.properties` içinde `royImzaZorunlu=true` zaten açık: key.properties
olmadan sürüm derlemesi **durur** (sessizce yanlış anahtarla imzalanmaz).
Derlerken artık "UYARI: … DEBUG anahtariyla" satırı **görünmemeli**.

> İleri seviye (isteğe bağlı): güçlü parolalı **yeni** bir anahtara geçmek için
> APK İmza Şeması v3 anahtar döndürme (`apksigner rotate` + `--lineage`)
> gerekir. Android 7–8 cihazlar bu geçişi desteklemez ve uygulamayı bir kez
> silip kurmak zorunda kalır. Bunu yalnız önce bir yedek telefonda deneyerek yapın.

## 3. Yeni sürümü yayınlayın

Sürüm numarası depoda zaten `1.9.0+31` (pubspec.yaml ve `mevcutSurum` birlikte;
farklı olurlarsa `test/surum_test.dart` CI'da kırılır).
```bash
git pull
flutter pub get
flutter build apk --release --target-platform android-arm64
```
GitHub Releases'e `v1.9.0` etiketiyle yükleyin. Uygulamalar açılışta artık
**sürüm notlarını gösterip onay ister** ("Sonra" / "Bu sürümü atla" / "Güncelle").
Notlar uygulamada **düz metin** görünür (Markdown işlenmez); aşağıdaki metni
olduğu gibi sürümün açıklamasına yapıştırabilirsiniz:

```text
Neler yeni:
• Fotoğraflar önce küçük ve hızlı açılır, dokununca ORİJİNAL boyutta; fotoğraf ve videoları telefona indirme düğmesi
• Kameradan çekip gönderme, birden çok fotoğraf/video seçme, fotoğrafa açıklama
• Dosya / PDF gönderme
• Başka uygulamadan "Paylaş → ROY MESSANGER"
• Mesajı sağa kaydırınca yanıt, çift dokununca ❤️, herkesin tepkisi ayrı görünür
• Mesaj düzenleme (15 dk), sohbet içinde arama, tıklanabilir linkler
• Tarih ayraçları (Bugün / Dün / tarih), taslak, "Bunu bana hatırlat"
• Ses kaydını yukarı kaydırıp kilitleme, göndermeden önce dinleme
• Cevapsız arama kaydı, görüşmede bağlantı kalitesi, görüntülü aramada küçük pencere
• Medya galerisi (Medya / Belgeler / Linkler), Davet et, doğum günleri ve önemli günler
• Yenilenen bildirimler: gönderenin fotoğrafı, fotoğraf önizlemesi, sohbet başına ayrı bildirim, Ayarlar → Bildirimi dene
• 13 yeni bildirim sesi ve 7 zil melodisi
• Yeni 3B uygulama ikonu
```

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

> **Aktarıcı zaten kuruluysa** bu sürümle bir kez yeniden yayınlayın
> (`cd sunucu/aktarici && npx wrangler deploy`): fotoğraf mesajının bildirimde
> görünen küçük hâli yalnız yeni aktarıcıdan geçer. Yayınlamazsanız hiçbir şey
> bozulmaz; bildirimler yalnız fotoğrafsız gelir.

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
- **Cloudinary:**
  - *Settings → Upload → kardes_mesaj* ön ayarında maksimum dosya boyutunu
    (ör. 100 MB) tanımlayın. **İzinli biçimler (Allowed formats) alanını boş
    bırakın** ya da belge türlerini de ekleyin (pdf, doc, docx, xls, xlsx, ppt,
    pptx, txt, csv, zip, rar, apk): yalnız medya biçimleri yazılırsa dosya/PDF
    gönderimi "yüklenemedi" hatası verir.
  - *Settings → Security → "Allow delivery of PDF and ZIP files"* kutusunu
    işaretleyin. Ücretsiz hesaplarda varsayılan kapalıdır; kapalıyken gönderilen
    PDF/ZIP karşı tarafta **açılmaz/inmez**.

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
- [ ] Kendi metin mesajına uzun bas → Düzenle → kaydet: iki telefonda da yeni metin + "düzenlendi" görünüyor (15 dk sonra seçenek çıkmıyor)
- [ ] Mesajdaki `https://…` / `www.…` linkine dokununca tarayıcı açılıyor
- [ ] Sohbette 🔍 → kelime yaz → ↑/↓ ile eşleşmeler arasında gidiliyor, bulunan mesaj parlıyor
- [ ] Profil → Doğum günleri ve önemli günler: kendi doğum gününü ayarla, bir gün ekle; arkadaşın profilinde 🎂 görünüyor
- [ ] Hatırlatıcı testi: bugünün tarihine bir gün ekle → ertesi yıl için kurulur; yarının tarihine ekleyip telefon saatini ertesi gün 09:01'e alınca bildirim geliyor

**v1.9.0 yeni özellikleri** (1. adımdaki kurallar + dizinler yayında olmalı):

- [ ] Fotoğraf balonda hızlı (küçük hâli) görünüyor; dokununca netleşip orijinal boyutta açılıyor, iki parmakla / çift dokunarak yakınlaşıyor
- [ ] Tam ekran fotoğraf ve videoda ⬇ (Galeriye indir) → telefonun galerisinde "ROY MESSANGER" albümünde görünüyor
- [ ] Videoya dokununca tam ekran oynatıcı açılıyor (balonda artık yerinde oynamıyor)
- [ ] Sohbette gün değişiminde "Bugün", "Dün", tarih ayraçları görünüyor
- [ ] Cevaplanmayan / reddedilen arama sohbette arama kaydı olarak düşüyor; kayda dokununca geri arıyor
- [ ] 📎 → Fotoğraf çek / Video çek ile gönderme; Galeri'den birden çok seçim; her fotoğrafa ayrı açıklama
- [ ] 📎 → Belge / Dosya: PDF gönder, karşı tarafta dokununca açılıyor; uzun bas → Telefona kaydet
- [ ] Galeri / Dosyalar uygulamasında Paylaş → ROY MESSANGER → kişi seç → sohbete geliyor
- [ ] Mesajı sağa kaydır → yanıt; çift dokun → ❤️; iki kişi farklı tepki verince ikisi de görünüyor
- [ ] Yarım bırakılan mesaj sohbet listesinde "Taslak:" diye görünüyor, geri dönünce yerinde
- [ ] Mesaja uzun bas → Bunu bana hatırlat → seçilen saatte bildirim; dokununca o sohbet açılıyor
- [ ] Mikrofona basılı tut, yukarı kaydır → kilitleniyor; durdurunca dinleyip sonra gönderiliyor
- [ ] Görüşmede sinyal çubukları görünüyor; görüntülü aramada Ana ekran tuşu → küçük pencere
- [ ] Sohbette sağ üst ⋮ → Medya, belgeler ve linkler: üç sekme doluyor
- [ ] Profil / Arkadaşlar → Davet et → paylaşım menüsü açılıyor
- [ ] Doğum günü olan arkadaşın sohbetinde pasta 🎂 ve konfeti; kendi doğum gününde açılışta konfeti
- [ ] Ayarlar → Bildirim sesi: sese dokununca seçiliyor ve çalıyor; zil melodileri çalıyor
- [ ] Ayarlar → **Bildirimi dene**: seçili sesle bildirim geliyor; telefon bildirimleri kapalıysa kırmızı uyarı kartı çıkıyor
- [ ] Uygulama açıkken başka bir sohbetten mesaj: bildirimde gönderenin fotoğrafı; fotoğraf mesajında fotoğrafın kendisi
- [ ] O sohbet açıkken gelen mesaj ayrıca bildirim çalmıyor; sohbete girince bildirim çubuğundaki bildirimi kalkıyor
- [ ] İki farklı kişiden mesaj → iki ayrı bildirim (biri diğerini silmiyor)
- [ ] Ana ekranda yeni 3B ikon; Android 13+ "Temalı simgeler" açıkken tek renkli sürümü görünüyor
