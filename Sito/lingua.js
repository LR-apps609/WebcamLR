// Italiano e inglese. Su ogni pagina:
// 1. il selettore IT / EN in alto porta alla stessa pagina nell'altra lingua, allo stesso punto (#…);
// 2. se il browser non è in italiano (o, sulle pagine inglesi, se è in italiano) compare una striscia piccola
//    «Read this page in English» / «Leggi questa pagina in italiano», che si chiude con ×. Mai un reindirizzamento.
// La scelta (chiusa o lingua cambiata) resta nel browser di chi visita; senza memoria la striscia torna, e basta.
(function () {
  var CHIAVE = "webcamlr-lingua";
  var lingua = (document.documentElement.lang || "it").slice(0, 2);
  var altra = document.querySelector('.lingue a[hreflang]');
  if (!altra) return;

  function ricorda() {
    try { localStorage.setItem(CHIAVE, "scelta"); } catch (e) {}
  }
  function giaScelto() {
    try { return localStorage.getItem(CHIAVE) === "scelta"; } catch (e) { return false; }
  }
  function conPunto(indirizzo) {
    return indirizzo.split("#")[0] + (location.hash || "");
  }

  altra.addEventListener("click", function () {
    altra.href = conPunto(altra.href);
    ricorda();
  });

  if (giaScelto()) return;
  var preferite = (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ""]);
  var prima = String(preferite[0] || "").toLowerCase();
  var italiano = prima.slice(0, 2) === "it";
  var suggerisci = lingua === "it" ? (prima !== "" && !italiano) : italiano;
  if (!suggerisci) return;

  var verso = lingua === "it" ? "en" : "it";
  var testi = verso === "en"
    ? { invito: "Read this page in English", chiudi: "Close", regione: "Language" }
    : { invito: "Leggi questa pagina in italiano", chiudi: "Chiudi", regione: "Lingua" };

  var striscia = document.createElement("div");
  striscia.className = "suggerimento-lingua";
  striscia.setAttribute("role", "region");
  striscia.setAttribute("aria-label", testi.regione);
  striscia.lang = verso;
  var dentro = document.createElement("div");
  dentro.className = "contenitore";
  var link = document.createElement("a");
  link.href = conPunto(altra.getAttribute("href"));
  link.hreflang = verso;
  link.textContent = testi.invito;
  link.addEventListener("click", function () { link.href = conPunto(altra.getAttribute("href")); ricorda(); });
  var chiudi = document.createElement("button");
  chiudi.type = "button";
  chiudi.className = "chiudi";
  chiudi.setAttribute("aria-label", testi.chiudi);
  chiudi.textContent = "×";
  chiudi.addEventListener("click", function () {
    striscia.remove();
    ricorda();
  });
  dentro.appendChild(link);
  dentro.appendChild(chiudi);
  striscia.appendChild(dentro);

  var testata = document.querySelector(".testata");
  if (testata && testata.parentNode) testata.parentNode.insertBefore(striscia, testata.nextSibling);
  else document.body.insertBefore(striscia, document.body.firstChild);
})();
