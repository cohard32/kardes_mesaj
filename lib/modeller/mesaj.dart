import 'package:cloud_firestore/cloud_firestore.dart';

import '../yardimcilar/link_metni.dart';
import '../yardimcilar/mesaj_metni.dart';

/// Tek bir mesajı temsil eder. Firestore'daki `mesajlar` koleksiyonundaki
/// bir dokümana karşılık gelir.
///
/// Yapı (PROJECT.md 1.3):
///   gonderen: gönderenin uid'i
///   metin:    mesaj içeriği
///   zaman:    sunucu zaman damgası
///   goruldu:  karşı taraf gördü mü
/// Mesaj türü: düz metin, bir medya (resim/video/ses/gif/sticker), cevapsız
/// arama kaydı ya da dosya (PDF vb.).
///
/// ⚠️ Eski sürümler bilmedikleri türü METİN sayar ve `metin` alanını
/// gösterir → yeni türlerde `metin` her zaman okunur bir özet taşır
/// ("📞 Cevapsız sesli arama", "📎 rapor.pdf").
enum MesajTipi { metin, resim, video, ses, gif, arama, dosya }

class Mesaj {
  final String id;
  final String gonderen;
  final String metin;
  final DateTime? zaman;
  final bool goruldu;
  /// ESKİ tek tepki alanı (1.9.0 öncesi sürümler yazar). Kimin verdiği
  /// bilinmez; iki kişi tepki verince biri diğerinin yerine geçiyordu.
  /// Yeni sürüm [tepkiler]'e yazar; bu alan yalnız GÖSTERİLİR.
  final String? tepki;

  /// HER KİŞİNİN AYRI tepkisi: uid → emoji. Herkes yalnız kendi anahtarını
  /// değiştirebilir (firestore.rules → tepkilerGecerli).
  final Map<String, String> tepkiler;
  final MesajTipi tip; // metin / resim / video / ses / gif
  final String? medyaUrl; // resim/video/ses Cloudinary URL'i veya GIPHY GIF URL'i
  final bool sesDinlendi; // sesli mesaj karşı tarafça dinlendi mi

  // YANIT (alıntı). Alıntılanan mesajın önizlemesi YAZIM ANINDA kopyalanır:
  // balonu çizmek için asıl mesajı ayrıca okumak gerekmez (kota) ve asıl
  // mesaj silinse / sayfalamayla listede yüklü olmasa bile alıntı görünür.
  final String? yanitId; // alıntılanan mesajın kimliği
  final String? yanitOnizleme; // ≤120 karakter metin veya "📷 Fotoğraf" vb.
  final String? yanitGonderen; // alıntılanan mesajın göndereninin uid'i

  /// Cevapsız arama kaydı ([MesajTipi.arama]): 'ses' | 'video'.
  final String? aramaTipi;

  /// Arama neden bağlanmadı: 'cevapsiz' | 'red' | 'mesgul' | 'iptal'.
  final String? aramaSonucu;

  /// Dosya mesajı ([MesajTipi.dosya]): özgün dosya adı ve boyutu (bayt).
  final String? dosyaAdi;
  final int? dosyaBoyutu;

  /// Mesaj gönderildikten sonra düzenlendi mi (balonda "düzenlendi" yazar).
  /// Sunucu damgası kuralda doğrulanır → sahte etiket yazılamaz.
  final bool duzenlendi;

  Mesaj({
    required this.id,
    required this.gonderen,
    required this.metin,
    this.zaman,
    this.goruldu = false,
    this.tepki,
    this.tepkiler = const {},
    this.tip = MesajTipi.metin,
    this.medyaUrl,
    this.sesDinlendi = false,
    this.yanitId,
    this.yanitOnizleme,
    this.yanitGonderen,
    this.duzenlendi = false,
    this.aramaTipi,
    this.aramaSonucu,
    this.dosyaAdi,
    this.dosyaBoyutu,
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
      tepki: _metinMi(d['tepki']),
      tepkiler: _tepkilerCoz(d['tepkiler']),
      tip: _tipCoz(d['tip'] as String?),
      medyaUrl: d['medyaUrl'] as String?,
      sesDinlendi: (d['sesDinlendi'] ?? false) as bool,
      // `as String?` yerine tip denetimi: bozuk/eski bir doküman tüm mesaj
      // akışını TypeError ile düşürmesin (alıntı sadece görünmez).
      yanitId: _metinMi(d['yanitId']),
      yanitOnizleme: _metinMi(d['yanitOnizleme']),
      yanitGonderen: _metinMi(d['yanitGonderen']),
      duzenlendi: d['duzenlendi'] != null,
      aramaTipi: _metinMi(d['aramaTipi']),
      aramaSonucu: _metinMi(d['aramaSonucu']),
      dosyaAdi: _metinMi(d['dosyaAdi']),
      dosyaBoyutu: d['dosyaBoyutu'] is int ? d['dosyaBoyutu'] as int : null,
    );
  }

  static String? _metinMi(Object? v) => v is String ? v : null;

  // Bozuk/eski girdiler (metin olmayan değer) atlanır; akış düşmesin.
  static Map<String, String> _tepkilerCoz(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
          e.key as String: e.value as String,
    };
  }

  /// Balonda tepki rozeti gösterilecek mi?
  bool get tepkiVar => tepkiler.isNotEmpty || tepki != null;

  /// Balonun altındaki rozet: her emoji ve kaç kişiden geldiği (ilk görülme
  /// sırasıyla). Eski tek alan ([tepki]) de sayılır — eski sürümlerden gelen
  /// tepkiler kaybolmasın.
  List<({String emoji, int sayi})> get tepkiOzeti {
    final sayac = <String, int>{};
    for (final e in [...tepkiler.values, ?tepki]) {
      sayac[e] = (sayac[e] ?? 0) + 1;
    }
    return [for (final e in sayac.entries) (emoji: e.key, sayi: e.value)];
  }

  /// Medya türünün listede/bildirimde/alıntıda görünen etiketi.
  static String medyaEtiketi(MesajTipi tip) => switch (tip) {
        MesajTipi.resim => '📷 Fotoğraf',
        MesajTipi.video => '🎥 Video',
        MesajTipi.ses => '🎤 Sesli mesaj',
        MesajTipi.gif => '🎞️ GIF',
        MesajTipi.arama => '📞 Arama',
        MesajTipi.dosya => '📎 Dosya',
        MesajTipi.metin => 'Mesaj',
      };

  /// Video aramaysa true (cevapsız arama kaydı).
  bool get videoAramaMi => aramaTipi == 'video';

  /// Sohbet listesi / yanıt önizlemesi: metinse metnin kendisi; açıklamalı
  /// fotoğraf/videoda "📷 açıklama"; dosyada "📎 ad"; aramada kaydın
  /// kendi metni; diğer medyada etiketi.
  String get onizleme => switch (tip) {
        MesajTipi.metin => metin,
        MesajTipi.arama =>
          metin.isNotEmpty ? metin : medyaEtiketi(MesajTipi.arama),
        MesajTipi.dosya => '📎 ${dosyaAdi ?? 'Dosya'}',
        MesajTipi.resim when metin.trim().isNotEmpty => '📷 ${metin.trim()}',
        MesajTipi.video when metin.trim().isNotEmpty => '🎥 ${metin.trim()}',
        _ => medyaEtiketi(tip),
      };

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
      case 'arama':
        return MesajTipi.arama;
      case 'dosya':
        return MesajTipi.dosya;
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
      // Medya galerisinin "Linkler" sekmesi bu işaretle sorgular.
      if (linkIceriyor(metin)) 'link': true,
      ...yanitAlanlari(yanit),
    };
  }

  /// Cevapsız arama kaydının metni (eski sürümler bu metni gösterir).
  static String aramaKaydiMetni({required bool video}) =>
      video ? '📹 Cevapsız görüntülü arama' : '📞 Cevapsız sesli arama';

  /// ARAYANIN yazdığı cevapsız arama kaydı ([MesajTipi.arama]).
  /// [sonuc]: 'cevapsiz' | 'red' | 'mesgul' | 'iptal' (kural doğrular).
  static Map<String, dynamic> aramaKaydiVerisi({
    required String gonderen,
    required bool video,
    required String sonuc,
  }) {
    return {
      'gonderen': gonderen,
      'metin': aramaKaydiMetni(video: video),
      'tip': MesajTipi.arama.name,
      'aramaTipi': video ? 'video' : 'ses',
      'aramaSonucu': sonuc,
      'zaman': FieldValue.serverTimestamp(),
      'goruldu': false,
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
