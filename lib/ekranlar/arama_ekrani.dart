import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servisler/arama_servisi.dart';
import '../servisler/hata_servisi.dart';
import '../servisler/ringback_servisi.dart';
import '../tema.dart';

/// Karşı tarafın kanaldaki varlığına göre arama aşaması.
enum AramaAsamasi {
  /// Karşı taraf henüz HİÇ katılmadı (çalıyor / bağlanıyor — 45 sn kuralı).
  bekleniyor,

  /// Karşı taraf kanalda, konuşma sürüyor.
  bagli,

  /// Daha önce bağlanmıştı, düştü; geri gelmesi bekleniyor (20 sn kuralı).
  yenidenBaglaniyor,
}

/// [BaglantiTakibi.guncelle]'nin ekrana söylediği olay.
enum BaglantiOlayi { yok, ilkBaglanti, koptu, geriGeldi }

/// Saf karar mantığı (Agora/zamanlayıcı yok → birim testlenebilir).
///
/// ⚠️ NEDEN: Eskiden karşı taraf düşünce (`onUserOffline`) yalnız
/// `karsiUid = null` oluyordu; 45 sn zaman aşımı bağlantıda iptal edildiği
/// için ekran sonsuza dek "Bağlanıyor…"da kalıyordu. "Hiç bağlanmadı" ile
/// "bağlanmıştı, düştü" AYRI durumlardır ve ayrı süre kuralı ister.
class BaglantiTakibi {
  AramaAsamasi _asama = AramaAsamasi.bekleniyor;
  AramaAsamasi get asama => _asama;

  /// Karşı tarafın Agora uid'i değişince çağrılır (null = kanalda değil).
  BaglantiOlayi guncelle(int? uid) {
    if (uid != null) {
      switch (_asama) {
        case AramaAsamasi.bekleniyor:
          _asama = AramaAsamasi.bagli;
          return BaglantiOlayi.ilkBaglanti;
        case AramaAsamasi.yenidenBaglaniyor:
          _asama = AramaAsamasi.bagli;
          return BaglantiOlayi.geriGeldi;
        case AramaAsamasi.bagli:
          return BaglantiOlayi.yok; // zaten bağlı (uid değişmiş olabilir)
      }
    }
    if (_asama == AramaAsamasi.bagli) {
      _asama = AramaAsamasi.yenidenBaglaniyor;
      return BaglantiOlayi.koptu;
    }
    // Hiç bağlanmamışken null → 45 sn kuralı geçerli, burada iş yok.
    return BaglantiOlayi.yok;
  }

  /// 45 sn "Cevap verilmedi" zaman aşımı dolduğunda aramayı kapatmalı mı?
  /// ⚠️ YALNIZ hiç bağlanılmamışken. Eskiden zamanlayıcı yalnız
  /// `karsiUid == null`'a bakıyordu: ilk 45 sn içindeki bir KOPMA
  /// (yenidenBaglaniyor) 20 sn yeniden bağlanma kuralını atlayıp yanlış
  /// mesajla ("Cevap verilmedi") görüşmeyi kapatıyordu.
  bool get cevapsizKapatilmali => _asama == AramaAsamasi.bekleniyor;
}

/// `aramalar/{chatId}` belgesindeki değişimin ekrana söylediği olay.
enum BelgeOlayi { yok, devralindi, reddedildi, mesgul, bitti }

/// Saf karar: arama belgesinin son hâli bu ekran için ne demek?
/// [benimKanal] ekranın katıldığı kanal (açılışta [AramaServisi.aktifKanal]).
///
/// ⚠️ KANAL, DURUMDAN ÖNCE bakılır: belge sohbetin ORTAK belgesidir; içinde
/// başka kanal varsa oradaki durum (çalıyor/red/bitti) YENİ aramaya aittir.
/// Eski ekran onu kendi görüşmesi sanıp 'bitti' yazar, iptal push'u gönderir
/// ve çalan zili kapatırsa yeni aramayı düşürür → yalnız sessizce çekilmeli
/// (bkz. [aramaDevralindiMi]). Anlık görüntüler birleşebildiği için ara
/// 'cagriliyor' hiç görülmeyip doğrudan yeni kanallı 'red'/'bitti' de
/// gelebilir; o da devralmadır ("Arama reddedildi" denmez).
BelgeOlayi aramaBelgesiOlayi(Map<String, dynamic>? veri, {String? benimKanal}) {
  if (veri == null) return BelgeOlayi.yok;
  final kanal = veri['kanal'];
  if (aramaDevralindiMi(
    benimKanal: benimKanal,
    belgeKanali: kanal is String ? kanal : null,
  )) {
    return BelgeOlayi.devralindi;
  }
  switch (veri['durum']) {
    case 'red':
      return BelgeOlayi.reddedildi;
    case 'mesgul':
      return BelgeOlayi.mesgul;
    case 'bitti':
      return BelgeOlayi.bitti;
    default:
      return BelgeOlayi.yok;
  }
}

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
  Timer? _yenidenBaglanma;
  final _takip = BaglantiTakibi();

  /// Bu ekranın ait olduğu görüşme oturumu (bkz. AramaServisi.oturumVN).
  late final int _oturum;

  /// Bu ekranın görüşmesinin Agora kanalı (devralma tespiti için).
  String? _kanal;
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
    // Ekran aramaBaslat/kabulEt BİTTİKTEN sonra açılır → şimdiki oturum bu
    // ekranın görüşmesidir.
    _oturum = _arama.oturum;
    _kanal = _arama.aktifKanal;
    HataServisi.instance.iz('ARAMA EKRANI acildi tip=${widget.tip.name} '
        'oturum=$_oturum kanal=${_kanal ?? "-"}');
    // Ekran çizildikten sonra "hazır" işaretini bırak. Bir daha NATIVE çökme
    // olursa son_adim'da nerede öldüğü net görünsün (önceki çökme tam da
    // burada, kamera önizlemesinde oluyordu — artık önizleme çağrılmıyor).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HataServisi.instance
          .sonAdim('EKRAN: arama ekrani HAZIR (tip=${widget.tip.name})');
      // Kamerayı ANCAK ekran görünürken yayına al (arka planda kamera açma
      // yasağı yüzünden görüntülü kabul tam burada ölüyordu).
      if (_video) _arama.kamerayiYayinaAl();
    });
    // Karşı taraf 45 sn içinde katılmazsa aramayı kapat.
    // ⚠️ İlk _baglantiKontrol()'den ÖNCE kurulur: arananda karşı taraf zaten
    // kanalda olduğundan o çağrı ilkBaglanti görüp `_zamanAsimi?.cancel()`
    // yapar. Eskiden zamanlayıcı SONRA kuruluyordu → iptal boşa gidiyor,
    // zamanlayıcı hep çalışır kalıyordu.
    _zamanAsimi = Timer(const Duration(seconds: 45), () {
      if (!_kapandi && _takip.cevapsizKapatilmali) {
        _kapat(mesaj: 'Cevap verilmedi');
      }
    });
    _arama.karsiUid.addListener(_baglantiKontrol);
    _arama.oturumVN.addListener(_oturumKontrol);
    // ARAYAN "çalıyor" tonu: SADECE arayanda ve karşı taraf henüz katılmadıysa.
    if (widget.benArayanim && _arama.karsiUid.value == null) {
      RingbackServisi.instance.baslat();
    }
    // ⚠️ Mevcut değeri BİR KEZ işle: arananda arayan kanalda zaten beklediği
    // için `onUserJoined` ekran açılmadan ÖNCE gelebiliyor; dinleyici yalnız
    // DEĞİŞİMLERİ duyar → süre sayacı başlamıyor, takip "hiç bağlanmadı"
    // sanıp sonraki kopmayı da kaçırıyordu.
    _baglantiKontrol();
    _sub = _arama.aramaDinle(widget.chatId).listen((doc) {
      switch (aramaBelgesiOlayi(doc.data(), benimKanal: _kanal)) {
        case BelgeOlayi.devralindi:
          // Aynı sohbetten YENİ arama (farklı kanal) — bu cihazda çalıyor
          // olabilir. Oturum henüz değişmedi (kabulEt başlamadı) → 20/45 sn
          // sayaçları yeni aramayı düşürmeden ÖNCE sessizce çekil.
          _cekil(yerelTemizlik: true, neden: 'belgede yeni kanal');
        case BelgeOlayi.reddedildi:
          _kapat(mesaj: 'Arama reddedildi');
        case BelgeOlayi.mesgul:
          // Karşı taraf başka bir aramada → boşuna çalmaya devam etme.
          _kapat(mesaj: 'Meşgul');
        case BelgeOlayi.bitti:
          _kapat();
        case BelgeOlayi.yok:
          break;
      }
    });
  }

  /// Yeni bir aramaBaslat/kabulEt bu ekranın görüşmesini DEVRALDI mı?
  /// (Aynı sohbetten yeniden arama: karşı tarafın uygulaması çökmüş/kopmuş.)
  /// ⚠️ Devralındıysa bitir() ÇAĞRILMAZ: AramaServisi tekil olduğu için
  /// YENİ görüşmenin motorunu bırakıp 'bitti' yazar, onu da düşürürdü.
  /// Eski motoru zaten yeni oturumun _engineHazirla'sı kapatır.
  void _oturumKontrol() {
    if (_kapandi) return;
    if (oturumGuncelMi(istenen: _oturum, guncel: _arama.oturum)) return;
    // Eski motoru yeni oturumun _engineHazirla'sı kapatır → yerel temizlik
    // BURADA YAPILMAZ (yeni görüşmenin bayraklarını/kaydını silerdi).
    _cekil(
      yerelTemizlik: false,
      neden: 'oturum $_oturum → ${_arama.oturum}',
    );
  }

  /// Görüşme devralındı: bitir() ÇAĞIRMADAN ('bitti' yok, iptal push'u yok,
  /// endAllCalls yok) kapan. [yerelTemizlik]: oturum hâlâ bizimse eski
  /// motoru/bayrakları servis bıraksın (bkz. AramaServisi.devredildi).
  void _cekil({required bool yerelTemizlik, required String neden}) {
    if (_kapandi) return;
    HataServisi.instance
        .iz('ARAMA EKRANI devredildi ($neden), bitir cagrilmadan kapaniyor');
    _kapandi = true;
    _zamanlayicilariBirak();
    _sub?.cancel();
    if (yerelTemizlik) _arama.devredildi(widget.chatId, oturum: _oturum);
    if (mounted) _rotayiKapat();
  }

  void _zamanlayicilariBirak() {
    RingbackServisi.instance.durdur();
    _sayac?.cancel();
    _zamanAsimi?.cancel();
    _yenidenBaglanma?.cancel();
    _arama.karsiUid.removeListener(_baglantiKontrol);
    _arama.oturumVN.removeListener(_oturumKontrol);
  }

  /// Bu ekranın KENDİ rotasını kapatır. ⚠️ `Navigator.pop()` değil: pop
  /// EN ÜSTTEKİ rotayı kapatır; devralmada yeni arama ekranı bunun üstüne
  /// açılmış olabilir → yanlış ekranı (yeni görüşmeyi) kapatırdı.
  void _rotayiKapat() {
    final rota = ModalRoute.of(context);
    if (rota == null || !rota.isActive) return;
    if (rota.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(rota);
    }
  }

  void _baglantiKontrol() {
    if (_kapandi) return;
    switch (_takip.guncelle(_arama.karsiUid.value)) {
      case BaglantiOlayi.ilkBaglanti:
        // Karşı taraf kanala katıldı → konuşma başlıyor, ton DERHAL sussun.
        RingbackServisi.instance.durdur();
        _zamanAsimi?.cancel();
        // Süre sayacı kopmada DURMAZ: gösterilen süre görüşmenin toplam
        // süresidir (telefon uygulamalarındaki gibi). Kopukken rozet süre
        // yerine "Yeniden bağlanıyor…" gösterdiği için akan sayaç görünmez;
        // geri gelince doğru toplam süre görünür.
        _sayac ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _saniye++);
        });
      case BaglantiOlayi.koptu:
        // Bağlıyken düştü (ağ, uygulama çökmesi). Karşı taraf bilerek kapattıysa
        // Firestore 'bitti' zaten ekranı kapatır; bu süre çökme/ağ kaybı için.
        HataServisi.instance.iz('ARAMA EKRANI karsi taraf dustu, 20 sn bekleniyor');
        _yenidenBaglanma?.cancel();
        _yenidenBaglanma = Timer(const Duration(seconds: 20), () {
          if (!_kapandi && _takip.asama == AramaAsamasi.yenidenBaglaniyor) {
            _kapat(mesaj: 'Bağlantı koptu');
          }
        });
      case BaglantiOlayi.geriGeldi:
        HataServisi.instance.iz('ARAMA EKRANI karsi taraf geri geldi');
        _yenidenBaglanma?.cancel();
        _yenidenBaglanma = null;
      case BaglantiOlayi.yok:
        break;
    }
  }

  @override
  void dispose() {
    // Ringback durdurma burada da var: güvenlik ağı (çift çağrı güvenli).
    _zamanlayicilariBirak();
    _sub?.cancel();
    // Kendi oturumu geçirilir: görüşme devralındıysa bitir hiçbir şeye dokunmaz.
    if (!_kapandi) _arama.bitir(widget.chatId, oturum: _oturum);
    super.dispose();
  }

  Future<void> _kapat({String? mesaj}) async {
    if (_kapandi) return;
    _kapandi = true;
    HataServisi.instance.iz('ARAMA EKRANI kapaniyor mesaj=${mesaj ?? "-"}');
    _zamanlayicilariBirak();
    await _sub?.cancel();
    // bitir() artık yalnız YEREL işleri bekler (ağ yok) → çevrimdışıyken de
    // ekran hemen kapanır. Kendi oturumu: devralındıysa yeni görüşmeye dokunmaz.
    await _arama.bitir(widget.chatId, oturum: _oturum);
    if (!mounted) return;
    if (mesaj != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mesaj)));
    }
    _rotayiKapat();
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
    final sahne = Stack(
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
    // ⚠️ Açık temada sahne koyu kalır (bkz. VideoSahne) → durum çubuğu
    // ikonları da açık olmalı; yoksa koyu ikon videonun üstünde kaybolur.
    // Koyu paletlerde global stil zaten açık ikonlu → sarmalama yok.
    if (!VideoSahne.koyuyaZorla) return sahne;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: VideoSahne.sistemCubuklari,
      child: sahne,
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
          // ⚠️ Açık temada video sahnesi koyu kalır (başlık yazısı bu
          // zeminin ve sonra gelecek videonun üstünde açık renkte durur).
          if (VideoSahne.koyuyaZorla) {
            return ColoredBox(
              color: VideoSahne.zemin,
              child: Center(child: _avatar(cap: 132)),
            );
          }
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
          return ColoredBox(color: VideoSahne.yerTutucu);
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

  /// İsim + durum rozeti (bağlanıyor / yeniden bağlanıyor / süre) + varsa
  /// Agora hatası.
  /// Hem görüntülü hem sesli düzende kullanılır.
  Widget _ustBilgi() {
    return ValueListenableBuilder<int?>(
      valueListenable: _arama.karsiUid,
      builder: (_, uid, _) {
        final bagli = uid != null;
        // `_takip` dinleyicide (karsiUid'e İLK eklenen) güncellenir; bu
        // builder aynı değişimle sonra kurulduğu için aşama zaten günceldir.
        final yenidenBaglaniyor =
            _takip.asama == AramaAsamasi.yenidenBaglaniyor;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️ Görüntülü aramada başlık doğrudan VİDEONUN üstünde (zemini
            // yok) → açık temada da açık renk (VideoSahne). Sesli aramada
            // paletin zemini üstünde → normal metin rengi.
            Text(
              widget.baslik,
              style: _video
                  ? Yazi.baslik.copyWith(color: VideoSahne.metin)
                  : Yazi.baslik,
            ),
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
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Renkler.neon),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      yenidenBaglaniyor ? 'Yeniden bağlanıyor…' : 'Bağlanıyor…',
                      style: Yazi.kucuk,
                    ),
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
            cocuk: Icon(Icons.call_end,
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
