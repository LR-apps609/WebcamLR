# Collaudo t19 (Emma, inglese): tutta l'app in inglese. Primo avvio, le 12 pagine di Impostazioni (albero completo),
# menu, App e assistenza con le schede, Pro, Segnala un bug, telefono che chiede la conferma (rifiutato e consentito),
# video, notifiche, rete che cade, telefono Android, telefono vecchio. I risultati si stampano nel registro.
$cartellaT19 = Cartella-Risultati
try {
    Lingua-Inglese
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 4
    Fotografa 'en-primo-avvio'
    Albero-UI 'en-primo-avvio-tutto' -Tutto
    Scrivi-Log "A schermo: $(Elenco-Visibili)"

    function Apri-Impostazioni {
        if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
        Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
    }
    function Chiudi-Impostazioni {
        if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
        Start-Sleep -Milliseconds 600
    }
    Passo 'Impostazioni (elenco)' { Apri-Impostazioni; Fotografa 'en-impostazioni' }
    $voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Gobbo', 'Avvio', 'Registro', 'Uscite'
    foreach ($voce in $voci) {
        $nome = Testo-App "Impostazioni_$voce"
        Passo "Impostazioni › $nome" {
            Apri-Impostazioni
            Clicca $nome -Dentro 'ScorrimentoImpostazioni'
            Start-Sleep -Milliseconds 900
            Schermata "en-imp-$voce"
            Albero-UI "en-imp-$voce-tutto" -Tutto
            Chiudi-Impostazioni
        }
    }
    Passo 'Menu account' {
        Clicca 'PulsanteAccount'; Start-Sleep -Milliseconds 700
        Fotografa 'en-menu-account'
        Tasto 'Esc'
    }
    Passo 'Menu schermo' { Clicca 'PulsanteSchermo'; Start-Sleep -Milliseconds 700; Fotografa 'en-menu-schermo'; Tasto 'Esc' }
    Passo 'Pro (Come sbloccarla)' {
        Clicca 'PulsanteAccount'; Start-Sleep -Milliseconds 700
        Clicca (Testo-App 'Account_ComeSbloccarla'); Start-Sleep -Seconds 1
        Fotografa 'en-pro'
        Albero-UI 'en-pro-tutto' -Tutto
        Tasto 'Esc'
    }
    Passo 'App e assistenza' {
        Clicca 'PulsanteAiuto'; Start-Sleep -Seconds 1
        Fotografa 'en-aiuto-guida'
        Albero-UI 'en-aiuto-guida-tutto' -Tutto
        foreach ($k in 'App_DomandeFrequenti', 'App_SegnalaBug', 'App_Informazioni') {
            Clicca (Testo-App $k); Start-Sleep -Milliseconds 900
            Fotografa "en-aiuto-$k"
            Albero-UI "en-aiuto-$k-tutto" -Tutto
            if ($k -eq 'App_SegnalaBug') {
                Scrivi 'The video freezes after a minute' -In (Testo-App 'Bug_CosaESuccesso')
                Start-Sleep -Milliseconds 500
                Clicca (Testo-App 'Bug_Copia'); Start-Sleep -Seconds 1
                Fotografa 'en-segnala-copiata'
            }
            if ($k -eq 'App_DomandeFrequenti') {
                Scrivi 'xyzzy' -In (Testo-App 'App_CercaDomande'); Start-Sleep -Milliseconds 700
                Fotografa 'en-faq-nessuna'
            }
        }
        Tasto 'Esc'
    }

    # Telefono nuovo senza gettone: conferma sul PC, «Don't allow».
    Passo 'Conferma: non consentire' {
        Avvia-TelefonoFinto --nome "Emma's iPhone" --durata 60 | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome "Emma's iPhone" -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_NonConsentire') 15 | Out-Null
        Fotografa 'en-conferma'
        Clicca (Testo-App 'Conferma_NonConsentire'); Start-Sleep -Seconds 3
        Fotografa 'en-dopo-non-consentire'
        Ferma-TelefonoFinto
    }
    $collegato = Passo 'Conferma: consenti' {
        Avvia-TelefonoFinto --nome "Emma's iPhone" --identita-nuova --durata 300 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome "Emma's iPhone" -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
        Clicca (Testo-App 'Conferma_Consenti')
        Attendi-Telefono 'ACCETTATO' 20 -Nome "Emma's iPhone" -Obbligatorio | Out-Null
    } -Esito
    if ($collegato) {
        Passo 'In onda' {
            Attendi-Telefono 'Video:' 20 -Nome "Emma's iPhone" | Out-Null
            Start-Sleep -Seconds 5
            Fotografa 'en-video'
            Albero-UI 'en-video-tutto' -Tutto
        }
        Passo 'Pillola e qualità' {
            Clicca 'PillolaTelefono'; Start-Sleep -Milliseconds 700; Fotografa 'en-pillola'; Tasto 'Esc'
            Clicca 'ChipQualita'; Start-Sleep -Milliseconds 700; Fotografa 'en-qualita'; Tasto 'Esc'
        }
        Passo 'Completo' { Tasto 'Ctrl+2'; Start-Sleep -Seconds 2; Fotografa 'en-completo'; Albero-UI 'en-completo-tutto' -Tutto }
        Passo 'Rete che cade' {
            Rete-Spenta; Start-Sleep -Seconds 12
            Fotografa 'en-rete-spenta'
            Rete-Accesa; Start-Sleep -Seconds 8
            Fotografa 'en-rete-accesa'
        }
        Passo 'Scollega' {
            Tasto 'Ctrl+1'; Start-Sleep -Seconds 1
            Ferma-TelefonoFinto; Start-Sleep -Seconds 5
            Fotografa 'en-telefono-perso'
        }
    }
    Passo 'Telefono Android Pro' {
        Avvia-TelefonoFinto --nome "Emma's Pixel" --android --pro --identita-nuova --durata 60 --batteria 12 --temperatura molto-calda | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome "Emma's Pixel" | Out-Null
        if (Attendi-Testo (Testo-App 'Conferma_Consenti') 15) { Fotografa 'en-conferma-android'; Clicca (Testo-App 'Conferma_Consenti') }
        Start-Sleep -Seconds 10
        Fotografa 'en-android-pro'
        Clicca 'PulsanteAccount'; Start-Sleep -Milliseconds 700; Fotografa 'en-menu-account-pro'; Tasto 'Esc'
        Ferma-TelefonoFinto
    }
    Passo 'Gettone sbagliato' {
        Avvia-TelefonoFinto --nome "Stranger" --gettone-sbagliato --identita-nuova --durata 40 | Out-Null
        Start-Sleep -Seconds 8
        Fotografa 'en-gettone-sbagliato'
        Ferma-TelefonoFinto
    }
} finally {
    . (Join-Path $PSScriptRoot '..\t19\stampa.ps1') -Cartella $cartellaT19
}
