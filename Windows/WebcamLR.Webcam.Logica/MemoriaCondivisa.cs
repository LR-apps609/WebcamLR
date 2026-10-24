using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace WebcamLR.Webcam;

/// <summary>
/// La memoria condivisa «Global\WebcamLR.Video» con il suo evento, solo su Windows.
/// La sorgente (Frame Server, LocalService) la crea con <see cref="Crea"/> e i permessi di
/// <see cref="NomiWebcam.SddlMemoria"/>; l'app la apre con <see cref="Apri"/>, che fallisce finché nessuna app
/// ha mai aperto la webcam dalla partenza di Frame Server.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed unsafe class MemoriaCondivisa : IDisposable
{
    private nint mappatura;
    private nint vista;
    private nint evento;

    public AnelloFotogrammi Anello { get; }

    private MemoriaCondivisa(nint mappatura, nint vista, nint evento)
    {
        this.mappatura = mappatura;
        this.vista = vista;
        this.evento = evento;
        Anello = new AnelloFotogrammi((byte*)vista, AnelloFotogrammi.DimensioneTotale);
    }

    /// <summary>Lato sorgente: crea (o apre, se un altro processo di Frame Server l'ha già creata) e prepara l'intestazione.</summary>
    public static MemoriaCondivisa Crea()
    {
        var dimensione = AnelloFotogrammi.DimensioneTotale;
        nint mappatura = 0, vista = 0, evento = 0;
        try
        {
            using (var attributi = new AttributiSicurezza(NomiWebcam.SddlMemoria))
            {
                mappatura = CreateFileMappingW(-1, attributi.Puntatore, PAGE_READWRITE,
                    (uint)(dimensione >> 32), (uint)(dimensione & 0xFFFFFFFF), NomiWebcam.NomeMemoria);
            }
            if (mappatura == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileMapping");
            vista = MapViewOfFile(mappatura, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, (nuint)dimensione);
            if (vista == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "MapViewOfFile");
            using (var attributi = new AttributiSicurezza(NomiWebcam.SddlEvento))
            {
                evento = CreateEventW(attributi.Puntatore, false, false, NomiWebcam.NomeEvento);
            }
            if (evento == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateEvent");
            var memoria = new MemoriaCondivisa(mappatura, vista, evento);
            memoria.Anello.Prepara();
            return memoria;
        }
        catch
        {
            if (vista != 0) UnmapViewOfFile(vista);
            if (mappatura != 0) CloseHandle(mappatura);
            if (evento != 0) CloseHandle(evento);
            throw;
        }
    }

    /// <summary>Lato app: null se la sorgente non l'ha ancora creata o se l'intestazione è di un'altra versione.</summary>
    public static MemoriaCondivisa? Apri()
    {
        var mappatura = OpenFileMappingW(FILE_MAP_READ | FILE_MAP_WRITE, false, NomiWebcam.NomeMemoria);
        if (mappatura == 0) return null;
        var vista = MapViewOfFile(mappatura, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, (nuint)AnelloFotogrammi.DimensioneTotale);
        if (vista == 0)
        {
            CloseHandle(mappatura);
            return null;
        }
        var evento = OpenEventW(EVENT_MODIFY_STATE | SYNCHRONIZE, false, NomiWebcam.NomeEvento);
        var memoria = new MemoriaCondivisa(mappatura, vista, evento);
        if (!memoria.Anello.Valido)
        {
            memoria.Dispose();
            return null;
        }
        return memoria;
    }

    /// <summary>L'app avvisa la sorgente che c'è un fotogramma nuovo.</summary>
    public void Segnala()
    {
        if (evento != 0) SetEvent(evento);
    }

    /// <summary>La sorgente aspetta un fotogramma nuovo, al massimo per il tempo dato. Vero se è arrivato.</summary>
    public bool Aspetta(int millisecondi) => evento != 0 && WaitForSingleObject(evento, (uint)Math.Max(0, millisecondi)) == 0;

    public void Dispose()
    {
        if (vista != 0) { UnmapViewOfFile(vista); vista = 0; }
        if (mappatura != 0) { CloseHandle(mappatura); mappatura = 0; }
        if (evento != 0) { CloseHandle(evento); evento = 0; }
    }

    /// <summary>SECURITY_ATTRIBUTES con il descrittore costruito da una stringa SDDL.</summary>
    private sealed class AttributiSicurezza : IDisposable
    {
        private nint descrittore;
        private readonly nint attributi;
        public nint Puntatore => attributi;

        public AttributiSicurezza(string sddl)
        {
            if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out descrittore, out _))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ConvertStringSecurityDescriptorToSecurityDescriptor");
            attributi = Marshal.AllocHGlobal(sizeof(SECURITY_ATTRIBUTES));
            *(SECURITY_ATTRIBUTES*)attributi = new SECURITY_ATTRIBUTES
            {
                nLength = (uint)sizeof(SECURITY_ATTRIBUTES), lpSecurityDescriptor = descrittore, bInheritHandle = 0,
            };
        }

        public void Dispose()
        {
            Marshal.FreeHGlobal(attributi);
            if (descrittore != 0) { LocalFree(descrittore); descrittore = 0; }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SECURITY_ATTRIBUTES
    {
        public uint nLength;
        public nint lpSecurityDescriptor;
        public int bInheritHandle;
    }

    private const uint PAGE_READWRITE = 0x04;
    private const uint FILE_MAP_WRITE = 0x0002;
    private const uint FILE_MAP_READ = 0x0004;
    private const uint EVENT_MODIFY_STATE = 0x0002;
    private const uint SYNCHRONIZE = 0x00100000;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint CreateFileMappingW(nint file, nint attributi, uint protezione, uint dimensioneAlta, uint dimensioneBassa, string nome);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint OpenFileMappingW(uint accesso, bool eredita, string nome);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint MapViewOfFile(nint mappatura, uint accesso, uint posizioneAlta, uint posizioneBassa, nuint byteDaMappare);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UnmapViewOfFile(nint indirizzo);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint CreateEventW(nint attributi, bool resetManuale, bool statoIniziale, string nome);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint OpenEventW(uint accesso, bool eredita, string nome);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetEvent(nint evento);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(nint oggetto, uint millisecondi);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(nint oggetto);

    [DllImport("kernel32.dll")]
    private static extern nint LocalFree(nint memoria);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revisione, out nint descrittore, out uint lunghezza);
}
