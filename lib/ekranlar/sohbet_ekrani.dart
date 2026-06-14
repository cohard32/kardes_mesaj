import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../modeller/mesaj.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/guncelleme_servisi.dart';
import '../servisler/mesaj_servisi.dart';
import '../servisler/presence_servisi.dart';
import '../tema.dart';
import 'ayarlar_ekrani.dart';

/// Ana sohbet ekranı. İki kişilik tek sohbet.
/// Kendi mesajların sağda mavi (#00b0ff), kardeşininki solda gri (#1c1c1c).
class SohbetEkrani extends StatefulWidget {
  const SohbetEkrani({super.key});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani>
    with WidgetsBindingObserver {
  final _mesajCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _servis = MesajServisi.instance;
  final _presence = PresenceServisi.instance;

  Timer? _yaziyorTimer;
  bool _yaziyorGonderildi = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // FCM token kaydet + çevrimiçi ol
    BildirimServisi.instance.tokenKaydet();
    _presence.cevrimiciYap();
    _mesajCtrl.addListener(_yaziyorDinle);
    // Açılışta güncelleme kontrolü (varsa kendi indirip kurar)
    _guncellemeKontrol();
  }

  // GitHub'da yeni sürüm varsa otomatik indirip kurulumu başlatır.
  Future<void> _guncellemeKontrol() async {
    final bilgi = await GuncellemeServisi.instance.kontrolEt();
    if (bilgi == null || !mounted) return;

    final ilerleme = ValueNotifier<double>(0);
    // İndirme ilerlemesini gösteren, kapatılamaz dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Renkler.yuzey,
        title: Text('Güncelleme indiriliyor (v${bilgi.surum})'),
        content: ValueListenableBuilder<double>(
          valueListenable: ilerleme,
          builder: (_, yuzde, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: yuzde > 0 ? yuzde : null,
                color: Renkler.accent,
                backgroundColor: Renkler.giris,
              ),
              const SizedBox(height: 12),
              Text('%${(yuzde * 100).toStringAsFixed(0)}'),
            ],
          ),
        ),
      ),
    );

    try {
      await GuncellemeServisi.instance.indirVeKur(
        bilgi.apkUrl,
        (y) => ilerleme.value = y,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme indirilemedi: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yaziyorTimer?.cancel();
    _presence.cevrimdisiYap();
    _mesajCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Uygulama ön plana/arka plana geçince çevrimiçi durumunu güncelle
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

  // Yazma kutusu değişince "yazıyor..." durumu gönder (2 sn sessizlikte kapat)
  void _yaziyorDinle() {
    final bos = _mesajCtrl.text.trim().isEmpty;
    if (!bos && !_yaziyorGonderildi) {
      _yaziyorGonderildi = true;
      _presence.yaziyorAyarla(true);
    }
    _yaziyorTimer?.cancel();
    _yaziyorTimer = Timer(const Duration(seconds: 2), () {
      _yaziyorGonderildi = false;
      _presence.yaziyorAyarla(false);
    });
  }

  Future<void> _gonder() async {
    final metin = _mesajCtrl.text;
    if (metin.trim().isEmpty) return;
    _mesajCtrl.clear();
    _yaziyorTimer?.cancel();
    _yaziyorGonderildi = false;
    _presence.yaziyorAyarla(false);
    await _servis.gonder(metin);
    _enAltaKaydir();
  }

  void _enAltaKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Mesaja uzun basınca emoji tepki seçici
  void _tepkiSec(Mesaj mesaj) {
    const emojiler = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Renkler.yuzey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                    _servis.tepkiDegistir(mesaj.id, e);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _AppBarBaslik(presence: _presence),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AyarlarEkrani(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _presence.cevrimdisiYap();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Mesaj>>(
              stream: _servis.mesajlariDinle(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Renkler.accent),
                  );
                }
                if (snapshot.hasError) {
                  return const _BosDurum(
                    ikon: Icons.error_outline,
                    yazi: 'Mesajlar yüklenemedi',
                  );
                }

                final mesajlar = snapshot.data ?? [];
                if (mesajlar.isEmpty) {
                  return const _BosDurum(
                    ikon: Icons.chat_bubble_outline_rounded,
                    yazi: 'Henüz mesaj yok.\nİlk mesajı sen yaz 👋',
                  );
                }

                _servis.gorulduIsaretle(mesajlar);
                _enAltaKaydir();

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: mesajlar.length,
                  itemBuilder: (context, i) {
                    final m = mesajlar[i];
                    return _MesajBalonu(
                      mesaj: m,
                      benimMi: m.gonderen == _uid,
                      onUzunBas: () => _tepkiSec(m),
                    );
                  },
                );
              },
            ),
          ),
          _YazmaAlani(controller: _mesajCtrl, onGonder: _gonder),
        ],
      ),
    );
  }
}

/// AppBar başlığı: isim + altında çevrimiçi/yazıyor/son görülme durumu.
class _AppBarBaslik extends StatelessWidget {
  final PresenceServisi presence;
  const _AppBarBaslik({required this.presence});

  String _sonGorulmeMetni(Map<String, dynamic>? veri) {
    if (veri == null) return '';
    if (veri['yaziyor'] == true) return 'yazıyor...';
    if (veri['online'] == true) return 'çevrimiçi';
    final ts = veri['sonGorulme'];
    if (ts is Timestamp) {
      final t = ts.toDate();
      final s = t.hour.toString().padLeft(2, '0');
      final d = t.minute.toString().padLeft(2, '0');
      return 'son görülme $s:$d';
    }
    return 'çevrimdışı';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: presence.karsiTarafiDinle(),
      builder: (context, snap) {
        final durum = _sonGorulmeMetni(snap.data);
        final yaziyor = snap.data?['yaziyor'] == true;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kardeş Mesaj', style: TextStyle(fontSize: 18)),
            if (durum.isNotEmpty)
              Text(
                durum,
                style: TextStyle(
                  fontSize: 12,
                  color: yaziyor ? Renkler.accent : Renkler.metinSoluk,
                  fontWeight: yaziyor ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tek bir mesaj balonu (uzun basınca tepki seçici).
class _MesajBalonu extends StatelessWidget {
  final Mesaj mesaj;
  final bool benimMi;
  final VoidCallback onUzunBas;

  const _MesajBalonu({
    required this.mesaj,
    required this.benimMi,
    required this.onUzunBas,
  });

  String _saat(DateTime? t) {
    if (t == null) return '';
    final s = t.hour.toString().padLeft(2, '0');
    final d = t.minute.toString().padLeft(2, '0');
    return '$s:$d';
  }

  @override
  Widget build(BuildContext context) {
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: benimMi ? Renkler.benimBalon : Renkler.kardesBalon,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(benimMi ? 16 : 4),
                  bottomRight: Radius.circular(benimMi ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mesaj.metin,
                    style: TextStyle(
                      color: benimMi ? Colors.white : Renkler.metin,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _saat(mesaj.zaman),
                        style: TextStyle(
                          color: benimMi
                              ? Colors.white.withValues(alpha: 0.7)
                              : Renkler.metinSoluk,
                          fontSize: 11,
                        ),
                      ),
                      if (benimMi) ...[
                        const SizedBox(width: 4),
                        Icon(
                          mesaj.goruldu ? Icons.done_all : Icons.done,
                          size: 15,
                          color: mesaj.goruldu
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Tepki rozeti (balonun alt köşesinde)
            if (mesaj.tepki != null)
              Positioned(
                bottom: 0,
                right: benimMi ? 8 : null,
                left: benimMi ? null : 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Renkler.yuzey,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Renkler.zemin, width: 1.5),
                  ),
                  child: Text(mesaj.tepki!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Alt mesaj yazma çubuğu.
class _YazmaAlani extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onGonder;

  const _YazmaAlani({required this.controller, required this.onGonder});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        color: Renkler.yuzey,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onGonder(),
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: Renkler.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onGonder,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
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
          Icon(ikon, size: 56, color: Renkler.metinSoluk),
          const SizedBox(height: 12),
          Text(
            yazi,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Renkler.metinSoluk),
          ),
        ],
      ),
    );
  }
}
