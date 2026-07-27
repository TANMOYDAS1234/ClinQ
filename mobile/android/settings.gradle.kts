pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    // Flutter warns that support for Kotlin below 2.1.0 is being dropped.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    // Reads google-services.json at build time and emits the Firebase config
    // the SDK looks for at runtime. Declared here rather than through the
    // buildscript/classpath form the Firebase console suggests, which conflicts
    // with the plugins DSL this project already uses.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
