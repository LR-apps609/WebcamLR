# Funzioni dei copioni t13 (Elena). Si carica con «. (Join-Path $PSScriptRoot '..\t13\comune.ps1')».

function Clic-Rapido {
    <# Clic veri del mouse ripetuti in fretta al centro di un elemento: $Volte clic a $Pausa ms. #>
    param([Parameter(Mandatory)]$Elemento, [int]$Volte = 2, [int]$Pausa = 80)
    $r = $Elemento.Current.BoundingRectangle
    $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    Porta-Davanti
    for ($i = 0; $i -lt $Volte; $i++) {
        [CollaudoNativo]::Clic($x, $y)
        Start-Sleep -Milliseconds $Pausa
    }
    Scrivi-Log "CLIC RAPIDI: $Volte su «$($Elemento.Current.Name)» ($($Elemento.Current.AutomationId)) in $x,$y ogni $Pausa ms"
}
function App-Viva {
    $p = Get-Process -Name 'WebcamLR' -ErrorAction SilentlyContinue
    if ($p) { Scrivi-Log "App viva: processo $($p.Id -join ',')"; $true } else { Segnala-Problema "WebcamLR non è più in esecuzione"; $false }
}
function Ultime-Telefono([string]$Nome, [int]$Righe = 10) {
    Registro-Telefono $Nome | Select-Object -Last $Righe | ForEach-Object { Scrivi-Log "  telefono «$Nome»: $_" }
}
function Imposta-Valore {
    <# ValuePattern.SetValue su un elemento già trovato; rende il valore riletto. #>
    param([Parameter(Mandatory)]$Elemento, [string]$Testo)
    $vp = $null
    if (-not $Elemento.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { throw "«$($Elemento.Current.Name)» non ha ValuePattern" }
    $Elemento.SetFocus()
    $inizio = Get-Date
    $vp.SetValue($Testo)
    $ms = [int]((Get-Date) - $inizio).TotalMilliseconds
    Start-Sleep -Milliseconds 400
    $letto = $vp.Current.Value
    Scrivi-Log "IMPOSTA VALORE: $($Testo.Length) caratteri in «$($Elemento.Current.Name)» in $ms ms; riletti $($letto.Length) caratteri"
    $letto
}
function Casella-Modifica {
    <# La prima casella di testo (ControlType Edit) visibile nelle finestre dell'app, o $null. #>
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    foreach ($f in @(Finestre-App)) {
        foreach ($e in $f.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
            try { if (-not $e.Current.IsOffscreen) { return $e } } catch { }
        }
    }
    $null
}
