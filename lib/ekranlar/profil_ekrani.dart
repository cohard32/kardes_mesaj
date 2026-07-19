import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../modeller/kullanici.dart';
import '../modeller/mesaj.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/kullanici_servisi.dart';
import '../servisler/medya_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../tema.dart';
import 'ayarlar_ekrani.dart';

/// Kendi profilim (FAZ 4.3): avatar (foto yükle), ad + bio düzenle,
/// @kullanıcı adı (kopyalanır) + QR kod (başkaları eklesin diye).
/// Ayarlar ve çıkış da buradadır.
class ProfilEkrani extends StatelessWidget {
  const ProfilEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    final akis = KullaniciServisi.instance.benimProfilim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani()),
            ),
          ),
        ],
      ),
      body: Zemin(
        child: akis == null
            ? const Center(child: Text('Oturum yok'))
            : StreamBuilder<Kullanici>(
                stream: akis,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Profil yüklenemedi. Bağlantını kontrol et.',
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: Renkler.neon));
                  }
                  return _ProfilGovde(kullanici: snap.data!);
                },
              ),
      ),
    );
  }
}

class _ProfilGovde extends StatefulWidget {
  final Kullanici kullanici;
  const _ProfilGovde({required this.kullanici});

  @override
  State<_ProfilGovde> createState() => _ProfilGovdeState();
}

class _ProfilGovdeState extends State<_ProfilGovde> {
  bool _fotoYukleniyor = false;

  Future<void> _fotoDegistir() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (x == null) return;
    setState(() => _fotoYukleniyor = true);
    final url = await MedyaServisi.instance.yukle(File(x.path), MesajTipi.resim);
    if (url != null) {
      await KullaniciServisi.instance.profilGuncelle(fotoUrl: url);
    }
    if (!mounted) return;
    setState(() => _fotoYukleniyor = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf yüklenemedi.')),
      );
    }
  }

  Future<void> _duzenle() async {
    final adCtrl = TextEditingController(text: widget.kullanici.ad);
    final bioCtrl = TextEditingController(text: widget.kullanici.bio ?? '');
    final kaydet = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDlg) {
          final ad = adCtrl.text.trim();
          final gecerli = ad.isNotEmpty && ad.length <= 30;
          return AlertDialog(
            title: const Text('Profili düzenle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // @kullanıcı adı — SABİT (şimdilik değiştirilemez)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: Kutular.duzYuzey(kose: Kose.alan, kenarli: true),
                  child: Row(
                    children: [
                      const Icon(Icons.alternate_email,
                          size: 18, color: Renkler.metinSoluk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('@${widget.kullanici.kullaniciAdi}',
                            style: Yazi.govde),
                      ),
                      const Icon(Icons.lock_outline,
                          size: 16, color: Renkler.metinSoluk),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 5, bottom: 10),
                  child: Text('Kullanıcı adı değiştirilemez', style: Yazi.zaman),
                ),
                // Görünen ad — düzenlenebilir + doğrulama
                TextField(
                  controller: adCtrl,
                  style: Yazi.govde,
                  autofocus: true,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setDlg(() {}),
                  decoration: InputDecoration(
                    labelText: 'Görünen ad',
                    counterText: '',
                    errorText: ad.isEmpty ? 'Ad boş olamaz' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioCtrl,
                  style: Yazi.govde,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 140,
                  decoration:
                      const InputDecoration(labelText: 'Hakkında (isteğe bağlı)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: gecerli ? () => Navigator.pop(dctx, true) : null,
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
    if (kaydet == true) {
      await KullaniciServisi.instance.profilGuncelle(
        ad: adCtrl.text.trim(),
        bio: bioCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil güncellendi ✓')),
        );
      }
    }
    adCtrl.dispose();
    bioCtrl.dispose();
  }

  Future<void> _cikis() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Çıkış yap'),
        content: const Text('Hesabından çıkmak istiyor musun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış',
                style: TextStyle(color: Renkler.tehlike)),
          ),
        ],
      ),
    );
    if (onay == true) {
      await PresenceServisi.instance.cevrimdisiYap();
      await FirebaseAuth.instance.signOut();
    }
  }

  void _qrGoster() {
    final k = widget.kullanici;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('@${k.kullaniciAdi}', style: Yazi.baslikOrta),
              const SizedBox(height: 4),
              Text('Bu kodu okutan seni ekleyebilir', style: Yazi.kucuk),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Renkler.metin,
                  borderRadius: Kose.kartKose,
                ),
                child: QrImageView(
                  data: 'kardesmesaj:@${k.kullaniciAdi}',
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Renkler.metin,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Renkler.zeminDerin,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Renkler.zeminDerin,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _kullaniciAdiKopyala() {
    Clipboard.setData(ClipboardData(text: '@${widget.kullanici.kullaniciAdi}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kullanıcı adı kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kullanici;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Stack(
            children: [
              KullaniciAvatar(kullanici: k, boyut: 120),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _fotoYukleniyor ? null : _fotoDegistir,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: Gradyanlar.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Renkler.zemin, width: 3),
                      boxShadow: Golgeler.neonGlow,
                    ),
                    child: _fotoYukleniyor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Renkler.metinKoyu),
                          )
                        : const Icon(Icons.camera_alt,
                            size: 18, color: Renkler.metinKoyu),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(k.ad, style: Yazi.baslik)),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            onTap: _kullaniciAdiKopyala,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('@${k.kullaniciAdi}', style: Yazi.neonKucuk),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 13, color: Renkler.metinSoluk),
              ],
            ),
          ),
        ),
        if ((k.bio ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: Kutular.yuzey(kose: Kose.kartKose),
            child: Text(k.bio!, style: Yazi.govde),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Uc3DDugme(
                genis: true,
                ikincil: true,
                onTap: _duzenle,
                cocuk: Text('Düzenle', style: Yazi.etiket),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Uc3DDugme(
                genis: true,
                onTap: _qrGoster,
                cocuk: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_2,
                        size: 20, color: Renkler.metinKoyu),
                    const SizedBox(width: 8),
                    Text('QR kodum', style: Yazi.dugme),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Ayarlar'),
                trailing: const Icon(Icons.chevron_right,
                    color: Renkler.metinSoluk),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const AyarlarEkrani()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: Renkler.tehlike),
                title: const Text('Çıkış yap',
                    style: TextStyle(color: Renkler.tehlike)),
                onTap: _cikis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
