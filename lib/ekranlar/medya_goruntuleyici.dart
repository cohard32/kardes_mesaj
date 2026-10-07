import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../modeller/mesaj.dart';
import '../parcalar/onbellekli_resim.dart';
import '../servisler/hata_servisi.dart';
import '../servisler/medya_indir_servisi.dart';
import '../tema.dart';
import '../yardimcilar/mesaj_metni.dart';
import '../yardimcilar/zaman_metni.dart';

/// Tam ekran görüntüleyiciyi kararma geçişiyle açar.
Future<void> _sayfaAc(BuildContext context, Widget sayfa) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => sayfa,
      transitionsBuilder: (_, anim, _, cocuk) =>
          FadeTransition(opacity: anim, child: cocuk),
    ),
  );
}

/// Üst çubuktaki "kim · ne zaman" başlığı.
class _Baslik extends StatelessWidget {
  final String? baslik;
  final DateTime? zaman;
  const _Baslik({this.baslik, this.zaman});

  @override
  Widget build(BuildContext context) {
    final t = zaman;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          baslik ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Yazi.stil(16, FontWeight.w700, Colors.white),
        ),
        if (t != null)
          Text(
            '${gunAyraciMetni(t)} ${saatMetni(t)}',
            style: Yazi.stil(12, FontWeight.w500, Colors.white70),
          ),
      ],
    );
  }
}

/// "Galeriye indir" düğmesi: indirirken ilerleme halkası, bitince bildirim.
/// Orijinal dosya önbellekteyse (tam ekranda zaten indiyse) yeniden
/// İNDİRİLMEZ, telefondaki kopyası galeriye kaydedilir.
class IndirDugmesi extends StatefulWidget {
  final String url;
  final MesajTipi tip;
  final Color renk;
  const IndirDugmesi({
    super.key,
    required this.url,
    required this.tip,
    this.renk = Colors.white,
  });

  @override
  State<IndirDugmesi> createState() => _IndirDugmesiState();
}

class _IndirDugmesiState extends State<IndirDugmesi> {
  bool _indiriyor = false;
  double? _ilerleme;

  Future<void> _indir() async {
    if (_indiriyor) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _indiriyor = true;
      _ilerleme = null;
    });
    final ok = await MedyaIndirServisi.instance.galeriyeIndir(
      widget.url,
      widget.tip,
      ilerleme: (p) {
        if (mounted) setState(() => _ilerleme = p);
      },
    );
    if (!mounted) return;
    setState(() => _indiriyor = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (widget.tip == MesajTipi.video
                  ? 'Video galeriye kaydedildi ✓'
                  : 'Fotoğraf galeriye kaydedildi ✓')
              : 'İndirilemedi. İnternet bağlantını kontrol et.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_indiriyor) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: _ilerleme,
              strokeWidth: 2.5,
              color: Renkler.neon,
              semanticsLabel: 'İndiriliyor',
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Galeriye indir',
      icon: Icon(Icons.download_rounded, color: widget.renk),
      onPressed: _indir,
    );
  }
}

/// Alttaki "Orijinal yükleniyor %45" rozeti.
class _YuklemeRozeti extends StatelessWidget {
  final ImageChunkEvent olay;
  const _YuklemeRozeti(this.olay);

  @override
  Widget build(BuildContext context) {
    final toplam = olay.expectedTotalBytes;
    final oran = toplam == null || toplam == 0
        ? null
        : (olay.cumulativeBytesLoaded / toplam).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  value: oran,
                  strokeWidth: 2,
                  color: Renkler.neon,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                oran == null
                    ? 'Orijinal yükleniyor…'
                    : 'Orijinal yükleniyor %${(oran * 100).round()}',
                style: Yazi.stil(12, FontWeight.w600, Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TAM EKRAN FOTOĞRAF: önce (telefonda önbellekli) küçük hâli anında
/// görünür, üstüne ORİJİNAL çözünürlük yüklenip yumuşakça belirir.
/// İki parmakla / çift dokunarak yakınlaştırma, sağ üstte "Galeriye indir".
class FotoGoruntuleyici extends StatefulWidget {
  /// Orijinal (dönüşümsüz) URL.
  final String url;

  /// [MesajTipi.resim] ya da [MesajTipi.gif].
  final MesajTipi tip;
  final String? baslik;
  final DateTime? zaman;

  const FotoGoruntuleyici({
    super.key,
    required this.url,
    this.tip = MesajTipi.resim,
    this.baslik,
    this.zaman,
  });

  static Future<void> ac(
    BuildContext context, {
    required String url,
    MesajTipi tip = MesajTipi.resim,
    String? baslik,
    DateTime? zaman,
  }) =>
      _sayfaAc(
        context,
        FotoGoruntuleyici(url: url, tip: tip, baslik: baslik, zaman: zaman),
      );

  @override
  State<FotoGoruntuleyici> createState() => _FotoGoruntuleyiciState();
}

class _FotoGoruntuleyiciState extends State<FotoGoruntuleyici> {
  bool _arayuz = true;
  final _donusum = TransformationController();
  TapDownDetails? _ciftKonum;

  // ORİJİNAL: en uzun kenarı 6000 px'e kadar olan fotoğraflar (12–24 MP
  // telefon fotoğrafları) TAM çözünürlükte açılır. Daha büyükleri telefonun
  // belleği taşmasın diye bu sınıra küçültülerek çözülür.
  late final ImageProvider _orijinal = ResizeImage(
    OnbellekliResim(widget.url),
    width: 6000,
    height: 6000,
    policy: ResizeImagePolicy.fit,
  );

  @override
  void dispose() {
    _donusum.dispose();
    super.dispose();
  }

  // Çift dokunma: yakınlaştırılmışsa sıfırla, değilse dokunulan noktaya 2.5x.
  void _ciftDokun() {
    if (_donusum.value != Matrix4.identity()) {
      _donusum.value = Matrix4.identity();
      return;
    }
    final p = _ciftKonum?.localPosition ?? Offset.zero;
    const k = 2.5;
    _donusum.value = Matrix4.diagonal3Values(k, k, 1)
      ..setTranslationRaw(-p.dx * (k - 1), -p.dy * (k - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final resimMi = widget.tip == MesajTipi.resim;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _arayuz
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.45),
              foregroundColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              title: _Baslik(baslik: widget.baslik, zaman: widget.zaman),
              actions: [IndirDugmesi(url: widget.url, tip: widget.tip)],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _arayuz = !_arayuz),
        onDoubleTapDown: (d) => _ciftKonum = d,
        onDoubleTap: _ciftDokun,
        child: InteractiveViewer(
          transformationController: _donusum,
          minScale: 1,
          maxScale: 8,
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1) Küçük hâl (balonda zaten indi → anında görünür).
                if (resimMi)
                  Image(
                    image: OnbellekliResim(kucukResimUrl(widget.url)),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                // 2) ORİJİNAL — inince küçük hâlin üstüne biner.
                Image(
                  image: _orijinal,
                  fit: BoxFit.contain,
                  frameBuilder: (_, cocuk, kare, senkron) => senkron
                      ? cocuk
                      : AnimatedOpacity(
                          opacity: kare == null ? 0 : 1,
                          duration: const Duration(milliseconds: 250),
                          child: cocuk,
                        ),
                  loadingBuilder: (_, cocuk, olay) => olay == null
                      ? cocuk
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            cocuk,
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: _YuklemeRozeti(olay),
                            ),
                          ],
                        ),
                  errorBuilder: (_, _, _) => Center(
                    child: resimMi
                        ? const SizedBox.shrink()
                        : const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// TAM EKRAN VİDEO: oynat/duraklat, ileri-geri sarma çubuğu, süre,
/// sağ üstte "Galeriye indir". Yüklenirken videonun kapağı görünür.
class VideoGoruntuleyici extends StatefulWidget {
  final String url;
  final String? baslik;
  final DateTime? zaman;
  const VideoGoruntuleyici({
    super.key,
    required this.url,
    this.baslik,
    this.zaman,
  });

  static Future<void> ac(
    BuildContext context, {
    required String url,
    String? baslik,
    DateTime? zaman,
  }) =>
      _sayfaAc(
        context,
        VideoGoruntuleyici(url: url, baslik: baslik, zaman: zaman),
      );

  @override
  State<VideoGoruntuleyici> createState() => _VideoGoruntuleyiciState();
}

class _VideoGoruntuleyiciState extends State<VideoGoruntuleyici> {
  VideoPlayerController? _ctrl;
  bool _hazir = false;
  bool _hata = false;
  bool _arayuz = true;
  Timer? _gizle;

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  @override
  void dispose() {
    _gizle?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _baslat() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() {
      _ctrl = c;
      _hazir = false;
      _hata = false;
    });
    // ⚠️ Hata yakalanmalı: bozuk/silinmiş videoda spinner sonsuza kadar
    // dönmesin. `identical`: bekleme sırasında yeniden denendiyse bu deneme
    // artık geçersiz.
    try {
      await c.initialize();
      if (!mounted || !identical(_ctrl, c)) return;
      await c.play();
      if (!mounted || !identical(_ctrl, c)) return;
      setState(() => _hazir = true);
      _sonraGizle();
    } catch (e) {
      HataServisi.instance.iz('VIDEO acilamadi: $e');
      if (!mounted || !identical(_ctrl, c)) return;
      setState(() {
        _ctrl = null;
        _hata = true;
      });
      await c.dispose();
    }
  }

  // Oynarken kontroller 3 sn sonra kendiliğinden gizlenir.
  void _sonraGizle() {
    _gizle?.cancel();
    _gizle = Timer(const Duration(seconds: 3), () {
      if (mounted && (_ctrl?.value.isPlaying ?? false)) {
        setState(() => _arayuz = false);
      }
    });
  }

  void _dokun() {
    setState(() => _arayuz = !_arayuz);
    if (_arayuz) _sonraGizle();
  }

  void _oynatDuraklat() {
    final c = _ctrl;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      _gizle?.cancel();
    } else {
      // Sona gelmişse baştan.
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
      _sonraGizle();
    }
  }

  String _mmss(Duration d) {
    final dk = d.inMinutes.toString().padLeft(2, '0');
    final sn = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$dk:$sn' : '$dk:$sn';
  }

  Widget _kapak() {
    final kapak = videoKapakUrl(widget.url);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (kapak != null)
          Image(
            image: OnbellekliResim(kucukResimUrl(kapak)),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        Center(
          child: _hata
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Video açılamadı',
                      style: Yazi.stil(15, FontWeight.w600, Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _baslat,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar dene'),
                    ),
                  ],
                )
              : CircularProgressIndicator(color: Renkler.neon),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _hazir ? _ctrl : null;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _arayuz
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.45),
              foregroundColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              title: _Baslik(baslik: widget.baslik, zaman: widget.zaman),
              actions: [IndirDugmesi(url: widget.url, tip: MesajTipi.video)],
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: c != null ? _dokun : null,
        child: c == null
            ? _kapak()
            : Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                  if (_arayuz)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, v, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: _oynatDuraklat,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  v.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: SafeArea(
                              child: Container(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                color: Colors.black.withValues(alpha: 0.35),
                                child: Row(
                                  children: [
                                    Text(
                                      _mmss(v.position),
                                      style: Yazi.stil(
                                        12,
                                        FontWeight.w600,
                                        Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: VideoProgressIndicator(
                                        c,
                                        allowScrubbing: true,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        colors: VideoProgressColors(
                                          playedColor: Renkler.neon,
                                          bufferedColor: Colors.white38,
                                          backgroundColor: Colors.white12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _mmss(v.duration),
                                      style: Yazi.stil(
                                        12,
                                        FontWeight.w600,
                                        Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
