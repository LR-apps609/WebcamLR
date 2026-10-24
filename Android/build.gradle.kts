// Il plugin Android (AGP) va caricato qui, nello stesso classloader del plugin Kotlin, ma solo se c'è l'app
// (cioè senza -PsoloProtocollo, vedi settings.gradle.kts): così `gradle -PsoloProtocollo :protocollo:test`
// non scarica nemmeno AGP. Versioni compatibili tra loro (tabelle di Google e JetBrains): AGP 8.9.1, Gradle 8.14.3, Kotlin 2.2.21, JDK 17 o 21.
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
