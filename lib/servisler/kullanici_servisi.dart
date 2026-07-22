import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'hata_servisi.dart';

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

  /// Rezerve/yanıltıcı kullanıcı adları (kimse alamaz).
  static const _rezerveAdlar = {
    'admin', 'administrator', 'root', 'system', 'sistem', 'support', 'destek',
    'moderator', 'moderatör', 'mod', 'kardes', 'kardesmesaj', 'kardes_mesaj',
    'null', 'undefined', 'me', 'ben', 'sen', 'you', 'everyone', 'herkes',
  };

  /// Kullanıcı adı biçim kuralı (küçük harf/rakam/alt çizgi, 3-20).
  /// Geçerliyse null, değilse hata metni döner.
  String? kullaniciAdiHatasi(String ad) {
    final a = ad.trim().toLowerCase();
    if (a.length < 3) return 'En az 3 karakter';
    if (a.length > 20) return 'En fazla 20 karakter';
    if (!_adDeseni.hasMatch(a)) {
      return 'Sadece küçük harf, rakam ve _ (boşluk yok)';
    }
    if (_rezerveAdlar.contains(a)) return 'Bu kullanıcı adı kullanılamaz';
    return null;
  }

  /// Şifre gücü kuralı. Geçerliyse null, değilse hata metni döner.
  ///
  /// ⚠️ Firebase'in tek kuralı "en az 6 karakter" — yani "123456" kabul edilir.
  /// Bu, kimlik doğrulamanın EN ZAYIF halkası (kurallar ne kadar sıkı olursa
  /// olsun tahmin edilen şifre hesabı verir). Bu yüzden istemcide daha güçlü
  /// bir asgari uygulanır. Kartsız/Spark planında sunucu tarafı şifre politikası
  /// (Identity Platform) YOK — burası tek kontrol noktası.
  String? sifreHatasi(String sifre) {
    if (sifre.length < 8) return 'En az 8 karakter olmalı';
    if (!RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(sifre)) {
      return 'En az bir harf içermeli';
    }
    if (!RegExp(r'[0-9]').hasMatch(sifre)) return 'En az bir rakam içermeli';
    if (_zayifSifreler.contains(sifre.toLowerCase())) {
      return 'Bu şifre çok yaygın, başka bir tane seç';
    }
    return null;
  }

  /// En sık denenen şifreler (sözlük saldırısının ilk sırası).
  static const _zayifSifreler = {
    '12345678', '123456789', '1234567890', 'password', 'password1',
    'parola123', 'sifre123', 'qwerty123', 'iloveyou', 'abc12345',
    '11111111', '00000000', 'admin123', 'welcome1', 'asdf1234',
  };

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
    final sHata = sifreHatasi(sifre);
    if (sHata != null) throw KullaniciHatasi('Şifre: $sHata');

    // Hızlı ön kontrol (kesin garanti transaction'da)
    if (!await kullaniciAdiMusaitMi(kAdi)) {
      throw KullaniciHatasi('@$kAdi alınmış, başka bir ad dene.');
    }

    HataServisi.instance.iz('KAYIT deneniyor @$kAdi');
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
          // ⚠️ E-POSTA YAZILMAZ: users/{uid} her giriş yapmış kullanıcıya
          // OKUNUR (arama/profil için şart). E-posta oraya konursa herkesin
          // e-postası herkese açılır. Uygulama zaten hiçbir yerde
          // kullanmıyor; kimlik için FirebaseAuth.currentUser.email var.
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

    // 3) Doğrulama maili (fire-and-forget). ⚠️ BAŞARISIZLIĞI KAYDI BOZMAZ:
    // uygulama doğrulanmamış hesapla TAM çalışır, profilde uyarı gösterilir.
    // Kullanıcı yeni kayıt olurken mail gönderilemedi diye hesabı silmek
    // (kota/ağ hatası yüzünden) çok daha kötü bir sonuç olurdu.
    try {
      await cred.user?.sendEmailVerification();
      HataServisi.instance.iz('DOGRULAMA maili gonderildi');
    } catch (e) {
      HataServisi.instance.iz('DOGRULAMA maili gonderilemedi: $e');
    }
  }

  /// Oturumdaki hesabın e-postası doğrulanmış mı?
  bool get epostaDogrulandi =>
      FirebaseAuth.instance.currentUser?.emailVerified ?? false;

  /// Oturumdaki hesabın e-postası (profil ekranında göstermek için).
  String? get oturumEpostasi => FirebaseAuth.instance.currentUser?.email;

  /// Doğrulama mailini yeniden gönderir.
  /// ⚠️ Firebase kısa aralıklı tekrarlarda `too-many-requests` döner —
  /// bu kullanıcıya anlaşılır bir metin olarak iletilir, sessizce yutulmaz.
  Future<void> dogrulamaMailiGonder() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw KullaniciHatasi('Oturum yok.');
    if (u.emailVerified) return;
    try {
      await u.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        throw KullaniciHatasi('Çok sık denendi, birkaç dakika sonra tekrar dene.');
      }
      throw KullaniciHatasi(_authHata(e.code));
    }
  }

  /// Auth durumunu sunucudan tazeler → kullanıcı maildeki linke tıkladıysa
  /// [epostaDogrulandi] artık true döner. (reload olmadan istemci ESKİ
  /// token'a bakar ve "doğrulanmadı" demeye devam eder.)
  Future<bool> dogrulamaDurumunuTazele() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    try {
      await u.reload();
      return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    } catch (_) {
      return u.emailVerified;
    }
  }

  /// Profil dokümanı var mı? (auth_gate: profil kurulmamışsa kuruluma yönlendir)
  Future<bool> profilVarMi(String uid) async =>
      (await _users.doc(uid).get()).exists;

  /// Oturumu AÇIK ama profili OLMAYAN kullanıcı için profil kurar
  /// (ör. eski hesaplar, ilk açılışta @kullanıcı adı seçimi). Auth hesabı
  /// oluşturmaz — mevcut uid/e-posta kullanılır. Kullanıcı adını TRANSACTION
  /// ile rezerve eder (yarış durumunda çakışmayı önler).
  Future<void> profilKur({
    required String ad,
    required String kullaniciAdi,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw KullaniciHatasi('Oturum yok.');
    final uid = user.uid;
    final adTemiz = ad.trim();
    final kAdi = kullaniciAdi.trim().toLowerCase();

    if (adTemiz.isEmpty) throw KullaniciHatasi('İsim boş olamaz.');
    final kHata = kullaniciAdiHatasi(kAdi);
    if (kHata != null) throw KullaniciHatasi('Kullanıcı adı: $kHata');

    try {
      await _db.runTransaction((tx) async {
        final unameRef = _usernames.doc(kAdi);
        final snap = await tx.get(unameRef);
        if (snap.exists) {
          throw KullaniciHatasi('@$kAdi alınmış, başka bir ad dene.');
        }
        tx.set(unameRef, {'uid': uid});
        tx.set(_users.doc(uid), {
          'ad': adTemiz,
          'kullaniciAdi': kAdi,
          // E-posta YAZILMAZ — bkz. kayitOl içindeki gizlilik açıklaması.
          'cevrimici': false,
          'olusturma': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      if (e is KullaniciHatasi) rethrow;
      throw KullaniciHatasi('Profil kurulamadı, tekrar dene.');
    }
  }

  /// Bir kullanıcının profilini canlı dinler.
  Stream<Kullanici> profilDinle(String uid) =>
      _users.doc(uid).snapshots().map(Kullanici.firestoreDan);

  /// Bir kullanıcının profilini bir kez okur.
  Future<Kullanici?> profilGetir(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? Kullanici.firestoreDan(doc) : null;
  }

  /// Tam @kullanıcı adından profili bulur (QR tarama / doğrudan giriş için).
  /// usernames/{ad} → uid → users/{uid}. Bulunamazsa null.
  Future<Kullanici?> kullaniciAdindanBul(String ad) async {
    final a = ad.trim().toLowerCase().replaceAll('@', '');
    if (a.isEmpty) return null;
    final doc = await _usernames.doc(a).get();
    final uid = doc.data()?['uid'] as String?;
    if (uid == null) return null;
    return profilGetir(uid);
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
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı, biraz sonra tekrar dene.';
      case 'requires-recent-login':
        return 'Güvenlik için çıkış yapıp tekrar giriş yapmalısın.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
      case 'user-not-found':
        return 'Bu e-postayla hesap yok.';
      default:
        return 'İşlem yapılamadı ($kod).';
    }
  }
}
