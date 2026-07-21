import 'package:audioplayers/audioplayers.dart';

import 'hata_servisi.dart';

/// ARAYAN tarafındaki "çalıyor" (ringback) tonu.
///
/// NEDEN VAR: Arama başlatan kullanıcı, karşı taraf cevaplayana kadar HİÇBİR
/// ses duymuyordu → "arama zili çalmıyor / arama çalışmıyor" izlenimi.
/// (Aranan taraftaki zil CallKit'ten çalar; bu ondan tamamen AYRIDIR.)
///
/// ⚠️ AGORA ÇAKIŞMA KORUMASI — tasarım kararları:
///  - Ton DÜŞÜK ses seviyesinde (0.35) ve audioplayers'ın VARSAYILAN medya
///    akışında çalar; Agora ses yolunu (VOICE_CALL) kullandığı için farklı
///    akışlardır. Yine de üst üste binmesin diye aşağıdaki kural uygulanır:
///    ⚠️ Bu ayrım cihazdan cihaza değişebilir → GERÇEK CİHAZDA doğrulanmalı.
///  - Karşı taraf kanala KATILIR KATILMAZ [durdur] çağrılır (AramaEkrani
///    `karsiUid` dinleyicisinde) → konuşma sırasında ASLA çalmaz.
///  - Arama biterken de [durdur] çağrılır; çift çağrı güvenlidir.
///  - Her hata yutulur: ringback bir konfor özelliğidir, aramayı ASLA düşürmez.
class RingbackServisi {
  RingbackServisi._();
  static final RingbackServisi instance = RingbackServisi._();

  AudioPlayer? _player;
  bool _caliyor = false;

  bool get caliyor => _caliyor;

  /// "Çalıyor" tonunu döngüde başlatır. Zaten çalıyorsa bir şey yapmaz.
  Future<void> baslat() async {
    if (_caliyor) return;
    _caliyor = true;
    try {
      final p = AudioPlayer();
      _player = p;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(0.35); // Agora sesini bastırmasın
      await p.play(AssetSource('sesler/cingirak.wav'));
      HataServisi.instance.iz('RINGBACK basladi');
    } catch (e) {
      // Ses çalınamadıysa arama devam etsin.
      _caliyor = false;
      HataServisi.instance.iz('RINGBACK baslatilamadi: $e');
    }
  }

  /// Tonu durdurur ve kaynağı bırakır. Birden çok kez çağrılabilir.
  Future<void> durdur() async {
    if (!_caliyor && _player == null) return;
    _caliyor = false;
    final p = _player;
    _player = null;
    try {
      await p?.stop();
      await p?.dispose();
      HataServisi.instance.iz('RINGBACK durdu');
    } catch (e) {
      HataServisi.instance.iz('RINGBACK durdurma hatasi: $e');
    }
  }
}
