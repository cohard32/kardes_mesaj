import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/servisler/arama_durumu.dart';

void main() {
  group('AramaDurumu', () {
    test('Firestore dizgileri eski sürümlerle AYNI (yeniden adlandırma yok)',
        () {
      // ⚠️ Bu liste değişirse eski sürümler yeni değerleri tanımaz.
      expect(AramaDurumu.values.map((d) => d.name).toList(),
          ['cagriliyor', 'kabul', 'red', 'bitti', 'mesgul']);
      expect(AramaDurumu.bitti.alan, {'durum': 'bitti'});
      expect(AramaDurumu.mesgul.alan, {'durum': 'mesgul'});
    });

    test('her değer kendi adından geri çözülür', () {
      for (final d in AramaDurumu.values) {
        expect(aramaDurumuCoz(d.name), d);
      }
    });

    test('bilinmeyen / eksik / yanlış türdeki değer → null', () {
      expect(aramaDurumuCoz(null), isNull);
      expect(aramaDurumuCoz(''), isNull);
      expect(aramaDurumuCoz('Bitti'), isNull); // büyük/küçük harf duyarlı
      expect(aramaDurumuCoz('iptal'), isNull); // gelecekteki yeni değer
      expect(aramaDurumuCoz(42), isNull);
      expect(aramaDurumuCoz(['red']), isNull);
    });

    test('aktif yalnız çalıyor/kabul', () {
      expect(
          AramaDurumu.values.where((d) => d.aktif).toList(),
          [AramaDurumu.cagriliyor, AramaDurumu.kabul]);
    });
  });
}
