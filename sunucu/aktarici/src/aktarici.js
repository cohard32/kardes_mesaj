// ═══════════════════════════════════════════════════════════════════
//  ROY AKTARICI — iş mantığı (Worker giriş noktası: index.js)
//
//  ⚠️ NEDEN VAR: FCM hizmet hesabı anahtarı (assets/service_account.json) ve
//  Agora App Certificate (lib/gizli.dart) APK'nın İÇİNDE dağıtılıyordu →
//  APK'yı açan herkes herkese sahte bildirim / sahte gelen arama
//  gönderebiliyor, sınırsız Agora token üretebiliyordu. Sırlar artık
//  YALNIZ burada (wrangler secret) durur; istemci kendi Firebase ID
//  token'ını gönderir.
//
//  ⚠️ YETKİ KARARI BURADA VERİLMEZ, FIRESTORE KURALLARINA SORULUR:
//  arkadaşlık / istek / engel dokümanları KULLANICININ KENDİ ID token'ıyla
//  Firestore REST'ten okunur → firestore.rules aynen uygulanır (üye olmayan
//  403, var olmayan doküman 404). Hizmet hesabı yalnız OKUMA ve FCM'e
//  gönderme için kullanılır: alıcının GİZLİ belgesi (users/{uid}/ozel/
//  bildirim: fcmToken + sessizSohbetler), alıcının yayınladığı kanal ve
//  gönderenin görünen adı. Böylece kurallarda bir şey değişirse aktarıcıda
//  ayrı bir kopya güncellemek gerekmez (iki ayrı yetki mantığı zamanla
//  ayrışırdı).
//
//  İstemci sözleşmesi: lib/servisler/aktarici_servisi.dart (birlikte değişmeli).
// ═══════════════════════════════════════════════════════════════════

import {
  createLocalJWKSet,
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from 'jose';
// agora-token CommonJS paketidir; adlandırılmış içe aktarma Node'da CJS
// sözcük çözümleyicisine bağlı kalır → varsayılan nesneden alınır.
import agora from 'agora-token';

const { RtcTokenBuilder, RtcRole } = agora;

const GOVDE_SINIRI = 8 * 1024; // bayt
const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const OAUTH_URL = 'https://oauth2.googleapis.com/token';
const SA_KAPSAM =
  'https://www.googleapis.com/auth/firebase.messaging ' +
  'https://www.googleapis.com/auth/datastore';

// Firebase'in ürettiği uid'ler 28 karakter [A-Za-z0-9]. '_' YASAK: çift
// kimliği (chatId) `a_b` biçiminde '_' ile ayrıldığı için '_' içeren bir uid
// çift kimliğini belirsiz yapardı. '/' de yasak: Firestore yol parçasına
// gömülüyor (başka koleksiyona sıçrama olmasın).
const UID_DESENI = /^[A-Za-z0-9-]{1,128}$/;
// Yeni kanal: 128 bit Random.secure() hex. Eski: k_<milisaniye> (geçiş
// sırasında eski sürümlerle başlamış aramalar kırılmasın diye kabul edilir).
const KANAL_DESENI = /^k_(?:[0-9a-f]{32}|\d{10,16})$/;

// ─── Yanıt yardımcıları ───────────────────────────────────────────

function json(durum, govde) {
  return new Response(JSON.stringify(govde), {
    status: durum,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

/// ⚠️ Hata yanıtı yalnız kısa bir KOD içerir; iç ayrıntı (Google'ın hata
/// gövdesi, yığın izi) istemciye sızdırılmaz — saldırgana kuralları/altyapıyı
/// haritalamada yardım etmesin. Ayrıntı yalnız Worker günlüğüne yazılır.
function hata(durum, kod) {
  return json(durum, { hata: kod });
}

class IstekHatasi extends Error {
  constructor(durum, kod) {
    super(kod);
    this.durum = durum;
    this.kod = kod;
  }
}

// ─── Kimlik doğrulama ─────────────────────────────────────────────

// Modül kapsamı: Worker örneği yaşadıkça JWKS önbellekte kalır (her istekte
// Google'a gitmesin). createRemoteJWKSet kendi içinde süreyi yönetir.
let uzakJwks;
let yerelJwks;
let yerelJwksMetni;

function jwksAl(env) {
  // ⚠️ TEST_JWKS YALNIZ TESTLER İÇİNDİR: üretimde ASLA tanımlanmamalı —
  // tanımlanırsa o anahtarla imzalanan her token geçerli sayılır.
  if (env.TEST_JWKS) {
    if (yerelJwksMetni !== env.TEST_JWKS) {
      yerelJwks = createLocalJWKSet(JSON.parse(env.TEST_JWKS));
      yerelJwksMetni = env.TEST_JWKS;
    }
    return yerelJwks;
  }
  return (uzakJwks ??= createRemoteJWKSet(new URL(JWKS_URL)));
}

async function kimlikDogrula(istek, env) {
  const baslik = istek.headers.get('Authorization') ?? '';
  const m = /^Bearer\s+(\S+)$/.exec(baslik);
  if (!m) throw new IstekHatasi(401, 'kimlik');
  const idToken = m[1];
  let yuk;
  try {
    ({ payload: yuk } = await jwtVerify(idToken, jwksAl(env), {
      algorithms: ['RS256'],
      issuer: `https://securetoken.google.com/${env.PROJE}`,
      audience: env.PROJE,
      requiredClaims: ['sub', 'iat', 'exp'],
      clockTolerance: 10,
    }));
  } catch {
    throw new IstekHatasi(401, 'kimlik');
  }
  // Firebase belgesi: auth_time geçmişte olmalı. sub yol parçasına
  // gömüleceği için desene de uymalı.
  const simdi = Math.floor(Date.now() / 1000);
  if (typeof yuk.auth_time === 'number' && yuk.auth_time > simdi + 10) {
    throw new IstekHatasi(401, 'kimlik');
  }
  if (typeof yuk.sub !== 'string' || !UID_DESENI.test(yuk.sub)) {
    throw new IstekHatasi(401, 'kimlik');
  }
  return { uid: yuk.sub, idToken };
}

// ─── Gövde ────────────────────────────────────────────────────────

/// Gövdeyi en fazla [GOVDE_SINIRI] bayt okur. ⚠️ Content-Length'e tek başına
/// güvenilmez (chunked gövdede yoktur) → akış okunurken de sayılır ve sınır
/// aşılınca okuma kesilir (büyük gövde belleğe alınmaz).
async function govdeOku(istek) {
  const uzunluk = Number(istek.headers.get('Content-Length') ?? '0');
  if (uzunluk > GOVDE_SINIRI) throw new IstekHatasi(413, 'govde_buyuk');
  if (!istek.body) throw new IstekHatasi(400, 'govde');
  const okuyucu = istek.body.getReader();
  const parcalar = [];
  let toplam = 0;
  for (;;) {
    const { done, value } = await okuyucu.read();
    if (done) break;
    toplam += value.byteLength;
    if (toplam > GOVDE_SINIRI) {
      await okuyucu.cancel().catch(() => {});
      throw new IstekHatasi(413, 'govde_buyuk');
    }
    parcalar.push(value);
  }
  const bayt = new Uint8Array(toplam);
  let i = 0;
  for (const p of parcalar) {
    bayt.set(p, i);
    i += p.byteLength;
  }
  try {
    const nesne = JSON.parse(new TextDecoder().decode(bayt));
    if (nesne === null || typeof nesne !== 'object' || Array.isArray(nesne)) {
      throw new Error();
    }
    return nesne;
  } catch {
    throw new IstekHatasi(400, 'govde');
  }
}

// ─── Firestore REST ───────────────────────────────────────────────

function dokumanUrl(env, ...parcalar) {
  const yol = parcalar.map(encodeURIComponent).join('/');
  return (
    `https://firestore.googleapis.com/v1/projects/${env.PROJE}` +
    `/databases/(default)/documents/${yol}`
  );
}

/// KULLANICI ADINA okuma → kurallar uygulanır. Yalnız durum kodu döner:
///   200 = var ve okuyabiliyor, 404 = yok, 403 = üye değil.
/// ⚠️ İstemci App Check belirteci gönderdiyse aynen iletilir: Firestore'da
/// App Check zorlaması açılırsa belirteçsiz REST okumaları reddedilir ve
/// HER bildirim "izin yok" diye düşerdi.
async function kullaniciAdinaDurum(env, kimlik, appCheck, ...parcalar) {
  return (await kullaniciAdinaOku(env, kimlik, appCheck, false, ...parcalar)).durum;
}

/// [kullaniciAdinaDurum] gibi; [govdeIste] true ise 200 yanıtının belge
/// alanlarını (`fields`) da döner → { durum, alanlar }.
async function kullaniciAdinaOku(env, kimlik, appCheck, govdeIste, ...parcalar) {
  const basliklar = { Authorization: `Bearer ${kimlik.idToken}` };
  if (appCheck) basliklar['X-Firebase-AppCheck'] = appCheck;
  const r = await fetch(dokumanUrl(env, ...parcalar), { headers: basliklar });
  if (govdeIste && r.status === 200) {
    let alanlar = null;
    try {
      alanlar = (await r.json())?.fields ?? null;
    } catch {
      // Bozuk gövde = içerik doğrulanamadı → çağıran "izin yok" sayar.
    }
    return { durum: r.status, alanlar };
  }
  // Gövde kullanılmıyor ama okunmazsa bağlantı serbest kalmayabilir.
  await r.body?.cancel().catch(() => {});
  return { durum: r.status, alanlar: null };
}

/// HİZMET HESABIYLA okuma (kurallar uygulanmaz) — YALNIZ [alanlar] maskesiyle
/// (gereksiz alan Worker'a hiç gelmesin). Belge yoksa null, varsa `fields`
/// nesnesi ({} olabilir). Başka her hata 502.
async function hizmetHesabiylaOku(env, erisim, alanlar, ...parcalar) {
  const maske = alanlar
    .map((a) => `mask.fieldPaths=${encodeURIComponent(a)}`)
    .join('&');
  const r = await fetch(`${dokumanUrl(env, ...parcalar)}?${maske}`, {
    headers: { Authorization: `Bearer ${erisim}` },
  });
  if (r.status === 404) {
    await r.body?.cancel().catch(() => {});
    return null;
  }
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) onbellegiSifirla();
    console.error(`${parcalar[0]} okuma HTTP ${r.status}`);
    await r.body?.cancel().catch(() => {});
    throw new IstekHatasi(502, 'firestore');
  }
  return (await r.json())?.fields ?? {};
}

/// [fcmToken] herkese okunur `users` koleksiyonunda [hedefUid] DIŞINDA bir
/// belgenin `fcmToken` alanında kayıtlı mı? (Hizmet hesabıyla sorgu.)
///
/// ⚠️ NEDEN (d10, ikinci tur): gizli belgeyi YALNIZ sahibi yazar ama DEĞERİ
/// serbesttir → saldırgan, kurbanın bugüne kadar herkese okunur olan (ya da
/// kurban aktarıcısız/eski derlemedeyse HÂLÂ okunur olan) token'ını kendi
/// ikinci hesabının gizli belgesine yazıp kendi hesapları arasında
/// "arkadaş" bildirimi atarak kurbanın telefonunu çaldırabilir. Aktarıcılı
/// derleme token'ı bir kez döndürür (istemci: tokenBirKezDondur) → eski
/// değer FCM'de ölür. Ama döndüremeyen (eski derleme, döndürmesi henüz
/// başarısız) kurbanın değeri public belgesinde DURUYOR: aynı değer hedeften
/// başka bir uid'in public belgesindeyse gönderilmez.
/// Neden `ozel` koleksiyon GRUBU değil de `users`: eski derlemedeki kurban
/// gizli belge HİÇ yazmaz (yalnız public) → grup sorgusu onu göremezdi; ayrıca
/// grup sorgusu ayrı bir dizin muafiyeti ister, `users.fcmToken` tek alan
/// dizini ise Firestore'da kendiliğinden vardır.
/// Hedefin KENDİ public alanı (aktarıcısız yeni derleme ikisine de yazar)
/// çakışma sayılmaz. limit 2: hedef + bir başkası da yakalanır.
async function tokenBaskasindaMi(env, erisim, fcmToken, hedefUid) {
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.PROJE}` +
      '/databases/(default)/documents:runQuery',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${erisim}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        structuredQuery: {
          // allDescendants YOK → yalnız kökteki `users` koleksiyonu.
          from: [{ collectionId: 'users' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'fcmToken' },
              op: 'EQUAL',
              value: { stringValue: fcmToken },
            },
          },
          // Yalnız belge adı gelsin (profil alanları Worker'a gelmesin).
          select: { fields: [{ fieldPath: '__name__' }] },
          limit: 2,
        },
      }),
    },
  );
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) onbellegiSifirla();
    console.error(`users token sorgusu HTTP ${r.status}`);
    await r.body?.cancel().catch(() => {});
    // ⚠️ Kapalı başarısız: denetim yapılamadıysa GÖNDERİLMEZ.
    throw new IstekHatasi(502, 'firestore');
  }
  let satirlar;
  try {
    satirlar = await r.json();
  } catch {
    satirlar = null;
  }
  if (!Array.isArray(satirlar)) throw new IstekHatasi(502, 'firestore');
  return satirlar.some((s) => {
    const ad = s?.document?.name;
    // Boş sonuç [{readTime}] biçimindedir (document yok).
    return typeof ad === 'string' && ad.split('/').pop() !== hedefUid;
  });
}

/// Firestore REST değer biçiminden düz string (yoksa/başka tipse undefined).
function metin(alanlar, ad) {
  const v = alanlar?.[ad]?.stringValue;
  return typeof v === 'string' ? v : undefined;
}

/// Firestore REST dizi alanındaki string'ler (yoksa/bozuksa []).
function metinDizisi(alanlar, ad) {
  const degerler = alanlar?.[ad]?.arrayValue?.values;
  if (!Array.isArray(degerler)) return [];
  return degerler
    .map((d) => d?.stringValue)
    .filter((v) => typeof v === 'string');
}

/// 200 → true, 403/404 → false; başka her şey (429/5xx) GEÇİCİ altyapı
/// hatasıdır → "izin yok" (403) diye YUTULMAZ, 502 döner. Yoksa Firestore
/// kotası dolduğunda kullanıcı "arkadaş değilsin" gibi yanıltıcı bir
/// sonuç alır ve teşhis imkânsızlaşırdı.
function varMi(durum, ne) {
  if (durum === 200) return true;
  if (durum === 404 || durum === 403) return false;
  console.error(`firestore ${ne} HTTP ${durum}`);
  throw new IstekHatasi(502, 'firestore');
}

function ciftKimligi(a, b) {
  // ⚠️ Dart'taki ciftKimligi ile AYNI sıra: String.compareTo ve JS sort()
  // ikisi de UTF-16 kod birimi sırasıyla karşılaştırır.
  return [a, b].sort().join('_');
}

// ─── Hizmet hesabı erişim token'ı ─────────────────────────────────

// Modül kapsamı önbellek: aynı Worker örneğine gelen istekler OAuth'a tekrar
// gitmez (her bildirimde fazladan bir Google gidiş-dönüşü ÇAĞRI push'unu
// geciktirirdi). Eşzamanlı ilk istekler aynı Promise'i bekler.
let saOnbellek = null; // { anahtar, token, bitis }
let saBekleyen = null; // { anahtar, promise }

/// Testler ve FCM 401/403 sonrası kullanım içindir.
export function onbellegiSifirla() {
  saOnbellek = null;
  saBekleyen = null;
}

function hizmetHesabi(env) {
  try {
    const sa = JSON.parse(env.SERVICE_ACCOUNT ?? '');
    if (typeof sa.client_email !== 'string' || typeof sa.private_key !== 'string') {
      throw new Error();
    }
    return sa;
  } catch {
    console.error('SERVICE_ACCOUNT gizlisi eksik/bozuk');
    throw new IstekHatasi(500, 'yapilandirma');
  }
}

async function erisimTokeni(env) {
  const sa = hizmetHesabi(env);
  // Anahtar değişirse (secret döndürme) eski önbellek kullanılmasın.
  const anahtar = sa.client_email + ':' + (sa.private_key_id ?? '');
  const simdi = Math.floor(Date.now() / 1000);
  if (saOnbellek && saOnbellek.anahtar === anahtar && saOnbellek.bitis - 60 > simdi) {
    return saOnbellek.token;
  }
  if (saBekleyen && saBekleyen.anahtar === anahtar) return saBekleyen.promise;

  const promise = (async () => {
    const jwt = await new SignJWT({ scope: SA_KAPSAM })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT', ...(sa.private_key_id ? { kid: sa.private_key_id } : {}) })
      .setIssuer(sa.client_email)
      .setSubject(sa.client_email)
      .setAudience(OAUTH_URL)
      .setIssuedAt(simdi)
      .setExpirationTime(simdi + 3600)
      .sign(await importPKCS8(sa.private_key, 'RS256'));
    const r = await fetch(OAUTH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    });
    if (!r.ok) {
      console.error(`oauth HTTP ${r.status}`);
      throw new IstekHatasi(502, 'oauth');
    }
    const g = await r.json();
    if (typeof g.access_token !== 'string') throw new IstekHatasi(502, 'oauth');
    const omur = Number.isFinite(g.expires_in) ? g.expires_in : 3600;
    saOnbellek = { anahtar, token: g.access_token, bitis: simdi + omur };
    return g.access_token;
  })();
  saBekleyen = { anahtar, promise };
  try {
    return await promise;
  } finally {
    if (saBekleyen?.promise === promise) saBekleyen = null;
  }
}

// ─── /bildirim ────────────────────────────────────────────────────

const ANDROID_ONCELIK = new Set(['HIGH', 'NORMAL']);
const GORUNURLUK = new Set(['PUBLIC', 'PRIVATE', 'SECRET']);
const ANDROID_BILDIRIM_ALANLARI = {
  // Biçim denetimi; DEĞER her zaman aşağıda sunucuda EZİLİR
  // ([alicininKanali]) — istemcinin seçtiği kanal kullanılmaz.
  channel_id: (v) => typeof v === 'string' && /^[A-Za-z0-9_.-]{1,64}$/.test(v),
  tag: (v) => typeof v === 'string' && v.length <= 128,
  visibility: (v) => GORUNURLUK.has(v),
  notification_priority: (v) => typeof v === 'string' && /^PRIORITY_[A-Z]{1,10}$/.test(v),
  sound: (v) => typeof v === 'string' && v.length <= 64,
  click_action: (v) => typeof v === 'string' && v.length <= 128,
};

// ─── Bildirim kanalı (Sözleşme: lib/servisler/bildirim_servisi.dart
// BildirimKanali — kimlikler ikisinde AYNI olmalı) ───
const VARSAYILAN_KANAL = 'km_v3_varsayilan';
const KAPALI_KANAL = 'km_v3_kapali';
const SESSIZ_SOHBET_KANALI = 'km_v3_sessiz_tsz';
// Alıcının YAYINLADIĞI kanal bu desene uymalı: km_v3_<secim>[_tsz],
// km_v3_kapali, özel ses km_v3_ozel_<8 hex>[_tsz]. Uymayan (eski sürüm
// km_v2_*, bozuk/kötü niyetli değer) güvenli varsayılana düşer — o kanal
// her istemcide her zaman kurulu.
const YAYIN_KANAL_DESENI = /^km_v3_[a-z0-9_]{1,40}$/;

// Gizli kullanıcı belgesi (yalnız sahibi okur/yazar; aktarıcı hizmet
// hesabıyla okur). ⚠️ fcmToken YALNIZ buradan okunur — bkz. bildirim().
const OZEL_KOLEKSIYON = 'ozel';
const OZEL_BELGE = 'bildirim';

/// Arkadaşlık isteği bildiriminin SABİT gövdesi (istemci gövdesi yok sayılır).
const ISTEK_GOVDESI = 'sana arkadaşlık isteği gönderdi';
const AD_SINIRI = 80;

/// Alıcının push'ta kullanılacak kanalı — KARAR SUNUCUDA.
/// ⚠️ NEDEN (d6): eskiden gönderen istemci alıcının sessiz listesine bakıp
/// channel_id'yi kendisi seçiyordu → sessize alma GÖNDERENİN sürümüne
/// bağlıydı (eski sürüm gönderen sessize alınmış sohbette yine çaldırıyordu)
/// ve liste herkese okunur belgede duruyordu (d8). Artık liste alıcının GİZLİ
/// belgesinde, kararı aktarıcı verir; istemcinin channel_id'si EZİLİR.
/// Bildirimler tamamen KAPALIYSA sessize alma onu "açmaz" (kapali kalır).
/// Sessiz denetimi data.chatId'ye değil ÇİFTE bakar: bu çift arasındaki her
/// bildirim zaten o sohbete aittir (chatId yalnız çift olabilir) → gönderen
/// chatId'yi atlayarak sessize almayı delemez.
/// [profil].sessizSohbetler: geçiş — eski sürüm listeyi herkese okunur
/// users belgesine yazıyordu; istemci onu ilk fırsatta gizli belgeye taşıyıp
/// siler. O ana kadar da sessiz sayılsın diye ikisi birleştirilir.
function alicininKanali(profil, ozel, cift) {
  const yayin = metin(profil, 'bildirimKanali');
  const kanal = yayin && YAYIN_KANAL_DESENI.test(yayin) ? yayin : VARSAYILAN_KANAL;
  if (kanal === KAPALI_KANAL) return kanal;
  const sessiz = [
    ...metinDizisi(ozel, 'sessizSohbetler'),
    ...metinDizisi(profil, 'sessizSohbetler'),
  ];
  return sessiz.includes(cift) ? SESSIZ_SOHBET_KANALI : kanal;
}

/// Gönderenin GERÇEK görünen adı (profilinden). Bildirim başlığı ve gelen
/// arama ekranındaki ad bundan üretilir → istemci "Annen" yazıp isim
/// sahteciliği yapamaz (d12).
function gorunenAd(profil) {
  const ad = metin(profil, 'ad')?.trim();
  if (ad) return ad.slice(0, AD_SINIRI);
  const kAdi = metin(profil, 'kullaniciAdi');
  return kAdi ? `@${kAdi}`.slice(0, AD_SINIRI) : 'ROY MESSANGER';
}

function duzNesneMi(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

/// chatId'si ZORUNLU olan veri push türleri (CallKit kimliği = chatId).
/// ⚠️ chatId'siz 'arama'da istemci kanal adını CallKit kimliği yapıyordu;
/// chatId'siz 'arama_iptal' ise eskiden endAllCalls() ile alıcının BAŞKA
/// biriyle süren/çalan aramasını da kesiyordu (d11).
const CHATID_ZORUNLU_TURLER = new Set(['arama', 'arama_iptal']);

/// İstemcinin gönderdiği FCM `message` parçalarını SÜZER. Yalnız
/// notification{title,body}, data (tüm değerler string) ve bilinen android
/// alanları geçer; bilinmeyen alanlar SESSİZCE atılır, tipi yanlış olan
/// alan 400 verir.
/// ⚠️ NEDEN: süzülmeseydi bir kullanıcı `token`/`topic`/`condition` alanı
/// koyup mesajı arkadaşı OLMAYAN birine ya da TÜM bir konuya (topic)
/// yönlendirebilir, `apns`/`webpush` ile beklenmedik yollar açabilirdi.
/// Hedef YALNIZ aktarıcının alıcının GİZLİ belgesinde bulduğu fcmToken'dır.
function mesajiSuz(mesaj, uid, cift) {
  if (!duzNesneMi(mesaj)) throw new IstekHatasi(400, 'mesaj');
  const cikti = {};

  if (mesaj.notification !== undefined) {
    const n = mesaj.notification;
    if (!duzNesneMi(n)) throw new IstekHatasi(400, 'mesaj');
    const t = {};
    for (const alan of ['title', 'body']) {
      if (n[alan] === undefined) continue;
      if (typeof n[alan] !== 'string') throw new IstekHatasi(400, 'mesaj');
      t[alan] = n[alan];
    }
    if (Object.keys(t).length) cikti.notification = t;
  }

  if (mesaj.data !== undefined) {
    const d = mesaj.data;
    if (!duzNesneMi(d)) throw new IstekHatasi(400, 'mesaj');
    const t = {};
    for (const [k, v] of Object.entries(d)) {
      if (typeof v !== 'string') throw new IstekHatasi(400, 'mesaj');
      t[k] = v;
    }
    // ⚠️ Kimlik alanları sunucuda DAMGALANIR: istemci verdiği değer ne olursa
    // olsun gönderen = doğrulanmış uid. Yoksa bir arkadaş "arayan: annen"
    // diye başka birinin uid'iyle sahte gelen arama çaldırabilirdi.
    for (const alan of ['gonderenUid', 'arayanUid']) {
      if (alan in t) t[alan] = uid;
    }
    // chatId (bildirime dokununca açılacak sohbet) yalnız bu ÇİFTİN sohbeti
    // olabilir (FAZ 4: chatId = friendshipId = ciftKimligi).
    if ('chatId' in t && t.chatId !== cift) throw new IstekHatasi(400, 'mesaj');
    if (CHATID_ZORUNLU_TURLER.has(t.tur) && !('chatId' in t)) {
      throw new IstekHatasi(400, 'mesaj');
    }
    if (Object.keys(t).length) cikti.data = t;
  }

  if (mesaj.android !== undefined) {
    const a = mesaj.android;
    if (!duzNesneMi(a)) throw new IstekHatasi(400, 'mesaj');
    const t = {};
    if (a.priority !== undefined) {
      if (!ANDROID_ONCELIK.has(a.priority)) throw new IstekHatasi(400, 'mesaj');
      t.priority = a.priority;
    }
    if (a.ttl !== undefined) {
      // FCM v1 Duration biçimi: "45s", "3.5s". En fazla 28 gün (FCM sınırı).
      if (typeof a.ttl !== 'string' || !/^\d{1,7}(\.\d{1,9})?s$/.test(a.ttl) ||
          parseFloat(a.ttl) > 2419200) {
        throw new IstekHatasi(400, 'mesaj');
      }
      t.ttl = a.ttl;
    }
    if (a.collapse_key !== undefined) {
      if (typeof a.collapse_key !== 'string' || a.collapse_key.length > 64) {
        throw new IstekHatasi(400, 'mesaj');
      }
      t.collapse_key = a.collapse_key;
    }
    if (a.notification !== undefined) {
      if (!duzNesneMi(a.notification)) throw new IstekHatasi(400, 'mesaj');
      const an = {};
      for (const [alan, gecerli] of Object.entries(ANDROID_BILDIRIM_ALANLARI)) {
        const v = a.notification[alan];
        if (v === undefined) continue;
        if (!gecerli(v)) throw new IstekHatasi(400, 'mesaj');
        an[alan] = v;
      }
      if (Object.keys(an).length) t.notification = an;
    }
    if (Object.keys(t).length) cikti.android = t;
  }

  if (!cikti.notification && !cikti.data) throw new IstekHatasi(400, 'mesaj');
  return cikti;
}

/// ENGEL varken geçebilecek TEK biçim: tam olarak
/// {data: {tur: 'arama_iptal', chatId: çift}} (+ android priority/ttl/
/// collapse_key). ⚠️ NEDEN (d11): eskiden yalnız data.tur'a bakılıyordu →
/// engellenen kişi 'arama_iptal' etiketiyle notification{title,body} ya da
/// ek data taşıyıp görünür taciz bildirimi gönderebiliyordu (arka planda
/// notification yükünü SİSTEM çizer). Görünür bir şey taşıyan her biçim 403.
function yalnizAramaIptalMi(mesaj, cift) {
  if (mesaj.notification || mesaj.android?.notification) return false;
  const d = mesaj.data;
  if (!d) return false;
  const anahtarlar = Object.keys(d).sort();
  return anahtarlar.length === 2 &&
    anahtarlar[0] === 'chatId' && anahtarlar[1] === 'tur' &&
    d.tur === 'arama_iptal' && d.chatId === cift;
}

async function bildirim(istek, env, kimlik) {
  const govde = await govdeOku(istek);
  const { hedefUid } = govde;
  if (typeof hedefUid !== 'string' || !UID_DESENI.test(hedefUid)) {
    throw new IstekHatasi(400, 'hedef');
  }
  if (hedefUid === kimlik.uid) throw new IstekHatasi(400, 'hedef');
  const cift = ciftKimligi(kimlik.uid, hedefUid);
  // Süzme yetki sorgularından ÖNCE: bozuk istek Firestore okuması harcamasın.
  const suzulmus = mesajiSuz(govde.mesaj, kimlik.uid, cift);
  const appCheck = istek.headers.get('X-Firebase-AppCheck');

  // Üç bağımsız iş PARALEL: ÇAĞRI push'unda her gidiş-dönüş zili geciktirir.
  const [arkadaslik, engel, erisim] = await Promise.all([
    kullaniciAdinaDurum(env, kimlik, appCheck, 'friendships', cift),
    kullaniciAdinaDurum(env, kimlik, appCheck, 'engellenenler', cift),
    erisimTokeni(env),
  ]);

  // İzin: arkadaşız VEYA benden ona bekleyen bir istek var (istek bildirimi).
  // ⚠️ İstek yönü {ben}_{hedef}: kurallar kimliği {gonderen}_{alan} diye
  // zorluyor → başkası adına açılmış bir "istek" ile bildirim atılamaz.
  const arkadas = varMi(arkadaslik, 'friendships');
  if (!arkadas) {
    const { durum, alanlar } = await kullaniciAdinaOku(
      env, kimlik, appCheck, true, 'friend_requests', `${kimlik.uid}_${hedefUid}`);
    if (!varMi(durum, 'friend_requests')) throw new IstekHatasi(403, 'izin');
    // ⚠️ İÇERİK de doğrulanır (t3): kimlik kuralı sonradan geldi; eski
    // kurallarla açılmış friend_requests/{ben}_{kurban} belgesinin içinde
    // alanUid başka biri olabilir → kurban o isteği listesinde GÖRMEZ,
    // reddedip silemez; yalnız kimliğe bakılsaydı kalıcı bildirim izni olurdu.
    if (metin(alanlar, 'gonderenUid') !== kimlik.uid ||
        metin(alanlar, 'alanUid') !== hedefUid) {
      throw new IstekHatasi(403, 'izin');
    }
  }

  // ENGEL: tek doküman iki yönü de kapatır (kurallardaki engelli() ile aynı).
  // Yalnız ARKADAŞIN çıplak 'arama_iptal'i geçer: engel tam arama çalarken
  // konursa karşı tarafın zili SUSTURULABİLMELİ (aksi halde CallKit 45 sn
  // boşa çalar). İstek yolunda arama olmadığı için iptal de yok.
  const engelli = varMi(engel, 'engellenenler');
  if (engelli && !(arkadas && yalnizAramaIptalMi(suzulmus, cift))) {
    throw new IstekHatasi(403, 'engel');
  }

  // Gönderilecek mesajın görünür bir bildirimi olacak mı / gelen arama mı?
  // (Gereksiz Firestore okuması yapılmasın: ÇAĞRI iptalinde ad/kanal yok.)
  const bildirimli = !arkadas || !!suzulmus.notification ||
    !!suzulmus.android?.notification;
  const adGerekli = bildirimli || suzulmus.data?.tur === 'arama';

  // HİZMET HESABIYLA, paralel: alıcının gizli belgesi (token + sessiz
  // listesi), alıcının yayınladığı kanal, gönderenin gerçek adı.
  // ⚠️ fcmToken YALNIZ gizli belgeden (d10): herkese okunur users/{uid}
  // belgesindeki fcmToken'ı herkes OKUYUP KENDİ belgesine yazabiliyordu →
  // saldırgan kendi ikinci hesabına istek atıp kurbanın cihazına sahte arama
  // çaldırabiliyordu (yetki denetimi hedefUid'e, teslimat ise o belgedeki
  // token'a bakıyordu). Public alan token KAYNAĞI olarak ASLA kullanılmaz;
  // yalnız çakışma denetiminde (başkasının token'ı mı?) sorgulanır.
  // Token çakışma denetimi ([tokenBaskasindaMi]) gizli belge gelir gelmez
  // başlar; profil okumalarıyla PARALEL yürür (zil gecikmesin).
  const ozelSozu = hizmetHesabiylaOku(env, erisim, ['fcmToken', 'sessizSohbetler'],
    'users', hedefUid, OZEL_KOLEKSIYON, OZEL_BELGE);
  const cakismaSozu = ozelSozu.then((o) => {
    const t = metin(o, 'fcmToken');
    return t ? tokenBaskasindaMi(env, erisim, t, hedefUid) : false;
  });
  const [ozel, cakisma, hedefProfil, gonderenProfil] = await Promise.all([
    ozelSozu,
    cakismaSozu,
    bildirimli
      ? hizmetHesabiylaOku(env, erisim, ['bildirimKanali', 'sessizSohbetler'],
        'users', hedefUid)
      : null,
    adGerekli
      ? hizmetHesabiylaOku(env, erisim, ['ad', 'kullaniciAdi'], 'users', kimlik.uid)
      : null,
  ]);
  const fcmToken = metin(ozel, 'fcmToken');
  if (!fcmToken) throw new IstekHatasi(404, 'token_yok');
  // Hedefin gizli belgesindeki token BAŞKA birinin (public) token'ı → bu
  // push o kişinin cihazına giderdi (d10 sahteciliği). Gönderilmez.
  if (cakisma) {
    console.error(`token cakismasi: hedef ${hedefUid}`);
    throw new IstekHatasi(409, 'token_cakismasi');
  }

  let mesaj;
  if (!arkadas) {
    // İSTEK YOLU (d12): arkadaş olmayan YALNIZ tek, sabit biçimli "istek"
    // bildirimi gönderebilir. İstemcinin gövdesi (data, tur='arama', serbest
    // başlık/metin, ttl…) TAMAMEN yok sayılır → yabancı biri bekleyen bir
    // istekle sahte gelen arama çaldıramaz, "Annen" diye bildirim atamaz.
    mesaj = {
      notification: { title: gorunenAd(gonderenProfil), body: ISTEK_GOVDESI },
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: alicininKanali(hedefProfil, ozel, cift),
          visibility: 'PUBLIC',
          tag: `km_${hedefUid}`,
        },
      },
    };
  } else {
    mesaj = suzulmus;
    const ad = adGerekli ? gorunenAd(gonderenProfil) : undefined;
    // Başlık HER ZAMAN gerçek ad (isim sahteciliği biter).
    if (mesaj.notification) mesaj.notification.title = ad;
    if (bildirimli) {
      mesaj.android ??= {};
      mesaj.android.notification ??= {};
      mesaj.android.notification.channel_id =
        alicininKanali(hedefProfil, ozel, cift);
    }
    if (mesaj.data?.tur === 'arama') {
      // Gelen arama ekranındaki ad (CallKit nameCaller) ve arayanUid sunucudan.
      mesaj.data.arayan = ad;
      mesaj.data.arayanUid = kimlik.uid;
    }
  }

  const fcm = await fetch(
    `https://fcm.googleapis.com/v1/projects/${env.PROJE}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${erisim}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: { token: fcmToken, ...mesaj } }),
    },
  );
  if (fcm.status === 401 || fcm.status === 403) onbellegiSifirla();
  if (!fcm.ok) {
    // Ayrıntı (ör. UNREGISTERED) yalnız günlükte; istemciye durum kodu yeter.
    console.error(`fcm HTTP ${fcm.status}: ${(await fcm.text()).slice(0, 300)}`);
    return hata(fcm.status, 'fcm');
  }
  await fcm.body?.cancel().catch(() => {});
  return json(200, { durum: 'gonderildi' });
}

// ─── /agora-token ─────────────────────────────────────────────────

// Mevcut istemci davranışıyla AYNI (arama_servisi.dart → RtcTokenBuilder.build):
// uid 0 (= herhangi bir uid; istemci kanala uid 0 ile katılır, Agora atar),
// publisher rolü, 24 saat. Uzun görüşmede token yenileme akışı istemcide
// olmadığı için süre KISALTILMADI — kısaltılırsa 24 saatten kısa sürede
// görüşmeler düşer. Kanal adı 128 bit rastgele olduğundan token yalnız o
// görüşmeye yarar.
const AGORA_SURE = 24 * 60 * 60;

async function agoraToken(istek, env, kimlik) {
  const govde = await govdeOku(istek);
  const { chatId, kanal } = govde;
  if (typeof chatId !== 'string' || typeof kanal !== 'string') {
    throw new IstekHatasi(400, 'parametre');
  }
  const uyeler = chatId.split('_');
  if (
    uyeler.length !== 2 ||
    !uyeler.every((u) => UID_DESENI.test(u)) ||
    ciftKimligi(uyeler[0], uyeler[1]) !== chatId ||
    uyeler[0] === uyeler[1]
  ) {
    throw new IstekHatasi(400, 'chatId');
  }
  if (!KANAL_DESENI.test(kanal)) throw new IstekHatasi(400, 'kanal');
  // Kural sorgusundan önce ucuz denetim: başkalarının çifti için Firestore'a
  // hiç gidilmez.
  if (!uyeler.includes(kimlik.uid)) throw new IstekHatasi(403, 'izin');

  const appCheck = istek.headers.get('X-Firebase-AppCheck');
  const [arkadaslik, engel] = await Promise.all([
    kullaniciAdinaDurum(env, kimlik, appCheck, 'friendships', chatId),
    kullaniciAdinaDurum(env, kimlik, appCheck, 'engellenenler', chatId),
  ]);
  if (!varMi(arkadaslik, 'friendships')) throw new IstekHatasi(403, 'izin');
  if (varMi(engel, 'engellenenler')) throw new IstekHatasi(403, 'engel');

  if (!env.AGORA_APP_ID || !env.AGORA_APP_CERTIFICATE) {
    console.error('AGORA_APP_ID / AGORA_APP_CERTIFICATE eksik');
    throw new IstekHatasi(500, 'yapilandirma');
  }
  const token = RtcTokenBuilder.buildTokenWithUid(
    env.AGORA_APP_ID,
    env.AGORA_APP_CERTIFICATE,
    kanal,
    0,
    RtcRole.PUBLISHER,
    AGORA_SURE,
    AGORA_SURE,
  );
  return json(200, { token });
}

// ─── Yönlendirme ──────────────────────────────────────────────────

const YOLLAR = {
  '/bildirim': bildirim,
  '/agora-token': agoraToken,
};

export async function isle(istek, env) {
  try {
    const yol = new URL(istek.url).pathname.replace(/\/+$/, '');
    const isleyici = YOLLAR[yol];
    if (!isleyici) return hata(404, 'yol');
    if (istek.method !== 'POST') {
      return new Response(JSON.stringify({ hata: 'yontem' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json; charset=utf-8', Allow: 'POST' },
      });
    }
    // Kimlik gövdeden ÖNCE: kimliksiz istek gövde okutup kaynak harcatmasın.
    const kimlik = await kimlikDogrula(istek, env);
    return await isleyici(istek, env, kimlik);
  } catch (e) {
    if (e instanceof IstekHatasi) return hata(e.durum, e.kod);
    console.error('beklenmeyen hata', e?.stack ?? e);
    return hata(500, 'ic');
  }
}
