import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'hata_servisi.dart';

/// ARAYAN tarafındaki "çalıyor" (ringback) tonu.
///
/// NEDEN VAR: Arama başlatan kullanıcı, karşı taraf cevaplayana kadar HİÇBİR
/// ses duymuyordu → "arama zili çalmıyor / arama çalışmıyor" izlenimi.
/// (Aranan taraftaki zil CallKit'ten çalar; bu ondan tamamen AYRIDIR.)
///
/// ⚠️ AGORA ÇAKIŞMA KORUMASI:
///  - Ton DÜŞÜK ses seviyesinde (0.35) çalar; karşı taraf kanala KATILIR
///    KATILMAZ [durdur] çağrılır (AramaEkrani `karsiUid` dinleyicisi) →
///    konuşma sırasında ASLA çalmaz. Bu ayrım GERÇEK CİHAZDA doğrulanmalı.
///  - Her hata yutulur: ringback bir konfor özelliğidir, aramayı ASLA düşürmez.
///
/// ⚠️ TEK OYNATICI — YARIŞ KORUMASI: Eskiden her başlatmada `AudioPlayer()`
/// yaratılıp durdurmada `dispose()` ediliyordu. Art arda arama denemelerinde
/// (kullanıcı hızlıca arayıp kapatınca) bu, native MediaPlayer'ı geçersiz
/// duruma sokup şu hatayı üretiyordu:
///   PlatformException(AndroidAudioError, MEDIA_ERROR_UNKNOWN {what:-38})
/// (Kanıt: v1.6.6 raporlarında 2 saniyede 4 kez.) Artık TEK oynatıcı yeniden
/// kullanılır, `dispose` edilmez ve işlemler sıraya alınır.
class RingbackServisi {
  RingbackServisi._();
  static final RingbackServisi instance = RingbackServisi._();

  AudioPlayer? _player;
  bool _caliyor = false;

  /// Başlat/durdur çağrılarını sıraya alır (aynı anda çalışıp MediaPlayer'ı
  /// geçersiz duruma düşürmesinler).
  Future<void> _kuyruk = Future<void>.value();

  bool get caliyor => _caliyor;

  Future<AudioPlayer> _oynatici() async {
    final mevcut = _player;
    if (mevcut != null) return mevcut;
    final p = AudioPlayer();
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setVolume(0.35); // Agora sesini bastırmasın
    _player = p;
    return p;
  }

  /// İşi kuyruğa ekler; hatayı yutar (arama akışını asla bozmaz).
  Future<void> _sirala(Future<void> Function() is_) {
    _kuyruk = _kuyruk.then((_) => is_()).catchError((Object e) {
      HataServisi.instance.iz('RINGBACK hata (yutuldu): $e');
    });
    return _kuyruk;
  }

  /// "Çalıyor" tonunu döngüde başlatır. Zaten çalıyorsa bir şey yapmaz.
  Future<void> baslat() => _sirala(() async {
        if (_caliyor) return;
        _caliyor = true;
        final p = await _oynatici();
        await p.stop(); // olası kalıntı durumdan temizle
        await p.play(AssetSource('sesler/cingirak.wav'));
        HataServisi.instance.iz('RINGBACK basladi');
      });

  /// Tonu durdurur. Oynatıcı DISPOSE EDİLMEZ (yeniden kullanılır).
  /// Birden çok kez çağrılabilir.
  Future<void> durdur() => _sirala(() async {
        if (!_caliyor) return;
        _caliyor = false;
        await _player?.stop();
        HataServisi.instance.iz('RINGBACK durdu');
      });
}
