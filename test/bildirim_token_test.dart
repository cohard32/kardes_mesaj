// d10 (ikinci tur): aktarıcılı derlemede FCM token'ının BİR KEZ döndürülmesi.
// Public alanı silmek, önceden toplanmış (hâlâ geçerli) değeri öldürmez;
// tokenBirKezDondur deleteToken çağırıp işareti diske yazar.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kardes_mesaj/servisler/bildirim_servisi.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ilk çağrı token\'ı siler ve işaret koyar; sonrakiler silmez', () async {
    var silme = 0;
    Future<void> sil() async => silme++;

    expect(await tokenBirKezDondur(sil), isTrue);
    expect(silme, 1);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(tokenDondurulduAnahtari), isTrue);

    expect(await tokenBirKezDondur(sil), isTrue);
    expect(await tokenBirKezDondur(sil), isTrue);
    expect(silme, 1, reason: 'her açılışta token yeniden döndürülmemeli');
  });

  test('silme başarısızsa false; işaret YAZILMAZ, sonraki çağrı yeniden dener',
      () async {
    var deneme = 0;
    Future<void> bozuk() async {
      deneme++;
      throw Exception('çevrimdışı');
    }

    expect(await tokenBirKezDondur(bozuk), isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(tokenDondurulduAnahtari), isNull);

    var silme = 0;
    expect(await tokenBirKezDondur(() async => silme++), isTrue);
    expect(deneme, 1);
    expect(silme, 1);
  });

  test('token yeniden public yazılınca işaret düşer → yeniden döndürülür',
      () async {
    var silme = 0;
    Future<void> sil() async => silme++;
    await tokenBirKezDondur(sil);
    await tokenDondurmaIsaretiniSil();
    await tokenBirKezDondur(sil);
    expect(silme, 2);
  });
}
