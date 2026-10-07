import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/yardimcilar/link_metni.dart';

void main() {
  group('linkleriAyir', () {
    test('link yoksa tek düz parça', () {
      expect(linkleriAyir('selam nasılsın'), [const MetinParcasi('selam nasılsın')]);
      expect(linkleriAyir(''), isEmpty);
    });

    test('ortadaki https linki ayrılır', () {
      expect(linkleriAyir('bak https://ornek.com/a?b=1 güzel'), [
        const MetinParcasi('bak '),
        const MetinParcasi('https://ornek.com/a?b=1', 'https://ornek.com/a?b=1'),
        const MetinParcasi(' güzel'),
      ]);
    });

    test('www. linki https ile açılır', () {
      expect(linkleriAyir('www.youtube.com'), [
        const MetinParcasi('www.youtube.com', 'https://www.youtube.com'),
      ]);
    });

    test('sondaki noktalama linke dahil değil', () {
      expect(linkleriAyir('şuna bak: https://x.com/a.'), [
        const MetinParcasi('şuna bak: '),
        const MetinParcasi('https://x.com/a', 'https://x.com/a'),
        const MetinParcasi('.'),
      ]);
    });

    test('parantez: eşleşmeyen kapanış atılır, eşleşen korunur', () {
      final p = linkleriAyir('(bkz. https://x.com/a)');
      expect(p[1], const MetinParcasi('https://x.com/a', 'https://x.com/a'));
      expect(p.last, const MetinParcasi(')'));
      const w = 'https://tr.wikipedia.org/wiki/Ankara_(il)';
      expect(linkleriAyir(w), [const MetinParcasi(w, w)]);
    });

    test('şemasız alan adı ve sayılar link sayılmaz', () {
      expect(linkleriAyir('saat 10.30 ornek.com'), hasLength(1));
      expect(linkleriAyir('https://'), [const MetinParcasi('https://')]);
    });

    test('birden çok link ve büyük harf şema', () {
      final p = linkleriAyir('HTTPS://A.com ve http://b.org');
      expect(p.where((e) => e.linkMi).map((e) => e.url),
          ['HTTPS://A.com', 'http://b.org']);
    });

    test('parçalar birleşince özgün metni verir', () {
      const m = 'a https://x.com/y, b www.z.net! (c https://q.io)';
      expect(linkleriAyir(m).map((e) => e.metin).join(), m);
    });
  });

  group('acilabilirLinkMi', () {
    test('yalnız http/https', () {
      expect(acilabilirLinkMi('https://x.com'), isTrue);
      expect(acilabilirLinkMi('HTTP://x.com'), isTrue);
      expect(acilabilirLinkMi('javascript:alert(1)'), isFalse);
      expect(acilabilirLinkMi('file:///sdcard/a'), isFalse);
      expect(acilabilirLinkMi('intent://x#Intent;end'), isFalse);
      expect(acilabilirLinkMi('https://'), isFalse);
    });
  });
}
