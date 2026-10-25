import Stile
import SwiftUI
import WebcamLRProtocollo

/// WebcamLR Pro sul Mac: niente acquisti qui. Si compra sull'iPhone e il telefono «Nella webcam» lo dice con
/// `capacita.pro` (Documenti/Protocollo.md, «WebcamLR Pro»). Il Mac lo usa solo per l'interfaccia: i limiti veri
/// (720p a 30 fps, comandi Pro ignorati) li applica il telefono.
extension Ricevitore {
    /// Il telefono «Nella webcam» ha sbloccato WebcamLR Pro (`capacita.pro == true`). Falso senza telefono, con un
    /// telefono gratis o con un telefono vecchio che non manda il campo. Lo usano anche la schermata d'attesa
    /// personalizzata e il secondo telefono.
    var proAttivo: Bool {
        capacita?.pro == true
    }

    /// Un telefono collegato senza Pro: i comandi Pro si vedono con il segno «PRO» e restano spenti. Senza telefono
    /// i comandi sono già grigi («Collega un telefono»): niente segno in più.
    var bloccoPro: Bool {
        telefonoAttivo && capacita != nil && !proAttivo
    }
}

/// La strada per sbloccare, uguale ovunque sul Mac.
enum TestiPro {
    static let sblocca = String(localized: "Sblocca WebcamLR Pro sull'iPhone")
    static let strada = String(localized: "Si sblocca dall'iPhone: apri WebcamLR › App › WebcamLR Pro.")
}

/// Una riga sotto una sezione Pro bloccata: «PRO Sblocca WebcamLR Pro sull'iPhone».
struct RigaPro: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SegnoPro()
            Text(TestiPro.sblocca)
                .font(.corpo(12))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(TestiPro.strada)
        .accessibilityElement(children: .combine)
    }
}

/// Un comando di WebcamLR Pro con un telefono gratis: grigio, con il segno «PRO» (se `segno`), l'aiuto al
/// passaggio e, al clic, la nota con la strada per sbloccarlo dall'iPhone. Come `richiedeTelefono`.
private struct RichiedePro: ViewModifier {
    let bloccato: Bool
    let segno: Bool
    @State private var mostraNota = false

    func body(content: Content) -> some View {
        corpo(content)
            .onChange(of: bloccato) { mostraNota = false }
    }

    @ViewBuilder private func corpo(_ content: Content) -> some View {
        if bloccato {
            HStack(spacing: 6) {
                content
                    .disabled(true)
                    .opacity(0.45)
                if segno { SegnoPro() }
            }
            // Sopra il comando spento: il clic arriva qui e apre la nota.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { mostraNota = true }
            }
            .popover(isPresented: $mostraNota, arrowEdge: .bottom) {
                NotaPro()
                    .padding(12)
            }
            .help(TestiPro.sblocca)
            .accessibilityHint(TestiPro.strada)
        } else {
            content
        }
    }
}

/// La nota del clic su un comando Pro bloccato.
private struct NotaPro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SegnoPro()
                Text(TestiPro.sblocca)
                    .font(.corpoEvidente(13))
                    .foregroundStyle(Tema.testo)
            }
            Text(TestiPro.strada)
                .font(.corpo(12))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300, alignment: .leading)
    }
}

extension View {
    /// Grigio, con il segno «PRO» e la strada per sbloccarlo quando `bloccato` è vero (`Ricevitore.bloccoPro`).
    /// `segno` falso quando il segno è già nel titolo della sezione.
    func richiedePro(_ bloccato: Bool, segno: Bool = true) -> some View {
        modifier(RichiedePro(bloccato: bloccato, segno: segno))
    }
}

/// La scheda «WebcamLR Pro» della finestra «App e assistenza»: lo stesso confronto dell'iPhone, con lo stato del
/// telefono collegato e la strada per sbloccarlo. Sul Mac non si compra nulla.
struct PaginaProMac: View {
    let ricevitore: Ricevitore

    var body: some View {
        ScrollView {
            PaginaPro(attivo: ricevitore.proAttivo) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .foregroundStyle(Tema.testoSecondario)
                            .accessibilityHidden(true)
                        Text(statoTelefono)
                            .font(.corpoEvidente(13))
                            .foregroundStyle(Tema.testo)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !ricevitore.proAttivo {
                        Text(TestiPro.strada)
                            .font(.corpo(13))
                            .foregroundStyle(Tema.testoChiaro)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Tema.lineaTenue))
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var statoTelefono: String {
        guard let nome = ricevitore.telefono?.nome, ricevitore.capacita != nil else {
            return String(localized: "Nessun telefono collegato: Pro si vede qui quando colleghi l'iPhone su cui l'hai sbloccato.")
        }
        if ricevitore.proAttivo {
            return String(localized: "Pro attivo su «\(nome)»: tutto WebcamLR è sbloccato anche su questo Mac.")
        }
        return String(localized: "«\(nome)» usa la versione gratuita.")
    }
}

extension OpzioneQualita {
    /// Le scelte di «Qualità video» che sono di WebcamLR Pro: con un telefono gratis si mostrano con «PRO».
    static let soloPro = [OpzioneQualita(larghezza: 1920, altezza: 1080, fps: 30),
                          OpzioneQualita(larghezza: 1920, altezza: 1080, fps: 60),
                          OpzioneQualita(larghezza: 3840, altezza: 2160, fps: 30)]
}
