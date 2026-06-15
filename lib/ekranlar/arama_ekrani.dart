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
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: _uzakGorunum()),
            if (_video && !_kameraKapali)
              Positioned(
                top: 44,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
          return Container(
            color: Renkler.zemin,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: Renkler.accent),
                SizedBox(height: 16),
                Text('Bağlanıyor...',
                    style: TextStyle(color: Renkler.metinSoluk)),
              ],
            ),
          );
        }
        final e = _arama.engine;
        if (!_video || e == null) {
          // Sesli arama: video yok → avatar
          return Container(
            color: Renkler.zemin,
            alignment: Alignment.center,
            child: const CircleAvatar(
              radius: 60,
              backgroundColor: Renkler.kardesBalon,
              child: Icon(Icons.person, size: 70, color: Renkler.metinSoluk),
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
    if (e == null) return const ColoredBox(color: Renkler.kardesBalon);
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
        Text(
          widget.baslik,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          bagli ? _sure : (_video ? 'Görüntülü arama' : 'Sesli arama'),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
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
          arka: _micKapali ? Colors.white24 : Colors.white10,
          onTap: () {
            setState(() => _micKapali = !_micKapali);
            _arama.mikrofonKapat(_micKapali);
          },
        ),
        if (_video) ...[
          _dugme(
            ikon: _kameraKapali ? Icons.videocam_off : Icons.videocam,
            arka: _kameraKapali ? Colors.white24 : Colors.white10,
            onTap: () {
              setState(() => _kameraKapali = !_kameraKapali);
              _arama.kameraKapat(_kameraKapali);
            },
          ),
          _dugme(
            ikon: Icons.cameraswitch,
            arka: Colors.white10,
            onTap: _arama.kameraDegistir,
          ),
        ],
        _dugme(
          ikon: _hoparlor ? Icons.volume_up : Icons.volume_down,
          arka: _hoparlor ? Colors.white24 : Colors.white10,
          onTap: () {
            setState(() => _hoparlor = !_hoparlor);
            _arama.hoparlor(_hoparlor);
          },
        ),
        _dugme(
          ikon: Icons.call_end,
          arka: Colors.red,
          buyuk: true,
          onTap: _kapat,
        ),
      ],
    );
  }

  Widget _dugme({
    required IconData ikon,
    required Color arka,
    required VoidCallback onTap,
    bool buyuk = false,
  }) {
    final cap = buyuk ? 64.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: arka,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: cap,
            height: cap,
            child: Icon(ikon, color: Colors.white, size: buyuk ? 30 : 26),
          ),
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const CircleAvatar(
              radius: 56,
              backgroundColor: Renkler.kardesBalon,
              child: Icon(Icons.person, size: 64, color: Renkler.metinSoluk),
            ),
            const SizedBox(height: 24),
            Text(
              widget.arayan,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              video ? 'Görüntülü arama...' : 'Sesli arama...',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _aramaDugme(
                  ikon: Icons.call_end,
                  renk: Colors.red,
                  etiket: 'Reddet',
                  onTap: _islemde ? null : _reddet,
                ),
                _aramaDugme(
                  ikon: video ? Icons.videocam : Icons.call,
                  renk: Colors.green,
                  etiket: 'Kabul Et',
                  onTap: _islemde ? null : _kabul,
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _aramaDugme({
    required IconData ikon,
    required Color renk,
    required String etiket,
    required VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: renk,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(ikon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(etiket, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
