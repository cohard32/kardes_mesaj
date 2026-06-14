import 'package:flutter/material.dart';

/// =====================================================================
///  MERKEZİ TEMA DOSYASI
///  Uygulamanın TÜM renkleri burada tanımlıdır.
///  Renk/ton değiştirmek istersen SADECE burayı düzenle — renkleri
///  başka dosyalara dağıtma (PROJECT.md kuralı).
/// =====================================================================

/// Tüm renk sabitleri tek noktada.
class Renkler {
  Renkler._(); // örnek oluşturulamaz; sadece Renkler.zemin gibi statik erişim

  static const Color zemin = Color(0xFF0D0D0D); // ana arka plan (dark)
  static const Color accent = Color(0xFF00B0FF); // vurgu rengi (mavi)

  static const Color benimBalon = Color(0xFF00B0FF); // senin mesaj balonların (mavi)
  static const Color kardesBalon = Color(0xFF1C1C1C); // kardeşinin balonları (koyu gri)

  static const Color yuzey = Color(0xFF141414); // app bar / kart yüzeyi
  static const Color giris = Color(0xFF1A1A1A); // mesaj yazma kutusu vb.

  static const Color metin = Color(0xFFEDEDED); // birincil metin
  static const Color metinSoluk = Color(0xFF8A8A8A); // ikincil / soluk metin
  static const Color cizgi = Color(0xFF262626); // ayraç çizgileri
}

/// Uygulamanın tek, merkezi teması. main.dart bunu kullanır.
class AppTema {
  AppTema._();

  static ThemeData karanlik() {
    final taban = ThemeData.dark(useMaterial3: true);

    return taban.copyWith(
      scaffoldBackgroundColor: Renkler.zemin,
      colorScheme: const ColorScheme.dark(
        surface: Renkler.zemin,
        primary: Renkler.accent,
        secondary: Renkler.accent,
        onPrimary: Colors.white,
        onSurface: Renkler.metin,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Renkler.yuzey,
        foregroundColor: Renkler.metin,
        elevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(color: Renkler.metin),
      textTheme: taban.textTheme.apply(
        bodyColor: Renkler.metin,
        displayColor: Renkler.metin,
      ),
      dividerColor: Renkler.cizgi,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Renkler.giris,
        hintStyle: TextStyle(color: Renkler.metinSoluk),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Renkler.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
