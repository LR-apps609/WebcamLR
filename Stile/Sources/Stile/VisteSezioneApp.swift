import SwiftUI

/// WebcamLR Pro: cosa include. Non ancora acquistabile (0.12): il pulsante è spento e lo dice.
public struct SchedaPro: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("PRO")
                    .font(.titolo(16))
                    .foregroundStyle(Tema.fondo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Tema.ciano, in: RoundedRectangle(cornerRadius: 5))
                Text("WebcamLR Pro")
                    .font(.titolo(24))
                    .foregroundStyle(Tema.testo)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(InfoApp.vantaggiPro, id: \.self) { vantaggio in
                    Label {
                        Text(vantaggio).foregroundStyle(Tema.testoChiaro)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Tema.ciano)
                    }
                }
            }
            Button {} label: {
                Text("Presto disponibile")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Tema.ciano)
            .disabled(true)
            .accessibilityHint("L'abbonamento non è ancora acquistabile")
            Text("Tutto il resto di WebcamLR è gratis, senza limiti di tempo.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
        .padding(18)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tema.lineaTenue))
    }
}

/// Accesso con l'account LR Apps: per ora non c'è, e lo spiega senza far sembrare l'app incompleta.
public struct SchedaAccesso: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 28))
                .foregroundStyle(Tema.testoTenue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Modalità senza account")
                    .fontWeight(.semibold)
                    .foregroundStyle(Tema.testo)
                Text("WebcamLR funziona completamente senza registrarti. L'accesso con l'account LR Apps arriverà per usare Pro su più dispositivi.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Accedi") {}
                    .disabled(true)
                    .padding(.top, 4)
            }
        }
    }
}

/// La guida: una sezione dopo l'altra, con i passi numerati.
public struct VistaGuida: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Guida.sezioni) { sezione in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(sezione.titolo, systemImage: sezione.simbolo)
                            .font(.titolo(22))
                            .foregroundStyle(Tema.testo)
                        ForEach(Array(sezione.passi.enumerated()), id: \.offset) { indice, passo in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(indice + 1)")
                                    .font(.numeri(13))
                                    .foregroundStyle(Tema.ciano)
                                    .frame(width: 18, alignment: .trailing)
                                Text(passo)
                                    .foregroundStyle(Tema.testoChiaro)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Link(destination: InfoApp.aiuto) {
                    Label("Altre risposte sul sito", systemImage: "arrow.up.right.square")
                }
                .tint(Tema.ciano)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(Tema.fondo)
    }
}

/// «Segnala un bug»: descrizione e dati tecnici già pronti, poi mail (se c'è l'indirizzo) o condivisione.
public struct ModuloSegnalazione: View {
    let datiTecnici: [(String, String)]
    @State private var descrizione = ""
    @State private var includiDati = true
    @FocusState private var scrivendo: Bool

    /// `datiTecnici`: coppie nome-valore che l'app conosce (versione, sistema, latenza…), mai dati personali.
    public init(datiTecnici: [(String, String)]) {
        self.datiTecnici = datiTecnici
    }

    private var testo: String {
        SegnalazioneBug.testo(descrizione: descrizione, datiTecnici: includiDati ? datiTecnici : nil)
    }

    private var indirizzoMail: URL? {
        guard !InfoApp.emailAssistenza.isEmpty else { return nil }
        var componenti = URLComponents()
        componenti.scheme = "mailto"
        componenti.path = InfoApp.emailAssistenza
        componenti.queryItems = [URLQueryItem(name: "subject", value: SegnalazioneBug.oggetto),
                                 URLQueryItem(name: "body", value: testo)]
        return componenti.url
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cosa è successo? Cosa stavi facendo?")
                    .fontWeight(.semibold)
                    .foregroundStyle(Tema.testo)
                TextEditor(text: $descrizione)
                    .focused($scrivendo)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tema.lineaTenue))
                    .accessibilityLabel("Descrizione del problema")

                Toggle("Includi i dati tecnici", isOn: $includiDati)
                    .tint(Tema.ciano)
                if includiDati {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(datiTecnici, id: \.0) { nome, valore in
                            HStack {
                                Text(nome).foregroundStyle(Tema.testoSecondario)
                                Spacer()
                                Text(valore).font(.numeri(12.5)).foregroundStyle(Tema.testoTenue)
                            }
                        }
                    }
                    .font(.footnote)
                    .padding(12)
                    .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 10))
                }

                Group {
                    if let indirizzoMail {
                        Link(destination: indirizzoMail) {
                            Label("Invia per email", systemImage: "envelope")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ShareLink(item: testo, subject: Text(SegnalazioneBug.oggetto)) {
                            Label("Invia la segnalazione", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tema.ciano)
                .disabled(descrizione.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Nessun video e nessuna immagine vengono inviati: solo il testo qui sopra.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(Tema.fondo)
        .onAppear { scrivendo = true }
    }
}
