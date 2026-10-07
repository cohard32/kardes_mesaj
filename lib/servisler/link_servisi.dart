import 'package:flutter/services.dart';

import '../yardimcilar/link_metni.dart';
import 'hata_servisi.dart';

/// Mesajdaki bağlantıyı telefonun TARAYICISINDA (ya da o adresi işleyen
/// uygulamada, ör. YouTube) açar. Ek paket yerine mevcut yerel kanal
/// (MainActivity.kt → "linkAc") kullanılır.
class LinkServisi {
  LinkServisi._();
  static final LinkServisi instance = LinkServisi._();

  static const MethodChannel _native = MethodChannel('kardes_mesaj/sesler');

  /// Açıldıysa true. Yalnız http/https açılır (bkz. [acilabilirLinkMi]).
  Future<bool> ac(String url) async {
    if (!acilabilirLinkMi(url)) return false;
    try {
      return await _native.invokeMethod<bool>('linkAc', {'url': url}) ?? false;
    } catch (e) {
      HataServisi.instance.iz('link acilamadi: $e');
      return false;
    }
  }
}
