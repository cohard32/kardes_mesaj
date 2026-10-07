import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/modeller/mesaj.dart';
import 'package:kardes_mesaj/yardimcilar/tarih_ayraci.dart';
import 'package:kardes_mesaj/yardimcilar/zaman_metni.dart';

Mesaj _m(String id, DateTime? t) =>
    Mesaj(id: id, gonderen: 'a', metin: id, zaman: t);

void main() {
  final simdi = DateTime(2026, 10, 7, 15, 0); // Çarşamba

  group('gunAyraciMetni', () {
    test('bugün / dün / hafta içi / bu yıl / başka yıl', () {
      expect(gunAyraciMetni(DateTime(2026, 10, 7, 0, 1), simdi: simdi), 'Bugün');
      expect(gunAyraciMetni(DateTime(2026, 10, 6, 23, 59), simdi: simdi), 'Dün');
      expect(gunAyraciMetni(DateTime(2026, 10, 5, 9), simdi: simdi), 'Pazartesi');
      expect(gunAyraciMetni(DateTime(2026, 10, 1, 9), simdi: simdi), 'Perşembe');
      expect(gunAyraciMetni(DateTime(2026, 9, 30, 9), simdi: simdi), '30 Eylül');
      expect(gunAyraciMetni(DateTime(2025, 12, 31), simdi: simdi), '31 Aralık 2025');
    });

    test('gelecekteki zaman (saat kayması) bugün sayılır', () {
      expect(gunAyraciMetni(DateTime(2026, 10, 8, 1), simdi: simdi), 'Bugün');
    });
  });

  group('tarihAyraclari', () {
    test('her günün EN ESKİ mesajının üstüne ayraç konur', () {
      // Yeniden eskiye: bugün (2), dün (2), 30 Eylül (1)
      final liste = [
        _m('b2', DateTime(2026, 10, 7, 14)),
        _m('b1', DateTime(2026, 10, 7, 9)),
        _m('d2', DateTime(2026, 10, 6, 22)),
        _m('d1', DateTime(2026, 10, 6, 8)),
        _m('e1', DateTime(2026, 9, 30, 12)),
      ];
      expect(tarihAyraclari(liste, simdi: simdi), {
        'b1': 'Bugün',
        'd1': 'Dün',
        'e1': '30 Eylül',
      });
    });

    test('zaman damgası henüz gelmemiş mesaj bugün sayılır', () {
      final liste = [
        _m('yeni', null),
        _m('b1', DateTime(2026, 10, 7, 9)),
      ];
      expect(tarihAyraclari(liste, simdi: simdi), {'b1': 'Bugün'});
    });

    test('boş liste', () {
      expect(tarihAyraclari(const [], simdi: simdi), isEmpty);
    });
  });
}
