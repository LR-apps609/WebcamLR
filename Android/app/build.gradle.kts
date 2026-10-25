import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// App Android di WebcamLR: Kotlin, Jetpack Compose (Material 3 con i colori LR Apps), Camera2, MediaCodec.
// Niente servizi Google: funziona anche sui telefoni Huawei senza Play Store.
plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.compose")
}

android {
    namespace = "it.lrapps.webcamlr.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "it.lrapps.webcamlr.android"
        // Android 8.0: circa il 97% dei telefoni in uso, compresi Xiaomi, Huawei e Samsung degli ultimi anni.
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Per provarla senza un certificato di pubblicazione: la firma di debug di Android Studio.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":protocollo"))

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // BOM 2025.05.01: Compose 1.8.2 e Material 3 1.3.2, le stesse API con cui il codice è stato controllato
    // (Compose Multiplatform 1.8.2); runtime 1.8 come si aspetta il compilatore Compose di Kotlin 2.2. compileSdk 35.
    implementation(platform("androidx.compose:compose-bom:2025.05.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Lettura dei QR code sui fotogrammi della fotocamera: ZXing core (Apache 2.0), senza ML Kit né Play Services.
    implementation("com.google.zxing:core:3.5.3")

    // Test della logica pura (cartella `logica`): in Android Studio, tasto destro su app/src/test › Run Tests.
    testImplementation(kotlin("test-junit"))
    testImplementation("junit:junit:4.13.2")
}
