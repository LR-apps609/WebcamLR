using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Per la diagnosi (1.3): il profilo delle reti collegate (Network List Manager di Windows), con a parte
/// la rete del Tethering USB di Android, e le regole
/// del firewall per WebcamLR (lette dal registro, dove le salva il sistema). La decisione è in
/// WebcamLR.Ricevitore (Diagnosi, RegoleFirewall), provata con i test. Ogni errore vale «non si sa»:
/// meglio non dire nulla che dare un consiglio sbagliato. Da chiamare fuori dal thread dell'interfaccia.
/// </summary>
public static class ReteWindows
{
    private const string ChiavePolitica = @"SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy";

    /// <summary>
    /// Il profilo delle reti normali e, a parte, quello della rete del Tethering USB di Android
    /// (<see cref="Diagnosi.Riassumi(IEnumerable{ReteCollegata})"/>).
    /// </summary>
    public static (ProfiloRete Profilo, ProfiloRete? Tethering) Profili() => Diagnosi.Riassumi(Reti());

    /// <summary>
    /// Le reti collegate con il loro profilo. Una rete è del tethering se una sua connessione passa da una scheda
    /// riconosciuta da <see cref="Collegamenti.TetheringUsb"/> (l'adattatore della connessione è l'Id della scheda).
    /// </summary>
    public static List<ReteCollegata> Reti()
    {
        var reti = new List<ReteCollegata>();
        try
        {
            var tethering = SchedeTethering();
            var tipo = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"));
            if (tipo is null || Activator.CreateInstance(tipo) is not INetworkListManager gestore) return reti;
            try
            {
                var elenco = gestore.GetNetworks(SoloCollegate);
                while (elenco.Next(1, out var rete, out var presi) == 0 && presi == 1 && rete is not null)
                {
                    var profilo = rete.GetCategory() switch
                    {
                        0 => ProfiloRete.Pubblica,
                        1 => ProfiloRete.Privata,
                        2 => ProfiloRete.Dominio,
                        _ => ProfiloRete.Sconosciuto,
                    };
                    reti.Add(new ReteCollegata(profilo, tethering.Count > 0 && DelTethering(rete, tethering)));
                    Marshal.ReleaseComObject(rete);
                }
                Marshal.ReleaseComObject(elenco);
            }
            finally { Marshal.ReleaseComObject(gestore); }
        }
        catch (Exception) { }
        return reti;
    }

    /// <summary>Gli Id delle schede accese del Tethering USB (lo stesso GUID che Network List Manager chiama adattatore).</summary>
    private static HashSet<Guid> SchedeTethering()
    {
        var schede = new HashSet<Guid>();
        foreach (var scheda in NetworkInterface.GetAllNetworkInterfaces())
        {
            try
            {
                if (scheda.OperationalStatus == OperationalStatus.Up && Collegamenti.TetheringUsb(scheda.Description)
                    && Guid.TryParse(scheda.Id, out var id))
                    schede.Add(id);
            }
            catch (Exception) { }
        }
        return schede;
    }

    private static bool DelTethering(INetwork rete, HashSet<Guid> tethering)
    {
        if (rete.GetNetworkConnections() is not IEnumNetworkConnections connessioni) return false;
        try
        {
            while (connessioni.Next(1, out var connessione, out var presi) == 0 && presi == 1 && connessione is not null)
            {
                try
                {
                    if (tethering.Contains(connessione.GetAdapterId())) return true;
                }
                finally { Marshal.ReleaseComObject(connessione); }
            }
            return false;
        }
        finally { Marshal.ReleaseComObject(connessioni); }
    }

    public static StatoFirewall Firewall(ProfiloRete profilo, int porta)
    {
        if (Environment.ProcessPath is not { } programma) return StatoFirewall.Sconosciuto;
        try
        {
            using var regole = Registry.LocalMachine.OpenSubKey($@"{ChiavePolitica}\FirewallRules");
            // Senza poter leggere le regole non si sa nulla: niente avviso.
            if (regole is null) return StatoFirewall.Sconosciuto;
            var testi = Valori(regole);
            using (var criteri = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules"))
            {
                if (criteri is not null) testi.AddRange(Valori(criteri));
            }
            var nomeProfilo = profilo switch
            {
                ProfiloRete.Pubblica => "PublicProfile",
                ProfiloRete.Dominio => "DomainProfile",
                _ => "StandardProfile",
            };
            bool? attivo = null;
            // Un criterio di gruppo (PC aziendali) vale più dell'impostazione locale: si guarda prima quello.
            using (var criterioProfilo = Registry.LocalMachine.OpenSubKey($@"SOFTWARE\Policies\Microsoft\WindowsFirewall\{nomeProfilo}"))
            {
                if (criterioProfilo?.GetValue("EnableFirewall") is int accesoDaCriterio) attivo = accesoDaCriterio != 0;
            }
            using (var chiaveProfilo = Registry.LocalMachine.OpenSubKey($@"{ChiavePolitica}\{nomeProfilo}"))
            {
                if (attivo is null && chiaveProfilo?.GetValue("EnableFirewall") is int acceso) attivo = acceso != 0;
            }
            return RegoleFirewall.Valuta(testi, programma, porta, profilo, attivo);
        }
        catch (Exception) { return StatoFirewall.Sconosciuto; }
    }

    private static List<string> Valori(RegistryKey chiave) =>
        chiave.GetValueNames().Select(nome => chiave.GetValue(nome) as string).OfType<string>().ToList();

    // Network List Manager (netlistmgr.h): solo i metodi che servono, nell'ordine della tabella dei metodi.
    private const int SoloCollegate = 1; // NLM_ENUM_NETWORK_CONNECTED

    [ComImport, Guid("DCB00000-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface INetworkListManager
    {
        IEnumNetworks GetNetworks(int flag);
    }

    [ComImport, Guid("DCB00003-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface IEnumNetworks
    {
        IntPtr NuovoEnumeratore { get; }   // get__NewEnum, non usato

        [PreserveSig]
        int Next(int quanti, out INetwork? rete, out int presi);
    }

    [ComImport, Guid("DCB00002-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface INetwork
    {
        [return: MarshalAs(UnmanagedType.BStr)] string GetName();
        void SetName([MarshalAs(UnmanagedType.BStr)] string nome);
        [return: MarshalAs(UnmanagedType.BStr)] string GetDescription();
        void SetDescription([MarshalAs(UnmanagedType.BStr)] string descrizione);
        Guid GetNetworkId();
        int GetDomainType();
        [return: MarshalAs(UnmanagedType.Interface)] object GetNetworkConnections();
        void GetTimeCreatedAndConnected(out uint creataBassa, out uint creataAlta, out uint collegataBassa, out uint collegataAlta);
        bool IsConnectedToInternet { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        bool IsConnected { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        int GetConnectivity();
        int GetCategory();
    }

    [ComImport, Guid("DCB00006-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface IEnumNetworkConnections
    {
        IntPtr NuovoEnumeratore { get; }   // get__NewEnum, non usato

        [PreserveSig]
        int Next(int quante, out INetworkConnection? connessione, out int prese);
    }

    [ComImport, Guid("DCB00005-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface INetworkConnection
    {
        [return: MarshalAs(UnmanagedType.Interface)] object GetNetwork();
        bool IsConnectedToInternet { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        bool IsConnected { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        int GetConnectivity();
        Guid GetConnectionId();
        Guid GetAdapterId();
        int GetDomainType();
    }
}
