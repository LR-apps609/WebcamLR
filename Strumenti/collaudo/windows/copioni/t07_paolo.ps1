# Collaudo t07 (Paolo, attento alla privacy) su Windows, con il telefono finto:
#  - telefoni fidati: rimuoverne uno (anche mentre è collegato) e vedere se rientra senza conferma (riconnessione,
#    nuovo avvio del telefono, app riavviata);
#  - «Segnala un bug»: cosa mostra e il testo INTERO copiato negli appunti (dati tecnici + registro);
#  - domande frequenti: privacy, dati, Google;
#  - ONNX Runtime: una sessione ETW sul fornitore di telemetria di ONNX Runtime per tutto il copione, con gli effetti
#    accesi (la sfocatura carica ONNX Runtime): quanti eventi escono? più le connessioni TCP del processo WebcamLR.
# Alla fine i risultati si stampano nel registro del lavoro con t13/stampa.ps1 (blocchi T13FILE … T13FINE).
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartella = Cartella-Risultati
$guidOrtTelemetria = '{3a26b1ff-7484-7484-7484-15261f42614d}'
$guidOrtTraccia = '{929DD115-1ECB-4CB5-B060-EBD4983C421D}'
$etl = Join-Path $cartella 'ort-telemetria.etl'
$etlTraccia = Join-Path $cartella 'ort-traccia.etl'
$fileRete = Join-Path $cartella 'rete-webcamlr.txt'
$connessioni = @{}

function T07-Rete([string]$quando) {
    $p = Get-Process -Name 'WebcamLR' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return }
    foreach ($c in @(Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue)) {
        $chiave = "TCP $($c.State) locale $($c.LocalAddress):$($c.LocalPort) remoto $($c.RemoteAddress):$($c.RemotePort)"
        if (-not $connessioni.ContainsKey($chiave)) { $connessioni[$chiave] = $quando }
    }
    foreach ($u in @(Get-NetUDPEndpoint -OwningProcess $p.Id -ErrorAction SilentlyContinue)) {
        $chiave = "UDP locale $($u.LocalAddress):$($u.LocalPort)"
        if (-not $connessioni.ContainsKey($chiave)) { $connessioni[$chiave] = $quando }
    }
}

function T07-Appunti {
    Add-Type -AssemblyName System.Windows.Forms
    try { [System.Windows.Forms.Clipboard]::GetText() } catch { "(appunti non letti: $($_.Exception.Message))" }
}

function T07-Telefoni([string]$nome) {
    Clicca 'PulsanteImpostazioni'
    Start-Sleep -Milliseconds 800
    Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
    Fotografa $nome
    Scrivi-Log "A schermo ($nome): $(Elenco-Visibili)"
}

function T07-ChiudiImpostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' } else { Tasto 'Esc' }
    Start-Sleep -Milliseconds 600
}

function T07-Rimuovi([string]$nome) {
    Clicca ((Testo-App 'Sicurezza_RimuoviNome') -f $nome)
    Start-Sleep -Seconds 1
    Fotografa "domanda-rimuovi-$($nome -replace '\W+','-')"
    Scrivi-Log "Domanda: $(Elenco-Visibili)"
    # Nel riquadro ci sono due «Rimuovi»: quello della riga e quello della domanda (l'ultimo trovato).
    $tipo = [System.Windows.Automation.ControlType]::Button
    $pulsanti = @(Tutti-Elementi | Where-Object { try { $_.Current.ControlType -eq $tipo -and $_.Current.Name -eq (Testo-App 'Rimuovi') -and -not $_.Current.IsOffscreen } catch { $false } })
    Scrivi-Log "Pulsanti «Rimuovi» semplici a schermo: $($pulsanti.Count)"
    if ($pulsanti.Count -eq 0) { throw 'non trovo «Rimuovi» nella domanda' }
    $p = $pulsanti[-1]
    $inv = $null
    if ($p.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$inv)) { $inv.Invoke() } else { Clic-Rapido $p 1 }
    Start-Sleep -Seconds 1
    Fotografa "dopo-rimuovi-$($nome -replace '\W+','-')"
    Scrivi-Log "Dopo la rimozione: $(Elenco-Visibili)"
}

function T07-Fidati {
    $f = Join-Path $env:LOCALAPPDATA 'WebcamLR'
    Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue | ForEach-Object {
        $t = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($t -match 'Fidat|fidat') { Scrivi-Log "  file $($_.Name) parla di fidati: $(($t -split "`n" | Select-String -Pattern 'idat' | Select-Object -First 3) -join ' / ')" }
    }
}

try {
    # ------------------------------------------------ ETW su ONNX Runtime prima che parta l'app
    Remove-Item -Force -ErrorAction SilentlyContinue $etl, $etlTraccia
    Scrivi-Log "logman telemetria: $(logman start t07OrtTelemetria -p $guidOrtTelemetria 0xffffffffffffffff 0xff -o $etl -ets 2>&1)"
    Scrivi-Log "logman traccia: $(logman start t07OrtTraccia -p $guidOrtTraccia 0xffffffffffffffff 0xff -o $etlTraccia -ets 2>&1)"

    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 3
    T07-Rete 'avvio'
    Fotografa 'primo-avvio'

    # ------------------------------------------------ 1. telefono dal QR, poi rimosso MENTRE è collegato
    $nome1 = 'Pixel di Paolo'
    Passo 'Telefono 1 dal QR, si ricollega da solo dopo una caduta' {
        Avvia-TelefonoFinto -DalQR --nome $nome1 --android --durata 0 --interrompi-dopo 45 --modo-interruzione chiusura --riconnetti-dopo 6 | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome $nome1 -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome $nome1 | Out-Null
        Start-Sleep -Seconds 4
        Fotografa 'telefono1-collegato'
        T07-Rete 'telefono 1 collegato'
    }
    Passo 'Impostazioni › Telefoni: lo rimuovo mentre è collegato' {
        T07-Telefoni 'telefoni-con-telefono1'
        T07-Rimuovi $nome1
        Albero-UI 'telefoni-dopo-rimozione' | Out-Null
        T07-ChiudiImpostazioni
        Start-Sleep -Seconds 2
        Fotografa 'dopo-rimozione-principale'
        Controlla-Video | Out-Null
        Ultime-Telefono $nome1 6
        T07-Fidati
    }
    Passo 'Il telefono rimosso cade e si ricollega: chiede il codice?' {
        # --interrompi-dopo 45: la connessione si chiude 45 s dopo il primo video, il telefono riprova dopo 6 s.
        $riga = Attendi-Telefono 'CODICE' 70 -Nome $nome1
        Start-Sleep -Seconds 2
        Fotografa 'telefono1-riconnessione'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Ultime-Telefono $nome1 15
        $accettati = @(Registro-Telefono $nome1 | Where-Object { $_ -like '*ACCETTATO*' }).Count
        Scrivi-Log "Telefono 1: ACCETTATO $accettati volte; CODICE: $riga"
        if (-not $riga -and $accettati -ge 2) { Segnala-Problema 'Il telefono rimosso dai fidati si è ricollegato SENZA conferma' }
        if (Trova-Elemento (Testo-App 'Conferma_NonConsentire')) {
            Fotografa 'telefono1-domanda-dopo-rimozione'
            Clicca (Testo-App 'Conferma_NonConsentire')
            Start-Sleep -Seconds 2
            Fotografa 'telefono1-non-consentito'
        }
    }
    Ferma-TelefonoFinto

    # ------------------------------------------------ 2. telefono con il codice, rimosso da fermo, poi app riavviata
    $nome2 = 'Galaxy di Paolo'
    Passo 'Telefono 2 con il codice: Consenti' {
        Avvia-TelefonoFinto --nome $nome2 --android --durata 40 | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome $nome2 -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
        Fotografa 'telefono2-domanda'
        Scrivi-Log "Domanda: $(Elenco-Visibili)"
        Clicca (Testo-App 'Conferma_Consenti')
        Attendi-Telefono 'ACCETTATO' 15 -Nome $nome2 -Obbligatorio | Out-Null
        Start-Sleep -Seconds 5
        T07-Rete 'telefono 2 collegato'
    }
    Ferma-TelefonoFinto
    Passo 'Telefono 2 fidato rientra senza codice (atteso)' {
        Avvia-TelefonoFinto --nome $nome2 --android --durata 20 | Out-Null
        $ok = Attendi-Telefono 'ACCETTATO' 20 -Nome $nome2
        $cod = @(Registro-Telefono $nome2 | Where-Object { $_ -like '*CODICE*' }).Count
        Scrivi-Log "Telefono 2 fidato: accettato «$ok», righe CODICE $cod"
    }
    Ferma-TelefonoFinto
    Passo 'Rimuovo il telefono 2 da fermo e riavvio l''app' {
        T07-Telefoni 'telefoni-con-telefono2'
        T07-Rimuovi $nome2
        T07-ChiudiImpostazioni
        T07-Fidati
        Chiudi-App
        Start-Sleep -Seconds 2
        Avvia-App | Out-Null
        Start-Sleep -Seconds 3
        T07-Telefoni 'telefoni-dopo-riavvio'
        T07-ChiudiImpostazioni
    }
    Passo 'Il telefono 2 rimosso rientra: chiede il codice?' {
        Avvia-TelefonoFinto --nome $nome2 --android --durata 40 | Out-Null
        $riga = Attendi-Telefono 'CODICE' 25 -Nome $nome2
        Start-Sleep -Seconds 1
        Fotografa 'telefono2-rientro'
        Ultime-Telefono $nome2 8
        if (-not $riga) {
            if (Attendi-Telefono 'ACCETTATO' 3 -Nome $nome2) { Segnala-Problema 'Il telefono 2 rimosso dai fidati è rientrato SENZA conferma dopo il riavvio' }
        } else {
            Clicca (Testo-App 'Conferma_Consenti')
            Attendi-Telefono 'Video:' 25 -Nome $nome2 | Out-Null
        }
    }

    # ------------------------------------------------ effetti accesi (carica ONNX Runtime)
    Passo 'Effetti: frontale e sfocatura (ONNX Runtime)' {
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        try { Clicca 'Frontale' -Dentro 'SceltaObiettivo' } catch { Scrivi-Log "frontale non scelta: $($_.Exception.Message)" }
        Start-Sleep -Seconds 3
        Clicca 'PulsanteSfondoVideo'
        Start-Sleep -Seconds 20
        Fotografa 'sfocatura'
        T07-Rete 'effetti accesi'
        $p = Get-Process -Name 'WebcamLR' -ErrorAction SilentlyContinue | Select-Object -First 1
        $moduli = @($p.Modules | Where-Object { $_.ModuleName -match 'onnx|DirectML' } | ForEach-Object { "$($_.ModuleName) $($_.FileVersionInfo.FileVersion)" })
        Scrivi-Log "Moduli ONNX/DirectML caricati in WebcamLR: $($moduli -join ', ')"
        $fornitori = (logman query providers -pid $p.Id 2>&1) -join "`n"
        $fornitori | Set-Content -LiteralPath (Join-Path $cartella 'fornitori-etw-webcamlr.txt') -Encoding UTF8
        $ha = $fornitori -match '3a26b1ff'
        Scrivi-Log "Il fornitore di telemetria ONNX Runtime $guidOrtTelemetria è registrato nel processo: $ha"
    }

    # ------------------------------------------------ Segnala un bug: il testo intero
    Passo 'Segnala un bug: il testo intero negli appunti' {
        Tasto 'F1'
        Start-Sleep -Seconds 2
        Clicca (Testo-App 'App_SegnalaBug')
        Start-Sleep -Seconds 1
        Fotografa 'segnala'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        $casella = Casella-Modifica
        Imposta-Valore $casella 'Paolo vuole sapere cosa viene inviato' | Out-Null
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'Bug_Copia')
        Start-Sleep -Seconds 2
        Fotografa 'segnala-copiata'
        $testo = T07-Appunti
        $testo | Set-Content -LiteralPath (Join-Path $cartella 'testo-segnalazione.txt') -Encoding UTF8
        Scrivi-Log "TESTO INTERO DELLA SEGNALAZIONE ($($testo.Length) caratteri):"
        $testo -split "`r?`n" | ForEach-Object { Scrivi-Log "  | $_" }
    }
    Passo 'Domande frequenti: privacy, dati, Google' {
        Clicca (Testo-App 'App_DomandeFrequenti')
        Start-Sleep -Seconds 1
        foreach ($parola in 'privacy', 'dati', 'Google', 'telemetria') {
            $casella = Casella-Modifica
            Imposta-Valore $casella $parola | Out-Null
            Start-Sleep -Seconds 1
            Fotografa "domande-$parola"
            Scrivi-Log "Domande «$parola»: $(Elenco-Visibili)"
        }
        Tasto 'Esc'
    }
    T07-Rete 'fine'
    Ferma-TelefonoFinto
} finally {
    Scrivi-Log "logman stop: $(logman stop t07OrtTelemetria -ets 2>&1) / $(logman stop t07OrtTraccia -ets 2>&1)"
    foreach ($f in @($etl, $etlTraccia)) {
        if (Test-Path $f) {
            $csv = [IO.Path]::ChangeExtension($f, '.csv')
            tracerpt $f -o $csv -of CSV -y 2>&1 | Out-Null
            $righe = if (Test-Path $csv) { @(Get-Content -LiteralPath $csv).Count } else { -1 }
            $eventi = @(Get-WinEvent -Path $f -Oldest -ErrorAction SilentlyContinue)
            Scrivi-Log "ETW $([IO.Path]::GetFileName($f)): $((Get-Item $f).Length) byte, $($eventi.Count) eventi (Get-WinEvent), $righe righe CSV"
            $eventi | Select-Object -First 15 | ForEach-Object { Scrivi-Log "  evento $($_.Id) $($_.ProviderName) $($_.TaskDisplayName) $($_.Message)" }
            if (Test-Path $csv) { Get-Content -LiteralPath $csv | Select-Object -First 25 | ForEach-Object { Scrivi-Log "  csv: $_" }; Rename-Item -LiteralPath $csv -NewName ([IO.Path]::GetFileName($csv) + '.txt') -ErrorAction SilentlyContinue }
            Remove-Item -Force -ErrorAction SilentlyContinue $f
        }
    }
    $connessioni.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)  (visto: $($_.Value))" } | Set-Content -LiteralPath $fileRete -Encoding UTF8
    Scrivi-Log "Connessioni di WebcamLR.exe viste:"
    Get-Content -LiteralPath $fileRete -ErrorAction SilentlyContinue | ForEach-Object { Scrivi-Log "  $_" }
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartella
}
