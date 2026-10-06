import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tema.dart';

/// Uygulama ayarlarını (bildirim/titreşim/ses/tema) cihazda kalıcı saklar.
/// SharedPreferences kullanır. ValueNotifier'lar ile UI canlı güncellenir.
class AyarServisi {
  AyarServisi._();
  static final AyarServisi instance = AyarServisi._();

  SharedPreferences? _prefs;

  // Varsayılan değerlerle başlar; baslat() ile kayıttan yüklenir.
  final ValueNotifier<bool> bildirimAcik = ValueNotifier<bool>(true);
  /// MESAJ bildirimi titreşimi. Android 8+'da titreşim kanala kilitli
  /// olduğu için bu değer YAYINLANAN kanalı seçer (`km_v3_<ses>_tsz`
  /// varyantı) → değişince `BildirimServisi.kanalYayinla()` çağrılmalı.
  /// Arama (CallKit) titreşimini ETKİLEMEZ (aşağıdaki NOT).
  final ValueNotifier<bool> titresimAcik = ValueNotifier<bool>(true);
  // Hazır seslerden birinin anahtarı (liste: ses_secenekleri.dart →
  // sesSecenekleri) ya da 'ozel' (bkz. BildirimKanali.secimler).
  final ValueNotifier<String> bildirimSesi = ValueNotifier<String>('varsayilan');
  // 'ozel' seçiliyse: kullanıcının telefondan seçtiği sesin content:// URI'si + adı
  final ValueNotifier<String?> ozelSesUri = ValueNotifier<String?>(null);
  final ValueNotifier<String?> ozelSesAdi = ValueNotifier<String?>(null);

  // ---- ARAMA ZİLİ (bildirim sesinden AYRI sistem) ----
  /// CallKit'e `ringtonePath` olarak verilir. Değerler res/raw kaynak ADI
  /// olmalı; `system_ringtone_default` ise telefonun kendi zilini çalar.
  /// ⚠️ content:// URI DESTEKLENMİYOR (CallKit eklentisi yalnız raw adı veya
  /// system_ringtone_default çözer) → telefondan özel zil dosyası seçilemez.
  static const String zilTelefon = 'system_ringtone_default';
  static const String zilVarsayilan = 'ringtone_default'; // eklentinin kendi zili
  static const String anahtarAramaZili = 'aramaZili';

  final ValueNotifier<String> aramaZili = ValueNotifier<String>(zilTelefon);

  // ---- GÖRÜNÜM ----
  static const String anahtarTema = 'tema';
  static const String anahtarParilti = 'parilti';

  /// Seçili palet adı ([RoyPalet.ad]; bilinmeyen değer → neonLime).
  /// ⚠️ Değer değişmeden ÖNCE [Renkler.uygula] çağrılır → dinleyiciler
  /// (main.dart) tetiklendiğinde `Renkler` zaten yeni paleti döndürür.
  final ValueNotifier<String> tema =
      ValueNotifier<String>(RoyPalet.neonLime.ad);

  /// Neon parıltısı AÇIK mı (varsayılan true). Ayarlar'daki
  /// "Neon parıltısını azalt" anahtarı bunun TERSİDİR.
  final ValueNotifier<bool> parilti = ValueNotifier<bool>(true);

  // NOT: "arama titreşimi aç/kapa" EKLENMEDİ — flutter_callkit_incoming
  // AndroidParams'ta titreşim alanı YOK; eklenti titreşimi koşulsuz uygular
  // (yalnızca telefon SESSİZ modda ise atlar). Çalışmayan bir anahtar
  // koymaktansa bu sınır belgelendi.

  /// main() içinde bir kez çağrılır.
  Future<void> baslat() async {
    _prefs = await SharedPreferences.getInstance();
    bildirimAcik.value = _prefs?.getBool('bildirimAcik') ?? true;
    titresimAcik.value = _prefs?.getBool('titresimAcik') ?? true;
    bildirimSesi.value = _prefs?.getString('bildirimSesi') ?? 'varsayilan';
    ozelSesUri.value = _prefs?.getString('ozelSesUri');
    ozelSesAdi.value = _prefs?.getString('ozelSesAdi');
    aramaZili.value = _prefs?.getString(anahtarAramaZili) ?? zilTelefon;
    // Tema runApp'ten ÖNCE uygulanmalı (main.dart bu metodu bekliyor) →
    // ilk kare doğru paletle çizilir, açılışta renk "zıplaması" olmaz.
    final palet = RoyPalet.bul(_prefs?.getString(anahtarTema));
    final pariltiAcik = _prefs?.getBool(anahtarParilti) ?? true;
    Renkler.uygula(palet, pariltiAzalt: !pariltiAcik);
    tema.value = palet.ad;
    parilti.value = pariltiAcik;
  }

  /// Paleti değiştirir ve kaydeder. Ekranın yeniden çizimi main.dart'taki
  /// [tema] dinleyicisinin işidir.
  Future<void> temaAyarla(String ad) async {
    final palet = RoyPalet.bul(ad);
    Renkler.uygula(palet);
    tema.value = palet.ad;
    await _prefs?.setString(anahtarTema, palet.ad);
  }

  /// [acik] = neon parıltısı açık mı (anahtar "azalt" olduğu için tersi).
  Future<void> pariltiAyarla(bool acik) async {
    Renkler.uygula(Renkler.aktif, pariltiAzalt: !acik);
    parilti.value = acik;
    await _prefs?.setBool(anahtarParilti, acik);
  }

  /// ARKA PLAN İZOLATI için: seçili palet adını doğrudan diskten okur
  /// (gelen arama CallKit renkleri). [aramaZiliDiskten] ile aynı gerekçe:
  /// orada [baslat] çalışmadığından [tema] ve [Renkler] VARSAYILANDADIR.
  static Future<String> temaDiskten() async {
    try {
      final p = await SharedPreferences.getInstance();
      return RoyPalet.bul(p.getString(anahtarTema)).ad;
    } catch (_) {
      return RoyPalet.neonLime.ad;
    }
  }

  Future<void> aramaZiliAyarla(String deger) async {
    aramaZili.value = deger;
    await _prefs?.setString(anahtarAramaZili, deger);
  }

  /// ARKA PLAN İZOLATI için: seçili arama zilini doğrudan diskten okur.
  /// ⚠️ Gelen arama FCM arka plan handler'ında işlenir; orada [baslat]
  /// çağrılmadığı için ValueNotifier'lar VARSAYILAN değerdedir. Bu yüzden
  /// zil/titreşim ayarı SharedPreferences'tan taze okunmalı.
  static Future<String> aramaZiliDiskten() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(anahtarAramaZili) ?? zilTelefon;
    } catch (_) {
      return zilTelefon;
    }
  }

  /// Telefondan seçilen özel sesi kaydeder.
  Future<void> ozelSesAyarla(String uri, String ad) async {
    ozelSesUri.value = uri;
    ozelSesAdi.value = ad;
    await _prefs?.setString('ozelSesUri', uri);
    await _prefs?.setString('ozelSesAdi', ad);
  }

  Future<void> bildirimAcikAyarla(bool deger) async {
    bildirimAcik.value = deger;
    await _prefs?.setBool('bildirimAcik', deger);
  }

  Future<void> titresimAcikAyarla(bool deger) async {
    titresimAcik.value = deger;
    await _prefs?.setBool('titresimAcik', deger);
  }

  Future<void> bildirimSesiAyarla(String deger) async {
    bildirimSesi.value = deger;
    await _prefs?.setString('bildirimSesi', deger);
  }

  bool get sessizMi => bildirimSesi.value == 'sessiz';
}
