// Firestore güvenlik kuralları birim testi (18 senaryo).
// ÇALIŞTIRMA (Java 21 gerekir — Android Studio JBR uygun):
//   1) geçici klasör aç, bu dosyayı + firestore.rules'u kopyala
//   2) npm init -y && npm pkg set type=module
//   3) npm i @firebase/rules-unit-testing firebase
//   4) firebase.json: {"firestore":{"rules":"firestore.rules"},"emulators":{"firestore":{"port":8080}}}
//   5) JAVA_HOME=<jbr> firebase emulators:exec --only firestore --project demo-x "node firestore_rules_test.mjs"
// Beklenen: 18 PASS / 0 FAIL (T6 fcmToken bilinen sınır olarak PASS sayılır).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc,
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
    await setDoc(doc(db, `chats/${pair('alice','bob')}`), { katilimcilar: ['alice','bob'].sort() });
    await setDoc(doc(db, `chats/${pair('alice','bob')}/messages/m1`), { gonderen: 'alice', metin: 'selam', goruldu: false });
    // bob -> carol bekleyen istek (kabul testi)
    await setDoc(doc(db, 'friend_requests/bob_carol'), { gonderenUid: 'bob', alanUid: 'carol', durum: 'bekliyor' });
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
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/m2`), { gonderen: 'alice', metin: 'sahte' }))), 'T4 baskasi adina mesaj yazilamaz');
log(await ok(assertSucceeds(setDoc(doc(B(), `chats/${AB}/messages/m3`), { gonderen: 'bob', metin: 'gercek' }))), 'T4b katilimci+arkadas kendi adina yazabilir');
log(await ok(assertFails(updateDoc(doc(C(), 'users/alice'), { ad: 'HACKED' }))), 'T5 baskasinin profili degistirilemez');
const t6 = await getDoc(doc(C(), 'users/alice')).then(s=>({ok:true,token:s.data()?.fcmToken}),()=>({ok:false}));
log(t6.ok, 'T6 fcmToken (BILINEN SINIR: okunabilir, kabul edildi)', t6.ok?`token='${t6.token}'`:'');
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
log(await ok(assertFails(setDoc(doc(B(), `chats/${AB}/messages/m9`), { gonderen: 'bob', metin: 'artik arkadas degiliz' }))), 'T11 arkadas cikinca yeni mesaj GONDERILEMEZ');
log(await ok(assertSucceeds(getDoc(doc(B(), `chats/${AB}/messages/m1`)))), 'T11b eski gecmis hala OKUNABILIR');
log(await ok(assertFails(setDoc(doc(B(), `aramalar/${AB}`), { arayanUid: 'bob', tip: 'ses' }))), 'T11c arkadas cikinca arama baslatilamaz');

console.log(`\n==== SONUC: ${pass} PASS / ${fail} FAIL ====`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
