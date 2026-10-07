// OnbellekliResim (disk önbellekli ImageProvider) gerçekten çözülüp resim
// veriyor mu, hata durumunda hata bildiriyor mu?

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kardes_mesaj/parcalar/onbellekli_resim.dart';
import 'package:kardes_mesaj/servisler/resim_onbellegi.dart';

// 1×1 piksel PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late Directory dizin;

  setUp(() => dizin = Directory.systemTemp.createTempSync('onbellekli_resim'));
  tearDown(() => dizin.deleteSync(recursive: true));

  Future<Object> coz(OnbellekliResim r) {
    final sonuc = Completer<Object>();
    r.resolve(ImageConfiguration.empty).addListener(
          ImageStreamListener(
            (info, _) => sonuc.complete(info),
            onError: (e, _) => sonuc.complete(e),
          ),
        );
    return sonuc.future.timeout(const Duration(seconds: 10));
  }

  testWidgets('indirip çözer; ikinci açılışta diskten gelir', (tester) async {
    var istek = 0;
    ResimOnbellegi kur() => ResimOnbellegi(
          dizin: () async => dizin,
          istemci: () => MockClient((_) async {
            istek++;
            return http.Response.bytes(_png, 200);
          }),
        );
    await tester.runAsync(() async {
      final a = await coz(OnbellekliResim('https://x/a.png', onbellek: kur()));
      expect(a, isA<ImageInfo>());
      expect((a as ImageInfo).image.width, 1);
      PaintingBinding.instance.imageCache.clear();
      final b = await coz(OnbellekliResim('https://x/a.png', onbellek: kur()));
      expect(b, isA<ImageInfo>());
    });
    expect(istek, 1);
  });

  testWidgets('ağ hatası resim hatası olarak bildirilir', (tester) async {
    final o = ResimOnbellegi(
      dizin: () async => dizin,
      istemci: () => MockClient((_) async => http.Response('yok', 404)),
    );
    await tester.runAsync(() async {
      final s = await coz(OnbellekliResim('https://x/yok.png', onbellek: o));
      expect(s, isA<HttpException>());
    });
  });

  test('eşitlik yalnız URL\'e bağlı (bellek önbelleği anahtarı)', () {
    expect(const OnbellekliResim('u'), const OnbellekliResim('u'));
    expect(const OnbellekliResim('u').hashCode, const OnbellekliResim('u').hashCode);
    expect(const OnbellekliResim('u'), isNot(const OnbellekliResim('v')));
  });
}
