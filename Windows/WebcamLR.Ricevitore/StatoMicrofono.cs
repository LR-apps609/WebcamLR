namespace WebcamLR.Ricevitore;

/// <summary>Cosa mostra la riga «Microfono del telefono» nella colonna Uscite (W2).</summary>
/// <param name="Stato">La parola a destra: «spento» o «attivo», come sul Mac.</param>
/// <param name="Nota">La riga sotto, solo quando serve dire qualcosa.</param>
/// <param name="Attivo">Verde (icona e stato) solo quando l'audio arriva davvero.</param>
/// <param name="Utilizzabile">L'interruttore si può usare: c'è un telefono che manda l'audio.</param>
public sealed record VistaMicrofono(string Stato, string? Nota, bool Attivo, bool Utilizzabile);

/// <summary>
/// I testi della riga del microfono su Windows, come ColonnaDispositivi.swift sul Mac ma onesti su Windows: qui non c'è un
/// microfono «WebcamLR (microfono)» (servirebbe un driver firmato, Documenti/Microfono Windows.md), l'audio va a
/// un'uscita scelta, di solito un cavo audio virtuale che l'utente ha già. Gratis, non è di WebcamLR Pro.
/// </summary>
public static class StatoMicrofono
{
    /// <param name="telefonoCollegato">C'è un telefono nella webcam.</param>
    /// <param name="mandaAudio"><c>capacita.audio</c> del telefono; null finché le capacità non arrivano.</param>
    /// <param name="acceso">L'interruttore.</param>
    /// <param name="audioInArrivo">Audio decodificato nell'ultimo mezzo secondo.</param>
    /// <param name="uscita">L'uscita audio scelta; null = nessuna (solo il livello).</param>
    /// <param name="cavoInstallato">Fra le uscite di Windows c'è un cavo audio virtuale.</param>
    /// <param name="erroreUscita">Perché l'uscita non si è aperta, se non si è aperta.</param>
    public static VistaMicrofono Descrivi(bool telefonoCollegato, bool? mandaAudio, bool acceso, bool audioInArrivo,
        DispositivoAudio? uscita, bool cavoInstallato, string? erroreUscita)
    {
        var utilizzabile = telefonoCollegato && mandaAudio == true;
        var stato = acceso ? "attivo" : "spento";
        var attivo = acceso && audioInArrivo && utilizzabile;
        return new VistaMicrofono(stato, Nota(), attivo, utilizzabile);

        string? Nota()
        {
            if (!telefonoCollegato) return "Collega un telefono per usarlo.";
            // Capacità non ancora arrivate: per un attimo non si dice niente.
            if (mandaAudio is null) return null;
            if (mandaAudio == false) return "Il telefono non manda l'audio.";
            if (acceso && erroreUscita is not null) return $"Uscita audio non disponibile: {erroreUscita}.";
            if (acceso && !audioInArrivo) return "In attesa dell'audio dal telefono…";
            if (uscita is null)
            {
                if (!cavoInstallato)
                    return "Su Windows il microfono del telefono si sente nelle app con un cavo audio virtuale, da installare a parte (per esempio VB-CABLE). Senza, qui vedi solo il livello.";
                return acceso ? "Scegli il cavo audio virtuale qui sotto: le app lo ricevono come microfono." : null;
            }
            if (!acceso) return null;
            if (UsciteAudio.IngressoDelCavo(uscita.Nome) is { } ingresso) return $"Nelle app scegli «{ingresso}» come microfono.";
            if (UsciteAudio.ECavoVirtuale(uscita.Nome)) return "Nelle app scegli come microfono l'altro lato del cavo audio virtuale.";
            return $"Lo senti da «{uscita.Nome}». Per usarlo nelle chiamate serve un cavo audio virtuale.";
        }
    }
}
