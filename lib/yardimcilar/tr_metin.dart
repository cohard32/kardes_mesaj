/// Türkçe metin yardımcıları.
///
/// ⚠️ Dart'ın `toUpperCase()`'i dilden BAĞIMSIZDIR: 'i' → 'I' (Türkçede
/// doğrusu 'İ'). Bu yüzden "Bildirimler".toUpperCase() → "BILDIRIMLER",
/// "ilker" adlı birinin avatar harfi "I" çıkıyordu.
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
