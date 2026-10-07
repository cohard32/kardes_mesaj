import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/servisler/taslak_servisi.dart';
import 'package:kardes_mesaj/yardimcilar/bildirim_yuku.dart';
import 'package:kardes_mesaj/yardimcilar/hatirlatma_zamani.dart';

void main() {
  group('hatırlatma seçenekleri', () {
    test('öğleden sonra: "bu akşam" var', () {
      final s = hatirlatmaSecenekleri(DateTime(2026, 10, 7, 15, 10));
      expect(s.map((e) => e.etiket), contains('Bu akşam 20:00'));
      expect(s.first.zaman, DateTime(2026, 10, 7, 15, 30));
      expect(s.last.zaman, DateTime(2026, 10, 8, 9));
    });

    test('akşam 19:45: "bu akşam" yok; ay sonu yarın doğru', () {
      final s = hatirlatmaSecenekleri(DateTime(2026, 10, 31, 19, 45));
      expect(s.map((e) => e.etiket), isNot(contains('Bu akşam 20:00')));
      expect(s.last.zaman, DateTime(2026, 11, 1, 9));
    });
  });

  test('hatırlatma metni', () {
    final simdi = DateTime(2026, 12, 31, 10);
    expect(hatirlatmaMetni(DateTime(2026, 12, 31, 20), simdi), 'Bugün 20:00');
    expect(hatirlatmaMetni(DateTime(2027, 1, 1, 9), simdi), 'Yarın 09:00');
    expect(hatirlatmaMetni(DateTime(2027, 1, 5, 14, 30), simdi),
        '5 Ocak 2027 14:30');
    expect(hatirlatmaMetni(DateTime(2026, 12, 2, 8), DateTime(2026, 11, 1)),
        '2 Aralık 08:00');
  });

  test('hatırlatma kimliği aralıkta ve kararlı', () {
    final t = DateTime(2026, 10, 7, 20);
    final a = mesajHatirlatmaKimligi('m1', t);
    expect(a, mesajHatirlatmaKimligi('m1', t));
    expect(a, isNot(mesajHatirlatmaKimligi('m2', t)));
    expect(a, inInclusiveRange(600000000, 699999999));
  });

  test('bildirim yükü gidiş-dönüş', () {
    final y = sohbetYuku('a_b', 'b');
    expect(sohbetYukuCoz(y), (chatId: 'a_b', karsiUid: 'b'));
    expect(sohbetYukuCoz(null), isNull);
    expect(sohbetYukuCoz('baska:x'), isNull);
    expect(sohbetYukuCoz('sohbet::b'), isNull);
  });

  test('taslak JSON çözümü bozuk veride boş döner', () {
    expect(taslaklariCoz('{"a_b":"merhaba","x":5}'), {'a_b': 'merhaba'});
    expect(taslaklariCoz('bozuk'), isEmpty);
    expect(taslaklariCoz(null), isEmpty);
  });
}
