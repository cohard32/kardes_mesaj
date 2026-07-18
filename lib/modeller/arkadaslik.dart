import 'package:cloud_firestore/cloud_firestore.dart';

/// İki uid'den DETERMİNİSTİK (sıralı) tek kimlik üretir.
/// Aynı çift için hep aynı değer → hem `friendships/{id}` hem `chats/{chatId}`
/// hem `aramalar/{id}` için kullanılır (mükerrer kayıt olmaz).
String ciftKimligi(String uid1, String uid2) {
  final s = [uid1, uid2]..sort();
  return '${s[0]}_${s[1]}';
}

/// Arama sonucunda bir kullanıcıyla ilişkimin durumu (buton metni buna göre).
enum IliskiDurumu { yok, arkadas, istekGonderdim, istekGeldi, benim }

/// Arkadaşlık isteği — `friend_requests/{gonderenUid}_{alanUid}` dokümanı.
class ArkadaslikIstegi {
  final String id;
  final String gonderenUid;
  final String alanUid;
  final String durum; // bekliyor / kabul / red
  final DateTime? tarih;

  const ArkadaslikIstegi({
    required this.id,
    required this.gonderenUid,
    required this.alanUid,
    required this.durum,
    this.tarih,
  });

  factory ArkadaslikIstegi.firestoreDan(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return ArkadaslikIstegi(
      id: doc.id,
      gonderenUid: (d['gonderenUid'] ?? '') as String,
      alanUid: (d['alanUid'] ?? '') as String,
      durum: (d['durum'] ?? 'bekliyor') as String,
      tarih: (d['tarih'] as Timestamp?)?.toDate(),
    );
  }
}
