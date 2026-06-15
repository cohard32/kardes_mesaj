import 'dart:convert';

import 'package:http/http.dart' as http;

/// Bir GIF/sticker sonucunun iki URL'i: ızgarada gösterilen küçük önizleme
/// ve mesajda paylaşılacak (biraz daha büyük) sürüm.
class GifSonuc {
  final String onizleme;
  final String gonder;
  const GifSonuc(this.onizleme, this.gonder);
}

/// GIPHY üzerinden GIF ve sticker arama — KARTSIZ.
/// GIPHY ücretsiz API anahtarı verir (kredi kartı GEREKMEZ).
///
/// ⚠️ KULLANICI AYARI: developers.giphy.com → giriş yap → "Create an App" →
/// "API" seç → uygulama adı yaz → oluştur → "API Key"i kopyala → aşağıdaki
/// [_apiKey] sabitine yapıştır. GIF'ler doğrudan GIPHY URL'i olarak gönderilir,
/// Cloudinary'ye yükleme yapılmaz.
class GifServisi {
  GifServisi._();
  static final GifServisi instance = GifServisi._();

  static const String _apiKey = 'OYJplWSmNn1T8skOZXI5hKkpr1GemeSt';

  /// API anahtarı girilmiş mi?
  bool get ayarliMi =>
      _apiKey != 'GIPHY_API_KEY_BURAYA' && _apiKey.trim().isNotEmpty;

  /// [sorgu] boşsa "trending" (popüler), doluysa arama yapar.
  /// [sticker] true ise saydam sticker'ları getirir.
  Future<List<GifSonuc>> ara({
    String sorgu = '',
    bool sticker = false,
    int limit = 30,
  }) async {
    if (!ayarliMi) return [];

    final tur = sticker ? 'stickers' : 'gifs';
    final temiz = sorgu.trim();
    final uc = temiz.isEmpty ? 'trending' : 'search';
    final params = <String, String>{
      'api_key': _apiKey,
      'limit': '$limit',
      'rating': 'pg-13',
      'bundle': 'fixed_width_downsampled',
      if (temiz.isNotEmpty) 'q': temiz,
    };

    try {
      final uri = Uri.https('api.giphy.com', '/v1/$tur/$uc', params);
      final yanit = await http.get(uri);
      if (yanit.statusCode != 200) return [];

      final govde = jsonDecode(yanit.body) as Map<String, dynamic>;
      final liste = (govde['data'] as List?) ?? const [];
      final sonuc = <GifSonuc>[];
      for (final e in liste) {
        final imgs = (e as Map<String, dynamic>)['images']
            as Map<String, dynamic>?;
        if (imgs == null) continue;
        final onizleme =
            _url(imgs, const ['fixed_width', 'downsized', 'original']);
        final gonder =
            _url(imgs, const ['downsized', 'fixed_width', 'original']);
        if (onizleme != null && gonder != null) {
          sonuc.add(GifSonuc(onizleme, gonder));
        }
      }
      return sonuc;
    } catch (_) {
      return [];
    }
  }

  // imgs içinde sırayla bakıp ilk geçerli .url'i döndürür.
  String? _url(Map<String, dynamic> imgs, List<String> anahtarlar) {
    for (final a in anahtarlar) {
      final m = imgs[a] as Map<String, dynamic>?;
      final u = m?['url'] as String?;
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }
}
