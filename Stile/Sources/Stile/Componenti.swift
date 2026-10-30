import SwiftUI

// I componenti del catalogo (Documenti/Stile.md, «Componenti»), una sola implementazione per iPhone e Mac:
// Comando di regia, Primario, Secondario, Link, Distruttivo, Chip informativo, Pillola di stato, Pulsante tondo,
// Avviso, più la riga dei menu. Misure di testo, spazi, raggi e opacità vengono solo da Token.swift.

/// Il logo: griglia di pixel 3×3 in toni di salvia con il centro corallo, su fondo verde scuro sfumato.
/// È un disegno: raggi e passi sono frazioni del lato, non token (come Strumenti/genera_icone.py).
public struct LogoWebcamLR: View {
    let lato: CGFloat

    public init(lato: CGFloat) {
        self.lato = lato
    }

    /// I nove quadratini riga per riga (logo del 25 ottobre, come Strumenti/genera_icone.py); il centro è il corallo.
    /// Pubblici per chi disegna il logo da sé (l'immagine di attesa della webcam virtuale): i colori restano qui.
    nonisolated public static let celle: [[UInt32]] = [
        [0x8FA199, 0xB2BFB7, 0x627A71],
        [0xACBAB2, 0xE67A67, 0x768D84],
        [0x83988F, 0x96A89F, 0x50685F]
    ]

    public var body: some View {
        // Misure in centesimi del lato: quadratini da 18, passo 23, margine 18.
        let cella = lato * 0.18
        let spazio = lato * 0.05
        ZStack {
            RoundedRectangle(cornerRadius: lato * 0.22)
                .fill(LinearGradient(colors: [Tema.sfumaturaChiara, Tema.sfumaturaScura],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Grid(horizontalSpacing: spazio, verticalSpacing: spazio) {
                ForEach(0..<3, id: \.self) { riga in
                    GridRow {
                        ForEach(0..<3, id: \.self) { colonna in
                            RoundedRectangle(cornerRadius: lato * 0.04)
                                .fill(Color(esadecimale: Self.celle[riga][colonna]))
                                .frame(width: cella, height: cella)
                        }
                    }
                }
            }
        }
        .frame(width: lato, height: lato)
        .accessibilityHidden(true)
    }
}

/// «WebcamLR» con «LR» nell'accento salvia: il corallo resta solo per «in onda» e la registrazione.
/// Fa parte del marchio: la misura la sceglie chi lo mostra (intestazione, presentazione).
public struct MarchioWebcamLR: View {
    let dimensione: CGFloat

    public init(dimensione: CGFloat) {
        self.dimensione = dimensione
    }

    public var body: some View {
        (Text(verbatim: "Webcam") + Text(verbatim: "LR").foregroundColor(Tema.accento))
            .font(.titolo(dimensione))
            .accessibilityLabel(Text(verbatim: "WebcamLR"))
    }
}

/// Etichetta di sezione in maiuscolo, come «TELEFONI» o «VIDEO»: lo stile di testo `sezione`.
public struct EtichettaSezione: View {
    let testo: String

    public init(_ testo: String) {
        self.testo = testo
    }

    public var body: some View {
        Text(testo)
            .stileTesto(.sezione)
            .foregroundStyle(Tema.testoSecondario)
    }
}

// MARK: - Pillola di stato

/// I quattro stati, uguali in tutte le app. Non «StatoCollegamento»: quello è il messaggio del protocollo
/// (strada in uso e preferenza), e con lo stesso nome nei due moduli il tipo sarebbe ambiguo.
public enum FaseCollegamento: Equatable, Sendable {
    /// Un'app sta usando il video: l'unico caso in cui compare il corallo (con la registrazione).
    case inOnda(app: String?)
    case collegato
    case riconnessione
    case nessunTelefono
}

public struct PillolaStato: View {
    let stato: FaseCollegamento
    let testo: String?
    let dimensione: CGFloat

    /// La misura di serie dell'etichetta: la pillola è un segno da leggere al volo, un poco più grande di `sezione`.
    /// Fuori dalla scala dei testi di proposito (Documenti/Stile.md); da lontano si usa `StileTesto.statoGrande`.
    nonisolated public static let misuraNormale: CGFloat = 16

    /// `testo` sostituisce la dicitura predefinita (per esempio il nome del computer). `dimensione` è quella
    /// dell'etichetta: `misuraNormale` di serie; sul telefono `StileTesto.statoGrande.misura` per leggere «IN ONDA»
    /// da 2–3 metri (schermo oscurato e vista pulita), con la capsula alta almeno 88. Con `.riconnessione` e un testo
    /// come «In pausa» la pillola è ambra.
    public init(_ stato: FaseCollegamento, testo: String? = nil, dimensione: CGFloat = PillolaStato.misuraNormale) {
        self.stato = stato
        self.testo = testo
        self.dimensione = dimensione
    }

    /// Le misure crescono con l'etichetta: alla misura normale restano quelle di sempre (punto 8, margini 12, alta 30).
    private var scala: CGFloat { max(1, dimensione / Self.misuraNormale) }

    public var body: some View {
        HStack(spacing: Spazi.stretto * scala) {
            punto
            Text((testo ?? diciturePredefinite).uppercased())
                .font(.etichetta(dimensione))
                .tracking(0.9 * scala)
                .lineLimit(1)
                // Grande e con il testo di sistema ingrandito può non starci: si stringe invece di troncare.
                .minimumScaleFactor(scala > 1 ? 0.5 : 1)
        }
        .padding(.horizontal, Spazi.piccolo * scala)
        // Almeno 30: su iPhone il carattere cresce con la dimensione del testo e la capsula deve contenerlo.
        // Grande almeno 88 (1,6 volte l'etichetta).
        .frame(minHeight: scala > 1 ? max(88, dimensione * 1.6) : 30)
        .foregroundStyle(colorTesto)
        .background(sfondo, in: Capsule())
        .overlay {
            if stato == .nessunTelefono {
                Capsule().stroke(Tema.bordo)
            }
        }
    }

    @ViewBuilder private var punto: some View {
        let lato = Spazi.stretto * scala
        switch stato {
        case .inOnda: Circle().fill(.white).frame(width: lato, height: lato)
        case .collegato: Circle().fill(Tema.verde).frame(width: lato, height: lato)
        case .riconnessione: Circle().fill(Tema.ambra).frame(width: lato, height: lato)
        case .nessunTelefono: Circle().stroke(Tema.testoTenue, lineWidth: 1.5).frame(width: lato, height: lato)
        }
    }

    private var diciturePredefinite: String {
        switch stato {
        case .inOnda(let app):
            app.map { String(localized: "In onda · \($0)", bundle: .stile) } ?? String(localized: "In onda", bundle: .stile)
        case .collegato: String(localized: "Collegato", bundle: .stile)
        case .riconnessione: String(localized: "Riconnessione", bundle: .stile)
        case .nessunTelefono: String(localized: "Nessun telefono", bundle: .stile)
        }
    }

    private var colorTesto: Color {
        switch stato {
        case .inOnda: .white
        case .collegato: Tema.testo
        case .riconnessione: Tema.ambraTesto
        case .nessunTelefono: Tema.testoTenue
        }
    }

    private var sfondo: Color {
        switch stato {
        case .inOnda: Tema.tallyPieno
        case .collegato: Tema.pannelloChiaro
        case .riconnessione: Tema.ambraTenue
        case .nessunTelefono: .clear
        }
    }
}

// MARK: - Pulsante tondo del telefono

/// Pulsante tondo con icona, come quelli della colonna di «In onda». Acceso nell'accento, spento sul pannello chiaro.
public struct PulsanteTondo: View {
    let icona: String
    let etichetta: String
    let attivo: Bool
    let azione: () -> Void

    /// Il diametro: 48 punti, sopra i 44 dell'area di tocco minima.
    nonisolated public static let diametro: CGFloat = 48

    public init(_ etichetta: String, icona: String, attivo: Bool = false, azione: @escaping () -> Void) {
        self.etichetta = etichetta
        self.icona = icona
        self.attivo = attivo
        self.azione = azione
    }

    public var body: some View {
        Button(action: azione) {
            Image(systemName: icona)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(attivo ? Tema.accentoChiaro : .white)
                .frame(width: Self.diametro, height: Self.diametro)
                .background(attivo ? Tema.accentoTenue : Tema.pannelloChiaro, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etichetta)
    }
}

// MARK: - Spento

private struct ChiaveSpentoDaFuori: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Vero dentro una vista già resa tenue da `spento(_:)`: i componenti non abbassano l'opacità una seconda volta.
    public var spentoDaFuori: Bool {
        get { self[ChiaveSpentoDaFuori.self] }
        set { self[ChiaveSpentoDaFuori.self] = newValue }
    }
}

extension View {
    /// Spento con l'opacità `Opacita.spento`, una volta sola: i componenti dentro non la applicano di nuovo
    /// (prima un comando di regia senza telefono finiva a 0,45 × 0,45, 1,8:1).
    public func spento(_ spento: Bool = true) -> some View {
        disabled(spento)
            .opacity(spento ? Opacita.spento : 1)
            .environment(\.spentoDaFuori, spento)
    }
}

// MARK: - Primario

/// Il pulsante primario contestuale: uno per contesto, pieno nell'accento con il testo scuro (`Tema.fondo`).
/// Mai corallo: il corallo è solo «in onda» e registrazione.
/// - `normale`: alto quanto un controllo (sul telefono almeno 44 punti, l'area di tocco minima), a capsula sul telefono.
/// - `grande`: largo quanto il contenitore, per la scelta principale di una schermata del telefono («Inquadra il QR code»).
public struct StilePrimario: ButtonStyle {
    public enum Misura: Sendable {
        case normale
        case grande
    }

    let misura: Misura

    public init(_ misura: Misura = .normale) {
        self.misura = misura
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsantePrimario(configuration: configuration, misura: misura)
    }
}

private struct CorpoPulsantePrimario: View {
    let configuration: ButtonStyleConfiguration
    let misura: StilePrimario.Misura
    @Environment(\.isEnabled) private var abilitato
    @Environment(\.spentoDaFuori) private var spentoDaFuori

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: raggio, style: .continuous)
    }

    private var raggio: CGFloat {
        #if os(macOS)
        return Raggi.controllo
        #else
        return misura == .grande ? Raggi.pannello : Raggi.capsula
        #endif
    }

    private var altezzaMinima: CGFloat {
        #if os(macOS)
        return 30
        #else
        return misura == .grande ? 54 : 44
        #endif
    }

    var body: some View {
        configuration.label
            .font(.stile(.comando))
            .foregroundStyle(Tema.fondo)
            // Il grande va a capo con il testo molto grande (Dynamic Type) invece di troncare.
            .lineLimit(misura == .grande ? 2 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, misura == .grande ? Spazi.medio : Spazi.piccolo)
            .frame(maxWidth: misura == .grande ? CGFloat.infinity : nil, minHeight: altezzaMinima)
            .background(configuration.isPressed ? Tema.accentoChiaro : Tema.accento, in: forma)
            .opacity(abilitato || spentoDaFuori ? 1 : Opacita.spento)
            .contentShape(forma)
    }
}

// MARK: - Secondario e distruttivo

/// Pulsante secondario: fondo del pannello chiaro e contorno `contornoControllo`. Per le azioni di tutti i giorni
/// (Foto, Registra, Finestra mini…); il corallo non c'entra, nemmeno mentre si registra (lì basta il punto).
/// `acceso`: un interruttore a un clic acceso (Finestra mini, il pannello «Impostazioni» aperto), nell'accento salvia.
public struct StileSecondario: ButtonStyle {
    let acceso: Bool

    public init(acceso: Bool = false) {
        self.acceso = acceso
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsanteSecondario(configuration: configuration, acceso: acceso)
    }
}

/// L'azione distruttiva (Scollega, Rimuovi): testo e contorno, mai pieno e mai il più evidente. Oggi ha l'aspetto
/// del secondario; la beta 4 lo distingue senza toccare chi lo usa.
public struct StileDistruttivo: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsanteSecondario(configuration: configuration, acceso: false)
    }
}

private struct CorpoPulsanteSecondario: View {
    let configuration: ButtonStyleConfiguration
    let acceso: Bool

    /// Sul Mac una riga; sul telefono il testo grande (Dynamic Type) può andare a capo invece di troncare.
    private var limiteRighe: Int {
        #if os(macOS)
        return 1
        #else
        return 2
        #endif
    }
    @Environment(\.isEnabled) private var abilitato
    @Environment(\.spentoDaFuori) private var spentoDaFuori

    var body: some View {
        configuration.label
            .font(.stile(.corpo, .corpoEvidente))
            .foregroundStyle(acceso ? Tema.accentoChiaro : Tema.testo)
            .lineLimit(limiteRighe)
            .superficieSecondaria(acceso: acceso, premuto: configuration.isPressed)
            .opacity(abilitato || spentoDaFuori ? 1 : Opacita.spento)
    }
}

/// Il fondo e il contorno del secondario, per ciò che non è un `Button` (i menu dell'intestazione del Mac).
private struct SuperficieSecondaria: ViewModifier {
    let acceso: Bool
    let premuto: Bool

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous)
    }

    private var fondo: Color {
        if premuto { return Tema.linea }
        return acceso ? Tema.accentoTenue : Tema.pannelloChiaro
    }

    /// Alto quanto un controllo del Mac; sul telefono almeno 44 punti, l'area di tocco minima.
    private var altezzaMinima: CGFloat {
        #if os(macOS)
        return 30
        #else
        return 44
        #endif
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spazi.piccolo)
            .frame(minHeight: altezzaMinima)
            .background(fondo, in: forma)
            .overlay(forma.stroke(acceso ? Tema.accento : Tema.contornoControllo, lineWidth: acceso ? 1.5 : 1))
            .contentShape(forma)
    }
}

extension View {
    /// Fondo, contorno e misure del pulsante secondario su una vista qualsiasi (un `Menu`, un'etichetta).
    public func superficieSecondaria(acceso: Bool = false, premuto: Bool = false) -> some View {
        modifier(SuperficieSecondaria(acceso: acceso, premuto: premuto))
    }
}

// MARK: - Link

/// Il link: testo nell'accento, sottolineato al passaggio del puntatore. Per le strade verso un'altra pagina o un
/// aiuto («Il telefono non trova il Mac?», «Mostra nel Finder»). Prende il carattere da chi lo usa.
public struct StileLink: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CorpoLink(configuration: configuration)
    }
}

private struct CorpoLink: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var abilitato
    @Environment(\.spentoDaFuori) private var spentoDaFuori
    @State private var sopra = false

    var body: some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Tema.accentoChiaro : Tema.accento)
            .underline(sopra && abilitato)
            .opacity(abilitato || spentoDaFuori ? 1 : Opacita.spento)
            .contentShape(Rectangle())
            .onHover { sopra = $0 }
    }
}

// MARK: - Comando di regia

/// I comandi della barra sotto il video del computer (Specchia · Sfondo · Foto · Registra | Schermo, interfaccia
/// finale): icona sopra e nome sotto, tutti larghi uguali. Spento trasparente (pannello chiaro al passaggio),
/// acceso pieno nell'accento salvia con il testo scuro. Mai corallo: per la registrazione basta il punto.
/// `larghezza` più stretta quando la finestra è piccola; con `soloIcona` il nome resta per VoiceOver.
public struct ComandoRegia: ButtonStyle {
    let acceso: Bool
    let larghezza: CGFloat
    let soloIcona: Bool

    public init(acceso: Bool = false, larghezza: CGFloat = 86, soloIcona: Bool = false) {
        self.acceso = acceso
        self.larghezza = larghezza
        self.soloIcona = soloIcona
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoComandoRegia(configuration: configuration, acceso: acceso, larghezza: larghezza, soloIcona: soloIcona)
    }
}

private struct CorpoComandoRegia: View {
    let configuration: ButtonStyleConfiguration
    let acceso: Bool
    let larghezza: CGFloat
    let soloIcona: Bool
    @Environment(\.isEnabled) private var abilitato
    @Environment(\.spentoDaFuori) private var spentoDaFuori
    @State private var sopra = false

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous)
    }

    private var fondo: Color {
        if acceso { return configuration.isPressed ? Tema.accentoChiaro : Tema.accento }
        if configuration.isPressed { return Tema.linea }
        return sopra && abilitato ? Tema.pannelloChiaro : .clear
    }

    var body: some View {
        configuration.label
            .labelStyle(EtichettaStudio(soloIcona: soloIcona))
            .font(acceso ? .stile(.corpo, .corpoEvidente) : .stile(.corpo))
            .foregroundStyle(acceso ? Tema.fondo : Tema.testo)
            .frame(width: larghezza)
            .padding(.vertical, Spazi.stretto)
            .background(fondo, in: forma)
            .opacity(abilitato || spentoDaFuori ? 1 : Opacita.spento)
            .contentShape(forma)
            .onHover { sopra = $0 }
    }
}

/// Icona sopra, nome sotto (barra sotto il video). `soloIcona`: il nome non si vede ma resta per VoiceOver.
public struct EtichettaStudio: LabelStyle {
    let soloIcona: Bool

    public init(soloIcona: Bool = false) {
        self.soloIcona = soloIcona
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: Spazi.minimo) {
            configuration.icon
                .font(.system(size: 18, weight: .regular))
                .frame(height: 22)
            if !soloIcona {
                configuration.title
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// La barra che contiene i comandi di regia: fondo scuro, contorno sottile, angoli tondi.
public struct BarraStudio<Contenuto: View>: View {
    let contenuto: Contenuto

    public init(@ViewBuilder contenuto: () -> Contenuto) {
        self.contenuto = contenuto()
    }

    public var body: some View {
        HStack(spacing: Spazi.stretto) {
            contenuto
        }
        .padding(Spazi.stretto)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous).stroke(Tema.linea))
    }
}

/// Il separatore verticale dentro la `BarraStudio` (prima di «Schermo»).
public struct SeparatoreStudio: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Tema.linea)
            // Altezza fissa: un rettangolo libero allungherebbe tutta la barra.
            .frame(width: 1, height: 36)
            .padding(.horizontal, Spazi.minimo)
            .accessibilityHidden(true)
    }
}

// MARK: - Chip informativo

/// Dove sta un chip informativo: sopra il video (velo scuro) o su un pannello.
public enum SuperficieChip: Sendable {
    case video
    case pannello
}

/// Il chip informativo (qualità, collegamento, «CAM 1»): un'informazione, non un'azione. Contornato, mai pieno.
/// Sopra il video sta su un velo medio con il contorno `contornoSuVideo`; su un pannello ha solo il contorno.
private struct StileChipInformativo: ViewModifier {
    let superficie: SuperficieChip

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: Raggi.piccolo, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, Spazi.stretto)
            .frame(minHeight: 28)
            .background(superficie == .video ? Veli.coloreMedio : .clear, in: forma)
            .overlay(forma.stroke(superficie == .video ? Tema.contornoSuVideo : Tema.contornoControllo))
            .contentShape(forma)
    }
}

extension View {
    /// Il chip informativo attorno a un contenuto qualsiasi: testo, icona e testo, `ChipQualita`.
    public func chipInformativo(_ superficie: SuperficieChip = .video) -> some View {
        modifier(StileChipInformativo(superficie: superficie))
    }
}

// MARK: - Riga dei menu

/// La riga dei menu disegnati da noi (qualità, collegamento, sfondo, elenco delle Impostazioni): larga quanto il
/// menu, chiara al passaggio del puntatore. `evidenziata`: fondo chiaro fisso (la strada in uso). Spenta: niente
/// fondo al passaggio.
public struct StileRigaMenu: ButtonStyle {
    let evidenziata: Bool

    public init(evidenziata: Bool = false) {
        self.evidenziata = evidenziata
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoRigaMenu(configuration: configuration, evidenziata: evidenziata)
    }
}

private struct CorpoRigaMenu: View {
    let configuration: ButtonStyleConfiguration
    let evidenziata: Bool
    @Environment(\.isEnabled) private var abilitato
    @State private var sopra = false

    private var fondo: Color {
        if configuration.isPressed && abilitato { return Tema.linea }
        return evidenziata || (sopra && abilitato) ? Tema.pannelloChiaro : .clear
    }

    var body: some View {
        configuration.label
            .padding(.horizontal, Spazi.stretto)
            .padding(.vertical, Spazi.stretto)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fondo, in: RoundedRectangle(cornerRadius: Raggi.piccolo, style: .continuous))
            .contentShape(Rectangle())
            .onHover { sopra = $0 }
    }
}

// MARK: - Avviso

/// Il tono di un avviso: `attenzione` (ambra: caldo, batteria, rete, un telefono perso) o `informazione`
/// (accento: un suggerimento, una versione da aggiornare). Il corallo mai.
public enum TonoAvviso: Sendable {
    case attenzione
    case informazione
}

/// L'avviso, uguale su iPhone e Mac: icona nel colore del tono, testo (con un titolo sopra, se c'è), le azioni sotto
/// e, con `chiudi`, la X. Sta sopra il video o in una colonna, su un velo forte del pannello. Resta finché lo
/// tiene chi lo mostra (finché la causa c'è).
/// `alTocco`: icona e testo diventano un pulsante (sul telefono un tocco chiude l'avviso); `suggerimentoTocco` è
/// quello che dice VoiceOver. `larghezzaMassima`: il fondo si allarga fin lì (`.infinity` per tutta la riga).
public struct Avviso<Azioni: View>: View {
    let titolo: String?
    let testo: String
    let icona: String
    let tono: TonoAvviso
    let larghezzaMassima: CGFloat?
    let alTocco: (() -> Void)?
    let suggerimentoTocco: Text?
    let chiudi: (() -> Void)?
    let azioni: Azioni

    public init(_ testo: String, titolo: String? = nil, icona: String, tono: TonoAvviso = .attenzione,
                larghezzaMassima: CGFloat? = nil, alTocco: (() -> Void)? = nil, suggerimentoTocco: Text? = nil,
                chiudi: (() -> Void)? = nil, @ViewBuilder azioni: () -> Azioni) {
        self.titolo = titolo
        self.testo = testo
        self.icona = icona
        self.tono = tono
        self.larghezzaMassima = larghezzaMassima
        self.alTocco = alTocco
        self.suggerimentoTocco = suggerimentoTocco
        self.chiudi = chiudi
        self.azioni = azioni()
    }

    private var coloreIcona: Color {
        switch tono {
        case .attenzione: Tema.ambra
        case .informazione: Tema.accento
        }
    }

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
            VStack(alignment: .leading, spacing: Spazi.stretto) {
                if let alTocco {
                    Button(action: alTocco) {
                        riga
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(suggerimentoTocco ?? Text(verbatim: ""))
                } else {
                    riga
                }
                azioni
            }
            if let chiudi {
                Button(action: chiudi) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tema.testoTenue)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(String(localized: "Chiudi", bundle: .stile)))
                .accessibilityLabel(Text(String(localized: "Chiudi", bundle: .stile)))
            }
        }
        .padding(.horizontal, Spazi.piccolo)
        .padding(.vertical, Spazi.stretto)
        .frame(maxWidth: larghezzaMassima, alignment: .leading)
        .background(Tema.pannello.opacity(Veli.forte), in: forma)
        // Con pulsanti dentro VoiceOver deve poterli raggiungere: niente elemento unico.
        .accessibilityElement(children: chiudi == nil && alTocco == nil && Azioni.self == EmptyView.self ? .combine : .contain)
    }

    /// Icona, titolo e testo.
    private var riga: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
            Image(systemName: icona)
                .foregroundStyle(coloreIcona)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if let titolo {
                    Text(titolo)
                        .font(.stile(.corpo, .corpoForte))
                        .foregroundStyle(Tema.testo)
                    Text(testo)
                        .font(.stile(.nota))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(testo)
                        .font(.stile(.nota, .corpoEvidente))
                        .foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension Avviso where Azioni == EmptyView {
    public init(_ testo: String, titolo: String? = nil, icona: String, tono: TonoAvviso = .attenzione,
                larghezzaMassima: CGFloat? = nil, alTocco: (() -> Void)? = nil, suggerimentoTocco: Text? = nil,
                chiudi: (() -> Void)? = nil) {
        self.init(testo, titolo: titolo, icona: icona, tono: tono, larghezzaMassima: larghezzaMassima,
                  alTocco: alTocco, suggerimentoTocco: suggerimentoTocco, chiudi: chiudi) { EmptyView() }
    }
}

// MARK: - Nomi di prima (solo durante il passaggio, si tolgono a fine parte B)

@available(*, deprecated, renamed: "StileSecondario")
public typealias StilePulsanteSecondario = StileSecondario
@available(*, deprecated, renamed: "StileSecondario")
public typealias StilePulsanteInterruttore = StileSecondario
@available(*, deprecated, renamed: "ComandoRegia")
public typealias StilePulsanteStudio = ComandoRegia
@available(*, deprecated, renamed: "StilePrimario")
public typealias StilePillolaAccento = StilePrimario
@available(*, deprecated, renamed: "StilePrimario")
public typealias StilePulsantePro = StilePrimario
