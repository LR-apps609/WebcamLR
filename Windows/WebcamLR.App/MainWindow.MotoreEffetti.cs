using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using WebcamLR.Effetti;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Gli effetti sul computer (27 ottobre, come iVCam; Documenti/Effetti su Windows.md): il telefono manda il video com'è,
/// il motore del PC (MotoreVideo, libreria WebcamLR.Effetti) lo elabora una volta e l'immagine elaborata va a tutte le
/// uscite: anteprima e finestra mini (VideoElaborato, sopra il video del lettore), webcam virtuale, foto e registrazione.
/// La colonna «Effetti», «Specchia», «Sfondo» e la pagina delle impostazioni leggono e scrivono le scelte del motore
/// (effettiComputer, salvate nelle preferenze); le regole Pro le applica il PC (RegoleMotore, <c>capacita.pro</c>).
/// Lo stesso fa il Mac (Mac/Sorgenti/MotoreEffetti.swift), con gli stessi nomi.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>L'interruttore (RegoleEffettiComputer.EffettiSulComputer), letto come proprietà: niente avvisi di codice irraggiungibile.</summary>
    private static bool SulComputer => RegoleEffettiComputer.EffettiSulComputer;

    private readonly MotoreVideo motoreVideo = new();

    /// <summary>Le scelte del motore del PC, le stesse per qualsiasi telefono; restano da una volta all'altra.</summary>
    private readonly ControlloEffetti effettiComputer = new(sulComputer: true, iniziali: RegoleEffettiComputer.DaTesto(Preferenze.RegoleEffettiComputer));

    /// <summary>Le capacità degli effetti: quelle del telefono, più quelle del PC con gli effetti sul computer.</summary>
    private Capacita? capacitaEffetti => RegoleEffettiComputer.CapacitaEffetti(capacitaAttuali, SulComputer);

    // Quale sfondo e quale logo il motore ha già (o sta leggendo): si rileggono solo quando cambiano.
    private string? sfondoNelMotore;
    private string? logoNelMotore;
    private bool modelloPreparato;

    // L'anteprima elaborata: l'ultima immagine dal motore, una sola in coda per il thread dell'interfaccia.
    private ImmagineBgra? ultimaElaborata;
    private int anteprimaInCoda;
    private WriteableBitmap? bitmapElaborata;
    private DispatcherQueueTimer? controlloElaborata;
    /// <summary>Secondi dall'ultima riga «Effetti sul PC» nel registro (ogni 30, mentre il motore lavora).</summary>
    private int secondiMotore;

    private void InizializzaMotoreEffetti()
    {
        if (!SulComputer) return;
        effettiComputer.Cambiati += () =>
        {
            Preferenze.RegoleEffettiComputer = RegoleEffettiComputer.InTesto(effettiComputer.Valori);
            AggiornaMotore();
        };
        effettiComputer.ImpostaImmagini(memoriaImmagini.Impronta(UsoImmagine.Sfondo), memoriaImmagini.Impronta(UsoImmagine.Logo));
        uscitaWebcam.DaMotore = true;
        motoreVideo.ServonoFotogrammi = () => uscitaWebcam.InUso || Volatile.Read(ref registrazione) is RegistrazioneElaborata;
        motoreVideo.Fotogramma += SuFotogrammaMotore;
        motoreVideo.Evento += registro.Aggiungi;
        motoreVideo.Stato.ImpostaDisegnoScritta(new DisegnoScritta());
        controlloElaborata = coda.CreateTimer();
        controlloElaborata.Interval = TimeSpan.FromMilliseconds(250);
        controlloElaborata.Tick += (_, _) => ControllaAnteprimaElaborata();
        controlloElaborata.Start();
        VideoElaborato.Stretch = Video.Stretch;
        AggiornaMotore();
    }

    /// <summary>
    /// Le scelte (effettiComputer) al motore, con le regole Pro del telefono nella webcam e quelle della fotocamera
    /// frontale; poi le immagini che servono. Dopo ogni cambio di scelte, di telefono, di capacità o di stato.
    /// </summary>
    private void AggiornaMotore()
    {
        if (!SulComputer) return;
        var scelti = effettiComputer.Valori;
        var immagine = RegoleSfondo.ImmagineAttuale(scelti, SfondiPronti.Tutti);
        if (immagine == SfondiPronti.Personale && memoriaImmagini.Impronta(UsoImmagine.Sfondo) is null) immagine = null;
        var impostazioni = RegoleMotore.Da(scelti, ProAttivo, statoTelefono, immagine, memoriaImmagini.Impronta(UsoImmagine.Logo) is not null);
        motoreVideo.Stato.Imposta(impostazioni);
        motoreVideo.Abilita(Scelto is not null);
        // Il modello si apre appena serve (lo sfondo o i volti): il primo fotogramma con lo sfondo non aspetta.
        var serveModello = impostazioni.SfondoAcceso || impostazioni.ServonoVolti;
        if (serveModello && !modelloPreparato && Scelto is not null) motoreVideo.Prepara();
        modelloPreparato = serveModello && Scelto is not null;
        AggiornaImmaginiMotore(impostazioni);
    }

    /// <summary>Legge in sottofondo l'immagine dello sfondo (le grandi in Assets\Sfondi\grandi, o la tua) e il logo.</summary>
    private void AggiornaImmaginiMotore(ImpostazioniMotore impostazioni)
    {
        if (impostazioni.Sfondo == ModiSfondo.Sostituito && impostazioni.ImmagineSfondo is { } id)
        {
            var personale = id == SfondiPronti.Personale;
            var chiave = personale ? $"{id}-{memoriaImmagini.Impronta(UsoImmagine.Sfondo)}" : id;
            if (chiave != sfondoNelMotore)
            {
                sfondoNelMotore = chiave;
                _ = CaricaSfondoMotoreAsync(id, chiave, personale);
            }
        }
        var chiaveLogo = impostazioni.Logo ? memoriaImmagini.Impronta(UsoImmagine.Logo) : null;
        if (chiaveLogo != logoNelMotore)
        {
            logoNelMotore = chiaveLogo;
            if (chiaveLogo is null) motoreVideo.Stato.ImpostaLogo(null);
            else _ = CaricaLogoMotoreAsync(chiaveLogo);
        }
    }

    private async Task CaricaSfondoMotoreAsync(string id, string chiave, bool personale)
    {
        try
        {
            var dati = personale
                ? memoriaImmagini.Leggi(UsoImmagine.Sfondo)
                : await Task.Run(() => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Assets", "Sfondi", "grandi", id + ".jpg")));
            if (dati is null) return;
            var immagine = await DecodificaAsync(dati, alfa: false);
            // Un'altra scelta arrivata intanto vince: questa non si mette più.
            if (immagine is not null && sfondoNelMotore == chiave) motoreVideo.Stato.ImpostaSfondo(id, immagine);
        }
        catch (Exception errore)
        {
            registro.Aggiungi(Testi.T("Effetti_SfondoNonLetto", id, errore.Message));
        }
    }

    private async Task CaricaLogoMotoreAsync(string chiave)
    {
        try
        {
            if (memoriaImmagini.Leggi(UsoImmagine.Logo) is not { } dati) return;
            var immagine = await DecodificaAsync(dati, alfa: true);
            if (immagine is not null && logoNelMotore == chiave) motoreVideo.Stato.ImpostaLogo(immagine);
        }
        catch (Exception errore)
        {
            registro.Aggiungi(Testi.T("Effetti_SfondoNonLetto", "logo", errore.Message));
        }
    }

    /// <summary>Un JPEG o PNG in BGRA (girato secondo l'EXIF); con <paramref name="alfa"/> la trasparenza non premoltiplicata.</summary>
    private static async Task<ImmagineBgra?> DecodificaAsync(byte[] dati, bool alfa)
    {
        using var flusso = new InMemoryRandomAccessStream();
        using (var scrittore = new DataWriter(flusso))
        {
            scrittore.WriteBytes(dati);
            await scrittore.StoreAsync();
            scrittore.DetachStream();
        }
        flusso.Seek(0);
        var decodificatore = await BitmapDecoder.CreateAsync(flusso);
        using var bitmap = await decodificatore.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8,
            alfa ? BitmapAlphaMode.Straight : BitmapAlphaMode.Ignore, new BitmapTransform(),
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
        if (bitmap.PixelWidth <= 0 || bitmap.PixelHeight <= 0) return null;
        var immagine = new ImmagineBgra(bitmap.PixelWidth, bitmap.PixelHeight);
        bitmap.CopyToBuffer(immagine.Dati.AsBuffer());
        if (!alfa)
        {
            for (var i = 3; i < immagine.Dati.Length; i += 4) immagine.Dati[i] = 255;
        }
        return immagine;
    }

    // MARK: uscite

    /// <summary>
    /// Su un thread del motore, per ogni fotogramma per le uscite: webcam e registrazione subito (copiano), l'anteprima
    /// sul thread dell'interfaccia con l'ultima immagine elaborata.
    /// </summary>
    private void SuFotogrammaMotore(ImmagineBgra immagine, bool elaborata)
    {
        uscitaWebcam.Scrivi(immagine, motoreVideo.Scarto);
        (Volatile.Read(ref registrazione) as RegistrazioneElaborata)?.Accoda(immagine);
        if (!elaborata) return;
        Volatile.Write(ref ultimaElaborata, immagine);
        if (Interlocked.Exchange(ref anteprimaInCoda, 1) == 0) coda.TryEnqueue(MostraElaborata);
    }

    /// <summary>L'ultima immagine elaborata nell'anteprima (e nella finestra mini), sopra il video del lettore.</summary>
    private void MostraElaborata()
    {
        Volatile.Write(ref anteprimaInCoda, 0);
        var immagine = Volatile.Read(ref ultimaElaborata);
        if (immagine is null || !motoreVideo.Attivo || Scelto is null || !Video.IsLoaded) return;
        try
        {
            if (bitmapElaborata is null || bitmapElaborata.PixelWidth != immagine.Larghezza || bitmapElaborata.PixelHeight != immagine.Altezza)
            {
                bitmapElaborata = new WriteableBitmap(immagine.Larghezza, immagine.Altezza);
                VideoElaborato.Source = bitmapElaborata;
            }
            using (var flusso = bitmapElaborata.PixelBuffer.AsStream())
                flusso.Write(immagine.Dati, 0, immagine.Passo * immagine.Altezza);
            bitmapElaborata.Invalidate();
            VideoElaborato.Visibility = Visibility.Visible;
            if (immagine.Timestamp is ulong timestamp && motoreVideo.Scarto is long scarto)
            {
                var adesso = Orologio.Adesso();
                if (RitardoVetro.Ms(timestamp, scarto, adesso) is int ms) motoreVideo.RitardoAnteprima.Aggiungi(ms, adesso);
            }
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Effetti spenti (o nessun telefono): si torna al video del lettore. Finché il motore lavora l'anteprima resta
    /// l'ultima immagine elaborata, anche se un fotogramma tarda: mai lo sfondo vero.
    /// </summary>
    private void ControllaAnteprimaElaborata()
    {
        if (VideoElaborato.Visibility == Visibility.Collapsed) return;
        if (motoreVideo.Attivo && Scelto is not null && Video.Visibility == Visibility.Visible) return;
        NascondiElaborata();
    }

    private void NascondiElaborata()
    {
        VideoElaborato.Visibility = Visibility.Collapsed;
        Volatile.Write(ref ultimaElaborata, null);
    }

    // MARK: telefono

    /// <summary>Un telefono è entrato (sessione nuova): spegne i suoi effetti di immagine, che ora fa il PC.</summary>
    private void SpegniEffettiDelTelefono(TelefonoCollegato collegato, SessioneComputer attiva)
    {
        if (!SulComputer) return;
        _ = ComandaAsync(attiva, RegoleEffettiComputer.SpegniEffettiDelTelefono);
        registro.Aggiungi(Testi.T("Registro_EffettiSpentiTelefono", DiChi(collegato)));
    }

    /// <summary>Il telefono nella webcam è cambiato (o non c'è più): il motore segue lui, con le sue regole Pro.</summary>
    private void MotoreSegueScelto()
    {
        if (!SulComputer) return;
        effettiComputer.Azzera();
        if (Scelto is { } scelto)
        {
            if (scelto.Capacita is { } capacita) effettiComputer.Capacita(capacita);
            if (scelto.Stato is { } stato) effettiComputer.Stato(stato, AdessoMs);
            if (scelto.Formato is { } formato) motoreVideo.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
            else motoreVideo.Ferma();
        }
        else
        {
            motoreVideo.Ferma();
            NascondiElaborata();
        }
        secondiMotore = 0;
        AggiornaMotore();
    }

    // MARK: misure

    /// <summary>
    /// Ogni secondo, con le statistiche del telefono nella webcam: gli avvisi del motore subito (qualità scesa, maschera
    /// in errore, dove gira il ritaglio), e ogni 30 secondi, mentre lavora, i suoi tempi.
    /// </summary>
    private void RegistraMotore(TelefonoCollegato collegato)
    {
        if (!SulComputer) return;
        foreach (var nota in motoreVideo.PrendiNote())
        {
            registro.Aggiungi(nota switch
            {
                MotoreEffetti.Nota.Livello l => Testi.T("Registro_EffettiLivello", l.FotogrammaMs, l.MascheraMs, l.ResaMs, NomeLivello(l.Nuovo)),
                MotoreEffetti.Nota.ErroreMaschera e => Testi.T("Registro_EffettiErrore", e.Totale, e.Errore),
                MotoreEffetti.Nota.Fonte f => f.Motivo is { } motivo
                    ? Testi.T("Registro_EffettiFonteMotivo", NomeFonte(f.InUso, f.Modello), motivo)
                    : Testi.T("Registro_EffettiFonte", NomeFonte(f.InUso, f.Modello)),
                _ => "",
            });
        }
        var misure = motoreVideo.PrendiMisure();
        misureMotore = misure;
        if (misure.EffettiMs is not int ms)
        {
            secondiMotore = 0;
            return;
        }
        if (++secondiMotore < 30) return;
        secondiMotore = 0;
        registro.Aggiungi(Testi.T("Registro_EffettiMotore", DiChi(collegato), ms, Millisecondi(misure.MascheraMs), Millisecondi(misure.ResaMs),
            NomeLivello(misure.Livello), misure.Fonte is { } fonte ? NomeFonte(fonte.InUso, fonte.Modello) : "—", misure.Scartati, misure.SenzaMaschera,
            RitardoNelRegistro.Testo(motoreVideo.RitardoAnteprima.Valore(Orologio.Adesso()))));
    }

    /// <summary>Le ultime misure del motore, per la riga «Effetti» nei numeri.</summary>
    private MotoreEffetti.Misure? misureMotore;

    /// <summary>La riga «Effetti» dei numeri (nelle «Tappe»): null se il motore non lavora.</summary>
    private string? RigaNumeriEffetti() =>
        SulComputer && motoreVideo.Attivo && misureMotore is { EffettiMs: int ms } m
            ? Testi.T("Numeri_Effetti", ms, Millisecondi(m.MascheraMs), Millisecondi(m.ResaMs))
            : null;

    private static string Millisecondi(double? ms) => ms is double v ? $"{Lingua.Decimale(v, "0.0")} ms" : "—";

    /// <summary>«scheda video, modello pieno», «processore, modello leggero».</summary>
    private static string NomeFonte(Acceleratore inUso, ModelloRitaglio modello) => Testi.T("Effetti_Fonte",
        inUso == Acceleratore.SchedaVideo ? Testi.T("Effetti_SchedaVideo") : Testi.T("Effetti_Processore"),
        modello == ModelloRitaglio.Pieno ? Testi.T("Effetti_ModelloPieno") : Testi.T("Effetti_ModelloLeggero"));

    private static string NomeLivello(LivelloResa livello) => livello switch
    {
        LivelloResa.BordoLeggero => Testi.T("Effetti_LivelloBordoLeggero"),
        LivelloResa.Veloce => Testi.T("Effetti_LivelloVeloce"),
        _ => Testi.T("Effetti_LivelloPieno"),
    };
}
