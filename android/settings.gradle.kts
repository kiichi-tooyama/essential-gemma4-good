pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localProperties = file("local.properties")
            if (localProperties.isFile) {
                localProperties.inputStream().use { properties.load(it) }
            }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
                ?: System.getenv("FLUTTER_ROOT")
                ?: System.getenv("FLUTTER_HOME")
                ?: runCatching {
                    val process = ProcessBuilder("bash", "-lc", "command -v flutter")
                        .redirectErrorStream(true)
                        .start()
                    val flutterBin = process.inputStream.bufferedReader().readText().trim()
                    if (process.waitFor() == 0 && flutterBin.isNotEmpty()) {
                        java.io.File(flutterBin).canonicalFile.parentFile.parent
                    } else {
                        null
                    }
                }.getOrNull()
                ?: listOf(
                    "/opt/homebrew/Caskroom/flutter/3.41.4/flutter",
                    "/opt/homebrew/Caskroom/flutter/latest/flutter",
                    "/opt/homebrew/share/flutter",
                    "/usr/local/Caskroom/flutter/latest/flutter",
                ).firstOrNull { java.io.File(it, "packages/flutter_tools/gradle").isDirectory }
                ?: error(
                    "Flutter SDK not found. Open the repository root with Android Studio, " +
                        "or set FLUTTER_ROOT, or create android/local.properties with flutter.sdk=/path/to/flutter."
                )
            if (!localProperties.isFile) {
                val androidSdkPath = System.getenv("ANDROID_HOME")
                    ?: System.getenv("ANDROID_SDK_ROOT")
                    ?: "${System.getProperty("user.home")}/Library/Android/sdk"
                localProperties.writeText(
                    "flutter.sdk=$flutterSdkPath\n" +
                        "sdk.dir=$androidSdkPath\n"
                )
            }
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
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
