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
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SwitchDefaults
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
}

/**
 * Gli stili di testo dell'app: i nove di [StiliTesto] (Token.kt, generato) con l'interlinea di sempre, più qualche
 * variante di peso o di famiglia della stessa misura. Nessuna misura scritta qui: vengono tutte dalla tabella.
 */
object Stili {
    // L'interlinea dei titoli in Barlow Condensed e del testo in Barlow, in proporzione alla misura (com'era prima).
    // Dentro l'oggetto: Stili si inizializza da solo, senza passare per il file (che a sua volta legge Stili).
    private val interlineaTitoli = 1.08.em
    private val interlineaComandi = 1.3.em
    private val interlineaTesto = 1.35.em

    /** IN ONDA da lontano (schermo oscurato, vista pulita). */
    val statoGrande = StiliTesto.statoGrande.copy(lineHeight = interlineaTitoli)

    /** Titolo di una schermata, di un foglio o di un dialogo. */
    val titoloGrande = StiliTesto.titoloGrande.copy(lineHeight = interlineaTitoli)

    /** Titolo di un pannello o di un avviso; il marchio nell'intestazione. */
    val titolo = StiliTesto.titolo.copy(lineHeight = interlineaTitoli)

    /** Etichetta di sezione in maiuscolo («VIDEO»). */
    val sezione = StiliTesto.sezione

    /** Nome di un pulsante o di un comando. */
    val comando = StiliTesto.comando.copy(lineHeight = interlineaComandi)

    /** Testo normale. */
    val corpo = StiliTesto.corpo.copy(lineHeight = interlineaTesto)

    /** Note e spiegazioni sotto un controllo. */
    val nota = StiliTesto.nota.copy(lineHeight = interlineaTesto)

    /** Numeri tecnici: «38 ms · 1080p30». */
    val numeri = StiliTesto.numeri

    /** Il codice di conferma: IBM Plex Mono, cifre a spaziatura fissa come su iPhone, Mac e Windows. */
    val codice = StiliTesto.codice

    /** [corpo] in Barlow Medium: il nome di un computer, il testo di un avviso. */
    val corpoEvidente = corpo.copy(fontWeight = FontWeight.Medium, lineHeight = interlineaComandi)

    /** [nota] in Barlow SemiBold: un numero in un cerchio, un comando piccolo dentro una riga. */
    val notaForte = nota.copy(fontWeight = FontWeight.SemiBold, lineHeight = interlineaComandi)

    /** [numeri] in IBM Plex Mono Medium. */
    val numeriEvidenti = numeri.copy(fontWeight = FontWeight.Medium)

    /** Numeri alla misura del [corpo]: l'indirizzo scritto a mano. */
    val numeriCorpo = numeri.copy(fontSize = StiliTesto.corpo.fontSize)

    /** Etichetta di stato in maiuscolo sopra il video («● COLLEGATO»), come [sezione] alla misura del [comando]. */
    val etichetta = sezione.copy(fontSize = StiliTesto.comando.fontSize)
}

/**
 * Misure dei componenti in dp (non sono spazi né raggi, quindi non stanno nella tabella dei token). Ogni area di tocco
 * è di almeno [areaTocco], come chiede Android.
 */
object Misure {
    /** L'area di tocco minima di Android. */
    val areaTocco = 48.dp

    /** Altezza del pulsante pieno grande, in fondo alle schermate. */
    val pulsanteGrande = 54.dp

    /** Altezza del pulsante secondario a tutta larghezza. */
    val pulsanteMedio = 50.dp

    /** Il pulsante tondo: colonna dei comandi, Impostazioni e Scollega sopra il video, intestazione dei computer. */
    val tondo = 48.dp

    /** Il cerchio che si vede nelle «orecchie» accanto al foro della fotocamera; il tocco resta [tondo]. */
    val tondoOrecchie = 36.dp

    /** Le icone di Material. */
    val icona = 24.dp

    /** Le icone nei cerchi piccoli e le rotelline dentro pulsanti e avvisi. */
    val iconaPiccola = 20.dp

    /** Il punto colorato dello stato (verde collegato, corallo in onda, ambra in attesa). */
    val punto = 8.dp

    /** Altezza minima della pillola di stato; [pillolaGrande] per leggerla da 2–3 metri. */
    val pillola = 30.dp
    val pillolaGrande = 88.dp
}

/**
 * Lo schema di Material 3 dai token: campi, interruttori, dialoghi, fogli e pulsanti prendono da qui i colori della
 * famiglia senza riscriverli a ogni chiamata. I contorni dei controlli sono [Colori.contornoControllo].
 */
private val schemaScuro = darkColorScheme(
    primary = Colori.accento,
    onPrimary = Colori.fondo,
    primaryContainer = Colori.accentoTenue,
    onPrimaryContainer = Colori.accentoChiaro,
    // Snackbar: fondo pannello chiaro, testo chiaro, azione nell'accento chiaro.
    inversePrimary = Colori.accentoChiaro,
    secondary = Colori.accentoChiaro,
    onSecondary = Colori.fondo,
    // Il pulsante secondario tonale (FilledTonalButton): fondo accento tenue, testo accento chiaro.
    secondaryContainer = Colori.accentoTenue,
    onSecondaryContainer = Colori.accentoChiaro,
    tertiary = Colori.ambra,
    onTertiary = Colori.fondo,
    tertiaryContainer = Colori.ambraTenue,
    onTertiaryContainer = Colori.ambraTesto,
    background = Colori.fondo,
    onBackground = Colori.testo,
    surface = Colori.pannello,
    onSurface = Colori.testo,
    surfaceVariant = Colori.pannelloChiaro,
    onSurfaceVariant = Colori.testoSecondario,
    surfaceTint = Colori.accento,
    inverseSurface = Colori.pannelloChiaro,
    inverseOnSurface = Colori.testo,
    // Gli errori dell'interfaccia sono avvisi ambra: il corallo è riservato a «in onda».
    error = Colori.ambra,
    onError = Colori.fondo,
    errorContainer = Colori.ambraTenue,
    onErrorContainer = Colori.ambraTesto,
    outline = Colori.contornoControllo,
    outlineVariant = Colori.lineaTenue,
    scrim = Colori.sfumaturaScura,
    surfaceBright = Colori.pannelloChiaro,
    surfaceDim = Colori.fondo,
    // I gradini dei contenitori: i fogli (Low) sul fondo, i dialoghi (High) sul pannello, come prima.
    surfaceContainerLowest = Colori.fondo,
    surfaceContainerLow = Colori.fondo,
    surfaceContainer = Colori.pannello,
    surfaceContainerHigh = Colori.pannello,
    surfaceContainerHighest = Colori.pannelloChiaro,
)

/** La tipografia di Material dagli otto stili: campi, dialoghi, pulsanti e righe in Barlow, i titoli in Barlow Condensed. */
private val tipografia = Typography(
    displayLarge = Stili.statoGrande,
    displayMedium = Stili.statoGrande,
    displaySmall = Stili.statoGrande,
    headlineLarge = Stili.titoloGrande,
    headlineMedium = Stili.titoloGrande,
    headlineSmall = Stili.titoloGrande,
    titleLarge = Stili.titolo,
    titleMedium = Stili.comando,
    titleSmall = Stili.comando,
    bodyLarge = Stili.corpo,
    bodyMedium = Stili.corpo,
    bodySmall = Stili.nota,
    labelLarge = Stili.comando,
    labelMedium = Stili.sezione,
    labelSmall = Stili.numeri,
)

@Composable
fun TemaWebcamLR(contenuto: @Composable () -> Unit) {
    MaterialTheme(colorScheme = schemaScuro, typography = tipografia, content = contenuto)
}

/**
 * I colori dell'interruttore, l'unica eccezione allo schema: Material disegna il pallino e il bordo dell'interruttore
 * spento con `outline`, che oggi ([Colori.contornoControllo] = `linea`) sparirebbe sul binario. Restano quelli di
 * sempre finché la beta 4 non porta il contorno a 3:1.
 */
@Composable
fun coloriInterruttore() = SwitchDefaults.colors(
    checkedBorderColor = Colori.accento,
    uncheckedThumbColor = Colori.testoSecondario,
    uncheckedTrackColor = Colori.pannelloScuro,
    uncheckedBorderColor = Colori.bordo,
)

/** I campi di testo: i colori dello schema, con il fondo pannello (fuori da un dialogo il campo si stacca dal fondo). */
@Composable
fun coloriCampo() = OutlinedTextFieldDefaults.colors(
    focusedContainerColor = MaterialTheme.colorScheme.surface,
    unfocusedContainerColor = MaterialTheme.colorScheme.surface,
    errorContainerColor = MaterialTheme.colorScheme.surface,
)

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
