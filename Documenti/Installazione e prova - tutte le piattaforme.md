# Installazione e prova · tutte le piattaforme (dopo W1 e A1)

Una sola guida per provare tutto insieme: Mac + iPhone, Windows, Android (Samsung S22 Ultra), poi la prova incrociata.
Il ramo è sempre `round-2`. Il codice Swift, l'app Windows (XAML) e l'app Android non sono stati compilati negli ambienti di
Claude: la prima build vera è la tua. Se qualcosa non compila, manda gli errori così come sono (testo o screenshot).

Tempo: circa 1 ora la prima volta (installazioni comprese), poi 15–20 minuti a giro.

## 1 · Mac e iPhone

1. Chiudi Xcode. Terminale: `cd ~/Documents/WebcamLR && git pull`
2. Doppio clic su `Strumenti/Costruisci e installa.command`, rispondi **N** (Apple ID gratuito). Aspetta «Fatto».
3. In Xcode scegli il tuo iPhone in alto e premi **▶**. Gli acquisti sono in prova (file `WebcamLR.storekit`): nessun addebito.
4. Per provare Pro: iPhone › App › **WebcamLR Pro** › «Sblocca Pro» › conferma. Per tornare gratis: Xcode › Debug › StoreKit ›
   Manage Transactions › seleziona › **Refund**.

Errori: gli errori rossi di Xcode e `Strumenti/ultima-build.log`.

## 2 · Windows 11

Guida completa, click per click: `Documenti/Windows - installazione e prova.md`. In breve:

1. Una volta: **.NET 8 SDK x64** (dotnet.microsoft.com › .NET 8.0 › colonna SDK › Windows › x64). Per il cavo con l'iPhone:
   **Dispositivi Apple** dal Microsoft Store.
2. Aggiorna la repository (GitHub Desktop › Fetch/Pull, oppure lo zip di `round-2`: clic destro › Proprietà › Sblocca prima
   di estrarlo).
3. Cartella `Strumenti` › doppio clic su **Costruisci e avvia.bat** (prove → compilazione → si apre WebcamLR).
4. Se Windows chiede la rete: **Reti private** › **Consenti**.
5. In WebcamLR › «Webcam per le altre app» › **Installa la webcam** (o **Ripara la webcam** se c'era già) › Sì.
6. Facoltativo: `Crea installer Windows.bat` e prova l'installatore («Windows ha protetto il PC» › Ulteriori informazioni ›
   Esegui comunque).

Errori: foto della finestra nera o le righe rosse; i file elencati nella sezione 7 della guida Windows.

## 3 · Android (Samsung S22 Ultra)

1. Installa **Android Studio** (gratis, developer.android.com/studio) e aprilo una volta fino alla fine della configurazione.
2. Sul Mac o sul PC aggiorna la repository come sopra.
3. Android Studio › **Open** › scegli la cartella **`Android`** dentro la repository (non quella principale). Aspetta che in
   basso finisca «Gradle sync» (la prima volta scarica l'SDK: qualche minuto). Se chiede di aggiornare il plugin Android,
   rispondi «Remind me later».
4. Sul telefono: **Impostazioni › Info sul telefono › Informazioni software** › tocca 7 volte **Numero build** (inserisci il PIN).
   Poi **Impostazioni › Opzioni sviluppatore** › attiva **Debug USB**.
5. Collega l'S22 Ultra con il cavo, sul telefono **Consenti** il debug USB, in Android Studio scegli il telefono in alto e premi
   **▶ Run**. L'app si installa e si apre con la presentazione.
6. Per provare Pro senza Google Play: App › in fondo **Simula Pro** (c'è solo nella versione di prova).
7. Prove automatiche Android (facoltative): nel pannello a sinistra `app/src/test` › clic destro › **Run Tests**.

Errori: in Android Studio, finestra **Build** in basso: copia le righe rosse (o screenshot). Se l'app si chiude da sola:
finestra **Logcat**, filtro `webcamlr`, screenshot delle righe rosse.

## 4 · Prova incrociata (il giro che conta)

Fai ogni riga con la versione gratis e poi con Pro (o «Simula Pro»). Se una riga non va, mandami il codice con uno screenshot.

| Codice | Telefono → computer | Cosa controllare |
|---|---|---|
| T1 | iPhone → Mac | Collegamento Wi-Fi, video, «Specchia» da entrambi i lati, «Sfoca sfondo», schermata di attesa staccando il Wi-Fi |
| T2 | iPhone → Windows | Come T1; in più la webcam «WebcamLR» nella Fotocamera di Windows e in Zoom; con il cavo USB |
| T3 | Android → Mac | Come T1; il microfono del telefono sul Mac; il telefono a faccia in giù mette in pausa |
| T4 | Android → Windows | Come T2; il cavo con il «Tethering USB» acceso sul telefono |
| T5 | Tutti | Gratis: al massimo 720p 30 fps, segni «PRO» sui comandi Pro. Pro: 1080p e 4K 30, effetti, profili sul computer |
| T6 | Tutti | 10 minuti di videochiamata vera (Zoom o Meet): niente scatti, il ritardo resta basso, il telefono non si scalda troppo |

Le prove di dettaglio restano nelle checklist: `Checklist iPhone e Mac.md` (sezioni X, Y, Z e il resto) e la sezione 8 di
`Windows - installazione e prova.md`.

## 5 · Interfaccia finale (26 ottobre, su tutte e 4 le app)

Disegno di riferimento: https://claude.ai/artifact/65CDbALuvrMyBFwTykXzoQ · specifica: `Interfaccia finale.md`.

| Codice | Dove | Cosa controllare |
|---|---|---|
| U1 | Mac e Windows | Senza telefono: QR in basso a sinistra «Collega il tuo smartphone», al centro la schermata di attesa, pulsanti grigi |
| U2 | Mac e Windows | Con un telefono: il QR dice «Collega un altro smartphone»; sotto il video Specchia · Sfoca · Foto · Registra \| Schermo |
| U3 | Mac e Windows | Clic sull'etichetta della qualità sul video: menu con 720p 30; senza Pro 1080p, 60 fps e 4K grigi con «PRO» |
| U4 | Mac e Windows | Telefono in Wi-Fi con il cavo attaccato: clic su «Wi-Fi ▾» → Automatico / Wi-Fi / Cavo USB con i ms e «più veloce ora»; la scelta cambia strada senza fermare il video |
| U5 | Tutte | Automatico: attacca il cavo (passa al cavo una volta), staccalo (torna al Wi-Fi), riattaccalo entro 30 s (resta sul Wi-Fi, poi passa al cavo) |
| U6 | Mac e Windows | In alto a destra Aiuto e Account; dentro Account: WebcamLR Pro, Preferenze, Telefoni conosciuti, Lingua, Aggiornamenti, Informazioni |
| U7 | Tutte | Due telefoni (serve Pro o «Simula Pro»): sul computer compare CAM 2 dentro il video con «Usa prospettiva»; il telefono non in webcam mostra «PRONTA · CAM 2» e «Usa questa prospettiva»; da entrambi i lati si scambiano |
| U8 | iPhone e Android | «In onda»: colonna di pulsanti tondi a destra (Specchia, Sfoca, Microfono, Pausa, Luce), obiettivi in basso |
| U9 | iPhone e Android | In orizzontale: dopo 5 s restano solo «IN ONDA» e «Tocca per i comandi»; un tocco li riporta |
| U10 | iPhone e Android | Computer chiuso: «Cerco il tuo computer…», dopo 15 s «Non trovo nessun computer» con i tre controlli; aprendo WebcamLR sul computer compare in «Computer trovati» |

## 6 · Farla provare a un amico

Windows con un doppio clic sull'installatore, Android con il file `.apk`: tutto in `Far provare a un amico.md`.

## Cosa mandarmi alla fine

1. Quali build sono riuscite (Mac, iPhone, Windows, Android) e gli errori di quelle che non sono riuscite.
2. I codici T1–T6 e U1–U10 che non vanno, con screenshot.
3. Un'impressione generale: cosa ti è piaciuto e cosa no.
