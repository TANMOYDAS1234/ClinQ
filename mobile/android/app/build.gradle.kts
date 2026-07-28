plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.akdcare.akd_care"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than `flutter.ndkVersion` (26.3.11579264), which is
    // present on this machine but missing its cmake toolchain files and fails
    // the native build outright. Raised from 27.0.12077973 to satisfy
    // speech_to_text; NDK releases are backward compatible, so this covers
    // every plugin in the project.
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Required by flutter_local_notifications (uses java.time on older APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.akdcare.akd_care"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Jitsi Meet (jitsi_meet_flutter_sdk 11.x) requires API 26+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Jitsi's WebRTC native lib (libjingle_peerconnection_so) aborts in
    // JNI_OnLoad when loaded from the compressed APK. Extracting native libs to
    // the filesystem is what makes the in-app call open instead of crashing.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
