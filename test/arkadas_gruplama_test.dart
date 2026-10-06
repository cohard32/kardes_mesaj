// ArkadasServisi.arkadaslar() gruplu okuma mantığı — saf testler.

import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/servisler/arkadas_servisi.dart';

void main() {
  group('gruplaraBol', () {
    test('30\'arlık gruplar, son grup artan kadar', () {
      final l = List.generate(65, (i) => 'u$i');
      final g = gruplaraBol(l, 30);
      expect(g.map((x) => x.length).toList(), [30, 30, 5]);
      expect(g.expand((x) => x).toList(), l);
    });

    test('tam katı ve boş liste', () {
      expect(gruplaraBol(List.generate(60, (i) => i), 30).length, 2);
      expect(gruplaraBol(<int>[], 30), isEmpty);
    });
  });

  group('gruplarHalindeGetir', () {
    Future<Map<String, String>> sahte(List<String> grup) async =>
        {for (final u in grup) u: 'P:$u'};

    test('boş liste → hiç sorgu atılmaz', () async {
      var cagri = 0;
      final r = await gruplarHalindeGetir<String>(
        anahtarlar: const [],
        grupGetir: (g) async {
          cagri++;
          return {};
        },
      );
      expect(r, isEmpty);
      expect(cagri, 0);
    });

    test('sıra korunur (sonuç haritası sırası önemsiz) ve gruplar ≤ 30',
        () async {
      final uidler = List.generate(70, (i) => 'u${69 - i}');
      final boyutlar = <int>[];
      final r = await gruplarHalindeGetir<String>(
        anahtarlar: uidler,
        grupGetir: (g) async {
          boyutlar.add(g.length);
          // Sunucu belgeleri kimlik sırasıyla döndürür → ters çevir.
          return Map.fromEntries(
              (await sahte(g)).entries.toList().reversed);
        },
      );
      expect(r, [for (final u in uidler) 'P:$u']);
      expect(boyutlar..sort(), [10, 30, 30]);
    });

    test('bir grup hata verirse yalnız o grup atlanır, akış düşmez', () async {
      final uidler = List.generate(65, (i) => 'u$i');
      final hatalar = <List<String>>[];
      final r = await gruplarHalindeGetir<String>(
        anahtarlar: uidler,
        grupGetir: (g) async {
          if (g.contains('u30')) throw Exception('izin yok');
          return sahte(g);
        },
        hatada: (e, g) => hatalar.add(g),
      );
      expect(hatalar.single, uidler.sublist(30, 60));
      expect(r, [
        for (final u in [...uidler.sublist(0, 30), ...uidler.sublist(60)])
          'P:$u',
      ]);
    });

    test('belgesi olmayan uid atlanır', () async {
      final r = await gruplarHalindeGetir<String>(
        anahtarlar: const ['a', 'silinmis', 'b'],
        grupGetir: (g) async => {'a': 'A', 'b': 'B'},
      );
      expect(r, ['A', 'B']);
    });
  });
}
