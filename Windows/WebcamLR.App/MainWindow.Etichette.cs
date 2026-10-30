using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Le etichette sul video del disegno finale (Documenti/Interfaccia finale.md): la strada del collegamento, che con più
/// strade apre la scelta Automatico · Wi-Fi · Cavo USB (con la latenza e «più veloce ora»), e «CAM 1» in basso a sinistra.
/// La regola «Automatico» senza sbalzi e il menu sono in WebcamLR.Ricevitore (SceltaStrada.cs), provati con i test.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Le voci del menu della strada mostrate adesso, per non rifarlo a ogni statistica.</summary>
    private IReadOnlyList<VoceCollegamento> vociStradaMostrate = [];

    /// <summary>Il telefono nella webcam sa cambiare strada e ne conosce più di una: l'etichetta apre la scelta.</summary>
    private bool StradaSceglibile =>
        Scelto is { Sessione: not null } scelto && MenuCollegamento.Cliccabile(scelto.SaScegliereStrada, scelto.Strade);

    private void SuChipCollegamento(object sender, RoutedEventArgs e)
    {
        if (StradaSceglibile) FlyoutBase.ShowAttachedFlyout(ChipCollegamento);
    }

    private void SuAperturaCollegamento(object? sender, object e)
    {
        RidaiAlMenu();
        vociStradaMostrate = [];
        MostraMenuCollegamento();
    }

    /// <summary>«Automatico» (sceglie all'inizio, poi resta), «Wi-Fi · 38 ms», «Cavo USB · 9 ms», con la spunta sulla scelta.</summary>
    private void MostraMenuCollegamento()
    {
        if (Scelto is not { Strade: { } strade } scelto) return;
        TitoloMenuCollegamento.Text = Testi.T("Collegamento_TitoloMenu");
        ToolTipService.SetToolTip(TitoloMenuCollegamento, scelto.Nome);
        var voci = MenuCollegamento.Voci(strade, scelto.Regola.Preferenza);
        if (voci.SequenceEqual(vociStradaMostrate)) return;
        vociStradaMostrate = voci;
        ElencoCollegamento.Children.Clear();
        foreach (var voce in voci) ElencoCollegamento.Children.Add(VoceStrada(voce));
    }

    private Button VoceStrada(VoceCollegamento voce)
    {
        var riga = new Grid { ColumnSpacing = Token.SpazioStretto };
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        riga.Children.Add(new TextBlock { Text = voce.Testo, FontSize = Token.MisuraCorpo, VerticalAlignment = VerticalAlignment.Center });
        var destra = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioStretto, VerticalAlignment = VerticalAlignment.Center };
        if (voce.Preferenza == PreferenzaCollegamento.Automatico)
        {
            destra.Children.Add(new TextBlock { Text = Testi.T("Collegamento_AutomaticoNota"), FontSize = Token.MisuraNota, Foreground = Pennello("TestoSecondario"), VerticalAlignment = VerticalAlignment.Center });
        }
        if (voce.PiuVeloce)
        {
            // Solo un'informazione: «Automatico» non segue la latenza.
            destra.Children.Add(new Border
            {
                Background = Pennello("AccentoTenue"),
                CornerRadius = new CornerRadius(Token.RaggioMinimo),
                Padding = Token.PaddingSegno,
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock { Text = Testi.T("Collegamento_PiuVeloce"), FontSize = Token.MisuraDettaglio, FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["CorpoForte"], Foreground = Pennello("Accento") },
            });
        }
        if (voce.Scelta) destra.Children.Add(new FontIcon { Glyph = "", FontSize = Token.MisuraCorpoPiccolo, Foreground = Pennello("Accento"), VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(destra, 1);
        riga.Children.Add(destra);
        var pulsante = new Button
        {
            Style = (Style)Application.Current.Resources["VoceMenu"],
            Content = riga,
            Background = voce.Scelta ? Pennello("PannelloChiaro") : null,
        };
        var nome = voce.Scelta ? Testi.T("Voce_Scelta", voce.Testo) : voce.Testo;
        if (voce.PiuVeloce) nome = Testi.T("Collegamento_PiuVeloceNome", nome);
        AutomationProperties.SetName(pulsante, nome);
        pulsante.Click += (_, _) => ScegliStrada(voce.Preferenza);
        return pulsante;
    }

    /// <summary>
    /// La scelta va al telefono (<c>comando.collegamento</c>), che cambia strada senza fermare il video, e vale anche qui per
    /// le sessioni che arrivano (cavo dell'iPhone). Scegliendo il cavo, o «Automatico», il cavo lasciato per il Wi-Fi torna.
    /// </summary>
    private void ScegliStrada(string preferenza)
    {
        FinestraCollegamento.Hide();
        if (Scelto is not { Sessione: { } attiva } scelto) return;
        var comando = ContrattoCollegamento.Comando(preferenza);
        scelto.Regola.Imposta(preferenza, telefoni.Orologio());
        registro.Aggiungi(Testi.T("Registro_StradaScelta", scelto.Nome, PreferenzaCollegamento.Testo(preferenza)));
        _ = ComandaAsync(attiva, comando);
        if (preferenza != PreferenzaCollegamento.WiFi) cavo.RiprendiScelti();
        vociStradaMostrate = [];
        AggiornaChip();
    }

    /// <summary>«CAM 1 · iPhone di Ledion» in basso a sinistra sul video; in corallo, con «in onda», quando un'app lo usa.</summary>
    private void MostraEtichettaCam(bool visibile)
    {
        EtichettaCam.Visibility = Visibile(visibile && telefono is not null);
        if (telefono is not { } ciao) return;
        var inOndaOra = inOnda && statoCollegamento == FaseCollegamento.Collegato;
        TestoCam.Text = inOndaOra ? Testi.T("Cam_UnoInOnda", ciao.Nome) : Testi.T("Cam_Uno", ciao.Nome);
        TestoCam.Foreground = Pennello(inOndaOra ? "Fondo" : "Testo");
        EtichettaCam.Background = Pennello(inOndaOra ? "Tally" : "VeloEtichetta");
    }
}
