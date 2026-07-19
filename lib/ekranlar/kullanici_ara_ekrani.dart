import 'dart:async';

import 'package:flutter/material.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/kullanici.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';
import 'profil_goruntule_ekrani.dart';

/// Kullanıcı adıyla (@) arama + arkadaş ekleme (FAZ 4.2).
class KullaniciAraEkrani extends StatefulWidget {
  const KullaniciAraEkrani({super.key});

  @override
  State<KullaniciAraEkrani> createState() => _KullaniciAraEkraniState();
}

class _KullaniciAraEkraniState extends State<KullaniciAraEkrani> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _yukleniyor = false;
  List<Kullanici> _sonuclar = [];
  bool _arandi = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _degisti(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _ara);
  }

  Future<void> _ara() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _sonuclar = [];
        _arandi = false;
      });
      return;
    }
    setState(() => _yukleniyor = true);
    final r = await KullaniciServisi.instance.kullaniciAra(q);
    if (!mounted) return;
    setState(() {
      _sonuclar = r;
      _yukleniyor = false;
      _arandi = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kullanıcı bul')),
      body: Zemin(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                autocorrect: false,
                onChanged: _degisti,
                style: Yazi.govde,
                decoration: const InputDecoration(
                  hintText: 'kullanıcı adı ara…',
                  prefixText: '@',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (_yukleniyor)
              const LinearProgressIndicator(
                color: Renkler.neon,
                backgroundColor: Renkler.yuzey,
              ),
            Expanded(child: _govde()),
          ],
        ),
      ),
    );
  }

  Widget _govde() {
    if (!_arandi) {
      return _bilgi(Icons.alternate_email, 'Arkadaşının kullanıcı adını yaz.');
    }
    if (_sonuclar.isEmpty) {
      return _bilgi(Icons.search_off, 'Kullanıcı bulunamadı.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _sonuclar.length,
      itemBuilder: (_, i) => _SonucSatiri(kullanici: _sonuclar[i]),
    );
  }

  Widget _bilgi(IconData ikon, String yazi) {
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
          Text(yazi, style: Yazi.kucuk),
        ],
      ),
    );
  }
}

/// Tek arama sonucu — ilişki durumuna göre buton.
class _SonucSatiri extends StatefulWidget {
  final Kullanici kullanici;
  const _SonucSatiri({required this.kullanici});

  @override
  State<_SonucSatiri> createState() => _SonucSatiriState();
}

class _SonucSatiriState extends State<_SonucSatiri> {
  final _arkadas = ArkadasServisi.instance;
  IliskiDurumu? _durum;
  bool _islemde = false;

  @override
  void initState() {
    super.initState();
    _durumYukle();
  }

  Future<void> _durumYukle() async {
    final d = await _arkadas.iliskiDurumu(widget.kullanici.uid);
    if (mounted) setState(() => _durum = d);
  }

  Future<void> _istekGonder() async {
    setState(() => _islemde = true);
    await _arkadas.istekGonder(widget.kullanici.uid);
    if (!mounted) return;
    setState(() {
      _islemde = false;
      _durum = IliskiDurumu.istekGonderdim;
    });
  }

  Future<void> _kabulEt() async {
    setState(() => _islemde = true);
    // Bana gelen isteği bul → kabul et
    final me = widget.kullanici; // gönderen
    await _arkadas.istekGonder(me.uid); // ters istek varsa doğrudan kabul eder
    if (!mounted) return;
    setState(() {
      _islemde = false;
      _durum = IliskiDurumu.arkadas;
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kullanici;
    return InkWell(
      borderRadius: Kose.kartKose,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfilGoruntuleEkrani(kullanici: k),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: Gradyanlar.yuzey,
          borderRadius: Kose.kartKose,
          border: Border.all(color: Renkler.kenar),
        ),
        child: Row(
          children: [
            KullaniciAvatar(kullanici: k, boyut: 48),
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
            _buton(),
          ],
        ),
      ),
    );
  }

  Widget _buton() {
    if (_durum == null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Renkler.metinSoluk,
        ),
      );
    }
    final yukleniyor = _islemde
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Renkler.metinKoyu,
            ),
          )
        : null;

    switch (_durum!) {
      case IliskiDurumu.yok:
        return Uc3DDugme(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          onTap: _islemde ? null : _istekGonder,
          cocuk:
              yukleniyor ??
              Text(
                'Ekle',
                style: Yazi.stil(13, FontWeight.w800, Renkler.metinKoyu),
              ),
        );
      case IliskiDurumu.istekGeldi:
        return Uc3DDugme(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          onTap: _islemde ? null : _kabulEt,
          cocuk:
              yukleniyor ??
              Text(
                'Kabul et',
                style: Yazi.stil(13, FontWeight.w800, Renkler.metinKoyu),
              ),
        );
      case IliskiDurumu.istekGonderdim:
        return _etiket('İstek gönderildi', Renkler.metinSoluk);
      case IliskiDurumu.arkadas:
        return _etiket('Arkadaşsınız', Renkler.neon);
      case IliskiDurumu.benim:
        return _etiket('Sen', Renkler.metinSoluk);
    }
  }

  Widget _etiket(String yazi, Color renk) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(yazi, style: Yazi.stil(12, FontWeight.w700, renk)),
  );
}
