import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../modeller/kullanici.dart';
import '../yardimcilar/bildirim_yuku.dart';
import '../yardimcilar/hatirlatma_zamani.dart';
import '../yardimcilar/onemli_gun.dart';
import 'arkadas_servisi.dart';
import 'hata_servisi.dart';

/// DOĞUM GÜNÜ / ÖNEMLİ GÜN HATIRLATICISI.
///
/// * Arkadaşların doğum günleri profillerindeki `dogumGunu` ("AA-GG")
///   alanından gelir.
/// * Kişisel önemli günler YALNIZ sahibinin okuyabildiği gizli belgede:
///   `users/{uid}/ozel/hatirlaticilar` → `{gunler: [{id, ad, ay, gun}]}`
///   (kural: ozel/{belge} yalnız sahibi — ek kural gerekmez).
/// * Bildirimler TELEFONDA zamanlanır (sunucu yok): her yıl o gün saat
///   [saat]:00'da. Liste değişince hepsi iptal edilip yeniden kurulur.
///   Uygulama hiç açılmasa da Android alarmı çalar; telefon yeniden
///   başlayınca eklentinin BootReceiver'ı alarmları geri kurar.
class HatirlaticiServisi {
  HatirlaticiServisi._();
  static final HatirlaticiServisi instance = HatirlaticiServisi._();

  /// Bildirimin geleceği saat (yerel).
  static const int saat = 9;

  static const String kanalId = 'hatirlatici_v1';
  static const String _anahtarAcik = 'hatirlaticiAcik';
  static const String _anahtarKimlikler = 'hatirlaticiKimlikleri';

  /// Ayarlar'daki aç/kapa (varsayılan açık).
  final ValueNotifier<bool> acik = ValueNotifier<bool>(true);

  final _plugin = FlutterLocalNotificationsPlugin();
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _ozelBelge {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ozel')
        .doc('hatirlaticilar');
  }

  // ---- KİŞİSEL GÜNLER ----

  Stream<List<OnemliGun>> ozelGunleriDinle() {
    final belge = _ozelBelge;
    if (belge == null) return Stream.value(const []);
    return belge.snapshots().map((s) {
      final ham = s.data()?['gunler'];
      if (ham is! List) return const <OnemliGun>[];
      return [
        for (final h in ham) ?OnemliGun.haritadan(h),
      ];
    });
  }

  Future<void> ozelGunEkle(String ad, int ay, int gun) async {
    final belge = _ozelBelge;
    if (belge == null || !gecerliAyGun(ay, gun)) return;
    final g = OnemliGun(
      id: 'o_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      ad: ad.trim(),
      ay: ay,
      gun: gun,
    );
    await belge.set({
      'gunler': FieldValue.arrayUnion([g.haritaya()]),
    }, SetOptions(merge: true));
  }

  Future<void> ozelGunSil(OnemliGun g) async {
    final belge = _ozelBelge;
    if (belge == null) return;
    await belge.set({
      'gunler': FieldValue.arrayRemove([g.haritaya()]),
    }, SetOptions(merge: true));
  }

  // ---- ZAMANLAMA ----

  StreamSubscription<List<Kullanici>>? _arkadasAbone;
  StreamSubscription<List<OnemliGun>>? _ozelAbone;
  List<Kullanici> _arkadaslar = const [];
  List<OnemliGun> _ozel = const [];
  Timer? _gecikme;

  /// Arkadaşların doğum günleri + kişisel günler (bildirim/ekran için).
  static List<OnemliGun> birlestir(
    List<Kullanici> arkadaslar,
    List<OnemliGun> ozel,
  ) => [
    for (final k in arkadaslar)
      if (ayGunCoz(k.dogumGunu) case final ag?)
        OnemliGun(
          id: 'dg_${k.uid}',
          ad: k.ad,
          ay: ag.ay,
          gun: ag.gun,
          dogumGunu: true,
        ),
    ...ozel,
  ];

  /// Giriş sonrası (AnaKabuk) çağrılır: arkadaş listesini ve kişisel
  /// günleri dinler, değiştikçe bildirimleri yeniden kurar.
  Future<void> baslat() async {
    final p = await SharedPreferences.getInstance();
    acik.value = p.getBool(_anahtarAcik) ?? true;
    await _kanalKur();
    await _arkadasAbone?.cancel();
    await _ozelAbone?.cancel();
    _arkadasAbone = ArkadasServisi.instance.arkadaslar().listen((a) {
      _arkadaslar = a;
      _planlaGecikmeli();
    }, onError: (Object e) => HataServisi.instance.iz('hatirlatici arkadas: $e'));
    _ozelAbone = ozelGunleriDinle().listen((o) {
      _ozel = o;
      _planlaGecikmeli();
    }, onError: (Object e) => HataServisi.instance.iz('hatirlatici ozel: $e'));
  }

  /// Çıkışta: dinleyicileri kapat, bu hesabın TÜM yerel bildirimlerini
  /// (doğum günü, mesaj hatırlatmaları, ekrandakiler) sil — başka hesapla
  /// girilen telefonda eski hesabın hatırlatması çalmasın.
  Future<void> durdur() async {
    _gecikme?.cancel();
    await _arkadasAbone?.cancel();
    await _ozelAbone?.cancel();
    _arkadasAbone = null;
    _ozelAbone = null;
    _arkadaslar = const [];
    _ozel = const [];
    await _hepsiniIptal();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  // ---- "BUNU BANA HATIRLAT" (mesaj hatırlatması) ----

  static const String mesajKanalId = 'mesaj_hatirlatma_v1';

  /// [zaman]'da TEK SEFERLİK bildirim kurar; dokununca sohbet açılır.
  /// Kesin alarm izni varsa dakikası dakikasına, yoksa birkaç dakika
  /// sapmayla (pil tasarrufu modunda) çalar. Kimliği döner (geri almak için).
  Future<int> mesajHatirlat({
    required String chatId,
    required String karsiUid,
    required String baslik,
    required String ozet,
    required String mesajId,
    required DateTime zaman,
  }) async {
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await a?.createNotificationChannel(const AndroidNotificationChannel(
      mesajKanalId,
      'Mesaj hatırlatmaları',
      description: '"Bunu bana hatırlat" ile kurduğun hatırlatmalar',
      importance: Importance.high,
    ));
    var kesin = false;
    try {
      kesin = await a?.canScheduleExactNotifications() ?? false;
    } catch (_) {}
    final id = mesajHatirlatmaKimligi(mesajId, zaman);
    await _plugin.zonedSchedule(
      id: id,
      title: baslik,
      body: ozet,
      scheduledDate: tz.TZDateTime.from(zaman, tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          mesajKanalId,
          'Mesaj hatırlatmaları',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(ozet),
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: kesin
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: sohbetYuku(chatId, karsiUid),
    );
    HataServisi.instance.iz('MESAJ HATIRLATMA kuruldu kesin=$kesin');
    return id;
  }

  Future<void> mesajHatirlatmaIptal(int id) => _plugin.cancel(id: id);

  Future<void> acikAyarla(bool v) async {
    acik.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_anahtarAcik, v);
    await _planla();
  }

  // Arkadaş akışı açılışta art arda birkaç kez gelir → tek sefer kur.
  void _planlaGecikmeli() {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(seconds: 2), _planla);
  }

  Future<void> _kanalKur() async {
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await a?.createNotificationChannel(const AndroidNotificationChannel(
      kanalId,
      'Doğum günü ve önemli günler',
      description: 'Arkadaşlarının doğum günleri ve kendi eklediğin günler',
      importance: Importance.high,
    ));
  }

  Future<void> _hepsiniIptal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final eski = p.getStringList(_anahtarKimlikler) ?? const [];
      for (final k in eski) {
        final id = int.tryParse(k);
        if (id != null) await _plugin.cancel(id: id);
      }
      await p.remove(_anahtarKimlikler);
    } catch (e) {
      HataServisi.instance.iz('hatirlatici iptal edilemedi: $e');
    }
  }

  Future<void> _planla() async {
    await _hepsiniIptal();
    if (!acik.value || _uid == null) return;
    final gunler = birlestir(_arkadaslar, _ozel);
    final simdi = DateTime.now();
    final kurulan = <String>[];
    for (final g in gunler) {
      final id = hatirlaticiBildirimKimligi(g.id);
      var t = sonrakiTarih(g.ay, g.gun, simdi);
      var an = DateTime(t.year, t.month, t.day, saat);
      // Gün bugün ama saat geçti → yarından itibaren bir sonraki (gelecek yıl).
      if (!an.isAfter(simdi)) {
        t = sonrakiTarih(
            g.ay, g.gun, DateTime(simdi.year, simdi.month, simdi.day + 1));
        an = DateTime(t.year, t.month, t.day, saat);
      }
      try {
        // Yerel saat → mutlak an (UTC). Saat dilimi veritabanı gerekmez;
        // yıllık tekrar UTC'de aynı ay/gün/saatte olur (Türkiye'de yaz
        // saati yok → her yıl 09:00).
        await _plugin.zonedSchedule(
          id: id,
          title: g.bildirimBasligi,
          body: g.bildirimGovdesi,
          scheduledDate: tz.TZDateTime.from(an, tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              kanalId,
              'Doğum günü ve önemli günler',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // Kesin alarm izni (SCHEDULE_EXACT_ALARM) gerekmez; birkaç dakika
          // sapma hatırlatıcı için önemsiz.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          // 29 Şubat'ı yıllık tekrara bırakmak artık olmayan yıllarda
          // atlatırdı; o kayıt yine de her açılışta yeniden kurulur.
          matchDateTimeComponents: DateTimeComponents.dateAndTime,
        );
        kurulan.add('$id');
      } catch (e) {
        HataServisi.instance.iz('hatirlatici kurulamadi: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_anahtarKimlikler, kurulan);
    HataServisi.instance.iz('HATIRLATICI ${kurulan.length} gun kuruldu');
  }
}
