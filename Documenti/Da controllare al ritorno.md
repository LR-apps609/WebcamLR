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

## Versione da provare
a471a90 (si aggiorna a ogni passo)
