# Far provare WebcamLR a un amico (prima della pubblicazione)

Finché non ci sono gli account sviluppatore, gli store non si possono usare. Ecco cosa si può dare a un amico oggi, dal più
semplice al più scomodo.

| Dispositivo dell'amico | Si può? | Come |
|---|---|---|
| **PC Windows** | Sì, con un doppio clic | Gli mandi `WebcamLR-Setup-1.0.exe` |
| **Telefono Android** | Sì | Gli mandi il file `.apk` |
| **iPhone** | Solo con il telefono attaccato al tuo Mac | Con l'Apple ID gratuito non si può mandare l'app; dura 7 giorni |
| **Mac** | No, per ora | Con l'Apple ID gratuito l'app gira solo sul tuo Mac. Serve l'account Apple a pagamento (TestFlight o dmg firmato) |

La combinazione più facile per un amico: **telefono Android + PC Windows**, oppure **il suo telefono + il tuo computer**.

## Cosa prepari tu (una volta)

### L'installatore per Windows (sul tuo PC)

1. Aggiorna la repository (GitHub Desktop › Pull).
2. Cartella `Strumenti` › doppio clic su **Crea installer Windows.bat**. Aspetta «Fatto».
3. Si apre la cartella `Distribuzione` con **WebcamLR-Setup-1.0.exe**. Alla domanda «Lo installo adesso» rispondi **N**.
4. Manda il file all'amico: Google Drive, WeTransfer o una chiavetta. Non per email: Gmail e Outlook bloccano i `.exe`.

### L'app per Android (con Android Studio)

1. Apri la cartella `Android` in Android Studio, come nella guida di installazione.
2. Menu **Build › Build App Bundle(s) / APK(s) › Build APK(s)**. Aspetta l'avviso in basso a destra e clicca **locate**.
3. Il file è `app-debug.apk`: rinominalo in **WebcamLR.apk** e mandalo (WhatsApp come documento, Drive o Telegram).
   È la versione di prova: c'è **Simula Pro** in fondo alla pagina App, così l'amico può provare anche le funzioni Pro.

## Cosa fa l'amico

### Windows: doppio clic

1. Doppio clic su **WebcamLR-Setup-1.0.exe**.
2. Se il browser avvisa che il file «non viene scaricato comunemente»: **…** › **Mantieni** (Edge) oppure **Conserva** (Chrome).
3. Esce la finestra blu «Windows ha protetto il PC»: **Ulteriori informazioni** › **Esegui comunque**.
   Succede perché l'installatore non è ancora firmato. È normale.
4. «Installo anche la webcam «WebcamLR»…?» › **Sì**. Poi un avviso spiega la domanda di Windows › **OK** › nella finestra di
   Windows («Autore: Sconosciuto») › **Sì**.
5. Si apre WebcamLR. Se Windows chiede la rete: **Reti private** › **Consenti**.

Disinstallare: Impostazioni › App › WebcamLR › Disinstalla.

### Android: tocca il file

1. Apri **WebcamLR.apk** sul telefono.
2. La prima volta Android chiede il permesso: **Impostazioni** › attiva **Consenti da questa fonte** › torna indietro › **Installa**.
3. Se compare «Play Protect»: **Altri dettagli** › **Installa comunque**.
4. Apri WebcamLR e consenti fotocamera, microfono e notifiche.

### Collegare telefono e computer

1. Telefono e computer sulla **stessa rete Wi-Fi**.
2. Apri WebcamLR sul computer: in basso a sinistra c'è il QR code.
3. Apri WebcamLR sul telefono: il computer compare in «Computer trovati». Toccalo, oppure **Inquadra il QR code**.
4. La prima volta compare un codice di conferma uguale sui due schermi: conferma.
5. In Zoom, Meet o Teams scegli la webcam **WebcamLR**. Su Windows, se l'app era già aperta, chiudila e riaprila.

Il microfono del telefono su Windows funziona solo con VB-CABLE: per una prima prova si può lasciar perdere.

### iPhone dell'amico (scomodo, solo se serve)

L'amico porta l'iPhone da te. Lo attacchi al Mac con il cavo, in Xcode lo scegli in alto e premi **▶**, come per il tuo.
Sull'iPhone: Impostazioni › Generali › VPN e gestione dispositivi › il tuo Apple ID › **Autorizza**. L'app smette di aprirsi
dopo 7 giorni. Con l'Apple ID gratuito puoi farlo con pochi iPhone. Con l'account a pagamento si usa TestFlight: l'amico riceve un link e installa
da solo.

## Cosa chiedere all'amico

- Ha capito da solo come collegarsi? Dove si è bloccato?
- In una videochiamata vera: immagine nitida? Scatti o ritardi?
- Il telefono si scalda? Quanta batteria in 15 minuti?
- Una cosa che gli è piaciuta e una che cambierebbe.
