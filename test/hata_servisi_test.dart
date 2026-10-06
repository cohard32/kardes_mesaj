// HataServisi tekrar süzgeci (saf karar fonksiyonu; Firebase gerektirmez).

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/hata_servisi.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  group('hataAnahtari', () {
    test('etiket + yalnız ilk satır', () {
      expect(hataAnahtari('Taşma\nayrıntı 1', 'flutter'), 'flutter|Taşma');
      // Alt satırlar değişse de anahtar aynı kalır.
      expect(hataAnahtari('Taşma\nayrıntı 2', 'flutter'), 'flutter|Taşma');
      // Farklı etiket → farklı anahtar.
      expect(hataAnahtari('Taşma', 'platform'), isNot('flutter|Taşma'));
    });
  });

  group('hataRaporlanmali', () {
    test('ilk kez → raporla; 10 dk içinde aynı → raporlama', () {
      final h = <String, DateTime>{};
      expect(hataRaporlanmali(h, 'a', t0), isTrue);
      expect(hataRaporlanmali(h, 'a', t0.add(const Duration(seconds: 1))),
          isFalse);
      expect(hataRaporlanmali(h, 'a', t0.add(const Duration(minutes: 9))),
          isFalse);
    });

    test('susturulan tekrar pencereyi UZATMAZ (zaman ilk rapordan sayılır)',
        () {
      final h = <String, DateTime>{};
      hataRaporlanmali(h, 'a', t0);
      hataRaporlanmali(h, 'a', t0.add(const Duration(minutes: 9)));
      expect(hataRaporlanmali(h, 'a', t0.add(const Duration(minutes: 10))),
          isTrue);
    });

    test('farklı anahtar bağımsızdır', () {
      final h = <String, DateTime>{};
      expect(hataRaporlanmali(h, 'a', t0), isTrue);
      expect(hataRaporlanmali(h, 'b', t0), isTrue);
    });

    test('saat geri alınırsa susturma kalıcı olmaz', () {
      final h = <String, DateTime>{};
      hataRaporlanmali(h, 'a', t0);
      expect(hataRaporlanmali(h, 'a', t0.subtract(const Duration(hours: 1))),
          isTrue);
    });

    test('harita sınırı aşılınca süresi dolanlar atılır', () {
      final h = <String, DateTime>{};
      for (var i = 0; i < 5; i++) {
        hataRaporlanmali(h, 'eski$i', t0, enFazlaAnahtar: 5);
      }
      final sonra = t0.add(const Duration(minutes: 11));
      expect(hataRaporlanmali(h, 'yeni', sonra, enFazlaAnahtar: 5), isTrue);
      expect(h.keys, ['yeni']);
    });
  });
}
