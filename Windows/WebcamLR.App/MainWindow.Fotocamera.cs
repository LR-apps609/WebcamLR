using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// La colonna di destra, come sul Mac (Mac/Sorgenti/ColonnaControlli.swift): in cima «Profilo» (i quattro profili pronti
/// di WebcamLR Pro e i profili salvati), poi «Fotocamera» a vista (obiettivo, zoom, esposizione, torcia, messa a fuoco) e
/// le sezioni richiudibili «Effetti» (MainWindow.Effetti.cs), «Regole fini» (ISO, tempo, bianco, regolazioni) e «Qualità
/// video». I comandi seguono lo «stato» del telefono (AllineamentoFotocamera). Con un telefono gratis i comandi Pro
/// restano a vista con il segno «PRO», spenti (AggiornaPro).
/// </summary>
public sealed partial class MainWindow
{
    private static readonly Dictionary<string, (string Breve, string Nome)> NomiObiettivi = new()
    {
        ["grandangolo"] = ($"{Lingua.Decimale(0.5, "0.0")}×", Testi.T("Obiettivo_Grandangolo")),
        ["principale"] = ("1×", Testi.T("Obiettivo_Principale")),
        ["tele"] = ("Tele", "Tele"),
        ["frontale"] = (Testi.T("Obiettivo_Frontale"), Testi.T("Obiettivo_Frontale")),
    };

    /// <summary>Gli obiettivi mostrati nei segmenti, nell'ordine del telefono.</summary>
    private IReadOnlyList<string> obiettiviMostrati = [];
    /// <summary>L'obiettivo appena scelto qui, finché lo «stato» del telefono non lo conferma.</summary>
    private string? obiettivoInAttesa;

    /// <summary>Le quattro schede dei profili pronti.</summary>
    private readonly List<(ProfiloPronto Profilo, Button Scheda, FontIcon Icona, TextBlock Nome)> schedeProfili = [];

    /// <summary>Le scelte del menu «Qualità video», per non rifarlo ogni secondo.</summary>
    private List<(OpzioneQualita Opzione, bool Bloccata)> qualitaMostrate = [];
    /// <summary>La scelta con la spunta e se le voci partono, quando il menu è stato fatto: cambiati, si rifà.</summary>
    private OpzioneQualita? qualitaSegnata;
    private bool qualitaComandi;

    /// <summary>Il telefono nella webcam è collegato, ha detto cosa sa fare e non ha WebcamLR Pro.</summary>
    private bool BloccoPro => RegolePro.Bloccato(sessione is not null, capacitaAttuali);

    /// <summary>Il telefono nella webcam ha WebcamLR Pro.</summary>
    private bool ProAttivo => RegolePro.Attivo(capacitaAttuali);

    private void InizializzaFotocamera()
    {
        for (var i = 0; i < ProfiloPronto.Tutti.Count; i++)
        {
            var profilo = ProfiloPronto.Tutti[i];
            var icona = new FontIcon { Glyph = profilo.Glifo, FontSize = 15, HorizontalAlignment = HorizontalAlignment.Left };
            var nome = new TextBlock
            {
                Text = profilo.Nome,
                FontFamily = (FontFamily)Application.Current.Resources["CorpoForte"],
                FontSize = 14,
                TextTrimming = TextTrimming.CharacterEllipsis,
            };
            var descrizione = new TextBlock
            {
                Text = profilo.Descrizione,
                FontSize = 11.5,
                TextWrapping = TextWrapping.Wrap,
                MaxLines = 2,
                Foreground = Pennello("TestoSecondario"),
            };
            var scheda = new Button
            {
                Content = new StackPanel { Spacing = 4, Children = { icona, nome, descrizione } },
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                VerticalContentAlignment = VerticalAlignment.Top,
                Padding = new Thickness(10),
                MinHeight = 92,
                CornerRadius = new CornerRadius(10),
            };
            ToolTipService.SetToolTip(scheda, profilo.Riepilogo);
            AutomationProperties.SetName(scheda, Testi.T("Profilo_NomeDescrizione", profilo.Nome, profilo.Descrizione));
            scheda.Click += (_, _) => ApplicaProfiloPronto(profilo);
            Grid.SetColumn(scheda, i % 2);
            Grid.SetRow(scheda, i / 2);
            GrigliaProfili.Children.Add(scheda);
            schedeProfili.Add((profilo, scheda, icona, nome));
        }
        InterruttoreRiempi.IsOn = Preferenze.Riempi;
        Video.Stretch = Preferenze.Riempi ? Stretch.UniformToFill : Stretch.Uniform;
        VideoElaborato.Stretch = Video.Stretch;
        MostraSezioni();
        MostraProfili();
        MostraQualita();
        // Zoom ed esposizione con il separatore decimale della lingua (W2), non i valori scritti nello XAML.
        MostraComandiManuali();
    }

    // MARK: obiettivo, zoom, esposizione, torcia

    /// <summary>I segmenti dell'obiettivo, come sul Mac: un pulsante per obiettivo, quello attuale nell'accento.</summary>
    private void MostraObiettivi(IReadOnlyList<string> obiettivi, string? attuale)
    {
        if (!obiettiviMostrati.SequenceEqual(obiettivi))
        {
            obiettiviMostrati = obiettivi;
            SceltaObiettivo.Children.Clear();
            SceltaObiettivo.ColumnDefinitions.Clear();
            for (var i = 0; i < obiettivi.Count; i++)
            {
                var obiettivo = obiettivi[i];
                var (breve, nome) = NomiObiettivi.GetValueOrDefault(obiettivo, (obiettivo, obiettivo));
                SceltaObiettivo.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var pulsante = new ToggleButton
                {
                    Content = breve,
                    Tag = obiettivo,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    Padding = new Thickness(4, 5, 4, 6),
                };
                ToolTipService.SetToolTip(pulsante, i < Scorciatoie.ObiettiviConTasto ? Testi.T("Obiettivo_ConTasto", nome, i + 1) : nome);
                AutomationProperties.SetName(pulsante, nome);
                pulsante.Click += (_, _) => SuObiettivo(obiettivo);
                Grid.SetColumn(pulsante, i);
                SceltaObiettivo.Children.Add(pulsante);
            }
        }
        foreach (var pulsante in SceltaObiettivo.Children.OfType<ToggleButton>())
            pulsante.IsChecked = (string)pulsante.Tag == attuale;
    }

    /// <summary>L'obiettivo da mostrare scelto: quello appena chiesto, altrimenti quello dello «stato».</summary>
    private string? ObiettivoAttuale => obiettivoInAttesa ?? statoTelefono?.Obiettivo ?? capacitaAttuali?.Obiettivi.FirstOrDefault();

    private void MostraComandi(Capacita capacita)
    {
        var prima = aggiornoComandi;
        aggiornoComandi = true;
        MostraObiettivi(capacita.Obiettivi, ObiettivoAttuale);
        CursoreZoom.Maximum = Math.Max(1.1, capacita.ZoomMassimo);
        PannelloZoom.Visibility = Visibile(capacita.ZoomMassimo > 1);
        PulsanteTorcia.Visibility = Visibile(capacita.Torcia);
        // Esposizione manuale solo se il telefono dice i limiti ISO del suo obiettivo (funzione 19).
        if (capacita.IsoMinimo is double minimo && capacita.IsoMassimo is double massimo && massimo > minimo)
        {
            CursoreIso.Minimum = minimo;
            CursoreIso.Maximum = massimo;
            CursoreIso.Value = Math.Clamp(CursoreIso.Value, minimo, massimo);
        }
        else
        {
            EsposizioneManuale.IsOn = false;
        }
        EsposizioneManuale.Visibility = Visibile(ManualeDisponibile);
        PannelloRegolazioni.Visibility = Visibile(effetti.Disponibili.Regolazioni);
        MostraComandiManuali();
        aggiornoComandi = prima;
        AggiornaDisponibilita();
        MostraQualita();
    }

    /// <summary>Senza telefono i segmenti mostrano come sarà, senza mandare nulla.</summary>
    private void MostraObiettiviDiEsempio()
    {
        var prima = aggiornoComandi;
        aggiornoComandi = true;
        MostraObiettivi([.. NomiObiettivi.Keys], "principale");
        CursoreZoom.Maximum = 10;
        PannelloZoom.Visibility = Visibility.Visible;
        PulsanteTorcia.Visibility = Visibility.Visible;
        EsposizioneManuale.Visibility = Visibility.Visible;
        PannelloRegolazioni.Visibility = Visibility.Visible;
        aggiornoComandi = prima;
    }

    /// <summary>Esposizione manuale solo se il telefono dice i limiti ISO del suo obiettivo (funzione 19).</summary>
    private bool ManualeDisponibile => capacitaAttuali is null
        || capacitaAttuali is { IsoMinimo: double minimo, IsoMassimo: double massimo } && massimo > minimo;

    /// <summary>ISO e tempo, bianco e la nota sotto l'esposizione: l'unico posto che decide cosa si vede.</summary>
    private void MostraComandiManuali()
    {
        // I gestori dei cursori scattano anche mentre la finestra si sta creando, prima che ci siano tutti i controlli.
        if (EsposizioneManuale is null || PannelloManuale is null || PannelloEsposizione is null || NotaEsposizioneManuale is null
            || CursoreBianco is null || BiancoAutomatico is null || ValoreZoom is null || ValoreEsposizione is null
            || CursoreZoom is null || CursoreEsposizione is null) return;
        var manuale = EsposizioneManuale.IsOn;
        PannelloManuale.Visibility = Visibile(manuale);
        // ISO e tempo manuali: l'esposizione automatica non vale, si cambia nelle «Regole fini».
        PannelloEsposizione.Visibility = Visibile(!manuale);
        NotaEsposizioneManuale.Visibility = Visibile(manuale);
        CursoreBianco.Visibility = Visibile(!BiancoAutomatico.IsOn);
        ValoreZoom.Text = $"{Lingua.Decimale(CursoreZoom.Value, "0.0")}×";
        ValoreEsposizione.Text = Lingua.Decimale(CursoreEsposizione.Value, "+0.0;-0.0;+0.0");
    }

    /// <summary>Un altro telefono parte in automatico: i comandi tornano come all'apertura, senza inviare nulla.</summary>
    private void AzzeraComandi() => ImpostaComandi(ComandiFotocamera.Iniziali);

    /// <summary>I comandi di un telefono nei controlli (P21: passando all'altro telefono, o dallo «stato»), senza inviare nulla.</summary>
    private void ImpostaComandi(ComandiFotocamera comandi)
    {
        var prima = aggiornoComandi;
        aggiornoComandi = true;
        CursoreZoom.Value = Math.Clamp(comandi.Zoom, CursoreZoom.Minimum, CursoreZoom.Maximum);
        CursoreEsposizione.Value = Math.Clamp(comandi.Esposizione, -2, 2);
        EsposizioneManuale.IsOn = comandi.Manuale && ManualeDisponibile;
        BiancoAutomatico.IsOn = comandi.BiancoAutomatico;
        CursoreBianco.Value = Math.Clamp(comandi.Bianco, CursoreBianco.Minimum, CursoreBianco.Maximum);
        CursoreIso.Value = Math.Clamp(comandi.Iso, CursoreIso.Minimum, CursoreIso.Maximum);
        SceltaTempo.SelectedItem = SceltaTempo.Items.OfType<ComboBoxItem>().FirstOrDefault(voce => (string)voce.Tag == comandi.Tempo.ToString())
            ?? SceltaTempo.SelectedItem;
        PulsanteTorcia.IsChecked = comandi.Torcia;
        MostraComandiManuali();
        aggiornoComandi = prima;
    }

    /// <summary>
    /// Al telefono nella webcam; la finestra ricorda i comandi di ogni telefono (P21) per rimandarli al ricollegamento,
    /// e per un attimo lo «stato» non li riporta indietro. Con un telefono gratis le parti Pro non partono.
    /// </summary>
    private void Comanda(Comando comando)
    {
        if (aggiornoComandi || Scelto is not { Sessione: { } attiva } scelto) return;
        // Effetti sul computer: gli effetti di immagine li applica il motore del PC, al telefono va il resto.
        if (SulComputer)
        {
            if (RegoleEffettiComputer.PerIlTelefono(comando) is not { } delTelefono) return;
            comando = delTelefono;
        }
        if (BloccoPro)
        {
            comando = RegolePro.SenzaPro(comando);
            if (RegolePro.Vuoto(comando)) return;
        }
        scelto.Comandi = scelto.Comandi.Applica(comando);
        scelto.Allineamento.Segna(comando, AdessoMs);
        _ = ComandaAsync(attiva, comando);
    }

    private void SuObiettivo(string obiettivo)
    {
        if (aggiornoComandi || sessione is null)
        {
            MostraObiettivi(obiettiviMostrati, ObiettivoAttuale);
            return;
        }
        // Un altro obiettivo è un altro video: la registrazione si chiude, quindi prima si chiede (windows.md 1.6).
        PrimaDiFermareLaRegistrazione(() => CambiaObiettivo(obiettivo), () => MostraObiettivi(obiettiviMostrati, ObiettivoAttuale),
            cambiaIlVideo: obiettivo != ObiettivoAttuale);
    }

    private void CambiaObiettivo(string obiettivo)
    {
        if (sessione is null) return;
        obiettivoInAttesa = obiettivo == statoTelefono?.Obiettivo ? null : obiettivo;
        MostraObiettivi(obiettiviMostrati, obiettivo);
        // Cambiando obiettivo lo zoom riparte da 1, come fa il telefono.
        var prima = aggiornoComandi;
        aggiornoComandi = true;
        CursoreZoom.Value = 1;
        aggiornoComandi = prima;
        MostraComandiManuali();
        Comanda(new Comando(Obiettivo: obiettivo));
    }

    private void SuZoom(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (ValoreZoom is null) return;
        MostraComandiManuali();
        Comanda(new Comando(Zoom: Math.Round(e.NewValue, 1)));
    }

    private void SuEsposizione(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (ValoreEsposizione is null) return;
        MostraComandiManuali();
        Comanda(new Comando(Esposizione: Math.Round(e.NewValue, 1)));
    }

    private void SuTorcia(object sender, RoutedEventArgs e) => Comanda(new Comando(Torcia: PulsanteTorcia.IsChecked == true));

    private void SuFuoco(object sender, RoutedEventArgs e) => Comanda(new Comando(Fuoco: "continuo"));

    /// <summary>Restituisce vero se il tasto è servito: senza telefono o senza quell'obiettivo il tasto passa oltre.</summary>
    private bool ScegliObiettivo(int numero)
    {
        if (sessione is null || capacitaAttuali is null) return false;
        if (Scorciatoie.Obiettivo(numero, obiettiviMostrati.Count) is not int indice) return false;
        SuObiettivo(obiettiviMostrati[indice]);
        return true;
    }

    private bool CambiaZoom(int verso)
    {
        if (sessione is null || capacitaAttuali is null || PannelloZoom.Visibility != Visibility.Visible) return false;
        // SuZoom manda il comando al telefono.
        CursoreZoom.Value = Scorciatoie.Zoom(CursoreZoom.Value, CursoreZoom.Maximum, verso);
        return true;
    }

    private bool FuocoDaTastiera()
    {
        if (sessione is null || capacitaAttuali is null) return false;
        Comanda(new Comando(Fuoco: "continuo"));
        return true;
    }

    /// <summary>
    /// Lo «stato» del telefono nella webcam ha cambiato i comandi (pizzico, obiettivo, torcia spenta dalla frontale,
    /// ISO e tempo sul telefono): i controlli si allineano, senza mandare nulla.
    /// </summary>
    private void MostraComandiDelTelefono(TelefonoCollegato collegato)
    {
        if (statoTelefono?.Obiettivo is { } obiettivo && obiettivo == obiettivoInAttesa) obiettivoInAttesa = null;
        if (capacitaAttuali is { } capacita) MostraObiettivi(capacita.Obiettivi, ObiettivoAttuale);
        ImpostaComandi(collegato.Comandi);
    }

    // MARK: regole fini (ISO, tempo, bianco)

    private void SuEsposizioneManuale(object sender, RoutedEventArgs e)
    {
        if (PannelloManuale is null) return;
        var manuale = EsposizioneManuale.IsOn;
        MostraComandiManuali();
        Comanda(manuale ? new Comando(Iso: Math.Round(CursoreIso.Value), Tempo: TempoScelto) : new Comando(Iso: 0, Tempo: 0));
    }

    private void SuIso(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Iso: Math.Round(e.NewValue)));

    private void SuTempo(object sender, SelectionChangedEventArgs e)
    {
        if (EsposizioneManuale is null || !EsposizioneManuale.IsOn) return;
        Comanda(new Comando(Tempo: TempoScelto));
    }

    private int TempoScelto => SceltaTempo.SelectedItem is ComboBoxItem { Tag: string testo } && int.TryParse(testo, out var tempo) ? tempo : 50;

    private void SuBiancoAutomatico(object sender, RoutedEventArgs e)
    {
        // Toggled può scattare mentre la finestra si sta ancora creando.
        if (CursoreBianco is null) return;
        MostraComandiManuali();
        Comanda(new Comando(Bianco: BiancoAutomatico.IsOn ? 0 : (int)CursoreBianco.Value));
    }

    private void SuBianco(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Bianco: (int)e.NewValue));

    // MARK: profili pronti (Riunione, Lezione, Diretta, Colloquio)

    /// <summary>
    /// «Profilo»: manda al telefono nella webcam gli effetti del profilo in un solo «comando» e chiede il suo formato.
    /// Solo con WebcamLR Pro, come sul Mac.
    /// </summary>
    private void ApplicaProfiloPronto(ProfiloPronto profilo)
    {
        if (Scelto is not { Sessione: { } attiva } scelto || capacitaAttuali is not { } capacita) return;
        if (!ProAttivo)
        {
            NotaPro.Mostra(GrigliaProfili);
            return;
        }
        // Un profilo con un altro formato chiude la registrazione: prima si chiede (windows.md 1.6).
        var formato = OpzioneQualita.Richiesta(profilo.Larghezza, profilo.Altezza, profilo.Fps, scelto.Formato, capacita.Formati, pro: true);
        PrimaDiFermareLaRegistrazione(() =>
        {
            if (Scelto == scelto && scelto.Sessione == attiva) ApplicaProfiloPronto(profilo, scelto, attiva, capacita, formato);
        }, cambiaIlVideo: formato is not null);
    }

    private void ApplicaProfiloPronto(ProfiloPronto profilo, TelefonoCollegato scelto, SessioneComputer attiva, Capacita capacita, FormatoVideo? formato)
    {
        if (profilo.Comando(capacitaEffetti ?? capacita) is { } comando)
        {
            ritardoEffetti?.Stop();
            Comanda(effetti.Subito(comando, AdessoMs));
        }
        scelto.ProfiloPronto = profilo.Id;
        registro.Aggiungi(Testi.T("Profilo_Applicato", profilo.Nome, DiChi(scelto)));
        if (profilo.Avviso(capacita, statoTelefono?.Obiettivo) is { } avviso) MostraAvvisoRiprese(avviso);
        if (formato is not null)
        {
            registro.Aggiungi(Testi.T("Formato_Chiesto", formato.Larghezza, formato.Altezza, formato.Fps));
            ChiediFormato(scelto, attiva, formato);
        }
        MostraValoriEffetti();
    }

    /// <summary>Le schede dei profili: quella scelta nell'accento (selezione), mai in corallo; «Personalizzato» se è cambiato qualcosa.</summary>
    private void MostraProfili()
    {
        var (scelto, personalizzato) = sessione is not null && ProAttivo
            ? ProfiloPronto.Stato(Scelto?.ProfiloPronto, effetti.Valori, capacitaEffetti)
            : (null, false);
        foreach (var (profilo, scheda, icona, nome) in schedeProfili)
        {
            var acceso = profilo == scelto;
            scheda.Background = Pennello(acceso ? "AccentoTenue" : "Pannello");
            scheda.BorderBrush = Pennello(acceso ? "Accento" : "LineaTenue");
            scheda.BorderThickness = new Thickness(acceso ? 1.5 : 1);
            icona.Foreground = Pennello(acceso ? "Accento" : "SalviaChiara");
            nome.Foreground = Pennello(acceso ? "AccentoChiaro" : "Testo");
            AutomationProperties.SetItemStatus(scheda, acceso ? Testi.T("Accessibilita_Scelto") : "");
        }
        SegnoPersonalizzato.Visibility = Visibile(personalizzato);
    }

    // MARK: profili salvati (funzione 23)

    private void SuAperturaProfili(object? sender, object e)
    {
        MenuProfili.Items.Clear();
        var profili = Preferenze.Profili;
        foreach (var nome in profili.Keys.Order())
        {
            var voce = new MenuFlyoutItem { Text = nome };
            voce.Click += (_, _) => ApplicaProfilo(profili[nome]);
            // Passo 8 (windows.md 2.9): clic destro con Applica ed Elimina… (MainWindow.Menu.cs).
            voce.ContextFlyout = MenuProfiloSalvato(nome, () => ApplicaProfilo(profili[nome]));
            MenuProfili.Items.Add(voce);
        }
        if (profili.Count > 0) MenuProfili.Items.Add(new MenuFlyoutSeparator());
        var salva = new MenuFlyoutItem { Text = Testi.T("Profili_Salva") };
        salva.Click += async (_, _) =>
        {
            // async void: se c'è già una finestra di dialogo aperta, ShowAsync fallisce e non deve chiudere l'app.
            try { await ChiediNomeProfiloAsync(); }
            catch (Exception) { }
        };
        MenuProfili.Items.Add(salva);
        if (profili.Count == 0) return;
        var elimina = new MenuFlyoutSubItem { Text = Testi.T("Elimina") };
        foreach (var nome in profili.Keys.Order())
        {
            var voce = new MenuFlyoutItem { Text = nome };
            voce.Click += (_, _) => ChiediEliminaProfilo(nome);
            elimina.Items.Add(voce);
        }
        MenuProfili.Items.Add(elimina);
    }

    /// <summary>
    /// Elimina un profilo salvato, dal sottomenu «Elimina» o dal clic destro. Passo 4 (windows.md 1.8): prima la domanda,
    /// «Annulla» predefinito. async void: un errore non chiude l'app.
    /// </summary>
    private async void ChiediEliminaProfilo(string nome)
    {
        try
        {
            if (!await ChiediAsync(Conferme.EliminaProfilo(nome))) return;
            var rimasti = Preferenze.Profili;
            rimasti.Remove(nome);
            Preferenze.Profili = rimasti;
        }
        catch (Exception errore) { App.ScriviErrore(errore); }
    }

    private async Task ChiediNomeProfiloAsync()
    {
        await PreparaDialogoAsync();
        var casella = new TextBox { PlaceholderText = Testi.T("Profili_NomeEsempio"), MaxLength = 40 };
        var finestra = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = Testi.T("Profili_Nuovo"),
            Content = new StackPanel
            {
                Spacing = 8,
                Children =
                {
                    new TextBlock { Text = Testi.T("Profili_Spiegazione"), TextWrapping = TextWrapping.Wrap },
                    casella,
                },
            },
            PrimaryButtonText = Testi.T("Salva"),
            CloseButtonText = Testi.T("Annulla"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await finestra.ShowAsync() != ContentDialogResult.Primary) return;
        var nome = casella.Text.Trim();
        if (nome.Length == 0) return;
        var profili = Preferenze.Profili;
        // Un nome già usato (maiuscole a parte) chiede prima di sostituire quel profilo (passo 4, windows.md 1.8).
        if (Conferme.NomeGiaUsato(nome, profili.Keys) is { } esistente)
        {
            if (!await ChiediAsync(Conferme.SostituisciProfilo(esistente))) return;
            profili.Remove(esistente);
        }
        profili[nome] = new ProfiloFotocamera(statoTelefono?.Obiettivo,
            CursoreZoom.Value, PulsanteTorcia.IsChecked == true, CursoreEsposizione.Value,
            BiancoAutomatico.IsOn, CursoreBianco.Value, EsposizioneManuale.IsOn, CursoreIso.Value, TempoScelto);
        Preferenze.Profili = profili;
    }

    /// <summary>Mette i comandi come nel profilo e li manda al telefono in un solo messaggio. ISO, tempo e bianco solo con Pro.</summary>
    private void ApplicaProfilo(ProfiloFotocamera profilo)
    {
        if (capacitaAttuali is not { } capacita || Scelto is not { } scelto) return;
        var obiettivo = profilo.Obiettivo is { } voluto && capacita.Obiettivi.Contains(voluto) ? voluto : null;
        // Un profilo con un altro obiettivo chiude la registrazione: prima si chiede (windows.md 1.6).
        PrimaDiFermareLaRegistrazione(() =>
        {
            if (Scelto == scelto && capacitaAttuali == capacita) ApplicaProfilo(profilo, scelto, capacita, obiettivo);
        }, cambiaIlVideo: obiettivo is not null && obiettivo != statoTelefono?.Obiettivo);
    }

    private void ApplicaProfilo(ProfiloFotocamera profilo, TelefonoCollegato scelto, Capacita capacita, string? obiettivo)
    {
        var manuale = profilo.EsposizioneManuale && ManualeDisponibile && capacita.IsoMinimo is not null;
        var comando = new Comando(Obiettivo: obiettivo, Zoom: Math.Clamp(profilo.Zoom, 1, Math.Max(1, capacita.ZoomMassimo)),
            Torcia: capacita.Torcia ? profilo.Torcia : null,
            Esposizione: Math.Clamp(Math.Round(profilo.Esposizione, 1), -2, 2),
            Bianco: profilo.BiancoAutomatico ? 0 : (int)profilo.Bianco,
            Iso: manuale ? Math.Round(profilo.Iso) : 0, Tempo: manuale ? profilo.Tempo : 0);
        if (obiettivo is not null && obiettivo != statoTelefono?.Obiettivo) obiettivoInAttesa = obiettivo;
        Comanda(comando);
        // I controlli come il telefono li avrà (Comanda ha già tolto le parti Pro con un telefono gratis).
        ImpostaComandi(scelto.Comandi);
        if (capacitaAttuali is { } attuali) MostraObiettivi(attuali.Obiettivi, ObiettivoAttuale);
    }

    // MARK: qualità video (menu dell'etichetta sul video)

    /// <summary>
    /// Il menu della qualità, come nel disegno finale: le scelte dalle capacità del telefono, la spunta su ciò che arriva
    /// ora; con un telefono gratis quelle sopra 720p a 30 fps restano grigie con «PRO» e dicono come sbloccarle.
    /// </summary>
    private void MostraQualita()
    {
        var (libere, bloccate) = OpzioneQualita.Menu(capacitaAttuali, BloccoPro);
        var nuove = libere.Select(o => (o, false)).Concat(bloccate.Select(o => (o, true))).ToList();
        var attuale = OpzioneQualita.Attuale(statistiche, libere);
        var comandi = Scelto is { Sessione: not null } && capacitaAttuali is not null;
        if (!qualitaMostrate.SequenceEqual(nuove) || !Equals(qualitaSegnata, attuale) || qualitaComandi != comandi)
        {
            qualitaMostrate = nuove;
            qualitaSegnata = attuale;
            qualitaComandi = comandi;
            ElencoQualita.Children.Clear();
            foreach (var (opzione, bloccata) in nuove)
                ElencoQualita.Children.Add(VoceQualita(opzione, bloccata, Equals(opzione, attuale), comandi));
        }
        NotaQualitaPro.Visibility = Visibile(bloccate.Count > 0);
        // Il 4K si nomina solo se il telefono lo sa fare.
        var con4K = OpzioneQualita.Con4K(libere, bloccate);
        NotaQualitaPro.Text = con4K ? Testi.T("Qualita_NotaPro4K") : Testi.T("Qualita_NotaPro");
        NotaScendere.Text = con4K ? Testi.T("Qualita_Scendere4K") : Testi.T("Qualita_Scendere");
        if (telefono is not null && statistiche is { Larghezza: > 0 } s)
        {
            TestoQualitaArriva.Text = Testi.T("Qualita_ArrivaOra", OpzioneQualita.NomeRisoluzione(Math.Min(s.Larghezza, s.Altezza)), s.Fps, (s.Codec == Codec.Hevc ? "HEVC" : "H.264"));
            TestoQualitaArriva.Visibility = Visibility.Visible;
        }
        else
        {
            TestoQualitaArriva.Visibility = Visibility.Collapsed;
        }
    }

    /// <summary>Una riga del menu: «1080p · 30 fps», con la spunta se è quella che arriva, o grigia con «PRO».</summary>
    private Button VoceQualita(OpzioneQualita opzione, bool bloccata, bool scelta, bool comandi)
    {
        var riga = new Grid { ColumnSpacing = 8 };
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        riga.Children.Add(new TextBlock
        {
            Text = opzione.Testo,
            FontSize = 14,
            Foreground = Pennello(bloccata ? "TestoSecondario" : "Testo"),
            VerticalAlignment = VerticalAlignment.Center,
        });
        FrameworkElement? destra = bloccata ? new SegnoPro { VerticalAlignment = VerticalAlignment.Center }
            : scelta ? new FontIcon { Glyph = "\uE73E", FontSize = 13, Foreground = Pennello("Accento") }
            : null;
        if (destra is not null)
        {
            Grid.SetColumn(destra, 1);
            riga.Children.Add(destra);
        }
        var voce = new Button
        {
            Style = (Style)Application.Current.Resources["VoceMenu"],
            Content = riga,
            Background = scelta ? Pennello("PannelloChiaro") : null,
            // Senza telefono (o prima delle capacità) le scelte si vedono ma non partono.
            IsEnabled = comandi,
        };
        AutomationProperties.SetName(voce, bloccata ? Testi.T("Qualita_ConPro", opzione.Testo)
            : scelta ? Testi.T("Voce_Scelta", opzione.Testo) : opzione.Testo);
        voce.Click += (_, _) => SuQualitaScelta(voce, opzione, bloccata);
        return voce;
    }

    private void SuAperturaQualita(object? sender, object e)
    {
        RidaiAlMenu();
        MostraNumeri();
        // Si rifà da capo: le capacità o il Pro possono essere cambiati a menu chiuso.
        qualitaMostrate = [];
        MostraQualita();
    }

    private void SuQualitaScelta(Button voce, OpzioneQualita opzione, bool bloccata)
    {
        if (bloccata)
        {
            // Una scelta «PRO» con un telefono gratis: la nota dice come sbloccarla, il menu resta su ciò che arriva.
            NotaPro.Mostra(voce);
            return;
        }
        if (Scelto is not { Sessione: { } attiva } scelto) return;
        FinestraNumeri.Hide();
        if (OpzioneQualita.Richiesta(opzione.Larghezza, opzione.Altezza, opzione.Fps, scelto.Formato, capacitaAttuali?.Formati, ProAttivo) is { } formato)
        {
            // Un'altra qualità è un altro video: la registrazione si chiude, quindi prima si chiede (windows.md 1.6).
            PrimaDiFermareLaRegistrazione(() =>
            {
                if (Scelto != scelto || scelto.Sessione != attiva) return;
                registro.Aggiungi(Testi.T("Formato_Chiesto", formato.Larghezza, formato.Altezza, formato.Fps));
                ChiediFormato(scelto, attiva, formato);
            });
        }
    }

    // MARK: sezioni richiudibili

    private void SuSezione(object sender, RoutedEventArgs e)
    {
        switch ((sender as FrameworkElement)?.Tag as string)
        {
            case "effetti": Preferenze.SezioneEffetti = !Preferenze.SezioneEffetti; break;
            case "regole": Preferenze.SezioneRegoleFini = !Preferenze.SezioneRegoleFini; break;
        }
        MostraSezioni();
    }

    /// <summary>Chiuse di serie e ricordate, come sul Mac; un clic sul titolo (non solo sulla freccia) le apre.</summary>
    private void MostraSezioni()
    {
        Sezione(IntestazioneEffetti, FrecciaEffetti, ContenutoEffetti, Testi.T("Sezione_Effetti"), Preferenze.SezioneEffetti);
        Sezione(IntestazioneRegoleFini, FrecciaRegoleFini, ContenutoRegoleFini, Testi.T("Sezione_RegoleFini"), Preferenze.SezioneRegoleFini);

        static void Sezione(Button intestazione, FontIcon freccia, UIElement contenuto, string nome, bool aperta)
        {
            freccia.Glyph = aperta ? "" : "";
            contenuto.Visibility = aperta ? Visibility.Visible : Visibility.Collapsed;
            AutomationProperties.SetName(intestazione, aperta ? Testi.T("Accessibilita_SezioneAperta", nome) : Testi.T("Accessibilita_SezioneChiusa", nome));
        }
    }

    // MARK: WebcamLR Pro

    /// <summary>
    /// Con un telefono gratis profili, foto, registrazione, «Regole fini» e gli effetti Pro restano a vista con il segno
    /// «PRO», grigi, e dicono come sbloccarli dal telefono. Da chiamare dopo aver deciso cosa è disponibile (riaccende).
    /// </summary>
    private void AggiornaPro()
    {
        if (ZonaProfili is null) return;
        var bloccato = BloccoPro;
        ZonaProfili.Bloccata = bloccato;
        RigaProProfili.Visibility = Visibile(bloccato);
        foreach (var zona in new[] { ZonaInquadratura, ZonaFiltro, ZonaPelle, ZonaScritta, ZonaDoppiaVista, ZonaGobbo })
            zona.Bloccata = bloccato;
        RigaProEffetti.Visibility = Visibile(bloccato);
        // «Sfocato» è gratis; «Sostituito» è di WebcamLR Pro.
        VoceSfondoSostituito.IsEnabled = !bloccato;
        NotaSfondoPro.Visibility = Visibile(bloccato && PannelloSfondo.Visibility == Visibility.Visible);
        ZonaRegoleFini.Bloccata = bloccato;
        SegnoProRegoleFini.Visibility = Visibile(bloccato);
        RigaProRegoleFini.Visibility = Visibile(bloccato);
        ZonaFoto.Bloccata = bloccato;
        // «Ferma» resta sempre attivo: una registrazione partita resta fermabile.
        ZonaRegistra.Bloccata = bloccato && registrazione is null;
        // Il secondo telefono non si collega finché quello nella webcam è gratis.
        NotaSecondoTelefono.Visibility = Visibile(bloccato && telefoni.Conteggio == 1);
        MostraProfili();
        MostraQualita();
        finestraGobbo?.Aggiorna(GobboDisponibile);
        // La schermata di attesa personalizzata è di Pro: senza, la webcam torna a quella di WebcamLR.
        AggiornaAttesa();
    }
}
