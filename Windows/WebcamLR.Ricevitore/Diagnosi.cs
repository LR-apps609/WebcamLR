namespace WebcamLR.Ricevitore;

/// <summary>Il profilo che Windows dà alla rete del PC.</summary>
public enum ProfiloRete
{
    Sconosciuto,
    Pubblica,
    Privata,
    Dominio,
}

/// <summary>Cosa dice il firewall di Windows di WebcamLR sulla rete attuale.</summary>
public enum StatoFirewall
{
    Sconosciuto,
    Spento,
    Consentito,
    Bloccato,
    RegolaMancante,
}

/// <summary>Quello che il PC sa di sé quando nessun telefono si collega.</summary>
/// <param name="Profilo">Il profilo delle reti del PC, senza quella del Tethering USB (vedi <see cref="Diagnosi.Riassumi(IEnumerable{ReteCollegata})"/>).</param>
/// <param name="Cavo">Null finché il servizio di Apple (cavo dell'iPhone) non è stato cercato.</param>
/// <param name="ProfiloTethering">Il profilo della rete del Tethering USB di Android; null se non c'è.</param>
public sealed record SituazioneRete(bool HaRete, ProfiloRete Profilo, StatoFirewall Firewall, StatoCavo? Cavo, bool IPhoneAlCavo,
    ProfiloRete? ProfiloTethering = null);

/// <summary>Una rete collegata come la vede Windows: il profilo, e se passa dal Tethering USB di un telefono Android.</summary>
public sealed record ReteCollegata(ProfiloRete Profilo, bool TetheringUsb = false);

/// <summary>
/// Un pulsante della diagnosi: testo e indirizzo da aprire (impostazioni di Windows, Microsoft Store), oppure
/// <see cref="Diagnosi.SistemaFirewall"/>, che l'app fa da sé.
/// </summary>
public sealed record AzioneDiagnosi(string Testo, string Indirizzo);

/// <summary>Una causa con la sua azione (Glossario: ogni errore dice cosa fare) e la risposta nelle domande frequenti.</summary>
/// <param name="Grave">Vero se impedisce il collegamento; falso per i suggerimenti (per esempio il cavo).</param>
/// <param name="Breve">Il titolo corto per la pillola del telefono nella vista Essenziale; null: <paramref name="Titolo"/>.</param>
public sealed record ProblemaCollegamento(string Id, string Titolo, string Messaggio, string IdDomanda, AzioneDiagnosi? Azione, bool Grave,
    string? Breve = null)
{
    public string TitoloBreve => Breve ?? Titolo;
}

/// <summary>Dove si risolve un problema mostrato nella pillola del telefono: la pagina del pannello Impostazioni.</summary>
public enum PaginaProblema
{
    /// <summary>Rete, firewall: «Telefoni», con la diagnosi e il QR.</summary>
    Telefoni,
    /// <summary>La webcam per le altre app (privacy della fotocamera, webcam da riparare): «Uscite».</summary>
    Uscite,
}

/// <summary>Il problema da mostrare nella pillola del telefono (passo 7, windows.md 2.3): titolo corto e pagina giusta.</summary>
public sealed record ProblemaInPillola(string Titolo, PaginaProblema Pagina);

/// <summary>
/// Diagnosi automatica (aggiornamento 1.3): perché nessun telefono si collega e cosa fare.
/// Pura logica, provata con i test; i dati veri li raccoglie l'app (profilo della rete, regole del firewall, cavo).
/// </summary>
public static class Diagnosi
{
    public const string ImpostazioniRete = "ms-settings:network-status";
    public const string ImpostazioniWiFi = "ms-settings:network-wifi";
    /// <summary>La rete del Tethering USB compare in Windows come una rete Ethernet.</summary>
    public const string ImpostazioniEthernet = "ms-settings:network-ethernet";
    public const string Firewall = "windowsdefender://network/";
    /// <summary>
    /// «Sistema» (passo 7, windows.md 2.4): non un indirizzo, ma la regola del firewall scritta dall'app con
    /// WebcamLR.Webcam.Installa.exe, con il permesso dell'amministratore, come «Installa la webcam».
    /// </summary>
    public const string SistemaFirewall = "webcamlr:sistema-firewall";

    /// <summary>I problemi trovati, i più gravi per primi; vuoto se non c'è nulla da dire.</summary>
    public static IReadOnlyList<ProblemaCollegamento> Problemi(SituazioneRete situazione)
    {
        var problemi = new List<ProblemaCollegamento>();
        if (!situazione.HaRete)
        {
            problemi.Add(new("senza-rete", TestiRicevitore.T("Diagnosi_SenzaReteTitolo"), TestiRicevitore.T("Diagnosi_SenzaRete"),
                "cavo", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_ApriWiFi"), ImpostazioniWiFi), Grave: true));
        }
        else
        {
            if (situazione.ProfiloTethering == ProfiloRete.Pubblica)
            {
                // Il Tethering USB di Android crea una rete nuova, che Windows fa nascere pubblica: il PC resta nascosto
                // proprio sul cavo. Va resa privata quella rete, anche se il Wi-Fi è già privato.
                problemi.Add(new("tethering-pubblica", TestiRicevitore.T("Diagnosi_TetheringPubblicaTitolo"), TestiRicevitore.T("Diagnosi_TetheringPubblica"),
                    "firewall", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_ApriEthernet"), ImpostazioniEthernet), Grave: true));
            }
            if (situazione.Profilo == ProfiloRete.Pubblica)
            {
                // Su una rete pubblica il firewall non conta: la soluzione è rendere la rete privata.
                problemi.Add(new("rete-pubblica", TestiRicevitore.T("Diagnosi_RetePubblicaTitolo"), TestiRicevitore.T("Diagnosi_RetePubblica"),
                    "firewall", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_ApriRete"), ImpostazioniRete), Grave: true,
                    Breve: TestiRicevitore.T("Diagnosi_RetePubblicaBreve")));
            }
            else if (situazione.Firewall == StatoFirewall.Bloccato)
            {
                // Una regola che blocca vince su una che consente: qui «Sistema» non basterebbe, si apre il firewall.
                problemi.Add(new("firewall-bloccato", TestiRicevitore.T("Diagnosi_FirewallBloccaTitolo"), TestiRicevitore.T("Diagnosi_FirewallBlocca"),
                    "firewall", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_ApriFirewall"), Firewall), Grave: true,
                    Breve: TestiRicevitore.T("Diagnosi_FirewallBreve")));
            }
            else if (situazione.Firewall == StatoFirewall.RegolaMancante)
            {
                // Manca solo la regola: «Sistema» la scrive (WebcamLR.Webcam.Installa.exe firewall, da amministratore).
                problemi.Add(new("firewall-mancante", TestiRicevitore.T("Diagnosi_FirewallMancaTitolo"), TestiRicevitore.T("Diagnosi_FirewallManca"),
                    "firewall", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_SistemaFirewall"), SistemaFirewall), Grave: true,
                    Breve: TestiRicevitore.T("Diagnosi_FirewallBreve")));
            }
        }

        if (situazione.IPhoneAlCavo && situazione.Cavo != StatoCavo.Collegato)
        {
            problemi.Add(new("iphone-al-cavo", TestiRicevitore.T("Diagnosi_IPhoneAlCavoTitolo"), TestiRicevitore.T("Diagnosi_IPhoneAlCavo"),
                "cavo", null, Grave: false));
        }
        else if (situazione.Cavo == StatoCavo.ServizioAssente)
        {
            problemi.Add(new("servizio-assente", TestiRicevitore.T("Collegamento_CavoUsb"), InfoApp.SuggerimentoCavo,
                "cavo", new AzioneDiagnosi(TestiRicevitore.T("Diagnosi_ApriStore"), InfoApp.DispositiviApple), Grave: false));
        }
        return problemi;
    }

    /// <summary>
    /// Passo 7 (windows.md 2.3): nella vista Essenziale la colonna di sinistra non c'è, e con lei la diagnosi. La pillola
    /// del telefono prende allora il punto ambra e il titolo del problema più grave, e un clic apre la pagina giusta.
    /// Senza telefono contano la rete e il firewall; sempre, la webcam per le altre app (privacy o da riparare), che con
    /// un telefono collegato è il problema che resta. Null se non c'è niente da dire.
    /// </summary>
    public static ProblemaInPillola? PerPillola(IReadOnlyList<ProblemaCollegamento> problemi, bool senzaTelefono,
        bool fotocameraNegata, bool webcamDaRiparare)
    {
        if (senzaTelefono && problemi.FirstOrDefault(p => p.Grave) is { } grave)
            return new(grave.TitoloBreve, PaginaProblema.Telefoni);
        if (fotocameraNegata) return new(TestiRicevitore.T("Diagnosi_FotocameraNegataBreve"), PaginaProblema.Uscite);
        if (webcamDaRiparare) return new(TestiRicevitore.T("Diagnosi_WebcamDaRiparareBreve"), PaginaProblema.Uscite);
        return null;
    }

    /// <summary>
    /// Le reti collegate divise in due: il profilo delle reti normali (Wi-Fi, cavo di rete), riassunto come sotto,
    /// e quello della rete del Tethering USB di Android, guardata a parte: è lì che arriva il telefono sul cavo,
    /// e una rete privata accanto non la rende raggiungibile. Il secondo è null senza tethering, «Pubblica»
    /// se almeno una rete del tethering è pubblica.
    /// </summary>
    public static (ProfiloRete Profilo, ProfiloRete? Tethering) Riassumi(IEnumerable<ReteCollegata> reti)
    {
        var elenco = reti.ToList();
        var tethering = elenco.Where(r => r.TetheringUsb).Select(r => r.Profilo).ToList();
        ProfiloRete? profiloTethering = tethering.Count == 0 ? null
            : tethering.Contains(ProfiloRete.Pubblica) ? ProfiloRete.Pubblica : Riassumi(tethering);
        return (Riassumi(elenco.Where(r => !r.TetheringUsb).Select(r => r.Profilo)), profiloTethering);
    }

    /// <summary>
    /// Il profilo delle reti collegate, riassunto: «Pubblica» solo se nessuna è privata o di dominio
    /// (le schede virtuali, come quelle di Hyper-V, sono spesso pubbliche anche a casa).
    /// </summary>
    public static ProfiloRete Riassumi(IEnumerable<ProfiloRete> profili)
    {
        var elenco = profili.Where(p => p != ProfiloRete.Sconosciuto).ToList();
        if (elenco.Contains(ProfiloRete.Privata)) return ProfiloRete.Privata;
        if (elenco.Contains(ProfiloRete.Dominio)) return ProfiloRete.Dominio;
        return elenco.Count > 0 ? ProfiloRete.Pubblica : ProfiloRete.Sconosciuto;
    }
}

/// <summary>
/// Le regole del firewall di Windows come le salva il sistema nel registro
/// (FirewallPolicy\FirewallRules: «v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|Profile=Private|App=…|Name=…|»).
/// </summary>
public static class RegoleFirewall
{
    /// <summary>I campi di una regola; un campo ripetuto (Profile) tiene tutti i valori.</summary>
    public static Dictionary<string, List<string>> Campi(string regola)
    {
        var campi = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var parte in regola.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            var uguale = parte.IndexOf('=');
            if (uguale <= 0) continue;
            var chiave = parte[..uguale];
            if (!campi.TryGetValue(chiave, out var valori)) campi[chiave] = valori = [];
            valori.Add(parte[(uguale + 1)..]);
        }
        return campi;
    }

    /// <summary>
    /// Cosa vale per WebcamLR in entrata (TCP) sul profilo attuale: un blocco vince su un permesso, come nel firewall.
    /// Contano le regole per il programma e quelle per la porta senza programma.
    /// </summary>
    /// <param name="attivo">Firewall acceso per quel profilo; null se non si sa.</param>
    public static StatoFirewall Valuta(IEnumerable<string> regole, string programma, int porta, ProfiloRete profilo, bool? attivo)
    {
        if (attivo == false) return StatoFirewall.Spento;
        // Profilo sconosciuto: si guarda quello privato, il caso di casa.
        var nomeProfilo = profilo switch
        {
            ProfiloRete.Pubblica => "Public",
            ProfiloRete.Dominio => "Domain",
            _ => "Private",
        };
        var consentito = false;
        foreach (var regola in regole)
        {
            var campi = Campi(regola);
            string? Uno(string chiave) => campi.TryGetValue(chiave, out var valori) ? valori[0] : null;
            if (!string.Equals(Uno("Active"), "TRUE", StringComparison.OrdinalIgnoreCase)) continue;
            if (!string.Equals(Uno("Dir"), "In", StringComparison.OrdinalIgnoreCase)) continue;
            if (Uno("Protocol") is { } protocollo && protocollo != "6") continue;
            if (campi.TryGetValue("Profile", out var profili) && !profili.Contains(nomeProfilo, StringComparer.OrdinalIgnoreCase)) continue;
            var app = Uno("App");
            var perNoi = app is not null
                ? string.Equals(Environment.ExpandEnvironmentVariables(app), programma, StringComparison.OrdinalIgnoreCase)
                : Uno("LPort") is { } porte && PortaCompresa(porte, porta);
            if (!perNoi) continue;
            if (string.Equals(Uno("Action"), "Block", StringComparison.OrdinalIgnoreCase)) return StatoFirewall.Bloccato;
            if (string.Equals(Uno("Action"), "Allow", StringComparison.OrdinalIgnoreCase)) consentito = true;
        }
        return consentito ? StatoFirewall.Consentito : StatoFirewall.RegolaMancante;
    }

    /// <summary>«52740», «52740-52750» o un elenco con le virgole.</summary>
    public static bool PortaCompresa(string porte, int porta)
    {
        foreach (var parte in porte.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var trattino = parte.IndexOf('-');
            if (trattino > 0 && int.TryParse(parte[..trattino], out var da) && int.TryParse(parte[(trattino + 1)..], out var a))
            {
                if (porta >= da && porta <= a) return true;
            }
            else if (int.TryParse(parte, out var singola) && singola == porta) return true;
        }
        return false;
    }
}
