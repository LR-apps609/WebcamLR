using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// WebcamLR Pro sul PC, come sul Mac (Mac/Sorgenti/ProMac.swift): niente acquisti qui. Si compra sul telefono e il
/// telefono «nella webcam» lo dice con <c>capacita.pro</c> (Documenti/Protocollo.md, «WebcamLR Pro»). Il PC lo usa solo
/// per l'interfaccia: i limiti veri (720p a 30 fps, comandi Pro ignorati) li applica il telefono.
/// Il telefono può essere un iPhone o un Android: i testi dicono «sul telefono».
/// </summary>
public static class RegolePro
{
    public static string Sblocca => TestiRicevitore.T("Pro_Sblocca");
    public static string Strada => TestiRicevitore.T("Pro_Strada");
    public static string SecondoTelefono => TestiRicevitore.T("Pro_SecondoTelefono");
    public static string SfondoSostituito => TestiRicevitore.T("Pro_SfondoSostituito");
    public static string TitoloSecondoTelefono => TestiRicevitore.T("Pro_TitoloSecondoTelefono");

    /// <summary>Il massimo della versione gratuita: 1280×720 a 30 fps.</summary>
    public const int LatoLungoGratis = 1280, LatoCortoGratis = 720, FpsGratis = 30;

    /// <summary>Il telefono ha sbloccato Pro. Falso senza capacità o con un telefono vecchio che non manda il campo.</summary>
    public static bool Attivo(Capacita? capacita) => capacita?.Pro == true;

    /// <summary>
    /// Un telefono collegato e pronto (capacità arrivate) senza Pro: i comandi Pro si vedono con il segno «PRO», spenti.
    /// Senza telefono i comandi sono già grigi («Collega un telefono»): niente segno in più.
    /// </summary>
    public static bool Bloccato(bool telefonoCollegato, Capacita? capacita) =>
        telefonoCollegato && capacita is not null && capacita.Pro != true;

    /// <summary>Un formato che la versione gratuita manda: fino a 1280×720 (anche in verticale) a 30 fps.</summary>
    public static bool FormatoGratis(int larghezza, int altezza, int fps) =>
        Math.Max(larghezza, altezza) <= LatoLungoGratis && Math.Min(larghezza, altezza) <= LatoCortoGratis && fps <= FpsGratis;

    /// <summary>Il messaggio per il secondo telefono che non entra perché quello nella webcam è gratis.</summary>
    public static string MessaggioSecondoTelefono(string? nome) =>
        TestiRicevitore.T("Pro_MessaggioSecondoTelefono", ElencoTelefoni.NomeInFrase(nome), Strada);

    /// <summary>
    /// Il comando senza le parti che accendono qualcosa di Pro (Documenti/Protocollo.md: filtro diverso da «naturale»,
    /// regolazioni, sfondo «sostituito», pelle, inquadratura, scritta, doppia vista, ISO, tempo, bianco diverso da 0).
    /// Spegnere resta sempre possibile: filtro «naturale», bianco/ISO/tempo a 0, pelle a 0, scritta vuota, interruttori spenti.
    /// Il telefono gratis ignorerebbe comunque quelle parti: così il PC non mostra per un attimo un valore che non vale.
    /// </summary>
    public static Comando SenzaPro(Comando comando) => comando with
    {
        Filtro = comando.Filtro is { } filtro && filtro != Filtri.Naturale ? null : comando.Filtro,
        Regolazioni = comando.Regolazioni is { } r && !Neutre(r) ? null : comando.Regolazioni,
        Sfondo = comando.Sfondo == ModiSfondo.Sostituito ? null : comando.Sfondo,
        Pelle = comando.Pelle is > 0 ? null : comando.Pelle,
        Inquadratura = comando.Inquadratura == true ? null : comando.Inquadratura,
        Scritta = comando.Scritta is { } scritta && !string.IsNullOrWhiteSpace(scritta.Nome) ? null : comando.Scritta,
        DoppiaVista = comando.DoppiaVista == true ? null : comando.DoppiaVista,
        Iso = comando.Iso is > 0 ? null : comando.Iso,
        Tempo = comando.Tempo is > 0 ? null : comando.Tempo,
        Bianco = comando.Bianco is > 0 ? null : comando.Bianco,
    };

    /// <summary>Vero se il comando non porta più nessun campo (allora non si manda).</summary>
    public static bool Vuoto(Comando comando) => comando == new Comando();

    private static bool Neutre(Regolazioni r) =>
        (r.Luminosita ?? 0) == 0 && (r.Contrasto ?? 0) == 0 && (r.Saturazione ?? 0) == 0 && (r.Nitidezza ?? 0) == 0;

    /// <summary>Ciò che resta gratis, per sempre e senza filigrana (lo stesso elenco di Stile/Sources/Stile/Pro.swift).</summary>
    public static IReadOnlyList<string> Gratis =>
    [
        TestiRicevitore.T("Pro_Gratis1"),
        TestiRicevitore.T("Pro_Gratis2"),
        TestiRicevitore.T("Pro_Gratis3"),
        TestiRicevitore.T("Pro_Gratis4"),
        TestiRicevitore.T("Pro_Gratis5"),
        TestiRicevitore.T("Pro_Gratis6"),
        TestiRicevitore.T("Pro_Gratis7"),
    ];

    /// <summary>Ciò che aggiunge Pro, sul telefono e sul PC.</summary>
    public static IReadOnlyList<string> VociPro =>
    [
        TestiRicevitore.T("Pro_Voce1"),
        TestiRicevitore.T("Pro_Voce2"),
        TestiRicevitore.T("Pro_Voce3"),
        TestiRicevitore.T("Pro_Voce4"),
        TestiRicevitore.T("Pro_Voce5"),
        TestiRicevitore.T("Pro_Voce6"),
        TestiRicevitore.T("Pro_Voce7"),
        TestiRicevitore.T("Pro_Voce8"),
        TestiRicevitore.T("Pro_Voce9"),
        TestiRicevitore.T("Pro_Voce10"),
        TestiRicevitore.T("Pro_Voce11"),
        TestiRicevitore.T("Pro_Voce12"),
    ];

    /// <summary>La riga di stato della pagina «WebcamLR Pro»: il telefono nella webcam, con o senza Pro.</summary>
    public static string StatoTelefono(string? nomeTelefono, Capacita? capacita)
    {
        if (string.IsNullOrWhiteSpace(nomeTelefono) || capacita is null)
            return TestiRicevitore.T("Pro_StatoNessunTelefono");
        return Attivo(capacita) ? TestiRicevitore.T("Pro_StatoAttivo", nomeTelefono) : TestiRicevitore.T("Pro_StatoGratis", nomeTelefono);
    }
}

/// <summary>Un'opzione di «Qualità video»: risoluzione in orizzontale e fotogrammi al secondo (Mac/Sorgenti/Profili.swift).</summary>
public sealed record OpzioneQualita(int Larghezza, int Altezza, int Fps)
{
    /// <summary>«1080p · 30 fps», «4K · 30 fps», come sul Mac e sul telefono.</summary>
    public string Testo => $"{NomeRisoluzione(Altezza)} · {Fps} fps";

    /// <summary>«720p», «1080p», «4K»: gli stessi nomi del telefono (prova 2: si scriveva «2160p»).</summary>
    public static string NomeRisoluzione(int latoCorto) => latoCorto >= 2160 ? "4K" : $"{latoCorto}p";

    /// <summary>Sopra 720p a 30 fps è di WebcamLR Pro.</summary>
    public bool SoloPro => !RegolePro.FormatoGratis(Larghezza, Altezza, Fps);

    /// <summary>Il 4K (lato corto da 2160) resta a 30 fps; sotto, fino a 60 (1.14: a 60 è troppo per il Wi-Fi e scalda).</summary>
    public static int FpsMassimi(int latoCorto) => latoCorto >= 2160 ? 30 : 60;

    /// <summary>HEVC per il 4K (circa il 40% di dati in meno), altrimenti quello che arriva già.</summary>
    public static Codec CodecPer(int latoCorto, Codec? attuale) => latoCorto >= 2160 ? Codec.Hevc : attuale ?? Codec.Hevc;

    /// <summary>
    /// Dalle capacità del telefono (<c>formati</c>), 30 e 60 fps dove ci arriva; il 4K solo a 30. Senza <c>formati</c>,
    /// le tre scelte comuni: il telefono scende se non ce la fa.
    /// </summary>
    public static IReadOnlyList<OpzioneQualita> Elenco(Capacita? capacita)
    {
        if (capacita?.Formati is not { Count: > 0 } formati)
            return [new(1280, 720, 30), new(1920, 1080, 30), new(1920, 1080, 60)];
        var risultato = new List<OpzioneQualita>();
        foreach (var formato in formati)
        {
            var lungo = Math.Max(formato.Larghezza, formato.Altezza);
            var corto = Math.Min(formato.Larghezza, formato.Altezza);
            foreach (var fps in new[] { 30, 60 })
            {
                if (fps > formato.FpsMassimo || fps > FpsMassimi(corto)) continue;
                var opzione = new OpzioneQualita(lungo, corto, fps);
                if (!risultato.Contains(opzione)) risultato.Add(opzione);
            }
        }
        return [.. risultato.OrderBy(o => o.Altezza).ThenBy(o => o.Fps)];
    }

    /// <summary>
    /// Le scelte del menu: con un telefono gratis le scelte Pro non partono (il telefono non le manderebbe) e restano
    /// in fondo con «PRO», così si vede cosa sblocca. Solo quelle che il telefono sa fare (prova 2: si offriva sempre il
    /// 4K): quelle sopra 720p a 30 che dichiara in <c>formati</c>; gratis però dichiara solo fino a 720p a 30
    /// (Documenti/Protocollo.md), e allora le scelte comuni 1080p a 30 e a 60, senza il 4K che non ha dichiarato.
    /// </summary>
    public static (IReadOnlyList<OpzioneQualita> Libere, IReadOnlyList<OpzioneQualita> Bloccate) Menu(Capacita? capacita, bool bloccoPro)
    {
        var tutte = Elenco(capacita);
        if (!bloccoPro) return (tutte, []);
        var libere = tutte.Where(o => !o.SoloPro).ToList();
        var bloccate = tutte.Where(o => o.SoloPro).ToList();
        if (bloccate.Count == 0) bloccate = [.. Elenco(null).Where(o => o.SoloPro)];
        return (libere, bloccate);
    }

    /// <summary>Il 4K è tra le scelte (libere o con «PRO»): solo allora le note lo nominano.</summary>
    public static bool Con4K(IReadOnlyList<OpzioneQualita> libere, IReadOnlyList<OpzioneQualita> bloccate) =>
        libere.Concat(bloccate).Any(o => o.Altezza >= 2160);

    /// <summary>L'opzione più vicina a ciò che arriva ora: stessa risoluzione, 60 sopra i 45 fps misurati.</summary>
    public static OpzioneQualita? Attuale(Statistiche? statistiche, IReadOnlyList<OpzioneQualita> opzioni)
    {
        if (statistiche is not { Larghezza: > 0, Altezza: > 0 }) return null;
        var corto = Math.Min(statistiche.Larghezza, statistiche.Altezza);
        var fps = statistiche.Fps > 45 ? 60 : 30;
        return opzioni.FirstOrDefault(o => o.Altezza == corto && o.Fps == fps) ?? opzioni.FirstOrDefault(o => o.Altezza == corto);
    }

    /// <summary>I fps che si possono chiedere a questa risoluzione: non oltre quelli dichiarati (0 = non la elenca).</summary>
    public static int FpsPossibili(int voluti, int larghezza, int altezza, IReadOnlyList<FormatoSupportato>? formati)
    {
        if (formati is null) return voluti;
        var massimo = formati
            .Where(f => (f.Larghezza == larghezza && f.Altezza == altezza) || (f.Larghezza == altezza && f.Altezza == larghezza))
            .Select(f => f.FpsMassimo)
            .DefaultIfEmpty(0)
            .Max();
        return Math.Min(voluti, massimo);
    }

    /// <summary>
    /// Il <c>formato</c> da chiedere per «Qualità video» e per i profili (dal PC è una richiesta: il telefono risponde con
    /// quello che manda davvero). Stesso orientamento e stesso codec del video che arriva (HEVC per il 4K); fps non oltre
    /// ciò che il telefono dichiara, e il 4K al massimo a 30. Null se non serve chiedere (è già così, il telefono non ci
    /// arriva, o il formato è di Pro e il telefono è gratis).
    /// </summary>
    public static FormatoVideo? Richiesta(int larghezza, int altezza, int fps, FormatoVideo? attuale,
        IReadOnlyList<FormatoSupportato>? formati, bool pro)
    {
        if (larghezza <= 0 || altezza <= 0 || fps <= 0) return null;
        var verticale = attuale is { } a && a.Altezza > a.Larghezza;
        var (l, h) = verticale ? (Math.Min(larghezza, altezza), Math.Max(larghezza, altezza)) : (Math.Max(larghezza, altezza), Math.Min(larghezza, altezza));
        var corto = Math.Min(larghezza, altezza);
        var voluti = Math.Min(fps, FpsMassimi(corto));
        var possibili = FpsPossibili(voluti, l, h, formati);
        if (possibili <= 0) return null;
        if (!pro && !RegolePro.FormatoGratis(l, h, possibili)) return null;
        var codec = CodecPer(corto, attuale?.Codec);
        var richiesta = new FormatoVideo(codec, l, h, possibili);
        return richiesta == attuale ? null : richiesta;
    }
}
