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

            // Almost the whole APK is the Flutter engine, shipped once per CPU
            // architecture: 20.7 MB for arm64, 18.9 for 32-bit ARM and 22.2 for
            // x86_64, against 3.5 MB for everything this app actually is.
            //
            // x86_64 is emulators only — no phone runs it — so a release build
            // carrying it posts 22 MB to every patient for nobody's benefit.
            // Both ARM slices stay: arm64 for anything current, armeabi-v7a
            // because budget handsets in this clinic's market are still 32-bit,
            // and locking them out to save space is not a trade worth making.
            //
            // Debug builds keep every architecture so an x86_64 emulator on a
            // development machine still runs.
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
            }

            // R8 runs on release builds. Without these rules it strips the
            // generic signatures Gson needs and flutter_local_notifications
            // throws on every read of its scheduled-notification store — which
            // is why medicine reminders never fired in a release build.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
