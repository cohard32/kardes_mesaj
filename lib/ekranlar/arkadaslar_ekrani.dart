import 'package:flutter/material.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/kullanici.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';
import 'kullanici_ara_ekrani.dart';
import 'profil_goruntule_ekrani.dart';
import 'sohbet_ekrani.dart';

/// Arkadaşlar + istekler (FAZ 4.3). İki sekme: "Arkadaşlar" ve "İstekler".
/// Üstte kişi bul (@ arama) butonu. İstek rozetleri canlı güncellenir.
class ArkadaslarEkrani extends StatelessWidget {
  final int baslangicSekme;
  const ArkadaslarEkrani({super.key, this.baslangicSekme = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: baslangicSekme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Arkadaşlar'),
          actions: [
            IconButton(
              tooltip: 'Kişi bul',
              icon: const Icon(Icons.person_search_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const KullaniciAraEkrani(),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: Renkler.neon,
            labelColor: Renkler.neon,
            unselectedLabelColor: Renkler.metinSoluk,
            labelStyle: Yazi.etiket,
            tabs: [
              const Tab(text: 'Arkadaşlar'),
              Tab(
                child: StreamBuilder<List<ArkadaslikIstegi>>(
                  stream: ArkadasServisi.instance.gelenIstekler(),
                  builder: (context, snap) {
                    final adet = snap.data?.length ?? 0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('İstekler'),
                        if (adet > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: Kutular.accent(
                              kose: BorderRadius.circular(10),
                              golge: const [],
                            ),
                            child: Text('$adet',
                                style: Yazi.stil(
                                    11, FontWeight.w800, Renkler.metinKoyu)),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: const Zemin(
          child: TabBarView(
            children: [_ArkadasListesi(), _IstekListesi()],
          ),
        ),
      ),
    );
  }
}

/// Sekme 1 — arkadaş listesi. Dokununca sohbet açılır; menüden çıkarılır.
class _ArkadasListesi extends StatelessWidget {
  const _ArkadasListesi();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Kullanici>>(
      stream: ArkadasServisi.instance.arkadaslar(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Renkler.neon));
        }
        final liste = snap.data ?? [];
        if (liste.isEmpty) {
          return const _Bilgi(
            ikon: Icons.group_outlined,
            yazi: 'Henüz arkadaşın yok.\nÜstteki 🔍 ile @kullanıcı adı ara.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: liste.length,
          itemBuilder: (_, i) => _ArkadasSatiri(kullanici: liste[i]),
        );
      },
    );
  }
}

class _ArkadasSatiri extends StatelessWidget {
  final Kullanici kullanici;
  const _ArkadasSatiri({required this.kullanici});

  Future<void> _cikar(BuildContext context) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Arkadaşlıktan çıkar'),
        content: Text('@${kullanici.kullaniciAdi} arkadaşlıktan çıkarılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkar',
                style: TextStyle(color: Renkler.tehlike)),
          ),
        ],
      ),
    );
    if (onay == true) {
      await ArkadasServisi.instance.arkadasCikar(kullanici.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: Gradyanlar.yuzey,
        borderRadius: Kose.kartKose,
        border: Border.all(color: Renkler.kenar),
      ),
      child: ListTile(
        onTap: () => sohbetiAc(context, kullanici),
        leading:
            KullaniciAvatar(kullanici: kullanici, boyut: 46, cevrimiciGoster: true),
        title: Text(kullanici.ad, style: Yazi.isim),
        subtitle: Text('@${kullanici.kullaniciAdi}', style: Yazi.kucuk),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Renkler.metinSoluk),
          color: Renkler.yuzey,
          onSelected: (v) {
            if (v == 'mesaj') sohbetiAc(context, kullanici);
            if (v == 'profil') {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ProfilGoruntuleEkrani(kullanici: kullanici),
              ));
            }
            if (v == 'cikar') _cikar(context);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'mesaj', child: Text('Mesaj gönder')),
            PopupMenuItem(value: 'profil', child: Text('Profili gör')),
            PopupMenuItem(value: 'cikar', child: Text('Arkadaşlıktan çıkar')),
          ],
        ),
      ),
    );
  }
}

/// Sekme 2 — gelen + giden istekler.
class _IstekListesi extends StatelessWidget {
  const _IstekListesi();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ArkadaslikIstegi>>(
      stream: ArkadasServisi.instance.gelenIstekler(),
      builder: (context, gelenSnap) {
        return StreamBuilder<List<ArkadaslikIstegi>>(
          stream: ArkadasServisi.instance.gidenIstekler(),
          builder: (context, gidenSnap) {
            final gelen = gelenSnap.data ?? [];
            final giden = gidenSnap.data ?? [];
            if (gelen.isEmpty && giden.isEmpty) {
              return const _Bilgi(
                ikon: Icons.mark_email_unread_outlined,
                yazi: 'Bekleyen istek yok.',
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                if (gelen.isNotEmpty) ...[
                  _Baslik('Gelen istekler (${gelen.length})'),
                  for (final i in gelen)
                    _IstekSatiri(istek: i, gelen: true, digerUid: i.gonderenUid),
                ],
                if (giden.isNotEmpty) ...[
                  _Baslik('Gönderdiklerim (${giden.length})'),
                  for (final i in giden)
                    _IstekSatiri(istek: i, gelen: false, digerUid: i.alanUid),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _IstekSatiri extends StatelessWidget {
  final ArkadaslikIstegi istek;
  final bool gelen;
  final String digerUid;
  const _IstekSatiri({
    required this.istek,
    required this.gelen,
    required this.digerUid,
  });

  @override
  Widget build(BuildContext context) {
    final arkadas = ArkadasServisi.instance;
    return FutureBuilder<Kullanici?>(
      future: KullaniciServisi.instance.profilGetir(digerUid),
      builder: (context, snap) {
        final k = snap.data ?? Kullanici.bos(digerUid);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: Gradyanlar.yuzey,
            borderRadius: Kose.kartKose,
            border: Border.all(color: Renkler.kenar),
          ),
          child: Row(
            children: [
              KullaniciAvatar(kullanici: k, boyut: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k.ad, style: Yazi.isim),
                    Text('@${k.kullaniciAdi}', style: Yazi.kucuk),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (gelen) ...[
                Uc3DDugme(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onTap: () => arkadas.kabulEt(istek),
                  cocuk: Text('Kabul',
                      style: Yazi.stil(12, FontWeight.w800, Renkler.metinKoyu)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Reddet',
                  icon: const Icon(Icons.close, color: Renkler.tehlike),
                  onPressed: () => arkadas.reddet(istek),
                ),
              ] else
                TextButton(
                  onPressed: () => arkadas.iptalEt(istek),
                  child: const Text('İptal',
                      style: TextStyle(color: Renkler.metinSoluk)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Baslik extends StatelessWidget {
  final String yazi;
  const _Baslik(this.yazi);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(yazi, style: Yazi.kucuk),
      );
}

class _Bilgi extends StatelessWidget {
  final IconData ikon;
  final String yazi;
  const _Bilgi({required this.ikon, required this.yazi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Renkler.neonSis,
              borderRadius: Kose.kartKose,
              border: Border.all(color: Renkler.kenar),
            ),
            child: Icon(ikon, size: 38, color: Renkler.neon),
          ),
          const SizedBox(height: 16),
          Text(yazi, textAlign: TextAlign.center, style: Yazi.kucuk),
        ],
      ),
    );
  }
}
