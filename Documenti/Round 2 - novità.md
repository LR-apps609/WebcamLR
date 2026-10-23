# Round 2 · 50 novità

Obiettivo: la webcam da telefono più semplice e piacevole da usare. Niente pannelli in più: ogni novità o toglie un passaggio, o rende più chiaro cosa succede, o fa andare il video più liscio.

Regole:
- **Meno passaggi**: ciò che si può fare da solo, si fa da solo (ricollegarsi, scegliere la qualità, oscurare lo schermo).
- **Parole, non numeri**: «Ottimo / Buono / Debole» al posto dei millisecondi; i numeri restano a portata di mano.
- **Nessuna novità rallenta il video**: la latenza resta sotto i 100 ms (al round 1: 51 ms in Wi-Fi).

Nessuna novità cambia il protocollo: iPhone, Mac e Windows del round 1 restano compatibili tra loro.

## In comune

1. **Qualità del collegamento in parole** — «▮▮▮ Ottimo / Buono / Debole», stesse soglie ovunque (Stile `QualitaCollegamento`, C# `Qualita`)

## iPhone

2. **Ricollegamento automatico** — all'avvio, se trova l'ultimo computer usato, si collega da solo dopo 3 secondi (con «Annulla»)
3. **Vibrazioni leggere** — collegato, scollegato, cambio obiettivo, blocco del fuoco
4. **Qualità che segue la rete** — se il Wi-Fi rallenta il bitrate scende da solo, e risale quando torna buono
5. **Codifica ancora più veloce** — il codificatore privilegia la velocità e non trattiene fotogrammi
6. **Rete per video in tempo reale** — il collegamento si dichiara video interattivo, Wi-Fi in priorità
7. **Stabilizzazione a scelta** — spenta di serie (meno latenza), «Standard» nelle impostazioni
8. **Luce bassa automatica** — dove l'iPhone la supporta, schiarisce le stanze buie
9. **Zoom fluido** — lo zoom dal computer scorre invece di saltare
10. **Blocco di fuoco ed esposizione** — tocco lungo sull'anteprima, come nella Fotocamera: «AE/AF bloccati»
11. **Griglia dei terzi** — da accendere per inquadrarsi bene
12. **Livella** — una linea che diventa verde quando il telefono è dritto
13. **Oscuramento automatico** — dopo 30 secondi senza tocchi lo schermo si oscura da solo (si può spegnere)
14. **Qualità del collegamento** in alto, al posto dei soli ms
15. **Riconnessione chiara** — banner con i secondi e «Riprova ora»
16. **Benvenuto** — tre schermate alla prima apertura, e i permessi spiegati prima di chiederli
17. **Risparmio batteria** — sotto il 20% senza caricatore passa a 24 fps (si può spegnere)
18. **Cambio fotocamera rapido** — doppio tocco sull'anteprima: frontale ↔ posteriore
19. **Accessibilità** — VoiceOver su ogni pulsante, testi che seguono la dimensione scelta nel sistema

## Mac

20. **Niente rallentamenti di macOS** — durante il collegamento l'app non va in sospensione (App Nap): latenza costante
21. **Finestra mini** — il video in una finestrella sempre in primo piano, da tenere in un angolo
22. **Notifiche** — telefono collegato o perso, batteria bassa, registrazione salvata
23. **Apri all'avvio del Mac** — un interruttore
24. **Menu nella barra completo** — obiettivo, specchia, foto, registra, finestra mini, scollega
25. **Scorciatoie** — 1–4 per gli obiettivi, + e − per lo zoom, F per il fuoco automatico
26. **Copia il fotogramma** — ⌘C copia l'immagine attuale, da incollare ovunque
27. **Scatto visibile** — lampo breve sull'anteprima e suono dello scatto
28. **Qualità del collegamento** — tacche e parola; i numeri si aprono con un clic
29. **Vista pulita** — nasconde statistiche e pulsanti, resta solo il video
30. **Riempi o adatta** — il video riempie la finestra o si vede intero
31. **Grafico della latenza** — gli ultimi 60 secondi in una linea sottile
32. **Primo avvio più chiaro** — QR code grande e i tre passi per collegarsi
33. **Avvisi dal telefono** — caldo e batteria in un banner sopra il video
34. **Icona della barra con lo stato** — vuota senza telefono, piena se collegato, rossa se in onda
35. **Impostazioni (⌘,)** — avvio al login, notifiche, specchia di serie
36. **Foto con timer** — 3 secondi, con conto alla rovescia sull'anteprima
37. **Registrazione sotto controllo** — durata e dimensione del file mentre registra; avviso se lo spazio sta finendo
38. **Accessibilità** — VoiceOver su ogni controllo

## Windows

39. **Notifiche** — telefono collegato o perso, batteria bassa
40. **Avvia con Windows** — un interruttore
41. **Finestra mini** — il video sempre in primo piano (sovrapposizione compatta)
42. **Qualità del collegamento** — tacche e parola, come sul Mac
43. **Scorciatoie** — 1–4 per gli obiettivi, + e − per lo zoom
44. **Menu dell'icona completo** — stato, finestra mini, scollega, esci
45. **Stato al passaggio del mouse** sull'icona accanto all'orologio
46. **Primo avvio più chiaro** — QR code grande e i tre passi per collegarsi
47. **Ricorda dimensione e posizione** della finestra
48. **Grafico della latenza** — gli ultimi 60 secondi
49. **Avvisi dal telefono** — caldo e batteria in una barra sopra il video
50. **Aspetto di Windows 11** — sfondo Mica, accessibilità da tastiera e lettore dello schermo
