pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")

        require(localPropertiesFile.exists()) {
            "local.properties was not found in the android directory."
        }

        localPropertiesFile.inputStream().use(properties::load)

        properties.getProperty("flutter.sdk")
            ?: error("flutter.sdk is not set in local.properties")
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
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("com.android.application") version "9.3.0" apply false
}

include(":app")