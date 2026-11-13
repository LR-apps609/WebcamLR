# Collaudo t13 (Elena): preferenze con valori fuori scala o rotti (come dopo un file rovinato o una versione vecchia),
# profili con numeri assurdi e nomi lunghissimi, cursori portati fuori scala con UI Automation, «Segnala un bug» vuoto,
# di soli spazi ed enorme, doppio clic su «Copia», finestra salvata fuori dallo schermo.
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartellaT13 = Cartella-Risultati
$dati = Join-Path $env:LOCALAPPDATA 'WebcamLR'
function Scrivi-Preferenza([string]$Nome, [string]$Valore) {
    New-Item -ItemType Directory -Force -Path $dati | Out-Null
    [IO.File]::WriteAllText((Join-Path $dati $Nome), $Valore)
    Scrivi-Log "PREFERENZA $Nome = «$(if ($Valore.Length -gt 120) { $Valore.Substring(0, 120) + "… ($($Valore.Length) caratteri)" } else { $Valore })»"
}
try {
    Azzera-Dati
    $nomeProfiloLungo = '🎥 Riunione del lunedì mattina con tutto il reparto commerciale e i clienti di Milano 🙃 ' + ('x' * 150)
    $profili = @"
{"Assurdo":{"Obiettivo":"obiettivo-inesistente","Zoom":1e308,"Torcia":true,"Esposizione":-1e308,"BiancoAutomatico":false,"Bianco":1e9,"EsposizioneManuale":true,"Iso":-5,"Tempo":-2147483648},
 "$nomeProfiloLungo":{"Obiettivo":null,"Zoom":1,"Torcia":false,"Esposizione":0,"BiancoAutomatico":true,"Bianco":5000,"EsposizioneManuale":false,"Iso":100,"Tempo":0},
 "Zeri":{"Obiettivo":"","Zoom":0,"Torcia":false,"Esposizione":0,"BiancoAutomatico":false,"Bianco":0,"EsposizioneManuale":true,"Iso":0,"Tempo":0}}
"@
    Scrivi-Preferenza 'profili.json' $profili
    Scrivi-Preferenza 'qualita-flusso' '8k-ultra-120fps'
    Scrivi-Preferenza 'vista' 'boh'
    Scrivi-Preferenza 'gobbo-velocita' '1e308'
    Scrivi-Preferenza 'gobbo-dimensione' 'gigantesca'
    Scrivi-Preferenza 'effetti-computer.json' '{rotto: [1,2,'
    Scrivi-Preferenza 'fidati.json' '[[[nonèjson'
    Scrivi-Preferenza 'schermata-attesa' '..\..\..\Windows\win.ini'
    Scrivi-Preferenza 'scritta-nome' ('Elena ' * 800)
    Scrivi-Preferenza 'livello-sfocatura' '-999'
    Scrivi-Preferenza 'ultimo-sfondo' '..\..\nessuno.png'
    Scrivi-Preferenza 'microfono-uscita' 'dispositivo-che-non-esiste'
    Scrivi-Preferenza 'webcam-inquadratura' '42'

    $partita = Passo 'Avvio con le preferenze rovinate' {
        Avvia-App | Out-Null
        Start-Sleep -Seconds 4
        Fotografa 'avvio-preferenze-rovinate'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
    } -Esito
    if (-not $partita) {
        Segnala-Problema "Con le preferenze rovinate l'app non parte"
        throw 'app non partita'
    }

    Passo 'Telefono dal QR' {
        Avvia-TelefonoFinto -DalQR --nome 'Elena impostazioni' --durata 500 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'Elena impostazioni' -Obbligatorio | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome 'Elena impostazioni' | Out-Null
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 3
        Fotografa 'completo-con-telefono'
    }

    Passo 'Profili: elenco e profilo «Assurdo»' {
        Clicca 'PulsanteProfili'
        Start-Sleep -Seconds 1
        Fotografa 'menu-profili'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Clicca 'Assurdo'
        Start-Sleep -Seconds 3
        Fotografa 'profilo-assurdo-applicato'
        Ultime-Telefono 'Elena impostazioni' 8
        App-Viva | Out-Null
    }
    Passo 'Profili: «Zeri»' {
        Clicca 'PulsanteProfili'
        Start-Sleep -Seconds 1
        Clicca 'Zeri'
        Start-Sleep -Seconds 3
        Fotografa 'profilo-zeri-applicato'
        Ultime-Telefono 'Elena impostazioni' 5
        App-Viva | Out-Null
    }
    Passo 'Profili: salva con un nome di 300 caratteri, poi solo spazi' {
        Clicca 'PulsanteProfili'
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'Profili_Salva')
        Start-Sleep -Seconds 1
        $casella = Casella-Modifica
        if (-not $casella) { throw 'nessuna casella nel dialogo del profilo' }
        $letto = Imposta-Valore $casella ('🙃 Elena ' * 40)
        Fotografa 'profilo-nome-lungo'
        Scrivi-Log "  la casella (MaxLength 40) tiene $($letto.Length) caratteri"
        Tasto 'Invio'
        Start-Sleep -Seconds 1
        Clicca 'PulsanteProfili'
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'Profili_Salva')
        Start-Sleep -Seconds 1
        $casella = Casella-Modifica
        Imposta-Valore $casella '        ' | Out-Null
        Fotografa 'profilo-nome-spazi'
        Tasto 'Invio'
        Start-Sleep -Seconds 1
        Fotografa 'profilo-nome-spazi-dopo-invio'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Clicca 'PulsanteProfili'
        Start-Sleep -Seconds 1
        Fotografa 'menu-profili-dopo'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Tasto 'Esc'
    }

    Passo 'Cursori fuori scala con UI Automation' {
        foreach ($id in 'CursoreZoom', 'CursoreEsposizione', 'CursoreLuminosita', 'CursoreContrasto', 'CursoreSaturazione', 'CursoreNitidezza', 'CursorePelle') {
            $e = Trova-Elemento $id -AncheNascosti
            if (-not $e) { Scrivi-Log "  ${id}: non c'è"; continue }
            $rv = $null
            if (-not $e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rv)) { Scrivi-Log "  ${id}: niente RangeValue"; continue }
            $min = $rv.Current.Minimum; $max = $rv.Current.Maximum; $prima = $rv.Current.Value
            foreach ($v in @(1e9, -1e9, [double]::NaN)) {
                try { $rv.SetValue($v); Scrivi-Log "  ${id}: SetValue($v) accettato → $($rv.Current.Value) (min $min, max $max, prima $prima)" }
                catch { Scrivi-Log "  ${id}: SetValue($v) rifiutato: $($_.Exception.GetType().Name) $($_.Exception.Message)" }
                Start-Sleep -Milliseconds 300
            }
        }
        Start-Sleep -Seconds 2
        Fotografa 'cursori-fuori-scala'
        Ultime-Telefono 'Elena impostazioni' 8
        App-Viva | Out-Null
    }

    # ------------------------------------------------ Segnala un bug
    $bug = Testo-App 'Bug_CosaESuccesso'
    $copia = Testo-App 'Bug_Copia'
    Passo 'Segnala un bug: vuoto' {
        Tasto 'F1'
        Start-Sleep -Seconds 2
        Clicca (Testo-App 'App_SegnalaBug')
        Start-Sleep -Seconds 1
        Fotografa 'segnala-vuoto'
        $p = Trova-Elemento $copia
        Scrivi-Log "  «$copia» attivo: $($p.Current.IsEnabled)"
        if ($p.Current.IsEnabled) { Segnala-Problema 'Segnala un bug: «Copia» attivo con la descrizione vuota' }
    }
    Passo 'Segnala un bug: solo spazi e a capo' {
        $casella = Casella-Modifica
        Imposta-Valore $casella "    `r`n   `r`n  " | Out-Null
        $p = Trova-Elemento $copia
        Scrivi-Log "  «$copia» attivo con solo spazi: $($p.Current.IsEnabled)"
        Fotografa 'segnala-spazi'
    }
    Passo 'Segnala un bug: 300 000 caratteri con emoji' {
        $blocco = "Errore 🔥📷💻 ‮al contrario‬ مرحبا «virgolette» <tag> & ancora`r`n"
        $testo = ($blocco * [int](300000 / $blocco.Length + 1)).Substring(0, 300000)
        $casella = Casella-Modifica
        $inizio = Get-Date
        $letto = Imposta-Valore $casella $testo
        Scrivi-Log "  testo enorme: riletti $($letto.Length) caratteri, $([int]((Get-Date) - $inizio).TotalSeconds) s"
        Start-Sleep -Seconds 2
        Fotografa 'segnala-enorme'
        $p = Trova-Elemento $copia
        $inizio = Get-Date
        Clic-Rapido $p 2 80
        Start-Sleep -Seconds 3
        Scrivi-Log "  doppio clic su «$copia»: $([int]((Get-Date) - $inizio).TotalSeconds) s"
        Fotografa 'segnala-enorme-copiata'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Add-Type -AssemblyName System.Windows.Forms
        try { $appunti = [System.Windows.Forms.Clipboard]::GetText(); Scrivi-Log "  appunti: $($appunti.Length) caratteri" } catch { Scrivi-Log "  appunti non letti: $($_.Exception.Message)" }
        $bozza = Join-Path $dati 'segnalazione-bozza.txt'
        Scrivi-Log "  bozza su disco: $(if (Test-Path $bozza) { (Get-Item $bozza).Length } else { 'nessuna' }) byte"
        App-Viva | Out-Null
    }
    Passo 'Segnala un bug: chiudo e riapro con una bozza enorme' {
        Tasto 'Esc'
        Start-Sleep -Seconds 1
        $casella = $null
        # di nuovo il testo enorme, senza copiarlo: deve restare come bozza
        Tasto 'F1'
        Start-Sleep -Seconds 2
        Clicca (Testo-App 'App_SegnalaBug')
        Start-Sleep -Seconds 1
        $casella = Casella-Modifica
        Imposta-Valore $casella (('Bozza enorme di Elena 🙃 ' * 12000)) | Out-Null
        Tasto 'Esc'
        Start-Sleep -Seconds 1
        $inizio = Get-Date
        Tasto 'F1'
        Start-Sleep -Seconds 1
        Clicca (Testo-App 'App_SegnalaBug')
        Scrivi-Log "  riapertura con la bozza enorme: $([int]((Get-Date) - $inizio).TotalMilliseconds) ms"
        Start-Sleep -Seconds 1
        Fotografa 'segnala-bozza-riaperta'
        Tasto 'Esc'
    }
    Ferma-TelefonoFinto
    App-Viva | Out-Null

    # ------------------------------------------------ finestra salvata fuori dallo schermo
    foreach ($caso in @(
            @{ Nome = 'lontanissima'; Valore = '-32000;-32000;800;600;0' },
            @{ Nome = 'gigante'; Valore = 'dip;0;0;99999;99999;0' },
            @{ Nome = 'minuscola'; Valore = '100;100;1;1;0' })) {
        Passo "Finestra salvata «$($caso.Nome)»" {
            Chiudi-App
            Start-Sleep -Seconds 1
            Scrivi-Preferenza 'finestra' $caso.Valore
            Avvia-App | Out-Null
            Start-Sleep -Seconds 3
            $f = Finestra-App
            $r = $f.Current.BoundingRectangle
            Scrivi-Log "  finestra «$($caso.Nome)»: $(Descrivi-Rettangolo $r)"
            if ($r.X + $r.Width -lt 50 -or $r.Y + $r.Height -lt 50 -or $r.X -gt 1900 -or $r.Y -gt 1060) {
                Segnala-Problema "Con la posizione salvata «$($caso.Valore)» la finestra si apre fuori dallo schermo ($(Descrivi-Rettangolo $r))"
            }
            Schermata "finestra-$($caso.Nome)"
        }
    }
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT13
}
