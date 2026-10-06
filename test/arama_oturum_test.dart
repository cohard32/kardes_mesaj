// Görüşme oturumu kuralı: eski ekran/istek YENİ görüşmeye dokunamaz.

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/ekranlar/arama_ekrani.dart';
import 'package:kardes_mesaj/servisler/arama_servisi.dart';

void main() {
  group('oturumGuncelMi', () {
    test('oturum verilmemiş (eski çağıranlar) → her zaman geçerli', () {
      expect(oturumGuncelMi(istenen: null, guncel: 0), isTrue);
      expect(oturumGuncelMi(istenen: null, guncel: 7), isTrue);
    });

    test('şimdiki oturum → geçerli (bitir temizler)', () {
      expect(oturumGuncelMi(istenen: 3, guncel: 3), isTrue);
    });

    test('eski oturum → geçersiz (yeni görüşme devraldı, dokunma)', () {
      // Senaryo: A↔B görüşmesi oturum 3; A çöküp yeniden arıyor, B kabul
      // ediyor → kabulEt oturumu 4 yapar. Eski ekranın 20 sn sayacı dolup
      // bitir(oturum: 3) çağırırsa yeni görüşme DÜŞMEMELİ.
      expect(oturumGuncelMi(istenen: 3, guncel: 4), isFalse);
      // Ekran tarafı da aynı kuralla "devredildim" der.
      expect(!oturumGuncelMi(istenen: 3, guncel: 4), isTrue);
    });
  });

  group('aramaDevralindiMi', () {
    test('aynı kanal → devralma yok', () {
      expect(aramaDevralindiMi(benimKanal: 'k_a', belgeKanali: 'k_a'), isFalse);
    });

    test('farklı kanal → devralındı', () {
      expect(aramaDevralindiMi(benimKanal: 'k_a', belgeKanali: 'k_b'), isTrue);
    });

    test('kanal bilinmiyorsa (null/boş) devralma SAYILMAZ', () {
      expect(aramaDevralindiMi(benimKanal: null, belgeKanali: 'k_b'), isFalse);
      expect(aramaDevralindiMi(benimKanal: '', belgeKanali: 'k_b'), isFalse);
      expect(aramaDevralindiMi(benimKanal: 'k_a', belgeKanali: null), isFalse);
      expect(aramaDevralindiMi(benimKanal: 'k_a', belgeKanali: ''), isFalse);
    });
  });

  group('aramaBelgesiOlayi', () {
    test('kendi kanalında durumlar eskisi gibi', () {
      Map<String, dynamic> b(String d) => {'durum': d, 'kanal': 'k_a'};
      expect(aramaBelgesiOlayi(b('cagriliyor'), benimKanal: 'k_a'),
          BelgeOlayi.yok);
      expect(aramaBelgesiOlayi(b('kabul'), benimKanal: 'k_a'), BelgeOlayi.yok);
      expect(aramaBelgesiOlayi(b('red'), benimKanal: 'k_a'),
          BelgeOlayi.reddedildi);
      expect(aramaBelgesiOlayi(b('mesgul'), benimKanal: 'k_a'),
          BelgeOlayi.mesgul);
      expect(
          aramaBelgesiOlayi(b('bitti'), benimKanal: 'k_a'), BelgeOlayi.bitti);
    });

    test('belge yok → olay yok', () {
      expect(aramaBelgesiOlayi(null, benimKanal: 'k_a'), BelgeOlayi.yok);
    });

    test('kanal bilinmiyorsa durum kuralı (eski davranış)', () {
      expect(aramaBelgesiOlayi({'durum': 'bitti'}, benimKanal: 'k_a'),
          BelgeOlayi.bitti);
      expect(
          aramaBelgesiOlayi({'durum': 'bitti', 'kanal': 'k_b'},
              benimKanal: null),
          BelgeOlayi.bitti);
      // Bozuk tür → kanal yok sayılır, çökmez.
      expect(aramaBelgesiOlayi({'durum': 'red', 'kanal': 42}, benimKanal: 'k_a'),
          BelgeOlayi.reddedildi);
    });

    test('başka kanal: durum ne olursa olsun devralma (yeni aramaya ait)', () {
      for (final d in ['cagriliyor', 'kabul', 'red', 'mesgul', 'bitti']) {
        expect(
          aramaBelgesiOlayi({'durum': d, 'kanal': 'k_b'}, benimKanal: 'k_a'),
          BelgeOlayi.devralindi,
          reason: 'durum=$d',
        );
      }
    });

    test('SENARYO: kopma sayacı sürerken aynı sohbetten yeniden arama '
        '(zil çalıyor, kabulEt başlamadı) → eski ekran sayaç dolmadan çekilir',
        () {
      // B'deki eski ekran: oturum 3, kanal k_eski, karşı taraf (A) çöktü.
      const ekranOturumu = 3;
      var servisOturumu = 3;
      final takip = BaglantiTakibi()..guncelle(42);
      expect(takip.guncelle(null), BaglantiOlayi.koptu); // 20 sn sayacı kuruldu
      expect(
        aramaBelgesiOlayi({'durum': 'kabul', 'kanal': 'k_eski'},
            benimKanal: 'k_eski'),
        BelgeOlayi.yok,
      );

      // A yeniden arıyor: belgeye YENİ kanal + 'cagriliyor' yazılır (push'tan
      // önce). B'de CallKit çalıyor; B henüz kabul etmedi → oturum DEĞİŞMEDİ.
      final yeni = {'durum': 'cagriliyor', 'kanal': 'k_yeni', 'arayanUid': 'A'};
      expect(oturumGuncelMi(istenen: ekranOturumu, guncel: servisOturumu),
          isTrue,
          reason: 'eski koruma (oturum) bu pencerede YETMEZ');
      expect(aramaBelgesiOlayi(yeni, benimKanal: 'k_eski'),
          BelgeOlayi.devralindi,
          reason: 'ekran sayaç dolmadan çekilmeli; bitti/push/endAllCalls yok');
      // Çekilen ekranın yerel temizliği oturum hâlâ onunken yapılır
      // (AramaServisi.devredildi kuralı) — yeni aramaya ait hiçbir şey yok.
      expect(oturumGuncelMi(istenen: ekranOturumu, guncel: servisOturumu),
          isTrue);

      // B kabul ederse kabulEt oturumu artırır; geç kalan eski istekler
      // (bitir / devredildi) artık yeni görüşmeye dokunamaz.
      servisOturumu++;
      expect(oturumGuncelMi(istenen: ekranOturumu, guncel: servisOturumu),
          isFalse);
    });
  });
}
