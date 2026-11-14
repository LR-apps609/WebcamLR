# Collaudo t14 (famiglia con un iPhone e un Android sullo stesso PC): due telefoni finti insieme, con e senza Pro.
# Chi entra, cosa dice il PC al secondo telefono, scambio nella webcam, uno che cade mentre l'altro è nella webcam,
# telefoni fidati rimossi. Alla fine stampa tutto nel registro del lavoro (t13/stampa.ps1: righe T13FILE/T13FINE).
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartella = Cartella-Risultati
$A = 'iPhone di Mamma'
$B = 'Pixel di Luca'

function QR-Ora {
    <# Il QR a schermo, anche con un telefono collegato: colonna di sinistra in Completo, o il menu della pillola. #>
    try { return (Leggi-QR) } catch { }
    Tasto 'Ctrl+2'; Start-Sleep -Seconds 2
    try { return (Leggi-QR) } catch { }
    if (Trova-Elemento 'PillolaTelefono') {
        Clicca 'PillolaTelefono'; Start-Sleep -Seconds 1
        try { $f = Leggi-QR; Tasto 'Esc'; return $f } catch { Tasto 'Esc' }
    }
    Scrivi-Log "QR-Ora: nessun QR a schermo. Visibili: $(Elenco-Visibili)"
    $null
}
function Telefono([string]$Nome, [switch]$ConQR, [string[]]$Altre) {
    $op = @('--nome', $Nome, '--durata', '900')
    if ($Altre) { $op += $Altre }
    if ($ConQR) { $qr = QR-Ora; if ($qr) { $op += @('--qr', $qr) } else { Scrivi-Log "  $Nome parte SENZA QR" } }
    $script:Inizio[$Nome] = @(Registro-Telefono $Nome).Count
    Avvia-TelefonoFinto -Opzioni $op | Out-Null
}
$script:Inizio = @{}
function Esito-Telefono([string]$Nome, [int]$Secondi = 25) {
    <# Aspetta ACCETTATO / CODICE / RIFIUTATO e lo restituisce. #>
    $limite = (Get-Date).AddSeconds($Secondi)
    do {
        $righe = @(Registro-Telefono $Nome | Select-Object -Skip ([int]$script:Inizio[$Nome]))
        foreach ($chiave in 'RIFIUTATO', 'ACCETTATO', 'CODICE', 'Connessione chiusa', 'ERRORE') {
            if ($righe | Where-Object { $_ -like "*$chiave*" }) { Scrivi-Log "ESITO «$Nome»: $chiave"; return $chiave }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $limite)
    Scrivi-Log "ESITO «$Nome»: niente in $Secondi s"; 'NIENTE'
}
function Uccidi([string]$Nome) {
    <# Chiude il processo del telefono di colpo (niente arrivederci): come una batteria che muore. #>
    & (Get-Module Collaudo) { param($n) $t = $script:Telefoni[$n]; if ($t -and -not $t.Processo.HasExited) { $t.Processo.Kill() }; $script:Telefoni.Remove($n) } $Nome
    Scrivi-Log "UCCISO il telefono «$Nome» (senza arrivederci)"
}
function Guarda([string]$Nome) {
    Fotografa $Nome
    Scrivi-Log "A schermo [$Nome]: $(Elenco-Visibili)"
    foreach ($id in 'BarraTelefoni', 'BarraTelefonoPerso', 'BarraAvvisoTelefono', 'TestoPillolaTelefono', 'TestoTelefoniNoti') {
        $e = Trova-Elemento $id -AncheNascosti
        if ($e) { try { Scrivi-Log "  ${id}: «$($e.Current.Name)» nascosto=$($e.Current.IsOffscreen)" } catch { } }
    }
}
function Apri-Telefoni {
    Tasto 'Ctrl+,'; Start-Sleep -Milliseconds 900
    Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
}
function Chiudi-Impostazioni { if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' } else { Tasto 'Esc' } }

try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 3

    # ------------------------------------------------ 1. senza Pro: iPhone nella webcam, poi arriva l'Android
    Passo '1a iPhone (gratis) dal QR' {
        Telefono $A -ConQR
        Esito-Telefono $A | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $A | Out-Null
        Start-Sleep -Seconds 3
        Guarda 'f1-iphone-solo'
    }
    Passo '1b Android (gratis) dal QR mentre l iPhone è nella webcam' {
        Telefono $B -ConQR -Altre @('--android')
        $e = Esito-Telefono $B
        Start-Sleep -Seconds 3
        Guarda "f1-android-secondo-$e"
        Tasto 'Ctrl+2'; Start-Sleep -Seconds 2
        Guarda 'f1-android-secondo-completo'
        Ultime-Telefono $B 10
    }
    Ferma-TelefonoFinto $B
    Passo '1c Android nuovo senza QR (codice) mentre l iPhone gratis è nella webcam' {
        Telefono 'Tablet di Nonna' -Altre @('--android', '--identita-nuova')
        $e = Esito-Telefono 'Tablet di Nonna'
        Start-Sleep -Seconds 2
        Guarda "f1-tablet-codice-$e"
        if ($e -eq 'CODICE') {
            Clicca (Testo-App 'Conferma_Consenti')
            $e2 = Esito-Telefono 'Tablet di Nonna' 15
            Start-Sleep -Seconds 3
            Guarda 'f1-tablet-dopo-consenti'
            Ultime-Telefono 'Tablet di Nonna' 8
        }
    }
    Ferma-TelefonoFinto

    # ------------------------------------------------ 2. Pro misto
    Passo '2a iPhone gratis nella webcam, Android Pro' {
        Start-Sleep -Seconds 3
        Telefono $A
        Esito-Telefono $A | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $A | Out-Null
        Telefono $B -ConQR -Altre @('--android', '--pro')
        $e = Esito-Telefono $B
        Start-Sleep -Seconds 3
        Guarda "f2a-android-pro-$e"
        Ultime-Telefono $B 6
    }
    Ferma-TelefonoFinto
    Passo '2b iPhone Pro nella webcam, Android gratis' {
        Start-Sleep -Seconds 3
        Telefono $A -Altre @('--pro')
        $ea = Esito-Telefono $A
        if ($ea -ne 'ACCETTATO') { Scrivi-Log "  l'iPhone (fidato) non entra da solo: $ea" }
        Attendi-Telefono 'Video:' 20 -Nome $A | Out-Null
        Telefono $B -ConQR -Altre @('--android')
        $e = Esito-Telefono $B
        Start-Sleep -Seconds 3
        Guarda "f2b-android-gratis-$e"
        Ultime-Telefono $B 6
    }
    Ferma-TelefonoFinto

    # ------------------------------------------------ 3. tutti e due Pro: scambio e cadute
    Passo '3a tutti e due Pro' {
        Start-Sleep -Seconds 3
        Telefono $A -Altre @('--pro')
        Esito-Telefono $A | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $A | Out-Null
        Telefono $B -ConQR -Altre @('--android', '--pro')
        $e = Esito-Telefono $B
        Attendi-Telefono 'Video:' 20 -Nome $B | Out-Null
        Start-Sleep -Seconds 4
        Tasto 'Ctrl+1'; Start-Sleep -Seconds 2
        Guarda "f3-due-pro-essenziale-$e"
        Tasto 'Ctrl+2'; Start-Sleep -Seconds 2
        Guarda 'f3-due-pro-completo'
        if (Trova-Elemento 'PillolaTelefono') { Clicca 'PillolaTelefono'; Start-Sleep -Seconds 1; Guarda 'f3-pillola'; Tasto 'Esc' }
    }
    Passo '3b scambio: Android nella webcam (scheda Telefoni)' {
        $prima = @(Registro-Telefono $B).Count
        try { Clicca (Testo-App 'Telefoni_NellaWebcam') -Dentro $B }
        catch { Scrivi-Log "  radio dentro la scheda non trovato: $($_.Exception.Message)"; Clicca 'PulsanteUsaProspettiva' }
        Start-Sleep -Seconds 3
        Guarda 'f3-scambio-android'
        Ultime-Telefono $A 5; Ultime-Telefono $B 5
    }
    Passo '3c scambio di ritorno con «Usa questa prospettiva»' {
        if (Trova-Elemento 'PulsanteUsaProspettiva') { Clicca 'PulsanteUsaProspettiva' } else { Scrivi-Log '  PulsanteUsaProspettiva non a schermo'; Clicca (Testo-App 'Telefoni_NellaWebcam') -Dentro $A }
        Start-Sleep -Seconds 3
        Guarda 'f3-scambio-iphone'
    }
    Passo '3d cade la rete dell Android (non nella webcam)' {
        Rete-Spenta $B
        Start-Sleep -Seconds 6;  Guarda 'f3d-android-muto-6s'
        Start-Sleep -Seconds 20; Guarda 'f3d-android-muto-26s'
        Rete-Accesa $B
        Start-Sleep -Seconds 8;  Guarda 'f3d-android-torna'
        Ultime-Telefono $B 6
    }
    Passo '3e cade la rete dell iPhone NELLA webcam' {
        Rete-Spenta $A
        Start-Sleep -Seconds 6;  Guarda 'f3e-iphone-muto-6s'
        Start-Sleep -Seconds 20; Guarda 'f3e-iphone-muto-26s'
        Start-Sleep -Seconds 25; Guarda 'f3e-iphone-muto-51s'
        Rete-Accesa $A
        Start-Sleep -Seconds 10; Guarda 'f3e-iphone-torna'
        Ultime-Telefono $A 8
    }
    Passo '3f l Android muore di colpo mentre l iPhone è nella webcam' {
        Uccidi $B
        Start-Sleep -Seconds 4;  Guarda 'f3f-android-morto-4s'
        Start-Sleep -Seconds 20; Guarda 'f3f-android-morto-24s'
    }
    Passo '3g torna l Android e l iPhone nella webcam muore di colpo' {
        Telefono $B -Altre @('--android', '--pro')
        $e = Esito-Telefono $B
        Attendi-Telefono 'Video:' 20 -Nome $B | Out-Null
        Start-Sleep -Seconds 3
        Guarda "f3g-android-torna-$e"
        Uccidi $A
        Start-Sleep -Seconds 4;  Guarda 'f3g-iphone-morto-4s'
        Start-Sleep -Seconds 30; Guarda 'f3g-iphone-morto-34s'
        Ultime-Telefono $B 6
    }
    App-Viva | Out-Null

    # ------------------------------------------------ 4. telefoni fidati rimossi
    Passo '4a Impostazioni › Telefoni con l Android collegato' {
        Apri-Telefoni
        Guarda 'f4-telefoni-fidati'
    }
    Passo '4b rimuovo l Android mentre è collegato' {
        Clicca "Rimuovi $B" -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Seconds 1
        Guarda 'f4-domanda-rimuovi'
        Clicca (Testo-App 'Rimuovi')
        Start-Sleep -Seconds 3
        Guarda 'f4-dopo-rimuovi-android'
        Ultime-Telefono $B 6
    }
    Passo '4c rimuovo l iPhone (non collegato)' {
        if (-not (Trova-Elemento "Rimuovi $A" -Dentro 'ScorrimentoImpostazioni')) { Apri-Telefoni }
        Clicca "Rimuovi $A" -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'Rimuovi')
        Start-Sleep -Seconds 2
        Guarda 'f4-dopo-rimuovi-iphone'
        Chiudi-Impostazioni
    }
    Passo '4d l Android rimosso si ricollega (scollego e riparto)' {
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 3
        Telefono $B -Altre @('--android', '--pro')
        $e = Esito-Telefono $B
        Start-Sleep -Seconds 2
        Guarda "f4-android-rimosso-riparte-$e"
        if ($e -eq 'CODICE') { Clicca (Testo-App 'Conferma_Consenti'); Esito-Telefono $B 15 | Out-Null }
        Telefono $A -Altre @('--pro')
        $e = Esito-Telefono $A
        Start-Sleep -Seconds 2
        Guarda "f4-iphone-rimosso-riparte-$e"
        if ($e -eq 'CODICE') { Clicca (Testo-App 'Conferma_Consenti'); Esito-Telefono $A 15 | Out-Null }
        Start-Sleep -Seconds 3
        Guarda 'f4-fine'
    }
    App-Viva | Out-Null
    Ferma-TelefonoFinto
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartella
}
