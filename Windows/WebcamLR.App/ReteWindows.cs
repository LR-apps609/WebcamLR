using System.Runtime.InteropServices;
using Microsoft.Win32;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Per la diagnosi (1.3): il profilo delle reti collegate (Network List Manager di Windows) e le regole
/// del firewall per WebcamLR (lette dal registro, dove le salva il sistema). La decisione è in
/// WebcamLR.Ricevitore (Diagnosi, RegoleFirewall), provata con i test. Ogni errore vale «non si sa»:
/// meglio non dire nulla che dare un consiglio sbagliato. Da chiamare fuori dal thread dell'interfaccia.
/// </summary>
public static class ReteWindows
{
    private const string ChiavePolitica = @"SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy";

    public static ProfiloRete Profilo()
    {
        try
        {
            var tipo = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"));
            if (tipo is null || Activator.CreateInstance(tipo) is not INetworkListManager gestore) return ProfiloRete.Sconosciuto;
            var profili = new List<ProfiloRete>();
            try
            {
                var reti = gestore.GetNetworks(ReteCollegata);
                while (reti.Next(1, out var rete, out var presi) == 0 && presi == 1 && rete is not null)
                {
                    profili.Add(rete.GetCategory() switch
                    {
                        0 => ProfiloRete.Pubblica,
                        1 => ProfiloRete.Privata,
                        2 => ProfiloRete.Dominio,
                        _ => ProfiloRete.Sconosciuto,
                    });
                    Marshal.ReleaseComObject(rete);
                }
                Marshal.ReleaseComObject(reti);
            }
            finally { Marshal.ReleaseComObject(gestore); }
            return Diagnosi.Riassumi(profili);
        }
        catch (Exception) { return ProfiloRete.Sconosciuto; }
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
    private const int ReteCollegata = 1; // NLM_ENUM_NETWORK_CONNECTED

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
}
