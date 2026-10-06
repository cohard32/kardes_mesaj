/// `aramalar/{chatId}.durum` alanının alabileceği değerler (sinyalleşme).
///
/// ⚠️ ENUM ADLARI = FİRESTORE'DAKİ DİZGİLER. Yazarken `.name` kullanılır;
/// adı değiştirmek eski sürümlerle (ve karşı cihazdaki eski uygulamayla)
/// uyumu bozar → bir değer yeniden adlandırılırsa karşı taraf o durumu hiç
/// tanımaz (ör. "red" görülmez, arayan 45 sn boşuna çalar). Sıra/adlar
/// test/arama_durumu_test.dart'ta sabitlenmiştir.
///
/// Bu dosya bilerek BAĞIMLILIKSIZ: bildirim_servisi (`_mesgulBildir`) de
/// kullanır ve arama_servisi'ni import edemez (dairesel bağımlılık).
enum AramaDurumu {
  /// Arayan belgeyi yazdı, karşı tarafta zil çalıyor.
  cagriliyor,

  /// Aranan kabul etti, görüşme sürüyor.
  kabul,

  /// Aranan reddetti (ya da kabul akışı başarısız oldu).
  red,

  /// Taraflardan biri kapattı / kalmış kayıt temizlendi.
  bitti,

  /// Aranan zaten başka bir görüşmede.
  mesgul;

  /// Görüşme hâlâ canlı mı (çalıyor ya da kabul edilmiş)?
  bool get aktif => this == cagriliyor || this == kabul;

  /// Firestore'a merge ile yazılacak alan: `{'durum': '<ad>'}`.
  Map<String, Object> get alan => {'durum': name};
}

/// Firestore'dan okunan ham `durum` değerini çözer (saf → test).
/// Bilinmeyen/eksik/yanlış türdeki değer → null (ileride eklenecek yeni bir
/// durumu eski sürüm "yok" sayar; asla fırlatmaz).
AramaDurumu? aramaDurumuCoz(Object? deger) {
  if (deger is! String) return null;
  for (final d in AramaDurumu.values) {
    if (d.name == deger) return d;
  }
  return null;
}
