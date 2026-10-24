# Stasera · cosa provare e in che ordine

Tutto è sul ramo `round-2`. Il codice Swift (iPhone e Mac) è stato riletto da più revisori, ma qui non si può compilare: **la prima cosa è la build**. Se Xcode mostra errori rossi, mandameli così come sono (testo o screenshot) e mi fermo lì: li correggo subito.

## 1 · Build (15 minuti)

1. Terminale: `cd ~/Documents/WebcamLR && git fetch && git checkout round-2 && git pull`
2. Doppio clic su `Strumenti/Costruisci e installa.command` (account **N**)
3. In Xcode: il tuo iPhone in alto, ▶
4. (PC) `Strumenti\Costruisci e avvia.bat`

Mandami: «build ok» oppure gli errori rossi.

## 2 · Le checklist, in ordine

**Novità (25 ottobre)**: per iPhone e Mac usa la checklist unica `Checklist iPhone e Mac.md`, che sostituisce le tre qui sotto. Parti dal «Giro veloce» in cima.


| Ordine | File | Tempo | Cosa prova |
| --- | --- | --- | --- |
| 1 | `Checklist 1.0.md` | 45 min | tutto il round 2 e la 1.0 |
| 2 | `Checklist 1.2-1.9.md` | 30 min | indicatore, diagnosi, domande frequenti, modalità avanzata, **cavo USB** |
| 3 | `Checklist 1.10-1.12.md` | 20 min | QR istantaneo, avvio rapido, ricollegamento in qualsiasi ordine |
| 4 (PC) | `Windows/FotocameraVirtuale/LEGGIMI.md` | 30 min | **webcam virtuale Windows**: Fotocamera, Meet, Zoom, Teams, WhatsApp, OBS |
| 5 (Android) | `Android/LEGGIMI.md` | 30 min | app Android: Android Studio → Run, poi la checklist in fondo |
| più avanti | `Webcam virtuale Mac.md` | — | solo con l'account sviluppatore a pagamento |

Se sei di corsa, fai solo: build → Checklist 1.0 sezioni B e C → Checklist 1.2–1.9 sezione P (cavo) → webcam Windows.

## 3 · Cosa mandarmi

- Il numero della riga che non va, con screenshot
- Il valore di latenza in Wi-Fi e col cavo
- Con la modalità avanzata accesa: il «Registro del collegamento» (pulsante Copia/Condividi) dopo un giro con il cavo
- (PC) se la webcam non va: lo stato nella scheda «Webcam per le altre app» e i due file in `C:\ProgramData\WebcamLR\`

## 4 · Decisioni da prendere insieme

Vedi la fine di `Registro lavori.md`: account Apple a pagamento, Mac dal sito o App Store, messa online del sito, email di assistenza, NDI.
