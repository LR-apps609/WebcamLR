import Stile
import SwiftUI

// I pezzi comuni della presentazione: argomenti di avvio, barrette di avanzamento, titolo, pulsanti, chip e
// l'impaginazione di una pagina. Colori e caratteri vengono tutti da Stile (Tema, Font.titolo, Font.corpo…).
// Restano qui perché per ora li usa solo la presentazione dell'iPhone: se serviranno anche altrove
// (Mac, «Novità»…) si possono spostare in Stile/Componenti.swift così come sono.

/// Argomenti di avvio della presentazione (si scrivono nello schema di Xcode, «Arguments Passed On Launch»).
enum ArgomentiPresentazione {
    /// `-presentazioneAutoplay`: la presentazione va avanti da sola con i tempi di una persona, per registrare
    /// il video del sito. Mostra anche la presentazione, come `-presentazione`. Non tocca mai «Inizia».
    static let autoplay = ProcessInfo.processInfo.arguments.contains("-presentazioneAutoplay")
    /// `-presentazione`: la mostra di nuovo anche se è già stata vista.
    static let forzata = autoplay || ProcessInfo.processInfo.arguments.contains("-presentazione")
}

/// L'avanzamento in stile «storie»: una barretta per pagina, quella attuale si riempie nel tempo della pagina.
struct BarreAvanzamento: View {
    let pagina: Int
    let totale: Int
    /// Riempimento della barretta della pagina attuale, da 0 a 1.
    let riempimento: Double

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<totale, id: \.self) { indice in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.linea)
                        Capsule().fill(Tema.accento)
                            .frame(width: g.size.width * quota(indice))
                    }
                }
                .frame(width: 30, height: 5)
            }
        }
        .accessibilityElement()
        // A11 (passo 9): il totale viene dalle pagine vere, non più scritto a mano.
        .accessibilityLabel(Text("Pagina \(numero) di \(totale)"))
    }

    private var numero: Int { min(pagina + 1, totale) }

    private func quota(_ indice: Int) -> CGFloat {
        if indice < pagina { return 1 }
        if indice == pagina { return CGFloat(riempimento) }
        return 0
    }
}

/// Titolo di una pagina, in Barlow Condensed.
struct TitoloPresentazione: View {
    let testo: Text

    init(_ testo: Text) {
        self.testo = testo
    }

    var body: some View {
        testo
            .font(.titolo(36))
            .foregroundStyle(Tema.testo)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Testo normale di una pagina.
struct TestoPresentazione: View {
    let testo: Text
    var colore: Color = Tema.testoChiaro
    var dimensione: CGFloat = 17

    init(_ testo: Text, colore: Color = Tema.testoChiaro, dimensione: CGFloat = 17) {
        self.testo = testo
        self.colore = colore
        self.dimensione = dimensione
    }

    var body: some View {
        testo
            .font(.corpo(dimensione))
            .foregroundStyle(colore)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Il pulsante pieno nell'accento salvia, in fondo a ogni pagina.
struct PulsantePresentazione: View {
    let titolo: Text
    var icona: String? = nil
    let identificatore: String
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 10) {
                titolo.font(.corpoForte(19))
                if let icona {
                    Image(systemName: icona)
                        .font(.system(size: 16, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Tema.fondo)
            .background(Tema.accento, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identificatore)
    }
}

/// Una scelta a capsula: scelta nell'accento, le altre sul pannello.
struct ChipPresentazione: View {
    let titolo: Text
    let scelto: Bool
    /// Vero dentro una griglia: la capsula occupa tutta la colonna.
    var pieno = false
    let identificatore: String
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            titolo
                .font(.corpoForte(16))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: pieno ? .infinity : nil, minHeight: 40)
                .foregroundStyle(scelto ? Tema.accentoChiaro : Tema.testo)
                .background(scelto ? Tema.accentoTenue : Tema.pannello, in: Capsule())
                .overlay(Capsule().stroke(scelto ? Tema.accento : Tema.linea, lineWidth: scelto ? 1.5 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(scelto ? .isSelected : [])
        .accessibilityIdentifier(identificatore)
    }
}

/// Il puntino corallo «in onda» su un riquadro video: l'unico corallo della presentazione.
/// A8: con «Riduci movimento» il punto sta fermo, acceso.
struct PuntoInOnda: View {
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Tema.tally)
                .frame(width: 6, height: 6)
                .phaseAnimator(riduciMovimento ? [true] : [false, true]) { punto, acceso in
                    punto.opacity(acceso ? 1 : 0.45)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            Text("In onda")
                .font(.etichetta(10))
                .textCase(.uppercase)
                .foregroundStyle(Tema.testo)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Tema.sfumaturaScura.opacity(0.75), in: Capsule())
    }
}

/// Una pagina: la scena disegnata in alto, il testo sotto (scorre se il carattere è molto grande)
/// e i pulsanti fermi in fondo.
struct ImpaginazionePagina<Scena: View, Contenuto: View, Azioni: View>: View {
    /// Quanto dell'altezza disponibile va alla scena.
    let quotaScena: CGFloat
    let scena: Scena
    let contenuto: Contenuto
    let azioni: Azioni

    init(quotaScena: CGFloat = 0.44,
         @ViewBuilder scena: () -> Scena,
         @ViewBuilder contenuto: () -> Contenuto,
         @ViewBuilder azioni: () -> Azioni) {
        self.quotaScena = quotaScena
        self.scena = scena()
        self.contenuto = contenuto()
        self.azioni = azioni()
    }

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        scena
                            .frame(maxWidth: .infinity)
                            .frame(height: altezzaScena(g.size.height))
                        contenuto
                    }
                    // Sotto le barrette e «Salta»
                    .padding(.top, 60)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                azioni
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func altezzaScena(_ altezza: CGFloat) -> CGFloat {
        min(340, max(180, altezza * quotaScena))
    }
}
