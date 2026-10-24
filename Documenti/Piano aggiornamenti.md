# Piano degli aggiornamenti · dalla 1.1 in poi

Basato sulla ricerca `Documenti/Ricerca utenti e concorrenti.md` (esigenze delle persone, lamentele sulle app simili, collegamenti possibili). Ogni aggiornamento è piccolo, si prova in pochi minuti, e risolve un problema vero di chi usa l'app. Niente funzioni «per fare numero»: se un'idea non serve all'utente medio o allo streamer, non entra.

## Cosa risolve WebcamLR

Chi usa il telefono come webcam oggi incontra quasi sempre gli stessi problemi:

1. **Non si collega e non dice perché.** Le app lasciano la diagnosi all'utente (firewall, rete ospiti, bande Wi-Fi diverse, indirizzi da scrivere a mano) e rimandano a siti confusi.
2. **Qualità limitata e pubblicità.** Le versioni gratuite sono ferme a 480p–720p, con filigrana o pubblicità; le licenze «a vita» a volte tornano a chiedere soldi.
3. **Instabile nel tempo.** Scatti, cadute, ricollegamenti a mano durante le dirette.
4. **iPhone + Windows scoperto.** Continuity Camera di Apple funziona solo con il Mac, Phone Link di Windows solo con Android; EpocCam di Elgato è abbandonata.

WebcamLR risponde con: **si collega da solo e spiega ogni problema con la soluzione**, **qualità alta senza filigrana**, **stabile per ore**, **sicuro e senza account**, **uguale su Mac e Windows**. Semplice per tutti, con una modalità avanzata per chi vuole di più.

## Principi (identità LR Apps)

- **Semplice di serie, avanzata a richiesta**: un pulsante «Avanzate» apre tutti i dettagli; chi non lo tocca non li vede mai.
- **Ogni errore ha una causa e un'azione**: mai un messaggio senza «cosa fare».
- **Tutto spiegato dentro l'app**: domande frequenti e guida senza bisogno del sito.
- **Locale e privato**: niente account obbligatorio, nessun dato raccolto, il video non esce dalla tua rete.
- **Stessa grafica in tutte le app**: colori, caratteri e parole della famiglia LR Apps.

## Fase A · Basi solide (1.1–1.5)

| Ver. | Aggiornamento | Perché (dalla ricerca) |
| --- | --- | --- |
| 1.1 | **Correzioni dalla prova della 1.0** (checklist di Ledion) | prima la stabilità |
| 1.2 | **Indicatore del collegamento attivo** su iPhone, Mac e Windows: «Wi-Fi», «Cavo USB», «Wi-Fi diretto», «Cavo di rete», «Hotspot», con un consiglio quando ne esiste uno migliore | chiesto da Ledion; chi ha problemi non sa come è collegato |
| 1.3 | **Diagnosi automatica**: quando non si collega l'app controlla da sola (stessa rete? rete ospiti? permesso Rete locale? firewall di Windows? computer acceso?) e propone il pulsante giusto | la lamentela n. 1 su iVCam e simili |
| 1.4 | **Domande frequenti nell'app**, con ricerca, che funzionano anche senza Internet; ogni errore porta alla risposta giusta | supporto e siti confusi dei concorrenti |
| 1.5 | **Modalità avanzata**: un interruttore che mostra formato, qualità, fps, statistiche complete, controlli manuali e registro del collegamento | semplice per tutti, completa per chi vuole |

## Fase B · Cavo USB (1.6–1.9)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.6 | **iPhone: collegamento via cavo**: l'iPhone resta in ascolto sul cavo, con la stessa sicurezza del Wi-Fi | serve per tutti i computer |
| 1.7 | **Windows: cavo USB** tramite il servizio Apple installato con l'app «Dispositivi Apple»; se manca, l'app lo dice e porta al download | il caso iPhone + Windows è il più scoperto |
| 1.8 | **Mac: cavo USB** (versione scaricata dal sito; il Mac App Store non lo permette) | decisione sulla distribuzione con Ledion |
| 1.9 | **Scelta automatica e cambio senza interruzioni**: se il cavo è collegato si usa il cavo; se il Wi-Fi cade e c'è il cavo, il video continua | «se il Wi-Fi non funziona per X motivo» |

## Fase C · Collegamento istantaneo (1.10–1.12)

| Ver. | Aggiornamento | Obiettivo |
| --- | --- | --- |
| 1.10 | **QR istantaneo**: il lettore si apre già pronto, il collegamento prova tutti gli indirizzi del QR insieme e usa il primo che risponde | dal QR al video in meno di 2 secondi |
| 1.11 | **Avvio rapido misurato**: tempo dall'apertura dell'app al video, mostrato in modalità avanzata e ridotto | sotto i 2 secondi con il computer già noto |
| 1.12 | **In qualsiasi ordine**: telefono prima del computer o viceversa, dopo lo stop del computer, dopo il cambio di rete: si ricollega da solo | lamentela comune su Iriun, DroidCam, OBS |

## Fase D · Qualità video (1.13–1.17)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.13 | **1080p a 60 fps e 4K a 30 fps** (60 dove l'iPhone lo regge), con controllo del calore | i concorrenti lo fanno pagare |
| 1.14 | **HDR / 10 bit** in HEVC, facoltativo | per chi registra o fa dirette di qualità |
| 1.15 | **Qualità che segue la rete, migliorata**, con statistiche in modalità avanzata | stabilità prima di tutto |
| 1.16 | **Poca luce e stabilizzazione cinematografica** come scelta (con avviso sulla latenza) | stanze buie, telefono a mano |
| 1.17 | **Latenza completa misurata** (fino allo schermo) e grafico; obiettivo: stabile sotto i 100 ms | trasparenza |

> **Ordine aggiornato (24 ottobre, dalla ricerca `Compatibilità webcam.md`)**: la Fase F (webcam virtuale) viene **prima** della Fase E (filtri). Senza webcam virtuale Zoom, Meet, Teams e WhatsApp non vedono WebcamLR. La webcam virtuale per Windows 11 è già in scrittura.

## Fase E · Filtri (1.18–1.22)

I filtri si applicano **sull'iPhone** (Core Image / Metal): non pesano sul computer e valgono in tutte le app di chiamata.

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.18 | **Filtri di colore curati** (10–12 «look»: Naturale, Caldo, Freddo, Luminoso, Cinema, Bianco e nero…), con anteprima a confronto | priorità di Ledion; Camo ne ha 18 |
| 1.19 | **Regolazioni**: luminosità, contrasto, saturazione, nitidezza, vignettatura | |
| 1.20 | **LUT importabili** (.cube) in modalità avanzata | per creator e streamer |
| 1.21 | **Sfondo sfocato o sostituito** con la segmentazione di Apple, anche dove gli effetti di sistema non ci sono | i concorrenti lo fanno pagare |
| 1.22 | **Pelle uniforme leggera**, discreta e regolabile | |

## Fase F · Webcam virtuale (1.23–1.26)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.23 | **Mac**: webcam virtuale provata con l'account sviluppatore a pagamento (Zoom, Teams, FaceTime, OBS) | già scritta, da provare |
| 1.24 | **Windows 11**: webcam virtuale moderna (Media Foundation), visibile anche al nuovo Teams, registrata anche senza telefono collegato | il nuovo Teams non vede le webcam vecchio stile |
| 1.25 | **Windows 10**: compatibilità con le app che usano ancora DirectShow | |
| 1.26 | **Disinstallazione pulita** e nessun riavvio necessario | lamentela su Iriun ed EpocCam |

## Fase G · Streaming e creator (1.27–1.30)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.27 | **Guida OBS** e preset «Diretta» (60 fps, qualità alta, latenza bassa) | |
| 1.28 | **Registrazione sul telefono** in qualità piena mentre si è in onda | |
| 1.29 | **Due telefoni insieme** (per esempio frontale e dall'alto) | multi-camera senza scheda di acquisizione |
| 1.30 | **Uscita NDI facoltativa** dal computer (licenza NDI da valutare) | per regie in rete; mai obbligatoria |

## Fase H · Aiuto e contenuti (1.31–1.33)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.31 | **Primo utilizzo guidato**: suggerimenti brevi sulle funzioni la prima volta che compaiono | |
| 1.32 | **Video illustrativi**: un breve video per ogni funzione, dentro l'app e sul sito | chiesto da Ledion |
| 1.33 | **«Novità»** a ogni aggiornamento, in poche righe | manutenzione visibile, contro le app abbandonate |

## Fase I · Fiducia (1.34–1.35)

| Ver. | Aggiornamento | Note |
| --- | --- | --- |
| 1.34 | **Etichetta privacy «Nessun dato raccolto»** sull'App Store, verificabile | Camo dichiara dati d'uso collegati all'identità |
| 1.35 | **Un solo sito e un solo canale di assistenza**, con risposta dentro l'app | contro i molti domini di iVCam |

## Dopo (2.x)

- **Audio**: microfono dell'iPhone sul computer, riduzione del rumore, sincronia perfetta con il video
- **Voice changer** (più avanti, come effetto facoltativo)
- **Android**: app per telefono Android (Wi-Fi e cavo via ADB)
- **Monetizzazione**: da decidere quando l'app è perfetta; principio: niente filigrana, niente pubblicità, prezzo chiaro e stabile

Ogni versione arriva con la sua checklist breve; si passa alla successiva solo quando la precedente funziona sui dispositivi veri.
