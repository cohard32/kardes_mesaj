// Bildirim sesi / arama zili seçenekleri — tek kaynak testleri.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/bildirim_servisi.dart';
import 'package:kardes_mesaj/servisler/ses_secenekleri.dart';

void main() {
  const yeniSira = [
    'varsayilan', 'sessiz',
    'tik', 'pit', 'damla',
    'marimba', 'kalimba', 'arp', 'gitar',
    'kristal', 'kampana', 'yumusak',
    'neon', 'kus', 'dingdong', 'cingirak',
    'kedi', 'kedi2', 'kedi3', 'kedi4',
  ];

  group('sesSecenekleri (tek kaynak)', () {
    test('anahtarlar ve görünen sıra (kategorilere göre)', () {
      expect(sesSecenekleri.map((s) => s.anahtar).toList(), yeniSira);
    });

    test('ESKİ anahtarlar ve adları KORUNDU (seçmiş olanların ayarı geçerli)', () {
      for (final (anahtar, ad) in [
        ('varsayilan', 'Varsayılan'),
        ('sessiz', 'Sessiz'),
        ('kedi', 'Yavru Kedi 1 🐱'),
        ('kedi2', 'Yavru Kedi 2 😻'),
        ('kedi3', 'Yavru Kedi 3 🐈'),
        ('kedi4', 'Yavru Kedi 4 🐾'),
        ('cingirak', 'Çıngırak 🔔'),
      ]) {
        expect(sesSecenegiBul(anahtar)?.ad, ad, reason: anahtar);
      }
    });

    test('BildirimKanali.secimler = hazır sesler + ozel', () {
      expect(BildirimKanali.secimler, [...yeniSira, 'ozel']);
    });

    test('kanal kimlikleri km_v3_<anahtar>[_tsz] (eskiler DEĞİŞMEDİ)', () {
      expect(
        sesSecenekleri.map((s) => BildirimKanali.sesKanali(s.anahtar)).toList(),
        [for (final a in yeniSira) 'km_v3_$a'],
      );
      expect(BildirimKanali.sesKanali('kedi3'), 'km_v3_kedi3');
      expect(
        sesSecenekleri
            .map((s) => BildirimKanali.aktif(
                secim: s.anahtar, bildirimAcik: true, titresim: false))
            .toList(),
        [for (final a in yeniSira) 'km_v3_${a}_tsz'],
      );
      // Sessize alınmış sohbet kanalı hâlâ 'sessiz' seçeneğinin _tsz çifti.
      expect(BildirimKanali.sessizSohbet,
          '${BildirimKanali.sesKanali('sessiz')}${BildirimKanali.tszEki}');
    });

    test('yalnız varsayilan ve sessiz raw/önizlemesiz; sessiz ses çalmaz', () {
      for (final s in sesSecenekleri) {
        final hazirSes = s.anahtar != 'varsayilan' && s.anahtar != 'sessiz';
        expect(s.rawKaynak != null, hazirSes, reason: s.anahtar);
        expect(s.onizlemeAsset != null, hazirSes, reason: s.anahtar);
        expect(s.sesCalar, s.anahtar != 'sessiz', reason: s.anahtar);
      }
    });

    test('önizleme asset\'i ve res/raw kaynağı diskte VAR, keep.xml korur', () {
      final raw = Directory('android/app/src/main/res/raw')
          .listSync()
          .map((f) => f.uri.pathSegments.last.split('.').first)
          .toSet();
      final keep =
          File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      for (final s in [...sesSecenekleri, ...zilMelodileri]) {
        if (s.onizlemeAsset != null) {
          expect(File('assets/${s.onizlemeAsset}').existsSync(), isTrue,
              reason: s.onizlemeAsset);
        }
        if (s.rawKaynak != null) {
          expect(raw, contains(s.rawKaynak), reason: s.anahtar);
          expect(keep, contains('@raw/${s.rawKaynak}'), reason: s.anahtar);
        }
      }
    });

    test('zil: önce 7 zil melodisi, sonra raw kaynaklı bildirim sesleri', () {
      expect(zilMelodileri.length, 7);
      expect(zilSecenekleri.take(7).map((s) => s.rawKaynak),
          zilMelodileri.map((s) => s.rawKaynak));
      expect(zilSecenekleri.skip(7).map((s) => s.rawKaynak).toList(),
          [for (final a in yeniSira.skip(2)) a]);
      // Zil melodileri bildirim kanalı KURMAZ (secimler'de yok).
      for (final z in zilMelodileri) {
        expect(BildirimKanali.secimler, isNot(contains(z.anahtar)));
      }
    });

    test('kategoriler sırayı bozmadan gruplanır', () {
      final g = kategorilereAyir(sesSecenekleri);
      expect(g.map((e) => e.kategori).toList(), [
        'Temel', 'Kısa ve sade', 'Melodik', 'Zarif', 'Eğlenceli', 'Sevimli',
      ]);
      expect(g.expand((e) => e.sesler).map((s) => s.anahtar).toList(),
          yeniSira);
    });

    test('anahtarlar benzersiz; bul() bilinmeyen ve ozel için null', () {
      final anahtarlar = sesSecenekleri.map((s) => s.anahtar).toList();
      expect(anahtarlar.toSet().length, anahtarlar.length);
      expect(anahtarlar, isNot(contains(ozelSesAnahtari)));
      expect(sesSecenegiBul('kedi3')?.ad, 'Yavru Kedi 3 🐈');
      expect(sesSecenegiBul(ozelSesAnahtari), isNull);
      expect(sesSecenegiBul('bozuk'), isNull);
    });
  });
}
