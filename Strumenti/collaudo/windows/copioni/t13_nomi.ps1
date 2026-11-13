# Collaudo t13 (Elena): nomi del telefono strani (solo spazi, a capo e tab, markup e testo al contrario, vuoto),
# uno alla volta (senza Pro un secondo telefono non entra), e cosa dice il PC a un secondo telefono.
. (Join-Path $PSScriptRoot '..\t13\comune.ps1')
$cartellaT13 = Cartella-Risultati
try {
    Avvia-App -Azzera | Out-Null
    Start-Sleep -Seconds 3
    $nomi = [ordered]@{
        'spazi'  = '      '
        'acapo'  = "Elena`r`nseconda riga`tcon tab"
        'codice' = '<b>Elena</b> ‮olleh‬ "virgolette" \ / ; DROP TABLE'
        'vuoto'  = ''
    }
    foreach ($chiave in $nomi.Keys) {
        $nome = $nomi[$chiave]
        Passo "Nome «$chiave»" {
            Avvia-TelefonoFinto --nome $nome --identita-nuova --durata 120 | Out-Null
            $riga = Attendi-Telefono 'CODICE' 25 -Nome $nome
            if (-not $riga) { Ultime-Telefono $nome 12; throw "il telefono «$chiave» non arriva al codice" }
            Attendi-Testo (Testo-App 'Conferma_Consenti') 15 | Out-Null
            Fotografa "nome-$chiave-domanda"
            Scrivi-Log "A schermo: $(Elenco-Visibili)"
            Clicca (Testo-App 'Conferma_Consenti')
            Attendi-Telefono 'ACCETTATO' 15 -Nome $nome | Out-Null
            Start-Sleep -Seconds 3
            Tasto 'Ctrl+2'
            Start-Sleep -Seconds 2
            Fotografa "nome-$chiave-collegato"
            Scrivi-Log "A schermo: $(Elenco-Visibili)"
        }
        if ($chiave -eq 'spazi') {
            Passo 'Secondo telefono mentre il primo è gratis' {
                Avvia-TelefonoFinto --nome 'Elena secondo' --identita-nuova --durata 60 | Out-Null
                Start-Sleep -Seconds 4
                Fotografa 'secondo-telefono'
                Scrivi-Log "A schermo: $(Elenco-Visibili)"
                Ultime-Telefono 'Elena secondo' 10
                Ferma-TelefonoFinto 'Elena secondo'
            }
        }
        Ferma-TelefonoFinto
        Start-Sleep -Seconds 3
    }
    Passo 'Impostazioni › Telefoni: i fidati con i nomi strani' {
        Clicca 'PulsanteImpostazioni'
        Start-Sleep -Milliseconds 800
        Clicca (Testo-App 'Impostazioni_Telefoni') -Dentro 'ScorrimentoImpostazioni'
        Start-Sleep -Seconds 1
        Fotografa 'impostazioni-telefoni-fidati'
        Scrivi-Log "A schermo: $(Elenco-Visibili)"
    }
    App-Viva | Out-Null
} finally {
    . (Join-Path $PSScriptRoot '..\t13\stampa.ps1') -Cartella $cartellaT13
}
