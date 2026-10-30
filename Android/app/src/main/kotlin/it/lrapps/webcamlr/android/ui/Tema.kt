package it.lrapps.webcamlr.android.ui

import android.content.Context
import android.provider.Settings
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import it.lrapps.webcamlr.android.R

/*
 * I colori della famiglia WebcamLR (`Colori.fondo`, `Colori.accento`…), con `Spazi`, `Raggi`, `Opacita`, `Veli` e
 * `StiliTesto`, stanno in Token.kt, generato da Strumenti/genera_token.py da Documenti/token.json insieme a iPhone,
 * Mac, Windows e al sito: si cambiano solo lì (tabella in Documenti/Stile.md). Qui restano il logo e il fondo delle
 * schermate, che non sono token.
 */

private val celle = listOf(
    listOf(Color(0xFF8FA199), Color(0xFFB2BFB7), Color(0xFF627A71)),
    listOf(Color(0xFFACBAB2), Color(0xFFE67A67), Color(0xFF768D84)),
    listOf(Color(0xFF83988F), Color(0xFF96A89F), Color(0xFF50685F)),
)

/** I nove quadratini del logo, riga per riga (Strumenti/logo.svg); il centro è il corallo. */
val Colori.celleLogo: List<List<Color>> get() = celle

/** Il fondo delle schermate: dal [Colori.fondo] in alto alla [Colori.sfumaturaScura] in basso, come la presentazione dell'iPhone. */
val Colori.sfondoSchermata: Brush get() = Brush.verticalGradient(listOf(fondo, sfumaturaScura))

/**
 * Barlow Condensed (titoli, etichette di stato), Barlow (testo) e IBM Plex Mono (numeri tecnici), licenza SIL Open
 * Font License (testi in assets/licenze). Gli stessi file di Stile/Sources/Stile/Caratteri.
 */
object Caratteri {
    val titoli = FontFamily(Font(R.font.barlow_condensed_bold, FontWeight.Bold))
    val etichette = FontFamily(Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold))
    val corpoFamiglia = FontFamily(
        Font(R.font.barlow_regular, FontWeight.Normal),
        Font(R.font.barlow_medium, FontWeight.Medium),
        Font(R.font.barlow_semibold, FontWeight.SemiBold),
    )
    val numeri = FontFamily(Font(R.font.ibm_plex_mono_regular, FontWeight.Normal), Font(R.font.ibm_plex_mono_medium, FontWeight.Medium))

    /** Titoli grandi, come «Scegli il computer». */
    fun titolo(dimensione: Int) = TextStyle(fontFamily = titoli, fontWeight = FontWeight.Bold, fontSize = dimensione.sp, lineHeight = (dimensione * 1.08).sp)

    /** Etichette in maiuscolo e stati, come «IN ONDA». */
    fun etichetta(dimensione: Int, spaziatura: TextUnit = 0.6.sp) =
        TextStyle(fontFamily = etichette, fontWeight = FontWeight.SemiBold, fontSize = dimensione.sp, letterSpacing = spaziatura)

    /** Testo normale in Barlow. */
    fun corpo(dimensione: Int = 16) = TextStyle(fontFamily = corpoFamiglia, fontWeight = FontWeight.Normal, fontSize = dimensione.sp, lineHeight = (dimensione * 1.35).sp)

    /** Testo in evidenza in Barlow, come il nome di un computer. */
    fun corpoEvidente(dimensione: Int = 16) = TextStyle(fontFamily = corpoFamiglia, fontWeight = FontWeight.Medium, fontSize = dimensione.sp, lineHeight = (dimensione * 1.3).sp)

    /** Testo forte in Barlow, come un pulsante. */
    fun corpoForte(dimensione: Int = 16) = TextStyle(fontFamily = corpoFamiglia, fontWeight = FontWeight.SemiBold, fontSize = dimensione.sp, lineHeight = (dimensione * 1.3).sp)

    /** Numeri tecnici: «38 ms · 1080p30». */
    fun numeri(dimensione: Int = 12) = TextStyle(fontFamily = numeri, fontWeight = FontWeight.Normal, fontSize = dimensione.sp)

    fun numeriEvidenti(dimensione: Int = 12) = TextStyle(fontFamily = numeri, fontWeight = FontWeight.Medium, fontSize = dimensione.sp)
}

private val schemaScuro = darkColorScheme(
    primary = Colori.accento,
    onPrimary = Colori.fondo,
    primaryContainer = Colori.accentoTenue,
    onPrimaryContainer = Colori.accentoChiaro,
    secondary = Colori.accentoChiaro,
    onSecondary = Colori.fondo,
    tertiary = Colori.ambra,
    background = Colori.fondo,
    onBackground = Colori.testo,
    surface = Colori.pannello,
    onSurface = Colori.testo,
    surfaceVariant = Colori.pannelloChiaro,
    onSurfaceVariant = Colori.testoSecondario,
    surfaceContainer = Colori.pannello,
    surfaceContainerHigh = Colori.pannelloChiaro,
    surfaceContainerHighest = Colori.pannelloChiaro,
    surfaceContainerLow = Colori.pannelloScuro,
    surfaceContainerLowest = Colori.fondo,
    outline = Colori.bordo,
    outlineVariant = Colori.linea,
    // Gli errori dell'interfaccia sono avvisi ambra: il corallo è riservato a «in onda».
    error = Colori.ambra,
    onError = Colori.fondo,
)

/** Tutti i testi di Material (campi, dialoghi, pulsanti di testo) in Barlow; i titoli in Barlow Condensed. */
private val tipografia: Typography = Typography().let { base ->
    base.copy(
        displayLarge = base.displayLarge.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        displayMedium = base.displayMedium.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        displaySmall = base.displaySmall.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        headlineLarge = base.headlineLarge.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        headlineMedium = base.headlineMedium.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        headlineSmall = base.headlineSmall.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold),
        titleMedium = base.titleMedium.copy(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.SemiBold),
        titleSmall = base.titleSmall.copy(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.SemiBold),
        bodyLarge = base.bodyLarge.copy(fontFamily = Caratteri.corpoFamiglia),
        bodyMedium = base.bodyMedium.copy(fontFamily = Caratteri.corpoFamiglia),
        bodySmall = base.bodySmall.copy(fontFamily = Caratteri.corpoFamiglia),
        labelLarge = base.labelLarge.copy(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.SemiBold),
        labelMedium = base.labelMedium.copy(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.Medium),
        labelSmall = base.labelSmall.copy(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.Medium),
    )
}

@Composable
fun TemaWebcamLR(contenuto: @Composable () -> Unit) {
    MaterialTheme(colorScheme = schemaScuro, typography = tipografia, content = contenuto)
}

/**
 * «Rimuovi animazioni» di Android (Accessibilità, o Opzioni sviluppatore › Scala durata animatore a 0): come
 * «Riduci movimento» dell'iPhone. Le scene stanno ferme e le pagine si scambiano in dissolvenza.
 */
fun animazioniRidotte(context: Context): Boolean =
    try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (e: Exception) {
        false
    }

@Composable
fun ricordaAnimazioniRidotte(): Boolean {
    val context = LocalContext.current
    return remember(context) { animazioniRidotte(context) }
}

/**
 * Vero se l'app è in inglese: domande frequenti e guida in inglese (come iPhone e Mac). Si legge dai testi stessi,
 * così vale anche la scelta di MainActivity (inglese per ogni lingua diversa dall'italiano), pure dopo una rotazione.
 */
@Composable
fun linguaInglese(): Boolean = stringResource(R.string.codice_lingua) == "en"
