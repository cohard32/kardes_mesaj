import 'package:flutter/material.dart';

import '../modeller/kullanici.dart';
import '../tema.dart';
import '../yardimcilar/mesaj_metni.dart';
import 'onbellekli_resim.dart';

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
      // ⚠️ Profil fotoğrafı boyut sınırı olmadan yüklenebiliyor (12 MP+).
      // 40-52 px'lik avatar için tam çözünürlükte decode etmek, sohbet
      // listesinde her satırda megabaytlarca bellek demekti. Hedefin 2 katına
      // sığacak şekilde küçültülür (BoxFit.cover kırparken bulanıklaşmasın).
      // İNDİRME de küçük: Cloudinary'den ~256 px'lik hâli gelir ve telefonda
      // saklanır (eskiden her açılışta orijinal, birkaç MB, yeniden iniyordu).
      final hedef = (boyut * MediaQuery.devicePixelRatioOf(context) * 2).round();
      icerik = ClipRRect(
        borderRadius: kose,
        child: Image(
          image: ResizeImage(
            OnbellekliResim(
              kucukResimUrl(foto, genislik: hedef > 256 ? 512 : 256),
            ),
            width: hedef,
            height: hedef,
            policy: ResizeImagePolicy.fit,
          ),
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
              // "Neon parıltısını azalt" açıkken nokta parlamaz.
              boxShadow: Renkler.pariltiAzalt
                  ? null
                  : [
                      BoxShadow(
                          color: Renkler.neon.withValues(alpha: 0.6),
                          blurRadius: 6),
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
