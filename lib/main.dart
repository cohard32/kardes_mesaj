import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'firebase_options.dart';
import 'ekranlar/arama_ekrani.dart';
import 'kimlik/auth_gate.dart';
import 'servisler/arama_servisi.dart';
import 'servisler/ayar_servisi.dart';
import 'servisler/bildirim_servisi.dart';
import 'tema.dart';

/// Uygulama dışından (CallKit olayları) gezinmek için global navigator anahtarı.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase'i baslat (firebase_options.dart flutterfire configure ile uretildi)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  // Sistem çubukları temaya uysun (AppBar'ı olmayan ekranlar dahil)
  SystemChrome.setSystemUIOverlayStyle(AppTema.sistemCubuklari);
  runApp(const KardesMesajApp());
}

/// Aynı aramanın iki kez (onEvent + activeCalls kurtarma) işlenmesini önler.
String? _islenenAramaKanali;

/// CallKit tam ekran gelen-arama ekranındaki olayları işler.
void _callkitDinle() {
  FlutterCallkitIncoming.onEvent.listen((event) async {
    debugPrint('CallKit olay: ${event?.runtimeType}');
    switch (event) {
      case CallEventActionCallAccept():
        await _aramayiKabulEt();
        break;
      case CallEventActionCallDecline():
        await AramaServisi.instance.reddet();
        break;
      // Cevap verilmeyen/kaçırılan arama → arayana bildir (o da kapansın).
      // NOT: sadece Timeout işlenir; Ended bizim endAllCalls'umuzdan da geldiği
      // için (kabul sonrası) yok sayılır — yoksa kendi aramamızı iptal ederdik.
      case CallEventActionCallTimeout():
        // Zaten bir aramaya katıldıysam (kabul) bu timeout bana ait değil.
        if (AramaServisi.instance.engine == null) {
          await AramaServisi.instance.reddet();
        }
        break;
      default:
        break;
    }
  });
}

/// Gelen aramayı kabul eder: Firestore'dan kanal/tip okur, Agora'ya katılır,
/// arama ekranını açar. onEvent ve soğuk-başlangıç kurtarma AYNI yolu kullanır.
Future<void> _aramayiKabulEt() async {
  try {
    // Kabul, auth + Firestore ister; soğuk başlangıçta oturum henüz gelmemiş
    // olabilir → kısa bir süre bekle.
    await _authHazirOlsun();
    final bilgi = await AramaServisi.instance.aktifArama();
    final kanal = bilgi?['kanal'] as String?;
    final durum = bilgi?['durum'];
    if (kanal == null) return;
    // Arama hâlâ geçerli mi? (arayan çoktan kapatmış olabilir)
    if (durum != 'cagriliyor' && durum != 'kabul') return;
    // Çift işleme koruması
    if (_islenenAramaKanali == kanal) return;
    _islenenAramaKanali = kanal;

    final tip = aramaTipiCoz(bilgi?['tip'] as String?);
    final ok = await AramaServisi.instance.kabulEt(kanal, tip);
    if (!ok) {
      _islenenAramaKanali = null;
      return;
    }
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(kanal: kanal, tip: tip, baslik: 'Kardeş'),
        ),
      );
    } else {
      // Navigator henüz yok → SohbetEkrani açılınca açar.
      AramaServisi.instance.bekleyenKanal = kanal;
      AramaServisi.instance.bekleyenTip = tip;
    }
  } catch (e) {
    debugPrint('CallKit kabul hatası: $e');
    _islenenAramaKanali = null;
  }
}

/// Uygulama ÖLDÜRÜLMÜŞKEN CallKit'ten kabulle açıldıysa, kabul olayı onEvent'e
/// düşmez. Kalan aktif çağrı varsa kabul akışını başlatır.
Future<void> _oldurulmuskenKabulEdileniAc() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.isEmpty) return;
    // Aktif çağrı, kabul akışını tetikler (içeride Firestore durumu doğrulanır).
    await _aramayiKabulEt();
  } catch (e) {
    debugPrint('Soğuk başlangıç kurtarma hatası: $e');
  }
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
