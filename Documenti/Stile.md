# Stile · i token di WebcamLR

Un'unica tabella di token grafici (colori, caratteri, spazi, raggi, opacità, veli) per le quattro app e per il sito.
Nata nella 1.0 beta 3 «Sistema» (parte A), **a parità di aspetto**: i valori sono quelli di prima, nessun colore,
misura o raggio visibile è cambiato. La grafica nuova (direzione A «Regia pulita») arriva nella beta 4 e si accende
cambiando una riga in `token.json` (vedi «Oggi e beta 4»).

## La regola
I token si cambiano **solo** in `Documenti/token.json`, poi si rilancia `python3 Strumenti/genera_token.py`. I file
generati portano in testa «File generato … non modificarlo a mano». Prima di un commit:

```
python3 Strumenti/genera_token.py --controlla
```

esce con 1 (ed elenca i file) se un file generato non coincide con la tabella. Lo script usa solo la libreria
standard di Python 3.

## Dove finiscono i token

| Piattaforma | File generato | Cosa contiene |
| --- | --- | --- |
| iPhone e Mac | `Stile/Sources/Stile/Token.swift` | i colori come `extension Tema`; `Spazi`, `Raggi`, `Opacita`, `Veli`; `StileTesto` e `.stileTesto(_:)` |
| Windows | `Windows/WebcamLR.App/Token.xaml` | ResourceDictionary incluso in `App.xaml`: Color, SolidColorBrush, sfumature, FontFamily, misure dei testi, Thickness, CornerRadius, Double |
| Windows | `Windows/WebcamLR.App/Token.cs` | gli stessi token per il codice C# (`Token.MisuraNota`, `Token.SpazioStretto`, `Token.PaddingChip`, colori in `0xAARRGGBB` con `Token.Colore(...)`) |
| Windows | `Windows/WebcamLR.App/App.xaml` | solo il blocco tra `genera_token: inizio` e `genera_token: fine` (testo sull'accento e accento di sistema, che WinUI vuole in App.xaml) |
| Android | `Android/app/src/main/kotlin/it/lrapps/webcamlr/android/ui/Token.kt` | `Colori`, `Spazi`, `Raggi`, `Opacita`, `Veli`, `StiliTesto` |
| Android | `Android/app/src/main/res/values/colors.xml` | i quattro colori che servono alle risorse (tema della finestra, icona) |
| Sito | `Strumenti/uscita/token.css` | variabili CSS (`:root`), con le misure del telefono sotto i 600 px |
| Documenti | `Documenti/Stile.md` | le tabelle qui sotto, tra `genera_token:inizio` e `genera_token:fine` |

Restano scritti a mano, perché non sono token: `Tema.swift` (dichiara `enum Tema` e `Color(esadecimale:)`),
`Caratteri.swift` e l'oggetto `Caratteri` di `Tema.kt` (registrano i file dei caratteri), i nove colori del logo
(`LogoWebcamLR.celle`, `Colori.celleLogo`, `Strumenti/genera_icone.py`, su Windows `LogoWebcamLR.xaml`: il logo non si
tocca), gli stili dei componenti (su Windows `Stili.xaml`, fatti solo di token: vedi «Componenti su Windows») e i disegni
(scene della presentazione, segni sopra il video). Le misure delle schermate stanno sui token su tutte le piattaforme dalla
parte B della beta 3: restano a mano solo i casi elencati in «Fuori dalla scala», più sotto.

## Nomi sulle piattaforme
Il nome di riferimento è quello italiano in camelCase della tabella (`pannelloChiaro`).

| Token | Swift | Windows (XAML) | Kotlin | CSS |
| --- | --- | --- | --- | --- |
| colore | `Tema.pannelloChiaro` | pennello `PannelloChiaro`, colore `ColorePannelloChiaro` | `Colori.pannelloChiaro` | `--pannello-chiaro` |
| spazio | `Spazi.medio` | `SpazioMedio` (Double), `MargineMedio` (Thickness) | `Spazi.medio` (dp) | `--spazio-medio` |
| raggio | `Raggi.controllo` | `RaggioControllo` (CornerRadius) | `Raggi.controllo` (dp) | `--raggio-controllo` |
| opacità | `Opacita.spento` | `OpacitaSpento` | `Opacita.spento` | `--opacita-spento` |
| velo | `Veli.medio`, `Veli.coloreMedio` | `OpacitaVeloMedio`, pennello `VeloMedio` | `Veli.medio`, `Veli.coloreMedio` | `--velo-medio` |
| stile di testo | `.font(.stile(.corpo))`, `.stileTesto(.corpo)`, con un altro peso `.font(.stile(.corpo, .corpoEvidente))` | `MisuraCorpo` + FontFamily `Corpo` | `StiliTesto.corpo` | `--misura-corpo` + `--testi` |

Nomi di prima che restano validi:
- **`ciano`, `cianoChiaro`, `cianoTenue`**: i nomi di prima di `accento`, `accentoChiaro`, `accentoTenue` (il colore
  non è più ciano). Dalla parte B della beta 3 non esistono più in Swift e in Kotlin (nessuno li usava più); restano
  solo su Windows, come pennelli `Ciano`, `CianoChiaro`, `CianoTenue` (`aliasWindows` in token.json), finché
  `MainWindow.xaml` li usa.
- Windows: `Scheda` = `PannelloChiaro`; le famiglie `Titoli`, `Etichette`, `Corpo`, `CorpoEvidente`, `CorpoForte`,
  `Numeri`, `NumeriEvidenti`; `VeloEtichetta`, `SfumaturaLogo`, `SfumaturaIntestazione`.
- CSS: `--barra` = `--barra-laterale` (il nome del sito di oggi); `--titoli`, `--testi`, `--numeri` sono le pile di
  caratteri del sito.

## Componenti (iPhone e Mac)
Una sola implementazione per ruolo del catalogo, nel pacchetto Stile (`Componenti.swift`, `Qualita.swift`, `Pro.swift`).
Le app non ridisegnano pulsanti, chip o avvisi: usano questi. Tutti prendono misure, spazi, raggi e opacità dai token.

| Ruolo | Componente | Note |
| --- | --- | --- |
| Comando di regia | `ComandoRegia` (con `BarraStudio`, `SeparatoreStudio`, `EtichettaStudio`) | la barra sotto il video del Mac; acceso pieno nell'accento |
| Primario contestuale | `StilePrimario(.normale)`, `StilePrimario(.grande)` | uno per contesto; sul telefono normale a capsula ≥ 44, grande alto 54 e largo quanto la colonna |
| Secondario bordato | `StileSecondario()`, `StileSecondario(acceso:)` | contorno `contornoControllo`; `acceso` per gli interruttori a un clic (Finestra mini, Torcia, «Impostazioni» aperto); sul telefono ≥ 44. Per i `Menu`: `.superficieSecondaria()` |
| Link | `StileLink()` | accento, sottolineato al passaggio; il carattere lo sceglie chi lo usa |
| Distruttivo | `StileDistruttivo()` | oggi con l'aspetto del secondario; mai pieno, mai il più evidente |
| Chip informativo | `.chipInformativo(.video)`, `.chipInformativo(.pannello)`; `ChipQualita`, `TaccheQualita` | sopra il video su `Veli.coloreMedio` con `contornoSuVideo` |
| Pillola di stato | `PillolaStato` | misura normale 16 (`PillolaStato.misuraNormale`), da lontano `StileTesto.statoGrande.misura` |
| Pulsante tondo del telefono | `PulsanteTondo` | 48 |
| Avviso | `Avviso(testo, titolo:, icona:, tono:)` con azioni e X facoltative | `tono: .attenzione` (ambra) o `.informazione` (accento), su `pannello` al velo forte |
| Riga dei menu | `StileRigaMenu(evidenziata:)` | i menu disegnati da noi (qualità, collegamento, sfondo, elenco delle Impostazioni) |

Lo spento si dà con `.spento(_:)`: opacità `Opacita.spento` una volta sola, anche se dentro c'è un componente che da
spento la applicherebbe di suo.

### Fuori dalla scala
Restano scritti a mano, apposta: i disegni (logo, tacche, livella, griglia dei terzi, mirino del QR, radar, le scene
della presentazione), il conto alla rovescia della foto sul Mac (120), il codice di conferma (46), il titolo della
presentazione (36), il gobbo (misure scelte dall'utente), la misura normale della pillola (16), le icone SF Symbols
(`.system(size:)`), le ombre, le posizioni nel video e i margini delle zone sicure dell'iPhone.

## Oggi e beta 4
Alcuni token cambiano valore nella beta 4: le superfici a gradini (ognuna ≥ 1,15:1 sulla precedente; oggi pannello e
barra laterale sono a 1,04) e i contorni dei controlli a 3:1. In `token.json` hanno due valori, `oggi` e `beta4`; il
campo `"attivo"` sceglie quello che usano le app. Oggi vale `"oggi"`. Per la beta 4 basta `"attivo": "beta4"` e
rilanciare lo script: cambiano tutte le app e il sito insieme. `pannelloChiaro` fa da «pannello rialzato».

I tre contorni (`contornoControllo`, `contornoSuRialzato`, `contornoSuVideo`) sono nomi nuovi: oggi valgono quanto
`linea` (il bordo che i pulsanti secondari usano davvero) e nessuna schermata li usa ancora, quindi non cambia nulla.

## Caratteri: Barlow o sistema
Barlow Condensed per titoli e stati, Barlow per il testo, IBM Plex Mono per i numeri tecnici (SIL Open Font License).
**Barlow dove disegniamo noi** (finestre, pannelli, liste nostre, telefono); **carattere di sistema solo dove disegna
il sistema** (menu, barra dei menu, dialoghi e avvisi di sistema, notifiche, barra del titolo, menu dell'area di
notifica). Su Windows Barlow Medium, SemiBold e Bold sono famiglie vere (niente grassetto finto).

I nove stili (gli otto della scala più `codice`, il codice di conferma in IBM Plex Mono) hanno una misura per Mac, una per Windows e il sito, una per il telefono (iPhone e Android). Su iPhone
crescono con Dynamic Type (`relativeTo:` dello stile di sistema in tabella), su Android in `sp`, su Windows con la
scala del testo di sistema.

## Le tabelle

<!-- genera_token:inizio (tabelle scritte da Strumenti/genera_token.py da Documenti/token.json: non modificarle a mano) -->

Valori attivi: **beta 4** (`"attivo": "beta4"` in token.json). La colonna «Attivo» dice quale valore hanno davvero le app; «Oggi» e «Beta 4» sono i due valori possibili.

### Colori

| Token | Attivo | Oggi | Beta 4 | Ruolo |
| --- | --- | --- | --- | --- |
| `sfumaturaChiara` | **#30453E** (oggi) | #30453E | = | Sfumatura del logo, angolo in alto a sinistra |
| `sfumaturaScura` | **#0D1B18** (oggi) | #0D1B18 | = | Sfumatura del logo, angolo in basso a destra; base dei veli |
| `fondo` | **#13211D** (beta 4) | #13211D | #13211D | Fondo della finestra (gradino 1 delle superfici) |
| `barraLaterale` | **#1B2E28** (beta 4) | #172824 | #1B2E28 | Colonne laterali (gradino 2) |
| `pannello` | **#243A33** (beta 4) | #1A2B26 | #243A33 | Pannelli (gradino 3) |
| `pannelloScuro` | **#15241F** (oggi) | #15241F | = | Pannello incassato |
| `pannelloChiaro` (su Windows anche `Scheda`) | **#2E4740** (beta 4) | #22352F | #2E4740 | Pannello rialzato (gradino 4); la superficie più chiara con testo sopra |
| `linea` | **#2E443D** (oggi) | #2E443D | = | Separatori e bordi leggeri |
| `lineaTenue` | **#283C36** (oggi) | #283C36 | = | Separatori più deboli |
| `bordo` | **#3A524A** (oggi) | #3A524A | = | Bordi di capsule e contorni |
| `testo` | **#E6EEEA** (oggi) | #E6EEEA | = | Testo principale, quasi bianco appena verde |
| `testoSecondario` | **#9DB0A7** (oggi) | #9DB0A7 | = | Testo secondario, in salvia |
| `testoChiaro` | **#C9D5CF** (oggi) | #C9D5CF | = | Testo chiaro |
| `testoTenue` | **#B4C2BB** (oggi) | #B4C2BB | = | Testo tenue |
| `salvia` | **#8FA199** (oggi) | #8FA199 | = | Salvia del logo, per superfici e segni (non testo piccolo) |
| `salviaChiara` | **#B2BFB7** (oggi) | #B2BFB7 | = | Salvia chiara del logo |
| `salviaScura` | **#627A71** (oggi) | #627A71 | = | Salvia scura del logo |
| `salviaTenue` | **#ACBAB2** (oggi) | #ACBAB2 | = | Salvia tenue del logo |
| `accento` (su Windows anche `Ciano`) | **#9FD0B6** (oggi) | #9FD0B6 | = | Azioni e selezione: menta salvia chiara |
| `accentoChiaro` (su Windows anche `CianoChiaro`) | **#B9E2CB** (oggi) | #B9E2CB | = | Testo di un elemento scelto |
| `accentoTenue` (su Windows anche `CianoTenue`) | **#1F3D33** (oggi) | #1F3D33 | = | Fondo di un elemento scelto |
| `tally` | **#E67A67** (oggi) | #E67A67 | = | Corallo del logo: solo «in onda» e registrazione |
| `tallyPieno` | **#B84A3A** (oggi) | #B84A3A | = | Fondo pieno della pillola IN ONDA, testo bianco sopra |
| `tallyTenue` | **#3A221D** (oggi) | #3A221D | = | Fondo tenue del tally |
| `tallyTesto` | **#F6B9AD** (oggi) | #F6B9AD | = | Testo sul fondo tenue del tally |
| `ambra` | **#E3B162** (oggi) | #E3B162 | = | Avvisi |
| `ambraTenue` | **#38301E** (oggi) | #38301E | = | Fondo tenue degli avvisi |
| `ambraTesto` | **#F0CD8C** (oggi) | #F0CD8C | = | Testo sul fondo tenue degli avvisi |
| `verde` | **#86C79C** (oggi) | #86C79C | = | Collegato: verde salvia, mai rosso |

29 colori di oggi. Contorni dei controlli (nomi nuovi, già usati dai componenti: oggi valgono quanto `linea`, la beta 4 li porta a 3:1):

| Token | Attivo | Oggi | Beta 4 | Ruolo |
| --- | --- | --- | --- | --- |
| `contornoControllo` | **#6E877D** (beta 4) | #2E443D | #6E877D | Contorno di pulsanti e campi su fondo e pannello (oggi è `linea`; beta 4 ≥ 3:1) |
| `contornoSuRialzato` | **#7A9389** (beta 4) | #2E443D | #7A9389 | Contorno dei controlli su pannelloChiaro (oggi è `linea`) |
| `contornoSuVideo` | **#C9D5CF** (beta 4) | #2E443D | #C9D5CF | Contorno dei controlli sopra il video (oggi è `linea`) |

### Tipografia

| Stile | Carattere | Peso | Mac | Windows e sito | Telefono | Dynamic Type | Uso |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `statoGrande` | Barlow Condensed | 700 | 56 | 56 | 56 | `largeTitle` | IN ONDA da lontano (schermo oscurato, vista pulita) |
| `titoloGrande` | Barlow Condensed | 700 | 28 | 28 | 28 | `title` | Titolo di una schermata o di un foglio |
| `titolo` | Barlow Condensed | 700 | 20 | 20 | 20 | `title3` | Titolo di un pannello o di un avviso |
| `sezione` | Barlow Condensed | 600, maiuscolo, spaziatura 1,1 | 13 | 13 | 13 | `caption` | Etichetta di sezione |
| `comando` | Barlow | 600 | 14 | 14 | 16 | `callout` | Nome di un pulsante o di un comando |
| `corpo` | Barlow | 400 | 13 | 14 | 16 | `body` | Testo normale |
| `nota` | Barlow | 400 | 12 | 12 | 13 | `footnote` | Note e spiegazioni sotto un controllo |
| `numeri` | IBM Plex Mono | 400 | 12 | 12 | 12 | `caption` | Numeri tecnici: «38 ms · 1080p30» |
| `codice` | IBM Plex Mono | 500 | 46 | 46 | 46 | `largeTitle` | Codice di conferma: cifre a spaziatura fissa, uguali su ogni piattaforma |

### Spazi, raggi, opacità, veli

| Gruppo | Nome | Valore | Uso |
| --- | --- | --- | --- |
| Spazi | `minimo` | 4 | |
| Spazi | `stretto` | 8 | |
| Spazi | `piccolo` | 12 | |
| Spazi | `medio` | 16 | |
| Spazi | `largo` | 24 | |
| Spazi | `ampio` | 32 | |
| Raggi | `piccolo` | 6 | chip, segni |
| Raggi | `controllo` | 10 | pulsanti, campi |
| Raggi | `pannello` | 16 | pannelli, fogli, avvisi |
| Raggi | `capsula` | 999 | pillole; su un quadrato fa il cerchio (ogni sistema limita il raggio a metà del lato corto) |
| Opacità | `spento` | 0,45 | controllo spento, su tutto e mai doppia |
| Veli | `lieve` | 0,6 | `sfumaturaScura` a questa opacità |
| Veli | `medio` | 0,8 | `sfumaturaScura` a questa opacità |
| Veli | `forte` | 0,92 | `sfumaturaScura` a questa opacità |

<!-- genera_token:fine -->

## Fuori dalla tabella comune
In `token.json`, sezione `soloWindows`, stanno le risorse che esistono solo su Windows, con i colori presi dalla
tabella dove possibile: `VeloEtichetta` (sfumaturaScura al 78 %, nella beta 4 diventerà `veloMedio`), le sfumature
`SfumaturaLogo` e `SfumaturaIntestazione`, il testo sull'accento (`TextOnAccentFillColor…`) e la scala
`SystemAccentColor` (tre gradi chiari e tre scuri dell'accento), più i veli e i bianchi/neri che servono solo lì
(`BordoEtichetta`, `VeloScuro`, `VeloImpostazioni`, `VeloConto`, `VeloAvviso`, `VeloScritta`, `BordoPro`, `Bianco`,
`Nero`). `risorseAndroid` elenca i colori copiati in `colors.xml`.

`soloWindows.misure` (beta 3, parte B) tiene le misure di oggi dell'app Windows che non stanno sulla scala comune, a
parità di aspetto: misure di testo (`MisuraTestoPiccolo` 12,5, `MisuraRilievo` 15, `MisuraTitoloPannello` 22…), spazi
(`SpazioMinuscolo` 2, `SpazioFine` 6, `SpazioMezzo` 10, `SpazioComodo` 14, `SpazioSezioni` 20), raggi (`RaggioMinimo` 4,
`RaggioStretto` 8, `RaggioScheda` 12…), spaziature delle lettere e gli spessori (Thickness) di margini e padding, ognuno
con il suo uso. Finiscono in Token.xaml e Token.cs; nella beta 4 si riportano sulla scala comune e la lista si accorcia.

## Componenti su Windows
`Windows/WebcamLR.App/Stili.xaml` (incluso in App.xaml dopo Token.xaml) ha uno stile per ruolo del catalogo, fatto solo
di token: `PulsantePrimario` (AccentButtonStyle), `PulsanteSecondario` (bordo `ContornoControllo`), `PulsanteDistruttivo`,
`PulsanteLink` (HyperlinkButton), `PulsanteDiscreto` (icone e pulsanti senza fondo), `ComandoRegia` (Button e
ToggleButton sotto il video, con `IconaComandoRegia` e `TestoComandoRegia`), `VoceMenu`, `ChipInformativo` (Button) e
`ChipInformativoFisso` (Border), `PillolaStato` con `TestoPillola`, `EtichettaSezione`, `Avviso` (InfoBar) e `TestoBase`
(Barlow, base dello stile implicito dei TextBlock). Il logo è un solo componente, `LogoWebcamLR.xaml` (`Fondo`:
Sfumatura, Nessuno, Velo). Nelle schermate niente misure, raggi, spazi, opacità o colori scritti a mano: si usa una
risorsa (`{StaticResource …}`) o `Token.…` nel codice.

## Il sito (fase 6)
Il sito sta sul ramo `main`, non su `round-2`: per questo il CSS si genera in `Strumenti/uscita/token.css`. Nella
fase 6 «Sito e store», dopo aver allineato il `main` locale a GitHub:
1. copiare `Strumenti/uscita/token.css` in `Sito/token.css` e caricarlo in ogni pagina prima di `stile.css`;
2. togliere da `stile.css` il blocco `:root` con i colori e le pile di caratteri (stessi valori e nomi, `--barra`
   compresa);
3. portare a poco a poco misure, raggi e spazi del sito sulle variabili (`--misura-…`, `--raggio-…`, `--spazio-…`);
4. aggiungere `Sito/token.css` ai file che `genera_token.py --controlla` confronta (oggi solo `Strumenti/uscita/`).
