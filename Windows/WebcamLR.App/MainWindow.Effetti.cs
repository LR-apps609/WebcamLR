using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// La sezione «Effetti» della colonna di destra, come sul Mac: inquadratura automatica, luce sul volto, filtro, sfondo,
/// ritocco pelle, scritta, volto e scrivania, promemoria postura e il gobbo; le regolazioni stanno in «Regole fini».
/// «Specchia» e «Sfoca sfondo» sono sotto il video, a un clic (1.14). Il telefono fa il lavoro; qui si manda «comando» e
/// si mostra lo «stato». Si vede solo ciò che il telefono dichiara in «capacita». La logica (valori, cursori raccolti ogni
/// 100 ms, stato vecchio che non riporta indietro un cursore, specchio unico) è in ControlloEffetti, provata con i test.
/// Con un telefono gratis restano liberi luce sul volto, sfondo sfocato, postura e specchio; il resto ha il segno «PRO».
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Gli effetti del telefono nella webcam (P21: ogni telefono ha i suoi); senza telefono, quelli di partenza.</summary>
    private ControlloEffetti effetti => Scelto?.Effetti ?? effettiSenzaTelefono;
    private readonly ControlloEffetti effettiSenzaTelefono = new();
    private DispatcherQueueTimer? ritardoEffetti;
    /// <summary>Vero mentre la finestra imposta gli effetti da codice: in quel caso non si manda nulla.</summary>
    private bool aggiornoEffetti;
    /// <summary>Nome e ruolo messi nelle caselle da codice: TextChanged arriva dopo, e quel cambio non va mandato.</summary>
    private string? scrittaImpostata;
    /// <summary>I filtri attualmente nell'elenco, per non rifarlo se non cambiano.</summary>
    private IReadOnlyList<string> filtriMostrati = [];

    /// <summary>Il gobbo del telefono nella webcam: ogni telefono ricorda il suo, per il ricollegamento.</summary>
    private MemoriaGobbo memoriaGobbo => Scelto?.Gobbo ?? gobboSenzaTelefono;
    private readonly MemoriaGobbo gobboSenzaTelefono = new();
    private FinestraGobbo? finestraGobbo;

    private static long AdessoMs => Environment.TickCount64;

    private void InizializzaEffetti()
    {
        ritardoEffetti = coda.CreateTimer();
        ritardoEffetti.Interval = effetti.Ritardo;
        ritardoEffetti.IsRepeating = false;
        ritardoEffetti.Tick += (_, _) =>
        {
            if (effetti.Scaduto() is { } comando) Comanda(comando);
        };
        aggiornoEffetti = true;
        // Le caselle della scritta ricordano l'ultimo nome e ruolo scritti, anche dopo il riavvio.
        CasellaNomeScritta.Text = Preferenze.NomeScritta;
        CasellaRuoloScritta.Text = Preferenze.RuoloScritta;
        scrittaImpostata = TestoScritta();
        aggiornoEffetti = false;
        MostraEffetti();
    }

    /// <summary>
    /// Con un telefono che ha mandato le capacità (prima non si sa ancora quali effetti ha); senza, la sezione è grigia
    /// e mostra come sarà.
    /// </summary>
    private bool EffettiAttivi => telefono is not null && capacitaAttuali is not null;

    /// <summary>Le capacità di un telefono: quali effetti mostrare (anche nessuno, per un telefono da aggiornare).</summary>
    private void CapacitaEffetti(TelefonoCollegato collegato, Capacita capacita)
    {
        collegato.Effetti.Capacita(capacita);
        if (!telefoni.ESelezionato(collegato)) return;
        MostraEffetti();
        finestraGobbo?.Aggiorna(GobboDisponibile);
    }

    /// <summary>Lo stato di un telefono: gli effetti cambiati (anche sul telefono) e la posizione del gobbo.</summary>
    private void StatoEffetti(TelefonoCollegato collegato, StatoTelefono stato)
    {
        var valori = collegato.Effetti.Stato(stato, AdessoMs);
        var gobbo = collegato.Gobbo.Stato(stato.Gobbo);
        if (!telefoni.ESelezionato(collegato)) return;
        if (valori) MostraValoriEffetti();
        if (gobbo) finestraGobbo?.Aggiorna(GobboDisponibile);
    }

    /// <summary>
    /// Un altro telefono nella webcam (P21), o nessuno: la sezione mostra i suoi effetti e il gobbo passa a lui;
    /// il testo del gobbo resta nella finestra.
    /// </summary>
    private void MostraEffettiDelScelto()
    {
        ritardoEffetti?.Stop();
        MostraEffetti();
        finestraGobbo?.UsaMemoria(memoriaGobbo, GobboDisponibile);
    }

    /// <summary>Prima di passare all'altro telefono: i cursori ancora in attesa partono verso quello di adesso.</summary>
    private void MandaEffettiInAttesa()
    {
        ritardoEffetti?.Stop();
        if (effetti.Scaduto() is { } comando) Comanda(comando);
    }

    /// <summary>Quali effetti si vedono (dalle capacità e dalla modalità avanzata), con i valori di adesso.</summary>
    private void MostraEffetti()
    {
        if (PannelloEffetti is null) return;
        var attivi = EffettiAttivi;
        var disponibili = attivi ? effetti.Disponibili : DisponibilitaEffetti.Esempio;
        var nessuno = attivi && !disponibili.Qualcuno;
        DettagliEffetti.Text = nessuno
            ? Testi.T("Effetti_TelefonoVecchio")
            : attivi ? Testi.T("Effetti_LiFaIlTelefono")
            : Testi.T("Comandi_SiAttivano");
        PannelloEffetti.Visibility = Visibile(!nessuno);
        PannelloRegolazioni.Visibility = Visibile(disponibili.Regolazioni);

        ZonaInquadratura.Visibility = Visibile(disponibili.Inquadratura);
        InterruttoreLuceVolto.Visibility = Visibile(disponibili.LuceVolto);
        ZonaFiltro.Visibility = Visibile(disponibili.Filtri.Count > 0);
        PannelloSfondo.Visibility = Visibile(disponibili.Sfondo);
        ZonaPelle.Visibility = Visibile(disponibili.Pelle);
        ZonaScritta.Visibility = Visibile(disponibili.Scritta);
        ZonaDoppiaVista.Visibility = Visibile(disponibili.DoppiaVista);
        InterruttorePostura.Visibility = Visibile(disponibili.Postura);
        ZonaGobbo.Visibility = Visibile(disponibili.Gobbo);

        if (!filtriMostrati.SequenceEqual(disponibili.Filtri))
        {
            var prima = aggiornoEffetti;
            aggiornoEffetti = true;
            SceltaFiltro.Items.Clear();
            foreach (var filtro in disponibili.Filtri)
                SceltaFiltro.Items.Add(new ComboBoxItem { Content = NomiEffetti.Filtro(filtro), Tag = filtro });
            filtriMostrati = disponibili.Filtri;
            aggiornoEffetti = prima;
        }
        MostraValoriEffetti();
    }

    /// <summary>I valori del telefono nei comandi, senza mandare nulla.</summary>
    private void MostraValoriEffetti()
    {
        if (PannelloEffetti is null) return;
        var v = effetti.Valori;
        var prima = aggiornoEffetti;
        aggiornoEffetti = true;
        InterruttoreInquadratura.IsOn = v.Inquadratura;
        InterruttoreLuceVolto.IsOn = v.LuceVolto;
        var filtro = NomiEffetti.FiltroValido(v.Filtro, filtriMostrati);
        SceltaFiltro.SelectedItem = SceltaFiltro.Items.OfType<ComboBoxItem>().FirstOrDefault(voce => (string)voce.Tag == filtro)
            ?? SceltaFiltro.Items.OfType<ComboBoxItem>().FirstOrDefault();
        CursoreLuminosita.Value = Math.Round(v.Luminosita * 100);
        CursoreContrasto.Value = Math.Round(v.Contrasto * 100);
        CursoreSaturazione.Value = Math.Round(v.Saturazione * 100);
        CursoreNitidezza.Value = Math.Round(v.Nitidezza * 100);
        SceltaSfondo.SelectedIndex = Math.Max(0, NomiEffetti.ModiSfondo.ToList().IndexOf(v.Sfondo));
        CursoreIntensitaSfondo.Value = Math.Round(v.IntensitaSfondo * 100);
        CursorePelle.Value = Math.Round(v.Pelle * 100);
        InterruttoreDoppiaVista.IsOn = v.DoppiaVista;
        InterruttorePostura.IsOn = v.Postura;
        // La scritta sul telefono riempie le caselle; tolta, le caselle restano come sono per rimostrarla.
        if (v.ScrittaMostrata)
        {
            CasellaNomeScritta.Text = v.Scritta.Nome;
            CasellaRuoloScritta.Text = v.Scritta.Ruolo ?? "";
            scrittaImpostata = TestoScritta();
        }
        InterruttoreScritta.IsOn = v.ScrittaMostrata;
        aggiornoEffetti = prima;
        MostraDettagliEffetti();
        MostraPulsantiVideo();
        MostraProfili();
    }

    /// <summary>Ciò che dipende dai valori: «Azzera» delle regolazioni, intensità dello sfondo, «Mostra» della scritta.</summary>
    private void MostraDettagliEffetti()
    {
        if (PannelloEffetti is null) return;
        var v = effetti.Valori;
        PulsanteAzzeraRegolazioni.IsEnabled = EffettiAttivi && !v.RegolazioniNeutre;
        CursoreIntensitaSfondo.Visibility = Visibile(v.Sfondo != ModiSfondo.Nessuno);
        ToolTipService.SetToolTip(CursoreIntensitaSfondo, v.Sfondo == ModiSfondo.Sostituito
            ? Testi.T("Effetti_IntensitaSostituito") : Testi.T("Effetti_IntensitaSfocato"));
        NotaSfondo.Visibility = Visibile(v.Sfondo == ModiSfondo.Sostituito);
        AbilitaEffetti();
    }

    /// <summary>
    /// Tutto a vista ma grigio senza telefono (come i comandi della fotocamera): la copertura dice cosa fare. Poi i
    /// comandi Pro, che con un telefono gratis restano spenti (AggiornaPro).
    /// </summary>
    private void AbilitaEffetti()
    {
        if (PannelloEffetti is null) return;
        var attivi = EffettiAttivi;
        Abilita(PannelloEffetti, attivi);
        CoperturaEffetti.Visibility = Visibile(!attivi);
        // «Mostra» serve un nome; spegnere si può sempre.
        InterruttoreScritta.IsEnabled = attivi && (InterruttoreScritta.IsOn || CasellaNomeScritta.Text.Trim().Length > 0);
        PulsanteAzzeraRegolazioni.IsEnabled = attivi && !effetti.Valori.RegolazioniNeutre;
        AggiornaPro();
    }

    // MARK: «Specchia» e «Sfoca sfondo» (1.14)

    /// <summary>
    /// Sotto il video, a un clic, accesi nell'accento. Valgono per il video inviato, quello che vedono anche le app e il
    /// telefono: il telefono li applica e il pulsante segue il suo «stato». Senza telefono grigi; con un telefono che non
    /// li sa fare (capacita) non ci sono.
    /// </summary>
    private void MostraPulsantiVideo()
    {
        if (PulsanteSpecchia is null) return;
        var inAttesa = sessione is null || capacitaAttuali is null;
        var v = effetti.Valori;
        ContenitoreSpecchia.Visibility = Visibile(inAttesa || capacitaAttuali?.Specchia == true);
        ContenitoreSfoca.Visibility = Visibile(inAttesa || capacitaAttuali?.Sfondo == true);
        PulsanteSpecchia.IsEnabled = !inAttesa;
        PulsanteSfoca.IsEnabled = !inAttesa;
        CoperturaSpecchia.Visibility = Visibile(inAttesa);
        CoperturaSfoca.Visibility = Visibile(inAttesa);
        var specchiato = !inAttesa && v.Specchia;
        var sfocato = !inAttesa && v.SfondoSfocato;
        PulsanteSpecchia.IsChecked = specchiato;
        PulsanteSfoca.IsChecked = sfocato;
        ToolTipService.SetToolTip(PulsanteSpecchia, specchiato
            ? Testi.T("Effetti_SpecchiatoAcceso")
            : Testi.T("Effetti_SpecchiaSpento"));
        ToolTipService.SetToolTip(PulsanteSfoca, sfocato
            ? Testi.T("Effetti_SfocatoAcceso")
            : Testi.T("Effetti_SfocaSpento"));
    }

    private void SuSpecchia(object sender, RoutedEventArgs e)
    {
        if (sessione is null || capacitaAttuali?.Specchia != true)
        {
            MostraPulsantiVideo();
            return;
        }
        ritardoEffetti?.Stop();
        var comando = effetti.AlternaSpecchio(AdessoMs);
        registro.Aggiungi(comando.Specchia == true ? Testi.T("Effetti_SpecchiaAcceso") : Testi.T("Effetti_SpecchiaSpentoBreve"));
        Comanda(comando);
        MostraValoriEffetti();
    }

    private void SuSfocaSfondo(object sender, RoutedEventArgs e)
    {
        if (sessione is null || capacitaAttuali?.Sfondo != true)
        {
            MostraPulsantiVideo();
            return;
        }
        ritardoEffetti?.Stop();
        Comanda(effetti.AlternaSfocatura(AdessoMs));
        MostraValoriEffetti();
    }

    /// <summary>Un interruttore o un elenco: subito, insieme ai cursori in attesa.</summary>
    private void ComandaEffetto(Comando comando)
    {
        if (aggiornoEffetti || sessione is null) return;
        ritardoEffetti?.Stop();
        Comanda(effetti.Subito(comando, AdessoMs));
        MostraDettagliEffetti();
    }

    /// <summary>Un cursore: si raccoglie con gli altri e parte dopo 100 ms.</summary>
    private void CambiaEffetto(Comando comando)
    {
        if (aggiornoEffetti || sessione is null) return;
        if (effetti.Cambia(comando, AdessoMs)) ritardoEffetti?.Start();
        MostraDettagliEffetti();
    }

    private static double DaCursore(double valore) => Math.Round(valore / 100, 2);

    private void SuInquadraturaAutomatica(object sender, RoutedEventArgs e)
    {
        if (InterruttoreInquadratura is null) return;
        ComandaEffetto(new Comando(Inquadratura: InterruttoreInquadratura.IsOn));
    }

    private void SuLuceVolto(object sender, RoutedEventArgs e)
    {
        if (InterruttoreLuceVolto is null) return;
        ComandaEffetto(new Comando(LuceVolto: InterruttoreLuceVolto.IsOn));
    }

    private void SuFiltro(object sender, SelectionChangedEventArgs e)
    {
        if (SceltaFiltro?.SelectedItem is ComboBoxItem { Tag: string filtro }) ComandaEffetto(new Comando(Filtro: filtro));
    }

    private void SuRegolazione(object sender, RangeBaseValueChangedEventArgs e)
    {
        var valore = DaCursore(e.NewValue);
        Regolazioni? regolazioni = ReferenceEquals(sender, CursoreLuminosita) ? new Regolazioni(Luminosita: valore)
            : ReferenceEquals(sender, CursoreContrasto) ? new Regolazioni(Contrasto: valore)
            : ReferenceEquals(sender, CursoreSaturazione) ? new Regolazioni(Saturazione: valore)
            : ReferenceEquals(sender, CursoreNitidezza) ? new Regolazioni(Nitidezza: valore)
            : null;
        if (regolazioni is not null) CambiaEffetto(new Comando(Regolazioni: regolazioni));
    }

    private void SuAzzeraRegolazioni(object sender, RoutedEventArgs e)
    {
        ComandaEffetto(new Comando(Regolazioni: new Regolazioni(0, 0, 0, 0)));
        MostraValoriEffetti();
    }

    private void SuSfondo(object sender, SelectionChangedEventArgs e)
    {
        if (SceltaSfondo?.SelectedItem is not ComboBoxItem { Tag: string modo }) return;
        // Con lo sfondo acceso parte anche l'intensità del cursore, così telefono e PC restano d'accordo.
        ComandaEffetto(modo == ModiSfondo.Nessuno
            ? new Comando(Sfondo: modo)
            : new Comando(Sfondo: modo, IntensitaSfondo: DaCursore(CursoreIntensitaSfondo.Value)));
    }

    private void SuIntensitaSfondo(object sender, RangeBaseValueChangedEventArgs e) =>
        CambiaEffetto(new Comando(IntensitaSfondo: DaCursore(e.NewValue)));

    private void SuPelle(object sender, RangeBaseValueChangedEventArgs e) => CambiaEffetto(new Comando(Pelle: DaCursore(e.NewValue)));

    private void SuDoppiaVista(object sender, RoutedEventArgs e)
    {
        if (InterruttoreDoppiaVista is null) return;
        ComandaEffetto(new Comando(DoppiaVista: InterruttoreDoppiaVista.IsOn));
    }

    private void SuPostura(object sender, RoutedEventArgs e)
    {
        if (InterruttorePostura is null) return;
        ComandaEffetto(new Comando(Postura: InterruttorePostura.IsOn));
    }

    // MARK: scritta

    private string TestoScritta() => $"{CasellaNomeScritta.Text}\n{CasellaRuoloScritta.Text}";

    private Scritta ScrittaDaMandare(bool mostra) =>
        Comandi.Scritta(CasellaNomeScritta.Text, CasellaRuoloScritta.Text, mostra);

    private void SuMostraScritta(object sender, RoutedEventArgs e)
    {
        if (InterruttoreScritta is null || CasellaNomeScritta is null) return;
        ComandaEffetto(new Comando(Scritta: ScrittaDaMandare(InterruttoreScritta.IsOn)));
    }

    /// <summary>
    /// Mentre la scritta è mostrata, nome e ruolo nuovi partono come un cursore (dopo 100 ms). Il nome cancellato toglie
    /// la scritta e spegne «Mostra». Le caselle si ricordano per la prossima volta.
    /// </summary>
    private void SuTestoScritta(object sender, TextChangedEventArgs e)
    {
        if (CasellaNomeScritta is null || CasellaRuoloScritta is null || InterruttoreScritta is null) return;
        var testo = TestoScritta();
        // TextChanged arriva anche per i testi messi da codice, e dopo: quelli non si mandano.
        if (testo == scrittaImpostata) return;
        scrittaImpostata = testo;
        Preferenze.NomeScritta = CasellaNomeScritta.Text;
        Preferenze.RuoloScritta = CasellaRuoloScritta.Text;
        if (!InterruttoreScritta.IsOn)
        {
            AbilitaEffetti();
            return;
        }
        if (CasellaNomeScritta.Text.Trim().Length == 0)
        {
            var prima = aggiornoEffetti;
            aggiornoEffetti = true;
            InterruttoreScritta.IsOn = false;
            aggiornoEffetti = prima;
            ComandaEffetto(new Comando(Scritta: Scritta.Nessuna));
            return;
        }
        CambiaEffetto(new Comando(Scritta: ScrittaDaMandare(true)));
    }

    // MARK: gobbo (P06)

    /// <summary>Il gobbo è di WebcamLR Pro, come sul Mac.</summary>
    private bool GobboDisponibile => sessione is not null && EffettiAttivi && effetti.Disponibili.Gobbo && ProAttivo;

    private void SuGobbo(object sender, RoutedEventArgs e)
    {
        if (BloccoPro)
        {
            NotaPro.Mostra(PulsanteGobbo);
            return;
        }
        finestraGobbo ??= new FinestraGobbo(memoriaGobbo, InviaGobbo, () => finestraGobbo = null);
        finestraGobbo.Mostra(GobboDisponibile);
    }

    /// <summary>Al telefono, nei limiti del protocollo; la memoria ricorda tutto per il ricollegamento.</summary>
    private void InviaGobbo(Gobbo gobbo)
    {
        if (!GobboDisponibile || sessione is not { } attiva) return;
        var pronto = memoriaGobbo.Prepara(gobbo);
        InviaGobbo(attiva, pronto);
        finestraGobbo?.Aggiorna(GobboDisponibile);
    }

    /// <summary>Dal thread dell'interfaccia, nell'ordine dei clic (Avvia e Pausa di fila arrivano in quest'ordine). Un errore di rete qui non conta.</summary>
    private static async void InviaGobbo(SessioneComputer attiva, Gobbo gobbo)
    {
        try { await attiva.GobboAsync(gobbo); }
        catch (Exception) { }
    }

    /// <summary>Lo stesso telefono è tornato: il testo vive sul telefono solo per la sessione, si rimanda dall'ultima posizione.</summary>
    private void RimandaGobbo(TelefonoCollegato collegato, SessioneComputer attiva)
    {
        if (collegato.Gobbo.DaRimandare() is not { } gobbo) return;
        registro.Aggiungi(Testi.T("Gobbo_Rimandato", MemoriaGobbo.TestoPosizione(gobbo.Posizione ?? 0)));
        InviaGobbo(attiva, gobbo);
    }
}
