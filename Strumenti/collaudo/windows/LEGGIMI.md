# Banco di prova Windows

L'app WebcamLR vera, compilata e avviata sul desktop di una macchina Windows di GitHub Actions, guidata da copioni
PowerShell con UI Automation. Un telefono finto (`Strumenti/collaudo/TelefonoFinto`) si collega come un iPhone vero.

## Lanciare un copione

```sh
gh workflow run collaudo-windows.yml -R LR-apps609/WebcamLR --ref collaudo-20-windows -f copioni="fumo"
gh run list -R LR-apps609/WebcamLR --workflow collaudo-windows.yml -L 3      # l'id del run
gh run watch <id> -R LR-apps609/WebcamLR
gh run download <id> -R LR-apps609/WebcamLR -n collaudo-windows -D risultati
```

`copioni` vuoto = tutti; più copioni separati da virgole (`-f copioni="fumo,impostazioni"`). Un push su un ramo
`collaudo-20*` che cambia `Windows/**` o `Strumenti/collaudo/**` li lancia tutti.

Nell'artifact `collaudo-windows` c'è una cartella per copione:

- `NN-<nome>.png` schermate (tutto lo schermo del runner, 1024×768) e `NN-<nome>.txt` alberi dell'interfaccia
  (tipo, «Name», `id=` AutomationId, stato, posizione);
- `passi.log` ogni passo, `telefono-<nome>.log` il telefono finto;
- `dati-app/` i file di `%LOCALAPPDATA%\WebcamLR` (preferenze, `Errori.txt` se l'app ne ha scritti);
- `esito.txt`: OK, PROBLEMI (con l'elenco) o INTERROTTO (con l'errore). Il lavoro resta verde anche con dei bug.

`riassunto.txt` in cima riassume tutti i copioni. Tempi tipici: 8–10 minuti di compilazione, poi il fumo circa 5 minuti.

## Scrivere un copione

Un file `copioni/<nome>.ps1` (UTF-8 **con BOM**, per le lettere accentate in PowerShell 5.1). Le funzioni sono già
caricate:

```powershell
Avvia-App -Azzera                        # primo avvio, dati dell'app cancellati (senza -Azzera: dati di prima)
Fotografa 'primo-avvio'                  # Schermata + Albero-UI con lo stesso nome
Passo 'Apro le impostazioni' {           # se fallisce: problema in esito.txt, schermata, e si va avanti
    Clicca 'PulsanteImpostazioni'        # AutomationId (= x:Name nello XAML) o testo visibile
    Clicca (Testo-App 'Impostazioni_Fotocamera')   # testo dell'app nella lingua attuale, da Resources.resw
    Schermata 'fotocamera'
}
Avvia-TelefonoFinto -DalQR --nome 'iPhone di Anna' --durata 120 | Out-Null
Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Anna'
Segnala-Problema 'Il video non scorre'   # un bug trovato a occhio o con un controllo
```

| Funzione | Cosa fa |
| --- | --- |
| `Avvia-App [-Azzera]`, `Chiudi-App` | avvia e aspetta la finestra; chiude con `WebcamLR.exe --esci` (la X la nasconde soltanto) |
| `Azzera-Dati` | cancella `%LOCALAPPDATA%\WebcamLR` (solo su GitHub Actions, altrove serve `-Forza`) |
| `Schermata <nome> [-Finestra]`, `Schermata-Elemento <id> <nome>` | PNG di schermo, finestra o elemento |
| `Albero-UI <nome> [-Tutto]` | l'albero UI Automation di tutte le finestre dell'app (`-Tutto`: anche fuori schermo) |
| `Clicca <id o nome> [-Mouse]` | Invoke/Toggle/Select/Expand, o un clic vero del mouse |
| `Scrivi <testo> [-In <id>]` | scrive nella casella o nel controllo con il fuoco |
| `Tasto 'Tab'`, `'Invio'`, `'Esc'`, `'Ctrl+S'`, `'Maiusc+Tab'` | tasti |
| `Attendi-Testo <testo> <s> [-Obbligatorio]`, `Attendi-Elemento <id> <s>`, `Esiste <id>` | attese e controlli |
| `Ridimensiona-Finestra <l> <a>`, `Ingrandisci-Finestra` | misura della finestra |
| `Lingua-Inglese [-Riavvia]`, `Lingua-Italiana` | lingua dell'app dal prossimo avvio (di serie: italiano) |
| `Avvia-TelefonoFinto [-DalQR] <opzioni>`, `Attendi-Telefono <riga>`, `Ferma-TelefonoFinto` | il telefono finto |
| `Leggi-QR` | salva il QR mostrato dall'app (per `--qr`) |
| `Rete-Spenta`, `Rete-Accesa` | la rete tra telefono e PC cade e torna (vedi limiti) |
| `Segnala-Problema`, `Passo`, `Scrivi-Log` | esito e registro |

Gli AutomationId sono i `x:Name` di `Windows/WebcamLR.App/MainWindow.xaml` (WinUI li usa da soli). Le voci create da
codice (le voci di Impostazioni, i pulsanti dei ContentDialog) si trovano per nome: `Testo-App` dà il nome giusto in
tutte e due le lingue. Per scoprire cosa c'è a schermo: `Albero-UI`.

## Il telefono finto

```sh
dotnet run --project Strumenti/collaudo/TelefonoFinto -- --aiuto
```

Protocollo 2 vero (stretta di mano, cifratura, abbinamento), video H.264 sintetico (un'immagine che si muove con un
orologio e i comandi ricevuti dal PC; ogni fotogramma è una chiave I_PCM, circa 1,4 MB a 720p: pesante ma letto da ogni
decodificatore). Opzioni principali: `--nome`, `--durata`, `--interrompi-dopo <s>` (con `--modo-interruzione
silenzio|chiusura` e `--riconnetti-dopo <s>`), `--riconnetti-sempre`, `--risoluzione 1280x720`, `--fps`, `--pro`,
`--android`.

**Abbinamento.** Il PC accetta subito un telefono già fidato o con il gettone del QR; altrimenti chiede «Consentire …?» con
un codice di 4 cifre. Il gettone non è salvato su disco (cambia a ogni avvio e dopo ogni uso): si legge dal QR a schermo
(`-DalQR`, oppure `Leggi-QR` e `--qr <file>`). Senza gettone il telefono scrive `CODICE 1234` e il copione clicca
`Testo-App 'Conferma_Consenti'` o `'Conferma_NonConsentire'`. `--gettone-sbagliato` prova un gettone falso (il PC deve
chiedere conferma). Dopo un «Non consentire» lo stesso telefono è respinto per 2 minuti: usa `--identita-nuova`.
L'identità resta tra un avvio e l'altro (una per nome, nella cartella temporanea), come su un telefono vero.

Su Linux: `dotnet test Strumenti/collaudo/TelefonoFinto.Prova` lo prova contro il `Ricevitore` vero su loopback (e, se
c'è ffmpeg, decodifica il video).

## Limiti

- Niente webcam vera e niente webcam virtuale installata (servirebbe l'amministratore e un riavvio dei servizi): le app
  che usano «WebcamLR» come webcam non si provano; «in onda» non si accende. La pausa automatica resta spenta (il PC non
  sa leggere l'uso della webcam).
- Niente GPU vera: WinUI disegna con WARP, il motore effetti usa il ripiego sul processore e DirectML può non partire.
  Lentezze e scatti qui non dicono nulla delle prestazioni su un PC vero.
- Niente cavo USB, niente iPhone o Android veri, niente Bonjour verso un telefono (il telefono finto entra per indirizzo).
- `Rete-Spenta` sospende il processo del telefono finto: la connessione resta aperta e tace, come un Wi-Fi che sparisce.
  Spegnere la scheda di rete del runner non si può (GitHub perderebbe la macchina). Per una connessione chiusa di colpo:
  `--interrompi-dopo <s> --modo-interruzione chiusura`.
- Lo schermo del runner è 1024×768 al 100%: niente prove di DPI alti o di più schermi.
- La lingua passa con un «startup hook» di .NET (`LinguaAvvio`), non con la lingua di Windows (sul runner è l'inglese
  e cambiarla richiede di uscire dalla sessione).
