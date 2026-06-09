plugins {
    id("com.android.application")
    id("kotlin-android")
    // Google Services – version comes from settings.gradle.kts
    id("com.google.gms.google-services")
    // Flutter must be last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ELT_EMP.as_f"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.ELT_EMP.as_f"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = 12
        versionName = "ELT_12.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ---------- Firebase ----------
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")
    // --------------------------------
}