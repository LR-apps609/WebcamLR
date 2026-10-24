import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Protocollo WebcamLR in Kotlin puro (Documenti/Protocollo.md): nessuna dipendenza Android,
// solo java.security e javax.crypto. Lo usa l'app; i test girano su qualsiasi JVM.
plugins {
    kotlin("jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(kotlin("test-junit"))
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // InteroperabilitaTest gira solo con un ricevitore vero in ascolto: cambia la variabile, cambia il risultato.
    inputs.property("ricevitore", System.getenv("WEBCAMLR_RICEVITORE") ?: "")
    testLogging {
        events("passed", "failed", "skipped")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
