package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.TipoCollegamento

/*
 * Il catalogo dei componenti del telefono (beta 3 «Sistema»), uno per ruolo: pulsante pieno, secondario, link,
 * pulsante tondo, interruttore, scelta, avviso, pillola di stato. Colori da Token.kt, misure da Spazi, Raggi,
 * Opacita, Veli, Stili e Misure: le schermate non scrivono numeri propri.
 */

/** Il logo (Strumenti/logo.svg): fondo verde scuro in diagonale, griglia 3×3 di quadratini salvia, il centro corallo. */
@Composable
fun LogoWebcamLR(lato: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(lato)) { disegnaLogo(this, size.minDimension, Offset.Zero) }
}

/** Il logo dentro un disegno: `lato` in pixel, a partire da `origine`. */
fun disegnaLogo(scope: androidx.compose.ui.graphics.drawscope.DrawScope, lato: Float, origine: Offset) = with(scope) {
    drawRoundRect(
        Brush.linearGradient(listOf(Colori.sfumaturaChiara, Colori.sfumaturaScura), start = origine, end = origine + Offset(lato, lato)),
        topLeft = origine, size = Size(lato, lato), cornerRadius = CornerRadius(lato * 0.22f),
    )
    // Misure in centesimi del lato: quadratini da 18, passo 23, margine 18.
    val cella = lato * 0.18f
    for (riga in 0 until 3) for (colonna in 0 until 3) {
        drawRoundRect(
            Colori.celleLogo[riga][colonna],
            topLeft = origine + Offset(lato * (0.18f + colonna * 0.23f), lato * (0.18f + riga * 0.23f)),
            size = Size(cella, cella),
            cornerRadius = CornerRadius(lato * 0.04f),
        )
    }
}

/** «WebcamLR» con «LR» nell'accento salvia: il corallo resta solo per «in onda» e la registrazione. */
@Composable
fun MarchioWebcamLR(stile: TextStyle = Stili.titolo) {
    Text(
        buildAnnotatedString {
            append("Webcam")
            withStyle(SpanStyle(color = Colori.accento)) { append("LR") }
        },
        style = stile,
        color = Colori.testo,
        modifier = Modifier.semantics { contentDescription = "WebcamLR" },
    )
}

/** Etichetta di sezione in maiuscolo, come «VIDEO». È un'intestazione per TalkBack. */
@Composable
fun EtichettaSezione(testo: String, modifier: Modifier = Modifier) {
    Text(
        testo.uppercase(),
        style = Stili.sezione,
        color = Colori.testoSecondario,
        modifier = modifier.padding(top = Spazi.largo, bottom = Spazi.stretto, start = Spazi.minimo).semantics { heading() },
    )
}

/** Il segno «PRO» accanto a un comando di WebcamLR Pro: testo scuro sull'accento salvia, mai corallo. */
@Composable
fun SegnoPro(grande: Boolean = false, modifier: Modifier = Modifier) {
    val descrizione = stringResource(R.string.pro_funzione)
    Text(
        "PRO",
        style = if (grande) Stili.etichetta else Stili.sezione,
        color = Colori.fondo,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(Raggi.piccolo))
            .background(Colori.accento)
            .padding(horizontal = if (grande) Spazi.stretto else Spazi.minimo, vertical = if (grande) Spazi.minimo else 0.dp)
            .semantics { contentDescription = descrizione },
    )
}

fun coloreQualita(qualita: QualitaCollegamento) = when (qualita) {
    QualitaCollegamento.OTTIMA -> Colori.verde
    QualitaCollegamento.BUONA -> Colori.accentoChiaro
    QualitaCollegamento.DEBOLE -> Colori.ambraTesto
}

/** «Ottimo», «Buono», «Debole» nella lingua dell'app (il protocollo ha solo l'italiano). */
@Composable
fun testoQualita(qualita: QualitaCollegamento): String = stringResource(
    when (qualita) {
        QualitaCollegamento.OTTIMA -> R.string.qualita_ottima
        QualitaCollegamento.BUONA -> R.string.qualita_buona
        QualitaCollegamento.DEBOLE -> R.string.qualita_debole
    },
)

@Composable
fun testoTipoCollegamento(tipo: TipoCollegamento): String = stringResource(
    when (tipo) {
        TipoCollegamento.WIFI -> R.string.collegamento_wifi
        // Su Android il cavo è il tethering USB: la rete sul cavo.
        TipoCollegamento.CAVO_USB -> R.string.collegamento_cavo_usb
        TipoCollegamento.WIFI_DIRETTO -> R.string.collegamento_wifi_diretto
        TipoCollegamento.CAVO_DI_RETE -> R.string.collegamento_cavo_rete
        TipoCollegamento.HOTSPOT -> R.string.collegamento_hotspot
    },
)

/** Il consiglio quando il collegamento è debole e ne esiste uno migliore; null sul cavo. */
@Composable
fun consiglioSeDebole(tipo: TipoCollegamento): String? = when (tipo) {
    TipoCollegamento.WIFI, TipoCollegamento.HOTSPOT -> stringResource(R.string.consiglio_cavo)
    TipoCollegamento.WIFI_DIRETTO -> stringResource(R.string.consiglio_cavo_o_rete)
    TipoCollegamento.CAVO_USB, TipoCollegamento.CAVO_DI_RETE -> null
}

// MARK: Pulsante tondo

/**
 * Il pulsante tondo del telefono, uno solo per la colonna dei comandi, Impostazioni e Scollega sopra il video, le icone
 * degli avvisi ridotti, l'intestazione dei computer e il lettore QR. Acceso: pieno nell'accento con l'icona scura (mai
 * corallo); spento: [Colori.pannelloChiaro], o il velo scuro se `sopraIlVideo`. `diametro` è il cerchio che si vede
 * (più piccolo nelle orecchie): l'area di tocco resta sempre di almeno [Misure.tondo]. `suggerimento`: cosa fa il tocco,
 * per TalkBack, se non basta l'etichetta.
 * Non `abilitato` (es. Specchia con la posteriore) è sbiadito ma resta toccabile: il tocco ([toccoSpento]) dice perché
 * e TalkBack legge il motivo ([motivoSpento]) dopo lo stato ([stato], «Acceso»/«Spento»).
 */
@Composable
fun PulsanteTondo(
    icona: ImageVector,
    etichetta: String,
    modifier: Modifier = Modifier,
    attivo: Boolean = false,
    sopraIlVideo: Boolean = false,
    diametro: Dp = Misure.tondo,
    coloreIcona: Color? = null,
    suggerimento: String? = null,
    abilitato: Boolean = true,
    stato: String? = null,
    motivoSpento: String? = null,
    toccoSpento: () -> Unit = {},
    azione: () -> Unit,
) {
    val fondo = when {
        attivo -> Colori.accento
        sopraIlVideo -> Veli.coloreMedio
        else -> Colori.pannelloChiaro
    }
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(maxOf(diametro, Misure.tondo))
            .clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = suggerimento ?: etichetta, onClick = if (abilitato) azione else toccoSpento)
            .semantics {
                contentDescription = etichetta
                val descrizione = if (!abilitato && motivoSpento != null) listOfNotNull(stato, motivoSpento).joinToString(". ") else stato
                if (descrizione != null) stateDescription = descrizione
            },
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(diametro).alpha(if (abilitato) 1f else Opacita.spento).clip(CircleShape).background(fondo),
        ) {
            Icon(
                icona, contentDescription = null,
                tint = coloreIcona ?: if (attivo) Colori.fondo else Colori.testo,
                modifier = Modifier.size(if (diametro < Misure.tondo) Misure.iconaPiccola else Misure.icona),
            )
        }
    }
}

// MARK: Pulsanti con testo

/** Il colore del pulsante pieno: accento di serie, ambra per risolvere un problema. */
enum class TonoPulsante { ACCENTO, AMBRA }

/**
 * Il pulsante pieno, il primario del contesto: Material 3 `Button` con il testo scuro. Due misure: grande, a tutta
 * larghezza e alto [Misure.pulsanteGrande] con gli angoli [Raggi.pannello] («Avanti», «Inquadra il QR code»); piccolo, a
 * capsula alto quanto il testo con il tocco di 48 dp («Riprova ora», «Apri Impostazioni»). Non `abilitato`: sbiadito a
 * [Opacita.spento]; `inCorso`: la rotellina al posto dell'icona e niente tocchi, senza sbiadire.
 */
@Composable
fun PulsantePieno(
    testo: String,
    modifier: Modifier = Modifier,
    piccolo: Boolean = false,
    tono: TonoPulsante = TonoPulsante.ACCENTO,
    icona: ImageVector? = null,
    abilitato: Boolean = true,
    inCorso: Boolean = false,
    azione: () -> Unit,
) {
    val fondo = when (tono) {
        TonoPulsante.ACCENTO -> Colori.accento
        TonoPulsante.AMBRA -> Colori.ambra
    }
    Button(
        onClick = azione,
        enabled = abilitato && !inCorso,
        shape = RoundedCornerShape(if (piccolo) Raggi.capsula else Raggi.pannello),
        colors = ButtonDefaults.buttonColors(
            containerColor = fondo, contentColor = Colori.fondo,
            disabledContainerColor = fondo, disabledContentColor = Colori.fondo,
        ),
        contentPadding = PaddingValues(horizontal = Spazi.medio, vertical = if (piccolo) Spazi.minimo else Spazi.stretto),
        modifier = (if (piccolo) modifier else modifier.fillMaxWidth().heightIn(min = Misure.pulsanteGrande))
            .alpha(if (abilitato) 1f else Opacita.spento),
    ) {
        if (inCorso) {
            CircularProgressIndicator(color = Colori.fondo, strokeWidth = 2.dp, modifier = Modifier.size(Misure.iconaPiccola))
            Spacer(Modifier.width(Spazi.stretto))
        } else if (icona != null) {
            Icon(icona, contentDescription = null)
            Spacer(Modifier.width(Spazi.stretto))
        }
        Text(
            testo, style = Stili.comando, textAlign = TextAlign.Center,
            maxLines = if (piccolo) 1 else Int.MAX_VALUE, overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Il pulsante secondario a tutta larghezza, alto [Misure.pulsanteMedio]. Di serie tonale (Material 3
 * `FilledTonalButton`: fondo accento tenue, testo accento chiaro, bordo salvia scura), «Mandami il link»; `bordato`:
 * `OutlinedButton` sul pannello con il contorno dei controlli, «Usa il cavo USB». `compatto`: a capsula, largo e alto
 * quanto il testo (tocco di 48 dp), come «Salta» della presentazione.
 */
@Composable
fun PulsanteSecondario(
    testo: String,
    modifier: Modifier = Modifier,
    icona: ImageVector? = null,
    bordato: Boolean = false,
    compatto: Boolean = false,
    azione: () -> Unit,
) {
    val forma = RoundedCornerShape(if (compatto) Raggi.capsula else Raggi.pannello)
    val misura = if (compatto) modifier else modifier.fillMaxWidth().heightIn(min = Misure.pulsanteMedio)
    val margini = PaddingValues(horizontal = Spazi.medio, vertical = Spazi.stretto)
    val contenuto: @Composable RowScope.() -> Unit = {
        if (icona != null) {
            Icon(icona, contentDescription = null)
            Spacer(Modifier.width(Spazi.stretto))
        }
        Text(testo, style = Stili.comando, textAlign = TextAlign.Center, maxLines = if (compatto) 1 else Int.MAX_VALUE)
    }
    if (bordato) {
        OutlinedButton(
            onClick = azione, modifier = misura, shape = forma, contentPadding = margini,
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Colori.pannello, contentColor = Colori.testo),
            content = contenuto,
        )
    } else {
        FilledTonalButton(
            onClick = azione, modifier = misura, shape = forma, contentPadding = margini,
            border = BorderStroke(1.dp, Colori.salviaScura),
            content = contenuto,
        )
    }
}

/**
 * Il link: Material 3 `TextButton`, testo nell'accento chiaro. `tenue`: grigio salvia, per «Annulla» nei dialoghi e le
 * strade di riserva come «Collega a mano».
 */
@Composable
fun PulsanteLink(
    testo: String,
    modifier: Modifier = Modifier,
    tenue: Boolean = false,
    azione: () -> Unit,
) {
    TextButton(
        onClick = azione,
        modifier = modifier,
        colors = ButtonDefaults.textButtonColors(contentColor = if (tenue) Colori.testoSecondario else Colori.accentoChiaro),
    ) {
        Text(testo, style = Stili.comando, textAlign = TextAlign.Center)
    }
}

// MARK: Righe delle liste

/** Le righe delle liste (Material 3 `ListItem`) sul fondo del [Gruppo]: trasparenti, con i colori della famiglia. */
@Composable
private fun coloriRiga(icona: Color = Colori.accento) = ListItemDefaults.colors(
    containerColor = Color.Transparent,
    headlineColor = Colori.testo,
    supportingColor = Colori.testoSecondario,
    leadingIconColor = icona,
    trailingIconColor = Colori.testoSecondario,
)

/**
 * L'interruttore: Material 3 `ListItem` con lo `Switch`; tutta la riga si tocca ed è un interruttore per TalkBack.
 * `soloPro`: fa parte di WebcamLR Pro; senza Pro si vede attenuato con il segno «PRO» e un tocco apre la pagina Pro
 * invece di cambiarlo.
 */
@Composable
fun RigaInterruttore(
    testo: String,
    valore: Boolean,
    icona: ImageVector? = null,
    soloPro: Boolean = false,
    apriPro: () -> Unit = {},
    cambia: (Boolean) -> Unit,
) {
    val bloccato = soloPro && !Pro.attivo()
    val descrizioneBloccato = stringResource(R.string.pro_funzione)
    ListItem(
        headlineContent = { Text(testo, modifier = Modifier.alpha(if (bloccato) Opacita.spento else 1f)) },
        leadingContent = icona?.let { { Icon(it, contentDescription = null, modifier = Modifier.alpha(if (bloccato) Opacita.spento else 1f)) } },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
                if (bloccato) SegnoPro()
                Switch(checked = valore, onCheckedChange = null, enabled = !bloccato, colors = coloriInterruttore())
            }
        },
        colors = coloriRiga(),
        modifier = Modifier.fillMaxWidth().then(
            if (bloccato) {
                Modifier.clickable(role = Role.Button, onClickLabel = descrizioneBloccato, onClick = apriPro)
            } else {
                Modifier.toggleable(value = valore, role = Role.Switch, onValueChange = cambia)
            },
        ),
    )
}

/**
 * La scelta tra poche voci, una per riga: Material 3 `ListItem` con il `RadioButton` («Automatico», «Wi-Fi», «Cavo
 * USB»). Tutta la riga si tocca ed è un pulsante di scelta per TalkBack.
 */
@Composable
fun RigaScelta(testo: String, scelta: Boolean, scegli: () -> Unit) {
    ListItem(
        headlineContent = { Text(testo, color = if (scelta) Colori.accentoChiaro else Colori.testo) },
        leadingContent = { RadioButton(selected = scelta, onClick = null) },
        colors = coloriRiga(),
        modifier = Modifier.fillMaxWidth().selectable(selected = scelta, role = Role.RadioButton, onClick = scegli),
    )
}

/** Una riga che apre una pagina o un foglio: `ListItem` con la freccia; `nota` sotto il nome dice cosa succede. */
@Composable
fun RigaLink(testo: String, icona: ImageVector? = null, valore: String? = null, pro: Boolean = false, nota: String? = null, azione: () -> Unit) {
    ListItem(
        headlineContent = { Text(testo) },
        supportingContent = nota?.let { { Text(it, style = Stili.nota) } },
        leadingContent = icona?.let { { Icon(it, contentDescription = null) } },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
                if (pro) SegnoPro()
                if (valore != null) Text(valore, style = Stili.numeri, color = Colori.testoSecondario)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
            }
        },
        colors = coloriRiga(),
        modifier = Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = azione),
    )
}

/** Titolo e valore, come i numeri dei «Dettagli». */
@Composable
fun RigaValore(titolo: String, valore: String) {
    ListItem(
        headlineContent = { Text(titolo) },
        trailingContent = { Text(valore, style = Stili.numeri, color = Colori.testoChiaro, textAlign = TextAlign.End) },
        colors = coloriRiga(),
        modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
    )
}

// MARK: Riquadri

/** Un gruppo di righe su sfondo pannello, come le sezioni delle impostazioni di sistema. */
@Composable
fun Gruppo(contenuto: @Composable ColumnScope.() -> Unit) {
    val forma = RoundedCornerShape(Raggi.pannello)
    Column(
        Modifier.fillMaxWidth().clip(forma).background(Colori.pannello).border(1.dp, Colori.lineaTenue, forma),
        content = contenuto,
    )
}

/** Un riquadro di contenuto: sfondo pannello, bordo sottile, angoli arrotondati. */
@Composable
fun Scheda(
    modifier: Modifier = Modifier,
    sfondo: Color = Colori.pannello,
    bordo: Color? = Colori.linea,
    contenuto: @Composable ColumnScope.() -> Unit,
) {
    val forma = RoundedCornerShape(Raggi.pannello)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(forma)
            .background(sfondo)
            .then(if (bordo != null) Modifier.border(BorderStroke(1.dp, bordo), forma) else Modifier)
            .padding(Spazi.medio),
        content = contenuto,
    )
}

/** Una nota sotto un gruppo. */
@Composable
fun NotaSotto(testo: String) {
    Text(testo, style = Stili.nota, color = Colori.testoSecondario, modifier = Modifier.fillMaxWidth().padding(horizontal = Spazi.minimo, vertical = Spazi.stretto))
}

// MARK: Avviso

/**
 * L'avviso sopra il video, uno per tutti: un'icona (o la rotellina se `attesa`), il `titolo` se c'è e il testo, su
 * un velo scuro; `attesa` in ambra (la riconnessione). `chiudi`: un tocco lo chiude. `azione`: un pulsante, sotto il
 * testo o, con `azioneALato`, a destra. TalkBack legge l'avviso quando compare (in attesa solo il titolo, non i
 * secondi che cambiano); il pulsante resta un elemento a sé.
 */
@Composable
fun Avviso(
    testo: String,
    modifier: Modifier = Modifier,
    titolo: String? = null,
    icona: ImageVector? = null,
    coloreIcona: Color = Colori.accentoChiaro,
    attesa: Boolean = false,
    stileTesto: TextStyle = if (titolo != null) Stili.nota else Stili.corpoEvidente,
    chiudi: (() -> Unit)? = null,
    azioneALato: Boolean = false,
    azione: (@Composable () -> Unit)? = null,
) {
    val suggerimento = stringResource(R.string.tocca_per_chiudere)
    val coloreTitolo = if (attesa) Colori.ambraTesto else Colori.testo
    val coloreTesto = when {
        attesa -> Colori.ambraTesto
        titolo != null -> Colori.testoSecondario
        else -> Colori.testo
    }
    Column(
        verticalArrangement = Arrangement.spacedBy(Spazi.stretto),
        modifier = modifier
            .widthIn(max = 420.dp)
            .clip(RoundedCornerShape(Raggi.pannello))
            .background(if (attesa) Colori.ambraTenue else Veli.coloreForte)
            .then(if (chiudi != null) Modifier.clickable(onClickLabel = suggerimento, onClick = chiudi) else Modifier)
            .then(if (attesa) Modifier else Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite })
            .padding(horizontal = Spazi.medio, vertical = Spazi.piccolo),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
            if (attesa) {
                CircularProgressIndicator(color = Colori.ambraTesto, strokeWidth = 2.dp, modifier = Modifier.size(Misure.iconaPiccola))
            } else if (icona != null) {
                Icon(icona, contentDescription = null, tint = coloreIcona)
            }
            Column(Modifier.weight(1f, fill = azioneALato)) {
                if (titolo != null) {
                    Text(
                        titolo, style = Stili.comando, color = coloreTitolo,
                        modifier = if (attesa) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier,
                    )
                }
                Text(testo, style = stileTesto, color = coloreTesto)
            }
            if (azioneALato && azione != null) azione()
        }
        if (!azioneALato && azione != null) {
            Box(Modifier.padding(start = Misure.icona + Spazi.piccolo)) { azione() }
        }
    }
}

// MARK: Pillola di stato

/** I due toni della [PillolaStato] che servono «da lontano». */
enum class TonoPillola {
    /** Un'app usa il video: corallo pieno ([Colori.tallyPieno]) e testo bianco (5,2:1). */
    IN_ONDA,

    /** Il video è in pausa: l'ambra degli stati d'attesa, mai il corallo. */
    PAUSA,
}

/** Le misure della [PillolaStato]: di serie, più piccola nelle orecchie se non ci sta, grande da 2–3 metri. */
enum class MisuraPillola { PICCOLA, NORMALE, GRANDE }

/**
 * La pillola di stato, lo stesso disegno di `PillolaStato` di Stile (iPhone e Mac): punto, etichetta in maiuscolo,
 * capsula piena. NORMALE: [Stili.etichetta]; PICCOLA: [Stili.sezione]; GRANDE: [Stili.statoGrande], per leggere «IN
 * ONDA» da 2–3 metri (schermo oscurato e vista pulita). Grande, l'etichetta non cresce oltre con il carattere di
 * sistema: è già enorme e deve restare su una riga. `misuraTesto` dice se il testo non ci sta.
 */
@Composable
fun PillolaStato(
    testo: String,
    tono: TonoPillola,
    modifier: Modifier = Modifier,
    misura: MisuraPillola = MisuraPillola.NORMALE,
    misuraTesto: (TextLayoutResult) -> Unit = {},
) {
    val grande = misura == MisuraPillola.GRANDE
    val base = when (misura) {
        MisuraPillola.PICCOLA -> Stili.sezione
        MisuraPillola.NORMALE -> Stili.etichetta
        MisuraPillola.GRANDE -> Stili.statoGrande
    }
    // Spazi, punto e spaziatura delle lettere crescono con l'etichetta (×3,5 per la grande).
    val scala = maxOf(1f, base.fontSize.value / Stili.etichetta.fontSize.value)
    val fondo = if (tono == TonoPillola.IN_ONDA) Colori.tallyPieno else Colori.ambraTenue
    val colore = if (tono == TonoPillola.IN_ONDA) Color.White else Colori.ambraTesto
    val punto = if (tono == TonoPillola.IN_ONDA) Color.White else Colori.ambra
    val spaziata = base.copy(letterSpacing = Stili.sezione.letterSpacing * scala)
    val stile = if (grande) spaziata.copy(fontSize = with(LocalDensity.current) { base.fontSize.value.dp.toSp() }) else spaziata
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spazi.stretto * scala),
        modifier = modifier
            .heightIn(min = if (grande) Misure.pillolaGrande else Misure.pillola)
            .clip(RoundedCornerShape(Raggi.capsula))
            .background(fondo)
            .padding(horizontal = Spazi.piccolo * scala),
    ) {
        Box(Modifier.size(Misure.punto * scala).clip(CircleShape).background(punto))
        Text(testo.uppercase(), style = stile, color = colore, maxLines = 1, softWrap = false, onTextLayout = misuraTesto)
    }
}
