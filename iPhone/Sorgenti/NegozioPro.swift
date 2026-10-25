import Foundation
import Observation
import Stile
import StoreKit
import WebcamLRProtocollo

/// WebcamLR Pro con StoreKit 2: un acquisto non consumabile (`it.lrapps.webcamlr.pro`), senza account, condiviso
/// In famiglia. L'iPhone è l'unica fonte di verità: la sessione lo dice al computer con `capacita.pro` e la rimanda
/// a ogni cambiamento (notifica `NegozioPro.cambiato`).
///
/// - Diritti: `Transaction.currentEntitlements`, solo transazioni verificate (`VerificationResult.verified`) e non
///   revocate. Un rimborso o la fine della condivisione In famiglia arrivano da `Transaction.updates`.
/// - L'ultimo stato si tiene in `UserDefaults` solo per partire subito con quello giusto (niente 720p per un attimo
///   a chi ha Pro): appena StoreKit risponde vale la sua lettura.
/// - `originalID` della transazione resta salvato sul telefono: servirà per collegare il Pro a un account
///   facoltativo più avanti (Documenti/Registro lavori.md, 25 ottobre).
/// - Il prezzo non è mai scritto nel codice: `prodotto.displayPrice` (con il prezzo di lancio, se c'è).
@Observable
@MainActor
final class NegozioPro {
    static let condiviso = NegozioPro()
    static let idProdotto = ConfrontoPro.idProdotto
    /// Pro sbloccato o tolto: la sessione rimanda `capacita` e adegua formati ed effetti.
    static let cambiato = Notification.Name("it.lrapps.webcamlr.proCambiato")

    enum Operazione: Equatable {
        case nessuna
        case acquisto
        case ripristino
    }

    private enum Chiave {
        static let attivo = "pro.attivo"
        static let idTransazioneOriginale = "pro.idTransazioneOriginale"
    }

    /// WebcamLR Pro è sbloccato su questo telefono (acquisto proprio o In famiglia).
    private(set) var attivo: Bool
    /// Il prodotto letto dall'App Store (o dal file StoreKit in Xcode); `nil` finché non arriva.
    private(set) var prodotto: Product?
    private(set) var caricamentoProdotto = false
    /// L'App Store non ha risposto o non conosce il prodotto: «Riprova».
    private(set) var prodottoNonTrovato = false
    private(set) var operazione: Operazione = .nessuna
    /// Acquisto in attesa di approvazione («Chiedi di acquistare» In famiglia, o un pagamento da confermare).
    private(set) var inAttesa = false
    /// Una frase per l'utente dopo un acquisto o un ripristino non riusciti.
    private(set) var avviso: String?
    /// StoreKit ha già detto almeno una volta quali diritti ci sono.
    private(set) var dirittiLetti = false
    /// Da dove viene il Pro: acquisto proprio o condiviso In famiglia.
    private(set) var condivisoInFamiglia = false

    @ObservationIgnored private var ascolto: Task<Void, Never>?

    private init() {
        attivo = UserDefaults.standard.bool(forKey: Chiave.attivo)
    }

    /// L'identificativo originale dell'acquisto (StoreKit `originalID`), per un account futuro.
    var idTransazioneOriginale: String? {
        UserDefaults.standard.string(forKey: Chiave.idTransazioneOriginale)
    }

    /// All'apertura dell'app (`WebcamLRApp`): ascolta gli aggiornamenti delle transazioni, legge i diritti e il prodotto.
    func avvia() {
        guard ascolto == nil else { return }
        // Acquisti fatti altrove (In famiglia, un altro iPhone, «Chiedi di acquistare» approvato), rimborsi e revoche.
        ascolto = Task { [weak self] in
            for await risultato in Transaction.updates {
                guard let self else { return }
                await self.gestisci(risultato)
            }
        }
        Task {
            await aggiornaDiritti()
            await caricaProdotto()
        }
    }

    /// Rilegge i diritti attuali: vero se c'è una transazione verificata e non revocata di WebcamLR Pro.
    func aggiornaDiritti() async {
        var trovata: Transaction?
        for await risultato in Transaction.currentEntitlements {
            guard case .verified(let transazione) = risultato,
                  transazione.productID == Self.idProdotto,
                  transazione.revocationDate == nil else { continue }
            trovata = transazione
        }
        dirittiLetti = true
        if let trovata {
            salvaOriginale(trovata)
            condivisoInFamiglia = trovata.ownershipType == .familyShared
            inAttesa = false
        } else {
            condivisoInFamiglia = false
        }
        imposta(trovata != nil)
    }

    /// Legge il prodotto (nome e prezzo nella valuta dell'utente). Senza rete si può riprovare.
    func caricaProdotto() async {
        guard prodotto == nil, !caricamentoProdotto else { return }
        caricamentoProdotto = true
        prodottoNonTrovato = false
        do {
            let prodotti = try await Product.products(for: [Self.idProdotto])
            prodotto = prodotti.first
        } catch {
            prodotto = nil
        }
        prodottoNonTrovato = prodotto == nil
        caricamentoProdotto = false
    }

    /// «Sblocca Pro»: il foglio di acquisto di Apple.
    func compra() async {
        guard let prodotto, operazione == .nessuna else { return }
        operazione = .acquisto
        avviso = nil
        do {
            let risultato = try await prodotto.purchase()
            switch risultato {
            case .success(let verifica):
                switch verifica {
                case .verified(let transazione):
                    await transazione.finish()
                    inAttesa = false
                    await aggiornaDiritti()
                case .unverified:
                    avviso = String(localized: "L'acquisto non si è potuto verificare. Riprova più tardi o tocca «Ripristina acquisti».")
                }
            case .pending:
                inAttesa = true
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            avviso = String(localized: "Acquisto non riuscito. Controlla la connessione e riprova.")
        }
        operazione = .nessuna
    }

    /// «Ripristina acquisti»: chiede all'App Store le transazioni di questo Apple ID (può chiedere la password).
    func ripristina() async {
        guard operazione == .nessuna else { return }
        operazione = .ripristino
        avviso = nil
        var annullato = false
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            annullato = true
        } catch {
            avviso = String(localized: "Ripristino non riuscito. Controlla la connessione e riprova.")
        }
        await aggiornaDiritti()
        if !attivo && avviso == nil && !annullato {
            avviso = String(localized: "Nessun acquisto di WebcamLR Pro per questo Apple ID.")
        }
        operazione = .nessuna
    }

    // MARK: - Interni

    private func gestisci(_ risultato: VerificationResult<Transaction>) async {
        // Le transazioni non verificate non sbloccano nulla, ma i diritti si rileggono comunque.
        if case .verified(let transazione) = risultato {
            await transazione.finish()
        }
        await aggiornaDiritti()
    }

    private func salvaOriginale(_ transazione: Transaction) {
        let id = String(transazione.originalID)
        if UserDefaults.standard.string(forKey: Chiave.idTransazioneOriginale) != id {
            UserDefaults.standard.set(id, forKey: Chiave.idTransazioneOriginale)
        }
    }

    private func imposta(_ nuovo: Bool) {
        if UserDefaults.standard.bool(forKey: Chiave.attivo) != nuovo {
            UserDefaults.standard.set(nuovo, forKey: Chiave.attivo)
        }
        guard nuovo != attivo else { return }
        attivo = nuovo
        RegistroCollegamento.condiviso.aggiungi(nuovo ? "WebcamLR Pro attivo" : "WebcamLR Pro non attivo")
        NotificationCenter.default.post(name: Self.cambiato, object: nil)
    }
}

/// I limiti della versione gratuita, applicati dalla sessione quando Pro non c'è (Documenti/Protocollo.md, «WebcamLR Pro»).
enum LimitiGratis {
    /// 720p a 30 fps: 1080p, 4K e 60 fps sono di WebcamLR Pro.
    static let larghezza: Int32 = 1280
    static let altezza: Int32 = 720
    static let fps = 30

    /// `capacita.formati` senza Pro: solo fino a 720p, al massimo a 30 fps.
    static func formati(_ formati: [FormatoSupportato]) -> [FormatoSupportato] {
        formati
            .filter { max($0.larghezza, $0.altezza) <= Int(larghezza) }
            .map { FormatoSupportato(larghezza: $0.larghezza, altezza: $0.altezza, fpsMassimo: min($0.fpsMassimo, fps)) }
    }

    /// Un `comando` senza i campi che accenderebbero una funzione Pro: filtri, regolazioni, sfondo sostituito,
    /// ritocco, inquadratura automatica, scritta, volto e scrivania, ISO, tempo e bianco manuali. Spegnere (filtro
    /// `naturale`, valori a 0, scritta vuota, `false`) resta sempre possibile; tutto il resto passa com'è.
    static func soloGratis(_ ricevuto: Comando) -> Comando {
        var comando = ricevuto
        if let filtro = comando.filtro, filtro != Filtri.naturale { comando.filtro = nil }
        if let regolazioni = comando.regolazioni,
           [regolazioni.luminosita, regolazioni.contrasto, regolazioni.saturazione, regolazioni.nitidezza]
            .contains(where: { ($0 ?? 0) != 0 }) {
            comando.regolazioni = nil
        }
        if comando.sfondo == ModiSfondo.sostituito { comando.sfondo = nil }
        if let pelle = comando.pelle, pelle > 0 { comando.pelle = nil }
        if comando.inquadratura == true { comando.inquadratura = nil }
        if let scritta = comando.scritta, !scritta.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            comando.scritta = nil
        }
        if comando.doppiaVista == true { comando.doppiaVista = nil }
        if let iso = comando.iso, iso != 0 { comando.iso = nil }
        if let tempo = comando.tempo, tempo != 0 { comando.tempo = nil }
        if let bianco = comando.bianco, bianco != 0 { comando.bianco = nil }
        return comando
    }
}
