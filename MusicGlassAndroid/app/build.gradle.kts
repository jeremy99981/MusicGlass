import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.musicglass.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.musicglass.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 6
        versionName = "0.0.6"

        buildConfigField("String", "GITHUB_REPO", "\"jeremy99981/MusicGlass\"")
    }

    signingConfigs {
        create("release") {
            val properties = Properties()
            val propertiesFile = rootProject.file("keystore.properties")
            if (propertiesFile.exists()) {
                propertiesFile.inputStream().use { properties.load(it) }
            }

            // Priority: keystore.properties -> Environment Variables -> Default Debug Key (fallback for local builds)
            val path = properties.getProperty("storeFile") 
                ?: System.getenv("RELEASE_STORE_FILE")
            
            storeFile = if (path != null) file(path) else file(System.getProperty("user.home") + "/.android/debug.keystore")
            
            storePassword = properties.getProperty("storePassword")
                ?: System.getenv("RELEASE_STORE_PASSWORD")
                ?: "android"
            
            keyAlias = properties.getProperty("keyAlias")
                ?: System.getenv("RELEASE_KEY_ALIAS")
                ?: "androiddebugkey"
            
            keyPassword = properties.getProperty("keyPassword")
                ?: System.getenv("RELEASE_KEY_PASSWORD")
                ?: "android"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Rename the output APK to a stable name (MusicGlass-0.0.3.apk)
    applicationVariants.all {
        val variantVersionName = versionName
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "MusicGlass-${variantVersionName}.apk"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.2")
    implementation("androidx.activity:activity-compose:1.8.1")
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    
    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    
    // ExoPlayer for Audio Playback
    implementation("androidx.media3:media3-exoplayer:1.2.0")
    implementation("androidx.media3:media3-session:1.2.0")
    implementation("androidx.media3:media3-datasource:1.2.0")
    implementation("androidx.media3:media3-database:1.2.0")

    // Image loading
    implementation("io.coil-kt:coil-compose:2.5.0")
    
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    
    // Navigation & Icons
    implementation("androidx.navigation:navigation-compose:2.7.5")
    implementation("androidx.compose.material:material-icons-extended")
}
