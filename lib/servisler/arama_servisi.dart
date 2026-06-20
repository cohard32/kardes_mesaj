import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_service/agora_token_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gizli.dart'; // agoraSertifika (.gitignore'da)
import 'bildirim_servisi.dart';

enum AramaTipi { video, ses }

AramaTipi aramaTipiCoz(String? s) =>
    s == 'video' ? AramaTipi.video : AramaTipi.ses;

/// Arama başlatma/katılma sırasında oluşan, kullanıcıya gösterilecek hata.
class AramaHatasi implements Exception {
  final String mesaj;
  AramaHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Görüntülü/sesli arama servisi — Agora (medya) + Firestore (sinyalleşme).
///
/// KARTSIZ: Agora "testing mode" (App Certificate kapalı) → token gerekmez,
/// `token: ''` ile katılınır. App ID istemci kimliğidir, gizli değildir.
/// İki kişilik tek aktif arama olduğu için sinyalleşme tek Firestore
/// dokümanında tutulur: `aramalar/aktif`.
class AramaServisi {
  AramaServisi._();
  static final AramaServisi instance = AramaServisi._();

  /// Agora App ID (console.agora.io → proje → Testing mode).
  static const String appId = 'c2bf944aa30a48bcaad7f1be6694949e';

  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  final DocumentReference<Map<String, dynamic>> _aramaDoc =
      FirebaseFirestore.instance.collection('aramalar').doc('aktif');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Karşı tarafın (uzak) Agora uid'i — katılınca dolar, ayrılınca boşalır.
  final ValueNotifier<int?> karsiUid = ValueNotifier<int?>(null);

  /// Kanala başarıyla katıldım mı (yerel önizleme/medya hazır).
  final ValueNotifier<bool> katildi = ValueNotifier<bool>(false);

  /// Son Agora hatası (bağlantı/token/sertifika vb.) — UI'da göstermek için.
  final ValueNotifier<String?> sonHata = ValueNotifier<String?>(null);

  Stream<DocumentSnapshot<Map<String, dynamic>>> aramaDinle() =>
      _aramaDoc.snapshots();

  /// Aktif arama bilgisini (kanal, tip, durum...) bir kez okur.
  /// CallKit'ten kabul edilince kanal/tip'i öğrenmek için kullanılır.
  Future<Map<String, dynamic>?> aktifArama() async {
    final doc = await _aramaDoc.get();
    return doc.data();
  }

  Future<bool> _izinIste(AramaTipi tip) async {
    final izinler = <Permission>[
      Permission.microphone,
      if (tip == AramaTipi.video) Permission.camera,
    ];
    final sonuc = await izinler.request();
    return sonuc.values.every((s) => s.isGranted);
  }

  Future<void> _engineHazirla(AramaTipi tip) async {
    sonHata.value = null;
    // Önceki motor kalmışsa (yarım kalan/çift tıklama) önce temizle —
    // iki RtcEngine aynı anda olursa Agora hata verir.
    if (_engine != null) {
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
        debugPrint('Agora: kanala katıldım → ${connection.channelId}');
        katildi.value = true;
        // Hoparlör yönlendirmesi ANCAK kanala katıldıktan sonra ayarlanabilir;
        // önce çağrılırsa ERR_NOT_READY (-3) verir. Hata olursa yok say.
        e.setEnableSpeakerphone(tip == AramaTipi.video).catchError((_) {});
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('Agora: karşı taraf katıldı → uid=$remoteUid');
        karsiUid.value = remoteUid;
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('Agora: karşı taraf ayrıldı → $reason');
        karsiUid.value = null;
      },
      onError: (err, msg) {
        debugPrint('Agora HATA: $err — $msg');
        // Token/sertifika hatası (en olası kök neden) burada görünür.
        sonHata.value = '$err: $msg';
      },
      onConnectionStateChanged: (connection, state, reason) {
        debugPrint('Agora bağlantı durumu: $state ($reason)');
        if (state == ConnectionStateType.connectionStateFailed) {
          sonHata.value = 'Bağlantı başarısız ($reason)';
        }
      },
    ));

    await e.enableAudio();
    if (tip == AramaTipi.video) {
      await e.enableVideo();
      await e.startPreview();
    } else {
      await e.disableVideo();
    }
    _engine = e;
  }

  Future<void> _katil(String kanal) async {
    // Projede App Certificate açık → token ZORUNLU. Token'ı uygulama içinde
    // üretiyoruz (kartsız, backend yok). uid '0' = herhangi bir uid'e izin verir.
    final token = RtcTokenBuilder.build(
      appId: appId,
      appCertificate: agoraSertifika,
      channelName: kanal,
      uid: '0',
      role: RtcRole.publisher,
      expireTimestamp:
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400, // 24 saat
    );
    await _engine?.joinChannel(
      token: token,
      channelId: kanal,
      uid: 0,
      options: const ChannelMediaOptions(),
    );
  }

  String _kanalUret() => 'k_${DateTime.now().millisecondsSinceEpoch}';

  /// ARAYAN: arama başlatır. İzin yoksa null, başlarsa katılınan kanalı döner.
  /// Agora/Firestore hatası olursa temizleyip [AramaHatasi] fırlatır.
  Future<String?> aramaBaslat(AramaTipi tip) async {
    if (!await _izinIste(tip)) return null;
    final kanal = _kanalUret();
    try {
      await _engineHazirla(tip);
      await _katil(kanal);

      final eposta = FirebaseAuth.instance.currentUser?.email ?? 'Kardeş';
      await _aramaDoc.set({
        'arayan': _uid,
        'arayanEposta': eposta,
        'tip': tip.name,
        'kanal': kanal,
        'durum': 'cagriliyor',
        'zaman': FieldValue.serverTimestamp(),
      });

      // Karşı tarafı çaldır (uygulama kapalıyken bile → CallKit)
      BildirimServisi.instance.karsiTarafaAramaGonder(
        arayan: eposta,
        tip: tip.name,
        kanal: kanal,
      );
      return kanal;
    } catch (e) {
      await bitir(); // motoru ve yarım kalan Firestore dokümanını temizle
      throw AramaHatasi('Arama başlatılamadı: $e');
    }
  }

  /// ARANAN: gelen aramayı kabul eder ve aynı kanala katılır.
  Future<bool> kabulEt(String kanal, AramaTipi tip) async {
    if (!await _izinIste(tip)) return false;
    try {
      await _engineHazirla(tip);
      await _katil(kanal);
      await _aramaDoc.set({'durum': 'kabul'}, SetOptions(merge: true));
      return true;
    } catch (e) {
      await bitir();
      throw AramaHatasi('Aramaya katılınamadı: $e');
    }
  }

  /// Açılışta kalmış (stale) arama dokümanını temizler. Eski bir 'cagriliyor'
  /// kaydı, gelen-arama ekranının durmadan açılmasına/siyah ekran titremesine
  /// yol açabilir; 90 sn'den eski kayıtları 'bitti' yapar.
  Future<void> eskiAramayiTemizle() async {
    try {
      final d = await aktifArama();
      if (d == null) return;
      final durum = d['durum'];
      if (durum != 'cagriliyor' && durum != 'kabul') return;
      final benimki = d['arayan'] == _uid; // kendi yarım kalan aramam
      final ts = d['zaman'];
      final eski = ts is! Timestamp ||
          DateTime.now().difference(ts.toDate()).inSeconds.abs() > 90;
      // Kendi yarım kalan aramam VEYA 90 sn'den eski herhangi bir arama → temizle.
      if (benimki || eski) {
        await _aramaDoc.set({'durum': 'bitti'}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// ARANAN: gelen aramayı reddeder.
  Future<void> reddet() async {
    await _aramaDoc.set({'durum': 'red'}, SetOptions(merge: true));
  }

  /// Aramayı bitirir: Firestore'u günceller + Agora'dan ayrılır + motoru bırakır.
  Future<void> bitir() async {
    try {
      await _aramaDoc.set({'durum': 'bitti'}, SetOptions(merge: true));
    } catch (_) {}
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) {}
    _engine = null;
    karsiUid.value = null;
    katildi.value = false;
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
