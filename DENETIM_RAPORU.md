# Kod denetimi raporu — ROY MESSANGER v1.8.0

**Tarih:** 30 Eylül 2026 · **Kapsam:** tüm depo (~11 bin satır Dart, Firestore
kuralları, Android yapılandırması, betikler)

Bu dosya, düzeltmelere başlamadan ÖNCE bulunan hataların tam listesidir.
Satır numaraları **düzeltme öncesi** koda (`main` dalı, `791d87f`) göre verilmiştir.
Düzeltmesiz orijinal kod `main` dalında olduğu gibi durmaktadır.

**Durum sütunu:**
- ✅ `claude/wonderful-fermat-1yfuuh` dalında düzeltildi (henüz `main`'e alınmadı, yayınlanmadı)
- ⏳ Bekliyor — büyük değişiklik gerektiriyor (ayrıntı: `BEKLEYEN_GUVENLIK_ISLERI.md`)

**Doğrulama:** 1–4 numaralı kural açıkları Firestore emülatöründe saldırı
senaryosu çalıştırılarak **doğrulandı**. Diğer bulgular kod okunarak tespit edildi.

---

## 🔴 Kritik — güvenlik

| # | Bulgu | Yer | Durum |
|---|---|---|---|
| 1 | **Onaysız arkadaşlık:** İstek kimliğinin `{gonderen}_{alan}` olduğu kontrol edilmiyor. Saldırgan `friend_requests/kurban_saldirgan` kimlikli isteği `gonderenUid: saldirgan` ile kendisi yazıp `banaIstekVar()`'ı geçiyor → arkadaşlık kurup kurbanla sohbet açabiliyor ve mesaj atabiliyor. | `firestore.rules:31-33`, `91-93`, `108-111` | ✅ |
| 2 | **Başkalarının arasına kaldırılamaz engel:** Engel dokümanının kimliği `uidler` ile eşleştirilmiyor. `engellenenler/bob_carol` dokümanını `uidler:[bob, saldirgan]` ile yazmak Bob ile Carol'un mesajlaşmasını ve aramasını durduruyor; ikisi de engeli kaldıramıyor. Aynı eksiklik `friendships` için de var. | `firestore.rules:185-188` | ✅ |
| 3 | **Kullanıcı adı taklidi:** `users/{uid}` güncellemesinde hiçbir alan kısıtlanmıyor; kişi kendine başkasının `@adını` yazıp aramada onun gibi görünebiliyor. | `firestore.rules:60-63` | ✅ |
| 4 | **Katılımcı listesi değiştirilebiliyor:** Sohbet katılımcısı `katilimcilar` listesine üçüncü birini ekleyip tüm geçmişi ona açabiliyor ya da karşı tarafı çıkarabiliyor. | `firestore.rules:129-130` | ✅ |
| 5 | **Service account anahtarı APK içinde:** APK herkese açık dağıtılıyor; anahtar çıkarılıp istenen kapsamla token alınabilir. Hesap `firebase-adminsdk` ise veritabanına kuralları atlayan tam yönetici erişimi demektir. | `bildirim_servisi.dart:631`, `pubspec.yaml` assets | ⏳ |
| 6 | **Agora App Certificate APK içinde:** Her kanal için 24 saatlik token üretilebilir; kanal adları tahmin edilebilir (`k_<milisaniye>`). | `arama_servisi.dart:238-245` | ⏳ |

## 🟠 Yüksek

| # | Bulgu | Yer | Durum |
|---|---|---|---|
| 7 | **Kilit ekranı üstünde gösterim:** `showWhenLocked="true"` ana aktivitede kalıcı. Telefon sohbet açıkken kilitlenirse mesajlar kilit açılmadan görülebiliyor. | `AndroidManifest.xml:46` | ✅ |
| 8 | **Aramanın kendiliğinden kabul edilmesi:** `activeCalls()` henüz çalan aramaları da döndürüyor; uygulama kapalıyken arama çalarken simgeye dokunmak aramayı "Kabul"e basmadan açıyor ve mikrofonu yayına alıyor. | `main.dart:150-157` | ✅ |
| 9 | **Çıkışta bildirimler devam ediyor:** `fcmToken` silinmiyor ve `deleteToken()` çağrılmıyor. Aynı cihazda başka hesapla girilirse önceki hesabın mesaj içerikleri bildirimde görünüyor. Ayrıca `_benimAdimCache` sıfırlanmadığı için bildirimler eski kullanıcının adıyla gidiyor. | `profil_ekrani.dart:209-210`, `mesaj_servisi.dart:34` | ✅ |
| 10 | **Release sürümü debug anahtarıyla imzalı:** Başka makineden derlenen güncelleme kurulamaz. Play dışı dağıtımda Play Integrity doğrulaması başarısız olur; App Check zorlaması açılırsa tüm kullanıcılar için uygulama çalışmaz. | `build.gradle.kts:68` | ⏳ |

## 🟡 Orta — işlev hataları

| # | Bulgu | Yer | Durum |
|---|---|---|---|
| 11 | Sohbetten çıkınca `cevrimdisiYap()` çağrılıyor; uygulama açıkken kullanıcı karşı tarafa çevrimdışı görünüyor. | `sohbet_ekrani.dart:277` | ✅ |
| 12 | Yazarken 2 sn içinde ekrandan çıkılırsa zamanlayıcı iptal ediliyor, `yaziyor:false` hiç gönderilmiyor → "yazıyor…" karşı tarafta takılı kalıyor. | `sohbet_ekrani.dart:271-287` | ✅ |
| 13 | `gorulduIsaretle` ve `okunduIsaretle` build içinde koşulsuz çağrılıyor: her yeniden çizimde Firestore yazması (Spark kotası) ve uygulama arka plandayken gelen mesajlar da "görüldü" sayılıyor. | `sohbet_ekrani.dart:667-668` | ✅ |
| 14 | 90 sn'den uzun bir aramada aynı kişinin mesaj bildirimine dokunulursa `eskiAramayiTemizle` aramayı "bitti" işaretleyip konuşmayı düşürüyor. | `arama_servisi.dart:399-413`, `sohbet_ekrani.dart:146` | ✅ |
| 15 | Medya gönderiminde Firestore yazması reddedilirse (engel, arkadaşlığın bitmesi) hata yakalanmıyor, `_yukleniyor` sonsuza kadar `true` kalıyor. Aynı durum `_gifSec`, arkadaşlık isteği gönderme ve kabul etme işlemlerinde de var (düğme kalıcı pasif kalıyor). | `sohbet_ekrani.dart:581-590`, `453-465`, `profil_goruntule_ekrani.dart`, `kullanici_ara_ekrani.dart:192-212`, `arkadaslar_ekrani.dart:267` | ✅ |
| 16 | Mikrofona çok hızlı dokunulursa parmak, kayıt başlamadan kalkıyor; bitir olayı kayboluyor, kayıt açık kalıp asılıyor. | `sohbet_ekrani.dart:495-548` | ✅ |
| 17 | Bildirim etiketi alıcıya göre (`km_$hedefUid`) veriliyor; farklı arkadaşlardan gelen bildirimler birbirinin yerine geçiyor. | `bildirim_servisi.dart:605` | ✅ |
| 18 | Eski mesajlar yüklenirken akış yeniden kuruluyor, liste bir anlığına yükleniyor göstergesine düşüyor ve kaydırma konumu kayboluyor. | `sohbet_ekrani.dart:640-660` | ✅ (kısmen, bkz. bekleyenler) |
| 19 | Stream'ler build içinde oluşturuluyor (`AuthGate`, `toplamOkunmamis()`, sohbet listesi); her sekme değişiminde dinleyici yeniden kuruluyor, ekran titriyor ve fazladan okuma yapılıyor. | `auth_gate.dart:255`, `ana_kabuk.dart:387`, `sohbet_listesi_ekrani.dart:41` | ✅ |

## ⚪ Düşük / not

| # | Bulgu | Yer | Durum |
|---|---|---|---|
| 20 | Karakter kodlaması bozuk (BOM ve çift kodlanmış Türkçe karakterler); yalnızca yorumlarda ve debug çıktılarında görülüyor. | `guncelleme_servisi.dart` | ✅ |
| 21 | Güncelleme APK'sı imza ya da özet (hash) doğrulaması yapılmadan kuruluyor. | `guncelleme_servisi.dart` `indirVeKur` | ⏳ |
| 22 | Cloudinary medyası herkese açık URL'lerde; silinen mesajın medyası silinmiyor. | `medya_servisi.dart` | ⏳ |
| 23 | `HataServisi` her Flutter hatasında Firestore'a yazıyor; tekrarlayan bir çizim hatası kotayı eritebilir. | `hata_servisi.dart:42-73` | ⏳ |
| 24 | Bir kullanıcı sınırsız `usernames` kaydı (ad işgali) ve sınırsız `hatalar` raporu yazabiliyor. | `firestore.rules:69-80`, `204-207` | ⏳ |
| 25 | `fcmToken` herkese okunur (kural testi T6'da bilinen sınır olarak kabul edilmiş). | `firestore.rules:60-61` | ⏳ |

---

## Yayın için yapılacaklar

1. `claude/wonderful-fermat-1yfuuh` dalını incele ve `main`'e al.
2. Sürümü `1.8.1` yap (`pubspec.yaml` + `guncelleme_servisi.dart` → `mevcutSurum`).
3. APK'yı kendi bilgisayarında derle (imza anahtarı ve gizli dosyalar orada).
   Önce bir telefonda kilit ekranı ve arama akışını dene.
4. `firebase deploy --only firestore:rules` — yeni kurallar ancak bundan sonra geçerli olur.
5. **Acil:** Google Cloud IAM'de service account'u yalnız
   *Firebase Cloud Messaging API Admin* rolüyle sınırla ve anahtarı döndür (madde 5).
