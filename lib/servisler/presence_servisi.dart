import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/kullanici.dart';

/// Çevrimiçi/son görülme (kullanıcı bazlı) + "yazıyor" (sohbet bazlı).
/// FAZ 4: tek karşı taraf yerine belirli kullanıcı/sohbet.
///   users/{uid}.cevrimici / sonGorulme
///   chats/{chatId}.yaziyor.{uid}
///
/// ⚠️ Uygulama öldürülünce `detached` güvenilir gelmez → `cevrimdisiYap`
/// çalışmaz, `cevrimici=true` sonsuza kadar kalırdı. İdeal çözüm Realtime
/// Database `onDisconnect` (ANALIZ_RAPORU §2.3‑C) ama konsolda RTDB açmayı
/// gerektiriyor. Konsolsuz çözüm: ön plandayken NABIZ (60 sn'de bir
/// sonGorulme tazelenir) + okuyan taraf `Kullanici.cevrimici` getter'ında
/// sonGorulme 150 sn'den eskiyse ham bayrağı yok sayar.
class PresenceServisi {
  PresenceServisi._();
  static final PresenceServisi instance = PresenceServisi._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Nabız aralığı. Kullanici.cevrimiciEsigi (150 sn) bundan büyük olmalı:
  /// bir nabız kaçsa/gecikse bile kullanıcı "titreyerek" düşmesin.
  static const nabizAraligi = Duration(seconds: 60);

  Timer? _nabiz;

  /// Önceki nabız yazımı hâlâ bekliyor mu? (Çevrimdışıyken Firestore yazımı
  /// sunucuya ulaşana dek tamamlanmaz; her dakika yenisini kuyruğa eklemek
  /// bağlantı gelince bir yığın gereksiz yazıma dönüşürdü.)
  bool _nabizYaziliyor = false;

  /// Ön plandayken dakikada bir `cevrimiciYap`. Tekrar çağrılırsa (ör. hem
  /// initState hem resumed) eski zamanlayıcı iptal edilir → çift nabız yok.
  ///
  /// Maliyet: aktif (ekranı açık) kullanıcı başına dakikada 1 yazma.
  /// Spark planı günde 20 bin yazma verir → ~330 saat·kullanıcı/gün; aile
  /// ölçeğinde rahat, ama aralığı düşürmeden önce bunu hesaba katın.
  void nabziBaslat() {
    _nabiz?.cancel();
    _nabiz = Timer.periodic(nabizAraligi, (_) => _nabizAt());
  }

  /// Nabzı durdur (arka plan / çıkış). Çağıran ardından `cevrimdisiYap`
  /// yapar; zamanlayıcı ÖNCE durdurulmalı ki geç bir tik true'yu geri yazmasın.
  void nabziDurdur() {
    _nabiz?.cancel();
    _nabiz = null;
  }

  Future<void> _nabizAt() async {
    if (_nabizYaziliyor) return;
    _nabizYaziliyor = true;
    try {
      await cevrimiciYap();
    } catch (_) {
      // Ağ/izin hatası: bir sonraki nabız tekrar dener; zamanlayıcıdan
      // fırlayan yakalanmamış hata uygulamayı rahatsız etmesin.
    } finally {
      _nabizYaziliyor = false;
    }
  }

  /// Kendimi çevrimiçi işaretle.
  Future<void> cevrimiciYap() async {
    final uid = _uid;
    if (uid == null) return;
    final ref = _users.doc(uid);
    final once = DateTime.now();
    await ref.set({
      'cevrimici': true,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _saatiOlc(ref, once, DateTime.now());
  }

  /// Az önce yazılan sunucu damgasından yerel saat kaymasını ölçer.
  /// Yazım onaylanınca SDK çözülmüş damgayı önbelleğe işler → önbellekten
  /// okumak ücretsiz (faturalı okuma değil). Damga, yazımın gidiş-dönüşü
  /// içinde bir anda atanır → orta nokta tahmini; gidiş-dönüş uzunsa ölçüm
  /// güvenilmez, atlanır.
  Future<void> _saatiOlc(
    DocumentReference<Map<String, dynamic>> ref,
    DateTime once,
    DateTime sonra,
  ) async {
    final gidisDonus = sonra.difference(once);
    if (gidisDonus > const Duration(seconds: 5)) return;
    try {
      final snap = await ref.get(const GetOptions(source: Source.cache));
      final sunucu = (snap.data()?['sonGorulme'] as Timestamp?)?.toDate();
      if (sunucu == null) return;
      final orta = once.add(gidisDonus ~/ 2);
      Kullanici.saatDuzeltmesi = sunucu.difference(orta);
    } catch (_) {
      // Önbellekte yoksa düzeltme eski değerinde kalır (varsayılan sıfır).
    }
  }

  /// Kendimi çevrimdışı işaretle.
  Future<void> cevrimdisiYap() async {
    final uid = _uid;
    if (uid == null) return;
    await _users.doc(uid).set({
      'cevrimici': false,
      'sonGorulme': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Bir sohbette "yazıyor" durumumu güncelle.
  Future<void> yaziyorAyarla(String chatId, bool yaziyor) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('chats').doc(chatId).set(
        {'yaziyor': {uid: yaziyor}},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Belirli bir kullanıcının profil/durumunu canlı dinler
  /// (çevrimiçi/son görülme için).
  Stream<Kullanici> kullaniciDinle(String uid) => cevrimiciTazele(
        _users.doc(uid).snapshots().map(Kullanici.firestoreDan),
      );
}

/// [kaynak]'ı aynen geçirir; ama son gelen kullanıcı çevrimiçiyse, eşik
/// dolduğu anda AYNI değeri tekrar yayar → dinleyen ekran yeniden çizilir
/// ve `Kullanici.cevrimici` getter'ı artık false döner.
///
/// ⚠️ Neden: uygulaması öldürülen kullanıcının dokümanı bir daha DEĞİŞMEZ;
/// snapshots() yeni olay üretmez, ekran da kendiliğinden yeniden çizilmez →
/// getter doğru olsa bile "çevrimiçi" yazısı ekranda takılı kalırdı.
Stream<Kullanici> cevrimiciTazele(Stream<Kullanici> kaynak) {
  late final StreamController<Kullanici> c;
  StreamSubscription<Kullanici>? abone;
  Timer? zaman;

  void kur(Kullanici k) {
    zaman?.cancel();
    zaman = null;
    final kalan = k.cevrimdisiOlmayaKalan();
    if (kalan == null) return;
    // +1 sn: tam sınırda tetiklenip hâlâ "çevrimiçi" hesaplanmasın.
    zaman = Timer(kalan + const Duration(seconds: 1), () {
      if (!c.isClosed) {
        c.add(k);
        kur(k); // gelecek damga vb. durumda hâlâ çevrimiçiyse yeniden kur
      }
    });
  }

  c = StreamController<Kullanici>(
    onListen: () {
      abone = kaynak.listen(
        (k) {
          c.add(k);
          kur(k);
        },
        onError: c.addError,
        onDone: () {
          zaman?.cancel();
          c.close();
        },
      );
    },
    onPause: () => abone?.pause(),
    onResume: () => abone?.resume(),
    onCancel: () async {
      zaman?.cancel();
      await abone?.cancel();
    },
  );
  return c.stream;
}
