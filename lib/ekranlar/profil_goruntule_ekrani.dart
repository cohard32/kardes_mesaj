import 'package:flutter/material.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/kullanici.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';
import 'sohbet_ekrani.dart';

/// Başka bir kullanıcının profilini görüntüleme (FAZ 4 cila).
/// Avatar + ad + @kullanıcı adı + bio + çevrimiçi; ilişki durumuna göre
/// aksiyon (Mesaj gönder / Arkadaş ekle / İstek gönderildi / Kabul et).
class ProfilGoruntuleEkrani extends StatefulWidget {
  final Kullanici kullanici;
  const ProfilGoruntuleEkrani({super.key, required this.kullanici});

  @override
  State<ProfilGoruntuleEkrani> createState() => _ProfilGoruntuleEkraniState();
}

class _ProfilGoruntuleEkraniState extends State<ProfilGoruntuleEkrani> {
  final _arkadas = ArkadasServisi.instance;
  IliskiDurumu? _durum;
  bool _islemde = false;

  @override
  void initState() {
    super.initState();
    _durumYukle();
  }

  Future<void> _durumYukle() async {
    try {
      final d = await _arkadas.iliskiDurumu(widget.kullanici.uid);
      if (mounted) setState(() => _durum = d);
    } catch (_) {
      // Hata → dönmeyi durdur, "Arkadaş ekle" göster (sonsuz loading olmasın)
      if (mounted) setState(() => _durum = IliskiDurumu.yok);
    }
  }

  Future<void> _istekGonder() async {
    setState(() => _islemde = true);
    await _arkadas.istekGonder(widget.kullanici.uid);
    if (!mounted) return;
    setState(() => _islemde = false);
    await _durumYukle();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İstek gönderildi ✓')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Zemin(
        child: StreamBuilder<Kullanici>(
          stream: KullaniciServisi.instance.profilDinle(widget.kullanici.uid),
          initialData: widget.kullanici,
          builder: (context, snap) {
            final k = snap.data ?? widget.kullanici;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 12),
                Center(
                  child: KullaniciAvatar(
                    kullanici: k,
                    boyut: 120,
                    cevrimiciGoster: true,
                  ),
                ),
                const SizedBox(height: 16),
                Center(child: Text(k.ad, style: Yazi.baslik)),
                const SizedBox(height: 4),
                Center(
                  child: Text('@${k.kullaniciAdi}', style: Yazi.neonKucuk),
                ),
                if (k.cevrimici) ...[
                  const SizedBox(height: 6),
                  Center(child: Text('çevrimiçi', style: Yazi.kucuk)),
                ],
                if ((k.bio ?? '').isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: Kutular.yuzey(kose: Kose.kartKose),
                    child: Text(k.bio!, style: Yazi.govde),
                  ),
                ],
                const SizedBox(height: 28),
                _aksiyon(k),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _aksiyon(Kullanici k) {
    if (_durum == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Renkler.neon),
        ),
      );
    }
    final yukleniyor = _islemde
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Renkler.metinKoyu,
            ),
          )
        : null;

    switch (_durum!) {
      case IliskiDurumu.arkadas:
        return Uc3DDugme(
          genis: true,
          onTap: () => sohbetiAc(context, k),
          cocuk: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble, size: 20, color: Renkler.metinKoyu),
              const SizedBox(width: 8),
              Text('Mesaj gönder', style: Yazi.dugme),
            ],
          ),
        );
      case IliskiDurumu.yok:
        return Uc3DDugme(
          genis: true,
          onTap: _islemde ? null : _istekGonder,
          cocuk:
              yukleniyor ??
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person_add_alt_1,
                    size: 20,
                    color: Renkler.metinKoyu,
                  ),
                  const SizedBox(width: 8),
                  Text('Arkadaş ekle', style: Yazi.dugme),
                ],
              ),
        );
      case IliskiDurumu.istekGeldi:
        return Uc3DDugme(
          genis: true,
          onTap: _islemde ? null : _istekGonder, // ters istek varsa auto-kabul
          cocuk: yukleniyor ?? Text('İsteği kabul et', style: Yazi.dugme),
        );
      case IliskiDurumu.istekGonderdim:
        return Uc3DDugme(
          genis: true,
          ikincil: true,
          onTap: null,
          cocuk: Text('İstek gönderildi', style: Yazi.etiket),
        );
      case IliskiDurumu.benim:
        return const SizedBox.shrink();
    }
  }
}
