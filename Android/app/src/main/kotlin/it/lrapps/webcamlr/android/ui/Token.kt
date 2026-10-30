// File generato da Strumenti/genera_token.py da Documenti/token.json: non modificarlo a mano.
// Valori attivi: «oggi». Descrizione e regole in Documenti/Stile.md.
package it.lrapps.webcamlr.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Colori della famiglia WebcamLR, gli stessi di Stile (Tema) e di Windows. Il corallo del logo è il colore del
 * tally: solo «in onda» e registrazione. I colori del logo e il fondo delle schermate stanno in Tema.kt.
 */
object Colori {
    /** Sfumatura del logo, angolo in alto a sinistra. */
    val sfumaturaChiara = Color(0xFF30453E)
    /** Sfumatura del logo, angolo in basso a destra; base dei veli. */
    val sfumaturaScura = Color(0xFF0D1B18)
    /** Fondo della finestra (gradino 1 delle superfici). */
    val fondo = Color(0xFF13211D)
    /** Colonne laterali (gradino 2). */
    val barraLaterale = Color(0xFF172824)
    /** Pannelli (gradino 3). */
    val pannello = Color(0xFF1A2B26)
    /** Pannello incassato. */
    val pannelloScuro = Color(0xFF15241F)
    /** Pannello rialzato (gradino 4); la superficie più chiara con testo sopra. */
    val pannelloChiaro = Color(0xFF22352F)
    /** Separatori e bordi leggeri. */
    val linea = Color(0xFF2E443D)
    /** Separatori più deboli. */
    val lineaTenue = Color(0xFF283C36)
    /** Bordi di capsule e contorni. */
    val bordo = Color(0xFF3A524A)
    /** Testo principale, quasi bianco appena verde. */
    val testo = Color(0xFFE6EEEA)
    /** Testo secondario, in salvia. */
    val testoSecondario = Color(0xFF9DB0A7)
    /** Testo chiaro. */
    val testoChiaro = Color(0xFFC9D5CF)
    /** Testo tenue. */
    val testoTenue = Color(0xFFB4C2BB)
    /** Salvia del logo, per superfici e segni (non testo piccolo). */
    val salvia = Color(0xFF8FA199)
    /** Salvia chiara del logo. */
    val salviaChiara = Color(0xFFB2BFB7)
    /** Salvia scura del logo. */
    val salviaScura = Color(0xFF627A71)
    /** Salvia tenue del logo. */
    val salviaTenue = Color(0xFFACBAB2)
    /** Azioni e selezione: menta salvia chiara. */
    val accento = Color(0xFF9FD0B6)
    /** Testo di un elemento scelto. */
    val accentoChiaro = Color(0xFFB9E2CB)
    /** Fondo di un elemento scelto. */
    val accentoTenue = Color(0xFF1F3D33)
    /** Corallo del logo: solo «in onda» e registrazione. */
    val tally = Color(0xFFE67A67)
    /** Fondo pieno della pillola IN ONDA, testo bianco sopra. */
    val tallyPieno = Color(0xFFB84A3A)
    /** Fondo tenue del tally. */
    val tallyTenue = Color(0xFF3A221D)
    /** Testo sul fondo tenue del tally. */
    val tallyTesto = Color(0xFFF6B9AD)
    /** Avvisi. */
    val ambra = Color(0xFFE3B162)
    /** Fondo tenue degli avvisi. */
    val ambraTenue = Color(0xFF38301E)
    /** Testo sul fondo tenue degli avvisi. */
    val ambraTesto = Color(0xFFF0CD8C)
    /** Collegato: verde salvia, mai rosso. */
    val verde = Color(0xFF86C79C)

    // Contorni dei controlli: nuovi nomi, oggi con il valore di `linea` (la beta 4 li porta a 3:1).
    /** Contorno di pulsanti e campi su fondo e pannello (oggi è `linea`; beta 4 ≥ 3:1). */
    val contornoControllo = Color(0xFF2E443D)
    /** Contorno dei controlli su pannelloChiaro (oggi è `linea`). */
    val contornoSuRialzato = Color(0xFF2E443D)
    /** Contorno dei controlli sopra il video (oggi è `linea`). */
    val contornoSuVideo = Color(0xFF2E443D)

    @Deprecated("Il colore non è più ciano: usa accento", ReplaceWith("accento"))
    val ciano get() = accento
    @Deprecated("Il colore non è più ciano: usa accentoChiaro", ReplaceWith("accentoChiaro"))
    val cianoChiaro get() = accentoChiaro
    @Deprecated("Il colore non è più ciano: usa accentoTenue", ReplaceWith("accentoTenue"))
    val cianoTenue get() = accentoTenue
}

/** Spazi tra gli elementi: 4 · 8 · 12 · 16 · 24 · 32 dp. */
object Spazi {
    val minimo = 4.dp
    val stretto = 8.dp
    val piccolo = 12.dp
    val medio = 16.dp
    val largo = 24.dp
    val ampio = 32.dp
}

/** Raggi degli angoli. [capsula] su un quadrato fa il cerchio: Compose limita il raggio a metà del lato corto. */
object Raggi {
    /** Chip, segni. */
    val piccolo = 6.dp
    /** Pulsanti, campi. */
    val controllo = 10.dp
    /** Pannelli, fogli, avvisi. */
    val pannello = 16.dp
    /** Pillole; su un quadrato fa il cerchio (ogni sistema limita il raggio a metà del lato corto). */
    val capsula = 999.dp
}

/** Opacità comuni. */
object Opacita {
    /** Controllo spento, su tutto e mai doppia. */
    const val spento = 0.45f
}

/** Veli sopra il video o sotto un foglio: [Colori.sfumaturaScura] con l'opacità del livello. */
object Veli {
    const val lieve = 0.6f
    const val medio = 0.8f
    const val forte = 0.92f
    val coloreLieve = Color(0x990D1B18)
    val coloreMedio = Color(0xCC0D1B18)
    val coloreForte = Color(0xEB0D1B18)
}

/** Gli otto stili di testo con nome, misure del telefono in sp (crescono con la dimensione del carattere di Android). */
object StiliTesto {
    /** IN ONDA da lontano (schermo oscurato, vista pulita). */
    val statoGrande = TextStyle(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold, fontSize = 56.sp)
    /** Titolo di una schermata o di un foglio. */
    val titoloGrande = TextStyle(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold, fontSize = 28.sp)
    /** Titolo di un pannello o di un avviso. */
    val titolo = TextStyle(fontFamily = Caratteri.titoli, fontWeight = FontWeight.Bold, fontSize = 20.sp)
    /** Etichetta di sezione. Si scrive in maiuscolo. */
    val sezione = TextStyle(fontFamily = Caratteri.etichette, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, letterSpacing = 1.1.sp)
    /** Nome di un pulsante o di un comando. */
    val comando = TextStyle(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    /** Testo normale. */
    val corpo = TextStyle(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.Normal, fontSize = 16.sp)
    /** Note e spiegazioni sotto un controllo. */
    val nota = TextStyle(fontFamily = Caratteri.corpoFamiglia, fontWeight = FontWeight.Normal, fontSize = 13.sp)
    /** Numeri tecnici: «38 ms · 1080p30». */
    val numeri = TextStyle(fontFamily = Caratteri.numeri, fontWeight = FontWeight.Normal, fontSize = 12.sp)
}
