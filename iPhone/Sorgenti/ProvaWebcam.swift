import CoreGraphics
import CoreVideo
import Foundation
import Observation
import Stile
import SwiftUI
import WebcamLRProtocollo

// MARK: - Sonda della luce

/// P05: misura la luce del volto e dello sfondo sui fotogrammi della cattura, solo mentre «Prova la webcam» è
/// in corso. Spenta costa un blocco letto per fotogramma; accesa, tre misure al secondo su una coda sua, sul piano
/// della luminanza (Y) a campioni radi: la cattura non aspetta mai.
final class SondaLuce: @unchecked Sendable {
    struct Campione: Sendable {
        /// Luminanza media da 0 (nero) a 1 (bianco); `volto` è `nil` se non c'era un volto.
        let luceVolto: Double?
        let luceSfondo: Double
        /// Il volto principale, normalizzato con l'origine in basso a sinistra (come l'analisi).
        let volto: CGRect?
    }

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.sonda", qos: .utility)
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var attiva = false
    private var inCorso = false
    private var ultimaMisura: TimeInterval = 0
    private var campioni: [Campione] = []

    func avvia() {
        blocco.withLock {
            campioni = []
            ultimaMisura = 0
            attiva = true
        }
    }

    /// Si ferma e ritorna i campioni raccolti.
    func ferma() -> [Campione] {
        blocco.withLock {
            attiva = false
            let raccolti = campioni
            campioni = []
            return raccolti
        }
    }

    /// Dalla coda di cattura, per ogni fotogramma (già dritto). Ritorna subito.
    func considera(_ immagine: CVPixelBuffer, analisi: AnalisiFotogramma) {
        let adesso = ProcessInfo.processInfo.systemUptime
        let tocca: Bool = blocco.withLock {
            guard attiva, !inCorso, adesso - ultimaMisura >= 0.33 else { return false }
            inCorso = true
            ultimaMisura = adesso
            return true
        }
        guard tocca else { return }
        // Un volto solo se il risultato dell'analisi è recente.
        let recenti = analisi.ultimiVolti.flatMap { adesso - $0.quando < 0.6 ? $0.rettangoli : nil } ?? []
        let volto = recenti.max { $0.width * $0.height < $1.width * $1.height }
        coda.async { [weak self] in
            let campione = Self.misura(immagine, volto: volto)
            guard let self else { return }
            self.blocco.withLock {
                self.inCorso = false
                if self.attiva, let campione { self.campioni.append(campione) }
            }
        }
    }

    /// Media della luminanza dentro e fuori dal volto, su una griglia di circa 100 × 60 punti.
    private static func misura(_ immagine: CVPixelBuffer, volto: CGRect?) -> Campione? {
        guard CVPixelBufferIsPlanar(immagine), CVPixelBufferGetPlaneCount(immagine) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(immagine, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(immagine, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(immagine, 0) else { return nil }
        let larghezza = CVPixelBufferGetWidthOfPlane(immagine, 0)
        let altezza = CVPixelBufferGetHeightOfPlane(immagine, 0)
        let riga = CVPixelBufferGetBytesPerRowOfPlane(immagine, 0)
        guard larghezza > 0, altezza > 0 else { return nil }
        let pixel = base.assumingMemoryBound(to: UInt8.self)
        // 420v: luminanza video da 16 a 235; 420f: piena da 0 a 255.
        let pieno = CVPixelBufferGetPixelFormatType(immagine) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let minimo: Double = pieno ? 0 : 16
        let ampiezza: Double = pieno ? 255 : 219

        // Il volto in pixel, con l'origine in alto.
        var area = CGRect.null
        if let volto {
            area = CGRect(x: volto.minX * CGFloat(larghezza), y: (1 - volto.maxY) * CGFloat(altezza),
                          width: volto.width * CGFloat(larghezza), height: volto.height * CGFloat(altezza))
        }
        let passoX = max(larghezza / 100, 1)
        let passoY = max(altezza / 60, 1)
        var sommaVolto = 0, puntiVolto = 0, sommaSfondo = 0, puntiSfondo = 0
        var y = passoY / 2
        while y < altezza {
            let inizioRiga = pixel + y * riga
            var x = passoX / 2
            while x < larghezza {
                let valore = Int(inizioRiga[x])
                if !area.isNull, area.contains(CGPoint(x: x, y: y)) {
                    sommaVolto += valore
                    puntiVolto += 1
                } else {
                    sommaSfondo += valore
                    puntiSfondo += 1
                }
                x += passoX
            }
            y += passoY
        }
        func normalizza(_ somma: Int, _ punti: Int) -> Double {
            min(max((Double(somma) / Double(punti) - minimo) / ampiezza, 0), 1)
        }
        guard puntiSfondo > 0 else { return nil }
        return Campione(luceVolto: puntiVolto > 0 ? normalizza(sommaVolto, puntiVolto) : nil,
                        luceSfondo: normalizza(sommaSfondo, puntiSfondo),
                        volto: puntiVolto > 0 ? volto : nil)
    }
}

// MARK: - Prova

/// P05 «Prova la webcam»: 5 secondi di analisi, poi una lista di controlli con ✓ o ⚠ e «Sistema» per le
/// correzioni che l'iPhone sa fare da solo.
@Observable
@MainActor
final class ProvaWebcam {
    enum Problema: Hashable {
        case senzaVideo, senzaVolto, buio, controluce, decentrato, lontano, vicino, storto
    }

    struct Esito: Identifiable {
        let id: String
        let titolo: String
        let dettaglio: String?
        let problema: Problema?
        var bene: Bool { problema == nil }
    }

    enum Fase: Equatable {
        case pronta
        case inCorso
        case finita
    }

    static let durata: TimeInterval = 5

    private(set) var fase: Fase = .pronta
    private(set) var progresso: Double = 0
    private(set) var esiti: [Esito] = []
    /// Le correzioni applicate con «Sistema», da mostrare sotto la lista.
    private(set) var correzioni: [String] = []

    private let sessione: SessioneTelefono
    private let livella = Livella()
    @ObservationIgnored private var compito: Task<Void, Never>?
    private static let consumatore = "prova"

    init(sessione: SessioneTelefono) {
        self.sessione = sessione
    }

    var problemi: Set<Problema> {
        Set(esiti.compactMap(\.problema))
    }

    /// Ci sono problemi che «Sistema» può correggere da solo.
    var sistemabile: Bool {
        !problemi.isDisjoint(with: [.buio, .controluce, .decentrato, .lontano])
    }

    func avvia() {
        guard fase != .inCorso else { return }
        fase = .inCorso
        progresso = 0
        esiti = []
        correzioni = []
        // P10: mentre si prova non si va in pausa «nessuna app» (e se lo era, la fotocamera si riaccende).
        sessione.pausa.trattieni(true)
        sessione.effetti.analisi.richiedi(.volti, per: Self.consumatore)
        sessione.sonda.avvia()
        livella.avvia()
        compito?.cancel()
        compito = Task { [weak self] in
            let inizio = Date()
            var inclinazioni: [Double] = []
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if let scostamento = self.livella.scostamento { inclinazioni.append(scostamento) }
                let trascorso = Date().timeIntervalSince(inizio)
                self.progresso = min(trascorso / Self.durata, 1)
                if trascorso >= Self.durata {
                    self.concludi(inclinazioni: inclinazioni)
                    return
                }
            }
        }
    }

    /// Foglio chiuso a metà: si smette di misurare.
    func annulla() {
        compito?.cancel()
        compito = nil
        if fase == .inCorso {
            _ = sessione.sonda.ferma()
            sessione.effetti.analisi.rinuncia(.volti, per: Self.consumatore)
            sessione.pausa.trattieni(false)
            livella.ferma()
            fase = .pronta
        }
    }

    /// Le correzioni che l'iPhone sa fare: luce sul volto ed esposizione più alta per buio e controluce,
    /// inquadratura automatica per volto decentrato o lontano. Gli altri problemi restano consigli.
    func sistema() {
        let problemi = self.problemi
        var fatte: [String] = []
        if !problemi.isDisjoint(with: [.buio, .controluce]) {
            if !sessione.funzioni.luceVolto {
                sessione.funzioni.impostaLuceVolto(true)
                fatte.append(String(localized: "Luce sul volto accesa"))
            }
            // Più luce, senza togliere quella già scelta (sul computer o qui).
            let voluta = problemi.contains(.controluce) ? 1.0 : 0.7
            if sessione.esposizione < voluta && sessione.iso == 0 && sessione.tempo == 0 {
                sessione.applica(Comando(esposizione: voluta))
                // «+0,7» in italiano, «+0.7» in inglese: la virgola o il punto li mette il catalogo.
                let decimi = Int((voluta * 10).rounded())
                fatte.append(String(localized: "Esposizione +\(Int(decimi / 10)),\(Int(decimi % 10))"))
            }
        }
        // L'inquadratura automatica è di WebcamLR Pro: senza resta il consiglio.
        if !problemi.isDisjoint(with: [.decentrato, .lontano]), !sessione.funzioni.inquadratura, sessione.pro {
            sessione.funzioni.impostaInquadratura(true)
            fatte.append(String(localized: "Inquadratura automatica accesa"))
        }
        correzioni = fatte.isEmpty ? [String(localized: "Era già tutto acceso: segui i consigli qui sopra.")] : fatte
    }

    private func concludi(inclinazioni: [Double]) {
        let campioni = sessione.sonda.ferma()
        sessione.effetti.analisi.rinuncia(.volti, per: Self.consumatore)
        sessione.pausa.trattieni(false)
        livella.ferma()
        compito = nil
        esiti = Self.valuta(campioni: campioni, inclinazioni: inclinazioni, torcia: sessione.torciaDisponibile)
        fase = .finita
    }

    private static func valuta(campioni: [SondaLuce.Campione], inclinazioni: [Double], torcia: Bool) -> [Esito] {
        guard !campioni.isEmpty else {
            return [Esito(id: "video", titolo: String(localized: "Non arriva il video dalla fotocamera"),
                          dettaglio: String(localized: "Aspetta che il video riparta e tocca «Prova di nuovo»."), problema: .senzaVideo)]
        }
        var esiti: [Esito] = []
        let conVolto = campioni.filter { $0.volto != nil }
        if Double(conVolto.count) < Double(campioni.count) * 0.5 {
            esiti.append(Esito(id: "volto", titolo: String(localized: "Non vedo il tuo volto"),
                               dettaglio: String(localized: "Mettiti davanti alla fotocamera, a circa un braccio di distanza."), problema: .senzaVolto))
        } else {
            let n = Double(conVolto.count)
            let luceVolto = conVolto.compactMap(\.luceVolto).reduce(0, +) / n
            let luceSfondo = conVolto.map(\.luceSfondo).reduce(0, +) / n
            let centroX = conVolto.compactMap { $0.volto.map { Double($0.midX) } }.reduce(0, +) / n
            // Dall'alto: il volto sta bene tra un quarto e poco più di metà altezza.
            let centroY = conVolto.compactMap { $0.volto.map { 1 - Double($0.midY) } }.reduce(0, +) / n
            let altezza = conVolto.compactMap { $0.volto.map { Double($0.height) } }.reduce(0, +) / n

            if luceVolto < 0.28 {
                esiti.append(Esito(id: "luce", titolo: String(localized: "Il volto è al buio"),
                                   dettaglio: torcia
                                       ? String(localized: "Accendi una luce davanti a te, oppure la torcia dell'iPhone.")
                                       : String(localized: "Accendi una luce davanti a te, all'altezza del viso."),
                                   problema: .buio))
            } else if luceSfondo - luceVolto > 0.18 {
                esiti.append(Esito(id: "luce", titolo: String(localized: "Sei in controluce"),
                                   dettaglio: String(localized: "La luce alle tue spalle scurisce il volto: girati verso la finestra o sposta la lampada davanti a te."),
                                   problema: .controluce))
            } else {
                esiti.append(Esito(id: "luce", titolo: String(localized: "Luce sul volto buona"), dettaglio: nil, problema: nil))
            }

            if abs(centroX - 0.5) > 0.15 || centroY < 0.2 || centroY > 0.62 {
                esiti.append(Esito(id: "centro", titolo: String(localized: "Volto decentrato"),
                                   dettaglio: String(localized: "Sposta l'iPhone o il supporto per avere il volto al centro, con gli occhi a un terzo dall'alto."),
                                   problema: .decentrato))
            } else {
                esiti.append(Esito(id: "centro", titolo: String(localized: "Volto al centro"), dettaglio: nil, problema: nil))
            }

            if altezza < 0.13 {
                esiti.append(Esito(id: "distanza", titolo: String(localized: "Sei lontano dalla fotocamera"),
                                   dettaglio: String(localized: "Avvicinati un po', oppure lascia fare all'inquadratura automatica."), problema: .lontano))
            } else if altezza > 0.5 {
                esiti.append(Esito(id: "distanza", titolo: String(localized: "Sei troppo vicino alla fotocamera"),
                                   dettaglio: String(localized: "Allontanati un po': si vedranno anche le spalle."), problema: .vicino))
            } else {
                esiti.append(Esito(id: "distanza", titolo: String(localized: "Distanza giusta"), dettaglio: nil, problema: nil))
            }
        }

        // L'iPhone steso sul tavolo non dice nulla: il controllo si salta.
        if !inclinazioni.isEmpty {
            let media = inclinazioni.reduce(0, +) / Double(inclinazioni.count)
            if abs(media) > 2.5 {
                let gradi = Int(abs(media).rounded())
                esiti.append(Esito(id: "dritto", titolo: String(localized: "iPhone storto di \(gradi)°"),
                                   dettaglio: String(localized: "Raddrizzalo sul supporto: la livella nelle Impostazioni diventa verde quando è dritto."),
                                   problema: .storto))
            } else {
                esiti.append(Esito(id: "dritto", titolo: String(localized: "iPhone dritto"), dettaglio: nil, problema: nil))
            }
        }
        return esiti
    }
}

// MARK: - Vista

/// La prova dentro il foglio dell'assistente.
struct VistaProvaWebcam: View {
    @State private var prova: ProvaWebcam

    init(sessione: SessioneTelefono) {
        _prova = State(initialValue: ProvaWebcam(sessione: sessione))
    }

    var body: some View {
        List {
            switch prova.fase {
            case .pronta:
                Section {
                    Text("Guarda verso la fotocamera e resta fermo per 5 secondi: controllo luce, inquadratura, distanza e se l'iPhone è dritto.")
                        .foregroundStyle(Tema.testoChiaro)
                        .listRowBackground(Tema.pannello)
                    pulsante("Inizia la prova") { prova.avvia() }
                }
            case .inCorso:
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Guarda verso la fotocamera…")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: prova.progresso)
                            .tint(Tema.ciano)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Tema.pannello)
                }
            case .finita:
                Section {
                    ForEach(prova.esiti) { esito in
                        RigaEsito(esito: esito)
                            .listRowBackground(Tema.pannello)
                    }
                } header: {
                    EtichettaSezione(String(localized: "Risultato"))
                }
                Section {
                    if prova.sistemabile && prova.correzioni.isEmpty {
                        pulsante("Sistema") { withAnimation { prova.sistema() } }
                    }
                    pulsante("Prova di nuovo") { prova.avvia() }
                } footer: {
                    if !prova.correzioni.isEmpty {
                        Text(prova.correzioni.joined(separator: "\n"))
                            .font(.footnote)
                            .foregroundStyle(Tema.cianoChiaro)
                    } else if prova.sistemabile {
                        Text("«Sistema» accende la luce sul volto, alza l'esposizione o accende l'inquadratura automatica, secondo il problema.")
                            .font(.footnote)
                            .foregroundStyle(Tema.testoSecondario)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .navigationTitle("Prova la webcam")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { prova.annulla() }
    }

    private func pulsante(_ titolo: LocalizedStringKey, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(titolo)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Tema.fondo)
                .background(Tema.ciano, in: Capsule())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

private struct RigaEsito: View {
    let esito: ProvaWebcam.Esito

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: esito.bene ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(esito.bene ? Tema.verde : Tema.ambra)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(esito.titolo)
                    .font(.subheadline.weight(.semibold))
                if let dettaglio = esito.dettaglio {
                    Text(dettaglio)
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(esito.bene ? String(localized: "A posto: \(descrizioneAccessibile)")
                            : String(localized: "Da sistemare: \(descrizioneAccessibile)"))
    }

    private var descrizioneAccessibile: String {
        esito.titolo + (esito.dettaglio.map { ". " + $0 } ?? "")
    }
}
