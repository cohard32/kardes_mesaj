// Uzaktan teşhis raporlarını okur (Firestore `hatalar` koleksiyonu).
//
// ÇALIŞTIRMA:
//   1) geçici klasör aç, bu dosyayı kopyala
//   2) assets/service_account.json dosyasını sa.json olarak kopyala
//   3) npm init -y && npm pkg set type=module && npm i firebase-admin
//   4) node hatalari_oku.mjs [kaçAdet]
//
// Çıktı: en yeniden eskiye; her rapor için sürüm/cihaz/hata + ADIM ADIM izler.
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';

initializeApp({ credential: cert(JSON.parse(readFileSync('sa.json', 'utf8'))) });
const db = getFirestore();

const adet = Number(process.argv[2] || 5);
const snap = await db
  .collection('hatalar')
  .orderBy('zaman', 'desc')
  .limit(adet)
  .get();

if (snap.empty) {
  console.log('Hiç rapor yok.');
  process.exit(0);
}

snap.forEach((d) => {
  const x = d.data();
  const t = x.zaman?.toDate?.()?.toISOString?.() ?? '(zaman yok)';
  console.log('\n' + '='.repeat(72));
  console.log(`${t}  [${x.etiket}]  v${x.surum}`);
  console.log(`uid: ${x.uid}`);
  console.log(`cihaz: ${x.cihaz}`);
  console.log(`HATA: ${x.hata}`);
  if (x.stack) console.log(`STACK:\n${x.stack}`);
  console.log('--- ADIMLAR (eski → yeni) ---');
  (x.izler ?? []).forEach((i) => console.log('  ' + i));
});
process.exit(0);
