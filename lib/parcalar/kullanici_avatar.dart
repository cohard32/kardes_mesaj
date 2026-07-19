import 'package:flutter/material.dart';

import '../modeller/kullanici.dart';
import '../tema.dart';

/// Kullanıcı avatarı — profil fotoğrafı varsa onu, yoksa gradient + baş harf.
/// Organik köşe + iç ışık (tema dili). Tüm ekranlarda ortak kullanılır.
class KullaniciAvatar extends StatelessWidget {
  final Kullanici? kullanici;
  final double boyut;

  /// Çevrimiçi neon noktası göster
  final bool cevrimiciGoster;

  const KullaniciAvatar({
    super.key,
    required this.kullanici,
    this.boyut = 48,
    this.cevrimiciGoster = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = kullanici;
    final foto = k?.fotoUrl;
    final kose = BorderRadius.circular(boyut * 0.34);

    Widget icerik;
    if (foto != null && foto.isNotEmpty) {
      icerik = ClipRRect(
        borderRadius: kose,
        child: Image.network(
          foto,
          width: boyut,
          height: boyut,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _harfli(k, kose),
        ),
      );
    } else {
      icerik = _harfli(k, kose);
    }

    if (!cevrimiciGoster || !(k?.cevrimici ?? false)) return icerik;

    // Sağ altta çevrimiçi neon noktası
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icerik,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: boyut * 0.28,
            height: boyut * 0.28,
            decoration: BoxDecoration(
              color: Renkler.neon,
              shape: BoxShape.circle,
              border: Border.all(color: Renkler.zemin, width: 2),
              boxShadow: [
                BoxShadow(
                    color: Renkler.neon.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _harfli(Kullanici? k, BorderRadius kose) {
    return Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(
        gradient: Gradyanlar.yesil,
        borderRadius: kose,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: IcIsik(kose: kose, guclu: false)),
          Center(
            child: Text(
              k?.harf ?? '?',
              style: Yazi.stil(
                boyut * 0.4,
                FontWeight.w800,
                Renkler.metinKoyu,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
