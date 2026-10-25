import SwiftUI

/// WebcamLR Pro: un acquisto solo, sull'iPhone, che sblocca anche il computer tramite il telefono collegato
/// (`capacita.pro`, vedi Documenti/Protocollo.md). Qui il confronto e le viste comuni a iPhone e Mac.
public enum ConfrontoPro {
    /// Il prodotto in App Store Connect e nel file StoreKit dell'iPhone.
    public static let idProdotto = "it.lrapps.webcamlr.pro"

    /// Ciò che resta gratis, per sempre e senza filigrana.
    public static let gratis = [
        String(localized: "Video fino a 720p a 30 fps, senza filigrana", bundle: .stile),
        String(localized: "Wi-Fi e cavo USB", bundle: .stile),
        String(localized: "Specchia", bundle: .stile),
        String(localized: "Sfoca lo sfondo", bundle: .stile),
        String(localized: "Luce sul volto", bundle: .stile),
        String(localized: "Microfono del telefono sul Mac", bundle: .stile),
        String(localized: "Zoom, torcia e compensazione dell'esposizione", bundle: .stile),
        String(localized: "Collegamento sicuro", bundle: .stile)
    ]

    /// Ciò che aggiunge Pro, sul telefono e sul computer.
    public static let pro = [
        String(localized: "1080p e 4K, fino a 60 fps (il 4K a 30)", bundle: .stile),
        String(localized: "Inquadratura automatica", bundle: .stile),
        String(localized: "Volto + scrivania", bundle: .stile),
        String(localized: "Filtri e regolazioni", bundle: .stile),
        String(localized: "Sfondo sostituito con un'immagine", bundle: .stile),
        String(localized: "Ritocco della pelle", bundle: .stile),
        String(localized: "Scritta e logo nel video", bundle: .stile),
        String(localized: "Controlli Pro: ISO, tempo, bianco e messa a fuoco", bundle: .stile),
        String(localized: "Sul Mac: profili Riunione, Lezione, Diretta e Colloquio", bundle: .stile),
        String(localized: "Sul Mac: foto e registrazione", bundle: .stile),
        String(localized: "Sul Mac: gobbo", bundle: .stile),
        String(localized: "Sul Mac: due telefoni insieme", bundle: .stile),
        String(localized: "Sul Mac: schermata d'attesa personalizzata", bundle: .stile)
    ]
}

/// Il segno «PRO» accanto a un comando che fa parte di WebcamLR Pro: testo scuro sull'accento salvia, mai corallo.
public struct SegnoPro: View {
    let grande: Bool

    public init(grande: Bool = false) {
        self.grande = grande
    }

    public var body: some View {
        Text(verbatim: "PRO")
            .font(.etichetta(grande ? 16 : 11.5))
            .tracking(grande ? 0.6 : 0.8)
            .foregroundStyle(Tema.fondo)
            .padding(.horizontal, grande ? 8 : 5)
            .padding(.vertical, grande ? 3 : 1)
            .background(Tema.accento, in: RoundedRectangle(cornerRadius: grande ? 5 : 4, style: .continuous))
            .fixedSize()
            .accessibilityLabel(String(localized: "Funzione di WebcamLR Pro", bundle: .stile))
    }
}

/// Il pulsante principale della pagina Pro («Sblocca Pro · 14,99 €»): pieno nell'accento, testo scuro (`Tema.fondo`),
/// largo quanto la pagina. Mai corallo: il corallo è solo «in onda» e registrazione.
public struct StilePulsantePro: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CorpoPulsantePro(configuration: configuration)
    }
}

private struct CorpoPulsantePro: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var abilitato

    var body: some View {
        configuration.label
            .font(.corpoForte(17))
            .foregroundStyle(Tema.fondo)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Tema.accentoChiaro : Tema.accento,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(abilitato ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// La pagina «WebcamLR Pro», uguale su iPhone e Mac: titolo, stato (o invito), le azioni dell'app e il confronto
/// Gratis/Pro. Le azioni cambiano: sull'iPhone acquisto e «Ripristina acquisti», sul Mac lo stato del telefono e
/// la strada per sbloccarlo dall'iPhone. Senza `ScrollView`: la mette chi la mostra.
public struct PaginaPro<Azioni: View>: View {
    let attivo: Bool
    let azioni: Azioni

    /// `attivo`: Pro sbloccato (sull'iPhone l'acquisto, sul Mac il telefono «nella webcam»).
    public init(attivo: Bool, @ViewBuilder azioni: () -> Azioni) {
        self.attivo = attivo
        self.azioni = azioni()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                SegnoPro(grande: true)
                Text(verbatim: "WebcamLR Pro")
                    .font(.titolo(28))
                    .foregroundStyle(Tema.testo)
            }
            if attivo {
                statoAttivo
            } else {
                Text(String(localized: "Qualità piena, effetti da studio e tutti i comandi del Mac. Si paga una volta sola, senza abbonamento. Il resto di WebcamLR resta gratis.", bundle: .stile))
                    .foregroundStyle(Tema.testoChiaro)
                    .fixedSize(horizontal: false, vertical: true)
            }
            azioni
            VStack(alignment: .leading, spacing: 12) {
                colonna(titolo: String(localized: "Gratis", bundle: .stile),
                        nota: String(localized: "per sempre", bundle: .stile),
                        voci: ConfrontoPro.gratis, pro: false)
                colonna(titolo: String(localized: "Pro", bundle: .stile),
                        nota: String(localized: "tutto il gratis, più:", bundle: .stile),
                        voci: ConfrontoPro.pro, pro: true)
            }
        }
    }

    private var statoAttivo: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(Tema.accento)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Pro attivo", bundle: .stile))
                    .font(.titolo(20))
                    .foregroundStyle(Tema.accentoChiaro)
                Text(String(localized: "Grazie per aver scelto WebcamLR Pro: è tutto sbloccato.", bundle: .stile))
                    .foregroundStyle(Tema.testoChiaro)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.accentoTenue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func colonna(titolo: String, nota: String, voci: [String], pro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if pro {
                    SegnoPro()
                } else {
                    Text(titolo)
                        .font(.titolo(20))
                        .foregroundStyle(Tema.testo)
                }
                Text(nota)
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(titolo), \(nota)"))
            ForEach(voci, id: \.self) { voce in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: pro ? "plus" : "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(pro ? Tema.accento : Tema.testoSecondario)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(voce)
                        .foregroundStyle(Tema.testoChiaro)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pro ? Tema.pannelloChiaro : Tema.pannello, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(pro ? Tema.accento.opacity(0.55) : Tema.lineaTenue))
    }
}
