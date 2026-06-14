import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ekranlar/giris_ekrani.dart';
import '../ekranlar/sohbet_ekrani.dart';
import '../tema.dart';

/// Oturum bekçisi.
/// Firebase oturumu KALICIDIR: kullanıcı bir kere giriş yapınca,
/// uygulama kapanıp açılsa bile [authStateChanges] onu hatırlar ve
/// direkt sohbete düşer. Çıkış yapılana kadar giriş ekranı görünmez.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase ilk durumu çözerken kısa bir bekleme
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Renkler.accent),
            ),
          );
        }

        // Giriş yapılmışsa sohbete, yapılmamışsa giriş ekranına
        if (snapshot.hasData) {
          return const SohbetEkrani();
        }
        return const GirisEkrani();
      },
    );
  }
}
