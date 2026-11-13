// Ricerca nelle domande frequenti, come nell'app: una domanda corrisponde se contiene
// tutte le parole cercate, senza badare a maiuscole e accenti, con le parole ridotte alla radice
// e senza le parole vuote («quanto», «come», «how»…). Senza JavaScript le domande
// restano tutte visibili e la casella di ricerca non compare. Italiano o inglese secondo <html lang>.
(function () {
  var inglese = (document.documentElement.lang || "").slice(0, 2) === "en";
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

  // Parole che da sole non dicono cosa si cerca: si ignorano se c'è almeno un'altra parola («quanto costa»).
  var VUOTE = ("a ad al alla allo che chi come con cosa cos da dal del della di e ed il in la le lo ma mi ne nel non o per " +
    "perche quale quali quando quanto quanta quanti quante se si su sul sulla un una uno " +
    "an and are can do does for how i in is it me much my of on or the to what when where which why with").split(" ");
  // Radice semplice, perché le parole delle domande non sono sempre nella stessa forma: «costa» trova «costo»,
  // «prezzi» trova «prezzo», «costs» e «cables» trovano «cost» e «cable». Solo sulle parole di almeno 4 lettere.
  function radice(parola) {
    if (parola.length < 4) return parola;
    if (/[^s]s$/.test(parola)) parola = parola.slice(0, -1);        // inglese: costs, prices, cables
    else if (/[aeiou]$/.test(parola)) parola = parola.slice(0, -1); // italiano: costa, prezzi, cavi
    return parola;
  }

  function filtra() {
    var tutte = normalizza(campo.value).split(/\s+/).filter(Boolean);
    var piene = tutte.filter(function (p) { return VUOTE.indexOf(p) === -1; });
    var parti = (piene.length ? piene : tutte).map(radice);
    var trovate = 0, ultima = null;
    for (var i = 0; i < domande.length; i++) {
      var ok = parti.every(function (p) { return testi[i].indexOf(p) !== -1; });
      domande[i].hidden = !ok;
      if (ok) { trovate++; ultima = domande[i]; }
    }
    if (parti.length && trovate === 1) ultima.open = true;
    nessuna.hidden = trovate !== 0;
    conteggio.textContent = !parti.length ? ""
      : inglese ? (trovate === 1 ? "1 answer" : trovate + " answers")
      : (trovate === 1 ? "1 risposta" : trovate + " risposte");
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
