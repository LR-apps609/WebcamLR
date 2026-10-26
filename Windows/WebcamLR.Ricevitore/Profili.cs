using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// I profili pronti del pannello «Profilo», come sul Mac (Mac/Sorgenti/Profili.swift): ognuno è un insieme di scelte
/// sensate per una situazione, mandato al telefono con un solo <c>comando</c> (gli effetti) e una richiesta di
/// <c>formato</c>. Si mandano solo le parti che il telefono dichiara in <c>capacita</c>: un telefono senza «Volto e
/// scrivania» riceve «Lezione» senza quella parte. Gli altri comandi (obiettivo, zoom, esposizione, regolazioni) restano
/// come sono. Sono di WebcamLR Pro.
/// </summary>
/// <param name="Glifo">L'icona di Segoe Fluent Icons.</param>
/// <param name="Larghezza">Il formato da chiedere, in orizzontale (in verticale i lati si scambiano).</param>
public sealed record ProfiloPronto(string Id, string Nome, string Glifo, string Descrizione,
    int Larghezza = 1920, int Altezza = 1080, int Fps = 30, bool LuceVolto = true, bool Inquadratura = false,
    bool DoppiaVista = false, string Filtro = Filtri.Naturale, string Sfondo = ModiSfondo.Nessuno,
    double IntensitaSfondo = 0.5, double Pelle = 0)
{
    /// <summary>Riunione: volto illuminato e sempre al centro, niente effetti vistosi.</summary>
    public static ProfiloPronto Riunione => new("riunione", TestiRicevitore.T("Profilo_Riunione"), "", TestiRicevitore.T("Profilo_RiunioneDescrizione"),
        Inquadratura: true);

    /// <summary>
    /// Lezione: volto e scrivania insieme, se il telefono lo sa fare; l'inquadratura resta ferma (inseguire il volto
    /// taglierebbe la lavagna o il foglio). «Volto e scrivania» porta il telefono sul Grandangolo 0,5× posteriore.
    /// </summary>
    public static ProfiloPronto Lezione => new("lezione", TestiRicevitore.T("Profilo_Lezione"), "", TestiRicevitore.T("Profilo_LezioneDescrizione"),
        DoppiaVista: true);

    /// <summary>Diretta: movimento fluido a 60 fps (se il telefono ci arriva), inquadratura ferma, luce e colori naturali.</summary>
    public static ProfiloPronto Diretta => new("diretta", TestiRicevitore.T("Profilo_Diretta"), "", TestiRicevitore.T("Profilo_DirettaDescrizione"),
        Fps: 60, LuceVolto: false);

    /// <summary>Colloquio: sfondo sfocato leggero, pelle appena curata, volto illuminato e al centro.</summary>
    public static ProfiloPronto Colloquio => new("colloquio", TestiRicevitore.T("Profilo_Colloquio"), "", TestiRicevitore.T("Profilo_ColloquioDescrizione"),
        Inquadratura: true, Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.35, Pelle: 0.2);

    /// <summary>Nella lingua attuale: nomi e descrizioni si leggono a ogni accesso.</summary>
    public static IReadOnlyList<ProfiloPronto> Tutti => [Riunione, Lezione, Diretta, Colloquio];

    public static ProfiloPronto? Cerca(string? id) => Tutti.FirstOrDefault(p => p.Id == id);

    /// <summary>Cosa fa, per l'aiuto al passaggio del puntatore.</summary>
    public string Riepilogo
    {
        get
        {
            var parti = new List<string> { $"{Altezza}p{Fps}" };
            if (LuceVolto) parti.Add(TestiRicevitore.T("Profilo_LuceVolto"));
            parti.Add(Inquadratura ? TestiRicevitore.T("Profilo_InquadraturaAutomatica") : TestiRicevitore.T("Profilo_InquadraturaFerma"));
            if (DoppiaVista) parti.Add(TestiRicevitore.T("Profilo_VoltoScrivania"));
            if (Sfondo == ModiSfondo.Sfocato) parti.Add(TestiRicevitore.T("Profilo_SfondoSfocato"));
            if (Pelle > 0) parti.Add(TestiRicevitore.T("Profilo_Pelle", Math.Round(Pelle * 100).ToString("0", System.Globalization.CultureInfo.InvariantCulture)));
            parti.Add(TestiRicevitore.T("Profilo_Filtro", NomiEffetti.Filtro(Filtro).ToLowerInvariant()));
            return string.Join(" · ", parti);
        }
    }

    /// <summary>Il <c>comando</c> con le sole parti che il telefono sa fare; null se non sa fare nessuna.</summary>
    public Comando? Comando(Capacita capacita)
    {
        var filtri = capacita.Filtri ?? [];
        var comando = new Comando(
            LuceVolto: capacita.LuceVolto == true ? LuceVolto : null,
            Inquadratura: capacita.Inquadratura == true ? Inquadratura : null,
            DoppiaVista: capacita.DoppiaVista == true ? DoppiaVista : null,
            Filtro: filtri.Contains(Filtro) ? Filtro : null,
            Sfondo: capacita.Sfondo == true ? Sfondo : null,
            IntensitaSfondo: capacita.Sfondo == true && Sfondo != ModiSfondo.Nessuno ? IntensitaSfondo : null,
            Pelle: capacita.Pelle == true ? Pelle : null);
        return RegolePro.Vuoto(comando) ? null : comando;
    }

    /// <summary>Gli effetti come diventano dopo il <c>comando</c> (solo le parti che il telefono sa fare).</summary>
    public ValoriEffetti Applica(ValoriEffetti valori, Capacita capacita) =>
        Comando(capacita) is { } comando ? valori.Applica(comando) : valori;

    /// <summary>
    /// Gli effetti del telefono sono ancora quelli del profilo? Se l'utente ne ha cambiato uno, no («Personalizzato»).
    /// Il formato non conta: il telefono può scendere da solo (caldo, rete debole) senza che l'utente cambi niente.
    /// Intensità dello sfondo e pelle con un margine: il telefono rimanda i valori con i suoi decimali.
    /// </summary>
    public bool Corrisponde(ValoriEffetti valori, Capacita capacita)
    {
        var atteso = Applica(valori, capacita);
        var vicini = Math.Abs(atteso.IntensitaSfondo - valori.IntensitaSfondo) < 0.03 && Math.Abs(atteso.Pelle - valori.Pelle) < 0.03;
        return vicini && atteso with { IntensitaSfondo = 0, Pelle = 0 } == valori with { IntensitaSfondo = 0, Pelle = 0 };
    }

    /// <summary>
    /// Il profilo che si vede scelto: quello applicato per ultimo, se gli effetti gli corrispondono ancora.
    /// <c>Personalizzato</c>: c'era un profilo, ma l'utente ha cambiato qualcosa.
    /// </summary>
    public static (ProfiloPronto? Scelto, bool Personalizzato) Stato(string? applicato, ValoriEffetti valori, Capacita? capacita)
    {
        if (Cerca(applicato) is not { } profilo) return (null, false);
        if (capacita is null) return (profilo, false);
        return profilo.Corrisponde(valori, capacita) ? (profilo, false) : (null, true);
    }

    /// <summary>
    /// «Volto e scrivania» porta il telefono sul Grandangolo 0,5× posteriore: con la frontale la persona uscirebbe dal
    /// video senza capire perché. Lo si dice.
    /// </summary>
    public string? Avviso(Capacita capacita, string? obiettivoAttuale) =>
        DoppiaVista && capacita.DoppiaVista == true && obiettivoAttuale == "frontale"
            ? TestiRicevitore.T("Profilo_AvvisoPosteriore", Nome)
            : null;
}
