#!/bin/bash
# Doppio clic dal Finder sul Mac.
# Prepara WebcamLR per Mac da pubblicare: costruisce in Release, crea «WebcamLR.dmg» (l'app e il collegamento ad
# Applicazioni) e «WebcamLR Microfono.pkg» (il microfono del telefono, P20: driver audio, aiutante e LaunchDaemon),
# che va anche dentro il dmg.
#
# La firma dipende da cosa c'è sul Mac (guida passo passo: Documenti/Pubblicazione.md):
# - certificato «Developer ID Application» → firma per tutti (runtime protetto) e, con il profilo di notarytool,
#   notarizzazione e «staple»: il dmg si apre su qualsiasi Mac senza avvisi. Con «Developer ID Installer» anche il pkg.
# - account a pagamento senza Developer ID → firma «Apple Development»: va solo sui Mac registrati nell'account.
# - Apple ID gratuito → firma locale («Sign to Run Locally»): solo per provare il dmg su questo Mac.
#
# Le identità si trovano da sole nel Portachiavi; se ce ne sono più di una, o per il profilo di notarizzazione,
# si scrivono in Strumenti/firma.txt (non va nella repository: c'è un esempio in Strumenti/firma.esempio.txt)
# oppure nelle variabili d'ambiente WEBCAMLR_FIRMA_APP, WEBCAMLR_FIRMA_INSTALLER, WEBCAMLR_PROFILO_NOTARIZZAZIONE.
set -euo pipefail
cd "$(dirname "$0")/.."
REGISTRO="Strumenti/ultima-build.log"
# Come in «Costruisci e installa»: i prodotti stanno fuori dalla repository (cartelle iCloud).
CARTELLA_BUILD="$HOME/Library/Developer/WebcamLR"
DERIVATI="$CARTELLA_BUILD/Rilascio"
ETICHETTA="it.lrapps.webcamlr.microfono"
DRIVER="WebcamLR Microfono.driver"
AIUTO="webcamlr-microfono-aiuto"
: > "$REGISTRO"

fallito() {
  echo
  echo "Qualcosa non va. Manda a Claude il file $REGISTRO o le righe qui sopra."
  read -r -p "Premi Invio per chiudere."
  exit 1
}
trap fallito ERR

# Mostra le righe utili di un errore di xcodebuild e si ferma.
errore_build() {
  grep -i -E "error|failed" "$REGISTRO" | grep -v -E "^\s*$" | tail -25 || tail -30 "$REGISTRO"
  false
}

# ——— Cosa c'è ———

if ! command -v xcodegen >/dev/null; then
  echo "Serve XcodeGen: fai prima doppio clic su «Costruisci e installa.command», che lo installa."
  false
fi
if [ ! -s Strumenti/team.txt ]; then
  echo "Manca Strumenti/team.txt (il Team ID Apple): fai prima doppio clic su «Costruisci e installa.command»."
  false
fi
export WEBCAMLR_TEAM="$(tr -d '[:space:]' < Strumenti/team.txt)"
ACCOUNT="$( [ -s Strumenti/account.txt ] && tr -d '[:space:]' < Strumenti/account.txt || echo gratuito)"
if [ "$ACCOUNT" = "completo" ]; then PROGETTO_MAC=project.yml; else PROGETTO_MAC=project-senza-account.yml; fi

leggi_versione() { sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p" Strumenti/Versione.xcconfig | head -1; }
VERSIONE="$(leggi_versione MARKETING_VERSION)"
BUILD="$(leggi_versione CURRENT_PROJECT_VERSION)"

# Un valore da Strumenti/firma.txt (righe CHIAVE=valore, senza virgolette).
leggi_firma() {
  [ -s Strumenti/firma.txt ] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p" Strumenti/firma.txt | head -1 | sed -E 's/^"(.*)"$/\1/'
}
FIRMA_APP="${WEBCAMLR_FIRMA_APP:-$(leggi_firma FIRMA_APP)}"
FIRMA_INSTALLER="${WEBCAMLR_FIRMA_INSTALLER:-$(leggi_firma FIRMA_INSTALLER)}"
PROFILO="${WEBCAMLR_PROFILO_NOTARIZZAZIONE:-$(leggi_firma PROFILO_NOTARIZZAZIONE)}"

# Senza indicazioni, le identità Developer ID del Portachiavi per questo team (solo se ce n'è una).
trova_identita() {
  local elenco
  elenco="$(security find-identity -v $2 2>/dev/null | sed -n -E "s/.*\"($1: .*\($WEBCAMLR_TEAM\))\"$/\1/p" | sort -u || true)"
  if [ "$(printf '%s' "$elenco" | grep -c .)" = "1" ]; then printf '%s' "$elenco"; fi
}
[ -n "$FIRMA_APP" ] || FIRMA_APP="$(trova_identita "Developer ID Application" "-p codesigning")"
[ -n "$FIRMA_INSTALLER" ] || FIRMA_INSTALLER="$(trova_identita "Developer ID Installer" "")"
if [ -n "$FIRMA_APP" ] && ! security find-identity -v -p codesigning | grep -qF "\"$FIRMA_APP\""; then
  echo "⚠️  Non trovo nel Portachiavi l'identità «$FIRMA_APP» (da Strumenti/firma.txt o WEBCAMLR_FIRMA_APP)."
  echo "   Controlla il nome con: security find-identity -v -p codesigning"
  false
fi
if [ -n "$PROFILO" ] && ! xcrun notarytool history --keychain-profile "$PROFILO" >/dev/null 2>&1; then
  echo "⚠️  Il profilo di notarizzazione «$PROFILO» non funziona: lo ignoro (niente notarizzazione)."
  echo "   Si crea una volta con: xcrun notarytool store-credentials \"$PROFILO\" --apple-id TUA@EMAIL --team-id $WEBCAMLR_TEAM"
  echo "   (la password è una «password specifica per app» da account.apple.com). Guida: Documenti/Pubblicazione.md."
  PROFILO=""
fi

if [ -n "$FIRMA_APP" ]; then
  MODO=pubblico
elif [ "$ACCOUNT" = "completo" ]; then
  MODO=sviluppo
else
  MODO=locale
fi

USCITA="$CARTELLA_BUILD/Pubblicazione/$VERSIONE"
LAVORO="$CARTELLA_BUILD/Pubblicazione/lavoro"
rm -rf "$LAVORO" "$USCITA"
mkdir -p "$LAVORO" "$USCITA"

echo "WebcamLR $VERSIONE (build $BUILD) per Mac · account: $ACCOUNT"
case "$MODO" in
  pubblico) echo "Firma: $FIRMA_APP" ;;
  sviluppo) echo "Firma: Apple Development (manca il certificato «Developer ID Application»): il dmg va solo sui Mac registrati nel tuo account." ;;
  locale)   echo "Firma: locale («Sign to Run Locally», Apple ID gratuito): il dmg serve solo per provarlo su questo Mac." ;;
esac
echo

# ——— Notarizzazione ———

# notarizza FILE: lo manda ad Apple, aspetta l'esito e attacca il ticket («staple»). Vero se accettato.
notarizza() {
  local file="$1" risultato stato id
  echo "   Mando «$(basename "$file")» ad Apple per la notarizzazione (di solito da 1 a 10 minuti)…"
  risultato="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILO" --wait --output-format json 2>>"$REGISTRO" || true)"
  echo "$risultato" >> "$REGISTRO"
  stato="$(printf '%s' "$risultato" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$risultato" | plutil -extract id raw -o - - 2>/dev/null || true)"
  if [ "$stato" = "Accepted" ]; then
    xcrun stapler staple "$file" >> "$REGISTRO" 2>&1 && echo "   Notarizzato e con il ticket attaccato." && return 0
    echo "⚠️  Notarizzato, ma il ticket non si attacca: manda a Claude il file $REGISTRO."
    return 1
  fi
  echo "⚠️  Apple non ha accettato «$(basename "$file")» (stato: ${stato:-nessuna risposta})."
  if [ -n "$id" ]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILO" "$USCITA/notarizzazione-$(basename "$file").json" >> "$REGISTRO" 2>&1 || true
    echo "   Il motivo è in $USCITA/notarizzazione-$(basename "$file").json: mandalo a Claude."
  fi
  return 1
}

# ——— 1. Progetto ———

echo "1/4 · Progetto Xcode ($PROGETTO_MAC)"
(cd Mac && xcodegen generate --quiet --spec "$PROGETTO_MAC")

# ——— 2. App ———

echo "2/4 · Compilo WebcamLR in Release"
case "$MODO" in
  pubblico)
    xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme WebcamLR -configuration Release \
      -derivedDataPath "$DERIVATI" -archivePath "$LAVORO/WebcamLR.xcarchive" -allowProvisioningUpdates \
      archive >> "$REGISTRO" 2>&1 || errore_build
    cat > "$LAVORO/OpzioniEsportazione.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$WEBCAMLR_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
    echo "   Firmo con Developer ID (runtime protetto)"
    xcodebuild -exportArchive -archivePath "$LAVORO/WebcamLR.xcarchive" -exportPath "$LAVORO/esportata" \
      -exportOptionsPlist "$LAVORO/OpzioniEsportazione.plist" -allowProvisioningUpdates >> "$REGISTRO" 2>&1 || {
        echo "⚠️  L'esportazione con Developer ID non è riuscita. Di solito: Xcode non è collegato all'account"
        echo "   (Xcode › Impostazioni › Account) o il tuo ruolo nel team non può creare profili Developer ID."
        errore_build
      }
    APP="$LAVORO/esportata/WebcamLR.app"
    ;;
  sviluppo)
    xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme WebcamLR -configuration Release \
      -derivedDataPath "$DERIVATI" -allowProvisioningUpdates build >> "$REGISTRO" 2>&1 || errore_build
    APP="$DERIVATI/Build/Products/Release/WebcamLR.app"
    ;;
  locale)
    xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme WebcamLR -configuration Release \
      -derivedDataPath "$DERIVATI" CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
      PROVISIONING_PROFILE_SPECIFIER="" build >> "$REGISTRO" 2>&1 || errore_build
    APP="$DERIVATI/Build/Products/Release/WebcamLR.app"
    ;;
esac
codesign --verify --deep --strict "$APP" >> "$REGISTRO" 2>&1 || {
  echo "⚠️  La firma di WebcamLR.app non è valida."
  errore_build
}

# ——— 3. Microfono (pkg) ———

echo "3/4 · Pacchetto del microfono"
PKG=""
PKG_NOTARIZZATO=no
# L'aiutante si firma come l'app: in modo locale tutti e due con la firma locale («-»), altrimenti «Apple Development»
# del team (in modo pubblico poi si rifirma con Developer ID, qui sotto). Documenti/Microfono Mac.md, Sicurezza.
FIRMA_MICROFONO=(-allowProvisioningUpdates)
if [ "$MODO" = "locale" ]; then
  FIRMA_MICROFONO=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
fi
if ! xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme "WebcamLR Microfono" -configuration Release \
    -derivedDataPath "$DERIVATI" "${FIRMA_MICROFONO[@]}" build >> "$REGISTRO" 2>&1; then
  echo "⚠️  Il microfono virtuale non compila: il dmg avrà solo l'app. Manda a Claude il file $REGISTRO."
else
  PRODOTTI="$DERIVATI/Build/Products/Release"
  RADICE="$LAVORO/microfono/radice"
  SCRIPT="$LAVORO/microfono/script"
  mkdir -p "$RADICE/Library/Audio/Plug-Ins/HAL" "$RADICE/Library/Application Support/WebcamLR" "$RADICE/Library/LaunchDaemons" "$SCRIPT"
  ditto "$PRODOTTI/$DRIVER" "$RADICE/Library/Audio/Plug-Ins/HAL/$DRIVER"
  install -m 755 "$PRODOTTI/$AIUTO" "$RADICE/Library/Application Support/WebcamLR/$AIUTO"
  install -m 644 "Mac/Microfono/Aiuto/$ETICHETTA.plist" "$RADICE/Library/LaunchDaemons/$ETICHETTA.plist"
  install -m 644 "Mac/Microfono/Aiuto/$ETICHETTA.rimozione.plist" "$RADICE/Library/LaunchDaemons/$ETICHETTA.rimozione.plist"

  if [ "$MODO" = "pubblico" ]; then
    # Nel progetto driver e aiutante hanno la firma locale («-»): qui si rifirmano per la distribuzione.
    codesign --force --options runtime --timestamp --sign "$FIRMA_APP" \
      "$RADICE/Library/Audio/Plug-Ins/HAL/$DRIVER" >> "$REGISTRO" 2>&1
    codesign --force --options runtime --timestamp --sign "$FIRMA_APP" --identifier "$ETICHETTA.aiuto" \
      "$RADICE/Library/Application Support/WebcamLR/$AIUTO" >> "$REGISTRO" 2>&1
  fi

  # Prima dell'installazione si ferma l'aiutante vecchio; dopo si avvia quello nuovo e si riavvia l'audio
  # (coreaudiod carica i driver solo all'avvio). Le stesse righe di «Installa microfono.command».
  cat > "$SCRIPT/preinstall" <<'SH'
#!/bin/sh
launchctl bootout system/it.lrapps.webcamlr.microfono 2>/dev/null
launchctl bootout system/it.lrapps.webcamlr.microfono.rimozione 2>/dev/null
exit 0
SH
  cat > "$SCRIPT/postinstall" <<'SH'
#!/bin/sh
PLIST=/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist
RIMOZIONE=/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.rimozione.plist
chown root:wheel "$PLIST" "$RIMOZIONE"
chmod 644 "$PLIST" "$RIMOZIONE"
xattr -dr com.apple.quarantine "/Library/Audio/Plug-Ins/HAL/WebcamLR Microfono.driver" \
  "/Library/Application Support/WebcamLR/webcamlr-microfono-aiuto" 2>/dev/null
launchctl bootstrap system "$PLIST" 2>/dev/null || launchctl kickstart -k system/it.lrapps.webcamlr.microfono 2>/dev/null
launchctl bootstrap system "$RIMOZIONE" 2>/dev/null
killall coreaudiod 2>/dev/null || launchctl kickstart -k system/com.apple.audio.coreaudiod 2>/dev/null
exit 0
SH
  chmod 755 "$SCRIPT/preinstall" "$SCRIPT/postinstall"

  # Il driver va sempre in /Library/Audio/Plug-Ins/HAL: senza questo, se trovasse un bundle con lo stesso
  # identificatore altrove (per esempio in una cartella di build), l'Installer lo aggiornerebbe lì.
  pkgbuild --analyze --root "$RADICE" "$LAVORO/microfono/componenti.plist" >> "$REGISTRO" 2>&1
  i=0
  while /usr/libexec/PlistBuddy -c "Print :$i" "$LAVORO/microfono/componenti.plist" >/dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$LAVORO/microfono/componenti.plist"
    i=$((i + 1))
  done

  pkgbuild --root "$RADICE" --component-plist "$LAVORO/microfono/componenti.plist" --scripts "$SCRIPT" \
    --identifier "$ETICHETTA" --version "$VERSIONE" --install-location / \
    "$LAVORO/microfono/componente.pkg" >> "$REGISTRO" 2>&1
  PKG="$USCITA/WebcamLR Microfono.pkg"
  if [ "$MODO" = "pubblico" ] && [ -n "$FIRMA_INSTALLER" ]; then
    productbuild --package "$LAVORO/microfono/componente.pkg" --sign "$FIRMA_INSTALLER" --timestamp "$PKG" >> "$REGISTRO" 2>&1
    echo "   Firmato con $FIRMA_INSTALLER"
    if [ -n "$PROFILO" ]; then
      if notarizza "$PKG"; then PKG_NOTARIZZATO=si; fi
    fi
  else
    productbuild --package "$LAVORO/microfono/componente.pkg" "$PKG" >> "$REGISTRO" 2>&1
    if [ "$MODO" = "pubblico" ]; then
      echo "   ⚠️  Pacchetto non firmato: manca il certificato «Developer ID Installer» (vedi Documenti/Pubblicazione.md)."
    else
      echo "   Pacchetto non firmato: va bene per le prove su questo Mac (clic destro › Apri)."
    fi
  fi
fi

# ——— 4. dmg ———

echo "4/4 · Immagine disco"
CONTENUTO="$LAVORO/dmg"
mkdir -p "$CONTENUTO"
ditto "$APP" "$CONTENUTO/WebcamLR.app"
ln -s /Applications "$CONTENUTO/Applicazioni"
[ -n "$PKG" ] && cp "$PKG" "$CONTENUTO/"
DMG="$USCITA/WebcamLR.dmg"
hdiutil create -volname "WebcamLR $VERSIONE" -srcfolder "$CONTENUTO" -fs HFS+ -format UDZO -ov "$DMG" >> "$REGISTRO" 2>&1
DMG_NOTARIZZATO=no
if [ "$MODO" = "pubblico" ]; then
  codesign --sign "$FIRMA_APP" --timestamp "$DMG" >> "$REGISTRO" 2>&1
  if [ -n "$PROFILO" ]; then
    if notarizza "$DMG"; then DMG_NOTARIZZATO=si; fi
  fi
fi

# ——— Riepilogo ———

echo
echo "Fatto. In $USCITA:"
echo "  · WebcamLR.dmg"
[ -n "$PKG" ] && echo "  · WebcamLR Microfono.pkg (è anche dentro il dmg)"
echo
case "$MODO" in
  pubblico)
    if [ "$DMG_NOTARIZZATO" = si ]; then
      spctl -a -t open --context context:primary-signature -v "$DMG" >> "$REGISTRO" 2>&1 \
        && echo "Pronto da pubblicare: Gatekeeper accetta il dmg." \
        || echo "⚠️  Notarizzato, ma Gatekeeper non accetta ancora il dmg: manda a Claude il file $REGISTRO."
    elif [ -z "$PROFILO" ]; then
      echo "Firmato ma NON notarizzato: manca il profilo di notarytool (PROFILO_NOTARIZZAZIONE in Strumenti/firma.txt)."
      echo "Senza notarizzazione macOS blocca l'app scaricata. Guida: Documenti/Pubblicazione.md, «Notarizzazione»."
    else
      echo "⚠️  Firmato ma la notarizzazione non è riuscita (vedi sopra): non pubblicarlo così."
    fi
    if [ -n "$PKG" ] && [ "$PKG_NOTARIZZATO" = no ]; then
      echo "Il pacchetto del microfono non è notarizzato: chi lo scarica vedrà l'avviso di macOS."
    fi
    ;;
  sviluppo)
    echo "Solo per i Mac registrati nel tuo account. Per pubblicare serve «Developer ID Application»:"
    echo "Documenti/Pubblicazione.md, «Certificati»."
    ;;
  locale)
    echo "Solo per provarlo su questo Mac: su altri Mac macOS lo blocca. Per pubblicare servono l'account"
    echo "sviluppatore a pagamento e il certificato «Developer ID Application» (Documenti/Pubblicazione.md)."
    ;;
esac
open "$USCITA"
read -r -p "Premi Invio per chiudere."
