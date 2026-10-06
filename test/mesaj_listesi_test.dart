// MesajListesi (sohbet ekranının kaydırma mantığı) widget testleri.
// Firebase gerektirmez: liste saf bir widget'tır, mesajlar elle verilir.
//
// Kanıtlanan davranışlar:
//  (a) yukarıda geçmişi okurken yeni mesaj gelince görünen içerik KAYMAZ,
//  (b) eski sayfa yüklenince görünen içerik KAYMAZ,
//  (c) en alttayken yeni mesaj gelince alta takip edilir,
//  (d) kendi mesajın gelince (nerede olursan ol) en alta inilir,
//  (e) üste yaklaşınca 'eski yükle' bir kez çağrılır,
//  ve State'ler (oynayan video vb.) index'te değil mesajda kalır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kardes_mesaj/modeller/mesaj.dart';
import 'package:kardes_mesaj/parcalar/mesaj_listesi.dart';

const _ben = 'ben';
const _karsi = 'karsi';
const _alt = 12.0; // MesajListesi.dikeyBosluk varsayılanı

/// n numaralı mesaj (büyük numara = daha yeni).
Mesaj _m(int n, {String gonderen = _karsi}) =>
    Mesaj(id: 'm$n', gonderen: gonderen, metin: 'm$n');

/// [bas]..[son] arası mesajlar YENİDEN ESKİYE (akıştaki sıra).
List<Mesaj> _aralik(int bas, int son) => [
  for (var n = son; n >= bas; n--) _m(n),
];

/// Değişken yükseklikli öğe (gerçek balonlar gibi farklı boylarda).
double _boy(String id) => 40.0 + (id.hashCode % 4) * 15.0;

/// Kendi kimliğini initState'te ezberleyen öğe: State başka mesaja geçerse
/// `ilkId != mesaj.id` olur. Dokununca işaretlenir (oynayan video yerine).
class _DurumluOge extends StatefulWidget {
  const _DurumluOge(this.mesaj);
  final Mesaj mesaj;
  @override
  State<_DurumluOge> createState() => _DurumluOgeState();
}

class _DurumluOgeState extends State<_DurumluOge> {
  late final String ilkId = widget.mesaj.id;
  bool isaretli = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => isaretli = true),
      child: SizedBox(
        height: _boy(widget.mesaj.id),
        child: Text('${widget.mesaj.id}${isaretli ? '*' : ''}'),
      ),
    );
  }
}

class _Duzenek {
  _Duzenek(List<Mesaj> ilk) : mesajlar = ValueNotifier<List<Mesaj>>(ilk);
  final ValueNotifier<List<Mesaj>> mesajlar;
  final ctrl = ScrollController(initialScrollOffset: -_alt);
  int eskiCagri = 0;
  bool dahaVar = true;

  Widget kur() => MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<List<Mesaj>>(
        valueListenable: mesajlar,
        builder: (_, liste, _) => MesajListesi(
          mesajlar: liste,
          benimUid: _ben,
          controller: ctrl,
          eskiYukle: dahaVar ? () => eskiCagri++ : null,
          ogeKurucu: (_, m) => _DurumluOge(m),
        ),
      ),
    ),
  );

  /// Başa (en yeni tarafa) mesaj ekle.
  void yeniGeldi(List<Mesaj> yeniler) =>
      mesajlar.value = [...yeniler, ...mesajlar.value];

  /// Sona (en eski tarafa) eski sayfa ekle.
  void eskiGeldi(List<Mesaj> eskiler) =>
      mesajlar.value = [...mesajlar.value, ...eskiler];

  ScrollPosition get pos => ctrl.position;
}

/// Ekranda (800x600 görüntü alanı içinde) tamamen görünen öğelerin kimlikleri.
List<String> _gorunenler(WidgetTester tester) {
  final sonuc = <String>[];
  for (final s in tester.stateList<_DurumluOgeState>(
    find.byType(_DurumluOge),
  )) {
    final r = tester.getRect(find.byWidget(s.widget));
    if (r.top >= 0 && r.bottom <= 600) sonuc.add(s.widget.mesaj.id);
  }
  return sonuc;
}

Map<String, Offset> _konumlar(WidgetTester tester, List<String> idler) => {
  for (final id in idler) id: tester.getTopLeft(find.text(id)),
};

/// Kurulu her öğenin State'i kendi mesajında mı (index'e göre kaymadı mı)?
void _durumlarMesajda(WidgetTester tester) {
  for (final s in tester.stateList<_DurumluOgeState>(
    find.byType(_DurumluOge),
  )) {
    expect(s.ilkId, s.widget.mesaj.id, reason: 'State başka mesaja geçti');
  }
}

/// Görünen öğeler doğru sırada mı (daha yeni = daha aşağıda)?
void _siraDogru(WidgetTester tester) {
  final g = _gorunenler(tester)
    ..sort(
      (a, b) => int.parse(a.substring(1)).compareTo(int.parse(b.substring(1))),
    );
  for (var i = 1; i < g.length; i++) {
    final once = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is _DurumluOge && w.mesaj.id == g[i - 1]),
    );
    final sonra = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is _DurumluOge && w.mesaj.id == g[i]),
    );
    expect(
      sonra.dy,
      greaterThan(once.dy),
      reason: '${g[i]} ${g[i - 1]} altında olmalı',
    );
  }
}

void main() {
  testWidgets('açılışta en altta: en yeni mesaj alt boşluğun hemen üstünde', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m59')).dy, 600 - _alt);
    _siraDogru(tester);
  });

  testWidgets(
    '(a) yukarıda okurken yeni mesajlar gelince görünen içerik kaymaz',
    (tester) async {
      final d = _Duzenek(_aralik(0, 59));
      await tester.pumpWidget(d.kur());
      d.ctrl.jumpTo(1500);
      await tester.pumpAndSettle();
      final gorunen = _gorunenler(tester);
      expect(gorunen, isNotEmpty);
      final once = _konumlar(tester, gorunen);

      for (var n = 60; n < 65; n++) {
        d.yeniGeldi([_m(n)]);
        await tester.pumpAndSettle();
        expect(_konumlar(tester, gorunen), once, reason: 'm$n gelince kaydı');
      }
      // Aynı anda birden çok mesaj da kaydırmaz.
      d.yeniGeldi([_m(67), _m(66), _m(65)]);
      await tester.pumpAndSettle();
      expect(_konumlar(tester, gorunen), once);
      expect(d.pos.pixels, 1500);
      _durumlarMesajda(tester);

      // Aşağı inince yeni mesajlar doğru sırada, en altta.
      d.ctrl.jumpTo(d.pos.minScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.text('m67')).dy, 600 - _alt);
      _siraDogru(tester);
      _durumlarMesajda(tester);
    },
  );

  testWidgets(
    '(a) yeni mesajlar alanını okurken daha yeni mesaj gelince de kaymaz',
    (tester) async {
      final d = _Duzenek(_aralik(0, 59));
      await tester.pumpWidget(d.kur());
      d.ctrl.jumpTo(1000);
      await tester.pumpAndSettle();
      d.yeniGeldi(_aralik(60, 75));
      await tester.pumpAndSettle();
      // Yeni gelenlerin arasına kaydır (en alttan uzak).
      d.ctrl.jumpTo(d.pos.minScrollExtent + 300);
      await tester.pumpAndSettle();
      final gorunen = _gorunenler(tester);
      expect(gorunen, contains('m70'));
      final once = _konumlar(tester, gorunen);
      d.yeniGeldi([_m(76)]);
      await tester.pumpAndSettle();
      expect(_konumlar(tester, gorunen), once);
      _durumlarMesajda(tester);
    },
  );

  testWidgets('(b) eski sayfa yüklenince görünen içerik kaymaz', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(50, 99));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1200);
    await tester.pumpAndSettle();
    final gorunen = _gorunenler(tester);
    final once = _konumlar(tester, gorunen);

    d.eskiGeldi(_aralik(0, 49));
    await tester.pumpAndSettle();
    expect(_konumlar(tester, gorunen), once);

    // Bekleyen yeni mesajlar varken de (iki sliver birlikte) kaymaz.
    d.yeniGeldi([_m(100)]);
    await tester.pumpAndSettle();
    expect(_konumlar(tester, gorunen), once);
    d.eskiGeldi([for (var n = -1; n >= -30; n--) _m(n)]);
    await tester.pumpAndSettle();
    expect(_konumlar(tester, gorunen), once);
    _durumlarMesajda(tester);
  });

  testWidgets('(b) sabit pencere: yeni mesajla en eski düşünce kaymaz', (
    tester,
  ) async {
    // Akış `limit(N)` → yeni mesaj gelince en eski mesaj listeden düşer.
    final d = _Duzenek(_aralik(0, 49));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(800);
    await tester.pumpAndSettle();
    final gorunen = _gorunenler(tester);
    final once = _konumlar(tester, gorunen);
    d.mesajlar.value = _aralik(1, 50);
    await tester.pumpAndSettle();
    expect(_konumlar(tester, gorunen), once);
  });

  testWidgets('(c) en alttayken yeni mesaj gelince alta takip edilir', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.yeniGeldi([_m(60)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m60')).dy, 600 - _alt);
    expect(
      tester.getBottomLeft(find.text('m59')).dy,
      tester.getTopLeft(find.text('m60')).dy,
    );

    // Alta çok yakınken (eşik içinde) de takip eder.
    d.ctrl.jumpTo(-_alt + 40);
    await tester.pumpAndSettle();
    d.yeniGeldi([_m(61)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m61')).dy, 600 - _alt);
    _siraDogru(tester);
    _durumlarMesajda(tester);
  });

  testWidgets('(c) kısa sohbet: alt boşluk ve takip', (tester) async {
    final d = _Duzenek(_aralik(0, 2));
    await tester.pumpWidget(d.kur());
    expect(tester.getBottomLeft(find.text('m2')).dy, 600 - _alt);
    d.yeniGeldi([_m(3)]);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('m3')).dy, 600 - _alt);
    _siraDogru(tester);
  });

  testWidgets('(d) yukarıdayken kendi mesajın gelince en alta inilir', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(2000);
    await tester.pumpAndSettle();
    // Önce karşıdan mesajlar (alta inmez), sonra benim mesajım.
    d.yeniGeldi([_m(61), _m(60)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 2000);
    d.yeniGeldi([_m(62, gonderen: _ben)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m62')).dy, 600 - _alt);
    _siraDogru(tester);
    _durumlarMesajda(tester);
  });

  testWidgets('(d) ekrandan uzun yeni mesaj yığını varken de dip KESİN', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(2500);
    await tester.pumpAndSettle();
    d.yeniGeldi(_aralik(60, 99)); // ~40 mesaj, görüntü alanından uzun
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 2500);
    d.yeniGeldi([_m(100, gonderen: _ben)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(d.pos.minScrollExtent, -_alt);
    expect(tester.getBottomLeft(find.text('m100')).dy, 600 - _alt);
    _siraDogru(tester);
    _durumlarMesajda(tester);
  });

  testWidgets('(d) eski sayfadaki kendi mesajların alta indirmez', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(50, 99));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    d.eskiGeldi([for (var n = 49; n >= 0; n--) _m(n, gonderen: _ben)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 1500);
  });

  testWidgets('(e) üste yaklaşınca eski yükle bir kez çağrılır', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 49));
    await tester.pumpWidget(d.kur());
    expect(d.eskiCagri, 0);
    // Parmakla yukarı doğru defalarca kaydır (ters liste: aşağı sürükle).
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
    }
    expect(d.pos.pixels, d.pos.maxScrollExtent);
    expect(d.eskiCagri, 1);

    // Sayfa gelince yeniden istenebilir; yine bir kez.
    d.eskiGeldi(_aralik(-50, -1).toList());
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
    }
    expect(d.eskiCagri, 2);
  });

  testWidgets('(e) daha eski yoksa (eskiYukle null) çağrılmaz', (tester) async {
    final d = _Duzenek(_aralik(0, 49))..dahaVar = false;
    await tester.pumpWidget(d.kur());
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
    }
    expect(d.eskiCagri, 0);
  });

  testWidgets('State mesajla taşınır (yeni sliver → merkez birleşmesi dahil)', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    d.yeniGeldi([_m(60)]);
    await tester.pumpAndSettle();
    // m60'a in ama tam dibe değil (birleşme olmasın), dokun.
    d.ctrl.jumpTo(d.pos.minScrollExtent + 30);
    await tester.pumpAndSettle();
    await tester.tap(find.text('m60'));
    await tester.pump();
    expect(find.text('m60*'), findsOneWidget);
    // Alta yakınken yeni mesaj → birleşme + alta inme; m60'ın State'i korunur.
    d.yeniGeldi([_m(61)]);
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(find.text('m60*'), findsOneWidget);
    expect(find.text('m61*'), findsNothing);
    _durumlarMesajda(tester);

    // Merkezde: index'ler kaysa da (yeni mesajlar) işaret m60'ta kalır.
    for (var n = 62; n < 66; n++) {
      d.yeniGeldi([_m(n)]);
      await tester.pumpAndSettle();
      _durumlarMesajda(tester);
    }
    d.ctrl.jumpTo(250);
    await tester.pumpAndSettle();
    expect(find.text('m60*'), findsOneWidget);
  });

  testWidgets('en dipte kaydırma bitince bekleyen yeni mesajlar merkeze katılır'
      ' (görünüm değişmez)', (tester) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    d.yeniGeldi(_aralik(60, 64));
    await tester.pumpAndSettle();
    expect(d.pos.minScrollExtent, lessThan(-_alt));
    // Parmakla dibe kadar kaydır.
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(d.pos.pixels, -_alt);
    expect(d.pos.minScrollExtent, -_alt); // yeni sliver boşaldı
    expect(tester.getBottomLeft(find.text('m64')).dy, 600 - _alt);
    _siraDogru(tester);
    _durumlarMesajda(tester);
  });

  testWidgets('çapa mesajı silinince liste bozulmaz', (tester) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    d.yeniGeldi([_m(60)]);
    await tester.pumpAndSettle();
    // Çapa = m59 (merkezdeki en yeni). Silinir. (Silinen mesajın altındaki
    // boşluk kapanır — silmede beklenen; burada sıra/State bütünlüğü sınanır.)
    d.mesajlar.value = d.mesajlar.value.where((m) => m.id != 'm59').toList();
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 1500);
    _siraDogru(tester);
    _durumlarMesajda(tester);
    d.ctrl.jumpTo(d.pos.minScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('m59'), findsNothing);
    expect(tester.getBottomLeft(find.text('m60')).dy, 600 - _alt);
    _siraDogru(tester);
  });

  testWidgets('(c) en alttayken sıra değişimi çapayı aşınca mesaj ekranda kalır', (
    tester,
  ) async {
    // Firestore yarışı: kendi mesajım A'nın serverTimestamp'i yerelde
    // bekliyor; karşının X'i sunucuda A'dan SONRA işlendi ama A'nın onayından
    // önce geldi → sıra [A, X]; onay gelince [X, A].
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    final a = _m(60, gonderen: _ben);
    final x = _m(61);
    final gecmis = d.mesajlar.value;
    d.mesajlar.value = [a, ...gecmis]; // kendi mesajım → çapa A olur
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    d.mesajlar.value = [a, x, ...gecmis];
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('m60')).dy, 600 - _alt);
    // Onay: A gerçek zamanını alır, X'in altına geçer.
    d.mesajlar.value = [x, a, ...gecmis];
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m61')).dy, 600 - _alt);
    expect(
      tester.getBottomLeft(find.text('m60')).dy,
      tester.getTopLeft(find.text('m61')).dy,
    );
    expect(
      tester.getBottomLeft(find.text('m59')).dy,
      tester.getTopLeft(find.text('m60')).dy,
    );
    _siraDogru(tester);
    _durumlarMesajda(tester);
  });

  testWidgets('(a) yukarıda okurken sıra değişimi çapayı aşınca içerik kaymaz', (
    tester,
  ) async {
    final d = _Duzenek(_aralik(0, 59)); // çapa = m59
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    final gorunen = _gorunenler(tester);
    expect(gorunen, isNotEmpty);
    final once = _konumlar(tester, gorunen);
    // m58 (merkezde) m59'un önüne geçer: çapa yanlış yönetilseydi m58 yeni
    // sliver'a düşer, geçmiş m58'in boyu kadar kayardı.
    final l = d.mesajlar.value;
    d.mesajlar.value = [l[1], l[0], ...l.skip(2)];
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 1500);
    expect(_konumlar(tester, gorunen), once);
    _durumlarMesajda(tester);
    d.ctrl.jumpTo(d.pos.minScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('m58')).dy, 600 - _alt);
    expect(
      tester.getBottomLeft(find.text('m59')).dy,
      tester.getTopLeft(find.text('m58')).dy,
    );
  });

  testWidgets('(c) alta yakınken bekleyen yeni mesaj varsa güncellemede dibe '
      'inilir', (tester) async {
    final d = _Duzenek(_aralik(0, 59));
    await tester.pumpWidget(d.kur());
    d.ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    d.yeniGeldi(_aralik(60, 62)); // uzaktayken → yeni sliver'da bekler
    await tester.pumpAndSettle();
    expect(d.pos.pixels, 1500);
    // Dibe çok yakın (eşik içinde) ama tam dipte değil → birleşme olmadı.
    d.ctrl.jumpTo(d.pos.minScrollExtent + 40);
    await tester.pumpAndSettle();
    expect(d.pos.minScrollExtent, lessThan(-_alt));
    // Yeni mesaj YOK; yalnız liste güncellendi (ör. okundu bilgisi).
    d.mesajlar.value = [...d.mesajlar.value];
    await tester.pumpAndSettle();
    expect(d.pos.pixels, -_alt);
    expect(tester.getBottomLeft(find.text('m62')).dy, 600 - _alt);
    _siraDogru(tester);
  });

  testWidgets('KONTROL: düz ters ListView aynı ölçümde kayar (test duyarlı)', (
    tester,
  ) async {
    // Ölçüm yönteminin kaymayı gerçekten yakaladığını gösterir: eski
    // yaklaşım (tek ters liste) bu testte kayıyor.
    final vn = ValueNotifier<List<Mesaj>>(_aralik(0, 59));
    final ctrl = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<Mesaj>>(
            valueListenable: vn,
            builder: (_, liste, _) => ListView.builder(
              controller: ctrl,
              reverse: true,
              itemCount: liste.length,
              itemBuilder: (_, i) => _DurumluOge(liste[i]),
            ),
          ),
        ),
      ),
    );
    ctrl.jumpTo(1500);
    await tester.pumpAndSettle();
    final gorunen = _gorunenler(tester);
    final once = _konumlar(tester, gorunen);
    vn.value = [_m(60), ...vn.value];
    await tester.pumpAndSettle();
    expect(_konumlar(tester, gorunen), isNot(once));
  });
}
