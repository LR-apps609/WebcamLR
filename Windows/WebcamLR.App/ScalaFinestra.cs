using System.Runtime.InteropServices;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// La scala di Windows (1 = 100 %, 1,5 = 150 %) di una finestra o di un punto dello schermo, per le misure in DIP della
/// finestra principale (passo 7, windows.md 2.2). Il manifest è PerMonitorV2: ogni schermo ha la sua.
/// </summary>
internal static class ScalaFinestra
{
    private const uint DpiNormali = 96;
    private const uint MonitorPiuVicino = 2; // MONITOR_DEFAULTTONEAREST
    private const int DpiEffettivi = 0; // MDT_EFFECTIVE_DPI

    /// <summary>La scala dello schermo su cui sta la finestra; 1 se Windows non la dice.</summary>
    public static double Di(IntPtr finestra)
    {
        try
        {
            var dpi = GetDpiForWindow(finestra);
            return PosizioneFinestra.ScalaValida(dpi / (double)DpiNormali);
        }
        catch (Exception) { return 1; }
    }

    /// <summary>La scala dello schermo che contiene il punto (in pixel), o del più vicino; 1 se Windows non la dice.</summary>
    public static double InPunto(int x, int y)
    {
        try
        {
            var schermo = MonitorFromPoint(new Punto { X = x, Y = y }, MonitorPiuVicino);
            if (schermo == IntPtr.Zero || GetDpiForMonitor(schermo, DpiEffettivi, out var dpiX, out _) != 0) return 1;
            return PosizioneFinestra.ScalaValida(dpiX / (double)DpiNormali);
        }
        catch (Exception) { return 1; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Punto
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr finestra);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(Punto punto, uint opzioni);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr schermo, int tipo, out uint dpiX, out uint dpiY);
}

/// <summary>
/// La misura minima della finestra principale, 960×600 DIP (passo 7): sotto, le colonne e il video non ci stanno.
/// La versione di Windows App SDK in uso non ha ancora una misura minima per <c>OverlappedPresenter</c>: si risponde a
/// WM_GETMINMAXINFO con una sottoclasse della finestra, in pixel dello schermo su cui sta (PerMonitorV2).
/// </summary>
internal sealed class MisuraMinimaFinestra
{
    private const uint WmGetMinMaxInfo = 0x0024;
    private static readonly UIntPtr IdSottoclasse = new(0x574C52); // «WLR»

    private delegate IntPtr ProceduraSottoclasse(IntPtr finestra, uint messaggio, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr dati);

    /// <summary>Tenuta qui: se il delegato finisse nel garbage collector, Windows chiamerebbe un puntatore morto.</summary>
    private readonly ProceduraSottoclasse procedura;
    private readonly Func<bool> attiva;

    /// <param name="attiva">Vero quando la misura minima vale: solo per la finestra normale, non per la mini.</param>
    public MisuraMinimaFinestra(IntPtr finestra, Func<bool> attiva)
    {
        this.attiva = attiva;
        procedura = Procedura;
        try { SetWindowSubclass(finestra, procedura, IdSottoclasse, UIntPtr.Zero); }
        catch (Exception) { }
    }

    private IntPtr Procedura(IntPtr finestra, uint messaggio, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr dati)
    {
        var risultato = DefSubclassProc(finestra, messaggio, wParam, lParam);
        if (messaggio != WmGetMinMaxInfo || lParam == IntPtr.Zero) return risultato;
        try
        {
            if (!attiva()) return risultato;
            var scala = ScalaFinestra.Di(finestra);
            var info = Marshal.PtrToStructure<MinMaxInfo>(lParam);
            // Mai più grande dell'area di lavoro dello schermo (collaudo 20, t09 B10: a 1366×768 al 125% la minima di
            // 600 DIP era 750 px, sotto la barra delle applicazioni; al 150% più grande dello schermo).
            var (larghezza, altezza) = PosizioneFinestra.MinimaInPixel(scala, AreaDiLavoro(finestra));
            info.MinimaLarghezza = Math.Max(info.MinimaLarghezza, larghezza);
            info.MinimaAltezza = Math.Max(info.MinimaAltezza, altezza);
            Marshal.StructureToPtr(info, lParam, false);
        }
        catch (Exception) { }
        return IntPtr.Zero;
    }

    /// <summary>L'area di lavoro (senza la barra delle applicazioni) dello schermo della finestra, in pixel; null se non si sa.</summary>
    private static Rettangolo? AreaDiLavoro(IntPtr finestra)
    {
        try
        {
            var schermo = MonitorFromWindow(finestra, 2); // MONITOR_DEFAULTTONEAREST
            var info = new InfoSchermo { Dimensione = Marshal.SizeOf<InfoSchermo>() };
            if (schermo == IntPtr.Zero || !GetMonitorInfo(schermo, ref info)) return null;
            return new Rettangolo(info.Lavoro.Sinistra, info.Lavoro.Alto, info.Lavoro.Destra - info.Lavoro.Sinistra,
                info.Lavoro.Basso - info.Lavoro.Alto);
        }
        catch (Exception) { return null; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rett
    {
        public int Sinistra, Alto, Destra, Basso;
    }

    /// <summary>MONITORINFO.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct InfoSchermo
    {
        public int Dimensione;
        public Rett Schermo;
        public Rett Lavoro;
        public uint Opzioni;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr finestra, uint opzioni);

    [DllImport("user32.dll")]
    private static extern bool GetMonitorInfo(IntPtr schermo, ref InfoSchermo info);

    /// <summary>MINMAXINFO: cinque coppie di interi; qui serve solo ptMinTrackSize.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public int RiservatoX, RiservatoY;
        public int MassimaX, MassimaY;
        public int PosizioneMassimaX, PosizioneMassimaY;
        public int MinimaLarghezza, MinimaAltezza;
        public int TracciaMassimaX, TracciaMassimaY;
    }

    [DllImport("comctl32.dll")]
    private static extern bool SetWindowSubclass(IntPtr finestra, ProceduraSottoclasse procedura, UIntPtr id, UIntPtr dati);

    [DllImport("comctl32.dll")]
    private static extern IntPtr DefSubclassProc(IntPtr finestra, uint messaggio, IntPtr wParam, IntPtr lParam);
}
