import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_service/agora_token_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gizli.dart'; // agoraSertifika (.gitignore'da)
import 'bildirim_servisi.dart';
import 'hata_servisi.dart';
import 'kullanici_servisi.dart';

enum AramaTipi { video, ses }

AramaTipi aramaTipiCoz(String? s) =>
    s == 'video' ? AramaTipi.video : AramaTipi.ses;

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

  Future<void> _katil(
    String kanal,
    String karsiUid_, [
    AramaTipi tip = AramaTipi.ses,
  ]) async {
    final token = RtcTokenBuilder.build(
      appId: appId,
      appCertificate: agoraSertifika,
      channelName: kanal,
      uid: '0',
      role: RtcRole.publisher,
      expireTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400,
    );
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
  }

  String _kanalUret() => 'k_${DateTime.now().millisecondsSinceEpoch}';

  /// ARAYAN: [chatId]'de [alanUid]'i arar. Kanal döner (ekran için).
  Future<String?> aramaBaslat(
      String chatId, String alanUid, AramaTipi tip) async {
    final iz = HataServisi.instance.iz;
    iz('ARAMA BASLAT istendi tip=${tip.name} chat=$chatId');
    if (!await izinleriHazirla(tip)) {
      iz('ARAMA BASLAT iptal: izin YOK');
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
      await _katil(kanal, alanUid, tip);
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
      await bitir(chatId);
      throw AramaHatasi('Arama başlatılamadı: $e');
    }
  }

  /// ARANAN: [chatId]'deki aramayı kabul eder (kanalı Firestore'dan okur).
  Future<bool> kabulEt(String chatId, AramaTipi tip) async {
    final iz = HataServisi.instance.iz;
    iz('KABUL istendi tip=${tip.name} chat=$chatId');
    if (!await izinleriHazirla(tip)) {
      iz('KABUL iptal: izin YOK');
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
        return false;
      }
      iz('arama dokumani okundu kanal=$kanal');
      await HataServisi.instance
          .sonAdim('KABUL: engine hazirlaniyor (tip=${tip.name})');
      await _engineHazirla(tip);
      iz('engine hazir');
      await HataServisi.instance.sonAdim('KABUL: kanala katiliyor');
      await _katil(kanal, karsi ?? '', tip);
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
      await bitir(chatId);
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

  /// Aramayı bitirir: karşı tarafın zilini sustur + Firestore + Agora temizle.
  Future<void> bitir(String chatId) async {
    HataServisi.instance.iz('BITIR chat=$chatId');
    await _aramaOzetiBildir(chatId); // alanlar sıfırlanmadan ÖNCE
    // 1) Karşı tarafın zilini sustur (iptal push).
    try {
      final karsi = _aktifKarsiUid;
      if (karsi != null && karsi.isNotEmpty) {
        await BildirimServisi.instance
            .hedefeVeriGonder(hedefUid: karsi, veri: {
          'tur': 'arama_iptal',
          'chatId': chatId,
        });
      }
    } catch (_) {}
    try {
      await _aramaDoc(chatId).set({'durum': 'bitti'}, SetOptions(merge: true));
    } catch (_) {}
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
    // ⚠️ AYRI try blokları: eskiden ikisi AYNI try'daydı; `leaveChannel` hata
    // verirse `release()` HİÇ çağrılmıyordu → motor sızıyor, KAMERA ve
    // MİKROFON açık kalabiliyordu (pil + gizlilik sorunu).
    // `release()` her hâlükârda çalışmalı.
    try {
      await _engine?.leaveChannel();
    } catch (e) {
      HataServisi.instance.iz('leaveChannel hata: $e');
    }
    try {
      await _engine?.release();
    } catch (e) {
      HataServisi.instance.iz('release hata: $e');
    }
    _engine = null;
    _aktifKarsiUid = null;
    _aktifKanal = null;
    aktifAramaVar = false;
    karsiUid.value = null;
    katildi.value = false;
    bekleyenChatId = null;
    bekleyenTip = null;
    bekleyenBaslik = null;
    // Sonraki aramanın işlenebilmesi için dedupe bayrağını SIFIRLA.
    islemeBitti();
  }

  /// Arama bitince OTOMATİK özet raporu (kullanıcı bir şeye basmak zorunda
  /// kalmasın). En kritik bilgi: karşı taraf Agora kanalına KATILDI MI?
  /// Katılmadıysa medya hiç kurulmamıştır → "ses yok / bağlanmıyor" budur.
  Future<void> _aramaOzetiBildir(String chatId) async {
    if (_aramaBaslangic == null) return; // bu turda arama olmadı
    final sn = DateTime.now().difference(_aramaBaslangic!).inSeconds;
    _aramaBaslangic = null;
    try {
      await HataServisi.instance.arkaplanRapor(
        'ARAMA OZETI (otomatik)',
        <String>[
          'rol=${_benArayan ? "ARAYAN" : "ARANAN"} tip=$_aramaTipi',
          'chatId=$chatId kanal=$_aktifKanal',
          'YEREL kanala katildi = $_yerelKatildi',
          'KARSI TARAF katildi   = $_karsiKatildi'
              '${_karsiKatildi ? "" : "  <-- MEDYA KURULMADI"}',
          'sure=${sn}sn',
          'agoraSonHata=${sonHata.value ?? "-"}',
          ...HataServisi.instance.sonIzler(25),
        ],
      );
    } catch (_) {}
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
