/// Sohbet içi arama (saf fonksiyon — bkz. test/sohbet_arama_test.dart).
library;

import '../modeller/mesaj.dart';
import 'tr_metin.dart';

/// [mesajlar] (YENİDEN ESKİYE sıralı) içinde METNİ [sorgu]yu içeren
/// mesajları AYNI sırayla döndürür. Büyük/küçük harf ve Türkçe harf
/// farkı gözetilmez. Medya mesajlarının (varsa) açıklama metninde de arar.
/// Sorgu 2 karakterden kısaysa boş liste (tek harf her mesajı bulur).
List<Mesaj> sohbetteAra(List<Mesaj> mesajlar, String sorgu) {
  final s = aramaIcinSadele(sorgu.trim());
  if (s.length < 2) return const [];
  return [
    for (final m in mesajlar)
      if (m.metin.isNotEmpty && aramaIcinSadele(m.metin).contains(s)) m,
  ];
}
