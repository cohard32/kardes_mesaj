import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ekranlar/ana_kabuk.dart';
import '../ekranlar/giris_ekrani.dart';
import '../ekranlar/profil_kurulum_ekrani.dart';
import '../modeller/kullanici.dart';
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
        // Anahtar = uid → hesap değişirse akış YENİ kullanıcı için kurulur.
        return _ProfilKapisi(
          key: ValueKey(snapshot.data!.uid),
          uid: snapshot.data!.uid,
        );
      },
    );
  }
}

/// Profil akışını BİR KEZ (initState'te) kurar. Eskiden stream build içinde
/// oluşturuluyordu → her yeniden çizimde abonelik yenilenip kısa süre
/// bekleme ekranına düşülüyordu.
class _ProfilKapisi extends StatefulWidget {
  final String uid;
  const _ProfilKapisi({super.key, required this.uid});

  @override
  State<_ProfilKapisi> createState() => _ProfilKapisiState();
}

class _ProfilKapisiState extends State<_ProfilKapisi> {
  late final Stream<Kullanici> _profil =
      KullaniciServisi.instance.profilDinle(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Kullanici>(
      stream: _profil,
      builder: (context, profilSnap) {
        if (profilSnap.connectionState == ConnectionState.waiting &&
            !profilSnap.hasData) {
          return const _Bekle();
        }
        final k = profilSnap.data;
        final profilVar = k != null && k.kullaniciAdi.isNotEmpty;
        return profilVar ? const AnaKabuk() : const ProfilKurulumEkrani();
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
