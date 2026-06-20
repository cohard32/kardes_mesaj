import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servisler/ayar_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../tema.dart';

/// Ayarlar ekranı: bildirim aç/kapa, titreşim, bildirim sesi
/// (varsayılan / sessiz / yavru kedi / çıngırak / telefondan özel ses).
class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key});

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  final _ayar = AyarServisi.instance;
  final _onizleyici = AudioPlayer();

  // Özel ses seçimi için native kanal (sistem zil sesi seçici).
  static const _sesKanali = MethodChannel('kardes_mesaj/sesler');

  @override
  void dispose() {
    _onizleyici.dispose();
    super.dispose();
  }

  Future<void> _sesSec(String deger) async {
    await _ayar.bildirimSesiAyarla(deger);
    await BildirimServisi.instance.sesGuncelle();
  }

  Future<void> _onizle(String asset) async {
    try {
      await _onizleyici.stop();
      await _onizleyici.play(AssetSource(asset));
    } catch (_) {}
  }

  Future<void> _telefondanSec() async {
    try {
      final r = await _sesKanali.invokeMethod<dynamic>(
        'sesSec',
        {'mevcut': _ayar.ozelSesUri.value},
      );
      if (r is Map) {
        final uri = r['uri'] as String?;
        final ad = (r['ad'] as String?) ?? 'Özel ses';
        if (uri != null) {
          await _ayar.ozelSesAyarla(uri, ad);
          await _sesSec('ozel');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ses seçilemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          const _BolumBaslik('Bildirimler'),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.bildirimAcik,
            builder: (context, acik, _) => SwitchListTile(
              activeThumbColor: Renkler.accent,
              title: const Text('Bildirimler'),
              subtitle: const Text('Yeni mesaj geldiğinde bildirim göster'),
              value: acik,
              onChanged: _ayar.bildirimAcikAyarla,
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.titresimAcik,
            builder: (context, acik, _) => SwitchListTile(
              activeThumbColor: Renkler.accent,
              title: const Text('Titreşim'),
              subtitle: const Text('Bildirimde titreşim'),
              value: acik,
              onChanged: _ayar.titresimAcikAyarla,
            ),
          ),

          const Divider(height: 1),
          const _BolumBaslik('Bildirim Sesi'),

          _sesTile(deger: 'varsayilan', baslik: 'Varsayılan'),
          _sesTile(deger: 'sessiz', baslik: 'Sessiz'),
          _sesTile(
            deger: 'kedi',
            baslik: 'Yavru Kedi 🐱',
            onizlemeAsset: 'sesler/kedi.mp3',
          ),
          _sesTile(
            deger: 'cingirak',
            baslik: 'Çıngırak 🔔',
            onizlemeAsset: 'sesler/cingirak.wav',
          ),

          // Telefondan özel ses
          ValueListenableBuilder<String?>(
            valueListenable: _ayar.ozelSesAdi,
            builder: (context, ad, _) => ValueListenableBuilder<String>(
              valueListenable: _ayar.bildirimSesi,
              builder: (context, secili, _) {
                final aktif = secili == 'ozel';
                final var_ = _ayar.ozelSesUri.value != null;
                return ListTile(
                  leading: Icon(
                    aktif
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: aktif ? Renkler.accent : Renkler.metinSoluk,
                  ),
                  title: const Text('Telefondan özel ses'),
                  subtitle: Text(
                    var_ ? (ad ?? 'Özel ses') : 'Telefondaki bir sesi seç',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Renkler.metinSoluk),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.folder_open, color: Renkler.accent),
                    tooltip: 'Ses seç',
                    onPressed: _telefondanSec,
                  ),
                  onTap: var_ ? () => _sesSec('ozel') : _telefondanSec,
                );
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Önizlemek için ▶ düğmesine dokun. "Telefondan özel ses" ile '
              'cihazındaki herhangi bir bildirim sesini seçebilirsin. Seçtiğin '
              'ses, sana mesaj/arama geldiğinde çalar (uygulama kapalıyken bile).',
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sesTile({
    required String deger,
    required String baslik,
    String? onizlemeAsset,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: _ayar.bildirimSesi,
      builder: (context, secili, _) {
        final aktif = secili == deger;
        return ListTile(
          leading: Icon(
            aktif ? Icons.radio_button_checked : Icons.radio_button_off,
            color: aktif ? Renkler.accent : Renkler.metinSoluk,
          ),
          title: Text(baslik),
          trailing: onizlemeAsset == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.play_circle_outline,
                      color: Renkler.accent),
                  tooltip: 'Önizle',
                  onPressed: () => _onizle(onizlemeAsset),
                ),
          onTap: () => _sesSec(deger),
        );
      },
    );
  }
}

class _BolumBaslik extends StatelessWidget {
  final String yazi;
  const _BolumBaslik(this.yazi);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        yazi.toUpperCase(),
        style: const TextStyle(
          color: Renkler.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
