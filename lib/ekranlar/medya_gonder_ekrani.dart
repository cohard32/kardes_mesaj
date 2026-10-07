import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../modeller/mesaj.dart';
import '../servisler/dosya_servisi.dart' show boyutMetni;
import '../tema.dart';

/// Gönderilecek bir fotoğraf/video + açıklaması.
class GonderilecekMedya {
  final File dosya;
  final MesajTipi tip;
  final String aciklama;
  const GonderilecekMedya(this.dosya, this.tip, this.aciklama);
}

/// Video uzantıları (seçicinin MIME bilgisi her zaman gelmez).
const Set<String> _videoUzantilari = {
  'mp4', 'mov', '3gp', '3g2', 'mkv', 'webm', 'avi', 'm4v', 'ts',
};

/// Dosya yolundan fotoğraf mı video mu? (saf → test edilir)
MesajTipi medyaTuruTahmin(String yol) {
  final nokta = yol.lastIndexOf('.');
  final uzanti = nokta < 0 ? '' : yol.substring(nokta + 1).toLowerCase();
  return _videoUzantilari.contains(uzanti) ? MesajTipi.video : MesajTipi.resim;
}

/// Cloudinary ücretsiz plan sınırları: fotoğraf 10 MB, video 100 MB.
int azamiMedyaBoyutu(MesajTipi tip) =>
    tip == MesajTipi.video ? 100 * 1024 * 1024 : 10 * 1024 * 1024;

/// GÖNDERMEDEN ÖNCE ÖNİZLEME: seçilen (ya da kameradan çekilen) fotoğraf ve
/// videolar büyük gösterilir; her birine AYRI açıklama yazılabilir, istenmeyen
/// çıkarılabilir. "Gönder" → [GonderilecekMedya] listesi döner.
class MedyaGonderEkrani extends StatefulWidget {
  final List<File> dosyalar;
  final String kime;
  const MedyaGonderEkrani({
    super.key,
    required this.dosyalar,
    required this.kime,
  });

  @override
  State<MedyaGonderEkrani> createState() => _MedyaGonderEkraniState();
}

class _MedyaGonderEkraniState extends State<MedyaGonderEkrani> {
  late final List<File> _dosyalar = List.of(widget.dosyalar);
  late final List<String> _aciklamalar =
      List.filled(widget.dosyalar.length, '', growable: true);
  late final Map<File, int> _boyutlar = {
    for (final f in widget.dosyalar) f: _boyut(f),
  };
  final _sayfa = PageController();
  final _aciklama = TextEditingController();
  int _secili = 0;

  static int _boyut(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _sayfa.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  bool _buyukMu(File f) =>
      (_boyutlar[f] ?? 0) > azamiMedyaBoyutu(medyaTuruTahmin(f.path));

  void _sec(int i) {
    _aciklamalar[_secili] = _aciklama.text;
    setState(() => _secili = i);
    _aciklama.text = _aciklamalar[i];
  }

  void _cikar(int i) {
    if (_dosyalar.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    _aciklamalar[_secili] = _aciklama.text;
    setState(() {
      _dosyalar.removeAt(i);
      _aciklamalar.removeAt(i);
      if (_secili >= _dosyalar.length) _secili = _dosyalar.length - 1;
    });
    _aciklama.text = _aciklamalar[_secili];
    _sayfa.jumpToPage(_secili);
  }

  void _gonder() {
    _aciklamalar[_secili] = _aciklama.text;
    final buyukler = [
      for (final f in _dosyalar)
        if (_buyukMu(f)) f,
    ];
    if (buyukler.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            buyukler.length == 1
                ? 'Bu dosya çok büyük (${boyutMetni(_boyutlar[buyukler.first] ?? 0)}). '
                    'Fotoğraf en fazla 10 MB, video en fazla 100 MB olabilir. '
                    'Çıkarıp tekrar dene.'
                : '${buyukler.length} dosya çok büyük (kırmızı işaretli). '
                    'Çıkarıp tekrar dene.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop([
      for (var i = 0; i < _dosyalar.length; i++)
        GonderilecekMedya(
          _dosyalar[i],
          medyaTuruTahmin(_dosyalar[i].path),
          _aciklamalar[i].trim(),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final coklu = _dosyalar.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          coklu ? '${_dosyalar.length} öğe → ${widget.kime}' : widget.kime,
          style: Yazi.stil(16, FontWeight.w700, Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Bunu çıkar',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _cikar(_secili),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _sayfa,
              itemCount: _dosyalar.length,
              onPageChanged: _sec,
              itemBuilder: (_, i) {
                final f = _dosyalar[i];
                final onizleme = medyaTuruTahmin(f.path) == MesajTipi.video
                    ? _VideoOnizleme(dosya: f)
                    : InteractiveViewer(
                        child: Image.file(
                          f,
                          fit: BoxFit.contain,
                          // Önizleme ekran boyutunda çözülsün (bellek).
                          cacheWidth: (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: onizleme),
                    if (_buyukMu(f))
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Renkler.tehlike,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Çok büyük: ${boyutMetni(_boyutlar[f] ?? 0)} — '
                            'gönderilemez',
                            style: Yazi.stil(
                              13,
                              FontWeight.w700,
                              Renkler.metinTehlikeUstu,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (coklu)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _dosyalar.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _dosyalar[i];
                  final video = medyaTuruTahmin(f.path) == MesajTipi.video;
                  return GestureDetector(
                    onTap: () => _sayfa.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _buyukMu(f)
                              ? Renkler.tehlike
                              : (i == _secili
                                  ? Renkler.neon
                                  : Colors.white24),
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: video
                          ? Container(
                              color: Colors.white10,
                              child: const Icon(
                                Icons.videocam_rounded,
                                color: Colors.white70,
                              ),
                            )
                          : Image.file(
                              f,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                    ),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _aciklama,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        style: Yazi.stil(15, FontWeight.w500, Colors.white),
                        cursorColor: Renkler.neon,
                        decoration: InputDecoration(
                          hintText: coklu
                              ? 'Bu öğeye açıklama ekle…'
                              : 'Açıklama ekle…',
                          hintStyle: Yazi.stil(
                            15,
                            FontWeight.w500,
                            Colors.white54,
                          ),
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Uc3DDugme(
                    kose: Kose.dugme,
                    padding: const EdgeInsets.all(14),
                    onTap: _gonder,
                    cocuk: Icon(
                      Icons.send_rounded,
                      color: Renkler.metinKoyu,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Önizlemedeki video: ilk kare + dokununca oynat/duraklat.
class _VideoOnizleme extends StatefulWidget {
  final File dosya;
  const _VideoOnizleme({required this.dosya});

  @override
  State<_VideoOnizleme> createState() => _VideoOnizlemeState();
}

class _VideoOnizlemeState extends State<_VideoOnizleme> {
  late final VideoPlayerController _c =
      VideoPlayerController.file(widget.dosya);
  bool _hazir = false;
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() => _hazir = true);
    }).catchError((Object _) {
      if (mounted) setState(() => _hata = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hata) {
      return const Icon(Icons.videocam_rounded, color: Colors.white54, size: 64);
    }
    if (!_hazir) return CircularProgressIndicator(color: Renkler.neon);
    return GestureDetector(
      onTap: () => setState(() {
        _c.value.isPlaying ? _c.pause() : _c.play();
      }),
      child: AspectRatio(
        aspectRatio: _c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_c),
            if (!_c.value.isPlaying)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
