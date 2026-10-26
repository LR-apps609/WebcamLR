using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// I messaggi del telefono arrivano dalla rete: un telefono rotto (o qualcuno che finge di esserlo, dopo la stretta di
/// mano) può mandare campi mancanti, testi lunghissimi o numeri fuori misura. Qui si portano nei limiti prima che
/// arrivino alla finestra, così un valore strano non fa cadere l'interfaccia (un cursore con il massimo a 1e300, un
/// testo da un megabyte nella scheda, un elenco nullo) e non si allocano decodificatori enormi.
/// Come sul Mac dopo il debug del 25 ottobre («crash con valori di rete anomali»).
/// </summary>
public static class ValoriSicuri
{
    public const int NomeMassimo = 64;
    public const int VoceMassima = 40;
    public const int VociMassime = 32;
    public const int LatoMinimo = 16;
    public const int LatoMassimo = 8192;
    public const int FpsMassimi = 240;
    public const double ZoomMassimo = 100;

    /// <summary>Nome e versione del telefono: mai nulli, mai lunghissimi, senza caratteri di controllo.</summary>
    public static Ciao Sanifica(Ciao ciao) => ciao with
    {
        Nome = Testo(ciao.Nome, NomeMassimo) is { Length: > 0 } nome ? nome : "Telefono",
        VersioneApp = Testo(ciao.VersioneApp, VoceMassima),
    };

    /// <summary>Il formato del video, oppure null se non è credibile (allora si ignora il messaggio).</summary>
    public static FormatoVideo? Sanifica(FormatoVideo formato) =>
        formato.Larghezza is >= LatoMinimo and <= LatoMassimo && formato.Altezza is >= LatoMinimo and <= LatoMassimo
        && formato.Fps is >= 1 and <= FpsMassimi && Enum.IsDefined(formato.Codec)
            ? formato
            : null;

    /// <summary>
    /// Il formato dell'audio (W2), oppure null se non è credibile: frequenze da 8 a 96 kHz, uno o due canali,
    /// una configurazione corta. Un codec sconosciuto passa: è il decodificatore a dire di no.
    /// </summary>
    public static FormatoAudio? Sanifica(FormatoAudio formato) =>
        formato.Frequenza is >= 8_000 and <= 96_000 && formato.Canali is 1 or 2
        && formato.Configurazione is { Length: <= 64 } && formato.Codec is { Length: > 0 and <= VoceMassima }
            ? formato
            : null;

    public static Capacita Sanifica(Capacita capacita)
    {
        var obiettivi = Elenco(capacita.Obiettivi, 8);
        var (isoMinimo, isoMassimo) = capacita.IsoMinimo is double minimo && capacita.IsoMassimo is double massimo
            && double.IsFinite(minimo) && double.IsFinite(massimo) && minimo > 0 && massimo > minimo && massimo <= 1_000_000
                ? (minimo, massimo)
                : ((double?)null, (double?)null);
        var formati = capacita.Formati?
            .Where(f => f is not null && f.Larghezza is >= LatoMinimo and <= LatoMassimo
                && f.Altezza is >= LatoMinimo and <= LatoMassimo && f.FpsMassimo is >= 1 and <= FpsMassimi)
            .Take(VociMassime)
            .ToList();
        return capacita with
        {
            Obiettivi = obiettivi,
            ZoomMassimo = double.IsFinite(capacita.ZoomMassimo) ? Math.Clamp(capacita.ZoomMassimo, 1, ZoomMassimo) : 1,
            IsoMinimo = isoMinimo,
            IsoMassimo = isoMassimo,
            Filtri = capacita.Filtri is null ? null : Elenco(capacita.Filtri, VociMassime),
            Formati = formati,
        };
    }

    public static StatoTelefono Sanifica(StatoTelefono stato) => stato with
    {
        Batteria = stato.Batteria is >= 0 and <= 100 ? stato.Batteria : -1,
        Temperatura = Enum.IsDefined(stato.Temperatura) ? stato.Temperatura : Temperatura.Normale,
        Obiettivo = Testo(stato.Obiettivo, VoceMassima),
        Filtro = stato.Filtro is null ? null : Testo(stato.Filtro, VoceMassima),
        Sfondo = stato.Sfondo is null ? null : Testo(stato.Sfondo, VoceMassima),
        IntensitaSfondo = Finito(stato.IntensitaSfondo),
        Pelle = Finito(stato.Pelle),
        Regolazioni = stato.Regolazioni is { } r
            ? new Regolazioni(Finito(r.Luminosita), Finito(r.Contrasto), Finito(r.Saturazione), Finito(r.Nitidezza))
            : null,
        Scritta = stato.Scritta is { } s ? new Scritta(Testo(s.Nome, 60), s.Ruolo is null ? null : Testo(s.Ruolo, 80)) : null,
        Pausa = stato.Pausa is null ? null : Testo(stato.Pausa, VoceMassima),
        Gobbo = stato.Gobbo is { } g ? g with { Posizione = double.IsFinite(g.Posizione) ? Math.Clamp(g.Posizione, 0, 1) : 0 } : null,
        Zoom = stato.Zoom is double z && double.IsFinite(z) ? Math.Clamp(z, 1, ZoomMassimo) : null,
        Esposizione = stato.Esposizione is double e && double.IsFinite(e) ? Math.Clamp(e, -2, 2) : null,
        Bianco = stato.Bianco is int b ? (b <= 0 ? 0 : Math.Clamp(b, 2500, 7500)) : null,
        Iso = stato.Iso is double i && double.IsFinite(i) ? Math.Clamp(i, 0, 1_000_000) : null,
        Tempo = stato.Tempo is int t ? Math.Clamp(t, 0, 100_000) : null,
    };

    /// <summary>Un testo dalla rete: nullo diventa vuoto, i caratteri di controllo spariscono, al massimo <paramref name="massimo"/> caratteri.</summary>
    public static string Testo(string? testo, int massimo)
    {
        if (string.IsNullOrEmpty(testo)) return "";
        var pulito = new string(testo.Where(c => !char.IsControl(c)).Take(massimo).ToArray()).Trim();
        // Un surrogato tagliato a metà non resta in fondo.
        return pulito.Length > 0 && char.IsHighSurrogate(pulito[^1]) ? pulito[..^1] : pulito;
    }

    private static List<string> Elenco(IReadOnlyList<string>? voci, int massimo) =>
        voci is null ? [] : voci.Where(v => !string.IsNullOrWhiteSpace(v)).Select(v => Testo(v, VoceMassima))
            .Where(v => v.Length > 0).Distinct().Take(massimo).ToList();

    private static double? Finito(double? valore) => valore is double v && double.IsFinite(v) ? v : null;
}
