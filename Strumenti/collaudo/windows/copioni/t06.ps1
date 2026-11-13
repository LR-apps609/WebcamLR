# Copione t06 (collaudo-20): Sara, insegnante, PC economico senza scheda video, telefono Android, ore di lezione.
# Effetti (sfocatura, sfondi, ritocco) senza GPU, qualità Auto, il PC che fatica (processore occupato apposta), cosa dice
# l'app quando scende di livello, pausa automatica, sessione lunga (10 minuti) con CPU e memoria campionate ogni 5 s,
# Impostazioni › Effetti, Qualità, Uscite (e il sospetto «elementi che spariscono» dopo Uscite).
# Alla fine i risultati (schermate in JPEG ridotte, registri, campioni) si stampano in base64 nel registro del lavoro,
# fra =====COLLAUDO-INIZIO===== e =====COLLAUDO-FINE===== (gli artifact non sono raggiungibili dal proxy).

$cartella = Cartella-Risultati
$campioni = Join-Path $cartella 'campioni-cpu-memoria.csv'
$nomeTelefono = 'Android di Sara'

# ---------------------------------------------------------------- aiuti di questo copione
function T06-Testo([string]$id) {
    $e = Trova-Elemento $id -AncheNascosti
    if ($e) { $e.Current.Name } else { "(«$id» non trovato)" }
}

function T06-Cursore([string]$id, [double]$valore) {
    $e = Attendi-Elemento $id 5 -AncheNascosti
    $p = $null
    if (-not $e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$p)) { throw "«$id» non è un cursore" }
    $prima = $p.Current.Value
    try { $p.SetValue($valore) } catch { throw "«$id»: valore $valore non accettato ($($_.Exception.Message)); attivo: $($e.Current.IsEnabled)" }
    Start-Sleep -Milliseconds 600
    Scrivi-Log "Cursore $id`: $prima → $($p.Current.Value) (chiesto $valore, attivo $($e.Current.IsEnabled))"
    $p.Current.Value
}

function T06-Scegli([string]$combo, [string]$voce) {
    $c = Attendi-Elemento $combo 5 -AncheNascosti
    $ec = $null
    if ($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ec)) { $ec.Expand(); Start-Sleep -Milliseconds 700 }
    $tipo = [System.Windows.Automation.ControlType]::ListItem
    $voci = @(Tutti-Elementi | Where-Object { try { $_.Current.ControlType -eq $tipo } catch { $false } })
    Scrivi-Log "  voci di $combo`: $(($voci | ForEach-Object { '«' + $_.Current.Name + '»' + $(if (-not $_.Current.IsEnabled) { '(spenta)' } else { '' }) }) -join ' ')"
    $trovata = $voci | Where-Object { $_.Current.Name -eq $voce } | Select-Object -First 1
    if (-not $trovata) { Tasto 'Esc'; throw "Nella scelta $combo non c'è «$voce»" }
    $s = $null
    if ($trovata.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$s)) { $s.Select() }
    Start-Sleep -Milliseconds 500
    if ($ec -and $ec.Current.ExpandCollapseState -ne 'Collapsed') { try { $ec.Collapse() } catch { } }
    Start-Sleep -Milliseconds 500
    $valore = $null
    $scelta = ''
    if ($c.TryGetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern, [ref]$valore)) {
        $scelta = ($valore.Current.GetSelection() | ForEach-Object { $_.Current.Name }) -join ','
    }
    Scrivi-Log "Scelta $combo`: «$voce» → selezionato adesso «$scelta»"
}

function T06-Registro([string]$titolo) {
    # Il registro del collegamento (colonna di sinistra, vista Completo): le righe arrivano nel nostro registro.
    try {
        Clicca 'PulsanteRegistro' -AncheNascosti
        Start-Sleep -Milliseconds 800
        Set-Clipboard -Value ' '
        Clicca 'PulsanteCopiaRegistro'
        Start-Sleep -Milliseconds 500
        $testo = (Get-Clipboard -Raw)
        Tasto 'Esc'
    } catch { $testo = "(registro non aperto: $($_.Exception.Message))" }
    Scrivi-Log "REGISTRO DELL'APP ($titolo):"
    foreach ($riga in ($testo -split "`n")) { if ($riga.Trim()) { Scrivi-Log "    | $riga" } }
    $testo
}

function T06-Numeri([string]$titolo, [switch]$Foto) {
    $tempo = Measure-Command {
        try {
            Clicca 'ChipQualita'
            Start-Sleep -Milliseconds 700
            if ($Foto) { Fotografa $titolo }
            $script:ultimiNumeri = T06-Testo 'TestoNumeri'
            Tasto 'Esc'
        } catch { $script:ultimiNumeri = "(numeri non letti: $($_.Exception.Message))" }
    }
    Scrivi-Log "NUMERI ($titolo, menu aperto e letto in $([int]$tempo.TotalMilliseconds) ms):"
    foreach ($riga in ($script:ultimiNumeri -split "`n")) { if ($riga.Trim()) { Scrivi-Log "    | $riga" } }
}

function T06-Reattivita([string]$titolo) {
    # Quanto ci mette l'interfaccia a rispondere a UI Automation (un'interfaccia bloccata non risponde).
    $t = Measure-Command { [void](Trova-Elemento 'PulsanteImpostazioni') }
    Scrivi-Log "REATTIVITÀ ($titolo): ricerca di un pulsante in $([int]$t.TotalMilliseconds) ms"
}

function T06-Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function T06-Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}
function T06-Scorri([double]$percento) {
    $e = Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti
    $p = $null
    if ($e -and $e.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$p) -and $p.Current.VerticallyScrollable) {
        $p.SetScrollPercent(-1, $percento)
        Start-Sleep -Milliseconds 500
        return $true
    }
    $false
}

# ---------------------------------------------------------------- la macchina
Passo 'La macchina di Sara (qui: il runner)' {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    Scrivi-Log "Processore: $($cpu.Name), $([Environment]::ProcessorCount) processori logici; memoria $([int]($mem / 1MB)) MB"
    foreach ($v in Get-CimInstance Win32_VideoController) { Scrivi-Log "Scheda video: $($v.Name) · driver $($v.DriverVersion) · $($v.AdapterRAM)" }
}

# ---------------------------------------------------------------- campionatore di CPU e memoria
$campionatore = Start-Job -ArgumentList $campioni -ScriptBlock {
    param($csv)
    $n = [Environment]::ProcessorCount
    'ora,secondi,app_cpu_pct,app_ws_mb,app_privati_mb,app_handle,app_thread,telefono_cpu_pct,telefono_ws_mb,cpu_totale_pct,memoria_libera_mb' | Set-Content -LiteralPath $csv -Encoding UTF8
    $prima = @{}
    $t0 = Get-Date
    $tPrima = $t0
    while ($true) {
        $ora = Get-Date
        $dt = ($ora - $tPrima).TotalSeconds
        $valori = @{}
        foreach ($nome in 'WebcamLR', 'TelefonoFinto') {
            $proc = @(Get-Process -Name $nome -ErrorAction SilentlyContinue)
            $cpuS = 0.0; $ws = 0; $priv = 0; $h = 0; $th = 0
            foreach ($p in $proc) {
                try { $cpuS += $p.TotalProcessorTime.TotalSeconds; $ws += $p.WorkingSet64; $priv += $p.PrivateMemorySize64; $h += $p.HandleCount; $th += $p.Threads.Count } catch { }
            }
            $pct = 0
            if ($prima.ContainsKey($nome) -and $dt -gt 0 -and $cpuS -ge $prima[$nome]) { $pct = [Math]::Round(100 * ($cpuS - $prima[$nome]) / ($dt * $n), 1) }
            $prima[$nome] = $cpuS
            $valori[$nome] = @($pct, [int]($ws / 1MB), [int]($priv / 1MB), $h, $th)
        }
        $tot = ''
        $libera = ''
        try { $tot = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime } catch { }
        try { $libera = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024) } catch { }
        $a = $valori['WebcamLR']; $t = $valori['TelefonoFinto']
        ('{0:HH:mm:ss},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}' -f $ora, [int]($ora - $t0).TotalSeconds, $a[0], $a[1], $a[2], $a[3], $a[4], $t[0], $t[1], $tot, $libera) |
            Add-Content -LiteralPath $csv -Encoding UTF8
        $tPrima = $ora
        Start-Sleep -Seconds 5
    }
}
Scrivi-Log "Campionatore avviato (lavoro $($campionatore.Id)): $campioni"

function T06-Segna([string]$fase) {
    Add-Content -LiteralPath (Join-Path $cartella 'fasi.txt') -Value ('{0:HH:mm:ss} {1}' -f (Get-Date), $fase) -Encoding UTF8
    Scrivi-Log "FASE: $fase"
}

try {
    # ---------------------------------------------------------------- primo avvio e telefono
    T06-Segna 'avvio'
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 4
    Fotografa 'primo-avvio'

    $collegato = Passo 'Telefono Android dal QR code' {
        Avvia-TelefonoFinto -DalQR --nome $nomeTelefono --android --durata 0 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome $nomeTelefono -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $nomeTelefono -Obbligatorio | Out-Null
    } -Esito
    if (-not $collegato) {
        Ferma-TelefonoFinto
        $collegato = Passo 'Telefono Android con la conferma sul PC' {
            Avvia-TelefonoFinto --nome $nomeTelefono --android --durata 0 --riconnetti-sempre | Out-Null
            Attendi-Telefono 'CODICE' 30 -Nome $nomeTelefono -Obbligatorio | Out-Null
            Attendi-Testo (Testo-App 'Conferma_Consenti') 15 -Obbligatorio | Out-Null
            Clicca (Testo-App 'Conferma_Consenti')
            Attendi-Telefono 'ACCETTATO' 20 -Nome $nomeTelefono -Obbligatorio | Out-Null
        } -Esito
    }
    if (-not $collegato) { throw 'Il telefono non si collega: il resto del copione non ha senso' }

    Start-Sleep -Seconds 6
    Fotografa 'video-senza-effetti'
    # Giro 2: lo sfondo si accende solo con la fotocamera frontale (giro 1: con la posteriore tutto grigio).
    Tasto 'Ctrl+2'
    Start-Sleep -Seconds 2
    Passo 'Passo alla fotocamera frontale' {
        Clicca 'Frontale' -Dentro 'SceltaObiettivo'
        Attendi-Telefono 'obiettivo frontale' 10 -Nome $nomeTelefono | Out-Null
        Start-Sleep -Seconds 3
        Fotografa 'frontale'
    }
    Controlla-Video | Out-Null

    # ---------------------------------------------------------------- un minuto senza effetti (riferimento)
    T06-Segna 'riferimento senza effetti (vista Essenziale)'
    Start-Sleep -Seconds 50
    T06-Reattivita 'senza effetti'
    T06-Numeri 'numeri-senza-effetti' -Foto

    # ---------------------------------------------------------------- il pulsante «Sfondo» sotto il video (il clic di Sara)
    T06-Segna 'clic su Sfondo (sfocatura di serie)'
    Passo 'Clic su «Sfondo» sotto il video' {
        Clicca 'PulsanteSfondoVideo'
        Start-Sleep -Seconds 8
        Fotografa 'sfondo-cliccato'
        Scrivi-Log "Pulsante Sfondo: stato «$(T06-Testo 'StatoSfondoVideo')»"
        Controlla-Video | Out-Null
    }
    Passo 'Menu dello sfondo (freccina)' {
        Clicca 'PulsanteMenuSfondo'
        Start-Sleep -Seconds 1
        Fotografa 'menu-sfondo'
        Tasto 'Esc'
    }

    Fotografa 'completo-con-sfocatura'
    T06-Registro 'dopo la sfocatura' | Out-Null
    T06-Numeri 'numeri-con-sfocatura'

    # ---------------------------------------------------------------- colonna «Effetti»
    T06-Segna 'colonna Effetti'
    Passo 'Apro «Effetti» nella colonna di destra' {
        Clicca 'IntestazioneEffetti' -AncheNascosti
        Start-Sleep -Seconds 1
        Fotografa 'effetti-colonna'
        Albero-UI 'effetti-colonna-tutto' -Tutto | Out-Null
    }
    foreach ($stile in @('Obiettivo (bokeh)', 'Mosaico', 'Normale')) {
        Passo "Stile della sfocatura: $stile" {
            T06-Scegli 'SceltaStileSfocatura' $stile
            Start-Sleep -Seconds 5
            Fotografa "stile-$stile"
            Controlla-Video | Out-Null
        }
    }
    Passo 'Intensità della sfocatura al massimo e poi a metà' {
        [void](T06-Cursore 'CursoreIntensitaSfondo' 100)
        Start-Sleep -Seconds 5
        Fotografa 'intensita-100'
        [void](T06-Cursore 'CursoreIntensitaSfondo' 50)
    }
    Passo 'Sfondo «Sostituito» (senza Pro)' {
        T06-Scegli 'SceltaSfondo' 'Sostituito'
        Start-Sleep -Seconds 5
        Fotografa 'sfondo-sostituito'
        Scrivi-Log "Nota sotto lo sfondo: «$(T06-Testo 'NotaSfondo')» · Pro: «$(T06-Testo 'NotaSfondoPro')»"
    }
    Passo 'Uno sfondo dal menu sotto il video' {
        Clicca 'PulsanteMenuSfondo'
        Start-Sleep -Seconds 1
        Albero-UI 'menu-sfondo-voci' | Out-Null
        $voci = @(Tutti-Elementi | Where-Object { try { $_.Current.ControlType.ProgrammaticName -match 'MenuItem|ListItem|Button' -and -not $_.Current.IsOffscreen } catch { $false } })
        Scrivi-Log "  nel menu: $(($voci | ForEach-Object { '«' + $_.Current.Name + '»' }) -join ' ')"
        Tasto 'Esc'
    }
    Passo 'Ritocco della pelle (senza Pro)' {
        $e = Trova-Elemento 'CursorePelle' -AncheNascosti
        if (-not $e) { throw 'CursorePelle non trovato' }
        Scrivi-Log "Ritocco: attivo $($e.Current.IsEnabled), fuori schermo $($e.Current.IsOffscreen)"
        try { [void](T06-Cursore 'CursorePelle' 60) } catch { Scrivi-Log "  $($_.Exception.Message)" }
        Start-Sleep -Seconds 4
        Fotografa 'ritocco-pelle'
    }
    Passo 'Di nuovo sfocato, come lo terrebbe Sara' {
        T06-Scegli 'SceltaSfondo' 'Sfocato'
        Start-Sleep -Seconds 4
        Controlla-Video | Out-Null
    }
    T06-Registro 'dopo il giro degli effetti' | Out-Null

    # ---------------------------------------------------------------- qualità
    T06-Segna 'qualità'
    Passo 'Menu della qualità (Auto, Alta, Massima)' {
        Clicca 'ChipQualita'
        Start-Sleep -Seconds 1
        Fotografa 'menu-qualita'
        Albero-UI 'menu-qualita-tutto' -Tutto | Out-Null
        Scrivi-Log "Livelli: $(T06-Testo 'ElencoLivelli') · nota «$(T06-Testo 'NotaScendere')»"
        Tasto 'Esc'
    }

    # ---------------------------------------------------------------- sessione lunga: 10 minuti con la sfocatura
    T06-Segna 'sessione lunga 10 minuti con sfocatura'
    $inizioLunga = Get-Date
    $giro = 0
    while (((Get-Date) - $inizioLunga).TotalMinutes -lt 10) {
        $giro++
        Start-Sleep -Seconds 25
        Controlla-Video | Out-Null
        T06-Reattivita "lezione, giro $giro"
        if ($giro % 2 -eq 0) { T06-Numeri "lezione-$giro" }
        if ($giro % 5 -eq 0) { Schermata "lezione-minuto-$([int]((Get-Date) - $inizioLunga).TotalMinutes)" | Out-Null }
    }
    T06-Registro 'fine della sessione lunga' | Out-Null

    # ---------------------------------------------------------------- il PC fatica: processore occupato da altro
    T06-Segna 'PC sotto sforzo (processore pieno per 150 s)'
    $fatica = @()
    for ($i = 0; $i -lt [Environment]::ProcessorCount; $i++) {
        $fatica += Start-Job -ScriptBlock { $fine = (Get-Date).AddSeconds(150); $x = 0.0; while ((Get-Date) -lt $fine) { for ($k = 0; $k -lt 200000; $k++) { $x += [Math]::Sqrt($k) } } }
    }
    Scrivi-Log "Sforzo: $($fatica.Count) lavori che occupano il processore"
    $inizioFatica = Get-Date
    $giro = 0
    while (((Get-Date) - $inizioFatica).TotalSeconds -lt 150) {
        $giro++
        Start-Sleep -Seconds 20
        Controlla-Video | Out-Null
        T06-Reattivita "sotto sforzo, giro $giro"
        if ($giro -eq 3) { Fotografa 'sotto-sforzo' }
        if ($giro % 2 -eq 0) { T06-Numeri "sforzo-$giro" }
    }
    $fatica | Stop-Job -ErrorAction SilentlyContinue
    $fatica | Remove-Job -Force -ErrorAction SilentlyContinue
    T06-Registro 'subito dopo lo sforzo' | Out-Null
    T06-Segna 'dopo lo sforzo (90 s di respiro)'
    Start-Sleep -Seconds 90
    T06-Numeri 'numeri-dopo-sforzo' -Foto
    T06-Registro 'dopo il respiro' | Out-Null

    # ---------------------------------------------------------------- impostazioni: Effetti e Qualità
    T06-Segna 'impostazioni Effetti e Qualità'
    foreach ($voce in 'Effetti', 'Qualita') {
        $nome = Testo-App "Impostazioni_$voce"
        Passo "Impostazioni › $nome" {
            T06-Apri-Impostazioni
            Clicca $nome -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Seconds 1
            Fotografa "impostazioni-$voce"
            if (T06-Scorri 100) { Schermata "impostazioni-$voce-in-fondo" | Out-Null }
            Albero-UI "impostazioni-$voce-tutto" -Tutto | Out-Null
            T06-Chiudi-Impostazioni
        }
    }

    T06-Segna 'torno alla fotocamera posteriore con la sfocatura accesa'
    Passo 'Fotocamera posteriore con la sfocatura accesa' {
        Clicca 'Principale 1×' -Dentro 'SceltaObiettivo'
        Start-Sleep -Seconds 5
        Fotografa 'posteriore-con-sfocatura'
        Scrivi-Log "Sfondo nella colonna: $(T06-Testo 'SceltaSfondo')"
    }
    T06-Registro 'dopo il ritorno alla posteriore' | Out-Null

    # ---------------------------------------------------------------- fine
    T06-Segna 'fine'
    Passo 'Riassunto dei campioni' {
        $righe = @(Import-Csv -LiteralPath $campioni)
        Scrivi-Log "Campioni: $($righe.Count)"
        $ws = $righe | ForEach-Object { [int]$_.app_ws_mb }
        $cpu = $righe | ForEach-Object { [double]$_.app_cpu_pct }
        Scrivi-Log ("App: memoria (working set) da {0} a {1} MB (max {2}); CPU media {3:0.0}% max {4:0.0}%" -f $ws[1], $ws[-1], ($ws | Measure-Object -Maximum).Maximum, ($cpu | Measure-Object -Average).Average, ($cpu | Measure-Object -Maximum).Maximum)
    }
} finally {
    Stop-Job $campionatore -ErrorAction SilentlyContinue
    Remove-Job $campionatore -Force -ErrorAction SilentlyContinue
    Raccogli-Registri

    # Pacchetto nel registro del lavoro: PNG → JPEG 1280×720, poi tar.gz in base64.
    $pacco = Join-Path $env:TEMP 't06-pacco'
    if (Test-Path $pacco) { Remove-Item -Recurse -Force $pacco }
    New-Item -ItemType Directory -Force -Path (Join-Path $pacco 't06') | Out-Null
    Add-Type -AssemblyName System.Drawing
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
    $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 72L
    Get-ChildItem -LiteralPath $cartella -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($cartella.Length + 1)
        $dest = Join-Path (Join-Path $pacco 't06') $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if ($_.Extension -eq '.png') {
            $img = [System.Drawing.Image]::FromFile($_.FullName)
            $l = [Math]::Min(1280, $img.Width); $a = [int]($img.Height * $l / $img.Width)
            $ridotta = New-Object System.Drawing.Bitmap $img, $l, $a
            $ridotta.Save(($dest -replace '\.png$', '.jpg'), $codec, $parametri)
            $ridotta.Dispose(); $img.Dispose()
        } elseif ($_.Extension -ne '.bmp') {
            Copy-Item -LiteralPath $_.FullName -Destination $dest
        }
    }
    $tgz = Join-Path $env:TEMP 't06.tar.gz'
    & tar.exe -czf $tgz -C $pacco t06
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($tgz))
    Write-Host "Pacchetto: $((Get-Item $tgz).Length) byte"
    Write-Host '=====COLLAUDO-INIZIO====='
    for ($i = 0; $i -lt $base64.Length; $i += 2000) { Write-Host $base64.Substring($i, [Math]::Min(2000, $base64.Length - $i)) }
    Write-Host '=====COLLAUDO-FINE====='
}
