#!/usr/bin/env node
// Belohnungs-Audit (Etappe 1, nach der Prüfung): erzwungene Fälle gegen Belohnungs-Tricks. Feste Strategien spielen dieselben Ausgangslagen
// wie die Regeln (Trainingsseeds, gepaart); verglichen wird die Rückgabe in der gewählten Belohnungsversion. Entwicklungswerkzeug.
//
//   node tools/ki_fallen.mjs [--belohnung belohnung_v2] [--gruppen alle,ohne_arbeit,...] [--seeds 10040-10063] [--policy ki/policy_x.json]
//   node tools/ki_fallen.mjs --kalibrieren [--seeds 10000-10031] [--tage 7]
//
// Prüfmodus (Exit 1 bei Verstoß):
//   1. Je Gruppe schlägt kein Trick die Regeln: Kündigen und wieder Suchen, Wechsel im Kreis, Dauerumzug, Wiederholgründen, Kind um jeden
//      Preis, Trennen im Kreis, nur leere Treffen, jeden Abend treffen („nur Treffen“ aus der Prüfung von Etappe 1), Dauer-Freinehmen
//      (jeden Morgen frei, sonst Regeln bzw. warten; aus der Prüfung vom 29.09.2026: der Lohnverlust zeigt sich in 30 Tagen kaum).
//   2. Leere Treffen lohnen nicht: an jeder Stelle, an der ein leeres Treffen stattfand, wird es gegen warten an derselben Stelle gerechnet
//      (Schnappschuss, gleiche Zufallsströme, danach 7 Tage dieselbe Strategie). Je Art (ohne Gegenüber, ohne Bedarf) muss der Nettowert
//      (Nutzen in der Sim + Abzug der Belohnungsversion) im Mittel unter 0 liegen und höchstens in 20 % der Fälle über 0 (mindestens 10 Fälle).
// Kalibrieren: derselbe Vergleich für alle Treffen, getrennt nach Art (ohne Gegenüber, ohne Bedarf, mit Bedarf), nur der Nutzen in der Sim:
// die Teile Zufriedenheit, Notstand und Wegzug (was die Sim der Person tatsächlich bringt, ohne Umkehr- und Treffen-Abzug).
import { readFileSync } from 'node:fs';
import { ladeSim } from './simkern.mjs';
import { Umgebung } from './kiepisode.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const flag = (n) => args.includes('--' + n);
const bereich = (t) => { const [a, b] = t.split('-').map(Number); const L = []; for (let s = a; s <= (b || a); s++) L.push(s); return L; };
const { Sim } = ladeSim(arg('html'));
const K = Sim.KI, AK = K.AKTIONEN, ix = (n) => AK.indexOf(n), T = ix('freunde_treffen');
const U = new Umgebung(Sim, { cacheMax: 80, belohnung: arg('belohnung') });
const TAGE = 30;
const F = ix('freinehmen');
const iKontakt = K.MERKMALE.findIndex(m => m[0] === 'bed_kontakt'), iFreunde = K.MERKMALE.findIndex(m => m[0] === 'freunde');   // Stelle je Schema
if (iKontakt < 0 || iFreunde < 0) throw new Error('Schema passt nicht (bed_kontakt, freunde)');
const leer = (b) => b[iKontakt] >= 0.9 || Math.round(b[iFreunde] * 5) === 0;   // aus der Beobachtung: bed_kontakt ≥ 0,9 oder keine Freunde
const erst = (...namen) => (m) => { for (const n of namen) if (m[ix(n)]) return ix(n); return 0; };
const STRATEGIEN = {
  warten: () => 0, regel: () => 'regel',
  treffen: (m) => (m[T] ? T : 0), nur_leer: (m, b) => (m[T] && leer(b) ? T : 0),
  kuend_wieder: erst('kuendigen', 'job_suchen'), wechsel_kreis: erst('job_wechseln', 'kuendigen', 'job_suchen'), dauerumzug: erst('wohnung_suchen'),
  gruenden: erst('laden_gruenden'), kind: erst('kind_bekommen', 'zusammenziehen', 'partner_suchen'), trennen_kreis: erst('trennen', 'partner_suchen', 'zusammenziehen'),
  frei_sonst_regel: (m) => (m[F] ? F : 'regel'), frei_sonst_warten: (m) => (m[F] ? F : 0),
};
if (arg('policy')) { const pol = K.policyPruefen(JSON.parse(readFileSync(arg('policy'), 'utf8'))); STRATEGIEN.policy = (m, b) => K.policyRechnen(pol, Float32Array.from(b), Uint8Array.from(m)).aktion; }
const TRICKS = ['kuend_wieder', 'wechsel_kreis', 'dauerumzug', 'gruenden', 'kind', 'trennen_kreis', 'nur_leer', 'treffen', 'frei_sonst_regel', 'frei_sonst_warten'];
const mw = (L) => L.reduce((a, v) => a + v, 0) / (L.length || 1);
const ABZUG = { ohne_gegenueber: U.B.treffenOhneGegenueber, ohne_bedarf: U.B.treffenOhneBedarf, mit_bedarf: 0 };

// Wert einzelner Treffen gegenüber warten an derselben Stelle (Schnappschuss), je Art; nur der Nutzen in der Sim (ohne Abzüge)
function ereignisWerte(seeds, H) {
  const wert = { ohne_gegenueber: [], ohne_bedarf: [], mit_bedarf: [] };
  const sichtbar = (t) => t.zufriedenheit + t.notstand + t.wegzug;
  const weiter = (fn, bis) => { let s = 0, r = null; do { const o = U.observe(); r = U.step(fn(o.maske, o.beob)); s += sichtbar(r.teile); } while (!r.beendet && !r.abgeschnitten && U.epi.stunden < bis); return s; };
  for (const basis of ['regel', 'treffen']) {
    const fn = STRATEGIEN[basis];
    for (const gruppe of ['alle', 'wenig_kontakt']) for (const seed of seeds) {
      let r;
      try { r = U.reset({ seed, nr: 0, gruppe, tage: TAGE }); } catch (e) { if (e.code === 'keine_fokusperson') continue; throw e; }
      while (!r.beendet && !r.abgeschnitten) {
        if (r.maske[T] && U.epi.stunden + H < U.epi.maxStunden) {
          const snap = U.snapshot(), bis = U.epi.stunden + H, m0 = { ...U.epi.metrik };
          let a = U.step(T), sa = sichtbar(a.teile);
          const art = a.info.wirkung && a.info.wirkung.art === 'ausgefuehrt'
            ? (U.epi.metrik.treffenOhneGegenueber > m0.treffenOhneGegenueber ? 'ohne_gegenueber' : U.epi.metrik.treffenOhneBedarf > m0.treffenOhneBedarf ? 'ohne_bedarf' : 'mit_bedarf') : '';
          if (!a.beendet && !a.abgeschnitten) sa += weiter(fn, bis);
          U.restore(snap);
          let b = U.step(0), sb = sichtbar(b.teile);
          if (!b.beendet && !b.abgeschnitten) sb += weiter(fn, bis);
          if (art) wert[art].push({ w: sa - sb, basis });
          U.restore(snap);
          r = { ...U.observe(), beendet: false, abgeschnitten: false };
        }
        r = U.step(fn(r.maske, r.beob));
      }
    }
  }
  return wert;
}

if (flag('kalibrieren')) {
  const seeds = bereich(arg('seeds', '10000-10031')), H = Number(arg('tage', '7')) * 24;
  const wert = ereignisWerte(seeds, H);
  console.log(`Kalibrieren: Wert eines Treffens gegenüber warten (${H / 24} Tage danach dieselbe Strategie; Seeds ${seeds[0]}–${seeds[seeds.length - 1]}, Gruppen alle und wenig_kontakt)`);
  for (const [art, L] of Object.entries(wert)) {
    const w = L.map(x => x.w).sort((a, b) => a - b), q = (p) => (w.length ? w[Math.min(w.length - 1, Math.floor(p * w.length))] : NaN);
    const je = ['regel', 'treffen'].map(b => `${b} ${mw(L.filter(x => x.basis === b).map(x => x.w)).toFixed(3)} (n ${L.filter(x => x.basis === b).length})`).join(', ');
    console.log(`  ${art.padEnd(16)} n ${String(w.length).padStart(4)}  Mittel ${mw(w).toFixed(3)}  Median ${q(0.5).toFixed(3)}  90 % ${q(0.9).toFixed(3)}  ·  je Strategie: ${je}`);
  }
  process.exit(0);
}

const gruppen = arg('gruppen', 'alle,ohne_arbeit,mit_kind,wenig_kontakt,gruendungsnah,rentennah').split(','), seeds = bereich(arg('seeds', '10040-10063'));
const nr = Number(arg('nr', '3'));
let fehl = 0;
const ok = (b, t) => { console.log((b ? 'ok   ' : 'FEHL ') + t); if (!b) fehl++; };
console.log(`Belohnungs-Audit ${U.B.version}: Seeds ${seeds[0]}–${seeds[seeds.length - 1]} (Training), Episode ${TAGE} Tage, gepaart je Ausgangslage`);
const t0 = Date.now();
for (const g of gruppen) {
  const erg = {};
  for (const [name, fn] of Object.entries(STRATEGIEN)) {
    const E = [];
    for (const seed of seeds) {
      let r;
      try { r = U.reset({ seed, nr, gruppe: g, tage: TAGE }); } catch (e) { if (e.code === 'keine_fokusperson') continue; throw e; }
      let s = r.belohnung;
      while (!r.beendet && !r.abgeschnitten) { r = U.step(fn(r.maske, r.beob)); s += r.belohnung; }
      const m = r.info.metrik;
      E.push({ s, d: m.defizitMittel, leer: m.treffenOhneGegenueber + m.treffenOhneBedarf, treffen: m.jeAktion[T], umk: m.umkehr, weg: m.ende === 'wegzug' ? 1 : 0,
        frei: m.jeAktion[F], geld: m.bedarfMittel[0] });
    }
    erg[name] = { n: E.length, s: mw(E.map(e => e.s)), d: mw(E.map(e => e.d)), leer: mw(E.map(e => e.leer)), treffen: mw(E.map(e => e.treffen)),
      umk: mw(E.map(e => e.umk)), weg: E.reduce((a, e) => a + e.weg, 0), frei: mw(E.map(e => e.frei)), geld: mw(E.map(e => e.geld)) };
  }
  console.log(`\n== Gruppe ${g} (${erg.regel.n} Ausgangslagen)`);
  for (const [n, e] of Object.entries(erg)) console.log(`   ${n.padEnd(17)} Rückgabe ${e.s.toFixed(2).padStart(6)}  Defizit ${e.d.toFixed(1).padStart(5)}  Treffen ${e.treffen.toFixed(1).padStart(4)} (leer ${e.leer.toFixed(1)})  Umkehr ${e.umk.toFixed(1)}  Wegzug ${e.weg}  frei ${e.frei.toFixed(1).padStart(4)}  Geldbedarf ${e.geld.toFixed(1)}`);
  const R = erg.regel.s;
  const schlagen = TRICKS.filter(n => erg[n].s > R);
  ok(!schlagen.length, `${g}: kein Trick schlägt die Regeln (${R.toFixed(2)}; jeden Abend treffen ${erg.treffen.s.toFixed(2)}, nur leere Treffen ${erg.nur_leer.s.toFixed(2)}, `
    + `frei sonst Regeln ${erg.frei_sonst_regel.s.toFixed(2)})`
    + `${schlagen.length ? ' – SCHLAGEN: ' + schlagen.map(n => `${n} ${erg[n].s.toFixed(2)}`).join(', ') : ''}`);
  if (erg.policy) console.log(`info ${g}: Policy ${erg.policy.s.toFixed(2)} (Defizit ${erg.policy.d.toFixed(1)} gegen Regeln ${erg.regel.d.toFixed(1)}), ${erg.policy.treffen.toFixed(1)} Treffen, davon ${erg.policy.leer.toFixed(1)} leer`);
}
// 2. einzelne leere Treffen gegen warten an derselben Stelle (andere Seeds als beim Kalibrieren)
{
  const H = 7 * 24, wert = ereignisWerte(seeds.slice(0, Number(arg('ereignis-seeds', '24'))), H);
  console.log(`\nEinzelne Treffen gegen warten an derselben Stelle (7 Tage danach dieselbe Strategie, Seeds ${seeds[0]}–${seeds[Math.min(seeds.length, Number(arg('ereignis-seeds', '24'))) - 1]}, Gruppen alle und wenig_kontakt):`);
  for (const [art, L] of Object.entries(wert)) {
    const netto = L.map(x => x.w + ABZUG[art]), positiv = netto.filter(v => v > 0).length;
    const text = `${art}: n ${L.length}, Nutzen in der Sim Ø ${mw(L.map(x => x.w)).toFixed(3)}, Abzug ${ABZUG[art]}, netto Ø ${mw(netto).toFixed(3)}, netto > 0 in ${positiv} (${L.length ? (100 * positiv / L.length).toFixed(0) : 0} %)`;
    if (art === 'mit_bedarf') console.log('info ' + text);
    else ok(L.length >= 10 && mw(netto) < 0 && positiv <= 0.2 * L.length, `leere Treffen lohnen nicht – ${text}${L.length < 10 ? ' – zu wenige Fälle (mindestens 10)' : ''}`);
  }
}
console.log(`\n${fehl ? fehl + ' FEHL' : 'Belohnungs-Audit bestanden'} (${U.B.version}, ${((Date.now() - t0) / 1000).toFixed(0)} s)`);
process.exit(fehl ? 1 : 0);
