plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tuonome.camera_2fps_app"
    
    // ✅ FORZA SDK 34 (sovrascrive flutter.compileSdkVersion)
    compileSdk = 34
    
    // ✅ Usa NDK da Flutter (va bene)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tuonome.camera_2fps_app"
        
        // ✅ FORZA minSdk 21 (compatibilità Android 5.0+)
        minSdk = 21
        
        // ✅ FORZA targetSdk 34
        targetSdk = 34
        
        // ✅ Usa versionCode e versionName da Flutter (va bene)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
