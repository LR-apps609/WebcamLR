# Da controllare al ritorno (domenica 1 novembre sera)

Ledion è in Spagna dal 30 ottobre. Questo foglio raccoglie, passo per passo, le cose da provare a mano sui dispositivi.
Si aggiorna a ogni passo finito. Per ogni prova: cosa fare, cosa deve succedere, cosa mandare se non va.

## Prima di tutto: aggiornare
1. Mac: chiudi WebcamLR con ⌘Q, poi nel Terminale
   `cd ~/Documents/WebcamLR && git stash && git pull && git log --oneline -1`
   (l'ultima riga deve iniziare con l'hash scritto in fondo a questo foglio, «Versione da provare»).
2. Doppio clic su `Strumenti/Costruisci e installa.command`, rispondi **N**.
3. iPhone: cavo, scegli l'iPhone in Xcode, **▶**.
4. Windows: GitHub Desktop › Pull, poi `Strumenti/Costruisci e avvia.bat`.
5. Android: Android Studio › Pull, poi ▶ con l'S22 collegato.

Se Xcode o Android Studio danno errori rossi: screenshot e me lo mandi. Swift e Android **non si compilano qui**:
la tua build è la prima vera.

## 1.0 beta 1 · sfocatura sul Mac (ancora da provare)
- Sfondo su **Medio**, 1080p. 20 s solo la stanza: tutto sfocato e **fermo**, niente zone che diventano nitide.
- 20 s tu: tu nitido, il resto sfocato; gira la testa: resti nitido. All'accensione puoi restare sfocato ~1 s.
- Se non va: Settings › Connection log › «Show or hide the person mask», 10 s di video con la maschera + registro (Copy).

## 1.0 beta 2 · «Al sicuro»
(Le sezioni si aggiungono qui sotto a ogni passo finito. Bozze prima/dopo: https://claude.ai/artifact/SiQBKFKbTKMAhnm9vMrKFm)

### Passo 1 · Pausa «sottofondo» (iPhone, Android, Mac, Windows)
- [ ] iPhone in onda, **blocca lo schermo** → il computer mostra «Webcam in pausa» con «WebcamLR è in sottofondo sul telefono: riaprila per riprendere», **mai** «Riconnessione». Sblocca dopo ~20 s → il video riparte da solo e il telefono dice «Il video si era fermato per 20 s…».
- [ ] Mentre **registri** sul computer, metti l'iPhone in sottofondo → la registrazione si ferma e si salva subito, con un avviso.
- [ ] In onda, apri **FaceTime** o la Fotocamera sull'iPhone → la riga dice «In pausa» in **ambra** e c'è il riquadro «Un'altra app sta usando la fotocamera…»; chiudi l'altra app → il video riprende.
- [ ] Con «Microfono al computer» acceso, **chiama l'iPhone** → avviso del microfono «Tocca per riprovare»; a fine chiamata l'audio torna.
- [ ] Pausa col pulsante o telefono **a faccia in giù** → «In pausa» in ambra, mai «In onda» in corallo.
- [ ] iPhone in sottofondo **più di 10 minuti** → il computer lo dimentica con «Il telefono non è tornato entro 10 minuti».
- [ ] Android: la **notifica** dice lo stato vero (In onda in Zoom · …, In pausa, Mi ricollego…); apri la Fotocamera di sistema → pausa con il motivo, chiudila → riprende; telefonata con il microfono al computer → «Chiamata in corso: il microfono del telefono è in pausa».
- [ ] Windows: stesse prove dell'iPhone viste dal PC (velo «Webcam in pausa» con il motivo; al ritorno «Il video riprende dopo N s di pausa»).

### Passo 2 · Uscire e chiudere senza sorprese (Mac, Windows)
- [ ] Mac, con un telefono collegato premi **⌘Q** → «Un telefono è collegato: se esci, si scollega.»; **Invio = Annulla**, l'app resta aperta. Senza telefono né registrazione ⌘Q esce subito.
- [ ] Mac, registra 20 s e scegli Esci → la domanda nomina la registrazione; conferma → «Chiudo la registrazione…», poi esce; il **Finder non si apre**; il file in Filmati › WebcamLR si apre.
- [ ] Mac, registrando chiudi la finestra con ⌘W → notifica «WebcamLR continua…» (solo la prima volta). **Clic destro sull'icona nel Dock** → stato, «Ferma la registrazione», «Mostra WebcamLR».
- [ ] Mac, con la finestra davanti chiudi WebcamLR sull'iPhone e aspetta 15 s → banner fisso «… non è tornato» con «Il telefono non trova il Mac?»; riapri l'app sul telefono → il banner sparisce.
- [ ] Mac, spegni o riavvia con WebcamLR aperta → nessuna domanda di WebcamLR blocca lo spegnimento.
- [ ] Windows, menu dell'icona › **Esci da WebcamLR** con un telefono collegato → «Uscire da WebcamLR?», Invio = Annulla. C'è anche in Account › Esci da WebcamLR.
- [ ] Windows, premi la **X** due volte senza registrare → notifica solo la prima volta; registrando, a ogni X.
- [ ] Windows, registra e scegli Esci › Esci → «Chiudo la registrazione…», la finestra non si blocca, l'MP4 si apre, Esplora file non si apre.
- [ ] Windows, **primo aggiornamento**: la versione installata oggi non conosce ancora la chiusura gentile, quindi **prima di lanciare l'installatore chiudi tu WebcamLR** (icona accanto all'orologio › Esci). Dagli aggiornamenti successivi l'installatore la chiude da solo, aspettando fino a 15 s. Su un PC senza .NET 8 l'installatore mostra una finestra con «Scarico .NET 8… N MB di 30».

## Versione da provare
Vedi l'ultima riga di «git log --oneline -1»: va bene qualsiasi versione uguale o successiva a quella scritta nell'ultimo aggiornamento che ti ho mandato.
