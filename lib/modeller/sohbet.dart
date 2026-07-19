import 'package:cloud_firestore/cloud_firestore.dart';

/// Bir sohbeti temsil eder. Firestore `chats/{chatId}` dokümanı.
/// chatId = iki uid'den sıralı üretilir (ciftKimligi) → mükerrer sohbet olmaz.
///
/// Yapı (FAZ 4.4):
///   katilimcilar     : [uid1, uid2]
///   sonMesaj         : önizleme metni
///   sonMesajZamani   : sıralama için
///   sonMesajGonderen : kim yazdı
///   okunmamis        : {uid: adet}
class Sohbet {
  final String chatId;
  final List<String> katilimcilar;
  final String sonMesaj;
  final DateTime? sonMesajZamani;
  final String? sonMesajGonderen;
  final Map<String, int> okunmamis;

  /// Kimlerin şu an yazdığı: {uid: true}
  final Map<String, bool> yaziyor;

  const Sohbet({
    required this.chatId,
    required this.katilimcilar,
    this.sonMesaj = '',
    this.sonMesajZamani,
    this.sonMesajGonderen,
    this.okunmamis = const {},
    this.yaziyor = const {},
  });

  factory Sohbet.firestoreDan(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return Sohbet(
      chatId: doc.id,
      katilimcilar:
          (d['katilimcilar'] as List?)?.cast<String>() ?? const [],
      sonMesaj: (d['sonMesaj'] ?? '') as String,
      sonMesajZamani: (d['sonMesajZamani'] as Timestamp?)?.toDate(),
      sonMesajGonderen: d['sonMesajGonderen'] as String?,
      okunmamis: (d['okunmamis'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const {},
      yaziyor: (d['yaziyor'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v == true),
          ) ??
          const {},
    );
  }

  /// Bendeki okunmamış mesaj sayısı.
  int benimOkunmamis(String uid) => okunmamis[uid] ?? 0;

  /// Karşı tarafın uid'i (iki kişilik sohbet).
  String digerKatilimci(String uid) =>
      katilimcilar.firstWhere((u) => u != uid, orElse: () => '');

  /// Karşı taraf bu sohbette yazıyor mu?
  bool digerYaziyor(String uid) => yaziyor[digerKatilimci(uid)] == true;
}
