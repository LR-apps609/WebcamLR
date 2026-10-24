// Ricerca nelle domande frequenti, come nell'app: una domanda corrisponde se contiene
// tutte le parole cercate, senza badare a maiuscole e accenti. Senza JavaScript le domande
// restano tutte visibili e la casella di ricerca non compare.
(function () {
  var riquadro = document.getElementById("ricerca");
  var campo = document.getElementById("cerca");
  var conteggio = document.getElementById("conteggio");
  var nessuna = document.getElementById("nessuna");
  var domande = document.querySelectorAll("#elenco-domande details");
  if (!riquadro || !campo) return;

  function normalizza(testo) {
    return testo.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  var testi = [];
  for (var i = 0; i < domande.length; i++) {
    testi.push(normalizza(domande[i].textContent + " " + (domande[i].getAttribute("data-parole") || "")));
  }

  function filtra() {
    var parti = normalizza(campo.value).split(/\s+/).filter(Boolean);
    var trovate = 0, ultima = null;
    for (var i = 0; i < domande.length; i++) {
      var ok = parti.every(function (p) { return testi[i].indexOf(p) !== -1; });
      domande[i].hidden = !ok;
      if (ok) { trovate++; ultima = domande[i]; }
    }
    if (parti.length && trovate === 1) ultima.open = true;
    nessuna.hidden = trovate !== 0;
    conteggio.textContent = parti.length ? (trovate === 1 ? "1 risposta" : trovate + " risposte") : "";
  }

  campo.addEventListener("input", filtra);
  riquadro.hidden = false;

  // Un link come aiuto.html#d-cavo apre già la risposta giusta.
  function apriDaIndirizzo() {
    var bersaglio = location.hash && document.getElementById(location.hash.slice(1));
    if (bersaglio && bersaglio.tagName === "DETAILS") bersaglio.open = true;
  }
  window.addEventListener("hashchange", apriDaIndirizzo);
  apriDaIndirizzo();
})();
