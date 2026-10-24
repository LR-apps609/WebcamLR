import AVFoundation
import CoreImage
import PhotosUI
import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// Il foglio «Effetti» aperto da «In onda» (B2): filtri con le miniature dal vivo e regolazioni (P13),
/// sfondo (P14), ritocco della pelle (P15), sottopancia e logo (P17).
/// Il foglio si ferma a metà schermo: sopra si vede l'anteprima con gli effetti, come la riceve il computer.
struct SchermataEffetti: View {
    let visivi: EffettiVisivi
    let anteprima: AnteprimaEffetti
    var chiudi: () -> Void
    @State private var miniature = MiniatureFiltri()
    @State private var fotoScelta: PhotosPickerItem? = nil
    @State private var erroreFoto: String? = nil
    @State private var logoScelto: PhotosPickerItem? = nil
    @State private var erroreLogo: String? = nil
    /// Le miniature degli sfondi pronti: si disegnano una volta.
    @State private var miniatureSfondi: [SfondoPronto: UIImage] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    sezioneFiltri
                    sezioneRegolazioni
                    sezioneSfondo
                    sezionePelle
                    sezioneScritta
                    Text("Gli effetti sono già nel video che arriva al computer, e si possono cambiare anche da lì. L'anteprima mostra il video come lo vede il computer: non è specchiata.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .navigationTitle("Effetti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Tema.ciano)
        .foregroundStyle(Tema.testo)
        .preferredColorScheme(.dark)
        .task {
            // Miniature dal vivo finché il foglio è aperto, a frequenza bassa.
            await miniature.aggiorna(da: anteprima)
        }
        .onAppear {
            if miniatureSfondi.isEmpty {
                for scelto in SfondoPronto.allCases where scelto != .foto {
                    miniatureSfondi[scelto] = EffettoSfondo.miniatura(scelto, misura: CGSize(width: 80, height: 50))
                }
            }
        }
        .onChange(of: fotoScelta) { _, nuova in
            guard let nuova else { return }
            Task {
                erroreFoto = nil
                let dati = try? await nuova.loadTransferable(type: Data.self)
                var riuscita = false
                if let dati { riuscita = await visivi.usaFotoSfondo(dati) }
                if !riuscita { erroreFoto = String(localized: "Questa foto non si apre: scegline un'altra.") }
                fotoScelta = nil
            }
        }
        .onChange(of: logoScelto) { _, nuovo in
            guard let nuovo else { return }
            Task {
                erroreLogo = nil
                let dati = try? await nuovo.loadTransferable(type: Data.self)
                var riuscito = false
                if let dati { riuscito = await visivi.usaLogo(dati) }
                if !riuscito { erroreLogo = String(localized: "Questa immagine non si apre: scegline un'altra.") }
                logoScelto = nil
            }
        }
    }

    // MARK: Filtri

    private var sezioneFiltri: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "Filtri"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Filtri.tutti, id: \.self) { filtro in
                        miniatura(filtro)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func miniatura(_ filtro: String) -> some View {
        let scelto = visivi.filtro == filtro
        return Button {
            visivi.scegliFiltro(filtro)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Tema.pannello)
                    if let immagine = miniature.immagini[filtro] {
                        Image(uiImage: immagine)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(scelto ? Tema.ciano : Tema.linea,
                                                                     lineWidth: scelto ? 2.5 : 1))
                Text(RicetteFiltri.nome(filtro))
                    .font(.caption.weight(scelto ? .semibold : .regular))
                    .foregroundStyle(scelto ? Tema.cianoChiaro : Tema.testoChiaro)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtro \(RicetteFiltri.nome(filtro))")
        .accessibilityAddTraits(scelto ? .isSelected : [])
    }

    // MARK: Regolazioni

    private var sezioneRegolazioni: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EtichettaSezione(String(localized: "Regolazioni"))
                Spacer()
                if visivi.regolazioni != RegolazioniBase.Valori() {
                    Button("Azzera") { visivi.impostaRegolazioni(RegolazioniBase.Valori()) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            VStack(spacing: 4) {
                CursoreEffetto(titolo: "Luminosità", valore: regolazione(\.luminosita), intervallo: -1...1)
                CursoreEffetto(titolo: "Contrasto", valore: regolazione(\.contrasto), intervallo: -1...1)
                CursoreEffetto(titolo: "Saturazione", valore: regolazione(\.saturazione), intervallo: -1...1)
                CursoreEffetto(titolo: "Nitidezza", valore: regolazione(\.nitidezza), intervallo: -1...1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: Sfondo

    private var sezioneSfondo: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "Sfondo"))
            Picker("Sfondo", selection: Binding(get: { visivi.sfondo }, set: { visivi.scegliSfondo($0) })) {
                Text("Nessuno").tag(ModiSfondo.nessuno)
                Text("Sfocato").tag(ModiSfondo.sfocato)
                Text("Sostituito").tag(ModiSfondo.sostituito)
            }
            .pickerStyle(.segmented)
            if visivi.ritrattoDiSistema {
                avvisoRitratto
            }
            if visivi.sfondo == ModiSfondo.sostituito {
                immaginiSfondo
            }
            if visivi.sfondo != ModiSfondo.nessuno {
                CursoreEffetto(titolo: visivi.sfondo == ModiSfondo.sostituito ? "Bordo netto" : "Sfocatura",
                               valore: Binding(get: { visivi.intensitaSfondo },
                                               set: { visivi.impostaIntensitaSfondo($0) }),
                               intervallo: 0...1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Lo sfondo segue la persona davanti alla fotocamera: rende meglio con una persona sola e una stanza ben illuminata.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pelle

    private var sezionePelle: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "Ritocco"))
            VStack(spacing: 4) {
                Toggle("Ritocco della pelle", isOn: Binding(get: { visivi.pelle > 0 },
                                                            set: { visivi.accendiPelle($0) }))
                    .padding(.vertical, 6)
                if visivi.pelle > 0 {
                    CursoreEffetto(titolo: "Intensità",
                                   valore: Binding(get: { visivi.pelle }, set: { visivi.impostaPelle(max($0, 0.02)) }),
                                   intervallo: 0...1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14))
            Text("Leviga appena la pelle del viso, lasciando nitidi occhi, labbra e capelli.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Scritta

    private var sezioneScritta: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "Scritta e logo"))
            VStack(spacing: 0) {
                TextField("Nome", text: Binding(get: { visivi.nomeScritta },
                                                set: { visivi.impostaScritta(nome: $0, ruolo: visivi.ruoloScritta) }))
                    .textContentType(.name)
                    .submitLabel(.done)
                    .padding(.vertical, 12)
                Divider().overlay(Tema.linea)
                TextField("Ruolo (facoltativo)", text: Binding(get: { visivi.ruoloScritta },
                                                               set: { visivi.impostaScritta(nome: visivi.nomeScritta, ruolo: $0) }))
                    .textContentType(.jobTitle)
                    .submitLabel(.done)
                    .padding(.vertical, 12)
                    .disabled(visivi.nomeScritta.isEmpty)
            }
            .padding(.horizontal, 14)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                if let logo = visivi.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .padding(4)
                        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $logoScelto, matching: .images) {
                        Label(visivi.logo == nil ? "Aggiungi un logo…" : "Cambia il logo…", systemImage: "seal")
                            .font(.subheadline.weight(.semibold))
                    }
                    if visivi.logo != nil {
                        Button("Togli il logo") { visivi.togliLogo() }
                            .font(.subheadline)
                    }
                }
                Spacer()
                if visivi.logo != nil {
                    Toggle("Mostra", isOn: Binding(get: { visivi.mostraLogo }, set: { visivi.impostaMostraLogo($0) }))
                        .labelsHidden()
                        .accessibilityLabel("Mostra il logo")
                }
            }
            if let erroreLogo {
                Text(erroreLogo)
                    .font(.footnote)
                    .foregroundStyle(Tema.ambraTesto)
            }
            Text("Nome e ruolo compaiono in basso a sinistra, il logo in alto a destra. Chi ti guarda li legge dritti anche con «Specchia l'immagine inviata». Senza nome non c'è scritta.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// «Ritratto» di iOS e lo sfondo di WebcamLR non si sommano: lo si dice, con la strada per spegnerlo.
    private var avvisoRitratto: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(visivi.sfondo == ModiSfondo.sfocato
                 ? "«Ritratto» di iOS è acceso e sfoca già lo sfondo: «Sfocato» di WebcamLR resta in pausa, per non sfocare due volte."
                 : "«Ritratto» di iOS è acceso e sfoca già lo sfondo. Con «Sostituito» lo sfondo di WebcamLR va sopra.")
                .font(.footnote)
                .foregroundStyle(Tema.ambraTesto)
                .fixedSize(horizontal: false, vertical: true)
            Button("Apri «Effetti video»") {
                AVCaptureDevice.showSystemUserInterface(.videoEffects)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.ambraTenue, in: RoundedRectangle(cornerRadius: 12))
    }

    private var immaginiSfondo: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SfondoPronto.allCases) { scelto in
                        if scelto != .foto || visivi.haFotoSfondo {
                            tesseraSfondo(scelto)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            PhotosPicker(selection: $fotoScelta, matching: .images) {
                Label(visivi.haFotoSfondo ? "Cambia la tua foto…" : "Usa una tua foto…", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
            }
            if let erroreFoto {
                Text(erroreFoto)
                    .font(.footnote)
                    .foregroundStyle(Tema.ambraTesto)
            }
        }
    }

    private func tesseraSfondo(_ scelto: SfondoPronto) -> some View {
        let attivo = visivi.sfondoScelto == scelto
        let immagine = scelto == .foto ? visivi.fotoSfondo : miniatureSfondi[scelto]
        return Button {
            visivi.scegliImmagineSfondo(scelto)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Tema.pannello)
                    if let immagine {
                        Image(uiImage: immagine)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(attivo ? Tema.ciano : Tema.linea,
                                                                   lineWidth: attivo ? 2.5 : 1))
                Text(scelto.nome)
                    .font(.caption.weight(attivo ? .semibold : .regular))
                    .foregroundStyle(attivo ? Tema.cianoChiaro : Tema.testoChiaro)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sfondo \(scelto.nome)")
        .accessibilityAddTraits(attivo ? .isSelected : [])
    }

    private func regolazione(_ campo: WritableKeyPath<RegolazioniBase.Valori, Double>) -> Binding<Double> {
        Binding(
            get: { visivi.regolazioni[keyPath: campo] },
            set: { nuovo in
                var valori = visivi.regolazioni
                valori[keyPath: campo] = nuovo
                visivi.impostaRegolazioni(valori)
            }
        )
    }
}

/// Un cursore con titolo e valore («+25», «0»), uguale per tutti gli effetti.
/// Con `intervallo` 0…1 il valore si legge come percentuale.
struct CursoreEffetto: View {
    let titolo: LocalizedStringKey
    @Binding var valore: Double
    var intervallo: ClosedRange<Double> = -1...1

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(titolo).font(.subheadline)
                Spacer()
                Text(testoValore)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoSecondario)
            }
            Slider(value: $valore, in: intervallo)
                .accessibilityLabel(titolo)
                .accessibilityValue(testoValore)
        }
        .padding(.vertical, 4)
    }

    private var testoValore: String {
        let percento = Int((valore * 100).rounded())
        if intervallo.lowerBound >= 0 { return "\(percento)%" }
        return percento > 0 ? "+\(percento)" : "\(percento)"
    }
}

/// Le miniature dei filtri dall'ultimo fotogramma, rifatte circa ogni 0,7 secondi mentre il foglio è aperto.
@Observable
@MainActor
final class MiniatureFiltri {
    private(set) var immagini: [String: UIImage] = [:]

    /// Finché il compito non si annulla (il foglio si chiude).
    func aggiorna(da anteprima: AnteprimaEffetti) async {
        while !Task.isCancelled {
            if let fotogramma = await anteprima.istantanea() {
                let nuove = await Task.detached(priority: .utility) {
                    Self.rendi(fotogramma)
                }.value
                if !Task.isCancelled { immagini = nuove }
            }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    /// Un quadrato al centro del fotogramma, con ogni filtro.
    private nonisolated static func rendi(_ fotogramma: CGImage) -> [String: UIImage] {
        let base = CIImage(cgImage: fotogramma)
        let lato = min(base.extent.width, base.extent.height)
        let quadrato = CGRect(x: base.extent.midX - lato / 2, y: base.extent.midY - lato / 2, width: lato, height: lato)
            .integral
        let ritagliata = base.cropped(to: quadrato)
        var risultato: [String: UIImage] = [:]
        for filtro in Filtri.tutti {
            let filtrata = RicetteFiltri.applica(filtro, a: ritagliata)
            if let immagine = ContestiEffetti.immagini.createCGImage(filtrata, from: quadrato) {
                risultato[filtro] = UIImage(cgImage: immagine)
            }
        }
        return risultato
    }
}
