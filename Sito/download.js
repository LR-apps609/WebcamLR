// Mette in evidenza la piattaforma di chi visita. Funziona anche senza: è solo un aiuto.
(function () {
  var agente = navigator.userAgent || "";
  var piattaforma = /iPhone|iPad|iPod/.test(agente) ? "iphone"
    : /Android/.test(agente) ? "android"
    : /Mac/.test(agente) ? "mac"
    : /Windows/.test(agente) ? "windows" : null;

  var scheda = piattaforma && document.querySelector('[data-piattaforma="' + piattaforma + '"]');
  if (scheda) {
    scheda.classList.add("evidente");
    var etichetta = scheda.querySelector(".riconosciuto");
    if (etichetta) etichetta.hidden = false;
    var pulsante = scheda.querySelector("a.pulsante");
    if (pulsante) { pulsante.classList.remove("contorno"); pulsante.classList.add("ciano"); }
  }

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
