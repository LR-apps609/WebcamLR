# Copione t18 «giornata lunga» (Windows): Andrea, formatore, ore in onda. Telefono finto dal QR, ~26 minuti:
# misure di memoria, CPU, handle, thread e oggetti GDI/USER di WebcamLR ogni 30 s (misure.csv); due lunghi silenzi del
# telefono (3 e 5 minuti: telefono che si sospende o Wi-Fi che sparisce); infine un telefono scarico e caldo.
# Gli artifact non si scaricano: alla fine schermate (JPEG piccoli), misure e registri in base64 nel registro del lavoro.

Add-Type -Namespace T18 -Name Gui -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetGuiResources(System.IntPtr h, uint f);'
$script:T18Inizio = Get-Date
$script:T18Prec = $null
$script:T18Misure = Join-Path (Cartella-Risultati) 'misure.csv'
Set-Content -LiteralPath $script:T18Misure -Value 't_s,ora,ws_mb,privata_mb,cpu_pct,handle,thread,gdi,user,telefono_ws_mb,stato,pillola,video' -Encoding UTF8
$n = 'iPhone di Andrea'

function T18-Testo([string]$Id) { $e = Trova-Elemento $Id; if ($e) { try { $e.Current.Name } catch { '' } } else { '' } }

function T18-Misura([switch]$ConVideo) {
    $p = Get-Process -Name WebcamLR -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { Add-Content -LiteralPath $script:T18Misure -Value ("{0:0},{1},,,,,,,,,app chiusa,," -f ((Get-Date) - $script:T18Inizio).TotalSeconds, (Get-Date -Format HH:mm:ss)); return }
    $ora = Get-Date
    $cpu = ''
    if ($script:T18Prec) {
        $s = ($ora - $script:T18Prec.Ora).TotalSeconds
        if ($s -gt 0) { $cpu = '{0:0.0}' -f (100.0 * ($p.TotalProcessorTime - $script:T18Prec.Cpu).TotalSeconds / $s / [Environment]::ProcessorCount) }
    }
    $script:T18Prec = @{ Ora = $ora; Cpu = $p.TotalProcessorTime }
    $gdi = [T18.Gui]::GetGuiResources($p.Handle, 0); $user = [T18.Gui]::GetGuiResources($p.Handle, 1)
    $tel = Get-Process -Name TelefonoFinto -ErrorAction SilentlyContinue | Select-Object -First 1
    $telMb = if ($tel) { '{0:0}' -f ($tel.WorkingSet64 / 1MB) } else { '' }
    $video = ''
    if ($ConVideo) { $video = if (Controlla-Video -Secondi 1) { 'scorre' } else { 'fermo' } }
    $stato = (T18-Testo 'TestoStato') -replace ',', ';'
    $pillola = (T18-Testo 'TestoPillolaTelefono') -replace ',', ';'
    Add-Content -LiteralPath $script:T18Misure -Value ("{0:0},{1},{2:0.0},{3:0.0},{4},{5},{6},{7},{8},{9},{10},{11},{12}" -f `
        ($ora - $script:T18Inizio).TotalSeconds, ($ora.ToString('HH:mm:ss')), ($p.WorkingSet64 / 1MB), ($p.PrivateMemorySize64 / 1MB),
        $cpu, $p.HandleCount, $p.Threads.Count, $gdi, $user, $telMb, $stato, $pillola, $video)
}

function T18-Guarda([string]$Nome) {
    Fotografa $Nome
    Scrivi-Log "TESTI ${Nome}: $((@(Testi-Visibili) | Select-Object -Unique) -join ' | ')"
}

# T18-Fino <s>: aspetta fino a <s> secondi dall'inizio, misurando ogni 30 s (con il controllo del video ogni 60 s).
function T18-Fino([int]$Secondi) {
    $k = 0
    while (((Get-Date) - $script:T18Inizio).TotalSeconds -lt $Secondi) {
        $k++
        T18-Misura -ConVideo:($k % 2 -eq 1)
        $resta = $Secondi - ((Get-Date) - $script:T18Inizio).TotalSeconds
        if ($resta -gt 0) { Start-Sleep -Seconds ([Math]::Min(30, [Math]::Ceiling($resta))) }
    }
    Scrivi-Log ("--- minuto {0:0.0}" -f (((Get-Date) - $script:T18Inizio).TotalMinutes))
}

function T18-Accettati { @(Registro-Telefono $n | Where-Object { $_ -like '*ACCETTATO*' }).Count }

function T18-Ritorno([int]$Prima, [int]$Massimo, [string]$Etichetta) {
    $inizio = Get-Date
    while (((Get-Date) - $inizio).TotalSeconds -lt $Massimo) {
        $nuovo = (T18-Accettati) -gt $Prima
        if (Controlla-Video -Secondi 1) {
            Scrivi-Log ("RITORNO ${Etichetta}: video di nuovo in {0:0.0} s (nuovo collegamento: {1})" -f ((Get-Date) - $inizio).TotalSeconds, $nuovo)
            return
        }
        Start-Sleep -Milliseconds 700
    }
    Segnala-Problema "${Etichetta}: il video non torna in $Massimo s"
    T18-Guarda "$Etichetta-senza-ritorno"
}

# Il silenzio del telefono: processo sospeso <Secondi> secondi, fotografie ai secondi indicati.
function T18-Silenzio([string]$Etichetta, [int]$Secondi, [int[]]$Foto) {
    $prima = T18-Accettati
    Rete-Spenta
    $inizio = Get-Date
    foreach ($f in $Foto) {
        while (((Get-Date) - $inizio).TotalSeconds -lt $f) { Start-Sleep -Seconds 5; if ((((Get-Date) - $inizio).TotalSeconds % 30) -lt 5) { T18-Misura } }
        T18-Guarda "$Etichetta-${f}s"
    }
    while (((Get-Date) - $inizio).TotalSeconds -lt $Secondi) { Start-Sleep -Seconds 5 }
    Rete-Accesa
    Scrivi-Log "${Etichetta}: telefono di nuovo attivo dopo $Secondi s"
    T18-Ritorno $prima 120 $Etichetta
    Start-Sleep -Seconds 3
    T18-Guarda "$Etichetta-dopo"
    $righe = @(Registro-Telefono $n | Select-Object -Last 8) -join ' // '
    Scrivi-Log "TELEFONO dopo ${Etichetta}: $righe"
}

function T18-Stampa {
    Add-Type -AssemblyName System.Drawing
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
    $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 55L
    foreach ($f in Get-ChildItem -LiteralPath (Cartella-Risultati) -Filter *.png | Sort-Object Name) {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        $piccola = New-Object System.Drawing.Bitmap $img, 960, ([int](960 * $img.Height / $img.Width))
        $flusso = New-Object System.IO.MemoryStream
        $piccola.Save($flusso, $codec, $parametri)
        $img.Dispose(); $piccola.Dispose()
        Write-Host "=====T18-IMG $($f.BaseName)====="
        Write-Host ([Convert]::ToBase64String($flusso.ToArray()))
        Write-Host "=====T18-FINE====="
    }
    $testi = @(Get-ChildItem -LiteralPath (Cartella-Risultati) -Filter 'telefono-*.log') + @(Get-Item -LiteralPath $script:T18Misure) + @(Get-Item -LiteralPath (Join-Path (Cartella-Risultati) 'passi.log') -ErrorAction SilentlyContinue)
    $errori = Join-Path $env:LOCALAPPDATA 'WebcamLR\Errori.txt'
    if (Test-Path $errori) { $testi += @(Get-Item -LiteralPath $errori) }
    foreach ($f in $testi | Where-Object { $_ }) {
        Write-Host "=====T18-TXT $($f.Name)====="
        Get-Content -LiteralPath $f.FullName -Encoding UTF8 | ForEach-Object { Write-Host "T18| $_" }
        Write-Host "=====T18-FINE====="
    }
}

try {
    Avvia-App -Azzera
    Start-Sleep -Seconds 3
    Passo 'Telefono dal QR' {
        Avvia-TelefonoFinto -DalQR --nome $n --durata 2400 --riconnetti-sempre --batteria 60 | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome $n -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 30 -Nome $n -Obbligatorio | Out-Null
        Start-Sleep -Seconds 5
        T18-Guarda 'in-onda'
    }
    $script:T18Inizio = Get-Date
    T18-Fino 60;  T18-Guarda 'minuto-1'
    T18-Fino 300; T18-Guarda 'minuto-5'
    T18-Fino 540; T18-Guarda 'minuto-9'
    Passo 'Silenzio del telefono 3 minuti' { T18-Silenzio 'silenzio-3min' 180 @(10, 30, 90, 175) }
    T18-Fino 900;  T18-Guarda 'minuto-15'
    T18-Fino 1080; T18-Guarda 'minuto-18'
    Passo 'Silenzio del telefono 5 minuti' { T18-Silenzio 'silenzio-5min' 300 @(20, 120, 295) }
    T18-Fino 1500; T18-Guarda 'minuto-25'
    Passo 'Telefono scarico e caldo' {
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 4
        T18-Guarda 'telefono-fermato'
        Avvia-TelefonoFinto --nome $n --durata 300 --batteria 7 --temperatura molto-calda | Out-Null
        Attendi-Telefono 'Video:' 40 -Nome $n | Out-Null
        Start-Sleep -Seconds 10
        T18-Guarda 'scarico-caldo'
        try { Clicca 'PillolaTelefono' } catch { Scrivi-Log "PillolaTelefono non cliccabile: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
        T18-Guarda 'scarico-caldo-pillola'
        Tasto 'Esc'
        T18-Fino 1620
    }
    T18-Misura -ConVideo
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 5
    T18-Misura
    T18-Guarda 'fine'
} finally {
    try { T18-Stampa } catch { Write-Host "T18-Stampa: $($_.Exception.Message)" }
}
