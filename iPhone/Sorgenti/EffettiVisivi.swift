import AVFoundation
import Foundation
import Observation
import UIKit
import WebcamLRProtocollo

/// Gli effetti sull'immagine scelti dal computer (B2): filtro e regolazioni (P13), sfondo (P14), ritocco della
/// pelle (P15), sottopancia e logo (P17). Sul telefono resta solo il pulsante «Sfoca» di «In onda».
///
/// - Tiene i valori, li salva (UserDefaults: gli effetti restano sul telefono, dice il protocollo) e li passa agli
///   effetti della pipeline, che girano sulla coda di cattura.
/// - `applica(_:)` prende i campi degli effetti di un `comando`; `completa(_:)` riempie `stato` e `capacita`.
/// - Sfondi dal computer (27 ottobre): con «sostituito» uno degli sfondi pronti del bundle (`Sfondi/<id>.jpg`) o
///   l'immagine personale; immagine personale e logo arrivano dal computer (`ricevi(_:)`, pacchetto di tipo 4) e
///   restano nell'Application Support, con la loro impronta in `stato.immaginePersonale` e `stato.logo`.
/// - A ogni cambiamento, da qualsiasi parte arrivi, chiama `suCambiamento` (al massimo 4 volte al secondo,
///   sempre con i valori finali): la sessione manda subito uno `stato`.
@Observable
@MainActor
final class EffettiVisivi {
    /// Uno dei `Filtri`; `naturale` = nessun filtro.
    private(set) var filtro = Filtri.naturale
    /// Luminosità, contrasto, saturazione e nitidezza, da -1 a 1.
    private(set) var regolazioni = RegolazioniBase.Valori()
    /// Uno dei `ModiSfondo`.
    private(set) var sfondo = ModiSfondo.nessuno
    /// Da 0 a 1: quanto sfocare, o quanto è netto il bordo dello sfondo sostituito.
    private(set) var intensitaSfondo = 0.5
    /// Con «sostituito»: l'id di uno dei `SfondiPronti`, o `SfondiPronti.personale` (l'immagine dal computer).
    private(set) var immagineSfondo = EffettiVisivi.sfondoDiSerie
    /// Impronta (`PacchettoImmagine.improntaDi`) dell'immagine personale salvata; `nil` = nessuna.
    private(set) var improntaPersonale: String?
    /// «Ritratto» di iOS (Effetti video) è acceso per WebcamLR: lo sfondo è già sfocato dal sistema.
    private(set) var ritrattoDiSistema = false
    /// Ritocco della pelle, da 0 (spento) a 1.
    private(set) var pelle = 0.0
    /// Sottopancia: nome vuoto = nessuna scritta.
    private(set) var nomeScritta = ""
    private(set) var ruoloScritta = ""
    /// Impronta del logo del sottopancia salvato; `nil` = nessun logo.
    private(set) var improntaLogo: String?
    /// Falso dopo la fine di WebcamLR Pro: il logo resta salvato ma non si vede finché Pro non torna.
    private(set) var mostraLogo = true
    /// Lo sfondo pronto di serie, e quello che vale per un id sconosciuto: il primo dell'elenco.
    nonisolated static let sfondoDiSerie = SfondiPronti.tutti.first ?? SfondiPronti.ufficio
    nonisolated static let lunghezzaNome = 40
    nonisolated static let lunghezzaRuolo = 50

    /// La sessione manda uno `stato` con i valori nuovi.
    @ObservationIgnored var suCambiamento: (() -> Void)?

    private let effettoFiltro = EffettoFiltro()
    private let effettoSfondo = EffettoSfondo()
    private let effettoPelle = EffettoPelle()
    private let effettoScritta = EffettoScritta()
    @ObservationIgnored private var compitoRitratto: Task<Void, Never>?
    @ObservationIgnored private weak var pipeline: PipelineEffetti?
    @ObservationIgnored private var compitoNotifica: Task<Void, Never>?
    /// L'immagine di «sostituito» data a `effettoSfondo` (o in lettura): l'id, con l'impronta per la personale.
    @ObservationIgnored private var immagineCaricata: String?
    /// Crescono a ogni immagine ricevuta o logo tolto: la lettura dei file all'avvio non sovrascrive ciò che è
    /// arrivato nel frattempo.
    @ObservationIgnored private var generazionePersonale = 0
    @ObservationIgnored private var generazioneLogo = 0

    private enum Chiave {
        static let filtro = "effetti.filtro"
        static let luminosita = "effetti.luminosita"
        static let contrasto = "effetti.contrasto"
        static let saturazione = "effetti.saturazione"
        static let nitidezza = "effetti.nitidezza"
        static let sfondo = "effetti.sfondo"
        static let intensitaSfondo = "effetti.intensitaSfondo"
        static let immagineSfondo = "effetti.immagineSfondo"
        static let improntaPersonale = "effetti.improntaPersonale"
        static let improntaLogo = "effetti.improntaLogo"
        static let pelle = "effetti.pelle"
        static let nomeScritta = "effetti.nomeScritta"
        static let ruoloScritta = "effetti.ruoloScritta"
        static let mostraLogo = "effetti.mostraLogo"
    }

    /// Un file nell'Application Support dell'app (resta dopo il riavvio, non va nella libreria Foto).
    private nonisolated static func file(_ nome: String) -> URL? {
        guard let cartella = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true) else { return nil }
        return cartella.appendingPathComponent(nome)
    }

    /// I byte ricevuti dal computer così come sono (JPEG o PNG): l'impronta si ricalcola uguale.
    private nonisolated static var fileLogo: URL? { file("logo-dal-computer") }
    private nonisolated static var fileSfondoPersonale: URL? { file("sfondo-dal-computer") }
    /// I file di prima, quando logo e foto si sceglievano dalla galleria del telefono: diventano quelli nuovi.
    private nonisolated static let fileVecchi = [("LogoWebcamLR.png", "logo-dal-computer"),
                                                 ("SfondoWebcamLR.jpg", "sfondo-dal-computer")]

    init() {
        let valori = UserDefaults.standard
        filtro = RicetteFiltri.normalizzato(valori.string(forKey: Chiave.filtro) ?? Filtri.naturale)
        regolazioni = RegolazioniBase.Valori(luminosita: valori.double(forKey: Chiave.luminosita),
                                             contrasto: valori.double(forKey: Chiave.contrasto),
                                             saturazione: valori.double(forKey: Chiave.saturazione),
                                             nitidezza: valori.double(forKey: Chiave.nitidezza))
        sfondo = Self.modoSfondo(valori.string(forKey: Chiave.sfondo) ?? ModiSfondo.nessuno)
        intensitaSfondo = Self.limita(valori.object(forKey: Chiave.intensitaSfondo) as? Double ?? 0.5, 0, 1)
        immagineSfondo = Self.sceltaSfondo(valori.string(forKey: Chiave.immagineSfondo) ?? Self.sfondoDiSerie)
        // Le impronte salvate valgono subito per il primo `stato`; `controllaFileSalvati` le verifica sui file.
        improntaPersonale = valori.string(forKey: Chiave.improntaPersonale)
        improntaLogo = valori.string(forKey: Chiave.improntaLogo)
        pelle = Self.limita(valori.double(forKey: Chiave.pelle), 0, 1)
        nomeScritta = String((valori.string(forKey: Chiave.nomeScritta) ?? "").prefix(Self.lunghezzaNome))
        ruoloScritta = String((valori.string(forKey: Chiave.ruoloScritta) ?? "").prefix(Self.lunghezzaRuolo))
        mostraLogo = valori.object(forKey: Chiave.mostraLogo) as? Bool ?? true
        ContestiEffetti.prepara()
    }

    /// Mette gli effetti nella pipeline, ognuno nella sua fase, con i valori salvati.
    func collega(_ pipeline: PipelineEffetti) {
        self.pipeline = pipeline
        pipeline.aggiungi(effettoFiltro, fase: .filtro)
        effettoFiltro.filtro = filtro
        pipeline.regolazioni.valori = regolazioni
        pipeline.aggiungi(effettoSfondo, fase: .sfondo)
        pipeline.aggiungi(effettoPelle, fase: .pelle)
        effettoPelle.forza = pelle
        pipeline.aggiungi(effettoScritta, fase: .scritta)
        aggiornaScritta()
        aggiornaSfondo()
        controllaFileSalvati()
        controllaRitratto()
        // «Ritratto» si accende e si spegne dal Centro di Controllo: si guarda ogni 2 secondi, finché la
        // sessione (e con lei questo oggetto) esiste.
        compitoRitratto = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.controllaRitratto()
            }
        }
    }

    // MARK: Dal telefono

    /// Il pulsante tondo «Sfoca» di «In onda».
    func scegliSfondo(_ modo: String) {
        let normalizzato = Self.modoSfondo(modo)
        guard normalizzato != sfondo else { return }
        sfondo = normalizzato
        aggiornaSfondo()
        cambiato()
    }

    /// Falso alla fine di WebcamLR Pro, vero quando torna: il logo salvato si nasconde e si rivede.
    func impostaMostraLogo(_ mostra: Bool) {
        guard mostra != mostraLogo else { return }
        mostraLogo = mostra
        aggiornaScritta()
        cambiato()
    }

    // MARK: Dal computer

    /// Un'immagine mandata dal computer (pacchetto di tipo 4; Pro l'ha già controllato la sessione). Si apre e si
    /// riduce fuori dal thread principale (lato lungo 1920 px lo sfondo, 512 il logo con la trasparenza), poi i byte
    /// ricevuti si salvano al posto di quelli di prima e restano dopo il riavvio. Lo `stato` che segue porta la
    /// nuova impronta. Falso se non si apre o non si salva: allora non cambia nulla.
    func ricevi(_ immagine: PacchettoImmagine) async -> Bool {
        let uso = immagine.uso
        let dati = immagine.dati
        let letta = await Task.detached(priority: .userInitiated) { () -> (immagine: CGImage, impronta: String)? in
            guard let aperta = UIImage(data: dati),
                  let piccola = uso == .logo ? Self.ridotta(aperta, latoMassimo: 512, opaca: false)
                                             : Self.ridotta(aperta, latoMassimo: 1920),
                  let file = uso == .logo ? Self.fileLogo : Self.fileSfondoPersonale else { return nil }
            do {
                try dati.write(to: file, options: .atomic)
            } catch {
                return nil
            }
            return (piccola, PacchettoImmagine.improntaDi(dati))
        }.value
        guard let letta else { return false }
        switch uso {
        case .sfondo:
            generazionePersonale += 1
            improntaPersonale = letta.impronta
            if immagineSfondo == SfondiPronti.personale {
                // Già scelta: si usa subito, senza rileggere il file.
                immagineCaricata = Self.chiaveImmagine(SfondiPronti.personale, impronta: letta.impronta)
                effettoSfondo.impostaImmagine(letta.immagine)
            }
            aggiornaSfondo()
        case .logo:
            generazioneLogo += 1
            improntaLogo = letta.impronta
            effettoScritta.impostaLogo(letta.immagine)
            mostraLogo = true
            aggiornaScritta()
        }
        cambiato()
        return true
    }

    /// `comando.togliLogo`: il logo si cancella, anche dal disco. Vero se c'era.
    private func togliLogo() -> Bool {
        guard improntaLogo != nil else { return false }
        generazioneLogo += 1
        improntaLogo = nil
        effettoScritta.impostaLogo(nil)
        if let file = Self.fileLogo { try? FileManager.default.removeItem(at: file) }
        return true
    }

    /// Senza WebcamLR Pro (mai comprato, rimborsato, fine della condivisione In famiglia): spegne filtri, regolazioni,
    /// sfondo sostituito, ritocco, scritta e logo. Lo sfondo sfocato resta: è gratis. Vero se il video cambia.
    @discardableResult
    func spegniFunzioniPro() -> Bool {
        var comando = Comando()
        if filtro != Filtri.naturale { comando.filtro = Filtri.naturale }
        if regolazioni != RegolazioniBase.Valori() {
            comando.regolazioni = Regolazioni(luminosita: 0, contrasto: 0, saturazione: 0, nitidezza: 0)
        }
        if sfondo == ModiSfondo.sostituito { comando.sfondo = ModiSfondo.nessuno }
        if pelle > 0 { comando.pelle = 0 }
        if !nomeScritta.isEmpty || !ruoloScritta.isEmpty { comando.scritta = Scritta.nessuna }
        var spento = applica(comando)
        if mostraLogo {
            if improntaLogo != nil { spento = true }
            impostaMostraLogo(false)
        }
        return spento
    }

    // MARK: Protocollo

    /// I campi degli effetti di un `comando` (solo quelli presenti). Ritorna vero se è cambiato qualcosa.
    @discardableResult
    func applica(_ comando: Comando) -> Bool {
        var cambiatoQualcosa = false
        if let nuovo = comando.filtro {
            let normalizzato = RicetteFiltri.normalizzato(nuovo)
            if normalizzato != filtro {
                filtro = normalizzato
                effettoFiltro.filtro = normalizzato
                cambiatoQualcosa = true
            }
        }
        if let parziali = comando.regolazioni {
            var nuove = regolazioni
            if let valore = parziali.luminosita { nuove.luminosita = Self.limita(valore, -1, 1) }
            if let valore = parziali.contrasto { nuove.contrasto = Self.limita(valore, -1, 1) }
            if let valore = parziali.saturazione { nuove.saturazione = Self.limita(valore, -1, 1) }
            if let valore = parziali.nitidezza { nuove.nitidezza = Self.limita(valore, -1, 1) }
            if nuove != regolazioni {
                regolazioni = nuove
                pipeline?.regolazioni.valori = nuove
                cambiatoQualcosa = true
            }
        }
        if let modo = comando.sfondo {
            let normalizzato = Self.modoSfondo(modo)
            if normalizzato != sfondo {
                sfondo = normalizzato
                cambiatoQualcosa = true
            }
        }
        if let scelta = comando.immagineSfondo {
            let normalizzata = Self.sceltaSfondo(scelta)
            if normalizzata != immagineSfondo {
                immagineSfondo = normalizzata
                cambiatoQualcosa = true
            }
        }
        if comando.togliLogo == true, togliLogo() {
            cambiatoQualcosa = true
        }
        if let valore = comando.intensitaSfondo {
            let limitato = Self.limita(valore, 0, 1)
            if limitato != intensitaSfondo {
                intensitaSfondo = limitato
                cambiatoQualcosa = true
            }
        }
        if let valore = comando.pelle {
            let limitato = Self.limita(valore, 0, 1)
            if limitato != pelle {
                pelle = limitato
                effettoPelle.forza = limitato
                cambiatoQualcosa = true
            }
        }
        if let scritta = comando.scritta {
            // Ruolo assente = nessun ruolo; nome vuoto = nessuna scritta.
            let nuovoNome = String(scritta.nome.prefix(Self.lunghezzaNome))
            let nuovoRuolo = String((scritta.ruolo ?? "").prefix(Self.lunghezzaRuolo))
            if nuovoNome != nomeScritta || nuovoRuolo != ruoloScritta {
                nomeScritta = nuovoNome
                ruoloScritta = nuovoRuolo
                aggiornaScritta()
                cambiatoQualcosa = true
            }
        }
        if cambiatoQualcosa {
            aggiornaSfondo()
            cambiato()
        }
        return cambiatoQualcosa
    }

    /// Un telefono che sa fare gli effetti manda sempre in `stato` tutti quelli che dichiara in `capacita`.
    func completa(_ stato: inout StatoTelefono) {
        stato.filtro = filtro
        stato.regolazioni = Regolazioni(luminosita: regolazioni.luminosita, contrasto: regolazioni.contrasto,
                                        saturazione: regolazioni.saturazione, nitidezza: regolazioni.nitidezza)
        stato.sfondo = sfondo
        stato.intensitaSfondo = intensitaSfondo
        stato.immagineSfondo = immagineSfondoEffettiva
        stato.immaginePersonale = improntaPersonale
        stato.logo = improntaLogo
        stato.pelle = pelle
        let nome = nomeScritta.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruolo = ruoloScritta.trimmingCharacters(in: .whitespacesAndNewlines)
        stato.scritta = Scritta(nome: nome, ruolo: nome.isEmpty || ruolo.isEmpty ? nil : ruolo)
    }

    func completa(_ capacita: inout Capacita) {
        capacita.filtri = Filtri.tutti
        // La maschera della persona (Vision) c'è su tutti gli iPhone con iOS 17.
        capacita.sfondo = true
        // Sfondi dal computer: gli sfondi pronti del bundle e il pacchetto immagine (sfondo personale e logo).
        capacita.sfondiPronti = SfondiPronti.tutti
        capacita.immagini = true
        capacita.pelle = true
        capacita.scritta = true
    }

    // MARK: Interni

    /// L'immagine di «sostituito» che si usa davvero: la personale solo se c'è, un id sconosciuto vale il primo.
    var immagineSfondoEffettiva: String {
        if immagineSfondo == SfondiPronti.personale {
            return improntaPersonale == nil ? Self.sfondoDiSerie : SfondiPronti.personale
        }
        return SfondiPronti.tutti.contains(immagineSfondo) ? immagineSfondo : Self.sfondoDiSerie
    }

    private func aggiornaSfondo() {
        effettoSfondo.impostazioni = EffettoSfondo.Impostazioni(modo: sfondo, intensita: intensitaSfondo,
                                                                ritrattoDiSistema: ritrattoDiSistema)
        // L'immagine si legge solo quando serve (con «sostituito») e quando cambia, fuori dal thread principale.
        guard sfondo == ModiSfondo.sostituito else { return }
        let scelta = immagineSfondoEffettiva
        let chiave = Self.chiaveImmagine(scelta, impronta: improntaPersonale)
        guard chiave != immagineCaricata else { return }
        immagineCaricata = chiave
        let effetto = effettoSfondo
        Task { [weak self] in
            let letta = await Task.detached(priority: .userInitiated) { Self.leggiSfondo(scelta) }.value
            // Intanto può essere cambiata la scelta: vale solo l'ultima.
            guard let self, self.immagineCaricata == chiave else { return }
            effetto.impostaImmagine(letta)
        }
    }

    private nonisolated static func chiaveImmagine(_ scelta: String, impronta: String?) -> String {
        scelta == SfondiPronti.personale ? scelta + "-" + (impronta ?? "") : scelta
    }

    /// Uno sfondo pronto dal bundle (`Sfondi/<id>.jpg`, 1920×1080) o l'immagine personale salvata, dritta e ridotta.
    private nonisolated static func leggiSfondo(_ scelta: String) -> CGImage? {
        let indirizzo = scelta == SfondiPronti.personale
            ? fileSfondoPersonale
            : Bundle.main.url(forResource: scelta, withExtension: "jpg", subdirectory: "Sfondi")
        guard let indirizzo, let dati = try? Data(contentsOf: indirizzo), let immagine = UIImage(data: dati) else {
            return nil
        }
        return ridotta(immagine, latoMassimo: 1920)
    }

    private func aggiornaScritta() {
        effettoScritta.contenuto = EffettoScritta.Contenuto(nome: nomeScritta, ruolo: ruoloScritta,
                                                            mostraLogo: mostraLogo)
    }

    /// Immagine personale e logo salvati, letti in sottofondo all'avvio: le impronte vere (un file mancante = nessuna)
    /// e il logo per il sottopancia. Prima i file di quando si sceglievano dalla galleria prendono il nome nuovo.
    private func controllaFileSalvati() {
        let personalePrima = generazionePersonale
        let logoPrima = generazioneLogo
        Task { [weak self] in
            let letti = await Task.detached(priority: .utility) { () -> FileSalvati in
                Self.spostaFileVecchi()
                let personale = Self.fileSfondoPersonale
                    .flatMap { try? Data(contentsOf: $0) }
                    .map { PacchettoImmagine.improntaDi($0) }
                guard let file = Self.fileLogo, let dati = try? Data(contentsOf: file), let aperto = UIImage(data: dati),
                      let ridotto = Self.ridotta(aperto, latoMassimo: 512, opaca: false) else {
                    return FileSalvati(personale: personale, logo: nil, improntaLogo: nil)
                }
                return FileSalvati(personale: personale, logo: ridotto, improntaLogo: PacchettoImmagine.improntaDi(dati))
            }.value
            guard let self else { return }
            var cambiate = false
            // Solo se nel frattempo non è arrivato nulla dal computer.
            if self.generazionePersonale == personalePrima, self.improntaPersonale != letti.personale {
                self.improntaPersonale = letti.personale
                self.aggiornaSfondo()
                cambiate = true
            }
            if self.generazioneLogo == logoPrima {
                self.effettoScritta.impostaLogo(letti.logo)
                if self.improntaLogo != letti.improntaLogo {
                    self.improntaLogo = letti.improntaLogo
                    cambiate = true
                }
            }
            if cambiate { self.cambiato() }
        }
    }

    /// Ciò che `controllaFileSalvati` trova sul disco.
    private struct FileSalvati: @unchecked Sendable {
        var personale: String?
        var logo: CGImage?
        var improntaLogo: String?
    }

    /// I file vecchi (galleria del telefono) diventano i file nuovi, se questi non ci sono già.
    private nonisolated static func spostaFileVecchi() {
        let gestore = FileManager.default
        for (vecchio, nuovo) in fileVecchi {
            guard let origine = file(vecchio), let destinazione = file(nuovo),
                  gestore.fileExists(atPath: origine.path) else { continue }
            if gestore.fileExists(atPath: destinazione.path) {
                try? gestore.removeItem(at: origine)
            } else {
                try? gestore.moveItem(at: origine, to: destinazione)
            }
        }
    }

    private func controllaRitratto() {
        let acceso = AVCaptureDevice.isPortraitEffectEnabled
        guard acceso != ritrattoDiSistema else { return }
        ritrattoDiSistema = acceso
        aggiornaSfondo()
    }

    /// L'immagine dritta (orientamento applicato) con il lato lungo al massimo `latoMassimo` pixel.
    private nonisolated static func ridotta(_ immagine: UIImage, latoMassimo: CGFloat, opaca: Bool = true) -> CGImage? {
        let misura = CGSize(width: immagine.size.width * immagine.scale, height: immagine.size.height * immagine.scale)
        guard misura.width > 0, misura.height > 0 else { return nil }
        let scala = min(1, latoMassimo / max(misura.width, misura.height))
        let finale = CGSize(width: (misura.width * scala).rounded(), height: (misura.height * scala).rounded())
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = opaca
        let disegnata = UIGraphicsImageRenderer(size: finale, format: formato).image { _ in
            immagine.draw(in: CGRect(origin: .zero, size: finale))
        }
        return disegnata.cgImage
    }

    /// Uno dei `SfondiPronti` o la personale; un id sconosciuto vale il primo sfondo pronto.
    private nonisolated static func sceltaSfondo(_ valore: String) -> String {
        valore == SfondiPronti.personale || SfondiPronti.tutti.contains(valore) ? valore : sfondoDiSerie
    }

    private nonisolated static func modoSfondo(_ valore: String) -> String {
        [ModiSfondo.nessuno, ModiSfondo.sfocato, ModiSfondo.sostituito].contains(valore) ? valore : ModiSfondo.nessuno
    }

    /// Salva e avvisa la sessione, al massimo 4 volte al secondo (i cursori cambiano a ogni movimento del dito).
    private func cambiato() {
        guard compitoNotifica == nil else { return }
        compitoNotifica = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.compitoNotifica = nil
            self.salva()
            self.suCambiamento?()
        }
    }

    private func salva() {
        let valori = UserDefaults.standard
        valori.set(filtro, forKey: Chiave.filtro)
        valori.set(regolazioni.luminosita, forKey: Chiave.luminosita)
        valori.set(regolazioni.contrasto, forKey: Chiave.contrasto)
        valori.set(regolazioni.saturazione, forKey: Chiave.saturazione)
        valori.set(regolazioni.nitidezza, forKey: Chiave.nitidezza)
        valori.set(sfondo, forKey: Chiave.sfondo)
        valori.set(intensitaSfondo, forKey: Chiave.intensitaSfondo)
        valori.set(immagineSfondo, forKey: Chiave.immagineSfondo)
        valori.set(improntaPersonale, forKey: Chiave.improntaPersonale)
        valori.set(improntaLogo, forKey: Chiave.improntaLogo)
        valori.set(pelle, forKey: Chiave.pelle)
        valori.set(nomeScritta, forKey: Chiave.nomeScritta)
        valori.set(ruoloScritta, forKey: Chiave.ruoloScritta)
        valori.set(mostraLogo, forKey: Chiave.mostraLogo)
    }

    private nonisolated static func limita(_ valore: Double, _ minimo: Double, _ massimo: Double) -> Double {
        valore.isFinite ? min(max(valore, minimo), massimo) : 0
    }
}
