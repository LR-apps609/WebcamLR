# Correzioni del collaudo 20 (t06 B5): quale pagina di Impostazioni fa sparire la vista Completo da UI Automation.
# Per ogni pagina: app riaperta, Completo (Ctrl+2), controllo, la pagina aperta e chiusa, di nuovo il controllo.

function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}
function Controlla([string]$Quando) {
    $mancano = @('PulsanteSchermo', 'TitoloFotocamera', 'IntestazioneEffetti', 'EtichettaTelefoni', 'ChipQualita') |
        Where-Object { -not (Trova-Elemento $_ -AncheNascosti) }
    Scrivi-Log "  CONTROLLO ${Quando}: $(if ($mancano) { 'mancano ' + ($mancano -join ', ') } else { 'tutto' })"
    return $mancano.Count
}

Avvia-App -Azzera | Out-Null
Chiudi-App
# Con un telefono collegato (dal QR, poi fidato): il chip e il video ci sono.
Avvia-App | Out-Null
Avvia-TelefonoFinto -DalQR --nome 'iPhone delle pagine' --durata 900 --riconnetti-sempre | Out-Null
Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone delle pagine' | Out-Null
Chiudi-App
$voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Gobbo', 'Avvio', 'Registro', 'Uscite'
foreach ($voce in $voci) {
    Passo "Pagina $voce" {
        Avvia-App | Out-Null
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        [void](Controlla "$voce prima")
        Apri-Impostazioni
        Clicca (Testo-App "Impostazioni_$voce") -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Milliseconds 800
        Chiudi-Impostazioni
        Start-Sleep -Seconds 1
        if ((Controlla "$voce dopo") -gt 0) {
            Segnala-Problema "Dopo Impostazioni › $voce la vista Completo non è tutta raggiungibile con UI Automation"
            Albero-UI "dopo-$voce" | Out-Null
        }
        Chiudi-App
    }
}
