plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
