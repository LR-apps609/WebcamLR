# WebcamLR · note per Claude

- Lingua: tutto in italiano (interfaccia, nomi di tipi e variabili, commenti, commit). I nomi delle API di sistema restano come sono.
- Metodo come OrbitLR: lavoro a round (piano nel documento di progetto, link nel README). Ogni round chiude alcune funzioni numerate 1–40 e arriva con una checklist di test breve. Ledion compila e prova su dispositivi veri e manda esito, screenshot o log.
- Il protocollo è definito in `Documenti/Protocollo.md`. Ogni modifica va fatta lì e in tutte le implementazioni (Swift in `Protocollo/`, C# in `Windows/WebcamLR.Protocollo/`), con i test aggiornati: i due test «CiaoComeNelDocumento» devono produrre lo stesso JSON.
- Progetti Xcode generati da XcodeGen (`project.yml`): non aggiungere `.xcodeproj` alla repository.
- Mac: `Mac/base.yml` è la parte comune; `project-senza-account.yml` (Apple ID gratuito, senza webcam virtuale) e `project.yml` (account a pagamento, con la Camera Extension) la includono. Per ora Ledion usa l'Apple ID gratuito: tutto ciò che non è la webcam virtuale deve funzionare senza account.
- In questo ambiente Linux non ci sono Swift né Xcode: il codice Swift non si può compilare qui, va detto chiaramente. Il protocollo C# si prova con `dotnet test Windows/WebcamLR.Protocollo.Test`.
- Grafica: colori, caratteri e componenti stanno nel pacchetto `Stile/` (iPhone e Mac); non ridefinirli nelle app. Windows ha gli stessi valori in `App.xaml`. Colori e stati come nella bozza (link nel README). Il rosso tally solo per «in onda» e registrazione; azioni e selezione in ciano.
- Tutto nativo: niente Flutter o React Native nella pipeline video. Codec solo hardware di sistema, nessuna libreria GPL.
