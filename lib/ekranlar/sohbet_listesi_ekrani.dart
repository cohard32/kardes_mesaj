import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/kullanici.dart';
import '../modeller/sohbet.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/kullanici_servisi.dart';
import '../servisler/sohbet_servisi.dart';
import '../tema.dart';
import 'arkadaslar_ekrani.dart';
import 'sohbet_ekrani.dart';

/// Sohbet listesi — ana ekran (FAZ 4.3). Son mesaja göre sıralı sohbetler.
/// Boşsa "Arkadaşlarına git" yönlendirmesi. Bir satıra dokununca sohbet açılır.
class SohbetListesiEkrani extends StatelessWidget {
  /// Alt bardan "Arkadaşlar" sekmesine geçmek için (boş durum butonu).
  final VoidCallback? onArkadaslara;

  const SohbetListesiEkrani({super.key, this.onArkadaslara});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sohbetler'),
        actions: [
          IconButton(
            tooltip: 'Kişi bul',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ArkadaslarEkrani(baslangicSekme: 0),
              ),
            ),
          ),
        ],
      ),
      body: Zemin(
        child: StreamBuilder<List<Sohbet>>(
          stream: SohbetServisi.instance.sohbetleriDinle(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Renkler.neon),
              );
            }
            final sohbetler =
                (snap.data ?? []).where((s) => s.sonMesajZamani != null).toList();
            if (sohbetler.isEmpty) {
              return _BosDurum(onArkadaslara: onArkadaslara);
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: sohbetler.length,
              itemBuilder: (_, i) => _SohbetSatiri(sohbet: sohbetler[i], me: me),
            );
          },
        ),
      ),
    );
  }
}

/// Tek sohbet satırı. Karşı tarafın profilini canlı dinler (çevrimiçi + ad).
class _SohbetSatiri extends StatelessWidget {
  final Sohbet sohbet;
  final String me;
  const _SohbetSatiri({required this.sohbet, required this.me});

  String _saat(DateTime? t) {
    if (t == null) return '';
    final s = t.hour.toString().padLeft(2, '0');
    final d = t.minute.toString().padLeft(2, '0');
    return '$s:$d';
  }

  @override
  Widget build(BuildContext context) {
    final digerUid = sohbet.digerKatilimci(me);
    final okunmamis = sohbet.benimOkunmamis(me);
    final benYazdim = sohbet.sonMesajGonderen == me;

    return StreamBuilder<Kullanici>(
      stream: KullaniciServisi.instance.profilDinle(digerUid),
      builder: (context, snap) {
        final k = snap.data ?? Kullanici.bos(digerUid);
        final yaziyor = sohbet.digerYaziyor(me);
        final onizleme = yaziyor
            ? 'yazıyor...'
            : (benYazdim ? '↩ ${sohbet.sonMesaj}' : sohbet.sonMesaj);

        return InkWell(
          borderRadius: Kose.kartKose,
          onTap: () => sohbetiAc(context, k),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: Gradyanlar.yuzey,
              borderRadius: Kose.kartKose,
              border: Border.all(
                color: okunmamis > 0 ? Renkler.kenarGuclu : Renkler.kenar,
              ),
            ),
            child: Row(
              children: [
                KullaniciAvatar(kullanici: k, boyut: 52, cevrimiciGoster: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.ad, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Yazi.isim),
                      const SizedBox(height: 2),
                      Text(
                        onizleme,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: yaziyor
                            ? Yazi.neonKucuk
                            : (okunmamis > 0
                                ? Yazi.stil(13, FontWeight.w600, Renkler.metin)
                                : Yazi.kucuk),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_saat(sohbet.sonMesajZamani), style: Yazi.zaman),
                    const SizedBox(height: 6),
                    if (okunmamis > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: Kutular.accent(
                          kose: BorderRadius.circular(11),
                          golge: const [],
                        ),
                        child: Text(
                          '$okunmamis',
                          style:
                              Yazi.stil(11, FontWeight.w800, Renkler.metinKoyu),
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BosDurum extends StatelessWidget {
  final VoidCallback? onArkadaslara;
  const _BosDurum({this.onArkadaslara});

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
            child: const Icon(Icons.forum_outlined,
                size: 38, color: Renkler.neon),
          ),
          const SizedBox(height: 16),
          Text('Henüz sohbet yok.', style: Yazi.isim),
          const SizedBox(height: 6),
          Text('Bir arkadaşınla sohbete başla 👋',
              textAlign: TextAlign.center, style: Yazi.kucuk),
          const SizedBox(height: 20),
          Uc3DDugme(
            onTap: onArkadaslara,
            cocuk: Text('Arkadaşlarım', style: Yazi.dugme),
          ),
        ],
      ),
    );
  }
}
