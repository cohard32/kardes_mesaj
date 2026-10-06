import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'hata_servisi.dart';

/// Sesli mesajlar için uygulama ömrü boyunca TEK oynatıcı.
///
/// ⚠️ Eskiden her sesli mesaj balonu kendi `AudioPlayer`'ını oluşturuyordu:
///  (1) iki sesli mesaja art arda basınca İKİSİ AYNI ANDA çalıyordu;
///  (2) ses dolu bir sohbette ekrana giren her balon yerel bir MediaPlayer
///      örneği açıyordu (Android'de pahalı, sınırlı kaynak);
///  (3) çalan balon kaydırılıp listeden düşünce (ListView geri dönüşümü)
///      oynatıcısı dispose edilip ses yarıda kesiliyordu.
/// Artık tek oynatıcı var; balonlar yalnızca bu servisin durumunu DİNLER.
/// Balon dispose olunca oynatıcı dispose EDİLMEZ (paylaşılan kaynaktır).
class SesOynaticiServisi {
  SesOynaticiServisi._();
  static final SesOynaticiServisi instance = SesOynaticiServisi._();

  /// Oynatıcıya yüklü (çalan veya duraklatılmış) mesajın kimliği; yoksa null.
  /// Balonlar "bu ben miyim" diye buna bakar.
  final ValueNotifier<String?> calanId = ValueNotifier<String?>(null);
  final ValueNotifier<bool> caliyor = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> konum = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> sure = ValueNotifier<Duration>(Duration.zero);

  /// Oynatma hızı (1x → 1.5x → 2x → 1x). Tüm sesli mesajlar için ortak.
  final ValueNotifier<double> hiz = ValueNotifier<double>(1.0);

  String? _calanUrl;
  String? _calanSohbet;
  bool _bitti = false;

  // Tembel oluşturulur: sesli mesaj hiç çalınmazsa yerel oynatıcı da açılmaz
  // (ve saf mantık testleri platform kanalı gerektirmez).
  AudioPlayer? _oynatici;
  AudioPlayer get _p => _oynatici ??= _olustur();

  AudioPlayer _olustur() {
    final p = AudioPlayer();
    // Abonelikler uygulama ömrü boyunca yaşar (servis tekil) → iptal yok.
    p.onDurationChanged.listen((d) => sure.value = d);
    p.onPositionChanged.listen((k) {
      // Mesaj değiştirilirken önceki kaynaktan geç gelen konum olayı yeni
      // balonun çubuğunu bir an ileri atmasın.
      if (calanId.value != null && !_bitti) konum.value = k;
    });
    p.onPlayerComplete.listen((_) {
      _bitti = true;
      konum.value = Duration.zero;
    });
    // "Çalıyor" bilgisinin TEK kaynağı oynatıcının kendi durumu: sistem
    // duraklatırsa (ses odağı kaybı, gelen arama) simge takılı kalmaz;
    // olaylar sıralı geldiği için stop→play geçişinde son durum doğru olur.
    p.onPlayerStateChanged.listen((s) {
      caliyor.value = s == PlayerState.playing;
    });
    return p;
  }

  /// [mesajId] çalıyorsa duraklatır; duraklatılmışsa kaldığı yerden sürdürür;
  /// başka bir mesajsa öncekini durdurup bunu baştan çalar.
  /// Dönüş: bu çağrıyla çalmaya BAŞLADIYSA true ("dinlendi" işareti için).
  Future<bool> oynatDuraklat({
    required String mesajId,
    required String url,
    required String chatId,
  }) async {
    try {
      if (calanId.value == mesajId && _calanUrl == url) {
        if (caliyor.value) {
          await _p.pause();
          return false;
        }
        if (!_bitti) {
          await _p.resume();
          return true;
        }
        // Sona ulaşmış → aşağıda baştan çalınır.
      } else {
        await _p.stop();
        calanId.value = mesajId;
        _calanUrl = url;
        _calanSohbet = chatId;
        sure.value = Duration.zero;
      }
      _bitti = false;
      konum.value = Duration.zero;
      await _p.play(UrlSource(url));
      await _p.setPlaybackRate(hiz.value);
      return true;
    } catch (e) {
      HataServisi.instance.iz('SES oynatilamadi: $e');
      caliyor.value = false;
      return false;
    }
  }

  /// Yalnız şu an yüklü mesajda konuma atlar (süre bilinmiyorsa yok sayılır).
  Future<void> konumaGit(String mesajId, double oran) async {
    if (calanId.value != mesajId) return;
    final s = sure.value;
    if (s.inMilliseconds == 0) return;
    final hedef = Duration(milliseconds: (s.inMilliseconds * oran).round());
    konum.value = hedef;
    try {
      await _p.seek(hedef);
    } catch (_) {}
  }

  /// Hızı bir sonraki kademeye alır (çalan sese anında uygulanır).
  Future<void> hizDegistir() async {
    hiz.value = sonrakiHiz(hiz.value);
    if (_oynatici == null) return;
    try {
      await _p.setPlaybackRate(hiz.value);
    } catch (_) {}
  }

  /// 1 → 1.5 → 2 → 1 döngüsü (saf; test edilir).
  static double sonrakiHiz(double h) => h == 1.0 ? 1.5 : (h == 1.5 ? 2.0 : 1.0);

  /// Çalanı durdurur ve durumu sıfırlar. [chatId] verilirse yalnız o
  /// sohbetin sesi çalıyorsa durdurur (üstte başka bir sohbet ekranı açıkken
  /// alttaki ekranın dispose'u onun sesini kesmesin).
  Future<void> durdur({String? chatId}) async {
    if (calanId.value == null) return;
    if (chatId != null && chatId != _calanSohbet) return;
    calanId.value = null;
    _calanUrl = null;
    _calanSohbet = null;
    _bitti = false;
    caliyor.value = false;
    konum.value = Duration.zero;
    sure.value = Duration.zero;
    try {
      await _oynatici?.stop();
    } catch (_) {}
  }
}
