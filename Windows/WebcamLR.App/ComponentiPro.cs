using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il segno «PRO» accanto a un comando che fa parte di WebcamLR Pro, come in Stile (SegnoPro): testo scuro sull'accento
/// salvia, mai corallo.
/// </summary>
public sealed partial class SegnoPro : Grid
{
    private readonly Border fondo;
    private readonly TextBlock lettere;

    public SegnoPro()
    {
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Left;
        lettere = new TextBlock
        {
            Text = "PRO",
            FontFamily = (FontFamily)Application.Current.Resources["Etichette"],
            FontSize = 12,
            CharacterSpacing = 80,
            Foreground = (Brush)Application.Current.Resources["Fondo"],
        };
        fondo = new Border
        {
            Background = (Brush)Application.Current.Resources["Accento"],
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(5, 0, 5, 1),
            Child = lettere,
        };
        Children.Add(fondo);
        AutomationProperties.SetName(this, Testi.T("Pro_Funzione"));
    }

    /// <summary>Il segno grande, accanto al titolo della pagina «WebcamLR Pro».</summary>
    public bool Grande
    {
        get => lettere.FontSize > 12;
        set
        {
            lettere.FontSize = value ? 16 : 12;
            fondo.Padding = value ? new Thickness(8, 2, 8, 3) : new Thickness(5, 0, 5, 1);
            fondo.CornerRadius = new CornerRadius(value ? 5 : 4);
        }
    }
}

/// <summary>Una riga sotto una sezione Pro bloccata: «PRO Sblocca WebcamLR Pro sul telefono», con la strada al passaggio.</summary>
public sealed partial class RigaPro : StackPanel
{
    public RigaPro()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 6;
        Children.Add(new SegnoPro());
        Children.Add(new TextBlock
        {
            Text = RegolePro.Sblocca,
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 230,
            Foreground = (Brush)Application.Current.Resources["TestoSecondario"],
            VerticalAlignment = VerticalAlignment.Center,
        });
        ToolTipService.SetToolTip(this, RegolePro.Strada);
        AutomationProperties.SetName(this, $"{RegolePro.Sblocca}. {RegolePro.Strada}");
    }
}

/// <summary>
/// Un comando di WebcamLR Pro, come <c>richiedePro</c> sul Mac (Mac/Sorgenti/ProMac.swift). Con un telefono gratis il
/// contenuto resta a vista ma grigio e spento, con il segno «PRO» accanto (se <see cref="Segno"/>); un clic apre la nota
/// con la strada per sbloccarlo dal telefono. Sbloccato, non cambia nulla.
/// Il contenuto si scrive dentro, nello XAML (prima colonna); segno e copertura li aggiunge la zona.
/// </summary>
public sealed partial class ZonaPro : Grid
{
    private readonly SegnoPro segno = new() { Visibility = Visibility.Collapsed, Margin = new Thickness(6, 0, 0, 0) };
    private readonly CoperturaSpenta copertura = new() { Visibility = Visibility.Collapsed };
    private bool bloccata;

    public ZonaPro()
    {
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        SetColumn(segno, 1);
        SetColumnSpan(copertura, 2);
        // Sopra il contenuto (aggiunto dopo, dallo XAML): il clic arriva qui e apre la nota.
        Canvas.SetZIndex(copertura, 100);
        copertura.Tapped += SuTocco;
        copertura.SpiegazioneChiesta += (_, _) => NotaPro.Mostra(copertura);
        Children.Add(segno);
        Children.Add(copertura);
    }

    /// <summary>Il segno «PRO» accanto: falso quando il segno è già nel titolo della sezione.</summary>
    public bool Segno { get; set; } = true;

    public bool Bloccata
    {
        get => bloccata;
        set
        {
            bloccata = value;
            segno.Visibility = value && Segno ? Visibility.Visible : Visibility.Collapsed;
            copertura.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
            ToolTipService.SetToolTip(copertura, value ? RegolePro.Sblocca : null);
            Control? primo = null;
            foreach (var figlio in Children)
            {
                if (figlio == segno || figlio == copertura || figlio is not UIElement elemento) continue;
                elemento.Opacity = value ? 0.45 : 1;
                if (value) Spegni(elemento);
                primo ??= PrimoControllo(elemento);
            }
            // Con Tab la copertura prende il posto del comando spento (windows.md 2.13): stesso ordine, e l'Assistente
            // vocale dice «Foto, non disponibile: sblocca WebcamLR Pro sul telefono».
            if (!value) return;
            copertura.TabIndex = primo?.TabIndex ?? int.MaxValue;
            var nome = primo is null ? null : AutomationProperties.GetName(primo);
            copertura.Descrivi(nome, RegolePro.Sblocca);
        }
    }

    private static Control? PrimoControllo(UIElement elemento) => elemento switch
    {
        Control controllo => controllo,
        Panel pannello => pannello.Children.Select(PrimoControllo).FirstOrDefault(c => c is not null),
        _ => null,
    };

    /// <summary>Bloccata spegne i comandi dentro (anche da tastiera); li riaccende chi decide la disponibilità, prima.</summary>
    private static void Spegni(UIElement elemento)
    {
        if (elemento is Control controllo) controllo.IsEnabled = false;
        else if (elemento is Panel pannello) foreach (var figlio in pannello.Children) Spegni(figlio);
    }

    private void SuTocco(object sender, TappedRoutedEventArgs e)
    {
        NotaPro.Mostra(copertura, e.GetPosition(copertura));
        e.Handled = true;
    }
}

/// <summary>La nota del clic su un comando Pro bloccato: «Sblocca WebcamLR Pro sul telefono» e la strada.</summary>
public static class NotaPro
{
    public static void Mostra(FrameworkElement dove, Windows.Foundation.Point? posizione = null)
    {
        var nota = new Flyout
        {
            Content = new StackPanel
            {
                Spacing = 6,
                MaxWidth = 300,
                Children =
                {
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Spacing = 6,
                        Children =
                        {
                            new SegnoPro(),
                            new TextBlock
                            {
                                Text = RegolePro.Sblocca,
                                FontFamily = (FontFamily)Application.Current.Resources["CorpoEvidente"],
                                VerticalAlignment = VerticalAlignment.Center,
                            },
                        },
                    },
                    new TextBlock
                    {
                        Text = RegolePro.Strada,
                        FontSize = 12,
                        TextWrapping = TextWrapping.Wrap,
                        Foreground = (Brush)Application.Current.Resources["TestoSecondario"],
                    },
                },
            },
        };
        nota.ShowAt(dove, new FlyoutShowOptions { Position = posizione, Placement = FlyoutPlacementMode.Bottom });
    }
}

/// <summary>
/// La copertura trasparente sopra un comando spento (senza telefono, con la fotocamera posteriore, Pro bloccato), che
/// dice perché (1.0 beta 2, passo 6; windows.md 2.13). Il comando sotto è spento e la tastiera lo salta: la copertura
/// prende il suo posto con Tab (stesso TabIndex), spiega con Invio o Spazio come con il clic
/// (<see cref="SpiegazioneChiesta"/>; il clic arriva con Tapped) e l'Assistente vocale legge «Specchia, non disponibile:
/// solo con la fotocamera frontale», con il motivo anche in HelpText. Non si vede: solo il riquadro del fuoco di sistema.
/// </summary>
public sealed partial class CoperturaSpenta : ContentControl
{
    public CoperturaSpenta()
    {
        IsTabStop = true;
        UseSystemFocusVisuals = true;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        VerticalAlignment = VerticalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        // Un fondo trasparente riceve il clic (senza fondo il clic passerebbe al comando spento sotto).
        Content = new Border { Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
    }

    /// <summary>Invio o Spazio sulla copertura: la stessa nota del clic.</summary>
    public event EventHandler? SpiegazioneChiesta;

    /// <summary>Il nome per l'Assistente vocale («{nome}, non disponibile: {motivo}») e il motivo in HelpText.</summary>
    public void Descrivi(string? nome, string motivo)
    {
        AutomationProperties.SetName(this, DescrizioneStato.NonDisponibile(nome, motivo));
        AutomationProperties.SetHelpText(this, motivo);
    }

    protected override void OnKeyDown(KeyRoutedEventArgs e)
    {
        if (e.Key is Windows.System.VirtualKey.Enter or Windows.System.VirtualKey.Space)
        {
            e.Handled = true;
            SpiegazioneChiesta?.Invoke(this, EventArgs.Empty);
            return;
        }
        base.OnKeyDown(e);
    }

    protected override AutomationPeer OnCreateAutomationPeer() => new PeerCopertura(this);

    /// <summary>Per l'Assistente vocale è un pulsante: il nome dice che non è disponibile e perché.</summary>
    private sealed partial class PeerCopertura : FrameworkElementAutomationPeer
    {
        public PeerCopertura(CoperturaSpenta copertura) : base(copertura) { }

        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Button;

        protected override string GetClassNameCore() => nameof(CoperturaSpenta);
    }
}
