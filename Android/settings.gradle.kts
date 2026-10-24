// WebcamLR per Android: protocollo (Kotlin puro, si prova ovunque) e app.
// L'app si include solo se c'è l'Android SDK (Android Studio lo installa da solo e scrive local.properties):
// così `gradle :protocollo:test` funziona anche su un computer senza SDK.

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

fun sdkPresente(): Boolean {
    val locale = file("local.properties")
    if (locale.exists()) {
        val proprieta = java.util.Properties()
        locale.inputStream().use { proprieta.load(it) }
        val cartella = proprieta.getProperty("sdk.dir")
        if (cartella != null && file(cartella).isDirectory) return true
    }
    return listOf("ANDROID_HOME", "ANDROID_SDK_ROOT").any { nome ->
        System.getenv(nome)?.let { file(it).isDirectory } == true
    }
}

if (sdkPresente()) {
    include(":app")
} else {
    logger.lifecycle("WebcamLR: Android SDK non trovato, costruisco solo :protocollo")
}
