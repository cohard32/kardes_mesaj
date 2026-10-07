package com.welat.kardes_mesaj

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bildirim sesi olarak telefondaki herhangi bir sesi seçmek için sistem
 * zil sesi seçicisini açar (RingtoneManager). Geri dönen content:// URI'si
 * bildirim sistemi tarafından oynatılabilir — bu yüzden özel ses güvenilir çalışır.
 */
class MainActivity : FlutterActivity() {
    private val kanalAdi = "kardes_mesaj/sesler"
    private val sesSecKodu = 4671
    private var beklenenSonuc: MethodChannel.Result? = null

    // Dosya (PDF, Word…) seçici
    private val dosyaSecKodu = 4672
    private var beklenenDosya: MethodChannel.Result? = null
    private var dosyaAzami: Long = Long.MAX_VALUE

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kanalAdi)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sesSec" -> {
                        // Aynı anda tek seçici
                        if (beklenenSonuc != null) {
                            beklenenSonuc?.success(null)
                        }
                        beklenenSonuc = result
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(
                                RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_NOTIFICATION
                            )
                            putExtra(
                                RingtoneManager.EXTRA_RINGTONE_TITLE,
                                "Bildirim sesi seç"
                            )
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            val mevcut = call.argument<String>("mevcut")
                            if (mevcut != null) {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    Uri.parse(mevcut)
                                )
                            }
                        }
                        startActivityForResult(intent, sesSecKodu)
                    }

                    // Medyayı (foto/video) TELEFON GALERİSİNE kaydeder.
                    // MediaStore kullanılır → Android 10+ (API 29) izin GEREKMEZ.
                    // Dosya Dart tarafında geçici dizine İNDİRİLİP yolu verilir;
                    // burada sadece kopyalanır (büyük videolarda RAM şişmesin).
                    //
                    // ⚠️ Kopyalama eskiden bu işleyicide, yani ANA (UI) iş
                    // parçacığında yapılıyordu: yüzlerce MB'lık videoda ekran
                    // donuyor, 5 sn'yi aşınca Android "uygulama yanıt vermiyor"
                    // (ANR) gösteriyordu. Artık kopya arka plan iş parçacığında;
                    // MethodChannel.Result ise YALNIZ ana iş parçacığında
                    // çağrılabildiği için yanıt runOnUiThread ile döner.
                    "galeriyeKaydet" -> {
                        val yol = call.argument<String>("yol")
                        val ad = call.argument<String>("ad") ?: "roy_medya"
                        val mime = call.argument<String>("mime")
                            ?: "application/octet-stream"
                        Thread {
                            try {
                                val tamam = galeriyeKopyala(yol, ad, mime)
                                runOnUiThread { result.success(tamam) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("KAYDEDILEMEDI", e.message, null)
                                }
                            }
                        }.start()
                    }

                    // Telefonun zil durumu: 'normal' | 'titresim' | 'sessiz'
                    // + zil ses seviyesi 0 mı? Zil çalmıyor şikayetinin en
                    // yaygın sebebi cihaz ayarıdır; kullanıcıyı bilgilendirmek
                    // için okunur (uygulama BUNU DEĞİŞTİRMEZ).
                    "zilDurumu" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                        val mod = when (am.ringerMode) {
                            android.media.AudioManager.RINGER_MODE_SILENT -> "sessiz"
                            android.media.AudioManager.RINGER_MODE_VIBRATE -> "titresim"
                            else -> "normal"
                        }
                        val seviye = am.getStreamVolume(android.media.AudioManager.STREAM_RING)
                        result.success(mapOf("mod" to mod, "seviye" to seviye))
                    }

                    // Android 14+ (API 34) tam ekran bildirim izni verilmiş mi?
                    // Verilmezse gelen arama tam ekran açılmaz, sadece bildirime düşer.
                    "tamEkranIzniVarMi" -> {
                        val ok = if (Build.VERSION.SDK_INT >= 34) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                            nm.canUseFullScreenIntent()
                        } else {
                            true // 14 altinda manifest izni yeterli
                        }
                        result.success(ok)
                    }

                    // Tam ekran bildirim izni ayar ekranini acar (Android 14+).
                    "tamEkranAyarlariniAc" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (e: Exception) {
                                // Ayar ekrani yoksa uygulama detay ayarlarina dus
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                        }
                        result.success(null)
                    }

                    // Sistem dosya seçicisini açar (PDF, Word, Excel…). Seçilen
                    // dosya uygulamanın önbelleğine KOPYALANIR (content:// URI
                    // kalıcı değil) ve {yol, ad, boyut, mime} döner. Boyut
                    // `azami`yı aşıyorsa kopyalanmaz: {hata: "buyuk", ad, boyut}.
                    // Vazgeçilirse null.
                    "dosyaSec" -> {
                        beklenenDosya?.success(null) // aynı anda tek seçici
                        beklenenDosya = result
                        dosyaAzami = (call.argument<Number>("azami"))?.toLong()
                            ?: Long.MAX_VALUE
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        try {
                            startActivityForResult(intent, dosyaSecKodu)
                        } catch (e: Exception) {
                            beklenenDosya = null
                            result.error("SECICI_YOK", e.message, null)
                        }
                    }

                    // Mesajdaki bağlantıyı tarayıcıda (ya da adresi işleyen
                    // uygulamada) açar. ⚠️ Yalnız http/https: karşı tarafın
                    // gönderdiği "intent:" / "file:" / "content:" gibi bir
                    // adres buradan ASLA başlatılmaz (Dart tarafında da kontrol var).
                    "linkAc" -> {
                        val adres = call.argument<String>("url")
                        val uri = try { Uri.parse(adres) } catch (e: Exception) { null }
                        val sema = uri?.scheme?.lowercase()
                        if (uri == null || (sema != "http" && sema != "https") ||
                            uri.host.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, uri)
                                        .addCategory(Intent.CATEGORY_BROWSABLE)
                                )
                                result.success(true)
                            } catch (e: Exception) {
                                // Tarayıcı yok / devre dışı
                                result.success(false)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * [galeriyeKaydet] kopyası — ARKA PLAN iş parçacığında çağrılır, bu yüzden
     * MethodChannel.Result'a DOKUNMAZ (yanıtı çağıran ana iş parçacığında verir).
     *
     * @return kaydedildiyse true; kaynak yoksa / MediaStore girdi açamazsa false.
     * Kopya sırasında hata olursa istisna çağırana fırlatılır.
     */
    private fun galeriyeKopyala(yol: String?, ad: String, mime: String): Boolean {
        val kaynak = if (yol != null) java.io.File(yol) else null
        if (kaynak == null || !kaynak.exists()) return false
        val video = mime.startsWith("video")
        // Foto/video DEĞİLSE (PDF, Word…) → İndirilenler klasörü.
        val belge = !video && !mime.startsWith("image")
        val klasor = when {
            video -> android.os.Environment.DIRECTORY_MOVIES
            belge -> android.os.Environment.DIRECTORY_DOWNLOADS
            else -> android.os.Environment.DIRECTORY_PICTURES
        }

        if (Build.VERSION.SDK_INT >= 29) {
            val hacim = android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY
            val koleksiyon = when {
                video -> android.provider.MediaStore.Video.Media.getContentUri(hacim)
                belge -> android.provider.MediaStore.Downloads.getContentUri(hacim)
                else -> android.provider.MediaStore.Images.Media.getContentUri(hacim)
            }
            val degerler = android.content.ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, ad)
                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    android.provider.MediaStore.MediaColumns.RELATIVE_PATH,
                    "$klasor/ROY MESSANGER"
                )
                put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(koleksiyon, degerler) ?: return false
            // ⚠️ Kopya yarıda kalırsa (disk dolu, kaynak silindi…) IS_PENDING=1
            // girdisi MediaStore'da ASILI kalıyordu: galeride görünmeyen ama yer
            // kaplayan yarım dosya. Başarısız her yolda girdi silinir.
            var tamam = false
            try {
                val cikis = contentResolver.openOutputStream(uri)
                if (cikis != null) {
                    cikis.use { c -> kaynak.inputStream().use { g -> g.copyTo(c) } }
                    degerler.clear()
                    degerler.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, degerler, null, null)
                    tamam = true
                }
            } finally {
                if (!tamam) {
                    try {
                        contentResolver.delete(uri, null, null)
                    } catch (silinemedi: Exception) {
                        // Temizlik en iyi çaba; asıl hata/sonuç çağırana gider.
                    }
                }
            }
            return tamam
        }

        // Android 9 ve altı: klasöre yaz + galeriye tarat
        // (WRITE_EXTERNAL_STORAGE manifestte maxSdk=28).
        val dizin = java.io.File(
            android.os.Environment
                .getExternalStoragePublicDirectory(klasor),
            "ROY MESSANGER"
        )
        if (!dizin.exists()) dizin.mkdirs()
        val hedef = java.io.File(dizin, ad)
        kaynak.inputStream().use { g ->
            hedef.outputStream().use { c -> g.copyTo(c) }
        }
        android.media.MediaScannerConnection.scanFile(
            this, arrayOf(hedef.absolutePath), arrayOf(mime), null
        )
        return true
    }

    /**
     * content:// adresindeki dosyayı önbelleğe kopyalar. ARKA PLAN iş
     * parçacığında çağrılmalı (büyük dosyada UI donmasın).
     * Boyut [azami]'yı aşarsa KOPYALAMAZ, {hata: "buyuk"} döner.
     */
    private fun uriyiKopyala(uri: Uri, azami: Long): Map<String, Any?> {
        var ad: String? = null
        var boyut: Long = -1
        try {
            contentResolver.query(
                uri,
                arrayOf(
                    android.provider.OpenableColumns.DISPLAY_NAME,
                    android.provider.OpenableColumns.SIZE
                ),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val adSutun = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    val boyutSutun = c.getColumnIndex(android.provider.OpenableColumns.SIZE)
                    if (adSutun >= 0) ad = c.getString(adSutun)
                    if (boyutSutun >= 0 && !c.isNull(boyutSutun)) boyut = c.getLong(boyutSutun)
                }
            }
        } catch (e: Exception) {
            // Ad/boyut okunamazsa kopyadan hesaplanır.
        }
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        val temizAd = (ad ?: "dosya").replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (boyut > azami) {
            return mapOf("hata" to "buyuk", "ad" to temizAd, "boyut" to boyut)
        }
        val dizin = java.io.File(cacheDir, "gelen_dosyalar")
        if (!dizin.exists()) dizin.mkdirs()
        val hedef = java.io.File(dizin, "${System.currentTimeMillis()}_$temizAd")
        val giris = contentResolver.openInputStream(uri)
            ?: return mapOf("hata" to "okunamadi", "ad" to temizAd)
        giris.use { g -> hedef.outputStream().use { c -> g.copyTo(c) } }
        val gercekBoyut = hedef.length()
        if (gercekBoyut > azami) {
            hedef.delete()
            return mapOf("hata" to "buyuk", "ad" to temizAd, "boyut" to gercekBoyut)
        }
        return mapOf(
            "yol" to hedef.absolutePath,
            "ad" to temizAd,
            "boyut" to gercekBoyut,
            "mime" to mime
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == dosyaSecKodu) {
            val sonuc = beklenenDosya ?: return
            beklenenDosya = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                sonuc.success(null)
                return
            }
            val azami = dosyaAzami
            Thread {
                try {
                    val bilgi = uriyiKopyala(uri, azami)
                    runOnUiThread { sonuc.success(bilgi) }
                } catch (e: Exception) {
                    runOnUiThread { sonuc.error("KOPYALANAMADI", e.message, null) }
                }
            }.start()
            return
        }
        if (requestCode != sesSecKodu) return
        val sonuc = beklenenSonuc ?: return
        beklenenSonuc = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            val uri: Uri? =
                data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            if (uri != null) {
                val ad = try {
                    RingtoneManager.getRingtone(this, uri)?.getTitle(this)
                } catch (e: Exception) {
                    null
                }
                sonuc.success(mapOf("uri" to uri.toString(), "ad" to (ad ?: "Özel ses")))
            } else {
                sonuc.success(null) // "Sessiz" seçildi
            }
        } else {
            sonuc.success(null) // iptal edildi
        }
    }
}
