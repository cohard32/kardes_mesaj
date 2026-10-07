# roy-aktarici — sunucusuz bildirim ve Agora token aktarıcısı

ROY MESSANGER için küçük bir **Cloudflare Worker**. İki işi var:

| Uç nokta | Gövde | Ne yapar |
|---|---|---|
| `POST /bildirim` | `{hedefUid, mesaj}` | Arkadaşa FCM bildirimi gönderir; arkadaş değilsen ve bekleyen isteğin varsa yalnız sabit "arkadaşlık isteği" bildirimi. |
| `POST /agora-token` | `{chatId, kanal}` | Çiftin üyesiysen o kanal için Agora RTC token'ı verir → `{"token": "..."}` |

Her istekte `Authorization: Bearer <Firebase ID token>` zorunlu; istemci
gönderirse `X-Firebase-AppCheck` aynen Firestore'a iletilir. Hatalar
`{"hata": "<kısa kod>"}` biçimindedir (iç ayrıntı istemciye verilmez, yalnız
Worker günlüğüne yazılır). İstemci tarafı: `lib/servisler/aktarici_servisi.dart`.

## Neden var?

Eskiden iki sır APK'nın **içinde** dağıtılıyordu (bkz. `docs/ANALIZ_RAPORU.md`
§1.2 A1/A2 ve §2.3‑D):

- `assets/service_account.json` — APK'yı açan herkes **herkese** sahte bildirim
  ve sahte gelen arama (CallKit) gönderebiliyordu; hesap `firebase-adminsdk`
  ise Firestore kurallarını tamamen atlayabiliyordu.
- Agora App Certificate (`lib/gizli.dart`) — herkes sınırsız Agora token
  üretip dakika kotasını tüketebiliyordu.

Aktarıcı bu sırları Cloudflare'in gizli değişkenlerinde tutar; istemci yalnız
**kendi** Firebase kimliğini gönderir.

## Mimari: yetkiyi Firestore kuralları verir

```
uygulama ──ID token──▶ aktarıcı ──(KULLANICININ token'ı)──▶ Firestore REST
                                     friendships / friend_requests / engellenenler
                          │
                          ├──(hizmet hesabı)──▶ users/{hedef}/ozel/bildirim   (fcmToken, sessizSohbetler)
                          ├──(hizmet hesabı)──▶ runQuery users where fcmToken == <o token>  (çakışma)
                          ├──(hizmet hesabı)──▶ users/{hedef}.bildirimKanali  (yayınlanan kanal)
                          ├──(hizmet hesabı)──▶ users/{gönderen}.ad           (gerçek görünen ad)
                          └──▶ FCM v1
```

- **Arkadaşlık / istek / engel** dokümanları kullanıcının **kendi ID
  token'ıyla** okunur → `firestore.rules` aynen uygulanır (var olmayan doküman
  `404`, üye olmayan `403`). Aktarıcıda kuralların ayrı bir kopyası yok; kural
  değişirse burada bir şey güncellemek gerekmez, iki yetki mantığı zamanla
  ayrışamaz.
- **Hizmet hesabı** yalnız OKUR (her okuma alan maskesiyle) ve FCM'e
  gönderir: alıcının **gizli** belgesi `users/{uid}/ozel/bildirim`
  (`fcmToken`, `sessizSohbetler` — kurallarda yalnız sahibi okur/yazar),
  alıcının yayınladığı `bildirimKanali` ve gönderenin `ad`ı. Bu yüzden ona
  yalnız şu iki rol verilir: *Firebase Cloud Messaging API Admin* +
  *Cloud Datastore Viewer* (yazamaz).
- ⚠️ `fcmToken` **yalnız gizli belgeden** okunur, herkese okunur
  `users/{uid}.fcmToken` alanı token **kaynağı** olarak **asla** kullanılmaz
  (yalnız aşağıdaki çakışma denetiminde sorgulanır). Eskiden oradan okunuyordu:
  o alan hem herkese okunur hem de sahibince serbestçe yazılabilir olduğu için
  saldırgan kurbanın token'ını kendi ikinci hesabının belgesine yazıp, o hesaba
  bekleyen bir istekle "izinli" bildirim atıyor ve push **kurbana** gidiyordu
  (yetki `hedefUid` için denetleniyor, teslimat ise o belgedeki token'a
  yapılıyordu).
- ⚠️ Gizli belgeyi yalnız sahibi yazar ama **değeri serbesttir**: saldırgan
  bugüne kadar herkese okunur olan bir kurban token'ını **kendi** ikinci
  hesabının gizli belgesine yazabilir. İki katmanlı kapatılır:
  1. **İstemci** (aktarıcılı derleme) token'ı cihaz başına **bir kez döndürür**
     (`deleteToken` → `getToken`, işaret `fcmTokenDonduruldu_v1`): public
     olmuş eski değer FCM'de `UNREGISTERED` olur, gizli belgeye yalnız hiç
     public olmamış yeni değer yazılır. Döndürme başarısızsa (çevrimdışı)
     istemci hiçbir şey yazmaz, public alanı da silmez; sonra yeniden dener.
  2. **Aktarıcı** göndermeden önce hizmet hesabıyla `users` koleksiyonunda
     `fcmToken == <gizli belgedeki değer>` sorgular (limit 2); değer hedeften
     **başka** bir uid'in public belgesinde duruyorsa `409 token_cakismasi`
     (döndürememiş ya da hâlâ eski/aktarıcısız derlemede olan kurbanın değeri
     public belgesinde durduğu için yakalanır). Hedefin **kendi** public alanı
     çakışma değildir (aktarıcısız yeni derleme ikisine de yazar). Sorgu
     başarısızsa gönderilmez (`502`). `ozel` koleksiyon **grubu** yerine
     `users` sorgulanır: eski derlemedeki kurban gizli belge hiç yazmaz, grup
     sorgusu onu göremezdi; üstelik grup sorgusu ayrı bir dizin muafiyeti
     ister, `users.fcmToken` tek alan dizini ise kendiliğinden vardır
     (⚠️ bu alan için dizin muafiyeti **eklemeyin**: sorgu `FAILED_PRECONDITION`
     verir ve her bildirim `502` olur).
- Hizmet hesabı erişim token'ı modül kapsamında **önbelleklenir** (süresi
  dolmadan 60 sn önce yenilenir) → her bildirimde Google OAuth'a gidilmez.

### `/bildirim` kuralları

1. `hedefUid` geçerli bir uid olmalı ve sen olmamalısın.
2. `mesaj` **süzülür**: yalnız `notification{title,body,image}`, `data` (tüm
   değerler string) ve bilinen `android` alanları (`priority`, `ttl`,
   `collapse_key`, `notification{channel_id, tag, visibility,
   notification_priority, sound, click_action}`) geçer; bilinmeyenler atılır.
   `notification.image` (fotoğraf mesajının bildirimdeki küçük hâli) YALNIZ
   uygulamanın Cloudinary bulutundan (`https://res.cloudinary.com/diifisaog/…`)
   olabilir; başka adres sessizce atılır (alıcının telefonuna keyfî sunucudan
   resim indirtilemez). Böylece kimse `token`/`topic`
   koyup mesajı başka birine ya da bir konuya yönlendiremez. `data.chatId`
   varsa çiftin kimliği olmalı; `data.tur` `arama` ya da `arama_iptal` ise
   `chatId` **zorunlu** (yoksa `400`).
3. İzin: `friendships/{çift}` okunabiliyor **veya** `friend_requests/{sen}_{hedef}`
   var **ve içeriği tutuyor** (`gonderenUid == sen`, `alanUid == hedef`; eski
   kurallarla başka içerikle açılmış belge `403`).
4. **Arkadaş değilsen (yalnız istek):** istemcinin gövdesi **tamamen yok
   sayılır**; aktarıcı tek bir sabit bildirim üretir:
   `{title: <senin profil adın>, body: "sana arkadaşlık isteği gönderdi"}`,
   `data` yok. (Bekleyen bir istekle sahte gelen arama çaldırılamaz, "Annen"
   başlıklı bildirim atılamaz.)
5. **Arkadaşsan:** `notification.title` her zaman senin **gerçek** profil
   adınla ezilir; `data.tur == "arama"` ise `data.arayan` (gelen arama
   ekranındaki ad) da gerçek adınla, `data.arayanUid` doğrulanmış uid ile
   yazılır. `data.gonderenUid` / `data.arayanUid` varsa her zaman
   doğrulanmış uid olur.
6. `engellenenler/{çift}` varsa yalnız **arkadaşın, tam olarak**
   `{data: {tur: "arama_iptal", chatId: <çift>}}` biçimindeki iptali geçer
   (engel tam arama çalarken konursa zil susturulabilsin). `notification`,
   `android.notification` ya da başka bir `data` alanı taşıyan her şey `403`
   (engellenen kişi "iptal" etiketiyle görünür bildirim gönderemez).
7. **Kanal sunucuda seçilir** (istemcinin `channel_id`'si ezilir): çift,
   alıcının gizli `sessizSohbetler` listesindeyse `km_v3_sessiz_tsz`; değilse
   alıcının yayınladığı `users/{hedef}.bildirimKanali` — `^km_v3_[a-z0-9_]{1,40}$`
   desenine uymuyorsa `km_v3_varsayilan`. Alıcı bildirimleri kapattıysa
   (`km_v3_kapali`) sessize alma onu açmaz. Böylece sessize alma
   **gönderenin uygulama sürümüne bağlı değildir**. (Geçiş: eski sürümün
   herkese okunur belgeye yazdığı `sessizSohbetler` da istemci onu gizli
   belgeye taşıyana kadar sessiz sayılır.)
8. Alıcının gizli belgesinde `fcmToken` yoksa `404 token_yok`; o değer
   alıcıdan **başka** bir uid'in public `users/{uid}.fcmToken` alanında da
   kayıtlıysa `409 token_cakismasi` (başkasının cihazına gidecek push; bkz.
   yukarıdaki iki katmanlı kapatma).
9. Dönüş: FCM'in HTTP durum kodu (`200` → `{"durum":"gonderildi"}`).

### `/agora-token` kuralları

`chatId` = sıralı iki uid (`a_b`) ve sen onlardan biri olmalısın; `kanal`
`k_<32 hex>` (yeni) ya da `k_<10-16 rakam>` (eski sürümler); arkadaşlık var ve
engel yok olmalı. Token mevcut istemciyle **aynı** üretilir: uid 0, publisher
rolü, 24 saat (istemcide token yenileme akışı olmadığı için kısaltılmadı).

## Kurulum

Gerekenler: Node 18+ ve ücretsiz bir Cloudflare hesabı (kart istemez).

```bash
cd sunucu/aktarici
npm i
npx wrangler login
```

**1. Yeni, kısıtlı bir hizmet hesabı oluşturun** (eskisini KULLANMAYIN):
GCP Konsolu → *IAM ve Yönetici → Hizmet Hesapları* → `kardes-mesaj` projesi →
*Hizmet hesabı oluştur* (ör. `roy-aktarici`). Rol olarak **yalnız** şu ikisini verin:

- `Firebase Cloud Messaging API Admin`
- `Cloud Datastore Viewer`

Hesap → *Anahtarlar → Anahtar ekle → JSON* ile anahtarı indirin.

**2. Gizlileri yükleyin** (depoya hiçbir zaman yazılmaz):

```bash
npx wrangler secret put SERVICE_ACCOUNT < roy-aktarici-anahtar.json
npx wrangler secret put AGORA_APP_CERTIFICATE     # Agora konsolundaki sertifika
rm roy-aktarici-anahtar.json                      # yerel kopyayı silin
```

`PROJE` ve `AGORA_APP_ID` gizli değildir, `wrangler.toml` → `[vars]` içindedir.
> ⚠️ `TEST_JWKS` yalnız testler içindir. Üretimde **tanımlamayın**: tanımlanırsa
> o anahtarla imzalanan her token geçerli sayılır.

**3. Yayınlayın:**

```bash
npx wrangler deploy
# → https://roy-aktarici.<hesap>.workers.dev
```

**4. Uygulamayı aktarıcıyla derleyin:**

```bash
flutter build apk --release --dart-define=AKTARICI_URL=https://roy-aktarici.<hesap>.workers.dev
```

`AKTARICI_URL` tanımlı değilse uygulama eski yolu (APK içindeki anahtarlar)
kullanır — aktarıcı yayına alınmadan hiçbir şey kırılmaz.

**5. Doğruladıktan sonra eski sırları öldürün** (iki cihazda mesaj, arkadaşlık
isteği, sesli/görüntülü arama ve arama iptalini denedikten sonra):

1. `pubspec.yaml` → `assets:` altından `assets/service_account.json` satırını
   kaldırın ve yeni sürümü yayınlayın.
2. GCP Konsolu → eski hizmet hesabının (APK'daki) **anahtarını silin** → eski
   APK'lardaki anahtar böylece işe yaramaz hâle gelir. ⚠️ Bunu yaptığınız an
   aktarıcısız eski sürümler bildirim **gönderemez**; herkes güncelledikten sonra yapın.
3. Agora konsolu → projede **ikincil sertifika** ekleyin, aktarıcıya onu
   `wrangler secret put AGORA_APP_CERTIFICATE` ile verin, sonra birincil
   (APK'da sızmış) sertifikayı devre dışı bırakın.
4. **Public `fcmToken`'ı kapatın** (herkes aktarıcılı derlemeye geçince):
   `firestore.rules` → `users/{uid}` içindeki "GEÇİŞ SONRASI AÇ" yorumlu
   satırları açın (alan artık eklenemez/değiştirilemez, yalnız silinebilir)
   ve kural testindeki G5b'den `fcmToken`'ı çıkarın.

### Yayın sırası ve geçiş (gizli token belgesi)

Token ve sessiz listesi artık `users/{uid}/ozel/bildirim` gizli belgesinde.
Sıra önemli:

1. **Önce kurallar** (`firebase deploy --only firestore:rules`): yeni
   `users/{uid}/ozel/{belge}` kuralı yokken istemci gizli belgeye yazamaz.
2. **Sonra aktarıcı** (`npx wrangler deploy`): token'ı yalnız gizli belgeden
   okur.
3. **Sonra uygulama.** Yeni sürüm (aktarıcılı ya da değil) token'ı her zaman
   gizli belgeye yazar. Herkese okunur `users/{uid}.fcmToken` alanını yalnız
   **aktarıcısız** derleme yazmaya devam eder (eski derlemelerin doğrudan
   FCM yolu kırılmasın); **aktarıcılı** derleme bu alanı siler.

Geçiş sınırları:

- Bu değişiklikten **önceki** bir sürümdeki kullanıcı gizli belgeye token
  yazmadığı için aktarıcı ona bildirim ulaştıramaz (`404 token_yok`); o kişi
  güncelleyince düzelir.
- Aktarıcılı derlemedeki kullanıcının public token'ı silindiği için,
  aktarıcısız **eski** derlemeler ona bildirim gönderemez.
- Saldırgan **kendi** gizli belgesine başkasının token değerini yazabilir.
  ⚠️ Public alanı silmek bunu **kapatmaz**: değer bugüne kadar her girişli
  kullanıcıya okunurdu (kural testi T6), yani **önceden toplanmış** olabilir
  ve FCM token'ı yalnız yeniden kurulum / veri silme / `deleteToken` ile
  değişir. Bu yüzden aktarıcılı derleme token'ı **bir kez döndürür** (eski
  değer ölür) ve aktarıcı, hâlâ birinin public belgesinde duran bir değeri
  başka bir hesaba göndermez (`409`). Kalan boşluk: kurban **eski** derlemede
  ve **birden fazla cihazda** ise public alanda yalnız son yazan cihazın
  token'ı durur; diğer cihazın önceden toplanmış token'ı çakışma sorgusunda
  görünmez. Kurban aktarıcılı derlemeye geçince (döndürme) kapanır. Herkes
  geçince public token kalmaz; sonra yukarıdaki 4. adımla alan kurallarda
  tamamen yasaklanır (çakışma denetimi yine de kalabilir, maliyeti tek sorgu).
- İlk aktarıcılı açılışta token döndürüldüğü için, döndürme ile yeni token'ın
  gizli belgeye yazılması arasında (saniyeler) gelen push'lar kaybolur.
- Aktarıcısız derlemede sessize alma **uygulanamaz** (gönderen alıcının gizli
  listesini okuyamaz); uygulama o derlemede menüyü gizler.

## Geliştirme

```bash
npm test                                            # node:test, ağ yok (fetch sahte)
npx wrangler deploy --dry-run --outdir /tmp/aktarici-dist   # paketlenebiliyor mu
npx wrangler tail                                   # canlı günlük (yayından sonra)
```

Testler Firebase JWKS'ini, OAuth'u, Firestore kurallarını ve FCM'i
`globalThis.fetch` üzerinden taklit eder; sahte anahtarlar her çalıştırmada
`jose` ile üretilir.

## Maliyet

Cloudflare Workers **ücretsiz katman**: günde 100.000 istek, kredi kartı
gerekmez. Her bildirim ve her arama tek istek → aile ölçeğinde fiilen sınırsız.
Firestore tarafında bildirim başına 4–7 doküman okuması (arkadaşlık, engel,
gerekirse istek; alıcının gizli belgesi, token çakışma sorgusu — sonuçsuz
sorgu da 1 okuma sayılır —, görünür bildirimde alıcı profili, gerektiğinde
gönderen profili — arama iptalinde yalnız gizli belge + sorgu) Spark
kotasından (günde 50.000 okuma) düşer.

## Bilinen sınırlar

- Hız sınırı yok: bekleyen bir isteği olan kişi sabit "arkadaşlık isteği"
  bildirimini tekrar tekrar gönderebilir (alıcı isteği reddedince ya da
  engelleyince durur).
- Arkadaşlıktan çıkarıldıktan sonra gönderilen `arama_iptal` bildirimi `403`
  alır (izin arkadaşlığa bağlı); çalan zil CallKit zaman aşımıyla (45 sn) susar.
- Agora token'ı kanalın `aramalar/{chatId}` dokümanındaki kanalla
  eşleştirilmiyor: çiftin üyesi kendi çifti için istediği kanala token alabilir
  (başkasının görüşmesine değil). İleride `aramalar/{chatId}.kanal` da kullanıcı
  token'ıyla okunup karşılaştırılabilir.
