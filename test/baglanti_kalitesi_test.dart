import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/servisler/baglanti_kalitesi.dart';

void main() {
  test('Agora değerleri gösterilecek kaliteye çevrilir', () {
    expect(kaliteCoz(1), BaglantiKalitesi.iyi);
    expect(kaliteCoz(2), BaglantiKalitesi.iyi);
    expect(kaliteCoz(3), BaglantiKalitesi.orta);
    expect(kaliteCoz(5), BaglantiKalitesi.zayif);
    expect(kaliteCoz(6), BaglantiKalitesi.kopuk);
    expect(kaliteCoz(0), BaglantiKalitesi.bilinmiyor);
    expect(kaliteCoz(8), BaglantiKalitesi.bilinmiyor);
  });

  test('birleştirme: kötü olan kazanır, bilinmeyen yok sayılır', () {
    expect(kaliteBirlestir(1, 4), 4);
    expect(kaliteBirlestir(5, 2), 5);
    expect(kaliteBirlestir(0, 3), 3);
    expect(kaliteBirlestir(8, 0), 0);
    expect(kaliteBirlestir(2, 7), 2);
  });

  test('çubuk ve uyarı', () {
    expect(kaliteCubuk(BaglantiKalitesi.iyi), 4);
    expect(kaliteCubuk(BaglantiKalitesi.zayif), 1);
    expect(kaliteUyarisi(BaglantiKalitesi.iyi), isNull);
    expect(kaliteUyarisi(BaglantiKalitesi.zayif), contains('zayıf'));
  });
}
