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
  cagrilar = { oauth: 0, fcm: [], firestore: [] };
  durum = {
    friendships: new Map([[AB, [ALICE, BOB]]]),
    engellenenler: new Map(),
    friend_requests: new Map(),
    users: new Map([
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

  if (url.href.startsWith(FS_ON)) {
    const yol = decodeURIComponent(url.pathname.split('/documents/')[1]);
    const [koleksiyon, id] = yol.split('/');
    cagrilar.firestore.push({ koleksiyon, id, yetki, appCheck: basliklar.get('X-Firebase-AppCheck') });

    if (koleksiyon === 'users') {
      // Yalnız hizmet hesabı token'ıyla okunmalı.
      if (!yetki.startsWith('Bearer sa-erisim-')) return jsonYanit(403, {});
      const d = durum.users.get(id);
      if (!d) return jsonYanit(404, { error: { status: 'NOT_FOUND' } });
      assert.equal(url.searchParams.get('mask.fieldPaths'), 'fcmToken');
      return jsonYanit(200, { fields: { fcmToken: { stringValue: d.fcmToken } } });
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
    return uye ? jsonYanit(200, { name: yol }) : jsonYanit(403, { error: { status: 'PERMISSION_DENIED' } });
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

test('arkadaşa: FCM\'e alıcının token\'ı ve kanalıyla gider; okumalar kullanıcı token\'ıyla', async () => {
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
  const users = cagrilar.firestore.find((c) => c.koleksiyon === 'users');
  assert.equal(users.id, BOB);
  assert.equal(users.yetki, 'Bearer sa-erisim-1');
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
  assert.deepEqual(cagrilar.fcm[0].govde.message.data, { tur: 'arama_iptal', chatId: AB });
  assert.equal(cagrilar.fcm[0].govde.message.android.ttl, '45s');
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

test('alıcının fcmToken\'ı yoksa 404', async () => {
  durum.users.set(BOB, {});
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
