# Collaudo t03 (Davide, streamer con OBS): qualità Massima, 1080p e 4K a 60 fps dal telefono finto (che simula il
# protocollo dell'iPhone, non l'app iPhone vera). Cosa promette il menu della qualità e cosa arriva, chip e numeri,
# formato mostrato, Impostazioni › Qualità e › Uscite, schermo intero e vista pulita, registrazione e foto dal PC con
# misura, fps e codec dei file. Alla fine schermate e registri nel registro del lavoro (t13/stampa.ps1).

$cartellaT03 = Cartella-Risultati

function Nome-Di([string]$Id) {
    $e = Trova-Elemento $Id -AncheNascosti
    if ($e) { try { return $e.Current.Name } catch { } }
    '(non trovato)'
}
function Nomi-Dentro([string]$Id) {
    $c = Trova-Elemento $Id -AncheNascosti
    if (-not $c) { return @('(contenitore non trovato)') }
    @(Tutti-Elementi -Dentro $c | ForEach-Object { try { $_.Current.Name } catch { } } | Where-Object { $_ })
}
function Chip([string]$Etichetta) {
    Passo "Chip sul video ($Etichetta)" {
        Scrivi-Log "  CHIP[$Etichetta] TestoQualita=«$(Nome-Di 'TestoQualita')» TestoFormatoVideo=«$(Nome-Di 'TestoFormatoVideo')» ChipQualita=«$(Nome-Di 'ChipQualita')» TestoCollegamento=«$(Nome-Di 'TestoCollegamento')»"
        if (Esiste 'ChipVideo') { Schermata-Elemento 'ChipVideo' "chip-$Etichetta" -Margine 20 | Out-Null }
        else { Scrivi-Log "  CHIP[$Etichetta] ChipVideo non è a schermo" }
    }
}
function Menu-Qualita([string]$Etichetta) {
    Passo "Menu della qualità ($Etichetta)" {
        Clicca 'ChipQualita'
        Start-Sleep -Milliseconds 1200
        Schermata "menu-$Etichetta" | Out-Null
        foreach ($id in 'ElencoQualita', 'ElencoLivelli') { Scrivi-Log "  MENU[$Etichetta] ${id}: $((Nomi-Dentro $id) -join ' | ')" }
        foreach ($id in 'NotaQualitaPro', 'TestoQualitaArriva', 'NotaScendere') { Scrivi-Log "  MENU[$Etichetta] ${id}=«$(Nome-Di $id)»" }
        foreach ($r in ((Nome-Di 'TestoNumeri') -split "`n")) { Scrivi-Log "  NUMERI[$Etichetta] $r" }
        Tasto 'Esc'
        Start-Sleep -Milliseconds 500
    }
}
function Scegli-Livello([string]$Livello) {
    Passo "Scelgo «$Livello» nel menu della qualità" {
        Clicca 'ChipQualita'
        Start-Sleep -Milliseconds 1200
        Clicca $Livello -Dentro 'ElencoLivelli'
        Start-Sleep -Seconds 2
        if (Trova-Elemento 'ChipQualita') { } # il menu si chiude da solo
        Schermata "dopo-$Livello" | Out-Null
        Tasto 'Esc'
    }
}
function Ultime-Telefono([string]$Etichetta, [int]$Righe = 12) {
    foreach ($r in @(Registro-Telefono $Etichetta | Select-Object -Last $Righe)) { Scrivi-Log "  TELEFONO: $r" }
}
function Registro-PC([string]$Etichetta) {
    Passo "Registro del collegamento ($Etichetta)" {
        Clicca 'PulsanteRegistro'
        Start-Sleep -Seconds 1
        Schermata "registro-$Etichetta" | Out-Null
        $e = Trova-Elemento 'TestoRegistro' -AncheNascosti
        if ($e) { foreach ($r in ($e.Current.Name -split "`n")) { Scrivi-Log "  REGISTRO-PC: $r" } }
        Tasto 'Esc'
    }
}
function Pagina-Impostazioni([string]$Voce) {
    $nome = Testo-App "Impostazioni_$Voce"
    Passo "Impostazioni › $nome" {
        if (-not (Trova-Elemento 'ScorrimentoImpostazioni')) { Clicca 'PulsanteImpostazioni'; Start-Sleep -Milliseconds 800 }
        if (Trova-Elemento 'PulsanteIndietroImpostazioni') { Clicca 'PulsanteIndietroImpostazioni'; Start-Sleep -Milliseconds 600 }
        Clicca $nome -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Seconds 1
        Schermata "impostazioni-$Voce" | Out-Null
        $pagina = Trova-Elemento 'ContenutoPagina' -AncheNascosti
        if ($pagina) { Scrivi-Log "  PAGINA[$Voce]: $((Nomi-Dentro 'ContenutoPagina' | Select-Object -Unique) -join ' | ')" }
        if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' } else { Tasto 'Esc' }
        Start-Sleep -Milliseconds 600
    }
}

# ---- lettura dei file salvati (MP4: tkhd, mdhd, stsz; PNG: IHDR)
function U32([byte[]]$b, [long]$i) { ([long]$b[$i] -shl 24) + ([long]$b[$i + 1] -shl 16) + ([long]$b[$i + 2] -shl 8) + [long]$b[$i + 3] }
function Descrivi-Mp4([string]$File) {
    $b = [IO.File]::ReadAllBytes($File)
    $s = [Text.Encoding]::GetEncoding(28591).GetString($b)
    $codec = if ($s.Contains('hvc1') -or $s.Contains('hev1')) { 'HEVC' } elseif ($s.Contains('avc1')) { 'H.264' } else { '?' }
    $testo = "$([IO.Path]::GetFileName($File)): $([math]::Round($b.Length / 1MB, 2)) MB, codec $codec"
    if ($s.Contains('moof')) { $testo += ', frammentato (moof)' }
    $p = $s.IndexOf('tkhd', [StringComparison]::Ordinal)
    if ($p -ge 4) {
        $inizio = $p - 4; $misura = U32 $b $inizio
        $testo += ", tkhd $([int]((U32 $b ($inizio + $misura - 8)) / 65536))x$([int]((U32 $b ($inizio + $misura - 4)) / 65536))"
    }
    $q = $s.IndexOf('mdhd', [StringComparison]::Ordinal)
    $secondi = 0
    if ($q -ge 0) {
        if ($b[$q + 4] -eq 0) { $scala = U32 $b ($q + 16); $durata = U32 $b ($q + 20) }
        else { $scala = U32 $b ($q + 24); $durata = (U32 $b ($q + 28)) * 4294967296 + (U32 $b ($q + 32)) }
        if ($scala -gt 0) { $secondi = $durata / $scala; $testo += ", durata $([math]::Round($secondi, 2)) s" }
    }
    $r = $s.IndexOf('stsz', [StringComparison]::Ordinal)
    if ($r -ge 0) {
        $campioni = U32 $b ($r + 12)
        $testo += ", $campioni fotogrammi"
        if ($secondi -gt 0) { $testo += " (= $([math]::Round($campioni / $secondi, 1)) fps)" }
    }
    if ($secondi -gt 0) { $testo += ", $([math]::Round($b.Length * 8 / $secondi / 1000000, 1)) Mbit/s" }
    $testo
}
function Descrivi-Png([string]$File) {
    $b = New-Object byte[] 24
    $f = [IO.File]::OpenRead($File); [void]$f.Read($b, 0, 24); $f.Close()
    "$([IO.Path]::GetFileName($File)): $([math]::Round((Get-Item $File).Length / 1MB, 2)) MB, $(U32 $b 16)x$(U32 $b 20)"
}
function File-Salvati([string]$Etichetta) {
    Passo "File salvati ($Etichetta)" {
        $video = Join-Path ([Environment]::GetFolderPath('MyVideos')) 'WebcamLR'
        $foto = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'WebcamLR'
        foreach ($f in @(Get-ChildItem -LiteralPath $video -Filter '*.mp4' -File -ErrorAction SilentlyContinue)) {
            if (-not $script:visti.Contains($f.FullName)) { [void]$script:visti.Add($f.FullName); Scrivi-Log "  FILE[$Etichetta] $(Descrivi-Mp4 $f.FullName)" }
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $foto -Filter '*.png' -File -ErrorAction SilentlyContinue)) {
            if (-not $script:visti.Contains($f.FullName)) { [void]$script:visti.Add($f.FullName); Scrivi-Log "  FILE[$Etichetta] $(Descrivi-Png $f.FullName)" }
        }
        Scrivi-Log "  cartelle: $video ($(Test-Path $video)), $foto ($(Test-Path $foto))"
    }
}
$script:visti = New-Object 'System.Collections.Generic.HashSet[string]'

function Registra-E-Foto([string]$Etichetta) {
    Passo "Registrazione di 10 s ($Etichetta)" {
        Clicca 'PulsanteRegistra'
        Start-Sleep -Seconds 4
        Schermata "registrazione-in-corso-$Etichetta" | Out-Null
        Scrivi-Log "  REG[$Etichetta] StatoRegistra=«$(Nome-Di 'StatoRegistra')» TestoRegistra=«$(Nome-Di 'TestoRegistra')» BarraTally=«$(Nome-Di 'BarraTally')»"
        Start-Sleep -Seconds 6
        Clicca 'PulsanteRegistra'
        Start-Sleep -Seconds 3
        Schermata "registrazione-salvata-$Etichetta" | Out-Null
        Scrivi-Log "  REG[$Etichetta] avviso: «$(Nome-Di 'TestoAvvisoRiprese')» barra: $((Nomi-Dentro 'BarraRiprese') -join ' | ')"
    }
    Passo "Foto dal PC ($Etichetta)" {
        Clicca 'PulsanteFoto'
        Start-Sleep -Seconds 1
        Schermata "foto-conto-$Etichetta" | Out-Null
        Start-Sleep -Seconds 4
        Schermata "foto-salvata-$Etichetta" | Out-Null
        Scrivi-Log "  FOTO[$Etichetta] barra: $((Nomi-Dentro 'BarraRiprese') -join ' | ')"
    }
    File-Salvati $Etichetta
}
function Viste([string]$Etichetta) {
    Passo "Schermo intero F11 ($Etichetta)" {
        Tasto 'F11'
        Start-Sleep -Seconds 2
        Schermata "schermo-intero-$Etichetta" | Out-Null
        Scrivi-Log "  F11[$Etichetta] a schermo: $(Elenco-Visibili)"
        Tasto 'Esc'
        Start-Sleep -Seconds 1
        Schermata "dopo-esc-$Etichetta" | Out-Null
    }
    Passo "Vista pulita Ctrl+Maiusc+P ($Etichetta)" {
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 2
        Schermata "vista-pulita-$Etichetta" | Out-Null
        Scrivi-Log "  PULITA[$Etichetta] a schermo: $(Elenco-Visibili)"
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 1
    }
}
function Collega([string]$Etichetta, [string[]]$Opzioni) {
    $ok = Passo "Collego «$Etichetta» ($($Opzioni -join ' '))" {
        Avvia-TelefonoFinto -DalQR --nome $Etichetta @Opzioni | Out-Null
        Attendi-Telefono 'ACCETTATO' 40 -Nome $Etichetta -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 40 -Nome $Etichetta -Obbligatorio | Out-Null
    } -Esito
    if (-not $ok) {
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 3
        $ok = Passo "Collego «$Etichetta» senza QR" {
            Avvia-TelefonoFinto --nome $Etichetta @Opzioni | Out-Null
            Attendi-Telefono 'ACCETTATO' 40 -Nome $Etichetta -Obbligatorio | Out-Null
            Attendi-Telefono 'Video:' 40 -Nome $Etichetta -Obbligatorio | Out-Null
        } -Esito
    }
    $ok
}

try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 4
    Schermata 'primo-avvio' | Out-Null

    # ---- 0: un iPhone senza Pro (720p, segue le richieste): cosa promette il menu
    $gratis = 'iPhone gratis di Davide'
    if (Collega $gratis @('--durata', '120', '--identita-nuova')) {
        Start-Sleep -Seconds 8
        Chip 'gratis'
        Menu-Qualita 'gratis'
        Ultime-Telefono $gratis 6
    }
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 5

    # ---- 1: iPhone Pro, 1080p a 60 fps (formato fisso: il finto non segue le richieste del PC)
    $davide = 'iPhone di Davide'
    if (Collega $davide @('--pro', '--risoluzione', '1920x1080', '--fps', '60', '--durata', '400', '--identita-nuova')) {
        Start-Sleep -Seconds 10
        Schermata 'pro-1080-10s' | Out-Null
        Controlla-Video | Out-Null
        Chip 'pro-1080'
        Menu-Qualita 'pro-1080'
        Scegli-Livello 'Massima'
        Start-Sleep -Seconds 5
        Ultime-Telefono $davide 10
        Chip 'pro-1080-massima'
        Menu-Qualita 'pro-1080-massima'
        Pagina-Impostazioni 'Qualita'
        Pagina-Impostazioni 'Uscite'
        Registra-E-Foto 'pro-1080'
        Viste 'pro-1080'
        Registro-PC 'pro-1080'
    }
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 5

    # ---- 2: iPhone Pro, 4K a 60 fps (H.264 I_PCM: circa 12 MB a fotogramma, pesante anche su loopback)
    $davide4k = 'iPhone 4K di Davide'
    if (Collega $davide4k @('--pro', '--risoluzione', '3840x2160', '--fps', '60', '--durata', '400', '--identita-nuova')) {
        Start-Sleep -Seconds 12
        Schermata 'pro-4k-12s' | Out-Null
        Controlla-Video | Out-Null
        Chip 'pro-4k'
        Menu-Qualita 'pro-4k'
        Ultime-Telefono $davide4k 10
        Start-Sleep -Seconds 10
        Chip 'pro-4k-22s'
        Menu-Qualita 'pro-4k-22s'
        Registra-E-Foto 'pro-4k'
        Viste 'pro-4k'
        Scegli-Livello 'Alta'
        Start-Sleep -Seconds 5
        Chip 'pro-4k-alta'
        Menu-Qualita 'pro-4k-alta'
        Ultime-Telefono $davide4k 10
        Registro-PC 'pro-4k'
    }
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 3
    Schermata 'fine' | Out-Null
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT03
}
