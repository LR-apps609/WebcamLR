using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// La finestra con la barra di avanzamento mentre si scarica .NET (windows.md N5): una Task Dialog di sistema
/// (TaskDialogIndirect di comctl32 6, già nel manifest), con il solo pulsante «Annulla». Prima il download (fino a
/// 10 minuti) non mostrava nessuna finestra e l'installatore sembrava bloccato.
/// Il lavoro gira su un altro thread; la finestra legge l'avanzamento ogni 200 ms (TDN_TIMER) e si chiude da sola alla
/// fine. Se la Task Dialog non si apre, si aspetta il lavoro senza finestra, come prima.
/// </summary>
internal static unsafe class FinestraAvanzamento
{
    /// <summary>Esito: il lavoro è finito (anche con un errore, in <paramref name="errore"/>) o l'utente ha annullato.</summary>
    public static bool Esegui(Func<Action<long, long?>, CancellationToken, Task> lavoro, Func<long, long?, string> testo, out Exception? errore)
    {
        var stato = new Stato(testo);
        var compito = Task.Run(() => lavoro((fatti, totale) =>
        {
            Interlocked.Exchange(ref stato.Fatti, fatti);
            Interlocked.Exchange(ref stato.Totale, totale ?? -1);
        }, stato.Annulla.Token));
        stato.Compito = compito;

        var maniglia = GCHandle.Alloc(stato);
        var titolo = Marshal.StringToHGlobalUni(Testi.S($"Installazione di {DatiProdotto.Nome}", $"{DatiProdotto.Nome} Setup"));
        var contenuto = Marshal.StringToHGlobalUni(testo(0, null));
        try
        {
            var configurazione = new ConfigurazioneTaskDialog
            {
                Dimensione = (uint)sizeof(ConfigurazioneTaskDialog),
                Flag = TDF_ALLOW_DIALOG_CANCELLATION | TDF_SHOW_PROGRESS_BAR | TDF_CALLBACK_TIMER | TDF_SIZE_TO_CONTENT,
                PulsantiComuni = TDCBF_CANCEL_BUTTON,
                Titolo = titolo,
                Contenuto = contenuto,
                Richiamo = (nint)(delegate* unmanaged[Stdcall]<nint, uint, nuint, nint, nint, int>)&Richiamo,
                DatiRichiamo = GCHandle.ToIntPtr(maniglia),
            };
            var hr = TaskDialogIndirect(&configurazione, null, null, null);
            if (hr < 0) Registro.Scrivi($"La finestra di avanzamento non si apre (0x{hr:X8}): aspetto senza");
        }
        catch (Exception eccezione)
        {
            Registro.Scrivi($"La finestra di avanzamento non si apre ({eccezione.Message}): aspetto senza");
        }
        finally
        {
            maniglia.Free();
            Marshal.FreeHGlobal(titolo);
            Marshal.FreeHGlobal(contenuto);
        }

        if (stato.AnnullatoDallUtente)
        {
            errore = null;
            try { compito.Wait(TimeSpan.FromSeconds(5)); } catch (Exception) { }
            return false;
        }
        try
        {
            compito.GetAwaiter().GetResult();
            errore = null;
        }
        catch (Exception eccezione)
        {
            errore = eccezione;
        }
        return true;
    }

    private sealed class Stato(Func<long, long?, string> testo)
    {
        public readonly Func<long, long?, string> Testo = testo;
        public readonly CancellationTokenSource Annulla = new();
        public Task? Compito;
        public long Fatti;
        public long Totale = -1;
        public bool AnnullatoDallUtente;
        public bool ChiusaDaQui;
        public bool Marquee;
        public string UltimoTesto = "";
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static int Richiamo(nint finestra, uint notifica, nuint wParam, nint lParam, nint dati)
    {
        try
        {
            if (GCHandle.FromIntPtr(dati).Target is not Stato stato) return 0;
            switch (notifica)
            {
                case TDN_TIMER:
                    if (stato.Compito?.IsCompleted == true)
                    {
                        // Finito: la finestra si chiude da sola (come un clic su «Annulla», ma non è un annullamento).
                        stato.ChiusaDaQui = true;
                        SendMessageW(finestra, TDM_CLICK_BUTTON, IDCANCEL, 0);
                        return 0;
                    }
                    var fatti = Interlocked.Read(ref stato.Fatti);
                    var totale = Interlocked.Read(ref stato.Totale);
                    var (_, _, percento) = AvanzamentoDownload.Calcola(fatti, totale > 0 ? totale : null);
                    if (percento is int p)
                    {
                        SendMessageW(finestra, TDM_SET_PROGRESS_BAR_POS, (nuint)p, 0);
                    }
                    else if (!stato.Marquee && fatti > 0)
                    {
                        // Il server non dice quanto è grande: la barra che scorre.
                        stato.Marquee = true;
                        SendMessageW(finestra, TDM_SET_MARQUEE_PROGRESS_BAR, 1, 0);
                        SendMessageW(finestra, TDM_SET_PROGRESS_BAR_MARQUEE, 1, 30);
                    }
                    var testo = stato.Testo(fatti, totale > 0 ? totale : null);
                    if (testo != stato.UltimoTesto)
                    {
                        stato.UltimoTesto = testo;
                        var puntatore = Marshal.StringToHGlobalUni(testo);
                        try { SendMessageW(finestra, TDM_SET_ELEMENT_TEXT, TDE_CONTENT, puntatore); }
                        finally { Marshal.FreeHGlobal(puntatore); }
                    }
                    return 0;
                case TDN_BUTTON_CLICKED when (int)wParam == IDCANCEL && !stato.ChiusaDaQui:
                    stato.AnnullatoDallUtente = true;
                    stato.Annulla.Cancel();
                    return 0;
            }
        }
        catch (Exception) { }
        return 0;
    }

    private const uint WM_USER = 0x0400;
    private const uint TDM_CLICK_BUTTON = WM_USER + 102;
    private const uint TDM_SET_MARQUEE_PROGRESS_BAR = WM_USER + 103;
    private const uint TDM_SET_PROGRESS_BAR_POS = WM_USER + 106;
    private const uint TDM_SET_PROGRESS_BAR_MARQUEE = WM_USER + 107;
    private const uint TDM_SET_ELEMENT_TEXT = WM_USER + 108;
    private const nuint TDE_CONTENT = 0;
    private const uint TDN_BUTTON_CLICKED = 2;
    private const uint TDN_TIMER = 4;
    private const int IDCANCEL = 2;
    private const int TDF_ALLOW_DIALOG_CANCELLATION = 0x0008;
    private const int TDF_SHOW_PROGRESS_BAR = 0x0200;
    private const int TDF_CALLBACK_TIMER = 0x0800;
    private const int TDF_SIZE_TO_CONTENT = 0x01000000;
    private const int TDCBF_CANCEL_BUTTON = 0x0008;

    /// <summary>TASKDIALOGCONFIG di CommCtrl.h, che è impaccata a 1 byte (pshpack1.h) su tutte le architetture.</summary>
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct ConfigurazioneTaskDialog
    {
        public uint Dimensione;
        public nint Genitore;
        public nint Istanza;
        public int Flag;
        public int PulsantiComuni;
        public nint Titolo;
        public nint IconaPrincipale;
        public nint IstruzionePrincipale;
        public nint Contenuto;
        public uint NumeroPulsanti;
        public nint Pulsanti;
        public int PulsantePredefinito;
        public uint NumeroScelte;
        public nint Scelte;
        public int SceltaPredefinita;
        public nint TestoVerifica;
        public nint InformazioniEspanse;
        public nint TestoEspandi;
        public nint TestoRiduci;
        public nint IconaPiede;
        public nint Piede;
        public nint Richiamo;
        public nint DatiRichiamo;
        public uint Larghezza;
    }

    [DllImport("comctl32.dll")]
    internal static extern int TaskDialogIndirect(ConfigurazioneTaskDialog* configurazione, int* pulsante, int* scelta, int* verifica);

    [DllImport("user32.dll")]
    private static extern nint SendMessageW(nint finestra, uint messaggio, nuint wParam, nint lParam);
}
