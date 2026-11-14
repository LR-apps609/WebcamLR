# Collaudo t03 (Davide), seconda parte: vista Completo, registro, viste pulite dopo qualche secondo, OBS e NDI,
# cambio di qualità durante la registrazione, fotogrammi dei file. Prima parte (funzioni comuni copiate da t03_davide.ps1):
# qualità Massima, 1080p e 4K a 60 fps dal telefono finto (che simula il
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
    $campioniFrammenti = 0; $frammenti = 0; $k = 0
    while (($k = $s.IndexOf('trun', $k, [StringComparison]::Ordinal)) -ge 0) { $campioniFrammenti += U32 $b ($k + 8); $frammenti++; $k += 4 }
    if ($frammenti -gt 0) { $testo += ", $frammenti frammenti con $campioniFrammenti fotogrammi" }
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


function Stato-Elemento([string]$Id) {
    $e = Trova-Elemento $Id -AncheNascosti
    if (-not $e) { return "$Id non trovato" }
    $c = $e.Current
    "$Id «$($c.Name)» abilitato=$($c.IsEnabled) fuori=$($c.IsOffscreen) aiuto=«$($c.HelpText)» $(Descrivi-Rettangolo $c.BoundingRectangle)"
}
function Viste-Lente([string]$Etichetta) {
    Passo "Schermo intero F11, 2 s e 8 s ($Etichetta)" {
        Tasto 'F11'
        Start-Sleep -Seconds 2
        Schermata "f11-2s-$Etichetta" | Out-Null
        Start-Sleep -Seconds 6
        Schermata "f11-8s-$Etichetta" | Out-Null
        Scrivi-Log "  F11-8s[$Etichetta] $(Stato-Elemento 'PulsanteTornaFinestra')"
        Tasto 'Esc'
        Start-Sleep -Seconds 1
    }
    Passo "Vista pulita, 2 s e 8 s ($Etichetta)" {
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 2
        Schermata "pulita-2s-$Etichetta" | Out-Null
        Start-Sleep -Seconds 6
        Schermata "pulita-8s-$Etichetta" | Out-Null
        Scrivi-Log "  PULITA-8s[$Etichetta] $(Stato-Elemento 'PulsanteTornaFinestra')"
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 1
    }
}

try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 4

    $davide = 'iPhone di Davide'
    if (Collega $davide @('--pro', '--risoluzione', '1920x1080', '--fps', '60', '--durata', '500', '--identita-nuova')) {
        Start-Sleep -Seconds 6
        Passo 'Vista Completo (Ctrl+2)' {
            Tasto 'Ctrl+2'
            Start-Sleep -Seconds 2
            Schermata 'completo-1080' | Out-Null
            foreach ($id in 'PulsanteSpecchia', 'PulsanteSfondoVideo', 'PulsanteRegistro', 'SezioneUscite', 'StatoWebcamTesto', 'DescrizioneWebcam') { Scrivi-Log "  STATO $(Stato-Elemento $id)" }
        }
        Scegli-Livello 'Massima'
        Start-Sleep -Seconds 3
        Passo 'Menu con la finestra ingrandita' {
            Ingrandisci-Finestra
            Start-Sleep -Seconds 1
            Clicca 'ChipQualita'
            Start-Sleep -Milliseconds 1200
            Schermata 'menu-ingrandita-1080' | Out-Null
            Scrivi-Log "  $(Stato-Elemento 'TestoNumeri')"
            Scrivi-Log "  $(Stato-Elemento 'FinestraNumeri')"
            Scrivi-Log "  $(Stato-Elemento 'ContenutoQualita')"
            Tasto 'Esc'
            Start-Sleep -Milliseconds 500
        }
        Viste-Lente '1080'
        Passo 'Uscite: «Come usarlo nelle chiamate e in OBS» e NDI' {
            Clicca 'PulsanteImpostazioni'
            Start-Sleep -Milliseconds 800
            Clicca (Testo-App 'Impostazioni_Uscite') -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Seconds 1
            Clicca 'Come usarlo nelle chiamate e in OBS'
            Start-Sleep -Seconds 2
            Schermata 'guida-obs' | Out-Null
            Scrivi-Log "  GUIDA-OBS: $((Testi-Visibili | Select-Object -Unique) -join ' | ')"
            Tasto 'Esc'
            Start-Sleep -Seconds 1
        }
        Passo 'Uscita NDI' {
            if (-not (Trova-Elemento 'ScorrimentoImpostazioni')) {
                Clicca 'PulsanteImpostazioni'; Start-Sleep -Milliseconds 800
                Clicca (Testo-App 'Impostazioni_Uscite') -Dentro 'ScorrimentoImpostazioni'; Start-Sleep -Seconds 1
            }
            Scrivi-Log "  $(Stato-Elemento 'UscitaNDI')"
            Clicca 'IN ARRIVO' -Mouse
            Start-Sleep -Seconds 1
            Schermata 'ndi' | Out-Null
            if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' } else { Tasto 'Esc' }
        }
        Registro-PC '1080'
    }
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 5

    $davide4k = 'iPhone 4K di Davide'
    if (Collega $davide4k @('--pro', '--risoluzione', '3840x2160', '--fps', '60', '--durata', '500', '--identita-nuova')) {
        Start-Sleep -Seconds 10
        Chip '4k'
        Passo 'Registrazione e cambio di qualità a metà' {
            Clicca 'PulsanteRegistra'
            Start-Sleep -Seconds 4
            Clicca 'ChipQualita'
            Start-Sleep -Milliseconds 1200
            Clicca 'Alta' -Dentro 'ElencoLivelli'
            Start-Sleep -Seconds 2
            Schermata 'cambio-durante-registrazione' | Out-Null
            Scrivi-Log "  DIALOGO: $((Testi-Visibili | Select-Object -Unique) -join ' | ')"
            Tasto 'Esc'
            Start-Sleep -Seconds 1
            Schermata 'dopo-annulla' | Out-Null
            Start-Sleep -Seconds 4
            Clicca 'PulsanteRegistra'
            Start-Sleep -Seconds 3
        }
        File-Salvati '4k'
        Passo 'Registro del collegamento (pagina nelle impostazioni)' {
            Clicca 'PulsanteImpostazioni'
            Start-Sleep -Milliseconds 800
            Clicca (Testo-App 'Impostazioni_Registro') -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Seconds 1
            Schermata 'impostazioni-registro' | Out-Null
            $e = Trova-Elemento 'TestoRegistro' -AncheNascosti
            if ($e) { foreach ($r in ($e.Current.Name -split "`n")) { Scrivi-Log "  REGISTRO-PC: $r" } }
            else { Scrivi-Log "  PAGINA-REGISTRO: $((Nomi-Dentro 'ContenutoPagina') -join ' | ')" }
            if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
        }
        Registro-PC '4k'
        Ultime-Telefono $davide4k 14
    }
    Ferma-TelefonoFinto
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT03
}
