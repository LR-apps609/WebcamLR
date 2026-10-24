using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WebcamLR.Webcam;

/// <summary>
/// Attese al millisecondo per il ritmo dei 30 fps. Thread.Sleep su Windows ha passi di 15,6 ms, che darebbero
/// fotogrammi a scatti; il timer ad alta risoluzione (Windows 10 1803 e successivi) no, e non cambia la risoluzione
/// del timer di tutto il processo Frame Server (come farebbe timeBeginPeriod).
/// </summary>
internal sealed class OrologioPreciso : IDisposable
{
    private const uint CREATE_WAITABLE_TIMER_HIGH_RESOLUTION = 0x00000002;
    private const uint TIMER_ALL_ACCESS = 0x001F0003;
    private nint timer;

    public OrologioPreciso()
    {
        timer = CreateWaitableTimerExW(0, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    }

    /// <summary>Aspetta fino al momento dato (in tick di Stopwatch).</summary>
    public void AspettaFino(long momento)
    {
        var restante = momento - Stopwatch.GetTimestamp();
        if (restante <= 0) return;
        var cento_ns = restante * 10_000_000 / Stopwatch.Frequency;
        if (timer != 0)
        {
            // Negativo: tempo relativo, in unità da 100 ns.
            var scadenza = -cento_ns;
            if (SetWaitableTimer(timer, ref scadenza, 0, 0, 0, false))
            {
                WaitForSingleObject(timer, 1000);
                return;
            }
        }
        Thread.Sleep(TimeSpan.FromTicks(cento_ns));
    }

    public void Dispose()
    {
        if (timer != 0) { CloseHandle(timer); timer = 0; }
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint CreateWaitableTimerExW(nint attributi, string? nome, uint flag, uint accesso);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetWaitableTimer(nint timer, ref long scadenza, int periodo, nint routine, nint argomento, bool riprendi);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(nint oggetto, uint millisecondi);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(nint oggetto);
}
