// WebcamLR per Android: protocollo (Kotlin puro, si prova ovunque) e app (serve l'Android SDK).

pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Il repository di Google solo per i pacchetti Android: tutto il resto viene da Maven Central.
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google\\.android.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "WebcamLR"

include(":protocollo")

// L'app si include sempre: in Android Studio il primo sync deve vedere :app anche quando local.properties
// non esiste ancora (Studio lo scrive solo dopo). Per provare solo il protocollo su un computer senza Android SDK
// (per esempio il Linux dove lavora Claude): `gradle -PsoloProtocollo :protocollo:test`,
// oppure la variabile d'ambiente WEBCAMLR_SOLO_PROTOCOLLO=1.
fun attivo(valore: String?): Boolean = valore != null && valore.trim().lowercase() !in setOf("false", "0", "no")

val soloProtocollo = attivo(providers.gradleProperty("soloProtocollo").orNull) ||
    attivo(providers.environmentVariable("WEBCAMLR_SOLO_PROTOCOLLO").orNull)

if (soloProtocollo) {
    logger.lifecycle("WebcamLR: solo :protocollo (senza l'app Android)")
} else {
    include(":app")
    // Solo un suggerimento: se l'SDK manca davvero, il plugin Android si ferma con «SDK location not found».
    val sdkDichiarato = file("local.properties").exists() ||
        listOf("ANDROID_HOME", "ANDROID_SDK_ROOT").any { providers.environmentVariable(it).isPresent }
    if (!sdkDichiarato) {
        logger.lifecycle("WebcamLR: nessun Android SDK dichiarato; per provare solo il protocollo usa -PsoloProtocollo")
    }
}
