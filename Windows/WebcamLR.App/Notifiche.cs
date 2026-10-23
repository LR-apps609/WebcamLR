using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace WebcamLR;

/// <summary>
/// Notifiche di Windows (round 2, funzione 39): telefono collegato o perso, avvisi dal telefono.
/// Se qualcosa non va (servizio spento, criteri aziendali) l'app continua senza notifiche:
/// nessun errore qui deve chiuderla.
/// </summary>
public sealed class Notifiche : IDisposable
{
    private readonly bool registrate;

    /// <param name="clic">Clic sulla notifica: arriva su un thread di sistema.</param>
    public Notifiche(Action clic)
    {
        try
        {
            var gestore = AppNotificationManager.Default;
            // Il gestore va collegato prima di Register, altrimenti un clic lancerebbe un'altra copia dell'app.
            gestore.NotificationInvoked += (_, _) => clic();
            gestore.Register();
            registrate = true;
        }
        catch (Exception)
        {
            registrate = false;
        }
    }

    public void Mostra(string titolo, string testo)
    {
        if (!registrate) return;
        try
        {
            var notifica = new AppNotificationBuilder()
                .AddText(titolo)
                .AddText(testo)
                .BuildNotification();
            AppNotificationManager.Default.Show(notifica);
        }
        catch (Exception) { }
    }

    public void Dispose()
    {
        if (!registrate) return;
        try { AppNotificationManager.Default.Unregister(); }
        catch (Exception) { }
    }
}
