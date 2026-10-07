// Gönderim önizleme ekranı: her öğeye ayrı açıklama, çıkarma, tür tahmini.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/ekranlar/medya_gonder_ekrani.dart';
import 'package:kardes_mesaj/modeller/mesaj.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  test('tür tahmini uzantıdan', () {
    expect(medyaTuruTahmin('/a/b/IMG_1.jpg'), MesajTipi.resim);
    expect(medyaTuruTahmin('/a/b/VID_1.MP4'), MesajTipi.video);
    expect(medyaTuruTahmin('/a/b/klip.mov'), MesajTipi.video);
    expect(medyaTuruTahmin('/a/b/uzantisiz'), MesajTipi.resim);
    expect(azamiMedyaBoyutu(MesajTipi.video), 100 * 1024 * 1024);
    expect(azamiMedyaBoyutu(MesajTipi.resim), 10 * 1024 * 1024);
  });

  group('MedyaGonderEkrani', () {
    late Directory dizin;
    late File f1, f2;

    setUp(() {
      dizin = Directory.systemTemp.createTempSync('medya_gonder');
      f1 = File('${dizin.path}/bir.png')..writeAsBytesSync(_png);
      f2 = File('${dizin.path}/iki.png')..writeAsBytesSync(_png);
    });
    tearDown(() => dizin.deleteSync(recursive: true));

    Future<List<GonderilecekMedya>?> ac(
      WidgetTester tester,
      List<File> dosyalar,
      Future<void> Function() islem,
    ) async {
      List<GonderilecekMedya>? sonuc;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                sonuc = await Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        MedyaGonderEkrani(dosyalar: dosyalar, kime: 'Ali'),
                  ),
                );
              },
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await islem();
      return sonuc;
    }

    testWidgets('her öğenin AYRI açıklaması gönderilir', (tester) async {
      final sonuc = await ac(tester, [f1, f2], () async {
        await tester.enterText(find.byType(TextField), 'birinci');
        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        await tester.enterText(find.byType(TextField), 'ikinci');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
      });
      expect(sonuc, isNotNull);
      expect(sonuc!.map((e) => e.aciklama).toList(), ['birinci', 'ikinci']);
      expect(sonuc.every((e) => e.tip == MesajTipi.resim), isTrue);
    });

    testWidgets('çıkarılan öğe gönderilmez', (tester) async {
      final sonuc = await ac(tester, [f1, f2], () async {
        await tester.tap(find.byTooltip('Bunu çıkar'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
      });
      expect(sonuc!.length, 1);
      expect(sonuc.single.dosya.path, f2.path);
    });
  });
}
