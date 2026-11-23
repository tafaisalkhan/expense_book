import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// A separate install is selected only by the dedicated preview entry point.
val isLocalPreview = providers.gradleProperty("target").orNull?.endsWith("main_preview.dart") == true
if (isLocalPreview) {
    check(gradle.startParameter.taskNames.none { it.contains("Release", ignoreCase = true) }) {
        "Local previews must be built in debug mode."
    }
    tasks.configureEach {
        if (name.endsWith("GoogleServices")) enabled = false
    }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val defaultTestAdmobAppId = "ca-app-pub-3940256099942544~3347511713"
val admobSecretsFile = rootProject.file("../admob_secrets.json")
val releaseAdmobAppId = if (!isLocalPreview && admobSecretsFile.exists()) {
    Regex("\"ADMOB_APP_ID\"\\s*:\\s*\"([^\"]+)\"")
        .find(admobSecretsFile.readText())
        ?.groupValues?.get(1)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: defaultTestAdmobAppId
} else {
    defaultTestAdmobAppId
}

android {
    namespace = "com.myexpense.book"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.myexpense.book"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "My Expence Book"
        manifestPlaceholders["admobAppId"] = defaultTestAdmobAppId
    }

    packaging {
        jniLibs {
            keepDebugSymbols.add("**/*.so")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("debug") {
            if (isLocalPreview) {
                applicationIdSuffix = ".preview"
                manifestPlaceholders["appLabel"] = "My Expence Book Preview"
            }
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            manifestPlaceholders["admobAppId"] = releaseAdmobAppId
            isMinifyEnabled = false
            isShrinkResources = false
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.play:review:2.0.1")
}
