# WebcamLR · note per Claude

## Documento della verità: regole

Documento: [WebcamLR · Documento della verità](https://claude.ai/artifact/Bhzkpo3Sn2RtTWvANUHknK), pagina privata su claude.ai con le schede Inizia qui · Test da fare · Link · Stato · Diario · Decisioni e regole · Come si fa · Archivio. Non condividerla senza l'ok di Ledion.

- Pagina e dati sono separati: i dati stanno nel database della pagina (raccolte `meta`, `test`, `bug`, `funzioni`, `diario`, `link`, `regole`, `decisioni`, `scartate`, `comefare`, `archivio`, `cambiamenti`). Un aggiornamento è una scrittura di righe con lo strumento ArtifactData; la pagina si ripubblica solo se cambia l'aspetto.
- Prima di ogni aggiornamento rileggi le righe dal database, non dalla memoria. Se una scrittura non riesce, dillo a Ledion.
- Date come 04/11/2026 · 13:45, ora italiana, prese da `TZ=Europe/Rome date` o dai commit. Ogni riga ha `creata` e `modificata`; a ogni scrittura aggiorna `meta/pagina.schede.<scheda>` e `meta/pagina.aggiornato` e aggiungi una riga in `cambiamenti`.
- Ogni cambiamento da verificare crea il suo test (raccolta `test`) insieme alla voce del Diario. Un test fallito diventa un bug in `bug`, collegato al test.

- Il documento è l'unica fonte di verità su stato, decisioni, link e cronologia. Se un altro file o pagina dice altro, vale il documento. Se il codice dice altro, verifica e correggi uno dei due.
- All'inizio di ogni lavoro: leggi «Inizia qui» e «Diario», confronta il Diario con gli ultimi commit e aggiungi quello che manca.
- Aggiorna il documento quando inizi un lavoro (voce 🔄), a ogni versione, rilascio o unione di rami, quando ti blocchi o aspetti Ledion, quando Ledion decide qualcosa e quando finisci (con tempi e difficoltà). Mai dire «fatto» senza averlo aggiornato.
- Niente nuovi documenti di appunti, piani o resoconti: va tutto nel documento. Restano fuori solo i file che servono all'app, alla compilazione, agli store o al sito. NOVITA resta per gli utenti, il Diario è per noi: si aggiornano insieme.
- Oltre 30 voci nel Diario, le più vecchie vanno in Archivio con un riassunto. I test passati restano visibili 7 giorni, poi finiscono in Archivio da soli.
- Niente password, chiavi o codici segreti nel documento.

## Note tecniche

- Lingua: tutto in italiano (interfaccia, nomi di tipi e variabili, commenti, commit). I nomi delle API di sistema restano come sono.
- Metodo come OrbitLR: lavoro a round (piano e stato nel Documento della verità). Ogni round chiude alcune funzioni numerate 1–40 e arriva con una checklist di test breve. Ledion compila e prova su dispositivi veri e manda esito, screenshot o log.
- Il protocollo è definito in `Documenti/Protocollo.md`. Ogni modifica va fatta lì e in tutte le implementazioni (Swift in `Protocollo/`, C# in `Windows/WebcamLR.Protocollo/`, Kotlin in `Android/protocollo/`), con i test aggiornati: i tre test «CiaoComeNelDocumento» devono produrre lo stesso JSON. Il Kotlin si prova con `gradle -PsoloProtocollo :protocollo:test` dentro `Android/` (il flag esclude `:app`, così non servono l'Android SDK né il plugin Android; senza il flag `:app` è sempre inclusa, come serve ad Android Studio. L'app Android qui non si compila).
- Progetti Xcode generati da XcodeGen (`project.yml`): non aggiungere `.xcodeproj` alla repository.
- Mac: `Mac/base.yml` è la parte comune; `project-senza-account.yml` (Apple ID gratuito, senza webcam virtuale) e `project.yml` (account a pagamento, con la Camera Extension) la includono. Per ora Ledion usa l'Apple ID gratuito: tutto ciò che non è la webcam virtuale deve funzionare senza account.
- In questo ambiente Linux non ci sono Swift né Xcode: il codice Swift non si può compilare qui, va detto chiaramente. Il protocollo C# si prova con `dotnet test Windows/WebcamLR.Protocollo.Test`; il cuore del ricevitore Windows (`Windows/WebcamLR.Ricevitore`, senza interfaccia) con `dotnet test Windows/WebcamLR.Ricevitore.Test`, che include un iPhone simulato su loopback.
- Grafica: colori, caratteri e componenti stanno nel pacchetto `Stile/` (iPhone e Mac); non ridefinirli nelle app. Windows prende gli stessi valori da `Token.xaml` e i componenti da `Stili.xaml`, Android da `Token.kt`: tutti generati da `Documenti/token.json`. Identità di LR Apps dal logo: fondo verde scuro (sfumatura #30453E → #0D1B18) e toni di salvia, testo quasi bianco, Barlow Condensed per i titoli e Barlow per il testo. Il corallo tally (`Tema.tally`, #E67A67) solo per «in onda» e registrazione; azioni e selezione nell'accento salvia chiaro (`Tema.accento`; il vecchio nome `ciano` resta solo nelle chiavi di Windows).
- Token grafici: i token si cambiano solo in `Documenti/token.json` + `Strumenti/genera_token.py` (tabella in `Documenti/Stile.md`; Token.swift, Token.xaml, Token.kt, colors.xml e `Strumenti/uscita/token.css` sono generati; prima di un commit `python3 Strumenti/genera_token.py --controlla`).
- Tutto nativo: niente Flutter o React Native nella pipeline video. Codec solo hardware di sistema, nessuna libreria GPL.
