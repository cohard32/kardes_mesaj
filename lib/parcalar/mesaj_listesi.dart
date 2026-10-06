import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../modeller/mesaj.dart';

/// Sohbet ekranının mesaj listesi (kaydırma mantığı). Firebase'e dokunmaz →
/// widget testleriyle doğrulanır (bkz. test/mesaj_listesi_test.dart).
///
/// [mesajlar] YENİDEN ESKİYE sıralıdır (index 0 = en yeni), tıpkı
/// `MesajServisi.mesajlariDinle` akışı gibi.
///
/// ⚠️ NEDEN İKİ SLIVER: Eskiden tek bir `ListView(reverse: true)` vardı. En
/// yeni mesaj index 0'da olduğundan HER yeni mesaj bütün index'leri bir
/// kaydırıyordu: (1) kullanıcı yukarıda geçmişi okurken görünen içerik her
/// gelen mesajda bir balon yukarı sıçrıyordu (okuduğu yeri kaybediyordu);
/// (2) anahtarsız balonların State'i index'te kalıp BAŞKA mesaja geçiyordu
/// (oynayan video kesiliyor ya da yeni videonun balonunda eski video
/// oynuyordu). Artık `CustomScrollView(center: ...)`:
///
///   * MERKEZ sliver (offset 0'dan YUKARI büyür): açılışta gelen mesajlar +
///     sonradan yüklenen ESKİ sayfalar. Eski sayfa bu listenin SONUNA (ekranın
///     üstüne) eklenir → görünen mesajlar yerinden oynamaz.
///   * YENİ sliver (offset 0'dan AŞAĞI büyür): kullanıcı alttan uzaktayken
///     gelen mesajlar. Görüntü alanının ALTINA eklenir; kaydırma ofseti ve
///     merkez sliver'ın düzeni değişmediği için görünen içerik KAYMAZ.
///
/// İkisinin sınırı bir "çapa" mesajdır ([_capaId] = merkezdeki en yeni mesaj).
/// Kullanıcı en alttayken ya da kendi mesajı gelince [_altaIn] çapayı en yeni
/// mesaja taşır (yeni sliver merkeze katılır) ve ofseti en alta (-[dikeyBosluk])
/// atar: bu konum yüksekliklerden bağımsız, KESİN olarak "en alt"tır.
///
/// Her öğe mesaj kimliğine bağlı bir GlobalKey taşır: State (oynayan video,
/// ses dalgası) liste içinde VE yeni→merkez birleşmesinde mesajla birlikte
/// taşınır (ValueKey yalnız aynı sliver içinde korurdu).
class MesajListesi extends StatefulWidget {
  const MesajListesi({
    super.key,
    required this.mesajlar,
    required this.ogeKurucu,
    required this.benimUid,
    this.eskiYukle,
    this.controller,
    this.yatayBosluk = 12,
    this.dikeyBosluk = 12,
  });

  /// YENİDEN ESKİYE sıralı mesajlar (index 0 = en yeni).
  final List<Mesaj> mesajlar;

  /// Tek bir mesajın balonunu kurar (anahtarı liste kendisi verir).
  final Widget Function(BuildContext context, Mesaj mesaj) ogeKurucu;

  /// Bu kullanıcının gönderdiği YENİ mesaj gelince liste en alta iner.
  final String benimUid;

  /// Kullanıcı en üste yaklaşınca çağrılır (daha eski sayfa). `null` = daha
  /// eski mesaj yok. Aynı sayfa için bir kez çağrılır: yeniden istemek için
  /// listenin en eski mesajı değişmelidir (yeni sayfa geldi).
  final VoidCallback? eskiYukle;

  /// Verilmezse liste kendi denetleyicisini kurar. Verilirse
  /// `initialScrollOffset: -dikeyBosluk` ile kurulmalıdır (en alt = -alt
  /// boşluk; bkz. sınıf notu), yoksa ilk karede alt boşluk görünmez.
  final ScrollController? controller;

  final double yatayBosluk;
  final double dikeyBosluk;

  /// En alta bu kadar (px) yakınken gelen mesaj "takip edilir" (alta inilir).
  static const double altEsigi = 80;

  /// En üste bu kadar (px) yaklaşınca [eskiYukle] çağrılır.
  static const double eskiYukleEsigi = 400;

  @override
  State<MesajListesi> createState() => _MesajListesiState();
}

/// Mesaj kimliğine bağlı GlobalKey (eşitlik = kimlik; her id için tek örnek).
class _MesajAnahtari extends GlobalKey<State<StatefulWidget>> {
  const _MesajAnahtari(this.id) : super.constructor();
  final String id;
}

class _MesajListesiState extends State<MesajListesi> {
  final Key _merkez = const ValueKey<String>('mesaj_listesi_merkez');
  ScrollController? _ic;
  ScrollController get _ctrl => widget.controller ?? _ic!;

  /// Merkez sliver'daki EN YENİ mesajın kimliği. Bundan daha yeni olanlar
  /// yeni sliver'da durur.
  String? _capaId;

  /// Birleşmede merkez SliverList'i YENİDEN kurmak için (bkz. [_altaIn]).
  int _nesil = 0;

  final Map<String, _MesajAnahtari> _anahtarlar = <String, _MesajAnahtari>{};
  bool _altaInPlanli = false;
  bool _eskiIstendi = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _ic = _icDenetleyici();
    _ctrl.addListener(_kaydirmaDinle);
    _capaId = widget.mesajlar.isEmpty ? null : widget.mesajlar.first.id;
    _kareSonra(_eskiKontrol);
  }

  // keepScrollOffset: false → PageStorage eski bir ofseti geri yüklemesin
  // (liste boş durumdan dönüp yeniden kurulunca en altta açılmalı).
  ScrollController _icDenetleyici() => ScrollController(
    initialScrollOffset: -widget.dikeyBosluk,
    keepScrollOffset: false,
  );

  @override
  void didUpdateWidget(MesajListesi old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ic)?.removeListener(_kaydirmaDinle);
      if (widget.controller == null) {
        _ic ??= _icDenetleyici();
      } else {
        _ic?.dispose();
        _ic = null;
      }
      _ctrl.addListener(_kaydirmaDinle);
    }
    if (old.eskiYukle == null && widget.eskiYukle != null) {
      _eskiIstendi = false;
    }
    if (identical(old.mesajlar, widget.mesajlar)) return;
    _mesajlarDegisti(old.mesajlar, widget.mesajlar);
    _kareSonra(_eskiKontrol);
  }

  void _mesajlarDegisti(List<Mesaj> eski, List<Mesaj> yeni) {
    final yeniIdler = <String>{for (final m in yeni) m.id};
    _anahtarlar.removeWhere((id, _) => !yeniIdler.contains(id));
    // En eski mesaj değişti = yeni sayfa geldi (ya da pencere kaydı) →
    // üste yaklaşınca yeniden istenebilir.
    if (eski.isEmpty || yeni.isEmpty || eski.last.id != yeni.last.id) {
      _eskiIstendi = false;
    }
    if (yeni.isEmpty) {
      _capaId = null;
      return;
    }
    final capaId = _capaId;
    if (capaId == null) {
      _capaId = yeni.first.id;
      return;
    }
    var capa = _indeks(yeni, capaId);
    if (capa < 0) {
      // Çapa mesajı silindi → eski listede ondan sonra gelen (daha eski) ilk
      // hayatta kalan mesaj yeni çapa olur: merkezin içeriği yalnız silinen
      // mesaj kadar değişir.
      final i = _indeks(eski, capaId);
      String? aday;
      if (i >= 0) {
        for (var j = i + 1; j < eski.length; j++) {
          if (yeniIdler.contains(eski[j].id)) {
            aday = eski[j].id;
            break;
          }
        }
      }
      if (aday == null) {
        // Tutunacak bir şey kalmadı → baştan kur, en alta in.
        _capaId = yeni.first.id;
        _altaInPlanla();
        return;
      }
      _capaId = aday;
      capa = _indeks(yeni, aday);
    }
    // ⚠️ SIRA DEĞİŞİMİ ÇAPAYI AŞABİLİR: Firestore'da yerelde bekleyen
    // serverTimestamp gerçek zamanlardan farklı sıralanır; onay gelince mesaj
    // gerçek zamanına göre YER DEĞİŞTİRİR. Ör. kendi mesajım A (çapa) bekliyor,
    // karşının X'i sunucuda A'dan sonra işlendi ama A'nın onayından önce geldi:
    // sıra [A, X] → onayla [X, A]. X önceki listede olduğundan "yeni gelen"
    // sayılmaz; çapa A'da kalsaydı X merkezden yeni sliver'a (görüntü alanının
    // ALTINA) düşer, en alttaki kullanıcı okuduğu mesajı kaybederdi; geçmişi
    // okurken de merkezden çıkan mesajın boyu kadar görünen içerik kayardı.
    // Bu yüzden önceden MERKEZDE olup artık çapanın üstüne geçen mesaj varsa
    // çapa ona taşınır: merkez aynı mesajları tutar (yalnız kendi içinde yer
    // değiştirir, toplam yükseklik aynı) → üstündeki geçmiş kaymaz, en altta
    // yeni sıra doğrudan görünür.
    final eskiCapa = _indeks(eski, capaId);
    if (eskiCapa >= 0 && capa > 0) {
      final eskiMerkez = <String>{for (final m in eski.skip(eskiCapa)) m.id};
      for (var k = 0; k < capa; k++) {
        if (eskiMerkez.contains(yeni[k].id)) {
          capa = k;
          _capaId = yeni[k].id;
          break;
        }
      }
    }
    // Çapadan DAHA YENİ ve önceki listede olmayanlar = yeni gelen mesajlar.
    // (Eski sayfa çapanın arkasına eklenir; onlar burada sayılmaz → sayfalama
    // asla "kendi mesajım geldi, alta in" sanılmaz.)
    final eskiIdler = <String>{for (final m in eski) m.id};
    final gelenler = yeni.take(capa).where((m) => !eskiIdler.contains(m.id));
    // ⚠️ "Zorla kaydır" BAYRAĞI YOK: eskiden gönderen ekran bir bayrak
    // kuruyordu; medya gönderiminde bayrak mesaj geldikten SONRA kuruluyor,
    // askıda kalıp dakikalar sonra karşının ilgisiz mesajında listeyi dibe
    // çekiyordu. Artık "kendi mesajım" doğrudan gelen mesajdan anlaşılır.
    final kendi = gelenler.any((m) => m.gonderen == widget.benimUid);
    // ⚠️ Alta takip "yeni mesaj geldi mi"ye değil KONUMA bağlı: en alttayken
    // çapanın üstünde (yeni sliver'da, ekranın altında) herhangi bir mesaj
    // varsa — yeni gelmiş ya da sıra değişimiyle oraya geçmiş olsun — hemen
    // merkeze katılıp dibe inilir. Yalnız "gelenler"e bakılsaydı, var olan bir
    // mesajın çapanın üstüne kayması (yukarıdaki düzeltmenin kapsamadığı,
    // ör. yeni sliver'dan merkeze/merkezden yeniye karışık sıralar) en alttaki
    // kullanıcıdan mesajı gizlerdi.
    if (kendi || (capa > 0 && _alttaMi(MesajListesi.altEsigi))) {
      _altaInPlanla();
    }
  }

  static int _indeks(List<Mesaj> liste, String id) {
    for (var i = 0; i < liste.length; i++) {
      if (liste[i].id == id) return i;
    }
    return -1;
  }

  /// Yeni sliver'daki mesaj sayısı (= çapanın index'i).
  int _yeniSayisi() {
    final capaId = _capaId;
    if (capaId == null) return 0;
    final i = _indeks(widget.mesajlar, capaId);
    return i < 0 ? 0 : i;
  }

  bool _alttaMi(double esik) {
    if (!_ctrl.hasClients) return true;
    final p = _ctrl.position;
    if (!p.hasContentDimensions || !p.hasPixels) return true;
    return p.pixels - p.minScrollExtent <= esik;
  }

  void _kareSonra(VoidCallback cb) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _altaInPlanla() {
    if (_altaInPlanli) return;
    _altaInPlanli = true;
    // Kare SONRASI: ofset değişikliği build sırasında yapılamaz; bu karede yeni
    // mesaj görüntü alanının altında (görünmez) çizilir, içerik kaymaz.
    _kareSonra(() {
      _altaInPlanli = false;
      _altaIn();
    });
  }

  /// Yeni sliver'ı merkeze katar ve EN ALTA iner. Birleşme ile atlama aynı
  /// karede uygulanır → ara durum hiç çizilmez.
  void _altaIn() {
    final m = widget.mesajlar;
    final hedef = m.isEmpty ? null : m.first.id;
    // ⚠️ Birleşmede merkez SliverList YENİDEN kurulur (_nesil): yerinde
    // güncellenseydi tüm index'ler kayar ve SliverList, taşınan çocuklara eski
    // index'lerin konumlarını verirdi. Uzaktan (index 0 kurulu değilken) en
    // alta atlayınca bu tahmin tutmuyor, Flutter ofseti "düzeltip" listeyi
    // dipten birkaç piksel kaydırıyordu. Taze liste index 0'dan dizilir →
    // en alt KESİN. Öğelerin State'i GlobalKey ile yeni listeye taşınır.
    if (hedef != _capaId) {
      setState(() {
        _capaId = hedef;
        _nesil++;
      });
    }
    if (_ctrl.hasClients && _ctrl.position.hasPixels) {
      // -dikeyBosluk eski ve yeni boyutlarda her zaman geçerli aralıktadır
      // (min <= -alt boşluk <= 0 <= max).
      final alt = -widget.dikeyBosluk;
      if (_ctrl.position.pixels != alt) _ctrl.jumpTo(alt);
    }
  }

  /// Kullanıcı kaydırmayı en altta bitirdiyse bekleyen yeni mesajları
  /// merkeze kat. En alttayken görünüm birebir aynıdır (alt kenar = alt
  /// boşluğun sonu, sıra ve yükseklikler aynı) → göze görünmez.
  /// Böylece yeni sliver büyüyüp durmaz; kısa sohbette de boşluk kalmaz.
  bool _kaydirmaBitti(ScrollEndNotification n) {
    if (n.depth != 0) return false; // balon içindeki başka bir kaydırılabilir
    if (_yeniSayisi() > 0 && _alttaMi(0.5)) _kareSonra(_altaIn);
    return false;
  }

  void _kaydirmaDinle() => _eskiKontrol();

  void _eskiKontrol() {
    final yukle = widget.eskiYukle;
    if (yukle == null || _eskiIstendi || !_ctrl.hasClients) return;
    final p = _ctrl.position;
    if (!p.hasContentDimensions || !p.hasPixels) return;
    if (p.pixels < p.maxScrollExtent - MesajListesi.eskiYukleEsigi) return;
    // Build/layout sırasında (ör. boyut değişiminde gelen bildirim) üst
    // ekranın setState'i hata verir → kare sonrasına ertele.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _kareSonra(_eskiKontrol);
      return;
    }
    _eskiIstendi = true;
    yukle();
  }

  _MesajAnahtari _anahtar(String id) =>
      _anahtarlar.putIfAbsent(id, () => _MesajAnahtari(id));

  SliverChildBuilderDelegate _delege(List<Mesaj> liste) {
    final indeks = <String, int>{
      for (var i = 0; i < liste.length; i++) liste[i].id: i,
    };
    return SliverChildBuilderDelegate(
      (context, i) {
        final m = liste[i];
        return KeyedSubtree(
          key: _anahtar(m.id),
          child: widget.ogeKurucu(context, m),
        );
      },
      childCount: liste.length,
      // State'ler index'te değil MESAJDA kalsın (bkz. sınıf notu).
      findChildIndexCallback: (key) =>
          key is _MesajAnahtari ? indeks[key.id] : null,
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_kaydirmaDinle);
    _ic?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesajlar;
    final bolum = _yeniSayisi();
    // Yeni sliver merkezden AŞAĞI büyür: index 0 = merkeze bitişik olan
    // (yenilerin en eskisi), son index = en yeni (en altta).
    final yeniler = m.sublist(0, bolum).reversed.toList(growable: false);
    final eskiler = m.sublist(bolum);
    final yatay = widget.yatayBosluk;
    return NotificationListener<ScrollEndNotification>(
      onNotification: _kaydirmaBitti,
      child: CustomScrollView(
        controller: _ctrl,
        reverse: true,
        center: _merkez,
        slivers: [
          // Merkezden önceki sliver'lar TERS sırayla dizilir: bu boşluk
          // yeni mesajların da ALTINDA, listenin en dibindedir.
          SliverToBoxAdapter(child: SizedBox(height: widget.dikeyBosluk)),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: yatay),
            sliver: SliverList(delegate: _delege(yeniler)),
          ),
          SliverPadding(
            key: _merkez,
            // reverse:true → `top` listenin uzak (üst) ucudur.
            padding: EdgeInsets.only(
              left: yatay,
              right: yatay,
              top: widget.dikeyBosluk,
            ),
            sliver: SliverList(
              key: ValueKey<int>(_nesil),
              delegate: _delege(eskiler),
            ),
          ),
        ],
      ),
    );
  }
}
