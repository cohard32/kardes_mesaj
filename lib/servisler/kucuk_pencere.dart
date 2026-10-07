import 'package:flutter/services.dart';

import 'hata_servisi.dart';

/// Görüntülü aramada KÜÇÜK PENCERE (Android resim içinde resim / PiP).
/// Görüşme bağlıyken izin verilir: ana ekrana dönülünce (Android 12+
/// kendiliğinden, 8–11'de "ev" tuşuyla) görüntü küçük pencerede sürer.
/// Pencere değişimi [YerelOlaylar.kucukPencerede] ile gelir.
class KucukPencere {
  KucukPencere._();

  static const _kanal = MethodChannel('kardes_mesaj/sesler');

  /// Ana ekrana dönünce küçük pencereye geçilebilsin mi?
  static Future<void> izinVer(bool acik) async {
    try {
      await _kanal.invokeMethod<void>('kucukPencereIzni', {'acik': acik});
    } catch (e) {
      HataServisi.instance.iz('kucuk pencere izni ayarlanamadi: $e');
    }
  }

  /// Hemen küçük pencereye geç (düğmeyle). Desteklenmiyorsa false.
  static Future<bool> gir() async {
    try {
      return await _kanal.invokeMethod<bool>('kucukPencereyeGec') ?? false;
    } catch (e) {
      HataServisi.instance.iz('kucuk pencereye gecilemedi: $e');
      return false;
    }
  }
}
