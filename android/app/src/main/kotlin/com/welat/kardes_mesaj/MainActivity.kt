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
                    "galeriyeKaydet" -> {
                        try {
                            val yol = call.argument<String>("yol")
                            val ad = call.argument<String>("ad") ?: "roy_medya"
                            val mime = call.argument<String>("mime")
                                ?: "application/octet-stream"
                            val kaynak = if (yol != null) java.io.File(yol) else null
                            if (kaynak == null || !kaynak.exists()) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val video = mime.startsWith("video")
                            val klasor = if (video)
                                android.os.Environment.DIRECTORY_MOVIES
                            else android.os.Environment.DIRECTORY_PICTURES

                            if (Build.VERSION.SDK_INT >= 29) {
                                val koleksiyon = if (video)
                                    android.provider.MediaStore.Video.Media
                                        .getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                else android.provider.MediaStore.Images.Media
                                    .getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                val degerler = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, ad)
                                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                                    put(
                                        android.provider.MediaStore.MediaColumns.RELATIVE_PATH,
                                        "$klasor/ROY MESSANGER"
                                    )
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                                val uri = contentResolver.insert(koleksiyon, degerler)
                                if (uri == null) { result.success(false); return@setMethodCallHandler }
                                contentResolver.openOutputStream(uri).use { cikis ->
                                    if (cikis == null) { result.success(false); return@setMethodCallHandler }
                                    kaynak.inputStream().use { it.copyTo(cikis) }
                                }
                                degerler.clear()
                                degerler.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                contentResolver.update(uri, degerler, null, null)
                                result.success(true)
                            } else {
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
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("KAYDEDILEMEDI", e.message, null)
                        }
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

                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
