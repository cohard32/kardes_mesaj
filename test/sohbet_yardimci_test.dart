// Sohbet ekranının Firebase gerektirmeyen saf mantık testleri:
// son görülme metni, yanıt önizlemesi, video kapak URL'i, ses hızı.

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/modeller/mesaj.dart';
import 'package:kardes_mesaj/servisler/ses_oynatici_servisi.dart';
import 'package:kardes_mesaj/yardimcilar/mesaj_metni.dart';
import 'package:kardes_mesaj/yardimcilar/zaman_metni.dart';

void main() {
  group('sonGorulmeMetni', () {
    final simdi = DateTime(2026, 10, 6, 18, 30);

    test('bugün → yalnız saat', () {
      expect(
        sonGorulmeMetni(DateTime(2026, 10, 6, 14, 5), simdi: simdi),
        'son görülme 14:05',
      );
      expect(
        sonGorulmeMetni(DateTime(2026, 10, 6, 0, 0), simdi: simdi),
        'son görülme 00:00',
      );
    });

    test('dün → "dün" + saat (gece yarısı sınırı)', () {
      expect(
        sonGorulmeMetni(DateTime(2026, 10, 5, 23, 59), simdi: simdi),
        'son görülme dün 23:59',
      );
      // Az önce gece yarısı geçti: 10 dk önce görülen biri "dün"dür.
      expect(
        sonGorulmeMetni(
          DateTime(2026, 10, 5, 23, 55),
          simdi: DateTime(2026, 10, 6, 0, 5),
        ),
        'son görülme dün 23:55',
      );
    });

    test('daha eski → gün + Türkçe kısa ay (saat YOK)', () {
      expect(
        sonGorulmeMetni(DateTime(2026, 10, 3, 9, 0), simdi: simdi),
        'son görülme 3 Eki',
      );
      expect(
        sonGorulmeMetni(DateTime(2026, 2, 14, 9, 0), simdi: simdi),
        'son görülme 14 Şub',
      );
      expect(
        sonGorulmeMetni(DateTime(2026, 8, 30, 9, 0), simdi: simdi),
        'son görülme 30 Ağu',
      );
    });

    test('ay / yıl sınırları', () {
      // 1 Kasım'dan bakınca 31 Ekim = dün
      expect(
        sonGorulmeMetni(
          DateTime(2026, 10, 31, 8, 7),
          simdi: DateTime(2026, 11, 1, 10, 0),
        ),
        'son görülme dün 08:07',
      );
      // 1 Ocak'tan bakınca 31 Aralık = dün; 30 Aralık = geçen yıl tarihi
      expect(
        sonGorulmeMetni(
          DateTime(2025, 12, 31, 22, 0),
          simdi: DateTime(2026, 1, 1, 9, 0),
        ),
        'son görülme dün 22:00',
      );
      expect(
        sonGorulmeMetni(
          DateTime(2025, 12, 30, 22, 0),
          simdi: DateTime(2026, 1, 1, 9, 0),
        ),
        'son görülme 30 Ara 2025',
      );
    });

    test('gelecekteki zaman (saat kayması) bugün sayılır', () {
      expect(
        sonGorulmeMetni(DateTime(2026, 10, 7, 1, 0), simdi: simdi),
        'son görülme 01:00',
      );
    });

    test('saatMetni sıfır doldurur', () {
      expect(saatMetni(DateTime(2026, 1, 1, 7, 3)), '07:03');
    });
  });

  group('tekSatiraKisalt (yanıt önizlemesi)', () {
    test('kısa metin aynen (boşluklar sadeleşir)', () {
      expect(tekSatiraKisalt('  merhaba\n\ndünya  '), 'merhaba dünya');
      expect(tekSatiraKisalt(''), '');
    });

    test('uzun metin ≤120 birim + "…"', () {
      final s = tekSatiraKisalt('a' * 300);
      expect(s.length, lessThanOrEqualTo(yanitOnizlemeSiniri));
      expect(s.endsWith('…'), isTrue);
      expect(tekSatiraKisalt('b' * 120), 'b' * 120); // tam sınır kesilmez
      expect(tekSatiraKisalt('b' * 121).length, 120);
    });

    test('emoji (vekil çift) ortadan BÖLÜNMEZ', () {
      final s = tekSatiraKisalt('😀' * 100); // 200 UTF-16 birimi
      expect(s.length, lessThanOrEqualTo(yanitOnizlemeSiniri));
      final govde = s.substring(0, s.length - 1); // "…" hariç
      expect(govde.runes.every((r) => r == 0x1F600), isTrue);
      // Tek başına kalmış vekil (0xD800–0xDFFF) olmamalı.
      expect(s.runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
    });
  });

  group('Mesaj yanıt alanları', () {
    test('metin mesajına yanıt: kimlik, önizleme, gönderen', () {
      final m = Mesaj(id: 'm1', gonderen: 'alice', metin: 'selam\nnasılsın');
      expect(Mesaj.yanitAlanlari(m), {
        'yanitId': 'm1',
        'yanitOnizleme': 'selam nasılsın',
        'yanitGonderen': 'alice',
      });
    });

    test('medya mesajına yanıt: etiket', () {
      Map<String, String> y(MesajTipi t) => Mesaj.yanitAlanlari(
        Mesaj(id: 'x', gonderen: 'bob', metin: '', tip: t, medyaUrl: 'u'),
      );
      expect(y(MesajTipi.resim)['yanitOnizleme'], '📷 Fotoğraf');
      expect(y(MesajTipi.video)['yanitOnizleme'], '🎥 Video');
      expect(y(MesajTipi.ses)['yanitOnizleme'], '🎤 Sesli mesaj');
      expect(y(MesajTipi.gif)['yanitOnizleme'], '🎞️ GIF');
    });

    test('uzun metne yanıt kural sınırını aşmaz', () {
      final m = Mesaj(id: 'm', gonderen: 'a', metin: 'ğ' * 500);
      expect(
        Mesaj.yanitAlanlari(m)['yanitOnizleme']!.length,
        lessThanOrEqualTo(120),
      );
    });

    test('yanıt yoksa alan eklenmez', () {
      expect(Mesaj.yanitAlanlari(null), isEmpty);
    });
  });

  group('videoKapakUrl', () {
    test('Cloudinary video → aynı yolda .jpg', () {
      expect(
        videoKapakUrl(
          'https://res.cloudinary.com/demo/video/upload/v1712/klasor/abc.mp4',
        ),
        'https://res.cloudinary.com/demo/video/upload/v1712/klasor/abc.jpg',
      );
      expect(
        videoKapakUrl('https://res.cloudinary.com/d/video/upload/v1/a.b.MOV'),
        'https://res.cloudinary.com/d/video/upload/v1/a.b.jpg',
      );
    });

    test('uzantısız ad ve sorgu parametresi korunur', () {
      expect(
        videoKapakUrl('https://res.cloudinary.com/d/video/upload/v1/abc'),
        'https://res.cloudinary.com/d/video/upload/v1/abc.jpg',
      );
      expect(
        videoKapakUrl(
          'https://res.cloudinary.com/d/video/upload/v1/abc.mp4?_a=XYZ.1',
        ),
        'https://res.cloudinary.com/d/video/upload/v1/abc.jpg?_a=XYZ.1',
      );
    });

    test('Cloudinary video URL\'i değilse null', () {
      expect(
        videoKapakUrl('https://res.cloudinary.com/d/image/upload/a.jpg'),
        isNull,
      );
      expect(videoKapakUrl('https://ornek.com/video.mp4'), isNull);
      expect(
        videoKapakUrl('https://res.cloudinary.com/d/video/upload/'),
        isNull,
      );
    });
  });

  test('ses hızı döngüsü 1 → 1.5 → 2 → 1', () {
    expect(SesOynaticiServisi.sonrakiHiz(1.0), 1.5);
    expect(SesOynaticiServisi.sonrakiHiz(1.5), 2.0);
    expect(SesOynaticiServisi.sonrakiHiz(2.0), 1.0);
    expect(SesOynaticiServisi.sonrakiHiz(0.7), 1.0); // bilinmeyen → 1x
  });

  group('tepkiler (her kişinin ayrı tepkisi)', () {
    test('özet: aynı emoji sayılır, eski tek alan da dahil', () {
      final m = Mesaj(
        id: 'm',
        gonderen: 'a',
        metin: 'x',
        tepkiler: const {'a': '❤️', 'b': '❤️', 'c': '👍'},
        tepki: '👍',
      );
      expect(m.tepkiVar, isTrue);
      expect(
        m.tepkiOzeti.map((t) => '${t.emoji}${t.sayi}').toList(),
        ['❤️2', '👍2'],
      );
    });

    test('tepkisiz mesajda rozet yok', () {
      final m = Mesaj(id: 'm', gonderen: 'a', metin: 'x');
      expect(m.tepkiVar, isFalse);
      expect(m.tepkiOzeti, isEmpty);
    });
  });
}

