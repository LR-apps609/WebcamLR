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
            info.MinimaLarghezza = Math.Max(info.MinimaLarghezza, PosizioneFinestra.InPixel(PosizioneFinestra.LarghezzaMinima, scala));
            info.MinimaAltezza = Math.Max(info.MinimaAltezza, PosizioneFinestra.InPixel(PosizioneFinestra.AltezzaMinima, scala));
            Marshal.StructureToPtr(info, lParam, false);
        }
        catch (Exception) { }
        return IntPtr.Zero;
    }

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
