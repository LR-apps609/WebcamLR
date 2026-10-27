import Stile
import SwiftUI
import WebcamLRProtocollo

/// Sopra il video di «In onda»: la pausa (P07, P10 e il pulsante «Pausa»). È uno stato vero, quindi resta
/// finché la pausa dura; piccola, non blocca nulla.
struct BannerPausa: View {
    let sessione: SessioneTelefono

    var body: some View {
        if sessione.stato == .collegato, let motivo = sessione.pausa.motivo {
            HStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tema.cianoChiaro)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TestiAssistente.titoloPausa(motivo))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.testo)
                    Text(TestiAssistente.spiegazionePausa(motivo))
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Tema.pannello.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Il promemoria della postura (P11): sparisce da solo o con un tocco. «In onda» lo mostra solo quando non c'è
/// già un altro avviso: uno alla volta.
struct BannerPostura: View {
    let sessione: SessioneTelefono

    var body: some View {
        if let avviso = sessione.funzioni.avvisoPostura {
            Button {
                withAnimation { sessione.funzioni.nascondiAvviso() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: avviso.icona)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.cianoChiaro)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(avviso.titolo)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tema.testo)
                        Text(avviso.consiglio)
                            .font(.footnote)
                            .foregroundStyle(Tema.testoSecondario)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Tema.pannello.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Tocca per chiudere")
        }
    }
}

/// Le spiegazioni dell'assistente: una riga ciascuna, il resto nella Guida.
enum TestiAssistente {

    static func titoloPausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: String(localized: "In pausa: iPhone a faccia in giù")
        case MotiviPausa.nessunaApp: String(localized: "In pausa: nessuna app usa la webcam")
        default: String(localized: "In pausa")
        }
    }

    static func spiegazionePausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: String(localized: "Gira l'iPhone per riprendere il video. Il collegamento resta aperto.")
        case MotiviPausa.nessunaApp: String(localized: "Fotocamera spenta per risparmiare batteria: riparte da sola quando un'app usa la webcam.")
        case MotiviPausa.utente: String(localized: "Tocca ▶ a destra per riprendere. Il collegamento resta aperto.")
        default: String(localized: "Il collegamento resta aperto.")
        }
    }
}
