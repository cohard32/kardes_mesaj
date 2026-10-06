// İsolate'ler arası "görüşmedeyim" kaydı: tazelik + nabız + sıralı yaz/sil.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kardes_mesaj/servisler/aktif_arama_kaydi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AktifAramaKaydi.cozumle', () {
    final simdi = DateTime(2026, 10, 6, 12);
    String kayit(String chatId, Duration once) =>
        '$chatId|${simdi.subtract(once).millisecondsSinceEpoch}';

    test('taze kayıt chatId döner', () {
      expect(AktifAramaKaydi.cozumle(kayit('A_B', Duration.zero), simdi), 'A_B');
      expect(
        AktifAramaKaydi.cozumle(kayit('A_B', const Duration(minutes: 2)), simdi),
        'A_B',
      );
    });

    test('tazelik (3 dk) geçmişse bayat → null', () {
      expect(AktifAramaKaydi.tazelik, const Duration(minutes: 3));
      expect(
        AktifAramaKaydi.cozumle(
            kayit('A_B', const Duration(minutes: 3, seconds: 1)), simdi),
        isNull,
      );
      // Eski 3 saatlik pencere artık kesinlikle geçerli DEĞİL.
      expect(
        AktifAramaKaydi.cozumle(kayit('A_B', const Duration(hours: 1)), simdi),
        isNull,
      );
    });

    test('gelecek zaman / bozuk kayıt → null', () {
      expect(
        AktifAramaKaydi.cozumle(
            kayit('A_B', const Duration(minutes: -1)), simdi),
        isNull,
      );
      expect(AktifAramaKaydi.cozumle(null, simdi), isNull);
      expect(AktifAramaKaydi.cozumle('A_B', simdi), isNull);
      expect(AktifAramaKaydi.cozumle('|123', simdi), isNull);
      expect(AktifAramaKaydi.cozumle('A_B|xyz', simdi), isNull);
    });

    test('nabız, tazelik penceresine en az iki kez sığar', () {
      // Bir tik gecikse/kaçsa da süren görüşme bayat sayılmamalı.
      expect(
        AktifAramaKaydi.nabizAraligi * 2 < AktifAramaKaydi.tazelik,
        isTrue,
      );
    });
  });

  group('AktifAramaKaydi yaz/sil/oku', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('yaz → oku, sil → null', () async {
      await AktifAramaKaydi.yaz('A_B');
      expect(await AktifAramaKaydi.oku(), 'A_B');
      await AktifAramaKaydi.sil();
      expect(await AktifAramaKaydi.oku(), isNull);
    });

    test('beklenmeyen yaz + hemen sil: sıra korunur, kayıt GERİ GELMEZ',
        () async {
      // Nabız tiki ile bitir() yarışı: yaz önce çağrıldıysa sil ondan
      // SONRA diske inmeli.
      final y = AktifAramaKaydi.yaz('A_B');
      await AktifAramaKaydi.sil();
      await y;
      expect(await AktifAramaKaydi.oku(), isNull);
    });

    test('açılıştaki sil, önceki süreçten kalan kaydı temizler', () async {
      SharedPreferences.setMockInitialValues({
        'aktifArama': 'A_B|${DateTime.now().millisecondsSinceEpoch}',
      });
      expect(await AktifAramaKaydi.oku(), 'A_B');
      await AktifAramaKaydi.sil();
      expect(await AktifAramaKaydi.oku(), isNull);
    });
  });
}
