# Collaudo t10 (Stefano), seconda parte: gobbo senza e con telefono Pro, clic destro vero sul video, finestra Pro,
# pulsante mini, «Esci dalla vista pulita», Aiuto in inglese.

Add-Type -Namespace T10 -Name Mouse -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, System.UIntPtr e);
'@
function ClicDestro([string]$Id) {
    $e = Trova-Elemento $Id -AncheNascosti
    if (-not $e) { throw "«$Id» non trovato" }
    $r = $e.Current.BoundingRectangle
    $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    [T10.Mouse]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 200
    [T10.Mouse]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
    [T10.Mouse]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
    Scrivi-Log "Clic destro su $Id a $x,$y"
    Start-Sleep -Seconds 1
}
function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4

Passo 'Gobbo senza telefono: la pagina e il pulsante' {
    Apri-Impostazioni
    Clicca (Testo-App 'Impostazioni_Gobbo') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
    $p = Trova-Elemento 'PulsanteGobbo' -AncheNascosti
    if ($p) { Scrivi-Log "  PulsanteGobbo: attivo $($p.Current.IsEnabled), aiuto «$($p.Current.HelpText)»" }
    Fotografa 'gobbo-pagina-senza-telefono'
    if ($p -and $p.Current.IsEnabled) { Clicca 'PulsanteGobbo'; Start-Sleep -Seconds 2; Fotografa 'gobbo-senza-telefono-aperto'; Tasto 'Esc' }
    Chiudi-Impostazioni
}
Passo 'WebcamLR Pro: «Come sbloccarla»' {
    Clicca 'PulsanteAccount'
    Start-Sleep -Milliseconds 700
    Clicca 'PulsanteProAccount'
    Start-Sleep -Seconds 2
    Fotografa 'pro-come-sbloccarla'
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
    Tasto 'Esc'
}
Passo 'Telefoni › «Il telefono non trova il PC?»' {
    Apri-Impostazioni
    Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
    Clicca 'Il telefono non trova il PC?'
    Start-Sleep -Seconds 2
    Fotografa 'non-trova-il-pc'
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
    Tasto 'Esc'
    Chiudi-Impostazioni
}

$collegato = Passo 'Telefono finto Pro dal QR code' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone di Stefano' --durata 400 --pro --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Stefano' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Stefano' | Out-Null
    Start-Sleep -Seconds 4
} -Esito

Passo 'Clic destro vero sul video' {
    ClicDestro 'VideoElaborato'
    Fotografa 'clic-destro-video'
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
    Tasto 'Esc'
}
Passo 'Gobbo con il telefono Pro (dalla pagina)' {
    Apri-Impostazioni
    Clicca (Testo-App 'Impostazioni_Gobbo') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
    Fotografa 'gobbo-pagina-con-telefono'
    $p = Trova-Elemento 'PulsanteGobbo' -AncheNascosti
    if ($p) { Scrivi-Log "  PulsanteGobbo: attivo $($p.Current.IsEnabled)" }
    Clicca 'PulsanteGobbo' -AncheNascosti
    Start-Sleep -Seconds 2
    Fotografa 'gobbo-finestra'
    Scrivi-Log "  finestre: $(Descrivi-Finestre)"
    Scrivi 'Buongiorno a tutti, oggi vi parlo di WebcamLR. 1234 + - F' -In (Testo-App 'Gobbo_TestoNome')
    Start-Sleep -Seconds 1
    Fotografa 'gobbo-con-testo'
    $c = Trova-Elemento (Testo-App 'Gobbo_TestoNome')
    if ($c) { try { Scrivi-Log "  testo: «$($c.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value)»" } catch { } }
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
    Clicca (Testo-App 'Gobbo_Avvia')
    Start-Sleep -Seconds 3
    Fotografa 'gobbo-avviato'
    Tasto 'Esc'
    Chiudi-Impostazioni
}
Passo 'Pulsante mini e ritorno' {
    Porta-Davanti
    Clicca 'PulsanteMini' -AncheNascosti
    Start-Sleep -Seconds 2
    Fotografa 'pulsante-mini'
    ClicDestro 'VideoElaborato'
    Fotografa 'mini-clic-destro'
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
    Tasto 'Esc'
    Tasto 'Esc'
    Start-Sleep -Seconds 2
}
Passo 'Vista pulita: il pulsante «Esci dalla vista pulita»' {
    Tasto 'Ctrl+Maiusc+P'
    Start-Sleep -Seconds 2
    Clicca (Testo-App 'Vista_EsciPulita') -Mouse
    Start-Sleep -Seconds 2
    Fotografa 'uscita-vista-pulita'
}
Ferma-TelefonoFinto

Passo "Inglese: Aiuto" {
    Lingua-Inglese -Riavvia
    Start-Sleep -Seconds 4
    Clicca 'PulsanteAiuto'
    Start-Sleep -Seconds 2
    Fotografa 'inglese-aiuto'
    Scrivi-Log "  a schermo: $(Elenco-Visibili)"
}
