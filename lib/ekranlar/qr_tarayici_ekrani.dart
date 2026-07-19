import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modeller/kullanici.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';
import 'profil_goruntule_ekrani.dart';

/// QR ile arkadaş bulma (FAZ 4 cila). Kamerayı açar, `kardesmesaj:@ad`
/// biçimindeki QR'ı okur → kullanıcıyı bulur → profilini açar (ekleme oradan).
/// Kart/Blaze gerektirmez: ML Kit barkod okuma CİHAZDA (on-device) çalışır.
class QrTarayiciEkrani extends StatefulWidget {
  const QrTarayiciEkrani({super.key});

  @override
  State<QrTarayiciEkrani> createState() => _QrTarayiciEkraniState();
}

class _QrTarayiciEkraniState extends State<QrTarayiciEkrani> {
  final _kontrol = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _islemde = false; // tek okuma (çift tetiklenmesin)

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  /// QR içeriğinden geçerli kullanıcı adını çözer.
  /// Kabul: `kardesmesaj:@welat`, `@welat`, `welat`.
  String? _kullaniciAdiCoz(String? ham) {
    if (ham == null) return null;
    var s = ham.trim();
    const onEk = 'kardesmesaj:';
    if (s.toLowerCase().startsWith(onEk)) s = s.substring(onEk.length);
    s = s.replaceFirst('@', '').trim().toLowerCase();
    return RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(s) ? s : null;
  }

  Future<void> _algila(BarcodeCapture capture) async {
    if (_islemde) return;
    final ham =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final ad = _kullaniciAdiCoz(ham);
    if (ad == null) return; // geçersiz/alakasız QR → okumaya devam
    _islemde = true;
    await _kontrol.stop();

    final Kullanici? k = await KullaniciServisi.instance.kullaniciAdindanBul(ad);
    if (!mounted) return;
    if (k == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@$ad bulunamadı')),
      );
      // Bulunamazsa taramaya devam et
      _islemde = false;
      await _kontrol.start();
      return;
    }
    // Bulundu → profili aç (tarayıcıyı değiştirerek; geri = arama ekranı)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProfilGoruntuleEkrani(kullanici: k),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Renkler.zeminDerin,
      appBar: AppBar(
        title: const Text('QR ile ekle'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Flaş',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _kontrol.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Kamera çevir',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _kontrol.switchCamera(),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _kontrol,
            onDetect: _algila,
            errorBuilder: (context, error) => _KameraHatasi(hata: error),
          ),
          // Tema çerçevesi (neon köşeli tarama penceresi)
          const _TaramaCercevesi(),
        ],
      ),
    );
  }
}

/// Kamera açılamazsa (izin yok / donanım) temalı hata + ayarlar.
class _KameraHatasi extends StatelessWidget {
  final MobileScannerException hata;
  const _KameraHatasi({required this.hata});

  @override
  Widget build(BuildContext context) {
    final izinSorunu =
        hata.errorCode == MobileScannerErrorCode.permissionDenied;
    return Zemin(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Renkler.neonSis,
                  borderRadius: Kose.kartKose,
                  border: Border.all(color: Renkler.kenar),
                ),
                child: const Icon(Icons.no_photography,
                    size: 38, color: Renkler.neon),
              ),
              const SizedBox(height: 16),
              Text(
                izinSorunu
                    ? 'Kamera izni gerekli.\nQR okumak için izin ver.'
                    : 'Kamera açılamadı.',
                textAlign: TextAlign.center,
                style: Yazi.kucuk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ortada neon köşeli tarama penceresi + alt yönerge (sadece görsel).
class _TaramaCercevesi extends StatelessWidget {
  const _TaramaCercevesi();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: Kose.kartKose,
                border: Border.all(color: Renkler.neon, width: 3),
                boxShadow: Golgeler.neonGlow,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: Kutular.duzYuzey(kose: Kose.alan, kenarli: true),
              child: Text('QR kodu çerçeveye hizala', style: Yazi.kucuk),
            ),
          ],
        ),
      ),
    );
  }
}
