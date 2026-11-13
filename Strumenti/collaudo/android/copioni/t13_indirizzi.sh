# t13 (Elena): «Collega a mano» con indirizzi sbagliati, irraggiungibili e un doppio tocco su Collega/Scollega.
source "$(dirname "${BASH_SOURCE[0]}")/t13_comune.inc"
avvia_computer_finto --nome "PC di Elena" --attesa-conferma 6 || fallisci "il computer finto non parte"
t13_prepara

# --- Indirizzi che non devono passare: il messaggio deve essere chiaro.
n=0
for indirizzo in "" "   " "abc" "ciao.come.stai.bene" "999.1.1.1" "10.0.2" "10.0.2.2.5" "10.0.2.2:0" "10.0.2.2:99999" \
                 "10.0.2.2:" "10.0.2.2:abc" "10.0.2.2:52740:1" "::1" "[fe80::1]:52740" "fe80::1" "localhost" \
                 "pc-di-elena.local" "http://10.0.2.2:52740" "10.0.2.2 52740" "-1.0.0.1"; do
    n=$((n + 1))
    t13_prova_indirizzo "$indirizzo" "sbagliato-$n"
    if ! c_e_testo "Indirizzo del computer"; then
        attendi 8
        schermata "sbagliato-$n-dopo-8s"
        testi_visibili
        t13_torna || nota "dopo «$indirizzo» non torno alla schermata principale"
    fi
done
# Il dialogo si chiude con Annulla: alla riapertura cosa propone?
tocca_testo "Annulla"
attendi 1
tocca_testo "Collega a mano (indirizzo)"
attendi 1
schermata "riapertura-dopo-errori"
testi_visibili
tocca_testo "Annulla"

# --- Indirizzi formalmente validi ma senza computer.
for coppia in "192.0.2.1:irraggiungibile" "10.0.2.2:1:porta-chiusa" "0.0.0.0:zeri" "255.255.255.255:broadcast" "10.0.2.15:se-stesso"; do
    indirizzo="${coppia%:*}"; nome="${coppia##*:}"
    t13_prova_indirizzo "$indirizzo" "$nome"
    for s in 5 15 30; do
        attendi $([ $s = 5 ] && echo 3 || echo 10)
        schermata "$nome-${s}s"
    done
    testi_visibili
    attendi 15
    schermata "$nome-45s"
    testi_visibili
    t13_torna || nota "dopo «$indirizzo» non torno alla schermata principale"
    attendi 1
done

# --- Spazi intorno a un indirizzo giusto: deve collegarsi.
t13_prova_indirizzo "  10.0.2.2:$(cat "$CF/porta.txt" 2>/dev/null || echo 52740)  " "spazi-intorno"
if attendi_testo "Conferma sul computer" 15; then
    passo "Spazi intorno: accettato, chiede il codice $(codice_computer)"
    schermata "spazi-intorno-codice"
fi
if attendi_computer video 45; then
    schermata "in-onda"
    # Tre tocchi rapidi su Scollega, poi tre sulla conferma.
    c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
    t13_tocchi_rapidi "Scollega" 3 0.15
    attendi 1
    schermata "scollega-tre-tocchi"
    testi_visibili
    if c_e_testo "Scollegare il telefono?"; then
        t13_tocchi_rapidi "Scollega" 3 0.1
        attendi 2
        schermata "dopo-conferma-tre-tocchi"
        testi_visibili
    fi
    attendi 3
    schermata "dopo-scollega"
else
    nota "con «  10.0.2.2  » (spazi intorno) niente video"
    testi_visibili
fi
t13_torna

# --- Doppio (triplo) tocco rapido su «Collega» nel dialogo, con l'indirizzo giusto.
tocca_testo "Collega a mano (indirizzo)"
tocca_classe android.widget.EditText
svuota_campo
scrivi "10.0.2.2:$(cat "$CF/porta.txt" 2>/dev/null || echo 52740)"
prima=$(collegamenti_computer)
t13_tocchi_rapidi "Collega" 3 0.12
attendi 1
schermata "collega-tre-tocchi"
attendi_computer video 45 && passo "Video dopo tre tocchi su Collega"
attendi 4
schermata "collega-tre-tocchi-dopo"
testi_visibili
passo "Collegamenti accettati dal computer: prima $prima, dopo $(collegamenti_computer)"
grep -c "COLLEGATO\|CONFERMA\|RIFIUT" "$CF/eventi.log" | xargs -I{} passo "Righe di eventi del computer: {}"
tail -n 30 "$CF/eventi.log" | while read -r r; do passo "  CF: $r"; done
t13_torna
schermata "fine"
