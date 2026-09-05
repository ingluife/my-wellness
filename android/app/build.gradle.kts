import java.util.Properties
import java.io.FileInputStream

// Release signing comes from android/key.properties, which is git-ignored and written by CI
// from repository secrets. Without it the release build falls back to the debug key, so a
// local `flutter build apk --release` still works for anyone who has just cloned the repo.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mywellness.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // The workout-day reminder is scheduled with java.time, which
        // flutter_local_notifications needs desugared to reach Android 8 and 9.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Its own namespace, distinct from openGym's, so both can be installed side by side.
        applicationId = "com.mywellness.app"
        // flutter_local_notifications and wakelock_plus both want 23+; the exercise library
        // and the animations do not care.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // The APK is ~150 MB of exercise media either way; shrinking the Dart-free Java
            // surface saves little and costs a slower build plus a class of release-only bugs.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // NotificationCompat/NotificationManagerCompat/NotificationChannelCompat for
    // WorkoutNotificationService. flutter_local_notifications carries its own copy, but as an
    // `implementation` dependency of a separate Gradle module it is not visible to app's own
    // Kotlin source, so this app needs its own.
    implementation("androidx.core:core-ktx:1.18.0")
}
