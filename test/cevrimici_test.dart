// Hesaplanan çevrimiçilik (Kullanici.cevrimici) — Firebase gerektirmez.
//
// ⚠️ Neden var: uygulama öldürülünce ham `cevrimici` true kalıyordu; artık
// sonGorulme eşiği (150 sn) aşılınca çevrimdışı sayılmalı.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/modeller/kullanici.dart';
import 'package:kardes_mesaj/servisler/presence_servisi.dart';

void main() {
  final simdi = DateTime(2026, 10, 6, 12, 0, 0);

  Kullanici k({bool ham = true, DateTime? son}) => Kullanici(
        uid: 'u',
        ad: 'Ayşe',
        kullaniciAdi: 'ayse',
        cevrimici: ham,
        sonGorulme: son,
      );

  tearDown(() => Kullanici.saatDuzeltmesi = Duration.zero);

  group('Kullanici.cevrimiciMi', () {
    test('eşik 150 sn ve nabızdan (60 sn) büyük', () {
      expect(Kullanici.cevrimiciEsigi, const Duration(seconds: 150));
      expect(
        Kullanici.cevrimiciEsigi > PresenceServisi.nabizAraligi * 2,
        isTrue,
      );
    });

    test('eşik içinde → çevrimiçi', () {
      final s = simdi.subtract(const Duration(seconds: 30));
      expect(k(son: s).cevrimiciMi(simdi), isTrue);
    });

    test('tam eşikte → hâlâ çevrimiçi', () {
      final s = simdi.subtract(Kullanici.cevrimiciEsigi);
      expect(k(son: s).cevrimiciMi(simdi), isTrue);
    });

    test('eşik dışında (öldürülmüş uygulama) → çevrimdışı', () {
      final s = simdi.subtract(const Duration(seconds: 151));
      expect(k(son: s).cevrimiciMi(simdi), isFalse);
      final cokEski = simdi.subtract(const Duration(days: 3));
      expect(k(son: cokEski).cevrimiciMi(simdi), isFalse);
    });

    test('ham true + sonGorulme null (çözülmemiş sunucu damgası) → çevrimiçi',
        () {
      expect(k(son: null).cevrimiciMi(simdi), isTrue);
    });

    test('ham false → her zaman çevrimdışı', () {
      expect(k(ham: false, son: simdi).cevrimiciMi(simdi), isFalse);
      expect(k(ham: false, son: null).cevrimiciMi(simdi), isFalse);
    });

    test('gelecekte görünen damga (saat kayması) → çevrimiçi', () {
      final gelecek = simdi.add(const Duration(minutes: 10));
      expect(k(son: gelecek).cevrimiciMi(simdi), isTrue);
    });

    test('getter o anki saati kullanır (build anında değerlendirilir)', () {
      expect(k(son: DateTime.now()).cevrimici, isTrue);
      final eski = DateTime.now().subtract(const Duration(minutes: 5));
      expect(k(son: eski).cevrimici, isFalse);
    });

    test('saat düzeltmesi getter\'a uygulanır (telefon saati ileri)', () {
      // Damga = yerel "şimdi". Düzeltme −5 dk (telefon 5 dk ileri): etkin
      // şimdi 5 dk geriye çekilir → damga gelecekte → çevrimiçi.
      final damga = DateTime.now();
      Kullanici.saatDuzeltmesi = const Duration(minutes: -5);
      expect(k(son: damga).cevrimici, isTrue);
      // Düzeltme +5 dk (telefon 5 dk geride): damga aslında 5 dk eski.
      Kullanici.saatDuzeltmesi = const Duration(minutes: 5);
      expect(k(son: damga).cevrimici, isFalse);
    });
  });

  group('Kullanici kurucu uyumluluğu', () {
    test('varsayılan ham false; bos çevrimdışı', () {
      expect(Kullanici.bos('x').cevrimici, isFalse);
      expect(Kullanici.bos('x').cevrimiciHam, isFalse);
    });

    test('copyWith ham değeri ve sonGorulme\'yi korur', () {
      final s = simdi.subtract(const Duration(seconds: 10));
      final c = k(son: s).copyWith(ad: 'Neşe');
      expect(c.cevrimiciHam, isTrue);
      expect(c.sonGorulme, s);
      expect(c.cevrimiciMi(simdi), isTrue);
    });
  });

  group('cevrimdisiOlmayaKalan', () {
    test('kalan süre = eşik − geçen', () {
      final s = simdi.subtract(const Duration(seconds: 100));
      expect(k(son: s).cevrimdisiOlmayaKalan(simdi),
          const Duration(seconds: 50));
    });

    test('çevrimdışı / null damga / ham false → null', () {
      final eski = simdi.subtract(const Duration(seconds: 200));
      expect(k(son: eski).cevrimdisiOlmayaKalan(simdi), isNull);
      expect(k(son: null).cevrimdisiOlmayaKalan(simdi), isNull);
      expect(k(ham: false, son: simdi).cevrimdisiOlmayaKalan(simdi), isNull);
    });
  });

  group('cevrimiciTazele', () {
    test('eşik dolunca aynı kullanıcıyı yeniden yayar (ekran yenilensin)',
        () async {
      final kaynak = StreamController<Kullanici>();
      final gelenler = <bool>[];
      final abone = cevrimiciTazele(kaynak.stream)
          .listen((u) => gelenler.add(u.cevrimici));

      // Eşiğin dolmasına ~0,3 sn kalmış (tazeleme +1 sn payla tetiklenir).
      final son = DateTime.now()
          .subtract(Kullanici.cevrimiciEsigi)
          .add(const Duration(milliseconds: 300));
      kaynak.add(k(son: son));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gelenler, [true]);

      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(gelenler, [true, false]);

      await abone.cancel();
      await kaynak.close();
    });

    test('çevrimdışı kullanıcı için zamanlayıcı kurulmaz', () async {
      final kaynak = StreamController<Kullanici>();
      final gelenler = <Kullanici>[];
      final abone = cevrimiciTazele(kaynak.stream).listen(gelenler.add);
      kaynak.add(k(ham: false, son: DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gelenler, hasLength(1));
      await abone.cancel();
      await kaynak.close();
    });
  });
}
