# Glossario · le parole di WebcamLR

Per testi chiari e uguali in tutte le app, sul sito e nella guida. Dove esiste, si usa il termine di Apple in italiano (iOS e macOS), perché è quello che le persone già conoscono. Riferimenti: le impostazioni di iOS e macOS in italiano, la funzione Videocamera Continuity di Apple, le app concorrenti (Camo, iVCam, EpocCam).

## Da usare

| Concetto | Parola | Note |
| --- | --- | --- |
| La fotocamera dell'iPhone | **fotocamera** | come in iOS: «Fotocamera», «fotocamera frontale» |
| La webcam per le app di chiamata | **videocamera** | come nelle impostazioni di Zoom, Teams, FaceTime: «scegli WebcamLR come videocamera» |
| Obiettivi | **Grandangolo 0,5×**, **Principale 1×**, **Tele**, **Frontale** | |
| Messa a fuoco | **messa a fuoco**, «Messa a fuoco automatica» | non «fuoco» da solo |
| Esposizione e fuoco bloccati | **Blocco AE/AF**, «AE/AF bloccati» | come nella Fotocamera di iOS |
| Bilanciamento del bianco | **bilanciamento del bianco** | in breve «bianco» solo dove manca spazio |
| ISO e tempo di posa | **ISO**, **tempo** (1/50 s) | |
| Fotogrammi al secondo | **fps** nei numeri, «fotogrammi al secondo» nelle frasi | |
| Il video passa a un'app | **In onda** | il termine della regia TV; unico caso di corallo (con la registrazione) |
| Collegarsi | **Collega**, **Scollega**, «Collegato» | non «connetti», «disconnetti», «disconnesso» |
| Ricollegarsi da solo | «Mi ricollego…», «Riconnessione» | |
| Qualità del collegamento | **Ottimo / Buono / Debole** | |
| La rete dei due dispositivi | **stessa rete Wi-Fi** | non «LAN», «subnet» |
| Hotspot | **Hotspot personale** | come in iOS |
| Permesso di rete dell'iPhone | **Rete locale** | Impostazioni › Privacy e sicurezza › Rete locale |
| Codice di 4 cifre al primo collegamento | **codice di conferma** | |
| Impronta della chiave (protocollo) | **codice di sicurezza** | nell'interfaccia mai «impronta» (fa pensare a Touch ID) né «chiave», «hash», «fingerprint» |
| Telefoni accettati dal computer | **telefoni fidati** | |
| Computer già usati dall'iPhone | **computer conosciuti** | |
| Effetti di Apple | **Effetti video**, **Ritratto**, **Luce da studio** | i nomi di Apple, invariati |
| Schermo nero del telefono | **Oscura** | |
| Finestra sempre in primo piano | **Finestra mini** | |
| Segnalazioni | **Segnala un bug** | scelto da Ledion |
| Abbonamento | **WebcamLR Pro** | |
| Senza account | **Modalità senza account** | |
| Il video fermo, il collegamento resta | **In pausa** | col motivo: «In pausa: WebcamLR è in sottofondo», «In pausa dal telefono»; in ambra, mai in corallo |
| L'app del telefono non è in primo piano | **in sottofondo** | «WebcamLR è in sottofondo sul telefono: riaprila per riprendere»; mai «background» |
| La schermata d'attesa che vedono le app di chiamata | **Webcam in pausa** | |
| Chiudere l'app del computer | **Esci da WebcamLR** | Mac ⌘Q, Windows anche nella finestra; «Esci» da solo solo come pulsante della domanda di uscita e per lasciare una vista («Esci dalla vista pulita», «Esci dallo schermo intero») |
| Aprire la cartella di un file | **Mostra nel Finder** (Mac), **Mostra nella cartella** (Windows) | nell'avviso di foto e registrazioni, invece di aprire la cartella da sola |
| Disco quasi pieno mentre si registra | **Spazio quasi finito** | «Spazio quasi finito: restano circa 5 minuti» |
| Registrazione solo video | **senza audio** | «Registra il video del telefono, senza audio, …»; va detto, non nascosto |
| Tornare al profilo dopo una modifica | **Torna a «Riunione»** | accanto a «Personalizzato» |
| Icona di stato fuori dalla finestra | **icona nella barra dei menu** (Mac), **icona accanto all'orologio** (Windows) | il nome di Windows è «area di notifica»: nei testi si dice «accanto all'orologio» |

## Da evitare nell'interfaccia

`stream` (→ video), `streaming` (solo come uso: «per lo streaming»), `device` (→ dispositivo / telefono), `pairing` (→ abbinamento), `handshake`, `TLS`, `chiave`, `impronta`, `gettone`, `token`, `bitrate` (→ qualità), `encoder` / `codec` (solo in Impostazioni › Formato), `frame` (→ fotogramma), `lag` (→ ritardo), `reconnect`, `timeout`, `errore sconosciuto` (dire sempre cosa fare).

## Tono

- Frasi brevi, seconda persona singolare («Collega l'iPhone…»).
- Ogni errore dice **cosa fare**, non solo cosa è successo.
- Numeri all'italiana: virgola decimale («0,5×», «8,4 MB»), spazio prima delle unità («51 ms»).
- Virgolette basse «…» per i nomi di pulsanti e voci.

## In inglese (P22)

L'italiano resta la lingua di partenza: nel codice la chiave di ogni testo è la frase italiana, la traduzione inglese sta nei cataloghi (`iPhone/Risorse/Localizable.xcstrings`, `Stile/Sources/Stile/Resources/Localizable.xcstrings`, controllati da `Strumenti/estrai_testi.py`). Con il telefono in italiano l'app è in italiano; in qualsiasi altra lingua è in inglese. Mac, Windows e Android usano le stesse parole. Su Windows i testi stanno in `Windows/WebcamLR.App/Strings/*/Resources.resw` e `Windows/WebcamLR.Ricevitore/Risorse/Testi*.resx`, con chiavi a nome (`Area_Nome`) invece della frase italiana, controllati da `Strumenti/controlla_testi_windows.py` (Documenti/Windows - installazione e prova.md, punto 10). Su Android i testi stanno in `values/strings.xml` (italiano) e `values-en/strings.xml` (inglese), anche quelli fuori dall'interfaccia (errori della sessione, avviso «Video al computer», registro: `sistema/Testi.kt`), controllati da `Strumenti/controlla_testi_android.py`. Il registro del collegamento si vede nell'app: le sue righe si traducono come gli altri testi, su tutte le piattaforme. Dove esiste si usa il termine di Apple in inglese (iOS e macOS in inglese, Continuity Camera).

| Italiano | English | Note |
| --- | --- | --- |
| fotocamera (dell'iPhone) | **camera** | «fotocamera frontale» → «front camera», «posteriore» → «back camera» |
| videocamera (nelle app di chiamata) | **camera** | «choose WebcamLR as the camera» |
| Grandangolo 0,5×, Principale 1×, Tele, Frontale | **Ultra Wide 0.5×**, **Main 1×**, **Tele** (per esteso **Telephoto**), **Front** | punto decimale in inglese |
| messa a fuoco, Messa a fuoco automatica | **focus**, **Autofocus** | «Messa a fuoco manuale» → «Manual focus» |
| Blocco AE/AF, AE/AF bloccati | **AE/AF Lock** | come la Fotocamera di iOS |
| bilanciamento del bianco | **white balance** | «Bilanciamento del bianco automatico» → «Auto white balance» |
| ISO, tempo (di posa) | **ISO**, **shutter** (**shutter speed**) | «ISO automatico» → «Auto ISO», «Tempo automatico» → «Auto shutter» |
| fotogrammi al secondo, Fotogrammi | **fps**, **frame rate** | |
| In onda | **Live** | unico caso di corallo; «In onda su Mac» → «Live on Mac» |
| Collega, Scollega, Collegato, Scollegato | **Connect**, **Disconnect**, **Connected**, **Disconnected** | |
| Mi ricollego…, Riconnessione | **Reconnecting…**, **Reconnecting** | |
| Ottimo / Buono / Debole | **Excellent / Good / Weak** | |
| stessa rete Wi-Fi | **same Wi-Fi network** | |
| Hotspot personale | **Personal Hotspot** | come in iOS |
| Rete locale | **Local Network** | Settings › Privacy & Security › Local Network |
| Impostazioni (di iOS e dell'app) | **Settings** | «Impostazioni › WebcamLR» → «Settings › WebcamLR» |
| codice di conferma | **confirmation code** | |
| codice di sicurezza | **security code** | mai «fingerprint», «key», «hash» |
| telefoni fidati | **trusted phones** | |
| computer conosciuti | **known computers** | |
| Consenti | **Allow** | |
| Riprova, Riprova ora | **Try again**, **Try now** | |
| Fine (pulsante) | **Done** | |
| Effetti video, Ritratto, Luce da studio | **Video Effects**, **Portrait**, **Studio Light** | i nomi di Apple |
| Effetti, Filtri, Regolazioni, Sfondo, Ritocco | **Effects**, **Filters**, **Adjustments**, **Background**, **Retouch** | «Sfocato» → «Blurred», «Sostituito» → «Replaced», «Ritocco della pelle» → «Skin smoothing» |
| Scritta e logo | **Caption and logo** | |
| Oscura (lo schermo) | **Darken (screen)** | |
| Finestra mini | **Mini window** | |
| Segnala un bug | **Report a bug** | |
| Domande frequenti | **FAQ** | |
| Guida | **Guide** | |
| WebcamLR Pro, Controlli Pro | **WebcamLR Pro**, **Pro controls** | |
| Modalità senza account | **No-account mode** | |
| Registro del collegamento | **Connection log** | nelle Impostazioni dell'iPhone sotto «Diagnosi» (**Diagnostics**) |
| Compatibile con | **Works with** | sostituita da «Disponibile per …» (vedi sotto) |
| Gobbo | **Teleprompter** | |
| Assistente | **Assistant** | |
| Inquadratura automatica | **Auto framing** | |
| Luce sul volto | **Face lighting** | |
| Promemoria della postura | **Posture reminders** | |
| Pausa a faccia in giù | **Pause when face down** | |
| Prova la webcam | **Webcam check** | «Prova di nuovo» → «Check again», «Sistema» → «Fix it» |
| Volto + scrivania (Volto e scrivania) | **Face + desk** | «Affiancate» → «Side by side», «Scrivania e riquadro» → «Desk with inset» |
| Griglia dei terzi, Livella | **Rule-of-thirds grid**, **Level** | |
| Microfono al computer | **Microphone to computer** | |
| Torcia | **Flashlight** | |
| Collega il tuo telefono, Collega un altro telefono | **Connect your phone**, **Connect another phone** | sul computer, il QR per collegarsi: senza telefoni è al centro della finestra. «Collega con QR code» non c'è più. «Telefono», mai «smartphone» (decisione di Ledion) |
| Inquadra il QR code del computer | **Scan the computer’s QR code** | sul telefono |
| Cavo USB, Via cavo USB | **USB cable**, **Via USB cable** | |
| Wi-Fi diretto | **Wi-Fi Direct** | |
| Cavo di rete | **Ethernet cable** | |
| Tethering USB (Android) | **USB tethering** | |
| Dispositivi Apple (Windows) | **Apple Devices** | l'app di Microsoft Store |
| Profili: Riunione, Dirette, Ritratto | **Meeting**, **Live streams**, **Portrait** | sul telefono |
| Profilo (Mac e Windows): Riunione, Lezione, Diretta, Colloquio, Personalizzato | **Profile**: **Meeting**, **Lesson**, **Live stream**, **Interview**, **Custom** | i profili pronti in cima alla colonna di destra; «Profili salvati» → **Saved profiles**. «Lezione» usa **una sola fotocamera** (niente «Volto e scrivania»): «Una fotocamera, inquadratura ferma» → **One camera, steady framing** |
| Dispositivi, Connessione, Uscite | **Devices**, **Connection**, **Outputs** | le sezioni della colonna di sinistra del Mac |
| App per il telefono | **Phone app** | il QR per scaricare l'app, diverso da «Collega il tuo telefono» |
| In pausa, In pausa dal telefono | **Paused**, **Paused from the phone** | «In pausa: …» → «Paused: …» |
| in sottofondo | **in the background** | «WebcamLR è in sottofondo sul telefono…» → «WebcamLR is in the background on the phone…» |
| Webcam in pausa | **Webcam paused** | |
| Esci da WebcamLR | **Quit WebcamLR** (Mac), **Exit WebcamLR** (Windows) | il verbo di ogni sistema; «Esci dalla vista pulita» → «Exit clean view» |
| Mostra nel Finder, Mostra nella cartella | **Show in Finder**, **Show in folder** | |
| Spazio quasi finito | **Almost out of space** | |
| senza audio | **without audio** | |
| Torna a «…» | **Back to “…”** | |
| icona nella barra dei menu, icona accanto all'orologio | **menu bar icon**, **icon next to the clock** | |
| Disponibile per Zoom · Slack · OBS · Meet e tanti altri; In uso da Zoom, In uso da un'altra app | **Works with Zoom · Slack · OBS · Meet and many more**; **In use by Zoom**, **In use by another app** | la riga in fondo sotto il video (Mac e Windows); «In uso da» in corallo: per quell'app il video è in onda. Nomi delle app in testo con un segno neutro, mai i loghi ufficiali |
| Regole fini, Qualità video | **Fine controls**, **Video quality** | ISO, tempo, bianco e regolazioni; risoluzione e fps |
| Aggiornamento disponibile, Scarica, Più tardi | **Update available**, **Download**, **Later** | |

Tono in inglese: frasi brevi, seconda persona («Plug the iPhone into the computer…»), ogni errore dice cosa fare. Virgolette inglesi curve “…” per i nomi di pulsanti e voci, apostrofo tipografico (’). Numeri all'inglese: punto decimale («0.5×»), spazio prima delle unità («51 ms»).

## Colori (Stile/Sources/Stile/Tema.swift)

| Ruolo | Colore | Nome nel codice |
| --- | --- | --- |
| Fondo della finestra, colonne, pannelli | verde scuro #13211D, #172824, #1A2B26, #22352F | `Tema.fondo`, `barraLaterale`, `pannello`, `pannelloChiaro` |
| Sfumatura del logo | #30453E → #0D1B18 | `Tema.sfumaturaChiara`, `sfumaturaScura` |
| Testo, testo secondario | quasi bianco #E6EEEA, salvia #9DB0A7 | `Tema.testo`, `testoSecondario` |
| Azioni e selezione | salvia chiaro #9FD0B6 | `Tema.accento` (anche `Tema.ciano`) |
| Collegato, pronto | verde salvia #86C79C | `Tema.verde` |
| In onda e registrazione | corallo #E67A67 | `Tema.tally` (solo qui) |
| Avvisi | ambra #E3B162 | `Tema.ambra` |
