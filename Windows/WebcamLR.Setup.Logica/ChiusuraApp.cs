namespace WebcamLR.Setup;

/// <summary>Che cosa dice l'installatore di WebcamLR aperta, prima di chiuderla (windows.md 1.7).</summary>
public enum AvvisoAppAperta
{
    /// <summary>WebcamLR non è aperta: niente da dire.</summary>
    Nessuno,
    /// <summary>Aperta, e nessuna app sta usando la webcam.</summary>
    Aperta,
    /// <summary>Aperta, e un'app sta usando la webcam adesso: la chiamata perderà il video per qualche secondo.</summary>
    ApertaVideoInUso,
    /// <summary>Aperta, ma non si sa se un'app usa la webcam (la memoria condivisa non si legge).</summary>
    ApertaForseVideoInUso,
}

/// <summary>Il prossimo passo per chiudere una copia aperta di WebcamLR.</summary>
public enum PassoChiusura
{
    /// <summary>Chiedere all'app di uscire bene: <c>WebcamLR.exe --esci</c>.</summary>
    ChiediUscita,
    /// <summary>Richiesta mandata: si aspetta che l'app chiuda la registrazione, salvi ed esca.</summary>
    Aspetta,
    /// <summary>Non è uscita in tempo (o non ha capito la richiesta, per esempio una versione vecchia): a forza.</summary>
    Forza,
    /// <summary>Uscita.</summary>
    Fatto,
}

/// <summary>
/// Come l'installatore e il disinstallatore chiudono WebcamLR aperta (1.7). Prima si chiedeva la chiusura della
/// finestra (WM_CLOSE), che nell'app nasconde soltanto: dopo 5 secondi, o subito con la finestra già nascosta, il
/// processo veniva terminato a forza, con la registrazione persa. Adesso l'installatore lancia
/// <c>WebcamLR.exe --esci</c>: la copia nuova passa la richiesta a quella aperta (istanza unica, App.xaml.cs), che esce
/// come con «Esci» ma senza domande (chiude e salva la registrazione). Solo dopo <see cref="AttesaUscita"/> la forza.
/// </summary>
public static class ChiusuraApp
{
    /// <summary>L'argomento che chiede a WebcamLR aperta di uscire. Lo stesso in UscitaRichiesta (WebcamLR.Ricevitore).</summary>
    public const string ArgomentoEsci = "--esci";

    /// <summary>Quanto si aspetta l'uscita gentile: chiudere una registrazione lunga richiede qualche secondo.</summary>
    public static readonly TimeSpan AttesaUscita = TimeSpan.FromSeconds(15);

    /// <summary>Dopo la chiusura a forza, quanto si aspetta che il processo sparisca davvero.</summary>
    public static readonly TimeSpan AttesaDopoForza = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Vero se il processo è WebcamLR installata in questa cartella (anche solo con l'icona accanto all'orologio).
    /// Un percorso che non si legge conta: altrimenti i file non si potrebbero sostituire. Una copia altrove
    /// (per esempio «…\WebcamLR.vecchia-…» o una cartella di prova) non si tocca.
    /// </summary>
    public static bool DaChiudere(string? percorsoProcesso, string cartellaApp)
    {
        if (string.IsNullOrEmpty(percorsoProcesso)) return true;
        var cartella = cartellaApp.TrimEnd('\\', '/') + "\\";
        return percorsoProcesso.Replace('/', '\\').StartsWith(cartella, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Che cosa dire prima di chiudere. <paramref name="webcamInstallata"/>: la webcam per le altre app è registrata;
    /// senza, nessuna app può usare il video. <paramref name="videoInUso"/>: letto dalla memoria condivisa della webcam,
    /// null se non si è potuta leggere.
    /// </summary>
    public static AvvisoAppAperta Avviso(bool aperta, bool webcamInstallata, bool? videoInUso) =>
        !aperta ? AvvisoAppAperta.Nessuno
        : !webcamInstallata ? AvvisoAppAperta.Aperta
        : videoInUso switch
        {
            true => AvvisoAppAperta.ApertaVideoInUso,
            false => AvvisoAppAperta.Aperta,
            null => AvvisoAppAperta.ApertaForseVideoInUso,
        };

    /// <summary>Il passo successivo, da chiamare in giro finché non torna <see cref="PassoChiusura.Fatto"/> o <see cref="PassoChiusura.Forza"/>.</summary>
    public static PassoChiusura Prossimo(bool uscita, bool richiestaMandata, TimeSpan dallaRichiesta)
    {
        if (uscita) return PassoChiusura.Fatto;
        if (!richiestaMandata) return PassoChiusura.ChiediUscita;
        return dallaRichiesta < AttesaUscita ? PassoChiusura.Aspetta : PassoChiusura.Forza;
    }
}

/// <summary>I numeri della finestra di avanzamento del download di .NET (N5): «12 MB di 30».</summary>
public static class AvanzamentoDownload
{
    private const double Mega = 1024 * 1024;

    /// <summary>Megabyte scaricati, il totale se il server lo dice (null altrimenti) e la percentuale 0-100 (null senza totale).</summary>
    public static (int Mb, int? MbTotali, int? Percento) Calcola(long scaricati, long? totale)
    {
        var mb = (int)Math.Floor(Math.Max(0, scaricati) / Mega);
        if (totale is not long t || t <= 0) return (mb, null, null);
        var mbTotali = Math.Max(1, (int)Math.Round(t / Mega));
        var percento = (int)Math.Clamp(Math.Floor(scaricati * 100.0 / t), 0, 100);
        return (Math.Min(mb, mbTotali), mbTotali, percento);
    }
}
