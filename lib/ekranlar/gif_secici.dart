import 'dart:async';

import 'package:flutter/material.dart';

import '../servisler/gif_servisi.dart';
import '../tema.dart';

/// GIF / sticker seçici alt panel. Seçilen GIF'in gönderilecek URL'ini
/// `Navigator.pop(context, url)` ile geri döndürür.
class GifSecici extends StatefulWidget {
  const GifSecici({super.key});

  @override
  State<GifSecici> createState() => _GifSeciciState();
}

class _GifSeciciState extends State<GifSecici> {
  final _aramaCtrl = TextEditingController();
  Timer? _debounce;
  bool _sticker = false;
  bool _yukleniyor = true;
  List<GifSonuc> _sonuclar = const [];

  @override
  void initState() {
    super.initState();
    _getir();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _getir() async {
    setState(() => _yukleniyor = true);
    final r = await GifServisi.instance
        .ara(sorgu: _aramaCtrl.text, sticker: _sticker);
    if (!mounted) return;
    setState(() {
      _sonuclar = r;
      _yukleniyor = false;
    });
  }

  void _aramaDegisti(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _getir);
  }

  void _turDegistir(bool sticker) {
    if (_sticker == sticker) return;
    setState(() => _sticker = sticker);
    _getir();
  }

  @override
  Widget build(BuildContext context) {
    final altBosluk = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: altBosluk),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Renkler.cizgi,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Arama + GIF/Sticker geçişi
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aramaCtrl,
                      onChanged: _aramaDegisti,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _getir(),
                      decoration: InputDecoration(
                        hintText: _sticker ? 'Sticker ara...' : 'GIF ara...',
                        prefixIcon:
                            const Icon(Icons.search, color: Renkler.metinSoluk),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _TurDugme(
                    secili: !_sticker,
                    etiket: 'GIF',
                    onTap: () => _turDegistir(false),
                  ),
                  const SizedBox(width: 8),
                  _TurDugme(
                    secili: _sticker,
                    etiket: 'Sticker',
                    onTap: () => _turDegistir(true),
                  ),
                  const Spacer(),
                  Text('GIPHY',
                      style: Yazi.stil(11, FontWeight.w700, Renkler.metinSoluk,
                          aralik: 1)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _govde()),
          ],
        ),
      ),
    );
  }

  Widget _govde() {
    if (!GifServisi.instance.ayarliMi) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'GIF için GIPHY API anahtarı gerekli.\n'
            'developers.giphy.com → Create an App → API Key\n'
            'Anahtarı lib/servisler/gif_servisi.dart içine yapıştır.',
            textAlign: TextAlign.center,
            style: Yazi.kucuk,
          ),
        ),
      );
    }
    if (_yukleniyor) {
      return const Center(
        child: CircularProgressIndicator(color: Renkler.neon),
      );
    }
    if (_sonuclar.isEmpty) {
      return Center(child: Text('Sonuç bulunamadı', style: Yazi.kucuk));
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _sonuclar.length,
      itemBuilder: (_, i) {
        final g = _sonuclar[i];
        return GestureDetector(
          onTap: () => Navigator.pop(context, g.gonder),
          child: ClipRRect(
            // Organik köşe — tasarım imzası
            borderRadius: Kose.dugme,
            child: Container(
              color: Renkler.yuzeyYuksek,
              child: Image.network(
                g.onizleme,
                fit: BoxFit.cover,
                loadingBuilder: (c, w, p) =>
                    p == null ? w : const SizedBox.shrink(),
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image,
                    color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// GIF / Sticker sekmesi — seçiliyken 3D neon.
class _TurDugme extends StatelessWidget {
  final bool secili;
  final String etiket;
  final VoidCallback onTap;
  const _TurDugme({
    required this.secili,
    required this.etiket,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Uc3DDugme(
      ikincil: !secili,
      kose: Kose.alan,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      onTap: onTap,
      cocuk: Text(
        etiket,
        style: Yazi.stil(
          13,
          FontWeight.w800,
          secili ? Renkler.metinKoyu : Renkler.metinSoluk,
        ),
      ),
    );
  }
}
