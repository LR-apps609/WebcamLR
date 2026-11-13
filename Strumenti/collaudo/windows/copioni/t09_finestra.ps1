# t09 · Anna: portatile 1366×768 con la scala di Windows al 150 % (911×512 DIP: sotto la misura minima di 960×600 DIP).
# Cambia risoluzione e scala dello schermo del runner (scala con DisplayConfigSetDeviceInfo, come il pannello Schermo di
# Windows, senza uscire dalla sessione), poi lancia t09/prova.ps1 in un processo nuovo per ogni configurazione.
# Alla fine le schermate (JPEG) e i registri escono nel registro del lavoro in base64 (gli artifact sono bloccati).

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class T09Schermo
{
    [StructLayout(LayoutKind.Sequential)] public struct Luid { public uint Basso; public int Alto; }
    [StructLayout(LayoutKind.Sequential)] public struct Intestazione { public int Tipo; public int Misura; public Luid Scheda; public uint Id; }
    [StructLayout(LayoutKind.Sequential)] public struct ScalaLetta { public Intestazione Testa; public int Minima; public int Attuale; public int Massima; }
    [StructLayout(LayoutKind.Sequential)] public struct ScalaScritta { public Intestazione Testa; public int Relativa; }
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint percorsi, out uint modi);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint percorsi, byte[] p, ref uint modi, byte[] m, IntPtr topologia);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref ScalaLetta pacchetto);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref ScalaScritta pacchetto);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dispositivo, int modo, ref DEVMODE impostazioni);

    public static string Modi()
    {
        var visti = new SortedSet<string>();
        var m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        for (int i = 0; i < 400 && EnumDisplaySettings(null, i, ref m); i++) visti.Add(m.dmPelsWidth + "x" + m.dmPelsHeight);
        return string.Join(" ", visti);
    }

    static bool Sorgente(out Luid scheda, out uint id)
    {
        scheda = new Luid(); id = 0;
        uint np, nm;
        if (GetDisplayConfigBufferSizes(2, out np, out nm) != 0 || np == 0) return false;
        var p = new byte[np * 72]; var m = new byte[nm * 64];
        if (QueryDisplayConfig(2, ref np, p, ref nm, m, IntPtr.Zero) != 0) return false;
        scheda.Basso = BitConverter.ToUInt32(p, 0); scheda.Alto = BitConverter.ToInt32(p, 4); id = BitConverter.ToUInt32(p, 8);
        return true;
    }

    /// "minima attuale massima" relative alla scala consigliata (passi della scala di Windows), o un errore.
    public static string Leggi()
    {
        Luid s; uint id;
        if (!Sorgente(out s, out id)) return "errore QueryDisplayConfig";
        var l = new ScalaLetta(); l.Testa.Tipo = -3; l.Testa.Misura = Marshal.SizeOf(typeof(ScalaLetta)); l.Testa.Scheda = s; l.Testa.Id = id;
        int e = DisplayConfigGetDeviceInfo(ref l);
        return e != 0 ? "errore " + e : l.Minima + " " + l.Attuale + " " + l.Massima;
    }

    public static int Scrivi(int relativa)
    {
        Luid s; uint id;
        if (!Sorgente(out s, out id)) return -1;
        var w = new ScalaScritta(); w.Testa.Tipo = -4; w.Testa.Misura = Marshal.SizeOf(typeof(ScalaScritta)); w.Testa.Scheda = s; w.Testa.Id = id; w.Relativa = relativa;
        return DisplayConfigSetDeviceInfo(ref w);
    }
}
'@

$passi = @(100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500)
$prova = Join-Path $PSScriptRoot '..\t09\prova.ps1'
Scrivi-Log "Modi dello schermo: $([T09Schermo]::Modi())"

function Prova-Configurazione([int]$L, [int]$A, [int]$Percento, [string]$Etichetta, [switch]$Breve, [switch]$AncheSeOltre) {
    Imposta-Schermo $L $A
    $letta = [T09Schermo]::Leggi()
    Scrivi-Log "Scala a ${L}×${A} (relativa alla consigliata, che qui si assume 100 %): minima attuale massima = $letta"
    $relativa = [array]::IndexOf($passi, $Percento)
    if ($letta -match '^(-?\d+) (-?\d+) (-?\d+)$') {
        $massima = [int]$Matches[3]
        if ($relativa -gt $massima) {
            Scrivi-Log "  Windows a ${L}×${A} non offre $Percento % (al massimo $($passi[$massima]) %)"
            if (-not $AncheSeOltre) { return $false }
            $relativa = $massima
            $Percento = $passi[$massima]
        }
    }
    $esito = [T09Schermo]::Scrivi($relativa)
    Start-Sleep -Seconds 4
    Scrivi-Log "  scala $Percento % (relativa $relativa): esito $esito, ora $([T09Schermo]::Leggi())"
    $cartella = Join-Path (Cartella-Risultati) $Etichetta
    New-Item -ItemType Directory -Force -Path $cartella | Out-Null
    $argomenti = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $prova, '-Cartella', $cartella, '-Etichetta', $Etichetta)
    if ($Breve) { $argomenti += '-Breve' }
    $figlio = Start-Process -FilePath 'powershell.exe' -ArgumentList $argomenti -PassThru -NoNewWindow
    if (-not $figlio.WaitForExit(600000)) { Segnala-Problema "$Etichetta · la prova non è finita in 10 minuti"; try { $figlio.Kill() } catch { } }
    Get-Process -Name WebcamLR, TelefonoFinto -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch { } }
    $esitoFiglio = Join-Path $cartella 'esito.txt'
    if (Test-Path $esitoFiglio) { Get-Content $esitoFiglio -Encoding UTF8 | Select-Object -Skip 2 | ForEach-Object { Segnala-Problema ($_ -replace '^- ', '') } }
    [void][T09Schermo]::Scrivi(0)
    return $true
}

try {
    # Anna: 1366×768 al 150 %. Se Windows non lo offre, il massimo che offre a 1366×768, e una configurazione con quasi la
    # stessa area in DIP (1600×900 al 175 % = 914×514, oppure 1920×1080 al 200 % = 960×540).
    $fatta = Prova-Configurazione 1366 768 150 'a-1366x768-150'
    if (-not $fatta) {
        [void](Prova-Configurazione 1366 768 150 'a-1366x768-massima' -AncheSeOltre)
        if (-not (Prova-Configurazione 1600 900 175 'b-1600x900-175')) {
            [void](Prova-Configurazione 1920 1080 200 'b-1920x1080-200' -AncheSeOltre)
        }
    }
    # Per confronto, breve: 1366×768 al 125 % (1093×614 DIP, sopra la misura minima).
    [void](Prova-Configurazione 1366 768 125 'c-1366x768-125' -Breve)
} finally {
    [void][T09Schermo]::Scrivi(0)
    Imposta-Schermo 1920 1080
    # Risultati nel registro del lavoro: schermate in JPEG e testi, in uno zip in base64.
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $sorgente = Cartella-Risultati
        $temp = Join-Path $env:TEMP 't09-pacco'
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $parametri = New-Object System.Drawing.Imaging.EncoderParameters 1
        $parametri.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 72L
        Get-ChildItem -LiteralPath $sorgente -Recurse -File | ForEach-Object {
            $relativo = $_.FullName.Substring($sorgente.Length + 1)
            $dest = Join-Path $temp $relativo
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            if ($_.Extension -eq '.png') {
                $img = [System.Drawing.Image]::FromFile($_.FullName)
                try { $img.Save(($dest -replace '\.png$', '.jpg'), $jpeg, $parametri) } finally { $img.Dispose() }
            } elseif ($_.Extension -in '.txt', '.log' -and $_.Length -lt 3MB) {
                Copy-Item $_.FullName $dest
            }
        }
        $zip = Join-Path $env:TEMP 't09-pacco.zip'
        Remove-Item -Force -ErrorAction SilentlyContinue $zip
        [System.IO.Compression.ZipFile]::CreateFromDirectory($temp, $zip)
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($zip))
        Write-Host '=====T09-INIZIO====='
        for ($i = 0; $i -lt $b64.Length; $i += 16000) { Write-Host $b64.Substring($i, [math]::Min(16000, $b64.Length - $i)) }
        Write-Host '=====T09-FINE====='
    } catch { Write-Host "t09: pacco non riuscito: $($_.Exception.Message)" }
}
