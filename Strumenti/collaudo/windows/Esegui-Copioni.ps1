# Esegue i copioni di collaudo (copioni/<nome>.ps1), uno dopo l'altro, ognuno con la sua cartella di risultati:
# schermate, alberi dell'interfaccia, passi.log, registri del telefono finto, dati dell'app ed esito.txt.
# Un copione che trova un bug non fa fallire niente: lo scrive in esito.txt. Uso:
#   powershell -File Strumenti\collaudo\windows\Esegui-Copioni.ps1 -Copioni "fumo, altro" -Uscita risultati
param(
    [string]$Copioni = '',
    [string]$Uscita = (Join-Path $PSScriptRoot '..\..\..\risultati-collaudo')
)

$ErrorActionPreference = 'Stop'
$cartellaCopioni = Join-Path $PSScriptRoot 'copioni'
$nomi = @($Copioni -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_ -replace '\.ps1$', '' })
if ($nomi.Count -eq 0) {
    $nomi = @(Get-ChildItem -Path $cartellaCopioni -Filter '*.ps1' | Sort-Object Name | ForEach-Object { $_.BaseName })
}
New-Item -ItemType Directory -Force -Path $Uscita | Out-Null
$Uscita = (Resolve-Path $Uscita).Path
$riassunto = New-Object System.Collections.Generic.List[string]

foreach ($nome in $nomi) {
    $file = Join-Path $cartellaCopioni "$nome.ps1"
    $cartella = Join-Path $Uscita $nome
    New-Item -ItemType Directory -Force -Path $cartella | Out-Null
    $inizio = Get-Date
    $esito = 'OK'
    $errore = ''
    # Ogni copione in un runspace pulito: il modulo riparte da capo (lingua, telefoni, numeri delle schermate).
    Remove-Module Collaudo -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot 'Collaudo.psm1') -DisableNameChecking -Force
    try {
        Inizia-Copione -Nome $nome -Cartella $cartella
        if (-not (Test-Path $file)) { throw "Copione non trovato: $file" }
        & $file
    } catch {
        $esito = 'INTERROTTO'
        $errore = "$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
        Scrivi-Log "COPIONE INTERROTTO: $($_.Exception.Message)"
        try { [void](Schermata 'interrotto') } catch { }
        try { [void](Albero-UI 'interrotto') } catch { }
    } finally {
        try { Raccogli-Registri } catch { Scrivi-Log "Raccogli-Registri: $($_.Exception.Message)" }
        Chiudi-Tutto
    }
    $problemi = @(Problemi)
    if ($esito -eq 'OK' -and $problemi.Count -gt 0) { $esito = 'PROBLEMI' }
    $durata = [int]((Get-Date) - $inizio).TotalSeconds
    $testo = @("Copione: $nome", "Esito: $esito", "Durata: $durata s", "Problemi: $($problemi.Count)")
    $testo += $problemi | ForEach-Object { "- $_" }
    if ($errore) { $testo += @('', 'Errore che ha interrotto il copione:', $errore) }
    [System.IO.File]::WriteAllLines((Join-Path $cartella 'esito.txt'), [string[]]$testo, (New-Object System.Text.UTF8Encoding $true))
    $riassunto.Add("$nome`t$esito`t$durata s`t$($problemi.Count) problemi")
    Write-Host "=== $nome · $esito · $durata s · $($problemi.Count) problemi"
}

[System.IO.File]::WriteAllLines((Join-Path $Uscita 'riassunto.txt'), $riassunto, (New-Object System.Text.UTF8Encoding $true))
if ($env:GITHUB_STEP_SUMMARY) {
    $tabella = @('| Copione | Esito | Durata | Problemi |', '| --- | --- | --- | --- |')
    $tabella += $riassunto | ForEach-Object { '| ' + ($_ -replace "`t", ' | ') + ' |' }
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $tabella -Encoding UTF8
}
exit 0
