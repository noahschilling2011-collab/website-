// Gemeinsamer Loader für Werkzeuge (Trainingsumgebung, Auswertung, Paritätstest, simtest --kipolicy). Entwicklungswerkzeug, nicht Teil
// des Produkts. Zieht den <script id="sim">-Block aus stadt.html, prüft ihn statisch wie tools/simtest.mjs (verbotene Namen) und führt
// ihn in einem leeren vm-Kontext aus (Math.random, Date und Intl gesperrt). So nutzen Spiel, Tests und Training dieselbe Simulation.
// Nur Node-Standardbibliothek.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

export const HIER = dirname(fileURLToPath(import.meta.url));
export const STANDARD_HTML = join(HIER, '..', 'stadt.html');

// Wie tools/simtest.mjs (Zeile 69–80 in 31ce452): Kommentare entfernen, dann nach Namen suchen, die im sim-Block nichts zu suchen haben
const VERBOTEN = /\b(window|document|fetch|THREE|localStorage|sessionStorage|indexedDB|performance|requestAnimationFrame|setTimeout|setInterval|XMLHttpRequest|Intl|Date|crypto|navigator|location|console)\b|Math\.random/;
export function statischPruefen(code) {
  const ohneKommentare = code.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
  const treffer = [];
  ohneKommentare.split('\n').forEach((z, i) => { const m = z.match(VERBOTEN); if (m) treffer.push(`Zeile ${i + 1} im sim-Block: ${m[0]} → ${z.trim().slice(0, 100)}`); });
  if (treffer.length) throw new Error('Der sim-Block benutzt Verbotenes:\n' + treffer.join('\n'));
}
export const sha256 = (t) => createHash('sha256').update(t).digest('hex');
export function simBlock(html) {
  const t = html.match(/<script id="sim">([\s\S]*?)<\/script>/);
  if (!t) throw new Error('Kein <script id="sim"> in der HTML-Datei gefunden.');
  return t[1];
}
// Eingebettete Policy (<script type="application/json" id="ki-policy">), roh als Text; null, wenn keine da ist
export function policyTextAusHtml(html) {
  const t = html.match(/<script type="application\/json" id="ki-policy">([\s\S]*?)<\/script>/);
  return t && t[1].trim() ? t[1] : null;
}
// ersetzen: [[alt, neu], …], alt genau einmal im sim-Block (wie ladeSimMit in simtest)
export function ladeSimAusHtml(html, ersetzen = []) {
  let code = simBlock(html);
  statischPruefen(code);
  for (const [alt, neu] of ersetzen) {
    if (code.split(alt).length !== 2) throw new Error('Stelle nicht eindeutig: ' + alt.slice(0, 60));
    code = code.replace(alt, () => neu);
  }
  const ctx = vm.createContext({});
  vm.runInContext(`
    Math.random = function () { throw new Error('Math.random ist in der Simulation verboten'); };
    globalThis.Date = undefined;
    globalThis.Intl = undefined;
  `, ctx);
  vm.runInContext(code, ctx, { filename: 'stadt.html#sim' });
  if (!ctx.StadtSim) throw new Error('Der sim-Block hat kein StadtSim angelegt.');
  return { Sim: ctx.StadtSim, ctx, code, simHash: sha256(simBlock(html)).slice(0, 16) };
}
export function ladeSim(pfad = STANDARD_HTML, ersetzen = []) {
  const html = readFileSync(pfad, 'utf8');
  return Object.assign(ladeSimAusHtml(html, ersetzen), { html, pfad });
}

// Zustand kopieren und laden (Schnappschuss im Speicher). exportZustand liefert Sichten auf die laufenden Arrays, importZustand übernimmt
// manche Arrays und JSON-Teile direkt: darum beim Sichern und beim Laden kopieren. JSON-Teile gehen wie beim echten Speichern durch JSON.
export function zustandKopie(Sim, S) {
  const d = Sim.exportZustand(S);
  return { format: d.format, version: d.version, werte: JSON.parse(JSON.stringify(d.werte)), json: JSON.stringify(d.json),
    arrays: d.arrays.map(a => ({ name: a.name, typ: a.typ, daten: a.daten.slice() })) };
}
export function zustandLaden(Sim, k) {
  return Sim.importZustand({ format: k.format, version: k.version, werte: JSON.parse(JSON.stringify(k.werte)), json: JSON.parse(k.json),
    arrays: k.arrays.map(a => ({ name: a.name, typ: a.typ, daten: a.daten.slice() })) });
}
// Fingerabdruck wie fingerabdruck() in simtest (Arrays nach Namen sortiert, dazu Buch, Statistik, KI, Einzelwerte und JSON-Teile)
export function fingerabdruck(Sim, S) {
  const h = createHash('sha256');
  const d = Sim.exportZustand(S);
  for (const a of d.arrays.slice().sort((x, y) => (x.name < y.name ? -1 : 1))) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
  h.update(JSON.stringify(d.werte)); h.update(JSON.stringify(d.json));
  return h.digest('hex').slice(0, 16);
}
