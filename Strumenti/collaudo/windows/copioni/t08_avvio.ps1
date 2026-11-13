# Copione t08 «avvio»: il collegamento iniziale con la rete instabile. La rete cade mentre il PC chiede «Consentire…?»,
# il PC dice «Non consentire», e lo stesso telefono riprova subito.

# ---------------------------------------------------------------- funzioni del tester t08 (in ogni copione t08)
function T08-Accettati([string]$Nome) { @(Registro-Telefono $Nome | Where-Object { $_ -like '*ACCETTATO*' }).Count }

function T08-Guarda([string]$Etichetta, [int]$Secondi, [int]$Ogni = 6) {
    # Per <Secondi> fotografa la finestra e scrive i testi a schermo ogni <Ogni> s: cosa vede Luca.
    $fine = (Get-Date).AddSeconds($Secondi); $k = 0
    while ((Get-Date) -lt $fine) {
        $k++
        [void](Schermata "$Etichetta-$k")
        Scrivi-Log "TESTI ${Etichetta}-${k}: $((@(Testi-Visibili) | Select-Object -Unique) -join ' | ')"
        Start-Sleep -Seconds $Ogni
    }
}

function T08-Ritorno([string]$Nome, [int]$Prima, [int]$Massimo, [string]$Etichetta) {
    # Secondi fino a un nuovo ACCETTATO (se $Prima -ge 0) e al video che scorre di nuovo sul PC.
    $inizio = Get-Date
    while (((Get-Date) - $inizio).TotalSeconds -lt $Massimo) {
        $ok = $true
        if ($Prima -ge 0 -and (T08-Accettati $Nome) -le $Prima) { $ok = $false }
        if ($ok -and (Controlla-Video -Secondi 1)) {
            Scrivi-Log ("RITORNO ${Etichetta}: video di nuovo in {0:0.0} s" -f ((Get-Date) - $inizio).TotalSeconds)
            return
        }
        Start-Sleep -Milliseconds 500
    }
    Segnala-Problema "${Etichetta}: il video non torna in $Massimo s"
    [void](Schermata "$Etichetta-senza-ritorno")
}

function T08-Stampa-Schermate {
    # Gli artifact non si scaricano: ogni schermata in JPEG piccolo e base64 nel registro del lavoro.
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
        Write-Host "=====T08-IMG $($f.BaseName)====="
        Write-Host ([Convert]::ToBase64String($flusso.ToArray()))
        Write-Host "=====T08-FINE====="
    }
    foreach ($f in Get-ChildItem -LiteralPath (Cartella-Risultati) -Filter 'telefono-*.log') {
        Write-Host "=====T08-TXT $($f.Name)====="
        Get-Content -LiteralPath $f.FullName -Encoding UTF8 | ForEach-Object { Write-Host "T08| $_" }
        Write-Host "=====T08-FINE====="
    }
}

$n = 'Pixel di Luca'
Avvia-App -Azzera
Start-Sleep -Seconds 3
Passo 'Rete che cade durante la conferma sul PC' {
    Avvia-TelefonoFinto --nome $n --android --identita-nuova --durata 120 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'CODICE' 30 -Nome $n -Obbligatorio | Out-Null
    Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
    Fotografa 'conferma'
    Rete-Spenta
    T08-Guarda 'conferma-senza-rete' 20 5
    Fotografa 'conferma-senza-rete-fine'
    if (Attendi-Testo (Testo-App 'Conferma_Consenti') 2) { Clicca (Testo-App 'Conferma_Consenti'); Scrivi-Log 'Consenti cliccato con il telefono muto' }
    Start-Sleep -Seconds 2
    Rete-Accesa
    T08-Guarda 'conferma-rete-tornata' 30 5
    $r = Attendi-Telefono 'Video:' 30 -Nome $n
    Scrivi-Log "Dopo la conferma con la rete caduta: video $([bool]$r)"
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3
Passo 'Il PC non consente' {
    Avvia-TelefonoFinto --nome 'Telefono sconosciuto' --android --identita-nuova --durata 60 | Out-Null
    Attendi-Telefono 'CODICE' 30 -Nome 'Telefono sconosciuto' -Obbligatorio | Out-Null
    Attendi-Testo (Testo-App 'Conferma_NonConsentire') 15 -Obbligatorio | Out-Null
    Clicca (Testo-App 'Conferma_NonConsentire')
    T08-Guarda 'non-consentito' 10 3
    Attendi-Telefono 'FINE' 15 -Nome 'Telefono sconosciuto' | Out-Null
}
Ferma-TelefonoFinto
Passo 'Lo stesso telefono riprova subito' {
    Avvia-TelefonoFinto --nome 'Telefono sconosciuto' --android --durata 40 | Out-Null
    Start-Sleep -Seconds 4
    T08-Guarda 'riprova' 12 4
    Attendi-Telefono 'FINE' 20 -Nome 'Telefono sconosciuto' | Out-Null
}
Ferma-TelefonoFinto
Passo 'Conferma che nessuno guarda (60 s)' {
    Avvia-TelefonoFinto --nome 'Pixel nuovo' --android --identita-nuova --durata 120 | Out-Null
    Attendi-Telefono 'CODICE' 30 -Nome 'Pixel nuovo' -Obbligatorio | Out-Null
    T08-Guarda 'senza-risposta' 70 15
    Attendi-Telefono 'FINE' 20 -Nome 'Pixel nuovo' | Out-Null
}
Ferma-TelefonoFinto
T08-Stampa-Schermate
