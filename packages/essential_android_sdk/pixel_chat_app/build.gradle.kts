import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseKeystoreProperties = Properties()
val releaseKeystorePropertiesFile = System.getenv("ESSENTIAL_RELEASE_KEYSTORE_PROPERTIES")
    ?.let(::file)
    ?: file("${System.getProperty("user.home")}/.android/essential-release.properties")
if (releaseKeystorePropertiesFile.isFile) {
    releaseKeystorePropertiesFile.inputStream().use(releaseKeystoreProperties::load)
}

if (tasks.findByName("prepareKotlinBuildScriptModel") == null) {
    tasks.register("prepareKotlinBuildScriptModel") {
        group = "build setup"
        description = "Compatibility task used by Android Studio Kotlin DSL sync."
    }
}

android {
    namespace = "io.essential.sdk.pixelchat"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.essential.sdk.pixelchat"
        minSdk = 26
        targetSdk = 35
        versionCode = 12
        versionName = "1.0.12"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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
        }
    }
}

dependencies {
    implementation(project(":"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
