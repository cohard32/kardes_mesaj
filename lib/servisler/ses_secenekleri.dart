/// Bildirim sesi / arama zili seçeneklerinin TEK KAYNAĞI (saf → test).
///
/// ⚠️ NEDEN: Liste eskiden üç yerde ayrı ayrı yazılıydı (bildirim servisinin
/// kanal kurulumu, Ayarlar ekranındaki bildirim sesi ve arama zili satırları,
/// ayar servisindeki yorum). Yeni bir ses eklenince birinin unutulması =
/// ayarlarda seçilebilen ama KANALI KURULMAMIŞ ses (push varsayılana düşer)
/// ya da kanalı olup ekranda görünmeyen ses. Artık hepsi buradan üretilir.
///
/// Sıra = Ayarlar ekranındaki görünen sıra. Anahtarlar Android kanal
/// kimliğine (`km_v3_<anahtar>`) ve SharedPreferences'a girer → bir anahtarı
/// DEĞİŞTİRMEK eski kanalı/ayarı yetim bırakır (test/ses_secenekleri_test.dart
/// sabitler).
class SesSecenegi {
  /// Ayar değeri (`AyarServisi.bildirimSesi`) ve kanal kimliği soneki.
  final String anahtar;

  /// Ayarlar'da ve Android kanal ayarlarında görünen ad.
  final String ad;

  /// Ayarlar'daki ▶ önizlemesinin yolu (`AssetSource`'a verilir → `assets/`
  /// öneki YOK). null → önizleme düğmesi yok.
  final String? onizlemeAsset;

  /// `android/app/src/main/res/raw` kaynak adı (uzantısız). Bildirim kanalının
  /// sesi ve arama zili (CallKit `ringtonePath`) bu adla çözülür. null →
  /// sistem varsayılan sesi (ya da [sesCalar] false ise sessiz).
  final String? rawKaynak;

  /// false → kanal sessiz kurulur (playSound: false).
  final bool sesCalar;

  /// Android kanal açıklaması (sistem bildirim ayarlarında görünür).
  final String? aciklama;

  /// Ayarlar'da altında listelendiği başlık ("Melodik", "Doğa"…).
  final String kategori;

  const SesSecenegi({
    required this.anahtar,
    required this.ad,
    this.onizlemeAsset,
    this.rawKaynak,
    this.sesCalar = true,
    this.aciklama,
    this.kategori = 'Temel',
  });

  /// Arama zili olarak da sunulabilir mi? CallKit yalnız res/raw adını
  /// çözer (content:// URI desteklenmez) → raw kaynağı olanlar.
  bool get zilOlabilir => rawKaynak != null;
}

/// Telefondan seçilen özel sesin ayar değeri. Kanalı URI'ye göre sürümlü
/// kurulur (bkz. `BildirimKanali.ozelKanal`) → bu listede DEĞİL.
const String ozelSesAnahtari = 'ozel';

/// Uygulamayla gelen sesin seçeneği (önizleme = `assets/sesler/{ad}.{uzantı}`,
/// zil/kanal sesi = `res/raw/{ad}`). Yeni sesler tool/ses_sentez.py ile
/// ÜRETİLDİ (tamamen sentez → telif/lisans sorunu yok).
SesSecenegi _hazir(
  String anahtar,
  String ad,
  String kategori, {
  String uzanti = 'ogg',
}) =>
    SesSecenegi(
      anahtar: anahtar,
      ad: ad,
      onizlemeAsset: 'sesler/$anahtar.$uzanti',
      rawKaynak: anahtar,
      kategori: kategori,
    );

/// Hazır (uygulamayla gelen) BİLDİRİM sesleri — Ayarlar'daki sırayla,
/// kategorilere göre gruplu. ⚠️ Eski anahtarlar (kedi…, cingirak) KORUNDU:
/// seçmiş olanların ayarı ve kanalı çalışmaya devam eder.
final List<SesSecenegi> sesSecenekleri = List.unmodifiable([
  const SesSecenegi(
    anahtar: 'varsayilan',
    ad: 'Varsayılan',
    aciklama: 'Yeni mesaj bildirimleri',
  ),
  const SesSecenegi(anahtar: 'sessiz', ad: 'Sessiz', sesCalar: false),
  // Kısa ve sade
  _hazir('tik', 'Tık 👆', 'Kısa ve sade'),
  _hazir('pit', 'Pıt 🫧', 'Kısa ve sade'),
  _hazir('damla', 'Damla 💧', 'Kısa ve sade'),
  // Melodik
  _hazir('marimba', 'Marimba 🎵', 'Melodik'),
  _hazir('kalimba', 'Kalimba 🎶', 'Melodik'),
  _hazir('arp', 'Arp 🎼', 'Melodik'),
  _hazir('gitar', 'Gitar 🎸', 'Melodik'),
  // Zarif
  _hazir('kristal', 'Kristal ✨', 'Zarif'),
  _hazir('kampana', 'Kampana 🛎️', 'Zarif'),
  _hazir('yumusak', 'Yumuşak 🌙', 'Zarif'),
  // Eğlenceli
  _hazir('neon', 'Neon ⚡', 'Eğlenceli'),
  _hazir('kus', 'Kuş Cıvıltısı 🐦', 'Eğlenceli'),
  _hazir('dingdong', 'Ding Dong 🏠', 'Eğlenceli'),
  _hazir('cingirak', 'Çıngırak 🔔', 'Eğlenceli', uzanti: 'wav'),
  // Sevimli
  _hazir('kedi', 'Yavru Kedi 1 🐱', 'Sevimli', uzanti: 'mp3'),
  _hazir('kedi2', 'Yavru Kedi 2 😻', 'Sevimli', uzanti: 'mp3'),
  _hazir('kedi3', 'Yavru Kedi 3 🐈', 'Sevimli', uzanti: 'mp3'),
  _hazir('kedi4', 'Yavru Kedi 4 🐾', 'Sevimli', uzanti: 'mp3'),
]);

/// YALNIZ ZİL olarak sunulan uzun melodiler (4–6 sn, gelen aramada döngüyle
/// çalar). Bildirim kanalı KURULMAZ.
final List<SesSecenegi> zilMelodileri = List.unmodifiable([
  _hazir('zil_marimba', 'Marimba Neşesi 🎵', 'Zil melodileri'),
  _hazir('zil_kalimba', 'Kalimba Ninnisi 🎶', 'Zil melodileri'),
  _hazir('zil_kristal', 'Kristal Zil ✨', 'Zil melodileri'),
  _hazir('zil_sakin', 'Sakin Sabah 🌅', 'Zil melodileri'),
  _hazir('zil_klasik', 'Klasik Telefon ☎️', 'Zil melodileri'),
  _hazir('zil_retro', 'Retro Oyun 👾', 'Zil melodileri'),
  _hazir('zil_neon', 'Neon Nabız ⚡', 'Zil melodileri'),
]);

/// Arama zili olarak sunulan hazır sesler (Ayarlar > Arama Zil Sesi'nde
/// telefon/uygulama zilinden SONRA): önce zil melodileri, sonra bildirim
/// sesleri (kısa olanlar zil olarak döngüyle tekrarlanır).
final List<SesSecenegi> zilSecenekleri = List.unmodifiable([
  ...zilMelodileri,
  ...sesSecenekleri.where((s) => s.zilOlabilir),
]);

/// [anahtar]ın hazır ses seçeneği; bilinmeyen / 'ozel' → null.
SesSecenegi? sesSecenegiBul(String anahtar) {
  for (final s in sesSecenekleri) {
    if (s.anahtar == anahtar) return s;
  }
  return null;
}

/// Listeyi sırayı bozmadan kategorilere böler (Ayarlar'daki başlıklar).
List<({String kategori, List<SesSecenegi> sesler})> kategorilereAyir(
  Iterable<SesSecenegi> liste,
) {
  final sonuc = <({String kategori, List<SesSecenegi> sesler})>[];
  for (final s in liste) {
    if (sonuc.isEmpty || sonuc.last.kategori != s.kategori) {
      sonuc.add((kategori: s.kategori, sesler: [s]));
    } else {
      sonuc.last.sesler.add(s);
    }
  }
  return sonuc;
}
