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
registro del lavoro (stampati in base64 dal passo «Risultati nel registro»): stesse cartelle, schermate in JPEG a
metà risoluzione, senza `logcat-completo.txt.gz`.

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

Note:

- I testi dell'app sono in `Android/app/src/main/res/values/strings.xml` (italiano) e `values-en/` (inglese).
  Le icone senza testo si toccano per descrizione: «Impostazioni», «App e assistenza», «Indietro».
- L'emulatore è in inglese: i dialoghi di sistema dei permessi sono in inglese («While using the app», «Allow»,
  «Don't allow»); usate `consenti_dialogo` / `rifiuta_dialogo`.
- Le animazioni di sistema sono spente (come «Rimuovi animazioni»): l'app ferma le scene animate e i dump riescono.
- Nessun computer con WebcamLR in rete: «In onda» non si raggiunge; la fotocamera è quella emulata di Android.
- `scrivi` non sa scrivere lettere accentate (limite di `adb shell input text`).

## Tempi tipici

Compilazione dell'APK 4–7 minuti, accensione dell'emulatore 2–4, il copione `fumo` circa 4 minuti: un run con un
copione dura 12–18 minuti. Più copioni nello stesso run costano solo il loro tempo; run lanciati insieme girano in
parallelo su macchine diverse.
