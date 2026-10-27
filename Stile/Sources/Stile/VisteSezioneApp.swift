import SwiftUI

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
                                Text(verbatim: "\(indice + 1)")
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
                    Label {
                        Text(String(localized: "Altre risposte sul sito", bundle: .stile))
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
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

    private var descrizioneVuota: Bool {
        descrizione.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sull'accento chiaro il bianco di `.borderedProminent` non si legge (1,7:1): testo scuro, come «Collega».
    private var colorePulsante: Color {
        descrizioneVuota ? Tema.testoSecondario : Tema.fondo
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
                Text(String(localized: "Cosa è successo? Cosa stavi facendo?", bundle: .stile))
                    .fontWeight(.semibold)
                    .foregroundStyle(Tema.testo)
                TextEditor(text: $descrizione)
                    .focused($scrivendo)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tema.lineaTenue))
                    .accessibilityLabel(Text(String(localized: "Descrizione del problema", bundle: .stile)))

                Toggle(isOn: $includiDati) { Text(String(localized: "Includi i dati tecnici", bundle: .stile)) }
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
                            Label {
                                Text(String(localized: "Invia per email", bundle: .stile))
                            } icon: {
                                Image(systemName: "envelope")
                            }
                                .foregroundStyle(colorePulsante)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ShareLink(item: testo, subject: Text(SegnalazioneBug.oggetto)) {
                            Label {
                                Text(String(localized: "Invia la segnalazione", bundle: .stile))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                                .foregroundStyle(colorePulsante)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tema.ciano)
                .disabled(descrizioneVuota)

                Text(String(localized: "Nessun video e nessuna immagine vengono inviati: solo il testo qui sopra.", bundle: .stile))
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        // La tastiera si apre subito e copre «Invia»: scorrendo la pagina si chiude.
        .scrollDismissesKeyboard(.interactively)
        .background(Tema.fondo)
        .onAppear { scrivendo = true }
    }
}
