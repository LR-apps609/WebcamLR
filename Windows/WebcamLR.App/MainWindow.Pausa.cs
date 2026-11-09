using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// Pausa intelligente (P07, P10) e 60 fps per la webcam (P12), come sul Mac.
/// Il PC dice al telefono se la finestra mostra il video («anteprima»): subito dopo il benvenuto (SessioneComputer) e a
/// ogni cambiamento (ridotta a icona, nascosta accanto all'orologio, riaperta; la finestra mini conta come visibile, e
/// anche una registrazione in corso, che senza video resterebbe ferma). Dal 27 ottobre il telefono non si ferma più per
/// questo (il video continua finché WebcamLR è aperta, anche ridotta a icona): «anteprima» serve ai telefoni di prima, che
/// senza app e senza finestra visibile da 10 secondi si fermavano. Quando lo stato porta «pausa» (faccia in giù, dal
/// telefono, calore, app in sottofondo, fotocamera interrotta; «nessuna app» solo i telefoni di prima), sopra il video
/// compare «In pausa» con il motivo, in toni calmi. In sottofondo il telefono può tacere: per 10 minuti niente
/// «Riconnessione» (TolleranzaSottofondo). Il registro ha una riga a ogni inizio di pausa e una alla ripresa, con la durata. Le decisioni sono in PausaIntelligente e Richiesta60Fps, provate con i test.
/// Qualità 18, pausa automatica: quando nessuna app usa la webcam, non si registra e nessuno guarda la finestra (non in
/// primo piano, e niente mini) da 20 secondi, il PC chiede ai telefoni di spegnere la fotocamera («pausa-automatica»), e la
/// toglie appena serve. La regola è RegolaPausaAutomatica (provata a tempi finti); qui solo i suoi ingressi e l'invio.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Lo legge anche il thread di rete, per la sessione nuova prima del benvenuto.</summary>
    private bool anteprimaVisibile = true;
    /// <summary>
    /// R18: la finestra mostra l'anteprima (aperta o mini, non ridotta né nascosta). Lo legge il thread del motore: a
    /// finestra nascosta l'immagine elaborata (~8 MB) non si copia sul thread dell'interfaccia.
    /// </summary>
    private bool finestraMostrata = true;
    private DispatcherQueueTimer? controlloAnteprima;
    private readonly Richiesta60Fps richiesta60Fps = new();
    /// <summary>Qualità 18: la regola dei 20 secondi, sul thread dell'interfaccia.</summary>
    private readonly RegolaPausaAutomatica regolaPausa = new();
    /// <summary>L'interruttore «Pausa quando nessuna app usa la webcam» (Preferenze.PausaAutomatica).</summary>
    private bool pausaAutomaticaAccesa = true;
    /// <summary>Le sessioni già viste dalla regola: una nuova (telefono appena collegato, anche al cavo) riparte da capo.</summary>
    private readonly HashSet<SessioneComputer> sessioniInPausaAutomatica = [];

    private void InizializzaPausa()
    {
        AppWindow.Changed += (_, _) => AggiornaAnteprimaVisibile();
        VisibilityChanged += (_, _) => AggiornaAnteprimaVisibile();
        // Riserva: non tutti i cambi (per esempio la registrazione che parte) hanno un evento della finestra.
        controlloAnteprima = coda.CreateTimer();
        controlloAnteprima.Interval = TimeSpan.FromSeconds(1);
        controlloAnteprima.Tick += (_, _) => AggiornaAnteprimaVisibile();
        controlloAnteprima.Start();
        uscitaWebcam.FpsChiestiCambiato += _ => coda.TryEnqueue(Valuta60Fps);
        // Qualità 18: la finestra torna in primo piano (o la lascia): la pausa automatica si decide subito, non al tick.
        Activated += (_, _) => coda.TryEnqueue(ValutaPausaAutomatica);
        InizializzaPausaAutomatica();
        // Il primo controllo a finestra già mostrata (nel costruttore non lo è ancora): fino ad allora vale «visibile».
    }

    private void FermaPausa() => controlloAnteprima?.Stop();

    // MARK: anteprima visibile

    private void AggiornaAnteprimaVisibile()
    {
        bool visibile, mostrata;
        try
        {
            var ridotta = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
            visibile = PausaIntelligente.AnteprimaVisibile(AppWindow.IsVisible, ridotta, InMini, registrazione is not null);
            anteprimaAltro = PausaIntelligente.AnteprimaAltroTelefono(AppWindow.IsVisible, ridotta, InMini, riquadroAperto);
            mostrata = PausaIntelligente.FinestraMostrata(AppWindow.IsVisible, ridotta, InMini);
        }
        catch (Exception) { return; }
        if (mostrata != Volatile.Read(ref finestraMostrata))
        {
            Volatile.Write(ref finestraMostrata, mostrata);
            // Riaperta: l'ultima immagine elaborata subito, senza aspettare il fotogramma dopo.
            if (mostrata && Interlocked.Exchange(ref anteprimaInCoda, 1) == 0) coda.TryEnqueue(MostraElaborata);
        }
        if (visibile != Volatile.Read(ref anteprimaVisibile))
        {
            Volatile.Write(ref anteprimaVisibile, visibile);
            registro.Aggiungi(visibile ? Testi.T("Pausa_AnteprimaVisibile") : Testi.T("Pausa_AnteprimaNascosta"));
        }
        // Ogni telefono il suo valore (P21); la sessione manda solo i cambiamenti.
        foreach (var collegato in telefoni.Telefoni) SegnalaAnteprima(collegato);
        ValutaPausaAutomatica();
    }

    // MARK: pausa automatica (Qualità 18)

    private void InizializzaPausaAutomatica()
    {
        pausaAutomaticaAccesa = Preferenze.PausaAutomatica;
        InterruttorePausaAutomatica.IsOn = pausaAutomaticaAccesa;
        MostraNotaPausaAutomatica();
    }

    /// <summary>L'interruttore nella pagina «Uscite»: si salva e vale subito.</summary>
    private void SuPausaAutomatica(object sender, RoutedEventArgs e)
    {
        if (InterruttorePausaAutomatica.IsOn == pausaAutomaticaAccesa) return;
        pausaAutomaticaAccesa = InterruttorePausaAutomatica.IsOn;
        Preferenze.PausaAutomatica = pausaAutomaticaAccesa;
        // Appena acceso si contano i 20 secondi da qui; spento, la pausa finisce subito.
        regolaPausa.Riparti(Environment.TickCount64);
        ValutaPausaAutomatica();
    }

    /// <summary>Sotto l'interruttore: cosa fa, o perché qui non può funzionare (webcam non installata).</summary>
    private void MostraNotaPausaAutomatica()
    {
        var testo = uscitaWebcam.SaLeggereUso
            ? Testi.T("PausaAutomatica_Nota", Servizio.SecondiPausaAutomatica)
            : Testi.T("PausaAutomatica_NonLeggibile");
        if (NotaPausaAutomatica.Text != testo) NotaPausaAutomatica.Text = testo;
    }

    /// <summary>
    /// A ogni controllo della finestra (ogni secondo), quando un'app apre o chiude la webcam, quando la finestra entra o
    /// esce dal primo piano e quando la registrazione parte o finisce: la regola decide, ogni sessione manda solo i
    /// cambiamenti. Durante la pausa la webcam si controlla ogni 250 ms, così il video riparte in meno di un secondo.
    /// </summary>
    private void ValutaPausaAutomatica()
    {
        bool guardata;
        try
        {
            var ridotta = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
            guardata = PausaIntelligente.FinestraGuardata(AppWindow.IsVisible, ridotta, InMini, inPrimoPiano);
        }
        catch (Exception) { return; }
        var adesso = Environment.TickCount64;
        // Un telefono appena collegato (o passato al cavo): i 20 secondi ripartono, e la sua sessione ha già mandato
        // «nessuna pausa» dopo il benvenuto.
        var attuali = telefoni.Telefoni.Select(t => t.Sessione).OfType<SessioneComputer>().ToList();
        if (attuali.Any(s => !sessioniInPausaAutomatica.Contains(s))) regolaPausa.Riparti(adesso);
        sessioniInPausaAutomatica.Clear();
        sessioniInPausaAutomatica.UnionWith(attuali);

        var uso = new UsoVideo(pausaAutomaticaAccesa, uscitaWebcam.SaLeggereUso, uscitaWebcam.InUso, registrazione is not null, guardata);
        var prima = regolaPausa.Pausa;
        var pausa = regolaPausa.Valuta(uso, adesso);
        uscitaWebcam.ImpostaControllo(regolaPausa.Controllo);
        MostraNotaPausaAutomatica();
        if (pausa != prima && attuali.Count > 0)
            registro.Aggiungi(pausa ? Testi.T("PausaAutomatica_Chiesta", Servizio.SecondiPausaAutomatica) : Testi.T("PausaAutomatica_Tolta"));
        foreach (var sessione in attuali) SegnalaPausaAutomatica(sessione, pausa);
    }

    /// <summary>Come <see cref="SegnalaAnteprima"/>: dal thread dell'interfaccia, un errore di rete qui non conta.</summary>
    private static async void SegnalaPausaAutomatica(SessioneComputer sessione, bool pausa)
    {
        try { await sessione.SegnalaPausaAutomaticaAsync(pausa); }
        catch (Exception) { }
    }

    /// <summary>P21: il telefono che non è nella webcam si vede solo nel riquadro piccolo, nella finestra intera.</summary>
    private bool anteprimaAltro = true;

    private bool AnteprimaPer(TelefonoCollegato collegato) =>
        telefoni.ESelezionato(collegato) ? Volatile.Read(ref anteprimaVisibile) : anteprimaAltro;

    /// <summary>
    /// Dal thread dell'interfaccia e senza Task.Run: il valore si imposta subito, nell'ordine dei cambi, e la sessione
    /// manda solo l'ultimo, una volta. Un errore di rete qui non conta.
    /// </summary>
    private async void SegnalaAnteprima(TelefonoCollegato collegato)
    {
        if (collegato.Sessione is not { } attiva) return;
        try { await attiva.SegnalaAnteprimaAsync(AnteprimaPer(collegato)); }
        catch (Exception) { }
    }

    // MARK: in pausa

    /// <summary>
    /// Lo stato del telefono: sopra il video la stessa schermata di attesa che vedono le altre app («Webcam in pausa»,
    /// «Collegamento interrotto»), con il motivo della pausa e cosa fare; e la webcam lo sa (AggiornaAttesa).
    /// </summary>
    private void MostraPausa()
    {
        var pausa = telefono is not null && statoCollegamento == FaseCollegamento.Collegato && PausaIntelligente.InPausa(statoTelefono);
        var interrotto = telefono is not null && statoCollegamento == FaseCollegamento.Riconnessione;
        if (pausa)
        {
            var motivo = statoTelefono!.Pausa;
            MotivoPausa.Text = PausaIntelligente.Motivo(motivo);
            SuggerimentoPausa.Text = PausaIntelligente.Suggerimento(motivo);
        }
        else
        {
            MotivoPausa.Text = "";
            SuggerimentoPausa.Text = "";
        }
        var stato = pausa ? StatoAttesa.Pausa : interrotto ? StatoAttesa.Interrotta : StatoAttesa.Nessuna;
        MostraVeloAttesa(stato);
        AggiornaAttesa();
    }

    /// <summary>
    /// Nel registro, per ogni telefono, una riga a ogni inizio di pausa (o cambio di motivo) con il motivo, e una alla
    /// ripresa con la durata. Alla ripresa del telefono nella webcam anche la frase sopra il video.
    /// </summary>
    private void RegistraPausa(TelefonoCollegato collegato, CambioPausa cambio, bool scelto)
    {
        if (cambio.Iniziata is { } motivo)
        {
            registro.Aggiungi(Testi.T("Pausa_InPausa", PausaIntelligente.MotivoInFrase(motivo), DiChi(collegato)));
            // In sottofondo il telefono può restare via fino a 10 minuti: la registrazione non resta aperta senza
            // immagini, si chiude e si salva subito, e lo si dice.
            if (scelto && motivo == MotiviPausa.Sottofondo && registrazione is not null)
                _ = FermaRegistrazioneAsync(Riprese.TelefonoInSottofondo);
        }
        if (cambio.FinitaDopo is not { } durata) return;
        var secondi = Math.Max(1, (int)Math.Round(durata.TotalSeconds));
        registro.Aggiungi(Testi.T("Pausa_RiprendeDopo", secondi, DiChi(collegato)));
        if (scelto) MostraAvvisoRiprese(Testi.T("Pausa_RiprendeDopo", secondi, ""), registra: false);
    }

    /// <summary>Vero se il telefono collegato è in pausa adesso.</summary>
    private bool InPausa => telefono is not null && PausaIntelligente.InPausa(statoTelefono);

    // MARK: 60 fps (P12)

    /// <summary>
    /// Un'app usa la webcam a 60 fps e il telefono ne manda meno: si chiede il formato a 60 fps, una volta per periodo
    /// d'uso, solo se il telefono lo sa fare (capacita.formati). La risposta è il «formato» che il telefono manda davvero.
    /// </summary>
    private void Valuta60Fps()
    {
        if (Scelto is not { Sessione: { } attiva } scelto) return;
        var formato = formatoVideo;
        // Mentre si registra niente formato nuovo: chiuderebbe la registrazione (windows.md 1.6). Si rivaluta alla fine.
        if (richiesta60Fps.Valuta(uscitaWebcam.InUso, uscitaWebcam.FpsChiesti, formato, capacitaAttuali?.Formati, ProAttivo,
                registrando: registrazione is not null) is not { } richiesto) return;
        registro.Aggiungi(Testi.T("Pausa_Webcam60", richiesto.Larghezza, richiesto.Altezza));
        ChiediFormato(scelto, attiva, richiesto);
    }

    /// <summary>
    /// Chiede un formato al telefono e lo ricorda: se il telefono manda meno, l'etichetta della qualità dice perché.
    /// </summary>
    private static async void ChiediFormato(TelefonoCollegato telefono, SessioneComputer attiva, FormatoVideo formato)
    {
        telefono.FormatoChiesto = formato;
        try { await attiva.ChiediFormatoAsync(formato); }
        catch (Exception) { }
    }
}
