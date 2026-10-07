/// Mesaj önizleme / medya URL yardımcıları (saf fonksiyonlar — Firebase'siz
/// test edilebilir, bkz. test/sohbet_yardimci_test.dart).
library;

/// Yanıt alıntısında saklanan önizlemenin üst sınırı. ⚠️ firestore.rules'taki
/// `yanitOnizleme.size() <= 120` ile AYNI olmalı — ikisi birlikte değişmeli.
const int yanitOnizlemeSiniri = 120;

/// Metni tek satıra indirip (satır sonu/çoklu boşluk → tek boşluk) en fazla
/// [sinir] UTF-16 birimine kısaltır; kısaltıldıysa sonuna "…" ekler.
///
/// ⚠️ Kesme noktası RUNE sınırında yapılır: düz `substring(0, n)` bir
/// emojinin (vekil çift) ortasından kesip geçersiz UTF-16 üretebilir →
/// alıntıda bozuk karakter ("�") görünürdü.
/// Sınır UTF-16 birimi olarak sayılır: kural motoru karakter sayar, bir
/// karakter ≥ 1 UTF-16 birimi olduğundan buradaki sınır kuralı hiç aşmaz.
String tekSatiraKisalt(String metin, {int sinir = yanitOnizlemeSiniri}) {
  final duz = metin.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (duz.length <= sinir) return duz;
  final b = StringBuffer();
  var uzunluk = 0;
  for (final r in duz.runes) {
    final birim = r > 0xFFFF ? 2 : 1;
    if (uzunluk + birim > sinir - 1) break; // "…" için 1 birim ayır
    b.writeCharCode(r);
    uzunluk += birim;
  }
  return '${b.toString().trimRight()}…';
}

/// Cloudinary video URL'inden kapak (poster) görseli URL'i üretir.
///
/// Cloudinary'de video kaynağının uzantısını `.jpg` yapmak, videodan bir
/// kare çıkarıp görsel olarak döndürür — ek yükleme / sunucu gerekmez.
///   https://res.cloudinary.com/x/video/upload/v1/abc.mp4
///     → https://res.cloudinary.com/x/video/upload/v1/abc.jpg
/// Cloudinary video URL'i değilse (ör. eski/harici bağlantı) null döner →
/// çağıran düz koyu kutu gösterir.
String? videoKapakUrl(String url) {
  if (!url.contains('/video/upload/')) return null;
  // Sorgu / parça kısmını ayır (varsa olduğu gibi geri eklenir).
  var kesim = url.length;
  final soru = url.indexOf('?');
  final diyez = url.indexOf('#');
  if (soru >= 0) kesim = soru;
  if (diyez >= 0 && diyez < kesim) kesim = diyez;
  final yol = url.substring(0, kesim);
  final ek = url.substring(kesim);
  final sonBolu = yol.lastIndexOf('/');
  if (sonBolu < 0 || sonBolu == yol.length - 1) return null; // dosya adı yok
  final ad = yol.substring(sonBolu + 1);
  final nokta = ad.lastIndexOf('.');
  final govde = nokta > 0 ? ad.substring(0, nokta) : ad;
  return '${yol.substring(0, sonBolu + 1)}$govde.jpg$ek';
}

/// Cloudinary RESİM (ya da [videoKapakUrl] ile üretilmiş video kapağı)
/// URL'ine boyut küçültme dönüşümü ekler: balonda/avatarda birkaç MB'lık
/// orijinal yerine en fazla [genislik] px'lik hafif bir JPEG (~50–150 KB)
/// iner. ORİJİNAL URL DEĞİŞMEZ — tam ekranda, galeriye indirmede o kullanılır.
///   https://res.cloudinary.com/x/image/upload/v1/abc.png
///     → https://res.cloudinary.com/x/image/upload/c_limit,w_720,q_auto,f_jpg/v1/abc.png
/// `c_limit`: küçükse BÜYÜTÜLMEZ. Cloudinary dışı (ör. GIPHY) adresler ve
/// videonun KENDİSİ olduğu gibi döner.
String kucukResimUrl(String url, {int genislik = 720}) {
  const kok = 'https://res.cloudinary.com/';
  const isaret = '/upload/';
  if (!url.startsWith(kok)) return url;
  final i = url.indexOf(isaret);
  if (i < 0) return url;
  final tur = url.substring(0, i);
  final resimMi = tur.endsWith('/image');
  final kapakMi = tur.endsWith('/video') && _uzanti(url) == 'jpg';
  if (!resimMi && !kapakMi) return url;
  final bas = i + isaret.length;
  return '${url.substring(0, bas)}c_limit,w_$genislik,q_auto,f_jpg/'
      '${url.substring(bas)}';
}

/// URL yolundaki dosya uzantısı (küçük harf; yoksa '').
String _uzanti(String url) {
  final yol = Uri.tryParse(url)?.path ?? url;
  final ad = yol.substring(yol.lastIndexOf('/') + 1);
  final nokta = ad.lastIndexOf('.');
  return nokta > 0 ? ad.substring(nokta + 1).toLowerCase() : '';
}
