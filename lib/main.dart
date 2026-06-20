import 'package:flutter/material.dart';
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
  runApp(const KardesMesajApp());
}

/// CallKit tam ekran gelen-arama ekranındaki Kabul/Reddet'i işler.
/// Uygulama KAPALIYKEN bile arama bu yolla yanıtlanabilir.
/// Kabul edilince aktif arama bilgisini (kanal/tip) Firestore'dan okuyup katılır.
void _callkitDinle() {
  FlutterCallkitIncoming.onEvent.listen((event) async {
    switch (event) {
      case CallEventActionCallAccept():
        try {
          final bilgi = await AramaServisi.instance.aktifArama();
          final kanal = bilgi?['kanal'] as String?;
          if (kanal == null) return;
          final tip = aramaTipiCoz(bilgi?['tip'] as String?);
          final ok = await AramaServisi.instance.kabulEt(kanal, tip);
          if (ok) {
            navigatorKey.currentState?.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AramaEkrani(kanal: kanal, tip: tip, baslik: 'Kardeş'),
              ),
            );
          }
        } catch (e) {
          debugPrint('CallKit kabul hatası: $e');
        }
        break;
      case CallEventActionCallDecline():
        await AramaServisi.instance.reddet();
        break;
      default:
        break;
    }
  });
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
