import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'ayar_servisi.dart';

/// Arka plan / uygulama kapalı mesaj handler'ı.
/// Top-level (sınıf dışı) olmak ZORUNDA — Android arka planda izole çalıştırır.
/// `notification` payload'lu mesajlar sistem tepsisinde otomatik gösterildiği
/// için burada ekstra iş yapmaya gerek yok.
@pragma('vm:entry-point')
Future<void> arkaplanMesajHandler(RemoteMessage message) async {
  // Bilinçli olarak boş: notification payload'ı sistem tarafından gösterilir.
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
            'message': {
              'token': hedefToken,
              'notification': {'title': baslik, 'body': govde},
              'android': {
                'priority': 'high',
                'notification': {'channel_id': _kanalId},
              },
            },
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
