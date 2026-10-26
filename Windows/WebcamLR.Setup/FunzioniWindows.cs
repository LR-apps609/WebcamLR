using System.Runtime.InteropServices;

namespace WebcamLR.Setup;

/// <summary>
/// Le poche funzioni di Windows che servono all'installatore, chiamate direttamente: niente WinForms né WPF,
/// così l'exe autonomo resta piccolo e il trimming non toglie niente di necessario.
/// </summary>
internal static unsafe class FunzioniWindows
{
    private const uint MB_OK = 0x0, MB_OKCANCEL = 0x1, MB_YESNO = 0x4;
    private const uint MB_ICONERROR = 0x10, MB_ICONQUESTION = 0x20, MB_ICONWARNING = 0x30, MB_ICONINFORMATION = 0x40;
    private const uint MB_SETFOREGROUND = 0x10000, MB_TOPMOST = 0x40000;
    private const int IDOK = 1, IDYES = 6;

    public static void Informa(string testo) => Mostra(testo, MB_OK | MB_ICONINFORMATION);
    public static void Avvisa(string testo) => Mostra(testo, MB_OK | MB_ICONWARNING);
    public static void Errore(string testo) => Mostra(testo, MB_OK | MB_ICONERROR);
    public static bool Conferma(string testo) => Mostra(testo, MB_OKCANCEL | MB_ICONINFORMATION) == IDOK;
    public static bool Chiedi(string testo) => Mostra(testo, MB_YESNO | MB_ICONQUESTION) == IDYES;

    private static int Mostra(string testo, uint tipo) =>
        MessageBoxW(0, testo, Testi.S($"Installazione di {DatiProdotto.Nome}", $"{DatiProdotto.Nome} Setup"), tipo | MB_SETFOREGROUND | MB_TOPMOST);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(nint finestra, string testo, string titolo, uint tipo);

    public const uint MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileExW(string esistente, string? nuovo, uint flag);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool DeleteFileW(string nome);

    /// <summary>
    /// Il collegamento nel menu Start (IShellLinkW + IPersistFile). I metodi si chiamano dalla tabella delle interfacce,
    /// come in WebcamLR.Webcam.Installa: niente COM «automatico» di .NET, che il trimming toglie.
    /// Ordine dei metodi da ShObjIdl_core.h e ObjIdl.h: IShellLinkW SetDescription 7, SetWorkingDirectory 9,
    /// SetIconLocation 17, SetPath 20; IPersistFile Save 6; IUnknown QueryInterface 0, Release 2.
    /// </summary>
    public static int CreaCollegamento(string file, string destinazione, string cartellaDiLavoro, string descrizione)
    {
        var clsidShellLink = new Guid("00021401-0000-0000-C000-000000000046");
        var iidShellLinkW = new Guid("000214F9-0000-0000-C000-000000000046");
        var iidPersistFile = new Guid("0000010B-0000-0000-C000-000000000046");

        var inizializzato = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
        try
        {
            var hr = CoCreateInstance(&clsidShellLink, 0, CLSCTX_INPROC_SERVER, &iidShellLinkW, out var collegamento);
            if (hr < 0) return hr;
            try
            {
                fixed (char* percorso = destinazione, lavoro = cartellaDiLavoro, testo = descrizione)
                {
                    var tabella = *(nint**)collegamento;
                    hr = ((delegate* unmanaged[Stdcall]<nint, char*, int>)tabella[20])(collegamento, percorso);
                    if (hr < 0) return hr;
                    ((delegate* unmanaged[Stdcall]<nint, char*, int>)tabella[9])(collegamento, lavoro);
                    ((delegate* unmanaged[Stdcall]<nint, char*, int>)tabella[7])(collegamento, testo);
                    ((delegate* unmanaged[Stdcall]<nint, char*, int, int>)tabella[17])(collegamento, percorso, 0);

                    nint persistente;
                    hr = ((delegate* unmanaged[Stdcall]<nint, Guid*, nint*, int>)tabella[0])(collegamento, &iidPersistFile, &persistente);
                    if (hr < 0) return hr;
                    try
                    {
                        fixed (char* nomeFile = file)
                        {
                            var tabellaFile = *(nint**)persistente;
                            return ((delegate* unmanaged[Stdcall]<nint, char*, int, int>)tabellaFile[6])(persistente, nomeFile, 1);
                        }
                    }
                    finally { Marshal.Release(persistente); }
                }
            }
            finally { Marshal.Release(collegamento); }
        }
        finally
        {
            if (inizializzato >= 0) CoUninitialize();
        }
    }

    private const uint COINIT_APARTMENTTHREADED = 0x2;
    private const uint CLSCTX_INPROC_SERVER = 0x1;

    [DllImport("ole32.dll")] private static extern int CoInitializeEx(nint riservato, uint modo);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(Guid* clsid, nint esterno, uint contesto, Guid* iid, out nint oggetto);

    /// <summary>Dice a Esplora risorse e al menu Start che le associazioni e le icone sono cambiate.</summary>
    public static void AvvisaShell() => SHChangeNotify(0x08000000 /* SHCNE_ASSOCCHANGED */, 0, 0, 0);

    [DllImport("shell32.dll")] private static extern void SHChangeNotify(int evento, uint flag, nint a, nint b);
}
