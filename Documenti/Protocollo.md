# Protocollo WebcamLR · versione 2

Il protocollo è l'unica cosa che le app condividono. Lo parlano tre implementazioni:

- Swift: `Protocollo/` (pacchetto usato da iPhone e Mac)
- C#: `Windows/WebcamLR.Protocollo/`
- Kotlin: `Android/protocollo/` (app Android)

Ogni modifica a questo file va riportata in tutte le implementazioni, con i loro test.

## Ruoli

- **Computer** (Mac o Windows): riceve il video. Si annuncia in rete e resta in ascolto.
- **Telefono** (iPhone o Android): cattura e invia. Cerca i computer e si collega.

## Scoperta

- Il computer pubblica il servizio Bonjour/mDNS `_webcamlr._tcp`, porta TCP **52740** (se occupata, una qualsiasi: la porta vera viaggia nell'annuncio).
- Nome del servizio: il nome del computer (es. «MacBook Pro di Ledion»).
- Record TXT: `v=2` (versione del protocollo), `p=mac` oppure `p=windows`.
- QR code, per le reti dove Bonjour non passa: `webcamlr://collega?h=<indirizzi>&p=<porta>&n=<nome>&v=2&k=<impronta>&g=<gettone>`
  - `h`: indirizzi IPv4 del computer separati da virgole, il più probabile per primo (Wi-Fi, poi cavo)
  - `p`: porta TCP; `n`: nome del computer (codificato per URL); `v`: versione del protocollo
  - esempio: `webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=2&k=…&g=…`
  - Lo stesso indirizzo si può scrivere a mano sul telefono: `192.168.1.20` (porta 52740) oppure `192.168.1.20:52741`.

## Connessione

Una sola connessione TCP per sessione, con `TCP_NODELAY` attivo. Controllo, video e audio viaggiano nella stessa connessione, distinti dal tipo di pacchetto. Se in futuro servirà, il video potrà passare su UDP senza cambiare i messaggi di controllo.

## Pacchetto

Ogni pacchetto ha un'intestazione di 6 byte seguita dal contenuto:

| Byte | Campo | Note |
| --- | --- | --- |
| 0 | tipo | 1 = controllo, 2 = video, 3 = audio, 4 = immagine |
| 1 | flag | dipende dal tipo |
| 2–5 | lunghezza | lunghezza del contenuto, intero senza segno a 32 bit, big-endian |

- Lunghezza massima del contenuto: 16 MiB. Oltre, la connessione si chiude.
- Un tipo sconosciuto chiude la connessione: è un errore di versione. Per questo i tipi nuovi si mandano solo a chi dichiara di conoscerli (il tipo 4 solo a un telefono con `capacita.immagini`).

### Tipo 1 · controllo

Contenuto: un oggetto JSON in UTF-8, con il campo `tipo`. Flag sempre 0. Un messaggio con `tipo` sconosciuto si ignora: così le versioni nuove possono aggiungere messaggi senza rompere quelle vecchie.

### Tipo 2 · video

Contenuto: 8 byte di timestamp (microsecondi, orologio monotono del telefono, big-endian) seguiti da un'unità H.264 o HEVC in formato Annex B (con i codici di inizio `00 00 00 01`).

Flag:

- bit 0: fotogramma chiave
- bit 1: contiene i parametri del codec (SPS/PPS, e VPS per HEVC)

Ogni fotogramma chiave porta con sé i parametri del codec, così il computer può partire da qualsiasi fotogramma chiave.

### Tipo 3 · audio

Contenuto: 8 byte di timestamp seguiti da **un** pacchetto AAC-LC grezzo (una «access unit», senza intestazione ADTS). Flag sempre 0 (in chiaro; cifrato `0x80` come ogni pacchetto). Dettagli in *Audio* più sotto.

### Tipo 4 · immagine (dal 27 ottobre)

Solo computer → telefono, e solo se il telefono ha mandato `capacita.immagini: true`. Contenuto: 1 byte `uso` seguito dai byte di un file **JPEG o PNG**. Flag sempre 0 (cifrato `0x80` come ogni pacchetto). Dettagli in *Sfondi e logo dal computer* più sotto.

- `uso`: 1 = sfondo personale, 2 = logo del sottopancia. Un `uso` sconosciuto si scarta (la connessione resta).
- Il file è al massimo **8 MiB** (8 388 608 byte); un pacchetto senza file o con un file più grande si scarta.
- **Impronta** di un'immagine: i primi 16 caratteri esadecimali minuscoli dello SHA-256 dei byte del file (senza il byte `uso`). Esempio: i byte ASCII di `WebcamLR` hanno impronta `45fd1ed0012afd8b`.

## Messaggi di controllo

Nomi dei campi in italiano, `camelCase`. I valori enumerati sono stringhe minuscole con il trattino.

| `tipo` | Direzione | Campi | Significato |
| --- | --- | --- | --- |
| `ciao` | telefono → computer | `versione`, `nome`, `piattaforma`, `versioneApp` | Primo messaggio, subito dopo la connessione |
| `benvenuto` | computer → telefono | `versione`, `nome`, `piattaforma` | Risposta a `ciao`: il computer accetta |
| `formato` | entrambe | `codec`, `larghezza`, `altezza`, `fps` | Dal computer: richiesta. Dal telefono: il formato effettivo che sta inviando |
| `stato` | telefono → computer | `batteria`, `inCarica`, `temperatura`, `obiettivo`; facoltativi: gli effetti attuali (come in `comando`, da `filtro` ad `audio`), `pausa`, `gobbo`, `specchia`, i comandi della fotocamera attuali (`zoom`, `torcia`, `esposizione`, `bianco`, `iso`, `tempo`), `collegamento`, `immagineSfondo`, `immaginePersonale`, `logo`, `sfocaturaSistema`, `luceSistema`, `calore` | Ogni 5 secondi e a ogni cambiamento |
| `ping` | computer → telefono | `t` | Ogni secondo; `t` = orologio del computer in µs |
| `pong` | telefono → computer | `t`, `telefono` | Risposta immediata: `t` copiato, `telefono` = orologio del telefono in µs |
| `latenza` | computer → telefono | `ms` | Ogni secondo: la latenza misurata dal computer, da mostrare anche sul telefono |
| `capacita` | telefono → computer | `obiettivi`, `zoomMassimo`, `torcia`, `isoMinimo`, `isoMassimo`; facoltativi: `filtri`, `sfondo`, `pelle`, `inquadratura`, `luceVolto`, `scritta`, `doppiaVista`, `postura`, `gobbo`, `audio`, `formati`, `specchia`, `pro`, `sceltaCollegamento`, `formatiPro`, `sfondiPronti`, `immagini`, `calore`, `effettiSulComputer` | Dopo `benvenuto`, a ogni cambio di obiettivo e a ogni cambio di stato dell'acquisto: cosa il computer può comandare |
| `in-onda` | computer → telefono | `attivo`, `app` (facoltativo), `selezionato` (facoltativo) | Un'app sta usando la webcam virtuale: il telefono mostra il rosso «IN ONDA» (regola dei colori della bozza). `selezionato`: vedi *Più telefoni: la prospettiva* |
| `usa-prospettiva` | telefono → computer | — | Il telefono chiede di andare nella webcam (vedi *Più telefoni: la prospettiva*) |
| `anteprima` | computer → telefono | `visibile` | La finestra del computer mostra il video (vedi *Pausa intelligente*) |
| `comando` | computer → telefono | tutti facoltativi: `obiettivo`, `zoom`, `torcia`, `esposizione`, `bianco`, `fuoco`, `iso`, `tempo`; effetti: `filtro`, `regolazioni`, `sfondo`, `intensitaSfondo`, `pelle`, `inquadratura`, `luceVolto`, `scritta`, `doppiaVista`, `postura`, `calore`; `audio`; `specchia`; `collegamento`; `immagineSfondo`, `togliLogo`; `effettiSulComputer` | Comandi della fotocamera e degli effetti dal computer; si applicano solo i campi presenti |
| `effetti` | computer → telefono | `specchia`, `sfondo`, `luceVolto` | Lo stato degli effetti fatti dal computer, per i pulsanti del telefono (vedi *Effetti sul computer*) |
| `chiedi-effetto` | telefono → computer | tutti facoltativi: `specchia`, `sfondo`, `luceVolto` | Un tocco su un pulsante del telefono: il computer applica e risponde con `effetti` (vedi *Effetti sul computer*) |
| `gobbo` | computer → telefono | tutti facoltativi: `testo`, `velocita`, `attivo`, `dimensione`, `posizione` | Il gobbo sul telefono (vedi *Gobbo*); si applicano solo i campi presenti |
| `formato-audio` | telefono → computer | `codec`, `frequenza`, `canali`, `configurazione` | Prima del primo pacchetto audio e a ogni cambiamento (vedi *Audio*) |
| `arrivederci` | entrambe | — | Chiusura volontaria, prima di chiudere la connessione |

Valori:

- `piattaforma`: `iphone`, `android`, `mac`, `windows`
- `codec`: `h264`, `hevc`
- `temperatura`: `normale`, `calda`, `molto-calda`, `critica` (gli stessi livelli di iOS)
- `batteria`: da 0 a 100, oppure -1 se non nota
- `obiettivo`: testo libero, per ora `grandangolo`, `principale`, `tele`, `frontale`
- `obiettivi`: elenco degli obiettivi di quel telefono, con gli stessi nomi
- `zoom`, `zoomMassimo`: fattore dentro l'obiettivo scelto, da 1 in su
- `torcia`: vero o falso (in `capacita`: se l'obiettivo attuale ha la torcia)
- `esposizione`: compensazione in stop, da -2 a +2 (0 = automatica pura)
- `bianco`: temperatura in kelvin da 2500 a 7500, oppure 0 per il bilanciamento automatico
- `fuoco`: `continuo` (automatico che segue la scena)
- `iso`: sensibilità manuale, entro `isoMinimo`–`isoMassimo`; 0 = automatica
- `tempo`: tempo di posa manuale come denominatore (60 = 1/60 di secondo); 0 = automatico. Con `iso` e `tempo` entrambi a 0 si torna all'esposizione automatica. Il telefono non supera mai la durata di un fotogramma: un tempo più lungo diventa il tempo senza bande più lungo che sta nel fotogramma (luci a 50 Hz: a 30 fps 1/50, a 60 fps 1/100; a 60 Hz: 1/30, 1/60), e i fotogrammi al secondo non cambiano. In `stato.tempo` il telefono manda il valore richiesto. Il computer propone tempi multipli di 1/100 s (1/25, 1/50, 1/100), che con le luci a 50 Hz non fanno bande

Tutti i campi aggiunti dopo la prima versione 2 (effetti, `pausa`, `gobbo`, `formati`, `formatiPro`, `audio`, `specchia`, `pro`, `collegamento`, `sceltaCollegamento`, `in-onda.selezionato`, il messaggio `usa-prospettiva`, i comandi della fotocamera in `stato`, i messaggi `anteprima`, `gobbo`, `formato-audio`, `immagineSfondo`, `togliLogo`, `immaginePersonale`, `logo`, `sfondiPronti`, `immagini`, `sfocaturaSistema`, `luceSistema`, `calore`, `effettiSulComputer`, i messaggi `effetti` e `chiedi-effetto`) sono **facoltativi**: chi non li conosce li ignora, chi li aspetta e non li riceve fa come se l'altro non li sapesse fare. I campi a `null` non si scrivono mai: per «togliere» qualcosa si manda un valore esplicito (es. la scritta con il nome vuoto). Un valore enumerato sconosciuto non è mai un errore: vedi *Valori sconosciuti*.

Quando lo stesso telefono (stesso `nome` nel `ciao`) si ricollega, il computer gli rimanda in un solo `comando` zoom, torcia, esposizione, bianco, `iso` e `tempo` che sta mostrando: la sessione sul telefono può essere nuova e ripartita in automatico. Un telefono diverso parte con i comandi del computer azzerati.

**Comandi della fotocamera in `stato` (dalla 1.14).** Zoom, torcia ed esposizione si cambiano anche sul telefono (pizzico, cambio di obiettivo, controlli manuali), e il telefono stesso li cambia da solo (la torcia si spegne passando alla frontale, lo zoom torna a 1 cambiando obiettivo). Per questo il telefono manda in `stato` i valori **attuali** di `zoom`, `torcia`, `esposizione`, `bianco`, `iso` e `tempo`, con gli stessi significati di `comando`, ogni 5 secondi e subito a ogni cambiamento (per lo zoom basta alla fine del pizzico). Il computer allinea i suoi controlli a questi valori. Un telefono vecchio non li manda: allora il computer, a ogni cambio di `stato.obiettivo`, rimette lo zoom a 1 e la torcia spenta.

Esempio:

```json
{"tipo":"ciao","versione":1,"nome":"iPhone di Ledion","piattaforma":"iphone","versioneApp":"0.1"}
{"tipo":"comando","esposizione":0.3,"bianco":4300}
{"tipo":"comando","iso":400,"tempo":50}
```

## Valori sconosciuti

Le versioni nuove possono aggiungere messaggi, campi e valori. Chi non li conosce **non chiude la sessione**:

- `tipo` sconosciuto: il messaggio si ignora.
- Campo sconosciuto: si ignora; gli altri campi del messaggio valgono.
- Valore enumerato sconosciuto: il messaggio si legge lo stesso, con questi valori al posto di quello sconosciuto:
  - `temperatura` → `normale`
  - `codec` (in `formato`) → `h264`, il codec che tutti sanno fare; il telefono risponde comunque con il `formato` vero
  - `piattaforma` → «sconosciuta» (nel codice `sconosciuta`; si mostra un nome generico e non si manda mai)
  - `obiettivo`, `obiettivi`, `fuoco`: testo libero, un nome nuovo si mostra com'è (o si ignora, se non si sa usare)
  - `filtro` → `naturale`; `sfondo` → `nessuno`; `pausa` → una pausa qualsiasi; `dimensione` → `media`
  - `immagineSfondo` → il primo degli `sfondiPronti` (anche `personale` quando il telefono non ha un'immagine personale)
  - `uso` di un pacchetto immagine (tipo 4) sconosciuto: il pacchetto si scarta
  - `codec` in `formato-audio` diverso da `aac-lc`: il computer non riproduce quell'audio
  - `comando.collegamento` → `automatico`; in `stato.collegamento`: `attivo` e `tipo` sconosciuti si mostrano come «Collegato» (o la strada si salta nel menu), `preferenza` sconosciuta come `automatico`
- Messaggio che non si riesce a leggere (JSON non valido, campo obbligatorio mancante o del tipo sbagliato) **dopo** la `prova`: si salta solo quel messaggio. Prima (la `stretta`, la `prova`) qualsiasi errore chiude la connessione, come un pacchetto di tipo sconosciuto o un pacchetto cifrato che non torna.

## Specchio (dalla 1.14)

Uno stato solo, di proprietà del **telefono**: «Specchia» gira da sinistra a destra **il video inviato**, cioè quello che vedono Zoom, Meet e ogni altra app (e quello registrato). Le due anteprime, sul telefono e sul computer, mostrano quello stesso video: nessuno dei due lati specchia di nuovo per conto suo.

- `comando.specchia` (computer → telefono): vero/falso, «specchia» o «raddrizza». Il telefono lo applica **dal vivo**, senza fermare il video.
- `stato.specchia` (telefono → computer): lo specchio attuale, **l'unica fonte di verità**. Il telefono manda subito uno `stato` quando cambia, da qualunque lato sia partito (pulsante sul telefono o `comando` dal computer). Il computer mostra il suo pulsante acceso o spento secondo l'ultimo `stato.specchia`, non secondo quello che ha chiesto.
- `capacita.specchia`: il telefono sa specchiare dal vivo su comando. Assente o falso = il computer non mostra il pulsante.
- Lo specchio resta salvato sul telefono, come gli effetti: al ricollegamento il computer non lo rimanda, lo legge dal primo `stato`.
- Il sottopancia (`scritta`) si disegna dopo lo specchio: si legge sempre dritto.

```json
{"tipo":"comando","specchia":true}
{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","specchia":true,"zoom":1.5,"torcia":false,"esposizione":-0.5,"bianco":0,"iso":0,"tempo":0}
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"specchia":true}
```

## WebcamLR Pro

Il Pro si compra **sull'iPhone** (acquisto in-app, una volta sola, senza account) e sblocca anche il computer **tramite il telefono collegato**. Il telefono è l'unica fonte di verità: il computer non compra, non verifica ricevute e non salva nulla, legge solo il campo.

| Campo | Messaggio | Tipo | Significato |
| --- | --- | --- | --- |
| `pro` | `capacita` (telefono → computer) | vero/falso, facoltativo | Vero = WebcamLR Pro è sbloccato su questo telefono (acquisto proprio o In famiglia). Falso o **assente** = versione gratuita (un telefono vecchio non lo manda e vale come gratis) |
| `formatiPro` | `capacita` (telefono → computer) | elenco come `formati`, facoltativo | Solo gratis: i formati **in più** rispetto a `formati` che l'obiettivo attuale saprebbe fare con il Pro (es. 1080p 60, 4K). Con il Pro non si manda (è già tutto in `formati`) |

- Il telefono manda di nuovo `capacita` **appena cambia lo stato dell'acquisto** (acquisto, ripristino, rimborso, fine della condivisione In famiglia), oltre che dopo `benvenuto` e al cambio di obiettivo.
- Gratis, il telefono **limita da solo** quello che fa: `capacita.formati` arriva al massimo a 1280×720 a 30 fps, un `formato` più alto riceve in risposta il `formato` vero (720p a 30), e i comandi solo Pro (`filtro` diverso da `naturale`, `regolazioni`, `sfondo` = `sostituito` con qualsiasi `immagineSfondo`, `pelle`, `inquadratura`, `scritta`, `doppiaVista`, `iso`, `tempo`, `bianco` diverso da 0) si ignorano. Anche il pacchetto immagine (tipo 4, sfondo personale o logo) si scarta senza Pro: lo `stato` non cambia. `togliLogo` vale sempre. Lo `stato` successivo porta i valori veri, così il computer si riallinea. Se il Pro sparisce (rimborso), il telefono spegne gli effetti solo Pro e lo dice nello `stato`.
- Restano gratis: 720p 30 fps, Wi-Fi e USB, `specchia`, `sfondo` = `sfocato` (con `intensitaSfondo`), `luceVolto`, `calore`, `audio`, `zoom`, `torcia`, `esposizione`, `postura`, il collegamento sicuro. Nessuna filigrana.
- Gratis, il telefono manda anche `capacita.formatiPro`, così computer e telefono mostrano le **stesse** qualità: il computer mostra `formati` normali e `formatiPro` disattivati con il segno «PRO». Se `formatiPro` manca (telefono vecchio) il computer mostra il suo elenco fisso di qualità Pro (1080p 30 e 60).
- Il computer usa `pro` solo per l'interfaccia: mostra i comandi solo Pro con il segno «PRO», disattivati, con l'invito a sbloccare dall'iPhone. Anche le funzioni solo del computer (profili, foto e registrazione, gobbo, secondo telefono, schermata d'attesa personalizzata) seguono il `pro` del telefono «nella webcam».

```json
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"specchia":true,"pro":true}
{"tipo":"capacita","obiettivi":["principale"],"zoomMassimo":5,"torcia":true,"pro":false,"formati":[{"larghezza":1280,"altezza":720,"fpsMassimo":30}],"formatiPro":[{"larghezza":1920,"altezza":1080,"fpsMassimo":60},{"larghezza":3840,"altezza":2160,"fpsMassimo":30}]}
```

## Video: 60 fps e 4K

`formato` porta larghezza, altezza e fps liberi: il computer può chiedere anche **1920×1080 a 60** e **3840×2160 a 30 o 60**. Il telefono risponde con il `formato` che invia davvero: se non ce la fa scende (prima gli fps, poi la risoluzione) e lo dice. Per non chiedere a vuoto, il computer guarda `capacita.formati`: per l'obiettivo attuale, le risoluzioni che il telefono sa codificare con i fotogrammi al secondo massimi.

- `formati`: elenco di `{"larghezza":1920,"altezza":1080,"fpsMassimo":60}`; assente = il telefono non lo dice (si chiede e si guarda la risposta)
- `formatiPro`: stessa forma; solo gratis, i formati in più che servirebbe il Pro per avere (vedi «WebcamLR Pro»)
- Con il 4K conviene `hevc`. Il bitrate base sale in proporzione ai pixel e agli fps (vedi `AdattamentoRete`).
- Dalla 1.14 il computer chiede il 4K solo a 30 fps e in `hevc` (se il telefono non lo sa fare risponde con il formato vero); il formato di partenza è 1920×1080 a 30.

## Effetti (pacchetto funzioni)

Il telefono fa tutto il lavoro: filtri, sfondo, ritocco, inquadratura, scritta e doppia vista sono già nel video che arriva. Il computer comanda con `comando` e mostra lo stato. Gli stessi effetti si possono cambiare sul telefono: il telefono manda subito uno `stato` con i valori nuovi, così l'interfaccia del computer resta allineata. Un telefono che sa fare gli effetti manda **sempre** in `stato` tutti quelli che dichiara in `capacita`.

Gli effetti restano salvati sul telefono: al ricollegamento il computer **non** li rimanda, li legge dal primo `stato` (i comandi della fotocamera invece sì, come sopra).

| Campo (`comando` e `stato`) | Tipo | Valori | In `capacita` |
| --- | --- | --- | --- |
| `filtro` | testo | uno dei filtri qui sotto; `naturale` = nessun filtro | `filtri`: elenco degli identificativi disponibili, nell'ordine in cui mostrarli |
| `regolazioni` | oggetto | `luminosita`, `contrasto`, `saturazione`, `nitidezza`: ognuno da -1 a 1, 0 = neutro; in `comando` si applicano solo quelli presenti | sempre, se c'è `filtri` |
| `sfondo` | testo | `nessuno`, `sfocato`, `sostituito` (l'immagine di `immagineSfondo`) | `sfondo`: vero/falso |
| `immagineSfondo` | testo | con `sfondo` = `sostituito`: l'id di uno sfondo pronto, oppure `personale` (vedi *Sfondi e logo dal computer*) | `sfondiPronti` |
| `intensitaSfondo` | numero | da 0 a 1: quanto sfocare, o quanto è netto il bordo dello sfondo sostituito | con `sfondo` |
| `pelle` | numero | ritocco della pelle, da 0 (spento) a 1 | `pelle` |
| `inquadratura` | vero/falso | inquadratura automatica: segue il volto con lo zoom digitale | `inquadratura` |
| `luceVolto` | vero/falso | esposizione con priorità al volto | `luceVolto` |
| `scritta` | oggetto | sottopancia `{"nome":"…","ruolo":"…"}` (`ruolo` facoltativo); **nome vuoto = nessuna scritta** | `scritta` |
| `doppiaVista` | vero/falso | volto e scrivania insieme, con due obiettivi | `doppiaVista` (serve la multicamera) |
| `postura` | vero/falso | promemoria della postura, mostrati solo sul telefono | `postura` |
| `calore` | numero | calore del viso, da 0 (colori della fotocamera) a 1 (vedi *Calore*); fuori dai limiti si porta al limite | `calore`: vero/falso |
| `audio` | vero/falso | microfono acceso (vedi *Audio*) | `audio`: il telefono ha un microfono utilizzabile |

Filtri (identificativi fissi; i nomi mostrati li sceglie l'app):

| `filtro` | Effetto |
| --- | --- |
| `naturale` | nessun filtro (predefinito) |
| `caldo` | toni più caldi, pelle più viva |
| `freddo` | toni più freddi, bianchi più puliti |
| `luminoso` | più luce sulle ombre, contrasto morbido |
| `cinema` | contrasto pieno, ombre verso il ciano e luci calde |
| `vivido` | colori più saturi |
| `tenue` | colori smorzati, contrasto basso |
| `bianco-nero` | bianco e nero |
| `seppia` | seppia |
| `notte` | per stanze buie: più luminosità, rumore ridotto |

Un `filtro` sconosciuto si tratta come `naturale`; uno `sfondo` sconosciuto come `nessuno`. Avvisi della postura e consigli di inquadratura sono interfaccia del telefono: non viaggiano.

Esempio:

```json
{"tipo":"comando","filtro":"cinema","regolazioni":{"luminosita":0.25,"contrasto":-0.5,"saturazione":0.75,"nitidezza":0},"sfondo":"sfocato","intensitaSfondo":0.5,"pelle":0.25,"inquadratura":true,"luceVolto":true,"scritta":{"nome":"Ledion","ruolo":"Sviluppatore"},"doppiaVista":false,"postura":true,"audio":true}
{"tipo":"comando","scritta":{"nome":""}}
```

### Calore (dal 27 ottobre)

Una leggera correzione verso il caldo di tutta l'immagine, fatta dal telefono **prima** degli altri effetti con una sola matrice di colore: a 1 la temperatura sale di circa +300…+600 K, tinta neutra, nessuna saturazione forzata. È **gratis** (non è tra i comandi solo Pro).

- `comando.calore` (computer → telefono): numero da 0 a 1; 0 = i colori della fotocamera («Neutro»). Un valore fuori da 0…1 si porta al limite più vicino.
- `stato.calore` (telefono → computer): il calore attuale; il computer allinea il suo cursore a questo valore, come per gli altri effetti.
- `capacita.calore`: vero = il telefono sa farlo e accetta `comando.calore`. Assente o falso = il computer non mostra il cursore.
- Il telefono parte da **0,3**, sia su un'installazione nuova sia per chi ha già l'app; poi il valore resta salvato sul telefono come gli altri effetti.

```json
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"calore":true}
{"tipo":"comando","calore":0.5}
{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","calore":0.25}
```

### Sfondi e logo dal computer (dal 27 ottobre)

Gli sfondi si scelgono e si caricano **solo dal computer**; il telefono li applica e dice cosa sta usando.

| Campo | Messaggio | Tipo | Significato |
| --- | --- | --- | --- |
| `sfondiPronti` | `capacita` | elenco di testi, facoltativo | Gli id degli sfondi pronti che il telefono ha, nell'ordine in cui mostrarli. Assente = il telefono non sa sostituire lo sfondo con un'immagine scelta dal computer |
| `immagini` | `capacita` | vero/falso, facoltativo | Il telefono accetta il pacchetto immagine (tipo 4). Assente o falso = il computer **non** lo manda mai (un telefono vecchio chiuderebbe la connessione) |
| `immagineSfondo` | `comando` e `stato` | testo, facoltativo | Con `sfondo` = `sostituito`: l'id di uno sfondo pronto, oppure `personale` (l'ultima immagine caricata). Un id sconosciuto vale come il primo degli `sfondiPronti` |
| `immaginePersonale` | `stato` | testo, facoltativo | L'impronta (vedi *Tipo 4*) dell'immagine personale che il telefono ha; assente = nessuna |
| `sfocaturaSistema` | `stato` | vero/falso, facoltativo | Vero = sul telefono è accesa la sfocatura del sistema (iPhone: Effetti video di Apple, «Ritratto»). La accende e la regola solo il telefono (pannello di sistema); il computer la mostra come «Sfocatura del telefono» e non manda livelli |
| `luceSistema` | `stato` | vero/falso, facoltativo | Vero = sul telefono è accesa la luce del sistema (iPhone: «Luce da studio»); come sopra |
| `logo` | `stato` | testo, facoltativo | L'impronta del logo del sottopancia che il telefono ha; assente = nessun logo |
| `togliLogo` | `comando` | vero/falso, facoltativo | Vero = il telefono cancella il logo (poi manda `stato` senza `logo`) |

Sfondi pronti (identificativi fissi; i nomi mostrati li sceglie l'app; immagini nostre, generate da `Strumenti/genera_sfondi.py`):

| id | Nome mostrato |
| --- | --- |
| `ufficio` | Ufficio luminoso / Bright office |
| `libreria` | Libreria / Bookshelf |
| `soggiorno` | Soggiorno / Living room |
| `studio` | Studio scuro / Dark studio |
| `citta` | Città di sera / City at night |
| `cemento` | Parete di cemento / Concrete wall |
| `piante` | Piante / Plants |
| `lrapps` | Verde WebcamLR / WebcamLR green |

- **Caricare un'immagine**: il computer la riduce (lato lungo al massimo 1920 px per lo sfondo, 512 px per il logo; JPEG di qualità ~0,85, il logo resta PNG per la trasparenza), manda il pacchetto di tipo 4 e **poi** `comando` con `sfondo: "sostituito", immagineSfondo: "personale"` (per il logo basta il pacchetto).
- Il telefono salva l'immagine (sostituisce la precedente dello stesso `uso` e resta dopo il riavvio), poi manda subito uno `stato` con la nuova impronta in `immaginePersonale` o `logo`. Senza Pro, o con un `uso` sconosciuto, la scarta e lo `stato` non cambia.
- Il logo si disegna nel sottopancia, accanto alla `scritta`; senza scritta non si vede.
- Il computer ricorda l'ultima immagine caricata (e il logo). Se si collega a un telefono con un'impronta diversa (o assente), la mostra comunque come «La tua immagine» e la rimanda solo quando l'utente la sceglie.
- `immagineSfondo: "personale"` senza un'immagine personale sul telefono vale come il primo degli `sfondiPronti`; lo `stato` dice cosa il telefono usa davvero.

```json
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"sfondo":true,"pro":true,"immagini":true,"sfondiPronti":["ufficio","libreria","soggiorno","studio","citta","cemento","piante","lrapps"]}
{"tipo":"comando","sfondo":"sostituito","immagineSfondo":"libreria"}
{"tipo":"comando","sfondo":"sostituito","immagineSfondo":"personale"}
{"tipo":"comando","togliLogo":true}
{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","sfondo":"sostituito","immagineSfondo":"personale","immaginePersonale":"45fd1ed0012afd8b","logo":"0b6f3c2a91d4e857"}
```

## Effetti sul computer (dal 27 ottobre)

Gli effetti di immagine li può fare il **computer**, dopo la decodifica, una volta sola per tutte le sue uscite (anteprima, finestra mini, webcam virtuale, foto, registrazione). Il telefono fa solo la fotocamera e la codifica, e i suoi pulsanti tondi diventano telecomandi del computer.

| Campo o messaggio | Direzione | Tipo | Significato |
| --- | --- | --- | --- |
| `capacita.effettiSulComputer` | telefono → computer | vero/falso, facoltativo | Vero = il telefono sa lavorare con gli effetti sul computer e accetta `comando.effettiSulComputer`, `effetti` e manda `chiedi-effetto`. Assente o falso = telefono vecchio |
| `comando.effettiSulComputer` | computer → telefono | vero/falso, facoltativo | Vero = il computer fa **tutti** gli effetti di immagine: il telefono spegne per intero la sua pipeline effetti (niente segmentazione, filtri, regolazioni, pelle, calore, luce, scritta e logo, specchio nel video, inquadratura) e manda il video della fotocamera così com'è. Esposizione e fuoco guidati dal volto restano (sono della fotocamera), come doppia vista, postura, microfono, pausa e obiettivi |
| `effetti` | computer → telefono | messaggio | Lo stato degli effetti fatti dal computer, per i pulsanti del telefono. Mandato subito dopo `comando.effettiSulComputer` e a ogni cambio |
| `chiedi-effetto` | telefono → computer | messaggio | Un tocco su un pulsante del telefono. Il computer applica (con le sue regole Pro) e risponde **sempre** con `effetti`, anche se non cambia nulla |

Campi di `effetti` (tutti presenti):

| Campo | Tipo | Valori |
| --- | --- | --- |
| `specchia` | vero/falso | il computer specchia il video |
| `sfondo` | testo | `nessuno`, `sfocato`, `sostituito` (uno sconosciuto vale `nessuno`) |
| `luceVolto` | vero/falso | la luce sul volto del computer è accesa |

Campi di `chiedi-effetto` (tutti facoltativi; si applicano solo quelli presenti):

| Campo | Tipo | Valori |
| --- | --- | --- |
| `specchia` | vero/falso | accende o spegne lo specchio |
| `sfondo` | testo | `sfocato` = accende la sfocatura con l'**ultimo livello** scelto sul computer; `nessuno` = spegne lo sfondo (sfocato o sostituito). Un altro valore si ignora |
| `luceVolto` | vero/falso | accende o spegne la luce sul volto |

- Il computer manda `comando.effettiSulComputer: true` **subito dopo il `benvenuto`, appena la `capacita` lo dichiara** (la prima di ogni sessione: il telefono lo tiene solo per la sessione), poi `effetti`. A un telefono senza `capacita.effettiSulComputer` non lo manda: gli manda invece un `comando` che spegne i suoi effetti di immagine (`filtro` `naturale`, `regolazioni` a 0, `sfondo` `nessuno`, `pelle` 0, `inquadratura` e `luceVolto` falsi, scritta vuota, `specchia` falso, `togliLogo`, `calore` 0), come prima.
- Un computer vecchio non lo manda: il telefono si comporta come prima (fa i suoi effetti e accetta i comandi degli effetti).
- Specchio sul telefono: l'anteprima del telefono è specchiata se `effetti.specchia` è vero **e** la fotocamera è la frontale (solo l'anteprima, come uno specchio), senza altri effetti di immagine.
- Specchio e sfondo solo con la fotocamera frontale: con un altro `stato.obiettivo` il computer non specchia e non applica sfondi (li riprende tornando alla frontale), `effetti` lo dice (`specchia` falso, `sfondo` `nessuno`) e in `chiedi-effetto` i campi `specchia` e `sfondo` si ignorano.
- Regole Pro (vedi *WebcamLR Pro*): le applica il computer in base a `capacita.pro`. Specchio, sfocatura e luce sul volto sono gratis; uno sfondo `sostituito` scelto sul computer resta solo con il Pro.

```json
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"effettiSulComputer":true}
{"tipo":"comando","effettiSulComputer":true}
{"tipo":"effetti","specchia":true,"sfondo":"sfocato","luceVolto":false}
{"tipo":"chiedi-effetto","sfondo":"nessuno"}
{"tipo":"chiedi-effetto","specchia":false,"sfondo":"sfocato","luceVolto":true}
```

## Gobbo (pacchetto funzioni)

Il computer manda un testo che scorre sullo schermo del telefono, vicino all'obiettivo. Messaggio `gobbo`, computer → telefono, tutti i campi facoltativi (si applicano solo quelli presenti; il primo porta il `testo`):

- `testo`: al massimo **20 000 caratteri**; il telefono taglia il resto. Gli a capo (`\n`) separano i paragrafi. Un testo nuovo riparte dall'inizio.
- `velocita`: **righe al secondo** alla dimensione scelta, da 0.5 a 3 (fuori dai limiti si porta al limite)
- `attivo`: vero = scorre, falso = fermo (il testo resta)
- `dimensione`: `piccola`, `media`, `grande` (sconosciuta = `media`)
- `posizione`: da 0 (inizio) a 1 (fine): salta a quel punto (0 = ricomincia)

Il telefono risponde in `stato.gobbo`: `{"attivo":true,"posizione":0.42}`, a ogni cambiamento di `attivo` e almeno ogni 5 secondi con lo `stato` normale (non a ogni riga). Assente = nessun gobbo. Il testo vive sul telefono solo per la sessione: se lo stesso telefono si ricollega, il computer rimanda un `gobbo` completo con la `posizione` dell'ultimo `stato`. `capacita.gobbo` dice se il telefono lo sa fare.

```json
{"tipo":"gobbo","testo":"Buongiorno a tutti.\nOggi parliamo del progetto.","velocita":1.5,"attivo":true,"dimensione":"media"}
{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"principale","gobbo":{"attivo":true,"posizione":0.25}}
```

## Pausa intelligente (pacchetto funzioni)

Il telefono può smettere di catturare e codificare quando nessuno guarda, senza chiudere la sessione.

- `in-onda` dice già se un'app usa la webcam virtuale. Il nuovo messaggio `anteprima` (`{"tipo":"anteprima","visibile":true}`) dice se la finestra del computer mostra il video (finestra aperta, non ridotta a icona né coperta del tutto, se il sistema lo sa dire). Il computer lo manda subito dopo il `benvenuto` e a ogni cambiamento.
- **Dal 27 ottobre i telefoni non usano più la pausa `nessuna-app`** (decisione di Ledion: il video deve continuare finché l'app del computer è aperta, anche ridotta a icona; se l'app si chiude il collegamento cade). Il computer continua a mandare `anteprima`, e mostra ancora il motivo se un telefono vecchio lo manda. La regola di prima, per riferimento: il telefono andava in pausa `nessuna-app` quando `in-onda.attivo` è falso **e** `anteprima.visibile` è falso da più di **10 secondi** (`Servizio.secondiPrimaDellaPausa`). Se non ha mai ricevuto `anteprima` (computer vecchio) **non** va mai in pausa per questo motivo.
- Altri motivi, decisi sul telefono: `faccia-in-giu` (il telefono è appoggiato con lo schermo in giù: il gesto per mettere in pausa) e `utente` (pausa chiesta sul telefono).
- `sottofondo` (dal 30 ottobre): l'app del telefono non è più in primo piano (un'altra app, la schermata Home, lo schermo bloccato). Il telefono manda `stato` con questo motivo **appena** perde il primo piano, prima che il sistema lo sospenda (su iOS dentro un tempo di sottofondo chiesto apposta). Il computer mostra la sua immagine d'attesa «In pausa» con il motivo («WebcamLR è in sottofondo sul telefono: riaprila per riprendere») invece del fotogramma fermo o di «Riconnessione». Dopo, il telefono può smettere di mandare `ping`: con l'ultimo motivo `sottofondo` il computer **non** passa a «Riconnessione» e non dimentica il telefono per **10 minuti**, tenendo il motivo a schermo; se la connessione cade, al ritorno il telefono si ricollega da solo come sempre. Un telefono Android con il servizio in primo piano attivo continua a mandare il video e non usa questo motivo.
- `fotocamera-interrotta` (dal 30 ottobre): il sistema ha tolto la fotocamera al telefono (chiamata in corso, un'altra app la usa, telefono troppo caldo). Il telefono resta collegato e continua `ping` e `stato`; il computer mostra «In pausa» con il motivo; la ripresa segue la regola qui sotto.
- In pausa: nessun pacchetto video (né audio); `ping`/`pong`, `latenza` e `stato` continuano, quindi la connessione non va in «Riconnessione». `stato.pausa` porta il motivo; il computer mostra la sua immagine d'attesa «In pausa». Un motivo sconosciuto si mostra come una pausa qualsiasi.
- Ripresa: appena `in-onda.attivo` o `anteprima.visibile` torna vero (o finisce il motivo sul telefono) il telefono riprende **senza riconnettersi**: manda `stato` senza `pausa`, poi il video a partire da un fotogramma chiave con i parametri (e un nuovo `formato` se è cambiato).

## Audio (pacchetto funzioni)

Il microfono del telefono, per il microfono virtuale del Mac (più avanti) e l'ascolto sul computer.

- Il telefono manda audio solo dopo `comando.audio = true` e smette con `false`. In `stato.audio` dice se sta inviando; `capacita.audio` se ha un microfono utilizzabile (permesso concesso).
- Codec: **AAC-LC**, encoder hardware/di sistema (AudioToolbox su iPhone, MediaCodec su Android), **48 kHz, mono**, circa 96 kbit/s. Ogni pacchetto di tipo 3 porta **un** frame AAC di 1024 campioni (21,33 ms), grezzo, senza ADTS.
- Prima del primo pacchetto audio, e a ogni cambiamento, il telefono manda `formato-audio`:
  `{"tipo":"formato-audio","codec":"aac-lc","frequenza":48000,"canali":1,"configurazione":"EYg="}`
  - `configurazione`: l'AudioSpecificConfig (ISO 14496-3) in base64; per AAC-LC 48 kHz mono è `11 88`
- Timestamp: microsecondi del **primo campione** del frame, sullo **stesso orologio dei fotogrammi** (orologio monotono del telefono): il computer sincronizza audio e video con la stessa differenza di orologi del `pong`.
- Sincronia all'uscita (dal 27 ottobre): audio e video viaggiano sulla stessa connessione, quindi un fotogramma chiave grande fa arrivare l'audio in ritardo. Il computer non suona l'audio all'arrivo: lo mette in un piccolo buffer e fa ascoltare ogni frame a «cattura + ritardo», dove il ritardo è quello «da vetro a uscita» del video (vedi *Latenza*), tra 60 e 300 ms. Il ritardo resta **stabile** (le app di chiamata non sopportano un ritardo che oscilla): vale il massimo degli ultimi 5 secondi e cambia solo oltre 20 ms di differenza, quindi sale subito e scende solo dopo 5 secondi di valori più bassi.
- Cifrato come il video (stesso contatore della direzione telefono → computer).

## Latenza

Con `ping` e `pong` il computer misura il tempo di andata e ritorno e la differenza tra il suo orologio e quello del telefono. Con quella differenza converte il timestamp di ogni fotogramma nel proprio orologio: la latenza mostrata è il tempo tra la cattura sul telefono e la visualizzazione sul computer.

**Da vetro a uscita (dal 27 ottobre).** Il computer misura quando il fotogramma, già decodificato, esce davvero: nell'anteprima della finestra e, per il telefono nella webcam, nella webcam virtuale (compresa l'attesa dentro la webcam virtuale fino alla consegna all'app di chiamata, quando la webcam la dice). `latenza.ms` è questo ritardo (mediana dell'ultimo secondo): quello della webcam virtuale se il telefono è nella webcam e la webcam riceve il video, altrimenti quello dell'anteprima; finché non c'è questa misura (computer di una versione precedente, video non ancora decodificato) è il tempo fino all'arrivo sul computer. Nessun campo nuovo: il telefono lo mostra nei Dettagli così com'è. Obiettivo: sotto i 100 ms con il cavo, sotto i 150 ms in Wi-Fi. Il computer mostra nei suoi numeri anche le tappe: arrivo, anteprima, webcam.

Per la differenza tra gli orologi si usa il `pong` con il tempo di andata e ritorno più breve tra gli ultimi 10: è quello meno disturbato dalla rete.

Orologi: sul telefono e sul Mac è il tempo di sistema dall'avvio (`mach_absolute_time`, lo stesso dei timestamp della fotocamera), in microsecondi.

## Sequenza tipica

1. Il telefono si collega e manda `ciao`.
2. Il computer risponde `benvenuto`, poi `formato` con il formato desiderato e `anteprima`; con gli effetti sul computer, alla prima `capacita` anche `comando.effettiSulComputer` ed `effetti`.
3. Il telefono manda `formato` con il formato effettivo, poi i pacchetti video, sempre a partire da un fotogramma chiave.
4. Da qui: `ping`/`pong` e `latenza` ogni secondo, `stato` ogni 5 secondi.
5. Se il computer non riceve nulla per 3 secondi, considera la connessione persa e mostra «Riconnessione».

## Collegamento sicuro · versione 2 (dalla 0.10)

Obiettivi: nessuno sulla rete può vedere il video o mandare comandi; il telefono è sicuro di parlare con il computer giusto; il computer decide quali telefoni accettare. Solo crittografia di sistema (CryptoKit su iPhone e Mac, .NET su Windows), nessuna libreria esterna.

### Identità

Ogni dispositivo ha una coppia di chiavi di firma **ECDSA P-256** permanente, creata alla prima apertura e conservata in modo protetto (Portachiavi su iPhone e Mac, file protetto da DPAPI su Windows).

- Chiave pubblica: formato X9.63 non compresso, 65 byte (`04 ‖ X ‖ Y`).
- Firma: ECDSA con SHA-256, formato grezzo `r ‖ s`, 64 byte.
- **Impronta**: i primi 16 byte di SHA-256 della chiave pubblica, in base64url senza `=` (22 caratteri).

Nel JSON i byte viaggiano in base64 standard; le impronte e il gettone in base64url senza `=`.

### Stretta di mano

Subito dopo la connessione TCP, prima di qualsiasi altro messaggio, due pacchetti di controllo in chiaro:

1. telefono → computer: `{"tipo":"stretta","versione":2,"chiave":"…","identita":"…"}`
   - `chiave`: chiave pubblica **ECDH P-256 effimera**, nuova per ogni connessione (65 byte)
   - `identita`: chiave pubblica di firma del telefono (65 byte)
2. computer → telefono: `{"tipo":"stretta","versione":2,"chiave":"…","identita":"…","firma":"…"}`
   - `firma`: la firma del computer sulla trascrizione **T**

**T** = SHA-256( `"WebcamLR v2"` ‖ chiave del telefono ‖ identità del telefono ‖ chiave del computer ‖ identità del computer ), con le stringhe in UTF-8 e le chiavi come byte grezzi.

Il telefono verifica la firma, poi l'identità del computer (vedi *Fiducia*). Se qualcosa non torna chiude la connessione.

### Chiavi della sessione

- Segreto: ECDH tra le due chiavi effimere (la coordinata x, 32 byte).
- Chiave telefono → computer: HKDF-SHA256(segreto, sale = T, info = `"WebcamLR v2 telefono-computer"`, 32 byte)
- Chiave computer → telefono: HKDF-SHA256(segreto, sale = T, info = `"WebcamLR v2 computer-telefono"`, 32 byte)

Le chiavi effimere si buttano a fine connessione: chi registrasse il traffico non potrà decifrarlo nemmeno rubando in futuro le chiavi permanenti.

### Pacchetti cifrati

Dopo la stretta di mano **ogni** pacchetto, di qualsiasi tipo, è cifrato con **AES-256-GCM**:

- flag: bit 7 (`0x80`) a 1, gli altri bit come in chiaro
- contenuto: testo cifrato ‖ etichetta di 16 byte (la lunghezza nell'intestazione li comprende)
- nonce (12 byte): 4 byte a zero ‖ contatore a 64 bit big-endian; il contatore parte da 0 per ogni direzione e cresce di 1 a ogni pacchetto
- dati associati: i primi 2 byte dell'intestazione (tipo e flag)

Chi riceve si aspetta esattamente il contatore successivo: un pacchetto ripetuto, mancante o alterato chiude la connessione.

### Prova e abbinamento

3. telefono → computer, cifrato: `{"tipo":"prova","firma":"…","gettone":"…"}`
   - `firma`: la firma del telefono su T, con la sua identità
   - `gettone`: solo se il telefono si collega dal QR code (vedi sotto)
4. Poi `ciao` (con `versione: 2`) e tutto il resto come nella versione 1, cifrato.

Il computer risponde a `ciao` con `benvenuto` solo se il telefono è accettato:

- identità del telefono già tra i **telefoni fidati** → subito;
- `gettone` uguale a quello del QR code mostrato ora → il telefono diventa fidato, subito (inquadrare lo schermo è la prova di essere davanti al computer);
- altrimenti il computer manda `{"tipo":"approvazione","codice":"4821"}` e chiede all'utente «Consentire l'iPhone di …?», mostrando lo stesso codice. Il telefono mostra il codice e «Conferma sul computer». Sì → fidato e `benvenuto`; No, o 60 secondi senza risposta → `arrivederci` e chiusura.

**Codice** = i primi 4 byte di SHA-256(`"WebcamLR codice"` ‖ T) come intero senza segno big-endian, modulo 10000, scritto con 4 cifre. Se sui due schermi è uguale, nessuno si è messo in mezzo.

### Fiducia del telefono verso il computer

- Collegamento dal QR code: l'impronta del computer è nel QR (`k`) e deve coincidere.
- Computer già conosciuto (stesso nome): la sua impronta salvata deve coincidere; se è diversa il telefono si ferma con «L'identità di … è cambiata»: si riabbina con il QR code.
- Prima volta dalla ricerca automatica: il telefono mostra il codice da confrontare con quello sul computer; dopo il `benvenuto` salva l'impronta.

### QR code e annuncio, versione 2

`webcamlr://collega?h=<indirizzi>&p=<porta>&n=<nome>&v=2&k=<impronta>&g=<gettone>`

- `k`: impronta del computer
- `g`: gettone di abbinamento, 16 byte casuali in base64url; cambia a ogni avvio del computer e dopo ogni uso

Record TXT: `v=2`. Un telefono versione 2 non parla con un computer versione 1, e viceversa: l'app chiede di aggiornare l'altra.

## Collegamento via cavo USB (dalla 1.6)

Sul cavo non c'è una rete: il computer raggiunge l'iPhone con **usbmux**, il servizio di Apple usato dal Finder e da «Dispositivi Apple» (vedi `Documenti/Studio USB.md`). Il protocollo è identico al Wi-Fi, stretta di mano e cifratura comprese; cambia solo **chi apre la connessione**.

- **iPhone**: mentre l'app è aperta resta in ascolto su **127.0.0.1, porta TCP 52741**, solo sull'indirizzo locale: non è raggiungibile dalla rete, solo dal cavo attraverso usbmux. Quando arriva una connessione, la tratta come un computer trovato: manda subito la `stretta` (è sempre il telefono a cominciare) e da lì tutto come nel Wi-Fi.
- **Computer**: tiene aperta una connessione con usbmux e chiede di essere avvisato quando un iPhone viene collegato (`Listen`). Appena ne arriva uno, chiede `Connect` verso la porta 52741 dell'iPhone e aspetta la `stretta`.
  - Mac: socket Unix `/var/run/usbmuxd` (fuori dal Mac App Store; con l'Apple ID gratuito va aggiunta l'eccezione del sandbox per quel percorso)
  - Windows: TCP `127.0.0.1:27015`, servizio installato con l'app «Dispositivi Apple»; se manca, il computer lo dice e propone il download
- **Fiducia**: uguale al Wi-Fi. Il nome del computer arriva nel `benvenuto`; l'iPhone salva o verifica il codice di sicurezza del computer con quel nome. Il computer riconosce il telefono dal suo codice di sicurezza, non dal nome.
- **Precedenza** (vedi anche *Scelta del collegamento*): se c'è il cavo si usa il cavo. Se un telefono collegato in Wi-Fi viene collegato anche al cavo, il computer apre la sessione sul cavo e chiude quella Wi-Fi con `arrivederci` solo dopo che la nuova è accettata (1.9).

### usbmux in breve

Ogni messaggio ha un'intestazione di 16 byte in **little-endian**: lunghezza totale (intestazione compresa), versione `1`, tipo `8` (plist), etichetta (un numero scelto da chi chiede, ripetuto nella risposta). Il contenuto è un plist XML con `MessageType` (`Listen`, `Connect`, `ListDevices`), `ClientVersionString`, `ProgName` e, per `Connect`, `DeviceID` e `PortNumber`. **`PortNumber` va scritto in ordine di rete**: la porta 52741 (`0xCE05`) diventa `0x05CE` = 1486. Le risposte sono `Result` (`Number` 0 = riuscito), `Attached` (con `DeviceID` e `Properties`, tra cui `ConnectionType` = `USB`) e `Detached`. Dopo un `Connect` riuscito, la stessa connessione diventa il canale TCP verso l'iPhone.

Il client usbmux di WebcamLR è scritto da zero (Swift e C#): le librerie esistenti (libimobiledevice, usbmuxd) sono LGPL o GPL.

### Riconoscere il telefono (dalla 1.1)

Il computer decide se è «lo stesso telefono» (per rimandargli i comandi, non contarlo come nuovo) dal **codice di sicurezza del telefono** (`ImprontaAltro` della sessione sicura), non dal nome: due telefoni chiamati entrambi «iPhone» sono telefoni diversi.

### Tipo di collegamento attivo (dalla 1.2)

Le app mostrano come sono collegate: «Wi-Fi», «Cavo USB», «Wi-Fi diretto», «Cavo di rete», «Hotspot». Ognuno lo ricava dal proprio lato (sull'iPhone dall'interfaccia del percorso di rete: `awdl0` = Wi-Fi diretto, connessione su 127.0.0.1 = cavo USB). Dalla scelta del collegamento il telefono lo dice anche in `stato.collegamento.attivo`: vedi sotto.

## Scelta del collegamento

Quando un telefono può arrivare al computer per più strade (Wi-Fi e cavo USB), il computer mostra quale si usa e
lascia scegliere: **Automatico**, **Wi-Fi** o **Cavo USB**, ognuna con l'ultima latenza misurata e la nota
«più veloce ora» sulla più veloce. Decide il **telefono** (è lui che apre o accetta le connessioni); il computer
manda la preferenza e mostra quello che il telefono dice.

| Campo | Messaggio | Tipo | Significato |
| --- | --- | --- | --- |
| `sceltaCollegamento` | `capacita` (telefono → computer) | vero/falso, facoltativo | Il telefono sa cambiare strada e accetta `comando.collegamento`. Assente o falso = il computer non mostra il menu (solo l'etichetta) |
| `collegamento` | `comando` (computer → telefono) | testo | La preferenza: `automatico`, `wifi`, `cavo` |
| `collegamento` | `stato` (telefono → computer) | oggetto, facoltativo | `attivo`: la strada in uso (`wifi`, `cavo`, `hotspot`, `wifiDiretto`, `rete`); `preferenza`: `automatico`, `wifi` o `cavo` (anche se cambiata sul telefono); `strade`: le strade disponibili ora, ognuna `{"tipo": …, "ms": …}` |

- In `strade` il `tipo` usa gli stessi nomi di `attivo`; `ms` è **facoltativo**: l'ultima latenza misurata su quella
  strada (assente se mai misurata). Se `strade` manca vale come elenco vuoto. «Più veloce ora» è la strada con
  `ms` più basso tra quelle note: è solo un'informazione, non fa cambiare nulla.
- Il telefono manda `stato` con `collegamento` subito quando cambia la strada in uso, la preferenza o l'elenco
  delle strade, oltre che con lo `stato` di ogni 5 secondi. Il computer mostra la scelta secondo l'ultimo
  `stato.collegamento`, non secondo quello che ha chiesto (come per `specchia`).
- La preferenza resta salvata sul telefono: al ricollegamento il computer non la rimanda.

**Regola «Automatico»** (niente sbalzi):

1. La strada si sceglie **all'inizio** (la più veloce disponibile) e poi **resta quella**.
2. Si cambia **solo** se la strada in uso **si stacca** (cavo tolto, Wi-Fi perso: si passa all'altra senza fermare
   il video), oppure se l'utente **attacca il cavo** durante una sessione in Wi-Fi (un solo passaggio al cavo).
3. **Mai** in base alla latenza misurata durante la sessione.
4. Dopo un cambio, nessun altro cambio automatico per almeno **30 secondi** (anche se il cavo va e viene).

**Preferenza manuale** (`wifi` o `cavo`): resta quella. Se si stacca si usa l'altra solo per non perdere il video,
e si torna alla scelta appena è di nuovo disponibile. Il passaggio da una strada all'altra segue la *Precedenza*
del cavo USB: la nuova sessione è accettata prima di chiudere la vecchia, il video non si ferma.

```json
{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false,"sceltaCollegamento":true}
{"tipo":"comando","collegamento":"cavo"}
{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","collegamento":{"attivo":"wifi","preferenza":"automatico","strade":[{"tipo":"wifi","ms":38},{"tipo":"cavo","ms":9}]}}
```

## Più telefoni: la prospettiva

Con due telefoni collegati allo stesso computer uno solo va nella webcam (CAM 1, «Nella webcam»); l'altro (CAM 2)
manda il video per l'anteprima del computer. Il telefono deve sapere quale dei due è, per mostrare «PRONTA · CAM 2»
e il pulsante «Usa questa prospettiva».

- `in-onda.selezionato` (computer → telefono, vero/falso, facoltativo): vero = questo telefono è quello nella webcam.
  Il computer lo manda in **ogni** `in-onda`, e manda un `in-onda` a ogni telefono collegato ogni volta che la scelta
  cambia (oltre che quando cambia `attivo`). Con un telefono solo è sempre vero. Assente (computer vecchio) = il
  telefono si comporta come oggi: niente «CAM 2», niente pulsante.
- `usa-prospettiva` (telefono → computer, senza campi): il telefono non selezionato chiede di andare nella webcam. Il
  computer lo tratta come un clic su «Usa prospettiva»: sceglie quel telefono (se può) e manda a tutti il nuovo
  `in-onda`. Il telefono lo manda solo se ha ricevuto `selezionato` (il computer lo conosce); un computer vecchio
  ignorerebbe comunque il tipo sconosciuto. Il telefono mostra la scelta solo quando arriva l'`in-onda` con
  `selezionato` vero, non quando la chiede.

```json
{"tipo":"in-onda","attivo":false,"selezionato":false}
{"tipo":"usa-prospettiva"}
```
