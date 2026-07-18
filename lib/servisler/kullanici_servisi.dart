import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/kullanici.dart';

/// Kullanıcıya gösterilecek hata (kayıt/kullanıcı adı vb.).
class KullaniciHatasi implements Exception {
  final String mesaj;
  KullaniciHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Kayıt, kullanıcı adı benzersizliği, profil ve kullanıcı arama.
///
/// Koleksiyonlar (FAZ 4.4):
///   users/{uid}            → profil
///   usernames/{ad}         → {uid}  (benzersizlik garantisi, transaction)
class KullaniciServisi {
  KullaniciServisi._();
  static final KullaniciServisi instance = KullaniciServisi._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _db.collection('usernames');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static final RegExp _adDeseni = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Kullanıcı adı biçim kuralı (küçük harf/rakam/alt çizgi, 3-20).
  /// Geçerliyse null, değilse hata metni döner.
  String? kullaniciAdiHatasi(String ad) {
    final a = ad.trim().toLowerCase();
    if (a.length < 3) return 'En az 3 karakter';
    if (a.length > 20) return 'En fazla 20 karakter';
    if (!_adDeseni.hasMatch(a)) {
      return 'Sadece küçük harf, rakam ve _ (boşluk yok)';
    }
    return null;
  }

  /// Kullanıcı adı müsait mi? (usernames koleksiyonuna bakar)
  Future<bool> kullaniciAdiMusaitMi(String ad) async {
    final a = ad.trim().toLowerCase();
    if (kullaniciAdiHatasi(a) != null) return false;
    final doc = await _usernames.doc(a).get();
    return !doc.exists;
  }

  /// Kayıt: Firebase Auth hesabı açar, ardından TRANSACTION ile kullanıcı adını
  /// rezerve eder + profil dokümanını yazar (yarış durumu = iki kişi aynı anda
  /// aynı adı alamaz). Hata olursa açılan Auth hesabını temizler.
  Future<void> kayitOl({
    required String ad,
    required String kullaniciAdi,
    required String eposta,
    required String sifre,
  }) async {
    final adTemiz = ad.trim();
    final kAdi = kullaniciAdi.trim().toLowerCase();

    if (adTemiz.isEmpty) throw KullaniciHatasi('İsim boş olamaz.');
    final kHata = kullaniciAdiHatasi(kAdi);
    if (kHata != null) throw KullaniciHatasi('Kullanıcı adı: $kHata');

    // Hızlı ön kontrol (kesin garanti transaction'da)
    if (!await kullaniciAdiMusaitMi(kAdi)) {
      throw KullaniciHatasi('@$kAdi alınmış, başka bir ad dene.');
    }

    // 1) Auth hesabı
    final UserCredential cred;
    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: eposta.trim(),
        password: sifre,
      );
    } on FirebaseAuthException catch (e) {
      throw KullaniciHatasi(_authHata(e.code));
    }
    final uid = cred.user!.uid;

    // 2) TRANSACTION: kullanıcı adını rezerve et + profil yaz
    try {
      await _db.runTransaction((tx) async {
        final unameRef = _usernames.doc(kAdi);
        final snap = await tx.get(unameRef);
        if (snap.exists) {
          throw KullaniciHatasi('@$kAdi az önce alındı, başka bir ad dene.');
        }
        tx.set(unameRef, {'uid': uid});
        tx.set(_users.doc(uid), {
          'ad': adTemiz,
          'kullaniciAdi': kAdi,
          'eposta': eposta.trim(),
          'cevrimici': false,
          'olusturma': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      // Profil/username yazılamadıysa yarım Auth hesabını temizle
      try {
        await cred.user?.delete();
      } catch (_) {}
      if (e is KullaniciHatasi) rethrow;
      throw KullaniciHatasi('Kayıt tamamlanamadı, tekrar dene.');
    }
  }

  /// Profil dokümanı var mı? (auth_gate: profil kurulmamışsa kuruluma yönlendir)
  Future<bool> profilVarMi(String uid) async =>
      (await _users.doc(uid).get()).exists;

  /// Bir kullanıcının profilini canlı dinler.
  Stream<Kullanici> profilDinle(String uid) =>
      _users.doc(uid).snapshots().map(Kullanici.firestoreDan);

  /// Bir kullanıcının profilini bir kez okur.
  Future<Kullanici?> profilGetir(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? Kullanici.firestoreDan(doc) : null;
  }

  /// Kendi profilim (canlı).
  Stream<Kullanici>? benimProfilim() {
    final uid = _uid;
    if (uid == null) return null;
    return profilDinle(uid);
  }

  /// Profil güncelle (ad/bio/foto). Sadece verilen alanlar değişir.
  Future<void> profilGuncelle({String? ad, String? bio, String? fotoUrl}) async {
    final uid = _uid;
    if (uid == null) return;
    final veri = <String, dynamic>{};
    if (ad != null) veri['ad'] = ad.trim();
    if (bio != null) veri['bio'] = bio.trim();
    if (fotoUrl != null) veri['fotoUrl'] = fotoUrl;
    if (veri.isEmpty) return;
    await _users.doc(uid).set(veri, SetOptions(merge: true));
  }

  /// Şifre sıfırlama e-postası gönderir.
  Future<void> sifreSifirla(String eposta) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: eposta.trim());
    } on FirebaseAuthException catch (e) {
      throw KullaniciHatasi(_authHata(e.code));
    }
  }

  /// Kullanıcı adına göre arama (önek eşleşmesi). Kendini hariç tutar.
  Future<List<Kullanici>> kullaniciAra(String sorgu, {int limit = 15}) async {
    final q = sorgu.trim().toLowerCase().replaceAll('@', '');
    if (q.isEmpty) return [];
    final snap = await _users
        .where('kullaniciAdi', isGreaterThanOrEqualTo: q)
        .where('kullaniciAdi', isLessThan: '$q')
        .limit(limit)
        .get();
    return snap.docs
        .map(Kullanici.firestoreDan)
        .where((k) => k.uid != _uid)
        .toList();
  }

  String _authHata(String kod) {
    switch (kod) {
      case 'email-already-in-use':
        return 'Bu e-posta zaten kayıtlı.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'weak-password':
        return 'Şifre çok zayıf (en az 6 karakter).';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
      case 'user-not-found':
        return 'Bu e-postayla hesap yok.';
      default:
        return 'İşlem yapılamadı ($kod).';
    }
  }
}
