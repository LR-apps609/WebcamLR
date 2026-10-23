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
- QR code (round 2): `webcamlr://<indirizzo>:<porta>?v=1&n=<nome>`, per le reti dove Bonjour non passa.

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
| `arrivederci` | entrambe | — | Chiusura volontaria, prima di chiudere la connessione |

Valori:

- `piattaforma`: `iphone`, `android`, `mac`, `windows`
- `codec`: `h264`, `hevc`
- `temperatura`: `normale`, `calda`, `molto-calda`, `critica` (gli stessi livelli di iOS)
- `batteria`: da 0 a 100, oppure -1 se non nota
- `obiettivo`: testo libero, per ora `grandangolo`, `principale`, `tele`, `frontale`

Esempio:

```json
{"tipo":"ciao","versione":1,"nome":"iPhone di Ledion","piattaforma":"iphone","versioneApp":"0.1"}
```

## Latenza

Con `ping` e `pong` il computer misura il tempo di andata e ritorno e la differenza tra il suo orologio e quello del telefono. Con quella differenza converte il timestamp di ogni fotogramma nel proprio orologio: la latenza mostrata è il tempo tra la cattura sul telefono e la visualizzazione sul computer.

## Sequenza tipica

1. Il telefono si collega e manda `ciao`.
2. Il computer risponde `benvenuto`, poi `formato` con il formato desiderato.
3. Il telefono manda `formato` con il formato effettivo, poi i pacchetti video, sempre a partire da un fotogramma chiave.
4. Da qui: `ping`/`pong` ogni secondo, `stato` ogni 5 secondi.
5. Se il computer non riceve nulla per 3 secondi, considera la connessione persa e mostra «Riconnessione».
