package it.lrapps.webcamlr.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import it.lrapps.webcamlr.android.R

/**
 * Colori della famiglia LR Apps, gli stessi di Stile/Sources/Stile/Tema.swift (iPhone e Mac) e di App.xaml (Windows).
 * Il rosso tally solo per «in onda» e registrazione; azioni e selezione in ciano.
 */
object Colori {
    val fondo = Color(0xFF0F1413)
    val barraLaterale = Color(0xFF141B1A)
    val pannello = Color(0xFF1B2321)
    val pannelloScuro = Color(0xFF16201F)
    val pannelloChiaro = Color(0xFF232D2A)
    val linea = Color(0xFF2F3A37)
    val lineaTenue = Color(0xFF2A3431)
    val bordo = Color(0xFF3C4844)
    val testo = Color(0xFFE3E8E5)
    val testoSecondario = Color(0xFF97A39F)
    val testoChiaro = Color(0xFFC2CCC8)
    val testoTenue = Color(0xFFB3BDB9)

    /** Azioni e selezione. */
    val ciano = Color(0xFF6CBCC4)
    val cianoChiaro = Color(0xFF8FD0D6)
    val cianoTenue = Color(0xFF1D3436)

    /** Solo quando il video è davvero in onda o si registra. */
    val tally = Color(0xFFEF5A4C)
    val tallyPieno = Color(0xFFC8372D)
    val tallyTenue = Color(0xFF3A1916)
    val tallyTesto = Color(0xFFFFB4AB)

    /** Avvisi. */
    val ambra = Color(0xFFE2A54B)
    val ambraTenue = Color(0xFF3A2E1A)
    val ambraTesto = Color(0xFFF0C27A)

    /** Collegato. */
    val verde = Color(0xFF6FC28C)

    val logo = Color(0xFF26302D)
}

/**
 * Barlow Condensed (titoli, etichette di stato) e IBM Plex Mono (numeri tecnici), licenza SIL Open Font License
 * (testi in assets/licenze). Gli stessi file di Stile/Sources/Stile/Caratteri.
 */
object Caratteri {
    val titoli = FontFamily(Font(R.font.barlow_condensed_bold, FontWeight.Bold))
    val etichette = FontFamily(Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold))
    val numeri = FontFamily(Font(R.font.ibm_plex_mono_regular, FontWeight.Normal), Font(R.font.ibm_plex_mono_medium, FontWeight.Medium))

    /** Titoli grandi, come «Scegli il computer». */
    fun titolo(dimensione: Int) = TextStyle(fontFamily = titoli, fontWeight = FontWeight.Bold, fontSize = dimensione.sp, lineHeight = (dimensione * 1.05).sp)

    /** Etichette in maiuscolo e stati, come «IN ONDA». */
    fun etichetta(dimensione: Int) = TextStyle(fontFamily = etichette, fontWeight = FontWeight.SemiBold, fontSize = dimensione.sp)

    /** Numeri tecnici: «38 ms · 1080p30». */
    fun numeri(dimensione: Int = 12) = TextStyle(fontFamily = numeri, fontWeight = FontWeight.Normal, fontSize = dimensione.sp)

    fun numeriEvidenti(dimensione: Int = 12) = TextStyle(fontFamily = numeri, fontWeight = FontWeight.Medium, fontSize = dimensione.sp)
}

private val schemaScuro = darkColorScheme(
    primary = Colori.ciano,
    onPrimary = Colori.fondo,
    primaryContainer = Colori.cianoTenue,
    onPrimaryContainer = Colori.cianoChiaro,
    secondary = Colori.cianoChiaro,
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
    // Gli errori dell'interfaccia sono avvisi ambra: il rosso è riservato a «in onda».
    error = Colori.ambra,
    onError = Colori.fondo,
)

@Composable
fun TemaWebcamLR(contenuto: @Composable () -> Unit) {
    MaterialTheme(colorScheme = schemaScuro, typography = Typography(), content = contenuto)
}
