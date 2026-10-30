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
(Le sezioni si aggiungono qui sotto a ogni passo finito.)

## Versione da provare
aeeb7b6 (si aggiorna a ogni passo)
