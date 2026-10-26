namespace WebcamLR.Ricevitore;

/// <summary>Un'uscita audio di Windows (altoparlanti, cuffie, cavo audio virtuale): l'ID di sistema e il nome visibile.</summary>
public sealed record DispositivoAudio(string Id, string Nome);

/// <summary>
/// Le scelte sull'uscita del microfono del telefono su Windows (W2). Su Windows non c'è un modo senza driver firmato per
/// creare un microfono che le altre app vedano (Documenti/Microfono Windows.md): l'audio del telefono va a un'uscita
/// audio scelta dall'utente. Con un cavo audio virtuale che l'utente ha già installato (VB-CABLE, Voicemeeter, Virtual
/// Audio Cable: mai inclusi in WebcamLR) le app di chiamata lo ricevono dal lato «ingresso» del cavo.
/// </summary>
public static class UsciteAudio
{
    /// <summary>Parole nei nomi dei cavi audio virtuali più diffusi, come compaiono in Windows.</summary>
    private static readonly string[] SegniDiCavo =
    [
        "VB-Audio", "CABLE Input", "Voicemeeter", "Virtual Audio Cable", "Virtual Cable", "Line 1 (", "VAIO",
    ];

    /// <summary>Il nome sembra quello di un cavo audio virtuale (non altoparlanti o cuffie veri).</summary>
    public static bool ECavoVirtuale(string? nome) =>
        !string.IsNullOrWhiteSpace(nome) && SegniDiCavo.Any(segno => nome.Contains(segno, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Il microfono da scegliere nelle app di chiamata per un cavo: il lato di registrazione ha lo stesso nome con
    /// «Output» al posto di «Input» (VB-CABLE: «CABLE Input» → «CABLE Output»; Voicemeeter: «Voicemeeter Input» →
    /// «Voicemeeter Output»). Null se non è un cavo o il nome non segue questa regola.
    /// </summary>
    public static string? IngressoDelCavo(string? nome)
    {
        if (!ECavoVirtuale(nome)) return null;
        var posto = nome!.IndexOf("Input", StringComparison.OrdinalIgnoreCase);
        if (posto < 0) return null;
        return string.Concat(nome.AsSpan(0, posto), "Output", nome.AsSpan(posto + "Input".Length));
    }

    /// <summary>
    /// L'uscita da usare: quella salvata, se c'è ancora; altrimenti il primo cavo virtuale; altrimenti nessuna.
    /// Mai gli altoparlanti da soli: il telefono accanto al PC farebbe eco e fischi.
    /// </summary>
    /// <param name="salvata">L'ID salvato nelle preferenze; "" se l'utente ha scelto «nessuna».</param>
    public static DispositivoAudio? Scelta(IReadOnlyList<DispositivoAudio> dispositivi, string? salvata)
    {
        if (salvata is not null)
        {
            if (salvata.Length == 0) return null;
            if (dispositivi.FirstOrDefault(d => d.Id == salvata) is { } trovata) return trovata;
        }
        return dispositivi.FirstOrDefault(d => ECavoVirtuale(d.Nome));
    }
}
