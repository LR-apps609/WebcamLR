# Studio · collegamento con il cavo USB (0.11)

Perché serve: è il collegamento più stabile, con la latenza più bassa, e intanto ricarica il telefono. iVCam, Camo e simili lo offrono.

## Come funziona negli altri

Sul cavo non c'è una rete: il computer parla con l'iPhone attraverso **usbmux**, il servizio di Apple che usa anche il Finder (o iTunes / «Dispositivi Apple» su Windows) per sincronizzare.

- L'**iPhone** resta in ascolto su una porta TCP locale (per esempio 52740) mentre l'app è aperta.
- Il **computer** chiede a usbmux di aprire una connessione verso quella porta del telefono attraverso il cavo. Da lì è una normale connessione TCP: il nostro protocollo (stretta di mano, cifratura, video) resta identico. Cambia solo chi apre la connessione.

| | Come si raggiunge usbmux | Note |
|---|---|---|
| Mac | socket Unix `/var/run/usbmuxd` | l'app Mac è nel sandbox: serve un'eccezione (`temporary-exception`) o un piccolo programma di supporto fuori dal sandbox. Va bene fuori dal Mac App Store; dentro, Apple potrebbe rifiutarla |
| Windows | TCP `127.0.0.1:27015` | c'è se è installato «Dispositivi Apple» (o iTunes). Nessun problema di sandbox |

Il protocollo di usbmux è semplice (messaggi plist con lunghezza in testa: `ListDevices`, `Connect` con il numero del dispositivo e la porta), documentato da progetti aperti come libimobiledevice. Va scritto da zero: le librerie esistenti sono LGPL o GPL, e il progetto usa solo codice nostro o di sistema.

## Cosa funziona già oggi, senza codice nuovo

**Hotspot personale via cavo**: con il cavo collegato e «Hotspot personale» attivo sull'iPhone, il computer vede una rete «iPhone USB». WebcamLR la usa come qualsiasi rete: la ricerca automatica e il QR code funzionano. Ha quasi tutti i vantaggi del cavo (stabile, ricarica) ma richiede un piano dati con hotspot e un passaggio in più.

## Proposta

1. **Subito**: spiegare nella guida l'hotspot via cavo (fatto nella guida dell'app).
2. **Round dedicato, dopo la 1.0**:
   - iPhone: ascolto sulla porta locale mentre l'app è aperta, con la stessa sessione sicura;
   - Windows: client usbmux su 127.0.0.1:27015, con test su un telefono finto;
   - Mac: client usbmux in un piccolo programma di supporto (XPC) fuori dal sandbox; da decidere insieme alla distribuzione (App Store o sito).
3. Il riquadro «Via cavo USB» nella schermata dell'iPhone resta come anteprima finché non c'è.

Rischi: usbmux non è un'interfaccia pubblica di Apple. Funziona da anni ed è usata da molti, ma può cambiare con un aggiornamento di sistema.
