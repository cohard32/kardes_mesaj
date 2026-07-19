import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'firebase_options.dart';
import 'ekranlar/arama_ekrani.dart';
import 'ekranlar/sohbet_ekrani.dart';
import 'kimlik/auth_gate.dart';
import 'servisler/arama_servisi.dart';
import 'servisler/ayar_servisi.dart';
import 'servisler/bildirim_servisi.dart';
import 'servisler/kullanici_servisi.dart';
import 'tema.dart';

/// Uygulama dışından (CallKit olayları) gezinmek için global navigator anahtarı.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase'i baslat (firebase_options.dart flutterfire configure ile uretildi)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Kullanici ayarlarini yukle (bildirim/titresim/ses tercihleri)
  await AyarServisi.instance.baslat();
  // Uygulama kapali/arka plandayken gelen mesajlar + cagri icin handler
  FirebaseMessaging.onBackgroundMessage(arkaplanMesajHandler);
  // Bildirim servisi: izin, kanal, foreground dinleyici
  await BildirimServisi.instance.baslat();
  // CallKit (gelen arama ekranı) olaylarını dinle
  _callkitDinle();
  // KRİTİK: Uygulama ÖLDÜRÜLMÜŞKEN kabule basılıp açıldıysa, accept olayı
  // dinleyici kurulmadan önce geldiği için KAYBOLUR. activeCalls() ile kurtar.
  await _oldurulmuskenKabulEdileniAc();
  // Mesaj bildirimine tıklama → doğru sohbeti aç.
  //  - arka plandayken: onMessageOpenedApp
  //  - öldürülmüşken açılışta: getInitialMessage (navigator hazır olunca açılır)
  FirebaseMessaging.onMessageOpenedApp.listen(_mesajBildirimineTiklandi);
  final ilkMesaj = await FirebaseMessaging.instance.getInitialMessage();
  if (ilkMesaj != null) _mesajBildirimineTiklandi(ilkMesaj);
  // Sistem çubukları temaya uysun (AppBar'ı olmayan ekranlar dahil)
  SystemChrome.setSystemUIOverlayStyle(AppTema.sistemCubuklari);
  runApp(const KardesMesajApp());
}

/// Aynı aramanın iki kez (onEvent + activeCalls kurtarma) işlenmesini önler.
String? _islenenChatId;

/// CallKit olaylarının id'si = chatId (gelenAramayiGoster böyle ayarlar).
void _callkitDinle() {
  FlutterCallkitIncoming.onEvent.listen((event) async {
    debugPrint('CallKit olay: ${event?.runtimeType}');
    switch (event) {
      case CallEventActionCallAccept(:final id):
        await _aramayiKabulEt(id);
        break;
      case CallEventActionCallDecline(:final id):
        await AramaServisi.instance.reddet(id);
        break;
      // Cevap verilmeyen/kaçırılan arama → arayana bildir. Sadece Timeout;
      // Ended kendi endAllCalls'umuzdan da geldiği için yok sayılır.
      case CallEventActionCallTimeout(:final id):
        if (AramaServisi.instance.engine == null) {
          await AramaServisi.instance.reddet(id);
        }
        break;
      default:
        break;
    }
  });
}

/// [chatId]'deki gelen aramayı kabul eder: Firestore'dan tip/arayan okur,
/// Agora'ya katılır, arama ekranını açar.
Future<void> _aramayiKabulEt(String chatId) async {
  try {
    await _authHazirOlsun();
    final bilgi = await AramaServisi.instance.aktifArama(chatId);
    final durum = bilgi?['durum'];
    if (bilgi == null) return;
    if (durum != 'cagriliyor' && durum != 'kabul') return; // iptal edilmiş
    if (_islenenChatId == chatId) return; // çift işleme koruması
    _islenenChatId = chatId;

    final tip = aramaTipiCoz(bilgi['tip'] as String?);
    final baslik = (bilgi['arayan'] ?? 'Arama').toString();
    final ok = await AramaServisi.instance.kabulEt(chatId, tip);
    if (!ok) {
      _islenenChatId = null;
      return;
    }
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(chatId: chatId, tip: tip, baslik: baslik),
        ),
      );
    } else {
      // Navigator henüz yok → SohbetEkrani/AnaKabuk açılınca açar.
      AramaServisi.instance.bekleyenChatId = chatId;
      AramaServisi.instance.bekleyenTip = tip;
      AramaServisi.instance.bekleyenBaslik = baslik;
    }
  } catch (e) {
    debugPrint('CallKit kabul hatası: $e');
    _islenenChatId = null;
  }
}

/// Uygulama ÖLDÜRÜLMÜŞKEN CallKit'ten kabulle açıldıysa, kabul olayı onEvent'e
/// düşmez. Kalan aktif çağrının id'si (=chatId) ile kabul akışını başlatır.
Future<void> _oldurulmuskenKabulEdileniAc() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.isEmpty) return;
    final chatId = calls.first.id;
    await _aramayiKabulEt(chatId);
  } catch (e) {
    debugPrint('Soğuk başlangıç kurtarma hatası: $e');
  }
}

/// Bildirime tıklanınca açılacak sohbet (navigator hazır değilse beklet).
String? _bekleyenSohbetChatId;
String? _bekleyenSohbetKarsiUid;

/// Mesaj bildirimine tıklandı → ilgili sohbeti aç. Veri: {tur, chatId, gonderenUid}.
void _mesajBildirimineTiklandi(RemoteMessage message) {
  final data = message.data;
  if (data['tur'] != 'mesaj') return;
  final chatId = data['chatId'];
  final karsiUid = data['gonderenUid'];
  if (chatId is! String || karsiUid is! String || chatId.isEmpty) return;
  _bekleyenSohbetChatId = chatId;
  _bekleyenSohbetKarsiUid = karsiUid;
  bekleyenSohbetiAc();
}

/// Bekleyen sohbet varsa VE navigator hazırsa açar. Soğuk başlangıçta
/// AnaKabuk kurulunca (postFrame) tekrar çağrılır.
Future<void> bekleyenSohbetiAc() async {
  final chatId = _bekleyenSohbetChatId;
  final karsiUid = _bekleyenSohbetKarsiUid;
  if (chatId == null || karsiUid == null) return;
  // navigator hazır değil → beklet (AnaKabuk postFrame'de tekrar dener)
  if (navigatorKey.currentState == null) return;
  _bekleyenSohbetChatId = null;
  _bekleyenSohbetKarsiUid = null;
  await _authHazirOlsun();
  final karsi = await KullaniciServisi.instance.profilGetir(karsiUid);
  if (karsi == null) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute<void>(
      builder: (_) => SohbetEkrani(chatId: chatId, karsi: karsi),
    ),
  );
}

/// Oturum (auth) hazır olana kadar kısa süre bekler (en fazla ~3 sn).
Future<void> _authHazirOlsun() async {
  if (FirebaseAuth.instance.currentUser != null) return;
  try {
    await FirebaseAuth.instance
        .authStateChanges()
        .firstWhere((u) => u != null)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}

class KardesMesajApp extends StatelessWidget {
  const KardesMesajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kardeş Mesaj',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTema.karanlik(), // merkezi tema (tema.dart)
      // AuthGate: oturum varsa sohbet, yoksa giriş ekranı
      home: const AuthGate(),
    );
  }
}
