# t13 (Elena): link webcamlr:// malformati, gettone sbagliato o già usato, codice rifiutato, nome del computer
# lunghissimo con emoji, conferma che non arriva.
source "$(dirname "${BASH_SOURCE[0]}")/t13_comune.inc"

apri_link() {
    local link="$1" nome="$2" esito
    passo "=== ELENA APRE IL LINK «$link» ($nome)"
    esito=$(adb shell "am start -W -a android.intent.action.VIEW -d '$link' $PACCHETTO" </dev/null 2>&1 | tr '\r\n' '  ')
    passo "am start: $esito"
    attendi 3
    schermata "$nome"
    testi_visibili
}

avvia_computer_finto --nome "PC di Elena" --attesa-conferma 6 || fallisci "il computer finto non parte"
LINK0=$(tr -d '\n' < "$CF/collegamento.txt")
PORTA=$(tr -d '\n' < "$CF/porta.txt" 2>/dev/null || echo 52740)
passo "Link vero del computer finto: $LINK0"
t13_prepara

# --- Link malformati: cosa vede Elena?
apri_link "webcamlr://collega" "link-senza-niente"; t13_torna
apri_link "webcamlr://collega?h=" "link-h-vuoto"; t13_torna
apri_link "webcamlr://collega?x=1&y=2" "link-parametri-strani"; t13_torna
apri_link "webcamlr://collega?h=%ZZ&n=Rotto" "link-percento-rotto"; t13_torna
apri_link "webcamlr://collega?h=999.999.999.999&p=52740&n=Finto" "link-ip-impossibile"
attendi 15; schermata "link-ip-impossibile-18s"; testi_visibili; t13_torna
apri_link "webcamlr://collega?h=ciao%20mondo&n=Spazi" "link-host-con-spazi"
attendi 15; schermata "link-host-con-spazi-18s"; testi_visibili; t13_torna
apri_link "webcamlr://collega?h=10.0.2.2&p=0&n=Porta%20zero" "link-porta-zero"
attendi 12; schermata "link-porta-zero-15s"; testi_visibili; t13_torna
apri_link "webcamlr://collega?h=10.0.2.2&p=$PORTA&v=999&n=Versione%20futura" "link-versione-999"
attendi 12; schermata "link-versione-999-15s"; testi_visibili; t13_torna
apri_link "webcamlr://altro?h=10.0.2.2" "link-host-sbagliato"; t13_torna
apri_link "WEBCAMLR://COLLEGA?h=10.0.2.2&p=$PORTA&n=Maiuscole" "link-maiuscole"
attendi 10; schermata "link-maiuscole-13s"; testi_visibili; t13_torna

# --- Gettone sbagliato: deve chiedere il codice (il computer finto consente da solo dopo 6 s).
LINK_SBAGLIATO=$(printf '%s' "$LINK0" | sed -E 's/([?&]g=)[^&]*/\1SBAGLIATOxxxxxxxxxxxxxxxx/')
passo "Link con il gettone sbagliato: $LINK_SBAGLIATO"
apri_link "$LINK_SBAGLIATO" "gettone-sbagliato"
if attendi_testo "Conferma sul computer" 10; then
    passo "Gettone sbagliato: chiede il codice ($(codice_computer)), bene"
    schermata "gettone-sbagliato-codice"
else
    nota "con il gettone sbagliato non compare «Conferma sul computer»"
fi
attendi_computer video 40 && schermata "gettone-sbagliato-in-onda"
t13_torna
schermata "dopo-gettone-sbagliato"

# --- Gettone già usato da un altro telefono: prima un telefono «nuovo» (dati cancellati) usa il link vero...
passo "Il link vero adesso è: $(tr -d '\n' < "$CF/collegamento.txt")"
cancella_dati_app
t13_prepara
apri_link "$LINK0" "link-vero-primo-uso"
if attendi_testo "Conferma sul computer" 6; then
    nota "il link vero (mai usato prima per entrare) chiede comunque il codice"
fi
attendi_computer video 40 && schermata "link-vero-in-onda"
t13_torna
# ...poi un altro telefono nuovo usa lo STESSO link (gettone scaduto).
cancella_dati_app
t13_prepara
apri_link "$LINK0" "link-scaduto"
if attendi_testo "Conferma sul computer" 10; then
    passo "Gettone scaduto: chiede il codice, bene"
    schermata "link-scaduto-codice"
else
    nota "con il gettone già usato non compare «Conferma sul computer»"
fi
attendi_computer video 40
schermata "link-scaduto-dopo"
testi_visibili
t13_torna
ferma_computer_finto

# --- Codice rifiutato sul computer, con un nome lunghissimo con emoji.
NOME_LUNGO="💻🔥 Il computer portatile dell'ufficio di Elena al terzo piano accanto alla macchinetta del caffè 🙃☕ (vecchio, Windows 10) — prova prova prova prova"
avvia_computer_finto --nome "$NOME_LUNGO" --rifiuta || fallisci "il computer finto (rifiuta) non parte"
LINK_LUNGO=$(tr -d '\n' < "$CF/collegamento.txt")
passo "Link del computer dal nome lungo: $LINK_LUNGO"
cancella_dati_app
t13_prepara
attendi 12
schermata "principale-con-nome-lungo"
testi_visibili
collega_indirizzo "10.0.2.2:$PORTA" || nota "non riesco a scrivere l'indirizzo"
attendi 2
schermata "rifiuta-dopo-collega"
testi_visibili
for s in 10 25 45; do attendi 10; schermata "rifiuta-${s}s"; done
testi_visibili
# Riprova dopo il rifiuto.
if c_e_testo "Riprova"; then
    tocca_testo "Riprova"
    attendi 5
    schermata "rifiuta-riprova"
    testi_visibili
fi
t13_torna
apri_link "$LINK_LUNGO" "link-nome-lungo-rifiuta"
attendi 10; schermata "link-nome-lungo-rifiuta-13s"; testi_visibili
t13_torna
tail -n 20 "$CF/eventi.log" | while read -r r; do passo "  CF: $r"; done
ferma_computer_finto

# --- Il computer non conferma mai: quanto aspetta il telefono e cosa dice?
avvia_computer_finto --nome "PC lento di Elena" --attesa-conferma 150 || fallisci "il computer finto (lento) non parte"
collega_indirizzo "10.0.2.2:$PORTA" || nota "non riesco a scrivere l'indirizzo"
for s in 5 30 60 90 120; do
    attendi $([ $s = 5 ] && echo 5 || echo 28)
    schermata "conferma-lenta-${s}s"
done
testi_visibili
attendi_computer video 60 && schermata "conferma-lenta-in-onda"
testi_visibili
t13_torna
tail -n 20 "$CF/eventi.log" | while read -r r; do passo "  CF: $r"; done
schermata "fine"
