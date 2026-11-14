# Copione t20 «Luisa»: la beta 4 (d49224a, compilata qui) installata come la mette l'installatore
# (%LOCALAPPDATA%\Programs\WebcamLR), un telefono fidato, «Avvia con Windows» acceso e la vista Completo; poi la versione
# nuova sopra gli stessi dati; poi il disinstallatore vero («Disinstalla WebcamLR.exe /disinstalla /silenzioso») e cosa
# resta (AppData, registro Run, menu Start); poi la reinstallazione. Gli artifact sono bloccati: schermate e dati
# stampati nel registro del lavoro (=====T20-…).

$beta4 = 'd49224a1681b661f5337382397a1e6ba58bdbf84'
$radice = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$lavoro = Join-Path $env:RUNNER_TEMP 't20'
$cartellaApp = Join-Path $env:LOCALAPPDATA 'Programs\WebcamLR'
$dati = Join-Path $env:LOCALAPPDATA 'WebcamLR'
$telefono = 'iPhone di Luisa'
New-Item -ItemType Directory -Force -Path $lavoro | Out-Null

function T20-Exe([string]$Percorso) {
    & (Get-Module Collaudo) { param($p) $script:Exe = $p } $Percorso
    Scrivi-Log "T20: l'app ora è $Percorso"
}

function T20-Cartella-Build([string]$Radice) {
    $exe = Get-ChildItem -Path (Join-Path $Radice 'Windows\WebcamLR.App\bin') -Recurse -Filter 'WebcamLR.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\win-x64\\WebcamLR\.exe$' } | Select-Object -First 1
    if (-not $exe) { throw "WebcamLR.exe non trovato sotto $Radice" }
    Split-Path $exe.FullName
}

function T20-Installa([string]$Da, [string]$Etichetta) {
    # Come Installazione.cs: la cartella dell'app sostituita, i dati in %LOCALAPPDATA%\WebcamLR non si toccano.
    if (Test-Path $cartellaApp) { Remove-Item -Recurse -Force $cartellaApp }
    New-Item -ItemType Directory -Force -Path $cartellaApp | Out-Null
    Copy-Item -Path (Join-Path $Da '*') -Destination $cartellaApp -Recurse -Force
    $dis = Join-Path $lavoro 'disinstallatore\WebcamLR.Setup.exe'
    if (Test-Path $dis) { Copy-Item $dis (Join-Path $cartellaApp 'Disinstalla WebcamLR.exe') -Force }
    Scrivi-Log ("T20: installata «$Etichetta» in $cartellaApp ({0} file)" -f @(Get-ChildItem -Recurse -File $cartellaApp).Count)
    T20-Exe (Join-Path $cartellaApp 'WebcamLR.exe')
}

function T20-Stato([string]$Nome) {
    # Cosa c'è su disco e nel registro di Windows: dati, cartella dell'app, Run, App installate, menu Start, Video.
    $righe = New-Object System.Collections.Generic.List[string]
    $righe.Add("### $Nome · $(Get-Date -Format HH:mm:ss)")
    foreach ($c in @($dati, (Join-Path $env:APPDATA 'WebcamLR'), $cartellaApp, (Join-Path ([Environment]::GetFolderPath('MyVideos')) 'WebcamLR'),
                     (Join-Path ([Environment]::GetFolderPath('MyPictures')) 'WebcamLR'), (Join-Path $env:ProgramFiles 'WebcamLR'), (Join-Path $env:ProgramData 'WebcamLR'))) {
        if (Test-Path $c) {
            $file = @(Get-ChildItem -LiteralPath $c -Recurse -File -ErrorAction SilentlyContinue)
            $righe.Add("CARTELLA ${c}: c'è ($($file.Count) file, $([int](($file | Measure-Object Length -Sum).Sum / 1KB)) KB)")
            if ($c -eq $dati) {
                foreach ($f in $file) {
                    $riga = "    {0,8}  {1}" -f $f.Length, $f.FullName.Substring($dati.Length + 1)
                    if ($f.Name -ne 'identita' -and $f.Length -lt 600 -and $f.Extension -notin '.png', '.jpg', '.bin') {
                        $riga += '  = ' + ((Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) -replace '\s+', ' ').Trim()
                    }
                    $righe.Add($riga)
                }
            }
        } else { $righe.Add("CARTELLA ${c}: non c'è") }
    }
    $run = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WebcamLR' -ErrorAction SilentlyContinue).WebcamLR
    $righe.Add("REGISTRO Run\WebcamLR: $(if ($run) { $run } else { '(nessuno)' })")
    if ($run -and $run -match '^"([^"]+)"') { $righe.Add("    l'exe di Run esiste: $(Test-Path $Matches[1])") }
    $approvato = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name 'WebcamLR' -ErrorAction SilentlyContinue).WebcamLR
    $righe.Add("REGISTRO StartupApproved\Run\WebcamLR: $(if ($approvato) { ($approvato | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' } else { '(nessuno)' })")
    $righe.Add("REGISTRO Uninstall\WebcamLR: $(Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WebcamLR')")
    $lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'WebcamLR.lnk'
    $righe.Add("MENU START WebcamLR.lnk: $(Test-Path $lnk)")
    $righe.Add("PROCESSI WebcamLR: $(@(Get-Process -Name WebcamLR -ErrorAction SilentlyContinue).Count)")
    $file = Join-Path (Cartella-Risultati) "stato-$Nome.txt"
    [System.IO.File]::WriteAllLines($file, $righe, (New-Object System.Text.UTF8Encoding $true))
    foreach ($r in $righe) { Scrivi-Log "  $r" }
}

function T20-StatoAvvio {
    $e = Trova-Elemento 'InterruttoreAvvio' -AncheNascosti
    if (-not $e) { return 'non trovato' }
    try { $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState.ToString() } catch { "? $($_.Exception.Message)" }
}

function T20-Apri-Pagina([string]$Voce) {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
    Clicca (Testo-App "Impostazioni_$Voce") -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Milliseconds 900
}
function T20-Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}

function T20-Telefono-Entra([string]$Etichetta) {
    # Il telefono finto con la stessa identità (stesso nome): ACCETTATO subito se fidato, CODICE se no (allora Consenti).
    # Il registro del telefono può contenere le righe dei giri prima: conto solo quelle nuove.
    $gia = @(Registro-Telefono $telefono).Count
    $file = Join-Path (Cartella-Risultati) ("telefono-" + (($telefono -replace '[^\w\-]+', '-').Trim('-')) + ".log")
    if (Test-Path $file) { $gia = @(Get-Content -LiteralPath $file -Encoding UTF8).Count }
    Avvia-TelefonoFinto --nome $telefono --durata 40 | Out-Null
    $nuove = { @(Registro-Telefono $telefono) | Select-Object -Skip $gia }
    $esito = $null
    $limite = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $limite -and -not $esito) {
        $log = @(& $nuove)
        if ($log | Where-Object { $_ -like '*CODICE*' }) { $esito = 'CODICE' }
        elseif ($log | Where-Object { $_ -like '*ACCETTATO*' }) { $esito = 'ACCETTATO' }
        elseif ($log | Where-Object { $_ -like '*RIFIUTATO*' }) { $esito = 'RIFIUTATO' }
        else { Start-Sleep -Milliseconds 500 }
    }
    Scrivi-Log "T20 ${Etichetta}: il telefono «$telefono» → $esito"
    if ($esito -eq 'CODICE') {
        Start-Sleep -Seconds 1
        Fotografa "$Etichetta-conferma"
        Clicca (Testo-App 'Conferma_Consenti')
    }
    $limite = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $limite -and -not (@(& $nuove) | Where-Object { $_ -like '*Video:*' })) { Start-Sleep -Milliseconds 500 }
    Scrivi-Log "T20 ${Etichetta}: video $([bool](@(& $nuove) | Where-Object { $_ -like '*Video:*' }))"
    Start-Sleep -Seconds 3
    Fotografa "$Etichetta-video"
    Ferma-TelefonoFinto $telefono
    Start-Sleep -Seconds 2
    $esito
}

function T20-Stampa {
    # Schermate scelte (JPEG ridotto) e testi nel registro del lavoro: gli artifact non si scaricano.
    Add-Type -AssemblyName System.Drawing
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
    $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 50L
    foreach ($f in Get-ChildItem -LiteralPath (Cartella-Risultati) -Filter *.png | Sort-Object Name) {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        $piccola = New-Object System.Drawing.Bitmap $img, 960, ([int](960 * $img.Height / $img.Width))
        $flusso = New-Object System.IO.MemoryStream
        $piccola.Save($flusso, $codec, $parametri)
        $img.Dispose(); $piccola.Dispose()
        Write-Host "=====T20-IMG $($f.BaseName)====="
        Write-Host ([Convert]::ToBase64String($flusso.ToArray()))
        Write-Host "=====T20-FINE====="
    }
    foreach ($f in @(Get-ChildItem -LiteralPath (Cartella-Risultati) -File | Where-Object { $_.Extension -in '.txt', '.log' })) {
        Write-Host "=====T20-TXT $($f.Name)====="
        Get-Content -LiteralPath $f.FullName -Encoding UTF8 | ForEach-Object { Write-Host "T20| $_" }
        Write-Host "=====T20-FINE====="
    }
}

try {
# ---------------------------------------------------------------- 0. compilo la beta 4 e il disinstallatore
Passo 'Compilo la beta 4 (d49224a)' {
    $sorgente = Join-Path $lavoro 'beta4'
    Push-Location $radice
    $glog = Join-Path (Cartella-Risultati) 'git-beta4.log'
    cmd /c "git fetch -q --depth=1 origin $beta4 > `"$glog`" 2>&1"
    cmd /c "git worktree add -q --detach `"$sorgente`" FETCH_HEAD >> `"$glog`" 2>&1"
    Scrivi-Log "T20: git → codice $LASTEXITCODE"
    Pop-Location
    $log = Join-Path (Cartella-Risultati) 'compila-beta4.log'
    $progetto = Join-Path $sorgente 'Windows\WebcamLR.App\WebcamLR.App.csproj'
    cmd /c "dotnet build `"$progetto`" -c Debug -p:Platform=x64 --nologo -v:q > `"$log`" 2>&1"
    Scrivi-Log "T20: dotnet build della beta 4 → codice $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Get-Content $log -Tail 30 | ForEach-Object { Scrivi-Log "  $_" }; throw 'la beta 4 non si compila' }
}
Passo 'Pubblico il disinstallatore (WebcamLR.Setup senza pacchetto)' {
    $log = Join-Path (Cartella-Risultati) 'compila-disinstallatore.log'
    $progetto = Join-Path $radice 'Windows\WebcamLR.Setup\WebcamLR.Setup.csproj'
    $uscitaDis = Join-Path $lavoro 'disinstallatore'
    cmd /c "dotnet publish `"$progetto`" -c Release -r win-x64 -o `"$uscitaDis`" --nologo -v:q > `"$log`" 2>&1"
    Scrivi-Log "T20: dotnet publish del disinstallatore → codice $LASTEXITCODE"
}
$buildVecchia = T20-Cartella-Build (Join-Path $lavoro 'beta4')
$buildNuova = T20-Cartella-Build $radice
Scrivi-Log "T20: beta 4 in $buildVecchia; nuova in $buildNuova"

# ---------------------------------------------------------------- 1. Luisa con la beta 4
Azzera-Dati
T20-Installa $buildVecchia 'beta 4'
T20-Stato '0-beta4-appena-installata'
Avvia-App | Out-Null
Start-Sleep -Seconds 4
Fotografa 'beta4-primo-avvio'
Passo 'Beta 4: telefono fidato' { Scrivi-Log "T20 beta 4 primo collegamento: $(T20-Telefono-Entra 'beta4')" }
Passo 'Beta 4: vista Completo' { Tasto 'Ctrl+2'; Start-Sleep -Seconds 1; Fotografa 'beta4-completo' }
Passo 'Beta 4: Avvia con Windows acceso' {
    T20-Apri-Pagina 'Avvio'
    Scrivi-Log "T20 beta 4 Avvia con Windows prima: $(T20-StatoAvvio)"
    Clicca 'InterruttoreAvvio' -AncheNascosti
    Start-Sleep -Milliseconds 800
    Scrivi-Log "T20 beta 4 Avvia con Windows dopo: $(T20-StatoAvvio)"
    Fotografa 'beta4-avvio-acceso'
    T20-Chiudi-Impostazioni
}
Chiudi-App
Start-Sleep -Seconds 2
T20-Stato '1-beta4-usata'

# ---------------------------------------------------------------- 2. la versione nuova sopra
T20-Installa $buildNuova 'nuova'
Avvia-App | Out-Null
Start-Sleep -Seconds 5
Fotografa 'nuova-primo-avvio'
Scrivi-Log "T20 nuova, testi al primo avvio: $((@(Testi-Visibili) | Select-Object -Unique) -join ' | ')"
Passo 'Nuova: il telefono di prima è ancora fidato?' {
    $esito = T20-Telefono-Entra 'nuova'
    Scrivi-Log "T20 nuova, telefono di prima: $esito"
    if ($esito -ne 'ACCETTATO') { Segnala-Problema "Dopo l'aggiornamento il telefono fidato della beta 4 deve confermare di nuovo ($esito)" }
}
Passo 'Nuova: Avvia con Windows e telefoni fidati' {
    T20-Apri-Pagina 'Avvio'
    $stato = T20-StatoAvvio
    Scrivi-Log "T20 nuova, Avvia con Windows: $stato"
    Fotografa 'nuova-avvio'
    if ($stato -ne 'On') { Segnala-Problema "Dopo l'aggiornamento «Avvia con Windows» non è più acceso ($stato)" }
    T20-Chiudi-Impostazioni
    T20-Apri-Pagina 'Telefoni'
    Fotografa 'nuova-telefoni'
    T20-Chiudi-Impostazioni
}
Chiudi-App
Start-Sleep -Seconds 2
T20-Stato '2-nuova-usata'

# ---------------------------------------------------------------- 3. disinstallazione con l'app aperta
Avvia-App | Out-Null
Start-Sleep -Seconds 3
$dis = Join-Path $cartellaApp 'Disinstalla WebcamLR.exe'
Passo 'Disinstallazione silenziosa con WebcamLR aperta' {
    if (-not (Test-Path $dis)) { throw "manca $dis" }
    $p = Start-Process -FilePath $dis -ArgumentList '/disinstalla', '/silenzioso' -PassThru
    if (-not $p.WaitForExit(120000)) { Fotografa 'disinstallazione-ferma'; $p.Kill(); Segnala-Problema 'Il disinstallatore non finisce in 120 s' }
    Scrivi-Log "T20: disinstallatore uscito con codice $($p.ExitCode)"
    Start-Sleep -Seconds 6
    Fotografa 'dopo-disinstallazione'
}
& (Get-Module Collaudo) { $script:Processo = $null }
T20-Stato '3-dopo-disinstallazione'
$reg = Join-Path $dati 'Installazione.txt'
if (Test-Path $reg) { Get-Content $reg -Encoding UTF8 | ForEach-Object { Scrivi-Log "  Installazione.txt: $_" } }
$run = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WebcamLR' -ErrorAction SilentlyContinue).WebcamLR
if ($run) { Segnala-Problema "Dopo la disinstallazione resta in Run la voce «WebcamLR» = $run" }

# ---------------------------------------------------------------- 4. reinstallazione
T20-Installa $buildNuova 'reinstallata'
Avvia-App | Out-Null
Start-Sleep -Seconds 5
Fotografa 'reinstallata-primo-avvio'
Scrivi-Log "T20 reinstallata, testi: $((@(Testi-Visibili) | Select-Object -Unique) -join ' | ')"
Passo 'Reinstallata: il telefono di prima' { Scrivi-Log "T20 reinstallata, telefono di prima: $(T20-Telefono-Entra 'reinstallata')" }
Passo 'Reinstallata: Avvia con Windows' {
    T20-Apri-Pagina 'Avvio'; Scrivi-Log "T20 reinstallata, Avvia con Windows: $(T20-StatoAvvio)"; Fotografa 'reinstallata-avvio'
    Clicca 'InterruttoreAvvio' -AncheNascosti; Start-Sleep -Milliseconds 800
    Scrivi-Log "T20 reinstallata, Avvia con Windows dopo un clic: $(T20-StatoAvvio)"
    T20-Chiudi-Impostazioni
}
Chiudi-App
T20-Stato '4-reinstallata'
} finally {
    try { Raccogli-Registri } catch { }
    T20-Stampa
}
