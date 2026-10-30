import Stile
import SwiftUI
import UIKit

/// I dati tecnici di «Segnala un bug» (prima nella sezione App, che dalla beta 4 è dentro le Impostazioni).
extension SchermataImpostazioni {
    /// Solo dati tecnici utili, nessun dato personale: niente nome del telefono, niente indirizzi.
    static func datiTecnici(ultimaLatenzaMs: Int?) -> [(String, String)] {
        var dati: [(String, String)] = [
            (String(localized: "App"), InfoApp.versione),
            // Il sistema operativo (la chiave distingue «Sistema» da altri usi della parola).
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
/// conferma sul computer, oppure QR code. Nelle Impostazioni (Altro › App e assistenza).
struct SezioneComputerConosciuti: View {
    @State private var conosciuti: [ComputerConosciuti.Voce] = []

    var body: some View {
        Section {
            if conosciuti.isEmpty {
                Text("Nessuno per ora: compaiono qui dopo il primo collegamento.")
                    .font(.stile(.corpo))
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            } else {
                ForEach(conosciuti) { voce in
                    VStack(alignment: .leading, spacing: Spazi.minimo) {
                        Text(voce.nome)
                            .font(.stile(.corpo, .corpoForte))
                        Text("Codice di sicurezza \(String(voce.impronta.prefix(8)))")
                            .font(.stile(.numeri))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    .padding(.vertical, Spazi.minimo)
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
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
        }
        .onAppear { conosciuti = ComputerConosciuti.tutti }
    }
}

/// Versione, privacy e sito, con la firma di LR Apps. Nelle Impostazioni (Altro › App e assistenza).
struct SezioneInformazioni: View {
    @State private var paginaAperta: PaginaWeb? = nil

    var body: some View {
        Section {
            LabeledContent("Versione") {
                Text(InfoApp.versione)
                    .font(.stile(.numeri))
                    .foregroundStyle(Tema.testoSecondario)
            }
            .listRowBackground(Tema.pannello)
            // G1.2: dentro l'app (Safari in un foglio), non in Safari: in diretta il video continua.
            Button {
                paginaAperta = PaginaWeb(indirizzo: InfoApp.privacy)
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
            .listRowBackground(Tema.pannello)
            Button {
                paginaAperta = PaginaWeb(indirizzo: InfoApp.sito)
            } label: {
                Label("Sito di WebcamLR", systemImage: "safari")
            }
            .listRowBackground(Tema.pannello)
            .sheet(item: $paginaAperta) { pagina in
                VistaSafari(indirizzo: pagina.indirizzo)
                    .ignoresSafeArea()
            }
        } header: {
            EtichettaSezione(String(localized: "Informazioni"))
        } footer: {
            VStack(spacing: Spazi.minimo) {
                Text("Un'app di LR Apps")
                    .font(.stile(.sezione))
                    .foregroundStyle(Tema.testoChiaro)
                Text("Della stessa famiglia: \(InfoApp.altreAppLR.joined(separator: " · "))")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
            }
            // Sugli iPhone stretti o con il testo grande «Della stessa famiglia…» va a capo: centrato anche lui.
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Spazi.largo)
        }
    }
}
