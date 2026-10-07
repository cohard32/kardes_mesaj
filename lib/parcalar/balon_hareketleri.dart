import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';

/// Sohbet balonu hareketleri: kaydırarak yanıt ve çift dokunma kalbi.
/// Ayrı dosyada: Firebase'siz widget testleriyle doğrulanabilsin
/// (bkz. test/balon_hareketleri_test.dart).

/// Çift dokununca balonun üstünde büyüyüp sönen ❤️.
class KalpPatlamasi extends StatefulWidget {
  const KalpPatlamasi({super.key});

  @override
  State<KalpPatlamasi> createState() => _KalpPatlamasiState();
}

class _KalpPatlamasiState extends State<KalpPatlamasi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward();

  late final Animation<double> _olcek = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.2, end: 1.25)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 45,
    ),
    TweenSequenceItem(tween: Tween<double>(begin: 1.25, end: 1), weight: 20),
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 35),
  ]).animate(_c);

  late final Animation<double> _saydamlik = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 70),
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 30),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _saydamlik,
      child: ScaleTransition(
        scale: _olcek,
        child: const Text(
          '❤️',
          style: TextStyle(
            fontSize: 46,
            shadows: [Shadow(blurRadius: 12, color: Color(0x66000000))],
          ),
        ),
      ),
    );
  }
}

/// Mesajı SAĞA KAYDIRINCA yanıtlama (WhatsApp gibi): balon parmakla
/// kayar, solda yanıt oku belirir; eşiği geçip bırakınca [onYanit] çağrılır
/// ve balon yerine döner. Sesli mesajın dalgası üstünde kaydırmak ise
/// (içteki tanıyıcı önce kazanır) sesi sarar.
class KaydirarakYanit extends StatefulWidget {
  final Widget child;
  final VoidCallback onYanit;
  const KaydirarakYanit({
    super.key,
    required this.child,
    required this.onYanit,
  });

  @override
  State<KaydirarakYanit> createState() => _KaydirarakYanitState();
}

class _KaydirarakYanitState extends State<KaydirarakYanit>
    with SingleTickerProviderStateMixin {
  static const double _esik = 64;
  static const double _azami = 96;

  double _dx = 0;
  double _donusBasi = 0;
  bool _tetik = false;

  late final AnimationController _donus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() {
      setState(
        () => _dx =
            _donusBasi * (1 - Curves.easeOut.transform(_donus.value)),
      );
    });

  @override
  void dispose() {
    _donus.dispose();
    super.dispose();
  }

  void _guncelle(DragUpdateDetails d) {
    _donus.stop();
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _azami));
    final gecti = _dx >= _esik;
    if (gecti && !_tetik) HapticFeedback.selectionClick();
    _tetik = gecti;
  }

  void _bitir() {
    if (_tetik) widget.onYanit();
    _tetik = false;
    _donusBasi = _dx;
    _donus.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final oran = (_dx / _esik).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _guncelle,
      onHorizontalDragEnd: (_) => _bitir(),
      // İptal (başka hareket kazandı) yanıt TETİKLEMEZ, yalnız geri döner.
      onHorizontalDragCancel: () {
        _tetik = false;
        _bitir();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_dx > 0)
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: oran,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * oran,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _tetik ? Renkler.neon : Renkler.yuzeyYuksek,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        size: 18,
                        color: _tetik ? Renkler.metinKoyu : Renkler.neon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
