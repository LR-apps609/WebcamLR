# t09 · Anna sul Pixel 6: «Dimensioni visualizzazione» al massimo (densità 560) e carattere 1,5; poi lo schermo
# piccolissimo del banco (480x800 @240) con carattere 1,3. Verticale e orizzontale della principale.
source "$_CARTELLA_LIB/t09_comune.sh"
adb_sh wm density 560; adb_sh settings put system font_scale 1.5
passo "PIXEL 6, densità 560, carattere 1.5x"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 && tocca_testo "Salta"
tocca_testo "Inizia"
giro_completo "g"
ruota orizzontale
attendi 2
giro "g-principale-orizzontale" 5
ruota verticale
adb_sh wm density reset
schermo_piccolo
carattere_grande 1.3
avvia_app
attendi 3
giro "p-principale" 6
if tocca_testo "Impostazioni"; then giro "p-impostazioni" 12; indietro; fi
ruota orizzontale
attendi 2
giro "p-principale-orizzontale" 6
