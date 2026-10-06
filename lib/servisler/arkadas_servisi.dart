import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/arkadaslik.dart';
import '../modeller/kullanici.dart';
import 'bildirim_servisi.dart';
import 'hata_servisi.dart';
import 'kullanici_servisi.dart';

/// [liste]yi en fazla [boyut] elemanlı ardışık gruplara böler (saf → test).
List<List<T>> gruplaraBol<T>(List<T> liste, int boyut) {
  assert(boyut > 0);
  return [
    for (var i = 0; i < liste.length; i += boyut)
      liste.sublist(i, i + boyut > liste.length ? liste.length : i + boyut),
  ];
}

/// [anahtarlar]ı [grupBoyutu]'luk gruplar hâlinde [grupGetir] ile PARALEL
/// okur ve sonuçları [anahtarlar] SIRASIYLA döndürür (saf → test).
///  - Boş liste → hiç sorgu atılmaz.
///  - Bir grup hata verirse YALNIZ o grup atlanır ([hatada] çağrılır); diğer
///    grupların sonucu yine döner (tüm akış hataya düşmez).
///  - Haritada karşılığı olmayan anahtar (silinmiş/okunamayan belge) atlanır.
Future<List<V>> gruplarHalindeGetir<V>({
  required List<String> anahtarlar,
  required Future<Map<String, V>> Function(List<String> grup) grupGetir,
  int grupBoyutu = KullaniciServisi.whereInSiniri,
  void Function(Object hata, List<String> grup)? hatada,
}) async {
  if (anahtarlar.isEmpty) return <V>[];
  final sonuclar = await Future.wait(
    gruplaraBol(anahtarlar, grupBoyutu).map((grup) async {
      try {
        return await grupGetir(grup);
      } catch (e) {
        hatada?.call(e, grup);
        return <String, V>{};
      }
    }),
  );
  final hepsi = <String, V>{for (final m in sonuclar) ...m};
  return [for (final a in anahtarlar) ?hepsi[a]];
}

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

  /// Bir dokümanın var olup olmadığını GÜVENLE döndürür.
  /// Var olmayan dokümanın okuması kural gereği permission-denied verebilir;
  /// bu bizim için "yok" demektir → hatayı yutup false döneriz (sonsuz loading
  /// yerine). Bkz. iliskiDurumu.
  Future<bool> _belgeVarMi(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return (await ref.get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// İki kişi arkadaş mı?
  Future<bool> arkadasMi(String digerUid) async {
    final me = _uid;
    if (me == null) return false;
    return _belgeVarMi(_friendships.doc(ciftKimligi(me, digerUid)));
  }

  /// Bir kullanıcıyla ilişki durumumu (buton metni için) hesaplar.
  /// Tüm okumalar [_belgeVarMi] ile güvenli — var olmayan doküman / izin hatası
  /// "ilişki yok" olarak ele alınır (asla exception fırlatıp UI'ı dondurmaz).
  Future<IliskiDurumu> iliskiDurumu(String digerUid) async {
    final me = _uid;
    if (me == null) return IliskiDurumu.yok;
    if (me == digerUid) return IliskiDurumu.benim;
    if (await arkadasMi(digerUid)) return IliskiDurumu.arkadas;
    // Ben gönderdim mi?
    if (await _belgeVarMi(_istekler.doc(_istekId(me, digerUid)))) {
      return IliskiDurumu.istekGonderdim;
    }
    // Bana geldi mi?
    if (await _belgeVarMi(_istekler.doc(_istekId(digerUid, me)))) {
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

    // Bildirim (fire-and-forget) — bkz. [_bildirimGonder].
    unawaited(_bildirimGonder(
      me: me,
      hedefUid: alanUid,
      varsayilanBaslik: 'Yeni istek',
      govde: 'sana arkadaşlık isteği gönderdi',
    ));
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
    unawaited(_bildirimGonder(
      me: me,
      hedefUid: istek.gonderenUid,
      varsayilanBaslik: 'Arkadaşlık',
      govde: 'arkadaşlık isteğini kabul etti 🎉',
    ));
  }

  /// Arkadaşlık bildirimini (gönderenin adıyla) yollar. ASLA fırlatmaz.
  ///
  /// ⚠️ Eskiden istek YAZILDIKTAN / transaction BİTTİKTEN sonra profil
  /// okuması `await` ediliyordu: o okuma hata verirse (çevrimdışı vb.)
  /// [istekGonder]/[kabulEt] fırlatıyor, ekran "İşlem yapılamadı" diyordu —
  /// oysa istek/arkadaşlık SUNUCUDA OLUŞMUŞTU (kullanıcı tekrar deneyince
  /// kafa karıştırıcı sonuçlar). Ayrıca bildirim hazırlığı UI'ı bekletiyordu.
  Future<void> _bildirimGonder({
    required String me,
    required String hedefUid,
    required String varsayilanBaslik,
    required String govde,
  }) async {
    try {
      final ben = await KullaniciServisi.instance.profilGetir(me);
      await BildirimServisi.instance.hedefeBildirimGonder(
        hedefUid: hedefUid,
        baslik: ben?.ad ?? varsayilanBaslik,
        govde: govde,
      );
    } catch (e) {
      HataServisi.instance.iz('ARKADAS bildirimi gonderilemedi: $e');
    }
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

  // ═══════════════ ENGELLEME ═══════════════
  // Doküman kimliği = ciftKimligi (friendships/chats ile AYNI) → A'nın B'yi
  // engellemesi ile B'nin A'yı engellemesi TEK dokümandır. Engel varken
  // İKİ TARAF da mesaj atamaz ve arama başlatamaz (kural: firestore.rules
  // `engelli()`), ama eski geçmiş görünmeye devam eder.

  CollectionReference<Map<String, dynamic>> get _engeller =>
      _db.collection('engellenenler');

  /// Bu kişiyle aramda engel var mı ve varsa KİM koydu (canlı).
  /// null → engel yok. Değer → engeli koyanın uid'i.
  Stream<String?> engelDinle(String digerUid) {
    final me = _uid;
    if (me == null) return Stream<String?>.value(null);
    return _engeller
        .doc(ciftKimligi(me, digerUid))
        .snapshots()
        // Hata (izin/ağ) engeli VAR saymamalı — aksi halde ağ titrerse sohbet
        // kilitlenmiş görünür. Sessizce "engel yok" döner, kural yine korur.
        .handleError((_) {})
        .map((d) => d.exists ? (d.data()?['engelleyen'] as String?) : null);
  }

  /// Engeli koyan kişinin uid'i (tek seferlik okuma). null → engel yok.
  Future<String?> engelKoyan(String digerUid) async {
    final me = _uid;
    if (me == null) return null;
    try {
      final d = await _engeller.doc(ciftKimligi(me, digerUid)).get();
      return d.exists ? (d.data()?['engelleyen'] as String?) : null;
    } catch (_) {
      return null;
    }
  }

  /// Kişiyi engelle. Arkadaşlık BOZULMAZ (kaldırınca sohbet kaldığı yerden
  /// devam etsin); yalnızca yeni mesaj/arama durur.
  Future<void> engelle(String digerUid) async {
    final me = _uid;
    if (me == null) return;
    await _engeller.doc(ciftKimligi(me, digerUid)).set({
      'uidler': [me, digerUid]..sort(),
      'engelleyen': me,
      'zaman': FieldValue.serverTimestamp(),
    });
  }

  /// Engeli kaldır. ⚠️ Kural gereği yalnızca engeli KOYAN silebilir; karşı
  /// taraf çağırırsa permission-denied alır (istemcide de buton gizlenir).
  Future<void> engelKaldir(String digerUid) async {
    final me = _uid;
    if (me == null) return;
    await _engeller.doc(ciftKimligi(me, digerUid)).delete();
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

  /// Arkadaşlarım (canlı) — profil listesi olarak (friendships sırasıyla).
  ///
  /// ⚠️ Eskiden HER anlık görüntüde arkadaş başına ayrı `get()` atılıyordu
  /// (N arkadaş = N okuma + N gidiş-dönüş) ve TEK bir okuma hatası tüm akışı
  /// hataya düşürüyordu (ekranda liste yerine hata). Artık `whereIn`
  /// (FieldPath.documentId) ile 30'arlık gruplar hâlinde okunur; hata veren
  /// grup atlanıp ize yazılır, geri kalan arkadaşlar yine görünür.
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
      return gruplarHalindeGetir<Kullanici>(
        anahtarlar: digerUidler,
        grupGetir: KullaniciServisi.instance.profilGrubuGetir,
        hatada: (e, grup) => HataServisi.instance
            .iz('ARKADAS profilleri okunamadi (${grup.length} kisi): $e'),
      );
    });
  }
}
