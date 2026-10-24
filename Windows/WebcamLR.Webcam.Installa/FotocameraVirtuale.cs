using System.Runtime.InteropServices;

namespace WebcamLR.Webcam.Installa;

/// <summary>
/// MFCreateVirtualCamera (mfsensorgroup.dll, Windows 11) e i tre metodi di IMFVirtualCamera che servono.
/// I metodi si chiamano dalla tabella dell'interfaccia (mfvirtualcamera.h): IUnknown (3), IMFAttributes (30),
/// poi AddDeviceSourceInfo 33, AddProperty 34, AddRegistryEntry 35, Start 36, Stop 37, Remove 38,
/// GetMediaSource 39, SendCameraProperty 40, CreateSyncEvent 41, CreateSyncSemaphore 42, Shutdown 43.
/// Indici, IID {1c08a864-ef6c-4c75-af59-5f2d68da9563} e valori delle enumerazioni (Session 0/System 1,
/// CurrentUser 0/AllUsers 1) verificati con mfvirtualcamera.h (dichiarazioni generate di DirectN) e la documentazione.
/// Windows aggiunge «(Windows Virtual Camera)» al nome: per riconoscerla c'è <see cref="NomiWebcam.ÈLaWebcam"/>.
/// </summary>
internal static unsafe class FotocameraVirtuale
{
    private const int MFVirtualCameraType_SoftwareCameraSource = 0;
    private const int MFVirtualCameraLifetime_System = 1;
    private const int MFVirtualCameraAccess_AllUsers = 1;
    private const uint MF_VERSION = 0x00020070;

    private const int IndiceStart = 36;
    private const int IndiceRemove = 38;
    private const int IndiceShutdown = 43;

    /// <summary>
    /// Crea la webcam per tutti gli utenti e per sempre (durata «System»: resta anche dopo il riavvio, finché non la si
    /// rimuove). Se esiste già con lo stesso nome e la stessa sorgente, Windows restituisce quella.
    /// </summary>
    public static int Crea(Action<string> registro)
    {
        return ConFotocamera(registro, camera =>
        {
            var hr = Chiama(camera, IndiceStart, 0);
            registro($"IMFVirtualCamera::Start: 0x{hr:X8}");
            return hr;
        });
    }

    /// <summary>Toglie la webcam da Windows (le app non la vedono più), senza riavvio.</summary>
    public static int Rimuovi(Action<string> registro)
    {
        return ConFotocamera(registro, camera =>
        {
            var hr = Chiama(camera, IndiceRemove);
            registro($"IMFVirtualCamera::Remove: 0x{hr:X8}");
            return hr;
        });
    }

    private static int ConFotocamera(Action<string> registro, Func<nint, int> azione)
    {
        var avviata = MFStartup(MF_VERSION, 0);
        registro($"MFStartup: 0x{avviata:X8}");
        try
        {
            var hr = MFCreateVirtualCamera(MFVirtualCameraType_SoftwareCameraSource, MFVirtualCameraLifetime_System,
                MFVirtualCameraAccess_AllUsers, NomiWebcam.Nome, NomiWebcam.ClsidTraGraffe, null, 0, out var camera);
            registro($"MFCreateVirtualCamera: 0x{hr:X8}");
            if (hr < 0) return hr;
            try
            {
                hr = azione(camera);
                var chiusa = Chiama(camera, IndiceShutdown);
                registro($"IMFVirtualCamera::Shutdown: 0x{chiusa:X8}");
                return hr;
            }
            finally { Marshal.Release(camera); }
        }
        catch (EntryPointNotFoundException)
        {
            // Windows 10: mfsensorgroup.dll c'è ma non ha MFCreateVirtualCamera.
            registro("MFCreateVirtualCamera non esiste in questo Windows");
            return unchecked((int)0x80004001);
        }
        catch (DllNotFoundException)
        {
            registro("mfsensorgroup.dll non trovato");
            return unchecked((int)0x8007007E);
        }
        finally
        {
            if (avviata >= 0) MFShutdown();
        }
    }

    private static int Chiama(nint oggetto, int indice)
    {
        var tabella = *(nint**)oggetto;
        return ((delegate* unmanaged[Stdcall]<nint, int>)tabella[indice])(oggetto);
    }

    private static int Chiama(nint oggetto, int indice, nint argomento)
    {
        var tabella = *(nint**)oggetto;
        return ((delegate* unmanaged[Stdcall]<nint, nint, int>)tabella[indice])(oggetto, argomento);
    }

    [DllImport("mfsensorgroup.dll", CharSet = CharSet.Unicode)]
    private static extern int MFCreateVirtualCamera(int type, int lifetime, int access, string friendlyName, string sourceId,
        Guid[]? categories, uint categoryCount, out nint virtualCamera);

    [DllImport("mfplat.dll")] private static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")] private static extern int MFShutdown();
}
