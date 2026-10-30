import SwiftUI

/// Il logo: griglia di pixel 3×3 in toni di salvia con il centro corallo, su fondo verde scuro sfumato.
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

/// Etichetta di sezione in maiuscolo, come «TELEFONI» o «VIDEO».
public struct EtichettaSezione: View {
    let testo: String

    public init(_ testo: String) {
        self.testo = testo
    }

    public var body: some View {
        Text(testo.uppercased())
            .font(.etichetta(14))
            .tracking(1.1)
            .foregroundStyle(Tema.testoSecondario)
    }
}

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

    /// `testo` sostituisce la dicitura predefinita (per esempio il nome del computer). `dimensione` è quella
    /// dell'etichetta: 16 di serie; sul telefono 56 per leggere «IN ONDA» da 2–3 metri (schermo oscurato e vista
    /// pulita), con la capsula alta almeno 88. Con `.riconnessione` e un testo come «In pausa» la pillola è ambra.
    public init(_ stato: FaseCollegamento, testo: String? = nil, dimensione: CGFloat = 16) {
        self.stato = stato
        self.testo = testo
        self.dimensione = dimensione
    }

    /// Le misure crescono con l'etichetta: a 16 restano quelle di sempre (punto 8, margini 12, alta 30).
    private var scala: CGFloat { max(1, dimensione / 16) }

    public var body: some View {
        HStack(spacing: 8 * scala) {
            punto
            Text((testo ?? diciturePredefinite).uppercased())
                .font(.etichetta(dimensione))
                .tracking(0.9 * scala)
                .lineLimit(1)
                // Grande e con il testo di sistema ingrandito può non starci: si stringe invece di troncare.
                .minimumScaleFactor(scala > 1 ? 0.5 : 1)
        }
        .padding(.horizontal, 12 * scala)
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
        let lato = 8 * scala
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

/// Pulsante tondo con icona, come quelli della barra laterale di «In onda».
public struct PulsanteTondo: View {
    let icona: String
    let etichetta: String
    let attivo: Bool
    let azione: () -> Void

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
                .foregroundStyle(attivo ? Tema.cianoChiaro : .white)
                .frame(width: 48, height: 48)
                .background(attivo ? Tema.cianoTenue : Tema.pannelloChiaro, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etichetta)
    }
}

/// Pulsante secondario: fondo del pannello chiaro, bordo sottile, testo in Barlow. Per le azioni di tutti i giorni
/// (Foto, Registra, Finestra mini…); il corallo non c'entra, nemmeno mentre si registra (lì basta il punto).
public struct StilePulsanteSecondario: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsanteSecondario(configuration: configuration)
    }
}

private struct CorpoPulsanteSecondario: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var abilitato

    var body: some View {
        configuration.label
            .font(.corpoEvidente(13))
            .foregroundStyle(Tema.testo)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(configuration.isPressed ? Tema.linea : Tema.pannelloChiaro,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Tema.linea))
            .opacity(abilitato ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Pulsante che si accende e si spegne con un clic (Specchia, Sfoca sfondo): spento come `StilePulsanteSecondario`,
/// acceso nell'accento salvia (azioni e selezione), mai in corallo.
public struct StilePulsanteInterruttore: ButtonStyle {
    let acceso: Bool

    public init(acceso: Bool) {
        self.acceso = acceso
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsanteInterruttore(configuration: configuration, acceso: acceso)
    }
}

private struct CorpoPulsanteInterruttore: View {
    let configuration: ButtonStyleConfiguration
    let acceso: Bool
    @Environment(\.isEnabled) private var abilitato

    private var fondo: Color {
        if configuration.isPressed { return Tema.linea }
        return acceso ? Tema.accentoTenue : Tema.pannelloChiaro
    }

    var body: some View {
        configuration.label
            .font(.corpoEvidente(13))
            .foregroundStyle(acceso ? Tema.accentoChiaro : Tema.testo)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(fondo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(acceso ? Tema.accento : Tema.linea, lineWidth: acceso ? 1.5 : 1))
            .opacity(abilitato ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Pillola d'azione nell'accento (azioni e selezione), come «Aggiornamento disponibile»: mai corallo.
public struct StilePillolaAccento: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.etichetta(15))
            .tracking(0.4)
            .foregroundStyle(Tema.accentoChiaro)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(configuration.isPressed ? Tema.linea : Tema.accentoTenue, in: Capsule())
            .overlay(Capsule().stroke(Tema.accento.opacity(0.6)))
            .contentShape(Capsule())
    }
}

/// I pulsanti della barra sotto il video del computer (Specchia · Sfoca · Foto · Registra | Schermo, interfaccia
/// finale): icona sopra e nome sotto, tutti larghi uguali. Spento trasparente (pannello chiaro al passaggio),
/// acceso pieno nell'accento salvia con il testo scuro. Mai corallo: per la registrazione basta il punto.
/// `larghezza` più stretta quando la finestra è piccola; con `soloIcona` il nome resta per VoiceOver.
public struct StilePulsanteStudio: ButtonStyle {
    let acceso: Bool
    let larghezza: CGFloat
    let soloIcona: Bool

    public init(acceso: Bool = false, larghezza: CGFloat = 86, soloIcona: Bool = false) {
        self.acceso = acceso
        self.larghezza = larghezza
        self.soloIcona = soloIcona
    }

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsanteStudio(configuration: configuration, acceso: acceso, larghezza: larghezza, soloIcona: soloIcona)
    }
}

private struct CorpoPulsanteStudio: View {
    let configuration: ButtonStyleConfiguration
    let acceso: Bool
    let larghezza: CGFloat
    let soloIcona: Bool
    @Environment(\.isEnabled) private var abilitato
    @State private var sopra = false

    private var fondo: Color {
        if acceso { return configuration.isPressed ? Tema.accentoChiaro : Tema.accento }
        if configuration.isPressed { return Tema.linea }
        return sopra && abilitato ? Tema.pannelloChiaro : .clear
    }

    var body: some View {
        configuration.label
            .labelStyle(EtichettaStudio(soloIcona: soloIcona))
            .font(acceso ? .corpoEvidente(12.5) : .corpo(12.5))
            .foregroundStyle(acceso ? Tema.fondo : Tema.testo)
            .frame(width: larghezza)
            .padding(.vertical, soloIcona ? 8 : 9)
            .background(fondo, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(abilitato ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        VStack(spacing: 4) {
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

/// La barra che contiene i pulsanti dello studio: fondo scuro, bordo sottile, angoli molto tondi.
public struct BarraStudio<Contenuto: View>: View {
    let contenuto: Contenuto

    public init(@ViewBuilder contenuto: () -> Contenuto) {
        self.contenuto = contenuto()
    }

    public var body: some View {
        HStack(spacing: 6) {
            contenuto
        }
        .padding(8)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Tema.linea))
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
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}
