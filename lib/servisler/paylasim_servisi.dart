import 'package:flutter/services.dart';

import 'hata_servisi.dart';

/// Başka uygulamadan paylaşılan, telefona kopyalanmış bir dosya.
class PaylasilanDosya {
  final String yol;
  final String ad;
  final int boyut;
  final String mime;
  const PaylasilanDosya({
    required this.yol,
    required this.ad,
    required this.boyut,
    required this.mime,
  });

  bool get resimMi => mime.startsWith('image/');
  bool get videoMu => mime.startsWith('video/');

  /// Fotoğraf/video DEĞİL → belge olarak gider.
  bool get belgeMi => !resimMi && !videoMu;
}

/// "Paylaş → ROY MESSANGER" ile gelen içerik.
class GelenPaylasim {
  /// Paylaşılan metin / link (yoksa null).
  final String? metin;
  final List<PaylasilanDosya> dosyalar;

  /// 100 MB'tan büyük olduğu için alınamayan dosyaların adları.
  final List<String> buyukler;

  const GelenPaylasim({
    this.metin,
    this.dosyalar = const [],
    this.buyukler = const [],
  });

  bool get bos =>
      (metin == null || metin!.trim().isEmpty) &&
      dosyalar.isEmpty &&
      buyukler.isEmpty;

  /// Kime gönderileceği seçilirken gösterilen özet.
  String get ozet {
    final parcalar = <String>[];
    final foto = dosyalar.where((d) => d.resimMi).length;
    final video = dosyalar.where((d) => d.videoMu).length;
    final belge = dosyalar.where((d) => d.belgeMi).length;
    if (foto > 0) parcalar.add(foto == 1 ? '1 fotoğraf' : '$foto fotoğraf');
    if (video > 0) parcalar.add(video == 1 ? '1 video' : '$video video');
    if (belge > 0) {
      parcalar.add(belge == 1 ? dosyalar.firstWhere((d) => d.belgeMi).ad : '$belge belge');
    }
    final m = metin?.trim();
    if (m != null && m.isNotEmpty) {
      parcalar.add(m.length > 60 ? '"${m.substring(0, 60)}…"' : '"$m"');
    }
    return parcalar.isEmpty ? 'Paylaşım' : parcalar.join(' · ');
  }
}

/// Android'in verdiği ham haritayı çözer (saf → test). Bozuk girdiler atlanır.
GelenPaylasim? paylasimCoz(Object? ham) {
  if (ham is! Map) return null;
  final metin = ham['metin'];
  final dosyalar = <PaylasilanDosya>[];
  final hamDosyalar = ham['dosyalar'];
  if (hamDosyalar is List) {
    for (final d in hamDosyalar) {
      if (d is! Map) continue;
      final yol = d['yol'];
      if (yol is! String || yol.isEmpty) continue;
      final ad = d['ad'];
      final boyut = d['boyut'];
      final mime = d['mime'];
      dosyalar.add(PaylasilanDosya(
        yol: yol,
        ad: ad is String && ad.isNotEmpty ? ad : 'dosya',
        boyut: boyut is int ? boyut : 0,
        mime: mime is String ? mime : 'application/octet-stream',
      ));
    }
  }
  final buyukler = <String>[
    if (ham['buyukler'] case final List l)
      for (final a in l)
        if (a is String) a,
  ];
  final p = GelenPaylasim(
    metin: metin is String ? metin : null,
    dosyalar: dosyalar,
    buyukler: buyukler,
  );
  return p.bos ? null : p;
}

/// Bekleyen paylaşımı Android'den alır (bkz. Paylasim.kt → PaylasimDeposu).
class PaylasimServisi {
  PaylasimServisi._();
  static final PaylasimServisi instance = PaylasimServisi._();

  static const _kanal = MethodChannel('kardes_mesaj/sesler');

  /// Bekleyen paylaşım (yoksa null). Alınan paylaşım Android'de silinir.
  Future<GelenPaylasim?> al() async {
    try {
      return paylasimCoz(await _kanal.invokeMethod<Object?>('paylasimAl'));
    } catch (e) {
      HataServisi.instance.iz('paylasim alinamadi: $e');
      return null;
    }
  }
}
