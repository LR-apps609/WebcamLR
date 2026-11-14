# Collaudo t07 (Paolo, attento alla privacy): concede tutto, va in onda e poi TOGLIE i permessi a metà.
#   1) appops CAMERA ignore (come «blocca l'accesso alla fotocamera» dalle impostazioni rapide: l'app resta viva);
#   2) appops CAMERA allow: torna il video da solo?
#   3) microfono acceso, poi appops RECORD_AUDIO ignore;
#   4) pm revoke RECORD_AUDIO (Android chiude l'app), riapertura;
#   5) di nuovo in onda, pm revoke CAMERA, riapertura;
#   6) pm revoke POST_NOTIFICATIONS in onda.
# Durante tutto il copione si osservano le connessioni dell'app (da /proc/net) e il logcat delle statistiche.
source "$(dirname "${BASH_SOURCE[0]}")/t07_comune.inc"

fps_computer() { tail -n 3 "$CF/statistiche.csv" 2>/dev/null | awk -F, '{s += $5} END {if (NR) printf "%d", s / NR; else print 0}'; }

guarda() {
    attendi "${2:-3}"
    c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
    schermata "$1"
    testi_visibili
    nota "$1: computer «$(stato_computer)», fps al computer $(fps_computer), processo $(processo_app)"
}

avvia_computer_finto --nome "PC di Paolo" --attesa-conferma 3 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
osserva_rete_inizia
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la principale non compare"
collega_indirizzo || fallisci "Collega a mano non riesce"
attendi_computer video 45 || fallisci "niente video al computer"
guarda "in-onda" 5
stato_permessi "in onda"

# ------------------------------------------------ 1) appops CAMERA ignore
adb_sh appops set "$PACCHETTO" CAMERA ignore
passo "APPOPS CAMERA ignore"
guarda "camera-ignore-3s" 3
guarda "camera-ignore-15s" 12
statistiche_computer 4
# ------------------------------------------------ 2) torna
adb_sh appops set "$PACCHETTO" CAMERA allow
passo "APPOPS CAMERA allow"
guarda "camera-allow-5s" 5
guarda "camera-allow-20s" 15
statistiche_computer 4

# ------------------------------------------------ 3) microfono acceso e poi ignorato
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
if tocca_testo "Microfono al computer"; then
    guarda "microfono-acceso" 3
    adb_sh appops set "$PACCHETTO" RECORD_AUDIO ignore
    passo "APPOPS RECORD_AUDIO ignore"
    guarda "microfono-ignore-10s" 10
    adb_sh appops set "$PACCHETTO" RECORD_AUDIO allow
    passo "APPOPS RECORD_AUDIO allow"
else
    nota "in onda non trovo «Microfono al computer»"
fi

# ------------------------------------------------ 4) pm revoke RECORD_AUDIO
prima=$(collegamenti_computer)
pid_prima=$(processo_app)
adb_sh pm revoke "$PACCHETTO" android.permission.RECORD_AUDIO
passo "PM REVOKE RECORD_AUDIO (processo prima: $pid_prima)"
guarda "revoca-microfono-3s" 3
guarda "revoca-microfono-12s" 9
avvia_app
guarda "revoca-microfono-riaperta" 4
avvisi_permessi "dopo revoca microfono e riapertura"
if attendi_ricollegamento "$prima" 40; then
    nota "dopo la revoca del microfono, riaperta l'app torna in onda da sola"
else
    nota "dopo la revoca del microfono, riaperta l'app NON torna in onda da sola (stato $(stato_computer))"
    collega_indirizzo
    attendi_computer video 40 || nota "neanche con «Collega a mano»"
fi
guarda "dopo-revoca-microfono-in-onda" 3
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
if tocca_testo "Microfono al computer"; then
    guarda "microfono-dopo-revoca" 2
    if attendi_id "permission_message" 4; then
        schermata "microfono-dopo-revoca-dialogo"
        nota "il microfono ora richiede il permesso con il dialogo di sistema"
        rifiuta_dialogo
        guarda "microfono-dopo-revoca-rifiutato" 2
    fi
fi

# ------------------------------------------------ 5) pm revoke CAMERA in onda
prima=$(collegamenti_computer)
adb_sh pm revoke "$PACCHETTO" android.permission.CAMERA
passo "PM REVOKE CAMERA"
guarda "revoca-fotocamera-3s" 3
nota "dopo la revoca della fotocamera, il computer: $(tail -n 3 "$CF/eventi.log" 2>/dev/null | tr '\n' ' ')"
avvia_app
guarda "revoca-fotocamera-riaperta" 4
avvisi_permessi "dopo revoca fotocamera e riapertura"
if attendi_id "permission_message" 4; then
    schermata "revoca-fotocamera-dialogo"
    nota "riaperta, l'app richiede la fotocamera con il dialogo"
    rifiuta_dialogo
fi
guarda "revoca-fotocamera-20s" 15
avvisi_permessi "revoca fotocamera dopo 20 s"
if attendi_ricollegamento "$prima" 10; then nota "senza fotocamera l'app si è ricollegata al computer (stato $(stato_computer), fps $(fps_computer))"; fi
statistiche_computer 4

# ------------------------------------------------ 6) pm revoke POST_NOTIFICATIONS in onda
adb_sh pm grant "$PACCHETTO" android.permission.CAMERA
avvia_app
attendi 3
c_e_testo "Collega a mano (indirizzo)" && collega_indirizzo
attendi_computer video 40 || nota "dopo aver ridato la fotocamera niente video (stato $(stato_computer))"
guarda "di-nuovo-in-onda" 3
adb_sh pm revoke "$PACCHETTO" android.permission.POST_NOTIFICATIONS
passo "PM REVOKE POST_NOTIFICATIONS"
guarda "revoca-notifiche-3s" 3
guarda "revoca-notifiche-15s" 12
stato_permessi "fine"

osserva_rete_ferma
lavori_app
logcat_statistiche
ferma_computer_finto
