using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class DiagnosiTest
{
    private static SituazioneRete TuttoAPosto => new(true, ProfiloRete.Privata, StatoFirewall.Consentito, StatoCavo.InAscolto, false);

    [Fact]
    public void NienteDaDireSeTuttoEAPosto()
    {
        Assert.Empty(Diagnosi.Problemi(TuttoAPosto));
    }

    [Fact]
    public void SenzaReteSuggerisceIlCavo()
    {
        var problema = Assert.Single(Diagnosi.Problemi(TuttoAPosto with { HaRete = false }));
        Assert.Equal("senza-rete", problema.Id);
        Assert.True(problema.Grave);
        Assert.Contains("cavo USB", problema.Messaggio);
        Assert.Equal("cavo", problema.IdDomanda);
    }

    [Fact]
    public void RetePubblicaSpiegaComeRenderlaPrivata()
    {
        // Sulla rete pubblica il firewall non si nomina: la soluzione è la rete privata.
        var problema = Assert.Single(Diagnosi.Problemi(TuttoAPosto with { Profilo = ProfiloRete.Pubblica, Firewall = StatoFirewall.RegolaMancante }));
        Assert.Equal("rete-pubblica", problema.Id);
        Assert.Contains("Privata", problema.Messaggio);
        Assert.Equal(Diagnosi.ImpostazioniRete, problema.Azione!.Indirizzo);
    }

    [Theory]
    [InlineData(StatoFirewall.Bloccato, "firewall-bloccato")]
    [InlineData(StatoFirewall.RegolaMancante, "firewall-mancante")]
    public void FirewallConLAzione(StatoFirewall firewall, string atteso)
    {
        var problema = Assert.Single(Diagnosi.Problemi(TuttoAPosto with { Firewall = firewall }));
        Assert.Equal(atteso, problema.Id);
        Assert.Equal("firewall", problema.IdDomanda);
        Assert.Equal(Diagnosi.Firewall, problema.Azione!.Indirizzo);
    }

    [Theory]
    [InlineData(StatoFirewall.Spento)]
    [InlineData(StatoFirewall.Sconosciuto)]
    public void FirewallSpentoOSconosciutoNonSiNomina(StatoFirewall firewall)
    {
        Assert.Empty(Diagnosi.Problemi(TuttoAPosto with { Firewall = firewall }));
    }

    [Fact]
    public void ServizioAppleAssenteEUnSuggerimento()
    {
        var problema = Assert.Single(Diagnosi.Problemi(TuttoAPosto with { Cavo = StatoCavo.ServizioAssente }));
        Assert.Equal("servizio-assente", problema.Id);
        Assert.False(problema.Grave);
        Assert.Equal(InfoApp.DispositiviApple, problema.Azione!.Indirizzo);
        Assert.Contains("Dispositivi Apple", problema.Messaggio);
        // Prima di aver cercato il servizio non si dice nulla.
        Assert.Empty(Diagnosi.Problemi(TuttoAPosto with { Cavo = null }));
    }

    [Fact]
    public void GraviPrimaDeiSuggerimenti()
    {
        var problemi = Diagnosi.Problemi(new SituazioneRete(false, ProfiloRete.Sconosciuto, StatoFirewall.Sconosciuto, StatoCavo.ServizioAssente, false));
        Assert.Equal(["senza-rete", "servizio-assente"], problemi.Select(p => p.Id));
    }

    [Fact]
    public void IPhoneAlCavoMaAppChiusa()
    {
        var problema = Assert.Single(Diagnosi.Problemi(TuttoAPosto with { IPhoneAlCavo = true }));
        Assert.Equal("iphone-al-cavo", problema.Id);
        Assert.Empty(Diagnosi.Problemi(TuttoAPosto with { IPhoneAlCavo = true, Cavo = StatoCavo.Collegato }));
    }

    [Fact]
    public void OgniProblemaPortaAUnaDomandaCheEsiste()
    {
        var situazioni = new[]
        {
            TuttoAPosto with { HaRete = false },
            TuttoAPosto with { Profilo = ProfiloRete.Pubblica },
            TuttoAPosto with { Firewall = StatoFirewall.Bloccato },
            TuttoAPosto with { Firewall = StatoFirewall.RegolaMancante },
            TuttoAPosto with { Cavo = StatoCavo.ServizioAssente },
            TuttoAPosto with { IPhoneAlCavo = true },
        };
        foreach (var problema in situazioni.SelectMany(Diagnosi.Problemi))
        {
            Assert.NotNull(DomandeFrequenti.Risposta(problema.IdDomanda));
            Assert.False(string.IsNullOrWhiteSpace(problema.Messaggio));
        }
    }

    [Theory]
    [InlineData(new[] { ProfiloRete.Pubblica }, ProfiloRete.Pubblica)]
    [InlineData(new[] { ProfiloRete.Pubblica, ProfiloRete.Privata }, ProfiloRete.Privata)]   // Wi-Fi privata + scheda virtuale pubblica
    [InlineData(new[] { ProfiloRete.Dominio, ProfiloRete.Pubblica }, ProfiloRete.Dominio)]
    [InlineData(new ProfiloRete[0], ProfiloRete.Sconosciuto)]
    public void ProfiloRiassunto(ProfiloRete[] profili, ProfiloRete atteso)
    {
        Assert.Equal(atteso, Diagnosi.Riassumi(profili));
    }
}

public class RegoleFirewallTest
{
    private const string Programma = @"C:\Programmi\WebcamLR\WebcamLR.exe";

    // Come le crea Windows quando l'utente sceglie «Consenti» al primo avvio: una regola TCP e una UDP.
    private const string ConsentitaPrivataTcp =
        @"v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|Profile=Private|App=C:\Programmi\WebcamLR\WebcamLR.exe|Name=webcamlr.exe|Desc=webcamlr.exe|Defer=User|";
    private const string ConsentitaPrivataUdp =
        @"v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=17|Profile=Private|App=C:\Programmi\WebcamLR\WebcamLR.exe|Name=webcamlr.exe|";
    private const string BloccataPubblica =
        @"v2.30|Action=Block|Active=TRUE|Dir=In|Protocol=6|Profile=Public|App=C:\Programmi\WebcamLR\WebcamLR.exe|Name=webcamlr.exe|";
    private const string AltroProgramma =
        @"v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|App=C:\Altro\altro.exe|Name=Altro|";

    [Fact]
    public void CampiConProfiliRipetuti()
    {
        var campi = RegoleFirewall.Campi("v2.30|Action=Allow|Profile=Private|Profile=Domain|App=C:\\a.exe|");
        Assert.Equal(["Private", "Domain"], campi["Profile"]);
        Assert.Equal("C:\\a.exe", campi["app"][0]);
    }

    [Fact]
    public void ConsentitoSullaRetePrivata()
    {
        Assert.Equal(StatoFirewall.Consentito,
            RegoleFirewall.Valuta([AltroProgramma, ConsentitaPrivataUdp, ConsentitaPrivataTcp], Programma, 52740, ProfiloRete.Privata, true));
        // Maiuscole diverse nel percorso: è lo stesso programma.
        Assert.Equal(StatoFirewall.Consentito,
            RegoleFirewall.Valuta([ConsentitaPrivataTcp], Programma.ToLowerInvariant(), 52740, ProfiloRete.Privata, null));
    }

    [Fact]
    public void BloccoVinceSulPermesso()
    {
        Assert.Equal(StatoFirewall.Bloccato,
            RegoleFirewall.Valuta([ConsentitaPrivataTcp, BloccataPubblica.Replace("Profile=Public", "Profile=Private")], Programma, 52740, ProfiloRete.Privata, true));
    }

    [Fact]
    public void RegolaMancanteSeNonCopreQuestaRete()
    {
        // Consentita solo sulle reti private, ma la rete è di dominio.
        Assert.Equal(StatoFirewall.RegolaMancante, RegoleFirewall.Valuta([ConsentitaPrivataTcp], Programma, 52740, ProfiloRete.Dominio, true));
        Assert.Equal(StatoFirewall.RegolaMancante, RegoleFirewall.Valuta([AltroProgramma, ConsentitaPrivataUdp], Programma, 52740, ProfiloRete.Privata, true));
        Assert.Equal(StatoFirewall.RegolaMancante, RegoleFirewall.Valuta([], Programma, 52740, ProfiloRete.Privata, true));
        // Regola spenta.
        Assert.Equal(StatoFirewall.RegolaMancante,
            RegoleFirewall.Valuta([ConsentitaPrivataTcp.Replace("Active=TRUE", "Active=FALSE")], Programma, 52740, ProfiloRete.Privata, true));
    }

    [Fact]
    public void RegolaSenzaProfiloValePerTutte()
    {
        var tutte = ConsentitaPrivataTcp.Replace("Profile=Private|", "");
        Assert.Equal(StatoFirewall.Consentito, RegoleFirewall.Valuta([tutte], Programma, 52740, ProfiloRete.Pubblica, true));
    }

    [Fact]
    public void RegolaPerLaPorta()
    {
        const string perPorta = "v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|Profile=Private|LPort=52740-52745|Name=WebcamLR porta|";
        Assert.Equal(StatoFirewall.Consentito, RegoleFirewall.Valuta([perPorta], Programma, 52740, ProfiloRete.Privata, true));
        Assert.Equal(StatoFirewall.RegolaMancante, RegoleFirewall.Valuta([perPorta], Programma, 60000, ProfiloRete.Privata, true));
        Assert.True(RegoleFirewall.PortaCompresa("80, 52740", 52740));
        Assert.False(RegoleFirewall.PortaCompresa("abc", 52740));
    }

    [Fact]
    public void FirewallSpento()
    {
        Assert.Equal(StatoFirewall.Spento, RegoleFirewall.Valuta([BloccataPubblica], Programma, 52740, ProfiloRete.Pubblica, false));
    }
}
