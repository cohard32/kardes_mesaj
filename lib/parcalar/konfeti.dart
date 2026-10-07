import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ekranın üstünden dökülen renkli konfeti (paket gerektirmez). Dokunmayı
/// engellemez; [sure] bitince [onBitti] çağrılır.
class KonfetiYagmuru extends StatefulWidget {
  final Duration sure;
  final VoidCallback? onBitti;
  final int adet;
  const KonfetiYagmuru({
    super.key,
    this.sure = const Duration(milliseconds: 3600),
    this.onBitti,
    this.adet = 90,
  });

  @override
  State<KonfetiYagmuru> createState() => _KonfetiYagmuruState();
}

class _Parca {
  final double x; // 0..1 başlangıç yatay konum
  final double gecikme; // 0..0.35 (sürenin oranı)
  final double hiz; // düşüş hızı çarpanı
  final double salinim; // yatay salınım genliği (px)
  final double faz;
  final double donus; // tur/sn
  final double boy;
  final Color renk;
  final bool daire;
  const _Parca({
    required this.x,
    required this.gecikme,
    required this.hiz,
    required this.salinim,
    required this.faz,
    required this.donus,
    required this.boy,
    required this.renk,
    required this.daire,
  });
}

class _KonfetiYagmuruState extends State<KonfetiYagmuru>
    with SingleTickerProviderStateMixin {
  static const _renkler = [
    Color(0xFFB4FF3C),
    Color(0xFFFF5C8A),
    Color(0xFFFFD23F),
    Color(0xFF4CC9F0),
    Color(0xFFB388FF),
    Color(0xFFFF8A3D),
  ];

  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.sure)
        ..addStatusListener((d) {
          if (d == AnimationStatus.completed) widget.onBitti?.call();
        })
        ..forward();

  late final List<_Parca> _parcalar = () {
    final r = Random();
    return List.generate(
      widget.adet,
      (_) => _Parca(
        x: r.nextDouble(),
        gecikme: r.nextDouble() * 0.35,
        hiz: 0.8 + r.nextDouble() * 0.6,
        salinim: 8 + r.nextDouble() * 22,
        faz: r.nextDouble() * pi * 2,
        donus: 0.5 + r.nextDouble() * 2,
        boy: 6 + r.nextDouble() * 6,
        renk: _renkler[r.nextInt(_renkler.length)],
        daire: r.nextInt(4) == 0,
      ),
    );
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: Size.infinite,
            painter: _KonfetiCizici(_parcalar, _c.value),
          ),
        ),
      ),
    );
  }
}

class _KonfetiCizici extends CustomPainter {
  final List<_Parca> parcalar;
  final double t; // 0..1
  _KonfetiCizici(this.parcalar, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final c in parcalar) {
      final yerel = ((t - c.gecikme) / (1 - c.gecikme)).clamp(0.0, 1.0);
      if (yerel <= 0) continue;
      final y = -20 + yerel * c.hiz * (size.height + 60);
      if (y > size.height + 20) continue;
      final x = c.x * size.width + sin(c.faz + yerel * 10) * c.salinim;
      // Son %20'de solarak kaybolur.
      final saydam = yerel > 0.8 ? (1 - (yerel - 0.8) / 0.2) : 1.0;
      p.color = c.renk.withValues(alpha: saydam.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(yerel * c.donus * pi * 2);
      if (c.daire) {
        canvas.drawCircle(Offset.zero, c.boy / 2.4, p);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: c.boy, height: c.boy * 0.45),
          p,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_KonfetiCizici eski) => eski.t != t;
}

/// Ekranın üstüne bir kez konfeti döker (Overlay; dokunmayı engellemez).
void konfetiPatlat(BuildContext context) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late final OverlayEntry giris;
  giris = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: KonfetiYagmuru(onBitti: () {
        if (giris.mounted) giris.remove();
      }),
    ),
  );
  overlay.insert(giris);
}

/// [anahtar] için konfeti BUGÜN gösterildi mi? Değilse işaretler ve true
/// döner (aynı gün aynı sohbette tekrar tekrar dökülmesin).
Future<bool> bugunIlkKezMi(String anahtar, {DateTime? simdi}) async {
  final s = simdi ?? DateTime.now();
  final gun = '${s.year}-${s.month}-${s.day}';
  try {
    final p = await SharedPreferences.getInstance();
    final k = 'konfeti_$anahtar';
    if (p.getString(k) == gun) return false;
    await p.setString(k, gun);
    return true;
  } catch (_) {
    return false;
  }
}
