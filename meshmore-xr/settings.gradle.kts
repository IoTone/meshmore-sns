// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
}

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    // Pinned here so `wrapper` and CI see the same versions without needing
    // them in the build scripts. Matches libmeshcore-android's AGP.
    plugins {
        id("com.android.application") version "8.10.1"
        id("org.jetbrains.kotlin.android") version "2.4.10"
        id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

// The MeshCore protocol stack lives next door. Composite build so changes to
// either library are picked up with no publish step.
//
// Only libmeshcore-android is included here: it already includeBuild()s
// ../libmeshcore itself, and Gradle resolves that nested include. Adding both
// explicitly would register the same build twice.
includeBuild("../libmeshcore-android")

rootProject.name = "meshmore-xr"

include(":app")
