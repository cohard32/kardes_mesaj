import 'package:cloud_firestore/cloud_firestore.dart';

import '../yardimcilar/onemli_gun.dart';
import '../yardimcilar/tr_metin.dart';

/// Bir kullanıcıyı temsil eder. Firestore'daki `users/{uid}` dokümanı.
///
/// Yapı (FAZ 4.4):
///   ad           : görünen isim
///   kullaniciAdi : benzersiz @kullanıcı adı (usernames koleksiyonu garanti eder)
///   fotoUrl      : profil fotoğrafı (Cloudinary URL'i) — opsiyonel
///   bio          : durum/hakkında yazısı — opsiyonel
///   fcmToken     : bildirim token'ı (hassas — kurallarda korunur)
///   cevrimici    : istemcinin yazdığı HAM bayrak (bkz. [cevrimiciHam])
///   sonGorulme   : son çevrimiçi zamanı (nabızla 60 sn'de bir tazelenir)
class Kullanici {
  final String uid;
  final String ad;
  final String kullaniciAdi;
  final String? fotoUrl;
  final String? bio;

  /// Doğum günü "AA-GG" (yıl yok — yaş gizli). Arkadaşların hatırlatıcısı
  /// buradan kurulur. Ayarlanmamışsa null.
  final String? dogumGunu;

  /// Firestore'daki ham `cevrimici` alanı — TEK BAŞINA GÜVENİLMEZ.
  /// ⚠️ Uygulama öldürülünce `detached` güvenilir gelmez, `cevrimdisiYap`
  /// hiç çalışmaz ve bu alan SONSUZA KADAR true kalıyordu ("hep çevrimiçi"
  /// görünen kullanıcı). UI bunun yerine hesaplanan [cevrimici]'yi kullanır.
  final bool cevrimiciHam;
  final DateTime? sonGorulme;

  /// Ham bayrak true olsa bile sonGorulme bundan eskiyse çevrimdışı sayılır.
  /// Nabız (PresenceServisi.nabziBaslat) 60 sn'de bir yazar → 150 sn, bir
  /// nabzın kaçması/geç gelmesi (ağ gecikmesi, kısa kopma) için pay bırakır.
  static const cevrimiciEsigi = Duration(seconds: 150);

  /// Yerel saat → sunucu saati düzeltmesi (sunucu − yerel). PresenceServisi
  /// kendi yazdığı sunucu damgasından ölçer; ölçülemezse sıfır kalır.
  /// ⚠️ Neden: sonGorulme SUNUCU saatidir, "şimdi" ise TELEFON saati. Saati
  /// 2 dk ileri olan bir telefonda herkes çevrimdışı görünürdü.
  static Duration saatDuzeltmesi = Duration.zero;

  // ⚠️ Kurucu parametresinin adı `cevrimici` olarak KALDI (alan adı
  // `cevrimiciHam` oldu): Kullanici.bos, copyWith, firestoreDan ve testler
  // `cevrimici:` ile çağırıyor, hiçbiri değişmek zorunda kalmasın.
  const Kullanici({
    required this.uid,
    required this.ad,
    required this.kullaniciAdi,
    this.fotoUrl,
    this.bio,
    this.dogumGunu,
    bool cevrimici = false,
    this.sonGorulme,
  }) : cevrimiciHam = cevrimici;

  /// Gerçekten çevrimiçi mi? (ham bayrak + sonGorulme tazeliği)
  ///
  /// Getter: alan değil — her build'de o anki saate göre yeniden hesaplanır.
  /// Böylece hiçbir ekran değişmeden (avatar noktası, sohbet başlığı,
  /// profil) öldürülmüş uygulamanın "çevrimiçi"si eşik dolunca düşer.
  ///
  /// ⚠️ Bilinen geçiş etkisi: nabız göndermeyen ESKİ sürümdeki kullanıcılar,
  /// güncellenmiş istemcilerde açılıştan 150 sn sonra (uygulamaları açık olsa
  /// bile) çevrimdışı görünür; herkes güncelleyince düzelir.
  bool get cevrimici => cevrimiciMi();

  /// [cevrimici]'nin saf hâli; testler için [simdi] enjekte edilebilir.
  bool cevrimiciMi([DateTime? simdi]) {
    if (!cevrimiciHam) return false;
    final t = sonGorulme;
    // Sunucu damgası henüz çözülmemiş yerel yazım (serverTimestamp → null):
    // az önce çevrimiçi yazılmış demektir → çevrimiçi say.
    if (t == null) return true;
    final fark = (simdi ?? DateTime.now().add(saatDuzeltmesi)).difference(t);
    // Negatif fark = damga "gelecekte" (yerel saat geride / düzeltme
    // ölçülmemiş). Az önce yazılmış sayılır → çevrimiçi. Saat kayması yüzünden
    // canlı kullanıcıyı çevrimdışı göstermek, tersinden daha kötü.
    if (fark.isNegative) return true;
    return fark <= cevrimiciEsigi;
  }

  /// Hesaplanan çevrimiçilik ne zaman düşecek? (Ekranı tam o anda yeniden
  /// çizdirmek için — PresenceServisi.kullaniciDinle kullanır.) Zaten
  /// çevrimdışıysa ya da düşüş zamanı bilinmiyorsa null.
  Duration? cevrimdisiOlmayaKalan([DateTime? simdi]) {
    final t = sonGorulme;
    if (!cevrimiciHam || t == null) return null;
    final kalan = t
        .add(cevrimiciEsigi)
        .difference(simdi ?? DateTime.now().add(saatDuzeltmesi));
    return kalan.isNegative ? null : kalan;
  }

  /// Firestore dokümanından Kullanici üretir.
  factory Kullanici.firestoreDan(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return Kullanici(
      uid: doc.id,
      ad: (d['ad'] ?? '') as String,
      kullaniciAdi: (d['kullaniciAdi'] ?? '') as String,
      fotoUrl: d['fotoUrl'] as String?,
      bio: d['bio'] as String?,
      // Geçersiz/bozuk değer yok sayılır (akış TypeError ile düşmesin).
      dogumGunu: ayGunCoz(d['dogumGunu']) == null
          ? null
          : d['dogumGunu'] as String,
      cevrimici: (d['cevrimici'] ?? false) as bool,
      sonGorulme: (d['sonGorulme'] as Timestamp?)?.toDate(),
    );
  }

  /// Boş/yükleniyor durumu için yer tutucu.
  factory Kullanici.bos(String uid) =>
      Kullanici(uid: uid, ad: '…', kullaniciAdi: '');

  /// Görünecek baş harf (avatar için). `runes` ile alınır: `[0]` emoji ile
  /// başlayan adlarda vekil çiftin YARISINI verip bozuk karakter çiziyordu.
  String get harf => ad.trim().isNotEmpty
      ? trBuyuk(String.fromCharCode(ad.trim().runes.first))
      : '?';

  Kullanici copyWith({
    String? ad,
    String? fotoUrl,
    String? bio,
  }) =>
      Kullanici(
        uid: uid,
        ad: ad ?? this.ad,
        kullaniciAdi: kullaniciAdi,
        fotoUrl: fotoUrl ?? this.fotoUrl,
        bio: bio ?? this.bio,
        dogumGunu: dogumGunu,
        // Ham değer taşınır; hesaplanan getter kopyada da güncel kalır.
        cevrimici: cevrimiciHam,
        sonGorulme: sonGorulme,
      );
}
