import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/kullanici.dart';

/// Çevrimiçi/son görülme (kullanıcı bazlı) + "yazıyor" (sohbet bazlı).
/// FAZ 4: tek karşı taraf yerine belirli kullanıcı/sohbet.
///   users/{uid}.cevrimici / sonGorulme
///   chats/{chatId}.yaziyor.{uid}
class PresenceServisi {
  PresenceServisi._();
  static final PresenceServisi instance = PresenceServisi._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Kendimi çevrimiçi işaretle.
  Future<void> cevrimiciYap() async {
    final uid = _uid;
    if (uid == null) return;
    await _users.doc(uid).set({
      'cevrimici': true,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Kendimi çevrimdışı işaretle.
  Future<void> cevrimdisiYap() async {
    final uid = _uid;
    if (uid == null) return;
    await _users.doc(uid).set({
      'cevrimici': false,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Bir sohbette "yazıyor" durumumu güncelle.
  Future<void> yaziyorAyarla(String chatId, bool yaziyor) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('chats').doc(chatId).set(
        {'yaziyor': {uid: yaziyor}},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Belirli bir kullanıcının profil/durumunu canlı dinler
  /// (çevrimiçi/son görülme için).
  Stream<Kullanici> kullaniciDinle(String uid) =>
      _users.doc(uid).snapshots().map(Kullanici.firestoreDan);
}
