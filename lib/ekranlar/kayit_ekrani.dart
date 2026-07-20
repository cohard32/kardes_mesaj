import 'dart:async';

import 'package:flutter/material.dart';

import '../servisler/kullanici_servisi.dart';
import '../tema.dart';

/// Kayıt ekranı (FAZ 4.1): ad + benzersiz @kullanıcı adı (canlı kontrol) +
/// e-posta + şifre. Kullanıcı adı yarış-güvenli (transaction) rezerve edilir.
class KayitEkrani extends StatefulWidget {
  const KayitEkrani({super.key});

  @override
  State<KayitEkrani> createState() => _KayitEkraniState();
}

enum _AdDurum { bos, kontrol, musait, dolu, hata }

class _KayitEkraniState extends State<KayitEkrani> {
  final _adCtrl = TextEditingController();
  final _kadiCtrl = TextEditingController();
  final _epostaCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  final _sifre2Ctrl = TextEditingController();

  final _servis = KullaniciServisi.instance;

  Timer? _kadiTimer;
  _AdDurum _adDurum = _AdDurum.bos;
  String _adNot = '';
  bool _yukleniyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _kadiCtrl.addListener(_kullaniciAdiDegisti);
  }

  @override
  void dispose() {
    _kadiTimer?.cancel();
    _adCtrl.dispose();
    _kadiCtrl.dispose();
    _epostaCtrl.dispose();
    _sifreCtrl.dispose();
    _sifre2Ctrl.dispose();
    super.dispose();
  }

  void _kullaniciAdiDegisti() {
    _kadiTimer?.cancel();
    final ad = _kadiCtrl.text.trim().toLowerCase();
    if (ad.isEmpty) {
      setState(() {
        _adDurum = _AdDurum.bos;
        _adNot = '';
      });
      return;
    }
    final bicimHata = _servis.kullaniciAdiHatasi(ad);
    if (bicimHata != null) {
      setState(() {
        _adDurum = _AdDurum.hata;
        _adNot = bicimHata;
      });
      return;
    }
    setState(() {
      _adDurum = _AdDurum.kontrol;
      _adNot = 'kontrol ediliyor…';
    });
    // Debounce: yazma durunca sor
    _kadiTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final musait = await _servis.kullaniciAdiMusaitMi(ad);
        if (!mounted || _kadiCtrl.text.trim().toLowerCase() != ad) return;
        setState(() {
          _adDurum = musait ? _AdDurum.musait : _AdDurum.dolu;
          _adNot = musait ? '@$ad müsait' : '@$ad alınmış';
        });
      } catch (_) {
        // Kontrol edilemedi (ağ/izin) → SONSUZ DÖNME OLMASIN.
        // Kayıt yine denenebilir: benzersizlik transaction ile garanti.
        if (!mounted || _kadiCtrl.text.trim().toLowerCase() != ad) return;
        setState(() {
          _adDurum = _AdDurum.hata;
          _adNot = 'Kontrol edilemedi — yine de deneyebilirsin';
        });
      }
    });
  }

  Future<void> _kayitOl() async {
    if (_sifreCtrl.text != _sifre2Ctrl.text) {
      setState(() => _hata = 'Şifreler eşleşmiyor.');
      return;
    }
    if (_adDurum == _AdDurum.dolu) {
      setState(() => _hata = 'Bu kullanıcı adı alınmış.');
      return;
    }
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await _servis.kayitOl(
        ad: _adCtrl.text,
        kullaniciAdi: _kadiCtrl.text,
        eposta: _epostaCtrl.text,
        sifre: _sifreCtrl.text,
      );
      // Başarılı → AuthGate otomatik yönlendirir. Kayıt ekranını kapat.
      if (mounted) Navigator.of(context).pop();
    } on KullaniciHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } catch (_) {
      if (mounted) setState(() => _hata = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıt Ol')),
      body: Zemin(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Hesabını oluştur', style: Yazi.baslik),
                const SizedBox(height: 6),
                Text('Kullanıcı adınla arkadaşların seni bulur.',
                    style: Yazi.kucuk),
                const SizedBox(height: 24),

                TextField(
                  controller: _adCtrl,
                  textCapitalization: TextCapitalization.words,
                  enabled: !_yukleniyor,
                  style: Yazi.govde,
                  decoration: const InputDecoration(
                    hintText: 'Adın (görünen isim)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 14),

                // Kullanıcı adı + canlı durum
                TextField(
                  controller: _kadiCtrl,
                  enabled: !_yukleniyor,
                  autocorrect: false,
                  style: Yazi.govde,
                  inputFormatters: const [],
                  decoration: InputDecoration(
                    hintText: 'kullaniciadi',
                    prefixText: '@',
                    prefixStyle: Yazi.govde,
                    prefixIcon: const Icon(Icons.alternate_email),
                    suffixIcon: _adDurumIkonu(),
                  ),
                ),
                if (_adNot.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 6),
                    child: Text(_adNot, style: _adNotStil()),
                  ),
                const SizedBox(height: 14),

                TextField(
                  controller: _epostaCtrl,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_yukleniyor,
                  autocorrect: false,
                  style: Yazi.govde,
                  decoration: const InputDecoration(
                    hintText: 'E-posta',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _sifreCtrl,
                  obscureText: true,
                  enabled: !_yukleniyor,
                  style: Yazi.govde,
                  decoration: const InputDecoration(
                    hintText: 'Şifre (en az 6 karakter)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _sifre2Ctrl,
                  obscureText: true,
                  enabled: !_yukleniyor,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _kayitOl(),
                  style: Yazi.govde,
                  decoration: const InputDecoration(
                    hintText: 'Şifre (tekrar)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),

                if (_hata != null) ...[
                  const SizedBox(height: 16),
                  Text(_hata!,
                      textAlign: TextAlign.center,
                      style: Yazi.stil(13, FontWeight.w600, Renkler.tehlike)),
                ],

                const SizedBox(height: 26),
                Uc3DDugme(
                  genis: true,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  onTap: _yukleniyor ? null : _kayitOl,
                  cocuk: _yukleniyor
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Renkler.metinKoyu),
                        )
                      : Text('Kayıt Ol', style: Yazi.dugme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _adDurumIkonu() {
    switch (_adDurum) {
      case _AdDurum.kontrol:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Renkler.metinSoluk),
          ),
        );
      case _AdDurum.musait:
        return const Icon(Icons.check_circle, color: Renkler.neon);
      case _AdDurum.dolu:
      case _AdDurum.hata:
        return const Icon(Icons.cancel, color: Renkler.tehlike);
      case _AdDurum.bos:
        return null;
    }
  }

  TextStyle _adNotStil() {
    final renk = switch (_adDurum) {
      _AdDurum.musait => Renkler.neon,
      _AdDurum.dolu || _AdDurum.hata => Renkler.tehlike,
      _ => Renkler.metinSoluk,
    };
    return Yazi.stil(12, FontWeight.w600, renk);
  }
}
