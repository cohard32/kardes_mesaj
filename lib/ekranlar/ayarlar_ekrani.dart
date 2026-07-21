import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parcalar/guncelleme_akisi.dart';
import '../servisler/ayar_servisi.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/guncelleme_servisi.dart';
import '../servisler/hata_servisi.dart';
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
      body: Zemin(
        child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _BolumBaslik('Bildirimler'),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.bildirimAcik,
            builder: (context, acik, _) => _Kart(
              child: SwitchListTile(
                activeThumbColor: Renkler.neon,
                title: Text('Bildirimler', style: Yazi.isim),
                subtitle: Text('Yeni mesaj geldiğinde bildirim göster',
                    style: Yazi.kucuk),
                value: acik,
                onChanged: _ayar.bildirimAcikAyarla,
              ),
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _ayar.titresimAcik,
            builder: (context, acik, _) => _Kart(
              child: SwitchListTile(
                activeThumbColor: Renkler.neon,
                title: Text('Titreşim', style: Yazi.isim),
                subtitle: Text('Bildirimde titreşim', style: Yazi.kucuk),
                value: acik,
                onChanged: _ayar.titresimAcikAyarla,
              ),
            ),
          ),

          const _BolumBaslik('Bildirim Sesi'),

          _sesTile(deger: 'varsayilan', baslik: 'Varsayılan'),
          _sesTile(deger: 'sessiz', baslik: 'Sessiz'),
          _sesTile(
            deger: 'kedi',
            baslik: 'Yavru Kedi 1 🐱',
            onizlemeAsset: 'sesler/kedi.mp3',
          ),
          _sesTile(
            deger: 'kedi2',
            baslik: 'Yavru Kedi 2 😻',
            onizlemeAsset: 'sesler/kedi2.mp3',
          ),
          _sesTile(
            deger: 'kedi3',
            baslik: 'Yavru Kedi 3 🐈',
            onizlemeAsset: 'sesler/kedi3.mp3',
          ),
          _sesTile(
            deger: 'kedi4',
            baslik: 'Yavru Kedi 4 🐾',
            onizlemeAsset: 'sesler/kedi4.mp3',
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
                return _Kart(
                  secili: aktif,
                  child: ListTile(
                    leading: _SecimIsareti(aktif: aktif),
                    title: Text('Telefondan özel ses', style: Yazi.isim),
                    subtitle: Text(
                      var_ ? (ad ?? 'Özel ses') : 'Telefondaki bir sesi seç',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Yazi.kucuk,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.folder_open, color: Renkler.neon),
                      tooltip: 'Ses seç',
                      onPressed: _telefondanSec,
                    ),
                    onTap: var_ ? () => _sesSec('ozel') : _telefondanSec,
                  ),
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Önizlemek için ▶ düğmesine dokun. "Telefondan özel ses" ile '
              'cihazındaki herhangi bir bildirim sesini seçebilirsin. Seçtiğin '
              'ses, sana mesaj/arama geldiğinde çalar (uygulama kapalıyken bile).',
              style: Yazi.zaman,
            ),
          ),

          const _BolumBaslik('Arama Zil Sesi'),

          _zilTile(
            deger: AyarServisi.zilTelefon,
            baslik: 'Telefon zil sesi 📱',
            altYazi: 'Telefonunun kendi zil sesi (önerilen)',
          ),
          _zilTile(
            deger: AyarServisi.zilVarsayilan,
            baslik: 'Uygulama zili 🔔',
            altYazi: 'ROY MESSANGER varsayılan zili',
          ),
          _zilTile(
            deger: 'kedi',
            baslik: 'Yavru Kedi 1 🐱',
            onizlemeAsset: 'sesler/kedi.mp3',
          ),
          _zilTile(
            deger: 'kedi2',
            baslik: 'Yavru Kedi 2 😻',
            onizlemeAsset: 'sesler/kedi2.mp3',
          ),
          _zilTile(
            deger: 'kedi3',
            baslik: 'Yavru Kedi 3 🐈',
            onizlemeAsset: 'sesler/kedi3.mp3',
          ),
          _zilTile(
            deger: 'kedi4',
            baslik: 'Yavru Kedi 4 🐾',
            onizlemeAsset: 'sesler/kedi4.mp3',
          ),
          _zilTile(
            deger: 'cingirak',
            baslik: 'Çıngırak 🔔',
            onizlemeAsset: 'sesler/cingirak.wav',
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Seçtiğin zil, biri seni aradığında çalar (uygulama kapalıyken '
              'bile). Telefonun sessiz/titreşim modundaysa Android zili çalmaz — '
              'bu uygulamanın değil, telefonun ayarıdır. Arama titreşimi '
              'Android tarafından otomatik yönetilir.',
              style: Yazi.zaman,
            ),
          ),

          const _BolumBaslik('Uygulama'),

          _Kart(
            child: ListTile(
              leading: const Icon(Icons.system_update, color: Renkler.neon),
              title: Text('Güncellemeleri kontrol et', style: Yazi.isim),
              subtitle: Text('Yüklü sürüm: v${GuncellemeServisi.mevcutSurum}',
                  style: Yazi.kucuk),
              trailing:
                  const Icon(Icons.chevron_right, color: Renkler.metinSoluk),
              onTap: () => guncellemeAkisi(context, sessiz: false),
            ),
          ),

          _Kart(
            child: ListTile(
              leading: const Icon(Icons.bug_report_outlined,
                  color: Renkler.neon),
              title: Text('Sorun bildir', style: Yazi.isim),
              subtitle: Text(
                'Son işlemlerin kaydını geliştiriciye gönderir '
                '(arama/mesaj sorunlarını çözmek için)',
                style: Yazi.kucuk,
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: Renkler.metinSoluk),
              onTap: () async {
                final ok = await HataServisi.instance.manuelBildir(
                  'Kullanıcı sorun bildirdi',
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Rapor gönderildi ✓ Teşekkürler!'
                        : 'Rapor gönderilemedi (bağlantı yok)'),
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// ARAMA ZİLİ satırı (bildirim sesinden ayrı ayar: `AyarServisi.aramaZili`).
  /// Önizleme, gerçek zilin çalacağı yoldan (CallKit/res-raw) değil assets'ten
  /// çalar — ses dosyası aynıdır, amaç kullanıcının sesi duymasıdır.
  Widget _zilTile({
    required String deger,
    required String baslik,
    String? altYazi,
    String? onizlemeAsset,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: _ayar.aramaZili,
      builder: (context, secili, _) {
        final aktif = secili == deger;
        return _Kart(
          secili: aktif,
          child: ListTile(
            leading: _SecimIsareti(aktif: aktif),
            title: Text(baslik, style: Yazi.isim),
            subtitle: altYazi == null ? null : Text(altYazi, style: Yazi.kucuk),
            trailing: onizlemeAsset == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.play_circle_outline,
                        color: Renkler.neon),
                    tooltip: 'Önizle',
                    onPressed: () => _onizle(onizlemeAsset),
                  ),
            onTap: () => _ayar.aramaZiliAyarla(deger),
          ),
        );
      },
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
        return _Kart(
          secili: aktif,
          child: ListTile(
            leading: _SecimIsareti(aktif: aktif),
            title: Text(baslik, style: Yazi.isim),
            trailing: onizlemeAsset == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.play_circle_outline,
                        color: Renkler.neon),
                    tooltip: 'Önizle',
                    onPressed: () => _onizle(onizlemeAsset),
                  ),
            onTap: () => _sesSec(deger),
          ),
        );
      },
    );
  }
}

/// Seçili satırın neon işareti (radyo yerine tasarım dilinde nokta).
class _SecimIsareti extends StatelessWidget {
  final bool aktif;
  const _SecimIsareti({required this.aktif});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: aktif ? null : Renkler.zeminDerin,
        gradient: aktif ? Gradyanlar.accent : null,
        shape: BoxShape.circle,
        border: Border.all(
          color: aktif ? Colors.transparent : Renkler.kenarGuclu,
        ),
        boxShadow: aktif ? Golgeler.neonGlow : null,
      ),
      child: aktif
          ? const Icon(Icons.check, size: 14, color: Renkler.metinKoyu)
          : null,
    );
  }
}

/// Ayarlar satır kartı — organik köşe, seçiliyken neon kenar.
class _Kart extends StatelessWidget {
  final Widget child;
  final bool secili;
  const _Kart({required this.child, this.secili = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: Gradyanlar.yuzey,
          borderRadius: Kose.kartKose,
          border: Border.all(
            color: secili ? Renkler.neon.withValues(alpha: 0.45) : Renkler.kenar,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Text(
        yazi.toUpperCase(),
        style: Yazi.stil(12, FontWeight.w800, Renkler.neon, aralik: 0.8),
      ),
    );
  }
}
