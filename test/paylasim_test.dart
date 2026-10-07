import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/servisler/paylasim_servisi.dart';

void main() {
  test('Android haritası çözülür, bozuk girdiler atlanır', () {
    final p = paylasimCoz({
      'metin': 'bak https://x.com',
      'dosyalar': [
        {'yol': '/c/1.jpg', 'ad': '1.jpg', 'boyut': 10, 'mime': 'image/jpeg'},
        {'yol': '/c/2.mp4', 'ad': '2.mp4', 'boyut': 20, 'mime': 'video/mp4'},
        {'yol': '/c/r.pdf', 'ad': 'rapor.pdf', 'boyut': 30, 'mime': 'application/pdf'},
        {'ad': 'yolsuz'},
        'bozuk',
      ],
      'buyukler': ['dev.mkv', 5],
    })!;
    expect(p.metin, 'bak https://x.com');
    expect(p.dosyalar.length, 3);
    expect(p.dosyalar[0].resimMi, isTrue);
    expect(p.dosyalar[1].videoMu, isTrue);
    expect(p.dosyalar[2].belgeMi, isTrue);
    expect(p.buyukler, ['dev.mkv']);
    expect(p.ozet, '1 fotoğraf · 1 video · rapor.pdf · "bak https://x.com"');
  });

  test('boş / geçersiz paylaşım null', () {
    expect(paylasimCoz(null), isNull);
    expect(paylasimCoz('x'), isNull);
    expect(paylasimCoz({'metin': '  ', 'dosyalar': []}), isNull);
  });

  test('uzun metin özette kısaltılır', () {
    final p = paylasimCoz({'metin': 'a' * 100})!;
    expect(p.ozet.length, lessThan(70));
    expect(p.ozet.endsWith('…"'), isTrue);
  });
}
