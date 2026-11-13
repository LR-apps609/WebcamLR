# Copione t08 «rete»: Luca, Wi-Fi pessimo, telefono Android. Cadute brevi, lunghe, ripetute, connessione chiusa di
# colpo (breve e lunga), telefono che non torna mai. Per ognuna: cosa mostra il PC e quanto ci mette il video a tornare.

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
Passo 'Telefono dal QR' {
    Avvia-TelefonoFinto -DalQR --nome $n --android --durata 900 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome $n -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 30 -Nome $n -Obbligatorio | Out-Null
    Start-Sleep -Seconds 5
    Fotografa 'in-onda'
}
Passo 'Silenzio breve 5 s' {
    Rete-Spenta
    T08-Guarda 'breve' 5 2
    Rete-Accesa
    T08-Ritorno $n -1 60 'silenzio 5 s'
    Fotografa 'breve-dopo'
}
Start-Sleep -Seconds 8
Passo 'Silenzio lungo 25 s' {
    $prima = T08-Accettati $n
    Rete-Spenta
    T08-Guarda 'lungo' 25 4
    Rete-Accesa
    T08-Ritorno $n $prima 60 'silenzio 25 s'
    Fotografa 'lungo-dopo'
}
Start-Sleep -Seconds 8
Passo 'Silenzi ripetuti 3 x 3 s' {
    foreach ($i in 1..3) { Rete-Spenta; Start-Sleep -Seconds 3; Rete-Accesa; Start-Sleep -Seconds 3 }
    Fotografa 'ripetuti'
    T08-Ritorno $n -1 60 'silenzi ripetuti'
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 4
Fotografa 'telefono-fermato'
Passo 'Chiusura di colpo, ritorno dopo 5 s' {
    Avvia-TelefonoFinto --nome $n --android --durata 120 --interrompi-dopo 12 --modo-interruzione chiusura --riconnetti-dopo 5 | Out-Null
    Attendi-Telefono 'Video:' 40 -Nome $n -Obbligatorio | Out-Null
    $prima = T08-Accettati $n
    Attendi-Telefono 'INTERRUZIONE' 30 -Nome $n -Obbligatorio | Out-Null
    T08-Guarda 'chiusura-breve' 5 2
    T08-Ritorno $n $prima 60 'chiusura, ritorno dopo 5 s'
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3
Passo 'Chiusura di colpo, ritorno dopo 45 s' {
    Avvia-TelefonoFinto --nome $n --android --durata 180 --interrompi-dopo 12 --modo-interruzione chiusura --riconnetti-dopo 45 | Out-Null
    Attendi-Telefono 'Video:' 40 -Nome $n -Obbligatorio | Out-Null
    $prima = T08-Accettati $n
    Attendi-Telefono 'INTERRUZIONE' 30 -Nome $n -Obbligatorio | Out-Null
    T08-Guarda 'chiusura-lunga' 44 6
    T08-Ritorno $n $prima 60 'chiusura, ritorno dopo 45 s'
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3
Passo 'Telefono che non torna mai (silenzio 150 s)' {
    Avvia-TelefonoFinto --nome $n --android --durata 600 | Out-Null
    Attendi-Telefono 'Video:' 40 -Nome $n -Obbligatorio | Out-Null
    Start-Sleep -Seconds 3
    Rete-Spenta
    T08-Guarda 'mai' 150 20
    Fotografa 'mai-fine'
}
Ferma-TelefonoFinto
T08-Stampa-Schermate
