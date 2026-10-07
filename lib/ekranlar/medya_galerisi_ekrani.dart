import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../modeller/kullanici.dart';
import '../modeller/mesaj.dart';
import '../parcalar/linkli_metin.dart';
import '../parcalar/onbellekli_resim.dart';
import '../servisler/dosya_servisi.dart';
import '../servisler/mesaj_servisi.dart';
import '../tema.dart';
import '../yardimcilar/mesaj_metni.dart';
import '../yardimcilar/zaman_metni.dart';
import 'medya_goruntuleyici.dart';

/// Bir kişiyle paylaşılan her şey tek ekranda: Medya (foto/video ızgarası),
/// Belgeler, Linkler. Dokununca tam ekran açılır (orada "Galeriye indir").
class MedyaGalerisiEkrani extends StatelessWidget {
  final String chatId;
  final Kullanici karsi;
  final String benimUid;
  const MedyaGalerisiEkrani({
    super.key,
    required this.chatId,
    required this.karsi,
    required this.benimUid,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(karsi.ad),
          bottom: TabBar(
            indicatorColor: Renkler.neon,
            labelColor: Renkler.neon,
            unselectedLabelColor: Renkler.metinSoluk,
            tabs: const [
              Tab(text: 'Medya'),
              Tab(text: 'Belgeler'),
              Tab(text: 'Linkler'),
            ],
          ),
        ),
        body: Zemin(
          child: TabBarView(
            children: [
              _Sekme(
                getir: (limit) =>
                    MesajServisi.instance.medyalar(chatId, limit: limit),
                sayfa: 90,
                bos: 'Henüz fotoğraf ya da video yok',
                kurucu: (c, liste, dahaVar, dahaYukle) =>
                    _MedyaIzgarasi(
                  liste: liste,
                  dahaVar: dahaVar,
                  dahaYukle: dahaYukle,
                  kimden: (m) => m.gonderen == benimUid ? 'Sen' : karsi.ad,
                ),
              ),
              _Sekme(
                getir: (limit) =>
                    MesajServisi.instance.belgeler(chatId, limit: limit),
                sayfa: 60,
                bos: 'Henüz belge yok',
                kurucu: (c, liste, dahaVar, dahaYukle) => _Liste(
                  liste: liste,
                  dahaVar: dahaVar,
                  dahaYukle: dahaYukle,
                  oge: (m) => _BelgeSatiri(mesaj: m),
                ),
              ),
              _Sekme(
                getir: (limit) =>
                    MesajServisi.instance.linkler(chatId, limit: limit),
                sayfa: 60,
                bos: 'Henüz link yok\n(bu sürümden sonra gönderilen linkler '
                    'burada listelenir)',
                kurucu: (c, liste, dahaVar, dahaYukle) => _Liste(
                  liste: liste,
                  dahaVar: dahaVar,
                  dahaYukle: dahaYukle,
                  oge: (m) => _LinkSatiri(
                    mesaj: m,
                    kimden: m.gonderen == benimUid ? 'Sen' : karsi.ad,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bir sekmenin yükleme/hata/sayfalama mantığı.
class _Sekme extends StatefulWidget {
  final Future<List<Mesaj>> Function(int limit) getir;
  final int sayfa;
  final String bos;
  final Widget Function(
    BuildContext context,
    List<Mesaj> liste,
    bool dahaVar,
    VoidCallback dahaYukle,
  ) kurucu;

  const _Sekme({
    required this.getir,
    required this.sayfa,
    required this.bos,
    required this.kurucu,
  });

  @override
  State<_Sekme> createState() => _SekmeState();
}

class _SekmeState extends State<_Sekme>
    with AutomaticKeepAliveClientMixin<_Sekme> {
  late int _limit = widget.sayfa;
  List<Mesaj>? _liste;
  Object? _hata;
  bool _yukleniyor = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (_yukleniyor) return;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final l = await widget.getir(_limit);
      if (!mounted) return;
      setState(() => _liste = l);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata = e);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _dahaYukle() {
    _limit += widget.sayfa;
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final liste = _liste;
    if (_hata != null) {
      // Dizin (index) henüz kurulmadıysa Firestore 'failed-precondition' verir.
      final dizinYok = _hata is FirebaseException &&
          (_hata as FirebaseException).code == 'failed-precondition';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded, color: Renkler.metinSoluk),
              const SizedBox(height: 10),
              Text(
                dizinYok
                    ? 'Galeri hazırlanıyor (sunucuda dizin oluşturuluyor).\n'
                        'Birkaç dakika sonra tekrar dene.'
                    : 'Yüklenemedi. İnternet bağlantını kontrol et.',
                textAlign: TextAlign.center,
                style: Yazi.kucuk,
              ),
              TextButton(onPressed: _yukle, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    if (liste == null) {
      return Center(child: CircularProgressIndicator(color: Renkler.neon));
    }
    if (liste.isEmpty) {
      return Center(
        child: Text(widget.bos, textAlign: TextAlign.center, style: Yazi.kucuk),
      );
    }
    // Tam sayfa geldiyse daha eskisi olabilir.
    final dahaVar = liste.length >= _limit;
    return widget.kurucu(context, liste, dahaVar && !_yukleniyor, _dahaYukle);
  }
}

class _MedyaIzgarasi extends StatelessWidget {
  final List<Mesaj> liste;
  final bool dahaVar;
  final VoidCallback dahaYukle;
  final String Function(Mesaj) kimden;
  const _MedyaIzgarasi({
    required this.liste,
    required this.dahaVar,
    required this.dahaYukle,
    required this.kimden,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final m = liste[i];
                final url = m.medyaUrl;
                if (url == null) return const SizedBox.shrink();
                final video = m.tip == MesajTipi.video;
                final kucuk = video
                    ? (videoKapakUrl(url) == null
                        ? null
                        : kucukResimUrl(videoKapakUrl(url)!, genislik: 360))
                    : kucukResimUrl(url, genislik: 360);
                return GestureDetector(
                  onTap: () => video
                      ? VideoGoruntuleyici.ac(
                          context,
                          url: url,
                          baslik: kimden(m),
                          zaman: m.zaman,
                        )
                      : FotoGoruntuleyici.ac(
                          context,
                          url: url,
                          baslik: kimden(m),
                          zaman: m.zaman,
                        ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: Renkler.yuzey),
                        if (kucuk != null)
                          Image(
                            image: ResizeImage(
                              OnbellekliResim(kucuk),
                              width: (130 * dpr).round(),
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: Renkler.metinSoluk,
                            ),
                          ),
                        if (video)
                          const Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 22,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              childCount: liste.length,
            ),
          ),
        ),
        if (dahaVar)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: dahaYukle,
                child: const Text('Daha eskileri göster'),
              ),
            ),
          ),
      ],
    );
  }
}

class _Liste extends StatelessWidget {
  final List<Mesaj> liste;
  final bool dahaVar;
  final VoidCallback dahaYukle;
  final Widget Function(Mesaj) oge;
  const _Liste({
    required this.liste,
    required this.dahaVar,
    required this.dahaYukle,
    required this.oge,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: liste.length + (dahaVar ? 1 : 0),
      itemBuilder: (_, i) => i < liste.length
          ? oge(liste[i])
          : Center(
              child: TextButton(
                onPressed: dahaYukle,
                child: const Text('Daha eskileri göster'),
              ),
            ),
    );
  }
}

String _tarih(DateTime? t) =>
    t == null ? '' : '${gunAyraciMetni(t)} ${saatMetni(t)}';

class _BelgeSatiri extends StatefulWidget {
  final Mesaj mesaj;
  const _BelgeSatiri({required this.mesaj});

  @override
  State<_BelgeSatiri> createState() => _BelgeSatiriState();
}

class _BelgeSatiriState extends State<_BelgeSatiri> {
  bool _aciliyor = false;

  Future<void> _ac() async {
    final url = widget.mesaj.medyaUrl;
    if (url == null || _aciliyor) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _aciliyor = true);
    final hata = await DosyaServisi.instance
        .ac(url, widget.mesaj.dosyaAdi ?? 'dosya');
    if (!mounted) return;
    setState(() => _aciliyor = false);
    if (hata != null) messenger.showSnackBar(SnackBar(content: Text(hata)));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesaj;
    final ad = m.dosyaAdi ?? 'Dosya';
    return ListTile(
      leading: Container(
        width: 42,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Renkler.yuzeyYuksek,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Renkler.kenar),
        ),
        child: _aciliyor
            ? SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Renkler.neon),
              )
            : Text(
                uzantiEtiketi(ad),
                style: Yazi.stil(11, FontWeight.w800, Renkler.neon),
              ),
      ),
      title: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: Yazi.isim),
      subtitle: Text(
        [
          if (m.dosyaBoyutu != null) boyutMetni(m.dosyaBoyutu!),
          _tarih(m.zaman),
        ].join(' · '),
        style: Yazi.kucuk,
      ),
      onTap: _ac,
    );
  }
}

class _LinkSatiri extends StatelessWidget {
  final Mesaj mesaj;
  final String kimden;
  const _LinkSatiri({required this.mesaj, required this.kimden});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$kimden · ${_tarih(mesaj.zaman)}',
            style: Yazi.kucuk,
          ),
          const SizedBox(height: 4),
          LinkliMetin(
            metin: mesaj.metin,
            stil: Yazi.govde,
            linkRengi: Renkler.neon,
          ),
        ],
      ),
    );
  }
}
