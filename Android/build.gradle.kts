// Il plugin Android (AGP) va caricato qui, insieme a quello Kotlin, ma solo se c'è l'app (cioè l'Android SDK,
// vedi settings.gradle.kts): così `gradle :protocollo:test` non scarica nemmeno AGP.
buildscript {
    if (findProject(":app") != null) {
        repositories {
            google()
            mavenCentral()
        }
        dependencies {
            classpath("com.android.tools.build:gradle:8.9.1")
        }
    }
}

plugins {
    kotlin("jvm") version "2.2.21" apply false
    kotlin("android") version "2.2.21" apply false
    kotlin("plugin.compose") version "2.2.21" apply false
}
