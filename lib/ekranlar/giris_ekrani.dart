import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../tema.dart';

/// Tek ekran: e-posta + şifre + "Giriş yap".
/// Kayıt ekranı YOK — hesaplar Firebase panelinden elle açılır.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _epostaCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();

  bool _yukleniyor = false;
  String? _hata;

  @override
  void dispose() {
    _epostaCtrl.dispose();
    _sifreCtrl.dispose();
    super.dispose();
  }

  Future<void> _girisYap() async {
    final eposta = _epostaCtrl.text.trim();
    final sifre = _sifreCtrl.text;

    if (eposta.isEmpty || sifre.isEmpty) {
      setState(() => _hata = 'E-posta ve şifre boş olamaz.');
      return;
    }

    setState(() {
      _yukleniyor = true;
      _hata = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: eposta,
        password: sifre,
      );
      // Başarılı giriş sonrası AuthGate otomatik sohbete geçirir.
    } on FirebaseAuthException catch (e) {
      setState(() => _hata = _hataMesaji(e.code));
    } catch (_) {
      setState(() => _hata = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Firebase hata kodlarını Türkçe, anlaşılır mesaja çevirir.
  String _hataMesaji(String kod) {
    switch (kod) {
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'user-disabled':
        return 'Bu hesap devre dışı bırakılmış.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya şifre hatalı.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
      case 'too-many-requests':
        return 'Çok fazla deneme. Biraz sonra tekrar dene.';
      default:
        return 'Giriş yapılamadı ($kod).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.forum_rounded,
                    size: 72, color: Renkler.accent),
                const SizedBox(height: 16),
                Text(
                  'Kardeş Mesaj',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Giriş yap',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Renkler.metinSoluk),
                ),
                const SizedBox(height: 32),

                // E-posta
                TextField(
                  controller: _epostaCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_yukleniyor,
                  decoration: const InputDecoration(
                    hintText: 'E-posta',
                    prefixIcon: Icon(Icons.mail_outline, color: Renkler.metinSoluk),
                  ),
                ),
                const SizedBox(height: 14),

                // Şifre
                TextField(
                  controller: _sifreCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  enabled: !_yukleniyor,
                  onSubmitted: (_) => _girisYap(),
                  decoration: const InputDecoration(
                    hintText: 'Şifre',
                    prefixIcon: Icon(Icons.lock_outline, color: Renkler.metinSoluk),
                  ),
                ),

                // Hata mesajı
                if (_hata != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _hata!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF5A5A)),
                  ),
                ],

                const SizedBox(height: 24),

                // Giriş butonu
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _yukleniyor ? null : _girisYap,
                    child: _yukleniyor
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Giriş yap',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
