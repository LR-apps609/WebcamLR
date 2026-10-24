// Download di WebcamLR.
//
// QUI SI CAMBIANO I LINK. Quando una versione è pubblicata, scrivi l'indirizzo in `url`
// (e, se vuoi, il nome e il peso del file in `dettaglio`): il pulsante diventa un link vero.
// Con `url: null` resta il pulsante grigio con «presto».
// Senza JavaScript la pagina mostra i testi scritti in download.html: quando un link diventa
// vero, aggiorna anche lo <span data-download="..."> corrispondente (o trasformalo in <a href>).
var DOWNLOAD = {
  "mac-dmg":             { url: null, testo: "Scarica per Mac (.dmg)",          dettaglio: null },
  "windows-installer":   { url: null, testo: "Scarica per Windows",             dettaglio: null },
  "linux":               { url: null, testo: "Scarica per Linux",               dettaglio: null },
  "iphone-app-store":    { url: null, testo: "Scarica da App Store",            dettaglio: null },
  "iphone-testflight":   { url: null, testo: "Prova la beta con TestFlight",    dettaglio: null },
  "android-google-play": { url: null, testo: "Scarica da Google Play",          dettaglio: null },
  "android-appgallery":  { url: null, testo: "Scarica da Huawei AppGallery",    dettaglio: null },
  "android-apk":         { url: null, testo: "Scarica il file APK",             dettaglio: null }
};

(function () {
  // 1. Pulsanti: da «presto» a link veri, secondo DOWNLOAD.
  var segnaposti = document.querySelectorAll("[data-download]");
  for (var i = 0; i < segnaposti.length; i++) {
    var el = segnaposti[i];
    var voce = DOWNLOAD[el.getAttribute("data-download")];
    if (!voce || !voce.url) continue;
    var link = document.createElement("a");
    link.className = "pulsante contorno";
    link.href = voce.url;
    link.textContent = voce.testo;
    link.setAttribute("data-download", el.getAttribute("data-download"));
    el.parentNode.replaceChild(link, el);
    if (voce.dettaglio) {
      var nota = document.createElement("div");
      nota.className = "file";
      nota.textContent = voce.dettaglio;
      link.parentNode.insertBefore(nota, link.nextSibling);
    }
  }

  // 2. Riconosce il dispositivo di chi visita. È solo un aiuto: senza, la pagina mostra tutto uguale.
  var agente = navigator.userAgent || "";
  var tocco = (navigator.maxTouchPoints || 0) > 1;
  var piattaforma =
      /iPhone|iPad|iPod/.test(agente) || (/Macintosh/.test(agente) && tocco) ? "iphone" // iPad si presenta come Mac
    : /Android/.test(agente) ? "android"
    : /Windows/.test(agente) ? "windows"
    : /Macintosh|Mac OS X/.test(agente) ? "mac"
    : /CrOS/.test(agente) ? null
    : /Linux|X11/.test(agente) ? "linux"
    : null;

  var nomi = { iphone: "un iPhone o un iPad", android: "Android", windows: "Windows", mac: "un Mac", linux: "Linux" };
  var scheda = piattaforma && document.querySelector('[data-piattaforma="' + piattaforma + '"]');
  if (scheda) {
    scheda.classList.add("evidente");
    var etichetta = scheda.querySelector(".riconosciuto");
    if (etichetta) etichetta.hidden = false;
    var primo = scheda.querySelector("a.pulsante[data-download]");
    if (primo) { primo.classList.remove("contorno"); primo.classList.add("ciano"); }

    var rilevato = document.getElementById("rilevato");
    if (rilevato) {
      rilevato.textContent = "Stai usando " + nomi[piattaforma] + ": la tua versione è la prima, evidenziata.";
      rilevato.hidden = false;
    }
  }

  // 3. Dal telefono il programma per computer non serve qui: si manda il link al computer.
  if (piattaforma === "iphone" || piattaforma === "android") {
    var avviso = document.getElementById("dal-telefono");
    var condividi = document.getElementById("condividi");
    if (avviso) avviso.hidden = false;
    if (condividi) {
      condividi.addEventListener("click", function () {
        var indirizzo = location.href.split("#")[0];
        if (navigator.share) {
          navigator.share({ title: "Scarica WebcamLR", url: indirizzo }).catch(function () {});
        } else if (navigator.clipboard) {
          navigator.clipboard.writeText(indirizzo).then(function () { condividi.textContent = "Link copiato"; });
        }
      });
    }
  }
})();
