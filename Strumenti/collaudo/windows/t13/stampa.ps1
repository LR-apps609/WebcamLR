# Collaudo t13: stampa nel registro del lavoro i risultati del copione (testi e schermate JPEG ridotte in base64),
# perché gli artifact non si scaricano da questa rete. Righe: «T13FILE <nome>», base64 a pezzi, «T13FINE».
param([string]$Cartella)
"PROBLEMI: $((Problemi) -join ' || ')" | Set-Content -LiteralPath (Join-Path $Cartella 'problemi-t13.txt') -Encoding UTF8
$dati = Join-Path $env:LOCALAPPDATA 'WebcamLR'
if (Test-Path $dati) {
    Get-ChildItem -LiteralPath $dati -File | ForEach-Object { "{0,10}  {1}" -f $_.Length, $_.Name } |
        Set-Content -LiteralPath (Join-Path $Cartella 'dati-app-elenco.txt') -Encoding UTF8
    $errori = Join-Path $dati 'Errori.txt'
    if (Test-Path $errori) { Copy-Item -LiteralPath $errori -Destination (Join-Path $Cartella 'dati-app-Errori.txt') -Force }
}
Add-Type -AssemblyName System.Drawing
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
$parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 65L
foreach ($f in Get-ChildItem -LiteralPath $Cartella -File | Sort-Object Name) {
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
            $byte = [IO.File]::ReadAllBytes($f.FullName)
            if ($byte.Length -gt 3MB) { $byte = $byte[0..(3MB - 1)] }
            $nome = $f.Name
        } else { continue }
        Write-Host "T13FILE $nome"
        $b64 = [Convert]::ToBase64String($byte)
        for ($i = 0; $i -lt $b64.Length; $i += 4000) { Write-Host $b64.Substring($i, [Math]::Min(4000, $b64.Length - $i)) }
        Write-Host 'T13FINE'
    } catch { Write-Host "T13ERRORE $($f.Name): $($_.Exception.Message)" }
}
