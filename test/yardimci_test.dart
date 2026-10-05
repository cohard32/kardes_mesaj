// Firebase gerektirmeyen saf mantık testleri.

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/modeller/arkadaslik.dart';
import 'package:kardes_mesaj/modeller/kullanici.dart';
import 'package:kardes_mesaj/yardimcilar/tr_metin.dart';

void main() {
  group('trBuyuk', () {
    test('i → İ, ı → I (Türkçe kuralı)', () {
      expect(trBuyuk('Bildirimler'), 'BİLDİRİMLER');
      expect(trBuyuk('ılık'), 'ILIK');
      expect(trBuyuk('arama zil sesi'), 'ARAMA ZİL SESİ');
    });

    test('zaten büyük / Türkçe olmayan harfler bozulmaz', () {
      expect(trBuyuk('İSTANBUL'), 'İSTANBUL');
      expect(trBuyuk('çğöşü'), 'ÇĞÖŞÜ');
      expect(trBuyuk(''), '');
    });
  });

  group('Kullanici.harf', () {
    Kullanici k(String ad) => Kullanici(uid: 'u', ad: ad, kullaniciAdi: 'x');

    test('Türkçe baş harf', () {
      expect(k('ilker').harf, 'İ');
      expect(k('ırmak').harf, 'I');
      expect(k('  ayşe ').harf, 'A');
    });

    test('emoji ile başlayan ad bozuk karakter üretmez', () {
      expect(k('😀 Neşe').harf, '😀');
    });

    test('boş ad → ?', () {
      expect(k('   ').harf, '?');
    });
  });

  group('ciftKimligi', () {
    // firestore.rules → ciftId() ile AYNI sonucu vermeli; kurallar artık
    // friendships/chats/engellenenler kimliğini buna göre doğruluyor.
    test('sıradan bağımsız ve deterministik', () {
      expect(ciftKimligi('bob', 'alice'), 'alice_bob');
      expect(ciftKimligi('alice', 'bob'), 'alice_bob');
    });

    test('Firebase uid biçiminde (büyük/küçük harf karışık) kod birimi sırası', () {
      // Kurallardaki `a < b` dizgi karşılaştırması ile aynı sıra.
      expect(ciftKimligi('aZ9', 'Ab1'), 'Ab1_aZ9');
    });
  });
}
