import 'package:flutter/material.dart';

import '../modeller/kullanici.dart';
import '../servisler/arkadas_servisi.dart';
import '../servisler/hatirlatici_servisi.dart';
import '../servisler/kullanici_servisi.dart';
import '../tema.dart';
import '../yardimcilar/onemli_gun.dart';

/// Doğum günleri ve önemli günler: kendi doğum günün, arkadaşlarının
/// doğum günleri (profillerinden) ve senin eklediğin günler. Her biri için
/// o gün saat 09:00'da bildirim gelir.
class HatirlaticilarEkrani extends StatefulWidget {
  const HatirlaticilarEkrani({super.key});

  @override
  State<HatirlaticilarEkrani> createState() => _HatirlaticilarEkraniState();
}

class _HatirlaticilarEkraniState extends State<HatirlaticilarEkrani> {
  final _servis = HatirlaticiServisi.instance;
  late final Stream<Kullanici>? _ben = KullaniciServisi.instance.benimProfilim();
  late final Stream<List<Kullanici>> _arkadaslar =
      ArkadasServisi.instance.arkadaslar();
  late final Stream<List<OnemliGun>> _ozel = _servis.ozelGunleriDinle();

  Future<void> _dogumGunumuAyarla(String? mevcut) async {
    final ag = ayGunCoz(mevcut);
    final secim = await ayGunSec(
      context,
      baslik: 'Doğum günün',
      ay: ag?.ay,
      gun: ag?.gun,
      silinebilir: ag != null,
    );
    if (secim == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await KullaniciServisi.instance.dogumGunuAyarla(
        secim.sil ? null : ayGunYaz(secim.ay, secim.gun),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi. Tekrar dene.')),
      );
    }
  }

  Future<void> _gunEkle() async {
    final adCtrl = TextEditingController();
    final ad = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Önemli gün ekle'),
        content: TextField(
          controller: adCtrl,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Örn. Annemle babamın evlilik yıldönümü',
          ),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, adCtrl.text),
            child: const Text('Tarih seç'),
          ),
        ],
      ),
    );
    adCtrl.dispose();
    if (ad == null || ad.trim().isEmpty || !mounted) return;
    final secim = await ayGunSec(context, baslik: ad.trim());
    if (secim == null || secim.sil || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _servis.ozelGunEkle(ad, secim.ay, secim.gun);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Eklenemedi. Tekrar dene.')),
      );
    }
  }

  Future<void> _gunSil(OnemliGun g) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text('"${g.ad}" hatırlatıcısı silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Sil', style: TextStyle(color: Renkler.tehlike)),
          ),
        ],
      ),
    );
    if (onay == true) await _servis.ozelGunSil(g);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doğum günleri ve önemli günler')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Renkler.neon,
        foregroundColor: Renkler.metinKoyu,
        onPressed: _gunEkle,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Gün ekle'),
      ),
      body: Zemin(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _servis.acik,
              builder: (_, acik, _) => Container(
                decoration: Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
                child: SwitchListTile(
                  activeThumbColor: Renkler.neon,
                  title: Text('Hatırlatıcı bildirimleri', style: Yazi.isim),
                  subtitle: Text(
                    'O gün saat ${HatirlaticiServisi.saat.toString().padLeft(2, '0')}:00\'da bildirim',
                    style: Yazi.kucuk,
                  ),
                  value: acik,
                  onChanged: _servis.acikAyarla,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_ben != null)
              StreamBuilder<Kullanici>(
                stream: _ben,
                builder: (_, s) {
                  final dg = s.data?.dogumGunu;
                  final ag = ayGunCoz(dg);
                  return Container(
                    decoration:
                        Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
                    child: ListTile(
                      leading: const Text('🎂', style: TextStyle(fontSize: 26)),
                      title: Text('Benim doğum günüm', style: Yazi.isim),
                      subtitle: Text(
                        ag == null
                            ? 'Ayarla — arkadaşların hatırlatıcı alsın'
                            : '${ayGunMetni(ag.ay, ag.gun)} · yıl gösterilmez',
                        style: Yazi.kucuk,
                      ),
                      trailing: Icon(Icons.edit_calendar_rounded,
                          color: Renkler.neon),
                      onTap: s.hasData ? () => _dogumGunumuAyarla(dg) : null,
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
            StreamBuilder<List<Kullanici>>(
              stream: _arkadaslar,
              builder: (_, a) => StreamBuilder<List<OnemliGun>>(
                stream: _ozel,
                builder: (_, o) {
                  if (!a.hasData && !o.hasData) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: Renkler.neon),
                      ),
                    );
                  }
                  final gunler = yakinligaGoreSirala(
                    HatirlaticiServisi.birlestir(
                      a.data ?? const [],
                      o.data ?? const [],
                    ),
                    DateTime.now(),
                  );
                  if (gunler.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Henüz bir gün yok.\n'
                        'Arkadaşların doğum gününü profilinde ayarlayınca '
                        'burada görünür; kendi günlerini "Gün ekle" ile ekle.',
                        textAlign: TextAlign.center,
                        style: Yazi.kucuk,
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text('YAKLAŞANLAR', style: Yazi.neonKucuk),
                      ),
                      for (final g in gunler) _GunSatiri(
                        gun: g,
                        onSil: g.dogumGunu ? null : () => _gunSil(g),
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

class _GunSatiri extends StatelessWidget {
  final OnemliGun gun;
  final VoidCallback? onSil;
  const _GunSatiri({required this.gun, this.onSil});

  @override
  Widget build(BuildContext context) {
    final kalan = kalanGun(gun.ay, gun.gun, DateTime.now());
    final yakin = kalan <= 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: Kutular.duzYuzey(kose: Kose.kartKose, kenarli: true),
      child: ListTile(
        leading: Text(gun.dogumGunu ? '🎂' : '📅',
            style: const TextStyle(fontSize: 24)),
        title: Text(gun.ad,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: Yazi.isim),
        subtitle: Text(ayGunMetni(gun.ay, gun.gun), style: Yazi.kucuk),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kalanMetni(kalan),
              style: yakin ? Yazi.neonKucuk : Yazi.kucuk,
            ),
            if (onSil != null)
              IconButton(
                tooltip: 'Sil',
                icon: Icon(Icons.delete_outline, color: Renkler.metinSoluk),
                onPressed: onSil,
              ),
          ],
        ),
      ),
    );
  }
}

/// Ay + gün seçici (yıl yok). [silinebilir] ise "Kaldır" düğmesi de çıkar
/// (sonuç `sil: true`). Vazgeçilirse null.
Future<({int ay, int gun, bool sil})?> ayGunSec(
  BuildContext context, {
  required String baslik,
  int? ay,
  int? gun,
  bool silinebilir = false,
}) {
  var secAy = ay ?? DateTime.now().month;
  var secGun = gun ?? DateTime.now().day;
  return showDialog<({int ay, int gun, bool sil})>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, yenile) {
        if (secGun > ayinGunSayisi(secAy)) secGun = ayinGunSayisi(secAy);
        return AlertDialog(
          title: Text(baslik, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: secGun,
                  dropdownColor: Renkler.yuzey,
                  items: [
                    for (var g = 1; g <= ayinGunSayisi(secAy); g++)
                      DropdownMenuItem(value: g, child: Text('$g')),
                  ],
                  onChanged: (v) => yenile(() => secGun = v ?? secGun),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: secAy,
                  dropdownColor: Renkler.yuzey,
                  items: [
                    for (var a = 1; a <= 12; a++)
                      DropdownMenuItem(value: a, child: Text(ayAdlari[a - 1])),
                  ],
                  onChanged: (v) => yenile(() => secAy = v ?? secAy),
                ),
              ),
            ],
          ),
          actions: [
            if (silinebilir)
              TextButton(
                onPressed: () =>
                    Navigator.pop(d, (ay: secAy, gun: secGun, sil: true)),
                child: Text('Kaldır', style: TextStyle(color: Renkler.tehlike)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(d, (ay: secAy, gun: secGun, sil: false)),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    ),
  );
}
