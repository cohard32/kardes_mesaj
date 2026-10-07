/// Görüşme bağlantı kalitesi (saf — Agora'ya bağımlı değil; bkz.
/// test/baglanti_kalitesi_test.dart). Agora `onNetworkQuality` ~2 sn'de bir
/// hem kendi (uid 0) hem karşı tarafın yükleme/indirme kalitesini bildirir:
///   0 bilinmiyor · 1 mükemmel · 2 iyi · 3 zayıfça · 4 kötü · 5 çok kötü ·
///   6 kopuk · 7 desteklenmiyor · 8 ölçülüyor
library;

enum BaglantiKalitesi { bilinmiyor, iyi, orta, zayif, kopuk }

/// Agora değeri → gösterilecek kalite.
BaglantiKalitesi kaliteCoz(int agoraDegeri) => switch (agoraDegeri) {
      1 || 2 => BaglantiKalitesi.iyi,
      3 => BaglantiKalitesi.orta,
      4 || 5 => BaglantiKalitesi.zayif,
      6 => BaglantiKalitesi.kopuk,
      _ => BaglantiKalitesi.bilinmiyor,
    };

/// İki ölçümün (yerel ve karşı taraf) KÖTÜSÜ; bilinmeyen (0, 7, 8) yok sayılır.
int kaliteBirlestir(int a, int b) {
  bool gecerli(int x) => x >= 1 && x <= 6;
  if (!gecerli(a)) return gecerli(b) ? b : 0;
  if (!gecerli(b)) return a;
  return a > b ? a : b;
}

/// Sinyal çubuğu sayısı (0–4).
int kaliteCubuk(BaglantiKalitesi k) => switch (k) {
      BaglantiKalitesi.iyi => 4,
      BaglantiKalitesi.orta => 2,
      BaglantiKalitesi.zayif => 1,
      BaglantiKalitesi.kopuk => 0,
      BaglantiKalitesi.bilinmiyor => 4,
    };

/// Ekranda gösterilecek uyarı (iyi/bilinmiyorsa null).
String? kaliteUyarisi(BaglantiKalitesi k) => switch (k) {
      BaglantiKalitesi.orta => 'Bağlantı biraz zayıf',
      BaglantiKalitesi.zayif => 'Bağlantı zayıf — ses/görüntü takılabilir',
      BaglantiKalitesi.kopuk => 'Bağlantı yok — yeniden deneniyor…',
      _ => null,
    };
