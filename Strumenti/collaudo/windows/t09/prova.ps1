# t09 · Anna: la stessa prova dell'app a una scala di Windows già impostata (la lancia copioni/t09_finestra.ps1 in un
# processo nuovo, consapevole dei DPI per schermo: così schermate e posizioni di UI Automation sono in pixel veri).
param([Parameter(Mandatory)][string]$Cartella, [Parameter(Mandatory)][string]$Etichetta, [switch]$Breve)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class T09Dpi
{
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr contesto);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr finestra);
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr finestra, int comando);
}
'@
$consapevole = [T09Dpi]::SetProcessDpiAwarenessContext([IntPtr](-4))
Import-Module (Join-Path $PSScriptRoot '..\Collaudo.psm1') -DisableNameChecking -Force
Inizia-Copione -Nome "t09-$Etichetta" -Cartella $Cartella
$schermo = [System.Windows.Forms.SystemInformation]::VirtualScreen
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
Scrivi-Log "Processo per-monitor: $consapevole · DPI di sistema $([T09Dpi]::GetDpiForSystem()) · schermo $($schermo.Width)×$($schermo.Height) · area di lavoro $($area.Width)×$($area.Height)"

function Misure([string]$Quando) {
    $f = Finestra-App
    if (-not $f) { Scrivi-Log "$Quando · nessuna finestra"; return }
    $r = $f.Current.BoundingRectangle
    $dpi = [T09Dpi]::GetDpiForWindow([IntPtr]$f.Current.NativeWindowHandle)
    $scala = [math]::Round($dpi / 96 * 100)
    $dipL = [math]::Round($r.Width * 96 / [math]::Max($dpi, 1)); $dipA = [math]::Round($r.Height * 96 / [math]::Max($dpi, 1))
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    Scrivi-Log "MISURE $Quando · finestra $(Descrivi-Rettangolo $r) px = ${dipL}×${dipA} DIP · DPI $dpi ($scala %) · area di lavoro $($area.X),$($area.Y) $($area.Width)×$($area.Height)"
    if ($r.Bottom -gt $area.Bottom + 8 -or $r.Right -gt $area.Right + 8 -or $r.X -lt $area.X - 8 -or $r.Y -lt $area.Y - 8) {
        Segnala-Problema "$Etichetta · ${Quando}: la finestra ($(Descrivi-Rettangolo $r)) esce dall'area di lavoro ($($area.Width)×$($area.Height))"
    }
    foreach ($id in 'PulsanteImpostazioni', 'PulsanteAiuto', 'PulsanteAccount', 'PulsanteSchermo', 'PillolaTelefono', 'ImmagineQRGrande', 'ChipQualita', 'TitoloFotocamera', 'PannelloSinistro', 'PulsanteRegistra', 'PulsanteFoto') {
        $e = Trova-Elemento $id -AncheNascosti
        if (-not $e) { continue }
        $c = $e.Current
        $fuori = (-not $c.BoundingRectangle.IsEmpty) -and ($c.BoundingRectangle.Bottom -gt $area.Bottom + 2 -or $c.BoundingRectangle.Right -gt $area.Right + 2)
        Scrivi-Log "  $id · fuori schermo (UIA) $($c.IsOffscreen) · $(Descrivi-Rettangolo $c.BoundingRectangle)$(if ($fuori) { ' · OLTRE IL BORDO DELLO SCHERMO' })"
        if ($fuori) { Segnala-Problema "$Etichetta · ${Quando}: $id è oltre il bordo dello schermo ($(Descrivi-Rettangolo $c.BoundingRectangle))" }
    }
}

try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 5
    Fotografa 'primo-avvio'
    Misure 'primo avvio'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"

    Passo 'Ingrandita' {
        Ingrandisci-Finestra
        Start-Sleep -Seconds 2
        Fotografa 'ingrandita'
        Misure 'ingrandita'
    }
    Passo 'Impostazioni' {
        Clicca 'PulsanteImpostazioni'
        Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
        Fotografa 'impostazioni'
        foreach ($voce in 'Fotocamera', 'Telefoni', 'Schermo') {
            if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
            Clicca (Testo-App "Impostazioni_$voce") -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Milliseconds 800
            Fotografa "impostazioni-$voce"
            if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
        }
        if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    }
    if (-not $Breve) {
        Passo 'Menu Schermo' { Clicca 'PulsanteSchermo'; Fotografa 'menu-schermo'; Tasto 'Esc' }
        Passo 'Aiuto' { Clicca 'PulsanteAiuto'; Start-Sleep -Seconds 1; Fotografa 'aiuto'; Tasto 'Esc' }
    }

    $collegato = Passo 'Telefono finto dal QR code' {
        Avvia-TelefonoFinto -DalQR --nome 'iPhone di Anna' --durata 400 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Anna' -Obbligatorio | Out-Null
    } -Esito
    if (-not $collegato) {
        Ferma-TelefonoFinto
        $collegato = Passo 'Telefono finto con la conferma sul PC' {
            Avvia-TelefonoFinto --nome 'iPhone di Anna 2' --durata 400 --riconnetti-sempre | Out-Null
            Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di Anna 2' -Obbligatorio | Out-Null
            Attendi-Testo (Testo-App 'Conferma_Consenti') 15 -Obbligatorio | Out-Null
            Fotografa 'conferma-telefono'
            Misure 'conferma'
            Clicca (Testo-App 'Conferma_Consenti')
            Attendi-Telefono 'ACCETTATO' 20 -Nome 'iPhone di Anna 2' -Obbligatorio | Out-Null
        } -Esito
    }
    if ($collegato) {
        Passo 'Essenziale con il telefono' {
            Start-Sleep -Seconds 6
            Tasto 'Ctrl+1'
            Start-Sleep -Seconds 2
            Fotografa 'essenziale-con-telefono'
            Misure 'essenziale con telefono'
        }
        Passo 'Pillola del telefono' { Clicca 'PillolaTelefono'; Fotografa 'pillola-telefono'; Tasto 'Esc' }
    }
    Passo 'Completo' {
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        Fotografa 'completo'
        Misure 'completo'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
    }
    Passo 'Vista pulita' {
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 2
        Fotografa 'vista-pulita'
        Misure 'vista pulita'
        Tasto 'Ctrl+Maiusc+P'
        Start-Sleep -Seconds 1
    }
    Passo 'Finestra mini' {
        Tasto 'Ctrl+Maiusc+M'
        Start-Sleep -Seconds 2
        Fotografa 'finestra-mini'
        Descrivi-Finestre
        Misure 'mini'
        Tasto 'Ctrl+Maiusc+M'
        Start-Sleep -Seconds 1
    }
    Passo 'Finestra normale stretta (800×450 chiesta)' {
        Tasto 'Ctrl+1'
        $f = Finestra-App
        [void][T09Dpi]::ShowWindow([IntPtr]$f.Current.NativeWindowHandle, 9)
        Start-Sleep -Seconds 1
        Ridimensiona-Finestra 800 450
        Start-Sleep -Seconds 2
        Fotografa 'normale-stretta'
        Misure 'normale stretta'
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        Fotografa 'normale-stretta-completo'
        Misure 'normale stretta, completo'
    }
    if (-not $Breve) {
        Passo 'Riapertura con la posizione salvata' {
            Ferma-TelefonoFinto
            Chiudi-App
            Avvia-App | Out-Null
            Start-Sleep -Seconds 4
            Fotografa 'riaperta'
            Misure 'riaperta'
        }
    }
} catch {
    Segnala-Problema "$Etichetta · interrotto: $($_.Exception.Message)"
    try { [void](Schermata 'interrotto') } catch { }
} finally {
    try { Raccogli-Registri } catch { }
    Chiudi-Tutto
    $testo = @("Prova: $Etichetta", "Problemi: $(@(Problemi).Count)") + (@(Problemi) | ForEach-Object { "- $_" })
    [System.IO.File]::WriteAllLines((Join-Path $Cartella 'esito.txt'), [string[]]$testo, (New-Object System.Text.UTF8Encoding $true))
}
