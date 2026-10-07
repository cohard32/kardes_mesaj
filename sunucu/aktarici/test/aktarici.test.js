// Aktarıcı testleri — gerçek ağ YOK: globalThis.fetch sahtelenir ve
// Firestore kuralları (friendships/engellenenler/friend_requests okuma)
// burada küçük bir benzetimle taklit edilir:
//   doküman yok → 404 (kurallar resource == null'a izin veriyor),
//   var ama üye değil → 403, var ve üye → 200.
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  exportJWK,
  exportPKCS8,
  generateKeyPair,
  jwtVerify,
  SignJWT,
  decodeProtectedHeader,
} from 'jose';
import agora from 'agora-token';

import { isle, onbellegiSifirla } from '../src/aktarici.js';
import worker from '../src/index.js';

const PROJE = 'kardes-mesaj';
const ALICE = 'aliceUid000000000000000000AA';
const BOB = 'bobUid00000000000000000000BB';
const CAROL = 'carolUid0000000000000000000C';
const MALLORY = 'malloryUid00000000000000000M';
const MALLORY2 = 'mallory2Uid0000000000000000N';
const ciftKimligi = (a, b) => [a, b].sort().join('_');
const AB = ciftKimligi(ALICE, BOB);
const KANAL = 'k_' + 'ab12'.repeat(8);

// ─── Anahtarlar ───────────────────────────────────────────────────
const firebaseAnahtar = await generateKeyPair('RS256');
const sahteAnahtar = await generateKeyPair('RS256'); // JWKS'te YOK
const saAnahtar = await generateKeyPair('RS256', { extractable: true });
const jwk = { ...(await exportJWK(firebaseAnahtar.publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };

const SA = {
  type: 'service_account',
  project_id: PROJE,
  private_key_id: 'saKid1',
  private_key: await exportPKCS8(saAnahtar.privateKey),
  client_email: 'roy-aktarici@kardes-mesaj.iam.gserviceaccount.com',
};

const env = {
  PROJE,
  AGORA_APP_ID: 'c2bf944aa30a48bcaad7f1be6694949e',
  AGORA_APP_CERTIFICATE: '0123456789abcdef0123456789abcdef',
  SERVICE_ACCOUNT: JSON.stringify(SA),
  TEST_JWKS: JSON.stringify({ keys: [jwk] }),
};

async function idToken(uid, { anahtar = firebaseAnahtar.privateKey, aud = PROJE, kid = 'k1' } = {}) {
  const simdi = Math.floor(Date.now() / 1000);
  return new SignJWT({ auth_time: simdi - 100 })
    .setProtectedHeader({ alg: 'RS256', kid })
    .setIssuer(`https://securetoken.google.com/${aud}`)
    .setAudience(aud)
    .setSubject(uid)
    .setIssuedAt(simdi - 10)
    .setExpirationTime(simdi + 3600)
    .sign(anahtar);
}

// ─── Sahte Google ─────────────────────────────────────────────────
let durum;
let cagrilar;

function sifirla() {
  onbellegiSifirla();
  cagrilar = { oauth: 0, fcm: [], firestore: [], sorgu: [] };
  durum = {
    friendships: new Map([[AB, [ALICE, BOB]]]),
    engellenenler: new Map(),
    friend_requests: new Map(),
    // HERKESE OKUNUR profil (users/{uid}). ⚠️ fcmToken burada da DURUYOR
    // (eski derlemeler yazar) — aktarıcı ona ASLA bakmamalı.
    users: new Map([
      [ALICE, { ad: 'Alice', kullaniciAdi: 'alice', bildirimKanali: 'km_v3_varsayilan', fcmToken: 'public-alice' }],
      [BOB, { ad: 'Bob', kullaniciAdi: 'bob', bildirimKanali: 'km_v3_kedi', fcmToken: 'public-bob' }],
      [CAROL, { ad: 'Carol', kullaniciAdi: 'carol', bildirimKanali: 'km_v3_cingirak', fcmToken: 'public-carol' }],
    ]),
    // GİZLİ belge (users/{uid}/ozel/bildirim): yalnız sahibi + hizmet hesabı.
    ozel: new Map([
      [ALICE, { fcmToken: 'fcm-alice' }],
      [BOB, { fcmToken: 'fcm-bob' }],
      [CAROL, { fcmToken: 'fcm-carol' }],
    ]),
  };
}

const FS_ON = `https://firestore.googleapis.com/v1/projects/${PROJE}/databases/(default)/documents/`;

function jsonYanit(kod, govde) {
  return new Response(JSON.stringify(govde), {
    status: kod,
    headers: { 'Content-Type': 'application/json' },
  });
}

/// Düz JS değerini Firestore REST değer biçimine çevirir.
function fsDeger(v) {
  if (Array.isArray(v)) return { arrayValue: v.length ? { values: v.map(fsDeger) } : {} };
  if (typeof v === 'number') return { integerValue: String(v) };
  return { stringValue: v };
}

/// Belgenin YALNIZ maskedeki alanlarını REST biçiminde döner.
function maskeli(belge, maske) {
  const fields = {};
  for (const a of maske) if (a in belge) fields[a] = fsDeger(belge[a]);
  return fields;
}

globalThis.fetch = async (girdi, secenek = {}) => {
  const url = new URL(typeof girdi === 'string' ? girdi : girdi.url);
  const basliklar = new Headers(secenek.headers);
  const yetki = basliklar.get('Authorization') ?? '';

  if (url.href === 'https://oauth2.googleapis.com/token') {
    cagrilar.oauth++;
    const assertion = new URLSearchParams(secenek.body).get('assertion');
    // İmza hizmet hesabının anahtarıyla mı ve kapsamlar doğru mu?
    const { payload } = await jwtVerify(assertion, saAnahtar.publicKey, {
      issuer: SA.client_email,
      audience: 'https://oauth2.googleapis.com/token',
    });
    assert.match(payload.scope, /firebase\.messaging/);
    assert.match(payload.scope, /datastore/);
    assert.equal(decodeProtectedHeader(assertion).kid, 'saKid1');
    return jsonYanit(200, { access_token: `sa-erisim-${cagrilar.oauth}`, expires_in: 3599 });
  }

  // Token çakışma sorgusu (runQuery) — yalnız hizmet hesabıyla, yalnız kök
  // `users` koleksiyonunda fcmToken == değer.
  if (url.href === `${FS_ON.slice(0, -1)}:runQuery`) {
    assert.equal(secenek.method, 'POST');
    if (!yetki.startsWith('Bearer sa-erisim-')) return jsonYanit(403, {});
    const { structuredQuery: q } = JSON.parse(secenek.body);
    assert.deepEqual(q.from, [{ collectionId: 'users' }]);
    assert.equal(q.where.fieldFilter.field.fieldPath, 'fcmToken');
    assert.equal(q.where.fieldFilter.op, 'EQUAL');
    assert.deepEqual(q.select, { fields: [{ fieldPath: '__name__' }] });
    const deger = q.where.fieldFilter.value.stringValue;
    cagrilar.sorgu.push(deger);
    const bulunan = [...durum.users]
      .filter(([, b]) => b.fcmToken === deger)
      .slice(0, q.limit)
      .map(([uid]) => ({
        document: { name: `projects/${PROJE}/databases/(default)/documents/users/${uid}` },
        readTime: '2026-01-01T00:00:00Z',
      }));
    return jsonYanit(200, bulunan.length ? bulunan : [{ readTime: '2026-01-01T00:00:00Z' }]);
  }

  if (url.href.startsWith(FS_ON)) {
    const yol = decodeURIComponent(url.pathname.split('/documents/')[1]);
    const parcalar = yol.split('/');
    const [koleksiyon, id] = parcalar;
    const maske = url.searchParams.getAll('mask.fieldPaths');
    cagrilar.firestore.push({
      koleksiyon, id, yol, maske, yetki, appCheck: basliklar.get('X-Firebase-AppCheck'),
    });

    if (koleksiyon === 'users') {
      // Yalnız hizmet hesabı token'ıyla ve MASKEYLE okunmalı.
      if (!yetki.startsWith('Bearer sa-erisim-')) return jsonYanit(403, {});
      assert.ok(maske.length > 0, 'users okuması maskesiz');
      let belge;
      if (parcalar.length === 2) {
        belge = durum.users.get(id);
      } else {
        assert.deepEqual(parcalar.slice(2), ['ozel', 'bildirim']);
        belge = durum.ozel.get(id);
      }
      if (!belge) return jsonYanit(404, { error: { status: 'NOT_FOUND' } });
      return jsonYanit(200, { name: yol, fields: maskeli(belge, maske) });
    }

    // Kullanıcı adına okumalar: ID token'dan uid çıkar, kuralları uygula.
    let uid;
    try {
      ({ payload: { sub: uid } } = await jwtVerify(yetki.replace('Bearer ', ''), firebaseAnahtar.publicKey));
    } catch {
      return jsonYanit(401, {});
    }
    const tablo = durum[koleksiyon];
    if (!tablo) return jsonYanit(403, {});
    const d = tablo.get(id);
    if (d === undefined) return jsonYanit(404, { error: { status: 'NOT_FOUND' } });
    const uye = koleksiyon === 'friend_requests'
      ? d.gonderenUid === uid || d.alanUid === uid
      : d.includes(uid);
    if (!uye) return jsonYanit(403, { error: { status: 'PERMISSION_DENIED' } });
    const fields = koleksiyon === 'friend_requests'
      ? maskeli(d, Object.keys(d))
      : { uidler: fsDeger(d) };
    return jsonYanit(200, { name: yol, fields });
  }

  if (url.href === `https://fcm.googleapis.com/v1/projects/${PROJE}/messages:send`) {
    cagrilar.fcm.push({ yetki, govde: JSON.parse(secenek.body) });
    return jsonYanit(200, { name: 'projects/kardes-mesaj/messages/1' });
  }

  throw new Error('beklenmeyen fetch: ' + url.href);
};

beforeEach(sifirla);

// ─── Yardımcılar ──────────────────────────────────────────────────
async function istek(yol, govde, { token, basliklar = {}, yontem = 'POST', ham } = {}) {
  const h = { 'Content-Type': 'application/json', ...basliklar };
  if (token) h.Authorization = `Bearer ${token}`;
  return isle(
    new Request(`https://roy-aktarici.test.workers.dev${yol}`, {
      method: yontem,
      headers: h,
      body: yontem === 'POST' ? (ham ?? JSON.stringify(govde)) : undefined,
    }),
    env,
  );
}

const mesajBildirimi = () => ({
  notification: { title: 'Alice', body: 'merhaba' },
  data: { tur: 'mesaj', chatId: AB, gonderenUid: ALICE },
  android: {
    priority: 'HIGH',
    notification: { channel_id: 'km_v3_kedi', visibility: 'PUBLIC', tag: `km_${BOB}` },
  },
});

// ─── Kimlik ───────────────────────────────────────────────────────
test('Authorization başlığı yoksa 401', async () => {
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() });
  assert.equal(r.status, 401);
  assert.deepEqual(await r.json(), { hata: 'kimlik' });
  assert.equal(cagrilar.firestore.length, 0);
});

test('JWKS dışı anahtarla imzalı token 401', async () => {
  const token = await idToken(ALICE, { anahtar: sahteAnahtar.privateKey });
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 401);
});

test('başka projenin token\'ı (yanlış audience) 401', async () => {
  const token = await idToken(ALICE, { aud: 'baska-proje' });
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 401);
});

test('POST dışı 405, bilinmeyen yol 404', async () => {
  const token = await idToken(ALICE);
  assert.equal((await istek('/bildirim', null, { token, yontem: 'GET' })).status, 405);
  assert.equal((await istek('/yok', {}, { token })).status, 404);
});

// ─── /bildirim ────────────────────────────────────────────────────
test('arkadaş değilse 403 ve FCM\'e gidilmez', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: CAROL,
    mesaj: { notification: { title: 'x', body: 'y' } },
  }, { token });
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { hata: 'izin' });
  assert.equal(cagrilar.fcm.length, 0);
});

test('arkadaşa: FCM\'e alıcının GİZLİ token\'ı ve YAYINLADIĞI kanalıyla gider', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, {
    token,
    basliklar: { 'X-Firebase-AppCheck': 'appcheck-belirteci' },
  });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm.length, 1);
  const { yetki, govde } = cagrilar.fcm[0];
  assert.equal(yetki, 'Bearer sa-erisim-1');
  assert.equal(govde.message.token, 'fcm-bob');
  assert.equal(govde.message.android.notification.channel_id, 'km_v3_kedi');
  assert.equal(govde.message.android.priority, 'HIGH');
  assert.deepEqual(govde.message.notification, { title: 'Alice', body: 'merhaba' });

  // Kural okumaları kullanıcının KENDİ token'ıyla ve App Check iletilerek.
  for (const c of cagrilar.firestore.filter((c) => c.koleksiyon !== 'users')) {
    assert.equal(c.yetki, `Bearer ${token}`);
    assert.equal(c.appCheck, 'appcheck-belirteci');
  }
  // users okumaları YALNIZ hizmet hesabıyla; token gizli belgeden.
  const users = cagrilar.firestore.filter((c) => c.koleksiyon === 'users');
  for (const c of users) assert.equal(c.yetki, 'Bearer sa-erisim-1');
  assert.ok(users.some((c) => c.yol === `users/${BOB}/ozel/bildirim` && c.maske.includes('fcmToken')));
});

test('arkadaşlık isteği bildirimi: friend_requests/{ben}_{hedef} varsa geçer', async () => {
  durum.friend_requests.set(`${ALICE}_${CAROL}`, { gonderenUid: ALICE, alanUid: CAROL });
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: CAROL,
    mesaj: { notification: { title: 'Alice', body: 'sana arkadaşlık isteği gönderdi' } },
  }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.token, 'fcm-carol');
});

test('istek yolu: istemci gövdesi YOK SAYILIR → sabit gövde + gerçek ad, data yok', async () => {
  durum.friend_requests.set(`${ALICE}_${CAROL}`, { gonderenUid: ALICE, alanUid: CAROL });
  const token = await idToken(ALICE);
  const AC = ciftKimligi(ALICE, CAROL);
  for (const mesaj of [
    { notification: { title: 'Annen', body: 'hemen ara' }, data: { tur: 'mesaj', chatId: AC } },
    // Sahte gelen arama denemesi (d12): bekleyen istekle ÇALDIRILAMAZ.
    { data: { tur: 'arama', chatId: AC, arayan: 'Annen', tip: 'video', kanal: KANAL },
      android: { priority: 'HIGH', ttl: '45s', notification: { channel_id: 'km_v3_kedi' } } },
  ]) {
    cagrilar.fcm = [];
    const r = await istek('/bildirim', { hedefUid: CAROL, mesaj }, { token });
    assert.equal(r.status, 200);
    const m = cagrilar.fcm[0].govde.message;
    assert.deepEqual(Object.keys(m).sort(), ['android', 'notification', 'token']);
    assert.deepEqual(m.notification, { title: 'Alice', body: 'sana arkadaşlık isteği gönderdi' });
    assert.equal(m.data, undefined);
    assert.equal(m.android.ttl, undefined);
    // Alıcının (Carol) yayınladığı kanal; istemcinin km_v3_kedi'si değil.
    assert.equal(m.android.notification.channel_id, 'km_v3_cingirak');
  }
});

test('istek yolu: ad yoksa @kullaniciAdi, o da yoksa uygulama adı', async () => {
  durum.friend_requests.set(`${ALICE}_${CAROL}`, { gonderenUid: ALICE, alanUid: CAROL });
  const token = await idToken(ALICE);
  durum.users.set(ALICE, { kullaniciAdi: 'alice' });
  await istek('/bildirim', { hedefUid: CAROL, mesaj: { notification: { body: 'x' } } }, { token });
  assert.equal(cagrilar.fcm[0].govde.message.notification.title, '@alice');
  durum.users.delete(ALICE);
  await istek('/bildirim', { hedefUid: CAROL, mesaj: { notification: { body: 'x' } } }, { token });
  assert.equal(cagrilar.fcm[1].govde.message.notification.title, 'ROY MESSANGER');
});

test('istek belgesinin İÇERİĞİ uyuşmazsa (eski kuralla açılmış) 403', async () => {
  // Kimlik {ben}_{kurban} ama içerik başka birine (t3): kurban göremez/silemez.
  durum.friend_requests.set(`${MALLORY}_${CAROL}`, { gonderenUid: MALLORY, alanUid: MALLORY2 });
  const token = await idToken(MALLORY);
  const r = await istek('/bildirim', {
    hedefUid: CAROL, mesaj: { notification: { title: 'x', body: 'y' } },
  }, { token });
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { hata: 'izin' });
  assert.equal(cagrilar.fcm.length, 0);
  // gonderenUid uyuşmazlığı da 403.
  durum.friend_requests.set(`${MALLORY}_${CAROL}`, { gonderenUid: CAROL, alanUid: MALLORY });
  const r2 = await istek('/bildirim', {
    hedefUid: CAROL, mesaj: { notification: { title: 'x', body: 'y' } },
  }, { token });
  assert.equal(r2.status, 403);
});

test('KURBAN TOKEN SAHTECİLİĞİ (d10): public fcmToken ASLA kullanılmaz', async () => {
  // Mallory, kurban Carol'ın token'ını kendi ikinci hesabının (M2) HERKESE
  // OKUNUR belgesine yazar, M1'den M2'ye istek atıp /bildirim çağırır.
  // ⚠️ Bu test yalnız "token KAYNAĞI public alan değil" kısmını sınar; kurban
  // token'ının saldırganın GİZLİ belgesine yazılması aşağıdaki "2. tur"
  // testinde (409) sınanır.
  durum.users.set(MALLORY, { ad: 'Mallory' });
  durum.users.set(MALLORY2, { ad: 'M2', fcmToken: 'fcm-carol' });
  durum.friend_requests.set(`${MALLORY}_${MALLORY2}`, { gonderenUid: MALLORY, alanUid: MALLORY2 });
  const token = await idToken(MALLORY);
  const mesaj = { data: { tur: 'mesaj' }, notification: { title: 'Annen', body: 'x' } };

  // 1) M2'nin gizli belgesi yok → 404, FCM'e HİÇ gidilmez.
  const r = await istek('/bildirim', { hedefUid: MALLORY2, mesaj }, { token });
  assert.equal(r.status, 404);
  assert.deepEqual(await r.json(), { hata: 'token_yok' });
  assert.equal(cagrilar.fcm.length, 0);

  // 2) Gizli belgede saldırganın KENDİ token'ı → yalnız ona gider.
  durum.ozel.set(MALLORY2, { fcmToken: 'fcm-m2-gizli' });
  const r2 = await istek('/bildirim', { hedefUid: MALLORY2, mesaj }, { token });
  assert.equal(r2.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.token, 'fcm-m2-gizli');
  // Public belgeden fcmToken hiç İSTENMEDİ.
  for (const c of cagrilar.firestore.filter((c) => c.yol === `users/${MALLORY2}`)) {
    assert.ok(!c.maske.includes('fcmToken'), 'public fcmToken okundu');
  }
  assert.ok(cagrilar.fcm.every((f) => f.govde.message.token !== 'fcm-carol'));
});

test('KURBAN TOKEN SAHTECİLİĞİ (d10, 2. tur): başkasının public token\'ı gizli belgeye yazılırsa 409', async () => {
  // Carol eski (aktarıcısız) derlemede: token'ı public belgesinde okunur.
  // Mallory onu kendi ikinci hesabının GİZLİ belgesine yazar (kural izin
  // verir: değer serbest), M1→M2 "arkadaş" yapıp sahte "Annen arıyor" atar.
  const carolToken = 'public-carol';
  durum.users.set(MALLORY, { ad: 'Annen' });
  durum.users.set(MALLORY2, { ad: 'M2' });
  durum.ozel.set(MALLORY2, { fcmToken: carolToken });
  durum.friendships.set(ciftKimligi(MALLORY, MALLORY2), [MALLORY, MALLORY2]);
  const token = await idToken(MALLORY);
  const cift = ciftKimligi(MALLORY, MALLORY2);
  for (const mesaj of [
    { data: { tur: 'arama', chatId: cift, kanal: KANAL, tip: 'sesli' } },
    { data: { tur: 'arama_iptal', chatId: cift } },
    { notification: { title: 'x', body: 'y' } },
  ]) {
    const r = await istek('/bildirim', { hedefUid: MALLORY2, mesaj }, { token });
    assert.equal(r.status, 409);
    assert.deepEqual(await r.json(), { hata: 'token_cakismasi' });
  }
  assert.equal(cagrilar.fcm.length, 0, 'kurbanın cihazına push gitti');
  assert.deepEqual(cagrilar.sorgu, [carolToken, carolToken, carolToken]);
  // Arkadaşlık YOLU kapanmadı: aynı gönderen kendi gerçek token'ıyla geçer.
  durum.ozel.set(MALLORY2, { fcmToken: 'fcm-m2-gizli' });
  const r = await istek('/bildirim', {
    hedefUid: MALLORY2, mesaj: { notification: { title: 'x', body: 'y' } },
  }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.token, 'fcm-m2-gizli');
});

test('token çakışması: hedefin KENDİ public alanı (aktarıcısız yeni derleme) çakışma değildir', async () => {
  durum.users.get(BOB).fcmToken = 'fcm-bob'; // aynı değer public + gizli
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.token, 'fcm-bob');
  assert.deepEqual(cagrilar.sorgu, ['fcm-bob']);
});

test('token çakışması: hedefin kendisi + başka biri aynı token\'da → 409', async () => {
  durum.users.get(BOB).fcmToken = 'fcm-bob';
  durum.users.get(CAROL).fcmToken = 'fcm-bob';
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 409);
  assert.equal(cagrilar.fcm.length, 0);
});

test('token çakışma sorgusu başarısızsa GÖNDERİLMEZ (kapalı başarısız) → 502', async () => {
  const eski = globalThis.fetch;
  globalThis.fetch = async (girdi, s) => {
    if (String(girdi).endsWith(':runQuery')) return jsonYanit(400, { error: { status: 'FAILED_PRECONDITION' } });
    return eski(girdi, s);
  };
  try {
    const token = await idToken(ALICE);
    const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
    assert.equal(r.status, 502);
    assert.deepEqual(await r.json(), { hata: 'firestore' });
    assert.equal(cagrilar.fcm.length, 0);
  } finally {
    globalThis.fetch = eski;
  }
});

test('ters yöndeki istek ({hedef}_{ben}) bildirim izni VERMEZ', async () => {
  durum.friend_requests.set(`${CAROL}_${ALICE}`, { gonderenUid: CAROL, alanUid: ALICE });
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: CAROL, mesaj: { notification: { title: 'x', body: 'y' } },
  }, { token });
  assert.equal(r.status, 403);
});

test('engelliyse 403', async () => {
  durum.engellenenler.set(AB, [ALICE, BOB]);
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { hata: 'engel' });
  assert.equal(cagrilar.fcm.length, 0);
});

test('engelliyken arama_iptal geçer (çalan zil susturulabilmeli)', async () => {
  durum.engellenenler.set(AB, [ALICE, BOB]);
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB,
    mesaj: { data: { tur: 'arama_iptal', chatId: AB }, android: { priority: 'HIGH', ttl: '45s' } },
  }, { token });
  assert.equal(r.status, 200);
  const m = cagrilar.fcm[0].govde.message;
  assert.deepEqual(m.data, { tur: 'arama_iptal', chatId: AB });
  assert.equal(m.android.ttl, '45s');
  assert.equal(m.notification, undefined);
  assert.equal(m.android.notification, undefined);
  // İptalde ad/kanal gerekmez → yalnız gizli belge okunur (zil gecikmesin).
  assert.deepEqual(
    cagrilar.firestore.filter((c) => c.koleksiyon === 'users').map((c) => c.yol),
    [`users/${BOB}/ozel/bildirim`]);
});

test('engelliyken GÖRÜNÜR/ek alanlı arama_iptal 403 (d11)', async () => {
  durum.engellenenler.set(AB, [ALICE, BOB]);
  const token = await idToken(ALICE);
  for (const mesaj of [
    { notification: { title: 'Engel', body: 'yine buradayim' }, data: { tur: 'arama_iptal', chatId: AB } },
    { data: { tur: 'arama_iptal', chatId: AB }, android: { notification: { channel_id: 'km_v3_kedi' } } },
    { data: { tur: 'arama_iptal', chatId: AB, not: 'taciz metni' } },
    { data: { tur: 'arama_iptal', chatId: AB, gonderenUid: ALICE } },
  ]) {
    const r = await istek('/bildirim', { hedefUid: BOB, mesaj }, { token });
    assert.equal(r.status, 403, JSON.stringify(mesaj));
    assert.deepEqual(await r.json(), { hata: 'engel' });
  }
  assert.equal(cagrilar.fcm.length, 0);
});

test('engelliyken istek yolundan arama_iptal de geçmez', async () => {
  const AC = ciftKimligi(ALICE, CAROL);
  durum.friend_requests.set(`${ALICE}_${CAROL}`, { gonderenUid: ALICE, alanUid: CAROL });
  durum.engellenenler.set(AC, [ALICE, CAROL]);
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: CAROL, mesaj: { data: { tur: 'arama_iptal', chatId: AC } },
  }, { token });
  assert.equal(r.status, 403);
  assert.equal(cagrilar.fcm.length, 0);
});

test('chatId\'siz arama / arama_iptal 400 (CallKit kimliği = chatId)', async () => {
  const token = await idToken(ALICE);
  for (const tur of ['arama', 'arama_iptal']) {
    const r = await istek('/bildirim', {
      hedefUid: BOB, mesaj: { data: { tur, kanal: KANAL } },
    }, { token });
    assert.equal(r.status, 400, tur);
  }
  assert.equal(cagrilar.firestore.length, 0);
  assert.equal(cagrilar.fcm.length, 0);
});

test('gelen arama: arayan adı ve arayanUid SUNUCUDAN (isim sahteciliği yok)', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB,
    mesaj: { data: { tur: 'arama', chatId: AB, arayan: 'Annen', tip: 'video', kanal: KANAL } },
  }, { token });
  assert.equal(r.status, 200);
  const d = cagrilar.fcm[0].govde.message.data;
  assert.equal(d.arayan, 'Alice');
  assert.equal(d.arayanUid, ALICE);
  assert.equal(d.kanal, KANAL);
  // Veri push'unda görünür bildirim yok → alıcı profili (kanal) okunmaz.
  assert.ok(!cagrilar.firestore.some((c) => c.yol === `users/${BOB}`));
});

test('arkadaş bildirimi: başlık HER ZAMAN gönderenin gerçek adı', async () => {
  const token = await idToken(ALICE);
  const mesaj = mesajBildirimi();
  mesaj.notification.title = 'Annen';
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.notification.title, 'Alice');
});

test('SESSİZ sohbet: alıcının gizli listesindeyse kanal km_v3_sessiz_tsz\'ye EZİLİR (d6)', async () => {
  durum.ozel.set(BOB, { fcmToken: 'fcm-bob', sessizSohbetler: ['x_y', AB] });
  const token = await idToken(ALICE);
  // Eski sürüm gönderen gibi: istemci alıcının normal kanalını yazıyor.
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.android.notification.channel_id, 'km_v3_sessiz_tsz');
  // chatId'yi atlamak sessize almayı DELEMEZ (karar çifte bakar).
  const m2 = mesajBildirimi();
  delete m2.data;
  await istek('/bildirim', { hedefUid: BOB, mesaj: m2 }, { token });
  assert.equal(cagrilar.fcm[1].govde.message.android.notification.channel_id, 'km_v3_sessiz_tsz');
  // android.notification hiç gönderilmese de kanal sunucuda eklenir.
  await istek('/bildirim', {
    hedefUid: BOB, mesaj: { notification: { title: 'x', body: 'y' }, data: { chatId: AB } },
  }, { token });
  assert.equal(cagrilar.fcm[2].govde.message.android.notification.channel_id, 'km_v3_sessiz_tsz');
});

test('sessiz sohbet: başka sohbet sessizse etkilenmez; bildirimler KAPALIYSA kapali kalır', async () => {
  const token = await idToken(ALICE);
  durum.ozel.set(BOB, { fcmToken: 'fcm-bob', sessizSohbetler: ['x_y'] });
  await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(cagrilar.fcm[0].govde.message.android.notification.channel_id, 'km_v3_kedi');
  durum.ozel.set(BOB, { fcmToken: 'fcm-bob', sessizSohbetler: [AB] });
  durum.users.set(BOB, { ad: 'Bob', bildirimKanali: 'km_v3_kapali' });
  await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(cagrilar.fcm[1].govde.message.android.notification.channel_id, 'km_v3_kapali');
});

test('geçiş: public belgede kalmış eski sessizSohbetler de sessiz sayılır', async () => {
  durum.users.set(BOB, { ad: 'Bob', bildirimKanali: 'km_v3_kedi', sessizSohbetler: [AB] });
  const token = await idToken(ALICE);
  await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(cagrilar.fcm[0].govde.message.android.notification.channel_id, 'km_v3_sessiz_tsz');
});

test('bildirimKanali deseni: geçersiz/eski → km_v3_varsayilan; özel ses kimliği geçer', async () => {
  const token = await idToken(ALICE);
  const vakalar = [
    ['km_v2_kedi', 'km_v3_varsayilan'],
    ['kardes_mesaj_kanal', 'km_v3_varsayilan'],
    ['KM_V3_KEDI', 'km_v3_varsayilan'],
    ['km_v3_../x', 'km_v3_varsayilan'],
    ['km_v3_' + 'a'.repeat(41), 'km_v3_varsayilan'],
    [undefined, 'km_v3_varsayilan'],
    ['km_v3_ozel_1a2b3c4d', 'km_v3_ozel_1a2b3c4d'],
    ['km_v3_ozel_1a2b3c4d_tsz', 'km_v3_ozel_1a2b3c4d_tsz'],
    ['km_v3_kedi2_tsz', 'km_v3_kedi2_tsz'],
  ];
  for (const [yayin, beklenen] of vakalar) {
    cagrilar.fcm = [];
    durum.users.set(BOB, yayin === undefined ? { ad: 'Bob' } : { ad: 'Bob', bildirimKanali: yayin });
    await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
    assert.equal(cagrilar.fcm[0].govde.message.android.notification.channel_id, beklenen, String(yayin));
  }
});

test('bilinmeyen mesaj alanları (token/topic/apns, android.direct_boot_ok) atılır', async () => {
  const token = await idToken(ALICE);
  const mesaj = mesajBildirimi();
  mesaj.token = 'saldirganin-hedefi';
  mesaj.topic = 'herkes';
  mesaj.apns = { payload: {} };
  mesaj.notification.image = 'https://kotu.example/x.png';
  mesaj.android.direct_boot_ok = true;
  mesaj.android.notification.image = 'https://kotu.example/y.png';
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj }, { token });
  assert.equal(r.status, 200);
  const m = cagrilar.fcm[0].govde.message;
  assert.deepEqual(Object.keys(m).sort(), ['android', 'data', 'notification', 'token']);
  assert.equal(m.token, 'fcm-bob');
  assert.deepEqual(m.notification, { title: 'Alice', body: 'merhaba' });
  assert.deepEqual(Object.keys(m.android).sort(), ['notification', 'priority']);
  assert.deepEqual(Object.keys(m.android.notification).sort(), ['channel_id', 'tag', 'visibility']);
});

test('bildirim resmi: yalnız uygulamanın Cloudinary bulutu geçer', async () => {
  const token = await idToken(ALICE);
  const vakalar = [
    ['https://res.cloudinary.com/diifisaog/image/upload/c_limit,w_720,q_auto,f_jpg/v1/abc.png', true],
    ['https://res.cloudinary.com/diifisaog/video/upload/c_limit,w_720,q_auto,f_jpg/v1/abc.jpg', true],
    ['https://res.cloudinary.com/baskasi/image/upload/v1/abc.png', false],
    ['http://res.cloudinary.com/diifisaog/image/upload/v1/abc.png', false],
    ['https://res.cloudinary.com/diifisaog/raw/upload/v1/belge.pdf', false],
    ['https://res.cloudinary.com/diifisaog/image/upload/v1/a.png?u=https://kotu.example', false],
    ['https://res.cloudinary.com.kotu.example/diifisaog/image/upload/v1/a.png', false],
    ['https://res.cloudinary.com/diifisaog/image/upload/' + 'a'.repeat(401), false],
  ];
  for (const [resim, gecer] of vakalar) {
    cagrilar.fcm = [];
    const mesaj = mesajBildirimi();
    mesaj.notification.image = resim;
    const r = await istek('/bildirim', { hedefUid: BOB, mesaj }, { token });
    assert.equal(r.status, 200, resim);
    const n = cagrilar.fcm[0].govde.message.notification;
    assert.deepEqual(n, gecer
      ? { title: 'Alice', body: 'merhaba', image: resim }
      : { title: 'Alice', body: 'merhaba' }, resim);
  }
});

test('bildirim resmi string değilse 400', async () => {
  const token = await idToken(ALICE);
  const mesaj = mesajBildirimi();
  mesaj.notification.image = { url: 'https://res.cloudinary.com/diifisaog/image/upload/v1/a.png' };
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj }, { token });
  assert.equal(r.status, 400);
  assert.equal(cagrilar.fcm.length, 0);
});

test('data değeri string değilse 400', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB, mesaj: { data: { tur: 'mesaj', sayi: 3 } },
  }, { token });
  assert.equal(r.status, 400);
});

test('kimlik alanları damgalanır: sahte arayanUid gönderenin uid\'iyle değişir', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB,
    mesaj: { data: { tur: 'arama', chatId: AB, arayanUid: CAROL, kanal: KANAL } },
  }, { token });
  assert.equal(r.status, 200);
  assert.equal(cagrilar.fcm[0].govde.message.data.arayanUid, ALICE);
});

test('data.chatId başka bir çiftinse 400', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB, mesaj: { data: { tur: 'mesaj', chatId: ciftKimligi(BOB, CAROL) } },
  }, { token });
  assert.equal(r.status, 400);
});

test('kendine bildirim ve geçersiz hedefUid 400', async () => {
  const token = await idToken(ALICE);
  const m = { notification: { title: 'x', body: 'y' } };
  assert.equal((await istek('/bildirim', { hedefUid: ALICE, mesaj: m }, { token })).status, 400);
  assert.equal((await istek('/bildirim', { hedefUid: '../users/x', mesaj: m }, { token })).status, 400);
  assert.equal((await istek('/bildirim', { hedefUid: 'a'.repeat(129), mesaj: m }, { token })).status, 400);
  assert.equal(cagrilar.firestore.length, 0);
});

test('alıcının gizli belgesinde fcmToken yoksa 404', async () => {
  durum.ozel.set(BOB, { sessizSohbetler: [] });
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
  assert.equal(r.status, 404);
});

test('8 KB üstü gövde 413 (Content-Length ile)', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', {
    hedefUid: BOB,
    mesaj: { notification: { title: 'x', body: 'a'.repeat(9000) } },
  }, { token });
  assert.equal(r.status, 413);
  assert.equal(cagrilar.firestore.length, 0);
});

test('8 KB üstü gövde 413 (Content-Length olmadan, akış)', async () => {
  const token = await idToken(ALICE);
  const parca = new TextEncoder().encode('a'.repeat(4096));
  let kalan = 3;
  const akis = new ReadableStream({
    pull(c) {
      if (kalan-- > 0) c.enqueue(parca);
      else c.close();
    },
  });
  const r = await isle(new Request('https://x.workers.dev/bildirim', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: akis,
    duplex: 'half',
  }), env);
  assert.equal(r.status, 413);
});

test('bozuk JSON 400', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/bildirim', null, { token, ham: '{bozuk' });
  assert.equal(r.status, 400);
});

test('OAuth erişim token\'ı önbellekte: ikinci çağrıda yeniden istenmez', async () => {
  const token = await idToken(ALICE);
  assert.equal((await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token })).status, 200);
  assert.equal((await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token })).status, 200);
  assert.equal(cagrilar.oauth, 1);
  assert.equal(cagrilar.fcm[1].yetki, 'Bearer sa-erisim-1');
});

test('eşzamanlı ilk istekler tek OAuth isteği paylaşır', async () => {
  const token = await idToken(ALICE);
  const sonuc = await Promise.all([1, 2, 3].map(() =>
    istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token })));
  assert.deepEqual(sonuc.map((r) => r.status), [200, 200, 200]);
  assert.equal(cagrilar.oauth, 1);
});

test('Firestore geçici hatası (503) "izin yok" diye yutulmaz → 502', async () => {
  const eski = globalThis.fetch;
  globalThis.fetch = async (girdi, s) => {
    if (String(girdi).includes('/friendships/')) return jsonYanit(503, {});
    return eski(girdi, s);
  };
  try {
    const token = await idToken(ALICE);
    const r = await istek('/bildirim', { hedefUid: BOB, mesaj: mesajBildirimi() }, { token });
    assert.equal(r.status, 502);
    assert.deepEqual(await r.json(), { hata: 'firestore' });
  } finally {
    globalThis.fetch = eski;
  }
});

// ─── /agora-token ─────────────────────────────────────────────────
test('agora-token: çiftin üyesi 200 + token', async () => {
  const token = await idToken(BOB);
  const r = await istek('/agora-token', { chatId: AB, kanal: KANAL }, { token });
  assert.equal(r.status, 200);
  const { token: agoraTok } = await r.json();
  assert.equal(typeof agoraTok, 'string');
  assert.match(agoraTok, /^007/); // AccessToken2

  // Token gerçekten bu kanal için, uid'siz (= uid 0) ve sertifikayla imzalı mı?
  const AccessToken2 = (await import('agora-token/src/AccessToken2.js')).default.AccessToken2;
  const t = new AccessToken2();
  assert.equal(t.from_string(agoraTok), true);
  assert.equal(t.verifySignature(env.AGORA_APP_CERTIFICATE), true);
  assert.equal(t.verifySignature('f'.repeat(32)), false);
  const [rtc] = t.getServices(1); // kRtcServiceType
  assert.equal(rtc.__channel_name.toString(), KANAL);
  assert.equal(rtc.__uid.toString(), '');
  assert.equal(t.expire, 86400);
});

test('agora-token: eski k_<milisaniye> kanalı da kabul edilir', async () => {
  const token = await idToken(ALICE);
  const r = await istek('/agora-token', { chatId: AB, kanal: 'k_1712345678901' }, { token });
  assert.equal(r.status, 200);
});

test('agora-token: yabancı chatId 403 (Firestore\'a hiç gidilmez)', async () => {
  const token = await idToken(CAROL);
  const r = await istek('/agora-token', { chatId: AB, kanal: KANAL }, { token });
  assert.equal(r.status, 403);
  assert.equal(cagrilar.firestore.length, 0);
});

test('agora-token: arkadaşlık bitmişse 403', async () => {
  durum.friendships.delete(AB);
  const token = await idToken(ALICE);
  const r = await istek('/agora-token', { chatId: AB, kanal: KANAL }, { token });
  assert.equal(r.status, 403);
});

test('agora-token: engelliyse 403', async () => {
  durum.engellenenler.set(AB, [ALICE, BOB]);
  const token = await idToken(ALICE);
  const r = await istek('/agora-token', { chatId: AB, kanal: KANAL }, { token });
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { hata: 'engel' });
});

test('agora-token: kötü kanal ve sırasız chatId 400', async () => {
  const token = await idToken(ALICE);
  for (const kanal of ['k_kisa', 'k_' + 'AB12'.repeat(8), 'baska', 'k_' + 'a'.repeat(33)]) {
    const r = await istek('/agora-token', { chatId: AB, kanal }, { token });
    assert.equal(r.status, 400, kanal);
  }
  const ters = [ALICE, BOB].sort().reverse().join('_');
  assert.equal((await istek('/agora-token', { chatId: ters, kanal: KANAL }, { token })).status, 400);
});

test('Worker varsayılan dışa aktarımı fetch\'i isle\'ye bağlar', async () => {
  const r = await worker.fetch(new Request('https://x.workers.dev/bildirim', { method: 'POST' }), env);
  assert.equal(r.status, 401);
});

// agora import'u kullanılmadı uyarısı olmasın: paket gerçekten yükleniyor mu?
test('agora-token paketi yüklenebiliyor', () => {
  assert.equal(typeof agora.RtcTokenBuilder.buildTokenWithUid, 'function');
});
