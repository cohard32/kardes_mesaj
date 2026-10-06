// AuthGate: tema değişimi (tumAgaciYenidenCiz) ve keyfi yeniden çizimler
// AnaKabuk'u ağaçtan SÖKMEMELİ. Eskiden akışlar build içinde üretiliyordu →
// her yeniden çizimde yeni abonelik → waiting → bekleme ekranı → AnaKabuk
// dispose + baştan initState (çevrimdışı/çevrimiçi yazımı, güncelleme
// penceresi, sekme sıfırlama). Firebase'siz: oturum/profil akışları ve alt
// ekranlar enjekte edilir.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/kimlik/auth_gate.dart';
import 'package:kardes_mesaj/modeller/kullanici.dart';
import 'package:kardes_mesaj/tema.dart';

/// AnaKabuk yerine geçen, yaşam döngüsünü sayan sahte ekran.
class _SahteKabuk extends StatefulWidget {
  const _SahteKabuk();
  static int init = 0;
  static int dispose = 0;
  @override
  State<_SahteKabuk> createState() => _SahteKabukState();
}

class _SahteKabukState extends State<_SahteKabuk> {
  int sekme = 0;
  @override
  void initState() {
    super.initState();
    _SahteKabuk.init++;
  }

  @override
  void dispose() {
    _SahteKabuk.dispose++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Text('kabuk $sekme', style: TextStyle(color: Renkler.metin)),
      );
}

void main() {
  late StreamController<String?> oturum;
  late Map<String, StreamController<Kullanici>> profiller;
  late List<String> profilCagrilari;
  var oturumCagrisi = 0;

  setUp(() {
    _SahteKabuk.init = 0;
    _SahteKabuk.dispose = 0;
    // ⚠️ Tek abonelikli: akış ikinci kez dinlenirse test patlar (yeniden
    // abonelik = eski hata).
    oturum = StreamController<String?>();
    profiller = {};
    profilCagrilari = [];
    oturumCagrisi = 0;
  });
  tearDown(() => Renkler.uygula(RoyPalet.neonLime, pariltiAzalt: false));

  Widget kapi() => AuthGate(
        oturumAkisi: () {
          oturumCagrisi++;
          return oturum.stream;
        },
        profilAkisi: (uid) {
          profilCagrilari.add(uid);
          return (profiller[uid] = StreamController<Kullanici>()).stream;
        },
        girisKurucu: (_) => const Text('giris'),
        kurulumKurucu: (_) => const Text('kurulum'),
        anaKurucu: (_) => const _SahteKabuk(),
      );

  /// Akış olayı mikro görevle gelir → bir kare olayı teslim eder, bir kare
  /// de setState'i çizer.
  Future<void> isle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> girisYap(WidgetTester tester, String uid,
      {String kullaniciAdi = 'ali'}) async {
    oturum.add(uid);
    await isle(tester);
    profiller[uid]!.add(
      Kullanici(uid: uid, ad: 'Ali', kullaniciAdi: kullaniciAdi),
    );
    await isle(tester);
  }

  testWidgets('tema değişimi AnaKabuk State\'ini korur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTema.olustur(), home: kapi()),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await girisYap(tester, 'u1');
    expect(find.byType(_SahteKabuk), findsOneWidget);
    expect(_SahteKabuk.init, 1);
    final ilkState = tester.state<_SahteKabukState>(find.byType(_SahteKabuk));
    ilkState.sekme = 3; // kaybolursa yeni State 0'dan başlar

    // main.dart _temaDegisti'nin eşleniği: palet + tüm ağacı kirlet.
    for (final p in RoyPalet.hepsi) {
      Renkler.uygula(p);
      tumAgaciYenidenCiz();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: p.ad);
      expect(find.byType(_SahteKabuk), findsOneWidget, reason: p.ad);
    }
    await tester.pumpAndSettle();

    expect(_SahteKabuk.init, 1);
    expect(_SahteKabuk.dispose, 0);
    expect(
      tester.state<_SahteKabukState>(find.byType(_SahteKabuk)),
      same(ilkState),
    );
    // Yeniden çizildi ama aynı State → seçili "sekme" korunmuş
    expect(find.text('kabuk 3'), findsOneWidget);
    // Akışlar bir kez kuruldu (yeniden abonelik yok)
    expect(oturumCagrisi, 1);
    expect(profilCagrilari, ['u1']);
  });

  testWidgets('keyfi yeniden çizim (yeni tema ile MaterialApp) State\'i korur',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTema.olustur(), home: kapi()),
    );
    await girisYap(tester, 'u1');
    final ilkState = tester.state<_SahteKabukState>(find.byType(_SahteKabuk));

    // Üst ağaç yeni bir AuthGate örneğiyle (const olmayan) yeniden kurulur.
    Renkler.uygula(RoyPalet.gunIsigi);
    await tester.pumpWidget(
      MaterialApp(theme: AppTema.olustur(), home: kapi()),
    );
    await tester.pump();
    tumAgaciYenidenCiz();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.state<_SahteKabukState>(find.byType(_SahteKabuk)),
      same(ilkState),
    );
    expect(_SahteKabuk.init, 1);
    expect(_SahteKabuk.dispose, 0);
    expect(oturumCagrisi, 1);
    expect(profilCagrilari, ['u1']);
  });

  testWidgets('çıkış → giriş; başka hesap → kendi profiline göre yönlenir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTema.olustur(), home: kapi()),
    );
    await girisYap(tester, 'u1');
    expect(find.byType(_SahteKabuk), findsOneWidget);

    oturum.add(null);
    await isle(tester);
    expect(find.text('giris'), findsOneWidget);
    expect(_SahteKabuk.dispose, 1);

    // Profili olmayan yeni hesap: önceki hesabın "profil var" verisi
    // taşınmamalı → önce bekleme, sonra kurulum.
    oturum.add('u2');
    await isle(tester);
    expect(find.byType(_SahteKabuk), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    profiller['u2']!.add(const Kullanici(uid: 'u2', ad: '', kullaniciAdi: ''));
    await isle(tester);
    expect(find.text('kurulum'), findsOneWidget);

    // Aynı hesapla yeniden giriş → taze profil akışı (tek abonelikli akış
    // ikinci kez dinlenmez).
    oturum.add(null);
    await isle(tester);
    await girisYap(tester, 'u1');
    expect(find.byType(_SahteKabuk), findsOneWidget);
    expect(profilCagrilari, ['u1', 'u2', 'u1']);
  });
}
