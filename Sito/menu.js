// Il menu sul telefono, su tutte le pagine. Sotto i 700 px le voci stanno dietro il pulsante «Menu»
// (aria-expanded dice se è aperto); Esc lo chiude e rimette il fuoco sul pulsante, come un clic fuori o su una voce.
// Senza JavaScript il pulsante non c'è e le voci restano tutte a vista, a capo (stile.css, senza la classe «con-menu»).
// Gli eventi sono sul documento: così funziona anche nella 404 inglese, che sostituisce il <body> dopo il caricamento.
(function () {
  var radice = document.documentElement;
  radice.classList.add("con-menu");

  function pulsante() { return document.querySelector(".menu-pulsante"); }
  function testata() { return document.querySelector(".testata"); }
  function aperto() { var p = pulsante(); return !!p && p.getAttribute("aria-expanded") === "true"; }

  function imposta(apri, rimettiFuoco) {
    var p = pulsante(), t = testata();
    if (!p || !t) return;
    p.setAttribute("aria-expanded", apri ? "true" : "false");
    t.classList.toggle("menu-aperto", apri);
    if (!apri && rimettiFuoco) p.focus();
  }

  document.addEventListener("click", function (evento) {
    var p = pulsante();
    if (!p) return;
    if (p.contains(evento.target)) { imposta(!aperto(), false); return; }
    if (!aperto()) return;
    var menu = document.getElementById("menu-principale");
    // Una voce del menu (anche un'ancora nella stessa pagina) o un clic fuori: si chiude.
    if (menu && menu.contains(evento.target) && !evento.target.closest("a")) return;
    imposta(false, false);
  });

  document.addEventListener("keydown", function (evento) {
    if ((evento.key === "Escape" || evento.key === "Esc") && aperto()) {
      evento.preventDefault();
      imposta(false, true);
    }
  });

  // Tornando sopra i 700 px (telefono girato, finestra allargata) il menu non resta aperto di nascosto.
  if (window.matchMedia) {
    var largo = window.matchMedia("(min-width: 701px)");
    var cambia = function () { if (largo.matches) imposta(false, false); };
    if (largo.addEventListener) largo.addEventListener("change", cambia); else if (largo.addListener) largo.addListener(cambia);
  }
})();
