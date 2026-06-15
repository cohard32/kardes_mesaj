import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'ayar_servisi.dart';

/// Arka plan / uygulama kapalı mesaj handler'ı.
/// Top-level (sınıf dışı) olmak ZORUNDA — Android arka planda izole çalıştırır.
/// Normal mesaj `notification` payload'ı sistem tepsisinde otomatik gösterilir.
/// Çağrı (data: tur=arama) gelirse uygulama KAPALI olsa bile tam ekran
/// gelen-arama ekranını (CallKit) gösterir.
@pragma('vm:entry-point')
Future<void> arkaplanMesajHandler(RemoteMessage message) async {
  if (message.data['tur'] == 'arama') {
    await gelenAramayiGoster(message.data);
  }
}

/// FCM çağrı verisinden tam ekran "gelen arama" bildirimini gösterir.
/// Hem arka plan handler'ı hem de uygulama açıkken kullanılır.
Future<void> gelenAramayiGoster(Map<String, dynamic> data) async {
  final kanal = (data['kanal'] ?? 'arama').toString();
  final arayan = (data['arayan'] ?? 'Kardeş').toString();
  final video = data['tip'] == 'video';
  final params = CallKitParams(
    id: kanal,
    nameCaller: arayan,
    appName: 'Kardeş Mesaj',
    handle: video ? 'Görüntülü arama' : 'Sesli arama',
    type: video ? 1 : 0,
    extra: <String, dynamic>{'kanal': kanal, 'tip': data['tip']},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      isShowCallID: false,
      ringtonePath: 'system_ringtone_default',
      textAccept: 'Kabul Et',
      textDecline: 'Reddet',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

/// Kartsız (Spark planı) bildirim servisi.
/// Mesaj atılınca gönderen cihaz, FCM HTTP v1 API'ye doğrudan istek atıp
/// karşı cihaza push gönderir. Cloud Functions / Blaze GEREKMEZ.
class BildirimServisi {
  BildirimServisi._();
  static final BildirimServisi instance = BildirimServisi._();

  // AndroidManifest'teki default_notification_channel_id ile AYNI olmalı.
  static const String _kanalId = 'kardes_mesaj_kanal';
  static const String _kanalAdi = 'Kardeş Mesaj Bildirimleri';

  final FirebaseMessaging _mesajlasma = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _yerel =
      FlutterLocalNotificationsPlugin();
  final CollectionReference<Map<String, dynamic>> _kullanicilar =
      FirebaseFirestore.instance.collection('kullanicilar');

  bool _kuruldu = false;

  /// Uygulama açılışında bir kez çağrılır (main.dart, Firebase init sonrası).
  /// İzin ister, yerel bildirim kanalını kurar, foreground dinleyicisini açar.
  Future<void> baslat() async {
    if (_kuruldu) return;
    _kuruldu = true;

    // 1) Bildirim izni (Android 13+ runtime izni)
    await _mesajlasma.requestPermission(alert: true, badge: true, sound: true);

    // 2) Yerel bildirim eklentisi + kanal (foreground'da göstermek için)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _yerel.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    const kanal = AndroidNotificationChannel(
      _kanalId,
      _kanalAdi,
      description: 'Yeni mesaj bildirimleri',
      importance: Importance.high,
    );
    await _yerel
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(kanal);

    // 3) Uygulama AÇIKKEN gelen mesajı elle göster (foreground'da sistem
    //    otomatik göstermez)
    FirebaseMessaging.onMessage.listen(_foregroundGoster);
  }

  void _foregroundGoster(RemoteMessage message) {
    final bildirim = message.notification;
    if (bildirim == null) return;

    // Kullanıcı ayarlarını uygula
    final ayar = AyarServisi.instance;
    if (!ayar.bildirimAcik.value) return; // bildirim kapalıysa gösterme

    _yerel.show(
      id: bildirim.hashCode,
      title: bildirim.title,
      body: bildirim.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kanalId,
          _kanalAdi,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: !ayar.sessizMi,
          enableVibration: ayar.titresimAcik.value,
        ),
      ),
    );
  }

  /// Giriş yapan kullanıcının FCM token'ını Firestore'a yazar.
  /// `kullanicilar/{uid}` dokümanına kaydeder. Token yenilenince günceller.
  Future<void> tokenKaydet() async {
    final kullanici = FirebaseAuth.instance.currentUser;
    if (kullanici == null) return;

    final token = await _mesajlasma.getToken();
    if (token != null) {
      await _kullanicilar.doc(kullanici.uid).set({
        'fcmToken': token,
        'eposta': kullanici.email,
        'guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Token zamanla yenilenebilir — değişince güncelle
    _mesajlasma.onTokenRefresh.listen((yeniToken) {
      _kullanicilar.doc(kullanici.uid).set(
        {'fcmToken': yeniToken},
        SetOptions(merge: true),
      );
    });
  }

  /// Karşı tarafa (iki kişilik: benim dışımdaki kullanıcı) bildirim gönderir.
  /// FCM HTTP v1 API + service account OAuth2. Hata olursa sessizce geçer
  /// (mesaj zaten Firestore'a yazıldı, bildirim ikincil).
  Future<void> karsiTarafaBildirimGonder({
    required String baslik,
    required String govde,
  }) async {
    await _push(mesajAlanlari: {
      'notification': {'title': baslik, 'body': govde},
      'android': {
        'priority': 'high',
        'notification': {'channel_id': _kanalId},
      },
    });
  }

  /// Karşı tarafa GELEN ARAMA push'u (data-only, yüksek öncelikli).
  /// Uygulama kapalıyken arka plan handler bunu yakalayıp CallKit gösterir.
  Future<void> karsiTarafaAramaGonder({
    required String arayan,
    required String tip,
    required String kanal,
  }) async {
    await _push(mesajAlanlari: {
      'data': {
        'tur': 'arama',
        'arayan': arayan,
        'tip': tip,
        'kanal': kanal,
      },
      'android': {'priority': 'high'},
    });
  }

  /// FCM HTTP v1 ortak gönderim: karşı tarafın token'ını bulur, service account
  /// ile OAuth2 alır, [mesajAlanlari]'nı `message` gövdesine ekleyip yollar.
  Future<void> _push({required Map<String, dynamic> mesajAlanlari}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Karşı tarafın token'ını bul
      final snap = await _kullanicilar.get();
      String? hedefToken;
      for (final doc in snap.docs) {
        if (doc.id != uid) {
          hedefToken = doc.data()['fcmToken'] as String?;
          if (hedefToken != null) break;
        }
      }
      if (hedefToken == null) return;

      // Service account ile OAuth2 erişim token'ı al
      final saJson =
          await rootBundle.loadString('assets/service_account.json');
      final saMap = jsonDecode(saJson) as Map<String, dynamic>;
      final projectId = saMap['project_id'] as String?;
      if (projectId == null) return; // placeholder dosya → henüz hazır değil

      final credentials = ServiceAccountCredentials.fromJson(saMap);
      final client = await clientViaServiceAccount(
        credentials,
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );

      try {
        final url = Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
        );
        final yanit = await client.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': {'token': hedefToken, ...mesajAlanlari},
          }),
        );
        if (yanit.statusCode != 200) {
          debugPrint('FCM gönderim hatası ${yanit.statusCode}: ${yanit.body}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Bildirim gönderilemedi: $e');
    }
  }
}
