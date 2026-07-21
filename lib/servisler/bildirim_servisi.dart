import 'dart:convert';
import 'hata_servisi.dart';

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
  HataServisi.instance.iz('PUSH geldi tur=${data['tur']}');
  switch (data['tur']) {
    case 'arama':
      // ARKA PLAN TEŞHİSİ: bu isolate'in izleri ana uygulamada görünmediği
      // için adımlar toplanıp doğrudan Firestore'a yazılır.
      final adimlar = <String>[
        'push alindi chatId=${data['chatId']} tip=${data['tip']} '
            'arayan=${data['arayan']} kanal=${data['kanal']}',
        'aktifAramaVar=$aktifAramaVar',
      ];
      // Önce zil çalsın (gecikme olmasın)...
      try {
        await gelenAramayiGoster(data);
        adimlar.add('CallKit showCallkitIncoming TAMAM');
        HataServisi.instance.iz('CALLKIT gelen arama gosterildi');
      } catch (e, st) {
        adimlar.add('CallKit showCallkitIncoming HATA: $e');
        final satirlar = st.toString().split('\n').take(4).join(' | ');
        adimlar.add('stack: $satirlar');
      }
      // CallKit gerçekten kaydetti mi? (0 ise gelen arama ekranı HİÇ açılmamış)
      try {
        final aktif = await FlutterCallkitIncoming.activeCalls();
        adimlar.add('activeCalls sonrasi=${aktif.length}');
        if (aktif.isNotEmpty) adimlar.add('activeCall id=${aktif.first.id}');
      } catch (e) {
        adimlar.add('activeCalls HATA: $e');
      }
      await HataServisi.instance.arkaplanRapor('GELEN ARAMA (arka plan)', adimlar);
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
        HataServisi.instance.iz('CALLKIT iptal: zil susturuldu');
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

/// MEŞGULken gelen aramayı arayana bildirir: `aramalar/{chatId}.durum='mesgul'`.
/// Arayanın [AramaEkrani] dinleyicisi bunu görüp "Meşgul" ile kapanır.
/// (AramaServisi'ni import ETMİYORUZ — o zaten bildirim_servisi'ni import
/// ediyor; dairesel bağımlılık olmasın diye Firestore'a doğrudan yazılır.)
Future<void> _mesgulBildir(String? chatId) async {
  if (chatId == null || chatId.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('aramalar')
        .doc(chatId)
        .set({'durum': 'mesgul'}, SetOptions(merge: true));
    HataServisi.instance.iz('MESGUL bildirildi chat=$chatId');
  } catch (e) {
    HataServisi.instance.iz('MESGUL bildirilemedi: $e');
  }
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
  // ARANANIN kendi zil tercihi. ⚠️ Burası ARKA PLAN izolatı olabilir →
  // AyarServisi.baslat() çalışmamıştır; ayar DİSKTEN taze okunur.
  final zilYolu = await AyarServisi.aramaZiliDiskten();
  final params = CallKitParams(
    id: chatId,
    nameCaller: arayan,
    appName: 'ROY MESSANGER',
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
      // KULLANICININ SEÇTİĞİ zil (Ayarlar > Arama Zil Sesi).
      // Eklenti bunu `res/raw/<ad>` olarak çözer; `system_ringtone_default`
      // ise telefonun kendi zilini çalar. STREAM_RING'de, döngüde.
      ringtonePath: zilYolu,
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
  static const String _kanalVer = 'v3';
  // ⚠️ VARSAYILAN kanal da SÜRÜMLÜ olmalı. Eskiden sabit 'kardes_mesaj_kanal'
  // idi; v1.x'te oluşturulduğu için Android sesini KALICI KİLİTLEMİŞTİ ve
  // "Varsayılan" seçiliyken hiç ses gelmiyordu (diğer sesler km_v2_* sürümlü
  // olduğu için çalışıyordu). Sürümlü id ile kanal TAZE oluşur, ses gelir.
  static const String _kanalVarsayilan = 'km_${_kanalVer}_varsayilan';

  // Eski (kilitli/sessiz kalmış olabilecek) kanallar — açılışta silinir.
  static const List<String> _eskiKanallar = [
    'kardes_mesaj_kanal', // v1.x varsayılan (sessiz kilitlenmişti)
    'kardes_mesaj_kanal_sessiz',
    'kardes_mesaj_kanal_kedi',
    'kardes_mesaj_kanal_cingirak',
    'kardes_mesaj_kanal_ozel',
    // v2 kuşağı (varsayılan sorunu nedeniyle v3'e geçildi)
    'km_v2_sessiz', 'km_v2_kedi', 'km_v2_kedi2', 'km_v2_kedi3',
    'km_v2_kedi4', 'km_v2_cingirak', 'km_v2_ozel',
  ];

  // Kedi sesleri: seçim anahtarı → gösterim adı (raw kaynak adı = anahtarın aynısı)
  static const Map<String, String> _kediSesleri = {
    'kedi': 'Yavru Kedi 1 🐱',
    'kedi2': 'Yavru Kedi 2 😻',
    'kedi3': 'Yavru Kedi 3 🐈',
    'kedi4': 'Yavru Kedi 4 🐾',
  };

  /// Karşı tarafın Firestore'da YAYINLADIĞI kanal id'sini doğrular.
  ///
  /// ⚠️ NEDEN GEREKLİ: Alıcı uygulamayı güncelledikten sonra AÇMADIYSA,
  /// `bildirimKanali` alanında ESKİ SÜRÜM kanal id'si (`km_v2_*`,
  /// `kardes_mesaj_kanal`) kalır. O kanallar açılışta SİLİNDİĞİ için push
  /// var olmayan bir kanala gider → bildirim sessiz kalabilir/görünmeyebilir.
  /// Geçersizse güvenli varsayılana düşeriz (o kanal her zaman kurulur).
  String _gecerliKanal(String? kanal) {
    if (kanal == null || kanal.isEmpty) return _kanalVarsayilan;
    if (kanal == _kanalVarsayilan) return kanal;
    // Yalnız GÜNCEL sürüm öneki kabul edilir.
    return kanal.startsWith('km_${_kanalVer}_') ? kanal : _kanalVarsayilan;
  }

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

  /// Telefonun zil durumu. Zil çalmama şikayetinin en yaygın sebebi cihazın
  /// SESSİZ/TİTREŞİM modu ya da zil sesinin 0 olmasıdır. Kullanıcıyı
  /// bilgilendirmek için okunur — uygulama cihaz ayarını DEĞİŞTİRMEZ.
  /// Dönen: (mod: 'normal'|'titresim'|'sessiz', seviye: int)
  Future<({String mod, int seviye})> zilDurumu() async {
    try {
      final r = await _native.invokeMapMethod<String, dynamic>('zilDurumu');
      return (
        mod: (r?['mod'] as String?) ?? 'normal',
        seviye: (r?['seviye'] as int?) ?? 1,
      );
    } catch (_) {
      return (mod: 'normal', seviye: 1); // okunamıyorsa uyarı gösterme
    }
  }

  /// Zil duyulmayacak mı? (sessiz/titreşim modu veya zil sesi 0)
  Future<bool> zilDuyulmazMi() async {
    final d = await zilDurumu();
    return d.mod != 'normal' || d.seviye == 0;
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
    // ⚠️ Eskiden burada SESSİZCE `return` ediliyordu → arayan 45 sn boyunca
    // boşuna çalıyor, meşgul olduğumuzu asla öğrenmiyordu. Artık arayana
    // 'mesgul' durumu yazılıyor; onun arama ekranı "Meşgul" deyip kapanır.
    if (message.data['tur'] == 'arama' && aktifAramaVar) {
      await _mesgulBildir(message.data['chatId']?.toString());
      return;
    }
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
      playSound: true, // AÇIKÇA: sistem varsayılan bildirim sesi çalsın
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
          'ROY MESSANGER',
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

  // ÖLÜ KOD SİLİNDİ (FAZ 4 öncesi 2 kişilik akış):
  //   karsiTarafaBildirimGonder / karsiTarafaAramaGonder /
  //   karsiTarafaAramaIptal / _push
  // Bunlar "karşı taraf"ı `kullanicilar` koleksiyonundan KENDİSİ OLMAYAN İLK
  // kullanıcıyı seçerek buluyordu — çok kullanıcılı yapıda YANLIŞ KİŞİYE
  // arama/iptal göndermeye açıktı. Yerlerini uid-hedefli
  // [hedefeBildirimGonder] / [hedefeVeriGonder] aldı (0 kullanımdaydılar).

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
    final kanal = _gecerliKanal(d?['bildirimKanali'] as String?);
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
