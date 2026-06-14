import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'kimlik/auth_gate.dart';
import 'servisler/ayar_servisi.dart';
import 'servisler/bildirim_servisi.dart';
import 'tema.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase'i baslat (firebase_options.dart flutterfire configure ile uretildi)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Kullanici ayarlarini yukle (bildirim/titresim/ses tercihleri)
  await AyarServisi.instance.baslat();
  // Uygulama kapali/arka plandayken gelen mesajlar icin handler
  FirebaseMessaging.onBackgroundMessage(arkaplanMesajHandler);
  // Bildirim servisi: izin, kanal, foreground dinleyici
  await BildirimServisi.instance.baslat();
  runApp(const KardesMesajApp());
}

class KardesMesajApp extends StatelessWidget {
  const KardesMesajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kardeş Mesaj',
      debugShowCheckedModeBanner: false,
      theme: AppTema.karanlik(), // merkezi tema (tema.dart)
      // AuthGate: oturum varsa sohbet, yoksa giriş ekranı
      home: const AuthGate(),
    );
  }
}
