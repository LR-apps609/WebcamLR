# Collaudo t17 (Chiara, podcaster): il microfono del telefono come microfono del PC. Impostazioni › Microfono senza
# telefono, con un telefono senza microfono, con un telefono che manda audio (TelefonoFinto --audio: AAC-LC vero da
# tono.aac), acceso e spento dall'app e «dal telefono», rete che cade, riavvio dell'app, Pro e gratis, inglese.
# I risultati si stampano nel registro del lavoro (t13/stampa.ps1) perché gli artifact non si scaricano da questa rete.
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartella = Cartella-Risultati

function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}
function Apri-Pagina([string]$Voce) {
    Apri-Impostazioni
    if (Trova-Elemento 'PulsanteIndietroImpostazioni') { Clicca 'PulsanteIndietroImpostazioni'; Start-Sleep -Milliseconds 500 }
    Clicca (Testo-App "Impostazioni_$Voce") -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Milliseconds 900
}
function Stato-Interruttore {
    $e = Trova-Elemento 'InterruttoreMicrofono' -AncheNascosti
    if (-not $e) { return 'interruttore assente' }
    $tp = $null
    $acceso = if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) { $tp.Current.ToggleState } else { '?' }
    "interruttore $acceso, abilitato $($e.Current.IsEnabled), a schermo $(-not $e.Current.IsOffscreen)"
}
function Leggi-Microfono([string]$Quando) {
    # Cosa dice la riga del microfono adesso: stato, nota, interruttore, uscite, link. Restituisce la nota.
    $stato = (Trova-Elemento 'StatoMicrofonoTesto' -AncheNascosti)
    $nota = (Trova-Elemento 'NotaMicrofono' -AncheNascosti)
    $guida = (Trova-Elemento 'GuidaMicrofono' -AncheNascosti)
    $scelta = (Trova-Elemento 'SceltaUscitaMicrofono' -AncheNascosti)
    $testoNota = if ($nota -and -not $nota.Current.IsOffscreen) { $nota.Current.Name } else { '(nessuna nota a schermo)' }
    Scrivi-Log "MICROFONO [$Quando] stato «$(if ($stato) { $stato.Current.Name })» · nota «$testoNota» · $(Stato-Interruttore)"
    if ($scelta) {
        $vp = $null
        $valore = if ($scelta.TryGetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern, [ref]$vp)) { ($vp.Current.GetSelection() | ForEach-Object { $_.Current.Name }) -join ',' } else { $scelta.Current.Name }
        Scrivi-Log "MICROFONO [$Quando] uscita «$valore» (abilitata $($scelta.Current.IsEnabled), a schermo $(-not $scelta.Current.IsOffscreen))"
    }
    if ($guida) { Scrivi-Log "MICROFONO [$Quando] link «$($guida.Current.Name)» a schermo $(-not $guida.Current.IsOffscreen) · help «$($guida.Current.HelpText)»" }
    $testoNota
}
function Riga-Microfono([string]$Nome) {
    try { Schermata-Elemento 'RigaMicrofono' "riga-$Nome" | Out-Null } catch { Scrivi-Log "  riga del microfono non fotografabile: $($_.Exception.Message)" }
}

try {
    Passo 'Il runner ha delle uscite audio?' {
        Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue | ForEach-Object { Scrivi-Log "  scheda audio: $($_.Name) ($($_.Status))" }
        Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | ForEach-Object { Scrivi-Log "  uscita/ingresso audio: $($_.FriendlyName) ($($_.Status))" }
        Scrivi-Log "  servizio Audiosrv: $((Get-Service Audiosrv -ErrorAction SilentlyContinue).Status)"
    }

    # ------------------------------------------------ 1. nessun telefono
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 4
    Passo '1 · Impostazioni › Microfono senza telefono' {
        Apri-Pagina 'Microfono'
        Fotografa '01-microfono-senza-telefono'
        Riga-Microfono '01-senza-telefono'
        $nota = Leggi-Microfono 'senza telefono'
        if ($nota -notlike '*Collega*') { Segnala-Problema "Senza telefono la nota del microfono non dice di collegarne uno: «$nota»" }
        Clicca 'InterruttoreMicrofono'
        Leggi-Microfono 'senza telefono, dopo un clic sull''interruttore' | Out-Null
        Clicca 'SceltaUscitaMicrofono'
        Start-Sleep -Milliseconds 700
        Fotografa '01b-tendina-uscite'
        Tasto 'Esc'
    }

    # ------------------------------------------------ 2. telefono senza microfono (permesso negato), gratis
    Passo '2 · Telefono senza microfono' {
        Chiudi-Impostazioni
        Avvia-TelefonoFinto -DalQR --nome 'iPhone senza microfono' --durata 400 --microfono-negato | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone senza microfono' -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone senza microfono' | Out-Null
        Start-Sleep -Seconds 2
        Apri-Pagina 'Microfono'
        Fotografa '02-microfono-telefono-senza-microfono'
        Riga-Microfono '02-telefono-senza-microfono'
        $nota = Leggi-Microfono 'telefono senza microfono'
        Clicca 'InterruttoreMicrofono'
        Start-Sleep -Seconds 1
        Leggi-Microfono 'telefono senza microfono, dopo un clic' | Out-Null
        Ultime-Telefono 'iPhone senza microfono' 6
        Ferma-TelefonoFinto 'iPhone senza microfono'
        Start-Sleep -Seconds 3
        Leggi-Microfono 'telefono senza microfono andato via' | Out-Null
    }

    # ------------------------------------------------ 3. telefono con il microfono, gratis: accendo dall'app
    Passo '3 · Telefono con il microfono (gratis): interruttore spento' {
        Chiudi-Impostazioni
        Avvia-TelefonoFinto -DalQR --nome 'iPhone di Chiara' --durata 500 --audio --riconnetti-sempre | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Chiara' -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Chiara' | Out-Null
        Start-Sleep -Seconds 2
        Apri-Pagina 'Microfono'
        Fotografa '03-microfono-pronto-spento'
        Riga-Microfono '03-pronto-spento'
        Leggi-Microfono 'telefono con microfono, spento' | Out-Null
    }
    Passo '3 · Accendo il microfono dall''app' {
        $inizio = Get-Date
        Clicca 'InterruttoreMicrofono'
        Leggi-Microfono 'appena acceso' | Out-Null
        Riga-Microfono '03b-appena-acceso'
        $riga = Attendi-Telefono 'MICROFONO acceso' 10 -Nome 'iPhone di Chiara'
        if (-not $riga) { Segnala-Problema "Acceso l'interruttore, il telefono non riceve «comando audio vero»" }
        Attendi-Telefono 'Audio: 1 pacchetti' 10 -Nome 'iPhone di Chiara' | Out-Null
        # Quanto ci mette la nota a lasciare «In attesa dell'audio…».
        $limite = (Get-Date).AddSeconds(10)
        do {
            $nota = (Trova-Elemento 'NotaMicrofono' -AncheNascosti)
            $testo = if ($nota -and -not $nota.Current.IsOffscreen) { $nota.Current.Name } else { '' }
            if ($testo -notlike '*attesa*') { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $limite)
        Scrivi-Log "MICROFONO: dopo $([int]((Get-Date) - $inizio).TotalMilliseconds) ms la nota è «$testo»"
        Start-Sleep -Seconds 3
        Fotografa '03c-microfono-acceso'
        Riga-Microfono '03c-acceso'
        foreach ($i in 1..4) { Start-Sleep -Milliseconds 700; Riga-Microfono "03d-livello-$i" }
        Leggi-Microfono 'acceso da 4 s' | Out-Null
        Ultime-Telefono 'iPhone di Chiara' 6
    }
    Passo '3 · Pagina Uscite e vista Completo con il microfono acceso' {
        Apri-Pagina 'Uscite'
        Fotografa '03e-pagina-uscite'
        Leggi-Microfono 'pagina Uscite' | Out-Null
        Chiudi-Impostazioni
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        Fotografa '03f-completo'
        Leggi-Microfono 'vista Completo' | Out-Null
        Riga-Microfono '03f-completo'
    }
    Passo '3 · Spengo il microfono dall''app' {
        Apri-Pagina 'Microfono'
        Clicca 'InterruttoreMicrofono'
        $riga = Attendi-Telefono 'MICROFONO spento dal computer' 10 -Nome 'iPhone di Chiara'
        if (-not $riga) { Segnala-Problema "Spento l'interruttore, il telefono non riceve «comando audio falso»" }
        Start-Sleep -Seconds 2
        Fotografa '03g-microfono-spento'
        Riga-Microfono '03g-spento'
        Leggi-Microfono 'spento dall''app' | Out-Null
    }
    Passo '3 · Riaccendo, poi la rete cade per 12 s' {
        Clicca 'InterruttoreMicrofono'
        Attendi-Telefono 'Audio:' 10 -Nome 'iPhone di Chiara' | Out-Null
        Start-Sleep -Seconds 2
        Rete-Spenta 'iPhone di Chiara'
        Start-Sleep -Seconds 4
        Fotografa '03h-rete-caduta-4s'
        Leggi-Microfono 'rete caduta da 4 s' | Out-Null
        Start-Sleep -Seconds 8
        Leggi-Microfono 'rete caduta da 12 s' | Out-Null
        Riga-Microfono '03h-rete-caduta-12s'
        Rete-Accesa 'iPhone di Chiara'
        Start-Sleep -Seconds 12
        Fotografa '03i-rete-tornata'
        Leggi-Microfono 'rete tornata da 12 s' | Out-Null
        Riga-Microfono '03i-rete-tornata'
        Ultime-Telefono 'iPhone di Chiara' 12
    }

    # ------------------------------------------------ 4. riavvio: la scelta resta? il microfono riparte da solo?
    Passo '4 · Riavvio dell''app con il microfono acceso' {
        Ferma-TelefonoFinto 'iPhone di Chiara'
        Chiudi-App
        Start-Sleep -Seconds 1
        Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WebcamLR') -File -Filter 'microfono*' -ErrorAction SilentlyContinue |
            ForEach-Object { Scrivi-Log "  preferenza $($_.Name) = «$(Get-Content -LiteralPath $_.FullName -Raw)»" }
        Avvia-App | Out-Null
        Start-Sleep -Seconds 3
        Apri-Pagina 'Microfono'
        Leggi-Microfono 'riavvio, senza telefono' | Out-Null
        Chiudi-Impostazioni
        # Già fidato: entra senza QR. Questa volta con WebcamLR Pro, per vedere se cambia qualcosa.
        Avvia-TelefonoFinto --nome 'iPhone di Chiara' --durata 300 --audio --pro | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Chiara' -Obbligatorio | Out-Null
        $riga = Attendi-Telefono 'MICROFONO acceso' 15 -Nome 'iPhone di Chiara'
        if (-not $riga) { Segnala-Problema "Dopo il riavvio con il microfono acceso, il PC non chiede l'audio al telefono che torna" }
        Start-Sleep -Seconds 4
        Apri-Pagina 'Microfono'
        Fotografa '04-riavvio-pro'
        Riga-Microfono '04-riavvio-pro'
        Leggi-Microfono 'riavvio, telefono Pro tornato' | Out-Null
        Ferma-TelefonoFinto 'iPhone di Chiara'
    }

    # ------------------------------------------------ 5. il microfono spento dal telefono
    Passo '5 · Microfono spento dal telefono dopo 8 s' {
        Chiudi-Impostazioni
        Avvia-TelefonoFinto --nome 'iPhone di Chiara' --durata 200 --audio --microfono-spento-dopo 8 | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Chiara' -Obbligatorio | Out-Null
        Attendi-Telefono 'MICROFONO acceso' 15 -Nome 'iPhone di Chiara' | Out-Null
        Apri-Pagina 'Microfono'
        Leggi-Microfono 'prima dello spegnimento dal telefono' | Out-Null
        $riga = Attendi-Telefono 'MICROFONO spento dal telefono' 20 -Nome 'iPhone di Chiara'
        Start-Sleep -Seconds 3
        Fotografa '05-spento-dal-telefono'
        Riga-Microfono '05-spento-dal-telefono'
        $stato = Stato-Interruttore
        Leggi-Microfono 'spento dal telefono' | Out-Null
        if ($riga -and $stato -like '*interruttore On*') { Segnala-Problema "Il telefono ha spento il microfono ma l'interruttore sul PC resta acceso" }
        Ferma-TelefonoFinto 'iPhone di Chiara'
    }

    # ------------------------------------------------ 6. il registro dell'app
    Passo '6 · Registro dell''app' {
        Apri-Pagina 'Registro'
        Start-Sleep -Seconds 1
        Fotografa '06-registro'
    }

    # ------------------------------------------------ 7. inglese
    Passo '7 · Inglese: Impostazioni › Microphone' {
        Chiudi-Impostazioni
        Lingua-Inglese -Riavvia
        Start-Sleep -Seconds 3
        Apri-Pagina 'Microfono'
        Fotografa '07-inglese-senza-telefono'
        Leggi-Microfono 'inglese, senza telefono' | Out-Null
        Chiudi-Impostazioni
        Avvia-TelefonoFinto --nome 'iPhone di Chiara' --durata 120 --audio | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Chiara' | Out-Null
        Start-Sleep -Seconds 5
        Apri-Pagina 'Microfono'
        Fotografa '07b-inglese-con-telefono'
        Riga-Microfono '07b-inglese'
        Leggi-Microfono 'inglese, telefono con microfono' | Out-Null
        Ferma-TelefonoFinto 'iPhone di Chiara'
    }
} finally {
    try {
        $dati = Join-Path $env:LOCALAPPDATA 'WebcamLR'
        Get-ChildItem -LiteralPath $dati -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'microfono*' -or $_.Name -eq 'Errori.txt' } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cartella "dati-$($_.Name).txt") -Force }
    } catch { }
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartella
}
