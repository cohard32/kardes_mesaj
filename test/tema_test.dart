// Tema sistemi testleri: palet kontrastları (WCAG), palet seçimi,
// çalışma anında palet değişimi ve kalıcılık (AyarServisi).
//
// ⚠️ Bir kontrast testi düşerse EŞİĞİ GEVŞETME — paleti (lib/tema.dart)
// düzelt. Eşikler: normal metin 4,5:1 (AA), büyük/kalın metin ve
// grafik öğe (ikon, avatar harfi) 3:1.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'package:kardes_mesaj/ekranlar/ayarlar_ekrani.dart';
import 'package:kardes_mesaj/ekranlar/giris_ekrani.dart';
import 'package:kardes_mesaj/ekranlar/profil_ekrani.dart';
import 'package:kardes_mesaj/servisler/ayar_servisi.dart';
import 'package:kardes_mesaj/tema.dart';

/// WCAG 2.x göreli parlaklık (sRGB → doğrusal).
double goreliParlaklik(Color c) {
  double kanal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * kanal(c.r) + 0.7152 * kanal(c.g) + 0.0722 * kanal(c.b);
}

/// WCAG kontrast oranı (1..21). Sıra önemsiz.
double kontrastOrani(Color a, Color b) {
  final la = goreliParlaklik(a);
  final lb = goreliParlaklik(b);
  final acik = math.max(la, lb);
  final koyu = math.min(la, lb);
  return (acik + 0.05) / (koyu + 0.05);
}

typedef _Cift = (
  String ad,
  Color Function(RoyPalet) on,
  Color Function(RoyPalet) arka,
  double esik,
);

final List<_Cift> _ciftler = [
  ('metin/zemin', (p) => p.metin, (p) => p.zemin, 4.5),
  ('metin/yuzey', (p) => p.metin, (p) => p.yuzey, 4.5),
  ('metin/balonGelen', (p) => p.metin, (p) => p.balonGelen, 4.5),
  ('metinSoluk/zemin', (p) => p.metinSoluk, (p) => p.zemin, 4.5),
  ('metinSoluk/yuzey', (p) => p.metinSoluk, (p) => p.yuzey, 4.5),
  ('metinSoluk/balonGelen', (p) => p.metinSoluk, (p) => p.balonGelen, 4.5),
  ('metinKoyu/neonAcik', (p) => p.metinKoyu, (p) => p.neonAcik, 4.5),
  ('metinKoyu/neonKoyu', (p) => p.metinKoyu, (p) => p.neonKoyu, 4.5),
  ('metinKoyu/neon', (p) => p.metinKoyu, (p) => p.neon, 4.5),
  (
    'metinKoyuYumusak/neonKoyu',
    (p) => p.metinKoyuYumusak,
    (p) => p.neonKoyu,
    3.0,
  ),
  ('neon/zemin (ikon)', (p) => p.neon, (p) => p.zemin, 3.0),
  // Vurgu KÜÇÜK METİN olarak da kullanılıyor (Yazi.neonKucuk 11 px, Ayarlar
  // bölüm başlıkları, sekme etiketleri) → normal metin eşiği.
  ('neon/zemin (küçük metin)', (p) => p.neon, (p) => p.zemin, 4.5),
  ('neon/yuzey (küçük metin)', (p) => p.neon, (p) => p.yuzey, 4.5),
  // Alt gezinme çubuğu (zeminDerin) seçili sekme ikonu, emoji kategorisi
  ('neon/zeminDerin (ikon)', (p) => p.neon, (p) => p.zeminDerin, 3.0),
  ('neon/yuzey (ikon)', (p) => p.neon, (p) => p.yuzey, 3.0),
  ('tehlike/yuzey', (p) => p.tehlike, (p) => p.yuzey, 3.0),
  ('tehlike/zemin', (p) => p.tehlike, (p) => p.zemin, 3.0),
  (
    'metinTehlikeUstu/tehlikeKoyu',
    (p) => p.metinTehlikeUstu,
    (p) => p.tehlikeKoyu,
    4.5,
  ),
  ('metinKoyu/yesil (avatar harfi)', (p) => p.metinKoyu, (p) => p.yesil, 3.0),
];

void main() {
  // Her testten sonra varsayılana dön — Renkler statik (global) durumdur.
  tearDown(() => Renkler.uygula(RoyPalet.neonLime, pariltiAzalt: false));

  group('kontrastOrani (saf fonksiyon)', () {
    test('siyah/beyaz = 21, aynı renk = 1, sıra önemsiz', () {
      expect(
        kontrastOrani(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        kontrastOrani(const Color(0xFF777777), const Color(0xFF777777)),
        closeTo(1, 0.0001),
      );
      const a = Color(0xFF86AD72), b = Color(0xFF0D2818);
      expect(kontrastOrani(a, b), kontrastOrani(b, a));
    });

    test('rapordaki ölçümle tutarlı (neonLime metinSoluk/yuzey ≈ 6,2)', () {
      expect(
        kontrastOrani(RoyPalet.neonLime.metinSoluk, RoyPalet.neonLime.yuzey),
        closeTo(6.17, 0.05),
      );
      // Eski değer AA altındaydı — düzeltmenin gerekçesi.
      expect(
        kontrastOrani(const Color(0xFF6B8F5A), RoyPalet.neonLime.yuzey),
        lessThan(4.5),
      );
    });
  });

  group('Palet kontrastları (WCAG)', () {
    for (final p in RoyPalet.hepsi) {
      for (final (ad, on, arka, esik) in _ciftler) {
        test('${p.ad}: $ad ≥ $esik', () {
          final oran = kontrastOrani(on(p), arka(p));
          expect(
            oran,
            greaterThanOrEqualTo(esik),
            reason: '${p.ad} $ad = ${oran.toStringAsFixed(2)}',
          );
        });
      }
    }
  });

  group('RoyPalet', () {
    test('5 palet, adlar benzersiz', () {
      expect(RoyPalet.hepsi, hasLength(5));
      expect(RoyPalet.hepsi.map((p) => p.ad).toSet(), hasLength(5));
    });

    test('bul: bilinen ad o paleti, bilinmeyen/null neonLime döner', () {
      for (final p in RoyPalet.hepsi) {
        expect(RoyPalet.bul(p.ad), same(p));
      }
      expect(RoyPalet.bul('yokBoyleTema'), same(RoyPalet.neonLime));
      expect(RoyPalet.bul(''), same(RoyPalet.neonLime));
      expect(RoyPalet.bul(null), same(RoyPalet.neonLime));
    });

    test('yalnız gunIsigi açık', () {
      expect(RoyPalet.hepsi.where((p) => p.acikMi).map((p) => p.ad), [
        'gunIsigi',
      ]);
    });

    test('türetilmiş tonlar vurgudan (neonLime eski sabitlerle aynı)', () {
      const p = RoyPalet.neonLime;
      expect(p.kenar.toARGB32(), 0x24B4FF3C);
      expect(p.kenarGuclu.toARGB32(), 0x2EB4FF3C);
      expect(p.kenarSolgun.toARGB32(), 0x1FB4FF3C);
      expect(p.neonSis.toARGB32(), 0x1FB4FF3C);
      expect(p.secim.toARGB32(), 0x4DB4FF3C);
      // Lavanta'da kenar mor olmalı (vurgudan türediği için)
      expect(
        RoyPalet.lavanta.kenar.toARGB32() & 0xFFFFFF,
        RoyPalet.lavanta.neon.toARGB32() & 0xFFFFFF,
      );
    });

    test('QR renkleri sabit: açık zemin + koyu desen, yüksek kontrast', () {
      expect(
        goreliParlaklik(QrRenkleri.zemin),
        greaterThan(goreliParlaklik(QrRenkleri.desen)),
      );
      expect(
        kontrastOrani(QrRenkleri.zemin, QrRenkleri.desen),
        greaterThanOrEqualTo(7),
      );
      // neonLime'ın eski görünümüyle birebir aynı (regresyon yok)
      expect(QrRenkleri.zemin, RoyPalet.neonLime.metin);
      expect(QrRenkleri.desen, RoyPalet.neonLime.zeminDerin);
    });
  });

  group('Renkler.uygula', () {
    test('sonrası Renkler yeni paletten okunuyor', () {
      expect(Renkler.neon, RoyPalet.neonLime.neon);
      Renkler.uygula(RoyPalet.lavanta);
      expect(Renkler.aktif, same(RoyPalet.lavanta));
      expect(Renkler.neon, RoyPalet.lavanta.neon);
      expect(Renkler.zemin, RoyPalet.lavanta.zemin);
      expect(Renkler.metinKoyu, RoyPalet.lavanta.metinKoyu);
      expect(Gradyanlar.accent.colors, [
        RoyPalet.lavanta.neonAcik,
        RoyPalet.lavanta.neonKoyu,
      ]);
      expect(TemaHex.zemin, '#120f1c');
    });

    test('parıltı azaltınca glow listeleri boş, derinlik gölgesi kalır', () {
      expect(Golgeler.neonGlow, isNotEmpty);
      Renkler.uygula(Renkler.aktif, pariltiAzalt: true);
      expect(Golgeler.neonGlow, isEmpty);
      expect(Golgeler.neonGlowGuclu, isEmpty);
      expect(Golgeler.neonGlowBasili, isEmpty);
      expect(Golgeler.balonNeon, isEmpty);
      expect(Golgeler.tehlikeGlow, isEmpty);
      expect(Golgeler.neonNokta, isEmpty);
      expect(Golgeler.yuzey, isNotEmpty);
      // pariltiAzalt verilmezse önceki tercih korunur
      Renkler.uygula(RoyPalet.amoled);
      expect(Renkler.pariltiAzalt, isTrue);
    });

    test('açık palette siyah gölgeler daha hafif', () {
      final koyu = Golgeler.yuzey.first.color.a;
      Renkler.uygula(RoyPalet.gunIsigi);
      expect(Golgeler.yuzey.first.color.a, lessThan(koyu));
    });

    test('ThemeData ve sistem çubukları parlaklığa uyar', () {
      Renkler.uygula(RoyPalet.gunIsigi);
      final t = AppTema.olustur();
      expect(t.brightness, Brightness.light);
      expect(t.colorScheme.primary, RoyPalet.gunIsigi.neon);
      expect(AppTema.sistemCubuklari.statusBarIconBrightness, Brightness.dark);
      Renkler.uygula(RoyPalet.amoled);
      expect(AppTema.olustur().brightness, Brightness.dark);
      expect(AppTema.sistemCubuklari.statusBarIconBrightness, Brightness.light);
    });

    test('VideoSahne: koyu paletlerde etkin palet, açıkta koyu kalır', () {
      for (final p in RoyPalet.hepsi) {
        Renkler.uygula(p);
        if (p.acikMi) {
          expect(VideoSahne.koyuyaZorla, isTrue, reason: p.ad);
          // Sahne koyu, başlık açık ve okunur
          expect(
            goreliParlaklik(VideoSahne.metin),
            greaterThan(goreliParlaklik(VideoSahne.zemin)),
            reason: p.ad,
          );
          expect(
            kontrastOrani(VideoSahne.metin, VideoSahne.zemin),
            greaterThanOrEqualTo(4.5),
            reason: p.ad,
          );
          expect(
            VideoSahne.sistemCubuklari.statusBarIconBrightness,
            Brightness.light,
          );
        } else {
          // Koyu paletlerde hiçbir şey değişmez
          expect(VideoSahne.koyuyaZorla, isFalse, reason: p.ad);
          expect(VideoSahne.zemin, p.zemin, reason: p.ad);
          expect(VideoSahne.yerTutucu, p.yuzey, reason: p.ad);
          expect(VideoSahne.metin, p.metin, reason: p.ad);
        }
      }
    });

    test('TemaHex.*Icin belirli paletten (arka plan izolatı yolu)', () {
      expect(TemaHex.zeminIcin(RoyPalet.gunIsigi), '#f6faf2');
      expect(TemaHex.neonIcin(RoyPalet.lavanta), '#c9a7ff');
      expect(TemaHex.metinIcin(RoyPalet.yuksekKontrast), '#ffffff');
    });
  });

  group('Ekranlar her palette çiziliyor', () {
    for (final p in RoyPalet.hepsi) {
      for (final azalt in [false, true]) {
        testWidgets(
          'GirisEkrani — ${p.ad}${azalt ? ' (parıltı azaltılmış)' : ''}',
          (tester) async {
            Renkler.uygula(p, pariltiAzalt: azalt);
            await tester.pumpWidget(
              MaterialApp(theme: AppTema.olustur(), home: const GirisEkrani()),
            );
            expect(tester.takeException(), isNull);
            expect(find.text('ROY MESSANGER'), findsOneWidget);
            expect(find.byType(TextField), findsNWidgets(2));
            // Zemin gerçekten paletin zemini
            final scaffold = tester.widget<Scaffold>(
              find.byType(Scaffold).first,
            );
            final zemin =
                scaffold.backgroundColor ??
                Theme.of(
                  tester.element(find.byType(Scaffold).first),
                ).scaffoldBackgroundColor;
            expect(zemin, p.zemin);
          },
        );
      }
    }
  });

  group('Açık/koyu anlam denetimi (widget)', () {
    for (final p in RoyPalet.hepsi) {
      testWidgets('ProfilQrKodu renkleri sabit — ${p.ad}', (tester) async {
        Renkler.uygula(p);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTema.olustur(),
            home: const Scaffold(
              body: Center(child: ProfilQrKodu(kullaniciAdi: 'deneme')),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final qr = tester.widget<QrImageView>(find.byType(QrImageView));
        expect(qr.backgroundColor, QrRenkleri.zemin);
        expect(qr.eyeStyle.color, QrRenkleri.desen);
        expect(qr.dataModuleStyle.color, QrRenkleri.desen);
        // Çerçeve (sessiz bölge) de QR zemini rengi
        final kutu = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(QrImageView),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((kutu.decoration! as BoxDecoration).color, QrRenkleri.zemin);
      });

      testWidgets('Alt gezinme seçili ikonu görünür — ${p.ad}', (tester) async {
        Renkler.uygula(p);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTema.olustur(),
            home: Scaffold(
              // ana_kabuk.dart'taki NavigationBar ayarlarının aynısı
              bottomNavigationBar: ColoredBox(
                color: Renkler.zeminDerin,
                child: NavigationBar(
                  selectedIndex: 0,
                  backgroundColor: Colors.transparent,
                  indicatorColor: Renkler.neonSis,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.forum_outlined),
                      selectedIcon: Icon(Icons.forum),
                      label: 'Sohbetler',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.group_outlined),
                      label: 'Arkadaşlar',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final secili = IconTheme.of(tester.element(find.byIcon(Icons.forum)));
        final secilmemis = IconTheme.of(
          tester.element(find.byIcon(Icons.group_outlined)),
        );
        expect(secili.color, p.neon);
        expect(secilmemis.color, p.metin);
        // Seçili ikon, gösterge (neonSis, zeminDerin üstünde) üstünde ≥ 3:1
        final gosterge = Color.alphaBlend(p.neonSis, p.zeminDerin);
        expect(
          kontrastOrani(secili.color!, gosterge),
          greaterThanOrEqualTo(3),
          reason: '${p.ad} = ${kontrastOrani(secili.color!, gosterge)}',
        );
      });

      testWidgets('IcIsik alt gölgesi palete göre — ${p.ad}', (tester) async {
        Renkler.uygula(p);
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: IcIsik(kose: Kose.dugme, guclu: false),
          ),
        );
        final kutu = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(IcIsik),
            matching: find.byType(DecoratedBox),
          ),
        );
        final gradyan =
            (kutu.decoration as BoxDecoration).gradient! as LinearGradient;
        // neonLime'da eski değer (0,28) korunur; açıkta golgeGucu ile hafif
        expect(gradyan.colors.last.a, closeTo(0.28 * p.golgeGucu, 0.005));
      });

      testWidgets('Ayarlar tema seçici çiziliyor — ${p.ad}', (tester) async {
        SharedPreferences.setMockInitialValues({AyarServisi.anahtarTema: p.ad});
        await AyarServisi.instance.baslat();
        expect(Renkler.aktif, same(p));
        await tester.pumpWidget(
          MaterialApp(theme: AppTema.olustur(), home: const AyarlarEkrani()),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final q in RoyPalet.hepsi) {
          expect(find.text(q.gorunenAd), findsOneWidget);
        }
        // Bölüm başlığı etkin paletin vurgusuyla
        expect(
          tester.widget<Text>(find.text('GÖRÜNÜM')).style?.color,
          p.neon,
        );
      });
    }
  });

  group('tumAgaciYenidenCiz', () {
    testWidgets('statik okuyan widget yeni paleti alır, yığın korunur', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const _RenkKutusu(anahtar: 'ana'),
        ),
      );
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _RenkKutusu(anahtar: 'ikinci'),
        ),
      );
      await tester.pumpAndSettle();

      Color renk(String a) => (tester
          .widget<ColoredBox>(
            find.byKey(ValueKey('kutu-$a'), skipOffstage: false),
          )
          .color);
      expect(renk('ikinci'), RoyPalet.neonLime.neon);

      Renkler.uygula(RoyPalet.lavanta);
      await tester.pump();
      // Yeniden çizim tetiklenmeden statik okuma güncellenmez (gerekçe)
      expect(renk('ikinci'), RoyPalet.neonLime.neon);

      tumAgaciYenidenCiz();
      await tester.pump();
      expect(renk('ikinci'), RoyPalet.lavanta.neon);
      // Arka plandaki (offstage) rota da güncellendi ve yığın yerinde
      expect(renk('ana'), RoyPalet.lavanta.neon);
      expect(navKey.currentState!.canPop(), isTrue);
    });
  });

  group('AyarServisi tema kalıcılığı', () {
    test('baslat kayıtlı paleti Renkler\'e uygular', () async {
      SharedPreferences.setMockInitialValues({
        AyarServisi.anahtarTema: 'lavanta',
        AyarServisi.anahtarParilti: false,
      });
      await AyarServisi.instance.baslat();
      expect(AyarServisi.instance.tema.value, 'lavanta');
      expect(AyarServisi.instance.parilti.value, isFalse);
      expect(Renkler.aktif, same(RoyPalet.lavanta));
      expect(Renkler.pariltiAzalt, isTrue);
    });

    test('bozuk kayıt → neonLime', () async {
      SharedPreferences.setMockInitialValues({AyarServisi.anahtarTema: 'eski'});
      await AyarServisi.instance.baslat();
      expect(AyarServisi.instance.tema.value, 'neonLime');
      expect(await AyarServisi.temaDiskten(), 'neonLime');
    });

    test('temaAyarla: dinleyici çağrıldığında Renkler zaten yeni', () async {
      SharedPreferences.setMockInitialValues({});
      await AyarServisi.instance.baslat();
      Color? dinleyicideGorulen;
      void dinle() => dinleyicideGorulen = Renkler.neon;
      AyarServisi.instance.tema.addListener(dinle);
      addTearDown(() => AyarServisi.instance.tema.removeListener(dinle));

      await AyarServisi.instance.temaAyarla('gunIsigi');
      expect(dinleyicideGorulen, RoyPalet.gunIsigi.neon);
      expect(await AyarServisi.temaDiskten(), 'gunIsigi');

      await AyarServisi.instance.pariltiAyarla(false);
      expect(Renkler.pariltiAzalt, isTrue);
      expect(Renkler.aktif, same(RoyPalet.gunIsigi)); // palet korunur
    });
  });
}

/// Renk'i `Renkler.neon`'dan STATİK okuyan test widget'ı (ekranlardaki gibi).
class _RenkKutusu extends StatelessWidget {
  final String anahtar;
  const _RenkKutusu({required this.anahtar});

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: ValueKey('kutu-$anahtar'),
    color: Renkler.neon,
    child: const SizedBox.expand(),
  );
}
