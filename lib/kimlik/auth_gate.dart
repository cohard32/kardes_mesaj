import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ekranlar/ana_kabuk.dart';
import '../ekranlar/giris_ekrani.dart';
import '../ekranlar/profil_kurulum_ekrani.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';

/// Oturum bekçisi (FAZ 4.3c).
/// Firebase oturumu KALICIDIR. Akış:
///   giriş yok            → GirisEkrani
///   giriş var, profil yok → ProfilKurulumEkrani (@kullanıcı adı seç)
///   giriş var, profil var → AnaKabuk (alt bar)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Bekle();
        }
        if (!snapshot.hasData) {
          return const GirisEkrani();
        }
        // Oturum var → profil dokümanı var mı diye canlı bak.
        // (Kurulum bitince users/{uid} yazılır ve buraya AnaKabuk düşer.)
        return StreamBuilder(
          stream: KullaniciServisi.instance.benimProfilim(),
          builder: (context, profilSnap) {
            if (profilSnap.connectionState == ConnectionState.waiting) {
              return const _Bekle();
            }
            final k = profilSnap.data;
            final profilVar = k != null && k.kullaniciAdi.isNotEmpty;
            return profilVar ? const AnaKabuk() : const ProfilKurulumEkrani();
          },
        );
      },
    );
  }
}

class _Bekle extends StatelessWidget {
  const _Bekle();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Zemin(
          child: Center(child: CircularProgressIndicator(color: Renkler.neon)),
        ),
      );
}
