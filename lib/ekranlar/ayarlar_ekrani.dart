import 'package:flutter/material.dart';

import '../servisler/ayar_servisi.dart';
import '../tema.dart';

/// Ayarlar ekranı: bildirim aç/kapa, titreşim, bildirim sesi.
class AyarlarEkrani extends StatelessWidget {
  const AyarlarEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    final ayar = AyarServisi.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          const _BolumBaslik('Bildirimler'),

          // Bildirim aç/kapa
          ValueListenableBuilder<bool>(
            valueListenable: ayar.bildirimAcik,
            builder: (context, acik, _) => SwitchListTile(
              activeThumbColor: Renkler.accent,
              title: const Text('Bildirimler'),
              subtitle: const Text('Yeni mesaj geldiğinde bildirim göster'),
              value: acik,
              onChanged: ayar.bildirimAcikAyarla,
            ),
          ),

          // Titreşim aç/kapa
          ValueListenableBuilder<bool>(
            valueListenable: ayar.titresimAcik,
            builder: (context, acik, _) => SwitchListTile(
              activeThumbColor: Renkler.accent,
              title: const Text('Titreşim'),
              subtitle: const Text('Bildirimde titreşim'),
              value: acik,
              onChanged: ayar.titresimAcikAyarla,
            ),
          ),

          const Divider(height: 1),
          const _BolumBaslik('Bildirim Sesi'),

          // Ses seçimi (RadioGroup: yeni Flutter API)
          ValueListenableBuilder<String>(
            valueListenable: ayar.bildirimSesi,
            builder: (context, secili, _) => RadioGroup<String>(
              groupValue: secili,
              onChanged: (v) {
                if (v != null) ayar.bildirimSesiAyarla(v);
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    title: Text('Varsayılan'),
                    value: 'varsayilan',
                  ),
                  RadioListTile<String>(
                    title: Text('Sessiz'),
                    value: 'sessiz',
                  ),
                ],
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Özel bildirim sesleri ileride eklenecek. Şimdilik varsayılan '
              'sistem sesi veya sessiz seçilebilir.',
              style: TextStyle(color: Renkler.metinSoluk, fontSize: 12),
            ),
          ),
        ],
      ),
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
