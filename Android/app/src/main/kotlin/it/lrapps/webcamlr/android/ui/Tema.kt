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

/**
 * Colori della famiglia WebcamLR, gli stessi di Stile/Sources/Stile/Tema.swift: l'identità di LR Apps dal logo del
 * 25 ottobre. Fondo verde scuro, superfici e accenti nei toni di salvia, testo quasi bianco appena verde.
 * Il corallo del logo è il colore del tally: solo «in onda» e registrazione. Azioni e selezione nell'accento salvia
 * chiaro, con il testo scuro ([fondo]) sopra i pulsanti pieni.
 */
object Colori {
    /** La sfumatura del logo, dall'angolo in alto a sinistra a quello in basso a destra. */
    val sfumaturaChiara = Color(0xFF30453E)
    val sfumaturaScura = Color(0xFF0D1B18)

    val fondo = Color(0xFF13211D)
    val barraLaterale = Color(0xFF172824)
    val pannello = Color(0xFF1A2B26)
    val pannelloScuro = Color(0xFF15241F)
    val pannelloChiaro = Color(0xFF22352F)
    val linea = Color(0xFF2E443D)
    val lineaTenue = Color(0xFF283C36)
    val bordo = Color(0xFF3A524A)
    val testo = Color(0xFFE6EEEA)
    /** Testo secondario, in salvia. */
    val testoSecondario = Color(0xFF9DB0A7)
    val testoChiaro = Color(0xFFC9D5CF)
    val testoTenue = Color(0xFFB4C2BB)

    /** I toni di salvia dei quadratini del logo, per superfici e segni (non per il testo piccolo). */
    val salvia = Color(0xFF8FA199)
    val salviaChiara = Color(0xFFB2BFB7)
    val salviaScura = Color(0xFF627A71)
    val salviaTenue = Color(0xFFACBAB2)

    /** Accento di azioni e selezione: menta salvia chiara (7,5:1 su [pannelloChiaro]). */
    val accento = Color(0xFF9FD0B6)
    /** Accento più chiaro, per il testo di un elemento scelto. */
    val accentoChiaro = Color(0xFFB9E2CB)
    /** Fondo di un elemento scelto. */
    val accentoTenue = Color(0xFF1F3D33)

    /** I nomi di prima (come `Tema.ciano` su iPhone e Mac): lo stesso accento salvia, non più ciano. */
    val ciano get() = accento
    val cianoChiaro get() = accentoChiaro
    val cianoTenue get() = accentoTenue

    /** Il corallo del logo: solo quando il video è davvero in onda o si registra. */
    val tally = Color(0xFFE67A67)
    /** Fondo pieno della pillola «IN ONDA», con il testo bianco sopra. */
    val tallyPieno = Color(0xFFB84A3A)
    val tallyTenue = Color(0xFF3A221D)
    val tallyTesto = Color(0xFFF6B9AD)

    /** Avvisi, in un'ambra calda che sta bene con il verde. */
    val ambra = Color(0xFFE3B162)
    val ambraTenue = Color(0xFF38301E)
    val ambraTesto = Color(0xFFF0CD8C)

    /** Collegato: verde salvia, mai rosso. */
    val verde = Color(0xFF86C79C)

    /** I nove quadratini del logo, riga per riga (Strumenti/logo.svg); il centro è il corallo. */
    val celleLogo = listOf(
        listOf(Color(0xFF8FA199), Color(0xFFB2BFB7), Color(0xFF627A71)),
        listOf(Color(0xFFACBAB2), Color(0xFFE67A67), Color(0xFF768D84)),
        listOf(Color(0xFF83988F), Color(0xFF96A89F), Color(0xFF50685F)),
    )

    /** Il fondo delle schermate: dal [fondo] in alto alla [sfumaturaScura] in basso, come la presentazione dell'iPhone. */
    val sfondoSchermata: Brush get() = Brush.verticalGradient(listOf(fondo, sfumaturaScura))
}

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
