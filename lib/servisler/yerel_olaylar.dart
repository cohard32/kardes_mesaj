import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android'den (MainActivity.kt) Dart'a gelen olaylar:
///  - `paylasimGeldi`: uygulama açıkken "Paylaş → ROY" ile içerik geldi
///  - `pipDegisti`: görüntülü aramada küçük pencere (PiP) açıldı/kapandı
///
/// ⚠️ Ayrı kanal ("kardes_mesaj/olaylar"): Dart → Android çağrıları
/// "kardes_mesaj/sesler" kanalında; bir kanalda Dart tarafında tek işleyici
/// olabildiği için olaylar ayrı tutulur.
class YerelOlaylar {
  YerelOlaylar._();

  static const _kanal = MethodChannel('kardes_mesaj/olaylar');

  /// Her yeni paylaşımda artar (dinleyen: AnaKabuk).
  static final ValueNotifier<int> paylasimGeldi = ValueNotifier<int>(0);

  /// Uygulama şu an küçük pencerede (PiP) mi?
  static final ValueNotifier<bool> kucukPencerede = ValueNotifier<bool>(false);

  static bool _kuruldu = false;

  /// main()'de bir kez.
  static void baslat() {
    if (_kuruldu) return;
    _kuruldu = true;
    _kanal.setMethodCallHandler((cagri) async {
      switch (cagri.method) {
        case 'paylasimGeldi':
          paylasimGeldi.value++;
        case 'pipDegisti':
          kucukPencerede.value = cagri.arguments == true;
      }
      return null;
    });
  }
}
