# Collaudo t02 (Giorgio, 62 anni, poco pratico, telefono Android): primo avvio, Aiuto e Domande frequenti, il telefono
# che chiede il permesso con il codice (prima «Non consentire» per paura, poi riprova), il QR code, il video, la X della
# finestra, l'icona cliccata di nuovo, chiudi e riapri.

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
Scrivi-Log "A schermo: $(Elenco-Visibili)"
Start-Sleep -Seconds 15
Fotografa 'primo-avvio-20s'
Scrivi-Log "A schermo dopo 20 s: $(Elenco-Visibili)"

# ---------------------------------------------------------------- Aiuto: Guida e Domande frequenti
Passo 'Aiuto › Guida' {
    Clicca 'PulsanteAiuto'
    Start-Sleep -Seconds 2
    Fotografa 'aiuto-guida'
    Albero-UI 'aiuto-guida-tutto' -Tutto | Out-Null
}
Passo 'Aiuto › Domande frequenti' {
    Clicca (Testo-App 'App_DomandeFrequenti')
    Start-Sleep -Seconds 2
    Fotografa 'aiuto-domande'
    Albero-UI 'aiuto-domande-tutto' -Tutto | Out-Null
    Tasto 'Esc'
    Start-Sleep -Seconds 1
}

# ---------------------------------------------------------------- telefono Android senza QR: il codice di conferma
Passo 'Telefono senza QR: la richiesta con il codice' {
    Avvia-TelefonoFinto --android --nome 'Telefono di Giorgio' --durata 600 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'CODICE' 30 -Nome 'Telefono di Giorgio' -Obbligatorio | Out-Null
    Attendi-Testo (Testo-App 'Conferma_NonConsentire') 15 -Obbligatorio | Out-Null
    Fotografa 'richiesta-codice'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"
}
Passo 'Giorgio si spaventa: «Non consentire»' {
    Clicca (Testo-App 'Conferma_NonConsentire')
    Start-Sleep -Seconds 3
    Fotografa 'dopo-non-consentire'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"
    Attendi-Telefono 'RIFIUTATO' 10 -Nome 'Telefono di Giorgio' | Out-Null
    Start-Sleep -Seconds 20
    Fotografa 'dopo-non-consentire-20s'
    Scrivi-Log "A schermo dopo 20 s: $(Elenco-Visibili)"
    Registro-Telefono 'Telefono di Giorgio' | Select-Object -Last 8 | ForEach-Object { Scrivi-Log "  telefono: $_" }
}
Ferma-TelefonoFinto

# ---------------------------------------------------------------- ci riprova con il QR (la stessa identità, entro 2 minuti)
$collegato = Passo 'Ci riprova con il QR code (stesso telefono)' {
    Avvia-TelefonoFinto -DalQR --android --nome 'Telefono di Giorgio' --durata 600 --riconnetti-sempre | Out-Null
    Start-Sleep -Seconds 3
    Fotografa 'qr-riprova'
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'Telefono di Giorgio' -Obbligatorio | Out-Null
} -Esito
if (-not $collegato) {
    Fotografa 'qr-riprova-respinto'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"
    Registro-Telefono 'Telefono di Giorgio' | Select-Object -Last 8 | ForEach-Object { Scrivi-Log "  telefono: $_" }
    Segnala-Problema 'Dopo un «Non consentire» lo stesso telefono non entra neanche con il QR code (vedi qr-riprova-respinto)'
    Ferma-TelefonoFinto
    $collegato = Passo 'Telefono «nuovo» dal QR code' {
        Avvia-TelefonoFinto -DalQR --android --identita-nuova --nome 'Telefono di Giorgio' --durata 600 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'ACCETTATO' 30 -Nome 'Telefono di Giorgio' -Obbligatorio | Out-Null
    } -Esito
}

if ($collegato) {
    Passo 'Video del telefono' {
        Attendi-Telefono 'Video:' 20 -Nome 'Telefono di Giorgio' | Out-Null
        Start-Sleep -Seconds 6
        Fotografa 'video'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Controlla-Video | Out-Null
    }
    Passo 'La pillola del telefono (cosa vede Giorgio)' {
        Clicca 'PillolaTelefono'
        Start-Sleep -Seconds 1
        Fotografa 'pillola'
        Tasto 'Esc'
    }
    # Giorgio chiude la finestra con la X (Alt+F4 fa lo stesso).
    Passo 'Chiude la finestra con la X' {
        Porta-Davanti
        Tasto 'Alt+F4'
        Start-Sleep -Seconds 3
        Schermata 'dopo-la-x'
        Descrivi-Finestre
        Scrivi-Log "Processo ancora vivo: $([bool](Get-Process -Name WebcamLR -ErrorAction SilentlyContinue))"
        $riga = Registro-Telefono 'Telefono di Giorgio' | Select-Object -Last 3
        $riga | ForEach-Object { Scrivi-Log "  telefono: $_" }
    }
    # Poi clicca di nuovo l'icona di WebcamLR.
    Passo 'Clicca di nuovo l''icona' {
        $exe = & (Get-Module Collaudo) { $script:Exe }
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) | Out-Null
        Start-Sleep -Seconds 6
        Schermata 'icona-di-nuovo'
        Descrivi-Finestre
        $f = Finestra-App
        if (-not $f -or $f.Current.BoundingRectangle.Width -lt 500) { Segnala-Problema 'Dopo la X, cliccando di nuovo l''icona la finestra di WebcamLR non torna' }
        else { Porta-Davanti; Start-Sleep -Seconds 1; Fotografa 'icona-di-nuovo-finestra' }
    }
    Passo 'Esce davvero e riapre: il telefono torna da solo?' {
        Chiudi-App
        Start-Sleep -Seconds 5
        Avvia-App | Out-Null
        Start-Sleep -Seconds 5
        Fotografa 'riaperta-5s'
        Start-Sleep -Seconds 20
        Fotografa 'riaperta-25s'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Registro-Telefono 'Telefono di Giorgio' | Select-Object -Last 8 | ForEach-Object { Scrivi-Log "  telefono: $_" }
        Controlla-Video | Out-Null
    }
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 4
Fotografa 'telefono-spento'
Scrivi-Log "A schermo: $(Elenco-Visibili)"
