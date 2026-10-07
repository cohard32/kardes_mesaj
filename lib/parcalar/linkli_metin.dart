import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servisler/link_servisi.dart';
import '../yardimcilar/link_metni.dart';

/// Mesaj metni: içindeki bağlantılar altı çizili ve tıklanabilir.
/// Dokununca tarayıcıda açılır (açılamazsa panoya kopyalanır). Uzun basma
/// balonun menüsüne gider — link üstünde de (dokunma tanıyıcısı uzun basmayı
/// sahiplenmez).
class LinkliMetin extends StatefulWidget {
  final String metin;
  final TextStyle? stil;
  final Color linkRengi;

  const LinkliMetin({
    super.key,
    required this.metin,
    required this.linkRengi,
    this.stil,
  });

  @override
  State<LinkliMetin> createState() => _LinkliMetinState();
}

class _LinkliMetinState extends State<LinkliMetin> {
  List<MetinParcasi> _parcalar = const [];
  final List<GestureRecognizer> _tanimlayicilar = [];

  @override
  void initState() {
    super.initState();
    _hazirla();
  }

  @override
  void didUpdateWidget(LinkliMetin old) {
    super.didUpdateWidget(old);
    // Mesaj düzenlenince metin değişir → parçalar yeniden.
    if (old.metin != widget.metin) _hazirla();
  }

  void _hazirla() {
    _temizle();
    _parcalar = linkleriAyir(widget.metin);
    for (final p in _parcalar) {
      if (!p.linkMi) continue;
      _tanimlayicilar.add(TapGestureRecognizer()..onTap = () => _ac(p.url!));
    }
  }

  Future<void> _ac(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await LinkServisi.instance.ac(url);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Bağlantı açılamadı — panoya kopyalandı')),
      );
    }
  }

  void _temizle() {
    for (final t in _tanimlayicilar) {
      t.dispose();
    }
    _tanimlayicilar.clear();
  }

  @override
  void dispose() {
    _temizle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Link yoksa düz Text (en yaygın durum, en ucuz çizim).
    if (_tanimlayicilar.isEmpty) return Text(widget.metin, style: widget.stil);
    var i = 0;
    return Text.rich(
      TextSpan(
        style: widget.stil,
        children: [
          for (final p in _parcalar)
            if (p.linkMi)
              TextSpan(
                text: p.metin,
                recognizer: _tanimlayicilar[i++],
                style: TextStyle(
                  color: widget.linkRengi,
                  decoration: TextDecoration.underline,
                  decorationColor: widget.linkRengi,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              TextSpan(text: p.metin),
        ],
      ),
    );
  }
}
