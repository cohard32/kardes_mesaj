import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/sohbet.dart';

/// Sohbet listesi ve chat dokümanı yönetimi (FAZ 4.3).
///
///   chats/{chatId}  → katilimcilar, sonMesaj, sonMesajZamani,
///                     sonMesajGonderen, okunmamis{uid:adet}
/// chatId = ciftKimligi(uid1, uid2) — mükerrer sohbet olmaz.
class SohbetServisi {
  SohbetServisi._();
  static final SohbetServisi instance = SohbetServisi._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// İki uid için sohbet kimliği.
  String sohbetId(String otherUid) => ciftKimligi(_uid ?? '', otherUid);

  /// Sohbetlerimi son mesaja göre (yeni → eski) canlı dinler.
  /// ⚠️ Firestore composite index gerekir:
  ///   collection: chats, fields: katilimcilar (array-contains) +
  ///   sonMesajZamani (desc). İlk çalıştırmada konsol linki verir.
  Stream<List<Sohbet>> sohbetleriDinle() {
    final me = _uid;
    if (me == null) return const Stream.empty();
    return _chats
        .where('katilimcilar', arrayContains: me)
        .orderBy('sonMesajZamani', descending: true)
        .limit(60)
        .snapshots()
        .map((s) => s.docs.map(Sohbet.firestoreDan).toList());
  }

  /// Tek bir sohbeti canlı dinler (sohbet ekranı başlığı/okunmamış için).
  Stream<Sohbet> sohbetDinle(String chatId) =>
      _chats.doc(chatId).snapshots().map(Sohbet.firestoreDan);

  /// Sohbeti aç (yoksa oluştur) ve chatId döndür.
  /// Kural: karşı tarafla ARKADAŞ olmak şart (firestore.rules doğrular).
  Future<String> sohbetAcOrGetir(String otherUid) async {
    final me = _uid;
    if (me == null) throw Exception('Oturum yok');
    final id = ciftKimligi(me, otherUid);
    final ref = _chats.doc(id);
    if (!(await ref.get()).exists) {
      await ref.set({
        'katilimcilar': <String>[me, otherUid]..sort(),
        'olusturma': FieldValue.serverTimestamp(),
      });
    }
    return id;
  }

  /// Bu sohbetteki okunmamışlarımı sıfırla (sohbeti açınca).
  Future<void> okunduIsaretle(String chatId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await _chats.doc(chatId).set(
        {'okunmamis': {me: 0}},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Toplam okunmamış sohbet sayısı (alt bar rozeti için).
  Stream<int> toplamOkunmamis() {
    final me = _uid;
    if (me == null) return const Stream.empty();
    return sohbetleriDinle().map(
      (liste) => liste.where((s) => s.benimOkunmamis(me) > 0).length,
    );
  }
}
