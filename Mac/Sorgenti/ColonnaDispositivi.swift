import Stile
import SwiftUI
import WebcamLRProtocollo

/// La colonna di sinistra della finestra principale: «Telefoni» (telefoni collegati e telefoni fidati non
/// collegati), «Connessione» (Wi-Fi, cavo USB, Wi-Fi diretto, con la diagnosi quando nessuno si collega),
/// «Uscite» (webcam virtuale, microfono del telefono) e in fondo, sempre visibile (interfaccia finale), il QR per
/// collegarsi: «Collega il tuo smartphone», o «Collega un altro smartphone» con un telefono già collegato.
/// Scorre se non ci sta (finestra alta 600 con la diagnosi aperta); il QR in fondo resta fermo.
/// Le tre sezioni sono viste a sé: le riusa il pannello «Impostazioni» della vista Essenziale (PannelloImpostazioni.swift).
struct ColonnaDispositivi: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    SezioneTelefoni(ricevitore: ricevitore)
                    SezioneConnessione(ricevitore: ricevitore)
                    SezioneUscite(ricevitore: ricevitore, fotocamera: fotocamera)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            RiquadroCollega(ricevitore: ricevitore)
                .padding(12)
        }
    }
}

// MARK: - Telefoni

/// «Telefoni»: i telefoni collegati (con due, la scelta «Nella webcam»), quelli fidati non collegati e, senza
/// telefono, cosa succede. Nella colonna di sinistra e nella pagina «Telefoni» delle Impostazioni.
struct SezioneTelefoni: View {
    let ricevitore: Ricevitore
    /// Il pulsante del registro del collegamento: nella colonna sì; nelle Impostazioni il registro ha la sua pagina.
    var conRegistro = true
    @State private var mostraRegistro = false
    @Environment(\.openWindow) private var apriFinestra

    /// I telefoni fidati che ora non sono collegati: si vede che il Mac li conosce e li aspetta.
    private var telefoniNoti: [TelefonoFidato] {
        let collegati = Set(ricevitore.telefoni.map(\.impronta))
        return ricevitore.telefoniFidati.filter { !collegati.contains($0.impronta) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtichettaSezione(String(localized: "Telefoni"))
            if ricevitore.telefoni.count > 1 {
                // Più telefoni insieme (P21): ognuno con «Nella webcam» e «Scollega». Con uno solo, come sempre.
                ForEach(ricevitore.telefoni) { collegato in
                    SchedaTelefono(telefono: collegato.telefono, stato: collegato.statoTelefono,
                                   latenza: collegato.statistiche.latenzaMs,
                                   via: collegato.tipoCollegamento,
                                   collegato: collegato.collegato || collegato.inSottofondo,
                                   avvio: collegato.tempoAvvio,
                                   scelta: SchedaTelefono.Scelta(
                                       nellaWebcam: collegato === ricevitore.attivo,
                                       scegli: {
                                           // Mentre registri chiede prima (punto 7); il telefono già nella webcam no.
                                           guard collegato === ricevitore.attivo || ricevitore.confermaSeFerma(.telefono) else { return }
                                           ricevitore.scegli(collegato)
                                       },
                                       scollega: { ricevitore.chiediEScollega(collegato) }))
                }
            } else if let telefono = ricevitore.telefono {
                SchedaTelefono(telefono: telefono, stato: ricevitore.statoTelefono,
                               latenza: ricevitore.statistiche.latenzaMs,
                               via: ricevitore.tipoCollegamento,
                               collegato: ricevitore.telefonoAttivo || ricevitore.inSottofondo,
                               avvio: ricevitore.tempoAvvio,
                               scollegaSolo: { ricevitore.chiediEScollega() })
            }
            ForEach(telefoniNoti) { noto in
                RigaTelefonoNoto(nome: noto.nome)
            }
            if ricevitore.telefoni.count == 1 && ricevitore.bloccoPro {
                // WebcamLR Pro: il secondo telefono non si collega finché quello nella webcam è gratis.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SegnoPro()
                    Text("Due telefoni insieme: sblocca WebcamLR Pro sull'iPhone.")
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(TestiPro.strada)
            }
            if ricevitore.telefono == nil {
                attesa
            }
            if conRegistro {
                pulsanteRegistro
            }
        }
    }

    /// Nessun telefono collegato: cosa succede e la domanda frequente. Il QR per collegarsi è sempre in fondo.
    private var attesa: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nessun telefono collegato")
                .font(.corpoEvidente(13))
                .foregroundStyle(Tema.testoTenue)
            Button("Il telefono non trova il Mac?") {
                apriDomandaFrequente("non-trova", apri: apriFinestra)
            }
            .buttonStyle(.link)
            .font(.corpo(12.5))
            .tint(Tema.ciano)
        }
        .padding(.top, 2)
    }

    /// 1.5: gli ultimi eventi del collegamento, per capire cosa è successo.
    private var pulsanteRegistro: some View {
        Button {
            mostraRegistro.toggle()
        } label: {
            Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                .font(.corpo(12.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tema.testoSecondario)
        .help("Gli ultimi \(Ricevitore.righeRegistro) eventi del collegamento, solo su questo Mac")
        .popover(isPresented: $mostraRegistro, arrowEdge: .trailing) {
            VistaRegistro(voci: ricevitore.registro)
        }
    }
}

// MARK: - Connessione

/// «Connessione»: Wi-Fi, cavo USB, Wi-Fi diretto (con l'interruttore) e, senza telefono, la diagnosi.
/// Nella colonna di sinistra e nella pagina «Qualità e collegamento» delle Impostazioni.
struct SezioneConnessione: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false

    /// Come sono collegati i telefoni adesso (con due telefoni possono essere due strade diverse).
    private var stradeInUso: Set<TipoCollegamento> {
        Set(ricevitore.telefoni.filter(\.collegato).compactMap(\.tipoCollegamento))
    }

    var body: some View {
        let inUso = stradeInUso
        VStack(alignment: .leading, spacing: 6) {
            EtichettaSezione(String(localized: "Connessione"))
            RigaConnessione(simbolo: "wifi", nome: String(localized: "Wi-Fi"),
                            stato: statoWifi(inUso), attiva: inUso.contains(.wifi) || inUso.contains(.hotspot))
            RigaConnessione(simbolo: "cable.connector", nome: String(localized: "Cavo USB"),
                            stato: statoCavo(inUso), attiva: inUso.contains(.cavoUSB))
            RigaConnessione(simbolo: "antenna.radiowaves.left.and.right", nome: String(localized: "Wi-Fi diretto"),
                            stato: inUso.contains(.wifiDiretto) ? String(localized: "In uso")
                                : wifiDiretto ? String(localized: "Acceso") : String(localized: "Spento"),
                            attiva: inUso.contains(.wifiDiretto),
                            interruttore: Binding(get: { wifiDiretto }, set: { acceso in
                                wifiDiretto = acceso
                                // Come l'interruttore delle Impostazioni: si riapre l'ascolto, con o senza AWDL.
                                ricevitore.riavviaAscolto()
                            }))
                .help("Per collegare l'iPhone dove non c'è una rete in comune, come con AirDrop. Lascialo spento se non serve: la latenza è più stabile.")
            if inUso.contains(.cavoDiRete) {
                RigaConnessione(simbolo: "network", nome: String(localized: "Cavo di rete"),
                                stato: String(localized: "In uso"), attiva: true)
            }
            if ricevitore.telefono == nil {
                // Diagnosi (1.3): una causa e cosa fare, al posto del solo errore.
                if let diagnosi = Diagnosi.calcola(ricevitore, wifiDiretto: wifiDiretto) {
                    RiquadroDiagnosi(diagnosi: diagnosi, ricevitore: ricevitore)
                        .help(testoRete)
                        .padding(.top, 4)
                } else {
                    Text(testoRete)
                        .font(.numeri(11.5))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func statoWifi(_ inUso: Set<TipoCollegamento>) -> String {
        if inUso.contains(.hotspot) { return String(localized: "In uso · Hotspot") }
        if inUso.contains(.wifi) { return String(localized: "In uso") }
        if case .errore = ricevitore.rete { return String(localized: "Non risponde") }
        if ricevitore.indirizzi.isEmpty { return String(localized: "Nessuna rete") }
        return String(localized: "Pronto")
    }

    private func statoCavo(_ inUso: Set<TipoCollegamento>) -> String {
        if inUso.contains(.cavoUSB) { return String(localized: "In uso") }
        switch ricevitore.statoCavo {
        case .nessunIPhone: return String(localized: "Nessun iPhone")
        case .servizioAssente: return String(localized: "Non disponibile")
        case .inAttesaApp: return String(localized: "Apri l'app")
        case .inPausa: return String(localized: "In pausa")
        case .collegato: return String(localized: "Collegato")
        }
    }

    private var testoRete: String {
        switch ricevitore.rete {
        case .fermo: String(localized: "Mi faccio trovare in rete…")
        // Passo 7 (mac.md 14): cosa fare, non la porta (che resta nel registro e nei numeri).
        case .visibile: String(localized: "Pronto: apri WebcamLR sul telefono.")
        case .errore(let descrizione): descrizione
        }
    }
}

// MARK: - Uscite

/// «Uscite»: webcam virtuale, microfono del telefono e NDI «in arrivo». Nella colonna di sinistra e nella pagina
/// «Uscite» delle Impostazioni.
struct SezioneUscite: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    @State private var confermaRimozione = false

    /// Il messaggio sotto «Rimuovere la webcam virtuale di WebcamLR?»: se un'app la usa, chi perde il video.
    private var testoRimozioneFotocamera: String {
        let base = String(localized: "«WebcamLR» sparisce dalle videocamere di tutte le app. Potrai riattivarla quando vuoi.")
        guard ricevitore.webcamInUso else { return base }
        let inUso: String
        if let app = AppCompatibile.nomeUnico(firme: ricevitore.appWebcam) {
            // «un sito nel browser» apre la frase: con la maiuscola.
            let app = app.prefix(1).uppercased() + app.dropFirst()
            inUso = String(localized: "\(app) la sta usando adesso: chi ti guarda perderà il video.")
        } else {
            inUso = String(localized: "Un'app la sta usando adesso: chi ti guarda perderà il video.")
        }
        return inUso + " " + base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EtichettaSezione(String(localized: "Uscite"))
            RigaUscita(nome: String(localized: "Webcam virtuale"), stato: testoFotocamera, attiva: fotocamera.stato == .attiva)
            if !fotocamera.disponibile {
                Text("Richiede l'account sviluppatore Apple a pagamento.")
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            } else if fotocamera.stato == .daApprovare {
                // M15: dopo l'approvazione, «Ricontrolla» se lo stato non è cambiato da solo.
                HStack(spacing: 8) {
                    Button("Apri Impostazioni di Sistema") { fotocamera.apriImpostazioni() }
                    Button("Ricontrolla") { fotocamera.ricontrolla() }
                        .help("Controlla di nuovo se macOS ha approvato la webcam virtuale")
                }
                .buttonStyle(StilePulsanteSecondario())
                .padding(.leading, 24)
            } else if fotocamera.stato != .attiva {
                Button("Attiva la webcam virtuale") { fotocamera.attiva() }
                    .buttonStyle(StilePulsanteSecondario())
                    .disabled(fotocamera.stato == .inCorso)
                    .padding(.leading, 24)
            } else {
                // Prima di cestinare l'app (Documenti/Webcam virtuale Mac.md).
                // Punto 8: prima chiede, come «Rimuovi il microfono…».
                Button("Rimuovi la webcam virtuale…") { confermaRimozione = true }
                    .buttonStyle(.plain)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.leading, 24)
                    .confirmationDialog("Rimuovere la webcam virtuale di WebcamLR?", isPresented: $confermaRimozione) {
                        Button("Rimuovi", role: .destructive) { fotocamera.rimuovi() }
                        Button("Annulla", role: .cancel) {}
                    } message: {
                        Text(testoRimozioneFotocamera)
                    }
            }
            if let spiegazione = spiegazioneFotocamera {
                Text(spiegazione)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.ambra)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
            if fotocamera.disponibile && fotocamera.fotocameraNegata {
                // Passo 7 (mac.md 15): senza il permesso della fotocamera le immagini non entrano nella webcam virtuale.
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS non dà la fotocamera a WebcamLR: le app vedono solo l'attesa. Attivala in Privacy e sicurezza › Fotocamera.")
                        .font(.corpo(12.5))
                        .foregroundStyle(Tema.ambra)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Apri Impostazioni") { ImpostazioniDiSistema.apri(.fotocamera) }
                        .buttonStyle(StilePulsanteSecondario())
                        .accessibilityHint("Impostazioni di Sistema › Privacy e sicurezza › Fotocamera")
                }
                .padding(.leading, 24)
            }
            RigaMicrofono(ricevitore: ricevitore)
                .padding(.top, 4)
            RigaUscita(nome: String(localized: "Uscita NDI"), stato: String(localized: "in arrivo"), attiva: false, inArrivo: true)
        }
    }

    private var testoFotocamera: String {
        guard fotocamera.disponibile else { return String(localized: "non inclusa") }
        if fotocamera.stato == .attiva && fotocamera.fotocameraNegata { return String(localized: "senza permesso") }
        return switch fotocamera.stato {
        case .nonAttiva: String(localized: "spenta")
        case .inCorso: String(localized: "attivazione…")
        case .daApprovare: String(localized: "da approvare")
        case .riavvioNecessario: String(localized: "riavvia il Mac")
        case .attiva: String(localized: "attiva")
        case .errore: String(localized: "non attivata")
        }
    }

    /// Cosa fare quando la webcam virtuale non è ancora pronta.
    private var spiegazioneFotocamera: String? {
        switch fotocamera.stato {
        case .daApprovare: AttivazioneFotocamera.doveApprovare
        case .riavvioNecessario: String(localized: "Riavvia il Mac per finire di installarla.")
        case .errore(let spiegazione): spiegazione
        default: nil
        }
    }
}

// MARK: - Componenti della colonna

/// In fondo alla colonna, sempre visibile: il QR per collegare un telefono (con il gettone di abbinamento).
/// Con tutti i posti occupati (due telefoni, P21) dice come liberarne uno. Sotto, «Non hai l'app?» apre il QR
/// per scaricarla (`AppPerIlTelefono`). Anche nel popover della pillola del telefono (vista Essenziale) e nella pagina
/// «Telefoni» delle Impostazioni. `grande` (passo 7, mac.md 13): al centro della vista Essenziale senza telefoni, il QR
/// grande e i tre passi. Dopo 30 secondi senza telefoni con la rete pronta, sotto il QR, «Il telefono non trova il Mac?»
/// (mac.md 14).
struct RiquadroCollega: View {
    let ricevitore: Ricevitore
    var grande = false
    @State private var mostraDownload = false

    var body: some View {
        if grande {
            riquadroGrande
        } else {
            riquadro
        }
    }

    private var riquadro: some View {
        let pieni = ricevitore.telefoni.count >= Ricevitore.massimoTelefoni
        return VStack(spacing: 10) {
            Text(ricevitore.telefoni.isEmpty ? LocalizedStringKey("Collega il tuo smartphone")
                                             : LocalizedStringKey("Collega un altro smartphone"))
                .font(.corpoForte(14))
                .multilineTextAlignment(.center)
            if pieni {
                Text("Già collegati due telefoni: scollegane uno per collegarne un altro.")
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PannelloAssociazione(ricevitore: ricevitore, lato: 118, compatto: true)
                Text("Inquadralo con l'app WebcamLR sul telefono: iPhone o Android")
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if ricevitore.nessunTelefonoDaTempo {
                    AiutoNonTrova()
                }
            }
            pulsanteDownload
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.linea))
    }

    /// Il primo avvio della vista Essenziale: il QR grande a sinistra e i tre passi a destra. Niente popover: si vede
    /// subito. Il QR è il più grande che ci sta in altezza (ViewThatFits): nel video basso della finestra a 600 punti,
    /// con «Il telefono non trova il Mac?» sotto, scende.
    private var riquadroGrande: some View {
        ViewThatFits(in: .vertical) {
            contenutoGrande(lato: 180)
            contenutoGrande(lato: 136)
            contenutoGrande(lato: 100)
        }
    }

    private func contenutoGrande(lato: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collega il telefono in tre passi")
                .font(.titolo(26))
                .foregroundStyle(Tema.testo)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 20) {
                PannelloAssociazione(ricevitore: ricevitore, lato: lato, compatto: true)
                    .frame(width: lato + 20)
                passi
                    .frame(width: 260, alignment: .leading)
            }
            if ricevitore.nessunTelefonoDaTempo {
                AiutoNonTrova()
                    .frame(width: lato + 280, alignment: .leading)
            }
            pulsanteDownload
        }
        .padding(20)
        .background(Tema.fondo.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.linea))
        .accessibilityElement(children: .contain)
    }

    private var passi: some View {
        VStack(alignment: .leading, spacing: 12) {
            PassoCollega(numero: 1, testo: Text("Apri WebcamLR sul telefono."))
            PassoCollega(numero: 2, testo: Text("Stessa rete Wi-Fi del Mac."))
            PassoCollega(numero: 3, testo: Text("Inquadra questo QR code."))
        }
    }

    private var pulsanteDownload: some View {
        Button("Non hai l'app? Scaricala") {
            mostraDownload.toggle()
        }
        .buttonStyle(.link)
        .font(.corpo(12))
        .tint(Tema.ciano)
        .popover(isPresented: $mostraDownload, arrowEdge: .trailing) {
            AppPerIlTelefono()
                .padding(14)
                .frame(width: 280)
        }
    }
}

/// Un passo del primo avvio: il numero in un cerchio nell'accento e la frase.
private struct PassoCollega: View {
    let numero: Int
    let testo: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(numero)")
                .font(.etichetta(14))
                .foregroundStyle(Tema.accento)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Tema.accento, lineWidth: 1.5))
                .accessibilityHidden(true)
            testo
                .font(.corpo(14))
                .foregroundStyle(Tema.testo)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Passo 7 (mac.md 14): dopo 30 secondi senza telefoni con la rete pronta, sotto il QR, che cosa controllare (il
/// firewall del Mac e la Rete locale dell'iPhone) e «Apri» verso Impostazioni di Sistema › Rete › Firewall.
struct AiutoNonTrova: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Il telefono non trova il Mac?")
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Tema.ambra)
            }
            .foregroundStyle(Tema.ambraTesto)
            Text("Controlla il firewall: Impostazioni di Sistema › Rete › Firewall › Opzioni › WebcamLR consentita. Sull'iPhone, WebcamLR deve avere «Rete locale» in Impostazioni › Privacy e sicurezza.")
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
            Button("Apri") { ImpostazioniDiSistema.apri(.firewall) }
                .buttonStyle(StilePulsanteSecondario())
                .accessibilityHint("Impostazioni di Sistema › Rete › Firewall")
        }
        .font(.corpo(12))
        .multilineTextAlignment(.leading)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.ambraTenue.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

/// Il QR per scaricare WebcamLR sul telefono (pagina del sito con App Store e Google Play), da «Non hai l'app?».
/// Non è il QR per collegarsi: quello è sempre in fondo alla colonna.
private struct AppPerIlTelefono: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CodiceQR(testo: InfoApp.download.absoluteString, lato: 96,
                     descrizione: String(localized: "QR code per scaricare WebcamLR sul telefono"))
            VStack(alignment: .leading, spacing: 3) {
                EtichettaSezione(String(localized: "App per il telefono"))
                Text("Inquadralo con la fotocamera del telefono per scaricare WebcamLR.")
                    .font(.corpo(11.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: InfoApp.download) {
                    Text("Apri la pagina")
                        .font(.corpoEvidente(12))
                }
                .tint(Tema.ciano)
                .foregroundStyle(Tema.ciano)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un telefono collegato, con il punto verde salvia (mai rosso) e i dettagli: strada, latenza, avvio, batteria.
struct SchedaTelefono: View {
    /// Con più telefoni (P21): è quello nella webcam? e i due pulsanti. Nil con un telefono solo.
    struct Scelta {
        let nellaWebcam: Bool
        let scegli: () -> Void
        let scollega: () -> Void
    }

    let telefono: Ciao
    let stato: StatoTelefono?
    let latenza: Int?
    let via: TipoCollegamento?
    let collegato: Bool
    /// «Avvio: 0,9 s» (1.11).
    var avvio: String?
    var scelta: Scelta?
    /// Con un telefono solo: «Scollega…» nel clic destro.
    var scollegaSolo: (() -> Void)?

    var body: some View {
        if let scelta {
            schedaConScelta(scelta)
                .contextMenu {
                    // Clic destro (M19): le stesse due azioni dei pulsanti della scheda.
                    Toggle("Nella webcam", isOn: Binding(get: { scelta.nellaWebcam }, set: { _ in
                        if !scelta.nellaWebcam { scelta.scegli() }
                    }))
                    Button("Scollega…") { scelta.scollega() }
                }
        } else if let scollegaSolo {
            scheda
                .contextMenu {
                    // Un telefono solo è sempre quello nella webcam: la voce c'è, spuntata e grigia.
                    Toggle("Nella webcam", isOn: .constant(true))
                        .disabled(true)
                    Button("Scollega…") { scollegaSolo() }
                }
        } else {
            scheda
        }
    }

    private var scheda: some View {
        intestazione
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Tema.linea))
            .accessibilityElement(children: .combine)
            .accessibilityValue(collegato ? "collegato" : "in riconnessione")
    }

    private var intestazione: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(collegato ? Tema.verde : Tema.ambra)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Image(systemName: "iphone")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tema.salviaChiara)
                    .accessibilityHidden(true)
                Text(telefono.nome)
                    .font(.corpoForte(13.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let stato, stato.batteria >= 0 {
                    Batteria(percentuale: stato.batteria, inCarica: stato.inCarica)
                }
            }
            Text(dettagli)
                .font(.numeri(11))
                .foregroundStyle(Tema.testoSecondario)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
            if let motivo = stato?.pausa {
                // In pausa, con il motivo; in sottofondo anche se il collegamento è caduto (torna da solo).
                Label(Ricevitore.testoPausa(motivo), systemImage: "pause.circle")
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
            if let stato, stato.temperatura != .normale {
                Label(Self.descrizione(stato.temperatura), systemImage: "thermometer.medium")
                    .font(.corpo(12))
                    .foregroundStyle(stato.temperatura == .calda ? Tema.testoSecondario : Tema.ambra)
                    .padding(.leading, 16)
            }
        }
    }

    /// Più telefoni (P21): la scelta «Nella webcam» nell'accento (azioni e selezione), mai in rosso; «Scollega» tenue.
    /// Il riquadro con l'accento resta solo per il telefono nella webcam.
    private func schedaConScelta(_ scelta: Scelta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            intestazione
                .accessibilityElement(children: .combine)
                .accessibilityValue(collegato ? "collegato" : "in riconnessione")
            HStack(spacing: 8) {
                Button {
                    scelta.scegli()
                } label: {
                    Label("Nella webcam", systemImage: scelta.nellaWebcam ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(scelta.nellaWebcam ? Tema.cianoChiaro : Tema.testoTenue)
                }
                .buttonStyle(.plain)
                .help(scelta.nellaWebcam ? "Questo telefono va nella webcam, nel microfono e nella finestra mini"
                      : "Metti questo telefono nella webcam, nel microfono e nella finestra mini")
                .accessibilityAddTraits(scelta.nellaWebcam ? .isSelected : [])
                Spacer(minLength: 4)
                Button("Scollega") { scelta.scollega() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tema.testoTenue)
                    .help("Scollega «\(telefono.nome)»: non si ricollega da solo")
            }
            .font(.corpo(12.5))
            .padding(.leading, 16)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scelta.nellaWebcam ? Tema.cianoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(scelta.nellaWebcam ? Tema.ciano.opacity(0.5) : Tema.lineaTenue))
    }

    private var dettagli: String {
        var parti = [via?.testo ?? "—"]
        parti.append(latenza.map { "\($0) ms" } ?? "— ms")
        if let avvio { parti.append(avvio) }
        return parti.joined(separator: " · ")
    }

    static func descrizione(_ temperatura: Temperatura) -> String {
        switch temperatura {
        case .normale: String(localized: "normale")
        case .calda: String(localized: "Telefono caldo")
        case .moltoCalda: String(localized: "Telefono molto caldo")
        case .critica: String(localized: "Telefono troppo caldo")
        }
    }
}

/// La batteria del telefono: icona e percentuale; ambra sotto il 20% senza caricatore.
private struct Batteria: View {
    let percentuale: Int
    let inCarica: Bool

    private var simbolo: String {
        if inCarica { return "battery.100percent.bolt" }
        switch percentuale {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        let bassa = percentuale <= 20 && !inCarica
        HStack(spacing: 3) {
            Image(systemName: simbolo)
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(verbatim: "\(percentuale)%")
                .font(.numeri(11))
        }
        .foregroundStyle(bassa ? Tema.ambra : Tema.testoSecondario)
        .fixedSize()
        .help(inCarica ? "Batteria del telefono: \(percentuale)%, in carica" : "Batteria del telefono: \(percentuale)%")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(inCarica ? "Batteria del telefono: \(percentuale)%, in carica" : "Batteria del telefono: \(percentuale)%")
    }
}

/// Un telefono fidato che ora non è collegato: punto vuoto, nome tenue, «Non collegato».
private struct RigaTelefonoNoto: View {
    let nome: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(Tema.testoSecondario, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Image(systemName: "iphone")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tema.testoSecondario)
                .accessibilityHidden(true)
            Text(nome)
                .font(.corpo(13))
                .foregroundStyle(Tema.testoTenue)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("Non collegato")
                .font(.etichetta(13))
                .foregroundStyle(Tema.testoSecondario)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help("Telefono fidato: si collega da solo quando apri WebcamLR sul telefono")
        .accessibilityElement(children: .combine)
    }
}

/// Una strada di collegamento: icona, nome, stato; quella in uso nell'accento, su un fondo leggero.
private struct RigaConnessione: View {
    let simbolo: String
    let nome: String
    let stato: String
    let attiva: Bool
    var interruttore: Binding<Bool>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: simbolo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(attiva ? Tema.accento : Tema.testoSecondario)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(nome)
                .font(attiva ? .corpoEvidente(13) : .corpo(13))
                .foregroundStyle(attiva ? Tema.testo : Tema.testoTenue)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(stato)
                .font(.etichetta(13))
                .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                .lineLimit(1)
                .fixedSize()
            if let interruttore {
                Toggle(nome, isOn: interruttore)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(attiva ? Tema.accentoTenue : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Il microfono del telefono come microfono del Mac (P20): «WebcamLR (microphone)» nelle altre app.
/// Stato (non installato, spento, attivo, in uso), interruttore che manda `comando.audio`, livello mentre arriva.
/// Nella colonna di sinistra («Uscite») e in Impostazioni › Microfono.
struct RigaMicrofono: View {
    let ricevitore: Ricevitore
    /// «Installa…» (passo 7, mac.md 16) porta a Impostazioni › Microfono, con la sua spiegazione. Nella pagina stessa
    /// no: l'installazione è subito sotto.
    var conInstalla = true
    @Environment(\.openWindow) private var apriFinestra

    private var installato: Bool {
        if case .installato = ricevitore.installazioneMicrofono { return true }
        return false
    }

    private var inUso: Bool {
        if case .installato(let inUso) = ricevitore.installazioneMicrofono { return inUso }
        return false
    }

    /// Si può accendere solo con un telefono collegato che sa mandare l'audio.
    private var utilizzabile: Bool {
        ricevitore.telefonoMandaAudio
    }

    private var stato: String {
        if !installato { return String(localized: "non installato") }
        if !ricevitore.microfonoAcceso { return String(localized: "spento") }
        return inUso ? String(localized: "in uso") : String(localized: "attivo")
    }

    /// Verde solo quando l'audio arriva davvero (il corallo resta per «in onda» e la registrazione).
    private var attivo: Bool {
        installato && ricevitore.microfonoAcceso && ricevitore.audioInArrivo
    }

    private var acceso: Binding<Bool> {
        Binding(get: { ricevitore.microfonoAcceso }, set: { ricevitore.impostaMicrofono($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: attivo ? "mic.fill" : "mic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(attivo ? Tema.verde : Tema.testoSecondario)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("Microfono del telefono")
                    .font(.corpo(13))
                    .foregroundStyle(utilizzabile ? Tema.testo : Tema.testoSecondario)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                Text(stato)
                    .font(.etichetta(13))
                    .foregroundStyle(attivo ? Tema.verde : Tema.testoSecondario)
                    .lineLimit(1)
                    .fixedSize()
                Toggle("Microfono del telefono", isOn: acceso)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!utilizzabile)
            }
            .frame(minHeight: 28)

            // Il livello si vede sempre (vuoto quando non arriva niente): si capisce subito dov'è.
            IndicatoreLivello(livello: ricevitore.microfonoAcceso && ricevitore.audioInArrivo && utilizzabile
                                ? ricevitore.livelloMicrofono : 0)
                .padding(.leading, 24)
                .accessibilityLabel("Livello del microfono")
                .accessibilityValue("\(Int(ricevitore.livelloMicrofono * 100)) per cento")

            if let nota {
                Text(nota)
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
            if !installato && conInstalla {
                // Passo 7 (mac.md 16): l'errore con il pulsante, anche senza telefono (l'installazione non ne ha bisogno).
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Il microfono non è ancora installato.")
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Installa…") { apriImpostazioniWebcamLR(.microfono, apri: apriFinestra) }
                        .buttonStyle(StilePulsanteSecondario())
                        .help("In Impostazioni › Microfono (⌘,)")
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 8)
        .opacity(ricevitore.telefonoAttivo || !installato ? 1 : 0.6)
    }

    /// Una riga sotto, solo quando serve dire qualcosa.
    private var nota: String? {
        if !ricevitore.telefonoAttivo { return String(localized: "Collega un telefono per usarlo.") }
        // Capacità non ancora arrivate: per un attimo non si dice niente.
        if let capacita = ricevitore.capacita, capacita.audio != true { return String(localized: "Il telefono non manda l'audio.") }
        // Non installato: lo dice la riga con «Installa…» qui sotto.
        if !installato { return nil }
        if ricevitore.microfonoAcceso && !ricevitore.audioInArrivo && ricevitore.capacita?.audio == true {
            return String(localized: "In attesa dell'audio dal telefono…")
        }
        if ricevitore.microfonoAcceso { return String(localized: "Nelle app scegli «WebcamLR (microphone)» come microfono.") }
        return nil
    }
}

/// Il livello del microfono: dodici tacche che si accendono nell'accento, ambra vicino alla saturazione.
private struct IndicatoreLivello: View {
    let livello: Double
    private static let tacche = 12

    var body: some View {
        let accese = Int((max(0, min(1, livello)) * Double(Self.tacche)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<Self.tacche, id: \.self) { indice in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(indice < accese ? colore(indice) : Tema.pannelloChiaro)
                    .frame(height: 6)
            }
        }
        .animation(.linear(duration: 0.1), value: accese)
    }

    /// Le ultime due tacche in ambra: oltre il 90% il suono rischia di saturare.
    private func colore(_ indice: Int) -> Color {
        indice >= Self.tacche - 2 ? Tema.ambra : Tema.ciano
    }
}

/// Un'uscita del video. Quelle «in arrivo» sono tenui, con l'etichetta in una capsula: si vede che è voluto.
private struct RigaUscita: View {
    let nome: String
    let stato: String
    let attiva: Bool
    var inArrivo = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: inArrivo ? "clock" : "video")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(nome)
                .font(.corpo(13))
                .foregroundStyle(inArrivo ? Tema.testoSecondario : Tema.testo)
                .lineLimit(1)
            Spacer(minLength: 8)
            if inArrivo {
                Text(stato.uppercased())
                    .font(.etichetta(12))
                    .tracking(0.6)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(Tema.linea))
                    .fixedSize()
            } else {
                Text(stato)
                    .font(.etichetta(13))
                    .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}
