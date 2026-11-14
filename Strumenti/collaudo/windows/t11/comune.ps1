# Funzioni dei copioni t11 (Marta, cieca: Assistente vocale e solo tastiera). Si carica con
# «. (Join-Path $PSScriptRoot '..\t11\comune.ps1')». Registrano dove va il fuoco della tastiera a ogni tasto, fanno
# un ritaglio dello schermo attorno all'elemento col fuoco (per vedere se il fuoco si vede) e annotano nome, tipo,
# testo d'aiuto e «LiveSetting» degli elementi che l'Assistente vocale leggerebbe.

$script:ProprietaLive = $null
try { $script:ProprietaLive = [System.Windows.Automation.AutomationProperty]::LookupById(30135) } catch { }

function Elemento-Fuoco {
    try { [System.Windows.Automation.AutomationElement]::FocusedElement } catch { $null }
}

function Descrivi-Fuoco {
    param($e = (Elemento-Fuoco))
    if (-not $e) { return '(nessun fuoco)' }
    try {
        $c = $e.Current
        $tipo = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $testo = "$tipo «$($c.Name -replace "`r?`n", ' ⏎ ')» id=$($c.AutomationId) @ $(Descrivi-Rettangolo $c.BoundingRectangle)"
        if ($c.HelpText) { $testo += " aiuto=«$($c.HelpText)»" }
        if ($c.ItemStatus) { $testo += " stato=«$($c.ItemStatus)»" }
        if ($c.AcceleratorKey) { $testo += " acceleratore=«$($c.AcceleratorKey)»" }
        if ($c.AccessKey) { $testo += " tastoaccesso=«$($c.AccessKey)»" }
        if ($c.ProcessId -ne (Get-Process -Name WebcamLR -ErrorAction SilentlyContinue | Select-Object -First 1).Id) { $testo += " [FUORI DALL'APP: processo $($c.ProcessId), classe $($c.ClassName)]" }
        $testo
    } catch { "(fuoco non leggibile: $($_.Exception.Message))" }
}

function Ritaglio-Fuoco {
    <# PNG dello schermo attorno all'elemento con il fuoco (margine 28 px): per guardare se il rettangolo del fuoco si vede. #>
    param([Parameter(Mandatory)][string]$Nome)
    $e = Elemento-Fuoco
    if (-not $e) { return }
    try {
        $r = $e.Current.BoundingRectangle
        if ($r.IsEmpty -or $r.Width -lt 1) { Scrivi-Log "  ritaglio ${Nome}: rettangolo vuoto"; return }
        $m = 28
        $x = [Math]::Max(0, [int]$r.X - $m); $y = [Math]::Max(0, [int]$r.Y - $m)
        $l = [Math]::Min(900, [int]$r.Width + 2 * $m); $a = [Math]::Min(600, [int]$r.Height + 2 * $m)
        $file = Nome-File "fuoco-$Nome" 'png'
        Salva-Area $x $y $l $a $file ([System.Drawing.Imaging.ImageFormat]::Png)
        Scrivi-Log "  ritaglio del fuoco: $(Split-Path -Leaf $file)"
    } catch { Scrivi-Log "  ritaglio $Nome non riuscito: $($_.Exception.Message)" }
}

function Giro-Tab {
    <# Preme Tab (o Maiusc+Tab con -Indietro) $Volte volte e scrive in passi.log dove va il fuoco; un ritaglio ogni $Ogni. #>
    param([Parameter(Mandatory)][string]$Nome, [int]$Volte = 30, [switch]$Indietro, [int]$Ogni = 0)
    $tasto = if ($Indietro) { 'Maiusc+Tab' } else { 'Tab' }
    Scrivi-Log "GIRO $tasto «$Nome» · inizio: $(Descrivi-Fuoco)"
    $visti = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le $Volte; $i++) {
        [System.Windows.Forms.SendKeys]::SendWait($(if ($Indietro) { '+{TAB}' } else { '{TAB}' }))
        Start-Sleep -Milliseconds 350
        $d = Descrivi-Fuoco
        Scrivi-Log ("  {0} {1,2}: {2}" -f $tasto, $i, $d)
        $visti.Add(($d -replace ' @ .*$', ''))
        if ($Ogni -gt 0 -and ($i % $Ogni) -eq 0) { Ritaglio-Fuoco "$Nome-$i" }
    }
    $diversi = @($visti | Select-Object -Unique).Count
    Scrivi-Log "GIRO «$Nome»: $Volte tasti, $diversi elementi diversi"
}

function Tab-Fino {
    <# Preme Tab finché il fuoco è sull'elemento con quell'AutomationId o con un nome che contiene il testo. Vero se arriva. #>
    param([Parameter(Mandatory)][string]$Chi, [int]$Massimo = 70, [switch]$Indietro)
    for ($i = 0; $i -le $Massimo; $i++) {
        $e = Elemento-Fuoco
        if ($e) {
            try {
                $c = $e.Current
                if ($c.AutomationId -eq $Chi -or ($c.Name -and $c.Name.IndexOf($Chi, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                    Scrivi-Log "Tab-Fino «$Chi»: arrivato con $i tasti · $(Descrivi-Fuoco $e)"
                    return $true
                }
            } catch { }
        }
        [System.Windows.Forms.SendKeys]::SendWait($(if ($Indietro) { '+{TAB}' } else { '{TAB}' }))
        Start-Sleep -Milliseconds 300
    }
    Scrivi-Log "Tab-Fino «$Chi»: NON raggiunto in $Massimo tasti (fuoco: $(Descrivi-Fuoco))"
    $false
}

function Premi {
    <# Un tasto (come Tasto) e poi dove va il fuoco. #>
    param([Parameter(Mandatory)][string]$Tasti)
    Tasto $Tasti
    Start-Sleep -Milliseconds 300
    Scrivi-Log "  dopo «$Tasti» il fuoco è su: $(Descrivi-Fuoco)"
}

function Leggi-Elemento {
    <# Nome, tipo, aiuto, stato e LiveSetting di un elemento (per id), come li riceve l'Assistente vocale. #>
    param([Parameter(Mandatory)][string]$Chi)
    $e = Trova-Elemento $Chi -AncheNascosti
    if (-not $e) { Scrivi-Log "LEGGI «$Chi»: non c'è"; return }
    $c = $e.Current
    $live = ''
    if ($script:ProprietaLive) { try { $live = " live=$($e.GetCurrentPropertyValue($script:ProprietaLive))" } catch { } }
    $tipo = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
    Scrivi-Log "LEGGI «$Chi»: $tipo «$($c.Name -replace "`r?`n", ' ⏎ ')» aiuto=«$($c.HelpText)» stato=«$($c.ItemStatus)» fuorischermo=$($c.IsOffscreen) focalizzabile=$($c.IsKeyboardFocusable) controllo=$($c.IsControlElement) contenuto=$($c.IsContentElement)$live"
}

function Controllo-Nomi {
    <#
    Nella vista dei controlli (quella dell'Assistente vocale): i controlli interattivi senza nome, le immagini con un nome
    (annunciate) o senza, i nomi che sembrano chiavi o in inglese. Scrive in passi.log e segnala i controlli senza nome.
    #>
    param([Parameter(Mandatory)][string]$Nome)
    $interattivi = 'Button', 'CheckBox', 'ComboBox', 'Edit', 'Hyperlink', 'ListItem', 'MenuItem', 'RadioButton', 'Slider', 'SplitButton', 'TabItem', 'ToggleButton', 'TreeItem', 'Spinner'
    $camminatore = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $senza = New-Object System.Collections.Generic.List[string]
    $immagini = New-Object System.Collections.Generic.List[string]
    $contati = 0
    $pila = New-Object System.Collections.Stack
    foreach ($f in @(Finestre-App)) { $pila.Push($f) }
    while ($pila.Count -gt 0 -and $contati -lt 4000) {
        $e = $pila.Pop(); $contati++
        try {
            $c = $e.Current
            if (-not $c.IsOffscreen) {
                $tipo = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
                $nomeE = "$($c.Name)".Trim()
                if ($interattivi -contains $tipo -and -not $nomeE) { $senza.Add("$tipo id=$($c.AutomationId) @ $(Descrivi-Rettangolo $c.BoundingRectangle) focalizzabile=$($c.IsKeyboardFocusable)") }
                if ($tipo -eq 'Image') { $immagini.Add("Image «$nomeE» id=$($c.AutomationId) @ $(Descrivi-Rettangolo $c.BoundingRectangle)") }
            }
        } catch { continue }
        $figlio = $camminatore.GetFirstChild($e)
        while ($figlio) { $pila.Push($figlio); $figlio = $camminatore.GetNextSibling($figlio) }
    }
    Scrivi-Log "NOMI «$Nome»: $contati elementi, $($senza.Count) controlli senza nome, $($immagini.Count) immagini"
    foreach ($s in $senza) { Scrivi-Log "  SENZA NOME: $s" }
    foreach ($s in $immagini) { Scrivi-Log "  IMMAGINE: $s" }
    if ($senza.Count) { Segnala-Problema "${Nome}: $($senza.Count) controlli senza nome per l'Assistente vocale ($(($senza | Select-Object -First 4) -join ' | '))" }
}
