import 'package:cloud_firestore/cloud_firestore.dart';

/// Bir kullanıcıyı temsil eder. Firestore'daki `users/{uid}` dokümanı.
///
/// Yapı (FAZ 4.4):
///   ad           : görünen isim
///   kullaniciAdi : benzersiz @kullanıcı adı (usernames koleksiyonu garanti eder)
///   fotoUrl      : profil fotoğrafı (Cloudinary URL'i) — opsiyonel
///   bio          : durum/hakkında yazısı — opsiyonel
///   eposta       : giriş e-postası
///   fcmToken     : bildirim token'ı (hassas — kurallarda korunur)
///   cevrimici    : anlık çevrimiçi mi
///   sonGorulme   : son çevrimiçi zamanı
class Kullanici {
  final String uid;
  final String ad;
  final String kullaniciAdi;
  final String? fotoUrl;
  final String? bio;
  final String? eposta;
  final bool cevrimici;
  final DateTime? sonGorulme;

  const Kullanici({
    required this.uid,
    required this.ad,
    required this.kullaniciAdi,
    this.fotoUrl,
    this.bio,
    this.eposta,
    this.cevrimici = false,
    this.sonGorulme,
  });

  /// Firestore dokümanından Kullanici üretir.
  factory Kullanici.firestoreDan(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return Kullanici(
      uid: doc.id,
      ad: (d['ad'] ?? '') as String,
      kullaniciAdi: (d['kullaniciAdi'] ?? '') as String,
      fotoUrl: d['fotoUrl'] as String?,
      bio: d['bio'] as String?,
      eposta: d['eposta'] as String?,
      cevrimici: (d['cevrimici'] ?? false) as bool,
      sonGorulme: (d['sonGorulme'] as Timestamp?)?.toDate(),
    );
  }

  /// Boş/yükleniyor durumu için yer tutucu.
  factory Kullanici.bos(String uid) =>
      Kullanici(uid: uid, ad: '…', kullaniciAdi: '');

  /// Görünecek baş harf (avatar için).
  String get harf =>
      ad.trim().isNotEmpty ? ad.trim()[0].toUpperCase() : '?';

  Kullanici copyWith({
    String? ad,
    String? fotoUrl,
    String? bio,
  }) =>
      Kullanici(
        uid: uid,
        ad: ad ?? this.ad,
        kullaniciAdi: kullaniciAdi,
        fotoUrl: fotoUrl ?? this.fotoUrl,
        bio: bio ?? this.bio,
        eposta: eposta,
        cevrimici: cevrimici,
        sonGorulme: sonGorulme,
      );
}
