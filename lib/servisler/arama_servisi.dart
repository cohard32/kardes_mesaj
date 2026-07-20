import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_service/agora_token_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gizli.dart'; // agoraSertifika (.gitignore'da)
import 'bildirim_servisi.dart';
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
        katildi.value = true;
        e.setEnableSpeakerphone(tip == AramaTipi.video).catchError((_) {});
      },
      onUserJoined: (connection, remoteUid, elapsed) =>
          karsiUid.value = remoteUid,
      onUserOffline: (connection, remoteUid, reason) => karsiUid.value = null,
      onError: (err, msg) {
        debugPrint('Agora HATA: $err — $msg');
        sonHata.value = '$err: $msg';
      },
      onConnectionStateChanged: (connection, state, reason) {
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

  Future<void> _katil(String kanal, String karsiUid_) async {
    final token = RtcTokenBuilder.build(
      appId: appId,
      appCertificate: agoraSertifika,
      channelName: kanal,
      uid: '0',
      role: RtcRole.publisher,
      expireTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400,
    );
    await _engine?.joinChannel(
      token: token,
      channelId: kanal,
      uid: 0,
      options: const ChannelMediaOptions(),
    );
    _aktifKarsiUid = karsiUid_;
    _aktifKanal = kanal;
    aktifAramaVar = true;
  }

  String _kanalUret() => 'k_${DateTime.now().millisecondsSinceEpoch}';

  /// ARAYAN: [chatId]'de [alanUid]'i arar. Kanal döner (ekran için).
  Future<String?> aramaBaslat(
      String chatId, String alanUid, AramaTipi tip) async {
    if (!await izinleriHazirla(tip)) return null;
    final kanal = _kanalUret();
    try {
      await _engineHazirla(tip);
      await _katil(kanal, alanUid);

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
      return kanal;
    } catch (e) {
      await bitir(chatId);
      throw AramaHatasi('Arama başlatılamadı: $e');
    }
  }

  /// ARANAN: [chatId]'deki aramayı kabul eder (kanalı Firestore'dan okur).
  Future<bool> kabulEt(String chatId, AramaTipi tip) async {
    if (!await izinleriHazirla(tip)) return false;
    try {
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
      final bilgi = await aktifArama(chatId);
      final kanal = bilgi?['kanal'] as String?;
      final karsi = bilgi?['arayanUid'] as String?;
      if (kanal == null) return false;
      await _engineHazirla(tip);
      await _katil(kanal, karsi ?? '');
      await _aramaDoc(chatId).set({'durum': 'kabul'}, SetOptions(merge: true));
      return true;
    } catch (e) {
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
    await _aramaDoc(chatId).set({'durum': 'red'}, SetOptions(merge: true));
  }

  /// Aramayı bitirir: karşı tarafın zilini sustur + Firestore + Agora temizle.
  Future<void> bitir(String chatId) async {
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
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) {}
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

  // ---- Arama içi kontroller ----
  Future<void> mikrofonKapat(bool kapali) async =>
      _engine?.muteLocalAudioStream(kapali);
  Future<void> kameraKapat(bool kapali) async =>
      _engine?.muteLocalVideoStream(kapali);
  Future<void> kameraDegistir() async => _engine?.switchCamera();
  Future<void> hoparlor(bool acik) async =>
      _engine?.setEnableSpeakerphone(acik);
}
