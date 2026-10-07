import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/parcalar/balon_hareketleri.dart';

void main() {
  Future<int> kaydir(WidgetTester tester, double dx) async {
    var yanit = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaydirarakYanit(
            onYanit: () => yanit++,
            child: const SizedBox(
              height: 60,
              width: double.infinity,
              child: Text('balon'),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('balon'), Offset(dx, 0));
    await tester.pumpAndSettle();
    return yanit;
  }

  testWidgets('eşiği geçen sağa kaydırma yanıtı tetikler', (tester) async {
    expect(await kaydir(tester, 120), 1);
    // Bırakınca balon yerine döner.
    final t = tester.widget<Transform>(
      find.ancestor(of: find.text('balon'), matching: find.byType(Transform)).first,
    );
    expect(t.transform.getTranslation().x, 0);
  });

  testWidgets('kısa kaydırma ve SOLA kaydırma tetiklemez', (tester) async {
    expect(await kaydir(tester, 30), 0);
    expect(await kaydir(tester, -150), 0);
  });

  testWidgets('kalp patlaması oynar ve kendini bitirir', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: KalpPatlamasi())),
    );
    expect(find.text('❤️'), findsOneWidget);
    await tester.pumpAndSettle();
    final f = tester.widget<FadeTransition>(find.byType(FadeTransition).last);
    expect(f.opacity.value, 0);
  });
}
