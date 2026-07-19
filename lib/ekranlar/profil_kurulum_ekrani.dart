import 'dart:async';

import 'package:flutter/material.dart';

import '../servisler/kullanici_servisi.dart';
import '../tema.dart';

/// Profil kurulum (FAZ 4.3c): oturumu açık ama profili olmayan kullanıcı
/// (eski hesaplar dahil) görünen ad + benzersiz @kullanıcı adı seçer.
/// Kaydedince AuthGate otomatik olarak AnaKabuk'a düşer.
class ProfilKurulumEkrani extends StatefulWidget {
  const ProfilKurulumEkrani({super.key});

  @override
  State<ProfilKurulumEkrani> createState() => _ProfilKurulumEkraniState();
}

enum _AdDurum { bos, kontrol, musait, dolu, hata }

class _ProfilKurulumEkraniState extends State<ProfilKurulumEkrani> {
  final _adCtrl = TextEditingController();
  final _kadiCtrl = TextEditingController();
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
    _kadiTimer = Timer(const Duration(milliseconds: 450), () async {
      final musait = await _servis.kullaniciAdiMusaitMi(ad);
      if (!mounted || _kadiCtrl.text.trim().toLowerCase() != ad) return;
      setState(() {
        _adDurum = musait ? _AdDurum.musait : _AdDurum.dolu;
        _adNot = musait ? '@$ad müsait' : '@$ad alınmış';
      });
    });
  }

  Future<void> _kaydet() async {
    if (_adDurum == _AdDurum.dolu) {
      setState(() => _hata = 'Bu kullanıcı adı alınmış.');
      return;
    }
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await _servis.profilKur(
        ad: _adCtrl.text,
        kullaniciAdi: _kadiCtrl.text,
      );
      // Başarılı → AuthGate profilVarMi'yi tekrar okuyup AnaKabuk'a geçer.
      // Bu ekran StreamBuilder tarafından otomatik değiştirilecek.
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
      body: Zemin(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: Gradyanlar.accent,
                    borderRadius: Kose.dugme,
                    boxShadow: Golgeler.neonGlow,
                  ),
                  child: const Icon(Icons.waving_hand,
                      color: Renkler.metinKoyu, size: 34),
                ),
                const SizedBox(height: 20),
                Text('Profilini oluştur', style: Yazi.baslik),
                const SizedBox(height: 6),
                Text(
                  'Görünen adını ve seni bulmaları için bir @kullanıcı adı seç.',
                  style: Yazi.kucuk,
                ),
                const SizedBox(height: 28),
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
                TextField(
                  controller: _kadiCtrl,
                  enabled: !_yukleniyor,
                  autocorrect: false,
                  style: Yazi.govde,
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
                  onTap: _yukleniyor ? null : _kaydet,
                  cocuk: _yukleniyor
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Renkler.metinKoyu),
                        )
                      : Text('Devam et', style: Yazi.dugme),
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
