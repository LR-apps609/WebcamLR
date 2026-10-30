# Windows · installazione e prova, passo passo

Guida per Ledion: cosa installare su un PC Windows 11 nuovo, come compilare WebcamLR, come creare e usare l'installatore,
come scegliere la webcam «WebcamLR» nelle app e come togliere tutto. Windows 10 (22H2) funziona allo stesso modo, con le
differenze scritte nei riquadri «Windows 10».

> Lo stato: scritto e provato su Linux (prove automatiche e compilazione di webcam, filtro e installatore). L'app con la
> finestra e la webcam dentro Windows si possono provare solo sul PC: annota ogni cosa che non va come scritto qui.

## 1. Da installare una volta

1. **.NET 8 SDK a 64 bit** (serve per compilare; il «Runtime» non basta).
   - Apri https://dotnet.microsoft.com/download/dotnet/8.0
   - Nella tabella, colonna **SDK** (la prima a sinistra), riga **Windows**, clic su **x64** (su un PC con processore ARM, come
     i Surface con Snapdragon: **Arm64**).
   - Apri il file scaricato → **Installa** → **Sì** alla domanda di Windows → **Chiudi**.
   - Non serve Visual Studio, non serve il C++, non serve il «Windows App SDK runtime»: WebcamLR lo porta con sé.
2. **Dispositivi Apple** (solo per il cavo USB con l'iPhone): apri **Microsoft Store** → cerca «Dispositivi Apple»
   (in inglese «Apple Devices») → **Ottieni**. Poi collega l'iPhone con il cavo, sblocca il telefono e premi **Autorizza**
   sul telefono. Con il Wi-Fi non serve. Android con il cavo usa il «Tethering USB» del telefono e non chiede nulla al PC.
   - Windows 10: se Dispositivi Apple non si installa, va bene anche **iTunes** dal Microsoft Store.
3. **La repository sul PC**. Il modo più semplice è **GitHub Desktop** (https://desktop.github.com) → File → Clone repository
   → `LR-apps609/WebcamLR`. Se invece scarichi lo zip da GitHub: prima di estrarlo, clic destro sullo zip → **Proprietà** →
   spunta **Sblocca** in basso → **OK**; altrimenti Windows chiede conferma per ogni script.

## 2. Compilare e avviare (sviluppo)

1. Apri la cartella della repository → cartella **Strumenti** → doppio clic su **Costruisci e avvia.bat**.
2. Si apre una finestra nera:
   - «1/3 - Provo…»: le prove automatiche (circa un minuto). Devono finire tutte con «Superato» / «Passed».
   - «2/3 - Compilo WebcamLR…»: la prima volta scarica i pacchetti e ci mette qualche minuto.
   - «3/3 - Avvio WebcamLR»: si apre WebcamLR.
3. Se la finestra dice **«Manca .NET 8 SDK a 64 bit»**: rifai il punto 1.1 e riapri lo script. Se dice
   **«Qualcosa non va»**: fai una foto della finestra (o copia le righe rosse) e mandala a Claude.
4. Alla prima apertura Windows può chiedere **«Consentire a WebcamLR di comunicare su queste reti?»**: spunta **Reti private**
   e premi **Consenti**. Senza, il telefono via Wi-Fi non trova il PC (l'installatore del punto 4 lo fa da solo).
5. Per ricompilare dopo un aggiornamento della repository: stesso doppio clic. WebcamLR aperta viene chiusa da sola.
   Da una finestra del Prompt dei comandi, `"Strumenti\Costruisci e avvia.bat" veloce` salta le prove.

## 3. La webcam per le altre app

### Dalla build di sviluppo

In WebcamLR, scheda **«Webcam per le altre app»** → **Installa la webcam WebcamLR** → **Sì** alla domanda di Windows
(«Autore: Sconosciuto» è normale, WebcamLR non è ancora firmata). Atteso: avviso verde «Webcam installata».

Dopo ogni aggiornamento della webcam (questo giro cambia la memoria condivisa alla versione 3) premi **Ripara la webcam**
(o «Rimuovi» e poi «Installa»): altrimenti la webcam mostra solo «La webcam non è collegata» anche con il telefono collegato.

### Con l'installatore

L'installatore (punto 4) installa o aggiorna la webcam da solo, con un'unica domanda di Windows.

## 4. Creare l'installatore e installare

1. Cartella **Strumenti** → doppio clic su **Crea installer Windows.bat**.
2. Prove, poi «2/2 - Costruisco l'installatore» (alcuni minuti la prima volta). Alla fine si apre la cartella
   **Distribuzione** con **WebcamLR-Setup-1.0.exe** (il numero è la versione di `Strumenti/Versione.xcconfig`).
3. La finestra chiede «Lo installo adesso su questo PC [S,N]?»: **S** per installarlo subito.
4. **Su un altro PC** (o scaricato da Internet) l'installatore non è firmato e Windows lo ferma, una volta:
   - **Edge** dice «WebcamLR-Setup….exe non viene scaricato comunemente»: passa sopra il download → **…** → **Mantieni** →
     **Mostra altro** → **Mantieni comunque**. **Chrome**: **Mantieni** / «Scarica file non verificato».
   - All'apertura: finestra blu **«PC protetto da Windows»** → clic su **Ulteriori informazioni** → **Esegui comunque**.
   - Se invece compare **«Smart App Control ha bloccato…»** non c'è un pulsante per proseguire: Smart App Control
     (Impostazioni → Privacy e sicurezza → Sicurezza di Windows → Controllo app e browser) blocca tutte le app non firmate.
     Per le prove si può disattivare lì; per gli utenti veri serve la firma (`Documenti/Pubblicazione.md`, sezione Windows).
5. L'installatore:
   1. «Installo WebcamLR 1.0 per il tuo utente in C:\Users\…\AppData\Local\Programs\WebcamLR» → **OK**.
   2. Se manca .NET 8 lo scarica da Microsoft (con una domanda di Windows). Sul PC di sviluppo c'è già.
   3. «Installo anche la webcam «WebcamLR» per Zoom, Teams…?» → **Sì** (se era già installata non chiede: la aggiorna).
   4. «Adesso Windows chiede il permesso dell'amministratore…» → **OK**, poi alla domanda di Windows («Autore: Sconosciuto»)
      → **Sì**. È l'unica: copia la webcam in `C:\Program Files\WebcamLR\Webcam`, la registra e aggiunge la regola del
      firewall «WebcamLR» per le reti private.
   5. «WebcamLR è installata: la trovi nel menu Start. Aprirla adesso?» → **Sì**.
6. Controlla: menu Start → **WebcamLR** c'è; Impostazioni → App → App installate → **WebcamLR** (editore LR Apps).
   Windows 11: Impostazioni → Bluetooth e dispositivi → Fotocamere → **WebcamLR (Windows Virtual Camera)**.
   Firewall: Pannello di controllo → Windows Defender Firewall → Impostazioni avanzate → Regole connessioni in entrata →
   **WebcamLR** (profilo Privato).
7. Per aggiornare: crea l'installatore nuovo e aprilo. Impostazioni e telefoni fidati restano.

Opzioni per gli amministratori di rete: `WebcamLR-Setup-1.0.exe /silenzioso /webcam` (senza domande, con la webcam),
`"%LOCALAPPDATA%\Programs\WebcamLR\Disinstalla WebcamLR.exe" /disinstalla /silenzioso`.

> **Windows 10**: la webcam è un filtro DirectShow. «WebcamLR» compare in Zoom, Meet e nei siti (Chrome, Edge, Firefox),
> in OBS e Discord, **non** nell'app Fotocamera di Windows né in Impostazioni → Fotocamere. Il nuovo Teams può non vederla:
> lì usa Teams nel browser.

## 5. Scegliere «WebcamLR» nelle app

Prima apri WebcamLR sul PC e sul telefono e collegali. Le app di chiamata già aperte prima di installare la webcam vanno
**chiuse del tutto** (anche dall'icona accanto all'orologio) e riaperte. Su Windows 11 il nome che vedi è
**«WebcamLR (Windows Virtual Camera)»**: la parte tra parentesi la aggiunge Windows.

- **Fotocamera di Windows** (solo Windows 11): apri Fotocamera → pulsante **Cambia fotocamera** (in alto a destra) finché
  vedi WebcamLR.
- **Zoom**: Zoom → ingranaggio **Impostazioni** → **Video** → **Fotocamera** → WebcamLR. In riunione: freccia accanto a
  **Avvia video** → WebcamLR.
- **Microsoft Teams (nuovo)**: **…** accanto alla foto profilo → **Impostazioni** → **Dispositivi** → **Fotocamera** →
  WebcamLR. In chiamata: **Fotocamera** → freccia → WebcamLR. Prova una chiamata vera: l'altra persona deve vederti.
- **Google Meet in Edge o Chrome**: entra in una riunione → la prima volta il browser chiede la fotocamera → **Consenti**
  → **⋮ Altre opzioni** → **Impostazioni** → **Video** → **Fotocamera** → WebcamLR. Se il browser non chiede nulla:
  lucchetto a sinistra dell'indirizzo → **Fotocamera** → Consenti, poi ricarica la pagina.
- **Altri siti** (Teams o Zoom nel browser, webcamtests.com): stesso permesso del browser, poi la scelta nelle impostazioni
  del sito.
- **OBS**: **Fonti** → **+** → **Dispositivo di acquisizione video** → Dispositivo: WebcamLR.
- **WhatsApp** e **Discord**: Impostazioni → Video (o Voce e video) → Fotocamera → WebcamLR.

### La schermata di attesa

Quando il video del telefono non c'è, chi ti guarda vede la schermata di WebcamLR (fondo verde quasi nero, logo, titolo):

| Quando | Cosa vede chi ti guarda |
| --- | --- |
| Nessun telefono collegato | «La webcam non è collegata» · «Apri WebcamLR sul telefono» |
| WebcamLR chiusa | «WebcamLR è chiusa» · «Apri WebcamLR sul computer» |
| Il telefono si perde durante la chiamata | l'ultima immagine ferma per 2 secondi, poi in mezzo secondo «Collegamento interrotto» · «Riconnessione in corso…» |
| Telefono in pausa | «Webcam in pausa» |
| Il video torna | il video, con la schermata che svanisce in 0,3 secondi |

In italiano se Windows è in italiano, altrimenti in inglese. Con WebcamLR Pro si potranno scegliere nero, un'immagine
propria o l'ultima immagine sfocata (quando la finestra di WebcamLR per Windows avrà la scelta).

## 6. Disinstallare

1. Impostazioni → **App** → **App installate** → **WebcamLR** → **…** → **Disinstalla** → **Disinstalla**.
2. «Disinstallo WebcamLR da questo PC, con la webcam per le altre app?» → **OK** → **Sì** alla domanda di Windows.
3. Controlla: WebcamLR sparisce dal menu Start e da App installate; «WebcamLR» sparisce dalla Fotocamera di Windows e da
   Impostazioni → Fotocamere (senza riavviare); la regola «WebcamLR» del firewall non c'è più; la fotocamera vera del PC
   funziona ancora. Le tue impostazioni restano (una reinstallazione le ritrova).
4. Se alla domanda di Windows hai risposto **No**, l'app si toglie ma la webcam resta: reinstalla e disinstalla di nuovo.

Dalla build di sviluppo la webcam si toglie con **Rimuovi la webcam** nella scheda «Webcam per le altre app».

## 7. Se qualcosa non va, manda

- una foto della finestra o del messaggio;
- `%LOCALAPPDATA%\WebcamLR\Installazione.txt` (installatore e disinstallatore: incolla il percorso in Esplora file);
- `C:\ProgramData\WebcamLR\Installazione webcam.txt` e `C:\ProgramData\WebcamLR\Registro webcam.txt` (webcam di Windows 11);
- `%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt` (Windows 10);
- la versione di Windows: Impostazioni → Sistema → Informazioni.

## 8. Prove di questo giro (W1, parte B)

| # | Prova | Atteso |
| --- | --- | --- |
| B1 | `Costruisci e avvia.bat` su un PC con anche il .NET a 32 bit installato | prove verdi, WebcamLR si apre |
| B2 | Fotocamera di Windows su WebcamLR, telefono non collegato | «La webcam non è collegata · Apri WebcamLR sul telefono», fluida |
| B3 | Collega il telefono, poi spegni il Wi-Fi del telefono | ultima immagine 2 s, poi dissolvenza in «Collegamento interrotto · Riconnessione in corso…»; al ritorno il video. Finché la finestra nuova di WebcamLR non scrive lo stato (aggancio `ImpostaAttesa`, vedi `Windows/FotocameraVirtuale/LEGGIMI.md`) compare «La webcam non è collegata»: annota quale vedi |
| B4 | Chiudi WebcamLR (anche dall'icona) con la webcam aperta in Fotocamera | ultima immagine 2 s, poi «La webcam non è collegata» |
| B5 | Windows in inglese (o un utente con lingua inglese) | testi in inglese: «The webcam is not connected» |
| B6 | Meet in Edge, 1080p e 720p | la schermata nitida, senza strisce nella sfumatura |
| B7 | `Crea installer Windows.bat` | `Distribuzione\WebcamLR-Setup-1.0.exe` e domanda «Lo installo adesso» |
| B8 | Installa su un altro utente Windows o un altro PC (scaricato) | avviso SmartScreen → Ulteriori informazioni → Esegui comunque; una sola domanda di Windows; menu Start, App installate, Fotocamere e regola del firewall come al punto 4.6 |
| B9 | Telefono via Wi-Fi con WebcamLR installata, senza l'avviso del firewall | il telefono trova il PC subito |
| B10 | Disinstalla | tutto sparisce come al punto 6.3, la fotocamera vera funziona |
| B11 | Windows 10: installatore e Chrome su webcamtests.com | «WebcamLR» con la schermata di attesa, poi il video |

## 9. Il microfono del telefono (W2)

Su Windows il microfono del telefono si sente nelle app con un **cavo audio virtuale** (WebcamLR non ne include nessuno):
il perché e le istruzioni complete sono in `Documenti/Microfono Windows.md`, sezione 3.

1. Installa **VB-CABLE** da https://vb-audio.com/Cable/ (zip → clic destro su `VBCABLE_Setup_x64.exe` → **Esegui come
   amministratore** → **Install Driver**) e riavvia.
2. Apri WebcamLR e collega il telefono. Colonna sinistra → **Uscite** → **Microfono del telefono**: accendi l'interruttore.
   In **Manda l'audio a** deve esserci **CABLE Input (VB-Audio Virtual Cable)**.
3. Nell'app di chiamata scegli il microfono **CABLE Output (VB-Audio Virtual Cable)**.

| # | Prova | Atteso |
| --- | --- | --- |
| M1 | Colonna Uscite senza telefono | riga «Microfono del telefono» grigia, interruttore spento e grigio, «Collega un telefono per usarlo.» |
| M2 | Senza VB-CABLE, telefono collegato | sotto la riga: «Su Windows il microfono del telefono si sente nelle app con un cavo audio virtuale…»; tendina su «Nessuna uscita (solo il livello)» |
| M3 | Accendi l'interruttore e parla al telefono (ancora senza cavo) | stato «attivo» in verde, le tacche si muovono con la voce, le ultime due ambra se gridi; nel registro «Audio: aac-lc · 48000 Hz · 1 canale» |
| M4 | Installa VB-CABLE, riapri la tendina | compare «CABLE Input (VB-Audio Virtual Cable)»; sceglilo: nota «Nelle app scegli «CABLE Output (VB-Audio Virtual Cable)» come microfono.» e nel registro «Microfono del telefono verso «CABLE Input…»» |
| M5 | Registratore di suoni di Windows con microfono «CABLE Output», 20 secondi parlando | voce chiara, senza clic, buchi o voce «da robot» |
| M6 | Battito di mani: Fotocamera o OBS con webcam WebcamLR e microfono CABLE Output, registra battendo le mani davanti al telefono | il suono sul fotogramma delle mani che si toccano: annota anticipo o ritardo (un fotogramma = 33 ms) |
| M7 | Zoom (zoom.us/test), Teams e Meet con microfono «CABLE Output» | ti sentono; spegni l'interruttore: silenzio senza clic; riaccendi: la voce torna |
| M8 | Spegni il microfono dal telefono (se l'app del telefono lo permette) | l'interruttore del PC si spegne da solo, nel registro «Microfono spento dal telefono» |
| M9 | Allontanati finché il Wi-Fi peggiora, poi torna | la voce può interrompersi ma senza scoppi; poi riprende |
| M10 | Scollega e ricollega il telefono con l'interruttore acceso | l'audio riparte da solo |
| M11 | Due telefoni: metti l'altro nella webcam | il microfono passa al telefono nella webcam |
| M12 | Scegli le cuffie come uscita | senti la tua voce in cuffia con un piccolo ritardo; nota «Lo senti da «…». Per usarlo nelle chiamate serve un cavo audio virtuale.» |
| M13 | Stacca la cuffia scelta mentre suona | nota «Uscita audio non disponibile: la scheda audio è stata staccata o disattivata.»; WebcamLR non si chiude |
| M14 | OBS 28+: Fonti → Cattura audio applicazione (BETA) → WebcamLR, con uscita le cuffie | in OBS la barra dell'audio si muove con la voce del telefono |
| M15 | Chiudi e riapri WebcamLR | interruttore e uscita scelta come prima |

Se qualcosa non va, manda: uno screenshot della colonna Uscite, il «Registro del collegamento» di WebcamLR (pulsante «Copia»),
il nome esatto dell'uscita audio scelta e la versione di Windows.

## 10. Testi in italiano e inglese (W2)

WebcamLR per Windows parla come iPhone, Mac e Android: **italiano se la lingua dell'interfaccia di Windows è
l'italiano, altrimenti inglese**, con le parole inglesi del Mac (Documenti/Glossario.md, «In inglese»).

### Dove stanno i testi

| Parte | File | Nel codice |
| --- | --- | --- |
| App (finestra, menu, avvisi) | `Windows/WebcamLR.App/Strings/it-IT/Resources.resw` e `Strings/en-US/Resources.resw` | XAML: `x:Uid="Nome"` e le voci `Nome.Text`, `Nome.Content`, `Nome.Header`, `Nome.[using:Microsoft.UI.Xaml.Controls]ToolTipService.ToolTip`, `Nome.[using:Microsoft.UI.Xaml.Automation]AutomationProperties.Name`; C#: `Testi.T("Chiave")` o `Testi.T("Chiave", valori…)` |
| Logica comune (stato, qualità, diagnosi, guida, domande frequenti, avvisi, Pro, registro del cavo) | `Windows/WebcamLR.Ricevitore/Risorse/Testi.resx` (italiano) e `Testi.en.resx` (inglese, finisce in `en\WebcamLR.Ricevitore.resources.dll`) | `TestiRicevitore.T("Chiave", valori…)`, senza WinUI: si prova su Linux |
| Installatore e disinstallatore | nel codice, a coppie | `Testi.S("italiano", "inglese")` (exe autonomo e ridotto: niente file di risorse) |
| Messaggi della webcam (installa, ripara, errori) | `Windows/WebcamLR.Webcam.Logica/StatoWebcam.cs` | `CodiciInstallazione.Descrivi(codice, lingua)` |

I registri (`Installazione.txt`, `Installazione webcam.txt`) e gli script di `Strumenti` restano in italiano.

### Come si sceglie la lingua (app non pacchettizzata)

`Testi.Imposta()`, prima riga del costruttore di `App`, legge `CultureInfo.CurrentUICulture` (la lingua di
visualizzazione dell'utente di Windows) e:

1. imposta `Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride` a `it-IT` o `en-US`:
   è la versione del Windows App SDK (dalla 1.5) che vale anche per le app **senza pacchetto**; quella di
   `Windows.Globalization` funziona solo con il pacchetto MSIX. Non si salva: si imposta a ogni avvio, prima che si
   carichi lo XAML, così gli `x:Uid` escono nella lingua giusta;
2. per il codice crea un `ResourceContext` di MRT Core (`Microsoft.Windows.ApplicationModel.Resources`, non il
   `ResourceLoader` di UWP, che senza pacchetto non trova le risorse) con la lingua scritta esplicitamente: `Testi.T`
   non dipende dall'override;
3. passa la stessa lingua al ricevitore (`Lingua.Imposta`) e alla webcam (schermata di attesa, `Testi.LinguaWebcam`).

I `.resw` li compila il Windows App SDK in `WebcamLR.pri` accanto a `WebcamLR.exe` (l'installatore copia tutta la
cartella). `DefaultLanguage` nel `.csproj` è `en-US`: è solo il ripiego di MRT se l'override non valesse e Windows
non fosse né in italiano né in inglese.

### Come aggiungere un testo

1. **XAML**: dai all'elemento un `x:Uid` (di solito uguale a `x:Name`), togli il letterale e aggiungi la voce
   `Uid.Proprietà` nei **due** `.resw`. **C#**: scrivi `Testi.T("Area_Nome")` (o `TestiRicevitore.T` nel ricevitore) e
   aggiungi `Area_Nome` nei due file; i valori come `{0}`, `{1:0}` (formattati nella lingua: virgola o punto).
2. L'italiano è la lingua di partenza (Glossario); l'inglese usa le stesse parole del Mac
   (`Mac/Risorse/Localizable.xcstrings`), virgolette “…” e apostrofo ’.
3. `python3 Strumenti/controlla_testi_windows.py` (anche su Linux): stesse chiavi e stessi `{0}` nelle due lingue,
   ogni `x:Uid` e ogni `T("…")` con la sua voce, avvisi per i letterali italiani rimasti fuori. Poi
   `dotnet test Windows/WebcamLR.Ricevitore.Test` (LinguaTest controlla i `.resx`).

### Provare l'inglese su Windows

1. Impostazioni → **Ora e lingua** → **Lingua e area geografica** → **Lingua di visualizzazione di Windows** →
   **English (United States)** (se manca: **Aggiungi una lingua** → English (United States) → spunta «Imposta come
   lingua di visualizzazione di Windows»). Windows chiede di **disconnettersi**: fallo, poi rientra.
   In inglese il percorso è Settings → Time & language → Language & region → Windows display language.
2. Apri WebcamLR: tutto in inglese (intestazione «NO PHONE», «Help», «Settings», colonne «DEVICES / CONNECTION /
   OUTPUTS», domande frequenti, diagnosi, notifiche, menu dell'icona accanto all'orologio, numeri con il punto: «1.0×»).
3. Installa con `WebcamLR-Setup` e disinstalla: finestre in inglese («Install WebcamLR … Continue?»).
4. Rimetti **Italiano (Italia)** come lingua di visualizzazione, disconnettiti e rientra: tutto di nuovo in italiano.

Più veloce, senza cambiare la lingua di Windows: un secondo utente di Windows con la lingua inglese.

| # | Prova (Windows in inglese) | Atteso |
| --- | --- | --- |
| E1 | Avvio senza telefono | intestazione «NO PHONE», colonne «DEVICES», «CONNECTION», «OUTPUTS»; nessun testo italiano |
| E2 | Collega il telefono, apri il chip della qualità | «Connected to … · Excellent», numeri «Resolution / Frame rate / Latency», decimali con il punto |
| E3 | Telefono nuovo | «Allow “Pixel 8”?», pulsanti «Allow» / «Don’t Allow» |
| E4 | Aiuto → Guida, FAQ, Report a bug, WebcamLR Pro, About | tutto in inglese; la ricerca nelle FAQ trova anche parole inglesi delle risposte |
| E5 | Scheda «Webcam for other apps»: installa, rimuovi | messaggi in inglese, anche quelli di Windows 10 |
| E6 | Foto e registrazione | «Photo saved to Pictures › WebcamLR», nome del file «WebcamLR 2026-10-26 at 14.05.33.png» |
| E7 | Installatore e disinstallatore | tutte le finestre in inglese, titolo «WebcamLR Setup» |
| E8 | Riga «Phone microphone» nelle Uscite (punto 9) | «Send audio to», «No output (level only)», stato «on» / «off», note e righe del registro in inglese |
| E9 | Di nuovo in italiano | tutto in italiano come prima |
