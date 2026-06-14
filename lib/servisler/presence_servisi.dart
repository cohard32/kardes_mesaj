import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Çevrimiçi durumu ve "yazıyor..." göstergesini yönetir.
/// Veriler `kullanicilar/{uid}` dokümanında tutulur (FCM token ile aynı yer).
class PresenceServisi {
  PresenceServisi._();
  static final PresenceServisi instance = PresenceServisi._();

  final CollectionReference<Map<String, dynamic>> _kullanicilar =
      FirebaseFirestore.instance.collection('kullanicilar');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Kendimi çevrimiçi işaretle.
  Future<void> cevrimiciYap() async {
    final uid = _uid;
    if (uid == null) return;
    await _kullanicilar.doc(uid).set({
      'online': true,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Kendimi çevrimdışı işaretle (son görülme güncellenir).
  Future<void> cevrimdisiYap() async {
    final uid = _uid;
    if (uid == null) return;
    await _kullanicilar.doc(uid).set({
      'online': false,
      'yaziyor': false,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// "yazıyor..." durumunu güncelle.
  Future<void> yaziyorAyarla(bool yaziyor) async {
    final uid = _uid;
    if (uid == null) return;
    await _kullanicilar.doc(uid).set(
      {'yaziyor': yaziyor},
      SetOptions(merge: true),
    );
  }

  /// Karşı tarafın (iki kişilik: benim dışımdaki) durum bilgisini canlı dinler.
  /// Döner: {online, yaziyor, sonGorulme} veya null.
  Stream<Map<String, dynamic>?> karsiTarafiDinle() {
    final uid = _uid;
    return _kullanicilar.snapshots().map((snap) {
      for (final doc in snap.docs) {
        if (doc.id != uid) return doc.data();
      }
      return null;
    });
  }
}
