import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// =====================================================================
///  MERKEZİ TASARIM DOSYASI — "İmza Karışım" (1c)
///  Neon-lime / derin yeşil cam dili (+ seçilebilir paletler).
///
///  Uygulamadaki TÜM renk, gradient, gölge, köşe ve tipografi değerleri
///  BURADADIR. Hiçbir ekranda hardcoded renk/stil olmamalı.
///  Değiştirmek istersen SADECE burayı düzenle.
///
///  ÇALIŞMA ANINDA TEMA (bkz. docs/ANALIZ_RAPORU.md §3):
///  Renkler bir [RoyPalet]'ten okunur ([Renkler.uygula] ile değişir).
///  ⚠️ Rapor `context.renk.x` (ThemeExtension) öneriyordu; ama bu ~200
///  çağrı noktasının elle çevrilmesi demekti. Bunun yerine `Renkler.x`
///  adları KORUNDU, yalnız `static const` → `static get` oldu. Bedeli:
///  `const` bağlamlarda kullanılamazlar ve tema değişince ağacın elle
///  yeniden çizilmesi gerekir (main.dart `_tumAgaciYenidenCiz`).
/// =====================================================================

/// Bir renk paletinin TAMAMI. Değişmezdir; uygulamada hangisinin etkin
/// olduğu [Renkler.aktif]'te tutulur.
///
/// Türetilmiş şeffaf tonlar (kenar, sis, seçim, glow) alan olarak değil
/// [neon]'dan HESAPLANAN getter olarak verilir → yeni palet = temel renkler;
/// şeffaflık oranları tüm paletlerde aynı kalır.
@immutable
class RoyPalet {
  const RoyPalet({
    required this.ad,
    required this.gorunenAd,
    required this.parlaklik,
    required this.zemin,
    required this.zeminDerin,
    required this.yuzey,
    required this.yuzeyYuksek,
    required this.balonGelen,
    required this.balonGelenUst,
    required this.neon,
    required this.neonAcik,
    required this.neonKoyu,
    required this.yesil,
    required this.yesilKoyu,
    required this.yesilAcik,
    required this.yesilOrta,
    required this.metin,
    required this.metinSoluk,
    required this.metinKoyu,
    required this.metinKoyuYumusak,
    required this.tehlike,
    required this.tehlikeAcik,
    required this.tehlikeKoyu,
    required this.metinTehlikeUstu,
    required this.cizgi,
    this.golgeGucu = 1,
    this.kenarGucu = 1,
  });

  /// Kalıcı kimlik (SharedPreferences'a yazılan değer). DEĞİŞTİRME —
  /// değişirse kullanıcının seçimi kaybolur ve varsayılana düşer.
  final String ad;

  /// Ayarlar'da görünen ad.
  final String gorunenAd;

  /// Açık mı koyu mu → ThemeData tabanı, sistem çubuğu ikonları, gölge gücü.
  final Brightness parlaklik;

  // --- Zemin & yüzeyler ---
  /// Ana arka plan (ekran zemini)
  final Color zemin;

  /// "Gömülü" ton — alt gezinme çubuğu, arama ekranı, boş kutu dolgusu.
  /// Koyu paletlerde zeminden KOYU, açık palette zeminden bir tık koyu gri-yeşil.
  final Color zeminDerin;

  /// Kart / panel / appbar / giriş kutusu yüzeyi
  final Color yuzey;

  /// Yükseltilmiş yüzey (gradient üst tonu)
  final Color yuzeyYuksek;

  /// Karşı tarafın mesaj balonu — zeminden NET ayrışsın diye yüzeyden
  /// bir tık farklı (cihazda balonlar zemine karışıyordu).
  final Color balonGelen;
  final Color balonGelenUst; // gradient üst tonu

  // --- Vurgu (adı tarihsel olarak "neon"; lavanta palette mor) ---
  /// Ana vurgu (ikon, aktif durum, çevrimiçi noktası)
  final Color neon;
  final Color neonAcik; // gradient açık ucu
  final Color neonKoyu; // gradient koyu ucu

  /// İkincil tonlar (avatar/rozet çeşitliliği). Adı "yeşil" ama palete göre
  /// vurgunun ailesidir (lavanta'da mor). Üstüne [metinKoyu] yazılır.
  final Color yesil;
  final Color yesilKoyu;
  final Color yesilAcik;
  final Color yesilOrta;

  // --- Metin ---
  /// Birincil metin (zemin/yüzey/balon üstü)
  final Color metin;

  /// İkincil / soluk metin (alt yazı, zaman damgası — AA ≥ 4,5 test edilir)
  final Color metinSoluk;

  /// VURGU ÜSTÜ metin (neon buton/balon üstü). ⚠️ Adı "koyu" ama anlamı
  /// "vurgunun üstündeki kontrast renk": açık palette vurgu koyu yeşil
  /// olduğu için bu BEYAZDIR. Ad, 200 çağrı noktası bozulmasın diye korundu.
  final Color metinKoyu;

  /// Vurgu üstü ikincil metin (neon balondaki zaman damgası)
  final Color metinKoyuYumusak;

  // --- Durum ---
  final Color tehlike;

  /// Kırmızı (kapat/reddet) düğme gradyanının uçları
  final Color tehlikeAcik;
  final Color tehlikeKoyu;

  /// Kırmızı (tehlike) buton üstündeki metin/ikon
  final Color metinTehlikeUstu;
  final Color cizgi;

  /// Siyah derinlik gölgelerinin çarpanı. Açık zeminde %40'lık siyah gölge
  /// kirli/çamurlu görünür → açık palette düşürülür.
  final double golgeGucu;

  /// Vurgu-tonlu kenarlıkların opaklık çarpanı (yüksek kontrastta güçlü).
  final double kenarGucu;

  bool get acikMi => parlaklik == Brightness.light;

  static Color _alfa(Color c, int a) =>
      c.withValues(alpha: (a / 255).clamp(0.0, 1.0));

  // --- Türetilmiş şeffaf tonlar (vurgudan) ---
  Color get kenar => _alfa(neon, (0x24 * kenarGucu).round()); // ~%14
  Color get kenarGuclu => _alfa(neon, (0x2E * kenarGucu).round()); // ~%18
  Color get kenarSolgun => _alfa(neon, (0x1F * kenarGucu).round()); // ~%12

  /// Neon'un şeffaf tonu (ikon kutusu dolgusu vb.)
  Color get neonSis => _alfa(neon, 0x1F); // ~%12

  /// Metin seçimi vurgusu
  Color get secim => _alfa(neon, 0x4D); // ~%30

  // ===================================================================
  //  PALETLER — değerler ANALIZ_RAPORU §3.3; kontrastlar test/tema_test.dart
  // ===================================================================

  /// Varsayılan kimlik. Tek fark: metinSoluk #6B8F5A → #86AD72
  /// (yüzeyde 4,27 / balonda 3,65 ile AA altındaydı; şimdi 6,2 / 5,3).
  /// tehlikeKoyu #D93A3A → #C62828: üstündeki açık metin 4,17 → 5,15.
  static const RoyPalet neonLime = RoyPalet(
    ad: 'neonLime',
    gorunenAd: 'Neon Lime',
    parlaklik: Brightness.dark,
    zemin: Color(0xFF071A10),
    zeminDerin: Color(0xFF050F0A),
    yuzey: Color(0xFF0D2818),
    yuzeyYuksek: Color(0xFF14301E),
    balonGelen: Color(0xFF16351F),
    balonGelenUst: Color(0xFF1D4027),
    neon: Color(0xFFB4FF3C),
    neonAcik: Color(0xFFD4FF5C),
    neonKoyu: Color(0xFFA8E02A),
    yesil: Color(0xFF63B81A),
    yesilKoyu: Color(0xFF3F7A10),
    yesilAcik: Color(0xFF8FE63C),
    yesilOrta: Color(0xFF5AA314),
    metin: Color(0xFFEAFFD8),
    metinSoluk: Color(0xFF86AD72),
    metinKoyu: Color(0xFF06170D),
    metinKoyuYumusak: Color(0xFF1A3D0D),
    tehlike: Color(0xFFFF5A5A),
    tehlikeAcik: Color(0xFFFF7B7B),
    tehlikeKoyu: Color(0xFFC62828),
    metinTehlikeUstu: Color(0xFFFFF2F2),
    cizgi: Color(0xFF14301E),
  );

  /// OLED ekranda siyah piksel kapalıdır → pil tasarrufu, gece kullanımı.
  static const RoyPalet amoled = RoyPalet(
    ad: 'amoled',
    gorunenAd: 'AMOLED Gece',
    parlaklik: Brightness.dark,
    zemin: Color(0xFF000000),
    zeminDerin: Color(0xFF000000),
    yuzey: Color(0xFF0B0F0C),
    yuzeyYuksek: Color(0xFF121A14),
    balonGelen: Color(0xFF141A16),
    balonGelenUst: Color(0xFF1B241D),
    neon: Color(0xFFB4FF3C),
    neonAcik: Color(0xFFD4FF5C),
    neonKoyu: Color(0xFFA8E02A),
    yesil: Color(0xFF63B81A),
    yesilKoyu: Color(0xFF3F7A10),
    yesilAcik: Color(0xFF8FE63C),
    yesilOrta: Color(0xFF5AA314),
    metin: Color(0xFFE8F5E0),
    metinSoluk: Color(0xFF8FA888),
    metinKoyu: Color(0xFF06170D),
    metinKoyuYumusak: Color(0xFF1A3D0D),
    tehlike: Color(0xFFFF5A5A),
    tehlikeAcik: Color(0xFFFF7B7B),
    tehlikeKoyu: Color(0xFFC62828),
    metinTehlikeUstu: Color(0xFFFFF2F2),
    cizgi: Color(0xFF151D17),
  );

  /// AÇIK tema — dış mekân / güneş altında okunabilirlik.
  /// ⚠️ Vurgu koyu yeşil → vurgu üstü metin ([metinKoyu]) BEYAZ.
  /// tehlike #FF5A5A beyazda 3,0 sınırındaydı → #C62828.
  static const RoyPalet gunIsigi = RoyPalet(
    ad: 'gunIsigi',
    gorunenAd: 'Gün Işığı',
    parlaklik: Brightness.light,
    zemin: Color(0xFFF6FAF2),
    zeminDerin: Color(0xFFE8F0E1),
    yuzey: Color(0xFFFFFFFF),
    yuzeyYuksek: Color(0xFFFFFFFF),
    balonGelen: Color(0xFFE6F0DF),
    balonGelenUst: Color(0xFFEEF5E8),
    neon: Color(0xFF3F7A10),
    neonAcik: Color(0xFF4A8418),
    neonKoyu: Color(0xFF336A0C),
    yesil: Color(0xFF4E7F2A),
    yesilKoyu: Color(0xFF2F5A12),
    yesilAcik: Color(0xFF5E9632),
    yesilOrta: Color(0xFF487A22),
    metin: Color(0xFF0F2416),
    metinSoluk: Color(0xFF4F6B45),
    metinKoyu: Color(0xFFFFFFFF),
    metinKoyuYumusak: Color(0xFFE3F2D6),
    tehlike: Color(0xFFC62828),
    tehlikeAcik: Color(0xFFE05252),
    tehlikeKoyu: Color(0xFFB71C1C),
    metinTehlikeUstu: Color(0xFFFFFFFF),
    cizgi: Color(0xFFDCE6D5),
    golgeGucu: 0.35,
  );

  /// Yaşlı / az gören aile üyeleri: saf siyah + saf beyaz, güçlü kenarlık.
  static const RoyPalet yuksekKontrast = RoyPalet(
    ad: 'yuksekKontrast',
    gorunenAd: 'Yüksek Kontrast',
    parlaklik: Brightness.dark,
    zemin: Color(0xFF000000),
    zeminDerin: Color(0xFF000000),
    yuzey: Color(0xFF0A0A0A),
    yuzeyYuksek: Color(0xFF141414),
    balonGelen: Color(0xFF1A1A1A),
    balonGelenUst: Color(0xFF222222),
    neon: Color(0xFFD4FF5C),
    neonAcik: Color(0xFFE4FF8F),
    neonKoyu: Color(0xFFC2F03A),
    yesil: Color(0xFF8FE63C),
    yesilKoyu: Color(0xFF6BBF1F),
    yesilAcik: Color(0xFFB4FF3C),
    yesilOrta: Color(0xFF7FD62E),
    metin: Color(0xFFFFFFFF),
    metinSoluk: Color(0xFFC8D6C2),
    metinKoyu: Color(0xFF000000),
    metinKoyuYumusak: Color(0xFF1F3300),
    tehlike: Color(0xFFFF6B6B),
    tehlikeAcik: Color(0xFFFF8A8A),
    tehlikeKoyu: Color(0xFFB71C1C),
    metinTehlikeUstu: Color(0xFFFFFFFF),
    cizgi: Color(0xFF3A3A3A),
    kenarGucu: 2,
  );

  /// Kişiselleştirme — mor vurgulu koyu tema.
  static const RoyPalet lavanta = RoyPalet(
    ad: 'lavanta',
    gorunenAd: 'Lavanta Gece',
    parlaklik: Brightness.dark,
    zemin: Color(0xFF120F1C),
    zeminDerin: Color(0xFF0C0A14),
    yuzey: Color(0xFF1C1830),
    yuzeyYuksek: Color(0xFF241F3B),
    balonGelen: Color(0xFF262040),
    balonGelenUst: Color(0xFF2E2750),
    neon: Color(0xFFC9A7FF),
    neonAcik: Color(0xFFDCC6FF),
    neonKoyu: Color(0xFFB08CF2),
    yesil: Color(0xFF9C7FE6),
    yesilKoyu: Color(0xFF7458C4),
    yesilAcik: Color(0xFFB89CF5),
    yesilOrta: Color(0xFF8A6BD9),
    metin: Color(0xFFF1ECFF),
    metinSoluk: Color(0xFFA79BC9),
    metinKoyu: Color(0xFF1A0F33),
    metinKoyuYumusak: Color(0xFF3A2766),
    tehlike: Color(0xFFFF6B81),
    tehlikeAcik: Color(0xFFFF8A9B),
    tehlikeKoyu: Color(0xFFC2304A),
    metinTehlikeUstu: Color(0xFFFFF2F4),
    cizgi: Color(0xFF241F3B),
  );

  /// Ayarlar'daki sıra.
  static const List<RoyPalet> hepsi = [
    neonLime,
    amoled,
    gunIsigi,
    yuksekKontrast,
    lavanta,
  ];

  /// [ad]'a karşılık gelen palet; bilinmeyen/boş ad → [neonLime]
  /// (eski sürümden kalan ya da elle bozulmuş kayıt uygulamayı çökertmesin).
  static RoyPalet bul(String? ad) {
    for (final p in hepsi) {
      if (p.ad == ad) return p;
    }
    return neonLime;
  }
}

/// Etkin paletin renkleri. Eskiden `static const` idi; şimdi [aktif]
/// paletten okunan getter'lar → tüm ekranlar ad değişmeden temaya uyar.
/// ⚠️ `const` bağlamda (const Icon(color: Renkler.neon) gibi) KULLANILAMAZ.
class Renkler {
  Renkler._();

  static RoyPalet _aktif = RoyPalet.neonLime;
  static bool _pariltiAzalt = false;

  /// Şu an uygulanan palet.
  static RoyPalet get aktif => _aktif;

  /// "Neon parıltısını azalt" açık mı (Golgeler glow'ları söner).
  static bool get pariltiAzalt => _pariltiAzalt;

  /// Paleti (ve istenirse parıltı tercihini) değiştirir.
  /// ⚠️ Bu yalnız DEĞERLERİ değiştirir; ekranlar statik okuduğu için
  /// ağacın yeniden çizilmesi çağıranın işidir (main.dart).
  static void uygula(RoyPalet p, {bool? pariltiAzalt}) {
    _aktif = p;
    if (pariltiAzalt != null) _pariltiAzalt = pariltiAzalt;
  }

  static Brightness get parlaklik => _aktif.parlaklik;
  static bool get acikMi => _aktif.acikMi;

  // --- Zemin & yüzeyler ---
  static Color get zemin => _aktif.zemin;
  static Color get zeminDerin => _aktif.zeminDerin;
  static Color get yuzey => _aktif.yuzey;
  static Color get yuzeyYuksek => _aktif.yuzeyYuksek;
  static Color get balonGelen => _aktif.balonGelen;
  static Color get balonGelenUst => _aktif.balonGelenUst;

  // --- Kenarlıklar (vurgunun düşük opaklıkları) ---
  static Color get kenar => _aktif.kenar;
  static Color get kenarGuclu => _aktif.kenarGuclu;
  static Color get kenarSolgun => _aktif.kenarSolgun;

  // --- Vurgu ---
  static Color get neon => _aktif.neon;
  static Color get neonAcik => _aktif.neonAcik;
  static Color get neonKoyu => _aktif.neonKoyu;
  static Color get yesil => _aktif.yesil;
  static Color get yesilKoyu => _aktif.yesilKoyu;
  static Color get yesilAcik => _aktif.yesilAcik;
  static Color get yesilOrta => _aktif.yesilOrta;
  static Color get neonSis => _aktif.neonSis;
  static Color get secim => _aktif.secim;

  // --- Metin ---
  static Color get metin => _aktif.metin;
  static Color get metinSoluk => _aktif.metinSoluk;

  /// VURGU ÜSTÜ metin (bkz. [RoyPalet.metinKoyu] — açık palette beyaz).
  static Color get metinKoyu => _aktif.metinKoyu;
  static Color get metinKoyuYumusak => _aktif.metinKoyuYumusak;

  // --- Durum ---
  static Color get tehlike => _aktif.tehlike;
  static Color get tehlikeAcik => _aktif.tehlikeAcik;
  static Color get tehlikeKoyu => _aktif.tehlikeKoyu;
  static Color get metinTehlikeUstu => _aktif.metinTehlikeUstu;
  static Color get cizgi => _aktif.cizgi;
}

/// QR kodu renkleri — BİLEREK palete bağlı DEĞİL (sabit).
///
/// ⚠️ Tarayıcılar KOYU modül + AÇIK zemin bekler; ters (açık desen / koyu
/// zemin) QR'ı birçok kamera uygulaması hiç okumaz. Paletten türetmek
/// (ör. eski `metin` zemin + `zeminDerin` desen) açık temada QR'ı TERS
/// çevirirdi; bir sonraki palet de aynı tuzağa düşebilir → renkler her
/// temada aynıdır. Değerler neonLime'ın eski görünümüyle birebir aynı
/// (açık yeşilimsi beyaz #EAFFD8 + neredeyse siyah #050F0A, kontrast ≈ 18:1),
/// yani varsayılan temada görsel değişiklik yok.
class QrRenkleri {
  QrRenkleri._();

  /// QR zemini ve sessiz bölge (her zaman AÇIK)
  static const Color zemin = Color(0xFFEAFFD8);

  /// QR modülleri ve göz kareleri (her zaman KOYU)
  static const Color desen = Color(0xFF050F0A);
}

/// Görüntülü arama sahnesi (uzak video + üstündeki bindirmeler).
///
/// ⚠️ Kamera görüntüsü temayı bilmez: video üstündeki başlık yazısı ve
/// video gelmeden önceki sahne zemini AÇIK temada da KOYU kalmalı (açık
/// temada koyu başlık rastgele bir videonun üstünde kaybolur; video
/// bağlanmadan önce açık zemin + açık-yazı çiftine de düşülemez).
/// Koyu paletlerde etkin paletin kendisi kullanılır → neonLime/AMOLED/
/// lavanta/yüksek kontrastta hiçbir şey değişmez. Açık palette sahne
/// varsayılan koyu paletten (neonLime) okunur.
class VideoSahne {
  VideoSahne._();

  static RoyPalet get _p => Renkler.acikMi ? RoyPalet.neonLime : Renkler.aktif;

  /// Sahne koyu mu zorlanıyor (yalnız açık palette true).
  static bool get koyuyaZorla => Renkler.acikMi;

  /// Video gelmeden önceki uzak görüntü zemini
  static Color get zemin => _p.zemin;

  /// Kendi görüntün hazır olmadan önceki küçük kutu
  static Color get yerTutucu => _p.yuzey;

  /// Video üstündeki başlık (karşı tarafın adı)
  static Color get metin => _p.metin;

  /// Sistem çubukları: video üstünde her zaman AÇIK ikon.
  static SystemUiOverlayStyle get sistemCubuklari =>
      AppTema.sistemCubuklari.copyWith(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: zemin,
        systemNavigationBarIconBrightness: Brightness.light,
      );
}

/// Native katmanlara (CallKit gelen arama ekranı gibi) verilecek renkler.
/// Onlar `#RRGGBB` string ister → değerler yine palet'ten türetilir,
/// böylece hiçbir yerde hardcoded hex olmaz.
class TemaHex {
  TemaHex._();

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Gelen arama ekranı zemini
  static String get zemin => zeminIcin(Renkler.aktif);

  /// Kabul/aksiyon rengi (neon)
  static String get neon => neonIcin(Renkler.aktif);

  /// Metin rengi
  static String get metin => metinIcin(Renkler.aktif);

  // ⚠️ Belirli bir paletten — ARKA PLAN izolatında [Renkler.aktif] her zaman
  // varsayılandır (AyarServisi.baslat çalışmaz); orada palet diskten okunur
  // (AyarServisi.temaDiskten) ve bu sürümler kullanılır.
  static String zeminIcin(RoyPalet p) => _hex(p.zemin);
  static String neonIcin(RoyPalet p) => _hex(p.neon);
  static String metinIcin(RoyPalet p) => _hex(p.metin);
}

/// Gradientler. Tasarımdaki 145° ≈ topLeft → bottomRight.
/// Etkin paletten her okumada yeniden kurulur (getter).
class Gradyanlar {
  Gradyanlar._();

  static const Alignment _bas = Alignment.topLeft;
  static const Alignment _son = Alignment.bottomRight;

  static LinearGradient _iki(Color a, Color b) =>
      LinearGradient(begin: _bas, end: _son, colors: [a, b]);

  /// Ana neon dolgu (butonlar, kendi mesaj balonun, aktif kartlar)
  static LinearGradient get accent => _iki(Renkler.neonAcik, Renkler.neonKoyu);

  /// Koyu yeşil dolgu (avatar, ikincil rozet)
  static LinearGradient get yesil => _iki(Renkler.yesil, Renkler.yesilKoyu);

  /// Açık yeşil dolgu (çeşitlilik)
  static LinearGradient get yesilAcik =>
      _iki(Renkler.yesilAcik, Renkler.yesilOrta);

  /// Yüzey kartı dolgusu (hafif hacim)
  static LinearGradient get yuzey => _iki(Renkler.yuzeyYuksek, Renkler.yuzey);

  /// Karşı tarafın balonu — zeminden ayrışan, hafif hacimli yüzey
  static LinearGradient get balonGelen =>
      _iki(Renkler.balonGelenUst, Renkler.balonGelen);

  /// Kırmızı (kapat/reddet) düğme dolgusu
  static LinearGradient get tehlike =>
      _iki(Renkler.tehlikeAcik, Renkler.tehlikeKoyu);

  /// Ekran zemininin üstündeki yumuşak neon parlaması.
  /// [hiza] ile parlamanın yeri değiştirilebilir.
  /// "Parıltıyı azalt" açıkken parlama söner (tamamen şeffaf).
  static RadialGradient zeminParlama({
    Alignment hiza = const Alignment(-0.5, -1),
  }) {
    final n = Renkler.neon;
    return RadialGradient(
      center: hiza,
      radius: 1.1,
      colors: [
        n.withValues(alpha: Renkler.pariltiAzalt ? 0 : 0x17 / 255),
        n.withValues(alpha: 0),
      ],
      stops: const [0, 0.55],
    );
  }
}

/// Organik köşeler — bir köşe kısa bırakılır (tasarımın imzası).
class Kose {
  Kose._();

  static const double kucuk = 6;
  static const double orta = 16;
  static const double buyuk = 20;
  static const double kart = 24;

  /// Kendi mesaj balonun (sağ alt köşe kısa)
  static const BorderRadius balonBen = BorderRadius.only(
    topLeft: Radius.circular(buyuk),
    topRight: Radius.circular(buyuk),
    bottomRight: Radius.circular(kucuk),
    bottomLeft: Radius.circular(buyuk),
  );

  /// Karşı tarafın balonu (sol alt köşe kısa)
  static const BorderRadius balonKarsi = BorderRadius.only(
    topLeft: Radius.circular(buyuk),
    topRight: Radius.circular(buyuk),
    bottomRight: Radius.circular(buyuk),
    bottomLeft: Radius.circular(kucuk),
  );

  /// Kart (sol alt köşe kısa)
  static const BorderRadius kartKose = BorderRadius.only(
    topLeft: Radius.circular(kart),
    topRight: Radius.circular(kart),
    bottomRight: Radius.circular(kart),
    bottomLeft: Radius.circular(8),
  );

  /// Buton / avatar (sağ alt köşe kısa)
  static const BorderRadius dugme = BorderRadius.only(
    topLeft: Radius.circular(orta),
    topRight: Radius.circular(orta),
    bottomRight: Radius.circular(kucuk),
    bottomLeft: Radius.circular(orta),
  );

  /// Balon İÇİNDEKİ medyanın köşesi — balonun organik köşesiyle uyumlu
  /// (balon yarıçapı − iç boşluk). Sağ alt köşe kısa.
  static const BorderRadius medyaBen = BorderRadius.only(
    topLeft: Radius.circular(orta),
    topRight: Radius.circular(orta),
    bottomRight: Radius.circular(4),
    bottomLeft: Radius.circular(orta),
  );

  /// Karşı tarafın balonundaki medya — sol alt köşe kısa.
  static const BorderRadius medyaKarsi = BorderRadius.only(
    topLeft: Radius.circular(orta),
    topRight: Radius.circular(orta),
    bottomRight: Radius.circular(orta),
    bottomLeft: Radius.circular(4),
  );

  /// Giriş alanı / arama kutusu (yumuşak, eşit)
  static const BorderRadius alan = BorderRadius.all(Radius.circular(buyuk));

  /// Panel / sayfa üstü
  static const BorderRadius panel = BorderRadius.vertical(
    top: Radius.circular(kart),
  );
}

/// Gölgeler — dış glow ve derinlik.
/// Glow renkleri vurgudan (alfa ile) türetilir; siyah derinlik gölgeleri
/// palet'in [RoyPalet.golgeGucu]'yle ölçeklenir (açık temada hafif).
/// "Neon parıltısını azalt" ([Renkler.pariltiAzalt]) açıkken glow listeleri
/// BOŞ döner — göz yorgunluğu için (cihazda balon glow'u zaten bu sebeple
/// azaltılmıştı); derinlik gölgeleri kalır (hiyerarşi bozulmasın).
class Golgeler {
  Golgeler._();

  static const List<BoxShadow> _yok = [];

  static List<BoxShadow> _glow(Color renk, int alfa, double blur, double dy) =>
      Renkler.pariltiAzalt
          ? _yok
          : [
              BoxShadow(
                color: renk.withValues(alpha: alfa / 255),
                blurRadius: blur,
                offset: Offset(0, dy),
              ),
            ];

  static List<BoxShadow> _derin(int alfa, double blur, double dy) => [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: (alfa / 255 * Renkler.aktif.golgeGucu).clamp(0.0, 1.0),
          ),
          blurRadius: blur,
          offset: Offset(0, dy),
        ),
      ];

  /// Neon glow (accent BUTONLAR — eylem çağrısı)
  static List<BoxShadow> get neonGlow => _glow(Renkler.neon, 0x40, 14, 4);

  /// Mesaj balonu için ÇOK HAFİF glow.
  /// Cihazda her balon ışık saçıp göz yoruyordu; balonlar sohbet listesinde
  /// yan yana geldiği için buradaki parlama minimum tutulur.
  /// (Gelen balonlarda glow YOK — bkz. [balonGelen].)
  static List<BoxShadow> get balonNeon => _glow(Renkler.neon, 0x1A, 8, 2);

  /// Gelen balon — neon glow YOK, sadece hafif derinlik gölgesi
  static List<BoxShadow> get balonGelen => _derin(0x40, 10, 3);

  /// Basılıyken kısılmış glow (gömülme hissi)
  static List<BoxShadow> get neonGlowBasili => _glow(Renkler.neon, 0x2E, 8, 2);

  /// Güçlü neon glow (arama kabul, ana eylem)
  static List<BoxShadow> get neonGlowGuclu => _glow(Renkler.neon, 0x66, 22, 8);

  /// Koyu yüzey derinliği
  static List<BoxShadow> get yuzey => _derin(0x66, 20, 6);

  /// Balon derinliği
  static List<BoxShadow> get balon => _derin(0x59, 16, 6);

  /// Kırmızı (kapat/reddet) glow
  static List<BoxShadow> get tehlikeGlow => _glow(Renkler.tehlike, 0x59, 18, 5);

  /// Çevrimiçi/okunmadı noktasının parıltısı
  static List<BoxShadow> get neonNokta => Renkler.pariltiAzalt
      ? _yok
      : [BoxShadow(color: Renkler.neon.withValues(alpha: 0xB3 / 255), blurRadius: 8)];
}

/// Tipografi — Manrope. Değişken font olduğu için ağırlık hem [fontWeight]
/// hem de [FontVariation] ile veriliyor (kesin uygulansın diye).
class Yazi {
  Yazi._();

  static TextStyle stil(
    double boyut,
    FontWeight agirlik,
    Color renk, {
    double? satir,
    double? aralik,
  }) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: boyut,
        fontWeight: agirlik,
        fontVariations: [FontVariation('wght', agirlik.value.toDouble())],
        color: renk,
        height: satir,
        letterSpacing: aralik,
      );

  /// Ekran başlığı (Sohbetler)
  static TextStyle get baslik =>
      stil(26, FontWeight.w800, Renkler.metin, aralik: -0.3);

  /// Bölüm/AppBar başlığı
  static TextStyle get baslikOrta => stil(18, FontWeight.w800, Renkler.metin);

  /// Kişi adı / satır başlığı
  static TextStyle get isim => stil(16, FontWeight.w700, Renkler.metin);

  /// Mesaj gövdesi (koyu balon)
  static TextStyle get govde =>
      stil(14, FontWeight.w500, Renkler.metin, satir: 1.4);

  /// Mesaj gövdesi (neon balon üstü)
  static TextStyle get govdeAccent =>
      stil(14, FontWeight.w600, Renkler.metinKoyu, satir: 1.4);

  /// İkincil / açıklama
  static TextStyle get kucuk => stil(12, FontWeight.w500, Renkler.metinSoluk);

  /// Etiket (rozet, sekme)
  static TextStyle get etiket => stil(13, FontWeight.w700, Renkler.metin);

  /// Zaman damgası (koyu balon)
  static TextStyle get zaman => stil(10, FontWeight.w500, Renkler.metinSoluk);

  /// Zaman damgası (neon balon üstü)
  static TextStyle get zamanAccent =>
      stil(10, FontWeight.w500, Renkler.metinKoyuYumusak);

  /// Buton yazısı (neon üstü)
  static TextStyle get dugme =>
      stil(15, FontWeight.w800, Renkler.metinKoyu, aralik: 0.2);

  /// Çevrimiçi / neon vurgulu küçük yazı
  static TextStyle get neonKucuk => stil(11, FontWeight.w700, Renkler.neon);
}

/// Sık kullanılan kutu süslemeleri (dekorasyon reçeteleri).
class Kutular {
  Kutular._();

  /// Cam/koyu yüzey paneli (kenarlıklı)
  static BoxDecoration yuzey({
    BorderRadius? kose,
    bool kenarli = true,
    List<BoxShadow>? golge,
  }) =>
      BoxDecoration(
        gradient: Gradyanlar.yuzey,
        borderRadius: kose ?? Kose.alan,
        border: kenarli ? Border.all(color: Renkler.kenar) : null,
        boxShadow: golge,
      );

  /// Düz koyu yüzey (liste satırı, giriş alanı)
  static BoxDecoration duzYuzey({
    BorderRadius? kose,
    bool kenarli = false,
  }) =>
      BoxDecoration(
        color: Renkler.yuzey,
        borderRadius: kose ?? Kose.alan,
        border: kenarli ? Border.all(color: Renkler.kenarGuclu) : null,
      );

  /// Neon accent dolgu + glow (kendi balonun, aktif kart)
  static BoxDecoration accent({BorderRadius? kose, List<BoxShadow>? golge}) =>
      BoxDecoration(
        gradient: Gradyanlar.accent,
        borderRadius: kose ?? Kose.dugme,
        boxShadow: golge ?? Golgeler.neonGlow,
      );

  /// Neon noktası (çevrimiçi / okunmadı)
  static BoxDecoration neonNokta() => BoxDecoration(
        color: Renkler.neon,
        shape: BoxShape.circle,
        boxShadow: Golgeler.neonNokta,
      );
}

/// Accent yüzeylerin üstüne konan iç highlight/gölge katmanı.
/// Flutter'da `inset` gölge yok → üstte beyaz, altta siyah geçişle taklit edilir.
/// Bu, tasarımdaki `inset 0 2px 3px rgba(255,255,255,.5)` +
/// `inset 0 -2px 3px rgba(0,0,0,.15)` reçetesinin karşılığıdır.
class IcIsik extends StatelessWidget {
  final BorderRadius kose;
  final bool basili;
  final bool guclu;

  const IcIsik({
    super.key,
    required this.kose,
    this.basili = false,
    this.guclu = true,
  });

  @override
  Widget build(BuildContext context) {
    final ust = guclu ? 0.5 : 0.10;
    // ⚠️ Alttaki siyah, Golgeler'deki derinlik gölgeleri gibi paletin
    // golgeGucu'yla ölçeklenir: açık temada ikincil (beyaz yüzeyli) düğmenin
    // altında %28'lik siyah, kirli gri bir şerit gibi duruyordu. Koyu
    // paletlerde golgeGucu = 1 → değer aynı.
    final golgeGucu = Renkler.aktif.golgeGucu;
    final alt = (guclu ? 0.15 : 0.28) * golgeGucu;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: kose,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // Basılıyken üst ışık söner, alt gölge artar → gömülme hissi
              Colors.white.withValues(alpha: basili ? ust * 0.25 : ust),
              Colors.transparent,
              Colors.black.withValues(
                alpha: (basili ? alt * 2.0 : alt).clamp(0.0, 1.0),
              ),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
    );
  }
}

/// 3D buton: gradient dolgu + dış glow + iç highlight/gölge,
/// basınca hafif aşağı iner ve glow kısılır (gömülme hissi).
class Uc3DDugme extends StatefulWidget {
  final Widget cocuk;
  final VoidCallback? onTap;
  final BorderRadius? kose;
  final EdgeInsetsGeometry padding;

  /// true → koyu yüzey varyantı (ikincil eylem)
  final bool ikincil;

  /// true → kırmızı (kapat/reddet)
  final bool tehlike;

  /// Genişliği doldursun mu
  final bool genis;

  const Uc3DDugme({
    super.key,
    required this.cocuk,
    this.onTap,
    this.kose,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.ikincil = false,
    this.tehlike = false,
    this.genis = false,
  });

  @override
  State<Uc3DDugme> createState() => _Uc3DDugmeState();
}

class _Uc3DDugmeState extends State<Uc3DDugme> {
  bool _basili = false;

  void _ayarla(bool v) {
    if (widget.onTap == null) return;
    setState(() => _basili = v);
  }

  @override
  Widget build(BuildContext context) {
    final kose = widget.kose ?? Kose.dugme;
    final kapali = widget.onTap == null;

    final Gradient dolgu = widget.tehlike
        ? Gradyanlar.tehlike
        : widget.ikincil
            ? Gradyanlar.yuzey
            : Gradyanlar.accent;

    final List<BoxShadow> golge = widget.ikincil
        ? Golgeler.yuzey
        : widget.tehlike
            ? Golgeler.tehlikeGlow
            : (_basili ? Golgeler.neonGlowBasili : Golgeler.neonGlow);

    return GestureDetector(
      onTapDown: (_) => _ayarla(true),
      onTapUp: (_) => _ayarla(false),
      onTapCancel: () => _ayarla(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        width: widget.genis ? double.infinity : null,
        transform: Matrix4.translationValues(0, _basili ? 2 : 0, 0),
        decoration: BoxDecoration(
          gradient: dolgu,
          borderRadius: kose,
          border: widget.ikincil ? Border.all(color: Renkler.kenar) : null,
          boxShadow: kapali ? null : golge,
        ),
        child: Opacity(
          opacity: kapali ? 0.5 : 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: IcIsik(
                  kose: kose,
                  basili: _basili,
                  guclu: !widget.ikincil,
                ),
              ),
              Padding(
                padding: widget.padding,
                child: Center(
                  widthFactor: widget.genis ? null : 1,
                  heightFactor: 1,
                  child: widget.cocuk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ekran zemini: palet zemini + üstte yumuşak vurgu parlaması.
class Zemin extends StatelessWidget {
  final Widget child;
  final Alignment parlama;
  const Zemin({
    super.key,
    required this.child,
    this.parlama = const Alignment(-0.5, -1),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Renkler.zemin,
        gradient: Gradyanlar.zeminParlama(hiza: parlama),
      ),
      child: child,
    );
  }
}

/// Uygulamanın tek, merkezi teması. main.dart bunu kullanır.
/// Etkin palet'ten ([Renkler.aktif]) kurulur → tema değişince yeniden çağrılır.
class AppTema {
  AppTema._();

  /// Sistem çubukları (status/navigation) — zeminle aynı; ikon parlaklığı
  /// palet'e göre (açık temada KOYU ikon, yoksa beyaz zeminde görünmez).
  /// AppBar'ı olmayan ekranlar (arama) için de main.dart'ta uygulanır.
  static SystemUiOverlayStyle get sistemCubuklari {
    final acik = Renkler.acikMi;
    final ikon = acik ? Brightness.dark : Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: ikon, // Android
      statusBarBrightness: acik ? Brightness.light : Brightness.dark, // iOS
      systemNavigationBarColor: Renkler.zemin,
      systemNavigationBarIconBrightness: ikon,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  static ThemeData olustur() {
    final acik = Renkler.acikMi;
    final taban = acik
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    final renkSemasi = acik
        ? ColorScheme.light(
            surface: Renkler.zemin,
            surfaceContainerHighest: Renkler.yuzey,
            primary: Renkler.neon,
            secondary: Renkler.neonKoyu,
            onPrimary: Renkler.metinKoyu,
            onSurface: Renkler.metin,
            error: Renkler.tehlike,
            outline: Renkler.kenar,
          )
        : ColorScheme.dark(
            surface: Renkler.zemin,
            surfaceContainerHighest: Renkler.yuzey,
            primary: Renkler.neon,
            secondary: Renkler.neonKoyu,
            onPrimary: Renkler.metinKoyu,
            onSurface: Renkler.metin,
            error: Renkler.tehlike,
            outline: Renkler.kenar,
          );

    OutlineInputBorder cerceve(Color renk, [double kalinlik = 1]) =>
        OutlineInputBorder(
          borderRadius: Kose.alan,
          borderSide: BorderSide(color: renk, width: kalinlik),
        );

    return taban.copyWith(
      scaffoldBackgroundColor: Renkler.zemin,
      canvasColor: Renkler.zemin,
      colorScheme: renkSemasi,
      appBarTheme: AppBarTheme(
        backgroundColor: Renkler.zemin,
        foregroundColor: Renkler.metin,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: Yazi.baslikOrta,
        iconTheme: IconThemeData(color: Renkler.metin),
        systemOverlayStyle: sistemCubuklari,
      ),
      iconTheme: IconThemeData(color: Renkler.metin),
      textTheme: taban.textTheme.apply(
        fontFamily: 'Manrope',
        bodyColor: Renkler.metin,
        displayColor: Renkler.metin,
      ),
      // ⚠️ NavigationBar (ana_kabuk) seçili ikonu M3 varsayılanında
      // `onSecondaryContainer`dır; ColorScheme'de verilmediği için
      // `onSecondary`ye (SİYAH) düşüyordu. Seçili göstergeyi neonSis'e
      // boyadığımız için koyu paletlerde siyah ikon neredeyse görünmezdi
      // (~1,3:1). Seçili = vurgu (emoji paneli kategori çubuğuyla aynı dil),
      // seçili değil = metin (eski varsayılan onSurfaceVariant → onSurface).
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? Renkler.neon
                : Renkler.metin,
          ),
        ),
      ),
      dividerColor: Renkler.cizgi,
      dividerTheme: DividerThemeData(color: Renkler.cizgi, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: Renkler.neon,
        textColor: Renkler.metin,
        titleTextStyle: Yazi.isim,
        subtitleTextStyle: Yazi.kucuk,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Renkler.neon
              : Renkler.metinSoluk,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Renkler.neon.withValues(alpha: 0.35)
              : Renkler.yuzey,
        ),
        trackOutlineColor: WidgetStatePropertyAll(Renkler.kenar),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: Renkler.neon,
        linearTrackColor: Renkler.yuzey,
        circularTrackColor: Renkler.yuzey,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Renkler.yuzeyYuksek,
        contentTextStyle: Yazi.govde,
        actionTextColor: Renkler.neon,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Kose.alan),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Renkler.yuzey,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Yazi.baslikOrta,
        contentTextStyle: Yazi.govde,
        shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Renkler.yuzey,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Renkler.yuzey,
        hintStyle: Yazi.kucuk,
        prefixIconColor: Renkler.metinSoluk,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: cerceve(Renkler.kenar),
        enabledBorder: cerceve(Renkler.kenar),
        focusedBorder: cerceve(Renkler.neon, 1.5),
        errorBorder: cerceve(Renkler.tehlike),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Renkler.neon,
        selectionColor: Renkler.secim,
        selectionHandleColor: Renkler.neon,
      ),
    );
  }
}

/// Tüm widget ağacını, ağacı KORUYARAK yeniden çizer (tema değişimi için).
///
/// Neden gerekli: `Renkler.x` statik getter'dır; bir widget onu okuduğunda
/// Flutter bir bağımlılık kaydetmez (Theme.of'taki gibi), yani palet
/// değişince hiçbir şey kendiliğinden yeniden kurulmaz.
///
/// Neden bu yol (seçenekler):
///  - KeyedSubtree ile alt ağacı yeni anahtarla kurmak → Navigator yığını ve
///    tüm State'ler sıfırlanır (kullanıcı Ayarlar'dan atılır). ✗
///  - `WidgetsBinding.reassembleApplication()` → Flutter kaynağında
///    (foundation/binding.dart, widgets/framework.dart BuildOwner.reassemble)
///    sürüm derlemesinde de çalışıyor; ama belgesi açıkça "üretimde
///    kullanılmamalı" diyor, işlem süresince girdi olaylarını kilitliyor
///    (lockEvents) ve her State'in `reassemble()` kancasını (hot reload
///    için yazılmış kodu) tetikliyor. ✗
///  - Burada: her etkin Element'i `markNeedsBuild` ile kirli işaretlemek.
///    `Element.reassemble`'ın yaptığının yalnız ilk yarısı — State kancası
///    yok, olay kilidi yok; bir sonraki karede her build() yeni paleti
///    okur. Yığın, kaydırma, metin girişleri korunur. ✓
///
/// Not: Overlay'deki (diyalog, alt sayfa, arka plandaki rotalar) elemanlar
/// da ağacın parçası olduğu için onlar da yenilenir. Rengi `initState`'te
/// önbelleğe alan bir State varsa o güncellenmez — böyle bir yer yok;
/// renkler her zaman build() içinde okunmalı.
void tumAgaciYenidenCiz() {
  final kok = WidgetsBinding.instance.rootElement;
  if (kok == null) return;
  void isaretle(Element e) {
    e.markNeedsBuild();
    e.visitChildren(isaretle);
  }

  isaretle(kok);
}
