# Rifinitura 1.0 · cose da sistemare

Raccolte durante il lavoro sulle versioni 0.2–0.12, da chiudere nella 1.0 (punti della roadmap tra parentesi).

## Parole (6)
- [ ] iPhone e Mac: togliere «round» dai testi visibili («dal round 5», «arriverà con il round 2», «Controlli pro, dal round 4»): dire «in arrivo» o spiegare cosa serve
- [ ] iPhone e Mac: «Fuoco automatico» → «Messa a fuoco automatica» (glossario)
- [ ] Ripasso completo di tutti i testi con `Documenti/Glossario.md`
- [x] Windows: niente «round», «Messa a fuoco automatica», «codice di sicurezza»

## Revisioni (2, 3)
- [x] Revisione indipendente del codice della sicurezza su iPhone (corretto: il codice di conferma ora è calcolato dall'iPhone)
- [ ] Revisione indipendente del codice della sicurezza sul Mac
- [ ] Le note «da controllare sul dispositivo» dei revisori (in fondo)
- [ ] Una revisione finale di tutto il codice Swift per errori di compilazione, prima della checklist finale

## Note dei revisori da verificare sul dispositivo
- iPhone, sicurezza: se il Portachiavi non salva l'identità (errore ignorato) l'iPhone cambia identità a ogni avvio e il computer chiede la conferma ogni volta; se la prima lettura avviene prima del primo sblocco, chiave temporanea per quell'avvio. Da gestire con un avviso
- iPhone: con il lettore QR aperto, il conto alla rovescia del ricollegamento può aprire «In onda» sotto il foglio (come già corretto per la sezione App)
- iPhone: la scritta «AE/AF bloccati» dopo un cambio di formato (caldo, batteria); `MaxFrameDelayCount = 0` su encoder più vecchi; doppia riconfigurazione all'avvio con risparmio batteria
- Mac: icona rossa nella barra (può diventare monocromatica); Impostazioni aperte dalla barra potrebbero aprirsi dietro; il clic sulle notifiche «collegato/perso» non riapre la finestra se era chiusa
- Windows: niente da segnalare oltre alla prova su un PC vero

## Già fatto
- [x] Glossario (6)
- [x] Test stabili: 25 giri su 25 del telefono finto
