# Viste: Essenziale e Completo appena aperta l'app, senza passare dalle impostazioni, con e senza telefono.
# Controlla che in Completo le tre colonne (dispositivi, video con la barra, fotocamera ed effetti) siano raggiungibili
# con UI Automation, e che il video scorra in ogni vista.

function Controlla-Colonne([string]$Quando) {
    foreach ($id in 'PannelloSinistro', 'EtichettaTelefoni', 'PulsanteSchermo', 'VideoElaborato', 'ChipQualita', 'TitoloFotocamera', 'IntestazioneEffetti') {
        $e = Trova-Elemento $id -AncheNascosti
        if ($e) { Scrivi-Log "  ${Quando} · ${id}: c'è, fuori schermo $($e.Current.IsOffscreen), $(Descrivi-Rettangolo $e.Current.BoundingRectangle)" }
        else { Scrivi-Log "  ${Quando} · ${id}: non c'è" }
    }
}

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 3
Fotografa 'essenziale-senza-telefono'
Controlla-Colonne 'Essenziale senza telefono'

Passo 'Completo senza telefono' {
    Tasto 'Ctrl+2'
    Start-Sleep -Seconds 2
    Fotografa 'completo-senza-telefono'
    Controlla-Colonne 'Completo senza telefono'
    if (-not (Esiste 'PulsanteSchermo')) { Segnala-Problema "Vista Completo appena aperta: la barra sotto il video (PulsanteSchermo) non è raggiungibile con UI Automation" }
    if (-not (Esiste 'TitoloFotocamera')) { Segnala-Problema "Vista Completo appena aperta: la colonna di destra (TitoloFotocamera) non è raggiungibile con UI Automation" }
}

$collegato = Passo 'Telefono finto' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone delle viste' --durata 200 | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone delle viste' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'iPhone delle viste' -Obbligatorio | Out-Null
    Start-Sleep -Seconds 5
} -Esito

if ($collegato) {
    Passo 'Completo con il telefono' {
        Fotografa 'completo-con-telefono'
        Controlla-Colonne 'Completo con telefono'
        Controlla-Video -Obbligatorio | Out-Null
    }
    Passo 'Essenziale con il telefono' {
        Tasto 'Ctrl+1'
        Start-Sleep -Seconds 2
        Fotografa 'essenziale-con-telefono'
        Controlla-Colonne 'Essenziale con telefono'
        Controlla-Video -Obbligatorio | Out-Null
    }
    Passo 'Completo in una finestra di 1280×800' {
        Tasto 'Ctrl+2'
        Ridimensiona-Finestra 1280 800 100 100
        Start-Sleep -Seconds 2
        Fotografa 'completo-1280x800'
        Controlla-Colonne 'Completo 1280×800'
    }
}
