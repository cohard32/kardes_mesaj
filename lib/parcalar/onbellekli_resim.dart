import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../servisler/resim_onbellegi.dart';

/// `NetworkImage` yerine kullanılan, DİSK önbellekli ağ resmi
/// (bkz. [ResimOnbellegi]). Bir kez inen resim uygulama kapanıp açılsa da
/// telefondan okunur. Balonlarda Cloudinary'nin küçük hâliyle
/// (`kucukResimUrl`), tam ekranda orijinal URL ile kullanılır.
@immutable
class OnbellekliResim extends ImageProvider<OnbellekliResim> {
  const OnbellekliResim(this.url, {this.onbellek});

  final String url;

  /// Testler için; normalde [ResimOnbellegi.instance].
  final ResimOnbellegi? onbellek;

  @override
  Future<OnbellekliResim> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<OnbellekliResim>(this);

  @override
  ImageStreamCompleter loadImage(
    OnbellekliResim key,
    ImageDecoderCallback decode,
  ) {
    final olaylar = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _yukle(key, decode, olaylar),
      chunkEvents: olaylar.stream,
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<OnbellekliResim>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _yukle(
    OnbellekliResim key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> olaylar,
  ) async {
    try {
      final baytlar = await (onbellek ?? ResimOnbellegi.instance).getir(
        url,
        ilerleme: (alinan, toplam) {
          if (olaylar.isClosed) return;
          olaylar.add(ImageChunkEvent(
            cumulativeBytesLoaded: alinan,
            expectedTotalBytes: toplam,
          ));
        },
      );
      final tampon = await ui.ImmutableBuffer.fromUint8List(baytlar);
      return await decode(tampon);
    } catch (_) {
      // Başarısız yüklemeyi bellek önbelleğinden çıkar → tekrar denenebilsin
      // (NetworkImage de böyle yapar).
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(olaylar.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OnbellekliResim && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => '${objectRuntimeType(this, 'OnbellekliResim')}("$url")';
}
