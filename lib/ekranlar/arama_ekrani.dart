import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../servisler/arama_servisi.dart';
import '../tema.dart';

/// Aktif arama ekranı (görüntülü + sesli ortak).
/// Bu ekrana gelindiğinde Agora kanalına ZATEN katılınmış olur
/// (arayan `aramaBaslat`, aranan `kabulEt` çağırmış olur).
class AramaEkrani extends StatefulWidget {
  final String kanal;
  final AramaTipi tip;
  final String baslik; // karşı tarafın adı/e-postası

  const AramaEkrani({
    super.key,
    required this.kanal,
    required this.tip,
    required this.baslik,
  });

  @override
  State<AramaEkrani> createState() => _AramaEkraniState();
}

class _AramaEkraniState extends State<AramaEkrani> {
  final _arama = AramaServisi.instance;
  StreamSubscription? _sub;
  Timer? _sayac;
  Timer? _zamanAsimi;
  int _saniye = 0;
  bool _micKapali = false;
  bool _kameraKapali = false;
  bool _hoparlor = true;
  bool _kapandi = false;

  bool get _video => widget.tip == AramaTipi.video;

  @override
  void initState() {
    super.initState();
    _hoparlor = _video;
    _arama.karsiUid.addListener(_baglantiKontrol);
    _sub = _arama.aramaDinle().listen((doc) {
      final durum = doc.data()?['durum'];
      if (durum == 'red') {
        _kapat(mesaj: 'Arama reddedildi');
      } else if (durum == 'bitti') {
        _kapat();
      }
    });
    // Karşı taraf 45 sn içinde katılmazsa aramayı kapat.
    _zamanAsimi = Timer(const Duration(seconds: 45), () {
      if (!_kapandi && _arama.karsiUid.value == null) {
        _kapat(mesaj: 'Cevap verilmedi');
      }
    });
  }

  void _baglantiKontrol() {
    if (_arama.karsiUid.value != null) {
      _zamanAsimi?.cancel();
      _sayac ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _saniye++);
      });
    }
  }

  @override
  void dispose() {
    _sayac?.cancel();
    _zamanAsimi?.cancel();
    _arama.karsiUid.removeListener(_baglantiKontrol);
    _sub?.cancel();
    if (!_kapandi) _arama.bitir();
    super.dispose();
  }

  Future<void> _kapat({String? mesaj}) async {
    if (_kapandi) return;
    _kapandi = true;
    _sayac?.cancel();
    _zamanAsimi?.cancel();
    _arama.karsiUid.removeListener(_baglantiKontrol);
    await _sub?.cancel();
    await _arama.bitir();
    if (!mounted) return;
    if (mesaj != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mesaj)));
    }
    Navigator.of(context).pop();
  }

  String get _sure {
    final d = (_saniye ~/ 60).toString().padLeft(2, '0');
    final s = (_saniye % 60).toString().padLeft(2, '0');
    return '$d:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _kapat();
      },
      child: Scaffold(
        backgroundColor: Renkler.zeminDerin,
        body: Stack(
          children: [
            Positioned.fill(child: _uzakGorunum()),
            // Kendi görüntün — organik köşe + neon kenar
            if (_video && !_kameraKapali)
              Positioned(
                top: 44,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: Kose.kartKose,
                    border: Border.all(color: Renkler.kenarGuclu),
                    boxShadow: Golgeler.yuzey,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 110,
                    height: 160,
                    child: _yerelGorunum(),
                  ),
                ),
              ),
            Positioned(top: 56, left: 0, right: 0, child: _ustBilgi()),
            Positioned(left: 0, right: 0, bottom: 44, child: _kontroller()),
          ],
        ),
      ),
    );
  }

  Widget _uzakGorunum() {
    return ValueListenableBuilder<int?>(
      valueListenable: _arama.karsiUid,
      builder: (_, uid, _) {
        if (uid == null) {
          return Zemin(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Renkler.neon),
                  const SizedBox(height: 16),
                  Text('Bağlanıyor…', style: Yazi.kucuk),
                  // Agora bağlantı/token hatası varsa göster (tanı için).
                  ValueListenableBuilder<String?>(
                    valueListenable: _arama.sonHata,
                    builder: (_, hata, _) => hata == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              'Bağlantı hatası: $hata',
                              textAlign: TextAlign.center,
                              style: Yazi.stil(
                                  13, FontWeight.w600, Renkler.tehlike),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        }
        final e = _arama.engine;
        if (!_video || e == null) {
          // Sesli arama: video yok → neon gradient avatar
          return Zemin(
            child: Center(
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  gradient: Gradyanlar.yesil,
                  borderRadius: Kose.kartKose,
                  boxShadow: Golgeler.yuzey,
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: IcIsik(kose: Kose.kartKose, guclu: false),
                    ),
                    const Center(
                      child: Icon(Icons.person,
                          size: 68, color: Renkler.metinKoyu),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: e,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.kanal),
          ),
        );
      },
    );
  }

  Widget _yerelGorunum() {
    final e = _arama.engine;
    if (e == null) return const ColoredBox(color: Renkler.yuzey);
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: e,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _ustBilgi() {
    final bagli = _arama.karsiUid.value != null;
    return Column(
      children: [
        Text(widget.baslik, style: Yazi.baslik),
        const SizedBox(height: 8),
        // Süre / durum — cam rozet
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: Kutular.duzYuzey(kose: Kose.alan, kenarli: true),
          child: Text(
            bagli ? _sure : (_video ? 'Görüntülü arama' : 'Sesli arama'),
            style: bagli
                ? Yazi.stil(14, FontWeight.w700, Renkler.neon)
                : Yazi.kucuk,
          ),
        ),
      ],
    );
  }

  Widget _kontroller() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dugme(
          ikon: _micKapali ? Icons.mic_off : Icons.mic,
          aktif: !_micKapali,
          onTap: () {
            setState(() => _micKapali = !_micKapali);
            _arama.mikrofonKapat(_micKapali);
          },
        ),
        if (_video) ...[
          _dugme(
            ikon: _kameraKapali ? Icons.videocam_off : Icons.videocam,
            aktif: !_kameraKapali,
            onTap: () {
              setState(() => _kameraKapali = !_kameraKapali);
              _arama.kameraKapat(_kameraKapali);
            },
          ),
          _dugme(
            ikon: Icons.cameraswitch,
            aktif: false,
            onTap: _arama.kameraDegistir,
          ),
        ],
        _dugme(
          ikon: _hoparlor ? Icons.volume_up : Icons.volume_down,
          aktif: _hoparlor,
          onTap: () {
            setState(() => _hoparlor = !_hoparlor);
            _arama.hoparlor(_hoparlor);
          },
        ),
        // Kapat — kırmızı 3D
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Uc3DDugme(
            tehlike: true,
            kose: Kose.dugme,
            padding: const EdgeInsets.all(19),
            onTap: _kapat,
            cocuk: const Icon(Icons.call_end,
                color: Renkler.metinTehlikeUstu, size: 28),
          ),
        ),
      ],
    );
  }

  /// Arama içi kontrol: aktifken neon (3D), kapalıyken koyu cam.
  Widget _dugme({
    required IconData ikon,
    required bool aktif,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Uc3DDugme(
        ikincil: !aktif,
        kose: Kose.dugme,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        cocuk: Icon(
          ikon,
          color: aktif ? Renkler.metinKoyu : Renkler.metin,
          size: 24,
        ),
      ),
    );
  }
}

/// Gelen arama ekranı (uygulama AÇIKKEN Firestore dinleyicisinden açılır).
/// Kabul → kanala katılır ve [AramaEkrani]'na geçer. Reddet → kapatır.
class GelenAramaEkrani extends StatefulWidget {
  final String arayan;
  final String kanal;
  final AramaTipi tip;

  const GelenAramaEkrani({
    super.key,
    required this.arayan,
    required this.kanal,
    required this.tip,
  });

  @override
  State<GelenAramaEkrani> createState() => _GelenAramaEkraniState();
}

class _GelenAramaEkraniState extends State<GelenAramaEkrani> {
  final _arama = AramaServisi.instance;
  StreamSubscription? _sub;
  bool _islemde = false;

  @override
  void initState() {
    super.initState();
    // Arayan vazgeç/iptal ederse (durum bitti/red) ekranı kapat
    _sub = _arama.aramaDinle().listen((doc) {
      final durum = doc.data()?['durum'];
      if (!_islemde && (durum == 'bitti' || durum == 'red')) {
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _kabul() async {
    setState(() => _islemde = true);
    try {
      final ok = await _arama.kabulEt(widget.kanal, widget.tip);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera/mikrofon izni gerekli')),
        );
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(
            kanal: widget.kanal,
            tip: widget.tip,
            baslik: widget.arayan,
          ),
        ),
      );
    } catch (e) {
      // kabulEt hata fırlatırsa (Agora) ekran takılı kalmasın, hatayı göster.
      if (!mounted) return;
      setState(() => _islemde = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kabul edilemedi: $e')),
      );
    }
  }

  Future<void> _reddet() async {
    setState(() => _islemde = true);
    await _arama.reddet();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.tip == AramaTipi.video;
    return Scaffold(
      body: Zemin(
        parlama: const Alignment(0, -0.7),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Arayan avatarı — gradient + glow, organik köşe
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: Gradyanlar.yesil,
                  borderRadius: Kose.kartKose,
                  boxShadow: Golgeler.yuzey,
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: IcIsik(kose: Kose.kartKose, guclu: false),
                    ),
                    const Center(
                      child: Icon(Icons.person,
                          size: 62, color: Renkler.metinKoyu),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(widget.arayan, style: Yazi.baslik),
              const SizedBox(height: 10),
              // Yanıp sönen neon nokta + durum
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 7, height: 7, decoration: Kutular.neonNokta()),
                  const SizedBox(width: 7),
                  Text(
                    video ? 'Görüntülü arama…' : 'Sesli arama…',
                    style: Yazi.stil(14, FontWeight.w600, Renkler.neon),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _aramaDugme(
                    ikon: Icons.call_end,
                    tehlike: true,
                    etiket: 'Reddet',
                    onTap: _islemde ? null : _reddet,
                  ),
                  _aramaDugme(
                    ikon: video ? Icons.videocam : Icons.call,
                    tehlike: false,
                    etiket: 'Kabul Et',
                    onTap: _islemde ? null : _kabul,
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aramaDugme({
    required IconData ikon,
    required bool tehlike,
    required String etiket,
    required VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Uc3DDugme(
          tehlike: tehlike,
          kose: Kose.kartKose,
          padding: const EdgeInsets.all(24),
          onTap: onTap,
          cocuk: Icon(
            ikon,
            color: tehlike ? Renkler.metinTehlikeUstu : Renkler.metinKoyu,
            size: 32,
          ),
        ),
        const SizedBox(height: 12),
        Text(etiket, style: Yazi.kucuk),
      ],
    );
  }
}
