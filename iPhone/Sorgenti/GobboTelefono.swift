import Foundation
import Observation
import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// P06 Gobbo: il testo mandato dal computer (messaggio `gobbo`) che scorre sullo schermo del telefono, vicino
/// all'obiettivo. È solo interfaccia del telefono: non passa mai dalla pipeline, quindi non finisce nel video.
///
/// - Posizione da 0 (inizio) a 1 (fine). Ferma vale `posizioneAncora`; mentre scorre si calcola dal tempo
///   (`posizione(a:)`), così la vista la legge a ogni fotogramma dello schermo senza che il modello cambi.
/// - Velocità in righe al secondo alla dimensione scelta: servono l'altezza di una riga e la distanza da
///   scorrere, che misura la vista (`misura`). Finché non le conosce il testo resta fermo.
/// - Al computer: `stato.gobbo` {attivo, posizione} con lo `stato` normale (ogni 5 secondi) e subito quando
///   cambia `attivo`, arriva un testo nuovo o il gobbo si chiude (`suCambio`).
@Observable
@MainActor
final class GobboTelefono {
    private(set) var testo = ""
    /// Righe al secondo, da 0,5 a 3.
    private(set) var velocita = 1.5
    /// Vero: scorre. Falso: fermo, il testo resta.
    private(set) var attivo = false
    /// Una delle `DimensioniGobbo`.
    private(set) var dimensione = DimensioniGobbo.media
    /// La posizione all'`istanteAncora`.
    private(set) var posizioneAncora = 0.0
    private(set) var istanteAncora = Date()

    /// Un cambiamento da dire subito al computer: la sessione manda uno `stato`.
    @ObservationIgnored var suCambio: (() -> Void)?
    /// Punti da scorrere dall'inizio alla fine; `nil` finché la vista non ha misurato il testo.
    /// Osservata: misurata la prima volta (o dopo una rotazione) la vista si ridisegna anche con il testo fermo.
    private(set) var distanza: Double?
    @ObservationIgnored private var altezzaRiga: Double = 40
    /// Ferma lo scorrimento quando arriva in fondo.
    @ObservationIgnored private var compitoFine: Task<Void, Never>?

    /// C'è un testo da mostrare.
    var visibile: Bool { !testo.isEmpty }

    /// Dove si trova il testo in quell'istante.
    func posizione(a data: Date) -> Double {
        guard attivo, let distanza, distanza > 0 else { return posizioneAncora }
        let trascorso = max(0, data.timeIntervalSince(istanteAncora))
        return min(1, posizioneAncora + trascorso * velocita * altezzaRiga / distanza)
    }

    // MARK: - Dal computer

    /// Si applicano solo i campi presenti (protocollo, «Gobbo»).
    func applica(_ messaggio: Gobbo) {
        fissa()
        let eraAttivo = attivo
        let eraVisibile = visibile
        var testoNuovo = false
        if let nuovo = messaggio.testo {
            testo = String(nuovo.prefix(Gobbo.lunghezzaMassima))
            // Un testo nuovo riparte dall'inizio; la vista lo misura di nuovo.
            posizioneAncora = 0
            distanza = nil
            testoNuovo = true
        }
        if let nuova = messaggio.velocita, nuova.isFinite {
            velocita = min(max(nuova, Gobbo.velocitaMinima), Gobbo.velocitaMassima)
        }
        if let nuova = messaggio.dimensione {
            dimensione = [DimensioniGobbo.piccola, DimensioniGobbo.media, DimensioniGobbo.grande].contains(nuova)
                ? nuova : DimensioniGobbo.media
        }
        if let salto = messaggio.posizione, salto.isFinite {
            posizioneAncora = min(max(salto, 0), 1)
        }
        if let nuovo = messaggio.attivo {
            // «Avvia» con il testo già in fondo: si ricomincia, se il computer non ha detto dove.
            if nuovo && !attivo && posizioneAncora >= 1 && messaggio.posizione == nil { posizioneAncora = 0 }
            attivo = nuovo
        }
        if testo.isEmpty { attivo = false }
        istanteAncora = Date()
        programmaFine()
        if attivo != eraAttivo || testoNuovo || visibile != eraVisibile { suCambio?() }
    }

    /// Per lo `stato`: assente se non c'è un gobbo.
    func completa(_ stato: inout StatoTelefono) {
        guard visibile else { return }
        let arrotondata = (posizione(a: Date()) * 1000).rounded() / 1000
        stato.gobbo = StatoGobbo(attivo: attivo, posizione: arrotondata)
    }

    // MARK: - Dal telefono

    /// Tocco sul testo: ferma o riprende. In fondo, riprendere ricomincia dall'inizio.
    func alternaPausa() {
        guard visibile else { return }
        fissa()
        if !attivo && posizioneAncora >= 1 { posizioneAncora = 0 }
        attivo.toggle()
        istanteAncora = Date()
        programmaFine()
        suCambio?()
    }

    /// Il pulsante di chiusura: il testo sparisce (lo `stato` non porta più `gobbo`).
    func chiudi() {
        guard visibile else { return }
        azzera()
        suCambio?()
    }

    /// Fine della sessione: il testo vive solo per la sessione (il computer lo rimanda al ricollegamento).
    func azzera() {
        compitoFine?.cancel()
        compitoFine = nil
        testo = ""
        attivo = false
        posizioneAncora = 0
        distanza = nil
        istanteAncora = Date()
    }

    // MARK: - Dalla vista

    /// Le misure del testo a schermo: altezza di una riga e distanza da scorrere, in punti.
    /// Cambiano con la dimensione, la rotazione del telefono o un testo nuovo.
    func misura(distanza nuovaDistanza: Double, altezzaRiga nuovaRiga: Double) {
        guard nuovaDistanza > 0, nuovaRiga > 0 else { return }
        if let distanza, abs(distanza - nuovaDistanza) < 0.5, abs(altezzaRiga - nuovaRiga) < 0.5 { return }
        // La posizione è una frazione: resta la stessa, cambia solo la velocità in punti.
        fissa()
        distanza = nuovaDistanza
        altezzaRiga = nuovaRiga
        istanteAncora = Date()
        programmaFine()
    }

    // MARK: - Interni

    /// Porta l'ancora a ora: da qui si può cambiare velocità, misure o stato senza salti.
    private func fissa() {
        let adesso = Date()
        posizioneAncora = posizione(a: adesso)
        istanteAncora = adesso
    }

    /// Quando arriva in fondo il testo si ferma, e il computer lo sa.
    private func programmaFine() {
        compitoFine?.cancel()
        compitoFine = nil
        guard attivo, let distanza, distanza > 0 else { return }
        let puntiAlSecondo = velocita * altezzaRiga
        guard puntiAlSecondo > 0 else { return }
        let secondi = max(0, (1 - posizioneAncora) * distanza / puntiAlSecondo)
        compitoFine = Task { [weak self] in
            try? await Task.sleep(for: .seconds(secondi + 0.05))
            guard !Task.isCancelled, let self, self.attivo else { return }
            self.fissa()
            self.posizioneAncora = 1
            self.attivo = false
            self.compitoFine = nil
            self.suCambio?()
        }
    }
}

/// Il gobbo sopra «In onda», vicino al bordo dell'obiettivo. Tocco: ferma o riprende; «×»: chiude.
struct VistaGobbo: View {
    let gobbo: GobboTelefono
    /// In orizzontale lo schermo è basso: meno righe visibili.
    let righeVisibili: Double

    /// Barlow Condensed SemiBold (Stile): stretto, ci stanno più parole per riga.
    private static let nomeCarattere = "BarlowCondensed-SemiBold"

    private var dimensioneCarattere: CGFloat {
        switch gobbo.dimensione {
        case DimensioniGobbo.piccola: 30
        case DimensioniGobbo.grande: 52
        default: 40
        }
    }

    private var spazioRighe: CGFloat { (dimensioneCarattere * 0.18).rounded() }

    /// Altezza di una riga con lo spazio tra le righe, come la disegna `Text` con `lineSpacing`.
    private var altezzaRiga: CGFloat {
        let altezza = UIFont(name: Self.nomeCarattere, size: dimensioneCarattere)?.lineHeight ?? dimensioneCarattere * 1.2
        return altezza + spazioRighe
    }

    var body: some View {
        let riga = altezzaRiga
        let altezzaFinestra = riga * righeVisibili
        ZStack(alignment: .topTrailing) {
            GeometryReader { area in
                TimelineView(.animation(minimumInterval: nil, paused: !gobbo.attivo)) { contesto in
                    let posizione = gobbo.posizione(a: contesto.date)
                    testo(larghezza: max(area.size.width - 40, 40), riga: riga, posizione: posizione)
                }
            }
            .frame(height: altezzaFinestra)
            .clipped()
            // Le righe entrano ed escono sfumate: l'occhio resta sulla riga in alto, la più vicina all'obiettivo.
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.8),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .contentShape(Rectangle())
            .onTapGesture { gobbo.alternaPausa() }
            .accessibilityElement()
            .accessibilityLabel("Gobbo")
            .accessibilityValue(gobbo.attivo ? "scorre" : "fermo")
            .accessibilityHint("Tocca per fermare o far ripartire il testo")
            .accessibilityAction { gobbo.alternaPausa() }

            HStack(spacing: Spazi.stretto) {
                if !gobbo.attivo {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Tema.accentoChiaro)
                        .frame(width: 28, height: 28)
                        .background(Tema.accentoTenue, in: Circle())
                        .accessibilityHidden(true)
                }
                Button {
                    gobbo.chiudi()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Tema.pannelloChiaro, in: Circle())
                        // Il pulsante è piccolo, ma la zona del tocco no.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi il gobbo")
            }
            // L'area di tocco da 44 sporge nell'angolo del riquadro: è una posizione, non una spaziatura.
            .padding(.top, -6)
            .padding(.trailing, -6)
        }
        .padding(.horizontal, Spazi.medio)
        .padding(.vertical, Spazi.stretto)
        .background(Veli.coloreForte, in: RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous).stroke(Tema.linea))
    }

    /// Il testo spostato in su della posizione: la riga da leggere sta in alto, vicino all'obiettivo.
    private func testo(larghezza: CGFloat, riga: CGFloat, posizione: Double) -> some View {
        Text(gobbo.testo)
            .font(.custom(Self.nomeCarattere, size: dimensioneCarattere))
            .lineSpacing(spazioRighe)
            .foregroundStyle(Tema.testo)
            .multilineTextAlignment(.leading)
            .frame(width: larghezza, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometria in
                geometria.size.height
            } action: { altezza in
                // In fondo l'ultima riga arriva dove all'inizio stava la prima.
                gobbo.misura(distanza: Double(max(altezza - riga, 1)), altezzaRiga: Double(riga))
            }
            .offset(y: riga * 0.35 - CGFloat(posizione) * CGFloat(max(gobbo.distanza ?? 0, 0)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
