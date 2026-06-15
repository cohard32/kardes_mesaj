import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir mesajı temsil eder. Firestore'daki `mesajlar` koleksiyonundaki
/// bir dokümana karşılık gelir.
///
/// Yapı (PROJECT.md 1.3):
///   gonderen: gönderenin uid'i
///   metin:    mesaj içeriği
///   zaman:    sunucu zaman damgası
///   goruldu:  karşı taraf gördü mü
/// Mesaj türü: düz metin veya bir medya (resim/video/ses/gif/sticker).
enum MesajTipi { metin, resim, video, ses, gif }

class Mesaj {
  final String id;
  final String gonderen;
  final String metin;
  final DateTime? zaman;
  final bool goruldu;
  final String? tepki; // mesaja verilen emoji tepkisi (👍 ❤️ ...) veya null
  final MesajTipi tip; // metin / resim / video / ses / gif
  final String? medyaUrl; // resim/video/ses Cloudinary URL'i veya GIPHY GIF URL'i
  final bool sesDinlendi; // sesli mesaj karşı tarafça dinlendi mi

  Mesaj({
    required this.id,
    required this.gonderen,
    required this.metin,
    this.zaman,
    this.goruldu = false,
    this.tepki,
    this.tip = MesajTipi.metin,
    this.medyaUrl,
    this.sesDinlendi = false,
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
      tip: _tipCoz(d['tip'] as String?),
      medyaUrl: d['medyaUrl'] as String?,
      sesDinlendi: (d['sesDinlendi'] ?? false) as bool,
    );
  }

  static MesajTipi _tipCoz(String? s) {
    switch (s) {
      case 'resim':
        return MesajTipi.resim;
      case 'video':
        return MesajTipi.video;
      case 'ses':
        return MesajTipi.ses;
      case 'gif':
        return MesajTipi.gif;
      default:
        return MesajTipi.metin;
    }
  }

  /// Düz metin mesajı için Firestore verisi.
  static Map<String, dynamic> yeniMesajVerisi({
    required String gonderen,
    required String metin,
  }) {
    return {
      'gonderen': gonderen,
      'metin': metin,
      'tip': 'metin',
      'zaman': FieldValue.serverTimestamp(),
      'goruldu': false,
    };
  }

  /// Medya (resim/video/ses) mesajı için Firestore verisi.
  static Map<String, dynamic> yeniMedyaVerisi({
    required String gonderen,
    required MesajTipi tip,
    required String medyaUrl,
    String metin = '',
  }) {
    return {
      'gonderen': gonderen,
      'metin': metin,
      'tip': tip.name,
      'medyaUrl': medyaUrl,
      'zaman': FieldValue.serverTimestamp(),
      'goruldu': false,
    };
  }
}
