# Round 0 · checklist di test

Il codice Swift è stato scritto senza poterlo compilare (nell'ambiente di Claude non c'è Xcode): è normale che al primo giro escano errori di compilazione. Mandali così come sono.

## Mac

- [ ] `Strumenti/Costruisci e installa.command` arriva fino a «Fatto»
- [ ] WebcamLR si apre e nella colonna di sinistra dice «Visibile in rete · porta 52740»
- [ ] L'icona compare nella barra in alto e il menu si apre
- [ ] **Controllo di passaggio:** «Attiva la webcam virtuale» → approvo in Impostazioni di Sistema → lo stato diventa «attiva». Se compare l'errore sul permesso mancante, serve l'account sviluppatore a pagamento: mandami il messaggio esatto
- [ ] Con la webcam attiva: in FaceTime o Photo Booth compare la videocamera «WebcamLR» con fondo scuro e una barra ciano che scende

## iPhone

- [ ] Il progetto si apre in Xcode e l'app si installa sull'iPhone
- [ ] Al primo avvio chiede il permesso «Rete locale»
- [ ] Con WebcamLR aperta sul Mac, la schermata «Scegli il computer» mostra il Mac entro pochi secondi
- [ ] «Collega» apre la schermata segnaposto «Collegamento a …»

## Windows

- [ ] `Strumenti/Costruisci e avvia.bat` passa i test del protocollo e apre la finestra di WebcamLR
- [ ] La finestra ha le tre colonne della bozza e l'avviso giallo sul microfono
