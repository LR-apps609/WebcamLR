import Stile
import SwiftUI
import UIKit

/// Sezione App (0.12): WebcamLR Pro, domande frequenti (1.4), guida, segnalazioni, computer conosciuti e informazioni.
/// Si apre come foglio dalla schermata dei computer. I contenuti comuni stanno in Stile.
struct SchermataApp: View {
    /// L'ultima latenza misurata in questo avvio, se c'è stata: va nei dati tecnici della segnalazione.
    let ultimaLatenzaMs: Int?
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SchermataPro()
                            .navigationTitle(Text(verbatim: "WebcamLR Pro"))
                            .navigationBarTitleDisplayMode(.inline)
                            .intestazioneOpaca()
                    } label: {
                        rigaPro
                    }
                    .listRowBackground(Tema.pannello)
                } header: {
                    EtichettaSezione("WebcamLR Pro")
                }

                Section {
                    NavigationLink {
                        VistaDomandeFrequenti()
                            .navigationTitle("Domande frequenti")
                            .navigationBarTitleDisplayMode(.inline)
                            .intestazioneOpaca()
                    } label: {
                        Label("Domande frequenti", systemImage: "questionmark.bubble")
                    }
                    .listRowBackground(Tema.pannello)
                    NavigationLink {
                        VistaGuida()
                            .navigationTitle("Guida")
                            .navigationBarTitleDisplayMode(.inline)
                            .intestazioneOpaca()
                    } label: {
                        Label("Guida", systemImage: "book")
                    }
                    .listRowBackground(Tema.pannello)
                    NavigationLink {
                        ModuloSegnalazione(datiTecnici: Self.datiTecnici(ultimaLatenzaMs: ultimaLatenzaMs))
                            .navigationTitle("Segnala un bug")
                            .navigationBarTitleDisplayMode(.inline)
                            .intestazioneOpaca()
                    } label: {
                        Label("Segnala un bug", systemImage: "ant")
                    }
                    .listRowBackground(Tema.pannello)
                } header: {
                    EtichettaSezione(String(localized: "Assistenza"))
                }

                SezioneComputerConosciuti()

                SezioneInformazioni()
            }
            .tint(Tema.ciano)
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle(Text(verbatim: "WebcamLR"))
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

    /// La riga di WebcamLR Pro: lo stato, o l'invito a sbloccarlo.
    private var rigaPro: some View {
        HStack(spacing: 12) {
            SegnoPro(grande: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "WebcamLR Pro")
                    .fontWeight(.semibold)
                Text(NegozioPro.condiviso.attivo
                     ? String(localized: "Pro attivo: grazie!")
                     : String(localized: "1080p, 4K, 60 fps, effetti e tutto il Mac"))
                    .font(.footnote)
                    .foregroundStyle(NegozioPro.condiviso.attivo ? Tema.accentoChiaro : Tema.testoSecondario)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Solo dati tecnici utili, nessun dato personale: niente nome del telefono, niente indirizzi.
    static func datiTecnici(ultimaLatenzaMs: Int?) -> [(String, String)] {
        var dati: [(String, String)] = [
            (String(localized: "App"), InfoApp.versione),
            // «Sistema» da solo è già il pulsante della prova della webcam («Fix it»): qui è il sistema operativo.
            (String(localized: "Sistema (dati tecnici)", defaultValue: "Sistema"), "iOS \(UIDevice.current.systemVersion)"),
            (String(localized: "Modello"), Self.identificatoreModello)
        ]
        if let latenza = ultimaLatenzaMs {
            dati.append((String(localized: "Ultima latenza"), "\(latenza) ms"))
        }
        // Il nome del computer no: spesso contiene il nome della persona («MacBook di …»).
        if UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer) != nil {
            dati.append((String(localized: "Collegato in passato"), String(localized: "sì")))
        }
        return dati
    }

    /// Per esempio «iPhone15,2»: dice il modello senza dire di chi è.
    private static let identificatoreModello: String = {
        var sistema = utsname()
        uname(&sistema)
        let identificatore = withUnsafeBytes(of: sistema.machine) { byte in
            String(decoding: byte.prefix { $0 != 0 }, as: UTF8.self)
        }
        return identificatore.isEmpty ? "—" : identificatore
    }()
}

/// I computer a cui l'iPhone si è già collegato. Togliendone uno, la volta dopo si riparte da capo: codice di
/// conferma sul computer, oppure QR code. Nella sezione App e nelle Impostazioni (Altro › Computer conosciuti).
struct SezioneComputerConosciuti: View {
    @State private var conosciuti: [ComputerConosciuti.Voce] = []

    var body: some View {
        Section {
            if conosciuti.isEmpty {
                Text("Nessuno per ora: compaiono qui dopo il primo collegamento.")
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            } else {
                ForEach(conosciuti) { voce in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(voce.nome)
                            .fontWeight(.semibold)
                        Text("Codice di sicurezza \(String(voce.impronta.prefix(8)))")
                            .font(.numeri(12))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Tema.pannello)
                    .accessibilityElement(children: .combine)
                }
                .onDelete { posizioni in
                    for posizione in posizioni {
                        ComputerConosciuti.dimentica(conosciuti[posizione].nome)
                    }
                    conosciuti.remove(atOffsets: posizioni)
                }
            }
        } header: {
            EtichettaSezione(String(localized: "Computer conosciuti"))
        } footer: {
            Text("Scorri verso sinistra per togliere un computer: la prossima volta andrà confermato di nuovo.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
        .onAppear { conosciuti = ComputerConosciuti.tutti }
    }
}

/// Versione, privacy e sito, con la firma di LR Apps. Nella sezione App e nelle Impostazioni (Altro › Informazioni).
struct SezioneInformazioni: View {
    var body: some View {
        Section {
            LabeledContent("Versione") {
                Text(InfoApp.versione)
                    .font(.numeri(13))
                    .foregroundStyle(Tema.testoSecondario)
            }
            .listRowBackground(Tema.pannello)
            Link(destination: InfoApp.privacy) {
                Label("Privacy", systemImage: "hand.raised")
            }
            .listRowBackground(Tema.pannello)
            Link(destination: InfoApp.sito) {
                Label("Sito di WebcamLR", systemImage: "safari")
            }
            .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione(String(localized: "Informazioni"))
        } footer: {
            VStack(spacing: 4) {
                Text("Un'app di LR Apps")
                    .font(.etichetta(16))
                    .foregroundStyle(Tema.testoChiaro)
                Text("Della stessa famiglia: \(InfoApp.altreAppLR.joined(separator: " · "))")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
            // Sugli iPhone stretti o con il testo grande «Della stessa famiglia…» va a capo: centrato anche lui.
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }
}

#Preview {
    SchermataApp(ultimaLatenzaMs: 42)
}
