# Fumo: primo avvio con i dati azzerati, ogni vista raggiungibile, poi il telefono finto collegato e il video in onda.
# Ogni «Passo» che fallisce diventa un problema in esito.txt (con una schermata) e il copione va avanti.

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
Scrivi-Log "Testi a schermo: $((Testi-Visibili) -join ' | ')"

Passo 'Impostazioni: il pannello' {
    Clicca 'PulsanteImpostazioni'
    Start-Sleep -Seconds 1
    Fotografa 'impostazioni'
}

# Le voci del pannello, con i nomi dell'app nella lingua scelta (stesso ordine di MainWindow.Viste.cs).
$voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Uscite', 'Gobbo', 'Avvio', 'Registro'
foreach ($voce in $voci) {
    $nome = Testo-App "Impostazioni_$voce"
    Passo "Impostazioni › $nome" {
        if (-not (Esiste 'PulsanteIndietroImpostazioni') -and -not (Esiste $nome)) { Clicca 'PulsanteImpostazioni' }
        Clicca $nome
        Start-Sleep -Milliseconds 800
        Fotografa "impostazioni-$voce"
        Clicca 'PulsanteIndietroImpostazioni'
    }
}
Passo 'Impostazioni: chiusura' { Clicca 'PulsanteChiudiImpostazioni' }

Passo 'Menu account' {
    Clicca 'PulsanteAccount'
    Fotografa 'menu-account'
    Tasto 'Esc'
}
Passo 'Aiuto' {
    Clicca 'PulsanteAiuto'
    Start-Sleep -Seconds 1
    Fotografa 'aiuto'
    Tasto 'Esc'
}
Passo 'Menu Schermo' {
    Clicca 'PulsanteSchermo'
    Fotografa 'menu-schermo'
}
Passo 'Vista Completo' {
    if (-not (Esiste 'PulsanteVistaCompleto')) { Clicca 'PulsanteSchermo' }
    Clicca 'PulsanteVistaCompleto'
    Tasto 'Esc'
    Start-Sleep -Seconds 1
    Fotografa 'vista-completo'
}
Passo 'Registro del collegamento (colonna di sinistra)' {
    Clicca 'PulsanteRegistro'
    Fotografa 'registro-collegamento'
    Tasto 'Esc'
}
Passo 'Finestra piccola 900×600' {
    Ridimensiona-Finestra 900 600
    Fotografa 'finestra-900x600'
    Ingrandisci-Finestra
}
Passo 'Schermo intero' {
    Clicca 'PulsanteSchermo'
    Clicca 'PulsanteSchermoIntero'
    Start-Sleep -Seconds 2
    Fotografa 'schermo-intero'
    Tasto 'Esc'
    Start-Sleep -Seconds 1
}
Passo 'Ritorno alla vista Essenziale' {
    Clicca 'PulsanteSchermo'
    Clicca 'PulsanteVistaEssenziale'
    Tasto 'Esc'
    Start-Sleep -Seconds 1
    Fotografa 'vista-essenziale'
}

# Il telefono finto: dal QR (entra senza conferma); se il QR non si legge, senza gettone e «Consenti» sul PC.
$collegato = Passo 'Telefono finto dal QR code' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone di collaudo' --durata 300 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
} -Esito
if (-not $collegato) {
    Ferma-TelefonoFinto
    $collegato = Passo 'Telefono finto con la conferma sul PC' {
        Avvia-TelefonoFinto --nome 'iPhone di collaudo' --durata 300 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 -Obbligatorio | Out-Null
        Fotografa 'conferma-telefono'
        Clicca (Testo-App 'Conferma_Consenti')
        Attendi-Telefono 'ACCETTATO' 20 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
    } -Esito
}
if ($collegato) {
    Passo 'Video in onda' {
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
        Start-Sleep -Seconds 6
        Fotografa 'video-in-onda'
        Start-Sleep -Seconds 3
        Schermata 'video-tre-secondi-dopo' | Out-Null
    }
    Passo 'Pillola del telefono' {
        Clicca 'PillolaTelefono'
        Fotografa 'pillola-telefono'
        Tasto 'Esc'
    }
    Passo 'Numeri della qualità' {
        Clicca 'ChipQualita'
        Fotografa 'numeri-qualita'
        Tasto 'Esc'
    }
    Passo 'Vista Completo con il telefono' {
        Clicca 'PulsanteSchermo'
        Clicca 'PulsanteVistaCompleto'
        Tasto 'Esc'
        Start-Sleep -Seconds 2
        Fotografa 'completo-con-telefono'
    }
    Passo 'Rete che cade e torna' {
        Rete-Spenta
        Start-Sleep -Seconds 6
        Fotografa 'rete-spenta'
        Rete-Accesa
        Start-Sleep -Seconds 6
        Fotografa 'rete-accesa'
    }
}
Ferma-TelefonoFinto
Start-Sleep -Seconds 3
Fotografa 'telefono-scollegato'

Passo "L'app in inglese" {
    Lingua-Inglese -Riavvia
    Start-Sleep -Seconds 4
    Fotografa 'inglese'
}
