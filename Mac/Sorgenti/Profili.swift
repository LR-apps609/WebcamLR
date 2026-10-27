import Foundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// I profili pronti del pannello «Profilo», in un posto solo: ognuno è un insieme di scelte sensate per una
/// situazione, mandato al telefono con un solo `comando` (gli effetti) e una richiesta di `formato`.
/// Si mandano solo le parti che il telefono dichiara in `capacita`: un telefono senza sfondo sfocato
/// riceve «Colloquio» senza quella parte. Gli altri comandi (obiettivo, zoom, esposizione, regolazioni) restano come sono.
struct ProfiloPronto: Identifiable, Equatable {
    let id: String
    let nome: String
    let simbolo: String
    /// Una riga sotto il nome, per capire a cosa serve.
    let descrizione: String
    /// Il formato da chiedere, in orizzontale (in verticale i lati si scambiano). I fps scendono se il telefono
    /// non ci arriva (`capacita.formati`).
    var larghezza = 1920
    var altezza = 1080
    var fps = 30
    var luceVolto = true
    var inquadratura = false
    var doppiaVista = false
    var filtro = Filtri.naturale
    var sfondo = ModiSfondo.nessuno
    var intensitaSfondo = 0.5
    var pelle = 0.0

    /// Riunione: volto illuminato e sempre al centro, niente effetti vistosi.
    static let riunione = ProfiloPronto(
        id: "riunione", nome: String(localized: "Riunione"), simbolo: "person.2.fill",
        descrizione: String(localized: "Volto illuminato e al centro"),
        inquadratura: true)

    /// Lezione: una sola fotocamera, volto illuminato e inquadratura ferma (inseguire il volto taglierebbe la
    /// lavagna o il foglio). Spegne «Volto e scrivania» se era accesa: la doppia vista resta una scelta a parte
    /// in Effetti (prova 2: due fotocamere insieme in un profilo erano strane).
    static let lezione = ProfiloPronto(
        id: "lezione", nome: String(localized: "Lezione"), simbolo: "book.fill",
        descrizione: String(localized: "Una fotocamera, inquadratura ferma"))

    /// Diretta: movimento fluido a 60 fps (se il telefono ci arriva), inquadratura ferma, luce e colori naturali
    /// (come la presenta l'iPhone: niente «Luce sul volto»).
    static let diretta = ProfiloPronto(
        id: "diretta", nome: String(localized: "Diretta"), simbolo: "dot.radiowaves.left.and.right",
        descrizione: String(localized: "Movimento fluido a 60 fps"),
        fps: 60, luceVolto: false)

    /// Colloquio: sfondo sfocato leggero, pelle appena curata, volto illuminato e al centro.
    static let colloquio = ProfiloPronto(
        id: "colloquio", nome: String(localized: "Colloquio"), simbolo: "briefcase.fill",
        descrizione: String(localized: "Sfondo sfocato, pelle curata"),
        inquadratura: true, sfondo: ModiSfondo.sfocato, intensitaSfondo: 0.35, pelle: 0.2)

    static let tutti = [riunione, lezione, diretta, colloquio]

    static func cerca(_ id: String?) -> ProfiloPronto? {
        tutti.first { $0.id == id }
    }

    /// Cosa fa, per l'aiuto al passaggio del puntatore.
    var riepilogo: String {
        var parti = ["\(altezza)p\(fps)"]
        if luceVolto { parti.append(String(localized: "luce sul volto")) }
        parti.append(inquadratura ? String(localized: "inquadratura automatica") : String(localized: "inquadratura ferma"))
        if doppiaVista { parti.append(String(localized: "volto e scrivania: il telefono passa al Grandangolo 0,5× posteriore")) }
        if sfondo == ModiSfondo.sfocato { parti.append(String(localized: "sfondo sfocato")) }
        if pelle > 0 { parti.append(String(localized: "ritocco della pelle \(Int((pelle * 100).rounded()))%")) }
        parti.append(String(localized: "filtro \(Effetti.nomeFiltro(filtro).lowercased())"))
        return parti.joined(separator: " · ")
    }

    /// Il `comando` con le sole parti che il telefono sa fare, e le chiavi degli effetti che tocca.
    func comando(per capacita: Capacita) -> (comando: Comando, chiavi: [String]) {
        var comando = Comando()
        var chiavi: [String] = []
        if capacita.luceVolto == true {
            comando.luceVolto = luceVolto
            chiavi.append(Effetti.chiaveLuceVolto)
        }
        if capacita.inquadratura == true {
            comando.inquadratura = inquadratura
            chiavi.append(Effetti.chiaveInquadratura)
        }
        if capacita.doppiaVista == true {
            comando.doppiaVista = doppiaVista
            chiavi.append(Effetti.chiaveDoppiaVista)
        }
        if let filtri = capacita.filtri, filtri.contains(filtro) {
            comando.filtro = filtro
            chiavi.append(Effetti.chiaveFiltro)
        }
        if capacita.sfondo == true {
            comando.sfondo = sfondo
            chiavi.append(Effetti.chiaveSfondo)
            if sfondo != ModiSfondo.nessuno {
                comando.intensitaSfondo = intensitaSfondo
                chiavi.append(Effetti.chiaveIntensitaSfondo)
            }
        }
        if capacita.pelle == true {
            comando.pelle = pelle
            chiavi.append(Effetti.chiavePelle)
        }
        return (comando, chiavi)
    }

    /// Gli effetti come diventano dopo il `comando` (solo le parti che il telefono sa fare).
    func applica(a effetti: Effetti, capacita: Capacita) -> Effetti {
        var nuovi = effetti
        if capacita.luceVolto == true { nuovi.luceVolto = luceVolto }
        if capacita.inquadratura == true { nuovi.inquadratura = inquadratura }
        if capacita.doppiaVista == true { nuovi.doppiaVista = doppiaVista }
        if let filtri = capacita.filtri, filtri.contains(filtro) { nuovi.filtro = filtro }
        if capacita.sfondo == true {
            nuovi.sfondo = sfondo
            if sfondo != ModiSfondo.nessuno { nuovi.intensitaSfondo = intensitaSfondo }
        }
        if capacita.pelle == true { nuovi.pelle = pelle }
        return nuovi
    }

    /// Gli effetti del telefono sono ancora quelli del profilo? Se l'utente ne ha cambiato uno, no («Personalizzato»).
    /// Il formato non conta: il telefono può scendere da solo (caldo, rete debole) senza che l'utente cambi niente.
    func corrisponde(_ effetti: Effetti, capacita: Capacita) -> Bool {
        applica(a: effetti, capacita: capacita).quasiUguale(effetti)
    }
}

private extension Effetti {
    /// Uguali, a meno degli arrotondamenti dei cursori (il telefono rimanda i valori con i suoi decimali).
    func quasiUguale(_ altri: Effetti) -> Bool {
        var a = self
        var b = altri
        let vicini = abs(a.intensitaSfondo - b.intensitaSfondo) < 0.03 && abs(a.pelle - b.pelle) < 0.03
        a.intensitaSfondo = 0
        b.intensitaSfondo = 0
        a.pelle = 0
        b.pelle = 0
        return vicini && a == b
    }
}

/// Un'opzione di «Qualità video»: risoluzione in orizzontale e fotogrammi al secondo.
struct OpzioneQualita: Hashable, Identifiable {
    let larghezza: Int
    let altezza: Int
    let fps: Int

    var id: String { "\(larghezza)x\(altezza)@\(fps)" }
    var testo: String { Lingua.risoluzione(altezza: altezza, fps: fps) }

    /// Dalle capacità del telefono (`formati`: per ogni risoluzione i fps massimi), 30 e 60 fps dove ci arriva;
    /// il 4K solo a 30 (1.14: a 60 è troppo per il Wi-Fi e scalda il telefono, e si chiede in HEVC).
    /// Senza `formati` il telefono non lo dice: le tre scelte comuni, il telefono scende se non ce la fa.
    static func elenco(_ capacita: Capacita?) -> [OpzioneQualita] {
        elenco(formati: capacita?.formati)
    }

    /// Come `elenco(_:)`, da un elenco di formati qualsiasi (anche `capacita.formatiPro`).
    static func elenco(formati: [FormatoSupportato]?) -> [OpzioneQualita] {
        guard let formati, !formati.isEmpty else {
            return [OpzioneQualita(larghezza: 1280, altezza: 720, fps: 30),
                    OpzioneQualita(larghezza: 1920, altezza: 1080, fps: 30),
                    OpzioneQualita(larghezza: 1920, altezza: 1080, fps: 60)]
        }
        var risultato: [OpzioneQualita] = []
        for formato in formati {
            let lungo = max(formato.larghezza, formato.altezza)
            let corto = min(formato.larghezza, formato.altezza)
            for fps in [30, 60] where fps <= formato.fpsMassimo && fps <= Self.fpsMassimi(altezza: corto) {
                let opzione = OpzioneQualita(larghezza: lungo, altezza: corto, fps: fps)
                if !risultato.contains(opzione) { risultato.append(opzione) }
            }
        }
        return risultato.sorted { ($0.altezza, $0.fps) < ($1.altezza, $1.fps) }
    }

    /// Il 4K (lato corto da 2160) resta a 30 fps; sotto, fino a 60.
    static func fpsMassimi(altezza: Int) -> Int {
        altezza >= 2160 ? 30 : 60
    }

    /// Il codec da chiedere: HEVC per il 4K (a parità di qualità circa il 40% di dati in meno), altrimenti quello attuale.
    static func codec(altezza: Int, attuale: Codec?) -> Codec {
        altezza >= 2160 ? .hevc : (attuale ?? .hevc)
    }

    /// L'opzione più vicina a ciò che arriva ora (`statistiche`): stessa risoluzione, 60 sopra i 45 fps misurati.
    static func attuale(_ statistiche: Statistiche, tra opzioni: [OpzioneQualita]) -> OpzioneQualita? {
        guard statistiche.larghezza > 0 else { return nil }
        let corto = min(statistiche.larghezza, statistiche.altezza)
        let fps = statistiche.fps > 45 ? 60 : 30
        if let uguale = opzioni.first(where: { $0.altezza == corto && $0.fps == fps }) { return uguale }
        return opzioni.first(where: { $0.altezza == corto })
    }
}

extension Ricevitore {
    /// «Profilo»: manda al telefono scelto gli effetti del profilo in un solo `comando` e chiede il suo formato.
    func applica(_ profilo: ProfiloPronto) {
        // WebcamLR Pro: i profili pronti solo con un telefono che l'ha sbloccato.
        guard telefonoAttivo, proAttivo, let telefono = attivo, let capacita = telefono.capacita else { return }
        let (comando, chiavi) = profilo.comando(per: capacita)
        // Come per ogni effetto cambiato da qui: per un attimo lo `stato` del telefono non lo sovrascrive.
        for chiave in chiavi {
            telefono.inviiInAttesa[chiave]?.cancel()
            telefono.inviiInAttesa[chiave] = nil
            telefono.modificheEffetti[chiave] = .now
        }
        telefono.effetti = profilo.applica(a: telefono.effetti, capacita: capacita)
        if !chiavi.isEmpty { telefono.sessione?.comanda(comando) }
        profiloPronto = profilo.id
        registra(String(localized: "Profilo «\(profilo.nome)»"), di: telefono)
        // «Volto e scrivania» porta il telefono sul Grandangolo 0,5× posteriore: con la frontale la persona
        // uscirebbe dal video senza capire perché. Lo si dice (A16).
        if comando.doppiaVista == true, telefono.statoTelefono?.obiettivo == "frontale" {
            mostraAvviso(String(localized: "«\(profilo.nome)» usa il Grandangolo 0,5× posteriore: gira il telefono con la fotocamera posteriore verso di te."))
        }
        chiediFormato(larghezza: profilo.larghezza, altezza: profilo.altezza, fps: profilo.fps)
    }

    /// Il profilo pronto che si vede scelto: quello applicato per ultimo, se gli effetti gli corrispondono ancora.
    /// `personalizzato`: c'era un profilo, ma l'utente ha cambiato qualcosa.
    var statoProfilo: (scelto: ProfiloPronto?, personalizzato: Bool) {
        guard let profilo = ProfiloPronto.cerca(profiloPronto) else { return (nil, false) }
        guard let capacita, telefonoAttivo else { return (profilo, false) }
        return profilo.corrisponde(effetti, capacita: capacita) ? (profilo, false) : (nil, true)
    }

    /// «Qualità video» e profili: chiede al telefono scelto un formato (dal computer è una richiesta, Documenti/Protocollo.md).
    /// Stesso orientamento e stesso codec del video che arriva (HEVC per il 4K); fps non oltre ciò che il telefono
    /// dichiara, e il 4K al massimo a 30.
    func chiediFormato(larghezza: Int, altezza: Int, fps: Int) {
        guard telefonoAttivo, let telefono = attivo, let sessione = telefono.sessione else { return }
        let attuale = telefono.formatoTelefono
        let verticale = attuale.map { $0.altezza > $0.larghezza } ?? false
        let lati = verticale ? (larghezza: altezza, altezza: larghezza) : (larghezza: larghezza, altezza: altezza)
        let corto = min(larghezza, altezza)
        let voluti = min(fps, OpzioneQualita.fpsMassimi(altezza: corto))
        let possibili = Self.fpsPossibili(voluti, larghezza: lati.larghezza, altezza: lati.altezza, formati: capacita?.formati)
        // 0: il telefono non elenca questa risoluzione, non ci arriva.
        guard possibili > 0 else { return }
        let codec = OpzioneQualita.codec(altezza: corto, attuale: attuale?.codec)
        if let attuale, attuale.larghezza == lati.larghezza, attuale.altezza == lati.altezza, attuale.fps == possibili,
           attuale.codec == codec { return }
        registra(String(localized: "Chiesti al telefono \(lati.larghezza)×\(lati.altezza) a \(possibili) fps"), di: telefono)
        sessione.chiedi(FormatoVideo(codec: codec, larghezza: lati.larghezza, altezza: lati.altezza, fps: possibili))
    }
}

/// In cima al pannello di destra: la scelta principale, quattro profili pronti in schede grandi.
/// Sotto, i profili salvati dall'utente (funzione 23: obiettivo, zoom, esposizione, bianco e torcia).
struct SezioneProfilo: View {
    let ricevitore: Ricevitore
    /// Senza telefono: schede visibili ma ferme (le grigia chi le contiene).
    var attiva = true
    /// Il titolo «Profilo» (nella pagina «Profili» delle Impostazioni il titolo è già in alto).
    var conTitolo = true
    @State private var chiediNome = false
    @State private var nomeProfilo = ""

    var body: some View {
        let stato: (scelto: ProfiloPronto?, personalizzato: Bool) = attiva ? ricevitore.statoProfilo : (nil, false)
        VStack(alignment: .leading, spacing: 10) {
            if conTitolo || stato.personalizzato {
                HStack {
                    if conTitolo {
                        Text("Profilo")
                            .font(.titolo(22))
                    }
                    Spacer(minLength: 8)
                    if stato.personalizzato {
                        Label("Personalizzato", systemImage: "slider.horizontal.3")
                            .font(.etichetta(14))
                            .foregroundStyle(Tema.accentoChiaro)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Tema.accentoTenue, in: Capsule())
                            .help("Hai cambiato qualcosa dopo aver scelto il profilo: scegline uno per tornare alle sue impostazioni")
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ProfiloPronto.tutti) { profilo in
                    SchedaProfilo(profilo: profilo, scelto: stato.scelto == profilo) {
                        ricevitore.applica(profilo)
                    }
                }
            }
            profiliSalvati
        }
    }

    private var profiliSalvati: some View {
        Menu {
            let nomi = ricevitore.profili.keys.sorted()
            ForEach(nomi, id: \.self) { nome in
                Button(nome) { ricevitore.applicaProfilo(nome) }
            }
            if !nomi.isEmpty { Divider() }
            Button("Salva i comandi attuali…") {
                nomeProfilo = ""
                chiediNome = true
            }
            if !nomi.isEmpty {
                Menu("Elimina") {
                    ForEach(nomi, id: \.self) { nome in
                        Button(nome, role: .destructive) { ricevitore.eliminaProfilo(nome) }
                    }
                }
            }
        } label: {
            Label("Profili salvati", systemImage: "tray.full")
                .font(.corpo(13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("I comandi della fotocamera salvati per nome: obiettivo, zoom, esposizione, bianco e torcia")
        .alert("Nuovo profilo", isPresented: $chiediNome) {
            TextField("Nome, per esempio «Riunione»", text: $nomeProfilo)
            Button("Salva") {
                let nome = nomeProfilo.trimmingCharacters(in: .whitespaces)
                if !nome.isEmpty { ricevitore.salvaProfilo(nome) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Obiettivo, zoom, esposizione, bianco e torcia di adesso. Con lo stesso nome il profilo si sovrascrive.")
        }
    }
}

/// Una scheda di profilo: simbolo, nome e una riga. Scelta nell'accento (selezione), mai in corallo.
private struct SchedaProfilo: View {
    let profilo: ProfiloPronto
    let scelto: Bool
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: profilo.simbolo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(scelto ? Tema.accento : Tema.salviaChiara)
                    .frame(height: 20)
                    .accessibilityHidden(true)
                Text(profilo.nome)
                    .font(.corpoForte(14))
                    .foregroundStyle(scelto ? Tema.accentoChiaro : Tema.testo)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(profilo.descrizione)
                    .font(.corpo(11.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(scelto ? Tema.accentoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(scelto ? Tema.accento : Tema.lineaTenue, lineWidth: scelto ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(profilo.riepilogo)
        .accessibilityLabel(profilo.nome)
        .accessibilityValue(profilo.descrizione)
        .accessibilityAddTraits(scelto ? .isSelected : [])
    }
}
