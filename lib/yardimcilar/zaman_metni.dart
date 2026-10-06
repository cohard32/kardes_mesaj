/// Sohbet ekranındaki saat / "son görülme" metinleri (saf fonksiyonlar —
/// Firebase'siz test edilebilir, bkz. test/sohbet_yardimci_test.dart).
///
/// ⚠️ intl paketi KULLANILMAZ (yeni bağımlılık araç zincirini kırıyor);
/// Türkçe kısa ay adları elle tutulur.
library;

const List<String> _kisaAylar = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// "14:05" (yerel saat).
String saatMetni(DateTime t) {
  final y = t.toLocal();
  final s = y.hour.toString().padLeft(2, '0');
  final d = y.minute.toString().padLeft(2, '0');
  return '$s:$d';
}

/// Takvim günü farkı (bugün = 0, dün = 1 …), yerel saate göre.
/// ⚠️ İki tarih UTC GECE YARISINA taşınıp öyle çıkarılır: yerel
/// DateTime'larla `difference().inDays` yaz saati geçişindeki 23 saatlik
/// günü "0 gün" sayar ve dünü bugün gösterirdi.
int _gunFarki(DateTime t, DateTime simdi) {
  final a = t.toLocal();
  final b = simdi.toLocal();
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

/// AppBar'daki son görülme metni.
///
/// ⚠️ Eskiden yalnız "son görülme HH:mm" yazılıyordu → 3 gün önce görülen
/// biri "son görülme 14:05" görünüp BUGÜN çevrimiçiymiş sanılıyordu.
///   bugün        → "son görülme 14:05"
///   dün          → "son görülme dün 14:05"
///   daha eski    → "son görülme 3 Eki"   (başka yılsa "3 Eki 2024")
/// Gelecekteki zaman (cihaz saati kaymış) bugün sayılır.
String sonGorulmeMetni(DateTime t, {DateTime? simdi}) {
  final su = simdi ?? DateTime.now();
  final fark = _gunFarki(t, su);
  if (fark <= 0) return 'son görülme ${saatMetni(t)}';
  if (fark == 1) return 'son görülme dün ${saatMetni(t)}';
  final y = t.toLocal();
  final gun = '${y.day} ${_kisaAylar[y.month - 1]}';
  return y.year == su.toLocal().year
      ? 'son görülme $gun'
      : 'son görülme $gun ${y.year}';
}
