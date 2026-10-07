import 'package:flutter/material.dart';
import '../servisler/hata_servisi.dart';

import '../main.dart' show bekleyenSohbetiAc;
import '../parcalar/guncelleme_akisi.dart';
import '../servisler/arama_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/hatirlatici_servisi.dart';
import '../servisler/paylasim_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../servisler/resim_onbellegi.dart';
import '../servisler/sohbet_servisi.dart';
import '../servisler/yerel_olaylar.dart';
import '../tema.dart';
import 'arama_ekrani.dart';
import 'arkadaslar_ekrani.dart';
import 'paylasim_hedefi_ekrani.dart';
import 'profil_ekrani.dart';
import 'sohbet_listesi_ekrani.dart';

/// Uygulama kabuğu (FAZ 4.3): alt bar ile Sohbetler / Arkadaşlar / Profil.
/// Giriş sonrası ana ekran. Çevrimiçi durumu, token kaydı ve CallKit ile
/// (kapalıyken) kabul edilmiş aramanın ekranını açmayı burada yönetir.
class AnaKabuk extends StatefulWidget {
  const AnaKabuk({super.key});

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> with WidgetsBindingObserver {
  int _sekme = 0;

  // Rozet akışı önbellekte: build'de oluşturulursa her sekme değişiminde
  // Firestore dinleyicisi yeniden kurulur.
  late final Stream<int> _okunmamisAkisi =
      SohbetServisi.instance.toplamOkunmamis();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HataServisi.instance.iz('ANA EKRAN acildi');
    BildirimServisi.instance.tokenKaydet();
    PresenceServisi.instance.cevrimiciYap();
    // ⚠️ Nabız: uygulama öldürülürse cevrimdisiYap hiç çalışmaz; okuyanlar
    // sonGorulme 150 sn'yi geçince çevrimdışı sayar (Kullanici.cevrimici).
    PresenceServisi.instance.nabziBaslat();
    // Doğum günü / önemli gün bildirimlerini (yerel alarm) güncel tut.
    HatirlaticiServisi.instance.baslat();
    // Resim önbelleği sınırı aştıysa en eski kullanılanları sil (arka planda).
    ResimOnbellegi.instance.budama();
    YerelOlaylar.paylasimGeldi.addListener(_paylasimKontrol);
    // Kapalıyken CallKit'ten kabul edilmiş arama / tıklanmış mesaj bildirimi
    // varsa (navigator artık hazır) ilgili ekranı aç.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bekleyenAramayiAc();
      bekleyenSohbetiAc();
      // "Paylaş → ROY" ile uygulama KAPALIYKEN gelen içerik.
      _paylasimKontrol();
      // Açılışta güncelleme kontrolü (eskiden SohbetEkrani'ndaydı; FAZ 4'te
      // ana ekran AnaKabuk olduğu için buraya taşındı → her açılışta çalışır).
      if (mounted) guncellemeAkisi(context, sessiz: true);
    });
  }

  /// Bekleyen paylaşım varsa "Kime gönderilsin?" ekranını açar.
  /// Uygulama açıkken gelen paylaşımda da (YerelOlaylar) çağrılır.
  Future<void> _paylasimKontrol() async {
    final p = await PaylasimServisi.instance.al();
    if (p == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaylasimHedefiEkrani(paylasim: p),
      ),
    );
  }

  @override
  void dispose() {
    YerelOlaylar.paylasimGeldi.removeListener(_paylasimKontrol);
    WidgetsBinding.instance.removeObserver(this);
    PresenceServisi.instance.nabziDurdur();
    PresenceServisi.instance.cevrimdisiYap();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PresenceServisi.instance.cevrimiciYap();
      PresenceServisi.instance.nabziBaslat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Önce nabız durur: geç bir tik cevrimdisiYap'tan sonra true yazmasın.
      PresenceServisi.instance.nabziDurdur();
      PresenceServisi.instance.cevrimdisiYap();
    }
  }

  void _bekleyenAramayiAc() {
    final s = AramaServisi.instance;
    final chatId = s.bekleyenChatId;
    final tip = s.bekleyenTip;
    if (chatId != null && tip != null && mounted) {
      final baslik = s.bekleyenBaslik ?? 'Arama';
      s.bekleyenChatId = null;
      s.bekleyenTip = null;
      s.bekleyenBaslik = null;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(chatId: chatId, tip: tip, baslik: baslik),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ekranlar = [
      SohbetListesiEkrani(onArkadaslara: () => setState(() => _sekme = 1)),
      const ArkadaslarEkrani(),
      const ProfilEkrani(),
    ];

    return Scaffold(
      body: IndexedStack(index: _sekme, children: ekranlar),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Renkler.zeminDerin,
          border: Border(top: BorderSide(color: Renkler.kenar)),
        ),
        child: NavigationBar(
          selectedIndex: _sekme,
          onDestinationSelected: (i) => setState(() => _sekme = i),
          backgroundColor: Colors.transparent,
          indicatorColor: Renkler.neonSis,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: _RozetliIkon(
                ikon: Icons.forum_outlined,
                seciliIkon: Icons.forum,
                secili: _sekme == 0,
                sayacAkisi: _okunmamisAkisi,
              ),
              label: 'Sohbetler',
            ),
            const NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Arkadaşlar',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

/// Okunmamış sohbet sayısını rozet olarak gösteren ikon.
class _RozetliIkon extends StatelessWidget {
  final IconData ikon;
  final IconData seciliIkon;
  final bool secili;
  final Stream<int> sayacAkisi;
  const _RozetliIkon({
    required this.ikon,
    required this.seciliIkon,
    required this.secili,
    required this.sayacAkisi,
  });

  @override
  Widget build(BuildContext context) {
    final i = Icon(secili ? seciliIkon : ikon);
    return StreamBuilder<int>(
      stream: sayacAkisi,
      builder: (context, snap) {
        final sayi = snap.data ?? 0;
        if (sayi == 0) return i;
        return Badge(
          label: Text('$sayi'),
          backgroundColor: Renkler.neon,
          textColor: Renkler.metinKoyu,
          child: i,
        );
      },
    );
  }
}
