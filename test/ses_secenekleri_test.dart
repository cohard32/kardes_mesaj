// Bildirim sesi / arama zili seçenekleri — tek kaynak testleri.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/bildirim_servisi.dart';
import 'package:kardes_mesaj/servisler/ses_secenekleri.dart';

void main() {
  group('sesSecenekleri (tek kaynak)', () {
    test('anahtarlar ve GÖRÜNEN SIRA eskisiyle aynı', () {
      expect(sesSecenekleri.map((s) => s.anahtar).toList(), [
        'varsayilan', 'sessiz', 'kedi', 'kedi2', 'kedi3', 'kedi4', 'cingirak',
      ]);
      expect(sesSecenekleri.map((s) => s.ad).toList(), [
        'Varsayılan',
        'Sessiz',
        'Yavru Kedi 1 🐱',
        'Yavru Kedi 2 😻',
        'Yavru Kedi 3 🐈',
        'Yavru Kedi 4 🐾',
        'Çıngırak 🔔',
      ]);
    });

    test('BildirimKanali.secimler = hazır sesler + ozel (eski liste)', () {
      expect(BildirimKanali.secimler, [
        'varsayilan', 'sessiz', 'kedi', 'kedi2', 'kedi3', 'kedi4', 'cingirak',
        'ozel',
      ]);
    });

    test('kanal kimlikleri DEĞİŞMEDİ (km_v3_<anahtar>[_tsz])', () {
      const beklenen = [
        'km_v3_varsayilan', 'km_v3_sessiz', 'km_v3_kedi', 'km_v3_kedi2',
        'km_v3_kedi3', 'km_v3_kedi4', 'km_v3_cingirak',
      ];
      expect(
        sesSecenekleri.map((s) => BildirimKanali.sesKanali(s.anahtar)).toList(),
        beklenen,
      );
      expect(
        sesSecenekleri
            .map((s) => BildirimKanali.aktif(
                secim: s.anahtar, bildirimAcik: true, titresim: false))
            .toList(),
        [for (final id in beklenen) '${id}_tsz'],
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

    test('önizleme asset\'i ve res/raw kaynağı diskte VAR', () {
      final raw = Directory('android/app/src/main/res/raw')
          .listSync()
          .map((f) => f.uri.pathSegments.last.split('.').first)
          .toSet();
      for (final s in sesSecenekleri) {
        if (s.onizlemeAsset != null) {
          expect(File('assets/${s.onizlemeAsset}').existsSync(), isTrue,
              reason: s.onizlemeAsset);
        }
        if (s.rawKaynak != null) {
          expect(raw, contains(s.rawKaynak), reason: s.anahtar);
        }
      }
    });

    test('zil seçenekleri: raw kaynaklı sesler, aynı sırayla', () {
      expect(zilSecenekleri.map((s) => s.rawKaynak).toList(),
          ['kedi', 'kedi2', 'kedi3', 'kedi4', 'cingirak']);
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
