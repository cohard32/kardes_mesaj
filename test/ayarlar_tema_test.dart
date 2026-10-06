// Ayarlar > Görünüm: tema kartına dokununca palet değişir, kalıcı olur ve
// ekran (gezinme yığını korunarak) yeni renklerle yeniden çizilir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kardes_mesaj/ekranlar/ayarlar_ekrani.dart';
import 'package:kardes_mesaj/servisler/ayar_servisi.dart';
import 'package:kardes_mesaj/tema.dart';

void main() {
  tearDown(() => Renkler.uygula(RoyPalet.neonLime, pariltiAzalt: false));

  testWidgets('tema kartı paleti değiştirir, Ayarlar açık kalır', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AyarServisi.instance.baslat();
    final ayar = AyarServisi.instance;

    // main.dart'taki bağlamanın küçük eşleniği.
    void yenile() => tumAgaciYenidenCiz();
    ayar.tema.addListener(yenile);
    ayar.parilti.addListener(yenile);
    addTearDown(() {
      ayar.tema.removeListener(yenile);
      ayar.parilti.removeListener(yenile);
    });

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        theme: AppTema.olustur(),
        home: const Scaffold(body: Text('ana')),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani()),
    );
    await tester.pumpAndSettle();

    expect(find.text('GÖRÜNÜM'), findsOneWidget);
    for (final p in RoyPalet.hepsi) {
      expect(find.text(p.gorunenAd), findsOneWidget);
    }

    await tester.tap(find.text('Lavanta Gece'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(Renkler.aktif, same(RoyPalet.lavanta));
    expect(await AyarServisi.temaDiskten(), 'lavanta');
    // Ayarlar hâlâ açık ve geri gidilebilir (yığın korunmuş)
    expect(find.byType(AyarlarEkrani), findsOneWidget);
    expect(navKey.currentState!.canPop(), isTrue);
    // Bölüm başlığı (statik Renkler.neon okuyor) yeni vurguyla çizildi
    final baslik = tester.widget<Text>(find.text('GÖRÜNÜM'));
    expect(baslik.style?.color, RoyPalet.lavanta.neon);

    await tester.tap(find.text('Neon parıltısını azalt'));
    await tester.pumpAndSettle();
    expect(ayar.parilti.value, isFalse);
    expect(Renkler.pariltiAzalt, isTrue);

    await tester.tap(find.text('Gün Işığı'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(Renkler.acikMi, isTrue);
  });
}
