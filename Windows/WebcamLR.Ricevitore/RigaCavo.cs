namespace WebcamLR.Ricevitore;

/// <summary>Quello che un cavo sa di sé, per la riga «Cavo USB» e la diagnosi.</summary>
/// <param name="Verificato">Il servizio è già stato cercato almeno una volta.</param>
/// <param name="TelefonoAlCavo">Un telefono è sul cavo e si prova a raggiungerlo (non sospeso).</param>
/// <param name="DaAutorizzare">Solo Android: telefoni che aspettano «Consenti» alla domanda del debug USB.</param>
public sealed record SituazioneCavo(bool Verificato, StatoCavo Stato, bool TelefonoAlCavo, int DaAutorizzare = 0)
{
    public static SituazioneCavo Di(ClienteUsbmux cavo) => new(cavo.Verificato, cavo.Stato, cavo.TelefonoAlCavo);

    public static SituazioneCavo Di(ClienteAdb cavo) => new(cavo.Verificato, cavo.Stato, cavo.TelefonoAlCavo, cavo.DaAutorizzare);
}

/// <summary>Che cosa dice la riga «Cavo USB» della colonna «Connessione».</summary>
public enum StatoRigaCavo
{
    /// <summary>«In uso»: un iPhone (o un Android con il Tethering USB) usa il cavo.</summary>
    InUso,
    /// <summary>«In uso · Android»: un telefono Android usa il cavo.</summary>
    InUsoAndroid,
    /// <summary>«…»: i servizi non sono ancora stati cercati.</summary>
    Verifica,
    Collegato,
    /// <summary>«Consenti sul telefono»: un Android sul cavo aspetta la risposta alla domanda del debug USB.</summary>
    DaAutorizzare,
    /// <summary>«Apri l'app»: un telefono è sul cavo, WebcamLR sul telefono non risponde.</summary>
    ApriApp,
    /// <summary>«Non disponibile»: né il servizio di Apple né adb rispondono.</summary>
    NonDisponibile,
    /// <summary>«Nessun telefono»: almeno un servizio c'è, nessun telefono sul cavo.</summary>
    NessunTelefono,
}

/// <summary>La riga «Cavo USB» con i due cavi (Qualità 17): iPhone con usbmux, Android con adb. Pura logica, con i test.</summary>
public static class RigaCavo
{
    /// <param name="inUso">Un telefono collegato usa il cavo USB.</param>
    /// <param name="inUsoAndroid">Tra quelli, un telefono Android.</param>
    public static StatoRigaCavo Stato(bool inUso, bool inUsoAndroid, SituazioneCavo iphone, SituazioneCavo android)
    {
        if (inUsoAndroid) return StatoRigaCavo.InUsoAndroid;
        if (inUso) return StatoRigaCavo.InUso;
        if (!iphone.Verificato && !android.Verificato) return StatoRigaCavo.Verifica;
        if (iphone.Stato == StatoCavo.Collegato || android.Stato == StatoCavo.Collegato) return StatoRigaCavo.Collegato;
        if (android.DaAutorizzare > 0) return StatoRigaCavo.DaAutorizzare;
        if (iphone.TelefonoAlCavo || android.TelefonoAlCavo) return StatoRigaCavo.ApriApp;
        var servizio = (iphone.Verificato && iphone.Stato != StatoCavo.ServizioAssente)
            || (android.Verificato && android.Stato != StatoCavo.ServizioAssente);
        return servizio ? StatoRigaCavo.NessunTelefono : StatoRigaCavo.NonDisponibile;
    }
}
