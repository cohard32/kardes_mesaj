// ResimOnbellegi (disk önbelleği) + kucukResimUrl testleri. Firebase'siz:
// geçici klasör + sahte HTTP istemcisi.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kardes_mesaj/servisler/resim_onbellegi.dart';
import 'package:kardes_mesaj/yardimcilar/mesaj_metni.dart';

void main() {
  group('kucukResimUrl', () {
    test('Cloudinary resmine küçültme dönüşümü eklenir', () {
      expect(
        kucukResimUrl('https://res.cloudinary.com/d/image/upload/v17/abc.png'),
        'https://res.cloudinary.com/d/image/upload/'
        'c_limit,w_720,q_auto,f_jpg/v17/abc.png',
      );
      expect(
        kucukResimUrl(
          'https://res.cloudinary.com/d/image/upload/v1/a.jpg',
          genislik: 256,
        ),
        contains('/upload/c_limit,w_256,q_auto,f_jpg/v1/a.jpg'),
      );
    });

    test('video KAPAĞI küçülür, videonun kendisi DOKUNULMAZ', () {
      final kapak = videoKapakUrl(
        'https://res.cloudinary.com/d/video/upload/v1/klip.mp4',
      )!;
      expect(kucukResimUrl(kapak), contains('/video/upload/c_limit,w_720'));
      const video = 'https://res.cloudinary.com/d/video/upload/v1/klip.mp4';
      expect(kucukResimUrl(video), video);
    });

    test('Cloudinary dışı (GIPHY) ve tuhaf adresler olduğu gibi kalır', () {
      const gif = 'https://media.giphy.com/media/xyz/giphy.gif';
      expect(kucukResimUrl(gif), gif);
      expect(kucukResimUrl(''), '');
      const raw = 'https://res.cloudinary.com/d/raw/upload/v1/belge.pdf';
      expect(kucukResimUrl(raw), raw);
    });
  });

  group('ResimOnbellegi', () {
    late Directory dizin;
    late int istekSayisi;
    late http.Response Function(http.Request) yanitla;

    ResimOnbellegi kur({int sinir = 1 << 30}) => ResimOnbellegi(
          dizin: () async => dizin,
          istemci: () => MockClient((r) async {
            istekSayisi++;
            return yanitla(r);
          }),
          sinirBayt: sinir,
        );

    setUp(() async {
      dizin = await Directory.systemTemp.createTemp('resim_onbellegi_test');
      istekSayisi = 0;
      yanitla = (r) => http.Response.bytes(
            Uint8List.fromList(List<int>.filled(100, 7)),
            200,
          );
    });

    tearDown(() async {
      if (await dizin.exists()) await dizin.delete(recursive: true);
    });

    test('ilk istek indirir ve diske yazar, ikincisi ağa ÇIKMAZ', () async {
      final o = kur();
      final a = await o.getir('https://x/a.jpg');
      expect(a.length, 100);
      expect(istekSayisi, 1);
      expect(await o.dosyasi('https://x/a.jpg'), isNotNull);

      // Yeni örnek = uygulama yeniden açıldı (bellek boş, disk dolu).
      final b = await kur().getir('https://x/a.jpg');
      expect(b, a);
      expect(istekSayisi, 1);
    });

    test('aynı anda gelen istekler TEK indirmede birleşir', () async {
      final o = kur();
      final sonuc = await Future.wait([
        o.getir('https://x/b.jpg'),
        o.getir('https://x/b.jpg'),
        o.getir('https://x/b.jpg'),
      ]);
      expect(sonuc.every((e) => e.length == 100), isTrue);
      expect(istekSayisi, 1);
    });

    test('HTTP hatası fırlatır ve önbelleğe bir şey yazılmaz', () async {
      yanitla = (r) => http.Response('yok', 404);
      final o = kur();
      await expectLater(o.getir('https://x/c.jpg'), throwsA(isA<HttpException>()));
      expect(await o.dosyasi('https://x/c.jpg'), isNull);
      // Hata kalıcı değil: sonraki denemede yeniden istenir.
      yanitla = (r) => http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
      expect((await o.getir('https://x/c.jpg')).length, 3);
      expect(istekSayisi, 2);
    });

    test('ilerleme bildirilir', () async {
      final o = kur();
      var son = 0;
      await o.getir('https://x/d.jpg', ilerleme: (alinan, toplam) {
        son = alinan;
      });
      expect(son, 100);
    });

    test('budama: sınır aşılınca EN ESKİ kullanılanlar silinir', () async {
      final o = kur(sinir: 250);
      // 3 × 100 bayt = 300 > 250 → en eskiden başlayarak %80'e (200) inilir.
      for (final ad in ['e1', 'e2', 'e3']) {
        await o.getir('https://x/$ad.jpg');
      }
      final simdi = DateTime.now();
      final dosyalar = {
        for (final ad in ['e1', 'e2', 'e3'])
          ad: (await o.dosyasi('https://x/$ad.jpg'))!,
      };
      await dosyalar['e1']!.setLastModified(simdi.subtract(const Duration(days: 3)));
      await dosyalar['e2']!.setLastModified(simdi.subtract(const Duration(days: 1)));
      await dosyalar['e3']!.setLastModified(simdi);

      await o.budama();
      expect(await o.dosyasi('https://x/e1.jpg'), isNull);
      expect(await o.dosyasi('https://x/e2.jpg'), isNotNull);
      expect(await o.dosyasi('https://x/e3.jpg'), isNotNull);
    });

    test('anahtar kararlı ve farklı adreslerde farklı', () {
      expect(ResimOnbellegi.anahtar('https://x/a'),
          ResimOnbellegi.anahtar('https://x/a'));
      expect(ResimOnbellegi.anahtar('https://x/a'),
          isNot(ResimOnbellegi.anahtar('https://x/b')));
      expect(ResimOnbellegi.anahtar('https://x/ab'),
          isNot(ResimOnbellegi.anahtar('https://x/ba')));
    });
  });
}
