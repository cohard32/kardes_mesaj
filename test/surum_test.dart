// Sürüm tutarlılığı + güncelleme onay kararı (Firebase gerektirmez).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/parcalar/guncelleme_akisi.dart';
import 'package:kardes_mesaj/servisler/guncelleme_servisi.dart';

void main() {
  // ⚠️ Sürüm iki yerde yazılı: pubspec.yaml (APK'nın versionName'i) ve
  // GuncellemeServisi.mevcutSurum (güncelleme kontrolünün karşılaştırdığı
  // derleme-zamanı sabiti). Biri unutulursa yeni APK kendini hâlâ eski sürüm
  // sanar → her açılışta aynı güncellemeyi tekrar önerir (sonsuz döngü). Bu
  // test CI'da unutulan sürüm artışını yakalar.
  test("pubspec 'version' X.Y.Z == GuncellemeServisi.mevcutSurum", () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final eslesme = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(eslesme, isNotNull,
        reason: "pubspec.yaml'da 'version: X.Y.Z+N' satırı bulunamadı");
    expect(
      GuncellemeServisi.mevcutSurum,
      eslesme!.group(1),
      reason: 'pubspec.yaml version ile guncelleme_servisi.dart mevcutSurum '
          'aynı olmalı — ikisini birlikte yükselt',
    );
  });

  group('guncellemeSorulmali', () {
    test('açılışta atlanan sürüm bir daha sorulmaz', () {
      expect(
        guncellemeSorulmali(yeniSurum: '1.9.0', atlanan: '1.9.0', sessiz: true),
        isFalse,
      );
    });

    test('açılışta atlanandan farklı (daha yeni) sürüm yine sorulur', () {
      expect(
        guncellemeSorulmali(yeniSurum: '1.9.1', atlanan: '1.9.0', sessiz: true),
        isTrue,
      );
      expect(
        guncellemeSorulmali(yeniSurum: '1.9.0', atlanan: null, sessiz: true),
        isTrue,
      );
    });

    test('manuel kontrol atlamayı yok sayar', () {
      expect(
        guncellemeSorulmali(
            yeniSurum: '1.9.0', atlanan: '1.9.0', sessiz: false),
        isTrue,
      );
    });
  });
}
