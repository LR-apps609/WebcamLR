import SwiftUI

/// La guida: una sezione dopo l'altra, con i passi numerati.
public struct VistaGuida: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spazi.largo) {
                ForEach(Guida.sezioni) { sezione in
                    VStack(alignment: .leading, spacing: Spazi.stretto) {
                        Label(sezione.titolo, systemImage: sezione.simbolo)
                            .font(.stile(.titolo))
                            .foregroundStyle(Tema.testo)
                        ForEach(Array(sezione.passi.enumerated()), id: \.offset) { indice, passo in
                            HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
                                Text(verbatim: "\(indice + 1)")
                                    .font(.stile(.numeri))
                                    .foregroundStyle(Tema.accento)
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
                .buttonStyle(StileLink())
            }
            // Testo nostro in Barlow (Documenti/Stile.md, «Barlow o sistema»).
            .font(.stile(.corpo))
            .padding(Spazi.largo)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(Tema.fondo)
    }
}

/// «Segnala un bug»: descrizione e dati tecnici già pronti, poi mail (se c'è l'indirizzo) o condivisione.
/// La descrizione resta nelle preferenze finché non si invia (passo 9): chiudere la finestra o il foglio non la perde.
public struct ModuloSegnalazione: View {
    /// Le chiavi in UserDefaults (le stesse su Mac e iPhone).
    public enum Chiavi {
        /// Il testo scritto e non ancora inviato.
        public static let bozza = "bozzaSegnalazione"
        /// Vero dopo «Invia»: alla prossima apertura la bozza riparte vuota. Il testo resta visibile finché il
        /// modulo è aperto, se l'invio è stato annullato.
        public static let bozzaInviata = "bozzaSegnalazioneInviata"
        /// L'interruttore «Includi il registro del collegamento», acceso di serie.
        public static let includiRegistro = "segnalazioneConRegistro"
    }

    let datiTecnici: [(String, String)]
    let registro: String?
    @AppStorage(Chiavi.bozza) private var descrizione = ""
    @AppStorage(Chiavi.bozzaInviata) private var bozzaInviata = false
    @AppStorage(Chiavi.includiRegistro) private var includiRegistro = true
    @State private var includiDati = true
    @FocusState private var scrivendo: Bool
    @Environment(\.openURL) private var apriIndirizzo

    /// `datiTecnici`: coppie nome-valore che l'app conosce (versione, sistema, latenza…), mai dati personali.
    /// `registro`: il registro del collegamento come testo, una riga per evento con l'ora (passo 9); nil se l'app
    /// non ne ha uno da allegare.
    public init(datiTecnici: [(String, String)], registro: String? = nil) {
        self.datiTecnici = datiTecnici
        self.registro = registro
    }

    private var testo: String {
        SegnalazioneBug.testo(descrizione: descrizione, datiTecnici: includiDati ? datiTecnici : nil,
                              registro: includiDati && includiRegistro ? registro : nil)
    }

    /// Dopo «Invia» la bozza ha fatto il suo lavoro: si svuota alla prossima apertura del modulo.
    private func segnaInviata() {
        bozzaInviata = true
    }

    private var descrizioneVuota: Bool {
        descrizione.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            VStack(alignment: .leading, spacing: Spazi.medio) {
                Text(String(localized: "Cosa è successo? Cosa stavi facendo?", bundle: .stile))
                    .font(.stile(.corpo, .corpoForte))
                    .foregroundStyle(Tema.testo)
                TextEditor(text: $descrizione)
                    .focused($scrivendo)
                    .scrollContentBackground(.hidden)
                    .padding(Spazi.stretto)
                    .frame(minHeight: 140)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                    .overlay(RoundedRectangle(cornerRadius: Raggi.controllo).stroke(Tema.lineaTenue))
                    .accessibilityLabel(Text(String(localized: "Descrizione del problema", bundle: .stile)))

                Toggle(isOn: $includiDati) { Text(String(localized: "Includi i dati tecnici", bundle: .stile)) }
                    .tint(Tema.accento)
                if registro != nil {
                    Toggle(isOn: $includiRegistro) {
                        Text(String(localized: "Includi il registro del collegamento (ultimi 50 eventi)", bundle: .stile))
                    }
                    .tint(Tema.accento)
                    .disabled(!includiDati)
                }
                if includiDati {
                    VStack(alignment: .leading, spacing: Spazi.minimo) {
                        ForEach(datiTecnici, id: \.0) { nome, valore in
                            HStack {
                                Text(nome).foregroundStyle(Tema.testoSecondario)
                                Spacer()
                                Text(valore).font(.stile(.numeri)).foregroundStyle(Tema.testoTenue)
                            }
                        }
                    }
                    .font(.stile(.nota))
                    .padding(Spazi.piccolo)
                    .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                }

                Group {
                    if let indirizzoMail {
                        Button {
                            segnaInviata()
                            apriIndirizzo(indirizzoMail)
                        } label: {
                            Label {
                                Text(String(localized: "Invia per email", bundle: .stile))
                            } icon: {
                                Image(systemName: "envelope")
                            }
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ShareLink(item: testo, subject: Text(SegnalazioneBug.oggetto)) {
                            Label {
                                Text(String(localized: "Invia la segnalazione", bundle: .stile))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                                .frame(maxWidth: .infinity)
                        }
                        // ShareLink non dice com'è andata: il tocco basta per segnare la bozza come inviata.
                        .simultaneousGesture(TapGesture().onEnded { segnaInviata() })
                    }
                }
                .buttonStyle(StilePrimario())
                .disabled(descrizioneVuota)

                Text(String(localized: "Nessun video e nessuna immagine vengono inviati: solo il testo qui sopra.", bundle: .stile))
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
            }
            .font(.stile(.corpo))
            .padding(Spazi.largo)
            .frame(maxWidth: 640, alignment: .leading)
        }
        // La tastiera si apre subito e copre «Invia»: scorrendo la pagina si chiude.
        .scrollDismissesKeyboard(.interactively)
        .background(Tema.fondo)
        .onAppear {
            if bozzaInviata {
                descrizione = ""
                bozzaInviata = false
            }
            scrivendo = true
        }
        // Si riscrive dopo l'invio (annullato o no): è di nuovo una bozza da tenere.
        .onChange(of: descrizione) { if bozzaInviata { bozzaInviata = false } }
    }
}
