// Arama ekranının "karşı taraf düştü / geri geldi" kararı (saf mantık).

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/ekranlar/arama_ekrani.dart';

void main() {
  group('BaglantiTakibi', () {
    test('başlangıç: bekleniyor', () {
      expect(BaglantiTakibi().asama, AramaAsamasi.bekleniyor);
    });

    test('hiç bağlanmamışken null → olay yok (45 sn kuralı geçerli)', () {
      final t = BaglantiTakibi();
      expect(t.guncelle(null), BaglantiOlayi.yok);
      expect(t.guncelle(null), BaglantiOlayi.yok);
      expect(t.asama, AramaAsamasi.bekleniyor);
    });

    test('ilk katılım → ilkBaglanti, sonra aynı/farklı uid → yok', () {
      final t = BaglantiTakibi();
      expect(t.guncelle(42), BaglantiOlayi.ilkBaglanti);
      expect(t.asama, AramaAsamasi.bagli);
      expect(t.guncelle(42), BaglantiOlayi.yok);
      expect(t.guncelle(7), BaglantiOlayi.yok);
      expect(t.asama, AramaAsamasi.bagli);
    });

    test('bağlıyken düşme → koptu (yeniden bağlanma zamanlayıcısı)', () {
      final t = BaglantiTakibi()..guncelle(42);
      expect(t.guncelle(null), BaglantiOlayi.koptu);
      expect(t.asama, AramaAsamasi.yenidenBaglaniyor);
      // Tekrarlanan null zamanlayıcıyı YENİDEN kurdurmamalı.
      expect(t.guncelle(null), BaglantiOlayi.yok);
      expect(t.asama, AramaAsamasi.yenidenBaglaniyor);
    });

    test('kopukken geri gelme → geriGeldi, ilkBaglanti DEĞİL', () {
      final t = BaglantiTakibi()
        ..guncelle(42)
        ..guncelle(null);
      // Farklı uid ile dönebilir (Agora uid 0 ile katılımda yeni uid atar).
      expect(t.guncelle(99), BaglantiOlayi.geriGeldi);
      expect(t.asama, AramaAsamasi.bagli);
    });

    test('birden çok kopma/geri gelme döngüsü', () {
      final t = BaglantiTakibi()..guncelle(1);
      for (var i = 0; i < 3; i++) {
        expect(t.guncelle(null), BaglantiOlayi.koptu);
        expect(t.guncelle(1), BaglantiOlayi.geriGeldi);
      }
      expect(t.asama, AramaAsamasi.bagli);
    });
  });
}
