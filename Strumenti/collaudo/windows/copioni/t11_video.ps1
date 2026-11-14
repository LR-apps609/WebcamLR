# Collaudo t11 (Marta), secondo giro: menu dell'account e Guida (F1) con frecce e Tab, poi telefono consentito con la
# sola tastiera (Tab su «Consenti», Invio) e il video: nomi e stati per l'Assistente vocale, ordine del fuoco, i chip,
# «Scollega», la rete che cade, la vista Completa con il telefono.
. (Join-Path $PSScriptRoot '..\t11\comune.ps1')
$cartellaT11 = Cartella-Risultati
function Tab-FinoId([string]$Id, [int]$Massimo = 70) {
    for ($i = 0; $i -le $Massimo; $i++) {
        $e = Elemento-Fuoco
        if ($e -and $e.Current.AutomationId -eq $Id) { Scrivi-Log "Tab-FinoId «$Id»: $i tasti · $(Descrivi-Fuoco $e)"; return $true }
        [System.Windows.Forms.SendKeys]::SendWait('{TAB}'); Start-Sleep -Milliseconds 300
    }
    Scrivi-Log "Tab-FinoId «$Id»: NON raggiunto in $Massimo tasti"; $false
}
function Schede-Guida {
    $sel = @(Tutti-Elementi | Where-Object { try { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::TabItem } catch { $false } } | ForEach-Object {
            $p = $null; $s = ''
            if ($_.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p) -and $p.Current.IsSelected) { $s = '*' }
            "$s$($_.Current.Name)" })
    Scrivi-Log "  schede della Guida: $($sel -join ' | ')"
}
try {
    Passo 'Avvio' { Avvia-App -Azzera | Out-Null; Start-Sleep -Seconds 5 }
    Passo 'Menu account: frecce e Tab' {
        Tab-FinoId 'PulsanteAccount' 12 | Out-Null
        Premi 'Invio'; Start-Sleep -Milliseconds 800
        Premi 'Giu'; Premi 'Su'
        Giro-Tab 'menu-account' 9 -Ogni 3
        Premi 'Esc'
    }
    Passo 'Guida (F1): le schede con la tastiera' {
        Premi 'F1'; Start-Sleep -Seconds 2
        Schede-Guida
        foreach ($t in 'Destra', 'Ctrl+Tab', 'Maiusc+Tab', 'Destra') { Premi $t; Schede-Guida }
        Fotografa 'guida-dopo-tasti'
        Premi 'Esc'; Start-Sleep -Seconds 1
    }
    Passo 'Telefono consentito con Tab e Invio' {
        Porta-Davanti
        Avvia-TelefonoFinto --nome 'iPhone di Marta video' --durata 700 --riconnetti-sempre --identita-nuova | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di Marta video' -Obbligatorio | Out-Null
        Start-Sleep -Seconds 2
        Scrivi-Log "FUOCO con il dialogo: $(Descrivi-Fuoco)"
        if (Tab-FinoId 'PrimaryButton' 6) { Premi 'Invio' } else { throw 'Consenti non raggiunto' }
        Attendi-Telefono 'ACCETTATO' 20 -Nome 'iPhone di Marta video' -Obbligatorio | Out-Null
        foreach ($s in 1..4) { Start-Sleep -Seconds 2; Leggi-Elemento 'TestoStato' }
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Marta video' | Out-Null
        Start-Sleep -Seconds 4
        Scrivi-Log "FUOCO dopo il collegamento: $(Descrivi-Fuoco)"
    }
    Passo 'Video: nomi e stati' {
        Fotografa 'video'
        Controllo-Nomi 'video'
        foreach ($id in 'PillolaStato', 'TestoStato', 'PillolaTelefono', 'TestoPillolaTelefono', 'ChipQualita', 'TestoQualita', 'ChipCollegamento', 'TestoCollegamento', 'ChipVideo', 'TestoFormatoVideo', 'Video', 'RiquadroVideo', 'BordoVideo', 'PulsanteSpecchia', 'PulsanteRegistra', 'PulsanteScollegaPillola') { Leggi-Elemento $id }
        Controlla-Video | Out-Null
    }
    Passo 'Video: Tab avanti' { Giro-Tab 'video' 30 -Ogni 2 }
    Passo 'Chip qualità con Invio ed Esc' {
        if (Tab-FinoId 'ChipQualita' 30) {
            Premi 'Invio'; Start-Sleep -Milliseconds 800
            Fotografa 'qualita-aperta'
            Giro-Tab 'qualita' 6
            Premi 'Esc'
        }
    }
    Passo 'Chip collegamento con Invio ed Esc' {
        if (Tab-FinoId 'ChipCollegamento' 30) {
            Premi 'Invio'; Start-Sleep -Milliseconds 800
            Fotografa 'collegamento-aperto'
            Giro-Tab 'collegamento' 6
            Premi 'Esc'
        }
    }
    Passo 'Pillola del telefono con Invio ed Esc' {
        if (Tab-FinoId 'PillolaTelefono' 30) {
            Premi 'Invio'; Start-Sleep -Milliseconds 800
            Fotografa 'pillola-aperta'
            Giro-Tab 'pillola' 6
            Premi 'Esc'
        }
    }
    Passo 'Rete che cade e torna: stati' {
        Rete-Spenta
        foreach ($s in 1..4) { Start-Sleep -Seconds 3; Leggi-Elemento 'TestoStato'; Leggi-Elemento 'PillolaTelefono' }
        Controllo-Nomi 'rete-spenta'
        Fotografa 'rete-spenta'
        Scrivi-Log "FUOCO a rete spenta: $(Descrivi-Fuoco)"
        Rete-Accesa
        foreach ($s in 1..3) { Start-Sleep -Seconds 3; Leggi-Elemento 'TestoStato'; Leggi-Elemento 'PillolaTelefono' }
    }
    Passo 'Completo con il telefono' {
        Premi 'Ctrl+2'; Start-Sleep -Seconds 2
        Fotografa 'completo-telefono'
        Controllo-Nomi 'completo-telefono'
        foreach ($id in 'SchedaTelefono', 'NomeTelefono', 'BatteriaTelefono', 'DettagliTelefono', 'PulsanteScollega', 'StatoWebcamTesto', 'InterruttoreMicrofono', 'LivelloMicrofono') { Leggi-Elemento $id }
        Giro-Tab 'completo-telefono' 50 -Ogni 5
    }
    Passo 'Scollega con la tastiera' {
        if (Tab-FinoId 'PulsanteScollega' 60) {
            Premi 'Invio'; Start-Sleep -Seconds 1
            Fotografa 'scollega'
            Giro-Tab 'scollega' 4
            Premi 'Esc'; Start-Sleep -Seconds 1
            Scrivi-Log "  Scollega ancora a schermo dopo Esc: $([bool](Trova-Elemento 'PulsanteScollega'))"
            Fotografa 'scollega-dopo-esc'
        }
    }
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT11
}
