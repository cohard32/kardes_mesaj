// Bildirim kanal kimliği seçimi — saf mantık testleri (Firebase gerektirmez).

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/bildirim_servisi.dart';

void main() {
  group('BildirimKanali.aktif', () {
    test('bildirim açık + titreşim açık → km_v3_<secim>', () {
      for (final s in BildirimKanali.secimler) {
        expect(
          BildirimKanali.aktif(secim: s, bildirimAcik: true, titresim: true),
          'km_v3_$s',
        );
      }
    });

    test('titreşim kapalı → _tsz varyantı (ozel dahil)', () {
      for (final s in BildirimKanali.secimler) {
        expect(
          BildirimKanali.aktif(secim: s, bildirimAcik: true, titresim: false),
          'km_v3_${s}_tsz',
        );
      }
    });

    test('bildirim kapalı → km_v3_kapali (titreşimden bağımsız)', () {
      for (final t in [true, false]) {
        expect(
          BildirimKanali.aktif(
              secim: 'kedi', bildirimAcik: false, titresim: t),
          'km_v3_kapali',
        );
      }
    });

    test('bilinmeyen seçim varsayılana düşer', () {
      expect(
        BildirimKanali.aktif(
            secim: 'bozuk', bildirimAcik: true, titresim: true),
        'km_v3_varsayilan',
      );
      expect(
        BildirimKanali.aktif(
            secim: '', bildirimAcik: true, titresim: false),
        'km_v3_varsayilan_tsz',
      );
    });
  });

  group('BildirimKanali.gecerli', () {
    test('güncel sürüm kimlikleri (tsz/kapali dahil) aynen kabul edilir', () {
      for (final k in [
        'km_v3_varsayilan',
        'km_v3_kedi2_tsz',
        'km_v3_ozel_tsz',
        'km_v3_kapali',
        'km_v3_sessiz_tsz',
      ]) {
        expect(BildirimKanali.gecerli(k), k);
      }
    });

    test('eski sürüm / boş / null → varsayılan', () {
      for (final k in [null, '', 'km_v2_kedi', 'kardes_mesaj_kanal']) {
        expect(BildirimKanali.gecerli(k), 'km_v3_varsayilan');
      }
    });
  });

  group('BildirimKanali.alicininKanali (sohbet sessize alma)', () {
    test('sohbet sessizSohbetler listesindeyse → km_v3_sessiz_tsz', () {
      expect(
        BildirimKanali.alicininKanali(
          yayinlanan: 'km_v3_kedi',
          sessizSohbetler: ['a_b', 'c_d'],
          chatId: 'c_d',
        ),
        'km_v3_sessiz_tsz',
      );
    });

    test('listede değilse yayınlanan kanal kalır', () {
      expect(
        BildirimKanali.alicininKanali(
          yayinlanan: 'km_v3_kedi_tsz',
          sessizSohbetler: ['a_b'],
          chatId: 'c_d',
        ),
        'km_v3_kedi_tsz',
      );
    });

    test('bildirimler KAPALIYSA sessize alma onu açmaz → kapali kalır', () {
      expect(
        BildirimKanali.alicininKanali(
          yayinlanan: 'km_v3_kapali',
          sessizSohbetler: ['c_d'],
          chatId: 'c_d',
        ),
        'km_v3_kapali',
      );
    });

    test('alan yok / bozuk tip / chatId yok → yayınlanan (doğrulanmış)', () {
      expect(
        BildirimKanali.alicininKanali(
            yayinlanan: 'km_v3_cingirak', chatId: 'c_d'),
        'km_v3_cingirak',
      );
      expect(
        BildirimKanali.alicininKanali(
          yayinlanan: 'km_v3_cingirak',
          sessizSohbetler: 'c_d', // liste değil (bozuk veri)
          chatId: 'c_d',
        ),
        'km_v3_cingirak',
      );
      expect(
        BildirimKanali.alicininKanali(
          yayinlanan: 'km_v2_kedi',
          sessizSohbetler: ['c_d'],
        ),
        'km_v3_varsayilan',
      );
    });
  });
}
