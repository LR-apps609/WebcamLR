# Collaudo t11 (Marta, cieca: Assistente vocale e solo tastiera). Dal primo avvio al video e alle Impostazioni SOLO con
# la tastiera (Tab, Maiusc+Tab, frecce, Invio, Spazio, Esc, scorciatoie). A ogni tasto si annota dove va il fuoco
# (UI Automation FocusedElement), con ritagli dello schermo attorno al fuoco per vedere se si vede. Il telefono finto
# fa la parte del telefono (non è la tastiera di Marta). Alla fine tutto si stampa nel registro (t13/stampa.ps1).
. (Join-Path $PSScriptRoot '..\t11\comune.ps1')
$cartellaT11 = Cartella-Risultati
try {
    Passo 'Primo avvio' {
        Avvia-App -Azzera | Out-Null
        Start-Sleep -Seconds 5
        Scrivi-Log "FUOCO all'avvio: $(Descrivi-Fuoco)"
        Fotografa 'primo-avvio'
        Controllo-Nomi 'primo-avvio'
        foreach ($id in 'ImmagineQRGrande', 'IndirizzoScrittoGrande', 'ImmagineQR', 'IndirizzoScritto', 'PillolaStato', 'TestoStato', 'PulsanteWiFiGrande', 'PrimoAvvio', 'TestoTerzoPasso') { Leggi-Elemento $id }
    }
    Passo 'Primo avvio: Tab avanti' { Giro-Tab 'avvio' 40 -Ogni 1 }
    Passo 'Primo avvio: Maiusc+Tab' { Giro-Tab 'avvio-indietro' 6 -Indietro }

    Passo 'F1 apre la Guida, Esc la chiude' {
        Premi 'F1'
        Start-Sleep -Seconds 2
        Descrivi-Finestre
        Fotografa 'f1-guida'
        Giro-Tab 'guida' 8
        Premi 'Esc'
        Start-Sleep -Seconds 1
        Descrivi-Finestre
        Fotografa 'f1-dopo-esc'
        Porta-Davanti
    }

    Passo 'Menu account con la tastiera' {
        if (Tab-Fino 'PulsanteAccount') {
            Premi 'Invio'
            Start-Sleep -Milliseconds 800
            Ritaglio-Fuoco 'menu-account'
            Premi 'Giu'; Premi 'Giu'; Premi 'Giu'
            Fotografa 'menu-account'
            Premi 'Esc'
            Ritaglio-Fuoco 'dopo-esc-account'
        } else { Segnala-Problema 'Con il solo Tab non si arriva al pulsante dell''account' }
    }

    Passo 'Impostazioni con Ctrl+virgola' {
        Tasto 'Ctrl+,'
        Start-Sleep -Seconds 1
        Scrivi-Log "FUOCO dopo Ctrl+,: $(Descrivi-Fuoco)"
        Fotografa 'impostazioni'
        Controllo-Nomi 'impostazioni'
        Giro-Tab 'impostazioni' 22 -Ogni 4
        Premi 'Esc'
        Start-Sleep -Milliseconds 700
        Scrivi-Log "  pannello ancora aperto dopo Esc: $([bool](Trova-Elemento 'ScorrimentoImpostazioni'))"
        Ritaglio-Fuoco 'dopo-esc-impostazioni'
    }

    # Ogni pagina: Ctrl+, poi Tab fino alla voce, Invio, giro di Tab nella pagina, Esc.
    $voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Gobbo', 'Avvio', 'Registro', 'Uscite'
    foreach ($voce in $voci) {
        $nome = Testo-App "Impostazioni_$voce"
        Passo "Impostazioni › $nome con la tastiera" {
            if (-not (Trova-Elemento 'ScorrimentoImpostazioni')) { Tasto 'Ctrl+,'; Start-Sleep -Milliseconds 800 }
            if (-not (Tab-Fino $nome 40)) { Segnala-Problema "Impostazioni: la voce «$nome» non si raggiunge con Tab"; Premi 'Esc'; return }
            Premi 'Invio'
            Start-Sleep -Milliseconds 900
            Fotografa "pagina-$voce"
            Controllo-Nomi "pagina-$voce"
            Giro-Tab "pagina-$voce" 16 -Ogni 5
            if ($voce -eq 'Gobbo') {
                # Le scorciatoie di una lettera (F, 1–4, +, −) non devono rubare i tasti a chi scrive in una casella.
                $casella = $null
                foreach ($i in 1..25) {
                    $e = Elemento-Fuoco
                    if ($e -and $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit) { $casella = $e; break }
                    [System.Windows.Forms.SendKeys]::SendWait('{TAB}'); Start-Sleep -Milliseconds 250
                }
                if ($casella) {
                    Scrivi-Log "Casella col fuoco: $(Descrivi-Fuoco $casella)"
                    [System.Windows.Forms.SendKeys]::SendWait('Fra 1 2 3 4 {+} -')
                    Start-Sleep -Milliseconds 600
                    $vp = $null
                    if ($casella.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { Scrivi-Log "  testo nella casella dopo «Fra 1 2 3 4 + -»: «$($vp.Current.Value)»" }
                    Ritaglio-Fuoco 'casella-gobbo'
                } else { Scrivi-Log 'Nella pagina Gobbo nessuna casella di testo raggiunta con Tab' }
            }
            Premi 'Esc'
            Start-Sleep -Milliseconds 600
            Scrivi-Log "  dopo Esc nella pagina: pannello aperto $([bool](Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)), indietro visibile $([bool](Trova-Elemento 'PulsanteIndietroImpostazioni'))"
            if (Trova-Elemento 'ScorrimentoImpostazioni') { Premi 'Esc' }
        }
    }

    # ---- telefono che chiede il codice: dialogo di conferma
    Passo 'Dialogo di conferma: fuoco e Esc' {
        Porta-Davanti
        Avvia-TelefonoFinto --nome 'iPhone di Marta' --durata 120 | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di Marta' -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
        Start-Sleep -Seconds 1
        Scrivi-Log "FUOCO con il dialogo aperto: $(Descrivi-Fuoco)"
        Fotografa 'conferma'
        Controllo-Nomi 'conferma'
        Giro-Tab 'conferma' 6 -Ogni 1
        Premi 'Esc'
        Start-Sleep -Seconds 2
        Registro-Telefono 'iPhone di Marta' | Select-Object -Last 8 | ForEach-Object { Scrivi-Log "  telefono: $_" }
        Ferma-TelefonoFinto 'iPhone di Marta'
        Fotografa 'conferma-dopo-esc'
    }
    Passo 'Dialogo di conferma: Consenti con Tab e Invio' {
        Avvia-TelefonoFinto --nome 'iPhone di Marta due' --durata 600 --riconnetti-sempre --identita-nuova | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di Marta due' -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
        Start-Sleep -Seconds 1
        Scrivi-Log "FUOCO con il dialogo aperto: $(Descrivi-Fuoco)"
        if (Tab-Fino (Testo-App 'Conferma_Consenti') 8) { Premi 'Invio' } else { Segnala-Problema 'Nel dialogo di conferma «Consenti» non si raggiunge con Tab' }
        Attendi-Telefono 'ACCETTATO' 20 -Nome 'iPhone di Marta due' | Out-Null
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Marta due' | Out-Null
        Start-Sleep -Seconds 5
        Scrivi-Log "FUOCO dopo il collegamento: $(Descrivi-Fuoco)"
    }
    Passo 'Video: nomi e stati' {
        Fotografa 'video'
        Controllo-Nomi 'video'
        foreach ($id in 'PillolaStato', 'TestoStato', 'PillolaTelefono', 'TestoPillolaTelefono', 'ChipQualita', 'TestoQualita', 'ChipCollegamento', 'TestoCollegamento', 'ChipVideo', 'SchedaTelefono', 'NomeTelefono', 'BatteriaTelefono', 'PulsanteScollega', 'Video', 'RiquadroVideo', 'StatoWebcamTesto', 'InterruttoreMicrofono') { Leggi-Elemento $id }
        Controlla-Video | Out-Null
    }
    Passo 'Video: Tab avanti' { Giro-Tab 'video' 45 -Ogni 3 }
    Passo 'Qualità con Invio ed Esc' {
        if (Tab-Fino 'ChipQualita') {
            Premi 'Invio'; Start-Sleep -Milliseconds 800
            Fotografa 'qualita-aperta'
            Giro-Tab 'qualita' 5
            Premi 'Esc'
            Ritaglio-Fuoco 'dopo-esc-qualita'
        } else { Segnala-Problema 'Con il solo Tab non si arriva al chip della qualità' }
    }
    Passo 'Pillola del telefono con Invio ed Esc' {
        if (Tab-Fino 'PillolaTelefono') {
            Premi 'Invio'; Start-Sleep -Milliseconds 800
            Fotografa 'pillola-aperta'
            Giro-Tab 'pillola' 5
            Premi 'Esc'
            Ritaglio-Fuoco 'dopo-esc-pillola'
        } else { Segnala-Problema 'Con il solo Tab non si arriva alla pillola del telefono' }
    }
    Passo 'Rete che cade: lo stato cambia per l''Assistente vocale?' {
        Rete-Spenta
        Start-Sleep -Seconds 8
        foreach ($id in 'PillolaStato', 'TestoStato', 'PillolaTelefono', 'ChipQualita', 'AvvisiSulVideo') { Leggi-Elemento $id }
        Fotografa 'rete-spenta'
        Rete-Accesa
        Start-Sleep -Seconds 8
        foreach ($id in 'PillolaStato', 'TestoStato', 'PillolaTelefono') { Leggi-Elemento $id }
    }
    Passo 'Vista Completa (Ctrl+2) con la tastiera' {
        Premi 'Ctrl+2'
        Start-Sleep -Seconds 2
        Fotografa 'completo'
        Controllo-Nomi 'completo'
        Giro-Tab 'completo' 60 -Ogni 6
        Premi 'Ctrl+1'
    }
    Passo 'Schermo intero (F11) ed Esc' {
        Premi 'F11'; Start-Sleep -Seconds 2
        Schermata 'f11'
        Giro-Tab 'f11' 6
        Premi 'Esc'; Start-Sleep -Seconds 2
        Schermata 'f11-dopo-esc'
    }
    Passo 'Vista pulita (Ctrl+Maiusc+P) ed Esc' {
        Premi 'Ctrl+Maiusc+P'; Start-Sleep -Seconds 1
        Giro-Tab 'pulita' 4
        Premi 'Esc'; Start-Sleep -Seconds 1
        Schermata 'pulita-dopo-esc'
    }
    Passo 'Finestra mini (Ctrl+Maiusc+M) ed Esc' {
        Premi 'Ctrl+Maiusc+M'; Start-Sleep -Seconds 2
        Descrivi-Finestre
        Schermata 'mini'
        Giro-Tab 'mini' 6
        Premi 'Esc'; Start-Sleep -Seconds 2
        Descrivi-Finestre
        Schermata 'mini-dopo-esc'
    }
    Passo 'Scollega con la tastiera' {
        Porta-Davanti
        if (Tab-Fino 'PulsanteScollega') {
            Premi 'Invio'; Start-Sleep -Seconds 1
            Fotografa 'scollega'
            Giro-Tab 'scollega' 4
            Premi 'Esc'; Start-Sleep -Seconds 1
            Scrivi-Log "  telefono ancora collegato dopo Esc: $([bool](Trova-Elemento 'PulsanteScollega'))"
            Fotografa 'scollega-dopo-esc'
        } else { Segnala-Problema 'Con il solo Tab non si arriva a «Scollega»' }
    }
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT11
}
