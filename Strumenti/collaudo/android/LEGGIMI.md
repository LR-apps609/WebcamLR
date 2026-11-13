# Collaudo Android: il banco di prova

Il workflow `.github/workflows/collaudo-android.yml` compila l'APK di debug, accende un emulatore Android 14
(API 34, x86_64, profilo Pixel 6, fotocamera emulata), installa l'app ed esegue i copioni di `copioni/`.

## Lanciare un copione

```sh
gh workflow run collaudo-android.yml -R LR-apps609/WebcamLR --ref collaudo-20-android -f copioni="fumo"
gh workflow run collaudo-android.yml -R LR-apps609/WebcamLR --ref collaudo-20-android -f copioni="fumo mio_copione"
gh workflow run collaudo-android.yml -R LR-apps609/WebcamLR --ref collaudo-20-android        # tutti i copioni
```

Parte anche da solo a ogni push su un ramo `collaudo-20*` che cambia `Android/**` o `Strumenti/collaudo/android/**`
(con tutti i copioni). Il copione deve stare nel ramo indicato con `--ref`: prima `git push`, poi `gh workflow run`.

## Scaricare i risultati

```sh
gh run list -R LR-apps609/WebcamLR -w collaudo-android.yml -L 5     # l'id del run
gh run watch <id> -R LR-apps609/WebcamLR                              # aspetta la fine
gh run download <id> -R LR-apps609/WebcamLR -n collaudo-android -D risultati-<id>
```

Se `gh run download` risponde «Forbidden» (la rete blocca il dominio degli artifact, `*.blob.core.windows.net`):
`bash Strumenti/collaudo/android/scarica.sh <id>` prova l'artifact e altrimenti ricostruisce i risultati dal
registro del lavoro (stampati in base64 dal passo «Risultati nel registro»): stesse cartelle (schermate PNG, o JPEG
ridotti se la macchina ha ImageMagick), senza `logcat-completo.txt.gz`.

Dentro: `riepilogo.txt` (un rigo per copione) e una cartella per copione con

- `esito.txt`: `OK` oppure `FALLITO` e il motivo (il copione ha chiamato `fallisci`, è uscito con errore, è
  scaduto il tempo, l'app è andata in crash o in ANR);
- `schermate/NNN-nome.png` e `albero/NNN-nome.xml`: le fotografie e l'interfaccia (uiautomator dump) a ogni passo
  (anche `NNN-prima-di-tocca-….xml`, l'albero letto per ogni tocco);
- `passi.log`: i passi leggibili, con l'ora; `note.txt`: le note del copione;
- `logcat-app.txt` (solo l'app, con crash e ANR), `crash.txt`, `logcat-completo.txt.gz`.

Il lavoro finisce verde anche se un copione trova un bug: guardate `esito.txt`.

## Scrivere un copione

Un file `copioni/<nome>.sh` (nome senza spazi), eseguito con le funzioni di `lib.sh` già caricate. Niente `set -e`:
le funzioni che cercano rendono 1 se non trovano e il copione sceglie se fermarsi.

```sh
cancella_dati_app                 # primo avvio pulito (pm clear), app in italiano
permessi_concedi                  # oppure lascia che la presentazione li chieda
avvia_app
attendi_testo "Il tuo telefono diventa la webcam" 30 || fallisci "niente presentazione"
tocca_testo "Salta"
schermata "pagina-permessi"
```

| Funzione | Cosa fa |
|---|---|
| `avvia_app`, `chiudi_app`, `cancella_dati_app` | avvia; force-stop; `pm clear` (primo avvio, permessi da chiedere) |
| `schermata <nome>`, `albero <nome>` | PNG + XML con lo stesso numero; solo XML |
| `testi_visibili` | scrive in passi.log tutti i testi e le descrizioni visibili |
| `tocca_testo "<testo>" [n]` | tocca il nodo con quel text o content-desc (uguale, poi «contiene»; scorre fino a 4 volte) |
| `tocca_id <id> [n]`, `tocca_xy x y` | per resource-id (dialoghi di sistema); per coordinate |
| `scrivi "<testo>"`, `invio` | scrive nel campo con il fuoco (solo ASCII) |
| `indietro`, `home`, `scorri_giu`, `scorri_su` | tasti e scorrimenti |
| `attendi_testo "<testo>" [s]`, `attendi_id <id> [s]`, `c_e_testo "<testo>"`, `attendi <s>` | attese e controlli |
| `consenti_dialogo`, `rifiuta_dialogo` | risponde a un dialogo di permesso di sistema |
| `permessi_concedi`, `permessi_nega` | `pm grant` / `pm revoke` di fotocamera e microfono (+ notifiche nel concedi) |
| `rete_spenta`, `rete_accesa`, `aereo` | Wi-Fi e dati spenti; tutto acceso; modalità aereo |
| `schermo_piccolo`, `carattere_grande [2.0]`, `ruota [orizzontale\|verticale]` | 480x800 @240 dpi; font_scale; rotazione |
| `lingua_inglese`, `lingua_italiana` | lingua dell'app (Android 13+, nessun riavvio) |
| `ripristina` | schermo, carattere, rotazione, rete e lingua come all'inizio (lo fa anche esegui.sh tra un copione e l'altro) |
| `nota "<testo>"`, `fallisci "<motivo>"` | un'osservazione; FALLITO in esito.txt e fine del copione |
| `tocca_classe <classe>`, `svuota_campo` | per esempio `android.widget.EditText`; cancella il campo con il fuoco |

Note:

- I testi dell'app sono in `Android/app/src/main/res/values/strings.xml` (italiano) e `values-en/` (inglese).
  Le icone senza testo si toccano per descrizione: «Impostazioni», «App e assistenza», «Indietro».
- L'emulatore è in inglese: i dialoghi di sistema dei permessi sono in inglese («While using the app», «Allow»,
  «Don't allow»); usate `consenti_dialogo` / `rifiuta_dialogo`.
- Le animazioni di sistema sono spente (come «Rimuovi animazioni»): l'app ferma le scene animate e i dump riescono.
- La fotocamera è quella emulata di Android (una stanza finta che si muove).
- `scrivi` scrive solo ASCII (limite di `adb shell input text`): «perché» diventa «perche», «»» e gli altri simboli non
  ASCII si saltano, e passi.log lo dice. Una tastiera di prova (ADBKeyboard) lo risolverebbe, ma va installata a parte.

## In onda: il computer finto

`Strumenti/collaudo/ComputerFinto` è un programma console con il cuore vero del ricevitore Windows
(`WebcamLR.Ricevitore`: ascolto sulla 52740, stretta di mano, abbinamento, statistiche). Il workflow lo compila e
lo lascia pronto; il copione lo accende. Dall'emulatore il computer è `10.0.2.2`.

```sh
avvia_computer_finto --nome "PC di collaudo"     # anche: --rifiuta, --interrompi-dopo 30 --pausa 15,
                                                # --senza-in-onda, --ogni 5, --attesa-conferma 2
collega_indirizzo                               # «Collega a mano (indirizzo)» con 10.0.2.2:52740
# oppure: collega_qr (il link del QR code, con il gettone: niente codice) o collega_cavo (adb forward → 52741)
attendi_computer video 45 || fallisci "niente video al computer"
statistiche_computer
ferma_computer_finto                            # lo fa anche esegui.sh alla fine del copione
```

| Funzione | Cosa fa |
|---|---|
| `avvia_computer_finto [opzioni]`, `ferma_computer_finto` | accende (aspetta che ascolti) / spegne con «arrivederci» |
| `collega_indirizzo [ip:porta]`, `collega_qr`, `collega_cavo`, `scollega_cavo` | le tre strade del telefono |
| `stato_computer`, `attendi_computer <stato> [s]` | `attesa`, `conferma`, `collegato`, `video`, `interrotto`, `fermo` |
| `collegamenti_computer`, `attendi_ricollegamento <prima> [s]` | quante volte ha accettato il telefono; aspetta un ricollegamento con video |
| `codice_computer`, `statistiche_computer [n]` | il codice di conferma chiesto; le ultime righe delle statistiche |

Il computer finto consente da solo un telefono nuovo dopo `--attesa-conferma` secondi (il telefono intanto mostra
«Conferma sul computer» con il codice), dice al telefono che un'app usa la webcam (il rosso «IN ONDA») e scrive in
`computer-finto/`: `eventi.log`, `statistiche.csv` (ogni secondo: risoluzione, fps, Mbit/s, latenza), `stato.txt`,
`codice.txt`, `collegamento.txt`, `fotogrammi/NNN-TTTs.png` (un fotogramma chiave ogni `--ogni` secondi, decodificato
con ffmpeg), `video.h264` (solo nell'artifact) e `riepilogo.txt`. `--interrompi-dopo <s>` chiude tutto di colpo
<s> secondi dopo il primo video e resta irraggiungibile per `--pausa` secondi (una caduta di rete vista dal
computer); `rete_spenta` fa la stessa prova dal telefono. Il cavo: il vero Windows apre il canale con adb, ma
salta gli emulatori; qui fa le sue veci un `adb forward tcp:52800 tcp:52741`, la stessa porta del telefono.

Copioni pronti: `in_onda` (a mano, codice, 60 s in onda, rete spenta 20 s e ricollegamento, Scollega) e `cavo`.

## Schermate e pulsanti (dal copione fumo)

- Presentazione (4 pagine): «Avanti», «Salta» in alto; l'ultima, «Goditi l'esperienza», ha «Inizia», che apre i
  dialoghi di sistema per fotocamera, microfono e notifiche.
- Principale: «Cerco il tuo computer…», dopo ~10 s senza computer «Non trovo nessun computer» con «Altre risposte
  nelle domande frequenti»; pulsanti «Inquadra il QR code del computer», «Usa il cavo USB» (dialogo con «Come
  funziona», «Oppure con il debug USB (più veloce)», «Apri il tethering», «Chiudi»), «Mandami il link per il
  computer», «Collega a mano (indirizzo)» (dialogo con campo, «Collega», «Annulla»). In cima: «WebcamLR Pro,
  Sblocca», «App e assistenza» (icona ?), «Impostazioni» (ingranaggio).
- Lettore QR: fotocamera emulata, chiude con Indietro.
- Impostazioni: WebcamLR Pro, Video › Qualità, Fotocamera (Griglia dei terzi, Livella), Collegamento (Automatico,
  Wi-Fi, Cavo USB, «Collegati da solo all'ultimo computer»), Schermo e batteria (interruttori), Altro («App e
  assistenza», «Segnala un bug», «Lingua», «Registro del collegamento»).
- App e assistenza: riga WebcamLR Pro (toccate «1080p, 4K, 60 fps»), «Simula Pro» / «Torna all'acquisto vero» (solo
  APK di debug: Pro acceso senza comprare), «Domande frequenti», «Guida», «Segnala un bug», computer conosciuti,
  versione, «Privacy», «Sito di WebcamLR».
- WebcamLR Pro: sull'emulatore «Google Play non è pronto per i pagamenti» con «Riprova» e «Ripristina acquisti».
- Segnala un bug: campo «Descrizione del problema», «Includi i dati tecnici», «Includi il registro…», «Invia la
  segnalazione» (attivo solo con del testo).

## Tempi tipici

Compilazione dell'APK 2–4 minuti, accensione dell'emulatore 1–3, il copione `fumo` circa 4 minuti: un run con un
copione dura 9–12 minuti. Più copioni nello stesso run costano solo il loro tempo; run lanciati insieme girano in
parallelo su macchine diverse.
