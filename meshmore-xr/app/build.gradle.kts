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

// THE VERSION, IN ONE PLACE, BUMPED BY HAND ON PURPOSE.
//
// Operator's instruction, 2026-08-12: move the minor with the changes. Four
// separate builds went onto the glasses in one afternoon all calling themselves
// 0.1.0, and "is that the one you just installed?" cost a device cycle to
// answer every time.
//
//   BUILD  moves on EVERY build that goes onto a device. This is the one that
//          answers "is that the one you just installed?", which is asked
//          several times an afternoon, and it is cheap because it means
//          nothing else.
//   MINOR  moves for a real step in what the app is, not for each change that
//          lands. Corrected 2026-08-12: the first cut moved the minor per
//          change and the minor is not what a device test is asking about.
//   PATCH  for a fix on top of a minor already installed somewhere.
//   MAJOR  stays 0 until launch.
//
// BUILD RESETS TO 0 ON A MINOR BUMP, and versionCode is derived so it stays
// monotonic across both: an installer refuses a downgrade, and hand-maintained
// codes drift out of order exactly when several builds are being flashed in a
// hurry.
val verMajor = 0
val verMinor = 3
val verPatch = 0
val verBuild = 2

android {
    namespace = "com.iotj.meshmore.xr"

    // compileSdk 36 is REQUIRED by androidx.xr.compose's alpha AAR metadata.
    // The constraint applies to the consuming module only, which is why
    // libmeshcore-android can stay at 35 and the SNS app is unaffected.
    compileSdk = 36

    defaultConfig {
        // WHEN THIS APK WAS BUILT, for the splash stamp.
        //
        // STILL EARNS ITS PLACE now that the version moves. The version answers
        // "which change is this"; the timestamp answers "is this the compile I
        // just ran", and during an afternoon of fixes at one minor those are
        // different questions. Both go under the wordmark.
        buildConfigField("long", "BUILD_TIME", "${System.currentTimeMillis()}L")

        applicationId = "com.iotj.meshmore.xr"
        minSdk = 34          // Android XR baseline
        targetSdk = 35
        // 0.3.0 build 1 -> 3001. The name's own digits, shifted up two places,
        // with the build in the last two: readable back to the version it came
        // from, and it still climbs when only the build moves. 100 builds under
        // a minor is more than any minor has ever needed here.
        versionCode =
            (verMajor * 1000 + verMinor * 10 + verPatch) * 100 + verBuild
        versionName = "$verMajor.$verMinor.$verPatch"
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
        debug {
            isMinifyEnabled = false
            // SAYS SO ON THE SPLASH, AND SAYS WHICH BUILD. A stamp reading
            // "v0.3.0" is indistinguishable from the release of the same name,
            // and from the four other debug builds of that same minor that went
            // onto the glasses the same afternoon. The build number is the part
            // a device test actually reads.
            versionNameSuffix = "-debug.$verBuild"
        }
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
