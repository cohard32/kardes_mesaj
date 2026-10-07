/// Mesaj metnindeki bağlantıları bulan saf yardımcılar (Firebase'siz test
/// edilebilir, bkz. test/link_metni_test.dart).
library;

/// Metnin bir parçası: düz yazı ya da tıklanabilir bağlantı.
class MetinParcasi {
  final String metin;

  /// Bağlantıysa tarayıcıda açılacak TAM adres (şemalı), değilse null.
  final String? url;

  const MetinParcasi(this.metin, [this.url]);

  bool get linkMi => url != null;

  @override
  bool operator ==(Object other) =>
      other is MetinParcasi && other.metin == metin && other.url == url;

  @override
  int get hashCode => Object.hash(metin, url);

  @override
  String toString() => url == null ? 'Duz($metin)' : 'Link($metin → $url)';
}

// `http(s)://…` ya da `www.…` ile başlayan, boşluğa kadar giden dizi.
// Bilerek basit: "ornek.com" gibi şemasız/wwwsiz adresler LİNK SAYILMAZ —
// "saat 10.30da" ya da "a.b" gibi sıradan yazılar yanlışlıkla link olmasın.
final RegExp _linkDeseni = RegExp(
  r'(?:https?://|www\.)[^\s<>"]+',
  caseSensitive: false,
);

// Cümle sonundaki noktalama bağlantıya dahil değildir:
// "şuna bak: https://x.com/a." → nokta linkin parçası değil.
const String _sondakiNoktalama = '.,;:!?\'"…';

/// [metin]i düz yazı / bağlantı parçalarına böler. Bağlantı yoksa tek bir
/// düz parça döner (boş metin → boş liste).
List<MetinParcasi> linkleriAyir(String metin) {
  final parcalar = <MetinParcasi>[];
  var konum = 0;
  for (final e in _linkDeseni.allMatches(metin)) {
    var ham = e.group(0)!;
    // Sondaki noktalamayı ve EŞLEŞMEYEN kapanış parantezini at:
    // "(bkz. https://x.com/a)" → ")" link değil; ama
    // "https://tr.wikipedia.org/wiki/Ankara_(il)" → ")" linkin parçası.
    while (ham.isNotEmpty) {
      final son = ham[ham.length - 1];
      if (_sondakiNoktalama.contains(son)) {
        ham = ham.substring(0, ham.length - 1);
      } else if (son == ')' &&
          ')'.allMatches(ham).length > '('.allMatches(ham).length) {
        ham = ham.substring(0, ham.length - 1);
      } else {
        break;
      }
    }
    // "www." ya da "https://" tek başına link değildir.
    final govde = ham.replaceFirst(
      RegExp(r'^(?:https?://|www\.)', caseSensitive: false),
      '',
    );
    if (govde.isEmpty) continue;

    if (e.start > konum) {
      parcalar.add(MetinParcasi(metin.substring(konum, e.start)));
    }
    final url = ham.toLowerCase().startsWith('www.') ? 'https://$ham' : ham;
    parcalar.add(MetinParcasi(ham, url));
    konum = e.start + ham.length;
  }
  if (konum < metin.length) parcalar.add(MetinParcasi(metin.substring(konum)));
  return parcalar;
}

/// Tarayıcıda açılması GÜVENLİ mi? Yalnız http/https (javascript:, file:,
/// intent: vb. ASLA açılmaz — yerel tarafta da aynı kontrol var).
bool acilabilirLinkMi(String url) {
  final u = Uri.tryParse(url);
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}

/// Metinde en az bir tıklanabilir bağlantı var mı? (Mesaja `link: true`
/// yazılır → medya galerisinin "Linkler" sekmesi sorgulayabilsin.)
bool linkIceriyor(String metin) => linkleriAyir(metin).any((p) => p.linkMi);
