using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Si accorge del risveglio dallo stop anche se nessuno lo dice (1.12): con un controllo ogni pochi secondi,
/// se tra due controlli è passato molto più tempo del previsto il computer dormiva (o il programma era fermo).
/// Fa da riserva all'avviso di Windows (<see cref="RisveglioWindows"/>).
/// </summary>
public sealed class SorveglianzaRisveglio(TimeSpan? soglia = null)
{
    /// <summary>Oltre questo intervallo tra due controlli si considera un risveglio.</summary>
    public TimeSpan Soglia { get; } = soglia ?? TimeSpan.FromSeconds(30);

    private DateTime? ultimo;

    /// <summary>Da chiamare a intervalli regolari con l'ora UTC; vero se dal controllo precedente il computer ha dormito.</summary>
    public bool Controlla(DateTime adessoUtc)
    {
        var risveglio = ultimo is { } precedente && adessoUtc - precedente > Soglia;
        ultimo = adessoUtc;
        return risveglio;
    }
}

/// <summary>
/// L'avviso di Windows al risveglio dallo stop (PowerRegisterSuspendResumeNotification, Windows 8 o successivo),
/// senza finestra. <see cref="Risvegliato"/> arriva su un thread di sistema. Dove non c'è non fa nulla:
/// resta <see cref="SorveglianzaRisveglio"/>.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class RisveglioWindows : IDisposable
{
    private const uint NotificaConRichiamo = 2;          // DEVICE_NOTIFY_CALLBACK
    private const uint RipresaAutomatica = 0x12;         // PBT_APMRESUMEAUTOMATIC
    private const uint RipresaUtente = 0x7;              // PBT_APMRESUMESUSPEND

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate uint Richiamo(IntPtr contesto, uint tipo, IntPtr impostazione);

    [StructLayout(LayoutKind.Sequential)]
    private struct ParametriIscrizione
    {
        public IntPtr Callback;
        public IntPtr Context;
    }

    [DllImport("powrprof.dll", ExactSpelling = true)]
    private static extern uint PowerRegisterSuspendResumeNotification(uint flags, IntPtr destinatario, out IntPtr iscrizione);

    [DllImport("powrprof.dll", ExactSpelling = true)]
    private static extern uint PowerUnregisterSuspendResumeNotification(IntPtr iscrizione);

    /// <summary>Il computer si è appena risvegliato.</summary>
    public event Action? Risvegliato;

    private readonly Richiamo richiamo;   // tenuto vivo: Windows lo chiama più tardi
    private IntPtr parametri;
    private IntPtr iscrizione;

    public RisveglioWindows()
    {
        richiamo = (_, tipo, _) =>
        {
            // Windows manda di solito tutti e due gli avvisi: chi riceve li unisce (vedi l'attesa nell'app).
            if (tipo is RipresaAutomatica or RipresaUtente)
            {
                try { Risvegliato?.Invoke(); } catch (Exception) { }
            }
            return 0;
        };
        try
        {
            parametri = Marshal.AllocHGlobal(Marshal.SizeOf<ParametriIscrizione>());
            Marshal.StructureToPtr(new ParametriIscrizione { Callback = Marshal.GetFunctionPointerForDelegate(richiamo) }, parametri, false);
            if (PowerRegisterSuspendResumeNotification(NotificaConRichiamo, parametri, out iscrizione) != 0) iscrizione = IntPtr.Zero;
        }
        catch (Exception)
        {
            // powrprof.dll senza questa funzione (Windows 7): resta il controllo dell'orologio.
            iscrizione = IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        if (iscrizione != IntPtr.Zero)
        {
            try { PowerUnregisterSuspendResumeNotification(iscrizione); } catch (Exception) { }
            iscrizione = IntPtr.Zero;
        }
        if (parametri != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(parametri);
            parametri = IntPtr.Zero;
        }
    }
}
