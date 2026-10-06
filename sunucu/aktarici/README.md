# roy-aktarici — sunucusuz bildirim ve Agora token aktarıcısı

ROY MESSANGER için küçük bir **Cloudflare Worker**. İki işi var:

| Uç nokta | Gövde | Ne yapar |
|---|---|---|
| `POST /bildirim` | `{hedefUid, mesaj}` | Arkadaşa (veya istek gönderdiğin kişiye) FCM bildirimi gönderir. |
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
                          └──(hizmet hesabı)──▶ users/{hedef}.fcmToken ──▶ FCM v1
```

- **Arkadaşlık / istek / engel** dokümanları kullanıcının **kendi ID
  token'ıyla** okunur → `firestore.rules` aynen uygulanır (var olmayan doküman
  `404`, üye olmayan `403`). Aktarıcıda kuralların ayrı bir kopyası yok; kural
  değişirse burada bir şey güncellemek gerekmez, iki yetki mantığı zamanla
  ayrışamaz.
- **Hizmet hesabı** yalnız iki iş için kullanılır: alıcının `fcmToken`'ını
  okumak ve FCM'e göndermek. Bu yüzden ona yalnız şu iki rol verilir:
  *Firebase Cloud Messaging API Admin* + *Cloud Datastore Viewer* (yazamaz).
- Hizmet hesabı erişim token'ı modül kapsamında **önbelleklenir** (süresi
  dolmadan 60 sn önce yenilenir) → her bildirimde Google OAuth'a gidilmez.

### `/bildirim` kuralları

1. `hedefUid` geçerli bir uid olmalı ve sen olmamalısın.
2. İzin: `friendships/{çift}` okunabiliyor **veya** `friend_requests/{sen}_{hedef}`
   var (arkadaşlık isteği bildirimi).
3. `engellenenler/{çift}` varsa yalnız `data.tur == "arama_iptal"` geçer (engel
   tam arama çalarken konursa karşı tarafın zili susturulabilsin); diğer her şey `403`.
4. `mesaj` **süzülür**: yalnız `notification{title,body}`, `data` (tüm değerler
   string) ve bilinen `android` alanları (`priority`, `ttl`, `collapse_key`,
   `notification{channel_id, tag, visibility, notification_priority, sound,
   click_action}`) geçer; bilinmeyenler atılır. Böylece kimse `token`/`topic`
   koyup mesajı başka birine ya da bir konuya yönlendiremez.
5. `data.gonderenUid` / `data.arayanUid` varsa doğrulanmış uid ile **üzerine
   yazılır** (sahte "arayan" olmasın); `data.chatId` varsa çiftin kimliği olmalı.
6. Dönüş: FCM'in HTTP durum kodu (`200` → `{"durum":"gonderildi"}`).

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
4. İsteğe bağlı: istemci artık `fcmToken` okumadığı için `users/{uid}` kuralında
   bu alan istemcilere kapatılabilir (bkz. `firestore.rules`, T6 notu).

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
Firestore tarafında bildirim başına 2–4 doküman okuması (arkadaşlık, engel,
gerekirse istek, alıcı) Spark kotasından (günde 50.000 okuma) düşer.

## Bilinen sınırlar

- Arkadaşlıktan çıkarıldıktan sonra gönderilen `arama_iptal` bildirimi `403`
  alır (izin arkadaşlığa bağlı); çalan zil CallKit zaman aşımıyla (45 sn) susar.
- Agora token'ı kanalın `aramalar/{chatId}` dokümanındaki kanalla
  eşleştirilmiyor: çiftin üyesi kendi çifti için istediği kanala token alabilir
  (başkasının görüşmesine değil). İleride `aramalar/{chatId}.kanal` da kullanıcı
  token'ıyla okunup karşılaştırılabilir.
