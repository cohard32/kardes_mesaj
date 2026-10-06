import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'hata_servisi.dart';

/// Sunucusuz AKTARICI (Cloudflare Worker, bkz. `sunucu/aktarici/`).
///
/// ⚠️ NEDEN: FCM hizmet hesabı anahtarı (`assets/service_account.json`) ve
/// Agora App Certificate (`lib/gizli.dart`) APK'nın İÇİNDE dağıtılıyordu;
/// APK'yı açan herkes bunları çıkarıp herkese sahte bildirim/arama
/// gönderebilir, sınırsız Agora token üretebilirdi. Aktarıcı bu sırları
/// sunucuda tutar; istemci yalnız KENDİ Firebase kimlik belirtecini gönderir.
///
/// Derleme anında açılır:
///   flutter build apk --dart-define=AKTARICI_URL=https://roy-aktarici.HESAP.workers.dev
/// Tanımlı değilse uygulama ESKİ yolu (APK içindeki anahtarlar) kullanır →
/// aktarıcı yayına alınmadan hiçbir şey kırılmaz.
const String aktariciUrl = String.fromEnvironment('AKTARICI_URL');

class AktariciServisi {
  AktariciServisi._();
  static final AktariciServisi instance = AktariciServisi._();

  static bool get etkin => aktariciUrl.isNotEmpty;

  static const Duration _zamanAsimi = Duration(seconds: 10);

  Future<Map<String, String>> _basliklar() async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) throw StateError('Oturum yok');
    // App Check zorlaması açılırsa aktarıcının Firestore'a KULLANICI adına
    // yaptığı okumalar da belirteç ister → varsa iletilir.
    String? appCheck;
    try {
      appCheck = await FirebaseAppCheck.instance.getToken();
    } catch (_) {}
    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': ?appCheck,
    };
  }

  Uri _uc(String yol) =>
      Uri.parse('${aktariciUrl.replaceAll(RegExp(r'/+$'), '')}$yol');

  /// [hedefUid]'ye FCM mesajı gönderir. [mesaj] FCM HTTP v1 `message`
  /// nesnesinin `notification` / `data` / `android` alanlarıdır (token'ı
  /// aktarıcı kendisi bulur). HTTP durum kodunu döner.
  Future<int> bildirimGonder({
    required String hedefUid,
    required Map<String, dynamic> mesaj,
  }) async {
    final yanit = await http
        .post(
          _uc('/bildirim'),
          headers: await _basliklar(),
          body: jsonEncode({'hedefUid': hedefUid, 'mesaj': mesaj}),
        )
        .timeout(_zamanAsimi);
    if (yanit.statusCode != 200) {
      HataServisi.instance.iz('AKTARICI bildirim HTTP ${yanit.statusCode}');
    }
    return yanit.statusCode;
  }

  /// [chatId] çiftinin üyesi olarak [kanal] için Agora RTC token'ı ister.
  /// Başarısızsa null.
  Future<String?> agoraTokeni({
    required String chatId,
    required String kanal,
  }) async {
    final yanit = await http
        .post(
          _uc('/agora-token'),
          headers: await _basliklar(),
          body: jsonEncode({'chatId': chatId, 'kanal': kanal}),
        )
        .timeout(_zamanAsimi);
    if (yanit.statusCode != 200) {
      HataServisi.instance.iz('AKTARICI agora HTTP ${yanit.statusCode}');
      return null;
    }
    final govde = jsonDecode(yanit.body);
    return govde is Map ? govde['token'] as String? : null;
  }
}
