import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../modeller/mesaj.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/guncelleme_servisi.dart';
import '../servisler/mesaj_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../tema.dart';
import 'ayarlar_ekrani.dart';

/// Ana sohbet ekranı. İki kişilik tek sohbet.
/// Kendi mesajların sağda mavi (#00b0ff), kardeşininki solda gri (#1c1c1c).
class SohbetEkrani extends StatefulWidget {
  const SohbetEkrani({super.key});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani>
    with WidgetsBindingObserver {
  final _mesajCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _servis = MesajServisi.instance;
  final _presence = PresenceServisi.instance;
  final _resimSecici = ImagePicker();
  final _kayitci = AudioRecorder();

  Timer? _yaziyorTimer;
  bool _yaziyorGonderildi = false;
  bool _kayitYapiliyor = false;
  bool _yukleniyor = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BildirimServisi.instance.tokenKaydet();
    _presence.cevrimiciYap();
    _mesajCtrl.addListener(_yaziyorDinle);
    _guncellemeKontrol();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yaziyorTimer?.cancel();
    _presence.cevrimdisiYap();
    _kayitci.dispose();
    _mesajCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presence.cevrimiciYap();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _presence.cevrimdisiYap();
    }
  }

  // GitHub'da yeni sürüm varsa otomatik indirip kurulumu başlatır.
  Future<void> _guncellemeKontrol() async {
    final bilgi = await GuncellemeServisi.instance.kontrolEt();
    if (bilgi == null || !mounted) return;

    final ilerleme = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: Text('Güncelleme indiriliyor (v${bilgi.surum})'),
        content: ValueListenableBuilder<double>(
          valueListenable: ilerleme,
          builder: (_, yuzde, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: yuzde > 0 ? yuzde : null,
                color: Renkler.accent,
                backgroundColor: Renkler.giris,
              ),
              const SizedBox(height: 12),
              Text('%${(yuzde * 100).toStringAsFixed(0)}'),
            ],
          ),
        ),
      ),
    );

    try {
      await GuncellemeServisi.instance.indirVeKur(
        bilgi.apkUrl,
        (y) => ilerleme.value = y,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme indirilemedi: $e')),
        );
      }
    }
  }

  void _yaziyorDinle() {
    final bos = _mesajCtrl.text.trim().isEmpty;
    if (!bos && !_yaziyorGonderildi) {
      _yaziyorGonderildi = true;
      _presence.yaziyorAyarla(true);
    }
    _yaziyorTimer?.cancel();
    _yaziyorTimer = Timer(const Duration(seconds: 2), () {
      _yaziyorGonderildi = false;
      _presence.yaziyorAyarla(false);
    });
  }

  Future<void> _gonder() async {
    final metin = _mesajCtrl.text;
    if (metin.trim().isEmpty) return;
    _mesajCtrl.clear();
    _yaziyorTimer?.cancel();
    _yaziyorGonderildi = false;
    _presence.yaziyorAyarla(false);
    await _servis.gonder(metin);
    _enAltaKaydir();
  }

  void _enAltaKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---- MEDYA ----

  // Ek (ataç) menüsü: foto / video seç
  void _ekMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: Renkler.accent),
              title: const Text('Fotoğraf'),
              onTap: () {
                Navigator.pop(context);
                _fotoSec();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Renkler.accent),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _videoSec();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fotoSec() async {
    final x = await _resimSecici.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (x != null) await _medyaGonder(File(x.path), MesajTipi.resim);
  }

  Future<void> _videoSec() async {
    final x = await _resimSecici.pickVideo(source: ImageSource.gallery);
    if (x != null) await _medyaGonder(File(x.path), MesajTipi.video);
  }

  // Sesli mesaj: dokun → başlat, tekrar dokun → durdur + gönder
  Future<void> _mikrofon() async {
    if (_kayitYapiliyor) {
      final yol = await _kayitci.stop();
      setState(() => _kayitYapiliyor = false);
      if (yol != null) await _medyaGonder(File(yol), MesajTipi.ses);
    } else {
      if (await _kayitci.hasPermission()) {
        final dizin = await getTemporaryDirectory();
        final yol =
            '${dizin.path}/ses_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _kayitci.start(const RecordConfig(), path: yol);
        setState(() => _kayitYapiliyor = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon izni gerekli')),
        );
      }
    }
  }

  Future<void> _medyaGonder(File dosya, MesajTipi tip) async {
    setState(() => _yukleniyor = true);
    final ok = await _servis.medyaGonder(dosya, tip);
    if (!mounted) return;
    setState(() => _yukleniyor = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Medya gönderilemedi. Cloudinary ayarı yapılmamış olabilir.',
          ),
        ),
      );
    } else {
      _enAltaKaydir();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _AppBarBaslik(presence: _presence),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani()),
            ),
          ),
          IconButton(
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _presence.cevrimdisiYap();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_yukleniyor)
            const LinearProgressIndicator(
              color: Renkler.accent,
              backgroundColor: Renkler.yuzey,
            ),
          Expanded(
            child: StreamBuilder<List<Mesaj>>(
              stream: _servis.mesajlariDinle(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Renkler.accent),
                  );
                }
                if (snapshot.hasError) {
                  return const _BosDurum(
                    ikon: Icons.error_outline,
                    yazi: 'Mesajlar yüklenemedi',
                  );
                }

                final mesajlar = snapshot.data ?? [];
                if (mesajlar.isEmpty) {
                  return const _BosDurum(
                    ikon: Icons.chat_bubble_outline_rounded,
                    yazi: 'Henüz mesaj yok.\nİlk mesajı sen yaz 👋',
                  );
                }

                _servis.gorulduIsaretle(mesajlar);
                _enAltaKaydir();

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: mesajlar.length,
                  itemBuilder: (context, i) {
                    final m = mesajlar[i];
                    return _MesajBalonu(
                      mesaj: m,
                      benimMi: m.gonderen == _uid,
                      onUzunBas: () => _tepkiSec(m),
                    );
                  },
                );
              },
            ),
          ),
          // Kayıt sırasında kayıt çubuğu, değilse normal yazma alanı
          if (_kayitYapiliyor)
            _KayitCubugu(onDurdurGonder: _mikrofon)
          else
            _YazmaAlani(
              controller: _mesajCtrl,
              onGonder: _gonder,
              onEk: _ekMenu,
              onMikrofon: _mikrofon,
            ),
        ],
      ),
    );
  }

  void _tepkiSec(Mesaj mesaj) {
    const emojiler = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in emojiler)
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () {
                    Navigator.pop(context);
                    _servis.tepkiDegistir(mesaj.id, e);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AppBar başlığı: isim + altında çevrimiçi/yazıyor/son görülme durumu.
class _AppBarBaslik extends StatelessWidget {
  final PresenceServisi presence;
  const _AppBarBaslik({required this.presence});

  String _sonGorulmeMetni(Map<String, dynamic>? veri) {
    if (veri == null) return '';
    if (veri['yaziyor'] == true) return 'yazıyor...';
    if (veri['online'] == true) return 'çevrimiçi';
    final ts = veri['sonGorulme'];
    if (ts is Timestamp) {
      final t = ts.toDate();
      final s = t.hour.toString().padLeft(2, '0');
      final d = t.minute.toString().padLeft(2, '0');
      return 'son görülme $s:$d';
    }
    return 'çevrimdışı';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: presence.karsiTarafiDinle(),
      builder: (context, snap) {
        final durum = _sonGorulmeMetni(snap.data);
        final yaziyor = snap.data?['yaziyor'] == true;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kardeş Mesaj', style: TextStyle(fontSize: 18)),
            if (durum.isNotEmpty)
              Text(
                durum,
                style: TextStyle(
                  fontSize: 12,
                  color: yaziyor ? Renkler.accent : Renkler.metinSoluk,
                  fontWeight: yaziyor ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tek bir mesaj balonu (uzun basınca tepki seçici). Metin veya medya gösterir.
class _MesajBalonu extends StatelessWidget {
  final Mesaj mesaj;
  final bool benimMi;
  final VoidCallback onUzunBas;

  const _MesajBalonu({
    required this.mesaj,
    required this.benimMi,
    required this.onUzunBas,
  });

  String _saat(DateTime? t) {
    if (t == null) return '';
    final s = t.hour.toString().padLeft(2, '0');
    final d = t.minute.toString().padLeft(2, '0');
    return '$s:$d';
  }

  // Mesaj türüne göre içerik
  Widget _icerik(BuildContext context) {
    switch (mesaj.tip) {
      case MesajTipi.resim:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _resmiBuyut(context, mesaj.medyaUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              mesaj.medyaUrl!,
              width: 220,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : Container(
                      width: 220,
                      height: 160,
                      alignment: Alignment.center,
                      color: Renkler.zemin,
                      child: const CircularProgressIndicator(
                          color: Renkler.accent),
                    ),
              errorBuilder: (c, e, s) => const SizedBox(
                width: 220,
                height: 100,
                child: Icon(Icons.broken_image, color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      case MesajTipi.video:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _VideoOynatici(url: mesaj.medyaUrl!);
      case MesajTipi.ses:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _SesOynatici(url: mesaj.medyaUrl!, benimMi: benimMi);
      case MesajTipi.metin:
        return Text(
          mesaj.metin,
          style: TextStyle(
            color: benimMi ? Colors.white : Renkler.metin,
            fontSize: 15,
          ),
        );
    }
  }

  void _resmiBuyut(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final medyaMi = mesaj.tip != MesajTipi.metin;
    return Align(
      alignment: benimMi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onUzunBas,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: EdgeInsets.only(
                top: 4,
                bottom: mesaj.tepki != null ? 16 : 4,
              ),
              padding: EdgeInsets.all(medyaMi ? 5 : 12),
              decoration: BoxDecoration(
                color: benimMi ? Renkler.benimBalon : Renkler.kardesBalon,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(benimMi ? 16 : 4),
                  bottomRight: Radius.circular(benimMi ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _icerik(context),
                  Padding(
                    padding: EdgeInsets.only(top: 3, left: medyaMi ? 6 : 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _saat(mesaj.zaman),
                          style: TextStyle(
                            color: benimMi
                                ? Colors.white.withValues(alpha: 0.7)
                                : Renkler.metinSoluk,
                            fontSize: 11,
                          ),
                        ),
                        if (benimMi) ...[
                          const SizedBox(width: 4),
                          Icon(
                            mesaj.goruldu ? Icons.done_all : Icons.done,
                            size: 15,
                            color: mesaj.goruldu
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (mesaj.tepki != null)
              Positioned(
                bottom: 0,
                right: benimMi ? 8 : null,
                left: benimMi ? null : 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Renkler.yuzey,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Renkler.zemin, width: 1.5),
                  ),
                  child:
                      Text(mesaj.tepki!, style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// İnline video oynatıcı (dokununca oynat/duraklat).
class _VideoOynatici extends StatefulWidget {
  final String url;
  const _VideoOynatici({required this.url});

  @override
  State<_VideoOynatici> createState() => _VideoOynaticiState();
}

class _VideoOynaticiState extends State<_VideoOynatici> {
  VideoPlayerController? _ctrl;
  bool _hazir = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _hazir = true);
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hazir || _ctrl == null) {
      return Container(
        width: 220,
        height: 160,
        alignment: Alignment.center,
        color: Renkler.zemin,
        child: const CircularProgressIndicator(color: Renkler.accent),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
      }),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_ctrl!),
                if (!_ctrl!.value.isPlaying)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 36),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sesli mesaj oynatıcı (çal/duraklat).
class _SesOynatici extends StatefulWidget {
  final String url;
  final bool benimMi;
  const _SesOynatici({required this.url, required this.benimMi});

  @override
  State<_SesOynatici> createState() => _SesOynaticiState();
}

class _SesOynaticiState extends State<_SesOynatici> {
  final AudioPlayer _player = AudioPlayer();
  bool _caliyor = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _caliyor = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _degistir() async {
    if (_caliyor) {
      await _player.pause();
      setState(() => _caliyor = false);
    } else {
      await _player.play(UrlSource(widget.url));
      setState(() => _caliyor = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final renk = widget.benimMi ? Colors.white : Renkler.metin;
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _caliyor ? Icons.pause_circle : Icons.play_circle,
              color: renk,
              size: 34,
            ),
            onPressed: _degistir,
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.graphic_eq, color: renk, size: 18),
                const SizedBox(width: 6),
                Text('Sesli mesaj', style: TextStyle(color: renk, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt mesaj yazma çubuğu (ataç + metin + mikrofon/gönder).
class _YazmaAlani extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onGonder;
  final VoidCallback onEk;
  final VoidCallback onMikrofon;

  const _YazmaAlani({
    required this.controller,
    required this.onGonder,
    required this.onEk,
    required this.onMikrofon,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        color: Renkler.yuzey,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Ekle',
              icon: const Icon(Icons.add_circle_outline, color: Renkler.accent),
              onPressed: onEk,
            ),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, deger, _) {
                  final bos = deger.text.trim().isEmpty;
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onGonder(),
                          decoration: const InputDecoration(
                            hintText: 'Mesaj yaz...',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: Renkler.accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: bos ? onMikrofon : onGonder,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              bos ? Icons.mic : Icons.send_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// Sesli mesaj kaydı sırasında gösterilen çubuk.
class _KayitCubugu extends StatelessWidget {
  final VoidCallback onDurdurGonder;
  const _KayitCubugu({required this.onDurdurGonder});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        color: Renkler.yuzey,
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Kaydediliyor...  Bitirmek için gönder',
                  style: TextStyle(color: Renkler.metin)),
            ),
            Material(
              color: Renkler.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDurdurGonder,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boş/hata durumu için ortak gösterim.
class _BosDurum extends StatelessWidget {
  final IconData ikon;
  final String yazi;

  const _BosDurum({required this.ikon, required this.yazi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ikon, size: 56, color: Renkler.metinSoluk),
          const SizedBox(height: 12),
          Text(
            yazi,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Renkler.metinSoluk),
          ),
        ],
      ),
    );
  }
}
