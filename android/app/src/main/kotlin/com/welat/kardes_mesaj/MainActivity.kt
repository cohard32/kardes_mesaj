package com.welat.kardes_mesaj

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
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
