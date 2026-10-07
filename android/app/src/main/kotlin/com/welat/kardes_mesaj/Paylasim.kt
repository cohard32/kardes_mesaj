package com.welat.kardes_mesaj

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Başka uygulamadan "Paylaş → ROY MESSANGER" ile gelen içerik, Dart onu
 * `paylasimAl` ile isteyene kadar burada bekler (aynı süreç, bellekte).
 * Biçim: {metin: String?, dosyalar: [{yol, ad, boyut, mime}], buyukler: [ad]}
 */
object PaylasimDeposu {
    @Volatile
    private var bekleyen: Map<String, Any?>? = null

    fun koy(veri: Map<String, Any?>) {
        bekleyen = veri
    }

    /** Bekleyeni verir ve siler (bir kez işlensin). */
    fun al(): Map<String, Any?>? {
        val v = bekleyen
        bekleyen = null
        return v
    }
}

/**
 * content:// adresindeki dosyayı uygulamanın önbelleğine kopyalar.
 * ARKA PLAN iş parçacığında çağrılmalı (büyük dosyada UI donmasın).
 * Boyut [azami]'yı aşarsa KOPYALAMAZ: {hata: "buyuk", ad, boyut} döner.
 * Başarılıysa {yol, ad, boyut, mime}.
 */
fun uriyiKopyala(ctx: Context, uri: Uri, azami: Long): Map<String, Any?> {
    val cr = ctx.contentResolver
    var ad: String? = null
    var boyut: Long = -1
    try {
        cr.query(
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
    val mime = cr.getType(uri) ?: "application/octet-stream"
    // Yol ayırıcı ve geçersiz karakterler dosya adından çıkarılır.
    val temizAd = (ad ?: uri.lastPathSegment ?: "dosya")
        .replace(Regex("[\\\\/:*?\"<>|]"), "_")
    if (boyut > azami) {
        return mapOf("hata" to "buyuk", "ad" to temizAd, "boyut" to boyut)
    }
    val dizin = java.io.File(ctx.cacheDir, "gelen_dosyalar")
    if (!dizin.exists()) dizin.mkdirs()
    val hedef = java.io.File(dizin, "${System.nanoTime()}_$temizAd")
    val giris = cr.openInputStream(uri)
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

/**
 * Paylaşım hedefi: görünmez, kısa ömürlü aktivite. Gelen metni/dosyaları
 * (content:// izni bu aktiviteye verildiği için BURADA) önbelleğe kopyalar,
 * [PaylasimDeposu]'na koyar ve uygulamanın asıl ekranını öne getirir.
 *
 * ⚠️ Neden ayrı aktivite: paylaşım MainActivity'ye gelseydi, gönderen
 * uygulamanın görev yığınında İKİNCİ bir MainActivity (ve ikinci bir Flutter
 * motoru: çift Firebase, çift bildirim dinleyicisi) açılırdı.
 */
class PaylasimAktivitesi : Activity() {
    companion object {
        const val EK_ANAHTAR = "roy_paylasim"

        // Video 100 MB'a kadar gönderilebilir; daha büyüğü kopyalanmaz.
        private const val AZAMI: Long = 100L * 1024 * 1024
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val gelen = intent
        Thread {
            val veri = try {
                paylasimiOku(gelen)
            } catch (e: Exception) {
                null
            }
            runOnUiThread {
                if (veri != null) PaylasimDeposu.koy(veri)
                val ac = Intent(this, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    putExtra(EK_ANAHTAR, true)
                }
                startActivity(ac)
                finish()
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun paylasimiOku(i: Intent?): Map<String, Any?>? {
        if (i == null) return null
        val metin = i.getStringExtra(Intent.EXTRA_TEXT)
        val adresler = mutableListOf<Uri>()
        when (i.action) {
            Intent.ACTION_SEND -> {
                val u: Uri? = i.getParcelableExtra(Intent.EXTRA_STREAM)
                if (u != null) adresler.add(u)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val liste: ArrayList<Uri>? =
                    i.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                if (liste != null) adresler.addAll(liste)
            }
        }
        // Bazı uygulamalar dosyayı yalnız ClipData ile verir.
        if (adresler.isEmpty()) {
            val clip = i.clipData
            if (clip != null) {
                for (k in 0 until clip.itemCount) {
                    clip.getItemAt(k).uri?.let { adresler.add(it) }
                }
            }
        }
        val dosyalar = mutableListOf<Map<String, Any?>>()
        val buyukler = mutableListOf<String>()
        for (u in adresler.take(30)) {
            try {
                val sonuc = uriyiKopyala(this, u, AZAMI)
                if (sonuc["hata"] == "buyuk") {
                    buyukler.add(sonuc["ad"] as? String ?: "dosya")
                } else if (sonuc["yol"] != null) {
                    dosyalar.add(sonuc)
                }
            } catch (e: Exception) {
                // Tek dosya okunamazsa diğerleri yine gelsin.
            }
        }
        if (metin.isNullOrBlank() && dosyalar.isEmpty() && buyukler.isEmpty()) {
            return null
        }
        return mapOf(
            "metin" to metin,
            "dosyalar" to dosyalar,
            "buyukler" to buyukler
        )
    }
}
