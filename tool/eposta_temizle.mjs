// GİZLİLİK TEMİZLİĞİ — `users/{uid}` dokümanlarındaki `eposta` alanını siler.
//
// NEDEN: `users/{uid}` dokümanı, kullanıcı arama/profil görüntüleme çalışsın
// diye GİRİŞ YAPMIŞ HERKESE okunur (firestore.rules → `allow read: if girisli()`).
// v1.8.0'a kadar kayıt/profil kurulumu bu dokümana `eposta` alanını da
// yazıyordu → arayüzde gösterilmese bile herkesin e-postası API'den okunabilir
// durumdaydı. v1.8.0 yazmayı durdurdu; bu betik ESKİ dokümanlardaki alanı siler.
//
// ⚠️ HESAP SİLİNMEZ. E-posta kimliği Firebase Auth'ta durmaya devam eder
// (giriş ve şifre sıfırlama oradan çalışır); silinen yalnızca Firestore'daki
// GEREKSİZ KOPYADIR. Uygulama bu alanı hiçbir yerde okumuyor (v1.8.0'da
// `Kullanici` modelinden de kaldırıldı) → veri kaybı riski yok.
//
// ÇALIŞTIRMA:
//   1) geçici klasör aç, bu dosyayı kopyala
//   2) assets/service_account.json dosyasını sa.json olarak kopyala
//   3) npm init -y && npm pkg set type=module && npm i firebase-admin
//   4) node eposta_temizle.mjs          → SADECE RAPOR (hiçbir şey değişmez)
//      node eposta_temizle.mjs --uygula → alanı gerçekten siler
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';

initializeApp({ credential: cert(JSON.parse(readFileSync('sa.json', 'utf8'))) });
const db = getFirestore();

// Varsayılan KURU ÇALIŞMA: yanlışlıkla veri değiştirmek, hiç çalıştırmamaktan
// daha kötüdür. Silmek için açıkça --uygula denmeli.
const uygula = process.argv.includes('--uygula');

// Eski `kullanicilar/` koleksiyonunda da e-posta kopyası olabilir (v1.8.0'da
// tokenKaydet oraya `eposta` yazıyordu). Koleksiyon artık kurallarla kilitli
// ama veri duruyor → o da temizlenir.
const koleksiyonlar = ['users', 'kullanicilar'];

let toplam = 0;
let temizlenen = 0;

for (const kol of koleksiyonlar) {
  const snap = await db.collection(kol).get();
  if (snap.empty) {
    console.log(`\n${kol}/ → doküman yok, atlandı.`);
    continue;
  }
  console.log(`\n${kol}/ → ${snap.size} doküman tarandı`);

  // Toplu yazma: tek tek yazmak yerine batch (kota ve hız).
  let batch = db.batch();
  let batchAdet = 0;

  for (const d of snap.docs) {
    toplam++;
    const veri = d.data();
    if (!('eposta' in veri)) continue;
    temizlenen++;
    // E-postanın TAMAMINI loglamak, gizlilik temizliği yaparken gizliliği
    // ihlal etmek olurdu → sadece maskeli hali yazılır.
    const e = String(veri.eposta || '');
    const maske = e ? `${e.slice(0, 2)}***${e.slice(e.indexOf('@'))}` : '(boş)';
    console.log(`   ${uygula ? 'SİLİNİYOR' : 'silinecek'}: ${kol}/${d.id}  ${maske}`);
    if (uygula) {
      batch.update(d.ref, { eposta: FieldValue.delete() });
      batchAdet++;
      if (batchAdet >= 400) {
        await batch.commit();
        batch = db.batch();
        batchAdet = 0;
      }
    }
  }
  if (uygula && batchAdet > 0) await batch.commit();
}

console.log(`\n==== ${toplam} doküman tarandı, ${temizlenen} tanesinde 'eposta' alanı var ====`);
console.log(
  uygula
    ? 'Alanlar SİLİNDİ.'
    : "KURU ÇALIŞMA — hiçbir şey değişmedi. Silmek için: node eposta_temizle.mjs --uygula",
);
process.exit(0);
