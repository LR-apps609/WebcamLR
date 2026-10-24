// Il plugin Kotlin si carica una volta sola qui, per tutti i moduli.
// Il plugin Android (AGP) sta solo in app/build.gradle.kts: senza SDK non si scarica nemmeno.
plugins {
    kotlin("jvm") version "2.2.21" apply false
    kotlin("android") version "2.2.21" apply false
    kotlin("plugin.compose") version "2.2.21" apply false
}
