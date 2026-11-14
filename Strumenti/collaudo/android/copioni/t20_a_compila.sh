# t20 · Luisa, passo A: compila sul runner l'APK di debug della beta 4 (d49224a, build 5) per i copioni t20_b e t20_c.
# Stessa macchina, stessa chiave di debug (~/.android/debug.keystore): l'aggiornamento con «adb install -r» è possibile.
source "$_CARTELLA_LIB/copioni/t20_comune.inc"
radice="${GITHUB_WORKSPACE:-$PWD}"
vecchia="$T20_CARTELLA/sorgente-beta4"
passo "Scarico la beta 4 ($T20_BETA4)"
( cd "$radice" && git fetch -q --depth=1 origin "$T20_BETA4" && git worktree add -q --detach "$vecchia" FETCH_HEAD ) \
    >> "$USCITA/compila.log" 2>&1 || fallisci "non riesco a scaricare la beta 4 (vedi compila.log)"
# La beta 4 così com'è non si compila più da zero: Billing 7.x vuole com.google.firebase dal repository di Google, che
# il suo settings.gradle.kts filtra (corretto dopo, nella versione nuova). Solo nella copia temporanea del runner.
sed -i 's|includeGroupByRegex("com\\\\.google\\\\.mediapipe.\*")|&\n                includeGroupByRegex("com\\\\.google\\\\.firebase.*")|' "$vecchia/Android/settings.gradle.kts"
grep -n 'firebase' "$vecchia/Android/settings.gradle.kts" | sed 's/^/        /' >> "$USCITA/passi.log" || nota "correzione del repository non applicata"
passo "Compilo la beta 4 (assembleDebug)"
( cd "$vecchia/Android" && ./gradlew --no-daemon -q :app:assembleDebug ) >> "$USCITA/compila.log" 2>&1 \
    || { tail -40 "$USCITA/compila.log" >> "$USCITA/passi.log"; fallisci "la beta 4 non si compila (vedi compila.log)"; }
apk=$(find "$vecchia/Android/app/build/outputs/apk/debug" -name '*.apk' | head -1)
[ -n "$apk" ] || fallisci "nessun APK della beta 4"
cp "$apk" "$T20_APK_VECCHIO"
passo "APK della beta 4: $(ls -la "$T20_APK_VECCHIO")"
bt=$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -1)
for f in "$T20_APK_VECCHIO" "$APK"; do
    passo "Firma di $(basename "$f"): $("$bt/apksigner" verify --print-certs "$f" 2>/dev/null | grep -m1 'SHA-256')"
    passo "Versione di $(basename "$f"): $("$bt/aapt2" dump badging "$f" 2>/dev/null | head -1)"
done
