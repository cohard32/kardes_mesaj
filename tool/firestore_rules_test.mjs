// Firestore güvenlik kuralları birim testi (97 senaryo).
// ÇALIŞTIRMA (Java 21 gerekir — Android Studio JBR uygun):
//   1) geçici klasör aç, bu dosyayı + firestore.rules'u kopyala
//   2) npm init -y && npm pkg set type=module
//   3) npm i @firebase/rules-unit-testing firebase
//   4) firebase.json: {"firestore":{"rules":"firestore.rules"},"emulators":{"firestore":{"port":8080}}}
//   5) JAVA_HOME=<jbr> firebase emulators:exec --only firestore --project demo-x "node firestore_rules_test.mjs"
// Beklenen: 97 PASS / 0 FAIL (T6 eski public fcmToken geçiş sınırı olarak PASS sayılır).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection,
  Timestamp as TS, serverTimestamp, writeBatch, increment,
  arrayUnion, arrayRemove, deleteField,
} from 'firebase/firestore';

const PROJECT = 'kardes-mesaj-test';
let pass = 0, fail = 0;
const log = (ok, name, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  -> ' + extra : ''}`);
  ok ? pass++ : fail++;
};

const env = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: { rules: readFileSync('firestore.rules', 'utf8') },
});

const pair = (a, b) => [a, b].sort().join('_');
async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { ad: 'Alice', kullaniciAdi: 'alice', fcmToken: 'TOKEN_ALICE' });
    await setDoc(doc(db, 'users/bob'),   { ad: 'Bob',   kullaniciAdi: 'bob',   fcmToken: 'TOKEN_BOB' });
    await setDoc(doc(db, 'users/carol'), { ad: 'Carol', kullaniciAdi: 'carol', fcmToken: 'TOKEN_CAROL' });
    await setDoc(doc(db, 'usernames/alice'), { uid: 'alice' });
    await setDoc(doc(db, 'usernames/bob'),   { uid: 'bob' });
    await setDoc(doc(db, `friendships/${pair('alice','bob')}`), { uidler: ['alice','bob'] });
    // alice & dave ARKADAŞ ama aralarında CHAT YOK (create/varlık-kontrol testi)
    await setDoc(doc(db, 'users/dave'), { ad: 'Dave', kullaniciAdi: 'dave' });
    await setDoc(doc(db, `friendships/${pair('alice','dave')}`), { uidler: ['alice','dave'] });
    await setDoc(doc(db, `chats/${pair('alice','bob')}`), { katilimcilar: ['alice','bob'].sort() });
    await setDoc(doc(db, `chats/${pair('alice','bob')}/messages/m1`), { gonderen: 'alice', metin: 'selam', goruldu: false });
    // bob -> carol bekleyen istek (kabul testi)
    await setDoc(doc(db, 'friend_requests/bob_carol'), { gonderenUid: 'bob', alanUid: 'carol', durum: 'bekliyor' });
    // ARAMA dokumani: alice-bob cifti arasinda aktif cagri (KANAL ADI hassas!)
    await setDoc(doc(db, `aramalar/${pair('alice','bob')}`), {
      arayanUid:'alice', arayan:'Alice', tip:'video',
      kanal:'k_GIZLI_KANAL', durum:'cagriliyor' });
  });
}
await seed();

const A = () => env.authenticatedContext('alice').firestore();
const B = () => env.authenticatedContext('bob').firestore();
const C = () => env.authenticatedContext('carol').firestore();
const AB = pair('alice','bob');
const ok = (p) => p.then(()=>true,()=>false);

// ---- ESKİ 12 TEST (regresyon) ----
log(await ok(assertFails(getDoc(doc(C(), `chats/${AB}`)))), 'T1 yabanci sohbet okuyamaz');
log(await ok(assertFails(getDoc(doc(C(), `chats/${AB}/messages/m1`)))), 'T2 yabanci mesaj okuyamaz');
log(await ok(assertFails(setDoc(doc(C(), `chats/${pair('alice','carol')}`), { katilimcilar: ['alice','carol'].sort() }))), 'T3 arkadas olmadan chat acilamaz');
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/m2`), { gonderen: 'alice', metin: 'sahte', zaman: serverTimestamp() }))), 'T4 baskasi adina mesaj yazilamaz');
log(await ok(assertSucceeds(setDoc(doc(B(), `chats/${AB}/messages/m3`), { gonderen: 'bob', metin: 'gercek', zaman: serverTimestamp() }))), 'T4b katilimci+arkadas kendi adina yazabilir');
log(await ok(assertFails(updateDoc(doc(C(), 'users/alice'), { ad: 'HACKED' }))), 'T5 baskasinin profili degistirilemez');
const t6 = await getDoc(doc(C(), 'users/alice')).then(s=>({ok:true,token:s.data()?.fcmToken}),()=>({ok:false}));
// T6: public profildeki ESKİ fcmToken hâlâ okunur (aktarıcısız eski derlemeler
// yazar). Aktarıcı ona BAKMAZ (yalnız gizli belge, OZ-serisi) → kabul edildi.
log(t6.ok, 'T6 eski public fcmToken (GECIS: okunabilir, aktarici kullanmaz)', t6.ok?`token='${t6.token}'`:'');
log(await ok(assertFails(setDoc(doc(C(), 'usernames/alice'), { uid: 'carol' }))), 'T7a alinmis ad calinamaz');
log(await ok(assertFails(setDoc(doc(C(), 'usernames/yeni'), { uid: 'alice' }))), 'T7b baska uid ile ad rezerve edilemez');
log(await ok(assertFails(setDoc(doc(C(), `friendships/${pair('alice','carol')}`), { uidler: ['alice','carol'] }))), 'T8 istek olmadan zorla arkadaslik KURULAMAZ (DUZELTILDI)');
log(await ok(assertSucceeds(setDoc(doc(C(), `friendships/${pair('bob','carol')}`), { uidler: ['bob','carol'] }))), 'T8b gecerli istek kabulu calisir (pozitif)');
log(await ok(assertFails(updateDoc(doc(C(), `chats/${AB}/messages/m1`), { goruldu: true }))), 'T9 yabanci mesaj guncelleyemez');

// ---- YENİ TESTLER ----
// T10: Katılımcı SADECE goruldu/tepki/sesDinlendi degistirebilir, metin/gonderen DEGIL
log(await ok(assertSucceeds(updateDoc(doc(B(), `chats/${AB}/messages/m1`), { goruldu: true }))), 'T10a katilimci goruldu isaretleyebilir');
log(await ok(assertFails(updateDoc(doc(B(), `chats/${AB}/messages/m1`), { metin: 'DEGISTIRILDI' }))), 'T10b katilimci baskasinin mesaj metnini degistiremez');
log(await ok(assertFails(updateDoc(doc(B(), `chats/${AB}/messages/m1`), { gonderen: 'bob' }))), 'T10c gonderen degistirilemez');

// T11: ARKADAŞ ÇIKINCA mevcut sohbette YENİ mesaj gonderilemez
await env.withSecurityRulesDisabled(async (ctx) => {
  await deleteDoc(doc(ctx.firestore(), `friendships/${AB}`)); // alice-bob artik arkadas degil
});
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/m9`), { gonderen: 'bob', metin: 'artik arkadas degiliz', zaman: serverTimestamp() }))), 'T11 arkadas cikinca yeni mesaj GONDERILEMEZ');
log(await ok(assertSucceeds(getDoc(doc(B(), `chats/${AB}/messages/m1`)))), 'T11b eski gecmis hala OKUNABILIR');
log(await ok(assertFails(setDoc(doc(B(), `aramalar/${AB}`), { arayanUid: 'bob', tip: 'ses' }))), 'T11c arkadas cikinca arama baslatilamaz');

// ---- SOHBET AÇMA (create) + VAR OLMAYAN CHAT VARLIK KONTROLÜ ----
const AD = pair('alice','dave');
log(await ok(assertSucceeds(getDoc(doc(A(), `chats/${AD}`)))), 'T12 arkadas var olmayan chat varlik kontrolu (get) OK');
log(await ok(assertSucceeds(setDoc(doc(A(), `chats/${AD}`), { katilimcilar: ['alice','dave'].sort() }))), 'T13 arkadas sohbet ACABILIR (create)');
log(await ok(assertFails(setDoc(doc(C(), `chats/${pair('carol','dave')}`), { katilimcilar: ['carol','dave'].sort() }))), 'T14 arkadas olmayan chat olusturamaz');

// ---- KAYIT AKISI: GIRIS YOKKEN @ad musaitlik kontrolu ----
const anon = env.unauthenticatedContext().firestore();
log(await ok(assertSucceeds(getDoc(doc(anon, 'usernames/alice')))), 'T15 girissiz @ad musaitlik GET (kayit) OK');
log(await ok(assertSucceeds(getDoc(doc(anon, 'usernames/bosbirad')))), 'T15b girissiz var-olmayan @ad GET OK');
log(await ok(assertFails(getDocs(collection(anon, 'usernames')))), 'T16 girissiz toplu username listeleme YASAK');
log(await ok(assertFails(getDoc(doc(anon, 'users/alice')))), 'T17 girissiz users okunamaz');

// ---- ARAMA GUVENLIGI (K1: yabanci baskalarinin aramasina erisemez) ----
// NOT: T11 alice-bob arkadasligini SILMISTI; arama testleri anlamli olsun diye
// (yabanci ENGELLENMELI ama UYELER calismali) arkadasligi geri kur.
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), `friendships/${AB}`), { uidler: ['alice','bob'] });
});
log(await ok(assertFails(getDoc(doc(C(), `aramalar/${AB}`)))),
  'T18 yabanci BASKALARININ arama dokumanini OKUYAMAZ (kanal adi sizmaz)');
log(await ok(assertFails(setDoc(doc(C(), `aramalar/${AB}`), { durum:'bitti' }))),
  'T19 yabanci baskalarinin aramasini DUSUREMEZ');
log(await ok(assertSucceeds(getDoc(doc(A(), `aramalar/${AB}`)))),
  'T20 arayan kendi aramasini okuyabilir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(B(), `aramalar/${AB}`), { durum:'kabul' }))),
  'T21 aranan KABUL yazabilir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(B(), `aramalar/${AB}`), { durum:'mesgul' }))),
  'T22 aranan MESGUL yazabilir (yeni ozellik, pozitif)');
log(await ok(assertSucceeds(getDoc(doc(A(), `aramalar/${pair('alice','dave')}`)))),
  'T23 uye var-olmayan arama dokumanini okuyabilir (varlik kontrolu)');

// ---- MESAJ SILME: yalniz KENDI mesajin ve yalniz ILK 60 SANIYE ----
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  const simdi = TS.now();
  const eskiT = TS.fromMillis(Date.now() - 5 * 60 * 1000);
  await setDoc(doc(db, `chats/${AB}/messages/s_yeni`), { gonderen:'alice', metin:'yeni', zaman:simdi });
  await setDoc(doc(db, `chats/${AB}/messages/s_eski`), { gonderen:'alice', metin:'eski', zaman:eskiT });
  await setDoc(doc(db, `chats/${AB}/messages/s_bob`),  { gonderen:'bob',   metin:'bob',  zaman:simdi });
});
log(await ok(assertFails(deleteDoc(doc(A(), `chats/${AB}/messages/s_bob`)))),
  'S1 BASKASININ mesaji silinemez');
log(await ok(assertFails(deleteDoc(doc(A(), `chats/${AB}/messages/s_eski`)))),
  'S2 1 DAKIKA dolmus mesaj silinemez');
log(await ok(assertSucceeds(deleteDoc(doc(A(), `chats/${AB}/messages/s_yeni`)))),
  'S3 kendi mesajini ILK 1 DK icinde silebilir (pozitif)');

// ---- ESKI KOLEKSIYONLAR KILITLI (K1/K2, yayin oncesi denetim) ----
// Eskiden ikisi de `if girisli()` idi: giris yapan HERKES 326 eski mesaji
// okuyup silebiliyor ve HERKESIN fcmToken'ini degistirebiliyordu.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'mesajlar/eski1'), { metin: 'eski gecmis' });
  await setDoc(doc(db, 'kullanicilar/bob'), { fcmToken: 'bobun-tokeni' });
});
log(await ok(assertFails(getDoc(doc(A(), 'mesajlar/eski1')))),
  'E1 eski mesajlar/ koleksiyonu OKUNAMAZ');
log(await ok(assertFails(deleteDoc(doc(A(), 'mesajlar/eski1')))),
  'E2 eski mesajlar/ koleksiyonu SILINEMEZ');
log(await ok(assertFails(setDoc(doc(A(), 'kullanicilar/bob'), { fcmToken:'sahte' }))),
  'E3 BASKASININ eski kullanicilar/ dokumanina yazilamaz (token calinamaz)');
log(await ok(assertFails(getDoc(doc(A(), 'kullanicilar/bob')))),
  'E4 BASKASININ eski kullanicilar/ dokumani okunamaz');
log(await ok(assertSucceeds(setDoc(doc(A(), 'kullanicilar/alice'), { fcmToken:'benim' }))),
  'E5 kendi eski kullanicilar/ dokumanina yazabilir (pozitif - teshis calisir)');

// ---- ENGELLEME ----
// Engel dokumani kimligi = ciftKimligi → tek dokuman iki yonu birden kapatir.
const ENGEL = `engellenenler/${AB}`;
log(await ok(assertFails(setDoc(doc(A(), ENGEL), { uidler:['alice','bob'], engelleyen:'bob' }))),
  'N1 BASKASI adina engel konamaz (engelleyen != auth.uid)');
log(await ok(assertFails(setDoc(doc(C(), ENGEL), { uidler:['alice','bob'], engelleyen:'carol' }))),
  'N2 yabanci BASKALARININ cifti icin engel olusturamaz');
log(await ok(assertSucceeds(setDoc(doc(A(), ENGEL), { uidler:['alice','bob'], engelleyen:'alice' }))),
  'N3 kisi karsi tarafi engelleyebilir (pozitif)');
log(await ok(assertFails(deleteDoc(doc(B(), ENGEL)))),
  'N4 ENGELLENEN taraf engeli KALDIRAMAZ (yoksa engelleme anlamsiz olurdu)');
log(await ok(assertFails(setDoc(doc(A(), `chats/${AB}/messages/n_a`), { gonderen:'alice', metin:'x', zaman: serverTimestamp() }))),
  'N5 ENGELLEYEN de mesaj atamaz (engel iki yonlu)');
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/n_b`), { gonderen:'bob', metin:'x', zaman: serverTimestamp() }))),
  'N6 ENGELLENEN mesaj atamaz');
log(await ok(assertFails(setDoc(doc(B(), `aramalar/${AB}`), { durum:'cagriliyor' }))),
  'N7 engelliyken ARAMA baslatilamaz');
log(await ok(assertSucceeds(getDoc(doc(B(), `aramalar/${AB}`)))),
  'N8 engelliyken arama dokumani OKUNABILIR (devam eden arama kapanabilsin)');
log(await ok(assertSucceeds(getDoc(doc(B(), `chats/${AB}/messages/s_bob`)))),
  'N9 engelliyken ESKI mesajlar okunmaya devam eder');
log(await ok(assertFails(getDoc(doc(C(), ENGEL)))),
  'N10 yabanci baskalarinin engel dokumanini okuyamaz');
log(await ok(assertSucceeds(deleteDoc(doc(A(), ENGEL)))),
  'N11 engeli KOYAN kaldirabilir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(A(), `chats/${AB}/messages/n_ok`), { gonderen:'alice', metin:'tekrar', zaman: serverTimestamp() }))),
  'N12 engel kalkinca mesajlasma devam eder (pozitif)');

// ---- KİMLİK / BÜTÜNLÜK DENETİMİ (G-serisi) ----
// Aşağıdaki açıkların HEPSİ eski kurallarda emülatörde "izin verildi" idi.
// Her saldırı testinin yanında meşru akışın çalıştığını gösteren pozitif
// test vardır (kural sıkılaştırması uygulamayı kırmasın).
const M = () => env.authenticatedContext('mallory').firestore();
const AM = pair('alice','mallory');
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/mallory'), { ad: 'Mallory', kullaniciAdi: 'mallory' });
  await setDoc(doc(db, 'usernames/mallory'), { uid: 'mallory' });
});

// G1: istek kimliği sahteciliği → onaysız arkadaşlık
log(await ok(assertFails(setDoc(doc(M(), 'friend_requests/alice_mallory'),
  { gonderenUid:'mallory', alanUid:'alice', durum:'bekliyor' }))),
  'G1a istek kimligi {gonderen}_{alan} olmali (sahte yon REDDEDILIR)');
log(await ok(assertFails(setDoc(doc(M(), `friendships/${AM}`), { uidler:['alice','mallory'] }))),
  'G1b sahte istek olmadan onaysiz arkadaslik KURULAMAZ');
log(await ok(assertSucceeds(setDoc(doc(M(), 'friend_requests/mallory_alice'),
  { gonderenUid:'mallory', alanUid:'alice', durum:'bekliyor', tarih: serverTimestamp() }))),
  'G1c dogru kimlikli istek gonderilebilir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(M(), 'friend_requests/mallory_alice'),
  { gonderenUid:'mallory', alanUid:'alice', durum:'bekliyor', tarih: serverTimestamp() }))),
  'G1d gonderen ayni istegi tekrar set edebilir (pozitif)');
log(await ok(assertFails(updateDoc(doc(A(), 'friend_requests/mallory_alice'), { alanUid:'carol' }))),
  'G1e istegin taraflari degistirilemez');
log(await ok(assertSucceeds(deleteDoc(doc(A(), 'friend_requests/mallory_alice')))),
  'G1f alan kisi istegi reddedebilir/silebilir (pozitif)');

// G2: arkadaşlık/sohbet kimliği uid'lerden türetilmeli
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'friend_requests/alice_mallory'),
    { gonderenUid:'alice', alanUid:'mallory', durum:'bekliyor' });
});
log(await ok(assertFails(setDoc(doc(M(), 'friendships/carol_dave'), { uidler:['alice','mallory'] }))),
  'G2a gercek istekle bile BASKA kimlikli arkadaslik acilamaz');
log(await ok(assertSucceeds(setDoc(doc(M(), `friendships/${AM}`), { uidler:['alice','mallory'], tarih: serverTimestamp() }))),
  'G2b gercek istegi kabul etmek calisir (pozitif)');
log(await ok(assertFails(setDoc(doc(M(), 'chats/carol_dave'), { katilimcilar:['alice','mallory'] }))),
  'G2c baskalarinin sohbet kimligi ISGAL edilemez');
log(await ok(assertSucceeds(setDoc(doc(M(), `chats/${AM}`), { katilimcilar:['alice','mallory'], olusturma: serverTimestamp() }))),
  'G2d arkadas kendi sohbetini acabilir (pozitif)');

// G2e: GERÇEK uid'ler büyük/küçük harf karışıktır. Kurallardaki `a < b`
// sıralaması istemcideki Dart `sort()` (kod birimi sırası) ile AYNI olmalı —
// aksi halde her yeni arkadaşlık reddedilirdi. ('A'=65 < 'a'=97)
{
  const uBuyuk = 'Ab1xYz', uKucuk = 'aZ9Qrs';
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `friend_requests/${uKucuk}_${uBuyuk}`),
      { gonderenUid: uKucuk, alanUid: uBuyuk, durum: 'bekliyor' });
  });
  const U = env.authenticatedContext(uBuyuk).firestore();
  const jsSirali = [uKucuk, uBuyuk].sort().join('_'); // Dart ile aynı sıra
  log(jsSirali === `${uBuyuk}_${uKucuk}` &&
      await ok(assertSucceeds(setDoc(doc(U, `friendships/${jsSirali}`), { uidler: [uKucuk, uBuyuk] }))),
    'G2e karisik harfli uidlerde istemci sirasi kuralla AYNI (pozitif)');
}

// G3: sahte engel (DoS) — yabancı başkalarının çiftine engel koyamaz
log(await ok(assertFails(setDoc(doc(M(), `engellenenler/${AB}`), { uidler:['mallory','zz'], engelleyen:'mallory' }))),
  'G3a yabanci baskalarinin ciftine kendi uidiyle ENGEL KOYAMAZ');
log(await ok(assertSucceeds(setDoc(doc(B(), `chats/${AB}/messages/g3`), { gonderen:'bob', metin:'hala yazabilirim', zaman: serverTimestamp() }))),
  'G3b alice-bob mesajlasmasi etkilenmez (pozitif)');

// G4: mesaj zaman damgası sunucu zamanı olmalı (60 sn silme kuralı delinmesin)
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/g4`),
  { gonderen:'bob', metin:'x', zaman: TS.fromDate(new Date('2100-01-01')) }))),
  'G4a gelecek tarihli zaman damgasi REDDEDILIR');
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/g4b`),
  { gonderen:'bob', metin:'x' }))),
  'G4b zaman damgasiz mesaj REDDEDILIR');
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/g4c`),
  { gonderen:'bob', metin:'x', zaman: serverTimestamp(), goruldu: false, admin: true }))),
  'G4c bilinmeyen alan eklenemez');
log(await ok(assertSucceeds(setDoc(doc(B(), `chats/${AB}/messages/g4d`),
  { gonderen:'bob', metin:'', tip:'resim', medyaUrl:'https://x/y.jpg', zaman: serverTimestamp(), goruldu: false }))),
  'G4d medya mesaji (istemcinin yazdigi alanlar) gonderilebilir (pozitif)');

// G5: @kullanıcı adı sahteciliği
log(await ok(assertFails(updateDoc(doc(M(), 'users/mallory'), { kullaniciAdi:'alice' }))),
  'G5a profilde BASKASININ @adi gosterilemez');
log(await ok(assertSucceeds(updateDoc(doc(M(), 'users/mallory'), { ad:'Mallory 2', bio:'merhaba', fcmToken:'t' }))),
  'G5b ad/bio/token guncelleme calisir (pozitif)');
{
  // Kayıt akışı: usernames + users AYNI batch/transaction'da (KullaniciServisi.kayitOl)
  const E = env.authenticatedContext('erin').firestore();
  const b = writeBatch(E);
  b.set(doc(E, 'usernames/erin'), { uid:'erin' });
  b.set(doc(E, 'users/erin'), { ad:'Erin', kullaniciAdi:'erin', cevrimici:false, olusturma: serverTimestamp() });
  log(await ok(assertSucceeds(b.commit())), 'G5c kayit (usernames+users ayni batch) calisir (pozitif)');
  const b2 = writeBatch(E);
  b2.set(doc(E, 'users/erin'), { ad:'Erin', kullaniciAdi:'bob' });
  log(await ok(assertFails(b2.commit())), 'G5d sonradan @ad DEGISTIRILEMEZ');
}
{
  // Eski hesap: users/{uid} var ama kullaniciAdi YOK (yalnız token) → profilKur
  const F = env.authenticatedContext('frank').firestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/frank'), { fcmToken:'eski' });
  });
  const b = writeBatch(F);
  b.set(doc(F, 'usernames/frank'), { uid:'frank' });
  b.set(doc(F, 'users/frank'), { ad:'Frank', kullaniciAdi:'frank', cevrimici:false });
  log(await ok(assertSucceeds(b.commit())), 'G5e eski hesap profil kurulumu calisir (pozitif)');
}

// G6: katılımcı sohbetten karşı tarafı atamaz / üçüncü kişi ekleyemez
log(await ok(assertFails(updateDoc(doc(B(), `chats/${AB}`), { katilimcilar:['bob','mallory'] }))),
  'G6a katilimcilar DEGISTIRILEMEZ');
log(await ok(assertSucceeds(setDoc(doc(B(), `chats/${AB}`),
  { sonMesaj:'selam', sonMesajZamani: serverTimestamp(), sonMesajGonderen:'bob', okunmamis:{ alice: increment(1) } },
  { merge: true }))),
  'G6b mesaj meta guncellemesi calisir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(A(), `chats/${AB}`), { okunmamis:{ alice: 0 }, yaziyor:{ alice: true } }, { merge: true }))),
  'G6c okundu + yaziyor guncellemesi calisir (pozitif)');

// G7: engellenen kişi istek (ve dolayısıyla bildirim) gönderemez
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), `engellenenler/${pair('carol','mallory')}`),
    { uidler:['carol','mallory'], engelleyen:'carol' });
});
log(await ok(assertFails(setDoc(doc(M(), 'friend_requests/mallory_carol'),
  { gonderenUid:'mallory', alanUid:'carol', durum:'bekliyor' }))),
  'G7 engelliyken arkadaslik istegi GONDERILEMEZ');

// ---- Y: MESAJA YANIT (alıntı) ----
// yanitId / yanitOnizleme / yanitGonderen OPSİYONEL; tip ve uzunluk sunucuda
// denetlenir (önizleme ≤ 120 karakter — istemci yanitOnizlemeSiniri ile aynı).
const yanitli = (id, ek) => setDoc(doc(B(), `chats/${AB}/messages/${id}`), {
  gonderen:'bob', metin:'katiliyorum', tip:'metin', zaman: serverTimestamp(), goruldu:false, ...ek });
log(await ok(assertSucceeds(yanitli('y1', { yanitId:'m1', yanitOnizleme:'selam', yanitGonderen:'alice' }))),
  'Y1 yanitli metin mesaji gonderilebilir (pozitif)');
log(await ok(assertSucceeds(yanitli('y2', { yanitId:'g3', yanitOnizleme:'📷 Fotoğraf', yanitGonderen:'bob' }))),
  'Y2 kendi medya mesajina yanit (etiketli onizleme) gonderilebilir (pozitif)');
// Sınır değeri: tam 120 karakter (Türkçe harf) kabul — istemci kısaltması
// kuralla uyumlu olmalı (kural karakter sayar, bayt değil).
log(await ok(assertSucceeds(yanitli('y3', { yanitId:'m1', yanitOnizleme:'ş'.repeat(120), yanitGonderen:'alice' }))),
  'Y3 tam 120 karakterlik (Turkce) onizleme kabul edilir (pozitif)');
log(await ok(assertFails(yanitli('y4', { yanitId:'m1', yanitOnizleme:'a'.repeat(121), yanitGonderen:'alice' }))),
  'Y4 121+ karakterlik onizleme REDDEDILIR');
log(await ok(assertFails(yanitli('y5', { yanitId: 42, yanitOnizleme:'selam', yanitGonderen:'alice' }))),
  'Y5 string olmayan yanitId REDDEDILIR');
log(await ok(assertFails(yanitli('y6', { yanitId:'m1', yanitOnizleme:{ x: 1 }, yanitGonderen:'alice' }))),
  'Y6 string olmayan yanitOnizleme REDDEDILIR');
log(await ok(assertFails(yanitli('y7', { yanitId:'m1', yanitOnizleme:'selam', yanitGonderen:'mallory' }))),
  'Y7 sohbet disi kisiye ait sahte alinti (yanitGonderen) REDDEDILIR');
log(await ok(assertFails(updateDoc(doc(A(), `chats/${AB}/messages/y1`), { yanitOnizleme:'degistirildi' }))),
  'Y8 yanit alintisi sonradan DEGISTIRILEMEZ');

// ---- OZ: GİZLİ KULLANICI BELGESİ (users/{uid}/ozel/bildirim) ----
// fcmToken + sessizSohbetler artık burada: YALNIZ sahibi okur/yazar
// (aktarıcı hizmet hesabıyla okur). ⚠️ Eskiden token herkese okunur
// profildeydi → saldırgan kurbanın token'ını kendi belgesine yazıp
// aktarıcının yetki denetimini atlatabiliyordu (d10).
const OZEL = (u) => `users/${u}/ozel/bildirim`;
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), OZEL('bob')), { fcmToken: 'GIZLI_BOB', sessizSohbetler: [AB] });
});
log(await ok(assertSucceeds(setDoc(doc(A(), OZEL('alice')), { fcmToken: 'GIZLI_ALICE', guncelleme: serverTimestamp() }, { merge: true }))),
  'OZ1 sahibi kendi gizli belgesine token yazabilir (pozitif)');
log(await ok(assertSucceeds(getDoc(doc(A(), OZEL('alice'))))),
  'OZ2 sahibi kendi gizli belgesini okuyabilir (pozitif)');
log(await ok(assertFails(getDoc(doc(A(), OZEL('bob'))))),
  'OZ3 ARKADAS bile baskasinin gizli belgesini (token) OKUYAMAZ');
log(await ok(assertFails(getDoc(doc(C(), OZEL('bob'))))),
  'OZ4 yabanci baskasinin gizli belgesini OKUYAMAZ');
log(await ok(assertFails(setDoc(doc(C(), OZEL('bob')), { fcmToken: 'SAHTE' }, { merge: true }))),
  'OZ5 baskasinin gizli belgesine token YAZILAMAZ');
log(await ok(assertFails(getDocs(collection(C(), 'users/bob/ozel')))),
  'OZ6 baskasinin gizli belgeleri LISTELENEMEZ');
log(await ok(assertFails(getDoc(doc(anon, OZEL('bob'))))),
  'OZ7 girissiz gizli belge okunamaz');
log(await ok(assertSucceeds(setDoc(doc(A(), OZEL('alice')), { fcmToken: deleteField() }, { merge: true }))),
  'OZ8 cikista kendi tokenini silebilir (pozitif)');

// ---- SZ: SOHBETİ SESSİZE ALMA (gizli belgede) ----
log(await ok(assertSucceeds(setDoc(doc(A(), OZEL('alice')), { sessizSohbetler: arrayUnion(AB) }, { merge: true }))),
  'SZ1 kendi sessiz listesine sohbet ekleyebilir (pozitif)');
log(await ok(assertSucceeds(setDoc(doc(A(), OZEL('alice')), { sessizSohbetler: arrayRemove(AB) }, { merge: true }))),
  'SZ2 sessizi kapatabilir (pozitif)');
log(await ok(assertFails(setDoc(doc(C(), OZEL('alice')), { sessizSohbetler: arrayUnion(AB) }, { merge: true }))),
  'SZ3 BASKASININ sessiz listesi degistirilemez');
// Geçiş: eski sürümün herkese okunur profile yazdığı liste temizlenebilmeli.
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'users/alice'), { sessizSohbetler: [AB] }, { merge: true });
});
log(await ok(assertSucceeds(setDoc(doc(A(), 'users/alice'), { sessizSohbetler: deleteField(), fcmToken: deleteField() }, { merge: true }))),
  'SZ4 eski public sessizSohbetler/fcmToken alani silinebilir (pozitif, gecis)');

console.log(`\n==== SONUC: ${pass} PASS / ${fail} FAIL ====`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
