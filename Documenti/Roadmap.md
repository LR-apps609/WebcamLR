# Roadmap · dalla 0.2 alla 1.0

Le 50 novità del round 2 (`Documenti/Round 2 - novità.md`, numeri tra parentesi) divise in otto versioni piccole.
Ogni versione ha un tema, si prova in 10–15 minuti e si chiude solo quando Ledion conferma che funziona.

Come si procede, versione per versione:
1. Claude porta sul ramo `round-2` solo le novità di quella versione e aggiorna il numero di versione delle app
2. Ledion: `git pull`, script di build, ▶ in Xcode, e la checklist della versione
3. Esito, screenshot o errori → correzioni → di nuovo il punto 2
4. Quando tutto è verde: tag `v0.x` su GitHub e si passa alla successiva

Windows è sempre facoltativo (serve un PC): le sue novità si possono provare anche tutte insieme alla 0.8.

## 0.2 · Più veloce e più chiaro
Nessun pulsante nuovo: il video va più liscio e si capisce subito se il collegamento è buono.
- Qualità del collegamento in parole, «Ottimo / Buono / Debole», su iPhone, Mac e Windows (1, 14, 28, 42)
- Qualità che segue la rete (4)
- Codifica più veloce (5) e rete per video in tempo reale (6)
- Il Mac non mette l'app in pausa durante il collegamento (20)

Prova: latenza uguale o più bassa di 51 ms; spegnendo e riaccendendo il Wi-Fi del router, il video si abbassa di qualità invece di bloccarsi.

## 0.3 · Si collega da solo
- Ricollegamento automatico all'ultimo computer (2)
- Vibrazioni leggere (3)
- Banner di riconnessione con «Riprova ora» (15)
- Benvenuto in tre schermate alla prima apertura (16)
- Primo avvio più chiaro sul Mac e su Windows: QR grande e tre passi (32, 46)

Prova: chiudi e riapri l'app sull'iPhone; si ricollega al Mac senza toccare niente.

## 0.4 · Inquadratura perfetta
- Griglia dei terzi (11) e livella (12)
- Blocco di fuoco ed esposizione con tocco lungo (10)
- Cambio fotocamera con doppio tocco (18)
- Zoom fluido dal computer (9)
- Stabilizzazione a scelta (7) e luce bassa automatica (8)

## 0.5 · Batteria e calore sotto controllo
- Oscuramento automatico dopo 30 secondi (13)
- Risparmio batteria sotto il 20% (17)
- Avvisi dal telefono, caldo e batteria, sul Mac e su Windows (33, 49)

Prova: una chiamata di 30 minuti con il telefono a batteria.

## 0.6 · Il Mac come una regia
- Finestra mini sempre in primo piano (21)
- Menu nella barra completo (24) e icona con lo stato (34)
- Scorciatoie da tastiera (25)
- Vista pulita (29), riempi o adatta (30)
- Grafico della latenza (31)

## 0.7 · Foto, registrazioni e impostazioni
- Copia il fotogramma con ⌘C (26), scatto visibile (27), foto con timer (36)
- Registrazione con durata, dimensione e avviso sullo spazio (37)
- Notifiche (22)
- Impostazioni con ⌘, e apertura all'avvio del Mac (23, 35)

## 0.8 · Windows al pari del Mac
- Notifiche (39) e avvio con Windows (40)
- Finestra mini (41), scorciatoie (43)
- Menu dell'icona (44) e stato al passaggio del mouse (45)
- Dimensione e posizione ricordate (47), grafico della latenza (48)

## 0.9 · Rifinitura
- Accessibilità su iPhone, Mac e Windows; aspetto di Windows 11 (19, 38, 50)
- Correzioni dalle prove delle versioni precedenti
- Controllo finale: 10 minuti senza scatti, latenza sotto i 100 ms, telefono tiepido dopo 30 minuti

## 0.10 · Collegamento sicuro
Priorità di Ledion: qualità del video e sicurezza del collegamento prima di tutto.
- Video e comandi cifrati (AES-256-GCM con chiavi di sessione nuove a ogni collegamento, protocollo versione 2)
- Abbinamento: alla prima volta il computer chiede «Consentire l'iPhone di …?»; il QR code contiene l'impronta della chiave del computer, così l'iPhone è sicuro di parlare con il computer giusto
- Telefoni fidati: dalla seconda volta ci si collega senza domande; dal computer si possono togliere

## 0.11 · Più modi per collegarsi
- Wi-Fi diretto tra iPhone e Mac, senza router (la stessa tecnologia di AirDrop): funziona anche dove la rete blocca i dispositivi tra loro
- Hotspot dell'iPhone spiegato nella guida
- Cavo USB: studio e prima prova (round dedicato se serve più lavoro)

## 0.12 · Sezione App
Sull'iPhone e sul computer, una sezione semplice con:
- **Abbonamento**: WebcamLR Pro e cosa include (non ancora acquistabile)
- **Accesso**: account LR Apps (non ancora attivo: per ora «modalità senza account»)
- **Guida**: come si usa, passo passo, e cosa fare se non si collega
- **Informazioni**: versione, privacy, contatti, la famiglia LR Apps
- **Segnala un bug**: descrizione, cosa stavi facendo e i dati tecnici utili già pronti (versione, dispositivo, latenza), da mandare con un tocco

## 1.0 · Pronta per il pubblico
1. Controllo qualità
2. Controllo dei possibili bug
3. Controllo del codice: tutto deve funzionare
4. Pulizia estetica
5. Pulizia grafica
6. Pulizia delle parole: i termini più comuni per un'app di questo tipo
7. Velocità di clic e azioni, su telefono e computer
8. App per telefono ottimizzata per iOS (Android dopo)
9. Grafica professionale e seria, nella famiglia LR Apps
10. Velocità di esecuzione e di collegamento tra i dispositivi
11. Controllo finale e riepilogo di tutte le modifiche
12. Checklist completa di tutto ciò da provare a mano sui dispositivi

Dopo la 1.0: account sviluppatore a pagamento e webcam virtuale per Zoom e Teams.
