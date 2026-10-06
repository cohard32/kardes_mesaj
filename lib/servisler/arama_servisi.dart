import 'dart:async';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_service/agora_token_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gizli.dart'; // agoraSertifika (.gitignore'da)
import 'aktarici_servisi.dart';
import 'aktif_arama_kaydi.dart';
import 'bildirim_servisi.dart';
import 'hata_servisi.dart';
import 'kullanici_servisi.dart';

enum AramaTipi { video, ses }

AramaTipi aramaTipiCoz(String? s) =>
    s == 'video' ? AramaTipi.video : AramaTipi.ses;

/// [AramaServisi.bitir] ve arama ekranı için TEK oturum kuralı (saf → test).
/// [istenen] null ise (oturumu bilmeyen eski çağıranlar) her zaman geçerli.
/// Aksi hâlde yalnız ŞİMDİKİ oturumla eşleşen istek görüşmeye dokunabilir.
bool oturumGuncelMi({required int? istenen, required int guncel}) =>
    istenen == null || istenen == guncel;

/// Aynı sohbetin arama belgesinde BAŞKA bir kanal mı var? (saf → test)
/// [benimKanal]: açık arama ekranının katıldığı kanal; [belgeKanali]:
/// `aramalar/{chatId}.kanal`'ın son hâli.
///
/// ⚠️ NEDEN: Oturum yalnız kabulEt BAŞINDA artar. Karşı taraf çöküp aynı
/// sohbetten yeniden aradığında yeni arama CallKit'te ÇALARKEN (ve kabule
/// basıldıktan sonra kabul akışı auth/Firestore beklerken) eski ekranın
/// oturumu hâlâ "güncel"di; 20 sn sayacı dolunca bitir() 'bitti' yazıp yeni
/// aramayı düşürüyor, çalan zili endAllCalls ile kapatıyordu. Yeni arama her
/// zaman yeni rastgele kanal (`_kanalUret`) yazar ve bu yazma
/// karşı tarafa push'tan ÖNCE yapılır → eski ekran devralmayı zil çalmadan
/// görür. Kanalı bilinmeyen taraf (null/boş) devralma SAYILMAZ (emin değilsek
/// eski davranış).
bool aramaDevralindiMi({String? benimKanal, String? belgeKanali}) =>
    benimKanal != null &&
    benimKanal.isNotEmpty &&
    belgeKanali != null &&
    belgeKanali.isNotEmpty &&
    belgeKanali != benimKanal;

/// Arama başlatma/katılma hatası (kullanıcıya gösterilir).
class AramaHatasi implements Exception {
  final String mesaj;
  AramaHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Görüntülü/sesli arama servisi — Agora (medya) + Firestore (sinyalleşme).
/// FAZ 4: arama artık SOHBET (chatId) bazlı; sinyal `aramalar/{chatId}`,
/// bildirim ilgili KULLANICIYA hedefli gider.
class AramaServisi {
  AramaServisi._();
  static final AramaServisi instance = AramaServisi._();

  /// Agora App ID (console.agora.io → Testing mode).
  static const String appId = 'c2bf944aa30a48bcaad7f1be6694949e';

  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  /// Aktif Agora kanalı (arama ekranındaki uzak video bağlantısı için).
  String? get aktifKanal => _aktifKanal;

  final _db = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> _aramaDoc(String chatId) =>
      _db.collection('aramalar').doc(chatId);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Aktif arama bağlamı (bitirince iptal push'u + temizlik için)
  String? _aktifKarsiUid;
  String? _aktifKanal;

  // ---- GÖRÜŞME OTURUMU ----
  // ⚠️ NEDEN: AramaServisi TEKİL; ekranlar ise görüşme başına. Aynı sohbetten
  // yeni arama kabul edilince (karşı tarafın uygulaması çökmüş, yeniden
  // arıyor) ESKİ AramaEkrani yığında açık kalıyor, aynı chatId'yi dinliyordu;
  // 20 sn'lik yeniden bağlanma sayacı dolunca bitir(chatId) çağırıp YENİ
  // görüşmenin motorunu serbest bırakıyor, 'bitti' yazıp onu da düşürüyordu.
  // chatId bu ikisini ayırt edemez → her aramaBaslat/kabulEt başında artan
  // bir sayaç: ekran açıldığı oturumu saklar, bitir() eski oturuma dokunmaz.
  int _oturum = 0;
  final ValueNotifier<int> _oturumVN = ValueNotifier<int>(0);

  /// Şimdiki görüşme oturumu (her aramaBaslat/kabulEt başında artar).
  int get oturum => _oturum;

  /// Oturum değişimi: açık arama ekranı yeni görüşmenin onu devraldığını
  /// buradan öğrenir ve bitir() ÇAĞIRMADAN kapanır.
  ValueListenable<int> get oturumVN => _oturumVN;

  int _yeniOturum() {
    _oturum++;
    _oturumVN.value = _oturum;
    return _oturum;
  }

  /// "Görüşmedeyim" disk kaydının nabzı (bkz. AktifAramaKaydi.tazelik).
  Timer? _nabiz;

  void _nabziBaslat(String chatId) {
    _nabiz?.cancel();
    _nabiz = Timer.periodic(AktifAramaKaydi.nabizAraligi, (_) {
      AktifAramaKaydi.yaz(chatId);
    });
  }

  void _nabziDurdur() {
    _nabiz?.cancel();
    _nabiz = null;
  }

  // ---- OTOMATİK ARAMA TEŞHİSİ ----
  // Her arama bitişinde özet rapor gönderilir; kullanıcının "Sorun bildir"e
  // basmasına gerek kalmasın diye. En kritik soru: KARŞI TARAF KATILDI MI?
  bool _karsiKatildi = false;
  bool _yerelKatildi = false;
  DateTime? _aramaBaslangic;
  String? _aramaTipi;
  bool _benArayan = false;

  final ValueNotifier<int?> karsiUid = ValueNotifier<int?>(null);
  final ValueNotifier<bool> katildi = ValueNotifier<bool>(false);
  final ValueNotifier<String?> sonHata = ValueNotifier<String?>(null);

  // CallKit ile (kapalıyken) kabul edilip henüz ekranı açılmamış arama.
  String? bekleyenChatId;
  AramaTipi? bekleyenTip;
  String? bekleyenBaslik;

  // Kabul akışı dedupe'u (CallKit onEvent + activeCalls kurtarma aynı aramayı
  // iki kez işlemesin). ⚠️ ZAMAN SINIRLI: akış bir yerde takılırsa bayrak
  // kalıcı kalıp SONRAKİ TÜM aramaları sessizce yok sayıyordu.
  String? _islenenChatId;
  DateTime? _islenenZaman;

  /// Bu arama şu anda (son 15 sn içinde) zaten işleniyor mu?
  bool ayniAramaIsleniyor(String chatId) {
    final t = _islenenZaman;
    if (_islenenChatId != chatId || t == null) return false;
    if (DateTime.now().difference(t).inSeconds >= 15) {
      // Takılı kalmış → yeniden işlenebilsin
      islemeBitti();
      return false;
    }
    return true;
  }

  void islemeBasla(String chatId) {
    _islenenChatId = chatId;
    _islenenZaman = DateTime.now();
  }

  void islemeBitti() {
    _islenenChatId = null;
    _islenenZaman = null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> aramaDinle(String chatId) =>
      _aramaDoc(chatId).snapshots();

  Future<Map<String, dynamic>?> aktifArama(String chatId) async =>
      (await _aramaDoc(chatId).get()).data();

  List<Permission> _izinListesi(AramaTipi tip) => <Permission>[
        Permission.microphone,
        if (tip == AramaTipi.video) Permission.camera,
      ];

  /// İzinler ZATEN verilmiş mi? Sistem diyaloğu AÇMAZ (hızlı yol).
  Future<bool> izinlerVerilmisMi(AramaTipi tip) async {
    for (final p in _izinListesi(tip)) {
      if (!await p.isGranted) return false;
    }
    return true;
  }

  /// İzinleri hazırlar. ⚠️ KRİTİK: izin ZATEN verilmişse diyalog AÇMAZ ve
  /// anında döner. Diyalog açmak gerekiyorsa zaman aşımı konur — çünkü sistem
  /// izin ekranı Flutter aktivitesini duraklatıyor ve dönen Future bazen HİÇ
  /// tamamlanmıyordu; bu yüzden arama kabulü askıda kalıp ekran açılmıyordu.
  /// Zaman aşımından sonra durum tekrar okunur (kullanıcı izni vermiş olabilir).
  Future<bool> izinleriHazirla(AramaTipi tip) async {
    if (await izinlerVerilmisMi(tip)) return true;
    try {
      final sonuc = await _izinListesi(tip)
          .request()
          .timeout(const Duration(seconds: 30));
      if (sonuc.values.every((s) => s.isGranted)) return true;
    } catch (_) {
      // yut: aşağıda gerçek durumu okuyacağız
    }
    return izinlerVerilmisMi(tip);
  }

  Future<void> _engineHazirla(AramaTipi tip) async {
    sonHata.value = null;
    if (_engine != null) {
      // ⚠️ ÖNCE leaveChannel, SONRA release. Eskiden yalnız release() vardı;
      // art arda arama yapılınca eski motor kanaldan ÇIKMADAN yenisi katılmaya
      // çalışıyor ve Agora -17 (ERR_JOIN_CHANNEL_REJECTED / "zaten kanaldasın")
      // fırlatıyordu → kabul başarısız, karşı taraf hiç bağlanmıyordu.
      // (Kanıt: v1.6.6 raporları, [kabulEt] AgoraRtcException(-17) → _katil.)
      try {
        await _engine?.leaveChannel();
      } catch (_) {}
      try {
        await _engine?.release();
      } catch (_) {}
      _engine = null;
      karsiUid.value = null;
      katildi.value = false;
    }
    final e = createAgoraRtcEngine();
    await e.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    e.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        HataServisi.instance.iz('AGORA kanala girildi (${elapsed}ms)');
        _yerelKatildi = true;
        katildi.value = true;
        e.setEnableSpeakerphone(tip == AramaTipi.video).catchError((_) {});
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        HataServisi.instance.iz('AGORA KARSI TARAF KATILDI uid=$remoteUid');
        _karsiKatildi = true;
        karsiUid.value = remoteUid;
      },
      onUserOffline: (connection, remoteUid, reason) {
        HataServisi.instance.iz('AGORA karsi taraf ayrildi ($reason)');
        karsiUid.value = null;
      },
      onError: (err, msg) {
        HataServisi.instance.iz('AGORA HATA $err — $msg');
        debugPrint('Agora HATA: $err — $msg');
        sonHata.value = '$err: $msg';
      },
      onConnectionStateChanged: (connection, state, reason) {
        HataServisi.instance.iz('AGORA baglanti durumu=$state ($reason)');
        if (state == ConnectionStateType.connectionStateFailed) {
          sonHata.value = 'Bağlantı başarısız ($reason)';
        }
      },
    ));
    await e.enableAudio();
    if (tip == AramaTipi.video) {
      await e.enableVideo();
      // ⚠️ startPreview() BURADA ÇAĞRILMIYOR — kamerayı açar.
      // Aranan taraf CallKit'ten kabul ettiğinde uygulama HENÜZ ÖN PLANDA
      // DEĞİL. Android 14+ arka plandan kamera açmayı kısıtlar ve görünür
      // yüzey yokken kamera başlatmak süreci NATIVE olarak çökertiyordu
      // ("uygulama durdu" — Dart hatası oluşmadığı için yakalanamıyordu).
      // Yerel görüntü, kamera track'i yayınlandığında `AgoraVideoView` (uid: 0)
      // tarafından zaten çizilir → ayrı bir önizleme çağrısına GEREK YOK.
    } else {
      await e.disableVideo();
    }
    _engine = e;
  }

  // ⚠️ `startPreview()` HİÇBİR YERDE ÇAĞRILMIYOR — KASITLI, GERİ EKLEME.
  // KANIT (v1.6.3, son_adim adli tıbbı, İKİ cihazda da birebir aynı):
  //   SON ADIM: "EKRAN: kamera onizleme baslatiliyor"
  // İşaret `startPreview()`'den hemen ÖNCE yazılıyordu → süreç tam orada
  // ölüyordu. try/catch yakalamıyor çünkü NATIVE çökme (Dart hatası değil).
  // SEBEP: `joinChannel(publishCameraTrack: true)` kamerayı ZATEN yayına alır;
  // üstüne `startPreview()` kamerayı İKİNCİ kez açmaya çalışıp çökertiyor.

  /// KAMERAYI YAYINA ALIR — yalnızca arama ekranı GÖRÜNÜR olduktan sonra
  /// çağrılmalı (AramaEkrani postFrame).
  ///
  /// Kanala katılırken `publishCameraTrack: false` ile giriyoruz; böylece
  /// ses bağlantısı kamera açılmasını BEKLEMEDEN kuruluyor. Uygulama ön plana
  /// geldikten sonra kamera burada yayına alınır — arka planda kamera açma
  /// yasağına takılmaz. Hata olursa arama DÜŞMEZ (sesli devam eder).
  Future<void> kamerayiYayinaAl() async {
    if (_aramaTipi != 'video') return;
    if (_engine == null) return;
    await HataServisi.instance.sonAdim('EKRAN: kamera yayina aliniyor');
    try {
      await _engine?.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: true,
        autoSubscribeVideo: true,
      ));
      HataServisi.instance.iz('kamera YAYINA ALINDI');
    } catch (e) {
      HataServisi.instance.iz('kamera yayina alinamadi: $e');
    }
  }

  /// Kanal token'ı. ⚠️ Aktarıcı tanımlıysa token SUNUCUDA üretilir: App
  /// Certificate APK'dan çıkarılabildiği için (bkz. gizli.dart) yerel üretim
  /// herkese sınırsız token demekti. Aktarıcı, isteyenin [chatId] çiftinin
  /// üyesi olduğunu doğrulayıp token verir.
  /// Aktarıcı tanımlı DEĞİLSE eski yerel yol aynen çalışır (hiçbir şey kırılmaz).
  /// Aktarıcı tanımlı ama ulaşılamıyorsa yerel yola DÜŞMEYİZ: sertifika
  /// sunucuya taşındığında APK'daki yer tutucuyla üretilen token zaten
  /// reddedilir; kullanıcıya net bir hata göstermek daha iyi.
  Future<String> _tokenAl(String chatId, String kanal) async {
    if (AktariciServisi.etkin) {
      String? token;
      try {
        token = await AktariciServisi.instance
            .agoraTokeni(chatId: chatId, kanal: kanal);
      } catch (e) {
        // Zaman aşımı / ağ / oturum yok → aşağıda tek tip hata.
        HataServisi.instance.iz('AKTARICI agora token hata: $e');
      }
      if (token == null || token.isEmpty) {
        throw AramaHatasi('Arama sunucusuna ulaşılamadı');
      }
      HataServisi.instance.iz('agora token AKTARICIDAN alindi');
      return token;
    }
    return RtcTokenBuilder.build(
      appId: appId,
      appCertificate: agoraSertifika,
      channelName: kanal,
      uid: '0',
      role: RtcRole.publisher,
      expireTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400,
    );
  }

  Future<void> _katil(
    String chatId,
    String kanal,
    String karsiUid_, [
    AramaTipi tip = AramaTipi.ses,
  ]) async {
    // Token bir kez alınır; aşağıdaki -17 yeniden denemesi AYNI token'ı
    // kullanır (aynı kanal + uid 0 → hâlâ geçerli, ikinci ağ isteği gerekmez).
    final token = await _tokenAl(chatId, kanal);
    // ⚠️ Seçenekler AÇIKÇA verilmeli. Boş `ChannelMediaOptions()` ile mikrofon/
    // kamera yayını ve otomatik abonelik SDK varsayılanlarına bırakılıyordu;
    // "karşılıklı bağlanıyor ama SES YOK" tablosunun en olası sebebi buydu.
    await HataServisi.instance.sonAdim('KATIL: joinChannel cagriliyor');
    final secenekler = ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        // ⚠️ KAMERA BURADA YAYINA ALINMAZ (video'da bile false).
        // KANIT (v1.6.6 izleri): görüntülü kabulde akış tam burada ölüyordu:
        //   "KABUL: kanala katiliyor"  → devamı YOK
        // Sesli kabulde ise "kanala katildi" geliyordu. Fark: video'da
        // publishCameraTrack=true → joinChannel KAMERAYI AÇIYOR. Aranan kişi
        // CallKit'ten kabul ettiğinde uygulama HENÜZ ÖN PLANDA DEĞİL; Android
        // arka plandan kamera açmayı engeller → süreç ölüyor/asılıyor.
        // (startPreview çökmesiyle AYNI aile.)
        // Kamera, ekran görünür olunca [kamerayiYayinaAl] ile açılır.
        publishCameraTrack: false,
        autoSubscribeAudio: true,
        // Abone olmak kamerayı AÇMAZ → güvenli, baştan açık kalabilir.
        autoSubscribeVideo: tip == AramaTipi.video,
    );
    try {
      await _engine?.joinChannel(
          token: token, channelId: kanal, uid: 0, options: secenekler);
    } on AgoraRtcException catch (e) {
      // -17 = ERR_JOIN_CHANNEL_REJECTED ("zaten bir kanaldasın").
      // Eski aramadan kalmış olabilir → kanaldan çık ve BİR KEZ daha dene.
      if (e.code != -17) rethrow;
      HataServisi.instance.iz('joinChannel -17 → leaveChannel + tekrar dene');
      try {
        await _engine?.leaveChannel();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _engine?.joinChannel(
          token: token, channelId: kanal, uid: 0, options: secenekler);
    }
    _aktifKarsiUid = karsiUid_;
    _aktifKanal = kanal;
    aktifAramaVar = true;
    // Ön plan meşgul kararı (gelenAramaMesgulMu) aynı sohbeti ayırt edebilsin.
    aktifAramaChatId = chatId;
    // ⚠️ `aktifAramaVar` yalnız BU isolate'te görünür; FCM arka plan
    // handler'ı ayrı isolate'te çalıştığı için orada hep false'tu → kilit
    // ekranındaki görüşmenin üstüne ikinci CallKit açılıyordu. Disk kaydı iki
    // isolate'ten de okunur. `await` KASITLI: beklemeden bırakılırsa hızlı bir
    // bitir() → sil() bu yazmadan ÖNCE bitip kaydı geride bırakabilir ve sonraki
    // aramalar tazelik süresince "meşgul" görünürdü. (Hata yutulur, akışı
    // durdurmaz.) yaz/sil ayrıca AktifAramaKaydi içinde sıralıdır.
    await AktifAramaKaydi.yaz(chatId);
    // Süreç ölürse nabız da durur → kayıt en geç `tazelik` içinde bayatlar.
    _nabziBaslat(chatId);
  }

  /// Agora kanal adı. ⚠️ Eskiden `k_<milisaniye>` idi → TAHMİN EDİLEBİLİR:
  /// App Certificate APK'dan çıkarılabildiği için (bkz. gizli.dart) token
  /// üretebilen biri, arama saatini kabaca bilerek kanal adını deneyip
  /// görüşmeye sessizce katılabilirdi. 128 bit rastgele ad bunu imkânsız kılar
  /// (Agora sınırı 64 karakter; bu 34).
  String _kanalUret() {
    final r = Random.secure();
    final hex = List<String>.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'k_$hex';
  }

  /// ARAYAN: [chatId]'de [alanUid]'i arar. Kanal döner (ekran için).
  Future<String?> aramaBaslat(
      String chatId, String alanUid, AramaTipi tip) async {
    final iz = HataServisi.instance.iz;
    final benim = _yeniOturum();
    iz('ARAMA BASLAT istendi tip=${tip.name} chat=$chatId oturum=$benim');
    if (!await izinleriHazirla(tip)) {
      iz('ARAMA BASLAT iptal: izin YOK');
      await _devralinaniBirak();
      return null;
    }
    iz('izinler tamam');
    _benArayan = true;
    _aramaTipi = tip.name;
    _aramaBaslangic = DateTime.now();
    _karsiKatildi = false;
    _yerelKatildi = false;
    final kanal = _kanalUret();
    try {
      await _engineHazirla(tip);
      iz('engine hazir');
      await _katil(chatId, kanal, alanUid, tip);
      iz('kanala katildi kanal=$kanal');

      final me = _uid;
      final ben = me == null
          ? null
          : await KullaniciServisi.instance.profilGetir(me);
      final ad = ben?.ad ?? 'Arayan';

      await _aramaDoc(chatId).set({
        'arayanUid': me,
        'arayan': ad,
        'tip': tip.name,
        'kanal': kanal,
        'durum': 'cagriliyor',
        'zaman': FieldValue.serverTimestamp(),
      });

      BildirimServisi.instance.hedefeVeriGonder(hedefUid: alanUid, veri: {
        'tur': 'arama',
        'chatId': chatId,
        'arayan': ad,
        'arayanUid': me ?? '',
        'tip': tip.name,
        'kanal': kanal,
      });
      iz('ARAMA BASLAT tamam, push gonderildi');
      return kanal;
    } catch (e, st) {
      iz('ARAMA BASLAT HATA: $e');
      HataServisi.instance.bildir(e, st, etiket: 'aramaBaslat');
      await bitir(chatId, oturum: benim);
      throw AramaHatasi('Arama başlatılamadı: $e');
    }
  }

  /// ARANAN: [chatId]'deki aramayı kabul eder (kanalı Firestore'dan okur).
  Future<bool> kabulEt(String chatId, AramaTipi tip) async {
    final iz = HataServisi.instance.iz;
    // ⚠️ Oturum EN BAŞTA artar: aynı sohbetteki eski ekran (varsa) kabul
    // sürerken sayacı dolup yeni görüşmeyi düşürmeden ÖNCE kapanmalı.
    final benim = _yeniOturum();
    iz('KABUL istendi tip=${tip.name} chat=$chatId oturum=$benim');
    if (!await izinleriHazirla(tip)) {
      iz('KABUL iptal: izin YOK');
      await _devralinaniBirak();
      return false;
    }
    iz('izinler tamam');
    _benArayan = false;
    _aramaTipi = tip.name;
    _aramaBaslangic = DateTime.now();
    _karsiKatildi = false;
    _yerelKatildi = false;
    try {
      final bilgi = await aktifArama(chatId);
      final kanal = bilgi?['kanal'] as String?;
      final karsi = bilgi?['arayanUid'] as String?;
      if (kanal == null) {
        iz('KABUL iptal: firestore kanal YOK');
        await _devralinaniBirak();
        return false;
      }
      iz('arama dokumani okundu kanal=$kanal');
      await HataServisi.instance
          .sonAdim('KABUL: engine hazirlaniyor (tip=${tip.name})');
      await _engineHazirla(tip);
      iz('engine hazir');
      await HataServisi.instance.sonAdim('KABUL: kanala katiliyor');
      await _katil(chatId, kanal, karsi ?? '', tip);
      iz('kanala katildi');
      await HataServisi.instance.sonAdim('KABUL: kanala katildi, ekran aciliyor');
      // ⚠️ Burada endAllCalls() ÇAĞIRMIYORUZ. Kabul anında sisteme "arama
      // bitti" demek, işletim sisteminin arama oturumunu kapatmasına ve
      // uygulamanın ARKA PLANA düşmesine yol açıyordu (kullanıcı kabul edince
      // sohbet listesine dönüyordu). Doğrusu: aramayı BAĞLANDI işaretlemek —
      // CallKit gelen-arama ekranı kapanır, oturum yaşamaya devam eder.
      try {
        await FlutterCallkitIncoming.setCallConnected(chatId);
        iz('callkit setCallConnected');
      } catch (e) {
        iz('setCallConnected hata: $e');
      }
      await _aramaDoc(chatId).set({'durum': 'kabul'}, SetOptions(merge: true));
      iz('KABUL tamam');
      return true;
    } catch (e, st) {
      iz('KABUL HATA: $e');
      HataServisi.instance.bildir(e, st, etiket: 'kabulEt');
      await bitir(chatId, oturum: benim);
      throw AramaHatasi('Aramaya katılınamadı: $e');
    }
  }

  /// Açılışta kalmış (stale) arama kaydını temizler (>90 sn).
  Future<void> eskiAramayiTemizle(String chatId) async {
    try {
      final d = await aktifArama(chatId);
      if (d == null) return;
      final durum = d['durum'];
      if (durum != 'cagriliyor' && durum != 'kabul') return;
      final benimki = d['arayanUid'] == _uid;
      final ts = d['zaman'];
      final eski = ts is! Timestamp ||
          DateTime.now().difference(ts.toDate()).inSeconds.abs() > 90;
      if (benimki || eski) {
        await _aramaDoc(chatId).set({'durum': 'bitti'}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// ARANAN reddeder.
  Future<void> reddet(String chatId) async {
    HataServisi.instance.iz('REDDET chat=$chatId');
    await _aramaDoc(chatId).set({'durum': 'red'}, SetOptions(merge: true));
  }

  /// Aramayı bitirir: önce YEREL temizlik (motor, bayraklar, disk kaydı,
  /// CallKit), sonra uzak işler (iptal push'u, özet rapor) BEKLENMEDEN.
  ///
  /// [oturum] verilmiş ve şimdiki oturum değilse HİÇBİR ŞEYE DOKUNMAZ: o
  /// görüşmeyi yeni bir aramaBaslat/kabulEt devralmıştır (bkz. [oturumVN]).
  ///
  /// ⚠️ NEDEN BU SIRA: Eskiden önce `await` ile özet rapor (hatalar.add) ve
  /// 'bitti' yazması bekleniyordu. Firestore yazma Future'ı SUNUCU ONAYINA
  /// kadar tamamlanmaz → çevrimdışıyken bitir() asılı kalıyordu: ekran donuk
  /// (kapat tuşu işlevsiz), motor serbest bırakılmamış (kamera/mikrofon açık),
  /// meşgul kaydı silinmemiş. Yerel işler ağ beklememeli.
  Future<void> bitir(String chatId, {int? oturum}) async {
    final iz = HataServisi.instance.iz;
    if (!oturumGuncelMi(istenen: oturum, guncel: _oturum)) {
      iz('BITIR atlandi: eski oturum ($oturum, simdiki $_oturum) chat=$chatId');
      return;
    }
    iz('BITIR chat=$chatId oturum=$_oturum');
    // Uzak işlerin verisi alanlar sıfırlanmadan ÖNCE yakalanır.
    final karsi = _aktifKarsiUid;
    final ozet = _aramaOzeti(chatId);
    // 'bitti' yazması HEMEN (eşzamanlı) kuyruğa girer ama BEKLENMEZ.
    // ⚠️ Push'tan sonraya bırakılmaz: push asılı kalırken kullanıcı aynı
    // sohbette yeni arama başlatırsa geç gelen 'bitti' YENİ aramanın
    // 'cagriliyor' yazmasının ÜSTÜNE binerdi. Firestore yerel yazmaları
    // çağrı sırasıyla uygular → şimdi çağırmak sırayı garanti eder.
    try {
      _aramaDoc(chatId)
          .set({'durum': 'bitti'}, SetOptions(merge: true))
          .ignore();
    } catch (_) {}
    await _yerelTemizlik();
    // Uzak işler arka planda; bitir() onları BEKLEMEZ.
    unawaited(_uzakBitir(chatId, karsi, ozet));
  }

  /// Aynı sohbette YENİ bir arama (belgede farklı kanal, bkz.
  /// [aramaDevralindiMi]) [oturum]'un görüşmesini devraldı ama henüz
  /// kabulEt başlamadı: yeni arama bu cihazda ÇALIYOR olabilir.
  ///
  /// Yalnız YEREL temizlik: eski motor bırakılır (mikrofon/kamera açık
  /// kalmasın; yeni arama reddedilirse kimse kapatmazdı), "görüşmedeyim"
  /// bayrakları/kaydı kalkar (yoksa sonraki aramalar "meşgul" alırdı).
  /// ⚠️ YAPILMAYANLAR (hepsi YENİ aramayı düşürürdü): 'bitti' yazmak (belge
  /// sohbetin ORTAK belgesi, yeni 'cagriliyor'un üstüne biner), karşı tarafa
  /// arama_iptal push'u, endAllCalls (CallKit id = chatId: eski görüşmenin
  /// kaydı ile çalan yeni arama AYNI id → yalnız eskisini kapatmak mümkün
  /// değil; o kaydı yeni aramanın kabul/red/zaman aşımı zaten sonlandırır).
  ///
  /// Oturum artık güncel değilse (kabulEt/aramaBaslat başladı) hiçbir şeye
  /// dokunmaz: eski motoru onların `_engineHazirla`'sı kapatır.
  Future<void> devredildi(String chatId, {required int oturum}) async {
    final iz = HataServisi.instance.iz;
    if (!oturumGuncelMi(istenen: oturum, guncel: _oturum)) {
      iz('DEVREDILDI atlandi: oturum zaten yeni ($oturum → $_oturum)');
      return;
    }
    iz('DEVREDILDI chat=$chatId oturum=$_oturum: yalniz yerel temizlik');
    // Özet rapor yine gider (teşhis değerli); iptal push'u YOK (karsi: null).
    final ozet = _aramaOzeti(chatId);
    await _yerelTemizlik(callkitKapat: false);
    unawaited(_uzakBitir(chatId, null, ozet));
  }

  /// Yeni oturum ESKİ bir görüşmeyi devraldı ama motor kurulmadan vazgeçti
  /// (izin yok / kanal yok). Eski ekran oturum değişince bitir() çağırmadan
  /// kapandığı için eski motor sahipsiz kalırdı → yalnız yerel temizlik.
  /// ('bitti'/iptal push'u YOK: aynı sohbetin yeni aramasını düşürürdü.)
  Future<void> _devralinaniBirak() async {
    if (_engine == null && !aktifAramaVar) return;
    HataServisi.instance.iz('devralinan eski gorusme birakiliyor');
    _aramaBaslangic = null;
    await _yerelTemizlik();
  }

  /// Ağ beklemeyen temizlik. ⚠️ İlk `await`'e kadar olan kısım EŞZAMANLI:
  /// bayraklar sıfırlanır ve disk silmesi kuyruğa alınır; araya yeni bir
  /// kabulEt girse bile onun motorunu/kaydını EZMEZ (motor yerelde tutulur,
  /// yaz/sil AktifAramaKaydi'nda sıralı).
  /// [callkitKapat] false: aynı chatId'li yeni arama çalıyor (bkz. [devredildi]).
  Future<void> _yerelTemizlik({bool callkitKapat = true}) async {
    _nabziDurdur();
    final motor = _engine;
    _engine = null;
    _aktifKarsiUid = null;
    _aktifKanal = null;
    aktifAramaVar = false;
    aktifAramaChatId = null;
    karsiUid.value = null;
    katildi.value = false;
    bekleyenChatId = null;
    bekleyenTip = null;
    bekleyenBaslik = null;
    // Sonraki aramanın işlenebilmesi için dedupe bayrağını SIFIRLA.
    islemeBitti();
    // İsolate'ler arası "görüşmedeyim" kaydı da kalkmalı; kalırsa arka plan
    // handler'ı yeni aramaları (tazelik süresi dolana dek) "meşgul" sayar.
    final silme = AktifAramaKaydi.sil();
    if (callkitKapat) {
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
    }
    // ⚠️ AYRI try blokları: eskiden ikisi AYNI try'daydı; `leaveChannel` hata
    // verirse `release()` HİÇ çağrılmıyordu → motor sızıyor, KAMERA ve
    // MİKROFON açık kalabiliyordu (pil + gizlilik sorunu).
    // `release()` her hâlükârda çalışmalı.
    try {
      await motor?.leaveChannel();
    } catch (e) {
      HataServisi.instance.iz('leaveChannel hata: $e');
    }
    try {
      await motor?.release();
    } catch (e) {
      HataServisi.instance.iz('release hata: $e');
    }
    await silme;
  }

  /// Karşı tarafın zilini sustur (iptal push'u) + özet rapor. Beklenmez;
  /// her biri zaman aşımlı ki çevrimdışıyken askıda Future birikmesin.
  Future<void> _uzakBitir(
      String chatId, String? karsi, List<String>? ozet) async {
    const sinir = Duration(seconds: 20);
    try {
      if (karsi != null && karsi.isNotEmpty) {
        await BildirimServisi.instance.hedefeVeriGonder(hedefUid: karsi, veri: {
          'tur': 'arama_iptal',
          'chatId': chatId,
        }).timeout(sinir);
      }
    } catch (_) {}
    if (ozet == null) return;
    try {
      await HataServisi.instance
          .arkaplanRapor('ARAMA OZETI (otomatik)', ozet)
          .timeout(sinir);
    } catch (_) {}
  }

  /// Arama bitince OTOMATİK özet raporu (kullanıcı bir şeye basmak zorunda
  /// kalmasın). En kritik bilgi: karşı taraf Agora kanalına KATILDI MI?
  /// Katılmadıysa medya hiç kurulmamıştır → "ses yok / bağlanmıyor" budur.
  /// ⚠️ EŞZAMANLI: satırlar alanlar sıfırlanmadan ÖNCE yakalanır; gönderim
  /// ([_uzakBitir]) sonra ve beklenmeden yapılır. Bu turda arama yoksa null.
  List<String>? _aramaOzeti(String chatId) {
    final baslangic = _aramaBaslangic;
    if (baslangic == null) return null; // bu turda arama olmadı
    final sn = DateTime.now().difference(baslangic).inSeconds;
    _aramaBaslangic = null;
    return <String>[
      'rol=${_benArayan ? "ARAYAN" : "ARANAN"} tip=$_aramaTipi',
      'chatId=$chatId kanal=$_aktifKanal oturum=$_oturum',
      'YEREL kanala katildi = $_yerelKatildi',
      'KARSI TARAF katildi   = $_karsiKatildi'
          '${_karsiKatildi ? "" : "  <-- MEDYA KURULMADI"}',
      'sure=${sn}sn',
      'agoraSonHata=${sonHata.value ?? "-"}',
      ...HataServisi.instance.sonIzler(25),
    ];
  }

  // ---- Arama içi kontroller ----
  Future<void> mikrofonKapat(bool kapali) async =>
      _engine?.muteLocalAudioStream(kapali);
  Future<void> kameraKapat(bool kapali) async =>
      _engine?.muteLocalVideoStream(kapali);
  Future<void> kameraDegistir() async => _engine?.switchCamera();
  Future<void> hoparlor(bool acik) async =>
      _engine?.setEnableSpeakerphone(acik);
}
