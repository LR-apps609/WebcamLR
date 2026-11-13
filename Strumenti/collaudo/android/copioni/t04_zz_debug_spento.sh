# Copione «t04_zz_debug_spento» (collaudo-20, tester t04): il debug USB spento in onda. Va lanciato per ULTIMO: spento
# il debug USB, adb non comanda più l'emulatore. Le schermate dopo lo spegnimento si prendono dalla console
# dell'emulatore (`adb emu screenrecord screenshot`), che non passa da adbd.

riaccendi() { c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte; return 0; }
foto_console() {
    mkdir -p "$USCITA/console"
    if adb emu screenrecord screenshot "$USCITA/console" >> "$USCITA/console/esito.txt" 2>&1; then
        passo "FOTO DALLA CONSOLE ($1): $(ls -t "$USCITA/console" | head -1)"
        local ultima; ultima=$(ls -t "$USCITA/console"/*.png 2>/dev/null | head -1)
        [ -n "$ultima" ] && mv "$ultima" "$USCITA/console/$1.png"
    else
        passo "FOTO DALLA CONSOLE ($1) non riuscita: $(tail -1 "$USCITA/console/esito.txt")"
    fi
}

avvia_computer_finto --nome "PC di Marco" --attesa-conferma 3 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
collega_cavo
attendi_computer video 45 || fallisci "dal cavo il computer finto non riceve il video"
attendi 5
schermata "1-in-onda-cavo"
foto_console "prova-console-prima"

# Prima di spegnere: il logcat finora (dopo non si legge più).
adb logcat -d -v threadtime > "$USCITA/logcat-prima-dello-spegnimento.txt" 2>/dev/null
SPENTO=$(date +%s)
adb shell settings put global adb_enabled 0 </dev/null
passo "DEBUG USB SPENTO (settings put global adb_enabled 0)"
attendi 5
passo "adb devices: $(adb devices 2>&1 | tr '\n' ' ')"
nota "dopo 5 s col debug spento il computer è «$(stato_computer)»"
attendi 10
foto_console "debug-spento-15s"
attendi 25
foto_console "debug-spento-40s"
nota "dopo 40 s col debug spento il computer è «$(stato_computer)»; adb: $(adb devices 2>&1 | tail -n +2 | tr '\n' ' ')"
# Se adb risponde ancora, l'emulatore non simula lo spegnimento: lo scrivo e fotografo anche così.
if adb shell true </dev/null 2>/dev/null; then
    nota "adb risponde ancora con adb_enabled=0: l'emulatore non chiude adbd"
    riaccendi
    schermata "2-debug-spento-40s"
    testi_visibili
    adb shell settings put global adb_enabled 1 </dev/null
fi
sed 's/^/        /' "$CF/eventi.log" >> "$USCITA/note.txt" 2>/dev/null
ferma_computer_finto
true
