// Collaudo t03 (Davide, streamer): sull'iPhone, che cosa dice l'app su qualità, Pro, 4K, 60 fps e HEVC senza un
// computer collegato. La presentazione («Diretta: movimento fluido a 60 fps»), le Impostazioni (riga «Qualità»),
// la pagina WebcamLR Pro e le domande frequenti cercando «4K», «60» e «HEVC».

import XCTest

final class CopioneT03Davide: CopioneCollaudo {

    /// La terza pagina della presentazione con il profilo «Diretta» toccato: che cosa promette.
    @MainActor func test01_presentazioneDiretta() {
        permessi = .concedi
        avviaPulito()
        attendi("presentazione.avanti.webcam")
        tocca("presentazione.avanti.webcam")
        tocca("presentazione.avanti.computer")
        aspettaUnPo(1)
        fotografa("presentazione impostazioni")
        if tocca("presentazione.profilo.diretta") {
            aspettaUnPo(1)
            fotografa("presentazione profilo diretta")
            nota("Profilo Diretta toccato: «Movimento fluido a 60 fps» c'è? \(esiste("60 fps"))")
        }
    }

    /// Impostazioni senza computer: la riga «Qualità», la pagina Pro, le domande su 4K, 60 fps e HEVC.
    @MainActor func test02_qualitaEPro() {
        permessi = .concedi
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        fotografa("principale")
        tocca("Impostazioni")
        attendi("Fine")
        fotografa("impostazioni")
        if let riga = trova("Qualità", secondi: 3) {
            nota("Riga Qualità: label «\(riga.label)» valore «\(String(describing: riga.value ?? ""))»")
        } else {
            nota("Riga «Qualità» non trovata nelle Impostazioni")
        }
        nota("Nota sotto Video: «Si sceglie sul computer quando colleghi il telefono.» c'è? \(esiste("Si sceglie sul computer"))")

        if tocca("WebcamLR Pro") {
            aspettaUnPo(3)
            fotografa("pro")
            nota("Pagina Pro: «1080p e 4K, fino a 60 fps (il 4K a 30)» c'è? \(esiste("il 4K a 30"))")
            scorri(giu: true)
            fotografa("pro in fondo")
            indietro()
        }

        if tocca("App e assistenza") {
            if tocca("Domande frequenti") {
                aspettaUnPo(1)
                fotografa("domande frequenti")
                for parola in ["4K", "60 fps", "HEVC", "OBS"] {
                    scrivi(parola, nelCampo: "Cerca tra le domande")
                    aspettaUnPo(1.5)
                    fotografa("domande cerca \(parola)")
                    let risultati = app.buttons.allElementsBoundByIndex.prefix(12).map { $0.label }.filter { !$0.isEmpty }
                    nota("Ricerca «\(parola)»: \(risultati.joined(separator: " | "))")
                    let campo = app.searchFields.firstMatch
                    if campo.exists {
                        let cancella = campo.buttons.firstMatch
                        if cancella.exists { cancella.tap() }
                    }
                }
                // La domanda sulla qualità aperta, se c'è.
                scrivi("4K", nelCampo: "Cerca tra le domande")
                aspettaUnPo(1)
                if let prima = app.buttons.allElementsBoundByIndex.first(where: { $0.label.localizedCaseInsensitiveContains("qualità") || $0.label.localizedCaseInsensitiveContains("nero") }) {
                    nota("Apro la domanda «\(prima.label)»")
                    prima.tap()
                    aspettaUnPo(1.5)
                    fotografa("domanda aperta 4K")
                }
            }
        }
    }
}
