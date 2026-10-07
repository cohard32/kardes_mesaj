import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../servisler/hata_servisi.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../modeller/kullanici.dart';
import '../modeller/mesaj.dart';
import '../modeller/sohbet.dart';
import '../parcalar/balon_hareketleri.dart';
import '../parcalar/kullanici_avatar.dart';
import '../parcalar/linkli_metin.dart';
import '../parcalar/mesaj_listesi.dart';
import '../parcalar/onbellekli_resim.dart';
import '../servisler/aktarici_servisi.dart';
import '../servisler/arama_servisi.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/dosya_servisi.dart';
import '../servisler/medya_indir_servisi.dart';
import '../servisler/mesaj_servisi.dart';
import '../servisler/paylasim_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../servisler/ses_oynatici_servisi.dart';
import '../servisler/sohbet_servisi.dart';
import '../servisler/hatirlatici_servisi.dart';
import '../servisler/taslak_servisi.dart';
import '../tema.dart';
import '../yardimcilar/hatirlatma_zamani.dart';
import '../yardimcilar/mesaj_metni.dart';
import '../yardimcilar/sohbet_arama.dart';
import '../yardimcilar/tarih_ayraci.dart';
import '../yardimcilar/zaman_metni.dart';
import 'arama_ekrani.dart';
import 'gif_secici.dart';
import 'medya_goruntuleyici.dart';
import 'medya_gonder_ekrani.dart';
import 'profil_goruntule_ekrani.dart';

/// Bir arkadaşla sohbeti açar (yoksa oluşturur) ve ekranı push eder.
/// Arkadaş listesi / sohbet listesi / profil bu ortak yolu kullanır.
Future<void> sohbetiAc(BuildContext context, Kullanici karsi) async {
  final nav = Navigator.of(context);
  try {
    final chatId = await SohbetServisi.instance.sohbetAcOrGetir(karsi.uid);
    if (!context.mounted) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => SohbetEkrani(chatId: chatId, karsi: karsi),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e')));
  }
}

/// Bir arkadaşla sohbet ekranı (FAZ 4). [chatId] = ciftKimligi(ben, karşı).
/// Kendi mesajların sağda neon gradient balonda, karşınınki solda koyu cam
/// balonda. Tüm renk/stil değerleri `tema.dart`'tan gelir (bkz. Renkler/Kose/…).
class SohbetEkrani extends StatefulWidget {
  final String chatId;
  final Kullanici karsi;

  /// Başka uygulamadan "Paylaş → ROY" ile gelen ve bu sohbete gönderilecek
  /// içerik (bkz. PaylasimHedefiEkrani). Açılışta bir kez işlenir.
  final GelenPaylasim? paylasim;

  const SohbetEkrani({
    super.key,
    required this.chatId,
    required this.karsi,
    this.paylasim,
  });

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani>
    with WidgetsBindingObserver {
  final _mesajCtrl = TextEditingController();
  final _servis = MesajServisi.instance;
  final _presence = PresenceServisi.instance;
  final _sohbetServis = SohbetServisi.instance;
  final _resimSecici = ImagePicker();
  final _kayitci = AudioRecorder();

  final _odak = FocusNode();

  Timer? _yaziyorTimer;
  bool _yaziyorGonderildi = false;
  bool _yukleniyor = false;
  // Birden çok medya gönderilirken "2/5 gönderiliyor…".
  String? _yuklemeMetni;

  // Arama kurulurken (izin + token + kanala katılma birkaç saniye sürebilir)
  // ara düğmeleri pasif ve AppBar'da ilerleme göstergesi var.
  // ⚠️ Eskiden gösterge yoktu: "bir şey olmuyor" sanılıp ikinci kez
  // dokunuluyor (çift arama) ya da geri çıkılıyordu (bkz. _aramaBaslat).
  bool _aramaBasliyor = false;

  // ⚠️ Mesaj akışı ÖNBELLEKTE tutulur. Eskiden `stream:` doğrudan
  // mesajlariDinle(...) çağırıyordu → HER build'de YENİ Stream nesnesi →
  // StreamBuilder aboneliği kopup yeniden kuruluyor → ConnectionState.waiting →
  // liste yerine spinner çiziliyordu. Kayıtta genlik 120 ms'de bir setState
  // yaptığı için ekran saniyede ~8 kez SİYAH YANIP SÖNÜYORDU.
  Stream<List<Mesaj>>? _mesajAkisi;
  int? _akisLimit;

  Stream<List<Mesaj>> get _mesajlarAkisi {
    if (_mesajAkisi == null || _akisLimit != _mesajLimit) {
      _akisLimit = _mesajLimit;
      _mesajAkisi = _servis.mesajlariDinle(widget.chatId, limit: _mesajLimit);
    }
    return _mesajAkisi!;
  }

  // NOT: kaydırma (alta takip, kendi mesajında alta inme, geçmişi okurken
  // kaymama, sayfalama tetiği) artık MesajListesi'nde (lib/parcalar/
  // mesaj_listesi.dart) — Firebase'siz test edilebilsin diye.

  // Sayfalama: başta son 50 mesaj; yukarı kaydırınca 50'şer artar.
  static const int _sayfaBoyu = 50;
  int _mesajLimit = _sayfaBoyu;
  bool _hepsiYuklendi = false;
  bool _eskiYukleniyor = false;

  // Sesli mesaj kaydı durumu.
  // ⚠️ setState YERİNE ValueNotifier: kayıt sırasında saniyede ~8 güncelleme
  // oluyor; setState tüm sohbet ekranını (mesaj listesi, video/foto balonları)
  // yeniden çizip takılmaya/yanıp sönmeye yol açıyordu. Artık sadece kayıt
  // çubuğu yeniden çizilir.
  Timer? _kayitTimer;
  StreamSubscription<Amplitude>? _ampSub;
  final _kayitYapiliyorVN = ValueNotifier<bool>(false);
  final _kayitSaniyeVN = ValueNotifier<int>(0);
  final _dalgaVN = ValueNotifier<List<double>>(<double>[]);
  final _iptalBolgesindeVN = ValueNotifier<bool>(false);

  // Emoji paneli
  bool _emojiAcik = false;

  // YANIT: yazma alanının üstündeki alıntı çubuğu. ValueNotifier: çubuğu
  // açıp kapatmak tüm sohbet ekranını (mesaj listesi) yeniden çizmesin.
  final _yanitVN = ValueNotifier<Mesaj?>(null);

  // DÜZENLEME: düzenlenen mesaj (null = normal gönderim). Yazma alanı
  // mesajın metniyle dolar; gönder düğmesi düzenlemeyi kaydeder.
  final _duzenleVN = ValueNotifier<Mesaj?>(null);

  // SOHBET İÇİ ARAMA. Yalnız YÜKLÜ mesajlarda arar; en eskiye gelince ↑
  // daha eski sayfaları yükleyip aramayı sürdürür.
  final _listeAnahtari = GlobalKey<MesajListesiDurumu>();
  final _aramaCtrl = TextEditingController();
  bool _aramaAcik = false;
  List<Mesaj> _aramaSonuclari = const [];
  int _aramaIndeks = 0; // 0 = en yeni eşleşme
  List<Mesaj>? _aramaKaynak; // sonuçların hesaplandığı liste
  bool _aramaEskiBekleniyor = false;
  // Bulunan mesajın kısa süre parlaması.
  final _vurguVN = ValueNotifier<String?>(null);
  Timer? _vurguTimer;

  // Çift dokunulup ❤️ verilen mesajın kalp animasyonu (mesaj kimliği).
  final _kalpVN = ValueNotifier<String?>(null);
  Timer? _kalpTimer;

  // SESSİZE ALMA (canlı; başlıktaki ikon + menü metni için).
  bool _sessiz = false;
  StreamSubscription<bool>? _sessizAbone;

  // ENGEL DURUMU (canlı). null = engel yok, değilse engeli koyanın uid'i.
  // Karşı taraf ekran AÇIKKEN engellerse yazma alanı anında kapanır —
  // kullanıcı "gönderilemedi" hatası almadan sebebi görür.
  String? _engelleyen;
  StreamSubscription<String?>? _engelAbone;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BildirimServisi.instance.tokenKaydet();
    // NOT: çevrimiçi/çevrimdışı durumu YALNIZCA AnaKabuk yönetir (bu ekran
    // her zaman onun üstünde açılır). Eskiden burası da yazıyordu ve sohbetten
    // geri çıkınca kullanıcı uygulama AÇIKKEN "çevrimdışı" görünüyordu.
    _sohbetServis.okunduIsaretle(widget.chatId); // sohbeti açınca okundu
    HataServisi.instance.iz('SOHBET acildi chat=${widget.chatId}');
    // Yarım kalan mesaj (TASLAK) yerine konur. ⚠️ Dinleyiciden ÖNCE: yoksa
    // taslağı geri koymak karşı tarafa "yazıyor…" gönderirdi.
    if (widget.paylasim == null) {
      final taslak = TaslakServisi.instance.al(widget.chatId);
      if (taslak != null) {
        _mesajCtrl.value = TextEditingValue(
          text: taslak,
          selection: TextSelection.collapsed(offset: taslak.length),
        );
      }
    }
    _mesajCtrl.addListener(_yaziyorDinle);
    _odak.addListener(() {
      if (_odak.hasFocus && _emojiAcik) {
        setState(() => _emojiAcik = false);
      }
    });
    // NOT: güncelleme kontrolü artık AnaKabuk'ta (açılışta) yapılıyor.
    // kalmış stale aramayı temizle
    AramaServisi.instance.eskiAramayiTemizle(widget.chatId);
    _aramaIzinleriniKontrolEt();
    _engelAbone = ArkadasServisi.instance
        .engelDinle(widget.karsi.uid)
        .listen((e) {
      if (mounted && e != _engelleyen) setState(() => _engelleyen = e);
    });
    _sohbetAbone = _sohbetServis.sohbetDinle(widget.chatId).listen((s) {
      _benimOkunmamis = s.benimOkunmamis(_uid);
      _gorulduGuncelle();
    }, onError: (Object _) {});
    // Aktarıcısız derlemede sessize alma uygulanamıyor (bkz. build'deki
    // menü notu) → kayıtlı eski bir "sessiz" durumu da gösterilmez.
    if (AktariciServisi.etkin) {
      _sessizAbone = _sohbetServis.sessizMi(widget.chatId).listen((v) {
        if (mounted && v != _sessiz) setState(() => _sessiz = v);
      }, onError: (Object _) {});
    }
    // CallKit ile (kapalıyken) kabul edilmiş bir arama varsa ekranını aç.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bekleyenAramayiAc());
    final paylasim = widget.paylasim;
    if (paylasim != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _paylasimiIsle(paylasim));
    }
  }

  /// "Paylaş → ROY" ile gelen içerik: metin/link yazma alanına konur (kişi
  /// düzenleyip gönderir), foto/video önizleme+açıklama ekranına gider,
  /// belge onayla gönderilir. Çok büyük dosyalar söylenir.
  Future<void> _paylasimiIsle(GelenPaylasim p) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (p.buyukler.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${p.buyukler.join(', ')} çok büyük olduğu için alınamadı '
            '(en fazla 100 MB).',
          ),
        ),
      );
    }
    final metin = p.metin?.trim();
    if (metin != null && metin.isNotEmpty) {
      _mesajCtrl.value = TextEditingValue(
        text: metin,
        selection: TextSelection.collapsed(offset: metin.length),
      );
      _odak.requestFocus();
    }
    final medya = [
      for (final d in p.dosyalar)
        if (!d.belgeMi) File(d.yol),
    ];
    if (medya.isNotEmpty) await _onizleVeGonder(medya);
    for (final d in p.dosyalar.where((d) => d.belgeMi)) {
      if (!mounted) return;
      if (d.boyut > DosyaServisi.azamiBoyut) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '"${d.ad}" çok büyük (${boyutMetni(d.boyut)}). '
              'Belgeler en fazla 10 MB olabilir.',
            ),
          ),
        );
        continue;
      }
      final onay = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          title: const Text('Belge gönderilsin mi?'),
          content: Text('"${d.ad}" (${boyutMetni(d.boyut)}) '
              '${widget.karsi.ad} kişisine gönderilecek.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dc, true),
              child: const Text('Gönder'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) continue;
      await _yukleVeGonder(
        () => _servis.dosyaGonder(
          widget.chatId,
          widget.karsi.uid,
          File(d.yol),
          ad: d.ad,
          boyut: d.boyut,
        ),
        hata: '"${d.ad}" gönderilemedi.',
      );
    }
  }

  // Ekran KAPALIYKEN aramanın çalışması için gereken izinler:
  // (1) pil optimizasyonu muafiyeti (Doze uyutmasın),
  // (2) Android 14+ tam ekran bildirim izni (yoksa arama tam ekran açılmaz).
  Future<void> _aramaIzinleriniKontrolEt() async {
    // ÖNEMLİ: mikrofon/kamera iznini ARAMA GELMEDEN ÖNCE al. İzin diyaloğu
    // kabul anında açılırsa sistem ekranı Flutter aktivitesini duraklatıyor,
    // kabul akışı askıda kalıyor ve arama ekranı hiç açılmıyordu.
    // (İzin zaten verilmişse bu çağrı diyalog AÇMAZ, anında döner.)
    await AramaServisi.instance.izinleriHazirla(AramaTipi.video);
    if (!mounted) return;
    final b = BildirimServisi.instance;
    // Zil duyulmayacaksa kullanıcıyı bilgilendir (en yaygın "zil çalmıyor"
    // sebebi cihazın sessiz/titreşim modu ya da zil sesinin 0 olmasıdır).
    if (await b.zilDuyulmazMi() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 6),
          content: Text(
            'Telefonun sessiz/titreşim modunda — gelen arama zili duyulmaz.',
          ),
        ),
      );
    }
    if (!mounted) return;
    await b.pilOptimizasyonuIste();
    if (!mounted) return;
    if (await b.tamEkranIzniVarMi()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: const Text(
          'Ekran kapalıyken arama gelmesi için "tam ekran bildirim" izni gerekli.',
        ),
        action: SnackBarAction(
          label: 'İzin ver',
          onPressed: b.tamEkranAyarlariniAc,
        ),
      ),
    );
  }

  void _bekleyenAramayiAc() {
    final s = AramaServisi.instance;
    final chatId = s.bekleyenChatId;
    final tip = s.bekleyenTip;
    if (chatId != null && tip != null && mounted) {
      final baslik = s.bekleyenBaslik ?? widget.karsi.ad;
      s.bekleyenChatId = null;
      s.bekleyenTip = null;
      s.bekleyenBaslik = null;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(chatId: chatId, tip: tip, baslik: baslik),
        ),
      );
    }
  }

  // NOT: Gelen arama ekranı ARTIK BURADA AÇILMIYOR.
  // Tek akış: gelen arama HER durumda (açık/arka plan/kapalı) CallKit ile
  // gösterilir (bkz. bildirim_servisi.gelenAramayiGoster). Eskiden buradaki
  // Firestore dinleyicisi de bir ekran açıyordu ve CallKit'in tam ekran
  // aktivitesiyle YARIŞIYORDU (yeşil ekran açılıp anında mavi CallKit'e
  // dönmesinin sebebi buydu). Kabul edilince main.dart CallKit olayını
  // yakalayıp AramaEkrani'nı açar.

  // Görüntülü/sesli arama başlat → arama ekranını aç. Hata olursa ekranda göster.
  Future<void> _aramaBaslat(AramaTipi tip) async {
    // Engelliyken kural `aramalar` yazmasını reddeder → Agora'yı boşuna
    // başlatıp izin isteyip sonra hata vermek yerine baştan söyle.
    if (_engelleyen != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_engelleyen == _uid
              ? 'Bu kişiyi engelledin, arama yapamazsın.'
              : 'Bu kişi seni engelledi, arama yapamazsın.'),
        ),
      );
      return;
    }
    if (_aramaBasliyor) return; // çift dokunma: ikinci arama başlatılmaz
    setState(() => _aramaBasliyor = true);
    final servis = AramaServisi.instance;
    try {
      final istek = servis.aramaBaslat(widget.chatId, widget.karsi.uid, tip);
      // aramaBaslat oturumu İLK await'ten önce (eşzamanlı) artırır → bu
      // değer BU aramanın oturumudur. Sonradan okunsaydı arada kabul edilen
      // başka bir görüşmenin oturumu olabilirdi.
      final oturum = servis.oturum;
      final kanal = await istek;
      if (!mounted) {
        // ⚠️ Kurulum sürerken ekrandan çıkıldı: arayan kanala MİKROFON
        // YAYINLAYARAK katılmış, karşıya "çalıyor" gitmişti ama AramaEkrani
        // hiç açılmayacak (zaman aşımı / kapat yalnız orada). Eskiden
        // görüşme yarım kalıyordu: karşı taraf kabul edince haberi olmayan
        // arayanın mikrofonunu canlı dinliyor, arayan da "meşgul" kalıyordu.
        // oturum: arada başka görüşme devraldıysa ona dokunulmaz.
        if (kanal != null) {
          await servis.bitir(widget.chatId, oturum: oturum);
        }
        return;
      }
      if (kanal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera/mikrofon izni gerekli')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(
            chatId: widget.chatId,
            tip: tip,
            baslik: widget.karsi.ad,
            benArayanim: true, // "çalıyor" tonu burada çalar
            karsiUid: widget.karsi.uid, // bağlanmazsa "cevapsız arama" kaydı
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _aramaBasliyor = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yaziyorTimer?.cancel();
    // ⚠️ Zamanlayıcı iptal edildiği için "yazmayı bıraktım" sinyali artık
    // ondan gelmeyecek → yazarken ekrandan çıkılırsa karşı tarafta
    // "yazıyor..." KALICI takılı kalıyordu. Burada açıkça kapatılır.
    if (_yaziyorGonderildi) {
      _presence.yaziyorAyarla(widget.chatId, false);
    }
    _kayitTimer?.cancel();
    _ampSub?.cancel();
    _engelAbone?.cancel();
    _sohbetAbone?.cancel();
    _sessizAbone?.cancel();
    // Ekrandan çıkınca bu sohbetin sesli mesajı çalmaya devam etmesin
    // (oynatıcı paylaşılan TEK örnektir; dispose edilmez, yalnız durdurulur).
    SesOynaticiServisi.instance.durdur(chatId: widget.chatId);
    _kayitci.dispose();
    _taslakKaydet();
    _mesajCtrl.dispose();
    _odak.dispose();
    _kayitYapiliyorVN.dispose();
    _kayitSaniyeVN.dispose();
    _dalgaVN.dispose();
    _iptalBolgesindeVN.dispose();
    _yanitVN.dispose();
    _duzenleVN.dispose();
    _aramaCtrl.dispose();
    _vurguTimer?.cancel();
    _vurguVN.dispose();
    _kalpTimer?.cancel();
    _kalpVN.dispose();
    super.dispose();
  }

  /// Yazma alanındaki metni TASLAK olarak saklar (boşsa siler). Düzenleme
  /// sırasındaki metin taslak sayılmaz (o, gönderilmiş bir mesajın metni).
  void _taslakKaydet() {
    if (_duzenleVN.value != null) return;
    TaslakServisi.instance.kaydet(widget.chatId, _mesajCtrl.text);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plana atılıp öldürülürse dispose çalışmaz → taslak şimdi.
    if (state == AppLifecycleState.paused) _taslakKaydet();
    _onPlanda = state == AppLifecycleState.resumed;
    // Uygulamaya dönüldü → bu arada gelen mesajlar ŞİMDİ görüldü sayılır.
    if (_onPlanda) _gorulduGuncelle();
  }

  // ---- GÖRÜLDÜ / OKUNDU ----
  // ⚠️ Eskiden build() içinden HER yeniden çizimde çağrılıyordu:
  //  (1) uygulama arka plandayken / ekran kilitliyken (sohbet ekranı yığında
  //      açık kaldığı için) gelen mesajlar ✓✓ "görüldü" işaretleniyordu —
  //      kullanıcı görmediği halde;
  //  (2) emoji paneli, yükleme çubuğu gibi her setState chats/{id}'ye bir
  //      YAZMA yapıyordu (Spark kotası).
  // Artık yalnız ekran GÖRÜNÜRKEN ve gerçekten görülmemiş mesaj varken yazılır.
  bool _onPlanda = true;
  bool _rotaGorunur = true; // build'de ModalRoute'tan güncellenir
  List<Mesaj> _sonMesajlar = const [];
  final Set<String> _gorulduGonderilenler = <String>{};

  // Okunmamış sayacı sohbet dokümanından CANLI izlenir: gönderen, sayacı
  // mesajı ekledikten SONRA artırır. Yalnız "yeni mesaj gelince sıfırla"
  // denseydi sıfırlama artırmadan önce düşüp listede sahte "1" kalabilirdi.
  StreamSubscription<Sohbet>? _sohbetAbone;
  int _benimOkunmamis = 0;

  void _gorulduGuncelle() {
    // Üstte başka bir ekran (arama, profil, foto) açıksa görülmedi sayılır.
    if (!mounted || !_onPlanda || !_rotaGorunur) return;
    final yeni = _sonMesajlar
        .where((m) =>
            m.gonderen != _uid &&
            !m.goruldu &&
            !_gorulduGonderilenler.contains(m.id))
        .toList();
    if (yeni.isNotEmpty) {
      _gorulduGonderilenler.addAll(yeni.map((m) => m.id));
      _servis.gorulduIsaretle(widget.chatId, yeni).catchError((Object e) {
        // Başarısızsa sonraki çizimde tekrar denensin.
        _gorulduGonderilenler.removeAll(yeni.map((m) => m.id));
        HataServisi.instance.iz('goruldu yazilamadi: $e');
      });
    }
    if (_benimOkunmamis > 0) {
      _benimOkunmamis = 0; // aynı sayaç için tekrar yazma
      _sohbetServis.okunduIsaretle(widget.chatId);
    }
  }

  void _yaziyorDinle() {
    final bos = _mesajCtrl.text.trim().isEmpty;
    if (!bos && !_yaziyorGonderildi) {
      _yaziyorGonderildi = true;
      _presence.yaziyorAyarla(widget.chatId, true);
    }
    _yaziyorTimer?.cancel();
    _yaziyorTimer = Timer(const Duration(seconds: 2), () {
      _yaziyorGonderildi = false;
      _presence.yaziyorAyarla(widget.chatId, false);
    });
  }

  Future<void> _gonder() async {
    final metin = _mesajCtrl.text;
    if (metin.trim().isEmpty) return;
    final duzenlenen = _duzenleVN.value;
    if (duzenlenen != null) return _duzenlemeyiKaydet(duzenlenen, metin);
    final yanit = _yanitVN.value;
    _mesajCtrl.clear();
    _yanitVN.value = null;
    _yaziyorTimer?.cancel();
    _yaziyorGonderildi = false;
    // ⚠️ await'SİZ (bilinçli): Firestore set()'in Future'ı SUNUCU onayında
    // biter; çevrimdışıyken beklemek mesaj gönderimini de bekletirdi. Yazma
    // sırası istemcide korunur, hata da yaziyorAyarla içinde yutulur.
    unawaited(_presence.yaziyorAyarla(widget.chatId, false));
    // NOT: alta inmek için bayrak YOK — MesajListesi kendi mesajım gelince
    // (yerel yazım anında akışa düşer) kendisi en alta iner.
    try {
      await _servis.gonder(
        widget.chatId,
        widget.karsi.uid,
        metin,
        yanit: yanit,
      );
    } catch (e) {
      // Firestore çevrimdışıyken kuyruğa alır; yine de hata olursa kullanıcıya
      // bildir ve metni (ve yanıtlanan mesajı) kaybetme.
      if (!mounted) return;
      _mesajCtrl.text = metin;
      _yanitVN.value = yanit;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi. Tekrar dene.')),
      );
    }
  }

  // Kullanıcı en üste yaklaşınca (MesajListesi çağırır) daha eski mesajları
  // yükle (sayfalama): limit artar → akış yeni limitle yeniden kurulur.
  void _eskiYukle() {
    if (_hepsiYuklendi || _eskiYukleniyor || !mounted) return;
    _eskiYukleniyor = true;
    setState(() => _mesajLimit += _sayfaBoyu);
  }

  // ---- EMOJI ----

  void _emojiToggle() {
    setState(() => _emojiAcik = !_emojiAcik);
    if (_emojiAcik) {
      _odak.unfocus();
    } else {
      _odak.requestFocus();
    }
  }

  void _emojiEkle(String emoji) {
    final t = _mesajCtrl.text;
    final sel = _mesajCtrl.selection;
    final bas = sel.start < 0 ? t.length : sel.start;
    final son = sel.end < 0 ? t.length : sel.end;
    final yeni = t.replaceRange(bas, son, emoji);
    _mesajCtrl.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(offset: bas + emoji.length),
    );
  }

  void _emojiSil() {
    final t = _mesajCtrl.text;
    if (t.isEmpty) return;
    final sel = _mesajCtrl.selection;
    final son = sel.end < 0 ? t.length : sel.end;
    if (son == 0) return;
    var sil = 1;
    if (son >= 2) {
      final k = t.codeUnitAt(son - 1);
      final o = t.codeUnitAt(son - 2);
      if (k >= 0xDC00 && k <= 0xDFFF && o >= 0xD800 && o <= 0xDBFF) sil = 2;
    }
    final yeni = t.substring(0, son - sil) + t.substring(son);
    _mesajCtrl.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(offset: son - sil),
    );
  }

  // ---- MEDYA ----

  // Ek (ataç) menüsü: kamera / galeri (çoklu) / GIF / belge
  void _ekMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: Renkler.neon),
              title: const Text('Galeri'),
              subtitle: Text('Fotoğraf ve video — birden çok seçebilirsin',
                  style: Yazi.kucuk),
              onTap: () {
                Navigator.pop(context);
                _galeridenSec();
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: Renkler.neon),
              title: const Text('Fotoğraf çek'),
              onTap: () {
                Navigator.pop(context);
                _kameraFoto();
              },
            ),
            ListTile(
              leading: Icon(Icons.videocam_outlined, color: Renkler.neon),
              title: const Text('Video çek'),
              onTap: () {
                Navigator.pop(context);
                _kameraVideo();
              },
            ),
            ListTile(
              leading: Icon(Icons.gif_box_outlined, color: Renkler.neon),
              title: const Text('GIF / Sticker'),
              onTap: () {
                Navigator.pop(context);
                _gifSec();
              },
            ),
            ListTile(
              leading: Icon(Icons.description_outlined, color: Renkler.neon),
              title: const Text('Belge / Dosya'),
              subtitle: Text('PDF, Word, Excel… (en fazla 10 MB)',
                  style: Yazi.kucuk),
              onTap: () {
                Navigator.pop(context);
                _dosyaSec();
              },
            ),
          ],
        ),
      ),
    );
  }

  // GIF/sticker seçici aç → seçilen GIPHY URL'ini gönder
  Future<void> _gifSec() async {
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => const GifSecici(),
    );
    if (url != null && url.isNotEmpty) {
      await _servis.gifGonder(widget.chatId, widget.karsi.uid, url);
    }
  }

  // ⚠️ imageQuality / maxWidth VERİLMEZ → fotoğraf ORİJİNAL/SAF haliyle
  // gider. Eskiden `imageQuality: 70` vardı; image_picker fotoğrafı %70
  // kalitede YENİDEN KODLUYORDU (görünür kalite kaybı).

  /// Galeriden BİRDEN ÇOK fotoğraf/video seç → önizleme → gönder.
  Future<void> _galeridenSec() async {
    try {
      final secilen = await _resimSecici.pickMultipleMedia(limit: 30);
      if (secilen.isEmpty) return;
      await _onizleVeGonder([for (final x in secilen) File(x.path)]);
    } catch (e) {
      HataServisi.instance.iz('galeri secilemedi: $e');
    }
  }

  Future<void> _kameraFoto() async {
    try {
      final x = await _resimSecici.pickImage(source: ImageSource.camera);
      if (x != null) await _onizleVeGonder([File(x.path)]);
    } catch (e) {
      HataServisi.instance.iz('kamera acilamadi: $e');
      _kameraHatasi();
    }
  }

  Future<void> _kameraVideo() async {
    try {
      final x = await _resimSecici.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (x != null) await _onizleVeGonder([File(x.path)]);
    } catch (e) {
      HataServisi.instance.iz('kamera acilamadi: $e');
      _kameraHatasi();
    }
  }

  void _kameraHatasi() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kamera açılamadı. Kamera iznini kontrol et.')),
    );
  }

  /// Önizleme/açıklama ekranını açar; "Gönder" denirse hepsini SIRAYLA
  /// gönderir (üstte "2/5 gönderiliyor…").
  Future<void> _onizleVeGonder(List<File> dosyalar) async {
    if (!mounted) return;
    final liste = await Navigator.of(context).push<List<GonderilecekMedya>>(
      MaterialPageRoute(
        builder: (_) =>
            MedyaGonderEkrani(dosyalar: dosyalar, kime: widget.karsi.ad),
      ),
    );
    if (liste == null || liste.isEmpty || !mounted) return;
    setState(() => _yukleniyor = true);
    var basarisiz = 0;
    for (var i = 0; i < liste.length; i++) {
      if (mounted && liste.length > 1) {
        setState(() => _yuklemeMetni = '${i + 1}/${liste.length} gönderiliyor…');
      }
      final m = liste[i];
      // Ekrandan çıkılsa da gönderim SÜRER (servis widget'a bağlı değil).
      final ok = await _servis.medyaGonder(
        widget.chatId,
        widget.karsi.uid,
        m.dosya,
        m.tip,
        aciklama: m.aciklama,
      );
      if (!ok) basarisiz++;
    }
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      _yuklemeMetni = null;
    });
    if (basarisiz > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            liste.length == 1
                ? 'Gönderilemedi. İnternet bağlantını kontrol et.'
                : '$basarisiz öğe gönderilemedi. İnternet bağlantını kontrol et.',
          ),
        ),
      );
    }
  }

  /// Telefondan belge seçip gönderir (Cloudinary ücretsiz: en fazla 10 MB).
  Future<void> _dosyaSec() async {
    final messenger = ScaffoldMessenger.of(context);
    SecilenDosya? d;
    try {
      d = await DosyaServisi.instance.sec();
    } on DosyaCokBuyuk catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '"${e.ad}" çok büyük (${boyutMetni(e.boyut)}). '
            'Belgeler en fazla 10 MB olabilir.',
          ),
        ),
      );
      return;
    } catch (e) {
      HataServisi.instance.iz('dosya secilemedi: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Dosya seçilemedi.')),
      );
      return;
    }
    if (d == null || !mounted) return;
    final secilen = d;
    await _yukleVeGonder(
      () => _servis.dosyaGonder(
        widget.chatId,
        widget.karsi.uid,
        File(secilen.yol),
        ad: secilen.ad,
        boyut: secilen.boyut,
      ),
      hata: 'Dosya gönderilemedi. İnternet bağlantını kontrol et.',
    );
    // Önbelleğe alınan kopya artık gereksiz.
    try {
      await File(secilen.yol).delete();
    } catch (_) {}
  }

  /// Yükleme çubuğunu göstererek [gorev]'i çalıştırır; başarısızsa [hata].
  Future<void> _yukleVeGonder(
    Future<bool> Function() gorev, {
    required String hata,
  }) async {
    setState(() => _yukleniyor = true);
    var ok = false;
    try {
      ok = await gorev();
    } catch (e) {
      HataServisi.instance.iz('gonderim hatasi: $e');
    }
    if (!mounted) return;
    setState(() => _yukleniyor = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  // ---- SESLİ MESAJ: BASILI TUT → KAYDET, BIRAK → GÖNDER, SOLA KAYDIR → İPTAL

  /// Mikrofona kısa dokunulunca ipucu (WhatsApp gibi basılı tutmak gerekir).
  void _mikrofonBilgi() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kaydetmek için mikrofona basılı tut'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Basılı tutma başladı → kaydı başlat.
  /// setState YOK: güncellemeler ValueNotifier üzerinden gider (yanıp sönme yok).
  Future<void> _kayitBaslat() async {
    if (_kayitYapiliyorVN.value) return;
    if (!await _kayitci.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mikrofon izni gerekli')));
      }
      return;
    }
    final dizin = await getTemporaryDirectory();
    final yol =
        '${dizin.path}/ses_${DateTime.now().millisecondsSinceEpoch}.m4a';
    HataServisi.instance.iz('SES KAYIT basladi');
    await _kayitci.start(const RecordConfig(), path: yol);
    _dalgaVN.value = <double>[];
    _kayitSaniyeVN.value = 0;
    _iptalBolgesindeVN.value = false;
    _kayitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _kayitSaniyeVN.value++;
    });
    _ampSub = _kayitci
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
          // dBFS (-45..0) → 0..1 ölçek (konuşurken dalga oynar)
          final normal = ((amp.current + 45) / 45).clamp(0.0, 1.0).toDouble();
          final yeni = List<double>.of(_dalgaVN.value)..add(normal);
          if (yeni.length > 50) yeni.removeAt(0);
          _dalgaVN.value = yeni; // yalnızca dalga yeniden çizilir
        });
    _kayitYapiliyorVN.value = true;
  }

  /// Parmak sola kaydıkça iptal bölgesine girildi mi (çöp kutusu).
  void _kayitSurukle(double dx) {
    if (!_kayitYapiliyorVN.value) return;
    final iptal = dx < -70;
    if (_iptalBolgesindeVN.value != iptal) _iptalBolgesindeVN.value = iptal;
  }

  /// Parmak kalktı → iptal bölgesindeyse çöpe at, değilse gönder.
  Future<void> _kayitBitir() async {
    if (!_kayitYapiliyorVN.value) return;
    if (_iptalBolgesindeVN.value) {
      await _kayitIptal();
      return;
    }
    // Çok kısa kayıt = yanlışlıkla dokunma → gönderme.
    if (_kayitSaniyeVN.value < 1) {
      await _kayitIptal();
      if (mounted) _mikrofonBilgi();
      return;
    }
    await _kayitGonder();
  }

  Future<void> _kayitTemizle() async {
    _kayitTimer?.cancel();
    _kayitTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
  }

  // Durdur ve gönder
  Future<void> _kayitGonder() async {
    HataServisi.instance.iz('SES KAYIT gonderiliyor');
    final yol = await _kayitci.stop();
    await _kayitTemizle();
    _kayitYapiliyorVN.value = false;
    if (yol != null) await _medyaGonder(File(yol), MesajTipi.ses);
  }

  // İptal: kaydı sil, gönderme
  Future<void> _kayitIptal() async {
    HataServisi.instance.iz('SES KAYIT iptal edildi');
    final yol = await _kayitci.stop();
    await _kayitTemizle();
    _kayitYapiliyorVN.value = false;
    _iptalBolgesindeVN.value = false;
    if (yol != null) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
  }

  Future<void> _medyaGonder(File dosya, MesajTipi tip) async {
    await _yukleVeGonder(
      () => _servis.medyaGonder(widget.chatId, widget.karsi.uid, dosya, tip),
      hata: 'Gönderilemedi. İnternet bağlantını kontrol et.',
    );
    // ⚠️ Eskiden burada (gönderim BİTTİKTEN sonra) `_zorlaKaydir = true`
    // kuruluyordu; mesaj ise yerel yazımla çok önce akışa düşmüş oluyordu →
    // bayrak askıda kalıp dakikalar sonra karşının ilgisiz mesajında listeyi
    // zorla dibe çekiyordu. Artık bayrak yok: MesajListesi, kendi mesajım
    // akışa düştüğü AN en alta iner (yükleme ne kadar sürerse sürsün).
  }

  @override
  Widget build(BuildContext context) {
    // ModalRoute'a bağımlılık: üstteki ekran kapanıp bu sohbet tekrar en üste
    // gelince build yeniden çalışır → bekleyen mesajlar o an "görüldü" olur.
    _rotaGorunur = ModalRoute.of(context)?.isCurrent ?? true;
    return PopScope(
      // Geri tuşu önce aramayı kapatır.
      canPop: !_aramaAcik,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _aramaAcik) _aramaKapat();
      },
      child: Scaffold(
        appBar: _aramaAcik ? _aramaCubugu() : AppBar(
          titleSpacing: 0,
          title: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfilGoruntuleEkrani(kullanici: widget.karsi),
              ),
            ),
            child: _AppBarBaslik(
              chatId: widget.chatId,
              karsi: widget.karsi,
              sessiz: _sessiz,
            ),
          ),
          actions: [
            if (_aramaBasliyor)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Renkler.neon,
                    semanticsLabel: 'Arama başlatılıyor',
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Sohbette ara',
              icon: const Icon(Icons.search_rounded),
              onPressed: _aramaAc,
            ),
            IconButton(
              tooltip: 'Sesli ara',
              icon: const Icon(Icons.call_outlined),
              onPressed:
                  _aramaBasliyor ? null : () => _aramaBaslat(AramaTipi.ses),
            ),
            IconButton(
              tooltip: 'Görüntülü ara',
              icon: const Icon(Icons.videocam_outlined),
              onPressed:
                  _aramaBasliyor ? null : () => _aramaBaslat(AramaTipi.video),
            ),
            // ⚠️ Menü (tek seçeneği "Sessize al") YALNIZ aktarıcılı derlemede:
            // gizlilik gereği sessiz sohbet listesi artık yalnız SAHİBİNİN
            // okuyabildiği gizli belgede (users/{uid}/ozel/bildirim). Sessizi
            // bildirim GÖNDERİRKEN uygulayan, o belgeyi hizmet hesabıyla okuyan
            // aktarıcıdır; aktarıcısız (eski yol) derlemede gönderen karşının
            // listesini okuyamaz → seçenek hiçbir şey yapmazken "sessize
            // alındı" demek yanıltıcı olurdu.
            if (AktariciServisi.etkin)
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                color: Renkler.yuzey,
                onSelected: (secim) {
                  if (secim == 'sessiz') _sessizDegistir();
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'sessiz',
                    child: Row(
                      children: [
                        Icon(
                          _sessiz
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          color: Renkler.neon,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(_sessiz ? 'Sessizi kapat' : 'Sohbeti sessize al'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: Zemin(
          parlama: const Alignment(0.6, -1),
          child: Column(
            children: [
              if (_yukleniyor)
                LinearProgressIndicator(
                  color: Renkler.neon,
                  backgroundColor: Renkler.yuzey,
                ),
              if (_yukleniyor && _yuklemeMetni != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_yuklemeMetni!, style: Yazi.kucuk),
                ),
              Expanded(
                child: StreamBuilder<List<Mesaj>>(
                  stream: _mesajlarAkisi, // önbellekli (her build'de yenilenmez)
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _BosDurum(
                        ikon: Icons.error_outline,
                        yazi: 'Mesajlar yüklenemedi',
                      );
                    }
                    // ⚠️ `waiting` DEĞİL `hasData`: sayfalamada limit artınca
                    // akış yenilenir ve StreamBuilder eski veriyi koruyarak
                    // `waiting`e döner. Eskiden bu anda liste yerine spinner
                    // çiziliyor (yanıp sönme) ve kaydırma konumu kayboluyordu.
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: Renkler.neon),
                      );
                    }

                    final mesajlar = snapshot.data!;
                    // Sayfalama durumunu YALNIZ yeni limitin verisi gelince
                    // güncelle: `waiting`teki ESKİ veri (50 < 100) "hepsi
                    // yüklendi" sanılıp sayfalama erkenden durmasın.
                    if (snapshot.connectionState == ConnectionState.active) {
                      _eskiYukleniyor = false;
                      _hepsiYuklendi = mesajlar.length < _mesajLimit;
                    }
                    if (mesajlar.isEmpty) {
                      return const _BosDurum(
                        ikon: Icons.chat_bubble_outline_rounded,
                        yazi: 'Henüz mesaj yok.\nİlk mesajı sen yaz 👋',
                      );
                    }

                    // NOT: liste YENİDEN ESKİYE sıralı; görüldü mantığı
                    // sıraya bakmaz (yalnız "karşıdan gelen + görülmemiş"
                    // filtresi), dolayısıyla etkilenmez.
                    _sonMesajlar = mesajlar;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _gorulduGuncelle(),
                    );
                    // Arama açıkken liste değişti (yeni mesaj / eski sayfa /
                    // düzenleme) → sonuçlar tazelenir.
                    if (_aramaAcik && !identical(mesajlar, _aramaKaynak)) {
                      _aramaKaynak = mesajlar;
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _aramaTazele(),
                      );
                    }

                    // Kaydırma mantığı (yeni mesajda kaymama, alta takip,
                    // kendi mesajında alta inme, sayfalama) MesajListesi'nde.
                    // Öğeler mesaj kimliğiyle anahtarlanır → oynayan video /
                    // ses dalgası index'te değil MESAJDA kalır.
                    // Her günün ilk mesajının üstüne "Bugün / Dün / 12 Eylül".
                    final ayraclar = tarihAyraclari(mesajlar);
                    return MesajListesi(
                      key: _listeAnahtari,
                      mesajlar: mesajlar,
                      benimUid: _uid,
                      eskiYukle: _hepsiYuklendi ? null : _eskiYukle,
                      ogeKurucu: (context, m) => _ogeKur(m, ayraclar[m.id]),
                    );
                  },
                ),
              ),
              // Yazma alanı HER ZAMAN ağaçta kalır: basılı-tut jestinin sahibi
              // odur; kayıt sırasında widget ağaçtan çıkarılsaydı parmak
              // kalktığında "bitir" olayı hiç gelmez, kayıt asılı kalırdı.
              // Kayıt göstergesi ÜSTÜNE bindirilir (IgnorePointer → jesti bozmaz).
              if (_engelleyen != null)
                _EngelSeridi(
                  benEngelledim: _engelleyen == _uid,
                  karsiAd: widget.karsi.ad,
                )
              else ...[
                ValueListenableBuilder<Mesaj?>(
                  valueListenable: _duzenleVN,
                  builder: (_, duzenlenen, _) => duzenlenen != null
                      ? _YanitCubugu(
                          ikon: Icons.edit_rounded,
                          kimden: 'Mesajı düzenle',
                          onizleme: duzenlenen.yanitIcinOnizleme,
                          kapatIpucu: 'Düzenlemeyi iptal et',
                          onKapat: _duzenlemeIptal,
                        )
                      : ValueListenableBuilder<Mesaj?>(
                          valueListenable: _yanitVN,
                          builder: (_, yanit, _) => yanit == null
                              ? const SizedBox.shrink()
                              : _YanitCubugu(
                                  kimden: yanit.gonderen == _uid
                                      ? 'Sen'
                                      : widget.karsi.ad,
                                  onizleme: yanit.yanitIcinOnizleme,
                                  onKapat: () => _yanitVN.value = null,
                                ),
                        ),
                ),
                Stack(
                  children: [
                    _YazmaAlani(
                      controller: _mesajCtrl,
                      odak: _odak,
                      emojiAcik: _emojiAcik,
                      onGonder: _gonder,
                      onEk: _ekMenu,
                      onEmoji: _emojiToggle,
                      onMikrofonBilgi: _mikrofonBilgi,
                      onKayitBasla: _kayitBaslat,
                      onKayitSurukle: _kayitSurukle,
                      onKayitBitir: _kayitBitir,
                    ),
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _kayitYapiliyorVN,
                        builder: (_, kayitta, _) => kayitta
                            ? IgnorePointer(
                                child: _KayitKaplamasi(
                                  saniye: _kayitSaniyeVN,
                                  dalga: _dalgaVN,
                                  iptalBolgesinde: _iptalBolgesindeVN,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ],
              ValueListenableBuilder<bool>(
                valueListenable: _kayitYapiliyorVN,
                builder: (_, kayitta, _) => (_emojiAcik && !kayitta)
                    ? _EmojiPaneli(onEmoji: _emojiEkle, onSil: _emojiSil)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Listedeki tek öğe: (gerekirse) tarih ayracı + mesaj balonu.
  /// Balon: sağa kaydırınca yanıt, çift dokununca ❤️, uzun basınca menü;
  /// aramada bulunan mesaj kısa süre parlar.
  Widget _ogeKur(Mesaj m, String? ayrac) {
    // Çift dokunma yalnız metin/foto/GIF'te: oynatma düğmeli balonlarda
    // (ses, video) tek dokunuşu ~300 ms geciktirmesin.
    final ciftDokunabilir = m.tip == MesajTipi.metin ||
        m.tip == MesajTipi.resim ||
        m.tip == MesajTipi.gif;
    Widget balon = ValueListenableBuilder<String?>(
      valueListenable: _kalpVN,
      builder: (_, kalpId, _) => _MesajBalonu(
        mesaj: m,
        benimMi: m.gonderen == _uid,
        chatId: widget.chatId,
        benimUid: _uid,
        karsiAd: widget.karsi.ad,
        onUzunBas: () => _tepkiSec(m),
        onCiftDokun: ciftDokunabilir ? () => _kalpAt(m) : null,
        kalp: kalpId == m.id,
        onAra: (video) =>
            _aramaBaslat(video ? AramaTipi.video : AramaTipi.ses),
      ),
    );
    balon = ValueListenableBuilder<String?>(
      valueListenable: _vurguVN,
      builder: (_, vurgu, cocuk) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: vurgu == m.id
              ? Renkler.neon.withValues(alpha: 0.16)
              : Renkler.neon.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: cocuk,
      ),
      child: balon,
    );
    // Engelliyken yazma alanı yok → kaydırarak yanıt da yok.
    if (_engelleyen == null) {
      balon = KaydirarakYanit(onYanit: () => _yanitla(m), child: balon);
    }
    if (ayrac == null) return balon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_TarihAyraci(ayrac), balon],
    );
  }

  /// Çift dokunma: mesaja ❤️ (zaten ❤️ ise yalnız animasyon — yanlışlıkla
  /// iki kez dokununca tepki kaybolmasın).
  void _kalpAt(Mesaj m) {
    HapticFeedback.lightImpact();
    if (m.tepkiler[_uid] != '❤️') {
      _tepkiYaz(_servis.tepkiAyarla(widget.chatId, m.id, '❤️'));
    }
    _kalpTimer?.cancel();
    _kalpVN.value = m.id;
    _kalpTimer = Timer(const Duration(milliseconds: 850), () {
      if (_kalpVN.value == m.id) _kalpVN.value = null;
    });
  }

  /// Tepki yazımını BEKLEMEDEN başlatır (çevrimdışıyken sunucu onayı
  /// gecikir); reddedilirse kullanıcıya söyler.
  void _tepkiYaz(Future<void> yazim) {
    final messenger = ScaffoldMessenger.of(context);
    yazim.catchError((Object e) {
      HataServisi.instance.iz('tepki yazilamadi: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Tepki kaydedilemedi. Tekrar dene.')),
      );
    });
  }

  /// Mesaja uzun basınca açılan menü: tepkiler + (medyada) İndir +
  /// (kendi mesajın, ilk 1 dk) Sil.
  void _tepkiSec(Mesaj mesaj) {
    const emojiler = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final benimTepkim = mesaj.tepkiler[_uid];
    // Galeriye yalnız foto/video/GIF (sesli mesaj ve dosya galeriye girmez).
    final indirilebilir = mesaj.medyaUrl != null &&
        const {MesajTipi.resim, MesajTipi.video, MesajTipi.gif}
            .contains(mesaj.tip);
    // Dosya (PDF…) → telefonun İndirilenler klasörüne.
    final dosyaMi = mesaj.tip == MesajTipi.dosya && mesaj.medyaUrl != null;
    final silinebilir = _servis.silinebilirMi(mesaj);
    final duzenlenebilir =
        _engelleyen == null && _servis.duzenlenebilirMi(mesaj);
    final kopyalanabilir =
        mesaj.tip == MesajTipi.metin && mesaj.metin.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in emojiler)
                    InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () {
                        Navigator.pop(context);
                        // Aynı emojiye yeniden basmak tepkiyi kaldırır.
                        _tepkiYaz(
                          _servis.tepkiDegistir(widget.chatId, mesaj, e),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        // Seçili tepkim neon halkayla belli olur.
                        decoration: e == benimTepkim
                            ? BoxDecoration(
                                color: Renkler.neonSis,
                                shape: BoxShape.circle,
                                border: Border.all(color: Renkler.neon),
                              )
                            : null,
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Engelliyken yazma alanı yok → yanıt da verilemez.
            if (_engelleyen == null)
              ListTile(
                leading: Icon(Icons.reply_rounded, color: Renkler.neon),
                title: Text('Yanıtla', style: Yazi.isim),
                onTap: () {
                  Navigator.pop(context);
                  _yanitla(mesaj);
                },
              ),
            if (duzenlenebilir)
              ListTile(
                leading: Icon(Icons.edit_rounded, color: Renkler.neon),
                title: Text('Düzenle', style: Yazi.isim),
                subtitle: Text('İlk 15 dakika içinde', style: Yazi.kucuk),
                onTap: () {
                  Navigator.pop(context);
                  _duzenle(mesaj);
                },
              ),
            ListTile(
              leading: Icon(Icons.alarm_add_rounded, color: Renkler.neon),
              title: Text('Bunu bana hatırlat', style: Yazi.isim),
              onTap: () {
                Navigator.pop(context);
                _hatirlatmaSec(mesaj);
              },
            ),
            if (kopyalanabilir)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: Renkler.neon),
                title: Text('Kopyala', style: Yazi.isim),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: mesaj.metin));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mesaj kopyalandı')),
                  );
                },
              ),
            if (indirilebilir)
              ListTile(
                leading: Icon(Icons.download_rounded, color: Renkler.neon),
                title: Text('Galeriye indir', style: Yazi.isim),
                subtitle: Text('Orijinal kalitede kaydedilir', style: Yazi.kucuk),
                onTap: () {
                  Navigator.pop(context);
                  _medyaIndir(mesaj);
                },
              ),
            if (dosyaMi)
              ListTile(
                leading: Icon(Icons.download_rounded, color: Renkler.neon),
                title: Text('Telefona kaydet', style: Yazi.isim),
                subtitle: Text(
                  'İndirilenler › ROY MESSANGER klasörüne',
                  style: Yazi.kucuk,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _dosyaKaydet(mesaj);
                },
              ),
            if (silinebilir)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Renkler.tehlike),
                title: Text('Mesajı sil',
                    style: Yazi.stil(16, FontWeight.w700, Renkler.tehlike)),
                subtitle:
                    Text('Yalnızca ilk 1 dakika içinde', style: Yazi.kucuk),
                onTap: () {
                  Navigator.pop(context);
                  _mesajSil(mesaj);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Mesajı yanıtlamak üzere seç: yazma alanının üstünde alıntı çubuğu
  /// açılır ve klavye gelir. Gönderilen METİN mesajı bu alıntıyı taşır.
  void _yanitla(Mesaj mesaj) {
    if (_duzenleVN.value != null) _duzenlemeIptal();
    _yanitVN.value = mesaj;
    if (_emojiAcik) setState(() => _emojiAcik = false);
    _odak.requestFocus();
  }

  // ---- DÜZENLEME ----

  /// Mesajı düzenlemeye başla: yazma alanı mesajın metniyle dolar, üstte
  /// "Mesajı düzenle" çubuğu açılır.
  void _duzenle(Mesaj mesaj) {
    _yanitVN.value = null;
    _duzenleVN.value = mesaj;
    _mesajCtrl.value = TextEditingValue(
      text: mesaj.metin,
      selection: TextSelection.collapsed(offset: mesaj.metin.length),
    );
    if (_emojiAcik) setState(() => _emojiAcik = false);
    _odak.requestFocus();
  }

  void _duzenlemeIptal() {
    _duzenleVN.value = null;
    _mesajCtrl.clear();
  }

  Future<void> _duzenlemeyiKaydet(Mesaj mesaj, String metin) async {
    final temiz = metin.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (temiz.length > MesajServisi.metinSiniri) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Mesaj çok uzun.')),
      );
      return;
    }
    _duzenleVN.value = null;
    _mesajCtrl.clear();
    _yaziyorTimer?.cancel();
    _yaziyorGonderildi = false;
    unawaited(_presence.yaziyorAyarla(widget.chatId, false));
    if (temiz == mesaj.metin.trim()) return; // değişiklik yok
    try {
      await _servis.mesajDuzenle(widget.chatId, mesaj.id, temiz);
    } catch (e) {
      HataServisi.instance.iz('mesaj duzenlenemedi: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Düzenlenemedi — 15 dakikalık süre dolmuş olabilir.'),
        ),
      );
    }
  }

  // ---- SOHBET İÇİ ARAMA ----

  void _aramaAc() {
    _aramaCtrl.clear();
    setState(() {
      _aramaAcik = true;
      _aramaSonuclari = const [];
      _aramaIndeks = 0;
      _aramaKaynak = _sonMesajlar;
    });
  }

  void _aramaKapat() {
    _vurguTimer?.cancel();
    _vurguVN.value = null;
    setState(() {
      _aramaAcik = false;
      _aramaSonuclari = const [];
      _aramaEskiBekleniyor = false;
    });
  }

  /// Sorgu değişti → en yeni eşleşmeye git.
  void _aramaYap() {
    final sonuc = sohbetteAra(_sonMesajlar, _aramaCtrl.text);
    setState(() {
      _aramaSonuclari = sonuc;
      _aramaIndeks = 0;
      _aramaKaynak = _sonMesajlar;
      _aramaEskiBekleniyor = false;
    });
    if (sonuc.isNotEmpty) _aramaGit();
  }

  /// Mesaj listesi değişti: seçili eşleşmeyi koruyarak sonuçları yenile.
  /// Eski sayfa ARAMA için yüklendiyse bir sonraki (daha eski) eşleşmeye geç.
  void _aramaTazele() {
    if (!mounted || !_aramaAcik) return;
    final seciliId = _aramaIndeks < _aramaSonuclari.length
        ? _aramaSonuclari[_aramaIndeks].id
        : null;
    final yeni = sohbetteAra(_sonMesajlar, _aramaCtrl.text);
    var i = seciliId == null ? 0 : yeni.indexWhere((m) => m.id == seciliId);
    if (i < 0) i = 0;
    final bekliyordu = _aramaEskiBekleniyor;
    final eskiyeGec = bekliyordu && i + 1 < yeni.length && seciliId != null;
    _aramaEskiBekleniyor = false;
    setState(() {
      _aramaSonuclari = yeni;
      _aramaIndeks = eskiyeGec ? i + 1 : i;
    });
    if (eskiyeGec || (bekliyordu && seciliId == null && yeni.isNotEmpty)) {
      _aramaGit();
    } else if (bekliyordu) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hepsiYuklendi
                ? 'Daha eski eşleşme yok.'
                : 'Yüklenen mesajlarda daha eski eşleşme yok — ↑ ile devam et.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// [yon] 1 = daha eski, -1 = daha yeni eşleşme. En eskideyken ↑ daha
  /// eski mesajları yükleyip aramayı sürdürür.
  void _aramaSonraki(int yon) {
    final n = _aramaSonuclari.length;
    if (yon > 0 && _aramaIndeks + 1 >= n) {
      if (_hepsiYuklendi) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daha eski eşleşme yok.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      if (_aramaEskiBekleniyor) return;
      _aramaEskiBekleniyor = true;
      setState(() => _mesajLimit += 200);
      return;
    }
    if (n == 0) return;
    setState(() => _aramaIndeks = (_aramaIndeks + yon).clamp(0, n - 1));
    _aramaGit();
  }

  Future<void> _aramaGit() async {
    if (_aramaIndeks >= _aramaSonuclari.length) return;
    final id = _aramaSonuclari[_aramaIndeks].id;
    _vurguTimer?.cancel();
    _vurguVN.value = id;
    await _listeAnahtari.currentState?.mesajaGit(id);
    _vurguTimer = Timer(const Duration(milliseconds: 1600), () {
      if (_vurguVN.value == id) _vurguVN.value = null;
    });
  }

  PreferredSizeWidget _aramaCubugu() {
    final n = _aramaSonuclari.length;
    final sorguVar = _aramaCtrl.text.trim().length >= 2;
    return AppBar(
      leading: IconButton(
        tooltip: 'Aramayı kapat',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _aramaKapat,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _aramaCtrl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: Yazi.govde,
        cursorColor: Renkler.neon,
        decoration: InputDecoration(
          hintText: 'Sohbette ara…',
          hintStyle: Yazi.kucuk,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
        ),
        onChanged: (_) => _aramaYap(),
        onSubmitted: (_) => _aramaSonraki(1),
      ),
      actions: [
        if (sorguVar)
          Center(
            child: Text(
              n == 0 ? '0' : '${_aramaIndeks + 1}/$n',
              style: Yazi.kucuk,
            ),
          ),
        if (_aramaEskiBekleniyor)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Renkler.neon,
              ),
            ),
          ),
        IconButton(
          tooltip: 'Daha eski eşleşme',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: sorguVar ? () => _aramaSonraki(1) : null,
        ),
        IconButton(
          tooltip: 'Daha yeni eşleşme',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: _aramaIndeks > 0 ? () => _aramaSonraki(-1) : null,
        ),
      ],
    );
  }

  /// Sohbeti sessize al / sessizi kapat. Ekrandaki durum canlı akıştan
  /// (sessizMi) güncellenir; hata olursa kullanıcıya söylenir.
  Future<void> _sessizDegistir() async {
    final yeni = !_sessiz;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sohbetServis.sessizeAl(widget.chatId, yeni);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            yeni
                ? 'Sohbet sessize alındı — bildirimler sessiz gelecek.'
                : 'Sohbetin sesi açıldı.',
          ),
        ),
      );
    } catch (e) {
      HataServisi.instance.iz('sessize alinamadi: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Ayar kaydedilemedi. Tekrar dene.')),
      );
    }
  }

  /// Medyayı galeriye indirir (ilerleme + sonuç bildirimi).
  Future<void> _medyaIndir(Mesaj mesaj) async {
    final url = mesaj.medyaUrl;
    if (url == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('İndiriliyor…'), duration: Duration(seconds: 2)),
    );
    final ok = await MedyaIndirServisi.instance.galeriyeIndir(url, mesaj.tip);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Galeriye kaydedildi ✓' : 'İndirilemedi'),
      ),
    );
  }

  /// "Bunu bana hatırlat": hazır süreler ya da tarih/saat seç → o an
  /// bildirim gelir, dokununca bu sohbet açılır.
  Future<void> _hatirlatmaSec(Mesaj mesaj) async {
    final simdi = DateTime.now();
    final secim = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.alarm_rounded, color: Renkler.neon),
                  const SizedBox(width: 10),
                  Text('Ne zaman hatırlatayım?', style: Yazi.baslikOrta),
                ],
              ),
            ),
            for (final s in hatirlatmaSecenekleri(simdi))
              ListTile(
                title: Text(s.etiket, style: Yazi.isim),
                trailing: Text(
                  hatirlatmaMetni(s.zaman, simdi),
                  style: Yazi.kucuk,
                ),
                onTap: () => Navigator.pop(bc, s.zaman),
              ),
            ListTile(
              leading: Icon(Icons.edit_calendar_rounded, color: Renkler.neon),
              title: Text('Tarih ve saat seç…', style: Yazi.isim),
              onTap: () async {
                final gun = await showDatePicker(
                  context: bc,
                  initialDate: simdi,
                  firstDate: DateTime(simdi.year, simdi.month, simdi.day),
                  lastDate: simdi.add(const Duration(days: 365)),
                );
                if (gun == null || !bc.mounted) return;
                final saat = await showTimePicker(
                  context: bc,
                  initialTime: TimeOfDay.fromDateTime(
                    simdi.add(const Duration(hours: 1)),
                  ),
                );
                if (saat == null || !bc.mounted) return;
                Navigator.pop(
                  bc,
                  DateTime(gun.year, gun.month, gun.day, saat.hour, saat.minute),
                );
              },
            ),
          ],
        ),
      ),
    );
    if (secim == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!secim.isAfter(DateTime.now())) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Geçmiş bir zaman seçilemez.')),
      );
      return;
    }
    final kimden = mesaj.gonderen == _uid ? 'Sen' : widget.karsi.ad;
    try {
      final id = await HatirlaticiServisi.instance.mesajHatirlat(
        chatId: widget.chatId,
        karsiUid: widget.karsi.uid,
        baslik: '⏰ Hatırlatma · ${widget.karsi.ad}',
        ozet: '$kimden: ${mesaj.yanitIcinOnizleme}',
        mesajId: mesaj.id,
        zaman: secim,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '⏰ ${hatirlatmaMetni(secim, DateTime.now())} hatırlatılacak',
          ),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () =>
                HatirlaticiServisi.instance.mesajHatirlatmaIptal(id),
          ),
        ),
      );
    } catch (e) {
      HataServisi.instance.iz('hatirlatma kurulamadi: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Hatırlatma kurulamadı.')),
      );
    }
  }

  /// Dosyayı telefonun İndirilenler klasörüne kaydeder.
  Future<void> _dosyaKaydet(Mesaj mesaj) async {
    final url = mesaj.medyaUrl;
    if (url == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('İndiriliyor…'), duration: Duration(seconds: 2)),
    );
    final ok = await DosyaServisi.instance
        .telefonaKaydet(url, mesaj.dosyaAdi ?? 'dosya');
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'İndirilenler klasörüne kaydedildi ✓' : 'Kaydedilemedi',
        ),
      ),
    );
  }

  /// Mesajı siler (onay ister). Süre dolduysa sunucu da reddeder.
  Future<void> _mesajSil(Mesaj mesaj) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Mesajı sil'),
        content: const Text(
          'Bu mesaj her iki taraftan da kalıcı olarak silinecek. '
          'Mesajlar yalnızca gönderildikten sonraki 1 dakika içinde silinebilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Sil', style: TextStyle(color: Renkler.tehlike)),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _servis.mesajSil(widget.chatId, mesaj.id);
      messenger.showSnackBar(const SnackBar(content: Text('Mesaj silindi')));
    } catch (_) {
      // Sunucu reddetti (büyük olasılıkla 1 dakika doldu).
      messenger.showSnackBar(
        const SnackBar(content: Text('Silinemedi — 1 dakikalık süre dolmuş.')),
      );
    }
  }
}

/// AppBar başlığı: karşı tarafın avatarı + adı + altında
/// yazıyor / çevrimiçi / son görülme durumu.
/// İki canlı kaynak: users/{karsi} (çevrimiçi/son görülme) ve
/// chats/{chatId}.yaziyor (anlık yazıyor).
class _AppBarBaslik extends StatefulWidget {
  final String chatId;
  final Kullanici karsi;

  /// Sohbet sessizdeyse adın yanında küçük bir sessiz ikonu gösterilir.
  final bool sessiz;
  const _AppBarBaslik({
    required this.chatId,
    required this.karsi,
    this.sessiz = false,
  });

  @override
  State<_AppBarBaslik> createState() => _AppBarBaslikState();
}

class _AppBarBaslikState extends State<_AppBarBaslik> {
  // ⚠️ Akışlar State'te ÖNBELLEKTE: eskiden `stream:` build içinde
  // kullaniciDinle/sohbetDinle çağırıyordu → sohbet ekranının HER yeniden
  // çiziminde (emoji paneli, yükleme çubuğu, tema değişimi, sessiz durumu)
  // iki Firestore aboneliği kapatılıp yeniden açılıyordu (okuma kotası;
  // arada başlık bir an "çevrimdışı"/yazıyor-sız görünebiliyordu).
  late Stream<Kullanici> _kullaniciAkisi;
  late Stream<Sohbet> _sohbetAkisi;

  @override
  void initState() {
    super.initState();
    _kullaniciAkisi = PresenceServisi.instance.kullaniciDinle(widget.karsi.uid);
    _sohbetAkisi = SohbetServisi.instance.sohbetDinle(widget.chatId);
  }

  @override
  void didUpdateWidget(_AppBarBaslik old) {
    super.didUpdateWidget(old);
    if (old.karsi.uid != widget.karsi.uid) {
      _kullaniciAkisi =
          PresenceServisi.instance.kullaniciDinle(widget.karsi.uid);
    }
    if (old.chatId != widget.chatId) {
      _sohbetAkisi = SohbetServisi.instance.sohbetDinle(widget.chatId);
    }
  }

  // Gün bilgisi de yazılır (bugün/dün/tarih) — bkz. zaman_metni.dart.
  String _sonGorulmeMetni(Kullanici k) {
    if (k.cevrimici) return 'çevrimiçi';
    final t = k.sonGorulme;
    if (t != null) return sonGorulmeMetni(t);
    return 'çevrimdışı';
  }

  @override
  Widget build(BuildContext context) {
    final karsi = widget.karsi;
    final sessiz = widget.sessiz;
    return StreamBuilder<Kullanici>(
      stream: _kullaniciAkisi,
      initialData: karsi,
      builder: (context, snap) {
        final k = snap.data ?? karsi;
        return StreamBuilder<Sohbet>(
          stream: _sohbetAkisi,
          builder: (context, sohbetSnap) {
            final yaziyor =
                sohbetSnap.data?.digerYaziyor(
                  FirebaseAuth.instance.currentUser?.uid ?? '',
                ) ??
                false;
            final durum = yaziyor ? 'yazıyor...' : _sonGorulmeMetni(k);
            final vurgulu = yaziyor || k.cevrimici;

            return Row(
              children: [
                KullaniciAvatar(kullanici: k, boyut: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              k.ad,
                              overflow: TextOverflow.ellipsis,
                              style: Yazi.isim,
                            ),
                          ),
                          if (sessiz) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 15,
                              color: Renkler.metinSoluk,
                              semanticLabel: 'Sessizde',
                            ),
                          ],
                        ],
                      ),
                      if (durum.isNotEmpty)
                        Row(
                          children: [
                            if (vurgulu) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: Kutular.neonNokta(),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                durum,
                                overflow: TextOverflow.ellipsis,
                                style: vurgulu ? Yazi.neonKucuk : Yazi.zaman,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Tek bir mesaj balonu (uzun basınca tepki seçici). Metin veya medya gösterir.
class _MesajBalonu extends StatelessWidget {
  final Mesaj mesaj;
  final bool benimMi;
  final String chatId;

  /// Alıntı başlığı için: alıntılanan mesaj benimse "Sen", değilse [karsiAd].
  final String benimUid;
  final String karsiAd;
  final VoidCallback onUzunBas;

  /// Çift dokunma (❤️). null → çift dokunma tanınmaz (ses/video: tek
  /// dokunuş gecikmesin).
  final VoidCallback? onCiftDokun;

  /// Az önce çift dokunuldu → balonun üstünde kalp patlaması.
  final bool kalp;

  /// Cevapsız arama kaydındaki "geri ara / tekrar ara" (video mu?).
  final void Function(bool video)? onAra;

  const _MesajBalonu({
    required this.mesaj,
    required this.benimMi,
    required this.chatId,
    required this.benimUid,
    required this.karsiAd,
    required this.onUzunBas,
    this.onCiftDokun,
    this.kalp = false,
    this.onAra,
  });

  String _saat(DateTime? t) => t == null ? '' : saatMetni(t);

  /// Tam ekran görüntüleyicinin başlığı: kimin gönderdiği.
  String get _kimden => benimMi ? 'Sen' : karsiAd;

  /// Yanıt balonunun üstündeki alıntı kutusu (kimden + önizleme).
  /// Neon balonda koyu, karşı tarafın koyu balonunda neon tonlarla çizilir.
  Widget _alintiKutusu() {
    final vurgu = benimMi ? Renkler.metinKoyu : Renkler.neon;
    final metinRengi = benimMi ? Renkler.metinKoyuYumusak : Renkler.metin;
    final kimden = mesaj.yanitGonderen == benimUid ? 'Sen' : karsiAd;
    // ⚠️ Sol şerit İÇ kutunun kenarı, yuvarlak köşe DIŞ kutunun kırpması:
    // tek BoxDecoration'da tek taraflı Border + borderRadius Flutter'da
    // "uniform border" doğrulamasına takılıp çizimde hata fırlatabiliyor.
    return Container(
      margin: EdgeInsets.only(bottom: mesaj.tip == MesajTipi.metin ? 6 : 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: vurgu.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: vurgu, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kimden,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Yazi.stil(12, FontWeight.w800, vurgu),
            ),
            const SizedBox(height: 2),
            Text(
              mesaj.yanitOnizleme ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Yazi.stil(13, FontWeight.w500, metinRengi),
            ),
          ],
        ),
      ),
    );
  }

  /// Balon içindeki medyanın organik köşesi (balonla uyumlu, bir köşe kısa).
  BorderRadius get _medyaKose => benimMi ? Kose.medyaBen : Kose.medyaKarsi;

  // Mesaj türüne göre içerik
  Widget _icerik(BuildContext context) {
    // ⚠️ VERİ + BELLEK: fotoğraflar ORİJİNAL kalitede (ör. 4000×3000, birkaç
    // MB) gidiyor. Balonda artık Cloudinary'nin KÜÇÜK hâli (kucukResimUrl,
    // ~100 KB) iner ve telefonda saklanır (OnbellekliResim) — eskiden her
    // açılışta orijinal yeniden iniyordu. Balon genişliğinde çözülür;
    // ORİJİNAL yalnız dokununca, tam ekranda yüklenir.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    switch (mesaj.tip) {
      case MesajTipi.resim:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => FotoGoruntuleyici.ac(
            context,
            url: mesaj.medyaUrl!,
            baslik: _kimden,
            zaman: mesaj.zaman,
          ),
          child: ClipRRect(
            borderRadius: _medyaKose,
            child: Image(
              image: ResizeImage(
                OnbellekliResim(kucukResimUrl(mesaj.medyaUrl!)),
                width: (220 * dpr).round(),
              ),
              width: 220,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : Container(
                      width: 220,
                      height: 160,
                      alignment: Alignment.center,
                      color: Renkler.zemin,
                      child: CircularProgressIndicator(
                        color: Renkler.neon,
                      ),
                    ),
              errorBuilder: (c, e, s) => SizedBox(
                width: 220,
                height: 100,
                child: Icon(Icons.broken_image, color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      case MesajTipi.video:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _VideoKapagi(
          url: mesaj.medyaUrl!,
          kose: _medyaKose,
          onTap: () => VideoGoruntuleyici.ac(
            context,
            url: mesaj.medyaUrl!,
            baslik: _kimden,
            zaman: mesaj.zaman,
          ),
        );
      case MesajTipi.ses:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _SesOynatici(
          url: mesaj.medyaUrl!,
          benimMi: benimMi,
          chatId: chatId,
          mesajId: mesaj.id,
          dinlendi: mesaj.sesDinlendi,
        );
      case MesajTipi.gif:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => FotoGoruntuleyici.ac(
            context,
            url: mesaj.medyaUrl!,
            tip: MesajTipi.gif,
            baslik: _kimden,
            zaman: mesaj.zaman,
          ),
          child: ClipRRect(
            borderRadius: _medyaKose,
            child: Image(
              // GIPHY adresi (Cloudinary değil) → küçültülmez, yalnız
              // telefonda saklanır.
              image: ResizeImage(
                OnbellekliResim(mesaj.medyaUrl!),
                width: (170 * dpr).round(),
              ),
              width: 170,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : Container(
                      width: 170,
                      height: 170,
                      alignment: Alignment.center,
                      color: Renkler.zemin,
                      child: CircularProgressIndicator(
                        color: Renkler.neon,
                      ),
                    ),
              errorBuilder: (c, e, s) => SizedBox(
                width: 170,
                height: 90,
                child: Icon(Icons.broken_image, color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      case MesajTipi.arama:
        return _AramaKaydiIcerik(mesaj: mesaj, benimMi: benimMi, onAra: onAra);
      case MesajTipi.dosya:
        return _DosyaIcerik(mesaj: mesaj, benimMi: benimMi);
      case MesajTipi.metin:
        // Neon balon üstünde koyu, karşı tarafın koyu balonunda açık metin
        // Bağlantılar altı çizili ve tıklanınca tarayıcıda açılır.
        return LinkliMetin(
          metin: mesaj.metin,
          stil: benimMi ? Yazi.govdeAccent : Yazi.govde,
          linkRengi: benimMi ? Renkler.metinKoyu : Renkler.neon,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Medya balonu içi dar boşluklu (foto kenara yakın); metin, arama kaydı
    // ve dosya normal boşluklu.
    final medyaMi = const {
      MesajTipi.resim,
      MesajTipi.video,
      MesajTipi.ses,
      MesajTipi.gif,
    }.contains(mesaj.tip);
    return Align(
      alignment: benimMi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onUzunBas,
        onDoubleTap: onCiftDokun,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: EdgeInsets.only(
                top: 4,
                bottom: mesaj.tepkiVar ? 16 : 4,
              ),
              // Kendi balonun: neon gradient + ÇOK HAFİF glow (göz yormasın).
              // Karşı taraf: zeminden net ayrışan koyu yüzey, GLOW YOK.
              // Organik köşe — dip köşe kısa. 3D his gradient + iç ışıktan gelir.
              decoration: benimMi
                  ? Kutular.accent(
                      kose: Kose.balonBen,
                      golge: Golgeler.balonNeon,
                    )
                  : BoxDecoration(
                      gradient: Gradyanlar.balonGelen,
                      borderRadius: Kose.balonKarsi,
                      border: Border.all(color: Renkler.kenarGuclu),
                      boxShadow: Golgeler.balonGelen,
                    ),
              child: Stack(
                children: [
                  // Cam parıltısı BALONUN TAMAMINDA (bkz. BalonParilti):
                  // iç boşluk aşağıdaki Padding'de, parıltı onun dışında.
                  Positioned.fill(
                    child: BalonParilti(
                      kose: benimMi ? Kose.balonBen : Kose.balonKarsi,
                      vurgu: benimMi,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(medyaMi ? 5 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mesaj.yanitMi) _alintiKutusu(),
                        _icerik(context),
                        // Fotoğraf/video AÇIKLAMASI (linkler tıklanabilir).
                        if ((mesaj.tip == MesajTipi.resim ||
                                mesaj.tip == MesajTipi.video) &&
                            mesaj.metin.trim().isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                              child: LinkliMetin(
                                metin: mesaj.metin.trim(),
                                stil: benimMi ? Yazi.govdeAccent : Yazi.govde,
                                linkRengi:
                                    benimMi ? Renkler.metinKoyu : Renkler.neon,
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(top: 3, left: medyaMi ? 6 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Gelen, henüz dinlenmemiş sesli mesaj → neon nokta
                              if (mesaj.tip == MesajTipi.ses &&
                                  !benimMi &&
                                  !mesaj.sesDinlendi) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: Kutular.neonNokta(),
                                ),
                                const SizedBox(width: 5),
                              ],
                              if (mesaj.duzenlendi) ...[
                                Text(
                                  'düzenlendi',
                                  style: (benimMi
                                          ? Yazi.zamanAccent
                                          : Yazi.zaman)
                                      .copyWith(fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                _saat(mesaj.zaman),
                                style: benimMi ? Yazi.zamanAccent : Yazi.zaman,
                              ),
                              if (benimMi) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  mesaj.goruldu ? Icons.done_all : Icons.done,
                                  size: 15,
                                  color: mesaj.goruldu
                                      ? Renkler.metinKoyu
                                      : Renkler.metinKoyuYumusak,
                                ),
                                // Gönderdiğim ses dinlendiyse kulaklık
                                if (mesaj.tip == MesajTipi.ses &&
                                    mesaj.sesDinlendi) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.headset_rounded,
                                    size: 13,
                                    color: Renkler.metinKoyu,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (mesaj.tepkiVar)
              Positioned(
                bottom: 0,
                right: benimMi ? 8 : null,
                left: benimMi ? null : 8,
                // Rozete dokununca tepki menüsü açılır (değiştir/kaldır).
                child: GestureDetector(
                  onTap: onUzunBas,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Renkler.yuzeyYuksek,
                      borderRadius: BorderRadius.circular(12),
                      // Benim de tepkim varsa kenar neon.
                      border: Border.all(
                        color: mesaj.tepkiler.containsKey(benimUid)
                            ? Renkler.neon
                            : Renkler.kenarGuclu,
                        width: 1.5,
                      ),
                      boxShadow: Golgeler.balon,
                    ),
                    child: Text(
                      [
                        for (final t in mesaj.tepkiOzeti)
                          t.sayi > 1 ? '${t.emoji} ${t.sayi}' : t.emoji,
                      ].join(' '),
                      style: Yazi.stil(13, FontWeight.w700, Renkler.metin),
                    ),
                  ),
                ),
              ),
            if (kalp)
              const Positioned.fill(
                child: IgnorePointer(child: Center(child: KalpPatlamasi())),
              ),
          ],
        ),
      ),
    );
  }
}

/// Video balonu: hafif KAPAK (Cloudinary'nin videodan çıkardığı küçük JPEG,
/// telefonda saklanır) + oynat rozeti. Dokununca TAM EKRAN oynatıcı açılır
/// (orada ileri-geri sarma ve "Galeriye indir" var).
///
/// ⚠️ Balonda oynatıcı KURULMAZ: eskiden her video balonu kendi
/// VideoPlayerController'ını kuruyordu; video dolu bir sohbeti açmak ekrana
/// giren her video için ağdan dosya başı indirip ExoPlayer açıyordu
/// (mobil veri, bellek, takılma).
class _VideoKapagi extends StatelessWidget {
  final String url;

  /// Balonun organik köşesiyle uyumlu medya köşesi
  final BorderRadius kose;
  final VoidCallback onTap;
  const _VideoKapagi({
    required this.url,
    required this.kose,
    required this.onTap,
  });

  Widget _koyuKutu() =>
      Container(width: 220, height: 160, color: Renkler.zeminDerin);

  @override
  Widget build(BuildContext context) {
    final kapakUrl = videoKapakUrl(url);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: kose,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (kapakUrl == null)
              _koyuKutu()
            else
              Image(
                image: ResizeImage(
                  OnbellekliResim(kucukResimUrl(kapakUrl)),
                  width: (220 * dpr).round(),
                ),
                width: 220,
                height: 160,
                fit: BoxFit.cover,
                // Kapak üretilemezse (eski/harici URL, ağ hatası) düz koyu
                // kutu: video yine dokununca açılır.
                errorBuilder: (c, e, s) => _koyuKutu(),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: Gradyanlar.accent,
                shape: BoxShape.circle,
                boxShadow: Golgeler.neonGlow,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(Icons.play_arrow, color: Renkler.metinKoyu, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sesli mesaj oynatıcı: çal/duraklat + ses dalgası (seek) + konum/süre + hız.
/// Kendi AudioPlayer'ı YOKTUR — uygulama genelindeki tek oynatıcının
/// (SesOynaticiServisi) durumunu dinler; birini başlatmak öncekini durdurur.
class _SesOynatici extends StatefulWidget {
  final String url;
  final bool benimMi;
  final String chatId;
  final String mesajId;
  final bool dinlendi;
  const _SesOynatici({
    required this.url,
    required this.benimMi,
    required this.chatId,
    required this.mesajId,
    required this.dinlendi,
  });

  @override
  State<_SesOynatici> createState() => _SesOynaticiState();
}

class _SesOynaticiState extends State<_SesOynatici> {
  final _servis = SesOynaticiServisi.instance;
  late List<double> _dalga;

  @override
  void initState() {
    super.initState();
    // Ağ dosyası için gerçek dalga çıkarmak ağırdır → URL'den sabit dekoratif dalga.
    _dalga = _dalgaUret(widget.url);
  }

  @override
  void didUpdateWidget(_SesOynatici old) {
    super.didUpdateWidget(old);
    // Dalga URL'den üretilir; State başka bir sesli mesaja geçerse (eskiden
    // anahtarsız listede her yeni mesajda oluyordu) dalga da onunki olsun.
    if (old.url != widget.url) _dalga = _dalgaUret(widget.url);
  }

  // NOT: dispose'ta oynatıcıya DOKUNULMAZ. Balon kaydırılıp listeden düşse
  // de ses çalmaya devam eder; ekrandan çıkınca SohbetEkrani durdurur.

  List<double> _dalgaUret(String s) {
    final r = Random(s.hashCode);
    return List.generate(48, (_) => 0.2 + r.nextDouble() * 0.8);
  }

  bool get _benim => _servis.calanId.value == widget.mesajId;

  Future<void> _degistir() async {
    final basladi = await _servis.oynatDuraklat(
      mesajId: widget.mesajId,
      url: widget.url,
      chatId: widget.chatId,
    );
    // Karşı tarafın sesli mesajıysa ve henüz dinlenmediyse "dinlendi" işaretle
    if (basladi && !widget.benimMi && !widget.dinlendi) {
      // Ateşle-unut: oynatmayı bekletmesin; hata servis içinde yutulur.
      unawaited(MesajServisi.instance
          .sesDinlendiIsaretle(widget.chatId, widget.mesajId));
    }
  }

  String _mmss(Duration d) {
    final dk = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final sn = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$dk:$sn';
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Yalnız ÇALAN balon konum olaylarıyla (saniyede birkaç kez) yeniden
    // çizilir: diğer balonlar sadece calanId/hız değişince çizilir.
    return ValueListenableBuilder<String?>(
      valueListenable: _servis.calanId,
      builder: (context, calan, _) {
        if (calan != widget.mesajId) return _cerceve(false, 0, 0);
        return ListenableBuilder(
          listenable: Listenable.merge([
            _servis.caliyor,
            _servis.konum,
            _servis.sure,
          ]),
          builder: (context, _) => _cerceve(
            _servis.caliyor.value,
            _servis.konum.value.inMilliseconds,
            _servis.sure.value.inMilliseconds,
          ),
        );
      },
    );
  }

  Widget _cerceve(bool caliyor, int konumMs, int sureMs) {
    // Neon balonda koyu, karşı tarafın koyu balonunda neon renk
    final renk = widget.benimMi ? Renkler.metinKoyu : Renkler.neon;
    final oran = sureMs == 0 ? 0.0 : (konumMs / sureMs).clamp(0.0, 1.0);
    final konum = Duration(milliseconds: konumMs);
    final sure = Duration(milliseconds: sureMs);
    void seek(double dx, double genislik) {
      if (!_benim) return; // yüklü olmayan seste süre bilinmiyor
      _servis.konumaGit(widget.mesajId, (dx / genislik).clamp(0.0, 1.0));
    }

    return SizedBox(
      width: 218,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _degistir,
                child: Icon(
                  caliyor ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: renk,
                  size: 36,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => seek(d.localPosition.dx, c.maxWidth),
                    onHorizontalDragUpdate: (d) =>
                        seek(d.localPosition.dx, c.maxWidth),
                    child: SizedBox(
                      height: 30,
                      child: CustomPaint(
                        painter: _DalgaPainter(_dalga, renk, ilerleme: oran),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 2),
            child: Row(
              children: [
                Text(
                  '${_mmss(konum)} / ${sureMs == 0 ? "--:--" : _mmss(sure)}',
                  style: TextStyle(
                    color: renk.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _servis.hizDegistir,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ValueListenableBuilder<double>(
                      valueListenable: _servis.hiz,
                      builder: (_, hiz, _) {
                        final hizYazi = hiz == hiz.roundToDouble()
                            ? '${hiz.toInt()}'
                            : '$hiz';
                        return Text(
                          '${hizYazi}x',
                          style: TextStyle(
                            color: renk,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cevapsız arama kaydı balonu. Aranan: "Cevapsız sesli arama — geri
/// aramak için dokun"; arayan: "Sesli arama — Cevap verilmedi / Reddedildi
/// / Meşgul". Dokununca aynı türde arama başlar.
class _AramaKaydiIcerik extends StatelessWidget {
  final Mesaj mesaj;
  final bool benimMi;
  final void Function(bool video)? onAra;
  const _AramaKaydiIcerik({
    required this.mesaj,
    required this.benimMi,
    this.onAra,
  });

  @override
  Widget build(BuildContext context) {
    final video = mesaj.videoAramaMi;
    final renk = benimMi ? Renkler.metinKoyu : Renkler.metin;
    final soluk = benimMi ? Renkler.metinKoyuYumusak : Renkler.metinSoluk;
    final vurgu = benimMi ? Renkler.metinKoyu : Renkler.tehlike;
    final baslik = benimMi
        ? (video ? 'Görüntülü arama' : 'Sesli arama')
        : (video ? 'Cevapsız görüntülü arama' : 'Cevapsız sesli arama');
    final alt = benimMi
        ? switch (mesaj.aramaSonucu) {
            'red' => 'Reddedildi',
            'mesgul' => 'Meşguldü',
            'iptal' => 'Cevap beklenmeden kapatıldı',
            _ => 'Cevap verilmedi',
          }
        : 'Geri aramak için dokun';
    final ara = onAra;
    return GestureDetector(
      onTap: ara == null ? null : () => ara(video),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: vurgu.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              benimMi ? Icons.call_made_rounded : Icons.call_missed_rounded,
              size: 20,
              color: vurgu,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(baslik, style: Yazi.stil(15, FontWeight.w700, renk)),
                const SizedBox(height: 2),
                Text(alt, style: Yazi.stil(12, FontWeight.w500, soluk)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Icon(
            video ? Icons.videocam_rounded : Icons.call_rounded,
            size: 22,
            color: benimMi ? Renkler.metinKoyu : Renkler.neon,
          ),
        ],
      ),
    );
  }
}

/// Dosya (PDF, Word…) balonu: renkli uzantı rozeti + ad + boyut. Dokununca
/// indirilir (ilerlemeyle) ve telefondaki uygun uygulamayla açılır.
class _DosyaIcerik extends StatefulWidget {
  final Mesaj mesaj;
  final bool benimMi;
  const _DosyaIcerik({required this.mesaj, required this.benimMi});

  @override
  State<_DosyaIcerik> createState() => _DosyaIcerikState();
}

class _DosyaIcerikState extends State<_DosyaIcerik> {
  double? _ilerleme;
  bool _aciliyor = false;

  Color _rozetRengi(String etiket) => switch (etiket) {
        'PDF' => const Color(0xFFE5484D),
        'DOC' || 'DOCX' => const Color(0xFF3E7BFA),
        'XLS' || 'XLSX' || 'CSV' => const Color(0xFF2EA043),
        'PPT' || 'PPTX' => const Color(0xFFF07B3F),
        'ZIP' || 'RAR' => const Color(0xFF9B6BDF),
        _ => const Color(0xFF6B7A8F),
      };

  Future<void> _ac() async {
    final url = widget.mesaj.medyaUrl;
    if (url == null || _aciliyor) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _aciliyor = true;
      _ilerleme = null;
    });
    final hata = await DosyaServisi.instance.ac(
      url,
      widget.mesaj.dosyaAdi ?? 'dosya',
      ilerleme: (p) {
        if (mounted) setState(() => _ilerleme = p);
      },
    );
    if (!mounted) return;
    setState(() => _aciliyor = false);
    if (hata != null) messenger.showSnackBar(SnackBar(content: Text(hata)));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesaj;
    final ad = m.dosyaAdi ?? 'Dosya';
    final etiket = uzantiEtiketi(ad);
    final renk = widget.benimMi ? Renkler.metinKoyu : Renkler.metin;
    final soluk =
        widget.benimMi ? Renkler.metinKoyuYumusak : Renkler.metinSoluk;
    final boyut = m.dosyaBoyutu;
    return GestureDetector(
      onTap: _ac,
      child: SizedBox(
        width: 230,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _rozetRengi(etiket),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _aciliyor
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: _ilerleme,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      etiket.length > 4 ? etiket.substring(0, 4) : etiket,
                      style: Yazi.stil(12, FontWeight.w800, Colors.white),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ad,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Yazi.stil(14, FontWeight.w700, renk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (boyut != null) boyutMetni(boyut),
                      _aciliyor ? 'İndiriliyor…' : 'Açmak için dokun',
                    ].join(' · '),
                    style: Yazi.stil(12, FontWeight.w500, soluk),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sohbetteki tarih ayracı: ortada küçük, yarı saydam "Bugün" etiketi.
class _TarihAyraci extends StatelessWidget {
  final String metin;
  const _TarihAyraci(this.metin);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Renkler.yuzey.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Renkler.kenar),
          ),
          child: Text(
            metin,
            style: Yazi.stil(12, FontWeight.w700, Renkler.metinSoluk),
          ),
        ),
      ),
    );
  }
}

/// Yazma alanının üstündeki çubuk: yanıtlanan mesaj (kime + alıntı
/// önizlemesi) ya da düzenlenen mesaj ([ikon] = kalem) + kapat (X).
/// Kapatınca mesaj normal (yanıtsız) gider / düzenleme iptal olur.
class _YanitCubugu extends StatelessWidget {
  final String kimden;
  final String onizleme;
  final VoidCallback onKapat;
  final IconData ikon;
  final String kapatIpucu;
  const _YanitCubugu({
    required this.kimden,
    required this.onizleme,
    required this.onKapat,
    this.ikon = Icons.reply_rounded,
    this.kapatIpucu = 'Yanıtı kapat',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Renkler.zemin,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      // Tek taraflı kenar + yuvarlak köşe: bkz. _alintiKutusu notu.
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Renkler.neonSis,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Renkler.neon, width: 3)),
          ),
          child: Row(
            children: [
              Icon(ikon, size: 18, color: Renkler.neon),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kimden,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Yazi.neonKucuk,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      onizleme,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Yazi.kucuk,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: kapatIpucu,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: Renkler.metinSoluk,
                ),
                onPressed: onKapat,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alt mesaj yazma çubuğu (emoji + ataç + metin + mikrofon/gönder).
class _YazmaAlani extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode odak;
  final bool emojiAcik;
  final VoidCallback onGonder;
  final VoidCallback onEk;
  final VoidCallback onEmoji;

  /// Mikrofona kısa dokunma (ipucu göster)
  final VoidCallback onMikrofonBilgi;

  /// Basılı tutma başladı → kayda başla
  final VoidCallback onKayitBasla;

  /// Basılıyken yatay kayma (sola kaydırınca iptal bölgesi)
  final void Function(double dx) onKayitSurukle;

  /// Parmak kalktı → gönder veya iptal
  final VoidCallback onKayitBitir;

  const _YazmaAlani({
    required this.controller,
    required this.odak,
    required this.emojiAcik,
    required this.onGonder,
    required this.onEk,
    required this.onEmoji,
    required this.onMikrofonBilgi,
    required this.onKayitBasla,
    required this.onKayitSurukle,
    required this.onKayitBitir,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
        color: Renkler.zemin,
        child: Row(
          children: [
            IconButton(
              tooltip: emojiAcik ? 'Klavye' : 'Emoji',
              icon: Icon(
                emojiAcik
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
                color: Renkler.neon,
              ),
              onPressed: onEmoji,
            ),
            IconButton(
              tooltip: 'Ekle',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.add_circle_outline, color: Renkler.neon),
              onPressed: onEk,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, deger, _) {
                  final bos = deger.text.trim().isEmpty;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: Kutular.duzYuzey(
                            kose: Kose.alan,
                            kenarli: true,
                          ),
                          child: TextField(
                            controller: controller,
                            focusNode: odak,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => onGonder(),
                            style: Yazi.govde,
                            decoration: const InputDecoration(
                              hintText: 'Mesaj yaz…',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Metin varsa GÖNDER; boşsa MİKROFON (basılı tut → kaydet,
                      // bırak → gönder, sola kaydır → çöpe at).
                      if (!bos)
                        Uc3DDugme(
                          kose: Kose.dugme,
                          padding: const EdgeInsets.all(13),
                          onTap: onGonder,
                          cocuk: Icon(
                            Icons.send_rounded,
                            color: Renkler.metinKoyu,
                            size: 22,
                          ),
                        )
                      else
                        GestureDetector(
                          onLongPressStart: (_) => onKayitBasla(),
                          onLongPressMoveUpdate: (d) =>
                              onKayitSurukle(d.localOffsetFromOrigin.dx),
                          onLongPressEnd: (_) => onKayitBitir(),
                          onLongPressCancel: onKayitBitir,
                          child: Uc3DDugme(
                            kose: Kose.dugme,
                            padding: const EdgeInsets.all(13),
                            onTap: onMikrofonBilgi, // kısa dokunuş → ipucu
                            cocuk: Icon(
                              Icons.mic,
                              color: Renkler.metinKoyu,
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kayıt sırasında yazma alanının ÜSTÜNE binen gösterge (WhatsApp gibi):
/// yanıp sönen kırmızı nokta + canlı süre + canlı dalga + "sola kaydır" ipucu.
/// Tamamen GÖRSEL (IgnorePointer ile sarılır) — kayıt, mikrofon butonundaki
/// basılı-tut jestiyle yönetilir. Güncellemeler ValueNotifier'la geldiği için
/// sohbet ekranının tamamı yeniden ÇİZİLMEZ (siyah yanıp sönme yok).
class _KayitKaplamasi extends StatefulWidget {
  final ValueNotifier<int> saniye;
  final ValueNotifier<List<double>> dalga;
  final ValueNotifier<bool> iptalBolgesinde;

  const _KayitKaplamasi({
    required this.saniye,
    required this.dalga,
    required this.iptalBolgesinde,
  });

  @override
  State<_KayitKaplamasi> createState() => _KayitKaplamasiState();
}

class _KayitKaplamasiState extends State<_KayitKaplamasi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _yanip;

  @override
  void initState() {
    super.initState();
    _yanip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _yanip.dispose();
    super.dispose();
  }

  String _sure(int sn) {
    final d = (sn ~/ 60).toString().padLeft(2, '0');
    final s = (sn % 60).toString().padLeft(2, '0');
    return '$d:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.iptalBolgesinde,
      builder: (context, iptal, _) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
            color: Renkler.zemin,
            child: Row(
              children: [
                // Çöp kutusu — iptal bölgesinde büyür ve kırmızıya döner
                AnimatedScale(
                  scale: iptal ? 1.35 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.delete_outline,
                    color: iptal ? Renkler.tehlike : Renkler.metinSoluk,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: Kutular.duzYuzey(
                      kose: Kose.alan,
                      kenarli: true,
                    ),
                    child: Row(
                      children: [
                        FadeTransition(
                          opacity: _yanip,
                          child: Icon(
                            Icons.fiber_manual_record,
                            color: Renkler.tehlike,
                            size: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          child: ValueListenableBuilder<int>(
                            valueListenable: widget.saniye,
                            builder: (_, sn, _) => Text(
                              _sure(sn),
                              style:
                                  Yazi.stil(
                                    13,
                                    FontWeight.w700,
                                    Renkler.metin,
                                  ).copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: iptal
                              ? Center(
                                  child: Text(
                                    'Bırak → iptal',
                                    style: Yazi.stil(
                                      12,
                                      FontWeight.w700,
                                      Renkler.tehlike,
                                    ),
                                  ),
                                )
                              : ValueListenableBuilder<List<double>>(
                                  valueListenable: widget.dalga,
                                  builder: (_, dalga, _) => SizedBox(
                                    height: 24,
                                    child: CustomPaint(
                                      painter: _DalgaPainter(
                                        dalga,
                                        Renkler.neon,
                                        canli: true,
                                      ),
                                      size: Size.infinite,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        if (!iptal)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.keyboard_arrow_left,
                                size: 16,
                                color: Renkler.metinSoluk,
                              ),
                              Text('kaydır', style: Yazi.zaman),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Mikrofon (basılı tutuluyor) — bırakınca gönderilir
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    gradient: iptal ? null : Gradyanlar.accent,
                    color: iptal ? Renkler.tehlike : null,
                    borderRadius: Kose.dugme,
                    boxShadow: iptal ? Golgeler.tehlikeGlow : Golgeler.neonGlow,
                  ),
                  child: Icon(
                    iptal ? Icons.delete : Icons.mic,
                    color: iptal ? Renkler.metinTehlikeUstu : Renkler.metinKoyu,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ses dalgası çizici. [canli]=true ise son çubukları kaydırarak gösterir
/// (kayıt); değilse sabit seti [ilerleme] oranına göre boyar (oynatma).
class _DalgaPainter extends CustomPainter {
  final List<double> dalga;
  final Color renk;
  final double ilerleme;
  final bool canli;
  _DalgaPainter(this.dalga, this.renk, {this.ilerleme = 1, this.canli = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (dalga.isEmpty) return;
    const cubuk = 3.0;
    const aralik = 2.0;
    const toplam = cubuk + aralik;
    final adet = (size.width / toplam).floor().clamp(1, 200);

    final goster = <double>[];
    if (canli) {
      final basla = (dalga.length - adet).clamp(0, dalga.length);
      for (var i = basla; i < dalga.length; i++) {
        goster.add(dalga[i]);
      }
    } else {
      for (var i = 0; i < adet; i++) {
        final idx = (i * dalga.length / adet).floor().clamp(
          0,
          dalga.length - 1,
        );
        goster.add(dalga[idx]);
      }
    }

    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cubuk;
    final orta = size.height / 2;
    for (var i = 0; i < goster.length; i++) {
      final x = i * toplam + cubuk / 2;
      final h = (goster[i] * size.height).clamp(4.0, size.height);
      final oran = goster.length <= 1 ? 1.0 : i / (goster.length - 1);
      p.color = oran <= ilerleme ? renk : renk.withValues(alpha: 0.3);
      canvas.drawLine(Offset(x, orta - h / 2), Offset(x, orta + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DalgaPainter old) =>
      old.ilerleme != ilerleme ||
      !identical(old.dalga, dalga) ||
      old.dalga.length != dalga.length;
}

/// Tema renkli, kategorili özel emoji seçici (paket gerektirmez).
class _EmojiPaneli extends StatefulWidget {
  final void Function(String) onEmoji;
  final VoidCallback onSil;
  const _EmojiPaneli({required this.onEmoji, required this.onSil});

  @override
  State<_EmojiPaneli> createState() => _EmojiPaneliState();
}

class _EmojiPaneliState extends State<_EmojiPaneli> {
  int _kategori = 0;

  static const _ikonlar = [
    Icons.emoji_emotions,
    Icons.front_hand,
    Icons.favorite,
    Icons.pets,
    Icons.fastfood,
    Icons.sports_soccer,
    Icons.lightbulb,
  ];

  static const _gruplar = <List<String>>[
    [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '🥲',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🥸',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
      '🤯',
      '😳',
      '🥵',
      '🥶',
      '😱',
      '😨',
      '😰',
      '😥',
      '😓',
      '🤗',
      '🤔',
      '🫡',
      '🤭',
      '🤫',
      '😴',
      '😪',
      '🤤',
      '😵',
      '🥴',
      '🤢',
      '🤮',
      '🤧',
      '😷',
    ],
    [
      '👍',
      '👎',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🫰',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '👋',
      '🤚',
      '🖐️',
      '✋',
      '🖖',
      '🫱',
      '🫲',
      '🫳',
      '🫴',
      '👏',
      '🙌',
      '🫶',
      '👐',
      '🤲',
      '🙏',
      '🤝',
      '💪',
      '🦾',
      '✍️',
      '💅',
      '🤳',
      '👀',
      '🫵',
      '🤜',
      '🤛',
    ],
    [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🤎',
      '🖤',
      '🤍',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
      '💌',
      '💋',
      '💯',
      '💢',
      '💥',
      '💫',
      '💦',
      '💨',
      '🔥',
      '✨',
    ],
    [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🦆',
      '🦉',
      '🐴',
      '🦄',
      '🐝',
      '🦋',
      '🐌',
      '🐞',
      '🐢',
      '🐍',
      '🐙',
      '🦀',
      '🐠',
      '🐬',
      '🐳',
      '🐋',
      '🌸',
      '🌹',
      '🌻',
      '🌷',
      '🌳',
      '🌵',
      '🍀',
      '🌙',
      '⭐',
      '🌈',
      '☀️',
      '⛅',
      '❄️',
    ],
    [
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🥑',
      '🍆',
      '🥕',
      '🌽',
      '🌶️',
      '🥔',
      '🥐',
      '🍞',
      '🧀',
      '🍗',
      '🍖',
      '🌭',
      '🍔',
      '🍟',
      '🍕',
      '🌮',
      '🌯',
      '🥗',
      '🍝',
      '🍜',
      '🍣',
      '🍦',
      '🍰',
      '🎂',
      '🍫',
      '🍬',
      '🍭',
      '🍩',
      '🍪',
      '☕',
      '🍵',
      '🥤',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
    ],
    [
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🎾',
      '🏐',
      '🏉',
      '🎱',
      '🏓',
      '🏸',
      '🥅',
      '⛳',
      '🏒',
      '🏏',
      '🥊',
      '🎮',
      '🎲',
      '🎯',
      '🎳',
      '🎤',
      '🎧',
      '🎸',
      '🎹',
      '🥁',
      '🎺',
      '🎻',
      '🎬',
      '🎨',
      '🎭',
      '🎟️',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🚗',
      '✈️',
      '🚀',
      '⛵',
      '🏖️',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
    ],
    [
      '📱',
      '💻',
      '⌚',
      '📷',
      '🔋',
      '💡',
      '🔦',
      '📺',
      '🛒',
      '💰',
      '💵',
      '💎',
      '🔑',
      '🔒',
      '🔔',
      '📌',
      '📎',
      '✂️',
      '✏️',
      '📝',
      '📚',
      '📖',
      '🗓️',
      '⏰',
      '⏳',
      '🔍',
      '❗',
      '❓',
      '💤',
      '✅',
      '❌',
      '⭕',
      '💬',
      '💭',
      '🗯️',
      '⚡',
      '🎵',
      '🎶',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    // Panel: sistem klavyesi gibi durmasın → tema yüzeyi, organik üst köşe,
    // neon kenar ve tutamaç.
    return Container(
      height: 272,
      decoration: BoxDecoration(
        gradient: Gradyanlar.yuzey,
        borderRadius: Kose.panel,
        border: Border(
          top: BorderSide(color: Renkler.kenarGuclu),
          left: BorderSide(color: Renkler.kenar),
          right: BorderSide(color: Renkler.kenar),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Tutamaç
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Renkler.kenarGuclu,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 44,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _gruplar[_kategori].length,
              itemBuilder: (_, i) {
                final e = _gruplar[_kategori][i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onEmoji(e),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Renkler.zeminDerin,
              border: Border(top: BorderSide(color: Renkler.kenar)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: _ikonlar.length,
                    itemBuilder: (_, i) {
                      final secili = i == _kategori;
                      // Seçili kategori: neon dolgu rozeti
                      return GestureDetector(
                        onTap: () => setState(() => _kategori = i),
                        child: Container(
                          width: 42,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: secili ? Renkler.neonSis : null,
                            borderRadius: Kose.dugme,
                            border: Border.all(
                              color: secili
                                  ? Renkler.kenarGuclu
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            _ikonlar[i],
                            color: secili ? Renkler.neon : Renkler.metinSoluk,
                            size: 21,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Sil',
                  icon: Icon(
                    Icons.backspace_outlined,
                    color: Renkler.metinSoluk,
                  ),
                  onPressed: widget.onSil,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş/hata durumu için ortak gösterim.
/// Yazma alanının YERİNE geçen engel şeridi.
///
/// ⚠️ Yazma alanını gizlemek KOZMETİK bir önlem değil, doğru davranıştır:
/// engelliyken Firestore kuralı mesaj oluşturmayı zaten reddeder
/// (firestore.rules `engelli()`), dolayısıyla kutuyu açık bırakmak kullanıcıya
/// yazdırıp sonra "gönderilemedi" demek olurdu. Geçmiş mesajlar görünür kalır.
class _EngelSeridi extends StatelessWidget {
  final bool benEngelledim;
  final String karsiAd;
  const _EngelSeridi({required this.benEngelledim, required this.karsiAd});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: Kutular.duzYuzey(kenarli: true),
        child: Row(
          children: [
            Icon(Icons.block, size: 18, color: Renkler.tehlike),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                benEngelledim
                    ? '$karsiAd engellendi. Engeli profilinden kaldırabilirsin.'
                    : 'Bu kişi seni engelledi. Mesaj gönderemezsin.',
                style: Yazi.kucuk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BosDurum extends StatelessWidget {
  final IconData ikon;
  final String yazi;

  const _BosDurum({required this.ikon, required this.yazi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Neon sisli ikon kutusu — organik köşe
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Renkler.neonSis,
              borderRadius: Kose.kartKose,
              border: Border.all(color: Renkler.kenar),
            ),
            child: Icon(ikon, size: 38, color: Renkler.neon),
          ),
          const SizedBox(height: 16),
          Text(yazi, textAlign: TextAlign.center, style: Yazi.kucuk),
        ],
      ),
    );
  }
}
