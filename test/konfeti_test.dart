import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/parcalar/konfeti.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('konfeti oynar ve bitince haber verir', (tester) async {
    var bitti = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KonfetiYagmuru(
            sure: const Duration(milliseconds: 500),
            onBitti: () => bitti = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(bitti, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(bitti, isTrue);
  });

  testWidgets('konfetiPatlat overlay\'i kendiliğinden kaldırır', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    );
    konfetiPatlat(ctx);
    await tester.pump();
    expect(find.byType(KonfetiYagmuru), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(KonfetiYagmuru), findsNothing);
  });

  test('günde bir kez', () async {
    SharedPreferences.setMockInitialValues({});
    final bugun = DateTime(2026, 10, 7, 9);
    expect(await bugunIlkKezMi('x', simdi: bugun), isTrue);
    expect(await bugunIlkKezMi('x', simdi: bugun), isFalse);
    expect(await bugunIlkKezMi('x', simdi: DateTime(2026, 10, 8)), isTrue);
    expect(await bugunIlkKezMi('y', simdi: bugun), isTrue);
  });
}
