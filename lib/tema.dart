import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// =====================================================================
///  MERKEZİ TASARIM DOSYASI — "İmza Karışım" (1c)
///  Neon-lime / derin yeşil cam dili.
///
///  Uygulamadaki TÜM renk, gradient, gölge, köşe ve tipografi değerleri
///  BURADADIR. Hiçbir ekranda hardcoded renk/stil olmamalı.
///  Değiştirmek istersen SADECE burayı düzenle.
/// =====================================================================

/// Ham renk paleti.
class Renkler {
  Renkler._();

  // --- Zemin & yüzeyler ---
  /// Ana arka plan (ekran zemini)
  static const Color zemin = Color(0xFF071A10);

  /// En koyu ton — sistem barları / accent üstü kontrast blokları
  static const Color zeminDerin = Color(0xFF050F0A);

  /// Kart / panel / appbar / giriş kutusu yüzeyi
  static const Color yuzey = Color(0xFF0D2818);

  /// Yükseltilmiş yüzey (gradient üst tonu)
  static const Color yuzeyYuksek = Color(0xFF14301E);

  // --- Kenarlıklar (neon'un düşük opaklıkları) ---
  static const Color kenar = Color(0x24B4FF3C); // ~%14
  static const Color kenarGuclu = Color(0x2EB4FF3C); // ~%18
  static const Color kenarSolgun = Color(0x1FB4FF3C); // ~%12

  // --- Neon accent ---
  /// Ana neon (vurgu, ikon, aktif durum)
  static const Color neon = Color(0xFFB4FF3C);
  static const Color neonAcik = Color(0xFFD4FF5C); // gradient açık ucu
  static const Color neonKoyu = Color(0xFFA8E02A); // gradient koyu ucu

  /// İkincil yeşiller (avatar/rozet çeşitliliği)
  static const Color yesil = Color(0xFF63B81A);
  static const Color yesilKoyu = Color(0xFF3F7A10);
  static const Color yesilAcik = Color(0xFF8FE63C);
  static const Color yesilOrta = Color(0xFF5AA314);

  /// Neon'un şeffaf tonu (ikon kutusu dolgusu vb.)
  static const Color neonSis = Color(0x1FB4FF3C); // ~%12

  // --- Metin ---
  /// Birincil metin (koyu zemin üstü)
  static const Color metin = Color(0xFFEAFFD8);

  /// İkincil / soluk metin
  static const Color metinSoluk = Color(0xFF6B8F5A);

  /// Neon/accent üstündeki metin (koyu)
  static const Color metinKoyu = Color(0xFF06170D);

  /// Neon üstü ikincil metin
  static const Color metinKoyuYumusak = Color(0xFF1A3D0D);

  // --- Durum ---
  static const Color tehlike = Color(0xFFFF5A5A);

  /// Kırmızı (tehlike) buton üstündeki metin/ikon
  static const Color metinTehlikeUstu = Color(0xFFFFF2F2);
  static const Color cizgi = Color(0xFF14301E);
}

/// Gradientler. Tasarımdaki 145° ≈ topLeft → bottomRight.
class Gradyanlar {
  Gradyanlar._();

  static const Alignment _bas = Alignment.topLeft;
  static const Alignment _son = Alignment.bottomRight;

  /// Ana neon dolgu (butonlar, kendi mesaj balonun, aktif kartlar)
  static const LinearGradient accent = LinearGradient(
    begin: _bas,
    end: _son,
    colors: [Renkler.neonAcik, Renkler.neonKoyu],
  );

  /// Koyu yeşil dolgu (avatar, ikincil rozet)
  static const LinearGradient yesil = LinearGradient(
    begin: _bas,
    end: _son,
    colors: [Renkler.yesil, Renkler.yesilKoyu],
  );

  /// Açık yeşil dolgu (çeşitlilik)
  static const LinearGradient yesilAcik = LinearGradient(
    begin: _bas,
    end: _son,
    colors: [Renkler.yesilAcik, Renkler.yesilOrta],
  );

  /// Yüzey kartı dolgusu (hafif hacim)
  static const LinearGradient yuzey = LinearGradient(
    begin: _bas,
    end: _son,
    colors: [Renkler.yuzeyYuksek, Renkler.yuzey],
  );

  /// Ekran zemininin üstündeki yumuşak neon parlaması.
  /// [hiza] ile parlamanın yeri değiştirilebilir.
  static RadialGradient zeminParlama({
    Alignment hiza = const Alignment(-0.5, -1),
  }) =>
      RadialGradient(
        center: hiza,
        radius: 1.1,
        colors: const [Color(0x17B4FF3C), Color(0x00B4FF3C)],
        stops: const [0, 0.55],
      );
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
class Golgeler {
  Golgeler._();

  /// Neon glow (accent butonlar/balonlar)
  static const List<BoxShadow> neonGlow = [
    BoxShadow(color: Color(0x59B4FF3C), blurRadius: 18, offset: Offset(0, 5)),
  ];

  /// Basılıyken kısılmış glow (gömülme hissi)
  static const List<BoxShadow> neonGlowBasili = [
    BoxShadow(color: Color(0x2EB4FF3C), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Güçlü neon glow (arama kabul, ana eylem)
  static const List<BoxShadow> neonGlowGuclu = [
    BoxShadow(color: Color(0x66B4FF3C), blurRadius: 22, offset: Offset(0, 8)),
  ];

  /// Koyu yüzey derinliği
  static const List<BoxShadow> yuzey = [
    BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// Balon derinliği
  static const List<BoxShadow> balon = [
    BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// Kırmızı (kapat/reddet) glow
  static const List<BoxShadow> tehlikeGlow = [
    BoxShadow(color: Color(0x59FF5A5A), blurRadius: 18, offset: Offset(0, 5)),
  ];
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
  static BoxDecoration neonNokta() => const BoxDecoration(
        color: Renkler.neon,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0xB3B4FF3C), blurRadius: 8),
        ],
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
    final alt = guclu ? 0.15 : 0.28;
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
              Colors.black.withValues(alpha: basili ? alt * 2.0 : alt),
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
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF7B7B), Color(0xFFD93A3A)],
          )
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

/// Ekran zemini: koyu yeşil + üstte yumuşak neon parlaması.
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
class AppTema {
  AppTema._();

  /// Sistem çubukları (status/navigation) — zeminle aynı, ikonlar açık.
  /// AppBar'ı olmayan ekranlar (arama) için de main.dart'ta uygulanır.
  static const SystemUiOverlayStyle sistemCubuklari = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android: açık ikonlar
    statusBarBrightness: Brightness.dark, // iOS
    systemNavigationBarColor: Renkler.zemin,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  static ThemeData karanlik() {
    final taban = ThemeData.dark(useMaterial3: true);

    return taban.copyWith(
      scaffoldBackgroundColor: Renkler.zemin,
      canvasColor: Renkler.zemin,
      colorScheme: const ColorScheme.dark(
        surface: Renkler.zemin,
        surfaceContainerHighest: Renkler.yuzey,
        primary: Renkler.neon,
        secondary: Renkler.neonKoyu,
        onPrimary: Renkler.metinKoyu,
        onSurface: Renkler.metin,
        error: Renkler.tehlike,
        outline: Renkler.kenar,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Renkler.zemin,
        foregroundColor: Renkler.metin,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: Yazi.baslikOrta,
        iconTheme: const IconThemeData(color: Renkler.metin),
        systemOverlayStyle: sistemCubuklari,
      ),
      iconTheme: const IconThemeData(color: Renkler.metin),
      textTheme: taban.textTheme.apply(
        fontFamily: 'Manrope',
        bodyColor: Renkler.metin,
        displayColor: Renkler.metin,
      ),
      dividerColor: Renkler.cizgi,
      dividerTheme: const DividerThemeData(color: Renkler.cizgi, thickness: 1),
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
        trackOutlineColor: const WidgetStatePropertyAll(Renkler.kenar),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Renkler.yuzey,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Kose.panel),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Renkler.yuzey,
        hintStyle: Yazi.kucuk,
        prefixIconColor: Renkler.metinSoluk,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: Kose.alan,
          borderSide: BorderSide(color: Renkler.kenar),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Kose.alan,
          borderSide: BorderSide(color: Renkler.kenar),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: Kose.alan,
          borderSide: BorderSide(color: Renkler.neon, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: Kose.alan,
          borderSide: BorderSide(color: Renkler.tehlike),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Renkler.neon,
        selectionColor: Color(0x4DB4FF3C),
        selectionHandleColor: Renkler.neon,
      ),
    );
  }
}
