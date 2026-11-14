# Copione t12 (collaudo-20): Roberto vuole capire WebcamLR Pro prima di comprarlo. Cosa dice il PC senza telefono,
# con un iPhone gratis, con un iPhone Pro e con un Android gratis: menu «WebcamLR», finestra «WebcamLR Pro», funzioni
# Pro bloccate (sfondo «Sostituito», ritocco, foto, registrazione, profili, qualità). I risultati (testi e schermate
# JPEG ridotte) si stampano in base64 nel registro del lavoro: righe «T12FILE <nome>», base64, «T12FINE».

$cartella = Cartella-Risultati

function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}

function T12-Testo([string]$id) {
    $e = Trova-Elemento $id -AncheNascosti
    if ($e) { "«$($e.Current.Name)» attivo=$($e.Current.IsEnabled)" } else { "(«$id» non trovato)" }
}

function T12-Scegli([string]$combo, [string]$voce) {
    $c = Attendi-Elemento $combo 5 -AncheNascosti
    $ec = $null
    if ($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ec)) { $ec.Expand(); Start-Sleep -Milliseconds 700 }
    $tipo = [System.Windows.Automation.ControlType]::ListItem
    $voci = @(Tutti-Elementi | Where-Object { try { $_.Current.ControlType -eq $tipo } catch { $false } })
    Scrivi-Log "  voci di $combo`: $(($voci | ForEach-Object { '«' + $_.Current.Name + '»' + $(if (-not $_.Current.IsEnabled) { '(spenta)' } else { '' }) }) -join ' ')"
    Fotografa "scelta-$combo-aperta"
    $trovata = $voci | Where-Object { $_.Current.Name -eq $voce } | Select-Object -First 1
    if ($trovata) {
        $s = $null
        try { if ($trovata.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$s)) { $s.Select() } }
        catch { Scrivi-Log "  «$voce» non si sceglie: $($_.Exception.Message)" }
    } else { Scrivi-Log "  nella scelta $combo non c'è «$voce»" }
    Start-Sleep -Milliseconds 500
    if ($ec) { try { if ($ec.Current.ExpandCollapseState -ne 'Collapsed') { $ec.Collapse() } } catch { } }
    Start-Sleep -Milliseconds 500
    $valore = $null; $scelta = ''
    if ($c.TryGetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern, [ref]$valore)) {
        $scelta = ($valore.Current.GetSelection() | ForEach-Object { $_.Current.Name }) -join ','
    }
    Scrivi-Log "Scelta $combo`: «$voce» → selezionato adesso «$scelta»"
}

function T12-Menu([string]$nome) {
    Passo "Menu WebcamLR ($nome)" {
        Clicca 'PulsanteAccount'
        Start-Sleep -Seconds 1
        Fotografa "menu-$nome"
        Scrivi-Log "  piano: $(T12-Testo 'PianoAccount') · descrizione: $(T12-Testo 'DescrizioneProAccount') · pulsante: $(T12-Testo 'TestoProAccount')"
        Clicca 'PulsanteProAccount'
        Start-Sleep -Seconds 3
        Fotografa "finestra-pro-$nome"
        Scrivi-Log "  testi: $((Testi-Visibili) -join ' | ')"
        Albero-UI "finestra-pro-$nome-tutto" -Tutto | Out-Null
        Clicca 'Chiudi'
        Start-Sleep -Seconds 1
        if (-not (Finestra-App)) { Segnala-Problema "Dopo «Chiudi» della finestra Pro la finestra principale non c'è più"; Avvia-App | Out-Null }
        Porta-Davanti
    }
}

function T12-Funzioni([string]$nome) {
    Passo "Impostazioni › Effetti ($nome)" {
        Apri-Impostazioni
        Clicca (Testo-App 'Impostazioni_Effetti') -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Milliseconds 900
        Fotografa "effetti-$nome"
        T12-Scegli 'SceltaSfondo' 'Sostituito'
        Start-Sleep -Seconds 2
        Fotografa "effetti-sostituito-$nome"
        Scrivi-Log "  NotaSfondo $(T12-Testo 'NotaSfondo') · NotaSfondoPro $(T12-Testo 'NotaSfondoPro') · VoceSfondoSostituito $(T12-Testo 'VoceSfondoSostituito') · pelle $(T12-Testo 'CursorePelle') · inquadratura $(T12-Testo 'InterruttoreInquadratura') · volto e scrivania $(T12-Testo 'InterruttoreDoppiaVista') · scritta $(T12-Testo 'InterruttoreScritta')"
        Chiudi-Impostazioni
    }
    Passo "Impostazioni › Sfondo e Profili ($nome)" {
        foreach ($voce in 'Sfondo', 'Profili', 'Qualita', 'Gobbo') {
            Apri-Impostazioni
            Clicca (Testo-App "Impostazioni_$voce") -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Milliseconds 900
            Fotografa "impostazioni-$voce-$nome"
            Chiudi-Impostazioni
        }
    }
    Passo "Foto, registrazione e qualità ($nome)" {
        Scrivi-Log "  foto $(T12-Testo 'PulsanteFoto') · registra $(T12-Testo 'PulsanteRegistra') · gobbo $(T12-Testo 'PulsanteGobbo')"
        Clicca 'PulsanteFoto'
        Start-Sleep -Seconds 1
        Fotografa "clic-foto-$nome"
        Tasto 'Esc'
        Clicca 'PulsanteRegistra'
        Start-Sleep -Seconds 1
        Fotografa "clic-registra-$nome"
        Tasto 'Esc'
        Start-Sleep -Seconds 1
        Scrivi-Log "  registra dopo il clic: $(T12-Testo 'PulsanteRegistra')"
        if ($nome -match 'pro') { Clicca 'PulsanteRegistra'; Start-Sleep -Seconds 1; Fotografa "registra-fermata-$nome" }
        Clicca 'ChipQualita'
        Start-Sleep -Seconds 1
        Fotografa "qualita-$nome"
        Scrivi-Log "  qualità: $((Testi-Visibili | Where-Object { $_ -match 'PRO|fps|1080|720|4K|Sblocca|Auto' }) -join ' | ')"
        Tasto 'Esc'
    }
}

# ---------------------------------------------------------------- 1. senza telefono
Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
T12-Menu 'senza-telefono'

# ---------------------------------------------------------------- 2. iPhone gratis
$ok = Passo 'iPhone gratis dal QR' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone di Roberto' --durata 900 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Roberto' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Roberto' -Obbligatorio | Out-Null
} -Esito
if ($ok) {
    Start-Sleep -Seconds 5
    Fotografa 'iphone-gratis'
    T12-Menu 'iphone-gratis'
    T12-Funzioni 'iphone-gratis'
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3

# ---------------------------------------------------------------- 3. iPhone con Pro
$ok = Passo 'iPhone con Pro dal QR' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone Pro di Roberto' --pro --durata 900 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone Pro di Roberto' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'iPhone Pro di Roberto' -Obbligatorio | Out-Null
} -Esito
if ($ok) {
    Start-Sleep -Seconds 5
    Fotografa 'iphone-pro'
    T12-Menu 'iphone-pro'
    T12-Funzioni 'iphone-pro'
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3

# ---------------------------------------------------------------- 4. Android gratis
$ok = Passo 'Android gratis dal QR' {
    Avvia-TelefonoFinto -DalQR --nome 'Pixel di Roberto' --android --durata 600 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'Pixel di Roberto' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'Pixel di Roberto' -Obbligatorio | Out-Null
} -Esito
if ($ok) {
    Start-Sleep -Seconds 5
    T12-Menu 'android-gratis'
    Passo 'Effetti con Android gratis' {
        Apri-Impostazioni
        Clicca (Testo-App 'Impostazioni_Effetti') -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Milliseconds 900
        T12-Scegli 'SceltaSfondo' 'Sostituito'
        Fotografa 'effetti-android-gratis'
        Scrivi-Log "  NotaSfondoPro $(T12-Testo 'NotaSfondoPro')"
        Chiudi-Impostazioni
    }
}
Ferma-TelefonoFinto

# ---------------------------------------------------------------- tutto nel registro del lavoro
"PROBLEMI: $((Problemi) -join ' || ')" | Set-Content -LiteralPath (Join-Path $cartella 'problemi-t12.txt') -Encoding UTF8
Add-Type -AssemblyName System.Drawing
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
$parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 60L
foreach ($f in Get-ChildItem -LiteralPath $cartella -File | Sort-Object Name) {
    try {
        if ($f.Extension -eq '.png') {
            $img = [System.Drawing.Image]::FromFile($f.FullName)
            $l = [Math]::Min(1280, $img.Width); $a = [int]($img.Height * $l / $img.Width)
            $bmp = New-Object System.Drawing.Bitmap $l, $a
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($img, 0, 0, $l, $a)
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, $codec, $parametri)
            $byte = $ms.ToArray()
            $g.Dispose(); $bmp.Dispose(); $img.Dispose()
            $nome = [IO.Path]::ChangeExtension($f.Name, '.jpg')
        } elseif ($f.Extension -in '.txt', '.log') {
            if ($f.Name -match '^\d\d-' -and $f.Extension -eq '.txt' -and $f.Name -notmatch 'tutto|menu') { continue }
            $byte = [IO.File]::ReadAllBytes($f.FullName)
            if ($byte.Length -gt 2MB) { $byte = $byte[0..(2MB - 1)] }
            $nome = $f.Name
        } else { continue }
        Write-Host "T12FILE $nome"
        $b64 = [Convert]::ToBase64String($byte)
        for ($i = 0; $i -lt $b64.Length; $i += 4000) { Write-Host $b64.Substring($i, [Math]::Min(4000, $b64.Length - $i)) }
        Write-Host 'T12FINE'
    } catch { Write-Host "T12ERRORE $($f.Name): $($_.Exception.Message)" }
}
