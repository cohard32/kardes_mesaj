// Yeni mesaj türleri (cevapsız arama, dosya), açıklamalı medya önizlemesi,
// link işareti ve dosya yardımcıları — Firebase'siz.

import 'package:flutter_test/flutter_test.dart';
import 'package:kardes_mesaj/modeller/mesaj.dart';
import 'package:kardes_mesaj/servisler/dosya_servisi.dart';

void main() {
  group('cevapsız arama kaydı', () {
    test('veri: tür, arama tipi, sonuç ve eski sürümler için metin', () {
      final d = Mesaj.aramaKaydiVerisi(
        gonderen: 'a',
        video: true,
        sonuc: 'cevapsiz',
      );
      expect(d['tip'], 'arama');
      expect(d['aramaTipi'], 'video');
      expect(d['aramaSonucu'], 'cevapsiz');
      expect(d['metin'], '📹 Cevapsız görüntülü arama');
      expect(d['gonderen'], 'a');
      expect(d.containsKey('zaman'), isTrue);
    });

    test('önizleme kaydın metnidir', () {
      final m = Mesaj(
        id: 'x',
        gonderen: 'a',
        metin: Mesaj.aramaKaydiMetni(video: false),
        tip: MesajTipi.arama,
        aramaTipi: 'ses',
      );
      expect(m.onizleme, '📞 Cevapsız sesli arama');
      expect(m.videoAramaMi, isFalse);
    });
  });

  group('önizleme', () {
    test('dosya → 📎 ad', () {
      final m = Mesaj(
        id: 'x',
        gonderen: 'a',
        metin: '',
        tip: MesajTipi.dosya,
        dosyaAdi: 'rapor.pdf',
      );
      expect(m.onizleme, '📎 rapor.pdf');
      expect(m.yanitIcinOnizleme, '📎 rapor.pdf');
    });

    test('açıklamalı fotoğraf/video açıklamayı gösterir', () {
      expect(
        Mesaj(id: 'x', gonderen: 'a', metin: ' Tatil ', tip: MesajTipi.resim)
            .onizleme,
        '📷 Tatil',
      );
      expect(
        Mesaj(id: 'x', gonderen: 'a', metin: '', tip: MesajTipi.video)
            .onizleme,
        '🎥 Video',
      );
    });
  });

  group('link işareti', () {
    test('linkli metin işaretlenir, linksiz işaretlenmez', () {
      expect(
        Mesaj.yeniMesajVerisi(gonderen: 'a', metin: 'bak www.x.com')['link'],
        isTrue,
      );
      expect(
        Mesaj.yeniMesajVerisi(gonderen: 'a', metin: 'merhaba')
            .containsKey('link'),
        isFalse,
      );
    });
  });

  group('dosya yardımcıları', () {
    test('boyutMetni Türkçe biçimde', () {
      expect(boyutMetni(512), '512 B');
      expect(boyutMetni(1024), '1 KB');
      expect(boyutMetni(1536), '1,5 KB');
      expect(boyutMetni(1258291), '1,2 MB');
      expect(boyutMetni(15 * 1024 * 1024), '15 MB');
    });

    test('uzantı etiketi ve MIME tahmini', () {
      expect(uzantiEtiketi('Rapor.Final.pdf'), 'PDF');
      expect(uzantiEtiketi('README'), 'DOSYA');
      expect(uzantiEtiketi('.gizli'), 'DOSYA');
      expect(mimeTahmin('a.PDF'), 'application/pdf');
      expect(mimeTahmin('a.docx'), contains('wordprocessingml'));
      expect(mimeTahmin('a.bilinmez'), 'application/octet-stream');
    });

    test('güvenli ad: yol ayırıcı yok, uzantı korunarak kısaltılır', () {
      expect(guvenliAd('../../etc/passwd'), '.._.._etc_passwd');
      expect(guvenliAd('a:b*c?.pdf'), 'a_b_c_.pdf');
      expect(guvenliAd(''), 'dosya');
      final uzun = guvenliAd('${'x' * 150}.pdf');
      expect(uzun.length, 100);
      expect(uzun.endsWith('.pdf'), isTrue);
    });
  });
}
