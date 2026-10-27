# Interfaccia finale (bozza approvata il 26 ottobre)

Bozza: https://claude.ai/artifact/65CDbALuvrMyBFwTykXzoQ (5 schermate). Da portare su Mac e Windows, e la colonna di
pulsanti tondi su iPhone e Android, dopo la prima prova di Ledion.

## Computer
- Base «Regia pulita»: colonna sinistra (telefoni, uscite, QR sempre visibile) e destra (profilo, fotocamera, effetti).
- QR in fondo a sinistra: «Collega il tuo smartphone» senza telefoni, «Collega un altro smartphone» con un telefono.
- Video più largo; sotto, la barra con icona e nome: Specchia · Sfoca · Foto · Registra | Schermo.
- Etichetta della qualità sul video cliccabile: menu con 720p 30 (gratis) e 1080p 30, 1080p 60, 4K 30 (grigi con «PRO»
  senza WebcamLR Pro).
- Etichetta del collegamento («Wi-Fi ▾») cliccabile quando ci sono più strade: Automatico, Wi-Fi, Cavo USB, ognuna con la
  latenza e la nota «più veloce ora» su quella più veloce in quel momento.
- In alto a destra: Aiuto e Account (WebcamLR Pro, preferenze, telefoni conosciuti, lingua, aggiornamenti, informazioni).
  Niente login per ora.
- Due telefoni: la CAM 2 compare solo quando si collega; riquadro dentro il video con «Usa prospettiva».

### Tre viste (27 ottobre, idea di Ledion)
- **Essenziale** (di partenza per le installazioni nuove): video grande e barra sotto; in alto a destra
  «Impostazioni» accanto ad Aiuto e Account; sul video in alto a sinistra la pillola del telefono (nome, oppure
  «Collega il tuo smartphone» con il QR in un popover). «Impostazioni» apre da destra un pannello di 360 punti a
  livelli: Fotocamera · Effetti · Sfondo · Profili · Qualità e collegamento · Schermo · Microfono · Telefoni · Uscite ·
  Gobbo · Registro del collegamento. Le pagine riusano le sezioni delle colonne. Si chiude con la X, Esc o un clic sul
  video.
- **Completo**: le due colonne, com'erano. Chi aveva già usato l'app resta qui.
- **Schermo intero**: solo il video; «Esci» compare per qualche secondo al movimento del mouse o a un tasto; Esc esce.
- Si scelgono dal pulsante «Schermo» (popover con tre pulsanti grandi: Schermo intero · Essenziale · Completo, accesa
  quella attuale) e dal menu Vista (Mac: ⌘1, ⌘2, ⌃⌘F; Windows: Ctrl+1, Ctrl+2, F11). Finestra mini e Riempi
  l'inquadratura sono nel menu Vista (⇧⌘M, ⌥⌘F) e in Impostazioni › Schermo. La scelta resta salvata.

## Telefono
- Colonna di pulsanti tondi a destra: Specchia · Sfoca sfondo · Microfono · Pausa · Luce; obiettivi in basso.
- In orizzontale: stessa colonna; dopo qualche secondo «vista pulita» con solo «IN ONDA», un tocco riporta i comandi.
- Senza computer: «Cerco il tuo computer…» → computer trovati → dopo 15 s aiuto in tre punti (app aperta, stessa rete,
  permesso «Rete locale»), «Mandami il link per il computer», «Prova con il cavo USB».

## Regola del collegamento «Automatico» (decisa da Ledion: niente sbalzi)
- La strada si sceglie **all'inizio** (la più veloce disponibile) e poi **resta quella**.
- Si cambia **solo** se:
  1. la strada in uso **si stacca** (cavo tolto, Wi-Fi perso): si passa all'altra senza fermare il video;
  2. l'utente **attacca il cavo** durante una sessione in Wi-Fi: un solo passaggio al cavo (gesto voluto).
- **Mai** in base alla latenza misurata durante la sessione: «più veloce ora» nel menu è solo un'informazione.
- Dopo un cambio, nessun altro cambio automatico per almeno 30 secondi (anche se il cavo va e viene).
- Scelta manuale (Wi-Fi o Cavo USB): resta quella; se si stacca si usa l'altra solo per non perdere il video e si
  torna alla scelta appena è di nuovo disponibile.
- Oggi (round-2) iPhone e Mac fanno già così per i punti 1 e 2 (passaggio al cavo quando arriva, ritorno al Wi-Fi
  solo se il cavo si stacca); da aggiungere: la pausa di 30 s, la scelta manuale, e lo stesso comportamento su
  Android e Windows.
