import 'dart:async';
import 'dart:convert';
import 'hata_servisi.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tema.dart';
import 'aktarici_servisi.dart';
import 'aktif_arama_kaydi.dart';
import 'arama_durumu.dart';
import 'app_check_servisi.dart';
import 'ayar_servisi.dart';
import 'ses_secenekleri.dart';
import '../yardimcilar/bildirim_yuku.dart';

/// Bildirim KANAL KİMLİĞİ seçimi — SAF mantık (Firebase/eklenti yok →
/// `test/bildirim_kanal_test.dart` ile birim testi yapılır).
///
/// Kimlikler: `km_v3_<secim>`, titreşimsiz varyant `km_v3_<secim>_tsz`,
/// bildirimler kapalıyken `km_v3_kapali`, özel ses `km_v3_ozel_<8 hex>`
/// (+ `_tsz`). Bu kimlikler ALICININ Firestore'da yayınladığı değerdir; push o
/// kanala gider → Android 8+'da ses ve titreşim KANALDAN gelir (uygulama
/// kapalıyken bile). ⚠️ Aktarıcı (sunucu/aktarici) yayınlanan değeri
/// `^km_v3_[a-z0-9_]{1,40}$` desenine göre doğrular — yeni kimlikler bu
/// desene UYMALI, yoksa alıcı varsayılan kanala düşer.
abstract final class BildirimKanali {
  // ⚠️ Kanalın sesi/titreşimi sonradan DEĞİŞTİRİLEMEZ. Ses çalmıyorsa kilitli
  // eski kanal sebebidir → sürümü artır (yeni id'ler TAZE oluşur, ses gelir).
  static const String surum = 'v3';
  static const String onek = 'km_${surum}_';

  // ⚠️ VARSAYILAN kanal da SÜRÜMLÜ olmalı. Eskiden sabit 'kardes_mesaj_kanal'
  // idi; v1.x'te oluşturulduğu için Android sesini KALICI KİLİTLEMİŞTİ ve
  // "Varsayılan" seçiliyken hiç ses gelmiyordu (diğer sesler km_v2_* sürümlü
  // olduğu için çalışıyordu). Sürümlü id ile kanal TAZE oluşur, ses gelir.
  // (AndroidManifest default_notification_channel_id ile AYNI olmalı.)
  static const String varsayilan = '${onek}varsayilan';

  /// "Bildirimler" anahtarı KAPALIYKEN yayınlanan kanal. Android'de önem
  /// derecesi NONE olan kanal ENGELLİ kanaldır → bu kanala gelen bildirim
  /// sistem tarafından hiç gösterilmez.
  /// ⚠️ NEDEN: Mesaj push'u `notification` yükü taşıdığı için uygulama
  /// arka plandayken/kapalıyken bildirimi Flutter değil SİSTEM çizer;
  /// anahtar yalnız ön plandaki gösterime bakıyordu, yani
  /// "Bildirimler: kapalı" çoğu zaman HİÇBİR ŞEY yapmıyordu.
  static const String kapali = '${onek}kapali';

  /// Titreşimsiz varyant eki.
  /// ⚠️ NEDEN: Android 8+'da titreşim de ses gibi KANALA kilitlidir;
  /// `enableVibration` yalnız kanal OLUŞTURULURKEN okunur. Eskiden "Titreşim"
  /// anahtarı yalnız ön plandaki bildirim detayına yazılıyordu → arka planda/
  /// kapalıyken (sistemin çizdiği bildirimde) HİÇBİR etkisi yoktu. Artık her
  /// ses için ikinci, titreşimsiz bir kanal var; anahtar hangisinin
  /// yayınlanacağını seçer.
  static const String tszEki = '_tsz';

  /// Ayarlar'daki ses seçimleri (kanalı kurulanlar): hazır sesler
  /// ([sesSecenekleri], tek kaynak) + telefondan özel ses.
  static final List<String> secimler = List.unmodifiable([
    for (final s in sesSecenekleri) s.anahtar,
    ozelSesAnahtari,
  ]);

  /// SESSİZE ALINMIŞ sohbetin mesajları bu kanala düşer: ses YOK, titreşim
  /// YOK (bildirim yine görünür, sohbet okunmamış olarak işaretlenir).
  static const String sessizSohbet = '${onek}sessiz$tszEki';

  /// Özel ses kanallarının ortak öneki (`km_v3_ozel_<8 hex>[_tsz]`).
  /// Eski sabit kimlikler `km_v3_ozel` / `km_v3_ozel_tsz` de bu önekle
  /// başlar → açılışta "eski özel kanal" olarak temizlenir.
  static const String ozelOnek = '${onek}ozel';

  /// Özel ses kanal kimliği — URI'ye göre SÜRÜMLÜ: `km_v3_ozel_<fnv1a32(uri)>`.
  /// ⚠️ NEDEN (d4): eskiden kimlik sabitti (`km_v3_ozel`) ve ses değişince
  /// kanal silinip AYNI kimlikle yeniden kuruluyordu. Android silinen kanalı
  /// aynı kimlikle yeniden oluşturunca onu ESKİ AYARLARIYLA diriltir
  /// (NotificationManager.deleteNotificationChannel belgesi) → yeni ses HİÇ
  /// uygulanmıyordu; üstelik her açılıştaki silme o kanaldaki tepside duran
  /// bildirimleri de siliyordu. Farklı URI = farklı kimlik = TAZE kanal.
  static String ozelKanal(String uri) => '${ozelOnek}_${fnv1a32Hex(uri)}';

  /// FNV-1a 32 bit özeti (UTF-8 baytları üzerinde), 8 küçük hex hane.
  /// SAF ve KARARLI: `String.hashCode` gibi sürüm/çalıştırma başına
  /// değişebilen bir değere dayanmaz (kanal kimliği diske/Firestore'a giriyor;
  /// sonraki açılışta AYNI URI AYNI kimliği vermeli).
  static String fnv1a32Hex(String metin) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(metin)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Ses seçiminin titreşimli kanal kimliği. Bilinmeyen seçim (eski/bozuk
  /// kayıt) varsayılana düşer — var olmayan kanala push GİTMESİN. 'ozel'
  /// kanalı yalnız URI varken kurulur → URI yoksa varsayılan.
  static String sesKanali(String secim, {String? ozelUri}) {
    if (secim == ozelSesAnahtari) {
      return (ozelUri == null || ozelUri.isEmpty)
          ? varsayilan
          : ozelKanal(ozelUri);
    }
    return secimler.contains(secim) ? '$onek$secim' : varsayilan;
  }

  /// Alıcının yayınlayacağı aktif kanal: kapalı > titreşimsiz varyant > normal.
  static String aktif({
    required String secim,
    required bool bildirimAcik,
    required bool titresim,
    String? ozelUri,
  }) {
    if (!bildirimAcik) return kapali;
    final id = sesKanali(secim, ozelUri: ozelUri);
    return titresim ? id : '$id$tszEki';
  }

  /// Açılışta SİLİNECEK eski özel ses kanalları: [mevcut] kanal
  /// kimliklerinden `km_v3_ozel*` olup şu anki URI'nin çiftine
  /// ([ozelUri] → `km_v3_ozel_<hash>` ve `_tsz`) ait OLMAYANLAR.
  /// URI yoksa hepsi eskidir. Doğru kimlik ASLA silinmez (d4: silinip
  /// yeniden kurulan kanal eski ayarlarla dirilir, tepsideki bildirimler gider).
  static List<String> eskiOzelKanallar(
    Iterable<String> mevcut, {
    required String? ozelUri,
  }) {
    final tut = <String>{
      if (ozelUri != null && ozelUri.isNotEmpty) ...[
        ozelKanal(ozelUri),
        '${ozelKanal(ozelUri)}$tszEki',
      ],
    };
    return [
      for (final id in mevcut)
        if (id.startsWith(ozelOnek) && !tut.contains(id)) id,
    ];
  }

  /// Karşı tarafın Firestore'da YAYINLADIĞI kanal id'sini doğrular.
  ///
  /// ⚠️ NEDEN GEREKLİ: Alıcı uygulamayı güncelledikten sonra AÇMADIYSA,
  /// `bildirimKanali` alanında ESKİ SÜRÜM kanal id'si (`km_v2_*`,
  /// `kardes_mesaj_kanal`) kalır. O kanallar açılışta SİLİNDİĞİ için push
  /// var olmayan bir kanala gider → bildirim sessiz kalabilir/görünmeyebilir.
  /// Geçersizse güvenli varsayılana düşeriz (o kanal her zaman kurulur).
  /// Yalnız GÜNCEL sürüm öneki kabul edilir (bilinçli olarak tam liste değil:
  /// alıcı daha YENİ bir sürümle yeni bir ses eklerse eski gönderen onu
  /// varsayılana çevirip bozmasın). `_tsz` ve `kapali` de bu öneki taşır.
  static String gecerli(String? kanal) {
    if (kanal == null || kanal.isEmpty) return varsayilan;
    return kanal.startsWith(onek) ? kanal : varsayilan;
  }

  /// GÖNDERENİN push'a yazacağı kanal (alıcının `users` dokümanından) —
  /// YALNIZ AKTARICISIZ (eski) yolda kullanılır. Aktarıcı açıkken kanalı
  /// aktarıcı seçer (sunucu/aktarici `alicininKanali`, aynı kurallar) ve
  /// istemcinin değerini ezer.
  /// Sohbet alıcının `sessizSohbetler` listesindeyse sessiz kanala düşer;
  /// ama alıcı bildirimleri TAMAMEN kapattıysa (`kapali`) o öncelikli kalır —
  /// sessize almak bildirimi "açmamalı".
  /// ⚠️ Liste artık alıcının GİZLİ belgesinde (users/{uid}/ozel/bildirim) →
  /// gönderen OKUYAMAZ; aktarıcısız yolda yalnız henüz taşınmamış eski
  /// public liste görülebilir. Yani aktarıcısız derlemede sessize alma
  /// UYGULANAMAZ (sohbet menüsü o derlemede gizlenir).
  static String alicininKanali({
    required String? yayinlanan,
    Object? sessizSohbetler,
    String? chatId,
  }) {
    final kanal = gecerli(yayinlanan);
    if (kanal == kapali) return kanal;
    if (chatId == null || chatId.isEmpty) return kanal;
    final liste = sessizSohbetler is List ? sessizSohbetler : const [];
    return liste.contains(chatId) ? sessizSohbet : kanal;
  }
}

/// Arka plan / uygulama kapalı mesaj handler'ı.
/// Top-level (sınıf dışı) olmak ZORUNDA — Android arka planda izole çalıştırır.
/// Normal mesaj `notification` payload'ı sistem tepsisinde otomatik gösterilir.
///   data.tur == 'arama'       → tam ekran gelen arama (CallKit)
///   data.tur == 'arama_iptal' → arayan kapattı, çalmayı DURDUR
@pragma('vm:entry-point')
Future<void> arkaplanMesajHandler(RemoteMessage message) async {
  // Arka plan izole edilmiş bir isolate'te çalışır — Firebase burada da
  // başlatılmalı, yoksa eklenti çağrıları çökebilir ve CallKit hiç açılmaz.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // Arka plan izolatı AYRI bir Firebase örneğidir → App Check burada da
  // etkinleştirilmeli, yoksa zorlama açıldığında bu isolate'in Firestore
  // yazmaları (meşgul sinyali, teşhis raporu) reddedilir.
  await AppCheckServisi.baslat();
  await aramaMesajiIsle(message.data);
}

/// Şu an aktif bir aramada mıyım? AramaServisi katılınca/bitince günceller.
/// (Aynı isolate'te) meşgulken gelen yeni çağrının CallKit'i açmasını engeller.
/// Dairesel import olmasın diye burada top-level tutulur.
bool aktifAramaVar = false;

/// Bu isolate'teki aktif görüşmenin chatId'si (AramaServisi katılınca yazar,
/// bitirince null yapar). Ön plan meşgul kararı [gelenAramaMesgulMu] ile
/// arka planla AYNI kurala bağlansın diye tutulur.
String? aktifAramaChatId;

/// TEK meşgul kuralı (ön plan ve arka plan aynı): başka bir sohbetle süren
/// görüşme varsa meşgul. AYNI sohbetten gelen arama meşgul SAYILMAZ: karşı
/// taraf görüşmeyi yeniden kuruyordur (onun uygulaması çökmüş/kopmuş).
bool gelenAramaMesgulMu({
  required String? aktifChat,
  required String? gelenChat,
}) =>
    aktifChat != null && aktifChat != gelenChat;

/// Çağrı ile ilgili FCM verisini işler. Hem arka plan handler'ı hem de
/// uygulama açıkken (onMessage) AYNI yolu kullanır → tek tutarlı akış.
/// İşlendiyse true döner.
Future<bool> aramaMesajiIsle(Map<String, dynamic> data) async {
  HataServisi.instance.iz('PUSH geldi tur=${data['tur']}');
  switch (data['tur']) {
    case 'arama':
      // ARKA PLAN TEŞHİSİ: bu isolate'in izleri ana uygulamada görünmediği
      // için adımlar toplanıp doğrudan Firestore'a yazılır.
      final adimlar = <String>[
        'push alindi chatId=${data['chatId']} tip=${data['tip']} '
            'arayan=${data['arayan']} kanal=${data['kanal']}',
        'aktifAramaVar=$aktifAramaVar',
      ];
      // MEŞGUL (İSOLATE'LER ARASI): `aktifAramaVar` bellekte → arka plan
      // isolate'inde HEP false. Sesli görüşmede ekran kilitlenince (çok
      // yaygın) ikinci çağrı CallKit'i görüşmenin ÜSTÜNE açıyordu. Görüşme
      // kaydı diskte (SharedPreferences) → bu isolate da görür.
      // ⚠️ Aşağıdaki "gösterimden önce async iş yapma" kuralının BİLİNÇLİ
      // istisnası: bu okuma ağ değil, YEREL bir prefs okumasıdır (ms
      // mertebesi; platform tarafındaki SharedPreferences zaten bellekte).
      // Ayrıca kural zilin GECİKMEMESİ içindir; meşgulsek zil hiç çalmayacak.
      // Zaten gelenAramayiGoster de zil tercihini aynı yoldan diskten okuyor.
      final gelenChat = (data['chatId'] ?? data['kanal'])?.toString();
      final aktifChat = await AktifAramaKaydi.oku();
      adimlar.add('aktifArama(disk)=$aktifChat');
      // TEK meşgul kuralı ([gelenAramaMesgulMu], ön planla AYNI): AYNI
      // sohbetten tekrar arama (ör. kopan görüşmeyi yeniden arama, ya da
      // çökme sonrası kalmış kayıt) meşgul SAYILMAZ → gösterilir.
      if (gelenAramaMesgulMu(aktifChat: aktifChat, gelenChat: gelenChat)) {
        adimlar.add('MESGUL: baska gorusme suruyor → CallKit GOSTERILMEDI');
        HataServisi.instance.iz('MESGUL (disk) aktif=$aktifChat gelen=$gelenChat');
        await _mesgulBildir(data['chatId']?.toString());
        await HataServisi.instance
            .arkaplanRapor('GELEN ARAMA (mesgul)', adimlar);
        return true;
      }
      // ⚠️ SIRALAMA KRİTİK: Gelen aramayı GÖSTERMEDEN ÖNCE hiçbir async iş
      // yapılmaz. FCM en iyi uygulaması: yüksek öncelikli çağrı mesajı
      // handler'a düşer düşmez bildirim/çağrı HEMEN gösterilmeli; öncesinde
      // ağ/kanal çağrısı yapılırsa zil gecikir ve sistem işlemi kesebilir.
      // Bu yüzden TÜM teşhis okumaları gösterimden SONRAYA alındı.
      try {
        await gelenAramayiGoster(data);
        adimlar.add('CallKit showCallkitIncoming TAMAM');
        HataServisi.instance.iz('CALLKIT gelen arama gosterildi');
      } catch (e, st) {
        adimlar.add('CallKit showCallkitIncoming HATA: $e');
        final satirlar = st.toString().split('\n').take(4).join(' | ');
        adimlar.add('stack: $satirlar');
      }
      // CallKit gerçekten kaydetti mi? (0 ise gelen arama ekranı HİÇ açılmamış)
      try {
        final aktif = await FlutterCallkitIncoming.activeCalls();
        adimlar.add('activeCalls sonrasi=${aktif.length}');
        if (aktif.isNotEmpty) adimlar.add('activeCall id=${aktif.first.id}');
      } catch (e) {
        adimlar.add('activeCalls HATA: $e');
      }
      // Teşhis okumaları ARTIK BURADA (zil çaldıktan sonra) — gecikme yaratmaz.
      try {
        adimlar.add('secili zil=${await AyarServisi.aramaZiliDiskten()}');
      } catch (_) {}
      try {
        final z = await BildirimServisi.instance.zilDurumu();
        adimlar.add('telefon zil modu=${z.mod} zil seviyesi=${z.seviye}'
            '${z.mod != 'normal' || z.seviye == 0 ? "  <-- ZIL DUYULMAZ" : ""}');
      } catch (_) {
        // Arka plan izolatında Activity yok → MethodChannel çalışmaz.
        adimlar.add('zil modu okunamadi (arka plan, Activity yok)');
      }
      await HataServisi.instance.arkaplanRapor('GELEN ARAMA (arka plan)', adimlar);
      // ...sonra TEŞHİS (fire-and-forget): handler'ın GERÇEKTEN çalıştığını
      // Firestore'a işaretle. "Kapalıyken hiç gelmiyor"un sebebi böyle ayrışır:
      //  - Bu zaman damgası güncellendiyse → FCM ULAŞTI (sorun CallKit/kod).
      //  - Güncellenmediyse → FCM cihaza HİÇ ulaşmadı (autostart/pil = cihaz ayarı).
      unawaited(_cagriPushTeshisYaz(data['kanal']?.toString()));
      return true;
    case 'arama_iptal':
      // Arayan kapattı/vazgeçti → zil sussun, ekran kapansın.
      // ⚠️ YALNIZ O SOHBETİN çağrısı (CallKit id = chatId). Eskiden
      // endAllCalls() idi: A ile konuşurken C arayıp "meşgul" alınca C'nin
      // iptal push'u A ile süren görüşmenin CallKit oturumunu da bitiriyordu.
      // ⚠️ chatId'siz iptal YOK SAYILIR (d11): eskiden endAllCalls()'a
      // düşüyordu → herhangi bir arkadaş (engellenmiş biri bile) çıplak bir
      // 'arama_iptal' ile alıcının BAŞKASIYLA çalan/süren aramasını
      // kesebiliyordu. Gönderen taraf (AramaServisi.bitir) chatId'yi v1.8'den
      // beri hep gönderiyor; aktarıcı da chatId'siz iptali 400 ile reddediyor.
      try {
        final chatId = data['chatId']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          await FlutterCallkitIncoming.endCall(chatId);
          HataServisi.instance.iz('CALLKIT iptal: zil susturuldu');
        } else {
          HataServisi.instance.iz('CALLKIT iptal: chatId yok → yok sayildi');
        }
      } catch (_) {}
      return true;
    default:
      return false;
  }
}

/// Çağrı push'unun alındığını (handler çalıştığını) Firestore'a yazar.
/// Arka plan izolatında da çalışır (Firebase init edilmiş + oturum diskten geri
/// yüklenmiş olur).
Future<void> _cagriPushTeshisYaz(String? kanal) async {
  try {
    // Arka plan izolatında oturum diskten geç yüklenebilir → kısa süre bekle.
    var uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      try {
        final u = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 3));
        uid = u?.uid;
      } catch (_) {}
    }
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('kullanicilar')
        .doc(uid)
        .set({
      'sonCagriPush': FieldValue.serverTimestamp(),
      'sonCagriPushKanal': kanal,
    }, SetOptions(merge: true));
  } catch (_) {}
}

/// MEŞGULken gelen aramayı arayana bildirir: `aramalar/{chatId}.durum='mesgul'`.
/// Arayanın [AramaEkrani] dinleyicisi bunu görüp "Meşgul" ile kapanır.
/// (AramaServisi'ni import ETMİYORUZ — o zaten bildirim_servisi'ni import
/// ediyor; dairesel bağımlılık olmasın diye Firestore'a doğrudan yazılır.)
Future<void> _mesgulBildir(String? chatId) async {
  if (chatId == null || chatId.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('aramalar')
        .doc(chatId)
        .set(AramaDurumu.mesgul.alan, SetOptions(merge: true));
    HataServisi.instance.iz('MESGUL bildirildi chat=$chatId');
  } catch (e) {
    HataServisi.instance.iz('MESGUL bildirilemedi: $e');
  }
}

/// GELEN ARAMA — uygulamanın TEK gelen arama ekranı (her durumda bu çalışır:
/// açık / arka plan / tamamen kapalı). Zil, tam ekran ve kilit ekranı
/// desteğini işletim sisteminden alır.
/// Renkler `tema.dart`'tan gelir (native katman hex string ister).
Future<void> gelenAramayiGoster(Map<String, dynamic> data) async {
  // FAZ 4: CallKit id = chatId → kabul olayı hangi sohbet olduğunu bilir.
  final chatId = (data['chatId'] ?? data['kanal'] ?? 'arama').toString();
  final arayan = (data['arayan'] ?? 'Kardeş').toString();
  final video = data['tip'] == 'video';
  // ARANANIN kendi zil tercihi. ⚠️ Burası ARKA PLAN izolatı olabilir →
  // AyarServisi.baslat() çalışmamıştır; ayar DİSKTEN taze okunur.
  final zilYolu = await AyarServisi.aramaZiliDiskten();
  // Seçili TEMA da aynı sebeple diskten (arka plan izolatında Renkler
  // varsayılan palettedir; ön planda da diskteki değer günceldir).
  final palet = RoyPalet.bul(await AyarServisi.temaDiskten());
  final params = CallKitParams(
    id: chatId,
    nameCaller: arayan,
    appName: 'ROY MESSANGER',
    handle: video ? 'Görüntülü arama' : 'Sesli arama',
    type: video ? 1 : 0,
    // Zil süresi: arayan tarafın 45 sn zaman aşımıyla uyumlu.
    duration: 45000,
    extra: <String, dynamic>{
      'chatId': chatId,
      'tip': data['tip'],
      'arayan': arayan,
    },
    // Eklentinin kendi "Missed call" bildirimi KAPALI: İngilizce ve
    // dokununca sohbeti açmıyor. Yerine ARAYAN, bağlanmayan aramayı
    // sohbete "📞 Cevapsız sesli arama" olarak yazar ve normal mesaj
    // bildirimi gelir (bkz. AramaEkrani._cevapsizKaydet) — arayan erken
    // vazgeçtiğinde de (eklenti o durumda zaten göstermiyordu).
    missedCallNotification: const NotificationParams(
      showNotification: false,
      isShowCallback: false,
    ),
    android: AndroidParams(
      // ⚠️ FALSE — KASITLI (kullanıcı ekran görüntüsü: bildirim YARIM görünüyor,
      // arayan adı ve Kabul/Reddet düğmeleri kırpılıyordu).
      // Eklenti kaynağı (CallkitNotificationManager.getIncomingNotification):
      //   isCustomNotification=true → Android 14 ALTINDA kendi RemoteViews
      //   düzenini kullanıyor (layout_custom_notification) → OEM kabuklarında
      //   KIRPILIYOR. Test cihazlarından biri Android 11 (RP1A...).
      //   isCustomNotification=false → Android 14+ native CallStyle,
      //   14 altında standart bildirim + Reddet/Kabul ACTION düğmeleri.
      // Her iki yol da sistemin kendi düzeni olduğu için kırpılmaz.
      // (Tema renkleri gider ama gelen aramada OKUNABİLİRLİK önceliklidir.)
      isCustomNotification: false,
      // ⚠️⚠️ isFullScreen: FALSE — KASITLI. Eskiden true idi ve ÜÇ SEMPTOMUN
      // DE KÖK NEDENİ buydu (eklenti kaynağından doğrulandı):
      //
      //   CallkitIncomingBroadcastReceiver:
      //     if (isFullScreen) { startActivity(...) }        // ses YOK
      //     else { showIncomingNotification(data)           // ZİL BURADA
      //            sendEventFlutter(CALL_INCOMING, data)
      //            addCall(context, incomingData) }
      //
      // true iken: (1) ZİL HİÇ ÇALMIYOR — `play()` yalnız
      // showIncomingNotification içinde; CallkitIncomingActivity zili
      // BAŞLATMIYOR (yalnız ses tuşuyla durduruyor). (2) addCall yok →
      // activeCalls hep 0 → soğuk başlangıç kurtarma ölü. (3) Flutter'a
      // CALL_INCOMING olayı gitmiyor. (4) startActivity arka plandaki bir
      // BroadcastReceiver'dan çağrılıyor; Android 10+ arka plan aktivite
      // başlatmayı ENGELLER → aranan kişi aramayı HİÇ GÖRMEYEBİLİR →
      // kabul edemez → ARAYAN "Bağlanıyor…"da kalır.
      //
      // false iken kayıp YOK: bildirim `setFullScreenIntent(..., true)` ile
      // kuruluyor (CallkitNotificationManager:207) → ekran kilitliyken tam
      // ekran arama ekranı işletim sisteminin ONAYLI yoluyla yine açılır,
      // üstelik zil çalar ve çağrı kaydedilir.
      // (Manifest'te USE_FULL_SCREEN_INTENT var; Android 14+ izni
      // `tamEkranIzniVarMi` ile zaten kontrol ediliyor.)
      isFullScreen: false,
      isShowFullLockedScreen: true,
      isShowCallID: false,
      isImportant: true,
      // KULLANICININ SEÇTİĞİ zil (Ayarlar > Arama Zil Sesi).
      // Eklenti bunu `res/raw/<ad>` olarak çözer; `system_ringtone_default`
      // ise telefonun kendi zilini çalar. STREAM_RING'de, döngüde.
      ringtonePath: zilYolu,
      // TEMA: varsayılan MAVİ (#0955fa) yerine kullanıcının seçtiği palet
      backgroundColor: TemaHex.zeminIcin(palet),
      actionColor: TemaHex.neonIcin(palet),
      textColor: TemaHex.metinIcin(palet),
      textAccept: 'Kabul Et',
      textDecline: 'Reddet',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

/// Aktarıcılı derlemede bu CİHAZIN FCM token'ı bir kez döndürüldü mü
/// (SharedPreferences; cihaz başına — token da cihaz başınadır).
@visibleForTesting
const tokenDondurulduAnahtari = 'fcmTokenDonduruldu_v1';

/// Cihazın FCM token'ını (aktarıcılı derlemede) BİR KEZ döndürür:
/// [tokenSil] (`FirebaseMessaging.deleteToken`) çağrılır, başarılıysa işaret
/// diske yazılır. Döndü / zaten dönmüş → true; başarısız → false (işaret
/// yazılmaz, sonraki çağrı yeniden dener). ASLA fırlatmaz.
///
/// ⚠️ NEDEN (d10, ikinci tur): token'ı gizli belgeye taşımak ve public
/// `users/{uid}.fcmToken` alanını silmek YETMEZ — o DEĞER bugüne kadar her
/// girişli kullanıcıya okunurdu (kural testi T6) ve getToken() aynı değeri
/// döndürmeye devam eder (FCM token'ı yalnız yeniden kurulum / veri silme /
/// deleteToken ile değişir). Önceden toplanmış X değerini saldırgan KENDİ
/// ikinci hesabının gizli belgesine yazıp kendi hesaplarından birine
/// "arkadaş" bildirimi atarsa aktarıcı X'e gönderir → kurbanın telefonu
/// "Annen arıyor" diye çalar ve kurban, hiçbir ilişkisi olmayan o hesabı
/// engelleyemez. deleteToken X'i FCM'de UNREGISTERED yapar; gizli belgeye
/// yalnız YENİ (hiç public olmamış) token yazılır.
Future<bool> tokenBirKezDondur(Future<void> Function() tokenSil) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(tokenDondurulduAnahtari) ?? false) return true;
    await tokenSil();
    // İşaret SİLMEDEN SONRA: arada uygulama ölürse bir kez daha döner
    // (zararsız); önce yazılsaydı dönmemiş token "dönmüş" sayılabilirdi.
    await p.setBool(tokenDondurulduAnahtari, true);
    return true;
  } catch (e) {
    HataServisi.instance.iz('TOKEN dondurulemedi: $e');
    return false;
  }
}

/// Token yeniden PUBLIC yazıldığında (aktarıcısız derleme) işaret düşer:
/// o değer de toplanabilir → aynı cihaz sonra aktarıcılı derlemeye geçerse
/// yeniden döndürülmeli. ASLA fırlatmaz.
@visibleForTesting
Future<void> tokenDondurmaIsaretiniSil() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(tokenDondurulduAnahtari);
  } catch (_) {}
}

/// Kartsız (Spark planı) bildirim servisi.
/// Mesaj atılınca gönderen cihaz, FCM HTTP v1 API'ye doğrudan istek atıp
/// karşı cihaza push gönderir. Cloud Functions / Blaze GEREKMEZ.
class BildirimServisi {
  BildirimServisi._();
  static final BildirimServisi instance = BildirimServisi._();

  // AndroidManifest default_notification_channel_id = BildirimKanali.varsayilan.
  // Android 8+'da bildirim sesi KANALA kilitlidir → her ses için ayrı kanal
  // (kimlik kuralları ve gerekçeleri: [BildirimKanali]).

  // Eski (kilitli/sessiz kalmış olabilecek) kanallar — açılışta silinir.
  static const List<String> _eskiKanallar = [
    'kardes_mesaj_kanal', // v1.x varsayılan (sessiz kilitlenmişti)
    'kardes_mesaj_kanal_sessiz',
    'kardes_mesaj_kanal_kedi',
    'kardes_mesaj_kanal_cingirak',
    'kardes_mesaj_kanal_ozel',
    // v2 kuşağı (varsayılan sorunu nedeniyle v3'e geçildi)
    'km_v2_sessiz', 'km_v2_kedi', 'km_v2_kedi2', 'km_v2_kedi3',
    'km_v2_kedi4', 'km_v2_cingirak', 'km_v2_ozel',
  ];

  String _kanalIdFor(String secim) => BildirimKanali.sesKanali(secim);

  static const String _kanalKapali = BildirimKanali.kapali;

  /// Seçili sese, bildirim ve TİTREŞİM anahtarlarına göre aktif kanal id'si.
  String get aktifKanalId {
    final ayar = AyarServisi.instance;
    // 'ozel' kanalı yalnız URI varken kurulur ([_ozelKanaliKur]) → URI yoksa
    // BildirimKanali.sesKanali varsayılana düşer (var olmayan kanal
    // yayınlanmaz). Özel kanal kimliği URI'ye göre sürümlü.
    return BildirimKanali.aktif(
      secim: ayar.bildirimSesi.value,
      bildirimAcik: ayar.bildirimAcik.value,
      titresim: ayar.titresimAcik.value,
      ozelUri: ayar.ozelSesUri.value,
    );
  }

  /// Seçili sesin AndroidNotificationSound karşılığı (Android <8 + detayda).
  AndroidNotificationSound? _sesFor(String secim) {
    if (secim == ozelSesAnahtari) {
      final u = AyarServisi.instance.ozelSesUri.value;
      return (u == null || u.isEmpty) ? null : UriAndroidNotificationSound(u);
    }
    return _rawSes(sesSecenegiBul(secim));
  }

  /// Hazır sesin res/raw karşılığı; raw kaynağı yoksa (varsayılan = sistem
  /// sesi, sessiz) ya da seçenek bilinmiyorsa null.
  static AndroidNotificationSound? _rawSes(SesSecenegi? s) {
    final raw = s?.rawKaynak;
    return raw == null ? null : RawResourceAndroidNotificationSound(raw);
  }

  // Native izin/ses kontrolleri (MainActivity.kt ile aynı kanal adı)
  static const MethodChannel _native = MethodChannel('kardes_mesaj/sesler');

  /// Android 14+ tam ekran bildirim izni var mı? (yoksa ekran kapalıyken
  /// gelen arama tam ekran açılmaz, sadece bildirime düşer)
  Future<bool> tamEkranIzniVarMi() async {
    try {
      return await _native.invokeMethod<bool>('tamEkranIzniVarMi') ?? true;
    } catch (_) {
      return true; // kontrol edilemiyorsa engelleme
    }
  }

  /// Telefonun zil durumu. Zil çalmama şikayetinin en yaygın sebebi cihazın
  /// SESSİZ/TİTREŞİM modu ya da zil sesinin 0 olmasıdır. Kullanıcıyı
  /// bilgilendirmek için okunur — uygulama cihaz ayarını DEĞİŞTİRMEZ.
  /// Dönen: (mod: 'normal'|'titresim'|'sessiz', seviye: int)
  Future<({String mod, int seviye})> zilDurumu() async {
    try {
      final r = await _native.invokeMapMethod<String, dynamic>('zilDurumu');
      return (
        mod: (r?['mod'] as String?) ?? 'normal',
        seviye: (r?['seviye'] as int?) ?? 1,
      );
    } catch (_) {
      return (mod: 'normal', seviye: 1); // okunamıyorsa uyarı gösterme
    }
  }

  /// Zil duyulmayacak mı? (sessiz/titreşim modu veya zil sesi 0)
  Future<bool> zilDuyulmazMi() async {
    final d = await zilDurumu();
    return d.mod != 'normal' || d.seviye == 0;
  }

  /// Tam ekran bildirim izni ayar ekranını açar.
  Future<void> tamEkranAyarlariniAc() async {
    try {
      await _native.invokeMethod<void>('tamEkranAyarlariniAc');
    } catch (_) {}
  }

  /// Pil optimizasyonu muafiyeti ister (Doze uygulamayı uyutup aramayı/
  /// bildirimi geciktirmesin). Zaten verilmişse tekrar sormaz.
  Future<void> pilOptimizasyonuIste() async {
    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  final FirebaseMessaging _mesajlasma = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _yerel =
      FlutterLocalNotificationsPlugin();
  final CollectionReference<Map<String, dynamic>> _kullanicilar =
      FirebaseFirestore.instance.collection('kullanicilar');
  // FAZ 4: profiller + token'lar buraya taşınıyor (hedefli bildirim için)
  final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  bool _kuruldu = false;
  bool _tokenDinleyiciKuruldu = false;
  // Aktarıcılı derlemede tek seferlik token döndürme (bkz. tokenKaydet).
  Future<bool>? _dondurmeBekleyen;

  /// Uygulama açılışında bir kez çağrılır (main.dart, Firebase init sonrası).
  /// İzin ister, yerel bildirim kanalını kurar, foreground dinleyicisini açar.
  Future<void> baslat() async {
    if (_kuruldu) return;
    _kuruldu = true;

    // 1) Bildirim izni (Android 13+ runtime izni)
    await _mesajlasma.requestPermission(alert: true, badge: true, sound: true);

    // 2) Yerel bildirim eklentisi + kanal (foreground'da göstermek için)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _yerel.initialize(
      settings: const InitializationSettings(android: androidInit),
      // Yerel bildirime (mesaj hatırlatması, ön planda gösterilen mesaj)
      // dokununca ilgili sohbet açılır.
      onDidReceiveNotificationResponse: _yerelBildirimeTiklandi,
    );

    await _kanallariKur();

    // 3) Uygulama AÇIKKEN gelen mesajı elle göster (foreground'da sistem
    //    otomatik göstermez)
    FirebaseMessaging.onMessage.listen(_gelenMesaj);
  }

  /// Yerel bildirime dokununca açılacak sohbet. main.dart bağlar
  /// (navigator orada; dairesel import olmasın diye geri çağırım).
  void Function(String chatId, String karsiUid)? sohbetAc;

  void _yerelBildirimeTiklandi(NotificationResponse yanit) {
    final hedef = sohbetYukuCoz(yanit.payload);
    if (hedef != null) sohbetAc?.call(hedef.chatId, hedef.karsiUid);
  }

  /// Uygulama KAPALIYKEN yerel bildirime dokunularak açıldıysa ilgili
  /// sohbeti açar. AnaKabuk ilk karede çağırır (navigator hazır).
  Future<void> acilisBildiriminiIsle() async {
    try {
      final d = await _yerel.getNotificationAppLaunchDetails();
      final yanit = d?.notificationResponse;
      if ((d?.didNotificationLaunchApp ?? false) && yanit != null) {
        _yerelBildirimeTiklandi(yanit);
      }
    } catch (e) {
      HataServisi.instance.iz('acilis bildirimi okunamadi: $e');
    }
  }

  /// Foreground mesaj yönlendiricisi.
  /// Çağrı mesajları arka planla AYNI yoldan geçer (CallKit) → uygulama açıkken
  /// de zil çalar, tek tutarlı akış olur.
  Future<void> _gelenMesaj(RemoteMessage message) async {
    // MEŞGUL: zaten bir aramadayken yeni gelen çağrıyı gösterme (üstüne binmesin).
    // ⚠️ Eskiden burada SESSİZCE `return` ediliyordu → arayan 45 sn boyunca
    // boşuna çalıyor, meşgul olduğumuzu asla öğrenmiyordu. Artık arayana
    // 'mesgul' durumu yazılıyor; onun arama ekranı "Meşgul" deyip kapanır.
    // ⚠️ Karar arka planla AYNI kuraldan ([gelenAramaMesgulMu], d3): eskiden
    // ön planda `aktifAramaVar` tek başına bakılıyordu → AYNI sohbetten
    // yeniden arama ön planda "meşgul", arka planda gösteriliyordu.
    // aktifChat: bellekteki görüşme sohbeti; görüşme var ama sohbeti
    // bilinmiyorsa '' (hiçbir gerçek chatId'ye eşit değil → GÜVENLİ taraf:
    // meşgul); görüşme yoksa null (meşgul değil). Ardından aramaMesajiIsle
    // aynı kuralı diskteki kayıtla da uygular (başka isolate'in görüşmesi).
    if (message.data['tur'] == 'arama') {
      final aktifChat = aktifAramaChatId ?? (aktifAramaVar ? '' : null);
      final gelenChat =
          (message.data['chatId'] ?? message.data['kanal'])?.toString();
      if (gelenAramaMesgulMu(aktifChat: aktifChat, gelenChat: gelenChat)) {
        HataServisi.instance
            .iz('MESGUL (bellek) aktif=$aktifChat gelen=$gelenChat');
        await _mesgulBildir(message.data['chatId']?.toString());
        return;
      }
    }
    if (await aramaMesajiIsle(message.data)) return; // çağrı/iptal ise bitti
    _foregroundGoster(message); // normal mesaj bildirimi
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _yerel.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Tüm ses kanallarını oluşturur. Önce eski/kilitli kanalları siler,
  /// sonra her sesi TAZE kanalda (doğru sesle) kurar.
  Future<void> _kanallariKur() async {
    final a = _android;
    if (a == null) return;

    // Eski sürüm kanallarını temizle (sesleri kilitli kalmış olabilir)
    for (final id in _eskiKanallar) {
      await a.deleteNotificationChannel(channelId: id);
    }

    // Kapalı (Ayarlar > Bildirimler kapalıyken; bkz. [BildirimKanali.kapali])
    await a.createNotificationChannel(const AndroidNotificationChannel(
      _kanalKapali, 'Kapalı',
      description: 'Bildirimler ayarlardan kapatıldığında kullanılır',
      importance: Importance.none,
    ));
    // Her ses İKİ kanalla kurulur: titreşimli + titreşimsiz (_tsz).
    // Liste TEK KAYNAKTAN ([sesSecenekleri]) — Ayarlar ekranıyla aynı.
    //  - varsayilan: raw yok + playSound → sistem varsayılan sesi çalar
    //  - sessiz: playSound false (sessiz_tsz aynı zamanda SESSİZE ALINMIŞ
    //    sohbetlerin kanalı, bkz. [BildirimKanali.sessizSohbet])
    //
    // ⚠️ YALNIZ GEREKENLER kurulur: varsayılan, sessiz (sessize alınmış
    // sohbetlerin kanalı) ve SEÇİLİ ses. Eskiden listedeki HER ses için
    // kurulurdu; 20'yi aşan seste Android'in bildirim ayarlarında 40+ kanal
    // birikirdi. Seçim değişince [sesGuncelle] yenisini kurar.
    for (final s in sesSecenekleri) {
      if (!_kanaliGerekli(s.anahtar)) continue;
      await _ciftKanalKur(a, s.anahtar, s.ad,
          aciklama: s.aciklama, sesCalsin: s.sesCalar, ses: _rawSes(s));
    }
    await _ozelKanaliKur();
  }

  bool _kanaliGerekli(String anahtar) =>
      anahtar == 'varsayilan' ||
      anahtar == 'sessiz' ||
      anahtar == AyarServisi.instance.bildirimSesi.value;

  /// Seçili HAZIR sesin kanal çiftini kurar (zaten varsa dokunmaz).
  Future<void> _seciliKanaliKur() async {
    final a = _android;
    final s = sesSecenegiBul(AyarServisi.instance.bildirimSesi.value);
    if (a == null || s == null) return;
    await _ciftKanalKur(a, s.anahtar, s.ad,
        aciklama: s.aciklama, sesCalsin: s.sesCalar, ses: _rawSes(s));
  }

  /// [secim] için titreşimli (`km_v3_<secim>`) ve titreşimsiz
  /// (`km_v3_<secim>_tsz`) kanalı birlikte kurar. Zaten varsa Android
  /// ses/titreşimi DEĞİŞTİRMEZ (yalnız ad/açıklama güncellenir) → güvenli.
  /// [id] verilirse (özel ses: URI'ye göre sürümlü kimlik) o kullanılır.
  Future<void> _ciftKanalKur(
    AndroidFlutterLocalNotificationsPlugin a,
    String secim,
    String ad, {
    String? id,
    String? aciklama,
    bool sesCalsin = true,
    AndroidNotificationSound? ses,
  }) async {
    id ??= _kanalIdFor(secim);
    for (final titresim in [true, false]) {
      await a.createNotificationChannel(AndroidNotificationChannel(
        titresim ? id : '$id${BildirimKanali.tszEki}',
        titresim ? ad : '$ad (titreşimsiz)',
        description: aciklama,
        importance: Importance.high,
        playSound: sesCalsin,
        sound: sesCalsin ? ses : null,
        enableVibration: titresim,
      ));
    }
  }

  /// Özel ses kanallarını (titreşimli + _tsz) seçili URI'nin SÜRÜMLÜ
  /// kimliğiyle ([BildirimKanali.ozelKanal]) kurar.
  /// ⚠️ Aynı kimlik ASLA silinip yeniden kurulmaz (d4): Android silinen
  /// kanalı aynı kimlikle yeniden oluşturunca ESKİ ayarlarıyla (eski ses)
  /// diriltir ve silme o kanaldaki tepside duran bildirimleri de siler.
  /// Yalnız URI değiştiğinde eski `km_v3_ozel*` kanalları (önceki URI'lerin
  /// ve sürümsüz eski `km_v3_ozel`/`_tsz`) silinir; yenisi TAZE kimlikle
  /// kurulur. Doğru kanal zaten varsa createNotificationChannel yalnız
  /// ad/açıklamayı günceller (ses aynı URI → değişmesi gerekmez).
  Future<void> _ozelKanaliKur() async {
    final a = _android;
    if (a == null) return;
    final uri = AyarServisi.instance.ozelSesUri.value;
    try {
      final mevcut = await a.getNotificationChannels() ?? const [];
      final eskiler = BildirimKanali.eskiOzelKanallar(
        mevcut.map((k) => k.id),
        ozelUri: uri,
      );
      for (final id in eskiler) {
        await a.deleteNotificationChannel(channelId: id);
      }
    } catch (e) {
      // Listeleme başarısızsa silme YAPILMAZ (yanlışlıkla doğru kanalı
      // silmektense eski bir kanalın kalması zararsız).
      HataServisi.instance.iz('ozel kanal listesi okunamadi: $e');
    }
    if (uri != null && uri.isNotEmpty) {
      await _ciftKanalKur(a, ozelSesAnahtari, 'Özel Ses',
          id: BildirimKanali.ozelKanal(uri),
          ses: UriAndroidNotificationSound(uri));
    }
  }

  /// Ses seçimi değişince çağrılır: özel kanalı (URI değiştiyse yeni
  /// kimlikle) kurar + tercihi Firestore'a yayınlar (push bu kanalı kullanır
  /// → kapalıyken bile doğru ses).
  Future<void> sesGuncelle() async {
    await _seciliKanaliKur();
    await _ozelKanaliKur();
    await kanalYayinla();
  }

  /// Aktif kanal id'sini Firestore'a yazar (hem eski `kullanicilar` hem
  /// FAZ 4 `users` — geçiş dönemi çift yazım).
  Future<void> kanalYayinla() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final veri = {'bildirimKanali': aktifKanalId};
    await _kullanicilar.doc(uid).set(veri, SetOptions(merge: true));
    try {
      await _users.doc(uid).set(veri, SetOptions(merge: true));
    } catch (_) {}
  }

  void _foregroundGoster(RemoteMessage message) {
    final bildirim = message.notification;
    if (bildirim == null) return;

    // Kullanıcı ayarlarını uygula
    final ayar = AyarServisi.instance;
    if (!ayar.bildirimAcik.value) return; // bildirim kapalıysa gösterme

    // SESSİZE ALINMIŞ sohbet: gönderen bunu alıcının listesine bakıp push'un
    // kanalına yazdı ([BildirimKanali.alicininKanali]). Ön planda bildirimi
    // biz çizdiğimiz için o kararı burada da uygula — yoksa uygulama açıkken
    // sessize alınmış sohbet yine çalardı.
    final sessizSohbet =
        bildirim.android?.channelId == BildirimKanali.sessizSohbet;

    // Ses hem kanaldan (Android 8+) hem detaydan (8 altı) gelir.
    final secim = sessizSohbet ? 'sessiz' : ayar.bildirimSesi.value;
    _yerel.show(
      id: bildirim.hashCode,
      title: bildirim.title,
      body: bildirim.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          sessizSohbet ? BildirimKanali.sessizSohbet : aktifKanalId,
          'ROY MESSANGER',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: secim != 'sessiz',
          sound: _sesFor(secim),
          enableVibration: !sessizSohbet && ayar.titresimAcik.value,
          // Kilit ekranında içerik GİZLENMESİN (yarım görünme sorunu)
          visibility: NotificationVisibility.public,
          // Uzun mesaj tek satıra kırpılmasın, açılabilir olsun
          styleInformation: BigTextStyleInformation(
            bildirim.body ?? '',
            contentTitle: bildirim.title,
          ),
        ),
      ),
    );
  }

  /// GİZLİ kullanıcı belgesi: `users/{uid}/ozel/bildirim`
  /// {fcmToken, sessizSohbetler: [chatId], guncelleme}. YALNIZ sahibi
  /// okur/yazar (firestore.rules); aktarıcı hizmet hesabıyla okur.
  /// ⚠️ NEDEN (d10): fcmToken herkese okunur `users/{uid}` belgesindeydi ve
  /// değeri serbestçe yazılabiliyordu → saldırgan kurbanın token'ını okuyup
  /// KENDİ ikinci hesabının belgesine yazıyor, o hesaba "izinli" bildirim
  /// atıp aktarıcının yetki denetimini atlatıyordu (push kurbana gidiyordu).
  static DocumentReference<Map<String, dynamic>> ozelBelge(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ozel')
          .doc('bildirim');

  /// Giriş yapan kullanıcının FCM token'ını Firestore'a yazar
  /// (bkz. [_tokenYaz]). Token yenilenince günceller.
  Future<void> tokenKaydet() async {
    final kullanici = FirebaseAuth.instance.currentUser;
    if (kullanici == null) return;

    // ⚠️ Aktarıcılı derlemede önce (bir kez) token DÖNDÜRÜLÜR (bkz.
    // [tokenBirKezDondur]). Döndürülemezse (çevrimdışı vb.) token HİÇ
    // yazılmaz — public alan da SİLİNMEZ: hâlâ geçerli eski değer kurbanın
    // public belgesinde durdukça aktarıcı, aynı değeri BAŞKA bir uid'in
    // gizli belgesinde görünce gönderimi reddedebiliyor (aktarıcı:
    // tokenBaskasindaMi). Silseydik bu kanıt giderdi ama değer geçerli
    // kalırdı. Sonraki tokenKaydet yeniden dener.
    // Eşzamanlı çağrılar (sohbet ekranı her açılışta çağırıyor) TEK
    // döndürmeyi paylaşır: iki deleteToken üst üste binerse birinin yazdığı
    // taze token ötekince öldürülürdü.
    var dondu = true;
    if (AktariciServisi.etkin) {
      final bekleyen = _dondurmeBekleyen ??= tokenBirKezDondur(
        _mesajlasma.deleteToken,
      );
      dondu = await bekleyen;
      if (!dondu && identical(_dondurmeBekleyen, bekleyen)) {
        _dondurmeBekleyen = null;
      }
    }
    if (dondu) {
      final token = await _mesajlasma.getToken();
      if (token != null) await _tokenYaz(kullanici.uid, token);
    }

    // Seçili bildirim kanalını da yayınla (push bu kanala gider)
    await kanalYayinla();

    // Token zamanla yenilenebilir — değişince güncelle.
    // tokenKaydet() sohbet ekranı her açıldığında çağrılıyor; dinleyici
    // birikmesin diye SADECE BİR KEZ kur.
    if (!_tokenDinleyiciKuruldu) {
      _tokenDinleyiciKuruldu = true;
      _mesajlasma.onTokenRefresh.listen((yeniToken) {
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) return;
        _tokenYaz(u.uid, yeniToken);
      });
    }
  }

  /// Token'ı yazar. ⚠️ ASLA fırlatmaz; her hedef AYRI denenir (biri
  /// reddedilirse — ör. yeni kurallar henüz yayınlanmamışken gizli belge —
  /// diğerleri yine yazılsın, aktarıcısız yol kırılmasın).
  ///  1) GİZLİ belge: HER ZAMAN (aktarıcı token'ı YALNIZ buradan okur).
  ///  2) Eski `kullanicilar/{uid}` (yalnız sahibi okur; geçiş dönemi).
  ///  3) HERKESE OKUNUR `users/{uid}.fcmToken`: YALNIZ aktarıcısız
  ///     derlemede yazılır — o derlemede gönderen token'ı doğrudan buradan
  ///     okuyup FCM'e kendisi gönderiyor (eski derlemelerle uyum). Aktarıcılı
  ///     derlemede alan SİLİNİR: public token kalmasın (herkes aktarıcılı
  ///     derlemeye geçince kurallarda tamamen yasaklanacak, bkz.
  ///     firestore.rules). ⚠️ Sonuç: aktarıcılı derlemedeki kullanıcıya
  ///     aktarıcısız eski derlemeler bildirim GÖNDEREMEZ (geçiş bedeli).
  ///     ⚠️ Alanı silmek tek başına yetmez: değer önceden toplanmış olabilir
  ///     → aktarıcılı derlemede buraya gelen token [tokenKaydet]'te bir kez
  ///     DÖNDÜRÜLMÜŞ (hiç public olmamış) token'dır ([tokenBirKezDondur]).
  Future<void> _tokenYaz(String uid, String token) async {
    final zaman = FieldValue.serverTimestamp();
    final hedefler =
        <(String, DocumentReference<Map<String, dynamic>>, Map<String, Object>)>[
      ('gizli', ozelBelge(uid), {'fcmToken': token, 'guncelleme': zaman}),
      ('kullanicilar', _kullanicilar.doc(uid),
          {'fcmToken': token, 'guncelleme': zaman}),
      (
        'users',
        _users.doc(uid),
        // E-posta EKLENMEZ (users/{uid} herkese okunur — gizlilik).
        AktariciServisi.etkin
            ? {'fcmToken': FieldValue.delete()}
            : {'fcmToken': token, 'guncelleme': zaman},
      ),
    ];
    for (final (ad, ref, veri) in hedefler) {
      try {
        await ref.set(veri, SetOptions(merge: true));
      } catch (e) {
        HataServisi.instance.iz('TOKEN yazilamadi ($ad): $e');
      }
    }
    // Değer public'e yazıldı → toplanabilir; aktarıcılı derlemeye geçilirse
    // yeniden döndürülsün.
    if (!AktariciServisi.etkin) await tokenDondurmaIsaretiniSil();
  }

  /// ÇIKIŞTA çağrılır: bu cihazın token'ını hesaptan SÖKER.
  ///
  /// ⚠️ Eskiden çıkışta token `users/{uid}`'de kalıyordu → çıkış yapılmış
  /// hesabın mesaj bildirimleri ve GELEN ARAMALARI bu cihaza gelmeye devam
  /// ediyordu. Aynı telefonda başka bir aile üyesi giriş yapınca iki hesabın
  /// bildirimleri birden geliyordu (gizlilik sorunu).
  /// Yalnızca kayıtlı token BU cihazınkiyse silinir — hesap başka bir
  /// telefonda daha sonra açıldıysa onun token'ına dokunulmaz.
  /// Gizli belge (aktarıcının okuduğu), public profil (aktarıcısız yol) ve
  /// eski `kullanicilar` belgesinin ÜÇÜ de denetlenir.
  Future<void> tokenSil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final benim = await _mesajlasma.getToken();
      final sil = {'fcmToken': FieldValue.delete()};
      for (final ref in [
        ozelBelge(uid),
        _users.doc(uid),
        _kullanicilar.doc(uid),
      ]) {
        try {
          final kayitli = (await ref.get()).data()?['fcmToken'];
          if (benim != null && kayitli == benim) {
            await ref.set(sil, SetOptions(merge: true));
          }
        } catch (_) {}
      }
      // Yeni hesap girişte TAZE token alır (tokenKaydet).
      await _mesajlasma.deleteToken();
    } catch (e) {
      HataServisi.instance.iz('token silinemedi: $e');
    }
  }

  // ÖLÜ KOD SİLİNDİ (FAZ 4 öncesi 2 kişilik akış):
  //   karsiTarafaBildirimGonder / karsiTarafaAramaGonder /
  //   karsiTarafaAramaIptal / _push
  // Bunlar "karşı taraf"ı `kullanicilar` koleksiyonundan KENDİSİ OLMAYAN İLK
  // kullanıcıyı seçerek buluyordu — çok kullanıcılı yapıda YANLIŞ KİŞİYE
  // arama/iptal göndermeye açıktı. Yerlerini uid-hedefli
  // [hedefeBildirimGonder] / [hedefeVeriGonder] aldı (0 kullanımdaydılar).

  /// FAZ 4: BELİRLİ bir kullanıcıya (uid) mesaj bildirimi gönderir.
  /// [ekstraData] verilirse data payload olarak eklenir (sohbet açma vb.).
  /// ⚠️ ASLA fırlatmaz: çağıranlar (mesaj/arkadaşlık servisi) bunu
  /// `await` ETMEDEN çağırıyor → buradan kaçan bir hata (ör. çevrimdışı
  /// Firestore okuması) yakalanmamış async hata olarak HataServisi'ne düşer.
  Future<void> hedefeBildirimGonder({
    required String hedefUid,
    required String baslik,
    required String govde,
    Map<String, String>? ekstraData,
  }) async {
    // [kanal] null → channel_id yazılmaz (aktarıcı kendisi seçer).
    Map<String, dynamic> mesaj(String? kanal) => <String, dynamic>{
          'notification': {'title': baslik, 'body': govde},
          'data': ?ekstraData,
          'android': {
            // ⚠️ HTTP v1 kanonik değeri BÜYÜK harf 'HIGH'. Küçük harf 'high'
            // düşük önceliğe düşebiliyor → mesaj Doze'da gecikir/hiç gelmez.
            // (Bu tuzak projede daha önce ÇAĞRI push'unda yaşanmıştı; mesaj
            // push'u küçük harfte kalmış.)
            'priority': 'HIGH',
            'notification': {
              'channel_id': ?kanal,
              'visibility': 'PUBLIC',
              'tag': 'km_$hedefUid',
            },
          },
        };
    try {
      if (AktariciServisi.etkin) {
        // Token'ı (alıcının GİZLİ belgesinden) ve KANALI aktarıcı kendisi
        // bulur: alıcının yayınladığı kanal + gizli sessiz listesi (d6/d8).
        // Kanal kararı gönderenin sürümüne bağlı kalmasın diye istemcinin
        // değeri zaten EZİLİR → alıcı belgesi burada hiç okunmaz.
        await AktariciServisi.instance
            .bildirimGonder(hedefUid: hedefUid, mesaj: mesaj(null));
        return;
      }
      // AKTARICISIZ (eski) yol: gönderen alıcının public belgesinden token
      // ve kanalı okur. Sessiz liste artık gizli belgede → okunamaz; yalnız
      // henüz taşınmamış eski public liste görülür. Yani bu yolda sessize
      // alma UYGULANAMAZ (bkz. [BildirimKanali.alicininKanali]).
      final d = (await _users.doc(hedefUid).get()).data();
      final kanal = BildirimKanali.alicininKanali(
        yayinlanan: d?['bildirimKanali'] as String?,
        sessizSohbetler: d?['sessizSohbetler'],
        chatId: ekstraData?['chatId'],
      );
      final token = d?['fcmToken'] as String?;
      if (token == null) return;
      await _gonderMesaj(token, mesaj(kanal));
    } catch (e) {
      HataServisi.instance.iz('BILDIRIM gonderilemedi hedef=$hedefUid: $e');
    }
  }

  /// FAZ 4: BELİRLİ bir kullanıcıya data-only push (arama/iptal gibi).
  /// ⚠️ ASLA fırlatmaz (arama başlatma bunu `await` etmeden çağırıyor).
  Future<void> hedefeVeriGonder({
    required String hedefUid,
    required Map<String, String> veri,
  }) async {
    final mesaj = <String, dynamic>{
      'data': veri,
      'android': {'priority': 'HIGH', 'ttl': '45s'},
    };
    try {
      if (AktariciServisi.etkin) {
        // Veri push'unda kanal yok (bildirimi CallKit çizer) → alıcı
        // dokümanını okumaya gerek yok. ÇAĞRI push'u olduğu için fazladan bir
        // Firestore gidiş-dönüşü zili geciktirirdi; bilinçli olarak atlandı.
        await AktariciServisi.instance
            .bildirimGonder(hedefUid: hedefUid, mesaj: mesaj);
        return;
      }
      final token = (await _users.doc(hedefUid).get()).data()?['fcmToken']
          as String?;
      if (token == null) return;
      await _gonderMesaj(token, mesaj);
    } catch (e) {
      HataServisi.instance.iz('VERI push gonderilemedi hedef=$hedefUid: $e');
    }
  }

  /// FCM için yetkili HTTP istemcisi + proje kimliği (uygulama ömrü boyunca
  /// TEK örnek). ⚠️ Eskiden HER mesajda asset okunup JSON çözülüyor, RSA ile
  /// JWT imzalanıyor ve Google'a ayrı bir OAuth token isteği atılıyordu →
  /// her bildirimden önce fazladan bir ağ gidiş-dönüşü (mobil veride
  /// yüzlerce ms). [AutoRefreshingAuthClient] token'ı süresi dolmadan kendisi
  /// yeniler; kurulum hatası ya da 401/403'te önbellek sıfırlanır ve sonraki
  /// gönderim yeniden kurar (bkz. [_fcmSifirla]).
  Future<_FcmBaglanti>? _fcmKurulum;

  Future<_FcmBaglanti> _fcmBaglanti() =>
      _fcmKurulum ??= () async {
        final saJson =
            await rootBundle.loadString('assets/service_account.json');
        final saMap = jsonDecode(saJson) as Map<String, dynamic>;
        final projectId = saMap['project_id'] as String?;
        if (projectId == null) {
          throw StateError('service_account.json içinde project_id yok');
        }
        final istemci = await clientViaServiceAccount(
          ServiceAccountCredentials.fromJson(saMap),
          ['https://www.googleapis.com/auth/firebase.messaging'],
        );
        return (istemci: istemci, projectId: projectId);
      }();

  /// Önbelleği YALNIZ [hataVeren] kurulum hâlâ günceliyse sıfırlar.
  /// ⚠️ NEDEN (d5): eskiden o an önbellekte ne varsa (araya kurulmuş TAZE
  /// bir istemci bile) sıfırlanıp `close()` ediliyordu. IOClient.close()
  /// alttaki HttpClient'ı force:true ile kapatır → AYNI istemcide uçuştaki
  /// diğer istekler (ör. aynı anda giden ÇAĞRI push'u) "Client is already
  /// closed" ile düşüyordu, aranan kişinin telefonu hiç çalmıyordu.
  /// Eski istemci bu yüzden KAPATILMAZ: uçuştaki istekleri bitsin, boşta
  /// kalan bağlantıları HttpClient'ın boşta zaman aşımıyla kendiliğinden
  /// kapanır (yalnız seyrek sıfırlamalarda olur; sızıntı önemsiz).
  void _fcmSifirla(Future<_FcmBaglanti> hataVeren) {
    if (identical(_fcmKurulum, hataVeren)) _fcmKurulum = null;
  }

  /// DÜŞÜK SEVİYE: verilen token'a, service account OAuth2 ile FCM HTTP v1 gönderir.
  Future<void> _gonderMesaj(
    String hedefToken,
    Map<String, dynamic> mesajAlanlari,
  ) async {
    final kurulum = _fcmBaglanti();
    final _FcmBaglanti fcm;
    try {
      fcm = await kurulum;
    } catch (e) {
      // KURULUM hatası (asset/JSON/OAuth): bu future kalıcı olarak başarısız
      // → önbellekte kalırsa her gönderim aynı hatayı alır; sıfırla.
      _fcmSifirla(kurulum);
      debugPrint('FCM kurulamadı: $e');
      return;
    }
    try {
      final yanit = await fcm.istemci.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/${fcm.projectId}/messages:send',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {'token': hedefToken, ...mesajAlanlari},
        }),
      );
      if (yanit.statusCode == 401 || yanit.statusCode == 403) {
        // Kimlik bozulduysa sonraki gönderim yeniden kursun.
        _fcmSifirla(kurulum);
      }
      if (yanit.statusCode != 200) {
        debugPrint('FCM gönderim hatası ${yanit.statusCode}: ${yanit.body}');
      }
    } catch (e) {
      // ⚠️ SIFIRLAMA YOK: istek sırasındaki istisnalar ağ kaynaklıdır
      // (SocketException, TimeoutException, http.ClientException) — istemci
      // sağlam, bir sonraki gönderim aynı istemciyle çalışır. Sıfırlamak
      // yalnız gereksiz bir OAuth gidiş-dönüşü eklerdi.
      debugPrint('Bildirim gönderilemedi: $e');
    }
  }
}

/// FCM HTTP v1 yetkili istemcisi + proje kimliği (aktarıcısız yol).
typedef _FcmBaglanti = ({AutoRefreshingAuthClient istemci, String projectId});
