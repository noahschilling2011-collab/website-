#!/usr/bin/env node
// Auswertung: Regeln gegen trainierte Policy für dieselben Fokuspersonen und Ausgangslagen (gepaart), maskenfähig.
// Die Policy rechnet genau wie im Browser (Sim.KI.policyRechnen auf der exportierten Datei).
// Kriterien: training/AUSWERTUNG_V9.md (vorab festgelegt, Version 1); die alten von Etappe 1 stehen in training/AUSWERTUNG.md.
//   node tools/werte_aus.mjs --policy ki/policy_x.json [--seeds training|validierung|abschluss] [--versatz 16] [--je-gruppe 32] [--tage 30]
//        [--arme regeln,policy,zufall] [--belohnung belohnung_v2] [--laeufe 1] [--stadtwirkung datei.json] [--aus pfad/ohne_endung]
// Abschlussseeds (ab 30000) erst nach der Kandidatenwahl benutzen; das Skript verlangt dafür --abschluss-freigegeben.
// Änderungen für V9 (vor dem lokalen Lauf, 29.09.2026): jede Person (Seed, ID, Generation) höchstens einmal je Gruppe; 95-%-Intervall mit
// t-Quantil statt 1,96; absolute Mindestdifferenz 0,5; Nebenmetriken Ziele, Gründungen, Fehlgründungen, Kinder, leere Treffen, Stadtwirkung.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { ladeSim, HIER } from './simkern.mjs';
import { Umgebung, mische } from './kiepisode.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const flag = (n) => args.includes('--' + n);
const polPfad = arg('policy');
const seedArt = arg('seeds', 'validierung'), jeGruppe = Number(arg('je-gruppe', '32')), tage = Number(arg('tage', '30'));
const arme = arg('arme', 'regeln,policy').split(',');
const laeufe = Number(arg('laeufe', '1'));                 // so viele Trainingsläufe (Seeds) stehen hinter dem Kandidaten (Freigabe: ≥ 3)
if (seedArt === 'abschluss' && !flag('abschluss-freigegeben')) { console.error('Abschlussseeds erst nach der Kandidatenwahl (--abschluss-freigegeben).'); process.exit(2); }
const versatz = Number(arg('versatz', '0'));
// --versatz n: erst ab dem n-ten Seed der Liste (16: nicht die Validierungsseeds, mit denen das Training den Checkpoint „bester“ gewählt hat)
const SEEDS = JSON.parse(readFileSync(join(HIER, '..', 'training', 'seeds.json'), 'utf8'))[seedArt].slice(versatz);
const GR = ['ohne_arbeit', 'mit_kind', 'wenig_kontakt', 'gruendungsnah', 'rentennah'];
const { Sim, simHash } = ladeSim();
const U = new Umgebung(Sim, { cacheMax: 64, belohnung: arg('belohnung') });
const A = Sim.KI.AKTIONEN, ix = (n) => A.indexOf(n);
const I_GRUENDEN = ix('laden_gruenden'), I_KIND = ix('kind_bekommen');
let pol = null, polD = null;
if (arme.includes('policy')) { polD = JSON.parse(readFileSync(polPfad, 'utf8')); pol = Sim.KI.policyPruefen(polD); }
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex').slice(0, 16);

// Vorab festgelegte Schwellen (training/AUSWERTUNG_V9.md, Version 1)
const K = { relativ: 0.10, absolut: 0.5, notstandPP: 0.02, zieleFaktor: 0.8, zaehlMin: 4, zaehlUnten: 0.5, zaehlOben: 2.0, zaehlAbs: 3,
  fehlgruendungPlus: 2, leerFaktor: 1.5, leerPlus: 5, charakterR: 0.1, charakterHalb: 0.5, stadtEinwohner: 0.9, stadtKasse: 0.2, stadtGruendungen: 0.5,
  paareMin: 20, laeufeMin: 3 };

function episode(seed, nr, gruppe, arm) {
  let r = U.reset({ seed, nr, gruppe, tage }), z = mische(seed * 7 + 1, nr), rueck = r.belohnung, rueckfall = 0;
  const erste = { id: U.epi.id, gen: U.epi.gen };
  while (!r.beendet && !r.abgeschnitten) {
    let a;
    if (arm === 'regeln') a = 'regel';
    else if (arm === 'policy') {
      try { a = Sim.KI.policyRechnen(pol, Float32Array.from(r.beob), Uint8Array.from(r.maske)).aktion; }
      catch (e) { rueckfall++; a = 'regel'; }             // wie im Spiel: Fehler → Regeln
    } else { const L = r.maske.map((v, k) => (v ? k : -1)).filter(k => k >= 0); z = mische(z, 3); a = L[z % L.length]; }
    r = U.step(a);
    rueck += r.belohnung;
  }
  return { ...r.info.metrik, rueckgabe: rueck, rueckfall, fokus: erste };
}
const mittel = (a) => a.reduce((s, v) => s + v, 0) / (a.length || 1);
const sd = (a) => { if (a.length < 2) return 0; const m = mittel(a); return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1)); };
// 97,5-%-Quantil der t-Verteilung (Tabelle; über 30 Freiheitsgrade linear in 1/df zwischen 30, 40, 60, 120, ∞)
const T975 = [0, 12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093,
  2.086, 2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042];
function t975(df) {
  if (df < 1) return Infinity;
  if (df <= 30) return T975[df];
  const P = [[30, 2.042], [40, 2.021], [60, 2.000], [120, 1.980], [Infinity, 1.960]];
  for (let k = 0; k < P.length - 1; k++) if (df <= P[k + 1][0]) {
    const x = 1 / df, x0 = 1 / P[k][0], x1 = P[k + 1][0] === Infinity ? 0 : 1 / P[k + 1][0];
    return P[k][1] + (P[k + 1][1] - P[k][1]) * (x0 - x) / (x0 - x1);
  }
  return 1.960;
}
const ki95 = (a) => (a.length < 2 ? Infinity : t975(a.length - 1) * sd(a) / Math.sqrt(a.length));
const pearson = (x, y) => { const mx = mittel(x), my = mittel(y); let a = 0, b = 0, c = 0;
  for (let k = 0; k < x.length; k++) { a += (x[k] - mx) * (y[k] - my); b += (x[k] - mx) ** 2; c += (y[k] - my) ** 2; } return b && c ? a / Math.sqrt(b * c) : 0; };
// Zählgrößen (Gründungen, Kinder): Policy zwischen 50 % und 200 % der Regeln; bei weniger als 4 Fällen der Regeln höchstens 3 Abstand
const zaehlOk = (p, r) => (r >= K.zaehlMin ? p >= K.zaehlUnten * r && p <= K.zaehlOben * r : Math.abs(p - r) <= K.zaehlAbs);

const t0 = performance.now();
const ergebnis = { kriterien: 'training/AUSWERTUNG_V9.md Version 1', schwellen: K, simHash, belohnung: U.B.version,
  werkzeug: { 'tools/werte_aus.mjs': sha(join(HIER, 'werte_aus.mjs')), 'tools/kiepisode.mjs': sha(join(HIER, 'kiepisode.mjs')) },
  policy: polD ? { name: polD.name, hash: polD.hash, status: polD.status, herkunft: polD.herkunft, datei: polPfad, dateiSha256: sha(polPfad) } : null,
  seeds: seedArt, versatz, seedListe: SEEDS, jeGruppe, tage, arme, laeufe, gruppen: {}, episoden: [], invariantenFehler: [] };
for (const g of GR) {
  const reihe = [], gesehen = new Set();
  let versuche = 0, doppelt = 0, ohne = 0;
  while (reihe.length < jeGruppe && versuche < jeGruppe * 6) {
    const seed = SEEDS[versuche % SEEDS.length], n = Math.floor(versuche / SEEDS.length);
    versuche++;
    try { U.reset({ seed, nr: n, gruppe: g, tage }); } catch (e) { if (e.code === 'keine_fokusperson') { ohne++; continue; } throw e; }
    const schluessel = `${seed}:${U.epi.id}:${U.epi.gen}`;
    if (gesehen.has(schluessel)) { doppelt++; continue; }   // dieselbe Person nicht zweimal in einer Gruppe
    gesehen.add(schluessel);
    const paar = {};
    try {
      for (const arm of arme) paar[arm] = episode(seed, n, g, arm);
    } catch (e) {
      if (e.code === 'invariante' || e.code === 'maske_verletzt') { ergebnis.invariantenFehler.push({ gruppe: g, seed, nr: n, code: e.code, fehler: e.message }); continue; }
      throw e;
    }
    const f0 = paar[arme[0]].fokus;
    for (const arm of arme) if (paar[arm].fokus.id !== f0.id || paar[arm].fokus.gen !== f0.gen) throw new Error('Arme haben verschiedene Fokuspersonen');
    reihe.push({ seed, nr: n, ...paar });
  }
  const G = { episoden: reihe.length, versuche, doppeltUebersprungen: doppelt, ohneKandidat: ohne, arme: {} };
  for (const arm of arme) {
    const E = reihe.map(x => x[arm]);
    const summe = (k) => E.reduce((s, e) => s + e[k], 0);
    const gegr = E.map(e => e.ausgefuehrtJeAktion[I_GRUENDEN]);
    G.arme[arm] = { defizitMittel: { mittel: mittel(E.map(e => e.defizitMittel)), sd: sd(E.map(e => e.defizitMittel)), ki95: ki95(E.map(e => e.defizitMittel)) },
      notstandAnteil: mittel(E.map(e => e.notstandAnteil)), rueckgabe: mittel(E.map(e => e.rueckgabe)),
      bedarfMittel: [0, 1, 2, 3].map(k => mittel(E.map(e => e.bedarfMittel[k]))),
      wegzug: E.filter(e => e.ende === 'wegzug' || e.ende === 'weg').length, tod: E.filter(e => e.ende === 'tod').length,
      entscheidungen: summe('entscheidungen'), ausgefuehrt: summe('ausgefuehrt'), fehlgeschlagen: summe('fehlgeschlagen'), abgelehnt: summe('abgelehnt'),
      warten: summe('warten'), maskeVerletzt: summe('maskeVerletzt'), rueckfall: summe('rueckfall'), umkehr: summe('umkehr'),
      zieleErreicht: summe('zieleErreicht'), zieleAufgegeben: summe('zieleAufgegeben'),
      gruendungen: gegr.reduce((s, v) => s + v, 0), fehlgruendungen: E.filter((e, k) => gegr[k] > 0 && !e.betriebEnde).length,
      betriebEnde: summe('betriebEnde'), kinder: E.reduce((s, e) => s + e.ausgefuehrtJeAktion[I_KIND], 0),
      treffenOhneGegenueber: summe('treffenOhneGegenueber'), treffenOhneBedarf: summe('treffenOhneBedarf'), amtStunden: summe('amtStunden'),
      aktionen: Object.fromEntries(A.map((n, k) => [n, E.reduce((s, e) => s + e.jeAktion[k], 0)])),
      ausgefuehrtJeAktion: Object.fromEntries(A.map((n, k) => [n, E.reduce((s, e) => s + e.ausgefuehrtJeAktion[k], 0)])) };
  }
  if (arme.includes('regeln') && arme.includes('policy')) {
    const d = reihe.map(x => x.regeln.defizitMittel - x.policy.defizitMittel);   // > 0: Policy besser (weniger Defizit)
    const reg = G.arme.regeln.defizitMittel.mittel, md = mittel(d), k95 = ki95(d);
    G.vergleich = { differenzMittel: md, sd: sd(d), ki95: k95, untergrenze: md - k95, relativ: reg ? md / reg : 0,
      relativUnten: reg ? (md - k95) / reg : 0, relativOben: reg ? (md + k95) / reg : 0,
      besser: d.filter(v => v > 1e-9).length, schlechter: d.filter(v => v < -1e-9).length, gleich: d.filter(v => Math.abs(v) <= 1e-9).length };
    G.vergleich.verbessert = G.vergleich.relativ >= K.relativ && G.vergleich.untergrenze > 0 && md >= K.absolut;
  }
  ergebnis.gruppen[g] = G;
  for (const x of reihe) ergebnis.episoden.push({ gruppe: g, seed: x.seed, nr: x.nr, fokus: x[arme[0]].fokus, ...Object.fromEntries(arme.map(a => [a, {
    defizitMittel: x[a].defizitMittel, ende: x[a].ende, entscheidungen: x[a].entscheidungen, jeAktion: x[a].jeAktion, ausgefuehrtJeAktion: x[a].ausgefuehrtJeAktion,
    persoenlichkeit: x[a].persoenlichkeit, kontrolle: x[a].kontrolle, zieleErreicht: x[a].zieleErreicht, notstandAnteil: x[a].notstandAnteil,
    betriebStart: x[a].betriebStart, betriebEnde: x[a].betriebEnde, rueckgabe: x[a].rueckgabe }])) });
  process.stderr.write(`${g}: ${reihe.length} Paare (${versuche} Versuche, ${doppelt} doppelt, ${ohne} ohne Kandidat)\n`);
}
// Persönlichkeit: wirkt der Charakter noch? Korrelation Merkmal ↔ Anteil einer Aktion an den Entscheidungen (alle Gruppen)
const PAARE = [['gesellig', ['freunde_treffen', 'partner_suchen']], ['ehrgeiz', ['job_wechseln', 'laden_gruenden']], ['fleiss', ['freinehmen']],
  ['heimat', ['wegziehen']], ['spar', ['kuendigen']]];
ergebnis.persoenlichkeit = {};
for (const arm of arme) {
  const E = ergebnis.episoden.map(e => e[arm]).filter(e => e.entscheidungen > 0);
  ergebnis.persoenlichkeit[arm] = Object.fromEntries(PAARE.map(([t, akt]) => [`${t}~${akt.join('+')}`,
    pearson(E.map(e => e.persoenlichkeit[t]), E.map(e => akt.reduce((s, n) => s + e.jeAktion[ix(n)], 0) / e.entscheidungen))]));
}
// Kontrollmessung (nur Messung, nie Eingabe der Policy): ohne Eltern in der Stadt gegen hier geboren
ergebnis.kontrolle = {};
for (const arm of arme) {
  const E = ergebnis.episoden.map(e => e[arm]);
  const teil = (z) => E.filter(e => e.kontrolle.zugezogen === z);
  ergebnis.kontrolle[arm] = { zugezogen: { n: teil(1).length, defizit: mittel(teil(1).map(e => e.defizitMittel)) },
    geboren: { n: teil(0).length, defizit: mittel(teil(0).map(e => e.defizitMittel)) } };
}
// Prüfung nach training/AUSWERTUNG_V9.md (vorab festgelegt)
if (arme.includes('regeln') && arme.includes('policy')) {
  const gruppen = GR.map(g => ergebnis.gruppen[g]);
  const sumArm = (arm, k) => gruppen.reduce((s, G) => s + G.arme[arm][k], 0);
  const P = (k) => sumArm('policy', k), R = (k) => sumArm('regeln', k);
  const pruef = [];
  const neu = (name, ok, wert, grenze) => pruef.push({ name, ok: !!ok, wert, grenze });
  for (const g of GR) {
    const X = ergebnis.gruppen[g].arme;
    neu(`notstand_${g}`, X.policy.notstandAnteil <= X.regeln.notstandAnteil + K.notstandPP, +X.policy.notstandAnteil.toFixed(4), `≤ ${(X.regeln.notstandAnteil + K.notstandPP).toFixed(4)} (Regeln + 2 pp)`);
    neu(`wegzug_${g}`, X.policy.wegzug <= X.regeln.wegzug, X.policy.wegzug, `≤ ${X.regeln.wegzug} (Regeln)`);
  }
  neu('ziele_erreicht', P('zieleErreicht') >= K.zieleFaktor * R('zieleErreicht'), P('zieleErreicht'), `≥ ${(K.zieleFaktor * R('zieleErreicht')).toFixed(1)} (0,8 × Regeln ${R('zieleErreicht')})`);
  neu('gruendungen', zaehlOk(P('gruendungen'), R('gruendungen')), P('gruendungen'), `Regeln ${R('gruendungen')}: ${R('gruendungen') >= K.zaehlMin ? '0,5× bis 2×' : '±3'}`);
  neu('fehlgruendungen', P('fehlgruendungen') <= R('fehlgruendungen') + K.fehlgruendungPlus, P('fehlgruendungen'), `≤ ${R('fehlgruendungen') + K.fehlgruendungPlus} (Regeln + 2)`);
  neu('kinder', zaehlOk(P('kinder'), R('kinder')), P('kinder'), `Regeln ${R('kinder')}: ${R('kinder') >= K.zaehlMin ? '0,5× bis 2×' : '±3'}`);
  const leer = (f) => f('treffenOhneGegenueber') + f('treffenOhneBedarf');
  neu('leere_treffen', leer(P) <= K.leerFaktor * leer(R) + K.leerPlus, leer(P), `≤ ${(K.leerFaktor * leer(R) + K.leerPlus).toFixed(1)} (1,5 × Regeln ${leer(R)} + 5)`);
  for (const k of Object.keys(ergebnis.persoenlichkeit.regeln)) {
    const r = ergebnis.persoenlichkeit.regeln[k], p = ergebnis.persoenlichkeit.policy[k];
    neu(`charakter_${k}`, Math.abs(r) < K.charakterR || (Math.sign(r) === Math.sign(p) && Math.abs(p) >= K.charakterHalb * Math.abs(r)), +p.toFixed(3),
      Math.abs(r) < K.charakterR ? `frei (Regeln |r| ${Math.abs(r).toFixed(3)} < 0,1)` : `Vorzeichen wie Regeln (${r.toFixed(3)}), |r| ≥ ${(K.charakterHalb * Math.abs(r)).toFixed(3)}`);
  }
  // Stadtwirkung (Policy für alle im Trainingsbereich): aus tools/ki_stadtwirkung.mjs --aus, dieselbe Policy (Hash), passende Seeds
  const swPfad = arg('stadtwirkung');
  let sw = null;
  if (swPfad) {
    sw = JSON.parse(readFileSync(swPfad, 'utf8'));
    if (!polD || sw.policyHash !== polD.hash) throw new Error(`Stadtwirkung ${swPfad} gehört zu Policy ${sw.policyHash}, nicht ${polD && polD.hash}`);
    for (const teil of ['neu', 'gewachsen']) {
      const s = sw.summen[teil];
      neu(`stadt_${teil}_einwohner`, s.policy.einwohner >= K.stadtEinwohner * s.regeln.einwohner, s.policy.einwohner, `≥ ${(K.stadtEinwohner * s.regeln.einwohner).toFixed(0)} (0,9 × Regeln ${s.regeln.einwohner})`);
      neu(`stadt_${teil}_kasse`, s.policy.kasse >= s.regeln.kasse - K.stadtKasse * Math.abs(s.regeln.kasse), s.policy.kasse, `≥ ${(s.regeln.kasse - K.stadtKasse * Math.abs(s.regeln.kasse)).toFixed(0)} (Regeln ${s.regeln.kasse} − 20 %)`);
      neu(`stadt_${teil}_gruendungen`, s.policy.gruendungen >= K.stadtGruendungen * s.regeln.gruendungen, s.policy.gruendungen, `≥ ${(K.stadtGruendungen * s.regeln.gruendungen).toFixed(1)} (0,5 × Regeln ${s.regeln.gruendungen})`);
    }
  }
  ergebnis.stadtwirkung = sw ? { datei: swPfad, seeds: sw.seeds, summen: sw.summen } : null;
  const verbessert = gruppen.filter(G => G.vergleich.verbessert).length;
  const inv = ergebnis.invariantenFehler.length === 0 && gruppen.every(G => G.arme.policy.maskeVerletzt === 0 && G.arme.policy.rueckfall === 0);
  const neben = pruef.every(x => x.ok) && !!sw;
  const genug = gruppen.every(G => G.episoden >= K.paareMin);
  const vorlaeufig = verbessert >= 3 && inv && neben && genug && seedArt === 'abschluss';
  ergebnis.freigabe = { gruppenMitVerbesserung: verbessert, invarianten: inv, nebenmetriken: neben, stadtwirkungGemessen: !!sw,
    nebenBestanden: pruef.filter(x => x.ok).length, nebenGesamt: pruef.length, pruefungen: pruef, genugEpisoden: genug, laeufe,
    urteil: seedArt !== 'abschluss' ? `nur ${seedArt} (keine Freigabe)` : !vorlaeufig ? 'NICHT BESTANDEN' : laeufe >= K.laeufeMin ? 'BESTANDEN' : `VORLÄUFIG BESTANDEN (${laeufe} Trainingslauf, verlangt ≥ 3)`,
    bestanden: vorlaeufig && laeufe >= K.laeufeMin };
}
ergebnis.laufzeit_s = +((performance.now() - t0) / 1000).toFixed(1);
// Bericht
const f1 = (v) => v.toFixed(1), f2 = (v) => v.toFixed(2), pz = (v) => (100 * v).toFixed(1) + ' %';
let md = `# Auswertung ${polD ? polD.name : ''} (${seedArt} ${SEEDS[0]}–${SEEDS[SEEDS.length - 1]}, ${jeGruppe} Paare je Gruppe, ${tage} Tage)\n\n`
  + `${polD ? `Policy „${polD.name}“ (${polD.status}, Hash ${polD.hash}, ${polD.herkunft.trainingsSchritte} Trainingsschritte, Lauf ${polD.herkunft.lauf}, Checkpoint ${polD.herkunft.checkpoint}). ` : ''}`
  + `Sim ${simHash}, Belohnung ${U.B.version}. Hauptmetrik: mittleres Bedürfnisdefizit (100 − Zufriedenheit) je Stunde der Fokusperson, Wegzug zählt die fehlenden Stunden mit 100. `
  + `Kleiner ist besser. Intervalle: 95 % mit t-Quantil. Laufzeit ${ergebnis.laufzeit_s} s.\n\n`
  + `| Gruppe | Paare | ${arme.map(a => `Defizit ${a} (Streuung; ±95 %)`).join(' | ')} | Differenz Regeln − Policy (Streuung; ±95 %) | relativ (95 %) | besser/schlechter/gleich | zählt |\n|---|---|${arme.map(() => '---|').join('')}---|---|---|---|\n`;
for (const g of GR) {
  const G = ergebnis.gruppen[g], v = G.vergleich;
  md += `| ${g} | ${G.episoden} | ${arme.map(a => `${f1(G.arme[a].defizitMittel.mittel)} (${f1(G.arme[a].defizitMittel.sd)}; ±${f1(G.arme[a].defizitMittel.ki95)})`).join(' | ')} | `
    + (v ? `${f2(v.differenzMittel)} (${f2(v.sd)}; ±${f2(v.ki95)}) | ${pz(v.relativ)} (${pz(v.relativUnten)} … ${pz(v.relativOben)}) | ${v.besser}/${v.schlechter}/${v.gleich} | ${v.verbessert ? 'ja' : 'nein'} |\n` : '– | – | – | – |\n');
}
md += `\n| Gruppe | Arm | Entsch. | ausgeführt | ohne Erfolg | abgelehnt | gewartet | Maske verl. | Rückfall | Umkehr | Notstand | Wegzug | Ziele err./aufg. | Gründungen (Fehl-) | Kinder | leere Treffen (ohne Gegenüber/ohne Bedarf) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
for (const g of GR) for (const a of arme) {
  const X = ergebnis.gruppen[g].arme[a];
  md += `| ${g} | ${a} | ${X.entscheidungen} | ${X.ausgefuehrt} | ${X.fehlgeschlagen} | ${X.abgelehnt} | ${X.warten} | ${X.maskeVerletzt} | ${X.rueckfall} | ${X.umkehr} | ${pz(X.notstandAnteil)} | ${X.wegzug} | ${X.zieleErreicht}/${X.zieleAufgegeben} | ${X.gruendungen} (${X.fehlgruendungen}) | ${X.kinder} | ${X.treffenOhneGegenueber}/${X.treffenOhneBedarf} |\n`;
}
md += `\nAktionen (alle Gruppen; gewählt / davon ausgeführt):\n\n| Aktion | ${arme.join(' | ')} |\n|---|${arme.map(() => '---|').join('')}\n`;
for (const n of A) md += `| ${n} | ${arme.map(a => `${GR.reduce((s, g) => s + ergebnis.gruppen[g].arme[a].aktionen[n], 0)} / ${GR.reduce((s, g) => s + ergebnis.gruppen[g].arme[a].ausgefuehrtJeAktion[n], 0)}`).join(' | ')} |\n`;
md += `\nPersönlichkeit (Pearson r, Merkmal gegen Anteil der Aktion an den Entscheidungen, alle Episoden):\n\n| Paar | ${arme.join(' | ')} |\n|---|${arme.map(() => '---|').join('')}\n`;
for (const k of Object.keys(ergebnis.persoenlichkeit[arme[0]])) md += `| ${k} | ${arme.map(a => f2(ergebnis.persoenlichkeit[a][k])).join(' | ')} |\n`;
md += `\nKontrollmessung (nur gemessen, die Policy sieht es nicht; „ohne Eltern in der Stadt“ = Startbevölkerung oder zugezogen): ${arme.map(a => `${a}: ohne Eltern in der Stadt n=${ergebnis.kontrolle[a].zugezogen.n} Defizit ${f1(ergebnis.kontrolle[a].zugezogen.defizit)}, in der Stadt geboren n=${ergebnis.kontrolle[a].geboren.n}${ergebnis.kontrolle[a].geboren.n ? ` Defizit ${f1(ergebnis.kontrolle[a].geboren.defizit)}` : ' (keine: der Vergleich sagt hier nichts)'}`).join('; ')}\n`;
if (ergebnis.invariantenFehler.length) md += `\n**Invarianten verletzt:** ${ergebnis.invariantenFehler.length}× (${ergebnis.invariantenFehler.map(x => `${x.gruppe} ${x.seed}/${x.nr}: ${x.fehler}`).join('; ')})\n`;
if (ergebnis.freigabe) {
  const F = ergebnis.freigabe;
  md += `\nNebenmetriken (AUSWERTUNG_V9.md): ${F.nebenBestanden} von ${F.nebenGesamt} in Toleranz${F.stadtwirkungGemessen ? '' : ', Stadtwirkung nicht übergeben'}.\n\n| Prüfung | ok | Policy | Grenze |\n|---|---|---|---|\n`;
  for (const x of F.pruefungen) md += `| ${x.name} | ${x.ok ? 'ja' : '**nein**'} | ${x.wert} | ${x.grenze} |\n`;
  md += `\nUrteil: **${F.urteil}** (Gruppen mit ≥ 10 %, Untergrenze über 0 und ≥ 0,5 Punkte: ${F.gruppenMitVerbesserung} von 5; Invarianten ${F.invarianten ? 'ok' : 'VERLETZT'}; `
    + `Nebenmetriken ${F.nebenmetriken ? 'in Toleranz' : 'nicht alle in Toleranz'}; ≥ 20 Paare je Gruppe ${F.genugEpisoden ? 'ja' : 'nein'}; Trainingsläufe ${laeufe}). Regeln bleiben Standard, solange nicht „BESTANDEN“.\n`;
}
const aus = arg('aus');
if (aus) { mkdirSync(dirname(aus), { recursive: true }); writeFileSync(aus + '.json', JSON.stringify(ergebnis, null, 1)); writeFileSync(aus + '.md', md); }
console.log(md);
