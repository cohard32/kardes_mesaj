import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/yardimcilar/onemli_gun.dart';

void main() {
  test('ayGunYaz / ayGunCoz gidiş-dönüş, geçersizler reddedilir', () {
    expect(ayGunYaz(7, 5), '07-05');
    expect(ayGunCoz('07-05'), (ay: 7, gun: 5));
    expect(ayGunCoz('02-29'), (ay: 2, gun: 29));
    expect(ayGunCoz('02-30'), isNull);
    expect(ayGunCoz('13-01'), isNull);
    expect(ayGunCoz('7-5'), isNull);
    expect(ayGunCoz(705), isNull);
    expect(ayGunCoz(null), isNull);
  });

  test('ayGunMetni Türkçe', () {
    expect(ayGunMetni(8, 30), '30 Ağustos');
  });

  test('sonrakiTarih: bugün, geçmiş, gelecek', () {
    final simdi = DateTime(2026, 10, 7, 15, 30);
    expect(sonrakiTarih(10, 7, simdi), DateTime(2026, 10, 7));
    expect(sonrakiTarih(10, 6, simdi), DateTime(2027, 10, 6));
    expect(sonrakiTarih(12, 31, simdi), DateTime(2026, 12, 31));
  });

  test('29 Şubat artık olmayan yılda 28 Şubat', () {
    expect(sonrakiTarih(2, 29, DateTime(2026, 3, 1)), DateTime(2027, 2, 28));
    expect(sonrakiTarih(2, 29, DateTime(2027, 3, 1)), DateTime(2028, 2, 29));
  });

  test('kalanGun ve metni', () {
    final simdi = DateTime(2026, 12, 31, 23, 59);
    expect(kalanGun(12, 31, simdi), 0);
    expect(kalanGun(1, 1, simdi), 1);
    expect(kalanMetni(0), 'Bugün 🎉');
    expect(kalanMetni(1), 'Yarın');
    expect(kalanMetni(12), '12 gün sonra');
  });

  test('OnemliGun haritadan bozuk kaydı atlar', () {
    const g = OnemliGun(id: 'a', ad: 'Yıldönümü', ay: 5, gun: 12);
    expect(OnemliGun.haritadan(g.haritaya())?.ad, 'Yıldönümü');
    expect(OnemliGun.haritadan({'id': 'a', 'ad': '', 'ay': 5, 'gun': 12}), isNull);
    expect(OnemliGun.haritadan({'id': 'a', 'ad': 'x', 'ay': 2, 'gun': 31}), isNull);
    expect(OnemliGun.haritadan('bozuk'), isNull);
  });

  test('yakinligaGoreSirala', () {
    final simdi = DateTime(2026, 10, 7);
    final s = yakinligaGoreSirala(const [
      OnemliGun(id: 'a', ad: 'a', ay: 1, gun: 1),
      OnemliGun(id: 'b', ad: 'b', ay: 10, gun: 8),
      OnemliGun(id: 'c', ad: 'c', ay: 10, gun: 7),
    ], simdi);
    expect(s.map((e) => e.id), ['c', 'b', 'a']);
  });

  test('bildirim kimliği kararlı ve aralıkta', () {
    final a = hatirlaticiBildirimKimligi('dg_abc');
    expect(a, hatirlaticiBildirimKimligi('dg_abc'));
    expect(a, isNot(hatirlaticiBildirimKimligi('dg_abd')));
    expect(a, inInclusiveRange(700000000, 799999999));
  });

  test('bugün doğum günü mü', () {
    final simdi = DateTime(2026, 10, 7, 23, 59);
    expect(bugunDogumGunuMu('10-07', simdi: simdi), isTrue);
    expect(bugunDogumGunuMu('10-08', simdi: simdi), isFalse);
    expect(bugunDogumGunuMu(null, simdi: simdi), isFalse);
    expect(bugunDogumGunuMu('02-29', simdi: DateTime(2027, 2, 28)), isTrue);
  });
}

