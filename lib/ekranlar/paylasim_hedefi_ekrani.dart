import 'package:flutter/material.dart';

import '../modeller/kullanici.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/paylasim_servisi.dart';
import '../servisler/sohbet_servisi.dart';
import '../tema.dart';
import '../yardimcilar/tr_metin.dart';
import 'sohbet_ekrani.dart';

/// "Paylaş → ROY MESSANGER" ile gelen içerik için "Kime gönderilsin?":
/// arkadaş listesi (aramalı). Seçilen kişinin sohbeti açılır ve içerik
/// oraya aktarılır (metin yazma alanına, foto/video önizleme ekranına,
/// belge onaya).
class PaylasimHedefiEkrani extends StatefulWidget {
  final GelenPaylasim paylasim;
  const PaylasimHedefiEkrani({super.key, required this.paylasim});

  @override
  State<PaylasimHedefiEkrani> createState() => _PaylasimHedefiEkraniState();
}

class _PaylasimHedefiEkraniState extends State<PaylasimHedefiEkrani> {
  late final Stream<List<Kullanici>> _arkadaslar =
      ArkadasServisi.instance.arkadaslar();
  final _ara = TextEditingController();
  bool _aciliyor = false;

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  Future<void> _sec(Kullanici k) async {
    if (_aciliyor) return;
    setState(() => _aciliyor = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chatId = await SohbetServisi.instance.sohbetAcOrGetir(k.uid);
      if (!mounted) return;
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SohbetEkrani(
            chatId: chatId,
            karsi: k,
            paylasim: widget.paylasim,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aciliyor = false);
      messenger.showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kime gönderilsin?')),
      body: Zemin(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
              child: Row(
                children: [
                  Icon(Icons.ios_share_rounded, color: Renkler.neon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.paylasim.ozet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Yazi.govde,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ara,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Kişi ara…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_aciliyor)
              LinearProgressIndicator(
                color: Renkler.neon,
                backgroundColor: Renkler.yuzey,
              ),
            Expanded(
              child: StreamBuilder<List<Kullanici>>(
                stream: _arkadaslar,
                builder: (_, s) {
                  if (!s.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: Renkler.neon),
                    );
                  }
                  final sorgu = aramaIcinSadele(_ara.text.trim());
                  final liste = [
                    for (final k in s.data!)
                      if (sorgu.isEmpty ||
                          aramaIcinSadele(k.ad).contains(sorgu) ||
                          aramaIcinSadele(k.kullaniciAdi).contains(sorgu))
                        k,
                  ]..sort((a, b) =>
                      aramaIcinSadele(a.ad).compareTo(aramaIcinSadele(b.ad)));
                  if (liste.isEmpty) {
                    return Center(
                      child: Text('Kimse bulunamadı', style: Yazi.kucuk),
                    );
                  }
                  return ListView.builder(
                    itemCount: liste.length,
                    itemBuilder: (_, i) {
                      final k = liste[i];
                      return ListTile(
                        leading: KullaniciAvatar(kullanici: k, boyut: 44),
                        title: Text(k.ad, style: Yazi.isim),
                        subtitle: Text('@${k.kullaniciAdi}', style: Yazi.kucuk),
                        trailing: Icon(Icons.send_rounded, color: Renkler.neon),
                        onTap: _aciliyor ? null : () => _sec(k),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
