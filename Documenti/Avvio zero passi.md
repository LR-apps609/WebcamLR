# Avvio «zero passi» (Qualità 19, 9 novembre)

Obiettivo della lista qualità 1.0, punto 19: con i telefoni già fidati **apri l'app e il video arriva**. Qui il
percorso di oggi, passo per passo, i passi tolti e le prove da fare sui dispositivi veri.

- **Ramo:** `avvio-zero-passi`, da `prestazioni` (0c348f1).
- **Protocollo invariato.** Il percorso di un telefono fidato era già corto sul protocollo (`benvenuto` subito,
  Protocollo.md «Prova e abbinamento»): i passi in più erano tutti nelle app.
- **Sicurezza invariata.** Si collega da solo solo un telefono che conosce già il computer (codice di sicurezza
  salvato) verso un computer che conosce già il telefono (telefoni fidati): stretta di mano e cifratura come sempre,
  e un telefono nuovo continua a chiedere il codice o il QR code. Le autorizzazioni di sistema (fotocamera, rete
  locale, notifiche su Android) restano.
- **Swift e app Android qui non si compilano**: le modifiche sono state rilette a mano. Il C# di Windows è provato
  con i test (sotto).

«Fidato» qui vuol dire: abbinati una volta con il QR code (o con il codice di conferma), il telefono ha l'impronta
del computer tra i «Computer conosciuti» e il computer ha il telefono tra i «Telefoni fidati».

## 1. Il percorso prima (punta di `prestazioni`)

Mac e Windows si comportano allo stesso modo: ascolto e annuncio Bonjour/mDNS partono all'avvio dell'app (Mac in
`WebcamLRMacApp.init`, Windows nel costruttore di `MainWindow`), un telefono fidato riceve il `benvenuto` senza
domande e il primo telefono va da solo nella webcam (Mac `Ricevitore.attivo`, Windows `ElencoTelefoni.Accogli`).
Le differenze sono sul telefono.

### A · iPhone (Mac o Windows), prima il telefono

| # | Passo | Chi | Necessario? |
|---|---|---|---|
| 1 | Si apre l'app, legge Portachiavi e obiettivi in sottofondo | iPhone | sì |
| 2 | Parte la ricerca Bonjour (dopo la presentazione, solo la prima volta) e l'ascolto sul cavo | iPhone | sì |
| 3 | «Cerco il tuo computer…» con «Apri WebcamLR su «Nome»: mi collego da solo appena compare» | iPhone | sì (informa) |
| 4 | Si apre WebcamLR sul computer: annuncio e ascolto subito | computer | sì |
| 5 | La ricerca vede il computer | iPhone | sì |
| 6 | **Conto alla rovescia di 2 secondi** «Mi ricollego a … tra 2…» con «Annulla»; intanto stretta di mano e fotocamera, `ciao` trattenuto | iPhone | **no**: il computer è già conosciuto |
| 7 | Fine del conto: `ciao`, `benvenuto` subito (fidato), «In onda» | iPhone, computer | sì |
| 8 | Il primo telefono va nella webcam, il video arriva | computer | sì |

### B · iPhone, prima il computer

Come A dal passo 4, ma il computer si vede subito alla ricerca: 1, 2, 5, **6 (2 s)**, 7, 8.

### C · Android (Mac o Windows), prima il telefono

| # | Passo | Chi | Necessario? |
|---|---|---|---|
| 1 | Si apre l'app, parte la ricerca mDNS (NsdManager) e quella sul cavo | Android | sì |
| 2 | «Cerco il tuo computer…» | Android | sì |
| 3 | Si apre WebcamLR sul computer | computer | sì |
| 4 | La ricerca vede l'ultimo computer usato (non si controllava che fosse tra i conosciuti) | Android | sì |
| 5 | **Conto alla rovescia di 3 secondi** con «Annulla», **senza** preparare nulla nel frattempo | Android | **no** |
| 6 | Fine del conto: permesso fotocamera (se già dato non chiede), sessione, fotocamera e collegamento partono solo ora | Android | sì (la parte dopo il conto) |
| 7 | `benvenuto` subito (fidato), il primo telefono va nella webcam, video | computer | sì |

### D · Android, prima il computer

1, 4, **5 (3 s)**, 6, 7.

### Cavo USB (iPhone)

Con l'iPhone già sul cavo il computer prova `Connect` verso l'app **ogni 2 secondi** finché l'app non ascolta:
aprendo l'app si aspettava fino a 2 secondi (in media 1) prima che il computer la raggiungesse. Poi come sopra,
senza conto alla rovescia (sul cavo non c'era).

### Ricollegamento dopo una caduta (telefono in onda)

- iPhone e Android: dopo una caduta il primo tentativo dopo 0,5 s, poi **ogni 2 s**, 5 tentativi (8,5 s in tutto).
- iPhone, poi: «In attesa di …» con tentativi a 5, 10, 20, 40, 60 s e subito quando il computer ricompare nella
  ricerca (1.12). Invariato.
- Android, dopo i 5 tentativi o dopo l'`arrivederci` del computer: errore con «Riprova» (vedi *Da decidere*).

## 2. Il percorso dopo

| Caso | Prima | Dopo |
|---|---|---|
| A · iPhone, prima il telefono | 2 s di conto alla rovescia dopo la comparsa | **subito**: alla comparsa del computer «In onda» si apre e il `ciao` parte appena la stretta di mano è fatta |
| B · iPhone, prima il computer | 2 s di conto | **subito** |
| C · Android, prima il telefono | 3 s di conto, poi sessione e fotocamera da capo | **subito**: sessione, fotocamera e collegamento partono alla comparsa, solo verso un computer conosciuto |
| D · Android, prima il computer | 3 s di conto + avvio | **subito** |
| Cavo USB, app aperta dopo | fino a 2 s (in media 1) | fino a **1 s** (in media 0,5) |
| Ricaduta: tentativi | 0,5 · 2 · 2 · 2 · 2 s | 0,5 · **1** · 2 · 2 · **3** s (gli stessi 8,5 s in tutto: più fitti all'inizio, l'iPhone non entra prima nell'attesa lunga e Android non mostra prima l'errore) |

Passi tolti:

1. **Conto alla rovescia del ricollegamento** su iPhone (2 s) e Android (3 s): con un computer già conosciuto ci si
   collega subito. Il banner «Mi ricollego a … tra …» con «Annulla» non c'è più. Per scegliere un altro computer
   basta «Scollega» (il collegamento da solo avviene una volta per avvio dell'app, come prima).
2. **Interruttore nuovo** «Collegati da solo all'ultimo computer» (Impostazioni › Collegamento, iPhone e Android,
   acceso di serie): è il consenso dell'utente. Spento, all'avvio resta l'elenco e si sceglie con un tocco.
3. **Android verso un computer nuovo**: il collegamento da solo ora richiede che l'ultimo computer sia tra i
   conosciuti, come sull'iPhone (mai da soli verso uno nuovo).
4. **Cavo USB**: il computer riprova `Connect` ogni secondo invece che ogni 2 (Mac `ClienteUSB.intervalloConnect`,
   Windows `ClienteUsbmux.IntervalloConnectPredefinito`). L'attesa che raddoppia dopo i rifiuti resta 2, 4, 8 … 30 s.
5. **Tentativi di ricollegamento** più fitti nei primi secondi (sopra).

Rimangono, perché servono:

- la presentazione e la domanda «Rete locale» alla prima apertura dell'iPhone; il permesso della fotocamera; su
  Android 13+ la domanda delle notifiche finché non ha una risposta;
- la stretta di mano (decine di millisecondi) e l'accensione della fotocamera, che partono insieme;
- sul computer nessun passo: non c'era nessun pulsante né conferma per un telefono fidato, e non ne è stato aggiunto
  nessuno.

## 3. Cosa è cambiato nei file

- `iPhone/Sorgenti/SchermataConnessione.swift`: niente conto alla rovescia né sessione «preparata»; alla comparsa
  dell'ultimo computer conosciuto `apri(…, origine: .comparsa)`; QR code e indirizzo a mano tolgono il collegamento
  da solo per questo avvio. `Ricollegamento.chiaveDaSolo` / `consentito`.
- `iPhone/Sorgenti/SchermataImpostazioni.swift`: l'interruttore nella sezione Collegamento, con la frase sotto.
- `iPhone/Sorgenti/SessioneTelefono.swift` (file condiviso, **una riga**): le attese tra i tentativi.
  `trattieniCiao`/`conferma()` restano ma non li usa più nessuno: si possono togliere più avanti.
- `Android/…/ui/SchermataComputer.kt`, `ui/SchermataImpostazioni.kt`, `dati/Preferenze.kt`
  (`Impostazioni.collegaDaSolo`), `sessione/SessioneTelefono.kt` (le attese tra i tentativi), testi in
  `values/` e `values-en/`.
- `Mac/Sorgenti/ClienteUSB.swift`, `Windows/WebcamLR.Ricevitore/ClienteUsbmux.cs`: Connect ogni secondo.
- Testi: iPhone e Mac nei cataloghi `.xcstrings` (italiano e inglese), Android in `strings.xml`.

Prove automatiche (Windows, `WebcamLR.Ricevitore.Test/AvvioZeroPassiTest.cs`, telefono simulato su loopback):

- un telefono fidato che si collega riceve il `benvenuto` senza `approvazione`, entra nell'elenco come primo, è nella
  webcam («in onda» rosso con un'app che usa la webcam) e il suo primo fotogramma arriva all'uscita, senza azioni;
- lo stesso telefono che cade e torna resta nella webcam, senza domande;
- un telefono nuovo continua a chiedere la conferma (la fiducia non si salta);
- con l'app dell'iPhone chiusa il `Connect` sul cavo si riprova ogni secondo; l'attesa dopo i rifiuti resta 2, 4 s….

## 4. Prove sui dispositivi veri

Prima: abbina una volta iPhone e Android con il QR code al Mac e al PC. Nel registro del collegamento guarda la riga
«Avvio: …» (iPhone: «dalla comparsa del computer»).

- [ ] Z1 · ★ iPhone + Mac, Mac già aperto: chiudi del tutto l'app sull'iPhone e riaprila. «In onda» si apre da sola,
  nessun conto alla rovescia, video **senza** codice. Avvio sotto i 2 s
- [ ] Z2 · ★ iPhone + Mac, iPhone prima: con WebcamLR chiuso sul Mac apri l'iPhone («mi collego da solo appena
  compare»), poi apri il Mac: il video parte da solo, senza toccare nulla su nessuno dei due
- [ ] Z3 · ★ Android + PC Windows, PC già aperto: chiudi e riapri l'app Android. Nessun «Mi ricollego… tra 3», si va
  subito in onda e il video arriva
- [ ] Z4 · Android + PC, Android prima: apri l'app Android, poi WebcamLR sul PC: video da solo
- [ ] Z5 · iPhone + PC e Android + Mac: Z1 e Z2 incrociati (una prova a testa basta)
- [ ] Z6 · Impostazioni › Collegamento › «Collegati da solo all'ultimo computer» spento (iPhone e Android): riaprendo
  l'app resta l'elenco; un tocco sul computer collega senza codice. Riaccendilo alla fine
- [ ] Z7 · Collegamento da solo partito verso il computer sbagliato: «Scollega» torna all'elenco e non riparte da
  solo finché non riapri l'app
- [ ] Z8 · Un telefono **nuovo** (o tolto dai fidati sul computer) non si collega da solo: il computer chiede il codice
- [ ] Z9 · iPhone sul cavo, app chiusa, Mac e PC aperti: apri l'app. Il video arriva entro circa un secondo
  (registro del computer: «Collegato via cavo»)
- [ ] Z10 · In onda in Wi-Fi spegni e riaccendi il Wi-Fi del telefono per 3–4 secondi: il video riparte da solo
  (registro: tentativi a 0,5 e 1 s, poi 2)

Se qualcosa non va: screenshot del telefono e del computer e il registro del collegamento di entrambi.

## 5. Da decidere (Ledion)

1. **Interruttore acceso di serie?** Proposto sì (era già il comportamento, con il conto alla rovescia). Spento
   significa: nessun collegamento da solo all'avvio.
2. **Niente «Annulla».** Chi apre l'app per collegarsi a un altro computer ora fa «Scollega» e sceglie: un passo in
   più per il caso raro, zero per quello normale. Se preferisci, si può tenere un breve banner «Collegato a …
   · Cambia» dentro «In onda».
3. **Android dopo l'`arrivederci` del computer** (WebcamLR chiuso o riaperto sul computer con il telefono in onda) e
   dopo i 5 tentativi mostra un errore con «Riprova», mentre l'iPhone aspetta con calma e si ricollega da solo quando
   il computer ricompare (1.12). Portarlo su Android è un lavoro a sé (stato «In attesa di …», fotocamera spenta
   nell'attesa, testi nuovi): non fatto qui, da mettere in un round.
4. **`trattieniCiao` sull'iPhone** non serve più: lo si toglie da `SessioneTelefono.swift` quando nessun altro ci
   lavora.
5. Le checklist vecchie (`Checklist 1.0.md` B7/B9, `Checklist 1.10-1.12.md` A2, `Round 2 - checklist.md`) parlano
   ancora del conto alla rovescia: valgono per le versioni di allora. Aggiornata solo `Checklist iPhone e Mac.md` (B1, B2).
