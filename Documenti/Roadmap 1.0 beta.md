# Roadmap · dalla 1.0 beta 1 alla 1.0

Decisa il 30 ottobre 2026 dopo il rapporto di interfaccia (Fase 1:
https://claude.ai/artifact/VNB3Nq1wzRmeBmTstKacyW) e la scelta della direzione (Fase 2:
https://claude.ai/artifact/HmECVaxA4WwQNvgaQPccrb): **A «Regia pulita» come linguaggio, con i bordi nativi di C e la
riga di stato scritta di B**. Ledion ha approvato l'elenco delle comodità e tutte le decisioni come consigliate.

## Numerazione
- **1.0** = prima pubblicazione. Prima: **1.0 beta N** (tag `v1.0-beta.N`). Ogni beta è fatta di **passi** piccoli
  (beta 2 · passo 3), ognuno con la sua riga nella checklist e il suo commit su `round-2`.
- Le etichette di prima (1.2–1.14, P01–P25, E01–E21) restano solo come tappe interne nel Registro lavori.
- Dopo la 1.0: 1.0.x correzioni, 1.1+ novità. Il Piano aggiornamenti ripartirà da 1.1.

## Come si procede
Ogni passo: lavoro su un ramo a parte → revisione indipendente del codice («come un compilatore» per Swift, test per
C# e Kotlin) → unione su `round-2` → `dotnet test`, test del protocollo Kotlin, `controlla_testi_*.py` → push.
Swift e l'app Android **non si compilano qui**: ogni passo lo dice, e la prova vera è di Ledion.

## 1.0 beta 1 · oggi (2fe1163)
Sfocatura sul Mac (guided filter, zona persona, fluidità). Da provare: vedi `Da controllare al ritorno.md`.

## 1.0 beta 2 · «Al sicuro» (Fase 3)
Gravità 1 e 2 del rapporto, sulle quattro app, **senza cambiare l'aspetto**.
1. **Pausa «sottofondo»**: protocollo (fatto, aeeb7b6) + iPhone e Android la mandano; Mac e Windows la mostrano e
   aspettano 10 minuti; banner al ritorno sul telefono. Anche «fotocamera interrotta» (chiamata, altra app, calore).
2. **Uscire e chiudere senza sorprese**: ⌘Q / Esci chiedono se un'app usa il video o se registri; chiudere la
   finestra lo dice; Windows: «Esci» anche nella finestra, installatore che chiude l'app con garbo.
3. **Registrazioni che non si perdono**: file frammentati (Mac .mov, Windows MP4), file parziale tenuto con il disco
   pieno, domanda prima dei comandi che fermano la registrazione, «senza audio» detto, avviso con «Mostra nella
   cartella» invece di aprire Finder o Esplora file.
4. **Niente gesti distruttivi a sorpresa**: conferme (Scollega in onda o registrando, elimina e sovrascrivi profilo,
   rimuovi telefono fidato) o Annulla («Azzera», togli computer); telefono: la X dice chi usa il video, Indietro su
   Android chiede, la notifica non scollega da sola, il doppio tocco non cambia fotocamera in onda.
5. **Interruzioni dette**: iPhone fotocamera e microfono interrotti, Android chiamata e servizio rifiutato, computer
   «telefono perso» con un banner che resta.
6. **Stato sempre visibile**: pillola IN ONDA corallo piena (da lontano), IN PAUSA in ambra; avvisi che restano finché
   la causa c'è e finiscono nel registro; Mac icona nella barra dei menu; Windows icona a 3 stati.
7. **Permessi e rete senza vicoli ciechi**: fotocamera, microfono, Rete locale con «Apri Impostazioni»; Android
   batteria; Mac firewall e Rete locale; Windows firewall «Sistema», diagnosi visibili anche in Essenziale, misure DPI,
   HEVC con «Apri Microsoft Store».
8. **Standard di piattaforma**: Mac menu Video e Aiuto con le scorciatoie, ⌘, apre il pannello Impostazioni, clic
   destro; Windows F1, Ctrl+W, Ctrl+,; annunci di VoiceOver/TalkBack/Assistente vocale; Riduci movimento.
9. **Dati che non si perdono e testi veri**: testo del gobbo salvato, bozza di «Segnala un bug» e registro allegabile,
   registro copiabile su Android, indirizzo ricordato, primo avvio del Mac con il QR grande, Guida e domande frequenti
   allineate.

Checklist: `Documenti/Checklist 1.0 beta 2.md` (una sezione per passo, 10–15 minuti in tutto).

## 1.0 beta 3 · «Sistema» (Fase 4)
`Documenti/Stile.md` con l'unica tabella di token; `Strumenti/genera_token.py` che scrive Tema.swift, App.xaml,
Tema.kt e le variabili CSS; componenti del catalogo sulle quattro app, **a parità di aspetto**.

## 1.0 beta 4 · «Volto nuovo» (Fase 5)
La direzione scelta, schermata per schermata: contorni a 3:1, superfici a gradini, comandi di regia con lo stato
scritto, primario uno per contesto, distruttivi mai pieni, chip bordati, Mica e barra del titolo unica su Windows,
Material 3 su Android, un posto solo per le impostazioni, un nome solo per la lista dei telefoni.

## 1.0 RC · «Sito e store» (Fase 6)
Stessi token e parole sul sito (WOFF2, bordi a 3:1, animazioni con pausa, menu mobile, 404), promesse allineate a ciò
che è provato, materiale degli store aggiornato. Prima: allineare il `main` locale a GitHub.

## 1.0
Dopo la checklist completa di Ledion sui quattro dispositivi.
