using System.Diagnostics;
using System.Net;
using WebcamLR.Collaudo;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Collaudo.Prova;

/// <summary>
/// Il telefono finto del collaudo contro il ricevitore vero (Ascoltatore e SessioneComputer, come li usa la finestra),
/// su loopback: abbinamento con il gettone del QR, con la conferma, rifiuto, video che arriva e si decodifica.
/// </summary>
public class TelefonoFintoTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(20);

    /// <summary>Un ricevitore in ascolto su loopback, con le sessioni create come fa la finestra.</summary>
    private sealed class Ricevitore : IDisposable
    {
        public readonly Ascoltatore Ascoltatore = new(IPAddress.Loopback, porta: 0);
        public readonly TaskCompletionSource<Ciao> Salutato = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource<FormatoVideo> Formato = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource<Capacita> Capacita = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource Silenzio = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly List<FotogrammaVideo> Fotogrammi = [];
        public readonly IdentitaDispositivo IdComputer = IdentitaDispositivo.Nuova();
        public readonly Abbinamento Abbinamento;

        public Ricevitore()
        {
            Abbinamento = new Abbinamento(IdComputer);
            Ascoltatore.NuovoTelefono += presa =>
            {
                var sessione = new SessioneComputer(presa, "PC di collaudo", Abbinamento, TimeSpan.FromMilliseconds(200));
                sessione.Salutato += ciao => Salutato.TrySetResult(ciao);
                sessione.FormatoRicevuto += f => Formato.TrySetResult(f);
                sessione.CapacitaRicevute += c => Capacita.TrySetResult(c);
                sessione.Silenzio += () => Silenzio.TrySetResult();
                sessione.FotogrammaRicevuto += f => { lock (Fotogrammi) Fotogrammi.Add(f); };
                sessione.Avvia();
            };
        }

        public int QuantiFotogrammi
        {
            get { lock (Fotogrammi) return Fotogrammi.Count; }
        }

        public void Dispose()
        {
            Ascoltatore.Dispose();
            IdComputer.Dispose();
        }
    }

    private static (Telefono Telefono, List<string> Righe) NuovoTelefono(Ricevitore ricevitore, params string[] altre)
    {
        var righe = new List<string>();
        var opzioni = Opzioni.Leggi(["--porta", ricevitore.Ascoltatore.Porta.ToString(), "--risoluzione", "320x180", "--fps", "15", .. altre]);
        var telefono = new Telefono(opzioni, IdentitaDispositivo.Nuova(), riga => { lock (righe) righe.Add(riga); });
        return (telefono, righe);
    }

    private static async Task Aspetta(Func<bool> condizione)
    {
        var orologio = Stopwatch.StartNew();
        while (!condizione())
        {
            if (orologio.Elapsed > Limite) throw new TimeoutException();
            await Task.Delay(50);
        }
    }

    [Fact]
    public async Task ConIlGettoneDelQrEntraSubitoEMandaVideo()
    {
        using var ricevitore = new Ricevitore();
        var associazione = new Associazione(["127.0.0.1"], (ushort)ricevitore.Ascoltatore.Porta, "PC di collaudo",
            Impronta: ricevitore.Abbinamento.Identita.Impronta, Gettone: ricevitore.Abbinamento.Gettone);
        // Il programma applica il QR prima di creare il telefono: qui lo stesso, a mano.
        var righe = new List<string>();
        var opzioni = Opzioni.Leggi(["--risoluzione", "320x180", "--fps", "15", "--nome", "iPhone di prova"]);
        opzioni.ApplicaQr(associazione);
        var telefono = new Telefono(opzioni, IdentitaDispositivo.Nuova(), riga => { lock (righe) righe.Add(riga); });

        var sessione = telefono.SessioneAsync(TimeSpan.FromSeconds(3), null, CancellationToken.None);
        var ciao = await ricevitore.Salutato.Task.WaitAsync(Limite);
        Assert.Equal("iPhone di prova", ciao.Nome);
        Assert.Equal(new FormatoVideo(Codec.H264, 320, 180, 15), await ricevitore.Formato.Task.WaitAsync(Limite));
        Assert.True((await ricevitore.Capacita.Task.WaitAsync(Limite)).SceltaQualita);
        Assert.Equal(Esito.Finita, await sessione.WaitAsync(Limite));
        Assert.Contains(righe, r => r.StartsWith("ACCETTATO"));
        Assert.InRange(ricevitore.QuantiFotogrammi, 20, 60);
        lock (ricevitore.Fotogrammi)
            Assert.All(ricevitore.Fotogrammi, f => Assert.True(f.Chiave && f.ConParametri));
    }

    [Fact]
    public async Task SenzaGettoneIlComputerChiedeConfermaConLoStessoCodice()
    {
        using var ricevitore = new Ricevitore();
        var codiceComputer = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        ricevitore.Abbinamento.ChiediConferma = (nome, codice, _) =>
        {
            codiceComputer.TrySetResult(codice);
            return Task.FromResult(true);
        };
        var (telefono, righe) = NuovoTelefono(ricevitore, "--gettone-sbagliato", "--senza-video");
        var esito = await telefono.SessioneAsync(TimeSpan.FromSeconds(2), null, CancellationToken.None).WaitAsync(Limite);

        Assert.Equal(Esito.Finita, esito);
        var codice = await codiceComputer.Task.WaitAsync(Limite);
        Assert.Contains(righe, r => r.StartsWith($"CODICE {codice}"));
        Assert.Contains(righe, r => r.StartsWith("ACCETTATO"));
    }

    [Fact]
    public async Task NonConsentitoIlTelefonoERifiutato()
    {
        using var ricevitore = new Ricevitore();
        ricevitore.Abbinamento.ChiediConferma = (_, _, _) => Task.FromResult(false);
        var (telefono, righe) = NuovoTelefono(ricevitore, "--senza-video");
        var esito = await telefono.SessioneAsync(TimeSpan.FromSeconds(10), null, CancellationToken.None).WaitAsync(Limite);

        Assert.Equal(Esito.Rifiutato, esito);
        Assert.Contains(righe, r => r.StartsWith("RIFIUTATO"));
    }

    [Fact]
    public async Task LaReteCheCadeDiventaSilenzioSulComputer()
    {
        using var ricevitore = new Ricevitore();
        var associazione = new Associazione(["127.0.0.1"], (ushort)ricevitore.Ascoltatore.Porta, "PC",
            Gettone: ricevitore.Abbinamento.Gettone);
        var opzioni = Opzioni.Leggi(["--risoluzione", "320x180", "--fps", "15", "--interrompi-dopo", "1", "--riconnetti-dopo", "5"]);
        opzioni.ApplicaQr(associazione);
        var righe = new List<string>();
        var telefono = new Telefono(opzioni, IdentitaDispositivo.Nuova(), riga => { lock (righe) righe.Add(riga); });
        var sessione = telefono.SessioneAsync(TimeSpan.FromSeconds(15), opzioni.InterrompiDopo, CancellationToken.None);

        // Il computer passa a «Riconnessione» dopo 3 secondi senza nulla (Protocollo.md, «Sequenza tipica»).
        await ricevitore.Silenzio.Task.WaitAsync(Limite);
        var arrivati = ricevitore.QuantiFotogrammi;
        await Task.Delay(500);
        Assert.Equal(arrivati, ricevitore.QuantiFotogrammi);
        Assert.Equal(Esito.Interrotta, await sessione.WaitAsync(Limite));
        Assert.Contains(righe, r => r.StartsWith("INTERRUZIONE"));
    }

    [Fact]
    public void IlQrSiLeggeDallaSchermata()
    {
        var associazione = new Associazione(["192.168.1.20", "10.0.0.5"], 52741, "PC di Ledion",
            Impronta: "abcdefghijklmnopqrstuv", Gettone: Sicurezza.NuovoGettone());
        var file = Path.Combine(Path.GetTempPath(), $"qr-{Guid.NewGuid():N}.png");
        File.WriteAllBytes(file, IndirizziLocali.QRCodePng(associazione)!);
        try { Assert.Equal(associazione.Testo, LettoreQr.Leggi(file)); }
        finally { File.Delete(file); }
    }

    /// <summary>Il flusso I_PCM è H.264 valido: se c'è ffmpeg (solo sulla macchina di sviluppo) lo si decodifica davvero.</summary>
    [Fact]
    public void IlVideoSiDecodifica()
    {
        var codificatore = new CodificatorePcm(320, 180);
        var disegno = new Disegno(320, 180);
        var file = Path.Combine(Path.GetTempPath(), $"finto-{Guid.NewGuid():N}.h264");
        using (var uscita = File.Create(file))
            for (var i = 0; i < 5; i++)
            {
                disegno.Disegna(i, DateTime.Now, i / 15.0, ["PROVA"], specchia: false);
                uscita.Write(codificatore.Codifica(disegno.Y, disegno.Cb, disegno.Cr));
            }
        try
        {
            ProcessStartInfo avvio = new("ffmpeg", ["-v", "error", "-i", file, "-f", "null", "-"]) { RedirectStandardError = true };
            Process? ffmpeg;
            try { ffmpeg = Process.Start(avvio); }
            catch (System.ComponentModel.Win32Exception) { return; } // niente ffmpeg: si prova solo che si codifica
            var errori = ffmpeg!.StandardError.ReadToEnd();
            ffmpeg.WaitForExit();
            Assert.Equal(0, ffmpeg.ExitCode);
            Assert.Equal("", errori.Trim());
        }
        finally { File.Delete(file); }
    }
}
