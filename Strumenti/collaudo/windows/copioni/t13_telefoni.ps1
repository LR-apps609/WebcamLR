# Collaudo t13 (Elena, cerca di rompere tutto): gettone sbagliato, codice rifiutato e riprova subito, nomi del telefono
# lunghissimi, con emoji, a capo o solo spazi, due richieste insieme, doppi clic su Consenti e Scollega.
# Alla fine stampa tutto nel registro del lavoro (t13/stampa.ps1).
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartellaT13 = Cartella-Risultati
try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 3
    Fotografa 'primo-avvio'

    # ------------------------------------------------ gettone sbagliato e «Non consentire»
    Passo 'Gettone sbagliato: il PC chiede il codice' {
        Avvia-TelefonoFinto --nome 'Elena gettone' --gettone-sbagliato --durata 200 | Out-Null
        $riga = Attendi-Telefono 'CODICE' 30 -Nome 'Elena gettone'
        if (-not $riga) { Segnala-Problema 'Con il gettone sbagliato il telefono non arriva al codice'; Ultime-Telefono 'Elena gettone' 15 }
        Attendi-Testo (Testo-App 'Conferma_NonConsentire') 15 | Out-Null
        Fotografa 'gettone-sbagliato-domanda'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
    }
    Passo 'Non consentire' {
        Clicca (Testo-App 'Conferma_NonConsentire')
        Attendi-Telefono 'RIFIUTATO' 10 -Nome 'Elena gettone' | Out-Null
        Start-Sleep -Seconds 2
        Fotografa 'dopo-non-consentire'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Ultime-Telefono 'Elena gettone' 12
    }
    Ferma-TelefonoFinto
    Passo 'Lo stesso telefono riprova subito (respinto per 2 minuti)' {
        Avvia-TelefonoFinto --nome 'Elena gettone' --durata 60 | Out-Null
        Start-Sleep -Seconds 8
        Fotografa 'riprova-subito'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Ultime-Telefono 'Elena gettone' 12
        if (Trova-Elemento (Testo-App 'Conferma_Consenti')) { Scrivi-Log '  il PC chiede di nuovo la conferma' }
        else { Scrivi-Log '  il PC NON mostra nulla: il telefono è respinto in silenzio' }
    }
    Ferma-TelefonoFinto

    # ------------------------------------------------ nomi strani
    $nomeLungo = '📱🔥 Il telefono nuovissimo di Elena la tester puntigliosa che prova tutto quanto 🙃🧪 con un nome davvero esagerato ' + ('🦄' * 10)
    $nomi = [ordered]@{
        'lungo'  = $nomeLungo
        'spazi'  = '      '
        'acapo'  = "Elena`r`nseconda riga`tcon tab"
        'codice' = '<b>Elena</b> ‮olleh‬ "virgolette" \ / ; DROP TABLE'
    }
    foreach ($chiave in $nomi.Keys) {
        $nome = $nomi[$chiave]
        Passo "Nome del telefono «$chiave»: la domanda" {
            Avvia-TelefonoFinto --nome $nome --identita-nuova --durata 400 | Out-Null
            $riga = Attendi-Telefono 'CODICE' 30 -Nome $nome
            if (-not $riga) { Ultime-Telefono $nome 15; throw "il telefono «$chiave» non arriva al codice" }
            Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
            Fotografa "nome-$chiave-domanda"
            Scrivi-Log "A schermo: $(Elenco-Visibili)"
        }
        if ($chiave -eq 'lungo') {
            Passo 'Doppio clic rapido su Consenti' {
                $consenti = Trova-Elemento (Testo-App 'Conferma_Consenti')
                Clic-Rapido $consenti 2 60
                Start-Sleep -Seconds 2
                Fotografa 'consenti-doppio-clic'
                Scrivi-Log "A schermo: $(Elenco-Visibili)"
                Attendi-Telefono 'ACCETTATO' 15 -Nome $nome | Out-Null
                Attendi-Telefono 'Video:' 20 -Nome $nome | Out-Null
                Start-Sleep -Seconds 4
                Fotografa 'nome-lungo-essenziale'
                Tasto 'Ctrl+2'
                Start-Sleep -Seconds 2
                Fotografa 'nome-lungo-completo'
                Scrivi-Log "A schermo: $(Elenco-Visibili)"
                if (Trova-Elemento 'PillolaTelefono') { Clicca 'PillolaTelefono'; Start-Sleep -Seconds 1; Fotografa 'nome-lungo-pillola'; Tasto 'Esc' }
            }
            Passo 'Impostazioni › Telefoni con il nome lungo' {
                Clicca 'PulsanteImpostazioni'
                Start-Sleep -Milliseconds 800
                Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
                Start-Sleep -Seconds 1
                Fotografa 'impostazioni-telefoni-nome-lungo'
                if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
            }
        } else {
            Passo "Nome «$chiave»: Consenti" {
                Clicca (Testo-App 'Conferma_Consenti')
                Attendi-Telefono 'ACCETTATO' 15 -Nome $nome | Out-Null
                Start-Sleep -Seconds 4
                Fotografa "nome-$chiave-collegato"
                Scrivi-Log "A schermo: $(Elenco-Visibili)"
            }
        }
    }
    App-Viva | Out-Null

    # ------------------------------------------------ due richieste nuove insieme
    Passo 'Due telefoni nuovi chiedono insieme' {
        Avvia-TelefonoFinto --nome 'Elena A' --identita-nuova --durata 300 | Out-Null
        Avvia-TelefonoFinto --nome 'Elena B' --identita-nuova --durata 300 | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'Elena A' | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'Elena B' | Out-Null
        Start-Sleep -Seconds 2
        Fotografa 'due-richieste'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        # Elena preme Invio due volte di fila (il pulsante predefinito)
        Tasto 'Invio'
        Tasto 'Invio'
        Start-Sleep -Seconds 3
        Fotografa 'due-richieste-dopo-invio'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Ultime-Telefono 'Elena A' 6
        Ultime-Telefono 'Elena B' 6
        if (Trova-Elemento (Testo-App 'Conferma_Consenti')) { Clicca (Testo-App 'Conferma_Consenti'); Start-Sleep -Seconds 2 }
        Fotografa 'due-richieste-fine'
    }

    # ------------------------------------------------ Scollega: doppio e triplo clic
    Passo 'Doppio clic rapido su Scollega' {
        Tasto 'Ctrl+2'
        Start-Sleep -Seconds 2
        Fotografa 'prima-di-scollega'
        $scollega = Trova-Elemento 'PulsanteScollega'
        if (-not $scollega) { $scollega = Trova-Elemento (Testo-App 'Scollega') }
        if (-not $scollega) { throw 'non trovo Scollega' }
        Clic-Rapido $scollega 2 70
        Start-Sleep -Milliseconds 800
        Fotografa 'scollega-doppio-clic'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Start-Sleep -Seconds 3
        $scollega = Trova-Elemento 'PulsanteScollega'
        if ($scollega) { Clic-Rapido $scollega 3 50; Start-Sleep -Seconds 1; Fotografa 'scollega-triplo-clic' }
        Start-Sleep -Seconds 3
        Fotografa 'dopo-scollega'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        foreach ($n in @($nomeLungo, '      ', 'Elena A', 'Elena B')) { Ultime-Telefono $n 4 }
    }
    App-Viva | Out-Null
    Ferma-TelefonoFinto
    Start-Sleep -Seconds 3
    Fotografa 'fine'
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT13
}
