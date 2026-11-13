# Fumo: primo avvio con i dati azzerati, ogni vista raggiungibile, poi il telefono finto collegato e il video in onda.
# Ogni «Passo» che fallisce diventa un problema in esito.txt (con una schermata) e il copione va avanti.
# Scorciatoie dell'app usate qui: Ctrl+1 Essenziale, Ctrl+2 Completo, F11 schermo intero, Ctrl+Maiusc+P vista pulita,
# Ctrl+Maiusc+M finestra mini.

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
Scrivi-Log "A schermo: $(Elenco-Visibili)"

# ---------------------------------------------------------------- impostazioni, una voce alla volta
function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}

Passo 'Impostazioni: il pannello' {
    Apri-Impostazioni
    Fotografa 'impostazioni'
}
# Le voci del pannello, con i nomi dell'app nella lingua scelta (stesso ordine di MainWindow.Viste.cs). Hanno lo stesso
# nome di altri pulsanti («Sfondo», «Schermo»): si cercano dentro l'elenco del pannello.
# «Uscite» per ultima: nelle prove di novembre dopo quella pagina il pannello non si riapriva più (controllo qui sotto).
$voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Gobbo', 'Avvio', 'Registro', 'Uscite'
foreach ($voce in $voci) {
    $nome = Testo-App "Impostazioni_$voce"
    Passo "Impostazioni › $nome" {
        Apri-Impostazioni
        Clicca $nome -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Milliseconds 800
        Fotografa "impostazioni-$voce"
        if (-not (Trova-Elemento 'PulsanteIndietroImpostazioni')) {
            Segnala-Problema "Impostazioni › ${nome}: dopo l'apertura della pagina il pannello non si vede più"
        }
        Chiudi-Impostazioni
    }
}

Passo 'Impostazioni di nuovo dopo «Uscite»' {
    $cambio = Confronta-Finestra 'clic su Impostazioni' { Clicca 'PulsanteImpostazioni'; Start-Sleep -Seconds 1 }
    Fotografa 'impostazioni-dopo-uscite'
    $vede = [bool](Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)
    Scrivi-Log "  dopo «Uscite»: elenco delle impostazioni per UI Automation $vede, finestra cambiata $cambio%"
    if (-not $vede) {
        Segnala-Problema "Dopo Impostazioni › Uscite il pannello Impostazioni non si riapre (UI Automation non lo vede; a schermo è cambiato il $cambio% della finestra: guarda impostazioni-dopo-uscite.png)"
    }
    Chiudi-Impostazioni
    if (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti) { Clicca 'PulsanteImpostazioni' }
}

# ---------------------------------------------------------------- menu dell'intestazione
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
    Tasto 'Esc'
}

# ---------------------------------------------------------------- telefono finto e video (vista Essenziale)
# Dal QR (entra senza conferma); se il QR non si legge, senza gettone e «Consenti» sul PC.
$collegato = Passo 'Telefono finto dal QR code' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone di collaudo' --durata 400 --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
} -Esito
if (-not $collegato) {
    Ferma-TelefonoFinto
    $collegato = Passo 'Telefono finto con la conferma sul PC' {
        Avvia-TelefonoFinto --nome 'iPhone di collaudo' --durata 400 --riconnetti-sempre | Out-Null
        Attendi-Telefono 'CODICE' 30 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
        Attendi-Testo (Testo-App 'Conferma_Consenti') 15 -Obbligatorio | Out-Null
        Fotografa 'conferma-telefono'
        Clicca (Testo-App 'Conferma_Consenti')
        Attendi-Telefono 'ACCETTATO' 20 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
    } -Esito
}
if ($collegato) {
    Passo 'Video in onda (Essenziale)' {
        Attendi-Telefono 'Video:' 20 -Nome 'iPhone di collaudo' -Obbligatorio | Out-Null
        Start-Sleep -Seconds 6
        Fotografa 'video-in-onda'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
        Controlla-Video -Obbligatorio | Out-Null
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
    Passo 'Rete che cade e torna' {
        Rete-Spenta
        Start-Sleep -Seconds 6
        Fotografa 'rete-spenta'
        Controlla-Video | Out-Null   # qui ci si aspetta «FERMO» (o l'animazione della riconnessione)
        Rete-Accesa
        Start-Sleep -Seconds 6
        Fotografa 'rete-accesa'
        Controlla-Video -Obbligatorio | Out-Null
    }
}

# ---------------------------------------------------------------- le altre viste
Passo 'Vista Completo (Ctrl+2)' {
    Tasto 'Ctrl+2'
    Start-Sleep -Seconds 2
    Fotografa 'vista-completo'
    Scrivi-Log "A schermo: $(Elenco-Visibili)"
    foreach ($id in 'PulsanteSchermo', 'VideoElaborato', 'ChipQualita', 'PannelloDestroScorrimento', 'SezioneFotocamera') {
        $e = Trova-Elemento $id -AncheNascosti
        if ($e) { Scrivi-Log "  ${id}: c'è, fuori schermo $($e.Current.IsOffscreen), $(Descrivi-Rettangolo $e.Current.BoundingRectangle)" }
        else { Scrivi-Log "  ${id}: non c'è" }
    }
    if ($collegato) { Controlla-Video -Obbligatorio | Out-Null }
}
Passo 'Registro del collegamento (colonna di sinistra)' {
    Clicca 'PulsanteRegistro'
    Fotografa 'registro-collegamento'
    Tasto 'Esc'
}
Passo 'Finestra piccola 900×600 e di nuovo grande' {
    Ridimensiona-Finestra 900 600
    Fotografa 'finestra-900x600'
    Ingrandisci-Finestra
    Start-Sleep -Seconds 1
    Fotografa 'finestra-ingrandita'
    # Nel copione «viste» (senza passare da Impostazioni › Uscite) la barra c'è sempre.
    if (-not (Esiste 'PulsanteSchermo')) { Segnala-Problema "Vista Completo (dopo Impostazioni › Uscite, 900×600 e Ingrandisci): la barra sotto il video (PulsanteSchermo) e la colonna di destra non sono raggiungibili con UI Automation" }
}
Passo 'Schermo intero (F11)' {
    Tasto 'F11'
    Start-Sleep -Seconds 2
    Fotografa 'schermo-intero'
    if ($collegato) { Controlla-Video | Out-Null }
    Tasto 'Esc'
    Start-Sleep -Seconds 1
}
Passo 'Vista pulita (Ctrl+Maiusc+P)' {
    Tasto 'Ctrl+Maiusc+P'
    Start-Sleep -Seconds 2
    Fotografa 'vista-pulita'
    Tasto 'Ctrl+Maiusc+P'
}
Passo 'Finestra mini (Ctrl+Maiusc+M)' {
    Tasto 'Ctrl+Maiusc+M'
    Start-Sleep -Seconds 2
    Fotografa 'finestra-mini'
    Tasto 'Ctrl+Maiusc+M'
}
Passo 'Ritorno alla vista Essenziale (Ctrl+1)' {
    Tasto 'Ctrl+1'
    Start-Sleep -Seconds 2
    Fotografa 'vista-essenziale'
}

Ferma-TelefonoFinto
Start-Sleep -Seconds 4
Fotografa 'telefono-scollegato'

Passo "L'app in inglese" {
    Lingua-Inglese -Riavvia
    Start-Sleep -Seconds 4
    Fotografa 'inglese'
    Clicca 'PulsanteImpostazioni'
    Fotografa 'inglese-impostazioni'
}
