import SwiftUI

/// Finestra del ricevitore (bozza grafica, Mac 1): telefoni e uscite, anteprima, controlli.
struct ContenutoPrincipale: View {
    let annuncio: AnnuncioInRete
    let fotocamera: AttivazioneFotocamera

    var body: some View {
        HStack(spacing: 0) {
            barraLaterale
                .frame(width: 250)
                .background(Tema.barraLaterale)
            Divider()
            anteprima
                .frame(maxWidth: .infinity)
            Divider()
            controlli
                .frame(width: 280)
                .background(Tema.barraLaterale)
        }
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
    }

    private var barraLaterale: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                TitoloSezione("Telefoni")
                Text(testoAnnuncio)
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                TitoloSezione("Uscite")
                RigaUscita(nome: "Webcam virtuale", stato: testoFotocamera, attiva: fotocamera.stato == .attiva)
                if !fotocamera.disponibile {
                    Text("Serve l'account sviluppatore Apple: arriverà con il round 2.")
                        .font(.callout)
                        .foregroundStyle(Tema.testoSecondario)
                        .padding(.horizontal, 8)
                } else if fotocamera.stato != .attiva {
                    Button("Attiva la webcam virtuale") { fotocamera.attiva() }
                        .disabled(fotocamera.stato == .inCorso)
                        .padding(.horizontal, 8)
                }
                if case .errore(let spiegazione) = fotocamera.stato {
                    Text(spiegazione)
                        .font(.callout)
                        .foregroundStyle(Tema.ambra)
                        .padding(.horizontal, 8)
                }
                RigaUscita(nome: "Microfono virtuale", stato: "dal round 5", attiva: false)
            }
            Spacer()
            Text("Nelle app scegli **WebcamLR** come videocamera e microfono.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
                .padding(10)
                .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var anteprima: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.black)
                VStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 36))
                        .foregroundStyle(Tema.testoSecondario)
                    Text("Apri WebcamLR sull'iPhone e scegli questo Mac")
                        .foregroundStyle(Tema.testoSecondario)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("Nessun telefono collegato")
                Spacer()
            }
            .font(Tema.numeri)
            .foregroundStyle(Tema.testoSecondario)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .padding(16)
    }

    private var controlli: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fotocamera")
                .font(.title2.weight(.bold))
            Text("I controlli si attivano quando un telefono è collegato (round 4).")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var testoAnnuncio: String {
        switch annuncio.stato {
        case .fermo: "Non visibile in rete"
        case .visibile(let porta): "Visibile in rete · porta \(porta)"
        case .errore(let descrizione): "Errore di rete: \(descrizione)"
        }
    }

    private var testoFotocamera: String {
        guard fotocamera.disponibile else { return "non inclusa" }
        return switch fotocamera.stato {
        case .nonAttiva: "spenta"
        case .inCorso: "attivazione…"
        case .daApprovare: "da approvare in Impostazioni di Sistema"
        case .riavvioNecessario: "riavvia il Mac"
        case .attiva: "attiva"
        case .errore: "non attivata"
        }
    }
}

private struct TitoloSezione: View {
    let testo: String
    init(_ testo: String) { self.testo = testo }

    var body: some View {
        Text(testo.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Tema.testoSecondario)
            .padding(.horizontal, 8)
    }
}

private struct RigaUscita: View {
    let nome: String
    let stato: String
    let attiva: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attiva ? "checkmark" : "minus")
                .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                .frame(width: 16)
            Text(nome)
            Spacer()
            Text(stato)
                .font(.caption)
                .foregroundStyle(Tema.testoSecondario)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
    }
}
