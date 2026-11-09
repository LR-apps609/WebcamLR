namespace WebcamLR.Effetti;

/// <summary>
/// Qualità 7 e 8: come si sfoca lo sfondo «sfocato». Sono scelte del computer (Mac e PC), non viaggiano nel protocollo: al
/// telefono telecomando lo sfondo resta «sfocato» (Documenti/Protocollo.md, «Effetti sul computer»). Gratis come la
/// sfocatura. Uno stile sconosciuto (preferenze di una versione più nuova) vale <see cref="Normale"/>.
/// Stessi identificativi del Mac (Mac/Sorgenti/MotoreEffetti.swift, <c>StiliSfocatura</c>).
/// </summary>
public static class StiliSfocatura
{
    /// <summary>La sfocatura di sempre (gaussiana, senza alone).</summary>
    public const string Normale = "normale";

    /// <summary>Come un obiettivo: le luci forti dello sfondo diventano dischi.</summary>
    public const string Bokeh = "bokeh";

    /// <summary>Lo sfondo a quadretti (pixelate): il livello di sfocatura sceglie quanto sono grandi.</summary>
    public const string Mosaico = "mosaico";

    /// <summary>Tutti, nell'ordine in cui mostrarli.</summary>
    public static IReadOnlyList<string> Tutti { get; } = [Normale, Bokeh, Mosaico];

    /// <summary>Uno stile conosciuto, o <see cref="Normale"/>.</summary>
    public static string Valido(string? stile) => stile is Bokeh or Mosaico ? stile : Normale;

    /// <summary>
    /// Lo stile che si rende davvero a questo livello (Qualità 6): il bokeh costa più della sfocatura normale e ai livelli
    /// veloci (bordo bilineare, quelli per i PC lenti) torna alla sfocatura normale; il mosaico costa meno della sfocatura
    /// e resta a tutti i livelli.
    /// </summary>
    public static string AlLivello(string? stile, LivelloResa livello)
    {
        var valido = Valido(stile);
        return valido == Bokeh && livello.ConBordoBilineare() ? Normale : valido;
    }

    /// <summary>
    /// Il bokeh si calcola a un quarto della misura al livello pieno e a un ottavo agli altri livelli dove resta (bordo
    /// leggero, maschera alterna): 1 = un gradino sotto il quarto.
    /// </summary>
    public static int GradinoBokeh(LivelloResa livello) => livello == LivelloResa.Pieno ? 0 : 1;
}

/// <summary>
/// Qualità 8: lo sfondo verde pieno per il chroma key esterno (OBS e simili). È uno sfondo «sostituito» con un'immagine
/// fissa, quindi segue le regole Pro dello sfondo sostituito; il bordo è netto e senza light wrap, così il verde resta
/// pulito attorno alla persona. Solo del computer: al telefono telecomando lo sfondo risulta «sostituito».
/// </summary>
public static class SfondoVerde
{
    /// <summary>L'id di <c>immagineSfondo</c> sul computer (non è uno degli sfondi pronti del protocollo).</summary>
    public const string Id = "verde";

    /// <summary>#00B140, il verde «chroma key» delle produzioni video.</summary>
    public static readonly (byte R, byte G, byte B) Colore = (0x00, 0xB1, 0x40);

    /// <summary>
    /// Larghezza della soglia del bordo (sull'alfa a metà o a un quarto, poi ingrandito): più stretta di quella dello
    /// sfondo sostituito più netto (0,2), così il passaggio persona-verde è di un paio di pixel e il chroma key lo taglia pulito.
    /// </summary>
    public const float LarghezzaSoglia = 0.12f;
}
