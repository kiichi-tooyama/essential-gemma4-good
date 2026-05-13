import java.util.Properties
import org.gradle.api.tasks.Exec

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystoreProperties = Properties()
val releaseKeystorePropertiesFile = file(
    System.getenv("ESSENTIAL_RELEASE_KEYSTORE_PROPERTIES")
        ?: "${System.getProperty("user.home")}/.android/essential-gemma4-good-release.properties",
)
if (releaseKeystorePropertiesFile.isFile) {
    releaseKeystorePropertiesFile.inputStream().use(releaseKeystoreProperties::load)
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.isFile) {
    localPropertiesFile.inputStream().use(localProperties::load)
}
val flutterExecutable = localProperties.getProperty("flutter.sdk")
    ?.let { file("$it/bin/flutter").absolutePath }
    ?: "flutter"

val flutterPubGet = tasks.register<Exec>("flutterPubGet") {
    workingDir = rootProject.file("..")
    commandLine(flutterExecutable, "pub", "get")
}

android {
    namespace = "com.example.essential_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.essential_flutter"
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                abiFilters += listOf("arm64-v8a")
                cppFlags += listOf("-std=c++17")
                arguments += listOf(
                    "-DGGML_LLAMAFILE=OFF",
                    "-DGGML_OPENMP=OFF",
                    "-DLLAMA_OPENSSL=OFF",
                    "-DGGML_NATIVE=OFF",
                )
            }
        }
    }

    buildFeatures {
        aidl = true
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "**/libVkLayer_khronos_validation.so",
                "lib/armeabi-v7a/**",
                "lib/x86_64/**",
            )
        }
    }

    androidResources {
        noCompress += listOf("litertlm", "gguf", "ggml")
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (releaseKeystoreProperties.isNotEmpty()) {
            create("essentialRelease") {
                storeFile = file(releaseKeystoreProperties.getProperty("storeFile"))
                storePassword = releaseKeystoreProperties.getProperty("storePassword")
                keyAlias = releaseKeystoreProperties.getProperty("keyAlias")
                keyPassword = releaseKeystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseKeystoreProperties.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("essentialRelease")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.10.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test:runner:1.2.0")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

tasks.configureEach {
    if (name.startsWith("compileFlutterBuild")) {
        dependsOn(flutterPubGet)
    }
}

flutter {
    source = "../.."
}
