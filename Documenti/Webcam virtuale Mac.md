# Webcam virtuale sul Mac · attivazione, prove, rimozione

La webcam virtuale (funzione 11) è una **Camera Extension** di macOS (`Mac/FotocameraVirtuale/`). Le altre app la vedono come una videocamera chiamata **WebcamLR**: FaceTime, Photo Booth, Zoom, Teams, Meet in Chrome o Safari, WhatsApp, Discord, OBS. Le compatibilità attese e le fonti sono in `Compatibilità webcam.md`.

## Cosa fa

- Due formati: **1920×1080** e **1280×720**, tutti e due a **30 fps**. Ogni app sceglie quello che preferisce.
- Il video dell'iPhone entra intero. Se il telefono è in verticale, ai lati ci sono le **bande scure** di WebcamLR (il fondo di Stile), non nere.
- Se per più di 1 secondo non arrivano immagini (telefono non collegato, WebcamLR chiusa, rete caduta) le app vedono l'**immagine di attesa**: «WebcamLR · Apri WebcamLR sul telefono». Non vedono mai nero o un'immagine ferma.
- Il video in uscita **non è mai specchiato**. Le app di chiamata specchiano da sole l'anteprima di te stesso: nella tua anteprima la scritta dell'immagine di attesa appare al contrario, ma chi ti guarda la legge dritta. È normale. «Specchia» su WebcamLR per Mac cambia solo l'anteprima nella finestra di WebcamLR. «Specchia» sul telefono (funzione 25) invece specchia il video inviato, quindi anche la webcam: lascialo spento.
- **In onda**: quando un'app usa la webcam, WebcamLR per Mac e il telefono mostrano «IN ONDA» in corallo. Quando l'ultima app la lascia, il corallo si spegne. L'app controlla una volta al secondo.
- **Quale app**: l'estensione annota la firma di ogni app che avvia il video (`authorizedToStartStream`, per esempio `us.zoom.xos`) e la pubblica nella proprietà personalizzata «appl», una per riga (accanto a «inon» e «fmto»). Sul Mac la scheda di quell'app, sotto il video, dice «In uso»; un'app fuori elenco è «Altra app». Un'app esce dall'elenco quando si scollega dall'estensione o quando nessuna app usa più la webcam: CoreMediaIO non dice quale app ferma il video, quindi un'app che chiude il video ma resta aperta può restare «In uso» finché anche le altre non smettono.

## Cosa serve

1. **Account sviluppatore Apple a pagamento.** Con l'Apple ID gratuito la webcam virtuale non c'è: l'app scrive «Richiede l'account sviluppatore Apple a pagamento» e tutto il resto funziona.
2. In `Strumenti/account.txt` scrivi `completo` e in `Strumenti/team.txt` il Team ID (10 caratteri: Xcode › Impostazioni › Account).
3. Doppio clic su `Strumenti/Costruisci e installa.command`. Lo script mette WebcamLR in **Applicazioni**: macOS attiva la webcam virtuale solo da lì, non da Download né dalla cartella della build.

## Attivazione (una volta sola)

1. Apri WebcamLR da **Applicazioni**.
2. Nella colonna **Uscite** premi **«Attiva la webcam virtuale»**.
3. macOS mostra l'avviso «Estensione di sistema bloccata» e WebcamLR apre da sola le Impostazioni di Sistema. Se non si aprono, premi **«Apri Impostazioni di Sistema»** in WebcamLR.
4. Approva WebcamLR:
   - **macOS 15 Sequoia e successivi** (anche macOS 26): Impostazioni di Sistema → **Generali** → **Elementi di login ed estensioni** → in fondo, **Estensioni videocamera** → pulsante **ⓘ** → accendi **WebcamLR** → **Fine**.
   - **macOS 14 Sonoma**: Impostazioni di Sistema → **Privacy e sicurezza** → in basso, accanto a «WebcamLR», premi **Consenti**.
   - Se macOS chiede la password o Touch ID, inseriscila.
5. Torna in WebcamLR: accanto a «Webcam virtuale» deve esserci **attiva**. Se c'è «riavvia il Mac», riavvialo.
6. La prima volta WebcamLR chiede anche il permesso della **Fotocamera**: premi **Consenti**. Le serve per mettere il video dell'iPhone nella webcam virtuale.
7. **Chiudi del tutto (⌘Q) e riapri le app che erano già aperte.** Molte app leggono l'elenco delle videocamere solo all'avvio: Zoom, Teams, Discord, WhatsApp, OBS, FaceTime, Photo Booth e i browser. Nei browser a volte basta ricaricare la pagina, ma con Chrome è più sicuro chiuderlo con ⌘Q.

Dopo l'attivazione non serve rifare nulla. Ogni nuova build dello script installa da sola la nuova versione dell'estensione all'apertura di WebcamLR, senza chiedere un'altra approvazione. Il numero di build dell'estensione cambia a ogni compilazione.

## Dove si sceglie «WebcamLR» nelle app

| App | Dove |
|---|---|
| FaceTime | menu **Video** → WebcamLR |
| Photo Booth | menu **Videocamera** → WebcamLR |
| Zoom | Impostazioni → **Video** → Videocamera → WebcamLR (prova: https://zoom.us/test) |
| Teams | Impostazioni → **Dispositivi** → Fotocamera → WebcamLR |
| Meet in Chrome | prima della riunione, icona della videocamera → WebcamLR (o ⋮ → Impostazioni → Video) |
| Meet in Safari | Safari → Impostazioni per questo sito web → Fotocamera: Consenti; poi in Meet → WebcamLR |
| WhatsApp | durante la videochiamata, menu della videocamera → WebcamLR |
| Discord | Impostazioni utente → **Voce e video** → Fotocamera → WebcamLR → «Prova video» |
| OBS | Fonti → **+** → **Dispositivo di cattura video** → Dispositivo: WebcamLR |

Ogni app ha bisogno del permesso della **Fotocamera** (Impostazioni di Sistema → Privacy e sicurezza → Fotocamera), come per una webcam vera. Per Chrome e Safari è il permesso del browser.

## Prove (checklist)

Segna ✅/❌ e manda uno screenshot per ogni ❌.

1. Attivazione: quanti passi e quanti secondi ci sono voluti? WebcamLR scrive «attiva»?
2. Telefono **non collegato**, Photo Booth aperto su WebcamLR: si vede l'immagine «WebcamLR · Apri WebcamLR sul telefono» (fondo scuro, scritta chiara, tratto ciano), non nero.
3. Colleghi il telefono: entro un secondo Photo Booth mostra il video. Telefono in verticale: bande scure ai lati, niente tagli, niente stiramenti.
4. Con Photo Booth aperto, WebcamLR per Mac e il telefono mostrano «IN ONDA» in rosso. Chiudi Photo Booth (⌘Q): entro 2 secondi il rosso si spegne su tutti e due.
5. FaceTime: l'anteprima è specchiata (normale). In una chiamata vera l'altra persona ti vede dritto: prova con una scritta su un foglio.
6. Zoom (https://zoom.us/test), Teams (riunione immediata con un secondo account), Meet in Chrome e in Safari, WhatsApp, Discord («Prova video»), OBS: WebcamLR compare in elenco? L'anteprima si vede? **L'altra persona vede il video?**
7. https://webcamtests.com in Chrome e in Safari: risoluzione **1920×1080** o **1280×720**, circa **30 fps**.
8. Stacca il telefono durante una chiamata: entro un secondo l'altra persona vede l'immagine di attesa, non nero e non un'immagine ferma. Ricollegalo: il video torna senza riavviare l'app di chiamata.
9. Chiudi WebcamLR per Mac durante una chiamata: l'app di chiamata mostra l'immagine di attesa e non va in errore. Riapri WebcamLR: il video torna da solo in pochi secondi.
10. Due app insieme (Photo Booth e OBS): si vede in tutte e due. Chiudendone una sola, «IN ONDA» resta acceso.
11. Apri Zoom **prima** di WebcamLR per Mac: WebcamLR compare comunque (la webcam esiste anche con WebcamLR chiusa).
12. Ricostruisci con lo script con un'app di chiamata aperta: dopo la riapertura di WebcamLR la webcam funziona ancora, senza nuova approvazione (al massimo va scelta di nuovo nell'app di chiamata: annota se è servito).
13. Rimozione (sotto): «WebcamLR» sparisce dagli elenchi e la videocamera del Mac funziona ancora.

## Se qualcosa non va

| Cosa vedi | Cosa fare |
|---|---|
| «Sposta WebcamLR nella cartella Applicazioni» | Usa lo script, oppure trascina WebcamLR in Applicazioni e aprila da lì |
| «Manca il permesso per installare la webcam virtuale» | Il progetto è stato costruito con l'Apple ID gratuito: controlla `Strumenti/account.txt` (`completo`) e il team in Xcode |
| «Firma non valida» | Controlla il Team ID in `Strumenti/team.txt` e ricostruisci |
| Resta «da approvare» | Rifai il passo 4 dell'attivazione. Se nelle Impostazioni non c'è la voce WebcamLR, premi di nuovo «Attiva la webcam virtuale» |
| WebcamLR non compare in un'app | Chiudi l'app con ⌘Q e riaprila. Controlla il permesso della Fotocamera per quell'app |
| L'app mostra sempre l'immagine di attesa, anche col telefono collegato | Chiudi e riapri WebcamLR per Mac (deve avere il permesso della Fotocamera: Impostazioni di Sistema → Privacy e sicurezza → Fotocamera → WebcamLR) |

Per Claude, se serve un registro: in **Terminale**

```
systemextensionsctl list
log stream --predicate 'subsystem BEGINSWITH "it.lrapps.webcamlr.mac"' --level info
```

La prima riga dice se l'estensione è «activated enabled». La seconda mostra cosa fanno l'estensione e l'app mentre provi: copia le righe e mandale.

## Rimozione

1. Apri WebcamLR e premi **«Rimuovi la webcam virtuale»** (sotto «Webcam virtuale», quando è attiva). macOS può chiedere la password. Se WebcamLR scrive «riavvia il Mac», riavvialo.
2. Chiudi WebcamLR (menu WebcamLR → Esci).
3. Trascina WebcamLR da Applicazioni nel Cestino. Se macOS chiede di rimuovere anche l'estensione, conferma.
4. Controlla in FaceTime o Photo Booth che «WebcamLR» non ci sia più. Le app aperte durante la rimozione possono mostrarla finché non le riapri.

Se hai già cestinato l'app senza il passo 1: rimettila in Applicazioni (dal Cestino o con lo script), aprila e fai il passo 1. In alternativa spegni WebcamLR in Impostazioni di Sistema → Generali → Elementi di login ed estensioni → Estensioni videocamera (ⓘ). Non serve, e non va fatto, disattivare la protezione di sistema (SIP) per usare `systemextensionsctl uninstall`.
