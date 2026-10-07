/// "Bunu bana hatırlat" zaman seçenekleri (saf — bkz. test/hatirlatma_test.dart).
library;

import 'zaman_metni.dart';

const List<String> _aylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// Hazır seçenekler: (etiket, zaman). "Bu akşam" yalnız 19:30'dan önce.
List<({String etiket, DateTime zaman})> hatirlatmaSecenekleri(DateTime simdi) {
  final bugun = DateTime(simdi.year, simdi.month, simdi.day);
  final aksam = bugun.add(const Duration(hours: 20));
  return [
    (etiket: '20 dakika sonra', zaman: simdi.add(const Duration(minutes: 20))),
    (etiket: '1 saat sonra', zaman: simdi.add(const Duration(hours: 1))),
    (etiket: '3 saat sonra', zaman: simdi.add(const Duration(hours: 3))),
    if (simdi.isBefore(aksam.subtract(const Duration(minutes: 30))))
      (etiket: 'Bu akşam 20:00', zaman: aksam),
    (
      etiket: 'Yarın sabah 09:00',
      zaman: DateTime(simdi.year, simdi.month, simdi.day + 1, 9),
    ),
  ];
}

/// İLERİDEKİ bir zamanın kısa metni: "Bugün 20:00", "Yarın 09:00",
/// "12 Eylül 14:30" (başka yılsa yıl da).
String hatirlatmaMetni(DateTime hedef, DateTime simdi) {
  final a = DateTime.utc(simdi.year, simdi.month, simdi.day);
  final b = DateTime.utc(hedef.year, hedef.month, hedef.day);
  final fark = b.difference(a).inDays;
  final saat = saatMetni(hedef);
  if (fark <= 0) return 'Bugün $saat';
  if (fark == 1) return 'Yarın $saat';
  final gun = '${hedef.day} ${_aylar[hedef.month - 1]}';
  return hedef.year == simdi.year ? '$gun $saat' : '$gun ${hedef.year} $saat';
}

/// Mesaj hatırlatmasının bildirim kimliği (600000000+ aralığı; doğum günü
/// hatırlatıcıları 700000000+). Aynı mesaj + aynı zaman = aynı kimlik.
int mesajHatirlatmaKimligi(String mesajId, DateTime zaman) {
  var h = 0;
  for (final c in '$mesajId@${zaman.millisecondsSinceEpoch ~/ 60000}'.codeUnits) {
    h = (h * 31 + c) & 0x0FFFFFFF;
  }
  return 600000000 + (h % 100000000);
}
