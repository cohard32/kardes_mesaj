import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama ayarlarını (bildirim/titreşim/ses) cihazda kalıcı saklar.
/// SharedPreferences kullanır. ValueNotifier'lar ile UI canlı güncellenir.
class AyarServisi {
  AyarServisi._();
  static final AyarServisi instance = AyarServisi._();

  SharedPreferences? _prefs;

  // Varsayılan değerlerle başlar; baslat() ile kayıttan yüklenir.
  final ValueNotifier<bool> bildirimAcik = ValueNotifier<bool>(true);
  final ValueNotifier<bool> titresimAcik = ValueNotifier<bool>(true);
  // 'varsayilan' | 'sessiz' (ileride assets/sesler içindeki özel sesler eklenir)
  final ValueNotifier<String> bildirimSesi = ValueNotifier<String>('varsayilan');

  /// main() içinde bir kez çağrılır.
  Future<void> baslat() async {
    _prefs = await SharedPreferences.getInstance();
    bildirimAcik.value = _prefs?.getBool('bildirimAcik') ?? true;
    titresimAcik.value = _prefs?.getBool('titresimAcik') ?? true;
    bildirimSesi.value = _prefs?.getString('bildirimSesi') ?? 'varsayilan';
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
