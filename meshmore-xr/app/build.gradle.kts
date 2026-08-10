// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// IMPORTED, not fully qualified. In a Gradle .kts the name `java` resolves to
// the Java plugin's extension accessor at every scope in this file, so
// `java.util.Properties` does not compile anywhere in it.
val keystoreProps: Properties? =
    rootProject.file("app/keystore.properties").takeIf { it.exists() }?.let { f ->
        Properties().apply { f.inputStream().use { load(it) } }
    }

android {
    namespace = "com.iotj.meshmore.xr"

    // compileSdk 36 is REQUIRED by androidx.xr.compose's alpha AAR metadata.
    // The constraint applies to the consuming module only, which is why
    // libmeshcore-android can stay at 35 and the SNS app is unaffected.
    compileSdk = 36

    defaultConfig {
        applicationId = "com.iotj.meshmore.xr"
        minSdk = 34          // Android XR baseline
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += "arm64-v8a" }   // XR devices are arm64
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    /**
     * SIGNING, from a file that is not in the repository.
     *
     * Put a `keystore.properties` next to this build file with:
     *
     *   storeFile=/absolute/path/to/meshmore.jks
     *   storePassword=...
     *   keyAlias=...
     *   keyPassword=...
     *
     * If it is absent the release build still runs and produces an UNSIGNED
     * apk, which is what happens on any machine that is not the release one —
     * a build that fails outright because a secret is missing is a build
     * nobody else can run.
     */
    signingConfigs {
        if (keystoreProps != null) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug { isMinifyEnabled = false }
        release {
            isMinifyEnabled = false
            if (keystoreProps != null) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "MeshmoreXR: no app/keystore.properties — release apk will be UNSIGNED",
                )
            }
        }
    }

    packaging {
        resources.excludes += setOf(
            "/META-INF/{AL2.0,LGPL2.1}",
            // libmeshcore brings BouncyCastle, which ships an OSGi manifest inside
            // its multi-release JAR at the same path as jspecify's. Neither is used
            // at runtime on Android; without this the APK merge fails outright.
            // Anything consuming libmeshcore from an Android app will hit this.
            "/META-INF/versions/*/OSGI-INF/**",
            "/META-INF/versions/*/module-info.class",
        )
    }
}

dependencies {
    // --- Compose ------------------------------------------------------------
    implementation(platform("androidx.compose:compose-bom:2026.05.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // --- Jetpack XR ---------------------------------------------------------
    // Three of the four core libraries reached 1.0.0-beta01 on 2026-07-15;
    // xr.compose is still alpha. These are two release waves PAST the
    // "Developer Preview 4" SDK bundle (2026-05-19) -- see design brief 1.2.
    implementation("androidx.xr.compose:compose:1.0.0-alpha16")
    implementation("androidx.xr.scenecore:scenecore:1.0.0-beta01")
    implementation("androidx.xr.arcore:arcore:1.0.0-beta01")
    implementation("androidx.xr.runtime:runtime:1.0.0-beta01")

    // --- MeshCore protocol stack (composite build, no publish step) ---------
    // Pure-Java codec/crypto arrives transitively as an `api` dependency.
    implementation("io.iotone.meshcore:libmeshcore-android")

    testImplementation("junit:junit:4.13.2")
}

// androidx.lifecycle 2.11.0 raised its floor to compileSdk 37 AND AGP 9.1+.
// AGP is pinned at 8.10.1 to match libmeshcore-android -- a composite build
// cannot sensibly load two AGP versions -- so hold lifecycle just below that
// line. Anything can drag 2.11 in transitively, hence a force rather than a
// plain version pin.
//
// Lifting this is a deliberate migration (AGP 9.x + compileSdk 37) that has to
// move libmeshcore-android too, since it is shared with the Flutter SNS app.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.lifecycle" && requested.version == "2.11.0") {
            useVersion("2.10.0")
            because("2.11.0 requires AGP 9.1+/compileSdk 37; this build is AGP 8.10.1/36")
        }
    }
}
