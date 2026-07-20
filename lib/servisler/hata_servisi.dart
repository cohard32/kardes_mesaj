import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'guncelleme_servisi.dart';

/// Uzaktan teşhis: çökmeleri/hataları VE adım adım "iz" kaydını Firestore'a
/// yollar (`hatalar` koleksiyonu). Geliştirici admin erişimiyle okur.
///
/// NEDEN Firestore (GitHub değil): GitHub'a yazmak APK'ya yazma yetkili bir
/// token gömmeyi gerektirir; APK'yı açan herkes o token'ı ele geçirir.
/// Firestore'da yeni bir sır yok, kurallar yalnız YAZMAYA izin verir
/// (istemci okuyamaz), okuma sadece admin (service account) ile yapılır.
///
/// İZ (breadcrumb) mantığı: arama gibi akışlarda hata FIRLAMADAN "takılma"
/// oluyor. Bu yüzden adımlar sürekli kaydedilir; kullanıcı Ayarlar'dan
/// "Sorun bildir"e basınca son adımlar yüklenir → nerede durduğu görülür.
class HataServisi {
  HataServisi._();
  static final HataServisi instance = HataServisi._();

  static const int _enFazlaIz = 150;
  final List<String> _izler = <String>[];

  /// Bir adımı kaydet (hafızada halka tampon; ağ trafiği yok).
  void iz(String mesaj) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    _izler.add('$t  $mesaj');
    if (_izler.length > _enFazlaIz) _izler.removeAt(0);
    debugPrint('İZ  $mesaj');
  }

  /// Global hata yakalayıcıları kur (main içinde çağrılır).
  void baslat() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      bildir(details.exception, details.stack, etiket: 'flutter');
    };
    PlatformDispatcher.instance.onError = (hata, stack) {
      bildir(hata, stack, etiket: 'platform');
      return true; // yutuldu (rapor gönderildi)
    };
  }

  /// Hatayı/izleri Firestore'a yolla. Asla exception fırlatmaz.
  Future<void> bildir(
    Object hata,
    StackTrace? stack, {
    String etiket = 'genel',
  }) async {
    try {
      await FirebaseFirestore.instance.collection('hatalar').add({
        'zaman': FieldValue.serverTimestamp(),
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'etiket': etiket,
        'surum': GuncellemeServisi.mevcutSurum,
        'cihaz': Platform.operatingSystemVersion,
        'hata': hata.toString(),
        'stack': stack?.toString().split('\n').take(25).join('\n'),
        'izler': List<String>.from(_izler),
      });
    } catch (_) {
      // Rapor gönderilemezse sessizce vazgeç (uygulamayı asla bozma).
    }
  }

  /// Kullanıcı "Sorun bildir"e bastığında: hata olmasa da son izleri yolla.
  Future<bool> manuelBildir([String not = 'Kullanıcı raporu']) async {
    try {
      await FirebaseFirestore.instance.collection('hatalar').add({
        'zaman': FieldValue.serverTimestamp(),
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'etiket': 'manuel',
        'surum': GuncellemeServisi.mevcutSurum,
        'cihaz': Platform.operatingSystemVersion,
        'hata': not,
        'izler': List<String>.from(_izler),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
