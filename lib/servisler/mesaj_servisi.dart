import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../modeller/mesaj.dart';
import 'bildirim_servisi.dart';
import 'medya_servisi.dart';

/// Firestore üzerinde mesaj okuma/yazma işlemlerini yöneten servis.
/// İki kişilik tek sohbet olduğu için tek bir `mesajlar` koleksiyonu yeter.
class MesajServisi {
  MesajServisi._();
  static final MesajServisi instance = MesajServisi._();

  final CollectionReference<Map<String, dynamic>> _koleksiyon =
      FirebaseFirestore.instance.collection('mesajlar');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Tüm mesajları zaman sırasına göre (eski → yeni) canlı dinler.
  Stream<List<Mesaj>> mesajlariDinle() {
    return _koleksiyon
        .orderBy('zaman', descending: false)
        .snapshots()
        .map((anlik) =>
            anlik.docs.map((doc) => Mesaj.firestoreDan(doc)).toList());
  }

  /// Yeni mesaj gönderir (Firestore'a ekler). Boş mesaj gönderilmez.
  /// Gönderim sonrası karşı tarafa push bildirim tetikler.
  Future<void> gonder(String metin) async {
    final temiz = metin.trim();
    final uid = _uid;
    if (temiz.isEmpty || uid == null) return;

    await _koleksiyon.add(
      Mesaj.yeniMesajVerisi(gonderen: uid, metin: temiz),
    );

    // Karşı tarafa bildirim (fire-and-forget; mesaj zaten gitti, beklemeyiz)
    final eposta = FirebaseAuth.instance.currentUser?.email ?? 'Kardeş';
    BildirimServisi.instance.karsiTarafaBildirimGonder(
      baslik: eposta,
      govde: temiz,
    );
  }

  /// Medya (resim/video/ses) gönderir: önce Cloudinary'ye yükler,
  /// sonra Firestore'a medya mesajı ekler ve karşı tarafa bildirim atar.
  /// Yükleme başarısızsa false döner.
  Future<bool> medyaGonder(File dosya, MesajTipi tip) async {
    final uid = _uid;
    if (uid == null) return false;

    final url = await MedyaServisi.instance.yukle(dosya, tip);
    if (url == null) return false;

    await _koleksiyon.add(
      Mesaj.yeniMedyaVerisi(gonderen: uid, tip: tip, medyaUrl: url),
    );

    final eposta = FirebaseAuth.instance.currentUser?.email ?? 'Kardeş';
    final etiket = switch (tip) {
      MesajTipi.resim => '📷 Fotoğraf',
      MesajTipi.video => '🎥 Video',
      MesajTipi.ses => '🎤 Sesli mesaj',
      MesajTipi.gif => '🎞️ GIF',
      MesajTipi.metin => 'Mesaj',
    };
    BildirimServisi.instance.karsiTarafaBildirimGonder(
      baslik: eposta,
      govde: etiket,
    );
    return true;
  }

  /// GIF/sticker gönderir. GIPHY URL'i doğrudan Firestore'a yazılır
  /// (Cloudinary'ye yükleme gerekmez — GIF zaten internette barınıyor).
  Future<void> gifGonder(String url) async {
    final uid = _uid;
    if (uid == null) return;

    await _koleksiyon.add(
      Mesaj.yeniMedyaVerisi(gonderen: uid, tip: MesajTipi.gif, medyaUrl: url),
    );

    final eposta = FirebaseAuth.instance.currentUser?.email ?? 'Kardeş';
    BildirimServisi.instance.karsiTarafaBildirimGonder(
      baslik: eposta,
      govde: '🎞️ GIF',
    );
  }

  /// Karşı taraftan gelen bir sesli mesajı "dinlendi" işaretler.
  Future<void> sesDinlendiIsaretle(String mesajId) async {
    try {
      await _koleksiyon.doc(mesajId).update({'sesDinlendi': true});
    } catch (_) {
      // mesaj silinmiş olabilir; sessizce geç
    }
  }

  /// Bir mesaja emoji tepkisi ekler/kaldırır. Aynı emoji tekrar seçilirse
  /// tepki kaldırılır (toggle).
  Future<void> tepkiDegistir(String mesajId, String emoji) async {
    final doc = _koleksiyon.doc(mesajId);
    final mevcut = await doc.get();
    final eskiTepki = mevcut.data()?['tepki'] as String?;
    await doc.update({'tepki': eskiTepki == emoji ? null : emoji});
  }

  /// Karşı taraftan gelen, henüz görülmemiş mesajları "görüldü" işaretler.
  /// (Kendi mesajlarımı değil, karşı tarafınkileri.)
  Future<void> gorulduIsaretle(List<Mesaj> mesajlar) async {
    final uid = _uid;
    if (uid == null) return;

    final toplu = FirebaseFirestore.instance.batch();
    var degisiklikVar = false;

    for (final m in mesajlar) {
      if (m.gonderen != uid && !m.goruldu) {
        toplu.update(_koleksiyon.doc(m.id), {'goruldu': true});
        degisiklikVar = true;
      }
    }

    if (degisiklikVar) await toplu.commit();
  }
}
