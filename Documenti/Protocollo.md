# Protocollo WebcamLR · versione 1 (bozza)

Il protocollo è l'unica cosa che le app condividono. Lo parlano tre implementazioni:

- Swift: `Protocollo/` (pacchetto usato da iPhone e Mac)
- C#: `Windows/WebcamLR.Protocollo/`
- Kotlin: Android, più avanti

Ogni modifica a questo file va riportata in tutte le implementazioni, con i loro test.

## Ruoli

- **Computer** (Mac o Windows): riceve il video. Si annuncia in rete e resta in ascolto.
- **Telefono** (iPhone o Android): cattura e invia. Cerca i computer e si collega.

## Scoperta

- Il computer pubblica il servizio Bonjour/mDNS `_webcamlr._tcp`, porta TCP **52740** (se occupata, una qualsiasi: la porta vera viaggia nell'annuncio).
- Nome del servizio: il nome del computer (es. «MacBook Pro di Ledion»).
- Record TXT: `v=1` (versione del protocollo), `p=mac` oppure `p=windows`.
- QR code, per le reti dove Bonjour non passa: `webcamlr://collega?h=<indirizzi>&p=<porta>&n=<nome>&v=1`
  - `h`: indirizzi IPv4 del computer separati da virgole, il più probabile per primo (Wi-Fi, poi cavo)
  - `p`: porta TCP; `n`: nome del computer (codificato per URL); `v`: versione del protocollo
  - esempio: `webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=1`
  - Lo stesso indirizzo si può scrivere a mano sul telefono: `192.168.1.20` (porta 52740) oppure `192.168.1.20:52741`.

## Connessione

Una sola connessione TCP per sessione, con `TCP_NODELAY` attivo. Controllo, video e audio viaggiano nella stessa connessione, distinti dal tipo di pacchetto. Se in futuro servirà, il video potrà passare su UDP senza cambiare i messaggi di controllo.

## Pacchetto

Ogni pacchetto ha un'intestazione di 6 byte seguita dal contenuto:

| Byte | Campo | Note |
| --- | --- | --- |
| 0 | tipo | 1 = controllo, 2 = video, 3 = audio |
| 1 | flag | dipende dal tipo |
| 2–5 | lunghezza | lunghezza del contenuto, intero senza segno a 32 bit, big-endian |

- Lunghezza massima del contenuto: 16 MiB. Oltre, la connessione si chiude.
- Un tipo sconosciuto chiude la connessione: è un errore di versione.

### Tipo 1 · controllo

Contenuto: un oggetto JSON in UTF-8, con il campo `tipo`. Flag sempre 0. Un messaggio con `tipo` sconosciuto si ignora: così le versioni nuove possono aggiungere messaggi senza rompere quelle vecchie.

### Tipo 2 · video

Contenuto: 8 byte di timestamp (microsecondi, orologio monotono del telefono, big-endian) seguiti da un'unità H.264 o HEVC in formato Annex B (con i codici di inizio `00 00 00 01`).

Flag:

- bit 0: fotogramma chiave
- bit 1: contiene i parametri del codec (SPS/PPS, e VPS per HEVC)

Ogni fotogramma chiave porta con sé i parametri del codec, così il computer può partire da qualsiasi fotogramma chiave.

### Tipo 3 · audio

Contenuto: 8 byte di timestamp (come il video) seguiti da un pacchetto Opus, 48 kHz mono, 20 ms. Flag sempre 0.

## Messaggi di controllo

Nomi dei campi in italiano, `camelCase`. I valori enumerati sono stringhe minuscole con il trattino.

| `tipo` | Direzione | Campi | Significato |
| --- | --- | --- | --- |
| `ciao` | telefono → computer | `versione`, `nome`, `piattaforma`, `versioneApp` | Primo messaggio, subito dopo la connessione |
| `benvenuto` | computer → telefono | `versione`, `nome`, `piattaforma` | Risposta a `ciao`: il computer accetta |
| `formato` | entrambe | `codec`, `larghezza`, `altezza`, `fps` | Dal computer: richiesta. Dal telefono: il formato effettivo che sta inviando |
| `stato` | telefono → computer | `batteria`, `inCarica`, `temperatura`, `obiettivo` | Ogni 5 secondi e a ogni cambiamento |
| `ping` | computer → telefono | `t` | Ogni secondo; `t` = orologio del computer in µs |
| `pong` | telefono → computer | `t`, `telefono` | Risposta immediata: `t` copiato, `telefono` = orologio del telefono in µs |
| `latenza` | computer → telefono | `ms` | Ogni secondo: la latenza misurata dal computer, da mostrare anche sul telefono |
| `capacita` | telefono → computer | `obiettivi`, `zoomMassimo`, `torcia`, `isoMinimo`, `isoMassimo` | Dopo `benvenuto` e a ogni cambio di obiettivo: cosa il computer può comandare |
| `in-onda` | computer → telefono | `attivo`, `app` (facoltativo) | Un'app sta usando la webcam virtuale: il telefono mostra il rosso «IN ONDA» (regola dei colori della bozza) |
| `comando` | computer → telefono | tutti facoltativi: `obiettivo`, `zoom`, `torcia`, `esposizione`, `bianco`, `fuoco`, `iso`, `tempo` | Comandi della fotocamera dal computer (round 4); si applicano solo i campi presenti |
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
- `tempo`: tempo di posa manuale come denominatore (60 = 1/60 di secondo); 0 = automatico. Con `iso` e `tempo` entrambi a 0 si torna all'esposizione automatica. Il telefono non supera mai la durata di un fotogramma (a 30 fps, 1/25 diventa 1/30): i fotogrammi al secondo non cambiano

Esempio:

```json
{"tipo":"ciao","versione":1,"nome":"iPhone di Ledion","piattaforma":"iphone","versioneApp":"0.1"}
{"tipo":"comando","esposizione":0.3,"bianco":4300}
```

## Latenza

Con `ping` e `pong` il computer misura il tempo di andata e ritorno e la differenza tra il suo orologio e quello del telefono. Con quella differenza converte il timestamp di ogni fotogramma nel proprio orologio: la latenza mostrata è il tempo tra la cattura sul telefono e la visualizzazione sul computer.

Per la differenza tra gli orologi si usa il `pong` con il tempo di andata e ritorno più breve tra gli ultimi 10: è quello meno disturbato dalla rete.

Orologi: sul telefono e sul Mac è il tempo di sistema dall'avvio (`mach_absolute_time`, lo stesso dei timestamp della fotocamera), in microsecondi.

## Sequenza tipica

1. Il telefono si collega e manda `ciao`.
2. Il computer risponde `benvenuto`, poi `formato` con il formato desiderato.
3. Il telefono manda `formato` con il formato effettivo, poi i pacchetti video, sempre a partire da un fotogramma chiave.
4. Da qui: `ping`/`pong` e `latenza` ogni secondo, `stato` ogni 5 secondi.
5. Se il computer non riceve nulla per 3 secondi, considera la connessione persa e mostra «Riconnessione».
