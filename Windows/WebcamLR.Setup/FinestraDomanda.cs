using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace WebcamLR.Setup;

/// <summary>
/// Le due finestre dell'installatore (windows.md N6, 1.0 beta 4): Task Dialog di sistema (TaskDialogIndirect di comctl32
/// 6, come FinestraAvanzamento), con l'icona di WebcamLR, il titolo grande, il testo, una casella facoltativa («Installa
/// anche la webcam per Zoom, Teams…»), un piede facoltativo con lo scudo (l'avviso del Controllo account utente) e due
/// pulsanti scritti per esteso («Installa» · «Annulla», «Apri WebcamLR» · «Chiudi»). Il pulsante che porta al permesso
/// dell'amministratore ha lo scudo di Windows. Esc e la X valgono il secondo pulsante.
/// Le stesse finestre per il disinstallatore (beta 4, PianoDisinstallazione): titolo «Disinstallazione di WebcamLR»,
/// «Annulla» predefinito nella domanda, e la finestra finale con il solo «Chiudi» (<see cref="Informa"/>).
/// Se la Task Dialog non si apre (comctl32 vecchio), la stessa domanda in una MessageBox, come prima.
/// </summary>
internal static unsafe class FinestraDomanda
{
    /// <summary>Che cosa ha scelto: il primo pulsante (vero) o il secondo, e la casella.</summary>
    public readonly record struct Risposta(bool Primo, bool Casella);

    public enum Piede
    {
        Nessuno,
        /// <summary>Lo scudo: il permesso dell'amministratore che arriva.</summary>
        Scudo,
        /// <summary>Il triangolo: qualcosa non è andato e c'è da fare dopo.</summary>
        Avviso,
    }

    /// <param name="titolo">Il titolo della finestra: di serie «Installazione di WebcamLR».</param>
    /// <param name="predefinitoSecondo">Il secondo pulsante («Annulla») è il predefinito: per le domande che tolgono qualcosa.</param>
    public static Risposta Chiedi(string istruzione, string contenuto, string primo, string secondo,
        string? casella = null, bool casellaSpuntata = true, string? piede = null, Piede iconaPiede = Piede.Nessuno,
        bool scudoSulPrimo = false, string? titolo = null, bool predefinitoSecondo = false) =>
        Mostra(istruzione, contenuto, primo, secondo, casella, casellaSpuntata, piede, iconaPiede, scudoSulPrimo, titolo, predefinitoSecondo);

    /// <summary>Una finestra che dice com'è andata, con il solo pulsante <paramref name="chiudi"/> (Esc e la X lo valgono).</summary>
    public static void Informa(string istruzione, string contenuto, string chiudi, string? piede = null,
        Piede iconaPiede = Piede.Nessuno, string? titolo = null) =>
        Mostra(istruzione, contenuto, null, chiudi, null, false, piede, iconaPiede, false, titolo, true);

    private static Risposta Mostra(string istruzione, string contenuto, string? primo, string secondo, string? casella,
        bool casellaSpuntata, string? piede, Piede iconaPiede, bool scudoSulPrimo, string? titolo, bool predefinitoSecondo)
    {
        var testi = new List<nint>();
        nint Testo(string? s)
        {
            if (s is null) return 0;
            var p = Marshal.StringToHGlobalUni(s);
            testi.Add(p);
            return p;
        }
        try
        {
            // Senza il primo (Informa) un pulsante solo, che vale «Chiudi».
            var pulsanti = stackalloc PulsanteTaskDialog[2];
            var numero = 0;
            if (primo is not null) pulsanti[numero++] = new PulsanteTaskDialog { Id = IdPrimo, Testo = Testo(primo) };
            pulsanti[numero++] = new PulsanteTaskDialog { Id = IDCANCEL, Testo = Testo(secondo) };
            var icona = IconaWebcamLR();
            var flag = TDF_ALLOW_DIALOG_CANCELLATION;
            if (icona != 0) flag |= TDF_USE_HICON_MAIN;
            if (casella is not null && casellaSpuntata) flag |= TDF_VERIFICATION_FLAG_CHECKED;
            var configurazione = new FinestraAvanzamento.ConfigurazioneTaskDialog
            {
                Dimensione = (uint)sizeof(FinestraAvanzamento.ConfigurazioneTaskDialog),
                Flag = flag,
                Titolo = Testo(titolo ?? Testi.S($"Installazione di {DatiProdotto.Nome}", $"{DatiProdotto.Nome} Setup")),
                IconaPrincipale = icona,
                IstruzionePrincipale = Testo(istruzione),
                Contenuto = Testo(contenuto),
                NumeroPulsanti = (uint)numero,
                Pulsanti = (nint)pulsanti,
                PulsantePredefinito = primo is null || predefinitoSecondo ? IDCANCEL : IdPrimo,
                TestoVerifica = Testo(casella),
                Piede = Testo(piede),
                IconaPiede = piede is null ? 0 : iconaPiede switch
                {
                    Piede.Scudo => TD_SHIELD_ICON,
                    Piede.Avviso => TD_WARNING_ICON,
                    _ => 0,
                },
                Richiamo = scudoSulPrimo && primo is not null ? (nint)(delegate* unmanaged[Stdcall]<nint, uint, nuint, nint, nint, int>)&Richiamo : 0,
            };
            int scelto = 0, spuntata = 0;
            var hr = FinestraAvanzamento.TaskDialogIndirect(&configurazione, &scelto, null, &spuntata);
            if (hr >= 0) return new Risposta(primo is not null && scelto == IdPrimo, casella is not null && spuntata != 0);
            Registro.Scrivi($"La Task Dialog non si apre (0x{hr:X8}): MessageBox");
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"La Task Dialog non si apre ({errore.Message}): MessageBox");
        }
        finally
        {
            foreach (var p in testi) Marshal.FreeHGlobal(p);
        }
        // Ripiego: la stessa domanda in una MessageBox (Sì = il primo pulsante); la casella diventa una seconda domanda.
        var testo = piede is null ? $"{istruzione}\n\n{contenuto}" : $"{istruzione}\n\n{contenuto}\n\n{piede}";
        if (primo is null)
        {
            if (iconaPiede == Piede.Avviso && piede is not null) FunzioniWindows.Avvisa(testo); else FunzioniWindows.Informa(testo);
            return new Risposta(false, false);
        }
        var sì = FunzioniWindows.Conferma($"{testo}\n\n{primo}?");
        var spunta = sì && casella is not null && FunzioniWindows.Chiedi($"{casella}?");
        return new Risposta(sì, spunta);
    }

    /// <summary>Appena la finestra c'è: lo scudo di Windows sul primo pulsante (porta al permesso dell'amministratore).</summary>
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static int Richiamo(nint finestra, uint notifica, nuint wParam, nint lParam, nint dati)
    {
        if (notifica == TDN_CREATED) SendMessageW(finestra, TDM_SET_BUTTON_ELEVATION_REQUIRED_STATE, IdPrimo, 1);
        return 0;
    }

    /// <summary>L'icona dell'exe (quella di WebcamLR, ApplicationIcon nel progetto): 0 se non si trova.</summary>
    private static nint IconaWebcamLR()
    {
        try { return LoadIconW(GetModuleHandleW(null), IdIconaApplicazione); }
        catch (Exception) { return 0; }
    }

    private const int IdPrimo = 100;
    private const int IDCANCEL = 2;
    /// <summary>L'icona che .NET mette nell'exe da ApplicationIcon ha l'identificativo 32512.</summary>
    private const nint IdIconaApplicazione = 32512;
    private const int TDF_USE_HICON_MAIN = 0x0002;
    private const int TDF_ALLOW_DIALOG_CANCELLATION = 0x0008;
    private const int TDF_VERIFICATION_FLAG_CHECKED = 0x0100;
    private const uint TDN_CREATED = 0;
    private const uint TDM_SET_BUTTON_ELEVATION_REQUIRED_STATE = 0x0400 + 115;
    /// <summary>MAKEINTRESOURCEW(-1) e (-4): le icone di sistema della Task Dialog.</summary>
    private const nint TD_WARNING_ICON = 0xFFFF;
    private const nint TD_SHIELD_ICON = 0xFFFC;

    /// <summary>TASKDIALOG_BUTTON di CommCtrl.h, impaccata a 1 byte come TASKDIALOGCONFIG.</summary>
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct PulsanteTaskDialog
    {
        public int Id;
        public nint Testo;
    }

    [DllImport("user32.dll")]
    private static extern nint SendMessageW(nint finestra, uint messaggio, nuint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint LoadIconW(nint istanza, nint nome);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandleW(string? modulo);
}
