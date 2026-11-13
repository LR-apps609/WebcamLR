# Correzioni del collaudo 20 (t02 B4, banco): l'uscita con «--esci» dopo la X e la riapertura, con e senza
# l'aggiramento di HighContrastChanged del banco. Dopo ogni uscita il codice e gli eventi di Windows (Application Error,
# .NET Runtime, Windows Error Reporting). Schermate e registri nel registro del lavoro (t13/stampa.ps1).

function Eventi-Uscita([datetime]$Da) {
    try {
        $eventi = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $Da } -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -in 'Application Error', '.NET Runtime', 'Windows Error Reporting', 'Application Hang' }
        foreach ($e in $eventi) {
            Scrivi-Log "  EVENTO $($e.TimeCreated.ToString('HH:mm:ss')) $($e.ProviderName) $($e.Id):"
            ($e.Message -split "`r?`n") | Select-Object -First 40 | ForEach-Object { Scrivi-Log "    $_" }
        }
        if (-not $eventi) { Scrivi-Log '  nessun evento di errore nel registro Application' }
    } catch { Scrivi-Log "  eventi non letti: $($_.Exception.Message)" }
}

function Prova-Uscita([string]$Nome, [switch]$SenzaAggiramenti, [switch]$ConX, [switch]$ConTelefono) {
    Passo "Uscita: $Nome" {
        if ($SenzaAggiramenti) { Avvia-App -Azzera -SenzaAggiramenti | Out-Null } else { Avvia-App -Azzera | Out-Null }
        Start-Sleep -Seconds 3
        if ($ConTelefono) {
            Avvia-TelefonoFinto -DalQR --android --identita-nuova --nome 'Telefono di Giorgio' --durata 300 --riconnetti-sempre | Out-Null
            Attendi-Telefono 'ACCETTATO' 30 -Nome 'Telefono di Giorgio' -Obbligatorio | Out-Null
            Attendi-Telefono 'Video:' 20 -Nome 'Telefono di Giorgio' | Out-Null
            Start-Sleep -Seconds 5
        }
        Fotografa "$Nome-prima"
        if ($ConX) {
            Porta-Davanti
            Tasto 'Alt+F4'
            Start-Sleep -Seconds 3
            $exe = & (Get-Module Collaudo) { $script:Exe }
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) | Out-Null
            Start-Sleep -Seconds 6
            Porta-Davanti
            Fotografa "$Nome-riaperta"
        }
        $da = (Get-Date).AddSeconds(-2)
        Chiudi-App
        Start-Sleep -Seconds 4
        Eventi-Uscita $da
        if ($ConTelefono) { Ferma-TelefonoFinto }
        Start-Sleep -Seconds 2
    }
}

# Prima senza aggiramenti: l'app deve partire da sola anche su Windows Server.
Prova-Uscita 'senza-aggiramenti-x-telefono' -SenzaAggiramenti -ConX -ConTelefono
Prova-Uscita 'senza-aggiramenti-telefono' -SenzaAggiramenti -ConTelefono
Prova-Uscita 'senza-aggiramenti-x' -SenzaAggiramenti -ConX
Prova-Uscita 'aggiramento-x-telefono' -ConX -ConTelefono
Prova-Uscita 'senza-aggiramenti-x-telefono-2' -SenzaAggiramenti -ConX -ConTelefono

& (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella (Cartella-Risultati)
