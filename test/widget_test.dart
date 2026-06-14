// Giriş ekranı izole testi: Firebase başlatmadan, ekranın açılıp
// temel öğeleri (başlık + giriş butonu) gösterdiğini doğrular.
// (AuthGate Firebase gerektirdiği için doğrudan GirisEkrani test edilir.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/ekranlar/giris_ekrani.dart';
import 'package:kardes_mesaj/tema.dart';

void main() {
  testWidgets('Giris ekrani aciliyor', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTema.karanlik(),
        home: const GirisEkrani(),
      ),
    );

    expect(find.text('Kardeş Mesaj'), findsOneWidget);
    expect(find.text('Giriş yap'), findsWidgets); // alt başlık + buton
    expect(find.byType(TextField), findsNWidgets(2)); // e-posta + şifre
  });
}
