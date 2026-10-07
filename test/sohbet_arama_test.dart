import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/modeller/mesaj.dart';
import 'package:kardes_mesaj/yardimcilar/sohbet_arama.dart';
import 'package:kardes_mesaj/yardimcilar/tr_metin.dart';

Mesaj _m(String id, String metin, {MesajTipi tip = MesajTipi.metin}) =>
    Mesaj(id: id, gonderen: 'a', metin: metin, tip: tip);

void main() {
  test('trKucuk Türkçe kurallarına uyar', () {
    expect(trKucuk('IŞIK İzmir'), 'ışık izmir');
  });

  test('aramaIcinSadele harf farklarını katlar', () {
    expect(aramaIcinSadele('Görüşürüz ÇAĞ'), 'gorusuruz cag');
    expect(aramaIcinSadele('ISIK'), aramaIcinSadele('ışık'));
  });

  test('sohbetteAra sırayı korur, harf/aksan farkını yok sayar', () {
    final liste = [
      _m('3', 'Yarın görüşürüz'),
      _m('2', 'selam'),
      _m('1', 'GÖRÜŞÜRÜZ o zaman'),
    ];
    expect(sohbetteAra(liste, 'gorusuruz').map((m) => m.id), ['3', '1']);
    expect(sohbetteAra(liste, '  Selam ').map((m) => m.id), ['2']);
    expect(sohbetteAra(liste, 'yok'), isEmpty);
  });

  test('çok kısa sorgu ve boş metinli medya sonuç vermez', () {
    final liste = [_m('1', 'a'), _m('2', '', tip: MesajTipi.resim)];
    expect(sohbetteAra(liste, 'a'), isEmpty);
    expect(sohbetteAra(liste, ''), isEmpty);
  });
}
