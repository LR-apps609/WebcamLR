# Collaudo t10 (Stefano): esegue t10/corpo.ps1 e poi stampa nel registro del lavoro le schermate (JPEG ridotti) e gli
# alberi in base64, perché da questa rete gli artifact non si scaricano. Righe: «T10FILE <nome>», base64, «T10FINE».
try {
    & (Join-Path $PSScriptRoot '..\t10\corpo.ps1')
} finally {
    $cartella = Cartella-Risultati
    Add-Type -AssemblyName System.Drawing
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
    $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 70L
    "PROBLEMI: $((Problemi) -join ' || ')" | Set-Content -LiteralPath (Join-Path $cartella 'problemi-t10.txt') -Encoding UTF8
    foreach ($f in Get-ChildItem -LiteralPath $cartella -File | Sort-Object Name) {
        try {
            if ($f.Extension -eq '.png') {
                $img = [System.Drawing.Image]::FromFile($f.FullName)
                $l = [int]($img.Width * 0.6); $a = [int]($img.Height * 0.6)
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
                $nome = $f.Name
            } else { continue }
            Write-Host "T10FILE $nome"
            $b64 = [Convert]::ToBase64String($byte)
            for ($i = 0; $i -lt $b64.Length; $i += 4000) { Write-Host $b64.Substring($i, [Math]::Min(4000, $b64.Length - $i)) }
            Write-Host 'T10FINE'
        } catch { Write-Host "T10ERRORE $($f.Name): $($_.Exception.Message)" }
    }
}
