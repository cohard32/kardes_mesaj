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
///
/// ⚠️ StatefulWidget OLMAK ZORUNDA: tema değişince `tumAgaciYenidenCiz()`
/// normalde hiç yeniden kurulmayan `const AuthGate()`'i de yeniden kurar.
/// Akışlar eskiden build içinde üretiliyordu; `authStateChanges()` her
/// çağrıda YENİ bir Stream döndürdüğü için StreamBuilder aboneliği bırakıp
/// yeniden abone oluyor, `waiting`'e düşüyor ve bekleme ekranı AnaKabuk'u
/// ağaçtan söküyordu → AnaKabuk dispose (cevrimdisiYap) + baştan initState
/// (cevrimiciYap, tokenKaydet, güncelleme penceresi), sekme Sohbetler'e
/// sıfırlanıyordu. Artık oturum akışı State'te BİR KEZ kurulur, profil akışı
/// uid'e göre önbellekte tutulur; bekleme ekranı yalnız elde veri YOKKEN.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.oturumAkisi,
    this.profilAkisi,
    this.girisKurucu,
    this.kurulumKurucu,
    this.anaKurucu,
  });

  /// Oturumdaki kullanıcının uid'i (null = çıkış). Verilmezse
  /// `FirebaseAuth.instance.authStateChanges()`. Testler sahte akış verir.
  final Stream<String?> Function()? oturumAkisi;

  /// uid → canlı profil. Verilmezse `KullaniciServisi.profilDinle`.
  final Stream<Kullanici> Function(String uid)? profilAkisi;

  /// Alt ekran kurucuları (testte Firebase'siz sahte ekranlar için).
  /// Verilmezse GirisEkrani / ProfilKurulumEkrani / AnaKabuk.
  final WidgetBuilder? girisKurucu;
  final WidgetBuilder? kurulumKurucu;
  final WidgetBuilder? anaKurucu;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// ⚠️ late final: build kaç kez çalışırsa çalışsın AYNI Stream nesnesi →
  /// StreamBuilder.didUpdateWidget yeniden abone olmaz.
  late final Stream<String?> _oturum = widget.oturumAkisi?.call() ??
      FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);

  /// Profil akışı önbelleği — yalnız uid değişince yeniden kurulur.
  String? _profilUid;
  Stream<Kullanici>? _profil;

  Stream<Kullanici> _profilAkisi(String uid) {
    if (_profil == null || _profilUid != uid) {
      _profilUid = uid;
      _profil = widget.profilAkisi?.call(uid) ??
          KullaniciServisi.instance.profilDinle(uid);
    }
    return _profil!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _oturum,
      builder: (context, snapshot) {
        // ⚠️ Yalnız ilk yüklemede bekle; elde veri varken waiting'e düşmek
        // (ör. yeniden abonelik) ağacı yıkmasın.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Bekle();
        }
        final uid = snapshot.data;
        if (uid == null) {
          // Çıkış → önbelleği bırak; aynı hesapla tekrar girilince taze
          // akış kurulsun (tek abonelikli akış iki kez dinlenmesin).
          _profilUid = null;
          _profil = null;
          return widget.girisKurucu?.call(context) ?? const GirisEkrani();
        }
        // Oturum var → profil dokümanı var mı diye canlı bak.
        // (Kurulum bitince users/{uid} yazılır ve buraya AnaKabuk düşer.)
        return StreamBuilder<Kullanici>(
          // ⚠️ uid anahtarı: hesap değişince önceki hesabın profil verisi
          // (profilVar=true) yeni hesaba bir kare bile taşınmasın.
          key: ValueKey<String>(uid),
          stream: _profilAkisi(uid),
          builder: (context, profilSnap) {
            if (profilSnap.connectionState == ConnectionState.waiting &&
                !profilSnap.hasData) {
              return const _Bekle();
            }
            final k = profilSnap.data;
            final profilVar = k != null && k.kullaniciAdi.isNotEmpty;
            if (profilVar) {
              return widget.anaKurucu?.call(context) ?? const AnaKabuk();
            }
            return widget.kurulumKurucu?.call(context) ??
                const ProfilKurulumEkrani();
          },
        );
      },
    );
  }
}

class _Bekle extends StatelessWidget {
  const _Bekle();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Zemin(
          child: Center(child: CircularProgressIndicator(color: Renkler.neon)),
        ),
      );
}
