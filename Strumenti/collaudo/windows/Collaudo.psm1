# Collaudo.psm1 · banco di prova di WebcamLR per Windows (Windows PowerShell 5.1).
# Guida l'app vera con UI Automation (System.Windows.Automation, nessuna dipendenza da scaricare), fa schermate e alberi
# dell'interfaccia, avvia il telefono finto. Ogni passo scrive una riga leggibile in passi.log. Guida: LEGGIMI.md.
# Salvato in UTF-8 con BOM: senza, PowerShell 5.1 legge male le lettere accentate.

Set-StrictMode -Version 2.0
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CollaudoNativo
{
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr finestra);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr finestra, int comando);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr finestra, int x, int y, int l, int a, bool ridisegna);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint azione, uint x, uint y, uint dati, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte tasto, byte scan, uint azione, UIntPtr extra);
    [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr processo);
    [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr processo);
    public static void Clic(int x, int y)
    {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(60);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
}
'@
[void][CollaudoNativo]::SetProcessDPIAware()

$script:Radice = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:Exe = $env:WEBCAMLR_EXE
if (-not $script:Exe) {
    $script:Exe = Join-Path $script:Radice 'Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\WebcamLR.exe'
}
$script:TelefonoExe = Join-Path $script:Radice 'Strumenti\collaudo\TelefonoFinto\bin\Release\net8.0\TelefonoFinto.exe'
$script:Gancio = Join-Path $script:Radice 'Strumenti\collaudo\windows\LinguaAvvio\bin\Release\net8.0\LinguaAvvio.dll'
$script:DatiApp = Join-Path $env:LOCALAPPDATA 'WebcamLR'
$script:Uscita = Join-Path $env:TEMP 'collaudo'
$script:Log = $null
$script:Numero = 0
$script:Lingua = 'it-IT'
$script:Processo = $null
$script:Telefoni = @{}
$script:Problemi = New-Object System.Collections.ArrayList
$script:Passi = 0

$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]

# ---------------------------------------------------------------- registro dei passi

function Scrivi-Log {
    <# Una riga nel registro del copione (passi.log) e sulla console. #>
    param([Parameter(Mandatory)][string]$Testo)
    $riga = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Testo
    Write-Host $riga
    if ($script:Log) { Add-Content -LiteralPath $script:Log -Value $riga -Encoding UTF8 }
}

function Inizia-Copione {
    <# Prepara la cartella dei risultati del copione: schermate, alberi, registri ed esito.txt. #>
    param([Parameter(Mandatory)][string]$Nome, [string]$Cartella)
    if (-not $Cartella) { $Cartella = Join-Path $script:Uscita $Nome }
    New-Item -ItemType Directory -Force -Path $Cartella | Out-Null
    $script:Uscita = (Resolve-Path $Cartella).Path
    $script:Log = Join-Path $script:Uscita 'passi.log'
    $script:Numero = 0
    $script:Passi = 0
    $script:Problemi.Clear()
    Scrivi-Log "Copione «$Nome» · risultati in $script:Uscita"
    Scrivi-Log "App: $script:Exe"
}

function Cartella-Risultati { $script:Uscita }

function Segnala-Problema {
    <# Annota un problema trovato (finisce in esito.txt); il copione continua. #>
    param([Parameter(Mandatory)][string]$Testo)
    [void]$script:Problemi.Add($Testo)
    Scrivi-Log "PROBLEMA: $Testo"
}

function Problemi { , $script:Problemi.ToArray() }

function Passo {
    <#
    Esegue un blocco come passo con nome: se fallisce, il problema si annota (con una schermata) e il copione va avanti.
    Esempio: Passo 'Apri le impostazioni' { Clicca 'PulsanteImpostazioni' }
    Con -Esito restituisce vero o falso: if (Passo 'Collego il telefono' { ... } -Esito) { ... }
    #>
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][scriptblock]$Blocco, [switch]$Esito)
    $script:Passi++
    Scrivi-Log "── $Nome"
    try {
        & $Blocco | Out-Null
        if ($Esito) { return $true }
    } catch {
        Segnala-Problema "$Nome · $($_.Exception.Message)"
        try { [void](Schermata ('errore-' + ($Nome -replace '[^\w]+', '-'))) } catch { }
        if ($Esito) { return $false }
    }
}

# ---------------------------------------------------------------- app

function Azzera-Dati {
    <# Cancella i dati dell'app (%LOCALAPPDATA%\WebcamLR): preferenze, chiave del PC, telefoni fidati. Primo avvio vero. #>
    param([switch]$Forza)
    if (-not $env:GITHUB_ACTIONS -and -not $Forza) {
        throw 'Azzera-Dati cancella i dati veri di WebcamLR: fuori da GitHub Actions serve -Forza'
    }
    if (Test-Path $script:DatiApp) { Remove-Item -Recurse -Force $script:DatiApp }
    Scrivi-Log "Dati dell'app azzerati ($script:DatiApp)"
}

function Lingua-Inglese {
    <# I testi di WebcamLR in inglese, dal prossimo Avvia-App (con -Riavvia anche subito). #>
    param([switch]$Riavvia)
    $script:Lingua = 'en-US'
    Scrivi-Log 'Lingua: inglese (en-US)'
    if ($Riavvia) { Chiudi-App; Avvia-App }
}

function Lingua-Italiana {
    <# I testi di WebcamLR in italiano (la scelta di serie del banco), dal prossimo Avvia-App. #>
    param([switch]$Riavvia)
    $script:Lingua = 'it-IT'
    Scrivi-Log 'Lingua: italiano (it-IT)'
    if ($Riavvia) { Chiudi-App; Avvia-App }
}

function Avvia-App {
    <#
    Avvia WebcamLR.exe e aspetta la finestra. La lingua (Lingua-Inglese / Lingua-Italiana) passa con un «startup hook» di
    .NET (LinguaAvvio.dll): l'app la legge dalla lingua dell'interfaccia, che sul runner è l'inglese.
    -Azzera: prima Azzera-Dati (primo avvio). -Argomenti: riga di comando in più.
    #>
    param([switch]$Azzera, [string]$Argomenti = '', [int]$Attesa = 60)
    if ($Azzera) { Azzera-Dati }
    if (-not (Test-Path $script:Exe)) { throw "WebcamLR.exe non trovato: $script:Exe" }
    $info = New-Object System.Diagnostics.ProcessStartInfo $script:Exe
    $info.Arguments = $Argomenti
    $info.UseShellExecute = $false
    $info.WorkingDirectory = Split-Path $script:Exe
    if (Test-Path $script:Gancio) {
        $info.EnvironmentVariables['DOTNET_STARTUP_HOOKS'] = $script:Gancio
        $info.EnvironmentVariables['WEBCAMLR_COLLAUDO_LINGUA'] = $script:Lingua
    } else {
        Scrivi-Log "Attenzione: $script:Gancio non c'è, la lingua resta quella di Windows"
    }
    $script:Processo = [System.Diagnostics.Process]::Start($info)
    Scrivi-Log "Avvia-App: processo $($script:Processo.Id), lingua $script:Lingua"
    # La finestra vera: la prima che compare può essere un'altra (un messaggio d'errore, una finestra di servizio).
    $finestra = $null
    $limite = (Get-Date).AddSeconds($Attesa)
    while ((Get-Date) -lt $limite) {
        Start-Sleep -Milliseconds 500
        if ($script:Processo.HasExited) { throw "WebcamLR è uscita subito (codice $($script:Processo.ExitCode))" }
        $finestra = Finestra-App
        if ($finestra -and $finestra.Current.BoundingRectangle.Width -ge 500) { break }
    }
    Start-Sleep -Seconds 2
    Descrivi-Finestre
    $finestra = Finestra-App
    if (-not $finestra) { throw "La finestra di WebcamLR non è comparsa in $Attesa s" }
    if ($finestra.Current.BoundingRectangle.Width -lt 500) {
        Segnala-Problema "La finestra di WebcamLR è piccola ($(Descrivi-Rettangolo $finestra.Current.BoundingRectangle)): testi «$((Testi-Visibili) -join ' | ')»"
    }
    Porta-Davanti
    Scrivi-Log "Finestra: «$($finestra.Current.Name)» $(Descrivi-Rettangolo $finestra.Current.BoundingRectangle)"
    $finestra
}

function Descrivi-Finestre {
    <# Nel registro: le finestre del processo dell'app, con classe, nome e misura. #>
    foreach ($f in (Finestre-App)) {
        $c = $f.Current
        Scrivi-Log "  finestra dell'app: classe=$($c.ClassName) «$($c.Name)» $(Descrivi-Rettangolo $c.BoundingRectangle)"
    }
}

function Finestre-App {
    <# Tutte le finestre principali del processo dell'app (la finestra, i riquadri e i menu aperti in WinUI). #>
    if (-not $script:Processo) { return @() }
    $condizione = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $script:Processo.Id)
    $tutte = $AE::RootElement.FindAll($TS::Children, $condizione)
    , @($tutte | ForEach-Object { $_ })
}

function Finestra-App {
    <# La finestra principale di WebcamLR (la più grande del processo), o $null. #>
    $finestre = Finestre-App
    if ($finestre.Count -eq 0) { return $null }
    $finestre | Sort-Object { - ($_.Current.BoundingRectangle.Width * $_.Current.BoundingRectangle.Height) } | Select-Object -First 1
}

function Porta-Davanti {
    $finestra = Finestra-App
    if (-not $finestra) { return }
    $maniglia = [IntPtr]$finestra.Current.NativeWindowHandle
    [void][CollaudoNativo]::ShowWindow($maniglia, 9)
    [void][CollaudoNativo]::SetForegroundWindow($maniglia)
}

function Chiudi-App {
    <#
    Chiude WebcamLR come l'installatore: «WebcamLR.exe --esci» chiede alla copia aperta di uscire bene (la X della finestra
    la nasconde accanto all'orologio). Se dopo 15 s è ancora aperta, la si termina e lo si segnala.
    #>
    if (-not $script:Processo -or $script:Processo.HasExited) { $script:Processo = $null; return }
    Scrivi-Log 'Chiudi-App: WebcamLR.exe --esci'
    try { Start-Process -FilePath $script:Exe -ArgumentList '--esci' -WorkingDirectory (Split-Path $script:Exe) | Out-Null } catch { }
    if (-not $script:Processo.WaitForExit(15000)) {
        Segnala-Problema 'WebcamLR non si è chiusa con --esci entro 15 s: terminata'
        $script:Processo.Kill()
    }
    Scrivi-Log "WebcamLR chiusa (codice $($script:Processo.ExitCode))"
    $script:Processo = $null
}

function Ridimensiona-Finestra {
    <# Porta la finestra a larghezza × altezza (pixel dello schermo), in alto a sinistra. #>
    param([Parameter(Mandatory)][int]$Larghezza, [Parameter(Mandatory)][int]$Altezza, [int]$X = 0, [int]$Y = 0)
    $finestra = Finestra-App
    if (-not $finestra) { throw 'Nessuna finestra di WebcamLR' }
    $maniglia = [IntPtr]$finestra.Current.NativeWindowHandle
    [void][CollaudoNativo]::ShowWindow($maniglia, 9)
    [void][CollaudoNativo]::MoveWindow($maniglia, $X, $Y, $Larghezza, $Altezza, $true)
    Start-Sleep -Milliseconds 800
    Scrivi-Log "Ridimensiona-Finestra ${Larghezza}×${Altezza}: ora $(Descrivi-Rettangolo $finestra.Current.BoundingRectangle)"
}

function Ingrandisci-Finestra {
    $finestra = Finestra-App
    if ($finestra) { [void][CollaudoNativo]::ShowWindow([IntPtr]$finestra.Current.NativeWindowHandle, 3) }
    Start-Sleep -Milliseconds 800
    Scrivi-Log 'Finestra ingrandita'
}

function Testo-App {
    <#
    Un testo dell'app nella lingua scelta, dalla stessa fonte dell'app (Windows\WebcamLR.App\Strings\<lingua>\Resources.resw):
    così un copione funziona in italiano e in inglese. Es. Clicca (Testo-App 'Conferma_Consenti').
    I valori con {0} restano con {0}; -Inizio dà solo la parte prima del primo {.
    #>
    param([Parameter(Mandatory)][string]$Chiave, [switch]$Inizio)
    $file = Join-Path $script:Radice "Windows\WebcamLR.App\Strings\$script:Lingua\Resources.resw"
    if (-not $script:Risorse.ContainsKey($script:Lingua)) {
        $tabella = @{}
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($file)
        foreach ($dato in $xml.SelectNodes('/root/data')) { $tabella[$dato.GetAttribute('name')] = $dato.SelectSingleNode('value').InnerText }
        $script:Risorse[$script:Lingua] = $tabella
    }
    $valore = $script:Risorse[$script:Lingua][$Chiave]
    if ($null -eq $valore) { throw "Testo «$Chiave» non trovato in $file" }
    if ($Inizio) { $valore = ($valore -split '\{', 2)[0].Trim() }
    $valore
}
$script:Risorse = @{}

# ---------------------------------------------------------------- elementi

function Descrivi-Rettangolo($r) {
    if ($r.IsEmpty) { return '(vuoto)' }
    '{0},{1} {2}×{3}' -f [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height
}

function Tutti-Elementi {
    $risultato = New-Object System.Collections.ArrayList
    foreach ($finestra in (Finestre-App)) {
        [void]$risultato.Add($finestra)
        foreach ($e in $finestra.FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
            [void]$risultato.Add($e)
        }
    }
    , $risultato
}

function Trova-Elemento {
    <#
    Cerca in tutte le finestre dell'app un elemento per AutomationId esatto (in WinUI è il x:Name), poi per nome esatto,
    poi per nome che contiene il testo. Preferisce gli elementi a schermo. $null se non c'è.
    #>
    param([Parameter(Mandatory)][string]$Chi, [switch]$AncheNascosti)
    $finestre = Finestre-App
    # Prima le ricerche esatte, che UI Automation fa dentro il processo (veloci); poi il nome che contiene il testo.
    foreach ($proprieta in @($AE::AutomationIdProperty, $AE::NameProperty)) {
        $condizione = New-Object System.Windows.Automation.PropertyCondition($proprieta, $Chi)
        $trovati = @()
        foreach ($f in $finestre) {
            if ($f.Current.AutomationId -eq $Chi -or $f.Current.Name -eq $Chi) { $trovati += $f }
            $trovati += @($f.FindAll($TS::Descendants, $condizione) | ForEach-Object { $_ })
        }
        $visibili = @($trovati | Where-Object { try { -not $_.Current.IsOffscreen } catch { $false } })
        if ($visibili.Count -gt 0) { return $visibili[0] }
        if ($AncheNascosti -and $trovati.Count -gt 0) { return $trovati[0] }
    }
    $simili = @(Tutti-Elementi | Where-Object {
            try { $_.Current.Name -and $_.Current.Name.IndexOf($Chi, [StringComparison]::OrdinalIgnoreCase) -ge 0 } catch { $false } })
    $visibili = @($simili | Where-Object { try { -not $_.Current.IsOffscreen } catch { $false } })
    if ($visibili.Count -gt 0) { return $visibili[0] }
    if ($AncheNascosti -and $simili.Count -gt 0) { return $simili[0] }
    $null
}

function Attendi-Elemento {
    <# Aspetta fino a <secondi> che l'elemento ci sia e sia a schermo; lo restituisce, oppure errore. #>
    param([Parameter(Mandatory)][string]$Chi, [double]$Secondi = 10)
    $limite = (Get-Date).AddSeconds($Secondi)
    do {
        $e = Trova-Elemento $Chi
        if ($e) { return $e }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $limite)
    throw "Elemento «$Chi» non trovato in $Secondi s"
}

function Esiste {
    <# Vero se l'elemento c'è ed è a schermo adesso (senza aspettare). #>
    param([Parameter(Mandatory)][string]$Chi)
    [bool](Trova-Elemento $Chi)
}

function Descrivi-Elemento($e) {
    $c = $e.Current
    "$($c.ControlType.ProgrammaticName -replace 'ControlType\.', '') «$($c.Name)» id=$($c.AutomationId)"
}

function Clicca {
    <#
    Clicca un elemento (AutomationId o nome). Usa il comportamento dell'elemento (Invoke, Toggle, selezione, apri/chiudi);
    con -Mouse, o se non ne ha, un clic vero del mouse al centro.
    #>
    param([Parameter(Mandatory)][string]$Chi, [switch]$Mouse, [double]$Attesa = 10)
    $e = Attendi-Elemento $Chi $Attesa
    $descrizione = Descrivi-Elemento $e
    if (-not $Mouse) {
        foreach ($schema in @(
                [System.Windows.Automation.InvokePattern]::Pattern,
                [System.Windows.Automation.TogglePattern]::Pattern,
                [System.Windows.Automation.SelectionItemPattern]::Pattern,
                [System.Windows.Automation.ExpandCollapsePattern]::Pattern)) {
            $oggetto = $null
            if ($e.TryGetCurrentPattern($schema, [ref]$oggetto)) {
                switch ($schema.ProgrammaticName) {
                    'InvokePatternIdentifiers.Pattern' { $oggetto.Invoke() }
                    'TogglePatternIdentifiers.Pattern' { $oggetto.Toggle() }
                    'SelectionItemPatternIdentifiers.Pattern' { $oggetto.Select() }
                    'ExpandCollapsePatternIdentifiers.Pattern' {
                        if ($oggetto.Current.ExpandCollapseState -eq 'Collapsed') { $oggetto.Expand() } else { $oggetto.Collapse() }
                    }
                }
                Scrivi-Log "Clicca $descrizione ($($schema.ProgrammaticName -replace 'PatternIdentifiers.Pattern', ''))"
                Start-Sleep -Milliseconds 700
                return
            }
        }
    }
    $r = $e.Current.BoundingRectangle
    if ($r.IsEmpty) { throw "«$Chi» non ha una posizione a schermo" }
    Porta-Davanti
    [CollaudoNativo]::Clic([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    Scrivi-Log "Clicca $descrizione (mouse a $(Descrivi-Rettangolo $r))"
    Start-Sleep -Milliseconds 700
}

function Clicca-Punto {
    <# Un clic del mouse a coordinate dello schermo. #>
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y)
    [CollaudoNativo]::Clic($X, $Y)
    Scrivi-Log "Clic del mouse a $X,$Y"
    Start-Sleep -Milliseconds 500
}

function Scrivi {
    <#
    Scrive un testo. Con -In <elemento> imposta il valore della casella (ValuePattern), altrimenti lo batte sulla tastiera
    nel controllo che ha il fuoco.
    #>
    param([Parameter(Mandatory)][string]$Testo, [string]$In)
    if ($In) {
        $e = Attendi-Elemento $In
        $valore = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valore)) {
            $e.SetFocus()
            $valore.SetValue($Testo)
            Scrivi-Log "Scrivi «$Testo» in $(Descrivi-Elemento $e)"
            Start-Sleep -Milliseconds 400
            return
        }
        $e.SetFocus()
    }
    Porta-Davanti
    $protetto = [regex]::Replace($Testo, '[+^%~(){}\[\]]', '{$0}')
    [System.Windows.Forms.SendKeys]::SendWait($protetto)
    Scrivi-Log "Scrivi «$Testo» (tastiera)"
    Start-Sleep -Milliseconds 400
}

function Tasto {
    <#
    Preme dei tasti: nomi italiani (Tab, Invio, Esc, Spazio, Su, Giu, Sinistra, Destra, Canc, Indietro, F1…F12) separati
    da spazi, con Maiusc+, Ctrl+, Alt+ davanti (es. «Ctrl+S», «Maiusc+Tab», «Alt+F4»), oppure la sintassi di SendKeys.
    #>
    param([Parameter(Mandatory)][string]$Tasti)
    $nomi = @{
        'tab' = '{TAB}'; 'invio' = '{ENTER}'; 'enter' = '{ENTER}'; 'esc' = '{ESC}'; 'spazio' = ' '; 'su' = '{UP}';
        'giu' = '{DOWN}'; 'giù' = '{DOWN}'; 'sinistra' = '{LEFT}'; 'destra' = '{RIGHT}'; 'canc' = '{DELETE}';
        'indietro' = '{BACKSPACE}'; 'home' = '{HOME}'; 'fine' = '{END}'; 'pagsu' = '{PGUP}'; 'paggiu' = '{PGDN}'
    }
    $sequenza = ''
    foreach ($parte in ($Tasti -split '\s+' | Where-Object { $_ })) {
        $modificatori = ''
        $resto = $parte
        while ($resto -match '^(Maiusc|Shift|Ctrl|Alt)\+(.+)$') {
            switch ($Matches[1]) { 'Maiusc' { $modificatori += '+' } 'Shift' { $modificatori += '+' } 'Ctrl' { $modificatori += '^' } 'Alt' { $modificatori += '%' } }
            $resto = $Matches[2]
        }
        $chiave = $resto.ToLowerInvariant()
        if ($nomi.ContainsKey($chiave)) { $codice = $nomi[$chiave] }
        elseif ($chiave -match '^f([1-9]|1[0-2])$') { $codice = '{' + $chiave.ToUpperInvariant() + '}' }
        elseif ($resto.Length -eq 1) { $codice = $resto.ToLowerInvariant() }
        else { $codice = $resto }
        $sequenza += $modificatori + $codice
    }
    Porta-Davanti
    [System.Windows.Forms.SendKeys]::SendWait($sequenza)
    Scrivi-Log "Tasto $Tasti"
    Start-Sleep -Milliseconds 500
}

function Testi-Visibili {
    <# Tutti i nomi a schermo nelle finestre dell'app (per cercare un testo). #>
    , @(Tutti-Elementi | Where-Object { try { $_.Current.Name -and -not $_.Current.IsOffscreen } catch { $false } } |
        ForEach-Object { $_.Current.Name })
}

function Attendi-Testo {
    <# Aspetta fino a <secondi> che un testo compaia nell'app (nome di un elemento). Restituisce vero o falso. #>
    param([Parameter(Mandatory)][string]$Testo, [double]$Secondi = 10, [switch]$Obbligatorio)
    $limite = (Get-Date).AddSeconds($Secondi)
    do {
        $trovato = Testi-Visibili | Where-Object { $_.IndexOf($Testo, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
        if ($trovato) {
            Scrivi-Log "Attendi-Testo «$Testo»: c'è («$trovato»)"
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $limite)
    Scrivi-Log "Attendi-Testo «$Testo»: NON comparso in $Secondi s"
    if ($Obbligatorio) { throw "Testo «$Testo» non comparso in $Secondi s" }
    $false
}

# ---------------------------------------------------------------- schermate e alberi

function Nome-File([string]$Nome, [string]$Estensione) {
    $script:Numero++
    $pulito = ($Nome -replace '[^\w\-]+', '-').Trim('-')
    Join-Path $script:Uscita ('{0:D2}-{1}.{2}' -f $script:Numero, $pulito, $Estensione)
}

function Salva-Area([int]$X, [int]$Y, [int]$L, [int]$A, [string]$File, [System.Drawing.Imaging.ImageFormat]$Formato) {
    $bitmap = New-Object System.Drawing.Bitmap $L, $A, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $grafica = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $grafica.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $L, $A))
        $bitmap.Save($File, $Formato)
    } finally {
        $grafica.Dispose()
        $bitmap.Dispose()
    }
}

function Schermata {
    <# PNG di tutto lo schermo (o con -Finestra solo della finestra di WebcamLR) nella cartella dei risultati. #>
    param([Parameter(Mandatory)][string]$Nome, [switch]$Finestra)
    $file = Nome-File $Nome 'png'
    if ($Finestra -and (Finestra-App)) {
        $r = (Finestra-App).Current.BoundingRectangle
        Salva-Area ([int]$r.X) ([int]$r.Y) ([int]$r.Width) ([int]$r.Height) $file ([System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $schermo = [System.Windows.Forms.SystemInformation]::VirtualScreen
        Salva-Area $schermo.X $schermo.Y $schermo.Width $schermo.Height $file ([System.Drawing.Imaging.ImageFormat]::Png)
    }
    Scrivi-Log "Schermata $(Split-Path -Leaf $file)"
    $file
}

function Schermata-Elemento {
    <# Immagine di un solo elemento (es. il QR code). -Bmp per il formato BMP. #>
    param([Parameter(Mandatory)][string]$Chi, [Parameter(Mandatory)][string]$Nome, [switch]$Bmp, [int]$Margine = 12)
    $e = Attendi-Elemento $Chi
    $r = $e.Current.BoundingRectangle
    $estensione = 'png'
    $formato = [System.Drawing.Imaging.ImageFormat]::Png
    if ($Bmp) { $estensione = 'bmp'; $formato = [System.Drawing.Imaging.ImageFormat]::Bmp }
    $file = Nome-File $Nome $estensione
    Salva-Area ([int]$r.X - $Margine) ([int]$r.Y - $Margine) ([int]$r.Width + 2 * $Margine) ([int]$r.Height + 2 * $Margine) $file $formato
    Scrivi-Log "Schermata di $(Descrivi-Elemento $e): $(Split-Path -Leaf $file)"
    $file
}

function Albero-UI {
    <#
    Scrive in <nome>.txt l'albero dell'interfaccia di tutte le finestre dell'app: tipo, Name, AutomationId, stato
    (disattivato, fuori schermo, valore, interruttore) e posizione. Gli elementi fuori schermo si saltano senza -Tutto.
    #>
    param([Parameter(Mandatory)][string]$Nome, [switch]$Tutto)
    $file = Nome-File $Nome 'txt'
    $righe = New-Object System.Collections.Generic.List[string]
    $camminatore = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    function Visita($elemento, [int]$livello) {
        if ($livello -gt 60) { return }
        try { $c = $elemento.Current } catch { return }
        if ($c.IsOffscreen -and -not $Tutto -and $livello -gt 0) { return }
        $note = @()
        if (-not $c.IsEnabled) { $note += 'disattivato' }
        if ($c.IsOffscreen) { $note += 'fuori schermo' }
        $schema = $null
        if ($elemento.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$schema)) { $note += "interruttore=$($schema.Current.ToggleState)" }
        if ($elemento.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$schema)) {
            $v = $schema.Current.Value
            if ($v) { $note += "valore=«$($v.Substring(0, [Math]::Min(80, $v.Length)))»" }
        }
        if ($elemento.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$schema)) { $note += "valore=$($schema.Current.Value)" }
        if ($elemento.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$schema)) { if ($schema.Current.IsSelected) { $note += 'selezionato' } }
        if ($elemento.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$schema)) { $note += "apertura=$($schema.Current.ExpandCollapseState)" }
        $tipo = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $nome = $c.Name -replace "`r?`n", ' ⏎ '
        $riga = ('  ' * $livello) + "$tipo «$nome»"
        if ($c.AutomationId) { $riga += " id=$($c.AutomationId)" }
        if ($c.ClassName -and $livello -eq 0) { $riga += " classe=$($c.ClassName)" }
        if ($note.Count) { $riga += ' [' + ($note -join ', ') + ']' }
        $riga += ' @ ' + (Descrivi-Rettangolo $c.BoundingRectangle)
        $righe.Add($riga)
        $figlio = $camminatore.GetFirstChild($elemento)
        while ($figlio) {
            Visita $figlio ($livello + 1)
            $figlio = $camminatore.GetNextSibling($figlio)
        }
    }
    $finestre = Finestre-App
    if ($finestre.Count -eq 0) { $righe.Add('(nessuna finestra di WebcamLR)') }
    foreach ($f in $finestre) { Visita $f 0 }
    [System.IO.File]::WriteAllLines($file, $righe, (New-Object System.Text.UTF8Encoding $true))
    Scrivi-Log "Albero-UI $(Split-Path -Leaf $file) ($($righe.Count) elementi)"
    $file
}

function Fotografa {
    <# Schermata e albero dell'interfaccia con lo stesso nome. #>
    param([Parameter(Mandatory)][string]$Nome)
    [void](Schermata $Nome)
    [void](Albero-UI $Nome)
}

# ---------------------------------------------------------------- telefono finto

function Avvia-TelefonoFinto {
    <#
    Avvia il telefono finto (Strumenti/collaudo/TelefonoFinto) con le sue opzioni, es.
      Avvia-TelefonoFinto --nome 'iPhone di Anna' --durata 120 --interrompi-dopo 20
    -DalQR: prima legge il QR code mostrato dall'app (Leggi-QR), così entra senza conferma.
    Registro in telefono-<nome>.log; restituisce il nome con cui fermarlo o aspettarlo.
    #>
    param([switch]$DalQR, [Parameter(ValueFromRemainingArguments)][string[]]$Opzioni)
    if (-not (Test-Path $script:TelefonoExe)) { throw "TelefonoFinto non compilato: $script:TelefonoExe" }
    $opzioniTutte = @()
    if ($Opzioni) { $opzioniTutte += $Opzioni }
    $nome = 'iPhone finto'
    for ($i = 0; $i -lt $opzioniTutte.Count - 1; $i++) { if ($opzioniTutte[$i] -eq '--nome') { $nome = $opzioniTutte[$i + 1] } }
    if ($DalQR) { $opzioniTutte += @('--qr', (Leggi-QR)) }
    $pulito = ($nome -replace '[^\w\-]+', '-').Trim('-')
    $registro = Join-Path $script:Uscita "telefono-$pulito.log"
    $ferma = Join-Path $env:TEMP "telefono-$pulito-$PID.ferma"
    Remove-Item -Force -ErrorAction SilentlyContinue $ferma
    $opzioniTutte += @('--registro', $registro, '--ferma', $ferma)
    $argomenti = ($opzioniTutte | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $info = New-Object System.Diagnostics.ProcessStartInfo $script:TelefonoExe
    $info.Arguments = $argomenti
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $processo = [System.Diagnostics.Process]::Start($info)
    $script:Telefoni[$nome] = @{ Processo = $processo; Registro = $registro; Ferma = $ferma }
    Scrivi-Log "Avvia-TelefonoFinto «$nome» (processo $($processo.Id)): $argomenti"
    $nome
}

function Registro-Telefono {
    param([string]$Nome = 'iPhone finto')
    $t = $script:Telefoni[$Nome]
    if (-not $t -or -not (Test-Path $t.Registro)) { return @() }
    , @(Get-Content -LiteralPath $t.Registro -Encoding UTF8)
}

function Attendi-Telefono {
    <#
    Aspetta una riga nel registro del telefono finto: «ACCETTATO», «CODICE», «RIFIUTATO», «Video:», «FINE»… Restituisce la
    riga o $null. Con -Obbligatorio un errore se non arriva.
    #>
    param([Parameter(Mandatory)][string]$Testo, [double]$Secondi = 30, [string]$Nome = 'iPhone finto', [switch]$Obbligatorio)
    $limite = (Get-Date).AddSeconds($Secondi)
    do {
        $riga = Registro-Telefono $Nome | Where-Object { $_ -like "*$Testo*" } | Select-Object -Last 1
        if ($riga) {
            Scrivi-Log "Telefono «$Nome»: $riga"
            return $riga
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $limite)
    Scrivi-Log "Telefono «$Nome»: «$Testo» NON arrivato in $Secondi s"
    if ($Obbligatorio) { throw "Il telefono «$Nome» non ha scritto «$Testo» in $Secondi s" }
    $null
}

function Ferma-TelefonoFinto {
    <# Chiude bene il telefono finto (arrivederci). Senza nome: tutti. #>
    param([string]$Nome)
    $nomi = @($script:Telefoni.Keys)
    if ($Nome) { $nomi = @($Nome) }
    foreach ($n in $nomi) {
        $t = $script:Telefoni[$n]
        if (-not $t) { continue }
        if (-not $t.Processo.HasExited) {
            try { [void][CollaudoNativo]::NtResumeProcess($t.Processo.Handle) } catch { }
            Set-Content -LiteralPath $t.Ferma -Value 'ferma'
            if (-not $t.Processo.WaitForExit(8000)) { $t.Processo.Kill() }
        }
        Scrivi-Log "Telefono «$n» fermato (codice $($t.Processo.ExitCode))"
        Remove-Item -Force -ErrorAction SilentlyContinue $t.Ferma
        $script:Telefoni.Remove($n)
    }
}

function Rete-Spenta {
    <#
    Simula la rete che cade tra telefono e PC: il processo del telefono finto si sospende (niente pong, video né stato, la
    connessione TCP resta aperta), come un Wi-Fi che sparisce. Spegnere la scheda di rete del runner non si può: GitHub
    Actions perderebbe il contatto con la macchina. Senza nome: tutti i telefoni.
    #>
    param([string]$Nome)
    $nomi = @($script:Telefoni.Keys)
    if ($Nome) { $nomi = @($Nome) }
    foreach ($n in $nomi) {
        [void][CollaudoNativo]::NtSuspendProcess($script:Telefoni[$n].Processo.Handle)
        Scrivi-Log "Rete-Spenta: telefono «$n» sospeso"
    }
}

function Rete-Accesa {
    <# La rete torna: il telefono finto riprende da dove era (se il PC ha chiuso nel frattempo, con --riconnetti-sempre si ricollega). #>
    param([string]$Nome)
    $nomi = @($script:Telefoni.Keys)
    if ($Nome) { $nomi = @($Nome) }
    foreach ($n in $nomi) {
        [void][CollaudoNativo]::NtResumeProcess($script:Telefoni[$n].Processo.Handle)
        Scrivi-Log "Rete-Accesa: telefono «$n» ripreso"
    }
}

function Leggi-QR {
    <#
    Salva in BMP il QR code per collegarsi che l'app mostra adesso (quello grande del primo avvio, o quello della colonna di
    sinistra / del menu della pillola) e restituisce il percorso: Avvia-TelefonoFinto --qr <file> lo legge. Il gettone
    nel QR cambia dopo ogni uso.
    #>
    foreach ($id in @('ImmagineQRGrande', 'ImmagineQR')) {
        if (Esiste $id) { return (Schermata-Elemento $id 'qr' -Bmp) }
    }
    throw 'Nessun QR code a schermo (ImmagineQRGrande o ImmagineQR)'
}

# ---------------------------------------------------------------- fine del copione

function Raccogli-Registri {
    <# Copia nella cartella dei risultati i file dell'app (%LOCALAPPDATA%\WebcamLR: Errori.txt, preferenze) e l'elenco. #>
    $destinazione = Join-Path $script:Uscita 'dati-app'
    if (Test-Path $script:DatiApp) {
        New-Item -ItemType Directory -Force -Path $destinazione | Out-Null
        Get-ChildItem -LiteralPath $script:DatiApp -Recurse -File | ForEach-Object {
            "{0,10}  {1:yyyy-MM-dd HH:mm:ss}  {2}" -f $_.Length, $_.LastWriteTime, $_.FullName.Substring($script:DatiApp.Length + 1)
        } | Set-Content -LiteralPath (Join-Path $destinazione 'elenco.txt') -Encoding UTF8
        # La chiave del PC (identita) resta fuori: è cifrata con DPAPI e non serve a nessuno.
        Get-ChildItem -LiteralPath $script:DatiApp -File | Where-Object { $_.Name -ne 'identita' -and $_.Length -lt 2MB } |
            Copy-Item -Destination $destinazione -Force
        if (Test-Path (Join-Path $script:DatiApp 'Errori.txt')) {
            Segnala-Problema "L'app ha scritto Errori.txt (vedi dati-app/Errori.txt)"
            Get-Content -LiteralPath (Join-Path $script:DatiApp 'Errori.txt') -Encoding UTF8 -TotalCount 40 |
                ForEach-Object { Scrivi-Log "  Errori.txt: $_" }
        }
    }
}

function Chiudi-Tutto {
    Ferma-TelefonoFinto
    try { Chiudi-App } catch { Scrivi-Log "Chiudi-App: $($_.Exception.Message)" }
    Get-Process -Name WebcamLR -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }
}

Export-ModuleMember -Function *-*, Passo, Problemi, Esiste, Clicca, Scrivi, Tasto, Schermata, Fotografa
