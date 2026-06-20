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
      isImportant: true,
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

  // AndroidManifest default_notification_channel_id = _kanalVarsayilan.
  // Android 8+'da bildirim sesi KANALA kilitlidir → her ses için ayrı kanal.
  // ⚠️ Kanalın sesi sonradan DEĞİŞTİRİLEMEZ. Ses çalmıyorsa kilitli eski
  // kanal sebebidir → _kanalVer'i artır (yeni id'ler TAZE oluşur, ses gelir).
  static const String _kanalVer = 'v2';
  static const String _kanalVarsayilan = 'kardes_mesaj_kanal';

  // Eski (kilitli/sessiz kalmış olabilecek) kanallar — açılışta silinir.
  static const List<String> _eskiKanallar = [
    'kardes_mesaj_kanal_sessiz',
    'kardes_mesaj_kanal_kedi',
    'kardes_mesaj_kanal_cingirak',
    'kardes_mesaj_kanal_ozel',
  ];

  // Kedi sesleri: seçim anahtarı → gösterim adı (raw kaynak adı = anahtarın aynısı)
  static const Map<String, String> _kediSesleri = {
    'kedi': 'Yavru Kedi 1 🐱',
    'kedi2': 'Yavru Kedi 2 😻',
    'kedi3': 'Yavru Kedi 3 🐈',
    'kedi4': 'Yavru Kedi 4 🐾',
  };

  String _kanalIdFor(String secim) =>
      secim == 'varsayilan' ? _kanalVarsayilan : 'km_${_kanalVer}_$secim';

  /// Seçili sese göre aktif bildirim kanalı id'si.
  String get aktifKanalId =>
      _kanalIdFor(AyarServisi.instance.bildirimSesi.value);

  /// Seçili sesin AndroidNotificationSound karşılığı (Android <8 + detayda).
  AndroidNotificationSound? _sesFor(String secim) {
    if (_kediSesleri.containsKey(secim)) {
      return RawResourceAndroidNotificationSound(secim);
    }
    if (secim == 'cingirak') {
      return const RawResourceAndroidNotificationSound('cingirak');
    }
    if (secim == 'ozel') {
      final u = AyarServisi.instance.ozelSesUri.value;
      return (u == null || u.isEmpty) ? null : UriAndroidNotificationSound(u);
    }
    return null; // varsayilan (sistem) / sessiz
  }

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

    await _kanallariKur();

    // 3) Uygulama AÇIKKEN gelen mesajı elle göster (foreground'da sistem
    //    otomatik göstermez)
    FirebaseMessaging.onMessage.listen(_foregroundGoster);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _yerel.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Tüm ses kanallarını oluşturur. Önce eski/kilitli kanalları siler,
  /// sonra her sesi TAZE kanalda (doğru sesle) kurar.
  Future<void> _kanallariKur() async {
    final a = _android;
    if (a == null) return;

    // Eski sürüm kanallarını temizle (sesleri kilitli kalmış olabilir)
    for (final id in _eskiKanallar) {
      await a.deleteNotificationChannel(channelId: id);
    }

    // Varsayılan (sistem sesi)
    await a.createNotificationChannel(const AndroidNotificationChannel(
      _kanalVarsayilan, 'Varsayılan',
      description: 'Yeni mesaj bildirimleri',
      importance: Importance.high,
    ));
    // Sessiz
    await a.createNotificationChannel(AndroidNotificationChannel(
      _kanalIdFor('sessiz'), 'Sessiz',
      importance: Importance.high,
      playSound: false,
    ));
    // Kedi sesleri (4 adet)
    for (final e in _kediSesleri.entries) {
      await a.createNotificationChannel(AndroidNotificationChannel(
        _kanalIdFor(e.key), e.value,
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(e.key),
      ));
    }
    // Çıngırak
    await a.createNotificationChannel(AndroidNotificationChannel(
      _kanalIdFor('cingirak'), 'Çıngırak',
      importance: Importance.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('cingirak'),
    ));
    await _ozelKanaliKur();
  }

  /// Özel ses kanalını kullanıcının seçtiği URI ile (yeniden) kurar.
  /// Android kanalın sesini sonradan değiştirmez → önce sil, sonra oluştur.
  Future<void> _ozelKanaliKur() async {
    final a = _android;
    if (a == null) return;
    await a.deleteNotificationChannel(channelId: _kanalIdFor('ozel'));
    final uri = AyarServisi.instance.ozelSesUri.value;
    if (uri != null && uri.isNotEmpty) {
      await a.createNotificationChannel(AndroidNotificationChannel(
        _kanalIdFor('ozel'), 'Özel Ses',
        importance: Importance.high,
        sound: UriAndroidNotificationSound(uri),
      ));
    }
  }

  /// Ses seçimi değişince çağrılır: özel kanalı tazeler + tercihi Firestore'a
  /// yayınlar (karşı taraf push'u bu kanalı kullanır → kapalıyken bile doğru ses).
  Future<void> sesGuncelle() async {
    await _ozelKanaliKur();
    await kanalYayinla();
  }

  /// Aktif kanal id'sini Firestore'a yazar.
  Future<void> kanalYayinla() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _kullanicilar.doc(uid).set(
      {'bildirimKanali': aktifKanalId},
      SetOptions(merge: true),
    );
  }

  void _foregroundGoster(RemoteMessage message) {
    final bildirim = message.notification;
    if (bildirim == null) return;

    // Kullanıcı ayarlarını uygula
    final ayar = AyarServisi.instance;
    if (!ayar.bildirimAcik.value) return; // bildirim kapalıysa gösterme

    // Ses hem kanaldan (Android 8+) hem detaydan (8 altı) gelir.
    final secim = ayar.bildirimSesi.value;
    _yerel.show(
      id: bildirim.hashCode,
      title: bildirim.title,
      body: bildirim.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          aktifKanalId,
          'Kardeş Mesaj',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: secim != 'sessiz',
          sound: _sesFor(secim),
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

    // Seçili bildirim kanalını da yayınla (karşı taraf push'ta kullanır)
    await kanalYayinla();

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
    await _push(kur: (hedefKanal) => {
      'notification': {'title': baslik, 'body': govde},
      'android': {
        'priority': 'high',
        // Karşı tarafın SEÇTİĞİ kanal → kendi sesini duyar (kapalıyken bile)
        'notification': {'channel_id': hedefKanal},
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
    await _push(kur: (_) => {
      'data': {
        'tur': 'arama',
        'arayan': arayan,
        'tip': tip,
        'kanal': kanal,
      },
      'android': {'priority': 'high'},
    });
  }

  /// FCM HTTP v1 ortak gönderim: karşı tarafın token'ını + seçtiği bildirim
  /// kanalını bulur, service account ile OAuth2 alır, [kur](hedefKanal) ile
  /// `message` gövdesini oluşturup yollar.
  Future<void> _push({
    required Map<String, dynamic> Function(String hedefKanal) kur,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Karşı tarafın token'ı + seçtiği bildirim kanalı
      final snap = await _kullanicilar.get();
      String? hedefToken;
      var hedefKanal = _kanalVarsayilan;
      for (final doc in snap.docs) {
        if (doc.id != uid) {
          final d = doc.data();
          hedefToken = d['fcmToken'] as String?;
          hedefKanal = (d['bildirimKanali'] as String?) ?? _kanalVarsayilan;
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
            'message': {'token': hedefToken, ...kur(hedefKanal)},
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
