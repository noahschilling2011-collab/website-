#!/usr/bin/env node
// Etappe 2 (Noahs Entscheidung 10, berichte/etappe2/VERBLASSEN.md A.3): Wiedergründung nach einer Pleite. Je Seed ein Lauf über N Tage
// (stündlich wie im Spiel). Zwei Mitschreiber lesen nur (kein Zufall, nichts in S): Pleite (Erinnerung PLEITE: Tag, Person = Platz +
// Generation, Sparsamkeit) und ausgeführte Gründung (Tag, Person). Je Person mit Pleite: Tag der ersten Pleite, Sparsamkeit, Tag der ersten
// Gründung danach (−1: keine). Ausgabe JSON (stdout), Auswertung mit tools/wiedergruendung_auswertung.mjs. Entwicklungswerkzeug.
// Übernommen aus dem Messwerkzeug der Phase „Verblassen“ (vb_wieder.mjs); gleiche Mitschreiber, gleiche Ausgabe.
//   node tools/wiedergruendung.mjs [--html stadt.html] [--seeds 1-20] [--tage 1460] [--setze NAME=wert …] [--sofort] > wieder.json
//   --setze GED=0       ohne Erfahrung und Plan (Bezug); --setze ERF_HALB=0: ohne Verblassen; wirkt auf R nach dem Laden
//   --sofort            Messvariante „sofort vergessen“ (erfLernen speichert nichts; die Grenze des Verblassens)
import { ladeSim, STANDARD_HTML } from './simkern.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const html = arg('html', STANDARD_HTML), tage = Number(arg('tage', '1460')), seedArg = arg('seeds', '1-20'), sofort = args.includes('--sofort');
const seeds = seedArg.includes('-') ? (([a, b]) => Array.from({ length: b - a + 1 }, (x, i) => a + i))(seedArg.split('-').map(Number)) : seedArg.split(',').map(Number);
const setzen = args.flatMap((a, i) => (a === '--setze' && args[i + 1] ? [args[i + 1].split('=')] : []));
const LOG = 'const __L = (globalThis.__L || (globalThis.__L = []));';
const ERS = [
  ['  S.stat.gewaehlt[a]++;', '  S.stat.gewaehlt[a]++; if (ok && a === A.GRUENDEN) { ' + LOG + ' __L.push([0, S.tag, p, S.p.gen[p]]); }'],
  ['function erinnere(S, p, code, ref) {', 'function erinnere(S, p, code, ref) { if (code === M.PLEITE) { ' + LOG + ' __L.push([1, S.tag, p, S.p.gen[p], S.p.spar[p]]); }'],
];
if (sofort) ERS.push(['  P.erf[c] = ((w + 32) << 2) | (n < 3 ? n + 1 : 3);', '  P.erf[c] = 0;                                              // Messvariante „sofort“: nichts behalten']);
const { Sim, ctx, simHash } = ladeSim(html, ERS);
const R = Sim.R;
for (const [n, w] of setzen) {
  if (!(n in R)) throw new Error('R.' + n + ' gibt es in dieser Fassung nicht');
  R[n] = Number(w);
}
const erg = { html, simHash, sofort, gesetzt: Object.fromEntries(setzen.map(([n, w]) => [n, Number(w)])), ged: R.GED, staerke: R.GED_STAERKE,
  ruecklage: R.PLAN_RUECKLAGE, erfHalb: R.ERF_HALB ?? null, tage, seeds: {} };
for (const seed of seeds) {
  ctx.__L = [];
  const S = Sim.neueStadt(seed), stand = {};
  while (S.tag < tage) {
    Sim.stunde(S);
    if (S.stunde === 0 && (S.tag === 730 || S.tag === tage)) stand[S.tag] = { einwohner: S.einwohner, gruendungen: S.stat.gruendungen, pleiten: S.stat.pleiten };
  }
  const pl = new Map(), gr = new Map();
  for (const e of ctx.__L) {
    const k = e[2] + '/' + e[3];
    if (e[0] === 1) { if (!pl.has(k)) pl.set(k, [e[1], e[4]]); }
    else { if (!gr.has(k)) gr.set(k, []); gr.get(k).push(e[1]); }
  }
  // je Person mit Pleite: [Tag der ersten Pleite, Sparsamkeit, Tag der ersten Gründung danach oder −1]
  const personen = [...pl].map(([k, [t0, sp]]) => { const g = (gr.get(k) || []).find(t => t > t0); return [t0, sp, g === undefined ? -1 : g]; });
  erg.seeds[seed] = { personen, gruendungenAusgefuehrt: [...gr.values()].reduce((a, b) => a + b.length, 0), stand };
}
console.log(JSON.stringify(erg));
