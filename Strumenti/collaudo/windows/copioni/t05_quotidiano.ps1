# Copione t05 «quotidiano» (Francesca, impiegata: WebcamLR ogni giorno per Zoom/Teams, vuole zero passi).
# Il telefono già fidato si ricollega senza domande: telefono chiuso e riaperto, PC «riavviato» con l'avvio con Windows
# (--avvio, come dalla chiave Run), PC prima e telefono dopo, telefono prima e PC dopo. Poi che cosa vede un'app di
# videochiamata (sul runner non c'è la webcam virtuale) e la rimozione del telefono fidato.
# Il telefono è TelefonoFinto come iPhone (protocollo dell'iPhone, non l'app iPhone vera).
# Alla fine stampa schermate (JPEG ridotti) e registri nel registro del lavoro: righe «T05FILE <nome>» … «T05FINE».

$n = 'iPhone di Francesca'

function T05-Conta([string]$Testo) { @(Registro-Telefono $n | Where-Object { $_ -like "*$Testo*" }).Count }

function T05-Attendi-Accettato([int]$Prima, [int]$Secondi, [string]$Etichetta) {
    # Secondi fino a un ACCETTATO nuovo (più di $Prima); -1 se non arriva. Annota se il telefono ha dovuto dare il codice.
    $codiciPrima = T05-Conta 'CODICE'
    $inizio = Get-Date
    while (((Get-Date) - $inizio).TotalSeconds -lt $Secondi) {
        if ((T05-Conta 'ACCETTATO') -gt $Prima) {
            $s = ((Get-Date) - $inizio).TotalSeconds
            Scrivi-Log ("T05 ${Etichetta}: ACCETTATO dopo {0:0.0} s" -f $s)
            if ((T05-Conta 'CODICE') -gt $codiciPrima) { Segnala-Problema "${Etichetta}: il telefono già fidato ha dovuto dare il codice" }
            return $s
        }
        if ((T05-Conta 'CODICE') -gt $codiciPrima) {
            Segnala-Problema "${Etichetta}: il PC chiede di nuovo il codice a un telefono già fidato"
            [void](Fotografa "$Etichetta-chiede-codice")
            return -1
        }
        Start-Sleep -Milliseconds 300
    }
    Segnala-Problema "${Etichetta}: il telefono fidato non si ricollega in $Secondi s"
    Registro-Telefono $n | Select-Object -Last 12 | ForEach-Object { Scrivi-Log "  telefono: $_" }
    [void](Fotografa "$Etichetta-non-ricollegato")
    -1
}

function T05-Nessuna-Domanda([string]$Etichetta) {
    if (Attendi-Testo (Testo-App 'Conferma_Consenti') 2) {
        Segnala-Problema "${Etichetta}: a schermo c'è «Consentire…?» per un telefono già fidato"
        [void](Fotografa "$Etichetta-domanda")
    }
}

function T05-Apri-Pagina([string]$Chiave) {
    if (-not (Esiste 'PulsanteChiudiImpostazioni')) { Clicca 'PulsanteImpostazioni'; Start-Sleep -Milliseconds 800 }
    Clicca (Testo-App $Chiave) -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
}

function T05-Chiudi-Pannello { if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' } }

function T05-Stato-Avvio([string]$Quando) {
    $valore = $null
    try { $valore = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WebcamLR' -ErrorAction Stop).WebcamLR } catch { }
    $interruttore = '?'
    $e = Trova-Elemento 'InterruttoreAvvio' -AncheNascosti
    if ($e) {
        $p = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $interruttore = $p.Current.ToggleState }
    }
    Scrivi-Log "T05 AVVIO ${Quando}: interruttore $interruttore, chiave Run «$valore»"
    $valore
}

function T05-Testi([string]$Etichetta) {
    Scrivi-Log "T05 TESTI ${Etichetta}: $((@(Testi-Visibili) | Select-Object -Unique | Select-Object -First 80) -join ' | ')"
}

function T05-Stampa {
    $cartella = Cartella-Risultati
    "PROBLEMI: $((Problemi) -join ' || ')" | Set-Content -LiteralPath (Join-Path $cartella 'problemi-t05.txt') -Encoding UTF8
    Add-Type -AssemblyName System.Drawing
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
    $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 55L
    foreach ($f in Get-ChildItem -LiteralPath $cartella -File | Sort-Object Name) {
        try {
            if ($f.Extension -eq '.png') {
                $img = [System.Drawing.Image]::FromFile($f.FullName)
                $l = [Math]::Min(1024, $img.Width); $a = [int]($img.Height * $l / $img.Width)
                $bmp = New-Object System.Drawing.Bitmap $l, $a
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.InterpolationMode = 'HighQualityBicubic'
                $g.DrawImage($img, 0, 0, $l, $a)
                $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, $codec, $parametri)
                $byte = $ms.ToArray()
                $g.Dispose(); $bmp.Dispose(); $img.Dispose()
                $nome = [IO.Path]::ChangeExtension($f.Name, '.jpg')
            } elseif ($f.Extension -eq '.log' -or $f.Name -like 'problemi-*') {
                $byte = [IO.File]::ReadAllBytes($f.FullName)
                if ($byte.Length -gt 1MB) { $byte = $byte[($byte.Length - 1MB)..($byte.Length - 1)] }
                $nome = $f.Name
            } else { continue }
            Write-Host "T05FILE $nome"
            $b64 = [Convert]::ToBase64String($byte)
            for ($i = 0; $i -lt $b64.Length; $i += 4000) { Write-Host $b64.Substring($i, [Math]::Min(4000, $b64.Length - $i)) }
            Write-Host 'T05FINE'
        } catch { Write-Host "T05ERRORE $($f.Name): $($_.Exception.Message)" }
    }
}

try {
    # ------------------------------------------------ giorno 1: primo collegamento dal QR, avvio con Windows acceso
    Passo 'Primo avvio e primo collegamento dal QR' {
        Avvia-App -Azzera | Out-Null
        Start-Sleep -Seconds 3
        Fotografa 'g1-primo-avvio'
        $global:T05Exe = (Get-Process -Name WebcamLR | Select-Object -First 1).Path
        Scrivi-Log "T05 exe: $global:T05Exe"
        Avvia-TelefonoFinto -DalQR --nome $n --identita-nuova --durata 1500 --riconnetti-sempre | Out-Null
        [void](T05-Attendi-Accettato 0 40 'g1-qr')
        Attendi-Telefono 'Video:' 20 -Nome $n | Out-Null
        Start-Sleep -Seconds 4
        Fotografa 'g1-collegato'
        T05-Testi 'g1-collegato'
    }
    Passo 'Impostazioni › Avvio: avvio con Windows acceso' {
        T05-Apri-Pagina 'Impostazioni_Avvio'
        [void](T05-Stato-Avvio 'prima')
        Fotografa 'g1-pagina-avvio'
        Clicca 'InterruttoreAvvio'
        Start-Sleep -Seconds 1
        $valore = T05-Stato-Avvio 'dopo il clic'
        if (-not $valore) { Segnala-Problema 'Avvio con Windows acceso ma la chiave Run è vuota' }
        Schermata 'g1-avvio-acceso' | Out-Null
        T05-Testi 'g1-avvio'
        T05-Chiudi-Pannello
    }
    Passo 'Impostazioni › Telefoni: il telefono fidato' {
        T05-Apri-Pagina 'Impostazioni_Telefoni'
        Fotografa 'g1-pagina-telefoni'
        T05-Testi 'g1-telefoni'
        T05-Chiudi-Pannello
    }

    # ------------------------------------------------ il telefono si chiude e si riapre (PC acceso)
    Passo 'Telefono chiuso e riaperto, PC acceso' {
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 4
        Fotografa 'g2-telefono-chiuso'
        T05-Testi 'g2-telefono-chiuso'
        $prima = T05-Conta 'ACCETTATO'
        Avvia-TelefonoFinto --nome $n --durata 1500 --riconnetti-sempre | Out-Null
        $s = T05-Attendi-Accettato $prima 30 'g2-telefono-riaperto'
        T05-Nessuna-Domanda 'g2'
        Attendi-Telefono 'Video:' 15 -Nome $n | Out-Null
        Start-Sleep -Seconds 3
        Fotografa 'g2-ricollegato'
        if ($s -ge 0 -and -not (Controlla-Video)) { Segnala-Problema 'g2: ricollegato ma il video non scorre' }
    }

    # ------------------------------------------------ il PC si «riavvia»: all'accesso parte con --avvio, il telefono è aperto
    Passo 'PC riavviato con avvio con Windows, telefono rimasto aperto' {
        $prima = T05-Conta 'ACCETTATO'
        Chiudi-App
        Start-Sleep -Seconds 5
        Scrivi-Log "T05 telefono mentre il PC è spento: $((Registro-Telefono $n | Select-Object -Last 3) -join ' / ')"
        $comando = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WebcamLR' -ErrorAction SilentlyContinue).WebcamLR
        Scrivi-Log "T05 all'accesso Windows lancerebbe: $comando"
        $inizio = Get-Date
        try { Avvia-App -Argomenti '--avvio' -Attesa 12 | Out-Null; Scrivi-Log 'T05 con --avvio la finestra È comparsa' }
        catch { Scrivi-Log "T05 con --avvio: $($_.Exception.Message) (atteso: parte nascosta)" }
        Descrivi-Finestre
        $s = T05-Attendi-Accettato $prima 40 'g3-accesso'
        Scrivi-Log ("T05 g3: dall'avvio dell'app al telefono accettato {0:0.0} s" -f ((Get-Date) - $inizio).TotalSeconds)
        Start-Sleep -Seconds 2
        Schermata 'g3-dopo-accesso-schermo' | Out-Null
        # Francesca apre WebcamLR (icona accanto all'orologio o dal menu Start): una seconda copia porta davanti la prima.
        Start-Process -FilePath $global:T05Exe -WorkingDirectory (Split-Path $global:T05Exe) | Out-Null
        Start-Sleep -Seconds 4
        Descrivi-Finestre
        Porta-Davanti
        Fotografa 'g3-finestra-aperta'
        T05-Testi 'g3-finestra'
        T05-Nessuna-Domanda 'g3'
        if ($s -ge 0 -and -not (Controlla-Video)) { Segnala-Problema 'g3: ricollegato ma il video non scorre' }
    }

    # ------------------------------------------------ mattina: PC acceso prima, telefono dopo
    Passo 'Mattina: PC riaperto prima, telefono dopo' {
        Ferma-TelefonoFinto
        Chiudi-App
        Start-Sleep -Seconds 2
        Avvia-App | Out-Null
        Start-Sleep -Seconds 3
        Fotografa 'g4-pc-senza-telefono'
        T05-Testi 'g4-pc-senza-telefono'
        $prima = T05-Conta 'ACCETTATO'
        Avvia-TelefonoFinto --nome $n --durata 1500 --riconnetti-sempre | Out-Null
        [void](T05-Attendi-Accettato $prima 30 'g4-telefono-dopo')
        T05-Nessuna-Domanda 'g4'
        Start-Sleep -Seconds 4
        Fotografa 'g4-collegato'
    }

    # ------------------------------------------------ telefono aperto prima, PC dopo
    Passo 'Telefono aperto prima, PC dopo' {
        Ferma-TelefonoFinto
        Chiudi-App
        Avvia-TelefonoFinto --nome $n --durata 1500 --riconnetti-sempre | Out-Null
        Start-Sleep -Seconds 6
        $prima = T05-Conta 'ACCETTATO'
        Avvia-App | Out-Null
        [void](T05-Attendi-Accettato $prima 40 'g5-pc-dopo')
        T05-Nessuna-Domanda 'g5'
        Start-Sleep -Seconds 4
        Fotografa 'g5-collegato'
        T05-Testi 'g5-collegato'
    }

    # ------------------------------------------------ che cosa vede un'app di videochiamata
    Passo 'Webcam per le app di videochiamata' {
        $camere = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPClass -in 'Camera', 'Image' } |
            ForEach-Object { "$($_.Name) [$($_.PNPClass)] $($_.Status)" })
        Scrivi-Log "T05 webcam che Windows offre alle app: $(if ($camere.Count) { $camere -join ' ; ' } else { 'NESSUNA' })"
        T05-Apri-Pagina 'Impostazioni_Uscite'
        Fotografa 'g6-uscite'
        T05-Testi 'g6-uscite'
        T05-Chiudi-Pannello
    }

    # ------------------------------------------------ rimozione del telefono fidato
    Passo 'Rimuovo il telefono dai fidati' {
        T05-Apri-Pagina 'Impostazioni_Telefoni'
        Clicca "Rimuovi $n"
        Start-Sleep -Milliseconds 800
        Fotografa 'g7-domanda-rimuovi'
        T05-Testi 'g7-domanda'
        Clicca 'Rimuovi'
        Start-Sleep -Seconds 2
        Fotografa 'g7-dopo-rimuovi'
        T05-Testi 'g7-dopo'
        Scrivi-Log "T05 g7: telefono ancora collegato dopo la rimozione? ultime righe: $((Registro-Telefono $n | Select-Object -Last 3) -join ' / ')"
        T05-Chiudi-Pannello
    }
    Passo 'Il telefono rimosso torna: deve chiedere il codice' {
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 2
        $codici = T05-Conta 'CODICE'
        Avvia-TelefonoFinto --nome $n --durata 120 | Out-Null
        if (Attendi-Telefono 'CODICE' 30 -Nome $n) {
            Attendi-Testo (Testo-App 'Conferma_Consenti') 10 | Out-Null
            Fotografa 'g8-chiede-codice'
            Scrivi-Log 'T05 g8: dopo la rimozione il PC chiede il codice (giusto)'
        } else {
            Segnala-Problema 'g8: dopo «Rimuovi» il telefono entra senza codice'
            Fotografa 'g8-senza-codice'
        }
    }
    Passo "Spengo l'avvio con Windows" {
        Ferma-TelefonoFinto
        T05-Apri-Pagina 'Impostazioni_Avvio'
        Clicca 'InterruttoreAvvio'
        $valore = T05-Stato-Avvio 'spento alla fine'
        if ($valore) { Segnala-Problema "Avvio con Windows spento ma la chiave Run resta: $valore" }
        T05-Chiudi-Pannello
    }
} finally {
    T05-Stampa
}
