import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/kullanici.dart';
import 'bildirim_servisi.dart';
import 'kullanici_servisi.dart';

/// Arkadaşlık: istek gönder/kabul/red/iptal, arkadaş listesi, ilişki durumu.
///
/// Koleksiyonlar:
///   friend_requests/{gonderen}_{alan} → istek (aynı yön mükerrer olmasın diye
///                                        kimlik deterministik)
///   friendships/{ciftKimligi}         → {uidler:[a,b], tarih}
class ArkadasServisi {
  ArkadasServisi._();
  static final ArkadasServisi instance = ArkadasServisi._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _istekler =>
      _db.collection('friend_requests');
  CollectionReference<Map<String, dynamic>> get _friendships =>
      _db.collection('friendships');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String _istekId(String gonderen, String alan) => '${gonderen}_$alan';

  /// İki kişi arkadaş mı?
  Future<bool> arkadasMi(String digerUid) async {
    final me = _uid;
    if (me == null) return false;
    return (await _friendships.doc(ciftKimligi(me, digerUid)).get()).exists;
  }

  /// Bir kullanıcıyla ilişki durumumu (buton metni için) hesaplar.
  Future<IliskiDurumu> iliskiDurumu(String digerUid) async {
    final me = _uid;
    if (me == null) return IliskiDurumu.yok;
    if (me == digerUid) return IliskiDurumu.benim;
    if (await arkadasMi(digerUid)) return IliskiDurumu.arkadas;
    // Ben gönderdim mi?
    if ((await _istekler.doc(_istekId(me, digerUid)).get()).exists) {
      return IliskiDurumu.istekGonderdim;
    }
    // Bana geldi mi?
    if ((await _istekler.doc(_istekId(digerUid, me)).get()).exists) {
      return IliskiDurumu.istekGeldi;
    }
    return IliskiDurumu.yok;
  }

  /// İstek gönder. Kendine gönderemez; zaten arkadaş/istek varsa engellenir.
  /// Karşı tarafa bildirim atar.
  Future<void> istekGonder(String alanUid) async {
    final me = _uid;
    if (me == null || me == alanUid) return;
    if (await arkadasMi(alanUid)) return;

    // Ters yönde bekleyen istek varsa: doğrudan kabul et (karşılıklı istek)
    final tersId = _istekId(alanUid, me);
    if ((await _istekler.doc(tersId).get()).exists) {
      await kabulEt(ArkadaslikIstegi(
        id: tersId,
        gonderenUid: alanUid,
        alanUid: me,
        durum: 'bekliyor',
      ));
      return;
    }

    await _istekler.doc(_istekId(me, alanUid)).set({
      'gonderenUid': me,
      'alanUid': alanUid,
      'durum': 'bekliyor',
      'tarih': FieldValue.serverTimestamp(),
    });

    // Bildirim (fire-and-forget)
    final ben = await KullaniciServisi.instance.profilGetir(me);
    BildirimServisi.instance.hedefeBildirimGonder(
      hedefUid: alanUid,
      baslik: ben?.ad ?? 'Yeni istek',
      govde: 'sana arkadaşlık isteği gönderdi',
    );
  }

  /// İsteği kabul et: arkadaşlık oluştur + isteği sil (transaction).
  Future<void> kabulEt(ArkadaslikIstegi istek) async {
    final me = _uid;
    if (me == null) return;
    final fId = ciftKimligi(istek.gonderenUid, istek.alanUid);
    await _db.runTransaction((tx) async {
      tx.set(_friendships.doc(fId), {
        'uidler': [istek.gonderenUid, istek.alanUid],
        'tarih': FieldValue.serverTimestamp(),
      });
      tx.delete(_istekler.doc(istek.id));
    });

    // Kabul edildi bildirimi (isteği gönderen kişiye)
    final ben = await KullaniciServisi.instance.profilGetir(me);
    BildirimServisi.instance.hedefeBildirimGonder(
      hedefUid: istek.gonderenUid,
      baslik: ben?.ad ?? 'Arkadaşlık',
      govde: 'arkadaşlık isteğini kabul etti 🎉',
    );
  }

  /// İsteği reddet: sadece sil (nazik — gönderene bildirim gitmez).
  Future<void> reddet(ArkadaslikIstegi istek) async {
    await _istekler.doc(istek.id).delete();
  }

  /// Kendi gönderdiğim isteği iptal et.
  Future<void> iptalEt(ArkadaslikIstegi istek) async {
    await _istekler.doc(istek.id).delete();
  }

  /// Arkadaşlıktan çıkar (iki yönlü tek doküman siler).
  Future<void> arkadasCikar(String digerUid) async {
    final me = _uid;
    if (me == null) return;
    await _friendships.doc(ciftKimligi(me, digerUid)).delete();
  }

  /// Bana gelen bekleyen istekler (canlı).
  Stream<List<ArkadaslikIstegi>> gelenIstekler() {
    final me = _uid;
    if (me == null) return const Stream.empty();
    return _istekler.where('alanUid', isEqualTo: me).snapshots().map((s) => s
        .docs
        .map(ArkadaslikIstegi.firestoreDan)
        .where((i) => i.durum == 'bekliyor')
        .toList());
  }

  /// Benim gönderdiğim bekleyen istekler (canlı).
  Stream<List<ArkadaslikIstegi>> gidenIstekler() {
    final me = _uid;
    if (me == null) return const Stream.empty();
    return _istekler.where('gonderenUid', isEqualTo: me).snapshots().map((s) => s
        .docs
        .map(ArkadaslikIstegi.firestoreDan)
        .where((i) => i.durum == 'bekliyor')
        .toList());
  }

  /// Arkadaşlarım (canlı) — profil listesi olarak.
  Stream<List<Kullanici>> arkadaslar() {
    final me = _uid;
    if (me == null) return const Stream.empty();
    return _friendships
        .where('uidler', arrayContains: me)
        .snapshots()
        .asyncMap((snap) async {
      final digerUidler = snap.docs
          .map((d) => (d.data()['uidler'] as List)
              .cast<String>()
              .firstWhere((u) => u != me, orElse: () => ''))
          .where((u) => u.isNotEmpty)
          .toList();
      final profiller = await Future.wait(
        digerUidler.map(KullaniciServisi.instance.profilGetir),
      );
      return profiller.whereType<Kullanici>().toList();
    });
  }
}
