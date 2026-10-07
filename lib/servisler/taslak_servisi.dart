import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yarım kalan mesajlar (TASLAK): sohbetten çıkınca yazılan metin kaybolmaz,
/// sohbet listesinde "Taslak: …" görünür, sohbete dönünce yerinde durur.
/// Yalnız bu telefonda (SharedPreferences), hesap başına ayrı saklanır.
class TaslakServisi {
  TaslakServisi._();
  static final TaslakServisi instance = TaslakServisi._();

  /// chatId → taslak metni (sohbet listesi dinler).
  final ValueNotifier<Map<String, String>> taslaklar =
      ValueNotifier<Map<String, String>>(const {});

  SharedPreferences? _p;
  String? _uid;

  static String _anahtar(String uid) => 'taslaklar_$uid';

  /// Girişten sonra (AnaKabuk) bir kez: bu hesabın taslaklarını yükler.
  Future<void> yukle(String uid) async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    _uid = uid;
    taslaklar.value = taslaklariCoz(p.getString(_anahtar(uid)));
  }

  String? al(String chatId) => taslaklar.value[chatId];

  /// Taslağı kaydeder; metin boşsa siler. Değişmediyse diske yazmaz.
  void kaydet(String chatId, String metin) {
    final yeni = Map<String, String>.of(taslaklar.value);
    if (metin.trim().isEmpty) {
      if (yeni.remove(chatId) == null) return;
    } else {
      if (yeni[chatId] == metin) return;
      yeni[chatId] = metin;
    }
    taslaklar.value = yeni;
    final p = _p;
    final uid = _uid;
    if (p != null && uid != null) {
      p.setString(_anahtar(uid), jsonEncode(yeni)).ignore();
    }
  }

  /// Çıkışta: bellekteki taslaklar temizlenir (diskte hesaba bağlı kalır).
  void sifirla() {
    _uid = null;
    taslaklar.value = const {};
  }
}

/// Diskteki JSON → harita; bozuksa boş (saf → test).
Map<String, String> taslaklariCoz(String? ham) {
  if (ham == null || ham.isEmpty) return const {};
  try {
    final d = jsonDecode(ham);
    if (d is! Map) return const {};
    return {
      for (final e in d.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  } catch (_) {
    return const {};
  }
}
