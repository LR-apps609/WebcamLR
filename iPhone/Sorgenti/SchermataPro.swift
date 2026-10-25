import Stile
import StoreKit
import SwiftUI

/// La pagina «WebcamLR Pro» dell'iPhone: il confronto di Stile con acquisto e «Ripristina acquisti».
/// Si apre dalla sezione App e, come foglio (`FoglioPro`), da ogni comando con il segno «PRO».
struct SchermataPro: View {
    private var negozio: NegozioPro { NegozioPro.condiviso }

    var body: some View {
        ScrollView {
            PaginaPro(attivo: negozio.attivo) {
                if negozio.attivo {
                    attivo
                } else {
                    acquisto
                }
            }
            .padding(20)
        }
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .task { await negozio.caricaProdotto() }
    }

    /// Pro già sbloccato: da dove viene, e il ripristino resta a portata (per esempio dopo un cambio di Apple ID).
    private var attivo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(negozio.condivisoInFamiglia
                 ? "Condiviso In famiglia. Vale anche sul Mac collegato a questo iPhone."
                 : "Vale anche sul Mac collegato a questo iPhone, e su ogni iPhone con il tuo Apple ID o della tua famiglia.")
                .font(.subheadline)
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
            pulsanteRipristina
        }
    }

    private var acquisto: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prodotto = negozio.prodotto {
                Button {
                    Task { await negozio.compra() }
                } label: {
                    HStack(spacing: 8) {
                        if negozio.operazione == .acquisto {
                            ProgressView().tint(Tema.fondo)
                        }
                        Text("Sblocca Pro · \(prodotto.displayPrice)")
                    }
                }
                .buttonStyle(StilePulsantePro())
                .disabled(negozio.operazione != .nessuna)
            } else if negozio.prodottoNonTrovato {
                Text("L'App Store non risponde. Controlla la connessione.")
                    .font(.subheadline)
                    .foregroundStyle(Tema.ambraTesto)
                Button("Riprova") {
                    Task { await negozio.caricaProdotto() }
                }
                .buttonStyle(StilePulsanteSecondario())
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Collegamento all'App Store…")
                        .foregroundStyle(Tema.testoSecondario)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            Text("Una volta sola, per sempre. Vale per tutta la famiglia.")
                .font(.subheadline)
                .foregroundStyle(Tema.testoChiaro)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            if negozio.inAttesa {
                Text("Acquisto in attesa di approvazione: Pro si sblocca da solo appena è confermato.")
                    .font(.footnote)
                    .foregroundStyle(Tema.ambraTesto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let avviso = negozio.avviso {
                Text(avviso)
                    .font(.footnote)
                    .foregroundStyle(Tema.ambraTesto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pulsanteRipristina
                .frame(maxWidth: .infinity)
        }
    }

    private var pulsanteRipristina: some View {
        Button {
            Task { await negozio.ripristina() }
        } label: {
            HStack(spacing: 6) {
                if negozio.operazione == .ripristino { ProgressView() }
                Text("Ripristina acquisti")
            }
        }
        .font(.subheadline.weight(.semibold))
        .tint(Tema.accento)
        .disabled(negozio.operazione != .nessuna)
    }
}

/// «WebcamLR Pro» in un foglio con «Fine»: si apre toccando un comando con il segno «PRO».
struct FoglioPro: View {
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            SchermataPro()
                .navigationTitle(Text(verbatim: "WebcamLR Pro"))
                .navigationBarTitleDisplayMode(.inline)
                .intestazioneOpaca()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { chiudi() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
    }
}

/// Un comando di WebcamLR Pro senza Pro: si vede (attenuato) ma non si usa, e un tocco apre `FoglioPro`.
private struct BloccoPro: ViewModifier {
    let bloccato: Bool
    let apri: () -> Void

    func body(content: Content) -> some View {
        content
            .disabled(bloccato)
            .opacity(bloccato ? 0.5 : 1)
            .overlay {
                if bloccato {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: apri)
                        .accessibilityElement()
                        .accessibilityLabel("Funzione di WebcamLR Pro")
                        .accessibilityHint("Apre WebcamLR Pro")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { apri() }
                }
            }
    }
}

extension View {
    /// Senza Pro (`pro` falso) il comando resta visibile ma un tocco apre la pagina Pro invece del comando.
    func soloPro(_ pro: Bool, apri: @escaping () -> Void) -> some View {
        modifier(BloccoPro(bloccato: !pro, apri: apri))
    }
}

/// Un'etichetta di sezione con il segno «PRO» quando Pro non è attivo.
struct EtichettaPro: View {
    let testo: String
    let pro: Bool

    init(_ testo: String, pro: Bool) {
        self.testo = testo
        self.pro = pro
    }

    var body: some View {
        HStack(spacing: 6) {
            EtichettaSezione(testo)
            if !pro { SegnoPro() }
        }
    }
}
