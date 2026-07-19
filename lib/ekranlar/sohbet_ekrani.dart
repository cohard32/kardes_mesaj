import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../modeller/kullanici.dart';
import '../modeller/mesaj.dart';
import '../modeller/sohbet.dart';
import '../parcalar/kullanici_avatar.dart';
import '../servisler/arama_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/mesaj_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../servisler/sohbet_servisi.dart';
import '../tema.dart';
import 'arama_ekrani.dart';
import 'gif_secici.dart';
import 'profil_goruntule_ekrani.dart';

/// Bir arkadaşla sohbeti açar (yoksa oluşturur) ve ekranı push eder.
/// Arkadaş listesi / sohbet listesi / profil bu ortak yolu kullanır.
Future<void> sohbetiAc(BuildContext context, Kullanici karsi) async {
  final nav = Navigator.of(context);
  try {
    final chatId = await SohbetServisi.instance.sohbetAcOrGetir(karsi.uid);
    if (!context.mounted) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => SohbetEkrani(chatId: chatId, karsi: karsi),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e')));
  }
}

/// Bir arkadaşla sohbet ekranı (FAZ 4). [chatId] = ciftKimligi(ben, karşı).
/// Kendi mesajların sağda neon gradient balonda, karşınınki solda koyu cam
/// balonda. Tüm renk/stil değerleri `tema.dart`'tan gelir (bkz. Renkler/Kose/…).
class SohbetEkrani extends StatefulWidget {
  final String chatId;
  final Kullanici karsi;

  const SohbetEkrani({super.key, required this.chatId, required this.karsi});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani>
    with WidgetsBindingObserver {
  final _mesajCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _servis = MesajServisi.instance;
  final _presence = PresenceServisi.instance;
  final _sohbetServis = SohbetServisi.instance;
  final _resimSecici = ImagePicker();
  final _kayitci = AudioRecorder();

  final _odak = FocusNode();

  Timer? _yaziyorTimer;
  bool _yaziyorGonderildi = false;
  bool _kayitYapiliyor = false;
  bool _yukleniyor = false;

  // Otomatik kaydırma kontrolü (klavye/scroll zıplamasını önler)
  int _oncekiMesajSayisi = 0;
  bool _ilkKaydirma = true;
  bool _zorlaKaydir = false;

  // Sayfalama: başta son 50 mesaj; yukarı kaydırınca 50'şer artar.
  static const int _sayfaBoyu = 50;
  int _mesajLimit = _sayfaBoyu;
  bool _hepsiYuklendi = false;
  bool _eskiYukleniyor = false;

  // Sesli mesaj kaydı durumu
  Timer? _kayitTimer;
  int _kayitSaniye = 0;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _dalga = [];

  // Emoji paneli
  bool _emojiAcik = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BildirimServisi.instance.tokenKaydet();
    _presence.cevrimiciYap();
    _sohbetServis.okunduIsaretle(widget.chatId); // sohbeti açınca okundu
    _mesajCtrl.addListener(_yaziyorDinle);
    _scrollCtrl.addListener(_eskiMesajKontrol);
    _odak.addListener(() {
      if (_odak.hasFocus && _emojiAcik) {
        setState(() => _emojiAcik = false);
      }
    });
    // NOT: güncelleme kontrolü artık AnaKabuk'ta (açılışta) yapılıyor.
    // kalmış stale aramayı temizle
    AramaServisi.instance.eskiAramayiTemizle(widget.chatId);
    _aramaIzinleriniKontrolEt();
    // CallKit ile (kapalıyken) kabul edilmiş bir arama varsa ekranını aç.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bekleyenAramayiAc());
  }

  // Ekran KAPALIYKEN aramanın çalışması için gereken izinler:
  // (1) pil optimizasyonu muafiyeti (Doze uyutmasın),
  // (2) Android 14+ tam ekran bildirim izni (yoksa arama tam ekran açılmaz).
  Future<void> _aramaIzinleriniKontrolEt() async {
    final b = BildirimServisi.instance;
    await b.pilOptimizasyonuIste();
    if (!mounted) return;
    if (await b.tamEkranIzniVarMi()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: const Text(
          'Ekran kapalıyken arama gelmesi için "tam ekran bildirim" izni gerekli.',
        ),
        action: SnackBarAction(
          label: 'İzin ver',
          onPressed: b.tamEkranAyarlariniAc,
        ),
      ),
    );
  }

  void _bekleyenAramayiAc() {
    final s = AramaServisi.instance;
    final chatId = s.bekleyenChatId;
    final tip = s.bekleyenTip;
    if (chatId != null && tip != null && mounted) {
      final baslik = s.bekleyenBaslik ?? widget.karsi.ad;
      s.bekleyenChatId = null;
      s.bekleyenTip = null;
      s.bekleyenBaslik = null;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(chatId: chatId, tip: tip, baslik: baslik),
        ),
      );
    }
  }

  // NOT: Gelen arama ekranı ARTIK BURADA AÇILMIYOR.
  // Tek akış: gelen arama HER durumda (açık/arka plan/kapalı) CallKit ile
  // gösterilir (bkz. bildirim_servisi.gelenAramayiGoster). Eskiden buradaki
  // Firestore dinleyicisi de bir ekran açıyordu ve CallKit'in tam ekran
  // aktivitesiyle YARIŞIYORDU (yeşil ekran açılıp anında mavi CallKit'e
  // dönmesinin sebebi buydu). Kabul edilince main.dart CallKit olayını
  // yakalayıp AramaEkrani'nı açar.

  // Görüntülü/sesli arama başlat → arama ekranını aç. Hata olursa ekranda göster.
  Future<void> _aramaBaslat(AramaTipi tip) async {
    try {
      final kanal = await AramaServisi.instance.aramaBaslat(
        widget.chatId,
        widget.karsi.uid,
        tip,
      );
      if (!mounted) return;
      if (kanal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera/mikrofon izni gerekli')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AramaEkrani(
            chatId: widget.chatId,
            tip: tip,
            baslik: widget.karsi.ad,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yaziyorTimer?.cancel();
    _kayitTimer?.cancel();
    _ampSub?.cancel();
    _presence.cevrimdisiYap();
    _kayitci.dispose();
    _mesajCtrl.dispose();
    _scrollCtrl.dispose();
    _odak.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presence.cevrimiciYap();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _presence.cevrimdisiYap();
    }
  }

  void _yaziyorDinle() {
    final bos = _mesajCtrl.text.trim().isEmpty;
    if (!bos && !_yaziyorGonderildi) {
      _yaziyorGonderildi = true;
      _presence.yaziyorAyarla(widget.chatId, true);
    }
    _yaziyorTimer?.cancel();
    _yaziyorTimer = Timer(const Duration(seconds: 2), () {
      _yaziyorGonderildi = false;
      _presence.yaziyorAyarla(widget.chatId, false);
    });
  }

  Future<void> _gonder() async {
    final metin = _mesajCtrl.text;
    if (metin.trim().isEmpty) return;
    _mesajCtrl.clear();
    _yaziyorTimer?.cancel();
    _yaziyorGonderildi = false;
    _presence.yaziyorAyarla(widget.chatId, false);
    _zorlaKaydir = true;
    try {
      await _servis.gonder(widget.chatId, widget.karsi.uid, metin);
    } catch (e) {
      // Firestore çevrimdışıyken kuyruğa alır; yine de hata olursa kullanıcıya
      // bildir ve metni kaybetme.
      if (!mounted) return;
      _mesajCtrl.text = metin;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi. Tekrar dene.')),
      );
    }
  }

  // Kullanıcı en üste yaklaşınca daha eski mesajları yükle (sayfalama).
  void _eskiMesajKontrol() {
    if (_hepsiYuklendi || _eskiYukleniyor) return;
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels <= 120) {
      _eskiYukleniyor = true;
      setState(() => _mesajLimit += _sayfaBoyu);
    }
  }

  // Sadece yeni mesaj geldiğinde (ya da kullanıcı en alttayken) kaydırır.
  // Böylece klavye açılınca / yukarı kaydırırken liste zıplamaz.
  void _yeniMesajKaydir(int yeniSayi) {
    final artti = yeniSayi > _oncekiMesajSayisi;
    _oncekiMesajSayisi = yeniSayi;
    if (!artti && !_ilkKaydirma && !_zorlaKaydir) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      final enAltaYakin = pos.maxScrollExtent - pos.pixels < 220;
      if (_ilkKaydirma) {
        _ilkKaydirma = false;
        _scrollCtrl.jumpTo(pos.maxScrollExtent);
      } else if (_zorlaKaydir || enAltaYakin) {
        _scrollCtrl.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _zorlaKaydir = false;
    });
  }

  // ---- EMOJI ----

  void _emojiToggle() {
    setState(() => _emojiAcik = !_emojiAcik);
    if (_emojiAcik) {
      _odak.unfocus();
    } else {
      _odak.requestFocus();
    }
  }

  void _emojiEkle(String emoji) {
    final t = _mesajCtrl.text;
    final sel = _mesajCtrl.selection;
    final bas = sel.start < 0 ? t.length : sel.start;
    final son = sel.end < 0 ? t.length : sel.end;
    final yeni = t.replaceRange(bas, son, emoji);
    _mesajCtrl.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(offset: bas + emoji.length),
    );
  }

  void _emojiSil() {
    final t = _mesajCtrl.text;
    if (t.isEmpty) return;
    final sel = _mesajCtrl.selection;
    final son = sel.end < 0 ? t.length : sel.end;
    if (son == 0) return;
    var sil = 1;
    if (son >= 2) {
      final k = t.codeUnitAt(son - 1);
      final o = t.codeUnitAt(son - 2);
      if (k >= 0xDC00 && k <= 0xDFFF && o >= 0xD800 && o <= 0xDBFF) sil = 2;
    }
    final yeni = t.substring(0, son - sil) + t.substring(son);
    _mesajCtrl.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(offset: son - sil),
    );
  }

  // ---- MEDYA ----

  // Ek (ataç) menüsü: foto / video seç
  void _ekMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: Renkler.neon),
              title: const Text('Fotoğraf'),
              onTap: () {
                Navigator.pop(context);
                _fotoSec();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Renkler.neon),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _videoSec();
              },
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined, color: Renkler.neon),
              title: const Text('GIF / Sticker'),
              onTap: () {
                Navigator.pop(context);
                _gifSec();
              },
            ),
          ],
        ),
      ),
    );
  }

  // GIF/sticker seçici aç → seçilen GIPHY URL'ini gönder
  Future<void> _gifSec() async {
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => const GifSecici(),
    );
    if (url != null && url.isNotEmpty) {
      _zorlaKaydir = true;
      await _servis.gifGonder(widget.chatId, widget.karsi.uid, url);
    }
  }

  Future<void> _fotoSec() async {
    final x = await _resimSecici.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (x != null) await _medyaGonder(File(x.path), MesajTipi.resim);
  }

  Future<void> _videoSec() async {
    final x = await _resimSecici.pickVideo(source: ImageSource.gallery);
    if (x != null) await _medyaGonder(File(x.path), MesajTipi.video);
  }

  // Sesli mesaj kaydını başlat (canlı süre sayacı + ses dalgası)
  Future<void> _kayitBaslat() async {
    if (!await _kayitci.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mikrofon izni gerekli')));
      }
      return;
    }
    final dizin = await getTemporaryDirectory();
    final yol =
        '${dizin.path}/ses_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _kayitci.start(const RecordConfig(), path: yol);
    _dalga.clear();
    _kayitSaniye = 0;
    _kayitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _kayitSaniye++);
    });
    _ampSub = _kayitci
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
          // dBFS (-45..0) → 0..1 ölçek (konuşurken dalga oynar)
          final normal = ((amp.current + 45) / 45).clamp(0.0, 1.0);
          if (mounted) {
            setState(() {
              _dalga.add(normal.toDouble());
              if (_dalga.length > 50) _dalga.removeAt(0);
            });
          }
        });
    setState(() => _kayitYapiliyor = true);
  }

  Future<void> _kayitTemizle() async {
    _kayitTimer?.cancel();
    _kayitTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
  }

  // Durdur ve gönder
  Future<void> _kayitGonder() async {
    final yol = await _kayitci.stop();
    await _kayitTemizle();
    setState(() => _kayitYapiliyor = false);
    if (yol != null) await _medyaGonder(File(yol), MesajTipi.ses);
  }

  // İptal: kaydı sil, gönderme
  Future<void> _kayitIptal() async {
    final yol = await _kayitci.stop();
    await _kayitTemizle();
    setState(() => _kayitYapiliyor = false);
    if (yol != null) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
  }

  Future<void> _medyaGonder(File dosya, MesajTipi tip) async {
    setState(() => _yukleniyor = true);
    final ok = await _servis.medyaGonder(
      widget.chatId,
      widget.karsi.uid,
      dosya,
      tip,
    );
    if (!mounted) return;
    setState(() => _yukleniyor = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Medya gönderilemedi. Cloudinary ayarı yapılmamış olabilir.',
          ),
        ),
      );
    } else {
      _zorlaKaydir = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfilGoruntuleEkrani(kullanici: widget.karsi),
            ),
          ),
          child: _AppBarBaslik(chatId: widget.chatId, karsi: widget.karsi),
        ),
        actions: [
          IconButton(
            tooltip: 'Sesli ara',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _aramaBaslat(AramaTipi.ses),
          ),
          IconButton(
            tooltip: 'Görüntülü ara',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _aramaBaslat(AramaTipi.video),
          ),
        ],
      ),
      body: Zemin(
        parlama: const Alignment(0.6, -1),
        child: Column(
          children: [
            if (_yukleniyor)
              const LinearProgressIndicator(
                color: Renkler.neon,
                backgroundColor: Renkler.yuzey,
              ),
            Expanded(
              child: StreamBuilder<List<Mesaj>>(
                stream: _servis.mesajlariDinle(
                  widget.chatId,
                  limit: _mesajLimit,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Renkler.neon),
                    );
                  }
                  if (snapshot.hasError) {
                    return const _BosDurum(
                      ikon: Icons.error_outline,
                      yazi: 'Mesajlar yüklenemedi',
                    );
                  }

                  final mesajlar = snapshot.data ?? [];
                  // Sayfalama durumunu güncelle: gelen sayı istenen limitten azsa
                  // en eski mesaja ulaşılmıştır (daha fazla yükleme yok).
                  _eskiYukleniyor = false;
                  _hepsiYuklendi = mesajlar.length < _mesajLimit;
                  if (mesajlar.isEmpty) {
                    return const _BosDurum(
                      ikon: Icons.chat_bubble_outline_rounded,
                      yazi: 'Henüz mesaj yok.\nİlk mesajı sen yaz 👋',
                    );
                  }

                  _servis.gorulduIsaretle(widget.chatId, mesajlar);
                  _sohbetServis.okunduIsaretle(widget.chatId);
                  _yeniMesajKaydir(mesajlar.length);

                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    itemCount: mesajlar.length,
                    itemBuilder: (context, i) {
                      final m = mesajlar[i];
                      return _MesajBalonu(
                        mesaj: m,
                        benimMi: m.gonderen == _uid,
                        chatId: widget.chatId,
                        onUzunBas: () => _tepkiSec(m),
                      );
                    },
                  );
                },
              ),
            ),
            // Kayıt sırasında kayıt çubuğu, değilse yazma alanı (+ emoji paneli)
            if (_kayitYapiliyor)
              _KayitCubugu(
                saniye: _kayitSaniye,
                dalga: _dalga,
                onIptal: _kayitIptal,
                onGonder: _kayitGonder,
              )
            else ...[
              _YazmaAlani(
                controller: _mesajCtrl,
                odak: _odak,
                emojiAcik: _emojiAcik,
                onGonder: _gonder,
                onEk: _ekMenu,
                onMikrofon: _kayitBaslat,
                onEmoji: _emojiToggle,
              ),
              if (_emojiAcik)
                _EmojiPaneli(onEmoji: _emojiEkle, onSil: _emojiSil),
            ],
          ],
        ),
      ),
    );
  }

  void _tepkiSec(Mesaj mesaj) {
    const emojiler = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(borderRadius: Kose.panel),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in emojiler)
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () {
                    Navigator.pop(context);
                    _servis.tepkiDegistir(widget.chatId, mesaj.id, e);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AppBar başlığı: karşı tarafın avatarı + adı + altında
/// yazıyor / çevrimiçi / son görülme durumu.
/// İki canlı kaynak: users/{karsi} (çevrimiçi/son görülme) ve
/// chats/{chatId}.yaziyor (anlık yazıyor).
class _AppBarBaslik extends StatelessWidget {
  final String chatId;
  final Kullanici karsi;
  const _AppBarBaslik({required this.chatId, required this.karsi});

  String _sonGorulmeMetni(Kullanici k) {
    if (k.cevrimici) return 'çevrimiçi';
    final t = k.sonGorulme;
    if (t != null) {
      final s = t.hour.toString().padLeft(2, '0');
      final d = t.minute.toString().padLeft(2, '0');
      return 'son görülme $s:$d';
    }
    return 'çevrimdışı';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Kullanici>(
      stream: PresenceServisi.instance.kullaniciDinle(karsi.uid),
      initialData: karsi,
      builder: (context, snap) {
        final k = snap.data ?? karsi;
        return StreamBuilder<Sohbet>(
          stream: SohbetServisi.instance.sohbetDinle(chatId),
          builder: (context, sohbetSnap) {
            final yaziyor =
                sohbetSnap.data?.digerYaziyor(
                  FirebaseAuth.instance.currentUser?.uid ?? '',
                ) ??
                false;
            final durum = yaziyor ? 'yazıyor...' : _sonGorulmeMetni(k);
            final vurgulu = yaziyor || k.cevrimici;

            return Row(
              children: [
                KullaniciAvatar(kullanici: k, boyut: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.ad,
                        overflow: TextOverflow.ellipsis,
                        style: Yazi.isim,
                      ),
                      if (durum.isNotEmpty)
                        Row(
                          children: [
                            if (vurgulu) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: Kutular.neonNokta(),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                durum,
                                overflow: TextOverflow.ellipsis,
                                style: vurgulu ? Yazi.neonKucuk : Yazi.zaman,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Tek bir mesaj balonu (uzun basınca tepki seçici). Metin veya medya gösterir.
class _MesajBalonu extends StatelessWidget {
  final Mesaj mesaj;
  final bool benimMi;
  final String chatId;
  final VoidCallback onUzunBas;

  const _MesajBalonu({
    required this.mesaj,
    required this.benimMi,
    required this.chatId,
    required this.onUzunBas,
  });

  String _saat(DateTime? t) {
    if (t == null) return '';
    final s = t.hour.toString().padLeft(2, '0');
    final d = t.minute.toString().padLeft(2, '0');
    return '$s:$d';
  }

  /// Balon içindeki medyanın organik köşesi (balonla uyumlu, bir köşe kısa).
  BorderRadius get _medyaKose => benimMi ? Kose.medyaBen : Kose.medyaKarsi;

  // Mesaj türüne göre içerik
  Widget _icerik(BuildContext context) {
    switch (mesaj.tip) {
      case MesajTipi.resim:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _resmiBuyut(context, mesaj.medyaUrl!),
          child: ClipRRect(
            borderRadius: _medyaKose,
            child: Image.network(
              mesaj.medyaUrl!,
              width: 220,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : Container(
                      width: 220,
                      height: 160,
                      alignment: Alignment.center,
                      color: Renkler.zemin,
                      child: const CircularProgressIndicator(
                        color: Renkler.neon,
                      ),
                    ),
              errorBuilder: (c, e, s) => const SizedBox(
                width: 220,
                height: 100,
                child: Icon(Icons.broken_image, color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      case MesajTipi.video:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _VideoOynatici(url: mesaj.medyaUrl!, kose: _medyaKose);
      case MesajTipi.ses:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return _SesOynatici(
          url: mesaj.medyaUrl!,
          benimMi: benimMi,
          chatId: chatId,
          mesajId: mesaj.id,
          dinlendi: mesaj.sesDinlendi,
        );
      case MesajTipi.gif:
        if (mesaj.medyaUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _resmiBuyut(context, mesaj.medyaUrl!),
          child: ClipRRect(
            borderRadius: _medyaKose,
            child: Image.network(
              mesaj.medyaUrl!,
              width: 170,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : Container(
                      width: 170,
                      height: 170,
                      alignment: Alignment.center,
                      color: Renkler.zemin,
                      child: const CircularProgressIndicator(
                        color: Renkler.neon,
                      ),
                    ),
              errorBuilder: (c, e, s) => const SizedBox(
                width: 170,
                height: 90,
                child: Icon(Icons.broken_image, color: Renkler.metinSoluk),
              ),
            ),
          ),
        );
      case MesajTipi.metin:
        // Neon balon üstünde koyu, karşı tarafın koyu balonunda açık metin
        return Text(
          mesaj.metin,
          style: benimMi ? Yazi.govdeAccent : Yazi.govde,
        );
    }
  }

  void _resmiBuyut(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: Kose.kartKose,
            child: Image.network(url),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final medyaMi = mesaj.tip != MesajTipi.metin;
    return Align(
      alignment: benimMi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onUzunBas,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: EdgeInsets.only(
                top: 4,
                bottom: mesaj.tepki != null ? 16 : 4,
              ),
              padding: EdgeInsets.all(medyaMi ? 5 : 12),
              // Kendi balonun: neon gradient + ÇOK HAFİF glow (göz yormasın).
              // Karşı taraf: zeminden net ayrışan koyu yüzey, GLOW YOK.
              // Organik köşe — dip köşe kısa. 3D his gradient + iç ışıktan gelir.
              decoration: benimMi
                  ? Kutular.accent(
                      kose: Kose.balonBen,
                      golge: Golgeler.balonNeon,
                    )
                  : BoxDecoration(
                      gradient: Gradyanlar.balonGelen,
                      borderRadius: Kose.balonKarsi,
                      border: Border.all(color: Renkler.kenarGuclu),
                      boxShadow: Golgeler.balonGelen,
                    ),
              child: Stack(
                children: [
                  // Neon balonda iç highlight/gölge (3D hacim)
                  if (benimMi)
                    const Positioned.fill(child: IcIsik(kose: Kose.balonBen)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _icerik(context),
                      Padding(
                        padding: EdgeInsets.only(top: 3, left: medyaMi ? 6 : 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Gelen, henüz dinlenmemiş sesli mesaj → neon nokta
                            if (mesaj.tip == MesajTipi.ses &&
                                !benimMi &&
                                !mesaj.sesDinlendi) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: Kutular.neonNokta(),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              _saat(mesaj.zaman),
                              style: benimMi ? Yazi.zamanAccent : Yazi.zaman,
                            ),
                            if (benimMi) ...[
                              const SizedBox(width: 4),
                              Icon(
                                mesaj.goruldu ? Icons.done_all : Icons.done,
                                size: 15,
                                color: mesaj.goruldu
                                    ? Renkler.metinKoyu
                                    : Renkler.metinKoyuYumusak,
                              ),
                              // Gönderdiğim ses dinlendiyse kulaklık
                              if (mesaj.tip == MesajTipi.ses &&
                                  mesaj.sesDinlendi) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.headset_rounded,
                                  size: 13,
                                  color: Renkler.metinKoyu,
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (mesaj.tepki != null)
              Positioned(
                bottom: 0,
                right: benimMi ? 8 : null,
                left: benimMi ? null : 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Renkler.yuzeyYuksek,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Renkler.kenarGuclu, width: 1.5),
                    boxShadow: Golgeler.balon,
                  ),
                  child: Text(
                    mesaj.tepki!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// İnline video oynatıcı (dokununca oynat/duraklat).
class _VideoOynatici extends StatefulWidget {
  final String url;

  /// Balonun organik köşesiyle uyumlu medya köşesi
  final BorderRadius kose;
  const _VideoOynatici({required this.url, required this.kose});

  @override
  State<_VideoOynatici> createState() => _VideoOynaticiState();
}

class _VideoOynaticiState extends State<_VideoOynatici> {
  VideoPlayerController? _ctrl;
  bool _hazir = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _hazir = true);
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hazir || _ctrl == null) {
      return Container(
        width: 220,
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Renkler.zeminDerin,
          borderRadius: widget.kose,
        ),
        child: const CircularProgressIndicator(color: Renkler.neon),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
      }),
      child: ClipRRect(
        borderRadius: widget.kose,
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_ctrl!),
                // Neon 3D oynat rozeti
                if (!_ctrl!.value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      gradient: Gradyanlar.accent,
                      shape: BoxShape.circle,
                      boxShadow: Golgeler.neonGlow,
                    ),
                    padding: const EdgeInsets.all(10),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Renkler.metinKoyu,
                      size: 32,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sesli mesaj oynatıcı: çal/duraklat + ses dalgası (seek) + konum/süre + hız.
class _SesOynatici extends StatefulWidget {
  final String url;
  final bool benimMi;
  final String chatId;
  final String mesajId;
  final bool dinlendi;
  const _SesOynatici({
    required this.url,
    required this.benimMi,
    required this.chatId,
    required this.mesajId,
    required this.dinlendi,
  });

  @override
  State<_SesOynatici> createState() => _SesOynaticiState();
}

class _SesOynaticiState extends State<_SesOynatici> {
  final AudioPlayer _player = AudioPlayer();
  bool _caliyor = false;
  Duration _konum = Duration.zero;
  Duration _sure = Duration.zero;
  double _hiz = 1.0;
  late final List<double> _dalga;

  final List<StreamSubscription> _abonelikler = [];

  @override
  void initState() {
    super.initState();
    // Ağ dosyası için gerçek dalga çıkarmak ağırdır → URL'den sabit dekoratif dalga.
    _dalga = _dalgaUret(widget.url);
    _abonelikler.add(
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _sure = d);
      }),
    );
    _abonelikler.add(
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _konum = p);
      }),
    );
    _abonelikler.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _caliyor = false;
            _konum = Duration.zero;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final a in _abonelikler) {
      a.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  List<double> _dalgaUret(String s) {
    final r = Random(s.hashCode);
    return List.generate(48, (_) => 0.2 + r.nextDouble() * 0.8);
  }

  Future<void> _degistir() async {
    if (_caliyor) {
      await _player.pause();
      setState(() => _caliyor = false);
    } else {
      await _player.play(UrlSource(widget.url));
      await _player.setPlaybackRate(_hiz);
      setState(() => _caliyor = true);
      // Karşı tarafın sesli mesajıysa ve henüz dinlenmediyse "dinlendi" işaretle
      if (!widget.benimMi && !widget.dinlendi) {
        MesajServisi.instance.sesDinlendiIsaretle(
          widget.chatId,
          widget.mesajId,
        );
      }
    }
  }

  void _hizDegistir() {
    setState(() => _hiz = _hiz == 1.0 ? 1.5 : (_hiz == 1.5 ? 2.0 : 1.0));
    _player.setPlaybackRate(_hiz);
  }

  Future<void> _seek(double oran) async {
    if (_sure.inMilliseconds == 0) return;
    final hedef = Duration(milliseconds: (_sure.inMilliseconds * oran).round());
    await _player.seek(hedef);
    setState(() => _konum = hedef);
  }

  String _mmss(Duration d) {
    final dk = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final sn = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$dk:$sn';
  }

  @override
  Widget build(BuildContext context) {
    // Neon balonda koyu, karşı tarafın koyu balonunda neon renk
    final renk = widget.benimMi ? Renkler.metinKoyu : Renkler.neon;
    final oran = _sure.inMilliseconds == 0
        ? 0.0
        : (_konum.inMilliseconds / _sure.inMilliseconds).clamp(0.0, 1.0);
    final hizYazi = _hiz == _hiz.roundToDouble() ? '${_hiz.toInt()}' : '$_hiz';
    return SizedBox(
      width: 218,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _degistir,
                child: Icon(
                  _caliyor ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: renk,
                  size: 36,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _seek(
                      (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0),
                    ),
                    onHorizontalDragUpdate: (d) => _seek(
                      (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0),
                    ),
                    child: SizedBox(
                      height: 30,
                      child: CustomPaint(
                        painter: _DalgaPainter(_dalga, renk, ilerleme: oran),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 2),
            child: Row(
              children: [
                Text(
                  '${_mmss(_konum)} / ${_sure == Duration.zero ? "--:--" : _mmss(_sure)}',
                  style: TextStyle(
                    color: renk.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _hizDegistir,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${hizYazi}x',
                      style: TextStyle(
                        color: renk,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt mesaj yazma çubuğu (emoji + ataç + metin + mikrofon/gönder).
class _YazmaAlani extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode odak;
  final bool emojiAcik;
  final VoidCallback onGonder;
  final VoidCallback onEk;
  final VoidCallback onMikrofon;
  final VoidCallback onEmoji;

  const _YazmaAlani({
    required this.controller,
    required this.odak,
    required this.emojiAcik,
    required this.onGonder,
    required this.onEk,
    required this.onMikrofon,
    required this.onEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
        color: Renkler.zemin,
        child: Row(
          children: [
            IconButton(
              tooltip: emojiAcik ? 'Klavye' : 'Emoji',
              icon: Icon(
                emojiAcik
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
                color: Renkler.neon,
              ),
              onPressed: onEmoji,
            ),
            IconButton(
              tooltip: 'Ekle',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.add_circle_outline, color: Renkler.neon),
              onPressed: onEk,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, deger, _) {
                  final bos = deger.text.trim().isEmpty;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: Kutular.duzYuzey(
                            kose: Kose.alan,
                            kenarli: true,
                          ),
                          child: TextField(
                            controller: controller,
                            focusNode: odak,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => onGonder(),
                            style: Yazi.govde,
                            decoration: const InputDecoration(
                              hintText: 'Mesaj yaz…',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 3D gönder / mikrofon butonu
                      Uc3DDugme(
                        kose: Kose.dugme,
                        padding: const EdgeInsets.all(13),
                        onTap: bos ? onMikrofon : onGonder,
                        cocuk: Icon(
                          bos ? Icons.mic : Icons.send_rounded,
                          color: Renkler.metinKoyu,
                          size: 22,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sesli mesaj kaydı sırasında gösterilen çubuk:
/// yanıp sönen kırmızı nokta + canlı süre + canlı ses dalgası + iptal/gönder.
class _KayitCubugu extends StatefulWidget {
  final int saniye;
  final List<double> dalga;
  final VoidCallback onIptal;
  final VoidCallback onGonder;
  const _KayitCubugu({
    required this.saniye,
    required this.dalga,
    required this.onIptal,
    required this.onGonder,
  });

  @override
  State<_KayitCubugu> createState() => _KayitCubuguState();
}

class _KayitCubuguState extends State<_KayitCubugu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _yanip;

  @override
  void initState() {
    super.initState();
    _yanip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _yanip.dispose();
    super.dispose();
  }

  String get _sure {
    final d = (widget.saniye ~/ 60).toString().padLeft(2, '0');
    final s = (widget.saniye % 60).toString().padLeft(2, '0');
    return '$d:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
        color: Renkler.zemin,
        child: Row(
          children: [
            IconButton(
              tooltip: 'İptal',
              icon: const Icon(Icons.delete_outline, color: Renkler.tehlike),
              onPressed: widget.onIptal,
            ),
            // Kayıt göstergesi + süre + canlı dalga — cam yüzey içinde
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: Kutular.duzYuzey(kose: Kose.alan, kenarli: true),
                child: Row(
                  children: [
                    FadeTransition(
                      opacity: _yanip,
                      child: const Icon(
                        Icons.fiber_manual_record,
                        color: Renkler.tehlike,
                        size: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        _sure,
                        style: Yazi.stil(13, FontWeight.w700, Renkler.metin)
                            .copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: CustomPaint(
                          painter: _DalgaPainter(
                            widget.dalga,
                            Renkler.neon,
                            canli: true,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 3D gönder butonu
            Uc3DDugme(
              kose: Kose.dugme,
              padding: const EdgeInsets.all(13),
              onTap: widget.onGonder,
              cocuk: const Icon(
                Icons.send_rounded,
                color: Renkler.metinKoyu,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ses dalgası çizici. [canli]=true ise son çubukları kaydırarak gösterir
/// (kayıt); değilse sabit seti [ilerleme] oranına göre boyar (oynatma).
class _DalgaPainter extends CustomPainter {
  final List<double> dalga;
  final Color renk;
  final double ilerleme;
  final bool canli;
  _DalgaPainter(this.dalga, this.renk, {this.ilerleme = 1, this.canli = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (dalga.isEmpty) return;
    const cubuk = 3.0;
    const aralik = 2.0;
    const toplam = cubuk + aralik;
    final adet = (size.width / toplam).floor().clamp(1, 200);

    final goster = <double>[];
    if (canli) {
      final basla = (dalga.length - adet).clamp(0, dalga.length);
      for (var i = basla; i < dalga.length; i++) {
        goster.add(dalga[i]);
      }
    } else {
      for (var i = 0; i < adet; i++) {
        final idx = (i * dalga.length / adet).floor().clamp(
          0,
          dalga.length - 1,
        );
        goster.add(dalga[idx]);
      }
    }

    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cubuk;
    final orta = size.height / 2;
    for (var i = 0; i < goster.length; i++) {
      final x = i * toplam + cubuk / 2;
      final h = (goster[i] * size.height).clamp(4.0, size.height);
      final oran = goster.length <= 1 ? 1.0 : i / (goster.length - 1);
      p.color = oran <= ilerleme ? renk : renk.withValues(alpha: 0.3);
      canvas.drawLine(Offset(x, orta - h / 2), Offset(x, orta + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DalgaPainter old) =>
      old.ilerleme != ilerleme ||
      !identical(old.dalga, dalga) ||
      old.dalga.length != dalga.length;
}

/// Tema renkli, kategorili özel emoji seçici (paket gerektirmez).
class _EmojiPaneli extends StatefulWidget {
  final void Function(String) onEmoji;
  final VoidCallback onSil;
  const _EmojiPaneli({required this.onEmoji, required this.onSil});

  @override
  State<_EmojiPaneli> createState() => _EmojiPaneliState();
}

class _EmojiPaneliState extends State<_EmojiPaneli> {
  int _kategori = 0;

  static const _ikonlar = [
    Icons.emoji_emotions,
    Icons.front_hand,
    Icons.favorite,
    Icons.pets,
    Icons.fastfood,
    Icons.sports_soccer,
    Icons.lightbulb,
  ];

  static const _gruplar = <List<String>>[
    [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '🥲',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🥸',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
      '🤯',
      '😳',
      '🥵',
      '🥶',
      '😱',
      '😨',
      '😰',
      '😥',
      '😓',
      '🤗',
      '🤔',
      '🫡',
      '🤭',
      '🤫',
      '😴',
      '😪',
      '🤤',
      '😵',
      '🥴',
      '🤢',
      '🤮',
      '🤧',
      '😷',
    ],
    [
      '👍',
      '👎',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🫰',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '👋',
      '🤚',
      '🖐️',
      '✋',
      '🖖',
      '🫱',
      '🫲',
      '🫳',
      '🫴',
      '👏',
      '🙌',
      '🫶',
      '👐',
      '🤲',
      '🙏',
      '🤝',
      '💪',
      '🦾',
      '✍️',
      '💅',
      '🤳',
      '👀',
      '🫵',
      '🤜',
      '🤛',
    ],
    [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🤎',
      '🖤',
      '🤍',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
      '💌',
      '💋',
      '💯',
      '💢',
      '💥',
      '💫',
      '💦',
      '💨',
      '🔥',
      '✨',
    ],
    [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🦆',
      '🦉',
      '🐴',
      '🦄',
      '🐝',
      '🦋',
      '🐌',
      '🐞',
      '🐢',
      '🐍',
      '🐙',
      '🦀',
      '🐠',
      '🐬',
      '🐳',
      '🐋',
      '🌸',
      '🌹',
      '🌻',
      '🌷',
      '🌳',
      '🌵',
      '🍀',
      '🌙',
      '⭐',
      '🌈',
      '☀️',
      '⛅',
      '❄️',
    ],
    [
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🥑',
      '🍆',
      '🥕',
      '🌽',
      '🌶️',
      '🥔',
      '🥐',
      '🍞',
      '🧀',
      '🍗',
      '🍖',
      '🌭',
      '🍔',
      '🍟',
      '🍕',
      '🌮',
      '🌯',
      '🥗',
      '🍝',
      '🍜',
      '🍣',
      '🍦',
      '🍰',
      '🎂',
      '🍫',
      '🍬',
      '🍭',
      '🍩',
      '🍪',
      '☕',
      '🍵',
      '🥤',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
    ],
    [
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🎾',
      '🏐',
      '🏉',
      '🎱',
      '🏓',
      '🏸',
      '🥅',
      '⛳',
      '🏒',
      '🏏',
      '🥊',
      '🎮',
      '🎲',
      '🎯',
      '🎳',
      '🎤',
      '🎧',
      '🎸',
      '🎹',
      '🥁',
      '🎺',
      '🎻',
      '🎬',
      '🎨',
      '🎭',
      '🎟️',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🚗',
      '✈️',
      '🚀',
      '⛵',
      '🏖️',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
    ],
    [
      '📱',
      '💻',
      '⌚',
      '📷',
      '🔋',
      '💡',
      '🔦',
      '📺',
      '🛒',
      '💰',
      '💵',
      '💎',
      '🔑',
      '🔒',
      '🔔',
      '📌',
      '📎',
      '✂️',
      '✏️',
      '📝',
      '📚',
      '📖',
      '🗓️',
      '⏰',
      '⏳',
      '🔍',
      '❗',
      '❓',
      '💤',
      '✅',
      '❌',
      '⭕',
      '💬',
      '💭',
      '🗯️',
      '⚡',
      '🎵',
      '🎶',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    // Panel: sistem klavyesi gibi durmasın → tema yüzeyi, organik üst köşe,
    // neon kenar ve tutamaç.
    return Container(
      height: 272,
      decoration: BoxDecoration(
        gradient: Gradyanlar.yuzey,
        borderRadius: Kose.panel,
        border: Border(
          top: BorderSide(color: Renkler.kenarGuclu),
          left: BorderSide(color: Renkler.kenar),
          right: BorderSide(color: Renkler.kenar),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Tutamaç
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Renkler.kenarGuclu,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 44,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _gruplar[_kategori].length,
              itemBuilder: (_, i) {
                final e = _gruplar[_kategori][i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onEmoji(e),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: const BoxDecoration(
              color: Renkler.zeminDerin,
              border: Border(top: BorderSide(color: Renkler.kenar)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: _ikonlar.length,
                    itemBuilder: (_, i) {
                      final secili = i == _kategori;
                      // Seçili kategori: neon dolgu rozeti
                      return GestureDetector(
                        onTap: () => setState(() => _kategori = i),
                        child: Container(
                          width: 42,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: secili ? Renkler.neonSis : null,
                            borderRadius: Kose.dugme,
                            border: Border.all(
                              color: secili
                                  ? Renkler.kenarGuclu
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            _ikonlar[i],
                            color: secili ? Renkler.neon : Renkler.metinSoluk,
                            size: 21,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(
                    Icons.backspace_outlined,
                    color: Renkler.metinSoluk,
                  ),
                  onPressed: widget.onSil,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş/hata durumu için ortak gösterim.
class _BosDurum extends StatelessWidget {
  final IconData ikon;
  final String yazi;

  const _BosDurum({required this.ikon, required this.yazi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Neon sisli ikon kutusu — organik köşe
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Renkler.neonSis,
              borderRadius: Kose.kartKose,
              border: Border.all(color: Renkler.kenar),
            ),
            child: Icon(ikon, size: 38, color: Renkler.neon),
          ),
          const SizedBox(height: 16),
          Text(yazi, textAlign: TextAlign.center, style: Yazi.kucuk),
        ],
      ),
    );
  }
}
