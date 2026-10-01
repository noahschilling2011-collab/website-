#!/usr/bin/env node
// Trainingsumgebung als dauerhafter Node-Prozess: JSONL-Protokoll v1 über stdin/stdout (eine Zeile je Anfrage, eine je Antwort).
// Entwicklungswerkzeug, nicht Teil des Produkts. Dieselbe Simulation wie im Spiel (tools/simkern.mjs lädt den sim-Block aus stadt.html).
//
//   node tools/kiumgebung.mjs [--html pfad/stadt.html] [--belohnung belohnung_v2]   (Standard: kiepisode.BELOHNUNG; v1 für alte Läufe)
//
// Anfrage: {"id": 1, "cmd": "...", ...}. Antwort: {"id": 1, "ok": true, ...} oder {"id": 1, "ok": false, "fehler": "...", "code": "..."}.
//   hallo                         → Protokoll, Sim-Version und -Hash, Beobachtungs- und Aktionsschema, Belohnung, Szenarien, Gruppen
//   reset {seed, nr, szenario, gruppe, tage}   → erste Entscheidung der Fokusperson: beob, maske, info (keine Namen, keine ID in beob)
//   observe / actionMask          → aktuelle Beobachtung und Maske
//   step {aktion, vorspulen}      → aktion = Index (0 = warten) oder "regel"; Antwort: beob, maske, belohnung, teile, stunden,
//                                   beendet (Tod, Wegzug), abgeschnitten (Zeitlimit), grund, info (bei Ende: metrik, summe)
//   snapshot                      → {schnapp: n} (bleibt im Prozess); restore {schnapp: n}; freigeben {schnapp: n}
//   protokoll                     → Entscheidungen der laufenden Episode (Tag, Stunde, Anlass, Maske, gewählt, Art, Grund, Folge)
//   close                         → beendet den Prozess
// Technische Fehler (Ausnahme in der Sim, verletzte Invariante, verletzte Maske) kommen als ok: false mit code; sie sind kein Episodenende.
import { createInterface } from 'node:readline';
import { ladeSim } from './simkern.mjs';
import { Umgebung, PROTOKOLL, SZENARIEN, GRUPPEN } from './kiepisode.mjs';

const args = process.argv.slice(2);
const i = args.indexOf('--html'), ib = args.indexOf('--belohnung');
const { Sim, simHash, pfad } = ladeSim(i >= 0 ? args[i + 1] : undefined);
const U = new Umgebung(Sim, { belohnung: ib >= 0 ? args[ib + 1] : undefined });
const schnapp = new Map();
let schnappNr = 0;

function hallo() {
  const K = Sim.KI;
  return { protokoll: PROTOKOLL, sim: { version: Sim.VERSION, hash: simHash, datei: pfad },
    beobachtung: { schemaVersion: K.SCHEMA, laenge: K.MERKMALE.length, merkmale: K.MERKMALE.map(m => m[0]), skalen: K.MERKMALE.map(m => m[1]),
      bedeutung: K.MERKMALE.map(m => m[2]) },
    aktionen: K.AKTIONEN, schemaHash: K.schemaHash(), schemaText: K.schemaText(), belohnung: U.B,
    szenarien: Object.fromEntries(Object.entries(SZENARIEN).map(([k, v]) => [k, v.beschreibung])), gruppen: Object.keys(GRUPPEN) };
}
function bearbeite(q) {
  switch (q.cmd) {
    case 'hallo': return hallo();
    case 'reset': return U.reset({ seed: q.seed, nr: q.nr || 0, szenario: q.szenario || 'stabil', gruppe: q.gruppe || 'alle', tage: q.tage });
    case 'observe': return U.observe();
    case 'actionMask': return { maske: U.observe().maske };
    case 'step': return U.step(q.aktion, { vorspulen: q.vorspulen !== false });
    case 'snapshot': { const n = ++schnappNr; schnapp.set(n, U.snapshot()); return { schnapp: n }; }
    case 'restore': { const k = schnapp.get(q.schnapp); if (!k) throw new Error('unbekannter Schnappschuss ' + q.schnapp); U.restore(k); return U.observe(); }
    case 'freigeben': return { geloescht: schnapp.delete(q.schnapp) };
    case 'protokoll': return { log: U.epi ? U.epi.log : [], metrik: U.epi ? U.epi.metrik : null };   // je Entscheidung: gewählt, Art, Folge
    case 'close': setImmediate(() => process.exit(0)); return {};
    default: throw new Error('unbekannter Befehl ' + q.cmd);
  }
}
const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', (zeile) => {
  if (!zeile.trim()) return;
  let q = null, antwort;
  try {
    q = JSON.parse(zeile);
    antwort = Object.assign({ id: q.id, ok: true }, bearbeite(q));
  } catch (e) {
    antwort = { id: q && q.id, ok: false, fehler: String((e && e.message) || e), code: (e && e.code) || 'fehler' };
  }
  process.stdout.write(JSON.stringify(antwort) + '\n');
});
rl.on('close', () => process.exit(0));
