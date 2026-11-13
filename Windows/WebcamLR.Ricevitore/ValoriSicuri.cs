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
        Nome = NomeTelefono(ciao.Nome),
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
        // Le voci nulle (["formatiPro":[null]]) farebbero cadere chi legge Larghezza (collaudo 59).
        var formatiPro = capacita.FormatiPro?
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
            FormatiPro = formatiPro,
            SfondiPronti = capacita.SfondiPronti is null ? null : Elenco(capacita.SfondiPronti, VociMassime),
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
        Calore = stato.Calore is double ca && double.IsFinite(ca) ? Math.Clamp(ca, 0, 1) : null,
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
        // Un «null» dentro le strade lanciava a ogni stato e lo stato non arrivava più alla finestra (collaudo 59).
        Collegamento = stato.Collegamento is { } c
            ? c with
            {
                Attivo = Testo(c.Attivo, VoceMassima),
                Preferenza = Testo(c.Preferenza, VoceMassima),
                Strade = (c.Strade ?? []).Where(st => st is not null && !string.IsNullOrEmpty(st.Tipo))
                    .Select(st => st with { Tipo = Testo(st.Tipo, VoceMassima) }).Take(VociMassime).ToList(),
            }
            : null,
    };

    /// <summary>Il tempo manuale se un profilo non ne ha uno valido: 1/50 di secondo, senza bande con le luci a 50 Hz.</summary>
    public const int TempoPredefinito = 50;

    /// <summary>
    /// ISO di un profilo salvato, entro i limiti dell'obiettivo (Protocollo.md, «iso»); null se il telefono non dice i
    /// limiti o il valore non è un numero (allora l'esposizione resta automatica). Collaudo 20, t13 B9: ISO −5 arrivava così.
    /// </summary>
    public static double? IsoManuale(double iso, double? minimo, double? massimo)
    {
        if (!double.IsFinite(iso) || minimo is not double min || !double.IsFinite(min) || min <= 0) return null;
        var max = massimo is double m && double.IsFinite(m) && m >= min ? m : min;
        return Math.Round(Math.Clamp(iso, min, max));
    }

    /// <summary>Tempo di posa di un profilo (denominatore, 50 = 1/50 s): fuori da 1–100 000, quello predefinito.</summary>
    public static int TempoManuale(int tempo) => tempo is >= 1 and <= 100_000 ? tempo : TempoPredefinito;

    /// <summary>Temperatura del bianco di un profilo (K), 2500–7500; un valore non finito torna all'automatico (0).</summary>
    public static int BiancoManuale(double bianco) => double.IsFinite(bianco) ? (int)Math.Clamp(bianco, 2500, 7500) : 0;

    /// <summary>
    /// Il nome di un telefono da mostrare (domanda «Consentire …?», scheda, telefoni fidati): pulito come
    /// <see cref="Testo"/>, accorciato con «…» oltre <see cref="NomeMassimo"/> caratteri, «Telefono» se resta vuoto.
    /// </summary>
    public static string NomeTelefono(string? nome) =>
        Nome(nome, NomeMassimo) is { Length: > 0 } pulito ? pulito : TestiRicevitore.T("Telefono_NomePredefinito");

    /// <summary>
    /// Un nome da mostrare (telefono, profilo): pulito come <see cref="Testo"/>; se è più lungo di <paramref name="massimo"/>
    /// caratteri si accorcia tra due caratteri interi e finisce con «…» (collaudo 20, t13 B11: «…che p»?» sembrava un
    /// errore di battitura).
    /// </summary>
    public static string Nome(string? nome, int massimo)
    {
        var pulito = Pulisci(nome, massimo + 16);
        if (pulito.Length <= massimo) return pulito;
        return Accorcia(pulito, Math.Max(0, massimo - 1)).TrimEnd() + "…";
    }

    /// <summary>
    /// Un testo dalla rete: nullo diventa vuoto, al massimo <paramref name="massimo"/> caratteri. I caratteri di controllo
    /// e di formato spariscono (collaudo 20, t13 B8): a capo e tabulazioni diventano uno spazio (prima «Elenaseconda riga»),
    /// e i comandi di direzione del testo (U+202E e simili) non girano più il nome nella domanda «Consentire …?», dove un
    /// telefono estraneo poteva presentarsi con un nome che si legge come un altro.
    /// </summary>
    public static string Testo(string? testo, int massimo)
    {
        var pulito = Pulisci(testo, massimo + 16);
        return pulito.Length <= massimo ? pulito : Accorcia(pulito, massimo).TrimEnd();
    }

    /// <summary>
    /// Toglie i caratteri invisibili che cambiano come si legge un testo: controllo (Cc) e formato (Cf), tra cui i comandi
    /// bidirezionali (U+202A–U+202E, U+2066–U+2069, U+200E, U+200F, U+061C), e i surrogati spaiati. Restano i due
    /// «joiner» (U+200C, U+200D), che servono alle emoji composte e ad alcune lingue, e i tag delle bandiere
    /// (U+E0020–U+E007F). Gli spazi (a capo, tabulazioni, separatori di riga) diventano uno spazio solo.
    /// </summary>
    /// <param name="limite">Si smette dopo tanti caratteri puliti (un testo da un megabyte non si scorre tutto).</param>
    public static string Pulisci(string? testo, int limite = int.MaxValue)
    {
        if (string.IsNullOrEmpty(testo)) return "";
        var risultato = new System.Text.StringBuilder(Math.Min(testo.Length, 4096));
        Span<char> lettera = stackalloc char[2];
        var resto = testo.AsSpan();
        var spazio = false;
        while (resto.Length > 0 && risultato.Length <= limite)
        {
            var stato = System.Text.Rune.DecodeFromUtf16(resto, out var punto, out var usati);
            resto = resto[usati..];
            // Un surrogato spaiato sparisce.
            if (stato != System.Buffers.OperationStatus.Done) continue;
            var categoria = System.Text.Rune.GetUnicodeCategory(punto);
            if (System.Text.Rune.IsWhiteSpace(punto)
                || categoria is System.Globalization.UnicodeCategory.LineSeparator or System.Globalization.UnicodeCategory.ParagraphSeparator)
            {
                spazio = risultato.Length > 0;
                continue;
            }
            if (categoria == System.Globalization.UnicodeCategory.Control) continue;
            if (categoria == System.Globalization.UnicodeCategory.Format
                && punto.Value is not (0x200C or 0x200D) and not (>= 0xE0020 and <= 0xE007F))
                continue;
            if (spazio)
            {
                risultato.Append(' ');
                spazio = false;
            }
            risultato.Append(lettera[..punto.EncodeToUtf16(lettera)]);
        }
        return risultato.ToString();
    }

    /// <summary>I primi <paramref name="massimo"/> caratteri, senza spezzare una lettera con accenti o un'emoji composta.</summary>
    private static string Accorcia(string testo, int massimo)
    {
        var fine = 0;
        var elementi = System.Globalization.StringInfo.GetTextElementEnumerator(testo);
        while (elementi.MoveNext())
        {
            var dopo = elementi.ElementIndex + ((string)elementi.Current).Length;
            if (dopo > massimo) break;
            fine = dopo;
        }
        return testo[..fine];
    }

    private static List<string> Elenco(IReadOnlyList<string>? voci, int massimo) =>
        voci is null ? [] : voci.Where(v => !string.IsNullOrWhiteSpace(v)).Select(v => Testo(v, VoceMassima))
            .Where(v => v.Length > 0).Distinct().Take(massimo).ToList();

    private static double? Finito(double? valore) => valore is double v && double.IsFinite(v) ? v : null;
}
