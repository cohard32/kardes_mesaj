// Bildirim kanal kimliği seçimi — saf mantık testleri (Firebase gerektirmez).

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/bildirim_servisi.dart';

void main() {
  group('BildirimKanali.aktif', () {
    // 'ozel' URI'ye göre sürümlüdür → ayrı grupta.
    final sabitler = BildirimKanali.secimler.where((s) => s != 'ozel');

    test('bildirim açık + titreşim açık → km_v3_<secim>', () {
      for (final s in sabitler) {
        expect(
          BildirimKanali.aktif(secim: s, bildirimAcik: true, titresim: true),
          'km_v3_$s',
        );
      }
    });

    test('titreşim kapalı → _tsz varyantı', () {
      for (final s in sabitler) {
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

  group('Özel ses kanalı (URI\'ye göre sürümlü, d4)', () {
    const uriA = 'content://media/internal/audio/media/42';
    const uriB = 'content://media/external/audio/media/7?title=Zil';

    test('FNV-1a 32: bilinen test vektörleri', () {
      expect(BildirimKanali.fnv1a32Hex(''), '811c9dc5');
      expect(BildirimKanali.fnv1a32Hex('a'), 'e40c292c');
      expect(BildirimKanali.fnv1a32Hex('foobar'), 'bf9cf968');
    });

    test('FNV-1a: UTF-8 baytları üzerinde (Türkçe karakter) ve 8 hane', () {
      final h = BildirimKanali.fnv1a32Hex('çığ şölen');
      expect(h, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(h, isNot(BildirimKanali.fnv1a32Hex('cig solen')));
    });

    test('kimlik kararlı: aynı URI → aynı kimlik, farklı URI → farklı', () {
      expect(BildirimKanali.ozelKanal(uriA), BildirimKanali.ozelKanal(uriA));
      expect(BildirimKanali.ozelKanal(uriA),
          isNot(BildirimKanali.ozelKanal(uriB)));
      expect(BildirimKanali.ozelKanal(uriA),
          matches(RegExp(r'^km_v3_ozel_[0-9a-f]{8}$')));
    });

    test('aktif: ozel + URI → km_v3_ozel_<hash>[_tsz]', () {
      final id = BildirimKanali.ozelKanal(uriA);
      expect(
        BildirimKanali.aktif(
            secim: 'ozel', bildirimAcik: true, titresim: true, ozelUri: uriA),
        id,
      );
      expect(
        BildirimKanali.aktif(
            secim: 'ozel', bildirimAcik: true, titresim: false, ozelUri: uriA),
        '${id}_tsz',
      );
    });

    test('aktif: ozel ama URI yok/boş → varsayılan (var olmayan kanal yok)', () {
      for (final uri in [null, '']) {
        expect(
          BildirimKanali.aktif(
              secim: 'ozel', bildirimAcik: true, titresim: true, ozelUri: uri),
          'km_v3_varsayilan',
        );
        expect(
          BildirimKanali.aktif(
              secim: 'ozel', bildirimAcik: true, titresim: false, ozelUri: uri),
          'km_v3_varsayilan_tsz',
        );
      }
    });

    test('yeni kimlik istemci (gecerli) ve aktarıcı desenince kabul edilir', () {
      // sunucu/aktarici/src/aktarici.js YAYIN_KANAL_DESENI ile AYNI.
      final aktariciDeseni = RegExp(r'^km_v3_[a-z0-9_]{1,40}$');
      for (final uri in [uriA, uriB, 'x' * 2000]) {
        for (final id in [
          BildirimKanali.ozelKanal(uri),
          '${BildirimKanali.ozelKanal(uri)}_tsz',
        ]) {
          expect(BildirimKanali.gecerli(id), id);
          expect(aktariciDeseni.hasMatch(id), isTrue, reason: id);
        }
      }
      // Diğer tüm kimlikler de desene uyar.
      for (final s in BildirimKanali.secimler) {
        for (final t in [true, false]) {
          final id = BildirimKanali.aktif(
              secim: s, bildirimAcik: true, titresim: t, ozelUri: uriA);
          expect(aktariciDeseni.hasMatch(id), isTrue, reason: id);
        }
      }
      expect(aktariciDeseni.hasMatch(BildirimKanali.kapali), isTrue);
      expect(aktariciDeseni.hasMatch(BildirimKanali.sessizSohbet), isTrue);
    });

    test('eskiOzelKanallar: doğru çift ASLA silinmez; eski URI + sürümsüz silinir', () {
      final yeni = BildirimKanali.ozelKanal(uriB);
      final eski = BildirimKanali.ozelKanal(uriA);
      final mevcut = [
        'km_v3_varsayilan', 'km_v3_kedi_tsz', 'km_v3_sessiz_tsz',
        'km_v3_ozel', 'km_v3_ozel_tsz', // sürümsüz eski kimlikler
        eski, '${eski}_tsz',
        yeni, '${yeni}_tsz',
      ];
      expect(
        BildirimKanali.eskiOzelKanallar(mevcut, ozelUri: uriB),
        unorderedEquals(
            ['km_v3_ozel', 'km_v3_ozel_tsz', eski, '${eski}_tsz']),
      );
    });

    test('eskiOzelKanallar: URI değişmediyse açılışta HİÇBİR şey silinmez', () {
      final id = BildirimKanali.ozelKanal(uriA);
      expect(
        BildirimKanali.eskiOzelKanallar(
            ['km_v3_varsayilan', id, '${id}_tsz'], ozelUri: uriA),
        isEmpty,
      );
    });

    test('eskiOzelKanallar: URI kaldırıldıysa tüm özel kanallar eskidir', () {
      final id = BildirimKanali.ozelKanal(uriA);
      expect(
        BildirimKanali.eskiOzelKanallar(
            ['km_v3_kedi', id, '${id}_tsz'], ozelUri: null),
        unorderedEquals([id, '${id}_tsz']),
      );
    });
  });

  group('gelenAramaMesgulMu (ön plan + arka plan TEK kural)', () {
    test('görüşme yoksa meşgul değil', () {
      expect(gelenAramaMesgulMu(aktifChat: null, gelenChat: 'a_b'), isFalse);
    });
    test('AYNI sohbetten yeniden arama meşgul değil', () {
      expect(gelenAramaMesgulMu(aktifChat: 'a_b', gelenChat: 'a_b'), isFalse);
    });
    test('başka sohbetle görüşme varken meşgul', () {
      expect(gelenAramaMesgulMu(aktifChat: 'a_b', gelenChat: 'c_d'), isTrue);
    });
    test('görüşme var ama sohbeti bilinmiyor (\'\') → güvenli taraf: meşgul', () {
      expect(gelenAramaMesgulMu(aktifChat: '', gelenChat: 'a_b'), isTrue);
      expect(gelenAramaMesgulMu(aktifChat: '', gelenChat: null), isTrue);
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

  test('sohbet bildirim kimliği: kararlı, 31 bit pozitif, sohbete özgü', () {
    final a = BildirimServisi.sohbetBildirimKimligi('uidA_uidB');
    // Aynı sohbetin yeni mesajı eskisinin YERİNE geçer (aynı kimlik)…
    expect(a, BildirimServisi.sohbetBildirimKimligi('uidA_uidB'));
    // …başka sohbetinki ayrı durur.
    expect(a, isNot(BildirimServisi.sohbetBildirimKimligi('uidA_uidC')));
    expect(a, inInclusiveRange(0, 0x7fffffff));
    expect(BildirimServisi.sohbetBildirimKimligi(''), inInclusiveRange(0, 0x7fffffff));
  });
}
