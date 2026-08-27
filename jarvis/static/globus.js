/* Der Globus - einmal gebaut, an zwei Stellen benutzt.
 *
 * `weltlage.html` ist die eigene Seite dafuer; `index.html` haengt
 * dieselbe Datei als fuenften Tab ein. Zwei Kopien waeren zwei Orte fuer
 * jeden Fehler, und beim zweiten vergisst es irgendwann jemand.
 *
 * **Warum das Markup hier drin steht und nicht in der Seite.** Sonst
 * braeuchte jede der beiden Seiten dieselben vierzig Zeilen HTML - dasselbe
 * Duplikat, nur eine Ebene tiefer. So gibt es einen Ort: diese Datei.
 *
 * **Warum der Token ein Parameter ist.** `/static` wird von einem
 * StaticFiles-Mount roh ausgeliefert (`api/app.py:205`); den Platzhalter
 * `__JARVIS_TOKEN__` ersetzt nur die HTML-Route (`api/routes.py:515` und
 * `:533`). Stuende der Token hier in der Datei, ginge jeder API-Aufruf mit
 * dem Platzhalter raus und bekaeme 401. Die Seite reicht ihn herein.
 *
 * Drei Ausfuhren, mehr braucht der Einbau nicht:
 *
 *   starte(behaelter, token)   Markup und Stil einsetzen, Globus aufbauen.
 *                              Loest auf, wenn die Laendergrenzen da sind.
 *   pausiere()                 Zeichenschleife aus. Beim Tabwechsel.
 *   weiter()                   Schleife an, Groesse neu messen.
 *
 * Warum `pausiere()` und nicht der IntersectionObserver: `index.html`
 * blendet Ansichten mit `display:none` um (`index.html:446`). Ob ein
 * Observer dabei feuert, haengt am Browser - abschalten laesst sich nicht
 * daran aufhaengen. Der Observer bleibt trotzdem drin, fuer die eigene
 * Seite und fuers Scrollen.
 */

import * as THREE from 'three';

const STIL = `
/* Alles unter .globus-wurzel. Zwei Gruende, beide gemessen:

   1. Klassennamen. 'karte' und 'status' gibt es in index.html schon
      ('index.html:450' und ':129'). Ohne Schachtelung faerbt der Globus die
      Auftragskarten des Chats um - und umgekehrt. Nachgezaehlt wurden alle
      31 Globus-Klassen gegen die 99 aus index.html; genau diese zwei
      ueberschneiden sich. Die drei Eigenschaften, die index.html an ihnen
      setzt und der Globus bisher nicht, stehen unten ausdruecklich drin.
   2. Position. In weltlage.html hing alles per 'position:fixed' am
      Fenster. Als Tab in einer Ansicht ist das falsch: der Globus laege
      ueber dem Chat. Alles ist jetzt 'absolute' im Behaelter, und der
      Behaelter bekommt 'position:relative'. */

.globus-wurzel{
  /* Hier standen bis FIX-06 neun eigene Variablen - darunter ein zweites,
     blaues --akzent. Sie sind weg, und das ist der ganze Punkt: eine
     Deklaration AUF diesem Element haette den von :root geerbten Wert aus
     static/system.css verdraengt, ganz ohne Spezifitaetsstreit. Die App
     waere bernsteinfarben geworden und der Globus blau geblieben.

     --flaeche und --land waren ausserdem schon vorher tot: null Nutzungen
     im ganzen Block. */

  /* Der Behaelter ist das Bezugssystem fuer alles darin. */
  position:relative;
  overflow:hidden;
  background:var(--grund); color:var(--text);
  font:15px/1.55 var(--schriftfamilie);
}
/* Der Stern war frueher global. Hier gilt er nur im Behaelter - sonst
   raeumt der Globus die Abstaende der ganzen App ab. */
.globus-wurzel *{box-sizing:border-box;margin:0;padding:0}

.globus-wurzel #globus{position:absolute;inset:0;display:block;width:100%;height:100%;
        /* Ohne das scrollt Android die Seite, statt zu drehen. */
        touch-action:none;cursor:grab}
.globus-wurzel #globus:active{cursor:grabbing}
.globus-wurzel #globus:focus-visible{outline:2px solid var(--akzent);outline-offset:-2px}
.globus-wurzel .ersatz{position:absolute;inset:0;display:grid;place-items:center;padding:2rem;text-align:center;color:var(--text-leise)}

/* --- Kopf --- */
.globus-wurzel .kopf{
  position:absolute;top:0;left:0;right:0;z-index:3;
  display:flex;align-items:center;gap:.75rem;flex-wrap:wrap;
  padding:.7rem 1rem;
  background:linear-gradient(180deg,rgba(10,10,12,.9),rgba(10,10,12,0));
}
.globus-wurzel .marke{font-weight:600;letter-spacing:.02em}
.globus-wurzel .marke span{color:var(--akzent)}
.globus-wurzel .land{color:var(--text-leise);font-variant-numeric:tabular-nums}
.globus-wurzel .kopf .luecke{flex:1}
.globus-wurzel .knopf{
  appearance:none;border:1px solid var(--kante);border-radius:.55rem;
  background:var(--ebene-1);color:var(--text);
  padding:.42rem .7rem;font:inherit;font-size:.86rem;cursor:pointer;
  transition:border-color .2s var(--kurve-rein),background .2s var(--kurve-rein);
}
.globus-wurzel .knopf:hover{border-color:var(--akzent)}
.globus-wurzel .knopf:focus-visible{outline:2px solid var(--akzent);outline-offset:2px}
.globus-wurzel .knopf[aria-pressed="true"]{border-color:var(--akzent);color:var(--akzent)}

/* --- Landtafel (FIX-06 Abschnitt 7.2) ---
   Links ueber dem Canvas. Das ist die eine Stelle, an der Glas etwas zu tun
   hat: dahinter liegt der Globus und damit echte Struktur.
   Beim Wechsel geht die alte Zeile in 220 ms raus, die neue in 380 ms rein,
   mit 8 px Versatz von unten. Nur transform und opacity - alles andere
   loest ein Layout aus und ruckelt neben einer WebGL-Schleife. */
.globus-wurzel .landtafel{
  position:absolute;left:1rem;top:4.2rem;z-index:3;
  max-width:min(24rem,42vw);
  padding:.85rem 1.1rem;border-radius:.9rem;
  pointer-events:none;
}
.globus-wurzel .landtafel-buehne{position:relative;overflow:hidden}
.globus-wurzel .landtafel-satz{
  transform:translateY(0);opacity:1;
  transition:transform var(--dauer-rein,380ms) var(--kurve-rein),
             opacity var(--dauer-rein,380ms) var(--kurve-rein);
}
.globus-wurzel .landtafel-satz.geht{
  transform:translateY(-8px);opacity:0;
  transition-duration:220ms;
}
.globus-wurzel .landtafel-satz.kommt{transform:translateY(8px);opacity:0}
.globus-wurzel .landtafel-name{
  font-size:var(--kenngroesse);line-height:1.02;
  text-transform:uppercase;letter-spacing:.02em;
  color:var(--text-laut);font-weight:500;
  overflow-wrap:anywhere;
}
.globus-wurzel .landtafel-wo{
  margin-top:.25rem;font-size:var(--etikett);letter-spacing:.06em;
  color:var(--text-leise);font-variant-numeric:tabular-nums;
}
.globus-wurzel .landtafel-tut{
  margin-top:.5rem;font-size:.86rem;color:var(--akzent);
}
/* DoD 5: die Grenze steht in der ANSICHT, nicht nur im Code. */
.globus-wurzel .landtafel-sat{
  margin-top:.45rem;padding-top:.45rem;border-top:1px solid var(--kante);
  font-size:.78rem;line-height:1.45;color:var(--text-leise);
}
@media (max-width:640px){
  .globus-wurzel .landtafel{left:.6rem;right:.6rem;max-width:none;top:6.5rem}
}

/* --- Karten --- */
.globus-wurzel .karten{
  position:absolute;z-index:2;right:1rem;top:3.6rem;bottom:3.2rem;width:min(38ch,42%);
  display:flex;flex-direction:column;gap:.6rem;
  /* Karten sind so hoch wie ihr Inhalt und wachsen nicht ins Leere. Bei
     fuenf Karten schrumpfen sie, bis alle passen. Was dann immer noch nicht
     passt, wird nicht angezeigt - statt zu scrollen. */
  justify-content:flex-start;
  overflow:hidden;
}
.globus-wurzel .karte{flex:0 1 auto}
.globus-wurzel .karte{
  border:1px solid var(--kante);border-radius:.8rem;overflow:hidden;
  background:var(--ebene-1);
  -webkit-backdrop-filter:blur(18px) saturate(140%);
  backdrop-filter:blur(18px) saturate(140%);
  display:flex;flex-direction:column;min-height:0;
  animation:globus-auf .28s var(--kurve-rein) both;
  /* Gegen index.html:454-455. Dort hat '.karte' Innen- und Aussenabstand;
     hier machen das '.block' und der 'gap' der Spalte. Ohne diese zwei
     Zeilen sitzt im eingebauten Tab ploetzlich Luft um jede Karte. */
  padding:0;margin-bottom:0;
}
@keyframes globus-auf{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}

.globus-wurzel .bild{position:relative;flex:0 0 auto;height:4.4rem;background:var(--grund)}
.globus-wurzel .bild img{width:100%;height:100%;object-fit:cover;display:block}
/* Ueber dem Bild derselbe Herkunftsstempel - damit es nie ohne Zuordnung
   im Raum steht, auch nicht auf einem Screenshot. */
.globus-wurzel .bild .stempel{
  position:absolute;left:0;right:0;bottom:0;
  padding:1.4rem .55rem .35rem;
  background:linear-gradient(180deg,transparent,rgba(10,10,12,.92));
  font-size:.7rem;color:var(--text);letter-spacing:.02em;
}
/* Kein og:image -> Kartenkachel, sichtbar ANDERS als ein Foto. */
.globus-wurzel .kachel{
  height:4.4rem;display:grid;place-items:center;gap:.2rem;
  background:repeating-linear-gradient(45deg,var(--ebene-1) 0 8px,var(--ebene-2) 8px 16px);
  color:var(--text-leise);font-size:.72rem;text-align:center;
}
.globus-wurzel .kachel b{font-size:.78rem;color:var(--text);font-weight:600}

.globus-wurzel .block{padding:.5rem .7rem;min-height:0;overflow:hidden}
.globus-wurzel .meldung .schlag{font-weight:600;font-size:.95rem;margin-bottom:.15rem}
.globus-wurzel .meldung .kurz{color:var(--text);font-size:.86rem;
  display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.globus-wurzel .quelle{margin-top:.35rem;font-size:.7rem;color:var(--text-leise);letter-spacing:.03em;text-transform:uppercase}

/* Abschnitt 4b: andere Flaeche, andere Kante. Man muss sehen, wo die Belege
   aufhoeren und die Erklaerung anfaengt. */
.globus-wurzel .einordnung{
  border-top:1px dashed rgba(255,255,255,.16);
  /* War rgba(77,163,255,.055) - das blaue Pendant zur Akzentglut. */
  background:var(--akzent-glut);
}
.globus-wurzel .einordnung .marke2{
  font-size:.66rem;letter-spacing:.09em;text-transform:uppercase;
  color:var(--akzent);margin-bottom:.2rem;
}
.globus-wurzel .einordnung p{font-size:.84rem;color:var(--text);
  display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.globus-wurzel .einordnung .hinweis{margin-top:.25rem;font-size:.68rem;color:var(--text-leise);font-style:italic}

/* --- Statusleiste --- */
.globus-wurzel .status{
  position:absolute;left:0;right:0;bottom:0;z-index:3;
  display:flex;align-items:center;gap:1rem;flex-wrap:wrap;
  padding:.5rem 1rem;font-size:.76rem;color:var(--text-leise);
  background:linear-gradient(0deg,rgba(10,10,12,.92),rgba(10,10,12,0));
  /* Gegen index.html:130. Dort schiebt '.status' sich mit margin-left:auto
     in der Kopfleiste nach rechts; hier ist es eine volle Leiste. */
  margin-left:0;
}
.globus-wurzel .status b{color:var(--text);font-weight:600;font-variant-numeric:tabular-nums}
.globus-wurzel .gesagt{color:var(--text)}

.globus-wurzel .leer{
  place-self:start;padding:.7rem .8rem;border:1px dashed var(--kante);
  border-radius:.7rem;color:var(--text-leise);font-size:.85rem;background:var(--ebene-1);
}

@media (prefers-reduced-motion: reduce){
  .globus-wurzel,.globus-wurzel *,.globus-wurzel *::before,.globus-wurzel *::after{
    animation-duration:.001ms !important;transition-duration:.001ms !important}
}
.globus-wurzel .ortsuche{display:flex;gap:.4rem;align-items:center;min-width:0}
.globus-wurzel .ortsuche input{
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.14);
  color:var(--text-laut);border-radius:8px;padding:.38rem .6rem;font:inherit;
  /* Frueher 'width:min(30ch,34vw)'. vw misst das FENSTER, nicht den
     Behaelter - im eingebauten Tab lief die Kopfzeile damit ueber den Rand
     hinaus. Jetzt schrumpft das Feld mit dem Platz, den es wirklich hat. */
  flex:1 1 14ch;min-width:8ch;max-width:30ch;
}
.globus-wurzel .ortsuche input:focus{border-color:var(--akzent)}
/* Hier stand 'outline:none'. Eine gefaerbte Rahmenlinie ist KEIN Fokusring -
   sie ist ein Pixel breit, sitzt am selben Platz wie der Ruherahmen und
   verschwindet auf einem hellen Bild dahinter. 'web-selfcheck' hat das
   durchgewunken, weil es jeden Rahmen als Ring zaehlt; gefunden hat es erst
   ein Test, der die Umrandung selbst misst. Die Regel aus system.css kaeme
   gegen die Basisregel nicht an - deshalb hier ausdruecklich. */
.globus-wurzel .ortsuche input:focus-visible{
  outline:2px solid var(--akzent);outline-offset:2px}
.globus-wurzel .ortpanel{
  position:absolute;left:1.4rem;bottom:3.2rem;width:min(42ch,42%);z-index:5;
  background:rgba(14,18,26,.82);backdrop-filter:blur(14px);
  border:1px solid rgba(255,255,255,.1);border-radius:14px;padding:1rem 1.1rem;
}
.globus-wurzel .ortpanel h2{margin:0 0 .1rem;font-size:1.05rem;font-weight:600}
.globus-wurzel .ortkoord{margin:0 0 .7rem;font-size:.78rem;color:var(--text-leise)}
.globus-wurzel .ortbild{margin:0 0 .7rem;border-radius:10px;overflow:hidden;
         border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.3)}
.globus-wurzel .ortbild img{display:block;width:100%;height:auto}
.globus-wurzel .ortbild figcaption{padding:.35rem .6rem;font-size:.72rem;color:var(--text-leise)}
.globus-wurzel .orttext{margin:0;font-size:.88rem;line-height:1.5;color:var(--text)}
.globus-wurzel .orthinweis{margin:.6rem 0 0;font-size:.78rem;color:var(--akzent-satt)}
.globus-wurzel .orthinweis:empty{display:none}
.globus-wurzel .ortzu{position:absolute;top:.5rem;right:.6rem;background:none;border:0;
       color:var(--text-leise);font-size:1.2rem;line-height:1;cursor:pointer}
.globus-wurzel .ortzu:hover{color:var(--text-laut)}
@media (max-width:720px){ .globus-wurzel .ortpanel{left:1rem;width:auto;right:1rem} }
@media (min-width:1500px){
  .globus-wurzel .karten{width:min(64ch,50%);display:grid;grid-template-columns:1fr 1fr;
          grid-auto-rows:min-content;align-content:start}
}
@media (max-width:720px){
  .globus-wurzel .karten{left:1rem;width:auto}
}
`;

const MARKUP = `
<canvas id="globus" tabindex="0"
        aria-label="Globus. Ziehen dreht, Pfeiltasten drehen, Plus und Minus zoomen. Länder sind anwählbar."></canvas>

<header class="kopf">
  <div class="marke">JARVIS <span>· Weltlage</span></div>
  <div class="land" id="land">weltweit</div>
  <div class="luecke"></div>
  <form class="ortsuche" id="ortsuche">
    <input id="ort-eingabe" type="search" autocomplete="off"
           placeholder="Ort eingeben, z. B. Schwäbisch Gmünd"
           aria-label="Ort suchen">
    <button class="knopf" type="submit" id="btn-ort">Hinfliegen</button>
  </form>
  <button class="knopf" id="btn-welt" type="button">Weltweit</button>
  <button class="knopf" id="btn-globus-mic" type="button" aria-pressed="false"
          title="Leertaste halten und sprechen">🎤 Halten</button>
</header>

<section class="landtafel glas" id="landtafel" aria-live="polite">
  <div class="landtafel-buehne" id="landtafel-buehne">
    <div class="landtafel-satz" id="landtafel-satz">
      <div class="landtafel-name" id="landtafel-name">Weltweit</div>
      <div class="landtafel-wo" id="landtafel-wo">alle Länder</div>
    </div>
  </div>
  <div class="landtafel-tut" id="landtafel-tut">Bereit.</div>
  <div class="landtafel-sat" id="sat-hinweis">Satellitenbahnen werden geladen …</div>
</section>

<section class="ortpanel" id="ortpanel" hidden aria-live="polite">
  <button class="ortzu" id="ort-zu" type="button" aria-label="Schließen">×</button>
  <h2 id="ort-name">—</h2>
  <p class="ortkoord" id="ort-koord"></p>
  <figure class="ortbild" id="ort-bild-box" hidden>
    <img id="ort-bild" alt="Satellitenaufnahme des gesuchten Ortes">
    <figcaption id="ort-bildunterschrift"></figcaption>
  </figure>
  <p class="orttext" id="ort-text"></p>
  <p class="orthinweis" id="ort-hinweis"></p>
</section>

<main class="karten" id="karten" aria-live="polite"></main>

<footer class="status">
  <span class="gesagt" id="gesagt">Bereit.</span>
  <span>Abfragen <b id="z-abfragen">0</b></span>
  <span>aus dem Cache <b id="z-treffer">0</b></span>
  <span>Cache-Quote <b id="z-quote">0 %</b></span>
  <span id="z-verworfen-box">verworfen <b id="z-verworfen">0</b></span>
  <span>Modellaufrufe heute <b id="z-aufrufe">0</b></span>
</footer>
`;

/* Modulweiter Zustand. Alles, was `pausiere()` und `weiter()` anfassen
   muessen, steckt sonst in der Closure von `starte()`. */
let renderer = null;
let schleifeFn = null;
let resizeFn = null;
let sichtbarSetzen = null;
let neuZeichnen = null;
let hoerenAbstellen = null;
let kartenNachholen = null;
let geometrieFertig = Promise.resolve();
let gestartet = false;
let aktiv = false;
/* FIX-06 Zone 2: dasselbe Canvas, an einer anderen Stelle im Dokument.
   Ein zweiter Renderer waere ein zweiter WebGL-Kontext, und Browser
   verwerfen den aelteren ohne Vorwarnung, sobald die Zahl reisst. Beide
   Ansichten sind Tabs - sie sind nie gleichzeitig sichtbar, also reicht
   ein Canvas fuer beide. */
let leinwand = null;
let leinwandHeimat = null;
let leinwandAnker = null;

function stilEinsetzen(){
  // Ein Stilblock je Dokument, auch wenn zwei Behaelter starten wuerden.
  if (document.getElementById('globus-stil')) return;
  const s = document.createElement('style');
  s.id = 'globus-stil';
  s.textContent = STIL;
  document.head.appendChild(s);
}

/** Globus in `behaelter` aufbauen. Loest auf, wenn die Grenzen geladen sind. */
export async function starte(behaelter, token){
  if (gestartet){ weiter(); return geometrieFertig; }
  gestartet = true;
  aktiv = true;
  behaelter.classList.add('globus-wurzel');
  stilEinsetzen();
  behaelter.insertAdjacentHTML('beforeend', MARKUP);

  const TOKEN = token;

  /* Three.js liest kein CSS. Damit die Palette trotzdem an EINER Stelle
     steht, werden die Farben der Szene hier aus den Custom Properties
     gelesen statt als 0x-Zahl danebengeschrieben - genau so ist frueher
     ein zweiter, blauer Akzent entstanden und jahrelang stehengeblieben.

     `THREE.Color` nimmt eine CSS-Zeichenkette an: `set()` verzweigt bei
     `typeof value === 'string'` auf `setStyle()`, und `setStyle()` hat
     einen Zweig fuer sechsstellige Hex-Werte. Nachgesehen in
     static/vendor/three.core.js, Zeile 14044 und 14253 - nicht erinnert. */
  const gelesen = getComputedStyle(behaelter);
  function farbe(name){
    const wert = gelesen.getPropertyValue(name).trim();
    if (!wert){
      // Ohne static/system.css gibt es die Palette nicht. Dann lieber laut
      // in der Konsole als still in einer falschen Farbe.
      console.error('globus.js: ' + name + ' ist leer - fehlt static/system.css?');
    }
    return new THREE.Color(wert || '#888888');
  }

  // Nur im eigenen Behaelter suchen. In index.html gibt es `btn-mic`
  // schon (die Sprachtaste des Chats); document.getElementById wuerde
  // je nach Reihenfolge die falsche treffen.
  const el = id => behaelter.querySelector('#' + id);
  const reduziert = matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.body.dataset.reduziert = String(reduziert);
  const MAX_KARTEN = 5;

  function api(pfad, opt){
    const o = opt || {};
    // Mischen, nicht ersetzen: ein POST braucht zusaetzlich content-type.
    // Vorher stand hier eine Zuweisung - damit ging jeder mitgegebene Header
    // still verloren.
    o.headers = Object.assign({}, o.headers || {}, {'X-Jarvis-Token': TOKEN});
    return fetch(pfad, o).then(r => r.text().then(roh => {
      let d = null; try { d = roh ? JSON.parse(roh) : null; } catch(e){}
      if (!r.ok) throw new Error((d && d.detail) || roh || ('HTTP ' + r.status));
      return d;
    }));
  }

  /* ---------------------------------------------------------------- Karten */

  function textKnoten(tag, klasse, text){
    const n = document.createElement(tag);
    if (klasse) n.className = klasse;
    if (text != null) n.textContent = text;      // nie innerHTML: fremder Text
    return n;
  }

  function stempelText(m){
    const d = new Date(m.veroeffentlicht);
    const datum = isNaN(d) ? '' : d.toLocaleDateString('de-DE');
    const zeit  = isNaN(d) ? '' : d.toLocaleTimeString('de-DE',{hour:'2-digit',minute:'2-digit'});
    return [m.medium, datum, zeit].filter(Boolean).join(' · ');
  }

  function bildBereich(m){
    if (m.bild_url){
      const box = textKnoten('div','bild');
      const img = document.createElement('img');
      img.src = m.bild_url;
      // Die Bildbeschreibung kommt AUS DER QUELLE. Gibt es keine, bleibt alt
      // leer - JARVIS erfindet keine.
      img.alt = m.bild_beschreibung || '';
      img.loading = 'lazy';
      img.decoding = 'async';
      // referrerpolicy NICHT abschalten: manche Verlage unterbinden sonst.
      img.addEventListener('error', () => box.replaceWith(kachel(m)));
      box.appendChild(img);
      box.appendChild(textKnoten('div','stempel', stempelText(m)));
      return box;
    }
    return kachel(m);
  }

  function kachel(m){
    // Kein Quellbild. Sieht bewusst anders aus als ein Foto - der Nutzer muss
    // auf einen Blick sehen, ob er ein Foto oder einen Ersatz vor sich hat.
    const k = textKnoten('div','kachel');
    k.appendChild(textKnoten('b', null, m.land_iso || '—'));
    k.appendChild(textKnoten('span', null, 'keine Quellgrafik'));
    return k;
  }

  function karteNode(m){
    const k = textKnoten('article','karte');
    k.appendChild(bildBereich(m));

    const meldung = textKnoten('div','block meldung');
    meldung.appendChild(textKnoten('div','schlag', m.schlagzeile));
    meldung.appendChild(textKnoten('div','kurz', m.kurz));
    meldung.appendChild(textKnoten('div','quelle', stempelText(m)));
    k.appendChild(meldung);

    // Zweiter, optisch getrennter Block. Und er sagt selbst, dass er nicht aus
    // der Quelle stammt.
    const ein = textKnoten('div','block einordnung');
    ein.appendChild(textKnoten('div','marke2','Einordnung'));
    if (m.einordnung){
      ein.appendChild(textKnoten('p', null, m.einordnung));
      ein.appendChild(textKnoten('div','hinweis',
        'Von JARVIS, nicht aus der Quelle. Kein Beleg.'));
    } else {
      ein.appendChild(textKnoten('p', null,
        m.einordnung_fehlt || 'Dazu habe ich keinen Kontext.'));
      ein.appendChild(textKnoten('div','hinweis','Leer gelassen statt gefüllt.'));
    }
    k.appendChild(ein);
    return k;
  }

  function zeichneKarten(daten){
    const ziel = el('karten');
    ziel.textContent = '';
    zustand.ausgeblendet = 0;
    const liste = (daten.meldungen || []).slice(0, MAX_KARTEN);
    if (!liste.length){
      ziel.appendChild(textKnoten('div','leer','0 belegte Meldungen.'));
      zustand.ausgeblendet = 0;
      document.body.dataset.karten = '0';
      return;
    }
    liste.forEach(m => ziel.appendChild(karteNode(m)));

    requestAnimationFrame(schneideKarten);
  }

  /* "Was nicht reinpasst, wird nicht angezeigt" heisst: ganze Karten
     weglassen. Eine Karte, die mitten im Satz abgeschnitten ist, ist
     schlechter als eine Karte weniger.

     Eigene Funktion, weil `weiter()` sie nachholen muss. Als eingebauter
     Tab steht `#view-welt` auf `display:none`, sobald der Nutzer woanders
     ist - dann liefert `getBoundingClientRect()` lauter Nullen, die
     Abbruchbedingung ist sofort wahr und es wird nichts weggenommen.
     Kommt die Antwort im Hintergrund an, staenden beim Zurueckkommen fuenf
     Karten uebereinander statt zwei. Gemessen, nicht vermutet. */
  function schneideKarten(){
    const ziel = el('karten');
    if (!ziel || !ziel.children.length) return;
    const platz = ziel.getBoundingClientRect();
    // Versteckte Ansicht: nichts messbar, also nichts entscheiden.
    if (!platz.width || !platz.height) return;
    let weg = 0;
    while (ziel.children.length > 1){
      const letzte = ziel.lastElementChild.getBoundingClientRect();
      if (letzte.bottom <= platz.bottom + 1 && letzte.right <= platz.right + 1) break;
      ziel.lastElementChild.remove();
      weg++;
    }
    zustand.ausgeblendet = (zustand.ausgeblendet || 0) + weg;
    if (weg) sageStatus(el('gesagt').textContent
      + ` ${weg} weitere ${weg === 1 ? 'Meldung passt' : 'Meldungen passen'} nicht ins Bild.`);
    document.body.dataset.karten = String(ziel.querySelectorAll('.karte').length);
  }
  kartenNachholen = schneideKarten;

  /* FIX-06 Abschnitt 7.2 - die Landtafel.

     Der Statustext steht ab jetzt an zwei Stellen: klein in der Fusszeile,
     wo er seit Phase 11 steht, und gross auf der Tafel. Ein Setter, damit
     die beiden nicht auseinanderlaufen. */
  function sageStatus(text){
    el('gesagt').textContent = text;
    const tut = el('landtafel-tut');
    if (tut) tut.textContent = text;
  }

  /* Namenswechsel. Alte Zeile raus in 220 ms, neue rein in 380 ms mit 8 px
     Versatz von unten - nur `transform` und `opacity`, wie im Auftrag
     verlangt. Alles andere loest ein Layout aus, und ein Layout neben einer
     WebGL-Schleife ist genau das Ruckeln, das FIX-05 A4 abgestellt hat. */
  function setzeLandtafel(name, wo){
    const buehne = el('landtafel-buehne');
    const jetzt = el('landtafel-satz');
    if (!buehne || !jetzt) return;
    const alterName = jetzt.querySelector('.landtafel-name').textContent;
    if (alterName === name){
      jetzt.querySelector('.landtafel-wo').textContent = wo || '';
      return;
    }

    const neu = document.createElement('div');
    neu.className = 'landtafel-satz kommt';
    neu.id = 'landtafel-satz';
    const n = document.createElement('div');
    n.className = 'landtafel-name';
    n.id = 'landtafel-name';
    n.textContent = name;
    const w = document.createElement('div');
    w.className = 'landtafel-wo';
    w.id = 'landtafel-wo';
    w.textContent = wo || '';
    neu.appendChild(n);
    neu.appendChild(w);

    // Waehrend des Wechsels liegen beide uebereinander. Ohne das springt
    // die Tafel in der Hoehe, und "ohne Sprung" ist Kriterium 4.
    jetzt.style.position = 'absolute';
    jetzt.style.inset = '0';
    jetzt.removeAttribute('id');
    jetzt.classList.add('geht');
    buehne.appendChild(neu);

    // Ein Frame warten, sonst gilt `kommt` als Anfangszustand UND Endzustand
    // und es wird gar nicht animiert.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      neu.classList.remove('kommt');
    }));
    setTimeout(() => { if (jetzt.parentNode) jetzt.remove(); }, 450);
  }

  function zeigeStatus(daten){
    var text = daten.gesagt
      || (daten.cache ? `Aus dem Cache, ${daten.alter_minuten} Minuten alt.` : 'Bereit.');

    // "verworfen 3" sagt nichts. Welche drei Gruende es waren, sagt alles.
    var gruende = daten.verworfen_gruende || {};
    var namen = Object.keys(gruende);
    if (namen.length){
      text += ' Verworfen: ' + namen.map(function (g){
        return gruende[g] + '× ' + g;
      }).join(', ') + '.';
    }
    sageStatus(text);

    var box = el('z-verworfen-box');
    if (box) box.title = namen.length
      ? namen.map(function (g){ return gruende[g] + '× ' + g; }).join('\n')
      : 'nichts verworfen';
  }

  function ladeZaehler(){
    return api('/api/weltlage/zaehler').then(z => {
      el('z-abfragen').textContent  = z.abfragen;
      el('z-treffer').textContent   = z.treffer;
      el('z-quote').textContent     = Math.round(z.quote * 100) + ' %';
      el('z-verworfen').textContent = z.verworfen;
      // Schritt 4: keine Euro-Kachel mehr. Stehen hier 0 Aufrufe, waehrend
      // Karten zu sehen sind, ist das ein sichtbarer Widerspruch - und genau
      // das soll es sein.
      el('z-aufrufe').textContent   = z.modellaufrufe;
    }).catch(() => {});
  }

  /* ------------------------------------------------------------ Laden */

  let laeuft = false;

  function ladeLand(iso, name){
    if (laeuft) return Promise.resolve();
    laeuft = true;
    el('land').textContent = name || iso;
    // FIX-06 7.2: derselbe Name gross auf der Tafel, mit ISO und Koordinaten.
    const eintrag = (zustand.laender || []).find(l => l.iso === iso);
    setzeLandtafel(name || iso, iso === 'WELT'
      ? 'alle Länder'
      : (eintrag
          ? `${iso} · ${eintrag.lat.toFixed(1)}°, ${eintrag.lon.toFixed(1)}°`
          : String(iso)));
    // Abschnitt 4c: EIN Satz beim Start, dann Ruhe bis die Karten da sind.
    sageStatus('Ich schaue nach ' + (name || iso) + '.');
    el('karten').textContent = '';

    return api('/api/weltlage/' + encodeURIComponent(iso))
      .then(d => d.auftrag_noetig
        ? api('/api/weltlage/' + encodeURIComponent(iso), {method:'POST'})
        : d)
      .then(d => { zeichneKarten(d); zeigeStatus(d); return ladeZaehler(); })
      .catch(err => {
        // Scheitert die Recherche, ist der richtige Zustand leer plus Begruendung.
        // Kein Platzhalter, keine Karte - und die Begruendung ist die echte.
        zeichneKarten({ meldungen: [] });
        sageStatus(err.message);
        return ladeZaehler();
      })
      .finally(() => { laeuft = false; });
  }

  /* ------------------------------------------------------------ Globus */

  const canvas = el('globus');
  // `renderer` ist modulweit deklariert - `pausiere()` und `weiter()`
  // muessen drankommen, und die stehen ausserhalb von `starte()`.
  // Dasselbe gilt fuer das Canvas: `miniAn()` haengt es um, `miniAus()`
  // haengt es genau dorthin zurueck, wo es stand.
  leinwand = canvas;
  leinwandHeimat = canvas.parentNode;
  leinwandAnker = canvas.nextSibling;

  function ersatzAnzeigen(text){
    const d = textKnoten('div','ersatz', text);
    canvas.replaceWith(d);
  }

  try {
    renderer = new THREE.WebGLRenderer({canvas, antialias:true, alpha:true,
                                        powerPreference:'high-performance'});
  } catch (e) {
    ersatzAnzeigen('Ohne WebGL kein Globus. Die Länderliste geht trotzdem: /api/weltlage/DEU');
  }

  const zustand = {laender: [], aktiv: null};
  /* Nach aussen sichtbar, weil die Abnahme A6 sonst nichts messen kann: die
     Weltdrehung und der Kamerastand stecken in der Three.js-Szene und sind
     von aussen unsichtbar. Was unten drankommt (`drehung`, `naehe`,
     `mitteLonLat`) liest nur; `waehle` macht nichts, was ein Klick nicht
     auch macht. Kein Token, kein Datenweg. */
  window.zustand = zustand;

  if (renderer){
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;

    const szene = new THREE.Scene();
    const kamera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
    kamera.position.set(0, 0, 3.1);

    const welt = new THREE.Group();
    szene.add(welt);

    // Die Kugel selbst - dunkel, damit die Grenzen darauf lesbar sind.
    // FIX-05 A1: getroffen wird ab jetzt SIE, nicht mehr die Landesmarken.
    // Vorher lief der Strahl bei einem Fehlschuss zwischen den Marken weiter
    // und traf ein Land auf der RUECKSEITE (Klick auf den Nordatlantik
    // waehlte Indonesien). Eine Kugel stoppt ihn.
    // Gerechnet wird der Schnitt gegen `kugel` weiter unten - dieses Mesh
    // zeichnet nur. Warum nicht gegen seine Dreiecke, steht dort.
    const erde = new THREE.Mesh(
      new THREE.SphereGeometry(1, 64, 48),
      new THREE.MeshBasicMaterial({color: farbe('--ebene-1')})
    );
    welt.add(erde);

    const AKZENT = farbe('--akzent');
    const RUHE   = farbe('--text-leise');   // Graustufe, wie im Auftrag

    /* FIX-06 Abschnitt 7.1 - der Atmosphaerensaum.
       Ein zweites Kugel-Mesh, knapp groesser, von INNEN gerendert: dann
       wird sein Rand zum Saum. Radien im Ueberblick, damit der Saum
       ausserhalb von allem liegt: Erde 1.0, Grenzlinien 1.002, Landesmarken
       1.01, Saum 1.032.

       Alle vier Namen darin sind in static/vendor/three.core.js
       nachgeschlagen, nicht erinnert: ShaderMaterial, BackSide,
       AdditiveBlending und `normalMatrix` (die Uniform, die Three.js jedem
       Shader mitgibt).

       `depthWrite: false` ist Pflicht - sonst verdeckt der Saum die
       Satellitenbahnen, die weiter aussen liegen.

       Der Saum haengt an `welt`, nicht an `szene`: sonst dreht er nicht mit,
       und beim Drehen sieht man, dass er nicht rund ist. */
    const luft = new THREE.Mesh(
      new THREE.SphereGeometry(1.032, 64, 48),
      new THREE.ShaderMaterial({
        transparent: true,
        side: THREE.BackSide,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        uniforms: {farbe: {value: AKZENT.clone()}},
        vertexShader: [
          'varying vec3 vN; varying vec3 vP;',
          'void main(){',
          '  vN = normalize(normalMatrix * normal);',
          '  vec4 mv = modelViewMatrix * vec4(position, 1.0);',
          '  vP = mv.xyz;',
          '  gl_Position = projectionMatrix * mv;',
          '}'
        ].join('\n'),
        fragmentShader: [
          'uniform vec3 farbe; varying vec3 vN; varying vec3 vP;',
          'void main(){',
          '  float f = pow(1.0 - abs(dot(normalize(vN), normalize(-vP))), 4.2);',
          '  gl_FragColor = vec4(farbe, f * 0.55);',
          '}'
        ].join('\n')
      })
    );
    welt.add(luft);
    // Von aussen pruefbar (DoD 1): sonst laesst sich nicht messen, ob der
    // Saum ueberhaupt da ist und ob er mitdreht. `zustand` haengt schon am
    // window, aus demselben Grund wie `drehung` und `naehe`.
    zustand.saum = luft;

    /* FIX-05 A4. Vorher lief `renderer.render()` in JEDEM Frame, auch wenn
       sich nichts bewegte - 60 Bilder je Sekunde fuer ein Standbild. Im
       eigenen Tab ist das Verschwendung, als eingebetteter Tab ist es genau
       das Lag, das man im Chat merkt.
       Gesetzt wird das Flag von: Zeigerdrehung, laufendem Flug, Auswahl,
       Resize, dem ersten Laden der Geometrie. */
    let dreckig = true;
    // Nur zum Nachmessen von aussen (Abnahme A6 Kriterium 5 und B6
    // Kriterium 3). Zwei Zaehler, weil sie zwei verschiedene Dinge
    // messen: `__globusBilder` sind die wirklich gezeichneten Bilder,
    // `__globusSchleife` die Aufrufe der Schleife. Nur der zweite zeigt,
    // ob `setAnimationLoop` ueberhaupt noch laeuft - und genau das ist
    // die Frage von B-4.
    window.__globusBilder = 0;
    window.__globusSchleife = 0;

    function aufKugel(lon, lat, r){
      const phi = (90 - lat) * Math.PI / 180;
      const theta = (lon + 180) * Math.PI / 180;
      return new THREE.Vector3(
        -r * Math.sin(phi) * Math.cos(theta),
         r * Math.cos(phi),
         r * Math.sin(phi) * Math.sin(theta)
      );
    }

    /* Die Umkehrung von aufKugel. Genau diese Formel rueckwaerts, keine
       zweite erfunden:
         x = -r sin(phi) cos(theta)      phi   = (90 - lat) * PI/180
         y =  r cos(phi)                 theta = (lon + 180) * PI/180
         z =  r sin(phi) sin(theta)
       Also phi = acos(y/r) und theta = atan2(z, -x). */
    function vonKugel(v){
      const r = v.length() || 1;
      const phi = Math.acos(Math.max(-1, Math.min(1, v.y / r)));
      const theta = Math.atan2(v.z, -v.x);
      const lat = 90 - phi * 180 / Math.PI;
      let lon = theta * 180 / Math.PI - 180;
      // atan2 liefert -180..180, minus 180 ergibt -360..0. Zurueckfalten.
      while (lon < -180) lon += 360;
      while (lon >  180) lon -= 360;
      return [lon, lat];
    }

    /* Minimaler TopoJSON-Decoder: nur was fuer Grenzlinien noetig ist.
       Kein topojson-client als zweite Abhaengigkeit fuer 40 Zeilen. */
    function bogen(topo, i){
      const umgedreht = i < 0;
      const roh = topo.arcs[umgedreht ? ~i : i];
      const [sx, sy] = topo.transform ? topo.transform.scale : [1, 1];
      const [tx, ty] = topo.transform ? topo.transform.translate : [0, 0];
      let x = 0, y = 0;
      const punkte = roh.map(([dx, dy]) => {
        x += dx; y += dy;
        return topo.transform ? [x * sx + tx, y * sy + ty] : [dx, dy];
      });
      return umgedreht ? punkte.reverse() : punkte;
    }
    function ringe(topo, geo){
      const teile = geo.type === 'Polygon' ? [geo.arcs] : geo.arcs;
      return teile.flatMap(poly => poly.map(ring =>
        ring.flatMap((i, n) => {
          const p = bogen(topo, i);
          return n ? p.slice(1) : p;
        })));
    }
    /* Flaeche eines Rings, Shoelace. Vorzeichen egal, nur die Groesse
       zaehlt - es geht darum, das Festland vom Ueberseegebiet zu trennen. */
    function flaeche(ring){
      let s = 0;
      for (let i = 0, n = ring.length; i < n; i++){
        const [x1, y1] = ring[i];
        const [x2, y2] = ring[(i + 1) % n];
        s += x1 * y2 - x2 * y1;
      }
      return Math.abs(s) / 2;
    }

    /* FIX-05 A2. Hier stand eine arithmetische Mittelung ALLER Punkte ALLER
       Ringe in lon/lat. Zwei Fehler auf einmal, beide gemessen:

         FRA  lon= -10,71  lat= 35,40  -> Atlantik vor Portugal
         FJI  lon=  88,88  lat=-17,01  -> Indischer Ozean
         USA  lon=-121,39  lat= 45,02  -> Pazifik vor Oregon
         NOR  lon=  18,60  lat= 71,74  -> Barentssee

       Ueberseegebiete zaehlten gleich stark wie das Festland (FRA, USA, NOR),
       und ueber der Datumsgrenze mitteln sich +178 und -178 zu 0 (FJI).

       Zwei Aenderungen: nur der FLAECHENGROESSTE Ring, und gemittelt wird
       ueber 3D-Vektoren auf der Einheitskugel - dort gibt es keine
       Datumsgrenze. */
    function mittelpunkt(rr){
      if (!rr.length) return [0, 0];
      let groesster = rr[0], best = -1;
      rr.forEach(r => { const a = flaeche(r); if (a > best){ best = a; groesster = r; } });

      const summe = new THREE.Vector3();
      const hilfsvektor = new THREE.Vector3();
      groesster.forEach(([lon, lat]) => {
        hilfsvektor.copy(aufKugel(lon, lat, 1));
        summe.add(hilfsvektor);
      });
      // Ein Ring, dessen Punkte sich zu null aufheben (ein exakter Grosskreis),
      // hat keinen sinnvollen Mittelpunkt. Kommt hier nicht vor, waere aber
      // eine stille Division durch fast null.
      if (summe.lengthSq() < 1e-9) return groesster[0];
      return vonKugel(summe.normalize());
    }

    geometrieFertig = Promise.all([
      fetch('/static/vendor/countries-110m.json').then(r => r.json()),
      fetch('/static/vendor/iso3166.json').then(r => r.json()),
    ]).then(([topo, iso]) => {
      const geos = topo.objects.countries.geometries;

      /* FIX-06 Abschnitt 7.3: Grenzlinien in ZWEI Staerken statt einer
         Erdtextur. Der Auftrag nennt das die dritte Moeglichkeit und sagt
         "probier das zuerst" - sie gibt Flaechenwirkung ohne eine einzige
         zusaetzliche Flaeche und ohne eine Binaerdatei im Repo.

         Woher die Unterscheidung kommt: TopoJSON teilt sich Boegen zwischen
         Nachbarn. Ein Bogen, der in genau EINEM Land vorkommt, ist eine
         Aussenkante - Kueste. Kommt er in zweien vor, ist es eine
         Binnengrenze. Negative Indizes sind derselbe Bogen rueckwaerts
         (`~i`), also wird kanonisiert.

         Das ist keine Heuristik, sondern die Struktur des Formats. */
      const bogenZaehler = new Map();
      function bogenIndizes(g){
        const teile = g.type === 'Polygon' ? [g.arcs] : g.arcs;
        return teile.flatMap(poly => poly.flatMap(ring =>
          ring.map(i => (i < 0 ? ~i : i))));
      }
      geos.forEach(g => {
        bogenIndizes(g).forEach(i => {
          bogenZaehler.set(i, (bogenZaehler.get(i) || 0) + 1);
        });
      });

      // Zwei Geometrien, nicht 177: derselbe Grund wie vorher, nur eben
      // zweimal. Zwei Draw Calls statt einem sind der Preis fuer die
      // Tiefenwirkung.
      const kueste = [];
      const binnen = [];
      // JEDER Bogen genau einmal. Der alte Code lief ueber die Ringe und hat
      // damit jede Binnengrenze doppelt gezeichnet - einmal aus jedem der
      // beiden Nachbarlaender. Zweimal dieselbe Linie ist unsichtbar, aber
      // sie kostet.
      const gesehen = new Set();
      geos.forEach(g => {
        bogenIndizes(g).forEach(kanon => {
          if (gesehen.has(kanon)) return;
          gesehen.add(kanon);
          // Vorwaertsrichtung reicht: eine Strecke hat keine Richtung.
          const linie = bogen(topo, kanon);
          const ziel = (bogenZaehler.get(kanon) || 1) > 1 ? binnen : kueste;
          for (let n = 0; n < linie.length - 1; n++){
            ziel.push(aufKugel(linie[n][0], linie[n][1], 1.002));
            ziel.push(aufKugel(linie[n+1][0], linie[n+1][1], 1.002));
          }
        });
      });
      welt.add(new THREE.LineSegments(
        new THREE.BufferGeometry().setFromPoints(kueste),
        new THREE.LineBasicMaterial({color: farbe('--text')})));
      welt.add(new THREE.LineSegments(
        new THREE.BufferGeometry().setFromPoints(binnen),
        new THREE.LineBasicMaterial({color: farbe('--text-leise'),
                                     transparent: true, opacity: 0.45})));
      document.body.dataset.linien = kueste.length + ':' + binnen.length;

      geos.forEach(g => {
        const rr = ringe(topo, g);
        const code = g.id != null ? String(g.id).padStart(3, '0') : null;
        const eintrag = code && iso[code] ? iso[code] : null;
        const [lon, lat] = mittelpunkt(rr);
        zustand.laender.push({
          iso: eintrag ? eintrag.a3 : null,
          name: (eintrag && eintrag.name) || g.properties.name || '?',
          lon, lat, ohne_iso: !eintrag,
          // FIX-05 A1: die Ringe bleiben liegen. Sie sind ab jetzt die
          // Trefferflaeche - vorher war es ein Punkt je Land, und der lag
          // bei vier Laendern im Meer.
          ringe: rr,
          // Vorfilter. Ohne ihn prueft jeder Klick alle 177 Laender
          // Punkt-fuer-Punkt; mit ihm bleiben eine Handvoll uebrig.
          box: kasten(rr),
        });
      });

      // Ein Punkt je Land: das ist die anwählbare Fläche.
      const kugel = new THREE.SphereGeometry(0.016, 8, 6);
      const marken = new THREE.InstancedMesh(
        kugel, new THREE.MeshBasicMaterial({color:0xffffff}),
        zustand.laender.length);
      const hilfe = new THREE.Object3D();
      zustand.laender.forEach((l, i) => {
        hilfe.position.copy(aufKugel(l.lon, l.lat, 1.01));
        hilfe.updateMatrix();
        marken.setMatrixAt(i, hilfe.matrix);
        marken.setColorAt(i, RUHE);
      });
      marken.instanceMatrix.needsUpdate = true;
      welt.add(marken);
      zustand.marken = marken;
      dreckig = true;
      document.body.dataset.laender = String(zustand.laender.length);
      // Erst wenn die Erde steht, kommen die Bahnen dazu. Scheitern sie,
      // bleibt der Globus trotzdem benutzbar.
      ladeBahnen();
    }).catch(err => {
      sageStatus('Ländergrenzen nicht geladen: ' + err.message);
    });

    /* Umschliessendes Rechteck in lon/lat. `ueber_datumsgrenze` merkt sich,
       ob das Land die 180 Grad kreuzt - dann taugt der einfache Vergleich
       nicht, und es wird ohne Vorfilter geprueft. Betrifft Russland, Fidschi
       und Neuseeland. */
    function kasten(rr){
      let lo = 180, la = 90, LO = -180, LA = -90, weit = false;
      rr.forEach(r => r.forEach(([lon, lat]) => {
        if (lon < lo) lo = lon;
        if (lon > LO) LO = lon;
        if (lat < la) la = lat;
        if (lat > LA) LA = lat;
      }));
      weit = (LO - lo) > 180;
      return {lo, la, LO, LA, weit};
    }

    /* Punkt-in-Polygon, Ray-Casting nach Westen. Fuenfzehn Zeilen statt einer
       Abhaengigkeit - CLAUDE.md legt den Stack fest, und turf.js waere ein
       halbes Megabyte fuer das hier. */
    function imRing(lon, lat, ring){
      let drin = false;
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++){
        const [xi, yi] = ring[i];
        const [xj, yj] = ring[j];
        if ((yi > lat) !== (yj > lat) &&
            lon < (xj - xi) * (lat - yi) / (yj - yi) + xi){
          drin = !drin;
        }
      }
      return drin;
    }

    /* Welches Land liegt unter lon/lat? Index oder -1.

       Ein Land ist getroffen, wenn eine UNGERADE Zahl seiner Ringe den Punkt
       enthaelt. Das behandelt Loecher richtig: Suedafrika enthaelt Lesotho
       als inneren Ring, und wer nach Maseru klickt, meint nicht Suedafrika. */
    function landAn(lon, lat){
      const kandidaten = [];
      for (let i = 0; i < zustand.laender.length; i++){
        const b = zustand.laender[i].box;
        if (!b) continue;
        if (lat < b.la || lat > b.LA) continue;
        if (!b.weit && (lon < b.lo || lon > b.LO)) continue;
        kandidaten.push(i);
      }
      for (const i of kandidaten){
        let treffer = 0;
        for (const ring of zustand.laender[i].ringe) if (imRing(lon, lat, ring)) treffer++;
        if (treffer % 2 === 1) return i;
      }
      return -1;
    }

    /* Auswahl per Klick */
    const zeiger = new THREE.Raycaster();
    const maus = new THREE.Vector2();

    function waehle(index){
      const land = zustand.laender[index];
      if (!land) return;
      // FIX-05 A5: drei der 177 Geometrien haben keinen ISO-Code (N. Cyprus,
      // Somaliland, Kosovo). Frueher wurde daraus eine Pseudo-Kennung
      // gebastelt, die /api/weltlage/<iso> nie kennt - der Klick lief ins
      // Leere. Lieber gar nicht anwaehlbar und den echten Grund sagen.
      if (land.ohne_iso){
        sageStatus('Für ' + land.name + ' habe ich keinen Ländercode.');
        return;
      }
      if (zustand.marken){
        zustand.laender.forEach((_, i) =>
          zustand.marken.setColorAt(i, i === index ? AKZENT : RUHE));
        zustand.marken.instanceColor.needsUpdate = true;
        dreckig = true;
      }
      zustand.aktiv = land;
      dreheZu(land.lon, land.lat);
      ladeLand(land.iso, land.name);
    }

    /* ---------------------------------------------- Satellitenbahnen
       FIX-06 Abschnitt 7.3. Was hier gezeichnet wird, ist die BODENSPUR:
       der Punkt senkrecht unter dem Satelliten, ueber die Zeit. Sie sagt,
       wo er steht - nicht, ob er von hier zu sehen ist. Dafuer braeuchte
       es den Sonnenstand und damit `de421.bsp`, rund 16 MB. Der Satz steht
       deshalb auch in der Oberflaeche und nicht nur hier (DoD 5).

       Gerechnet wird auf dem Server (`GET /api/satelliten/spur`) aus den
       zwischengespeicherten TLE-Saetzen - kein zweiter Abrufpfad zu
       CelesTrak. */
    let bahnenGeladen = false;

    function bahnRadius(hoehe_km){
      // Erdradius 6371 km. Bei der ISS sind das rund 1.065 - deutlich
      // ausserhalb des Atmosphaerensaums (1.032), und genau deshalb liegt
      // der Saum dort und nicht weiter draussen.
      return 1.0 + hoehe_km / 6371;
    }

    function ladeBahnen(){
      if (bahnenGeladen) return Promise.resolve();
      bahnenGeladen = true;
      return api('/api/satelliten/spur?gruppe=visual&minuten=90')
        .then(d => {
          const spuren = d.spuren || [];
          if (!spuren.length) return;

          // ALLE Bahnen in EINE Geometrie - derselbe Grund wie bei den
          // Grenzlinien: 157 Meshes waeren 157 Draw Calls.
          const strecken = [];
          const koepfe = [];
          spuren.forEach(sp => {
            const r = bahnRadius(sp.hoehe_km);
            const punkte = sp.punkte;
            for (let i = 0; i < punkte.length - 1; i++){
              const a = punkte[i], b = punkte[i+1];
              // Der Sprung ueber die Datumsgrenze ist keine Strecke. Ohne
              // diese Zeile zieht sich eine Linie quer durch die Kugel.
              if (Math.abs(b[1] - a[1]) > 180) continue;
              strecken.push(aufKugel(a[1], a[0], r));
              strecken.push(aufKugel(b[1], b[0], r));
            }
            koepfe.push({p: aufKugel(punkte[0][1], punkte[0][0], r), name: sp.name});
          });

          if (strecken.length){
            const bahnen = new THREE.LineSegments(
              new THREE.BufferGeometry().setFromPoints(strecken),
              new THREE.LineBasicMaterial({color: AKZENT, transparent: true,
                                           opacity: 0.5}));
            welt.add(bahnen);
            zustand.bahnen = bahnen;
          }

          // Ein kleines helles Mesh am aktuellen Ende jeder Bahn.
          if (koepfe.length){
            const punkt = new THREE.SphereGeometry(0.008, 6, 4);
            const jetzt = new THREE.InstancedMesh(
              punkt, new THREE.MeshBasicMaterial({color: AKZENT}), koepfe.length);
            const hilfe2 = new THREE.Object3D();
            koepfe.forEach((k, i) => {
              hilfe2.position.copy(k.p);
              hilfe2.updateMatrix();
              jetzt.setMatrixAt(i, hilfe2.matrix);
            });
            jetzt.instanceMatrix.needsUpdate = true;
            welt.add(jetzt);
            zustand.satelliten = jetzt;
          }

          document.body.dataset.bahnen = String(spuren.length);
          const alt = spuren.filter(x => x.tle_zu_alt).length;
          el('sat-hinweis').textContent = spuren.length + ' Satelliten · '
            + d.grenze + (alt ? ' ' + alt + ' Bahndatensätze sind älter als sieben Tage.' : '');
          // FIX-05 A4: nur zeichnen, wenn sich etwas geaendert hat. Hier hat
          // sich etwas geaendert.
          dreckig = true;
        })
        .catch(err => {
          // Kein leeres Ergebnis, das wie "keine Satelliten" aussieht.
          el('sat-hinweis').textContent = 'Satellitenbahnen nicht geladen: '
            + err.message;
        });
    }

    /* Die Trefferkugel. Sie liegt im Weltkoordinatensystem auf dem Ursprung
       mit Radius 1 - genau dort, wo `erde` steht, denn `welt` wird nur
       gedreht, nie verschoben oder skaliert. */
    const kugel = new THREE.Sphere(new THREE.Vector3(0, 0, 0), 1);
    const treffpunkt = new THREE.Vector3();

    /* Ein Punkt im Bildfeld (-1 .. 1 in beiden Achsen, 0/0 ist die Mitte)
       -> lon/lat. Gibt null zurueck, wenn dort keine Kugel ist.

       Geschnitten wird gegen die RECHNERISCHE Kugel, nicht gegen die 6144
       Dreiecke des Meshes. Gemessen am 26.08.2026: bei welt.rotation.y =
       -3*PI/2 laeuft der Strahl durch die Bildmitte genau eine Kante der
       SphereGeometry entlang, und `intersectObject` liefert dort 0 Treffer -
       ein Zehntausendstel NDC daneben 1. Ein Klick auf einer Dreieckskante
       faellt also durch. `Ray.intersectSphere(sphere, target)` (Signatur aus
       static/vendor/three.core.js) hat diese Kanten nicht, ist billiger, und
       sie gibt den VORDEREN Schnittpunkt zurueck - der Strahl stoppt weiter
       an der Kugel und trifft nichts auf der Rueckseite. Das war der Kern
       von A1. */
    function punktAufErde(nx, ny){
      maus.set(nx, ny);
      zeiger.setFromCamera(maus, kamera);
      if (!zeiger.ray.intersectSphere(kugel, treffpunkt)) return null;
      // Der Treffer steckt im Weltkoordinatensystem, die Ringe liegen in
      // Kugelkoordinaten der ungedrehten Kugel. worldToLocal( vector ) rechnet
      // um - Signatur gegen static/vendor/three.core.js geprueft, nicht
      // geraten. updateMatrixWorld davor, sonst rechnet es mit der Drehung
      // des VORIGEN Frames.
      welt.updateMatrixWorld();
      const lokal = welt.worldToLocal(treffpunkt.clone());
      return vonKugel(lokal);
    }

    /* Zeigerposition -> Punkt auf der Erde -> lon/lat.
       Gibt null zurueck, wenn daneben geklickt wurde (leerer Raum). */
    function zeigerAufErde(ev){
      const r = canvas.getBoundingClientRect();
      return punktAufErde(((ev.clientX - r.left) / r.width) * 2 - 1,
                          -((ev.clientY - r.top) / r.height) * 2 + 1);
    }

    /* --- Drehen, Zoomen, Auswaehlen ------------------------------------
       EIN Satz Zeiger-Ereignisse fuer Maus und Finger. Kein zweiter Pfad
       fuer Touch, kein OrbitControls - das waeren 600 KB fuer 30 Zeilen. */

    const ZIEH_SCHWELLE = 5;          // Pixel. Darunter ist es ein Klick.
    const KIPP_GRENZE = 85 * Math.PI / 180;
    let zieht = false, zeigerId = null;
    let startX = 0, startY = 0, letztX = 0, letztY = 0, bewegt = 0;

    canvas.addEventListener('pointerdown', ev => {
      zieht = true;
      zeigerId = ev.pointerId;
      startX = letztX = ev.clientX;
      startY = letztY = ev.clientY;
      bewegt = 0;
      // Wer selbst dreht, will nicht weggezogen werden.
      ziel = null;
      // Damit ein Zug ausserhalb des Canvas nicht abreisst.
      try { canvas.setPointerCapture(ev.pointerId); } catch (e) { /* egal */ }
    });

    canvas.addEventListener('pointermove', ev => {
      if (!zieht || ev.pointerId !== zeigerId) return;
      const dx = ev.clientX - letztX, dy = ev.clientY - letztY;
      letztX = ev.clientX; letztY = ev.clientY;
      bewegt = Math.max(bewegt, Math.hypot(ev.clientX - startX, ev.clientY - startY));
      // 0.005 rad je Pixel: eine Bildschirmbreite ist etwa eine halbe Drehung.
      welt.rotation.y += dx * 0.005;
      welt.rotation.x += dy * 0.005;
      // Ohne Klemmung kippt die Kugel ueber den Pol und steht auf dem Kopf.
      welt.rotation.x = Math.max(-KIPP_GRENZE, Math.min(KIPP_GRENZE, welt.rotation.x));
      dreckig = true;
    });

    function zeigerFertig(ev){
      if (!zieht || ev.pointerId !== zeigerId) return;
      zieht = false;
      zeigerId = null;
      try { canvas.releasePointerCapture(ev.pointerId); } catch (e) { /* egal */ }
      // Ziehen ist KEINE Auswahl. Sonst startet jede Drehung eine Recherche.
      if (bewegt > ZIEH_SCHWELLE) return;
      const punkt = zeigerAufErde(ev);
      if (!punkt) return;                       // neben die Kugel geklickt
      const index = landAn(punkt[0], punkt[1]);
      if (index >= 0) waehle(index);            // Ozean: gar nichts
    }
    canvas.addEventListener('pointerup', zeigerFertig);
    canvas.addEventListener('pointercancel', ev => { zieht = false; zeigerId = null; });

    canvas.addEventListener('wheel', ev => {
      ev.preventDefault();
      // NAH und WEIT sind die vorhandenen Grenzen, keine neuen Zahlen.
      const z = kamera.position.z + Math.sign(ev.deltaY) * 0.15;
      kamera.position.z = Math.max(NAH, Math.min(WEIT, z));
      dreckig = true;
    }, {passive: false});

    /* Tastatur. Ohne sie waere die Ansicht nur mit Maus bedienbar. */
    canvas.addEventListener('keydown', ev => {
      const schritt = 0.12;
      let getan = true;
      switch (ev.key){
        case 'ArrowLeft':  welt.rotation.y -= schritt; break;
        case 'ArrowRight': welt.rotation.y += schritt; break;
        case 'ArrowUp':    welt.rotation.x -= schritt; break;
        case 'ArrowDown':  welt.rotation.x += schritt; break;
        case '+': case '=':
          kamera.position.z = Math.max(NAH, kamera.position.z - 0.2); break;
        case '-': case '_':
          kamera.position.z = Math.min(WEIT, kamera.position.z + 0.2); break;
        default: getan = false;
      }
      if (!getan) return;
      ev.preventDefault();
      ziel = null;
      welt.rotation.x = Math.max(-KIPP_GRENZE, Math.min(KIPP_GRENZE, welt.rotation.x));
      dreckig = true;
    });

    /* Die Drehung IST die Ladeanzeige. Hoechstens 1,8 s. */
    let ziel = null, start = null, t0 = 0;
    const DAUER_MS = 1800;

    // Kamerastand. 3.1 ist der Ueberblick, 1.45 ist so nah, wie es geht,
    // ohne in die Kugel zu fahren - der Radius ist 1, die Grenzlinien
    // liegen bei 1.002 und die Landesmarken bei 1.01.
    const WEIT = 3.1, NAH = 1.45;

    zustand.dreheZu = dreheZu;
    zustand.fliegeZu = fliegeZu;
    // Lesend, nur fuer die Abnahme A6 (Kriterien 2, 3, 6, 7).
    zustand.drehung = () => ({x: welt.rotation.x, y: welt.rotation.y});
    zustand.naehe = () => kamera.position.z;
    zustand.mitteLonLat = () => punktAufErde(0, 0);
    zustand.waehle = waehle;

    function dreheZu(lon, lat){ fliegeZu(lon, lat, WEIT); }

    /* FIX-05 A3. Hier stand eine dritte Formel neben `aufKugel` und
       `vonKugel` - und sie war um genau 180 Grad verdreht. Gemessen:
       `dreheZu(3.3, 47)` stellte lon=-176,7 in die Mitte, `dreheZu(-150, 30)`
       stellte Aegypten hin. Solange niemand gegen die Kugel raycastete, fiel
       das nicht auf; jetzt entscheidet die Bildmitte, was getroffen wird.

       Nicht geraten, sondern hergeleitet. `welt.rotation` ist ein Euler in
       der Reihenfolge XYZ; mit z = 0 ist die Weltmatrix M = Rx(x)·Ry(y)
       (nachgesehen in static/vendor/three.core.js, makeRotationFromEuler).
       Gesucht ist M · aufKugel(lon, lat) = (0, 0, 1), also der Punkt vorn
       zur Kamera. Mit
           aufKugel = (-cos(lat)·cos(th), sin(lat), cos(lat)·sin(th)),
           th = (lon + 180)·PI/180
       gibt Ry(y) die x-Komponente -cos(lat)·cos(th + y). Die wird null fuer
       th + y = PI/2, also y = PI/2 - th. Danach steht (0, sin(lat),
       cos(lat)) da, und Rx(x) dreht das genau fuer x = lat auf (0, 0, 1). */
    function fliegeZu(lon, lat, naehe){
      const zielY = Math.PI / 2 - (lon + 180) * Math.PI / 180;
      const zielX = lat * Math.PI / 180;
      const zielZ = Math.max(NAH, Math.min(WEIT, naehe == null ? WEIT : naehe));
      if (reduziert){
        welt.rotation.set(zielX, zielY, 0);      // springt direkt
        kamera.position.z = zielZ;
        document.body.dataset.drehung = 'sprung';
        document.body.dataset.naehe = zielZ.toFixed(2);
        dreckig = true;
        return;
      }
      document.body.dataset.drehung = 'animiert';
      // Von aussen pruefbar machen, wohin geflogen wird. Die Kameraposition
      // selbst steckt in der Three.js-Szene und ist es nicht.
      document.body.dataset.naehe = zielZ.toFixed(2);
      dreckig = true;
      start = {x: welt.rotation.x, y: welt.rotation.y, z: kamera.position.z};
      ziel = {x: zielX, y: zielY, z: zielZ};
      t0 = performance.now();
    }

    function resize(){
      const w = canvas.clientWidth, h = canvas.clientHeight;
      if (!w || !h) return;
      renderer.setSize(w, h, false);
      kamera.aspect = w / h;
      kamera.updateProjectionMatrix();
      dreckig = true;
    }
    new ResizeObserver(resize).observe(canvas);
    resize();

    let sichtbar = true;
    // Griffe fuer weiter(): die beiden Zustaende stecken sonst in
    // dieser Closure und sind von aussen nicht erreichbar.
    sichtbarSetzen = wert => { sichtbar = wert; };
    neuZeichnen = () => { dreckig = true; };
    document.addEventListener('visibilitychange', () => { sichtbar = !document.hidden; });
    new IntersectionObserver(([e]) => { sichtbar = e.isIntersecting; }).observe(canvas);

    const glatt = t => t < .5 ? 4*t*t*t : 1 - Math.pow(-2*t + 2, 3) / 2;

    function schleife(){
      window.__globusSchleife++;
      if (!sichtbar) return;
      if (ziel){
        const t = Math.min((performance.now() - t0) / DAUER_MS, 1);
        const e = glatt(t);
        welt.rotation.x = start.x + (ziel.x - start.x) * e;
        welt.rotation.y = start.y + (ziel.y - start.y) * e;
        kamera.position.z = start.z + (ziel.z - start.z) * e;
        if (t >= 1) ziel = null;
        dreckig = true;
      }
      // Der Kern von A4: im Ruhezustand faellt die Zeichenlast auf null.
      if (!dreckig) return;
      renderer.render(szene, kamera);
      window.__globusBilder++;
      dreckig = false;
    }
    schleifeFn = schleife;
    resizeFn = resize;
    renderer.setAnimationLoop(schleife);
    renderer.render(szene, kamera);
    window.__globusBilder++;
    window.addEventListener('pagehide', pausiere);
  }

  /* ------------------------------------------------------- Bedienung */

  /* --------------------------------------------------------- Ortssuche */

  /* Schreib einen Ort, flieg hin, sieh nach.
     Der Globus konnte bisher nur Laender, und nur die, deren Mittelpunkt als
     Marke auf der Kugel sitzt. */

  function zeigeOrtBild(pfad, unterschrift){
    const box = el('ort-bild-box');
    const bild = el('ort-bild');
    if (!pfad){ box.hidden = true; bild.removeAttribute('src'); return; }

    // Die ID herausziehen, gegen die Form pruefen, die Adresse selbst bauen -
    // `pfad` kommt aus einer Antwort, die mittelbar aus einem Modell stammt.
    const id = String(pfad).split('/').pop();
    if (!/^[0-9a-f]{32}$/.test(id)){ box.hidden = true; return; }

    // Ein <img src> schickt keinen X-Jarvis-Token. Also holen wir die Bytes
    // selbst und machen eine Blob-URL daraus - der Token bleibt im Header
    // und landet nicht in Adresszeile, Verlauf und Log.
    fetch('/api/bild/' + id, { headers: {'X-Jarvis-Token': TOKEN} })
      .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob(); })
      .then(blob => {
        const url = URL.createObjectURL(blob);
        bild.onload = () => URL.revokeObjectURL(url);
        bild.src = url;
        el('ort-bildunterschrift').textContent = unterschrift || '';
        box.hidden = false;
      })
      .catch(fehler => {
        box.hidden = true;
        el('ort-hinweis').textContent = 'Bild nicht geladen: ' + fehler.message;
      });
  }

  function ortAnzeigen(d){
    const panel = el('ortpanel');
    panel.hidden = false;
    el('ort-name').textContent = d.ort.name;
    const ew = d.ort.einwohner
      ? ' · ' + d.ort.einwohner.toLocaleString('de-DE') + ' Einwohner' : '';
    const mehr = d.ort.weitere_treffer
      ? ' · ' + d.ort.weitere_treffer + ' weitere(r) Treffer gleichen Namens' : '';
    el('ort-koord').textContent =
      d.ort.lat.toFixed(4) + ', ' + d.ort.lon.toFixed(4) + ew + mehr;
    el('ort-text').textContent = d.text || '';
    el('ort-hinweis').textContent = d.hinweis || '';

    const unterschrift = d.bild
      ? [d.bild.attribution,
         d.bild.aufloesung_m ? d.bild.aufloesung_m + ' m je Pixel' : '',
         d.szene && d.szene.aufgenommen ? 'Aufnahme ' + d.szene.aufgenommen : '',
         d.szene && d.szene.wolken_pct != null ? d.szene.wolken_pct + ' % Wolken' : '']
        .filter(Boolean).join(' · ')
      : '';
    zeigeOrtBild(d.bild && d.bild.url, unterschrift);
  }

  el('ort-zu').addEventListener('click', () => {
    el('ortpanel').hidden = true;
    if (zustand.dreheZu) zustand.dreheZu(0, 15);
  });

  el('ortsuche').addEventListener('submit', ev => {
    ev.preventDefault();
    const name = el('ort-eingabe').value.trim();
    if (!name) return;
    const knopf = el('btn-ort');
    knopf.disabled = true;
    sageStatus('Suche ' + name + ' …');
    api('/api/ort', {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({name}),
    }).then(d => {
      // Erst hinfliegen, dann anzeigen: die Drehung ist auch hier die
      // Ladeanzeige, und sie dauert 1,8 s.
      if (zustand.fliegeZu) zustand.fliegeZu(d.ort.lon, d.ort.lat, 1.45);
      ortAnzeigen(d);
      sageStatus(d.ort.name);
    }).catch(fehler => {
      el('ortpanel').hidden = true;
      sageStatus('Ort nicht gefunden: ' + fehler.message);
    }).finally(() => { knopf.disabled = false; });
  });

  el('btn-welt').addEventListener('click', () => {
    // Zurueck auf die Uebersicht: die Drehung ist auch hier die Ladeanzeige.
    el('ortpanel').hidden = true;
    if (zustand.dreheZu) zustand.dreheZu(0, 15);
    ladeLand('WELT', 'weltweit');
  });

  /* Push-to-Talk. Sprache ist eine Abkuerzung, keine Pflicht: alles hier ist
     auch mit Maus und Tastatur erreichbar. */
  const Erkennung = window.SpeechRecognition || window.webkitSpeechRecognition;
  let hoerer = null;

  function suchLand(gesagt){
    const wort = (gesagt || '').trim().toLowerCase();
    if (!wort) return null;
    if (/^(weltweit|welt|global)$/.test(wort)) return {iso:'WELT', name:'weltweit'};
    return zustand.laender.find(l => l.name.toLowerCase() === wort)
        || zustand.laender.find(l => l.name.toLowerCase().startsWith(wort))
        || null;
  }

  function starteHoeren(){
    if (!Erkennung || hoerer) return;
    hoerer = new Erkennung();
    hoerer.lang = 'de-DE';
    hoerer.continuous = false;       // kein Streaming-STT
    hoerer.interimResults = false;
    hoerer.onresult = ev => {
      const gesagt = ev.results[0][0].transcript;
      const land = suchLand(gesagt);
      // Dieselbe Regel wie beim Klick (A5): ohne ISO keine Anfrage. Seit
      // `iso` fuer diese drei Laender null ist, waere sonst /api/weltlage/null
      // rausgegangen.
      if (land && land.ohne_iso){
        sageStatus('Für ' + land.name + ' habe ich keinen Ländercode.');
      } else if (land){
        ladeLand(land.iso, land.name);
      } else {
        sageStatus(`"${gesagt}" kenne ich nicht als Land.`);
      }
    };
    hoerer.onend = () => { hoerer = null; el('btn-globus-mic').setAttribute('aria-pressed','false'); };
    hoerer.onerror = () => { hoerer = null; el('btn-globus-mic').setAttribute('aria-pressed','false'); };
    el('btn-globus-mic').setAttribute('aria-pressed','true');
    hoerer.start();
  }
  function stoppeHoeren(){ if (hoerer) hoerer.stop(); }
  hoerenAbstellen = stoppeHoeren;

  if (!Erkennung){
    el('btn-globus-mic').disabled = true;
    el('btn-globus-mic').title = 'Dieser Browser kann keine Spracherkennung.';
  }
  el('btn-globus-mic').addEventListener('mousedown', starteHoeren);
  el('btn-globus-mic').addEventListener('mouseup', stoppeHoeren);
  /* Leertaste haelt das Mikrofon. FIX-05 B: ein `addEventListener` ohne Ziel
     haengt am FENSTER - im eingebauten Tab ist das Fenster der ganze Chat.
     Ohne die zwei Schranken startet die Leertaste im Chatfeld die
     Laendersuche des Globus. `aktiv` ist nur wahr, solange die Weltansicht
     laeuft; `tippt` haelt Eingabefelder frei. */
  function tippt(ziel){
    return !!ziel && (/^(INPUT|TEXTAREA|SELECT)$/.test(ziel.tagName)
                      || ziel.isContentEditable);
  }
  function fuerUns(ziel){
    if (tippt(ziel)) return false;
    return ziel === document.body || behaelter.contains(ziel);
  }
  window.addEventListener('keydown', ev => {
    if (!aktiv || ev.repeat || ev.code !== 'Space' || !fuerUns(ev.target)) return;
    ev.preventDefault(); starteHoeren();
  });
  window.addEventListener('keyup', ev => {
    if (!aktiv || ev.code !== 'Space' || !fuerUns(ev.target)) return;
    ev.preventDefault(); stoppeHoeren();
  });

  ladeZaehler();

  // Erst zurueckkommen, wenn wirklich etwas zu sehen ist. Ohne das
  // meldet der Tab "fertig", waehrend die Kugel noch leer ist.
  return geometrieFertig;
}

/** Zeichenschleife aus. Nach dem Tabwechsel faellt die Last auf null. */
export function pausiere(){
  aktiv = false;
  if (hoerenAbstellen) hoerenAbstellen();   // ein laufendes Mikrofon auch
  if (renderer) renderer.setAnimationLoop(null);
}

/** Zeichenschleife an, Groesse neu messen. */
export function weiter(){
  if (!gestartet) return;
  aktiv = true;
  if (kartenNachholen) requestAnimationFrame(kartenNachholen);
  if (!renderer) return;
  if (sichtbarSetzen) sichtbarSetzen(true);
  // B-5: in einer Ansicht mit `display:none` sind clientWidth und
  // clientHeight 0, und `resize()` steigt frueh aus. Beim ersten
  // Sichtbarwerden muss es deshalb noch einmal laufen - sonst ist das
  // Canvas 0x0 oder verzerrt.
  if (resizeFn) resizeFn();
  if (neuZeichnen) neuZeichnen();
  if (schleifeFn) renderer.setAnimationLoop(schleifeFn);
}

/** Nur fuer die Abnahme: laeuft die Ansicht gerade? */
export function laeuftGerade(){ return aktiv; }

/** Das Canvas nach `behaelter` umhaengen und weiterzeichnen (FIX-06 Zone 2).
 *
 *  Gibt `false` zurueck, wenn es noch kein Canvas gibt - dann ist Three.js
 *  schlicht noch nicht geladen, und der Aufrufer zeigt seinen eigenen
 *  Hinweis. Kein zweiter Renderer, kein zweiter Kontext: es ist dasselbe
 *  Canvas, das die Weltansicht benutzt.
 */
export function miniAn(behaelter){
  if (!leinwand || !behaelter) return false;
  if (leinwand.parentNode !== behaelter) behaelter.appendChild(leinwand);
  // `resize()` haengt an einem ResizeObserver auf dem Canvas selbst - der
  // feuert nach dem Umhaengen von allein. `weiter()` misst zusaetzlich
  // sofort nach, damit nicht ein Bild lang die alte Groesse steht.
  weiter();
  return true;
}

/** Das Canvas zurueck in die Weltansicht, an dieselbe Stelle. */
export function miniAus(){
  if (!leinwand || !leinwandHeimat) return false;
  if (leinwandAnker && leinwandAnker.parentNode === leinwandHeimat){
    leinwandHeimat.insertBefore(leinwand, leinwandAnker);
  } else {
    leinwandHeimat.appendChild(leinwand);
  }
  pausiere();
  return true;
}

/** Nur fuer die Abnahme: in welchem Behaelter liegt das Canvas gerade? */
export function wohinGehaengt(){
  return leinwand && leinwand.parentNode ? leinwand.parentNode.className : null;
}
