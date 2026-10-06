import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// SURUM IMZASI: android/key.properties (git'e GIRMEZ, bkz. android/.gitignore)
//   storeFile=<keystore yolu; android/app'e gore goreli ya da mutlak>
//   storePassword=...   keyAlias=...   keyPassword=...
// ⚠️ Eskiden release APK DEBUG anahtariyla imzalaniyordu. Debug keystore
// (~/.android/debug.keystore) makineye ozel: bilgisayar degisir/sifirlanirsa
// yeni APK eskisinin USTUNE KURULAMAZ (imza uyusmazligi) → otomatik guncelleme
// kirilir, herkes uygulamayi silip yerel veriyi kaybeder. key.properties varsa
// gercek anahtar kullanilir; YOKSA (yerel/CI derlemesi) debug'a dusulur ve
// uyarilir — derleme kirilmasin diye.
val imzaDosyasi = rootProject.file("key.properties")
val imza = Properties().apply {
    if (imzaDosyasi.exists()) imzaDosyasi.inputStream().use { load(it) }
}
val imzaAnahtarlari = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val imzaHazir = imzaDosyasi.exists() &&
    imzaAnahtarlari.all { !imza.getProperty(it).isNullOrBlank() }
// ⚠️ GERCEK ANAHTARA GECTIKTEN SONRA debug'a sessizce dusmek, onlemek
// istedigimiz arizayi (guncelleme kurulamaz) AYNEN geri getirir. Bu yuzden:
//  - android/gradle.properties'te royImzaZorunlu=true ise release derlemesi
//    key.properties olmadan HATA verir (gecis yapildiktan sonra acin);
//  - degilse uyari logger.quiet ile basilir: flutter araci Gradle'i '-q' ile
//    calistirir ve WARN duzeyi orada HIC gorunmez, QUIET duzeyi gorunur.
val imzaZorunlu = (findProperty("royImzaZorunlu") as String?)?.toBoolean() == true
val releaseIstendi = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (!imzaHazir) {
    val neden = if (imzaDosyasi.exists())
        "android/key.properties eksik alan iceriyor ($imzaAnahtarlari)"
    else
        "android/key.properties yok"
    if (imzaZorunlu && releaseIstendi) {
        throw GradleException(
            "$neden ama royImzaZorunlu=true: release DEBUG anahtariyla " +
                "imzalanamaz (yuklu uygulamalar bu APK'yi KURAMAZ)."
        )
    }
    logger.quiet(
        "UYARI: $neden → release DEBUG anahtariyla imzalanacak " +
            "(dagitim icin uygun DEGIL)."
    )
}

android {
    namespace = "com.welat.kardes_mesaj"
    // Agora (agora_rtc_engine) compileSdk 34+ gerektirir → 36'ya sabitlendi.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications icin gerekli (core library desugaring)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // APK boyutunu kucult: Agora'nin temel arama icin GEREKSIZ ek ozellik
    // kutuphanelerini cikar (AV1, sanal arka plan, uzamsal ses, super cozunurluk,
    // yuz/icerik analizi vb.). Temel ses/goruntulu arama core'da, etkilenmez.
    packaging {
        jniLibs {
            excludes += listOf(
                "**/libagora_ai_echo_cancellation_extension.so",
                "**/libagora_ai_echo_cancellation_ll_extension.so",
                "**/libagora_ai_noise_suppression_extension.so",
                "**/libagora_ai_noise_suppression_ll_extension.so",
                "**/libagora_audio_beauty_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_drm_loader_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_full_audio_format_extension.so",
                "**/libagora_pvc_extension.so",
                "**/libagora_screen_capture_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_super_resolution_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_vqa_extension.so",
            )
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.welat.kardes_mesaj"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (imzaHazir) {
            create("release") {
                storeFile = file(imza.getProperty("storeFile"))
                storePassword = imza.getProperty("storePassword")
                keyAlias = imza.getProperty("keyAlias")
                keyPassword = imza.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (imzaHazir)
                signingConfigs.getByName("release")
            else signingConfigs.getByName("debug")
            // Bildirim ses kaynakları (res/raw) atılmasın diye küçültme KAPALI.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications icin core library desugaring kutuphanesi
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
