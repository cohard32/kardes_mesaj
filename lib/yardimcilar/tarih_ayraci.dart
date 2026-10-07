/// Sohbetteki tarih ayraçları (saf — bkz. test/tarih_ayraci_test.dart).
library;

import '../modeller/mesaj.dart';
import 'zaman_metni.dart';

/// [mesajlar] YENİDEN ESKİYE sıralı (sohbet akışı gibi). Bir günün İLK
/// (en eski) mesajının üstüne o günün ayracı konur: dönen harita
/// `mesaj kimliği → ayraç metni` ("Bugün", "Dün", "12 Eylül"…).
///
/// En eski YÜKLÜ mesajın üstüne de ayraç konur; daha eski sayfa gelince
/// aynı günse ayraç kendiliğinden bir öncekine geçer.
/// Henüz sunucu damgası olmayan (az önce gönderilen) mesaj "şimdi" sayılır.
Map<String, String> tarihAyraclari(List<Mesaj> mesajlar, {DateTime? simdi}) {
  final su = simdi ?? DateTime.now();
  final sonuc = <String, String>{};
  for (var i = 0; i < mesajlar.length; i++) {
    final t = mesajlar[i].zaman ?? su;
    final dahaEski =
        i + 1 < mesajlar.length ? (mesajlar[i + 1].zaman ?? su) : null;
    if (dahaEski == null || !ayniGun(t, dahaEski)) {
      sonuc[mesajlar[i].id] = gunAyraciMetni(t, simdi: su);
    }
  }
  return sonuc;
}
