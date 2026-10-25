import Stile
import SwiftUI

// I disegni della presentazione, fatti solo di forme SwiftUI nei colori di Tema: niente foto, niente video,
// niente loghi di altri. Ogni disegno prende una larghezza e ricava il resto in proporzione.

/// Le proporzioni dei disegni (altezza diviso larghezza), per impaginare le scene.
enum Proporzioni {
    /// Portatile: schermo più base.
    static let portatile: CGFloat = 0.655
    /// Telefono in verticale.
    static let telefono: CGFloat = 2.05
    /// Il supporto sotto il telefono.
    static let supporto: CGFloat = 0.65
    /// Monitor da scrivania: schermo, collo e piede.
    static let monitor: CGFloat = 0.78
}

/// Il retro dell'iPhone con il modulo delle fotocamere: è lui che riprende.
struct DisegnoIPhone: View {
    let larghezza: CGFloat

    var body: some View {
        let raggio = larghezza * 0.2
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: raggio, style: .continuous)
                .fill(LinearGradient(colors: [Tema.pannelloChiaro, Tema.pannello],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: raggio, style: .continuous).stroke(Tema.bordo, lineWidth: 1.5))
            RoundedRectangle(cornerRadius: larghezza * 0.13, style: .continuous)
                .fill(Tema.pannelloScuro)
                .overlay(RoundedRectangle(cornerRadius: larghezza * 0.13, style: .continuous)
                    .stroke(Tema.linea, lineWidth: 1))
                .frame(width: larghezza * 0.5, height: larghezza * 0.5)
                .overlay { obiettivi }
                .padding(larghezza * 0.08)
        }
        .frame(width: larghezza, height: larghezza * Proporzioni.telefono)
    }

    private var obiettivi: some View {
        let lato = larghezza * 0.17
        let spazio = larghezza * 0.04
        return VStack(spacing: spazio) {
            HStack(spacing: spazio) {
                obiettivo(lato)
                obiettivo(lato)
            }
            HStack(spacing: spazio) {
                obiettivo(lato)
                Circle()
                    .fill(Tema.salviaTenue.opacity(0.7))
                    .frame(width: lato * 0.45, height: lato * 0.45)
                    .frame(width: lato, height: lato)
            }
        }
    }

    private func obiettivo(_ lato: CGFloat) -> some View {
        Circle()
            .fill(Tema.sfumaturaScura)
            .overlay(Circle().stroke(Tema.salviaScura, lineWidth: 1.5))
            .overlay(Circle()
                .fill(Tema.accento.opacity(0.45))
                .frame(width: lato * 0.32, height: lato * 0.32)
                .offset(x: -lato * 0.12, y: -lato * 0.12))
            .frame(width: lato, height: lato)
    }
}

/// Il piccolo supporto da scrivania: morsetto, asta e piede.
struct SupportoTelefono: View {
    let larghezza: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: larghezza * 0.04)
                .fill(Tema.salviaScura)
                .frame(width: larghezza * 0.5, height: larghezza * 0.1)
            Rectangle()
                .fill(Tema.salviaScura)
                .frame(width: larghezza * 0.1, height: larghezza * 0.45)
            Capsule()
                .fill(Tema.salviaScura)
                .frame(width: larghezza * 0.95, height: larghezza * 0.1)
        }
    }
}

/// Il telefono sul supporto, alto `larghezza × (Proporzioni.telefono + Proporzioni.supporto)`.
struct TelefonoSuSupporto: View {
    let larghezza: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            DisegnoIPhone(larghezza: larghezza)
            SupportoTelefono(larghezza: larghezza)
        }
    }
}

/// Il fronte del telefono, con un contenuto sullo schermo.
struct TelefonoFronte<Schermo: View>: View {
    let larghezza: CGFloat
    @ViewBuilder let schermo: () -> Schermo

    var body: some View {
        let raggio = larghezza * 0.18
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: raggio, style: .continuous)
                .fill(Tema.pannelloScuro)
                .overlay(RoundedRectangle(cornerRadius: raggio, style: .continuous).stroke(Tema.bordo, lineWidth: 1.5))
            schermo()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: raggio * 0.8, style: .continuous))
                .padding(larghezza * 0.05)
            // L'isola in alto
            Capsule()
                .fill(Tema.sfumaturaScura)
                .frame(width: larghezza * 0.3, height: larghezza * 0.08)
                .padding(.top, larghezza * 0.09)
        }
        .frame(width: larghezza, height: larghezza * Proporzioni.telefono)
    }
}

/// Un portatile generico (nessun marchio), con un contenuto sullo schermo.
struct DisegnoPortatile<Schermo: View>: View {
    let larghezza: CGFloat
    @ViewBuilder let schermo: () -> Schermo

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: larghezza * 0.035, style: .continuous)
                    .fill(Tema.pannelloChiaro)
                    .overlay(RoundedRectangle(cornerRadius: larghezza * 0.035, style: .continuous)
                        .stroke(Tema.bordo, lineWidth: 1.5))
                schermo()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.sfumaturaScura)
                    .clipShape(RoundedRectangle(cornerRadius: larghezza * 0.015, style: .continuous))
                    .padding(larghezza * 0.028)
            }
            .frame(width: larghezza * 0.86, height: larghezza * 0.62)
            UnevenRoundedRectangle(bottomLeadingRadius: larghezza * 0.03, bottomTrailingRadius: larghezza * 0.03)
                .fill(Tema.salviaScura)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Tema.pannelloScuro)
                        .frame(width: larghezza * 0.14, height: larghezza * 0.012)
                }
                .frame(width: larghezza, height: larghezza * 0.035)
        }
        .frame(width: larghezza, height: larghezza * Proporzioni.portatile)
    }
}

/// Un monitor da scrivania generico, per il PC (nessun marchio).
struct DisegnoMonitor<Schermo: View>: View {
    let larghezza: CGFloat
    @ViewBuilder let schermo: () -> Schermo

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: larghezza * 0.03, style: .continuous)
                    .fill(Tema.pannelloChiaro)
                    .overlay(RoundedRectangle(cornerRadius: larghezza * 0.03, style: .continuous)
                        .stroke(Tema.bordo, lineWidth: 1.5))
                schermo()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.sfumaturaScura)
                    .clipShape(RoundedRectangle(cornerRadius: larghezza * 0.012, style: .continuous))
                    .padding(larghezza * 0.03)
            }
            .frame(width: larghezza, height: larghezza * 0.6)
            Rectangle()
                .fill(Tema.salviaScura)
                .frame(width: larghezza * 0.1, height: larghezza * 0.14)
            Capsule()
                .fill(Tema.salviaScura)
                .frame(width: larghezza * 0.42, height: larghezza * 0.04)
        }
        .frame(width: larghezza, height: larghezza * Proporzioni.monitor)
    }
}

/// Una persona stilizzata (testa, capelli, spalle), alta `altezza`.
struct PersonaDisegnata: View {
    let altezza: CGFloat
    var pelle: Color = Tema.salviaChiara
    var maglia: Color = Tema.salviaScura
    var capelli: Color = Tema.sfumaturaScura

    var body: some View {
        let testa = altezza * 0.42
        VStack(spacing: -altezza * 0.05) {
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(pelle)
                    .frame(width: testa * 0.82, height: testa)
                UnevenRoundedRectangle(topLeadingRadius: testa * 0.45, bottomLeadingRadius: testa * 0.1,
                                       bottomTrailingRadius: testa * 0.1, topTrailingRadius: testa * 0.45)
                    .fill(capelli)
                    .frame(width: testa * 0.88, height: testa * 0.36)
                    .offset(y: -testa * 0.05)
            }
            .zIndex(1)
            UnevenRoundedRectangle(topLeadingRadius: altezza * 0.24, topTrailingRadius: altezza * 0.24)
                .fill(maglia)
                .frame(width: altezza * 0.9, height: altezza * 0.52)
        }
        .frame(height: altezza, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// L'inquadratura di una persona nella sua stanza (parete, finestra, mensola, pianta), con le regolazioni
/// che i profili cambiano: luce sul volto, sfondo sfocato, persona più piccola con la scrivania davanti.
struct InquadraturaStanza: View {
    /// Da 0 a 1.
    var luceVolto: Double = 0
    var sfocaSfondo: CGFloat = 0
    var scalaPersona: CGFloat = 1
    /// Da 0 a 1: la scrivania in primo piano.
    var scrivania: Double = 0

    private static let coloriLibri: [Color] = [Tema.salvia, Tema.salviaTenue, Tema.salviaScura, Tema.testoSecondario]
    private static let altezzeLibri: [CGFloat] = [0.1, 0.13, 0.09, 0.12]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let altezzaPersona = h * 0.8 * scalaPersona
            // Con la scrivania la persona sta più in alto: il piano copre la parte bassa.
            let base = h - CGFloat(scrivania) * h * 0.2
            ZStack(alignment: .topLeading) {
                stanza(w: w, h: h)
                    .blur(radius: sfocaSfondo)
                PersonaDisegnata(altezza: altezzaPersona)
                    .brightness(0.1 * luceVolto)
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(RadialGradient(colors: [Tema.testo.opacity(0.55 * luceVolto), Tema.testo.opacity(0)],
                                                 center: .center, startRadius: 0, endRadius: altezzaPersona * 0.32))
                            .frame(width: altezzaPersona * 0.64, height: altezzaPersona * 0.64)
                            .offset(y: -altezzaPersona * 0.1)
                            .blendMode(.screen)
                    }
                    .position(x: w / 2, y: base - altezzaPersona / 2)
                tavolo(w: w, h: h)
                    .opacity(scrivania)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private func stanza(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Tema.pannelloChiaro, Tema.pannello], startPoint: .top, endPoint: .bottom)
            // La finestra
            RoundedRectangle(cornerRadius: w * 0.02)
                .fill(Tema.salviaTenue.opacity(0.3))
                .overlay(Rectangle().fill(Tema.pannelloChiaro).frame(width: max(1, w * 0.012)))
                .frame(width: w * 0.24, height: h * 0.34)
                .offset(x: w * 0.7, y: h * 0.1)
            // La mensola con i libri
            Rectangle()
                .fill(Tema.salviaScura)
                .frame(width: w * 0.26, height: max(1.5, h * 0.015))
                .offset(x: w * 0.05, y: h * 0.3)
            HStack(alignment: .bottom, spacing: w * 0.008) {
                ForEach(0..<4, id: \.self) { indice in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Self.coloriLibri[indice])
                        .frame(width: w * 0.03, height: h * Self.altezzeLibri[indice])
                }
            }
            .frame(height: h * 0.13, alignment: .bottom)
            .offset(x: w * 0.07, y: h * 0.17)
            // La pianta
            ZStack(alignment: .bottom) {
                ForEach(0..<5, id: \.self) { indice in
                    Capsule()
                        .fill(indice % 2 == 0 ? Tema.salvia : Tema.salviaScura)
                        .frame(width: w * 0.04, height: h * 0.2)
                        .rotationEffect(.degrees(Double(indice - 2) * 22), anchor: .bottom)
                        .offset(y: -h * 0.06)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(Tema.bordo)
                    .frame(width: w * 0.09, height: h * 0.08)
            }
            .frame(width: w * 0.2, height: h * 0.3, alignment: .bottom)
            .offset(x: w * 0.02, y: h * 0.7)
        }
        .frame(width: w, height: h)
    }

    private func tavolo(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(colors: [Tema.salviaScura, Tema.pannelloScuro], startPoint: .top, endPoint: .bottom))
            // Un quaderno e una matita
            RoundedRectangle(cornerRadius: 2)
                .fill(Tema.testoChiaro)
                .frame(width: w * 0.3, height: h * 0.11)
                .rotationEffect(.degrees(-6))
                .offset(x: w * 0.35, y: h * 0.05)
            Capsule()
                .fill(Tema.salviaChiara)
                .frame(width: w * 0.16, height: max(1.5, h * 0.015))
                .rotationEffect(.degrees(20))
                .offset(x: w * 0.72, y: h * 0.09)
        }
        .frame(width: w, height: h * 0.24)
        .offset(y: h * 0.76)
    }
}

/// Onde di segnale che partono dall'angolo in basso a sinistra verso `direzione`.
/// Con «Riduci movimento» restano ferme.
struct OndeSegnale: View {
    var direzione: Angle = .degrees(-45)
    var colore: Color = Tema.accento
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: riduciMovimento)) { contesto in
            let tempo = contesto.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let centro = CGPoint(x: 0, y: size.height)
                let massimo = min(size.width, size.height) * 1.15
                for indice in 0..<3 {
                    let fase: Double = riduciMovimento
                        ? (Double(indice) + 1) / 3.5
                        : (tempo * 0.7 + Double(indice) / 3).truncatingRemainder(dividingBy: 1)
                    let raggio = massimo * CGFloat(0.2 + 0.8 * fase)
                    var arco = Path()
                    for passo in 0...12 {
                        let angolo = direzione.radians + (Double(passo) / 12 - 0.5)
                        let punto = CGPoint(x: centro.x + raggio * CGFloat(cos(angolo)),
                                            y: centro.y + raggio * CGFloat(sin(angolo)))
                        if passo == 0 { arco.move(to: punto) } else { arco.addLine(to: punto) }
                    }
                    let opacita: Double = riduciMovimento ? 0.8 : 1 - fase
                    ctx.stroke(arco, with: .color(colore.opacity(opacita)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// La grana di una webcam scadente: puntini chiari e scuri che cambiano 12 volte al secondo
/// (fermi con «Riduci movimento»).
struct GranaVideo: View {
    var intensita: Double = 0.35
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        TimelineView(.periodic(from: .now, by: riduciMovimento ? 3600 : 1.0 / 12)) { contesto in
            let seme = UInt64(max(0, contesto.date.timeIntervalSinceReferenceDate * 12))
            Canvas { ctx, size in
                var casuale = GeneratoreCasuale(stato: riduciMovimento ? 7 : seme)
                var chiari = Path()
                var scuri = Path()
                let quanti = Int(size.width * size.height / 14)
                for indice in 0..<max(0, quanti) {
                    let punto = CGRect(x: casuale.frazione() * size.width, y: casuale.frazione() * size.height,
                                       width: 1.3, height: 1.3)
                    if indice % 2 == 0 { chiari.addRect(punto) } else { scuri.addRect(punto) }
                }
                ctx.fill(chiari, with: .color(Tema.testo.opacity(intensita)))
                ctx.fill(scuri, with: .color(Tema.sfumaturaScura.opacity(min(1, intensita * 1.4))))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Numeri pseudocasuali ripetibili (SplitMix64) per la grana: stesso seme, stessi puntini.
struct GeneratoreCasuale {
    var stato: UInt64

    mutating func prossimo() -> UInt64 {
        stato &+= 0x9E37_79B9_7F4A_7C15
        var z = stato
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Un numero tra 0 e 1.
    mutating func frazione() -> CGFloat {
        CGFloat(prossimo() >> 11) / CGFloat(UInt64(1) << 53)
    }
}
