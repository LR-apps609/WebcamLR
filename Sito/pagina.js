// La home: confronto prima/dopo, Specchia e Sfoca sfondo, profili. Senza JavaScript la pagina resta leggibile:
// il confronto si ferma a metà, i pulsanti e i profili mostrano lo stato di partenza.
(function () {
  var riduciMovimento = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // 1. Confronto: la linea si sposta con il mouse, con il dito (trascinando in orizzontale; in verticale la pagina
  //    scorre) e con la tastiera (frecce, Pagina su/giù, Inizio/Fine: è un <input type="range">).
  var riquadro = document.getElementById("riquadro-confronto");
  var cursore = document.getElementById("cursore-confronto");
  if (riquadro && cursore) {
    var sinistra = riquadro.querySelector(".etichetta-video.sinistra");
    var destra = riquadro.querySelector(".etichetta-video.destra");
    var toccato = false;

    var mostra = function (valore) {
      riquadro.style.setProperty("--confine", valore);
      if (sinistra) sinistra.style.opacity = valore > 22 ? 1 : 0;
      if (destra) destra.style.opacity = valore < 78 ? 1 : 0;
      cursore.setAttribute("aria-valuetext",
        valore < 40 ? "Si vede soprattutto l'iPhone: nitido e luminoso"
        : valore > 60 ? "Si vede soprattutto la webcam del computer: sgranata e scura"
        : "Metà webcam del computer, metà iPhone");
    };
    var daPuntatore = function (evento) {
      var r = riquadro.getBoundingClientRect();
      var valore = Math.round(Math.min(Math.max((evento.clientX - r.left) / r.width, 0), 1) * 100);
      cursore.value = valore;
      mostra(valore);
    };

    cursore.addEventListener("input", function () { toccato = true; mostra(Number(cursore.value)); });
    var trascina = false;
    cursore.addEventListener("pointerdown", function (evento) {
      toccato = true;
      trascina = true;
      if (cursore.setPointerCapture) { try { cursore.setPointerCapture(evento.pointerId); } catch (e) {} }
      daPuntatore(evento);
      cursore.focus({ preventScroll: true });
      evento.preventDefault();
    });
    cursore.addEventListener("pointermove", function (evento) { if (trascina) daPuntatore(evento); });
    var fine = function () { trascina = false; };
    cursore.addEventListener("pointerup", fine);
    cursore.addEventListener("pointercancel", fine);
    mostra(Number(cursore.value));

    // Una volta sola, quando il riquadro compare: la linea si muove da sola per far vedere che si può.
    if (!riduciMovimento && "IntersectionObserver" in window) {
      var anima = function () {
        var passi = [[50, 72, 800], [72, 30, 1000], [30, 50, 700]];
        var indice = 0, inizio = null;
        var passo = function (ora) {
          if (toccato || indice >= passi.length) return;
          if (inizio === null) inizio = ora;
          var p = passi[indice], t = Math.min((ora - inizio) / p[2], 1);
          var dolce = t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          var valore = Math.round(p[0] + (p[1] - p[0]) * dolce);
          cursore.value = valore;
          mostra(valore);
          if (t >= 1) { indice++; inizio = null; }
          requestAnimationFrame(passo);
        };
        setTimeout(function () { requestAnimationFrame(passo); }, 600);
      };
      var osservatore = new IntersectionObserver(function (voci) {
        if (voci[0].isIntersecting) { osservatore.disconnect(); anima(); }
      }, { threshold: 0.6 });
      osservatore.observe(riquadro);
    }
  }

  // 2. Specchia e Sfoca sfondo: un pulsante, due disegni che cambiano insieme, come tra iPhone e Mac.
  var sincronia = document.getElementById("sincronia");
  var esito = document.getElementById("esito-tocco");
  var pulsanti = document.querySelectorAll("[data-interruttore]");
  var nomi = { specchiato: "Specchia", sfocato: "Sfoca sfondo" };
  for (var i = 0; i < pulsanti.length; i++) {
    pulsanti[i].addEventListener("click", function () {
      var classe = this.getAttribute("data-interruttore");
      var acceso = this.getAttribute("aria-pressed") !== "true";
      this.setAttribute("aria-pressed", acceso ? "true" : "false");
      if (sincronia) sincronia.classList.toggle(classe, acceso);
      if (esito) esito.textContent = "«" + nomi[classe] + "» " + (acceso ? "acceso" : "spento") + " sull'iPhone e sul computer.";
    });
  }

  // 3. Profili: la scelta cambia l'anteprima disegnata e la riga di descrizione (testi di Mac/Sorgenti/Profili.swift).
  var anteprima = document.getElementById("anteprima-profilo");
  var descrizione = document.getElementById("descrizione-profilo");
  var profili = {
    riunione: ["Riunione", "Volto illuminato e al centro: luce sul volto e inquadratura automatica."],
    lezione: ["Lezione", "Tu e la scrivania, con il grandangolo 0,5× posteriore; l'inquadratura resta ferma per non tagliare il foglio."],
    diretta: ["Diretta", "Movimento fluido a 60 fps, luce e colori naturali, inquadratura ferma."],
    colloquio: ["Colloquio", "Sfondo sfocato leggero, pelle appena curata, volto illuminato e al centro."]
  };
  var scelte = document.querySelectorAll('input[name="profilo"]');
  for (var j = 0; j < scelte.length; j++) {
    scelte[j].addEventListener("change", function () {
      var voce = profili[this.value];
      if (!voce) return;
      if (anteprima) anteprima.setAttribute("data-profilo", this.value);
      if (descrizione) {
        descrizione.textContent = "";
        var nome = document.createElement("b");
        nome.textContent = voce[0];
        descrizione.appendChild(nome);
        descrizione.appendChild(document.createTextNode(" " + voce[1]));
      }
    });
  }
})();
