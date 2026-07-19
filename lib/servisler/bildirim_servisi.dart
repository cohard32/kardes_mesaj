import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:permission_handler/permission_handler.dart';

import '../tema.dart';
import 'ayar_servisi.dart';

/// Arka plan / uygulama kapalı mesaj handler'ı.
/// Top-level (sınıf dışı) olmak ZORUNDA — Android arka planda izole çalıştırır.
/// Normal mesaj `notification` payload'ı sistem tepsisinde otomatik gösterilir.
///   data.tur == 'arama'       → tam ekran gelen arama (CallKit)
///   data.tur == 'arama_iptal' → arayan kapattı, çalmayı DURDUR
@pragma('vm:entry-point')
Future<void> arkaplanMesajHandler(RemoteMessage message) async {
  // Arka plan izole edilmiş bir isolate'te çalışır — Firebase burada da
  // başlatılmalı, yoksa eklenti çağrıları çökebilir ve CallKit hiç açılmaz.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await aramaMesajiIsle(message.data);
}

/// Şu an aktif bir aramada mıyım? AramaServisi katılınca/bitince günceller.
/// (Aynı isolate'te) meşgulken gelen yeni çağrının CallKit'i açmasını engeller.
/// Dairesel import olmasın diye burada top-level tutulur.
bool aktifAramaVar = false;

/// Çağrı ile ilgili FCM verisini işler. Hem arka plan handler'ı hem de
/// uygulama açıkken (onMessage) AYNI yolu kullanır → tek tutarlı akış.
/// İşlendiyse true döner.
Future<bool> aramaMesajiIsle(Map<String, dynamic> data) async {
  switch (data['tur']) {
    case 'arama':
      // Önce zil çalsın (gecikme olmasın)...
      await gelenAramayiGoster(data);
      // ...sonra TEŞHİS (fire-and-forget): handler'ın GERÇEKTEN çalıştığını
      // Firestore'a işaretle. "Kapalıyken hiç gelmiyor"un sebebi böyle ayrışır:
      //  - Bu zaman damgası güncellendiyse → FCM ULAŞTI (sorun CallKit/kod).
      //  - Güncellenmediyse → FCM cihaza HİÇ ulaşmadı (autostart/pil = cihaz ayarı).
      _cagriPushTeshisYaz(data['kanal']?.toString());
      return true;
    case 'arama_iptal':
      // Arayan kapattı/vazgeçti → zil sussun, ekran kapansın.
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
      return true;
    default:
      return false;
  }
}

/// Çağrı push'unun alındığını (handler çalıştığını) Firestore'a yazar.
/// Arka plan izolatında da çalışır (Firebase init edilmiş + oturum diskten geri
/// yüklenmiş olur).
Future<void> _cagriPushTeshisYaz(String? kanal) async {
  try {
    // Arka plan izolatında oturum diskten geç yüklenebilir → kısa süre bekle.
    var uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      try {
        final u = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 3));
        uid = u?.uid;
      } catch (_) {}
    }
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('kullanicilar')
        .doc(uid)
        .set({
      'sonCagriPush': FieldValue.serverTimestamp(),
      'sonCagriPushKanal': kanal,
    }, SetOptions(merge: true));
  } catch (_) {}
}

/// GELEN ARAMA — uygulamanın TEK gelen arama ekranı (her durumda bu çalışır:
/// açık / arka plan / tamamen kapalı). Zil, tam ekran ve kilit ekranı
/// desteğini işletim sisteminden alır.
/// Renkler `tema.dart`'tan gelir (native katman hex string ister).
Future<void> gelenAramayiGoster(Map<String, dynamic> data) async {
  // FAZ 4: CallKit id = chatId → kabul olayı hangi sohbet olduğunu bilir.
  final chatId = (data['chatId'] ?? data['kanal'] ?? 'arama').toString();
  final arayan = (data['arayan'] ?? 'Kardeş').toString();
  final video = data['tip'] == 'video';
  final params = CallKitParams(
    id: chatId,
    nameCaller: arayan,
    appName: 'Kardeş Mesaj',
    handle: video ? 'Görüntülü arama' : 'Sesli arama',
    type: video ? 1 : 0,
    // Zil süresi: arayan tarafın 45 sn zaman aşımıyla uyumlu.
    duration: 45000,
    extra: <String, dynamic>{
      'chatId': chatId,
      'tip': data['tip'],
      'arayan': arayan,
    },
    android: AndroidParams(
      isCustomNotification: true,
      // TAM EKRAN AKTİVİTE (sadece bildirim değil) → ekran kapalı/kilitliyken
      // bile gelen arama ekranı açılır ve ekran uyanır.
      isFullScreen: true,
      isShowFullLockedScreen: true,
      isShowCallID: false,
      isImportant: true,
      // Paketin res/raw içindeki kendi zili (loop'lu çalar).
      ringtonePath: 'ringtone_default',
      // TEMA: varsayılan MAVİ (#0955fa) yerine uygulamanın neon-yeşil dili
      backgroundColor: TemaHex.zemin,
      actionColor: TemaHex.neon,
      textColor: TemaHex.metin,
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

  // Native izin/ses kontrolleri (MainActivity.kt ile aynı kanal adı)
  static const MethodChannel _native = MethodChannel('kardes_mesaj/sesler');

  /// Android 14+ tam ekran bildirim izni var mı? (yoksa ekran kapalıyken
  /// gelen arama tam ekran açılmaz, sadece bildirime düşer)
  Future<bool> tamEkranIzniVarMi() async {
    try {
      return await _native.invokeMethod<bool>('tamEkranIzniVarMi') ?? true;
    } catch (_) {
      return true; // kontrol edilemiyorsa engelleme
    }
  }

  /// Tam ekran bildirim izni ayar ekranını açar.
  Future<void> tamEkranAyarlariniAc() async {
    try {
      await _native.invokeMethod<void>('tamEkranAyarlariniAc');
    } catch (_) {}
  }

  /// Pil optimizasyonu muafiyeti ister (Doze uygulamayı uyutup aramayı/
  /// bildirimi geciktirmesin). Zaten verilmişse tekrar sormaz.
  Future<void> pilOptimizasyonuIste() async {
    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  final FirebaseMessaging _mesajlasma = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _yerel =
      FlutterLocalNotificationsPlugin();
  final CollectionReference<Map<String, dynamic>> _kullanicilar =
      FirebaseFirestore.instance.collection('kullanicilar');
  // FAZ 4: profiller + token'lar buraya taşınıyor (hedefli bildirim için)
  final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  bool _kuruldu = false;
  bool _tokenDinleyiciKuruldu = false;

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
    FirebaseMessaging.onMessage.listen(_gelenMesaj);
  }

  /// Foreground mesaj yönlendiricisi.
  /// Çağrı mesajları arka planla AYNI yoldan geçer (CallKit) → uygulama açıkken
  /// de zil çalar, tek tutarlı akış olur.
  Future<void> _gelenMesaj(RemoteMessage message) async {
    // MEŞGUL: zaten bir aramadayken yeni gelen çağrıyı gösterme (üstüne binmesin).
    if (message.data['tur'] == 'arama' && aktifAramaVar) return;
    if (await aramaMesajiIsle(message.data)) return; // çağrı/iptal ise bitti
    _foregroundGoster(message); // normal mesaj bildirimi
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

  /// Aktif kanal id'sini Firestore'a yazar (hem eski `kullanicilar` hem
  /// FAZ 4 `users` — geçiş dönemi çift yazım).
  Future<void> kanalYayinla() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final veri = {'bildirimKanali': aktifKanalId};
    await _kullanicilar.doc(uid).set(veri, SetOptions(merge: true));
    try {
      await _users.doc(uid).set(veri, SetOptions(merge: true));
    } catch (_) {}
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
          // Kilit ekranında içerik GİZLENMESİN (yarım görünme sorunu)
          visibility: NotificationVisibility.public,
          // Uzun mesaj tek satıra kırpılmasın, açılabilir olsun
          styleInformation: BigTextStyleInformation(
            bildirim.body ?? '',
            contentTitle: bildirim.title,
          ),
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
      final veri = {
        'fcmToken': token,
        'guncelleme': FieldValue.serverTimestamp(),
      };
      await _kullanicilar.doc(kullanici.uid)
          .set({...veri, 'eposta': kullanici.email}, SetOptions(merge: true));
      // FAZ 4: hedefli bildirim token'ı users'tan okuyor → oraya da yaz.
      try {
        await _users.doc(kullanici.uid).set(veri, SetOptions(merge: true));
      } catch (_) {}
    }

    // Seçili bildirim kanalını da yayınla (karşı taraf push'ta kullanır)
    await kanalYayinla();

    // Token zamanla yenilenebilir — değişince güncelle.
    // tokenKaydet() sohbet ekranı her açıldığında çağrılıyor; dinleyici
    // birikmesin diye SADECE BİR KEZ kur.
    if (!_tokenDinleyiciKuruldu) {
      _tokenDinleyiciKuruldu = true;
      _mesajlasma.onTokenRefresh.listen((yeniToken) {
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) return;
        _kullanicilar.doc(u.uid).set(
          {'fcmToken': yeniToken},
          SetOptions(merge: true),
        );
        _users.doc(u.uid).set(
          {'fcmToken': yeniToken},
          SetOptions(merge: true),
        ).catchError((_) {});
      });
    }
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
        'notification': {
          // Karşı tarafın SEÇTİĞİ kanal → kendi sesini duyar (kapalıyken bile)
          'channel_id': hedefKanal,
          // Kilit ekranında içerik gizlenmesin/yarım görünmesin
          'visibility': 'PUBLIC',
          // Aynı sohbet tek bildirimde toplansın
          'tag': 'kardes_mesaj',
        },
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
      'android': {
        // HTTP v1 kanonik değer BÜYÜK harf 'HIGH'. Data-only mesajın
        // ÖLDÜRÜLMÜŞ uygulamayı uyandırması için priority HIGH ŞART
        // (küçük harf 'high' düşük önceliğe düşebiliyordu → çağrı hiç gelmiyordu).
        'priority': 'HIGH',
        // Çağrı anlıktır; gecikirse anlamsız → kuyrukta bekletme.
        'ttl': '45s',
      },
    });
  }

  /// ARAMA İPTAL push'u — arayan kapatınca/vazgeçince karşı tarafın ZİLİNİ
  /// susturur. Firestore dinleyicisi karşı taraf KAPALIYKEN çalışmadığı için
  /// bu push olmadan CallKit çalmaya devam ediyordu (kritik hata).
  Future<void> karsiTarafaAramaIptal({required String kanal}) async {
    await _push(kur: (_) => {
      'data': {'tur': 'arama_iptal', 'kanal': kanal},
      'android': {'priority': 'HIGH', 'ttl': '45s'},
    });
  }

  /// (2 kişilik — eski akış) Karşı tarafın token'ını + kanalını bulur, yollar.
  /// FAZ 4'te yerini [hedefeBildirimGonder] / [hedefeVeriGonder] alacak.
  Future<void> _push({
    required Map<String, dynamic> Function(String hedefKanal) kur,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
    await _gonderMesaj(hedefToken, kur(hedefKanal));
  }

  /// FAZ 4: BELİRLİ bir kullanıcıya (uid) mesaj bildirimi gönderir.
  /// [ekstraData] verilirse data payload olarak eklenir (sohbet açma vb.).
  Future<void> hedefeBildirimGonder({
    required String hedefUid,
    required String baslik,
    required String govde,
    Map<String, String>? ekstraData,
  }) async {
    final d = (await _users.doc(hedefUid).get()).data();
    final token = d?['fcmToken'] as String?;
    if (token == null) return;
    final kanal = (d?['bildirimKanali'] as String?) ?? _kanalVarsayilan;
    await _gonderMesaj(token, {
      'notification': {'title': baslik, 'body': govde},
      'data': ?ekstraData,
      'android': {
        'priority': 'high',
        'notification': {
          'channel_id': kanal,
          'visibility': 'PUBLIC',
          'tag': 'km_$hedefUid',
        },
      },
    });
  }

  /// FAZ 4: BELİRLİ bir kullanıcıya data-only push (arama/iptal gibi).
  Future<void> hedefeVeriGonder({
    required String hedefUid,
    required Map<String, String> veri,
  }) async {
    final token = (await _users.doc(hedefUid).get()).data()?['fcmToken']
        as String?;
    if (token == null) return;
    await _gonderMesaj(token, {
      'data': veri,
      'android': {'priority': 'HIGH', 'ttl': '45s'},
    });
  }

  /// DÜŞÜK SEVİYE: verilen token'a, service account OAuth2 ile FCM HTTP v1 gönderir.
  Future<void> _gonderMesaj(
    String hedefToken,
    Map<String, dynamic> mesajAlanlari,
  ) async {
    try {
      final saJson =
          await rootBundle.loadString('assets/service_account.json');
      final saMap = jsonDecode(saJson) as Map<String, dynamic>;
      final projectId = saMap['project_id'] as String?;
      if (projectId == null) return;

      final credentials = ServiceAccountCredentials.fromJson(saMap);
      final client = await clientViaServiceAccount(
        credentials,
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );
      try {
        final yanit = await client.post(
          Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
          ),
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
