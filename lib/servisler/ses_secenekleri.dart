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

  const SesSecenegi({
    required this.anahtar,
    required this.ad,
    this.onizlemeAsset,
    this.rawKaynak,
    this.sesCalar = true,
    this.aciklama,
  });

  /// Arama zili olarak da sunulabilir mi? CallKit yalnız res/raw adını
  /// çözer (content:// URI desteklenmez) → raw kaynağı olanlar.
  bool get zilOlabilir => rawKaynak != null;
}

/// Telefondan seçilen özel sesin ayar değeri. Kanalı URI'ye göre sürümlü
/// kurulur (bkz. `BildirimKanali.ozelKanal`) → bu listede DEĞİL.
const String ozelSesAnahtari = 'ozel';

/// Hazır (uygulamayla gelen) bildirim sesleri — Ayarlar'daki sırayla.
const List<SesSecenegi> sesSecenekleri = [
  SesSecenegi(
    anahtar: 'varsayilan',
    ad: 'Varsayılan',
    aciklama: 'Yeni mesaj bildirimleri',
  ),
  SesSecenegi(anahtar: 'sessiz', ad: 'Sessiz', sesCalar: false),
  SesSecenegi(
    anahtar: 'kedi',
    ad: 'Yavru Kedi 1 🐱',
    onizlemeAsset: 'sesler/kedi.mp3',
    rawKaynak: 'kedi',
  ),
  SesSecenegi(
    anahtar: 'kedi2',
    ad: 'Yavru Kedi 2 😻',
    onizlemeAsset: 'sesler/kedi2.mp3',
    rawKaynak: 'kedi2',
  ),
  SesSecenegi(
    anahtar: 'kedi3',
    ad: 'Yavru Kedi 3 🐈',
    onizlemeAsset: 'sesler/kedi3.mp3',
    rawKaynak: 'kedi3',
  ),
  SesSecenegi(
    anahtar: 'kedi4',
    ad: 'Yavru Kedi 4 🐾',
    onizlemeAsset: 'sesler/kedi4.mp3',
    rawKaynak: 'kedi4',
  ),
  SesSecenegi(
    anahtar: 'cingirak',
    ad: 'Çıngırak 🔔',
    onizlemeAsset: 'sesler/cingirak.wav',
    rawKaynak: 'cingirak',
  ),
];

/// Arama zili olarak da sunulan hazır sesler (Ayarlar > Arama Zil Sesi'nde
/// telefon/uygulama zilinden SONRA, aynı sırayla).
final List<SesSecenegi> zilSecenekleri =
    List.unmodifiable(sesSecenekleri.where((s) => s.zilOlabilir));

/// [anahtar]ın hazır ses seçeneği; bilinmeyen / 'ozel' → null.
SesSecenegi? sesSecenegiBul(String anahtar) {
  for (final s in sesSecenekleri) {
    if (s.anahtar == anahtar) return s;
  }
  return null;
}
