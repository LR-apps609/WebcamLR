# Collaudo t14, seconda parte: Pro solo sull'Android entrato per primo, poi l'iPhone gratis messo nella webcam; con tutti
# e due collegati (e --riconnetti-sempre) cade quello nella webcam, muore di colpo l'altro, arriva un terzo telefono;
# un telefono tolto dai fidati torna e si consente. Alla fine stampa tutto nel registro del lavoro (t13/stampa.ps1: righe T13FILE/T13FINE).
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
    $script:Inizio[$Nome] = @(Righe-File $Nome).Count
    Avvia-TelefonoFinto -Opzioni $op | Out-Null
}
$script:Inizio = @{}
function Righe-File([string]$Nome) {
    $f = Join-Path (Cartella-Risultati) ("telefono-" + (($Nome -replace '[^\w\-]+', '-').Trim('-')) + '.log')
    if (Test-Path $f) { Get-Content -LiteralPath $f -Encoding UTF8 } else { @() }
}
function Esito-Telefono([string]$Nome, [int]$Secondi = 25) {
    <# Aspetta ACCETTATO / CODICE / RIFIUTATO e lo restituisce. #>
    $limite = (Get-Date).AddSeconds($Secondi)
    do {
        $righe = @(Righe-File $Nome | Select-Object -Skip ([int]$script:Inizio[$Nome]))
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
    $R = @('--riconnetti-sempre')

    Passo 'P1 Android Pro per primo, poi iPhone gratis' {
        Telefono $B -ConQR -Altre (@('--android', '--pro') + $R)
        Esito-Telefono $B | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $B | Out-Null
        Start-Sleep -Seconds 2
        Telefono $A -ConQR -Altre $R
        $e = Esito-Telefono $A
        Start-Sleep -Seconds 4
        Tasto 'Ctrl+2'; Start-Sleep -Seconds 2
        Guarda "p1-iphone-gratis-secondo-$e"
    }
    Passo 'P1b metto l iPhone gratis nella webcam' {
        Clicca 'PulsanteUsaProspettiva'
        Start-Sleep -Seconds 5
        Guarda 'p1b-iphone-gratis-nella-webcam'
        Start-Sleep -Seconds 10
        Guarda 'p1b-iphone-gratis-nella-webcam-15s'
        Ultime-Telefono $B 6
    }
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 3

    Passo 'P2 tutti e due Pro, cade la rete di quello nella webcam' {
        Telefono $A -Altre (@('--pro') + $R)
        Esito-Telefono $A | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $A | Out-Null
        Telefono $B -Altre (@('--android', '--pro') + $R)
        $e = Esito-Telefono $B
        Attendi-Telefono 'Video:' 20 -Nome $B | Out-Null
        Start-Sleep -Seconds 3
        Guarda "p2-due-collegati-$e"
        Rete-Spenta $A
        Start-Sleep -Seconds 6;  Guarda 'p2-webcam-muto-6s'
        Start-Sleep -Seconds 20; Guarda 'p2-webcam-muto-26s'
        Start-Sleep -Seconds 25; Guarda 'p2-webcam-muto-51s'
        Rete-Accesa $A
        Start-Sleep -Seconds 8;  Guarda 'p2-webcam-torna-8s'
        Start-Sleep -Seconds 10; Guarda 'p2-webcam-torna-18s'
        Ultime-Telefono $A 10
    }
    Passo 'P3 l altro (non nella webcam) muore di colpo' {
        Uccidi $B
        Start-Sleep -Seconds 4;  Guarda 'p3-altro-morto-4s'
        Start-Sleep -Seconds 30; Guarda 'p3-altro-morto-34s'
        Telefono $B -Altre (@('--android', '--pro') + $R)
        $e = Esito-Telefono $B
        Attendi-Telefono 'Video:' 20 -Nome $B | Out-Null
        Start-Sleep -Seconds 3
        Guarda "p3-altro-torna-$e"
    }
    Passo 'P4 quello nella webcam muore di colpo' {
        $chi = $A
        if ((Trova-Elemento 'TestoPillolaTelefono' -AncheNascosti).Current.Name -like "*$B*") { $chi = $B }
        Scrivi-Log "  nella webcam adesso: $chi"
        Uccidi $chi
        Start-Sleep -Seconds 4;  Guarda 'p4-webcam-morto-4s'
        Start-Sleep -Seconds 30; Guarda 'p4-webcam-morto-34s'
        Start-Sleep -Seconds 40; Guarda 'p4-webcam-morto-74s'
        $script:Morto = $chi
    }
    Passo 'P5 terzo telefono Pro con due collegati' {
        if ($script:Morto) { Telefono $script:Morto -Altre (@('--pro') + $R + $(if ($script:Morto -eq $B) { @('--android') } else { @() })); Esito-Telefono $script:Morto | Out-Null; Start-Sleep -Seconds 4 }
        Telefono 'Tablet di Nonna' -ConQR -Altre @('--android', '--pro', '--identita-nuova')
        $e = Esito-Telefono 'Tablet di Nonna'
        Start-Sleep -Seconds 3
        Guarda "p5-terzo-$e"
        Ultime-Telefono 'Tablet di Nonna' 6
        Ferma-TelefonoFinto 'Tablet di Nonna'
    }
    Ferma-TelefonoFinto
    Passo 'P6 iPhone tolto dai fidati torna: Non consentire, poi con identità nuova Consenti' {
        Apri-Telefoni
        Clicca "Rimuovi $A" -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'Rimuovi')
        Start-Sleep -Seconds 1
        Chiudi-Impostazioni
        Telefono $A -Altre @('--pro')
        $e = Esito-Telefono $A
        Start-Sleep -Seconds 2
        Guarda "p6-domanda-$e"
        if ($e -eq 'CODICE') {
            Clicca (Testo-App 'Conferma_Consenti')
            $e2 = Esito-Telefono $A 15
            Start-Sleep -Seconds 3
            Guarda "p6-dopo-consenti"
            Scrivi-Log "  dopo Consenti: $((Righe-File $A | Select-Object -Last 3) -join ' | ')"
        }
    }
    App-Viva | Out-Null
    Ferma-TelefonoFinto
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartella
}
