/// Doğum günü / önemli gün yardımcıları (saf — bkz. test/onemli_gun_test.dart).
library;

const List<String> ayAdlari = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// Ayın gün sayısı (Şubat 29 kabul edilir: 29 Şubat doğumlular seçebilsin).
int ayinGunSayisi(int ay) => const [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][ay - 1];

bool gecerliAyGun(int ay, int gun) =>
    ay >= 1 && ay <= 12 && gun >= 1 && gun <= ayinGunSayisi(ay);

/// Firestore'daki "AA-GG" biçimi (yıl SAKLANMAZ — yaş gizli kalır).
String ayGunYaz(int ay, int gun) =>
    '${ay.toString().padLeft(2, '0')}-${gun.toString().padLeft(2, '0')}';

/// "AA-GG" → (ay, gün); geçersizse null.
({int ay, int gun})? ayGunCoz(Object? deger) {
  if (deger is! String) return null;
  final m = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(deger);
  if (m == null) return null;
  final ay = int.parse(m.group(1)!), gun = int.parse(m.group(2)!);
  return gecerliAyGun(ay, gun) ? (ay: ay, gun: gun) : null;
}

/// "15 Temmuz"
String ayGunMetni(int ay, int gun) => '$gun ${ayAdlari[ay - 1]}';

/// [simdi]den itibaren bu ay/günün bir SONRAKİ tarihi (bugünse bugün).
/// 29 Şubat artık yıl olmayan yıllarda 28 Şubat sayılır.
DateTime sonrakiTarih(int ay, int gun, DateTime simdi) {
  DateTime yilda(int yil) {
    final artik = (yil % 4 == 0 && yil % 100 != 0) || yil % 400 == 0;
    final g = (ay == 2 && gun == 29 && !artik) ? 28 : gun;
    return DateTime(yil, ay, g);
  }

  final bugun = DateTime(simdi.year, simdi.month, simdi.day);
  final buYil = yilda(simdi.year);
  return buYil.isBefore(bugun) ? yilda(simdi.year + 1) : buYil;
}

/// Kaç gün kaldı (0 = bugün).
int kalanGun(int ay, int gun, DateTime simdi) {
  final bugun = DateTime.utc(simdi.year, simdi.month, simdi.day);
  final t = sonrakiTarih(ay, gun, simdi);
  return DateTime.utc(t.year, t.month, t.day).difference(bugun).inDays;
}

String kalanMetni(int kalan) => switch (kalan) {
      0 => 'Bugün 🎉',
      1 => 'Yarın',
      _ => '$kalan gün sonra',
    };

/// Hatırlatıcı listesindeki tek kayıt (arkadaşın doğum günü ya da kişisel
/// önemli gün).
class OnemliGun {
  /// Kişisel günlerde rastgele kimlik; doğum günlerinde `dg_<uid>`.
  final String id;
  final String ad;
  final int ay;
  final int gun;
  final bool dogumGunu;

  const OnemliGun({
    required this.id,
    required this.ad,
    required this.ay,
    required this.gun,
    this.dogumGunu = false,
  });

  Map<String, dynamic> haritaya() => {'id': id, 'ad': ad, 'ay': ay, 'gun': gun};

  /// Bozuk kaydı (eski/elle yazılmış) atlamak için null döner.
  static OnemliGun? haritadan(Object? h) {
    if (h is! Map) return null;
    final id = h['id'], ad = h['ad'], ay = h['ay'], gun = h['gun'];
    if (id is! String || ad is! String || ay is! int || gun is! int) return null;
    if (ad.trim().isEmpty || !gecerliAyGun(ay, gun)) return null;
    return OnemliGun(id: id, ad: ad, ay: ay, gun: gun);
  }

  /// Bildirim metni.
  String get bildirimBasligi =>
      dogumGunu ? '🎂 $ad — bugün doğum günü!' : '📅 Bugün: $ad';

  String get bildirimGovdesi =>
      dogumGunu ? 'Bir mesajla gününü kutlamayı unutma 🎉' : 'Önemli gününü hatırlatıyoruz.';
}

/// Listeyi en yakın tarihten uzağa sıralar.
List<OnemliGun> yakinligaGoreSirala(Iterable<OnemliGun> gunler, DateTime simdi) =>
    gunler.toList()
      ..sort((a, b) =>
          kalanGun(a.ay, a.gun, simdi).compareTo(kalanGun(b.ay, b.gun, simdi)));

/// Bildirim kimliği: kayıt kimliğinden KARARLI (her açılışta aynı) bir sayı,
/// diğer bildirimlerle çakışmasın diye ayrı bir aralıkta (700000000+).
int hatirlaticiBildirimKimligi(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x0FFFFFFF;
  }
  return 700000000 + (h % 100000000);
}
