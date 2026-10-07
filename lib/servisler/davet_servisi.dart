import 'package:flutter/services.dart';

import 'hata_servisi.dart';

/// Uygulamanın indirileceği adres (GitHub'daki son sürüm sayfası; APK
/// orada — uygulama içi güncelleme de buradan çeker).
const String indirmeAdresi =
    'https://github.com/cohard32/kardes_mesaj/releases/latest';

/// Davet mesajı (saf → test).
String davetMetni(String? kullaniciAdi) {
  final ad = (kullaniciAdi ?? '').trim();
  return [
    'Merhaba! 👋 Aile mesajlaşma uygulamamız ROY MESSANGER\'ı kur:',
    indirmeAdresi,
    '(Sayfadaki ".apk" dosyasını indirip aç.)',
    if (ad.isNotEmpty) 'Kurunca beni @$ad kullanıcı adıyla ekle, yazışalım! 💬',
  ].join('\n');
}

/// "Arkadaşlarını davet et": davet metni telefonun paylaşım menüsüyle
/// (WhatsApp, SMS, e-posta…) gönderilir.
class DavetServisi {
  DavetServisi._();

  static const _kanal = MethodChannel('kardes_mesaj/sesler');

  static Future<bool> davetEt(String? kullaniciAdi) async {
    try {
      return await _kanal.invokeMethod<bool>('metinPaylas', {
            'metin': davetMetni(kullaniciAdi),
            'baslik': 'Davet et',
          }) ??
          false;
    } catch (e) {
      HataServisi.instance.iz('davet paylasilamadi: $e');
      return false;
    }
  }
}
