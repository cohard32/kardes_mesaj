import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir mesajı temsil eder. Firestore'daki `mesajlar` koleksiyonundaki
/// bir dokümana karşılık gelir.
///
/// Yapı (PROJECT.md 1.3):
///   gonderen: gönderenin uid'i
///   metin:    mesaj içeriği
///   zaman:    sunucu zaman damgası
///   goruldu:  karşı taraf gördü mü
class Mesaj {
  final String id;
  final String gonderen;
  final String metin;
  final DateTime? zaman;
  final bool goruldu;
  final String? tepki; // mesaja verilen emoji tepkisi (👍 ❤️ ...) veya null

  Mesaj({
    required this.id,
    required this.gonderen,
    required this.metin,
    this.zaman,
    this.goruldu = false,
    this.tepki,
  });

  /// Firestore dokümanından Mesaj nesnesi üretir.
  factory Mesaj.firestoreDan(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return Mesaj(
      id: doc.id,
      gonderen: (d['gonderen'] ?? '') as String,
      metin: (d['metin'] ?? '') as String,
      zaman: (d['zaman'] as Timestamp?)?.toDate(),
      goruldu: (d['goruldu'] ?? false) as bool,
      tepki: d['tepki'] as String?,
    );
  }

  /// Firestore'a yazılacak harita. Zaman sunucu tarafında atanır.
  static Map<String, dynamic> yeniMesajVerisi({
    required String gonderen,
    required String metin,
  }) {
    return {
      'gonderen': gonderen,
      'metin': metin,
      'zaman': FieldValue.serverTimestamp(),
      'goruldu': false,
    };
  }
}
