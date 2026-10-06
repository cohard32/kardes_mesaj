import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/sohbet.dart';
import 'bildirim_servisi.dart';

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

  // ---- SESSİZE ALMA ----
  // Liste ALICININ GİZLİ belgesinde tutulur: users/{uid}/ozel/bildirim
  // .sessizSohbetler (yalnız sahibi okur/yazar; bkz. firestore.rules).
  // ⚠️ NEDEN (d8/t1): eskiden herkese okunur users/{uid} belgesindeydi →
  // chatId = iki uid olduğundan liste kişinin KİMLERLE sohbet ettiğini ve
  // kimi sessize aldığını yabancılara açıyordu. Gönderen artık listeyi
  // OKUYAMAZ; sessiz kanal kararını AKTARICI verir (hizmet hesabıyla okur,
  // push'un channel_id'sini ezer — d6: karar gönderenin sürümüne de bağlı
  // kalmaz). Aktarıcısız (eski) derlemede sessize alma UYGULANAMAZ.
  // ⚠️ arrayUnion/arrayRemove + merge: tüm listeyi okuyup yeniden yazmak
  // iki cihazdan aynı anda değişiklikte birinin işlemini EZERDİ.

  DocumentReference<Map<String, dynamic>> _ozel(String uid) =>
      BildirimServisi.ozelBelge(uid);

  /// Eski sürümün public belgeye yazdığı listenin taşınması (uid başına,
  /// oturumda bir kez; başarısızsa sonraki çağrıda yeniden denenir).
  Future<void>? _tasima;
  String? _tasimaUid;

  /// GEÇİŞ: public `users/{uid}.sessizSohbetler` kaldıysa gizli belgeye
  /// TAŞIR (arrayUnion: gizli listede olanlar korunur) ve public alanı
  /// FieldValue.delete ile siler. Böylece eski sürümde sessize alınmış
  /// sohbetler güncellemeden sonra sessizliğini kaybetmez.
  Future<void> _eskiListeyiTasi(String me) {
    if (_tasimaUid == me && _tasima != null) return _tasima!;
    _tasimaUid = me;
    return _tasima = () async {
      try {
        final ref = _db.collection('users').doc(me);
        final d = (await ref.get()).data();
        if (d == null || !d.containsKey('sessizSohbetler')) return;
        final eski = d['sessizSohbetler'];
        final liste = eski is List ? eski.whereType<String>().toList() : [];
        if (liste.isNotEmpty) {
          await _ozel(me).set({
            'sessizSohbetler': FieldValue.arrayUnion(liste),
          }, SetOptions(merge: true));
        }
        await ref.set({
          'sessizSohbetler': FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (_) {
        _tasima = null; // sonraki çağrıda yeniden denensin
      }
    }();
  }

  /// Sohbeti sessize alır ([sessiz]=true) veya sessizi kapatır.
  Future<void> sessizeAl(String chatId, bool sessiz) async {
    final me = _uid;
    if (me == null) return;
    // Önce eski public liste taşınır/silinir: taşıma SONRA olsaydı burada
    // kapatılan bir sessizi eski listeden geri getirebilirdi.
    await _eskiListeyiTasi(me);
    await _ozel(me).set({
      'sessizSohbetler': sessiz
          ? FieldValue.arrayUnion([chatId])
          : FieldValue.arrayRemove([chatId]),
    }, SetOptions(merge: true));
  }

  /// Bu sohbet sessizde mi (canlı, gizli belgeden). Alan yoksa / bozuksa
  /// false.
  Stream<bool> sessizMi(String chatId) {
    final me = _uid;
    if (me == null) return Stream.value(false);
    _eskiListeyiTasi(me); // geçiş (fire-and-forget; hata yutulur)
    return _ozel(me).snapshots().map((s) {
      final liste = s.data()?['sessizSohbetler'];
      return liste is List && liste.contains(chatId);
    }).distinct();
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
