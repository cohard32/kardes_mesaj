import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../servisler/arama_servisi.dart';
import '../servisler/hata_servisi.dart';
import '../servisler/ringback_servisi.dart';
import '../tema.dart';

/// Aktif arama ekranı (görüntülü + sesli ortak).
/// Bu ekrana gelindiğinde Agora kanalına ZATEN katılınmış olur
/// (arayan `aramaBaslat`, aranan `kabulEt` çağırmış olur).
class AramaEkrani extends StatefulWidget {
  final String chatId;
  final AramaTipi tip;
  final String baslik; // karşı tarafın adı/e-postası

  /// ARAYAN mıyım? Yalnız arayanda "çalıyor" (ringback) tonu çalar.
  /// ARANAN tarafta zaten CallKit zili çaldı; burada ton çalmamalı.
  final bool benArayanim;

  const AramaEkrani({
    super.key,
    required this.chatId,
    required this.tip,
    required this.baslik,
    this.benArayanim = false,
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
    HataServisi.instance.iz('ARAMA EKRANI acildi tip=${widget.tip.name}');
    // Ekran çizildikten sonra "hazır" işaretini bırak. Bir daha NATIVE çökme
    // olursa son_adim'da nerede öldüğü net görünsün (önceki çökme tam da
    // burada, kamera önizlemesinde oluyordu — artık önizleme çağrılmıyor).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_video) _arama.onizlemeBaslat(); // no-op: yalnız iz bırakır
      HataServisi.instance.sonAdim('EKRAN: arama ekrani HAZIR (tip=${widget.tip.name})');
    });
    _arama.karsiUid.addListener(_baglantiKontrol);
    // ARAYAN "çalıyor" tonu: SADECE arayanda ve karşı taraf henüz katılmadıysa.
    if (widget.benArayanim && _arama.karsiUid.value == null) {
      RingbackServisi.instance.baslat();
    }
    _sub = _arama.aramaDinle(widget.chatId).listen((doc) {
      final durum = doc.data()?['durum'];
      if (durum == 'red') {
        _kapat(mesaj: 'Arama reddedildi');
      } else if (durum == 'mesgul') {
        // Karşı taraf başka bir aramada → boşuna çalmaya devam etme.
        _kapat(mesaj: 'Meşgul');
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
      // Karşı taraf kanala katıldı → konuşma başlıyor, ton DERHAL sussun.
      RingbackServisi.instance.durdur();
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
    RingbackServisi.instance.durdur(); // güvenlik ağı (çift çağrı güvenli)
    if (!_kapandi) _arama.bitir(widget.chatId);
    super.dispose();
  }

  Future<void> _kapat({String? mesaj}) async {
    if (_kapandi) return;
    _kapandi = true;
    HataServisi.instance.iz('ARAMA EKRANI kapaniyor mesaj=${mesaj ?? "-"}');
    RingbackServisi.instance.durdur();
    _sayac?.cancel();
    _zamanAsimi?.cancel();
    _arama.karsiUid.removeListener(_baglantiKontrol);
    await _sub?.cancel();
    await _arama.bitir(widget.chatId);
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
        // Sesli aramada video yok → dengeli dikey düzen.
        // Görüntülü aramada video tam ekran → üstü/altı bindirmeli.
        body: _video ? _videoDuzeni() : _sesliDuzen(),
      ),
    );
  }

  /// Görüntülü arama: uzak görüntü tam ekran, üstte bilgi, altta kontroller.
  Widget _videoDuzeni() {
    return Stack(
      children: [
        Positioned.fill(child: _uzakGorunum()),
        // Kendi görüntün — organik köşe + neon kenar
        if (!_kameraKapali)
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
    );
  }

  /// Sesli arama: ortada avatar + isim + süre, altta kontroller.
  /// (Eskiden tek büyük avatar ortada duruyor, üstü/altı boş kalıyordu.)
  Widget _sesliDuzen() {
    return Zemin(
      parlama: const Alignment(0, -0.75),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            _avatar(cap: 104),
            const SizedBox(height: 24),
            _ustBilgi(),
            const Spacer(flex: 4),
            _kontroller(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Sesli aramada gösterilen gradient avatar.
  Widget _avatar({required double cap}) {
    return Container(
      width: cap,
      height: cap,
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
          Center(
            child: Icon(Icons.person, size: cap * 0.5, color: Renkler.metinKoyu),
          ),
        ],
      ),
    );
  }

  Widget _uzakGorunum() {
    return ValueListenableBuilder<int?>(
      valueListenable: _arama.karsiUid,
      builder: (_, uid, _) {
        final e = _arama.engine;
        final kanal = _arama.aktifKanal;
        // Karşı taraf henüz katılmadı VEYA kanal/motor hazır değil →
        // bekleme + avatar. (Boş kanal adıyla AgoraVideoView kurmak Agora'da
        // hataya/siyah ekrana yol açıyordu.)
        if (uid == null || e == null || kanal == null || kanal.isEmpty) {
          return Zemin(
            child: Center(child: _avatar(cap: 132)),
          );
        }
        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: e,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: kanal),
          ),
        );
      },
    );
  }

  /// KENDİ görüntün (küçük köşe).
  ///
  /// ⚠️ KANALA KATILMADAN OLUŞTURULMAZ. Kanıt zinciri: `son_adim` iki cihazda
  /// da "EKRAN: arama ekrani HAZIR"da duruyor → çökme ekran kurulduktan SONRA.
  /// O andan sonra native olarak oluşan tek şey bu YEREL video yüzeyidir.
  /// `startPreview()` kaldırıldığı için kamera capture'ı `joinChannel`
  /// (publishCameraTrack) ile başlar; katılım TAMAMLANMADAN yerel yüzey
  /// kurmak kamerayı hazır olmadan bağlamaya çalışıp süreci çökertebiliyor.
  /// Bu yüzden `katildi` true olana kadar yer tutucu gösterilir.
  Widget _yerelGorunum() {
    return ValueListenableBuilder<bool>(
      valueListenable: _arama.katildi,
      builder: (_, katildi, _) {
        final e = _arama.engine;
        if (e == null || !katildi) {
          // Henüz hazır değil → native yüzey OLUŞTURMA.
          return const ColoredBox(color: Renkler.yuzey);
        }
        _yerelGorunumIsaretle(); // çökerse son_adim tam burayı gösterir
        return AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: e,
            canvas: const VideoCanvas(uid: 0),
          ),
        );
      },
    );
  }

  bool _yerelIsaretlendi = false;

  /// Yerel video yüzeyi ilk kez oluşturulurken TEK KEZ işaret bırakır.
  /// (build içinden ağ yazımı olmasın diye bayrakla korunur.)
  void _yerelGorunumIsaretle() {
    if (_yerelIsaretlendi) return;
    _yerelIsaretlendi = true;
    HataServisi.instance.sonAdim('EKRAN: YEREL kamera goruntusu olusturuluyor');
  }

  /// İsim + durum rozeti (bağlanıyor / süre) + varsa Agora hatası.
  /// Hem görüntülü hem sesli düzende kullanılır.
  Widget _ustBilgi() {
    return ValueListenableBuilder<int?>(
      valueListenable: _arama.karsiUid,
      builder: (_, uid, _) {
        final bagli = uid != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.baslik, style: Yazi.baslik),
            const SizedBox(height: 10),
            // Durum rozeti — cam yüzey
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: Kutular.duzYuzey(kose: Kose.alan, kenarli: true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bagli) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: Kutular.neonNokta(),
                    ),
                    const SizedBox(width: 8),
                    Text(_sure,
                        style: Yazi.stil(14, FontWeight.w700, Renkler.neon)),
                  ] else ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Renkler.neon),
                    ),
                    const SizedBox(width: 10),
                    Text('Bağlanıyor…', style: Yazi.kucuk),
                  ],
                ],
              ),
            ),
            // Agora bağlantı/token hatası (tanı için)
            ValueListenableBuilder<String?>(
              valueListenable: _arama.sonHata,
              builder: (_, hata, _) => hata == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Text(
                        'Bağlantı hatası: $hata',
                        textAlign: TextAlign.center,
                        style: Yazi.stil(12, FontWeight.w600, Renkler.tehlike),
                      ),
                    ),
            ),
          ],
        );
      },
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
