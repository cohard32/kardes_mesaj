import 'package:cloud_firestore/cloud_firestore.dart';

import '../yardimcilar/mesaj_metni.dart';

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

  // YANIT (alıntı). Alıntılanan mesajın önizlemesi YAZIM ANINDA kopyalanır:
  // balonu çizmek için asıl mesajı ayrıca okumak gerekmez (kota) ve asıl
  // mesaj silinse / sayfalamayla listede yüklü olmasa bile alıntı görünür.
  final String? yanitId; // alıntılanan mesajın kimliği
  final String? yanitOnizleme; // ≤120 karakter metin veya "📷 Fotoğraf" vb.
  final String? yanitGonderen; // alıntılanan mesajın göndereninin uid'i

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
    this.yanitId,
    this.yanitOnizleme,
    this.yanitGonderen,
  });

  /// Bu mesaj bir yanıt mı (balonda alıntı kutusu çizilsin mi)?
  bool get yanitMi => yanitOnizleme != null;

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
      // `as String?` yerine tip denetimi: bozuk/eski bir doküman tüm mesaj
      // akışını TypeError ile düşürmesin (alıntı sadece görünmez).
      yanitId: _metinMi(d['yanitId']),
      yanitOnizleme: _metinMi(d['yanitOnizleme']),
      yanitGonderen: _metinMi(d['yanitGonderen']),
    );
  }

  static String? _metinMi(Object? v) => v is String ? v : null;

  /// Medya türünün listede/bildirimde/alıntıda görünen etiketi.
  static String medyaEtiketi(MesajTipi tip) => switch (tip) {
        MesajTipi.resim => '📷 Fotoğraf',
        MesajTipi.video => '🎥 Video',
        MesajTipi.ses => '🎤 Sesli mesaj',
        MesajTipi.gif => '🎞️ GIF',
        MesajTipi.metin => 'Mesaj',
      };

  /// Sohbet listesi önizlemesi: metinse metnin kendisi, medyaysa etiketi.
  String get onizleme => tip == MesajTipi.metin ? metin : medyaEtiketi(tip);

  /// Bu mesaja yanıt verilirken saklanacak alıntı önizlemesi (tek satır,
  /// en fazla [yanitOnizlemeSiniri] karakter — kural da bunu doğrular).
  String get yanitIcinOnizleme {
    final o = tekSatiraKisalt(onizleme);
    return o.isEmpty ? 'Mesaj' : o;
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

  /// Düz metin mesajı için Firestore verisi. [yanit] verilirse alıntı
  /// alanları eklenir (firestore.rules messages create izin listesinde).
  static Map<String, dynamic> yeniMesajVerisi({
    required String gonderen,
    required String metin,
    Mesaj? yanit,
  }) {
    return {
      'gonderen': gonderen,
      'metin': metin,
      'tip': 'metin',
      'zaman': FieldValue.serverTimestamp(),
      'goruldu': false,
      ...yanitAlanlari(yanit),
    };
  }

  /// Alıntı alanları (yanıt yoksa boş). Ayrı tutuldu: Firestore'suz test
  /// edilebilsin (serverTimestamp içermez).
  static Map<String, String> yanitAlanlari(Mesaj? yanit) {
    if (yanit == null) return const {};
    return {
      'yanitId': yanit.id,
      'yanitOnizleme': yanit.yanitIcinOnizleme,
      'yanitGonderen': yanit.gonderen,
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
