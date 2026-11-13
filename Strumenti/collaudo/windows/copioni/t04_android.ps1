# Copione «t04_android» (collaudo-20, tester t04): un telefono Android su un PC Windows, visto da uno sviluppatore.
# Numeri del collegamento (fps, Mbit/s, latenza) mentre il video scorre, mentre tace e dopo; connessione chiusa di
# colpo (come un cavo strappato) e ricollegamento; registro del collegamento. Alla fine stampa nel registro del job
# passi.log, alberi, registri del telefono e schermate ridotte in base64 (gli artifact sono bloccati dal proxy).

function Numeri([string]$Nome) {
    Passo "Numeri della qualità ($Nome)" {
        Clicca 'ChipQualita'
        Start-Sleep -Milliseconds 900
        Fotografa "numeri-$Nome"
        $testi = @(Testi-Visibili) | Where-Object { $_ -match 'Fotogrammi|Velocit|Latenza|Risoluzione|Media|Tappe|Parti|Formato|Avvio|ms' }
        foreach ($t in $testi) { Scrivi-Log "  NUMERI[$Nome] $t" }
        Tasto 'Esc'
    }
}
function Ultime-Righe([string]$Nome, [int]$Quante = 6) {
    foreach ($r in @(Registro-Telefono $Nome | Select-Object -Last $Quante)) { Scrivi-Log "  TELEFONO: $r" }
}
function Registro-PC([string]$Nome) {
    Passo "Registro del collegamento ($Nome)" {
        Clicca 'PulsanteRegistro'
        Start-Sleep -Seconds 1
        Fotografa "registro-$Nome"
        $e = Trova-Elemento 'TestoRegistro' -AncheNascosti
        if ($e) { foreach ($r in ($e.Current.Name -split "`n")) { Scrivi-Log "  REGISTRO-PC: $r" } }
        Tasto 'Esc'
    }
}

$telefono = 'Pixel di Marco'
Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
Registro-PC 'avvio'

Passo 'Come funziona il cavo USB' {
    if (Esiste 'RispostaCavo') { Clicca 'RispostaCavo'; Start-Sleep -Seconds 1; Fotografa 'risposta-cavo'; Tasto 'Esc' }
    else { Scrivi-Log '  RispostaCavo non è a schermo adesso' }
}

$collegato = Passo 'Telefono Android dal QR' {
    Avvia-TelefonoFinto -DalQR --nome $telefono --android --fps 30 --durata 600 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome $telefono -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome $telefono -Obbligatorio | Out-Null
} -Esito
if (-not $collegato) {
    Ferma-TelefonoFinto
    $collegato = Passo 'Telefono Android con la conferma' {
        Avvia-TelefonoFinto --nome $telefono --android --fps 30 --durata 600 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome $telefono -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 -Obbligatorio | Out-Null
        Clicca (Testo-App 'Conferma_Consenti')
        Attendi-Telefono 'ACCETTATO' 20 -Nome $telefono -Obbligatorio | Out-Null
    } -Esito
}

if ($collegato) {
    Start-Sleep -Seconds 10
    Fotografa 'in-onda-10s'
    Controlla-Video | Out-Null
    Ultime-Righe $telefono
    Numeri 'video-10s'
    Start-Sleep -Seconds 10
    Numeri 'video-20s'

    # Il telefono tace (Wi-Fi sparito o cavo che non risponde): i numeri dicono la verità?
    Rete-Spenta
    Start-Sleep -Seconds 2
    Numeri 'tace-2s'
    Start-Sleep -Seconds 4
    Fotografa 'tace-6s'
    Numeri 'tace-6s'
    Start-Sleep -Seconds 10
    Fotografa 'tace-16s'
    Numeri 'tace-16s'
    Registro-PC 'durante-silenzio'
    Rete-Accesa
    Start-Sleep -Seconds 8
    Fotografa 'dopo-silenzio-8s'
    Controlla-Video | Out-Null
    Numeri 'dopo-silenzio-8s'
    Ultime-Righe $telefono 10

    # Chiusa di colpo e di nuovo dopo 6 s (come un cavo strappato e riattaccato): un secondo telefono, lo stesso nome.
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 3
    $inizio = Get-Date
    Avvia-TelefonoFinto --nome $telefono --android --fps 30 --durata 200 --interrompi-dopo 15 --modo-interruzione chiusura --riconnetti-dopo 6 | Out-Null
    $ok = Attendi-Telefono 'Video:' 30 -Nome $telefono
    Scrivi-Log "  T04: telefono conosciuto di nuovo in video dopo $([int]((Get-Date) - $inizio).TotalSeconds) s"
    Attendi-Telefono 'INTERRUZIONE' 40 -Nome $telefono | Out-Null
    $strappo = Get-Date
    Start-Sleep -Seconds 2
    Fotografa 'strappo-2s'
    Numeri 'strappo-3s'
    Start-Sleep -Seconds 12
    Fotografa 'dopo-strappo-14s'
    Controlla-Video | Out-Null
    Numeri 'dopo-strappo-15s'
    Ultime-Righe $telefono 12
    Registro-PC 'dopo-strappo'
}

Passo 'Impostazioni › Telefoni' {
    Clicca 'PulsanteImpostazioni'
    Start-Sleep -Milliseconds 800
    Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Milliseconds 800
    Fotografa 'impostazioni-telefoni'
}
Passo 'Impostazioni › Registro' {
    if (Trova-Elemento 'PulsanteIndietroImpostazioni') { Clicca 'PulsanteIndietroImpostazioni'; Start-Sleep -Milliseconds 600 }
    Clicca (Testo-App 'Impostazioni_Registro') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Milliseconds 800
    Fotografa 'impostazioni-registro'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"
}

# ---- tutto nel registro del job
$cartella = Cartella-Risultati
Add-Type -AssemblyName System.Drawing
Write-Host '=====T04 INIZIO====='
foreach ($f in Get-ChildItem -LiteralPath $cartella -File | Where-Object { $_.Extension -in '.log', '.txt' }) {
    Write-Host "=====T04 TESTO $($f.Name)====="
    Get-Content -LiteralPath $f.FullName -Encoding UTF8 | ForEach-Object { Write-Host "T04| $_" }
}
foreach ($f in Get-ChildItem -LiteralPath $cartella -Filter '*.png' -File) {
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        $l = 1280; $a = [int]($img.Height * $l / $img.Width)
        $bmp = New-Object System.Drawing.Bitmap $l, $a
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($img, 0, 0, $l, $a)
        $ms = New-Object System.IO.MemoryStream
        $cod = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $par = New-Object System.Drawing.Imaging.EncoderParameters 1
        $par.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 70L
        $bmp.Save($ms, $cod, $par)
        $g.Dispose(); $bmp.Dispose(); $img.Dispose()
        Write-Host "=====T04 JPG $($f.BaseName)====="
        Write-Host ("T04B64 " + [Convert]::ToBase64String($ms.ToArray()))
    } catch { Write-Host "T04 errore immagine $($f.Name): $($_.Exception.Message)" }
}
Write-Host '=====T04 FINE====='
