# Collaudo t10 (Stefano, curioso, ha Mac e PC): ogni menu dell'intestazione, Aiuto e «App e assistenza», tutte le
# pagine delle Impostazioni, le scorciatoie senza e con telefono, le viste, il gobbo, i profili, l'inglese.
# Per confrontare con il Mac: annota nel registro i nomi a schermo (Elenco-Visibili) di ogni menu e pagina.

function Apri-Impostazioni {
    if (-not (Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti)) { Clicca 'PulsanteImpostazioni' }
    Attendi-Elemento 'ScorrimentoImpostazioni' 5 -AncheNascosti | Out-Null
}
function Chiudi-Impostazioni {
    if (Trova-Elemento 'PulsanteChiudiImpostazioni') { Clicca 'PulsanteChiudiImpostazioni' }
    Start-Sleep -Milliseconds 600
}
function Testi-Finestre {
    # Tutti i nomi (anche fuori schermo) di tutte le finestre dell'app, in una riga: per cercare segnaposto e confronti.
    $nomi = @(Tutti-Elementi | ForEach-Object { try { $_.Current.Name } catch { } } | Where-Object { $_ } | Select-Object -Unique)
    $nomi -join ' | '
}

Avvia-App -Azzera | Out-Null
Start-Sleep -Seconds 4
Fotografa 'primo-avvio'
Scrivi-Log "Finestre: $(Descrivi-Finestre)"
Scrivi-Log "A schermo: $(Elenco-Visibili)"

# ---------------------------------------------------------------- menu dell'intestazione
Passo 'Menu account' {
    Clicca 'PulsanteAccount'
    Start-Sleep -Milliseconds 800
    Fotografa 'menu-account'
    Scrivi-Log "Menu account: $(Elenco-Visibili)"
    Tasto 'Esc'
}
foreach ($voce in 'VoceInformazioni', 'VoceAggiornamenti', 'VoceLingua', 'VoceTelefoniFidati', 'VoceImpostazioni') {
    Passo "Menu account › $voce" {
        Clicca 'PulsanteAccount'
        Start-Sleep -Milliseconds 600
        Clicca $voce
        Start-Sleep -Seconds 3
        Fotografa "account-$voce"
        Scrivi-Log "  dopo ${voce}: finestre $(Descrivi-Finestre)"
        Scrivi-Log "  a schermo: $(Elenco-Visibili)"
        Tasto 'Esc'
        Start-Sleep -Milliseconds 600
        Tasto 'Esc'
        Chiudi-Impostazioni
    }
}
Passo 'Menu Schermo' {
    Clicca 'PulsanteSchermo'
    Start-Sleep -Milliseconds 800
    Fotografa 'menu-schermo'
    Scrivi-Log "Menu Schermo: $(Elenco-Visibili)"
    Tasto 'Esc'
}

# ---------------------------------------------------------------- Aiuto e «App e assistenza»
Passo 'Aiuto (pulsante)' {
    Clicca 'PulsanteAiuto'
    Start-Sleep -Seconds 2
    Fotografa 'aiuto'
    Scrivi-Log "Aiuto: finestre $(Descrivi-Finestre)"
    Scrivi-Log "Aiuto, testi: $(Testi-Finestre)"
}
foreach ($scheda in 'App_Guida', 'App_DomandeFrequenti', 'App_SegnalaBug', 'App_Informazioni') {
    Passo "App e assistenza › $scheda" {
        Clicca (Testo-App $scheda)
        Start-Sleep -Seconds 1
        Fotografa "app-$scheda"
        Scrivi-Log "  ${scheda}: $(Elenco-Visibili)"
    }
}
Passo 'Domande frequenti: ricerca' {
    Clicca (Testo-App 'App_DomandeFrequenti')
    Start-Sleep -Milliseconds 800
    Scrivi 'firewall' -In (Testo-App 'App_CercaDomande')
    Start-Sleep -Seconds 1
    Fotografa 'domande-firewall'
    Clicca (Testo-App 'App_CercaDomande')
    Tasto 'Ctrl+A'
    Scrivi 'zzzqqq'
    Start-Sleep -Seconds 1
    Fotografa 'domande-nessuna'
}
Passo 'App e assistenza: Esc la chiude' {
    Tasto 'Esc'
    Start-Sleep -Seconds 1
    Scrivi-Log "  dopo Esc: finestre $(Descrivi-Finestre)"
    Fotografa 'app-dopo-esc'
}
Passo 'F1 apre la guida' {
    Porta-Davanti
    Tasto 'F1'
    Start-Sleep -Seconds 2
    Scrivi-Log "  dopo F1: finestre $(Descrivi-Finestre)"
    Fotografa 'f1'
    Tasto 'Esc'
}

# ---------------------------------------------------------------- tutte le pagine delle Impostazioni
Passo 'Ctrl+, apre le impostazioni ed Esc le chiude' {
    Porta-Davanti
    Tasto 'Ctrl+,'
    Start-Sleep -Seconds 1
    Fotografa 'ctrl-virgola'
    Scrivi-Log "  impostazioni aperte con Ctrl+,: $([bool](Trova-Elemento 'ScorrimentoImpostazioni' -AncheNascosti))"
    Scrivi-Log "  elenco: $(Elenco-Visibili)"
    Tasto 'Esc'
    Start-Sleep -Seconds 1
    Scrivi-Log "  dopo Esc ancora aperte: $([bool](Trova-Elemento 'PulsanteChiudiImpostazioni'))"
}
$voci = 'Fotocamera', 'Effetti', 'Sfondo', 'Profili', 'Qualita', 'Schermo', 'Microfono', 'Telefoni', 'Gobbo', 'Avvio', 'Registro', 'Uscite'
foreach ($voce in $voci) {
    $nome = Testo-App "Impostazioni_$voce"
    Passo "Impostazioni › $nome" {
        Apri-Impostazioni
        Clicca $nome -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Milliseconds 900
        Fotografa "pagina-$voce"
        Scrivi-Log "  pagina ${voce}, testi: $(Testi-Finestre)"
        Chiudi-Impostazioni
    }
}

# ---------------------------------------------------------------- scorciatoie senza telefono
foreach ($t in 'Ctrl+T', 'Ctrl+R', 'Ctrl+Maiusc+T', 'F') {
    Passo "Tasto $t senza telefono" {
        Porta-Davanti
        Tasto $t
        Start-Sleep -Seconds 1
        Fotografa ("senza-telefono-" + ($t -replace '\+', '-'))
    }
}

# ---------------------------------------------------------------- telefono finto Pro, viste, gobbo, profili
$collegato = Passo 'Telefono finto Pro dal QR code' {
    Avvia-TelefonoFinto -DalQR --nome 'iPhone di Stefano' --durata 500 --pro --riconnetti-sempre | Out-Null
    Attendi-Telefono 'ACCETTATO' 30 -Nome 'iPhone di Stefano' -Obbligatorio | Out-Null
    Attendi-Telefono 'Video:' 20 -Nome 'iPhone di Stefano' | Out-Null
    Start-Sleep -Seconds 4
    Fotografa 'telefono-collegato'
} -Esito

Passo 'Vista Essenziale (Ctrl+1)' { Tasto 'Ctrl+1'; Start-Sleep -Seconds 2; Fotografa 'vista-essenziale'; Scrivi-Log "A schermo: $(Elenco-Visibili)" }
Passo 'Vista Completo (Ctrl+2)' { Tasto 'Ctrl+2'; Start-Sleep -Seconds 2; Fotografa 'vista-completo'; Scrivi-Log "A schermo: $(Elenco-Visibili)" }
Passo 'Vista pulita (Ctrl+Maiusc+P) ed Esc' {
    Tasto 'Ctrl+Maiusc+P'; Start-Sleep -Seconds 2; Fotografa 'vista-pulita'
    Tasto 'Esc'; Start-Sleep -Seconds 1; Fotografa 'vista-pulita-dopo-esc'
}
Passo 'Finestra mini (Ctrl+Maiusc+M) ed Esc' {
    Tasto 'Ctrl+Maiusc+M'; Start-Sleep -Seconds 2; Fotografa 'mini'
    Scrivi-Log "  mini: finestre $(Descrivi-Finestre)"
    Tasto 'Esc'; Start-Sleep -Seconds 2; Fotografa 'mini-dopo-esc'
    Scrivi-Log "  dopo Esc: finestre $(Descrivi-Finestre)"
}
Passo 'Schermo intero (F11) ed Esc' {
    Tasto 'F11'; Start-Sleep -Seconds 2; Fotografa 'schermo-intero'
    Tasto 'Esc'; Start-Sleep -Seconds 2; Fotografa 'schermo-intero-dopo-esc'
}
Passo 'Riempi l''inquadratura: c''è un tasto come ⌥⌘F sul Mac?' {
    Tasto 'Ctrl+Alt+F'; Start-Sleep -Seconds 1; Fotografa 'ctrl-alt-f'
}
Passo 'Clic destro sul video (Maiusc+F10)' {
    Clicca 'VideoElaborato' -Mouse
    Tasto 'Maiusc+F10'
    Start-Sleep -Seconds 1
    Fotografa 'menu-video'
    Scrivi-Log "Menu del video: $(Elenco-Visibili)"
    Tasto 'Esc'
}
Passo 'Menu Sfondo' {
    Clicca 'PulsanteMenuSfondo'
    Start-Sleep -Milliseconds 800
    Fotografa 'menu-sfondo'
    Scrivi-Log "Menu Sfondo: $(Elenco-Visibili)"
    Tasto 'Esc'
}
Passo 'Profili (menu sotto il video)' {
    Clicca 'PulsanteProfili'
    Start-Sleep -Seconds 1
    Fotografa 'menu-profili'
    Scrivi-Log "Menu profili: $(Elenco-Visibili)"
    Tasto 'Esc'
}
Passo 'Impostazioni › Profili con il telefono' {
    Apri-Impostazioni
    Clicca (Testo-App 'Impostazioni_Profili') -Dentro 'ScorrimentoImpostazioni'
    Start-Sleep -Seconds 1
    Fotografa 'pagina-profili-telefono'
    Scrivi-Log "  testi: $(Testi-Finestre)"
    Chiudi-Impostazioni
}
Passo 'Gobbo' {
    Clicca 'PulsanteGobbo'
    Start-Sleep -Seconds 2
    Scrivi-Log "  gobbo: finestre $(Descrivi-Finestre)"
    Fotografa 'gobbo'
    Scrivi 'Buongiorno a tutti, oggi vi parlo di WebcamLR. 1234 + - F' -In (Testo-App 'Gobbo_TestoNome')
    Start-Sleep -Seconds 1
    Fotografa 'gobbo-con-testo'
    $casella = Trova-Elemento (Testo-App 'Gobbo_TestoNome')
    if ($casella) {
        try { Scrivi-Log "  testo nel gobbo: «$($casella.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value)»" } catch { }
    }
    Scrivi-Log "  gobbo, testi: $(Testi-Finestre)"
    Tasto 'Esc'
}
Passo 'Ctrl+W nasconde la finestra' {
    Porta-Davanti
    Tasto 'Ctrl+W'
    Start-Sleep -Seconds 2
    Scrivi-Log "  dopo Ctrl+W: finestre $(Descrivi-Finestre)"
    Fotografa 'dopo-ctrl-w'
}
Ferma-TelefonoFinto

Passo "L'app in inglese: menu account e impostazioni" {
    Lingua-Inglese -Riavvia
    Start-Sleep -Seconds 4
    Fotografa 'inglese'
    Clicca 'PulsanteAccount'
    Start-Sleep -Milliseconds 800
    Fotografa 'inglese-menu-account'
    Scrivi-Log "EN menu account: $(Elenco-Visibili)"
    Tasto 'Esc'
    Clicca 'PulsanteImpostazioni'
    Start-Sleep -Seconds 1
    Fotografa 'inglese-impostazioni'
    Scrivi-Log "EN impostazioni: $(Elenco-Visibili)"
}
