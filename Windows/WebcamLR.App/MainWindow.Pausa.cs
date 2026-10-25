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
/// anche una registrazione in corso, che senza video resterebbe ferma). Con nessuna app sulla webcam e la finestra non
/// visibile da 10 secondi il telefono si ferma; quando lo stato porta «pausa», sopra il video compare «In pausa» con il
/// motivo, in toni calmi. Le decisioni sono in PausaIntelligente e Richiesta60Fps, provate con i test.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Lo legge anche il thread di rete, per la sessione nuova prima del benvenuto.</summary>
    private bool anteprimaVisibile = true;
    private DispatcherQueueTimer? controlloAnteprima;
    private readonly Richiesta60Fps richiesta60Fps = new();

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
        // Il primo controllo a finestra già mostrata (nel costruttore non lo è ancora): fino ad allora vale «visibile».
    }

    private void FermaPausa() => controlloAnteprima?.Stop();

    // MARK: anteprima visibile

    private void AggiornaAnteprimaVisibile()
    {
        bool visibile;
        try
        {
            var ridotta = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
            visibile = PausaIntelligente.AnteprimaVisibile(AppWindow.IsVisible, ridotta, InMini, registrazione is not null);
            anteprimaAltro = PausaIntelligente.AnteprimaAltroTelefono(AppWindow.IsVisible, ridotta, InMini, riquadroAperto);
        }
        catch (Exception) { return; }
        if (visibile != Volatile.Read(ref anteprimaVisibile))
        {
            Volatile.Write(ref anteprimaVisibile, visibile);
            registro.Aggiungi(visibile ? "Anteprima visibile" : "Anteprima non visibile: il telefono può andare in pausa");
        }
        // Ogni telefono il suo valore (P21); la sessione manda solo i cambiamenti.
        foreach (var collegato in telefoni.Telefoni) SegnalaAnteprima(collegato);
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
        var pausa = telefono is not null && statoCollegamento == StatoCollegamento.Collegato && PausaIntelligente.InPausa(statoTelefono);
        var interrotto = telefono is not null && statoCollegamento == StatoCollegamento.Riconnessione;
        var eraInPausa = pausaMostrata;
        pausaMostrata = pausa;
        if (pausa)
        {
            var motivo = statoTelefono!.Pausa;
            MotivoPausa.Text = PausaIntelligente.Motivo(motivo);
            SuggerimentoPausa.Text = PausaIntelligente.Suggerimento(motivo);
            if (!eraInPausa) registro.Aggiungi($"In pausa: {PausaIntelligente.Motivo(motivo).ToLowerInvariant()}");
        }
        else
        {
            if (eraInPausa) registro.Aggiungi("Il telefono riprende il video");
            MotivoPausa.Text = "";
            SuggerimentoPausa.Text = "";
        }
        var stato = pausa ? StatoAttesa.Pausa : interrotto ? StatoAttesa.Interrotta : StatoAttesa.Nessuna;
        MostraVeloAttesa(stato);
        AggiornaAttesa();
    }

    /// <summary>La pausa già scritta nel registro: una riga sola all'inizio e una alla fine.</summary>
    private bool pausaMostrata;

    /// <summary>Vero se il telefono collegato è in pausa adesso.</summary>
    private bool InPausa => telefono is not null && PausaIntelligente.InPausa(statoTelefono);

    // MARK: 60 fps (P12)

    /// <summary>
    /// Un'app usa la webcam a 60 fps e il telefono ne manda meno: si chiede il formato a 60 fps, una volta per periodo
    /// d'uso, solo se il telefono lo sa fare (capacita.formati). La risposta è il «formato» che il telefono manda davvero.
    /// </summary>
    private void Valuta60Fps()
    {
        if (sessione is not { } attiva) return;
        var formato = formatoVideo;
        if (richiesta60Fps.Valuta(uscitaWebcam.InUso, uscitaWebcam.FpsChiesti, formato, capacitaAttuali?.Formati, ProAttivo) is not { } richiesto) return;
        registro.Aggiungi($"Webcam a 60 fps: chiesto al telefono {richiesto.Larghezza}×{richiesto.Altezza} a 60 fps");
        ChiediFormato(attiva, richiesto);
    }

    private static async void ChiediFormato(SessioneComputer attiva, FormatoVideo formato)
    {
        try { await attiva.ChiediFormatoAsync(formato); }
        catch (Exception) { }
    }
}
