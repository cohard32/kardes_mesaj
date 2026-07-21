import 'dart:io';
import 'hata_servisi.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/mesaj.dart';
import 'bildirim_servisi.dart';
import 'kullanici_servisi.dart';
import 'medya_servisi.dart';

/// Sohbet bazlı mesaj okuma/yazma (FAZ 4.6).
/// Mesajlar `chats/{chatId}/messages` altında. Gönderimde sohbet meta'sı
/// (sonMesaj/okunmamış) güncellenir ve karşı tarafa hedefli bildirim gider.
class MesajServisi {
  MesajServisi._();
  static final MesajServisi instance = MesajServisi._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _chat(String chatId) =>
      _db.collection('chats').doc(chatId);
  CollectionReference<Map<String, dynamic>> _mesajlar(String chatId) =>
      _chat(chatId).collection('messages');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String? _benimAdimCache;
  Future<String> _benimAdim() async {
    if (_benimAdimCache != null) return _benimAdimCache!;
    final uid = _uid;
    if (uid == null) return 'Mesaj';
    final k = await KullaniciServisi.instance.profilGetir(uid);
    _benimAdimCache = (k?.ad.isNotEmpty ?? false) ? k!.ad : 'Mesaj';
    return _benimAdimCache!;
  }

  /// Bir sohbetin SON [limit] mesajını zaman sırasına göre (eski → yeni) dinler.
  /// [limit] artırılınca daha eski mesajlar yüklenir (sohbet ekranı yukarı
  /// kaydırınca artırır) — tüm geçmişi tek seferde çekmez (pil/kota/bellek).
  Stream<List<Mesaj>> mesajlariDinle(String chatId, {int limit = 50}) {
    return _mesajlar(chatId)
        .orderBy('zaman', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((s) => s.docs.map(Mesaj.firestoreDan).toList());
  }

  /// Metin mesajı gönderir + sohbet meta güncelle + karşı tarafa bildirim.
  Future<void> gonder(String chatId, String alanUid, String metin) async {
    final temiz = metin.trim();
    final uid = _uid;
    if (temiz.isEmpty || uid == null) return;

    HataServisi.instance.iz('MESAJ gonderiliyor chat=$chatId');
    await _mesajlar(chatId).add(
      Mesaj.yeniMesajVerisi(gonderen: uid, metin: temiz),
    );
    await _metaGuncelle(chatId, alanUid, temiz);
    _bildir(alanUid, chatId, temiz);
  }

  /// Medya (resim/video/ses) gönderir (Cloudinary'ye yükler).
  Future<bool> medyaGonder(String chatId, String alanUid, File dosya,
      MesajTipi tip) async {
    final uid = _uid;
    if (uid == null) return false;
    HataServisi.instance.iz('MEDYA yukleniyor tip=${tip.name}');
    final url = await MedyaServisi.instance.yukle(dosya, tip);
    if (url == null) {
      HataServisi.instance.iz('MEDYA YUKLENEMEDI (Cloudinary null)');
      return false;
    }
    HataServisi.instance.iz('MEDYA yuklendi');

    await _mesajlar(chatId).add(
      Mesaj.yeniMedyaVerisi(gonderen: uid, tip: tip, medyaUrl: url),
    );
    final etiket = switch (tip) {
      MesajTipi.resim => '📷 Fotoğraf',
      MesajTipi.video => '🎥 Video',
      MesajTipi.ses => '🎤 Sesli mesaj',
      MesajTipi.gif => '🎞️ GIF',
      MesajTipi.metin => 'Mesaj',
    };
    await _metaGuncelle(chatId, alanUid, etiket);
    _bildir(alanUid, chatId, etiket);
    return true;
  }

  /// GIF gönderir (GIPHY URL doğrudan yazılır).
  Future<void> gifGonder(String chatId, String alanUid, String url) async {
    final uid = _uid;
    if (uid == null) return;
    await _mesajlar(chatId).add(
      Mesaj.yeniMedyaVerisi(gonderen: uid, tip: MesajTipi.gif, medyaUrl: url),
    );
    await _metaGuncelle(chatId, alanUid, '🎞️ GIF');
    _bildir(alanUid, chatId, '🎞️ GIF');
  }

  /// Karşı taraftan gelen sesli mesajı "dinlendi" işaretler.
  Future<void> sesDinlendiIsaretle(String chatId, String mesajId) async {
    try {
      await _mesajlar(chatId).doc(mesajId).update({'sesDinlendi': true});
    } catch (_) {}
  }

  /// Mesajın geri alınabileceği süre. Sunucu kuralında da AYNI değer var
  /// (firestore.rules → messages allow delete). İkisi birlikte değişmeli.
  static const Duration silmeSuresi = Duration(seconds: 60);

  /// Bu mesaj ŞU AN silinebilir mi? (kendi mesajım + ilk 60 saniye)
  /// Yalnızca ARAYÜZ içindir; asıl kısıt sunucu kuralındadır.
  bool silinebilirMi(Mesaj m) {
    if (m.gonderen != _uid) return false;
    final t = m.zaman;
    if (t == null) return true; // henüz sunucu damgası yok = az önce gönderildi
    return DateTime.now().difference(t) < silmeSuresi;
  }

  /// Mesajı siler (yalnız kendi mesajın, ilk 60 sn). Silinen son mesajsa
  /// sohbet önizlemesi de tazelenir — yoksa listede SİLİNMİŞ metin görünürdü.
  Future<void> mesajSil(String chatId, String mesajId) async {
    HataServisi.instance.iz('MESAJ siliniyor chat=$chatId');
    await _mesajlar(chatId).doc(mesajId).delete();
    await _sonMesajTazele(chatId);
  }

  /// Silmeden sonra sohbet meta'sını kalan SON mesaja göre günceller.
  Future<void> _sonMesajTazele(String chatId) async {
    try {
      final son = await _mesajlar(chatId)
          .orderBy('zaman', descending: true)
          .limit(1)
          .get();
      if (son.docs.isEmpty) {
        await _chat(chatId).set({
          'sonMesaj': '',
          'sonMesajGonderen': null,
        }, SetOptions(merge: true));
        return;
      }
      final m = Mesaj.firestoreDan(son.docs.first);
      final onizleme = switch (m.tip) {
        MesajTipi.resim => '📷 Fotoğraf',
        MesajTipi.video => '🎥 Video',
        MesajTipi.ses => '🎤 Sesli mesaj',
        MesajTipi.gif => '🎞️ GIF',
        MesajTipi.metin => m.metin,
      };
      await _chat(chatId).set({
        'sonMesaj': onizleme,
        'sonMesajZamani': m.zaman == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(m.zaman!),
        'sonMesajGonderen': m.gonderen,
      }, SetOptions(merge: true));
    } catch (e) {
      HataServisi.instance.iz('son mesaj tazelenemedi: $e');
    }
  }

  /// Bir mesaja emoji tepkisi ekler/kaldırır (toggle).
  Future<void> tepkiDegistir(
      String chatId, String mesajId, String emoji) async {
    final doc = _mesajlar(chatId).doc(mesajId);
    final mevcut = await doc.get();
    final eskiTepki = mevcut.data()?['tepki'] as String?;
    await doc.update({'tepki': eskiTepki == emoji ? null : emoji});
  }

  /// Karşı taraftan gelen görülmemiş mesajları "görüldü" işaretler + okundu.
  Future<void> gorulduIsaretle(String chatId, List<Mesaj> mesajlar) async {
    final uid = _uid;
    if (uid == null) return;

    final toplu = _db.batch();
    var degisiklikVar = false;
    for (final m in mesajlar) {
      if (m.gonderen != uid && !m.goruldu) {
        toplu.update(_mesajlar(chatId).doc(m.id), {'goruldu': true});
        degisiklikVar = true;
      }
    }
    if (degisiklikVar) await toplu.commit();
  }

  // ---- yardımcılar ----

  /// Sohbet meta'sını güncelle: son mesaj + karşı tarafın okunmamışını +1.
  Future<void> _metaGuncelle(
      String chatId, String alanUid, String onizleme) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _chat(chatId).set({
        'sonMesaj': onizleme,
        'sonMesajZamani': FieldValue.serverTimestamp(),
        'sonMesajGonderen': uid,
        'okunmamis': {alanUid: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Karşı tarafa hedefli bildirim (fire-and-forget). Bildirime tıklanınca
  /// doğru sohbet açılsın diye chatId/gönderen data'da taşınır.
  void _bildir(String alanUid, String chatId, String onizleme) async {
    final ad = await _benimAdim();
    BildirimServisi.instance.hedefeBildirimGonder(
      hedefUid: alanUid,
      baslik: ad,
      govde: onizleme,
      ekstraData: {
        'tur': 'mesaj',
        'chatId': chatId,
        'gonderenUid': _uid ?? '',
      },
    );
  }
}
