/// Türkçe metin yardımcıları.
///
/// ⚠️ Dart'ın `toUpperCase()`'i dilden BAĞIMSIZDIR: 'i' → 'I' (Türkçede
/// doğrusu 'İ'). Bu yüzden "Bildirimler".toUpperCase() → "BILDIRIMLER",
/// "ilker" adlı birinin avatar harfi "I" çıkıyordu.
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Türkçe küçük harf: 'İ' → 'i', 'I' → 'ı' (Dart'ın toLowerCase'i 'I' → 'i'
/// yapar, Türkçede yanlış).
String trKucuk(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Arama için sadeleştirilmiş metin: küçük harf + Türkçe harfler katlanır
/// (ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u). Böylece "gorusuruz" yazan
/// "Görüşürüz"ü, "ISIK" yazan "ışık"ı bulur.
String aramaIcinSadele(String s) {
  const harita = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u'};
  final k = trKucuk(s);
  final b = StringBuffer();
  for (final r in k.runes) {
    final c = String.fromCharCode(r);
    b.write(harita[c] ?? c);
  }
  return b.toString();
}
