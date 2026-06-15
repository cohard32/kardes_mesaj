import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bildirim_servisi.dart';

enum AramaTipi { video, ses }

AramaTipi aramaTipiCoz(String? s) =>
    s == 'video' ? AramaTipi.video : AramaTipi.ses;

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
    final e = createAgoraRtcEngine();
    await e.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    e.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) => katildi.value = true,
      onUserJoined: (connection, remoteUid, elapsed) =>
          karsiUid.value = remoteUid,
      onUserOffline: (connection, remoteUid, reason) => karsiUid.value = null,
    ));

    await e.enableAudio();
    if (tip == AramaTipi.video) {
      await e.enableVideo();
      await e.startPreview();
    } else {
      await e.disableVideo();
    }
    await e.setEnableSpeakerphone(tip == AramaTipi.video);
    _engine = e;
  }

  Future<void> _katil(String kanal) async {
    await _engine?.joinChannel(
      token: '',
      channelId: kanal,
      uid: 0,
      options: const ChannelMediaOptions(),
    );
  }

  String _kanalUret() => 'k_${DateTime.now().millisecondsSinceEpoch}';

  /// ARAYAN: arama başlatır. İzin yoksa null, başlarsa katılınan kanalı döner.
  Future<String?> aramaBaslat(AramaTipi tip) async {
    if (!await _izinIste(tip)) return null;
    final kanal = _kanalUret();
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
  }

  /// ARANAN: gelen aramayı kabul eder ve aynı kanala katılır.
  Future<bool> kabulEt(String kanal, AramaTipi tip) async {
    if (!await _izinIste(tip)) return false;
    await _engineHazirla(tip);
    await _katil(kanal);
    await _aramaDoc.set({'durum': 'kabul'}, SetOptions(merge: true));
    return true;
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
