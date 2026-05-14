plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

configurations.all {
    exclude(group = "com.google.android.play")
    exclude(module = "play-core")
}

android {
    namespace = "com.simplelyrics.simple_lyrics"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.simplelyrics.simple_lyrics"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // F-Droid: The build server will handle signing
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        // F-Droid: Exclude Play Core classes from the APK
        exclude("com/google/android/play/**")
    }
}

flutter {
    source = "../.."
}

val createReleaseDesugarDexDir by tasks.registering {
    val desugarDexDir = layout.buildDirectory.dir(
        "intermediates/external_file_lib_dex_archives/release/desugarReleaseFileDependencies"
    )
    outputs.dir(desugarDexDir)

    doLast {
        desugarDexDir.get().asFile.mkdirs()
    }
}

tasks.matching { it.name == "mergeExtDexRelease" }.configureEach {
    dependsOn(createReleaseDesugarDexDir)
}
