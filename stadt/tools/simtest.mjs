#!/usr/bin/env node
// Entwicklungswerkzeug, nicht Teil des Produkts.
// Zieht den <script id="sim">-Block aus stadt.html, führt ihn in einem leeren Kontext aus
// (kein window, kein document, kein fetch, kein THREE; Math.random, Date und Intl gesperrt;
// vorher eine statische Suche nach verbotenen Namen)
// und simuliert N Spieltage. Nur Node-Standardbibliothek.
//
//   node tools/simtest.mjs --seed 1 --tage 365      Tabelle alle 30 Tage + Charakter-Auswertung
//   node tools/simtest.mjs --gate                   Phase-0-Gate mit Seeds 1, 2, 3 (je 730 Tage)
//   node tools/simtest.mjs --speichertest           Speichern/Laden mitten am Tag: läuft danach bitgleich weiter?
//   node tools/simtest.mjs --aufholtest             90 Tage stündlich gegen 90 Tagesschritte
//   node tools/simtest.mjs --kitest                 Hauptfiguren: erlaubte Aktionen, Anfragen, Fristen, Tagebuch (ohne echtes Modell)
//   node tools/simtest.mjs --bau                    Bauhof: Einteilung, Fortschritt je Person, jede Baustelle wird fertig (Seeds 1–3)
//   node tools/simtest.mjs --waren                  Kisten: geliefert ≤ gemacht, Werkstatt-Einnahmen wie vorher (Seeds 1–3)
//   node tools/simtest.mjs --tech                   Tech-Firmen: Arbeitstage an der Version, Käufe im Laden, Anbau (Seeds 1–3, 730 Tage)
//   node tools/simtest.mjs --regierung              Stadtregierung: Lohnsteuer (Freibetrag, Familiensplitting, Rentner-Freibetrag), Rentenkasse,
//                                                   Betreuungsgehalt, Grundsicherung und gemeinnützige Arbeit (erzwungen, auch Bauhof voll), Prämie,
//                                                   Wohnungsvorbehalt beim Zuzug, Tageswerte „gestern“, Speicherformat; Schritt 2: Beitragstage,
//                                                   Renteneintritt vor 67 und mit 67 (erzwungen), Mieterkauf (Rate, Erbe, Auflösung, Umzug,
//                                                   Zusammenziehen, Wegzug, Invariante, Budgetbuchungen); Betreuungsgehalt nur ohne Kita-Platz (Seeds 1–3)
//   node tools/simtest.mjs --kita                   Kitas (Schritt 2): Invarianten nach jeder Nacht, auch am Ende der Nacht (Plätze, Bestand, Personal,
//                                                   Lohn, Vorrang, Betreuungspflicht, Betreuungsgehalt nur ohne Platz, gebunden → keine Stellensuche),
//                                                   erzwungen: Kitas ohne Personal verlangen nichts, Personalabgang (höchstens 8 Einheiten je Nacht weg),
//                                                   Elternteil verliert die Stelle (Krippenplatz weg, dann Betreuungsgehalt), Besitzer-Haushalt bei vollen
//                                                   Kitas (Seeds 1–3)
//   node tools/simtest.mjs --migrationstest         Spielstände von Version 2, 3, 4, 5 und 6 übernehmen (alte stadt.html aus git 39c405b, 2b821c2,
//                                                   1c8d40b, 414ebab und bc7247a, --git ordner für ein anderes Repository, oder nur --alt pfad/zur/alten/stadt.html),
//                                                   erste Nacht (Käufe), Kita-Frist und die Nächte danach (Schwelle), 60 Tage weiter, keine NaN;
//                                                   beschädigte Stände der Version 5 werden abgelehnt; jede Version bekommt „Stadt erweitern“ (Stufe,
//                                                   Stadtteile, Karte); aus Version 6 läuft die Stadt danach 60 Tage lang genau wie in Version 6
//   node tools/simtest.mjs --erweiterung            Stadt erweitern (Version 7): statisch (kein Zufall, von Personen nur lebt und wohnung, Stadtteile
//                                                   nur zum Benennen und Anzeigen); Seeds 1–3 je 730 Tage jeden Tag wie Version 6 (git bc7247a oder
//                                                   --v6 datei), die Grenze hält nie eine Straße auf, Vorlauf, Wachsen, Stufe am ersten Tag über der
//                                                   Schwelle, Stadtteile, Zähler; Speichern und Laden über ein Wachsen hinweg bitgleich; beschädigte
//                                                   Stände abgelehnt; Übernahme von Version 6 (Dorf, Seeds 1–3); Gelände; mit --gross die große Stadt
//   node tools/simtest.mjs --sicherheit             Sicherheit (Version 7): statisch (Zufall, gelesene Personenfelder je Regel, Landeslöhne nicht aus dem
//                                                   Budget), Namenstausch bitgleich; Invarianten nach jeder Nacht (Haft, U-Haft, Plätze, Hofzeiten, Obhut,
//                                                   Wache ab Kleinstadt, Anstalt ab Stadt, Stadtbuch ohne Namen); erzwungene Urteile (Ersatzfreiheitsstrafe,
//                                                   Anrechnung, Tilgung, Widerruf, Randfall U-Haft), volle Anstalt, Obhut, Grundsicherung, Arbeitsentgelt;
//                                                   Speichern mit Haft; beschädigte Stände; Messung gegen die PKS 2024 und nach Gruppen (nur gemessen)
//   node tools/simtest.mjs --militaer               Bund (Version 7, Teil 3): statisch (kein Zufall, gelesene Personenfelder je Regel, keine Namen, kein
//                                                   Geschlecht, Löhne und Sold nicht aus dem Budget, Ersatzdienst ohne Kisten, Grenze: die Dienststelle
//                                                   liest niemanden), Namenstausch bitgleich; Invarianten nach jeder Nacht (Kaserne ab Stadt, Dienststelle
//                                                   ab Großstadt auf eigenem Gelände, Rollen, Stellen, Obergrenzen, Einberufung mit 18 erst ab dem Tag nach
//                                                   der Eröffnung und vollständig, genau 5 Diensttage, Bindung der Soldaten auf Zeit, Geld vom Bund,
//                                                   Stadtbuch ohne Namen); erzwungen: Tod, Haft, Wegzug im Dienst, Bindung, Gehirn, Einberufung, Bauhof voll,
//                                                   leeres Budget, ausgeschaltet; Speichern und Laden; beschädigte Stände; Messung (nur gemessen)
//   node tools/simtest.mjs --autos                  Tech-Firmen und Autos (Version 8): statisch (Zufall nur aus S.rsAuto, gelesene Personenfelder je
//                                                   Regel, keine Namen, Geschlecht nur fürs Pronomen), Namenstausch bitgleich; Invarianten je Nacht und
//                                                   Stunde (höchstens AUTO_MAX Werke, Werk auf eigenem Gelände, Stufen, 40-%-Grenze, Umzug, Fertigung,
//                                                   Käufe mit Reserve, Werk vor Umland, Umland ab Tag 0, Teile, laufende Kosten und CO₂, Verschrotten,
//                                                   Geldnot, Eröffnung, Grundregel für Autos, Testfahrt, faire Reihenfolge); erzwungen: Erbe, Geldnot,
//                                                   Haft, AUTO_MAX bei Übernahme; Speichern mitten im Werksbau bitgleich; beschädigte Stände (Seeds 1–3)
//   node tools/simtest.mjs --rathaus                Rathaus (Version 9): statisch (kein Zufall, keine Personen außer „frei“ für die Anzeige, Budget nur in
//                                                   rathausBezahlen); Invarianten nach jeder Nacht mit Gegenrechnung der Löhne (Seeds 1–3, 730 Tage);
//                                                   Speichern im Ausbau bitgleich, Aufholen; Übernahme von Version 8 (stadt.orig.html) und mit --git 7 und 6:
//                                                   nur Brache und höchstens ein Park; Park weicht dem Rathaus (erzwungen); beschädigte Stände; Namenstausch;
//                                                   mit R.RATHAUS = 0 Tag für Tag wie Version 8
//   node tools/simtest.mjs --buergermeister         Bürgermeister (Version 9): statisch (Wahl liest keine Namen, keine Herkunft, keinen Einzugstag, keine
//                                                   Eltern, kein Geschlecht; Zufall nur wahlZufall), Namenstausch bitgleich; Invarianten nach jeder Nacht;
//                                                   erzwungen: Tod, Haft, Wegzug im Amt, eigener Platz der Hauptfigur, Abwahl, Wählbarkeit; Rangfolge der
//                                                   Vorhaben mit Testvorhaben (Anfrage, Antworten, Frist, KI aus, Aufholen, Speichern); beschädigte Stände;
//                                                   Messung nach Gruppen (nur gemessen)
//   node tools/simtest.mjs --schule                 Schule (Version 9, Teil 2): statisch (Regeln lesen nur Alter, Wohnung, Obhut, Schulplatz; kein Zufall;
//                                                   Budget nur für Bau, Computer und Sachaufwand); Invarianten nach jeder Nacht (Plätze, Lehrkräfte, Geld,
//                                                   Lebenslauf, Bau erst ab einer Klasse, Kita, Dienst, Haft, Autos, Grundregel); Computer für die Schulen
//                                                   (Schnittstelle zum Haushalt, erzwungen); Speichern, beschädigte Stände; Übernahme von Version 8 und mit
//                                                   --git 7 bis 2; Namenstausch; ausgeschaltet; Gruppen (nur gemessen)
//   node tools/simtest.mjs --haushalt               Haushalt (Version 9, Teil 3): statisch (liest keine Personen, kein Zufall; jede Änderung des Budgets
//                                                   bucht; Lohnsteuer mit dem Satz des Haushalts); jede Stunde Konten = Budget; jede Nacht Vorhaben
//                                                   (Bedarf, Rücklage, Bauhof, je Vorhaben höchstens eins), Jahresabschluss mit Plan und Lohnsteuer
//                                                   nachgerechnet; Rangfolge des Bürgermeisters und Vorrang (erzwungen); Lohnsteuer erzwungen; Speichern;
//                                                   Übernahme von Version 8 (mit --git 7 bis 2); beschädigte Stände; ausgeschaltet; Namenstausch
//   node tools/simtest.mjs --wachstum               Wachstum, Tempo und KI (Version 9, Teil 4): statisch (Wachstum würfelt nicht, liest keine Person);
//                                                   ohne Anlauf Tag für Tag wie Version 8 (alle Bausteine von Version 9 aus) und mit --alt datei wie die
//                                                   Fassung davor; Anlauf je Nacht (Stelle nach der Regel, Grenze, Zählung ohne Kita- und Schulstellen,
//                                                   Anfragen); Schalter (Stadtbuch, Speichern, Übernahme, beschädigte Stände, „schnell“ wirkt); KI-Frist
//                                                   (Klemmen, Verlängern, späte Antwort, Rangfolge bis 23 Uhr); Kapazität der Warteschlange (nur gemessen)
//   node tools/simtest.mjs --techfrueh             Tech-Firmen früher und mehr (Version 9, Teil 5): statisch (würfelt nicht, liest von Personen nur Fleiß,
//                                                   Ehrgeiz, Geld, Wohnung; Karten passen zu R); ausgeschaltet Tag für Tag wie 31ce452 und mit --alt datei wie
//                                                   die Fassung davor; je Gründung (Stufe, Bremse, Preis, Markt, Tüftler im Dorf), je Nacht (Zählungen,
//                                                   Preis und Grenze der Welt, 40 % nur im Umland), Aufgabe ohne je eine Kraft, Computer der Schulen (Laden
//                                                   oder außerhalb); Speichern, beschädigte Stände, Übernahme von Version 8; Namenstausch; Gruppen (gemessen)
//   node tools/simtest.mjs --kipolicy               KI-Policy (Etappe 1, V9): Policy aus = bitgleich zu --orig (jeden Tag), Beobachtung ohne verbotene
//                                                   Felder, Maske nie verletzt, Fokus-ID und Generation, Wegzug und Tod, Schnappschuss, beschädigte
//                                                   Policy-Dateien, Rückfall, Policy für alle deterministisch (--orig <ungepatchte stadt.html>, --tage 730,
//                                                   --seeds 1,2,3, --policy ki/policy_x.json; ohne --policy: eingebettete oder künstliche Policy)
//   Optionen: --alle 30 (Zeilenabstand), --buch 20 (letzte Stadtbuch-Zeilen), --aktionen

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { performance } from 'node:perf_hooks';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const hier = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(hier, '..', 'stadt.html'), 'utf8');
const treffer = html.match(/<script id="sim">([\s\S]*?)<\/script>/);
if (!treffer) { console.error('Kein <script id="sim"> in stadt.html gefunden.'); process.exit(2); }
const SIM_CODE = treffer[1];

// Statische Prüfung: Kommentare entfernen, dann nach Namen suchen, die im sim-Block nichts zu suchen haben.
// Fängt auch Zugriffe, die im Lauf nie ausgeführt würden (z. B. hinter einem typeof-Test).
const VERBOTEN = /\b(window|document|fetch|THREE|localStorage|sessionStorage|indexedDB|performance|requestAnimationFrame|setTimeout|setInterval|XMLHttpRequest|Intl|Date|crypto|navigator|location|console)\b|Math\.random/;
function statischPruefen(code) {
  const ohneKommentare = code.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
  const zeilen = ohneKommentare.split('\n');
  const treffer = [];
  zeilen.forEach((z, i) => { const m = z.match(VERBOTEN); if (m) treffer.push(`  Zeile ${i + 1} im sim-Block: ${m[0]} → ${z.trim().slice(0, 100)}`); });
  if (treffer.length) { console.error('Der sim-Block benutzt Verbotenes:\n' + treffer.join('\n')); process.exit(3); }
}
statischPruefen(SIM_CODE);

function ladeSim() { return ladeSimMit([]).Sim; }
// Für Messungen: dieselbe Simulation mit eingefügten Zeilen, die in globalThis mitschreiben ([alt, neu], alt genau einmal im Code)
function ladeSimMit(ersetzen) {
  let code = SIM_CODE;
  for (const [alt, neu] of ersetzen) {
    if (code.split(alt).length !== 2) throw new Error('Stelle für die Messung nicht eindeutig: ' + alt.slice(0, 60));
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
  return { Sim: ctx.StadtSim, ctx };
}

// ─── Argumente ───
const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const flag = (n) => args.includes('--' + n);

const f0 = (v) => Math.round(v).toString();
const pad = (s, n) => String(s).padStart(n);

// Simuliert einen Seed. Ruft proTag(S, k, ms) nach jedem Spieltag auf.
function lauf(Sim, seed, tage, proTag) {
  const S = Sim.neueStadt(seed);
  const t0 = performance.now();
  for (let d = 0; d < tage; d++) {
    const ziel = S.tag + 1;
    while (S.tag < ziel) Sim.stunde(S);
    proTag(S, Sim.kennzahlen(S), performance.now() - t0);
  }
  return S;
}

function charakter(S) {
  const st = S.stat;
  const erwE = st.erwEhrgeiz / st.erwachsene, erwH = st.erwHeimat / st.erwachsene;
  const grE = st.gruendungen ? st.gruenderEhrgeiz / st.gruendungen : NaN;
  const wzH = st.wegzuege ? st.wegzugHeimat / st.wegzuege : NaN;
  // Zusätzlich: heutige Erwachsene (strengere Vergleichsgruppe ist die obige: alle, die je erwachsen hier waren)
  const P = S.p;
  let n = 0, sE = 0, sH = 0;
  for (let p = 0; p < S.pMax; p++) {
    if (!P.lebt[p] || S.tag - P.geb[p] < 18 * Sim.R.JAHR) continue;
    n++; sE += P.ehrgeiz[p]; sH += P.heimat[p];
  }
  return { erwN: st.erwachsene, erwE, erwH, grN: st.gruendungen, grE, wzN: st.wegzuege, wzH,
    jetztN: n, jetztE: n ? sE / n : NaN, jetztH: n ? sH / n : NaN };
}

function tabelleKopf() {
  return '   Tag  Einw.  Geb.  Gründ.  Pleiten  frW  frSt  Zufr.  Budget   Laufzeit';
}
function tabelleZeile(k, ms) {
  return `${pad(k.tag, 6)} ${pad(k.einwohner, 6)} ${pad(k.gebaeude, 5)} ${pad(k.gruendungen, 7)} ${pad(k.pleiten, 8)} `
    + `${pad(k.freieWohnungen, 4)} ${pad(k.freieStellen, 5)} ${pad(f0(k.zufriedenheit), 6)} ${pad(f0(k.budget), 7)} `
    + `${pad(f0(ms), 7)} ms`;
}

function charakterText(c) {
  const dE = c.grE - c.erwE, dH = c.wzH - c.erwH;
  return [
    `  Gründer:      n=${c.grN}, Ehrgeiz Ø ${c.grE.toFixed(1)}  |  alle je Erwachsenen n=${c.erwN}, Ø ${c.erwE.toFixed(1)}  →  ${dE >= 0 ? '+' : ''}${dE.toFixed(1)}  (Gate ≥ +15)`,
    `  Weggezogene:  n=${c.wzN}, Heimatliebe Ø ${c.wzH.toFixed(1)}  |  alle je Erwachsenen Ø ${c.erwH.toFixed(1)}  →  ${dH >= 0 ? '+' : ''}${dH.toFixed(1)}  (Gate ≤ −15)`,
    `  (heutige Erwachsene n=${c.jetztN}: Ehrgeiz Ø ${c.jetztE.toFixed(1)}, Heimatliebe Ø ${c.jetztH.toFixed(1)})`,
  ].join('\n');
}

const Sim = ladeSim();
// Haushalt (Version 9, Teil 3): Setzt ein erzwungener Fall das Budget von Hand, rückt der Start der Konten mit (sonst stimmten die Konten nicht mehr
// mit dem Budget überein, und der nächste Stand würde als beschädigt abgelehnt)
const budgetSetzen = (S, v) => { if (S.haushalt) S.haushalt.kasseStart += v - S.budget; S.budget = v; };

// Wie der Browser speichert: typisierte Arrays als Base64 in JSON (hier mit Buffer statt btoa/atob)
function speichernAlsText(Sim, S) {
  const d = Sim.exportZustand(S);
  return JSON.stringify({ ...d, arrays: d.arrays.map(a => ({ name: a.name, typ: a.typ,
    b64: Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength).toString('base64') })) });
}
const TYPEN = { Uint8Array, Uint16Array, Int16Array, Int32Array, Uint32Array, Float32Array, Float64Array };
function ladenAusText(Sim, text) {
  const d = JSON.parse(text);
  d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); const buf = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](buf) }; });
  return Sim.importZustand(d);
}
function fingerabdruck(Sim, S) {
  const h = createHash('sha256');
  const arrays = Sim.exportZustand(S).arrays.sort((x, y) => (x.name < y.name ? -1 : 1));   // Schlüsselreihenfolge egal
  for (const a of arrays) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
  h.update(JSON.stringify(S.buch)); h.update(JSON.stringify(S.stat)); h.update(JSON.stringify(S.ki)); h.update(String(S.budget) + '/' + S.rs + '/' + S.tag + '/' + S.stunde);
  if (S.regierung) h.update(JSON.stringify(S.regierung));  // Stadtregierung: Start und Tageswerte (gestern, Summen am Tagesende)
  // Stadt erweitern (Version 7): Kartengröße, Mitte, Viertel, alle anderen Einzelwerte, Stufe, Stadtteile, Gelände, Wachsen, Straßenenden
  if (S.erweiterung) { h.update(JSON.stringify(Sim.exportZustand(S).werte)); h.update(JSON.stringify(S.erweiterung)); h.update(JSON.stringify(S.enden)); h.update(JSON.stringify(S.kreuzungen)); }
  if (S.sicherheit) h.update(JSON.stringify(S.sicherheit));  // Sicherheit (Version 7): Wache, Anstalt, Stellen, Verfahren, Tatorte, Jahreswerte (rsSich steht in werte)
  if (S.bund) h.update(JSON.stringify(S.bund));              // Bund (Version 7, Teil 3): Kaserne, Dienststelle, Eröffnung, Einberufungen im Jahr, Geld von gestern
  if (S.rathaus) h.update(JSON.stringify(S.rathaus));        // Rathaus: Gebäude, Stellen, Budget und Kosten von gestern
  if (S.buergermeister) h.update(JSON.stringify(S.buergermeister));   // Bürgermeister: Amt, Wahl, Rangfolge, Anfrage
  if (S.schule) h.update(JSON.stringify(S.schule));          // Schule (Version 9): Schuljahr, Geld von gestern, Computer
  if (S.haushalt) h.update(JSON.stringify(S.haushalt));      // Haushalt (Version 9, Teil 3): Konten, Plan, Satz, Jahre
  return h.digest('hex').slice(0, 16);
}

// Stadt erweitern (Version 7): eine Stadt ohne ihre Lage auf der Karte (Kennzahlen, Zufall, Zähler, Felder und Gebäude relativ zur Mitte,
// dazu alle Personenfelder, alle Gebäudefelder außer der Lage, Statistik, Hauptfiguren und Stadtregierung), zum Vergleich derselben Stadt
// auf der festen Karte (bis Version 6: 96 × 96, Mitte 48) und auf der wachsenden Karte. Sicherheit (Version 7): Ihre Personenfelder und
// Summen gibt es in Version 6 nicht; sie bleiben außen vor. Verglichen wird dann mit ausgeschalteter Sicherheit (sicherheitAus). Bund (Teil 3):
// ebenso (Personenfelder bund, dienstBis; Summen S.stat.bund); sicherheitAus schaltet auch den Bund aus
// Version 8: dazu besuch (nur für Figuren und Autos: ab 19 Uhr fest, wirkt auf nichts in der Stadt)
const OHNE_SICH = new Set([...Sim.PF_SICHERHEIT, ...(Sim.PF_BUND || []), ...(Sim.PF_AUTO || []), 'besuch', ...(Sim.PF_SCHULE || [])]);   // Version 9: Schulplatz (gibt es vorher nicht)
const OHNE_G = new Set([...(Sim.GF_AUTO || []), ...(Sim.GF_TECH9 || [])]);   // Version 8: Gebäudefelder der Autos und Tech-Firmen; Version 9, Teil 5: Markt, Kraft (gibt es vorher nicht)
// Sicherheit, Bund und (Version 8) Autos ausschalten (keine Taten, Land und Bund bauen nicht, keine Wehrpflicht; niemand kauft ein Auto, Tech-Firmen
// bis Stufe 3, keine Autowerke, 40-%-Grenze wie in Version 7): für den Vergleich mit Version 6 und 7; gibt eine Funktion zurück, die alles
// wieder einschaltet
const AUS = ['KRIM_BASIS', 'LAND_BAUT', 'BUND_BAUT', 'WEHRPFLICHT', 'AUTO_CHANCE', 'AUTO_MAX', 'TECH_GRENZE_HALTEN', 'RATHAUS', 'SCHULEN', 'HH_VORHABEN', 'HH_STEUER',
  'ANLAUF_STUFE', 'TECH_FRUEH', 'WELT', 'ZUZUG_GENAU'];   // Rathaus, Schulen, Vorhaben und Lohnsteuer des Haushalts, Anlauf, Tech früher und Weltmarkt, Zuzug genau nach R10 (Version 9): für Vergleiche mit älteren Versionen aus
const sicherheitAus = (X, nurAutos) => { const R = X.R, alt = AUS.map(k => R[k]);
  for (const k of nurAutos ? AUS.slice(4) : AUS) if (k in R) R[k] = 0;
  const stufe = R.TECH_STUFE_MAX; if (stufe !== undefined) R.TECH_STUFE_MAX = 3;
  return () => { AUS.forEach((k, i) => { R[k] = alt[i]; }); if (stufe !== undefined) R.TECH_STUFE_MAX = stufe; }; };
// Version 8: Summen ohne die neuen (Autos; CO₂ in der Stadtregierung), zum Vergleich mit Version 6 und 7
const ohneCo2 = (o) => (o && typeof o === 'object' ? Object.fromEntries(Object.entries(o).filter(([k]) => k !== 'co2')) : o);
// Version 9, Teil 5: ohne die neuen Summen (aufgegeben; welt und aufgegeben der Tech-Firmen)
// Schlussprüfung von Version 9: nur Wortlaut (zweiter Wahlgang in der Wahlzeile, Stellen im Dorf in der Zuzugszeile); für Vergleiche mit älteren Fassungen
const textAlt = (t) => t.replace(' im zweiten Wahlgang', '').replace(/im Laden, in Werkstätten und Tech-Firmen(?:,| oder) im Bauhof/, 'in Betrieben und im Bauhof');
const techAlt = (t) => (t && typeof t === 'object' ? Object.fromEntries(Object.entries(t).filter(([k]) => k !== 'welt' && k !== 'aufgegeben')) : t);
const statAlt = (st) => ({ ...st, sicherheit: undefined, bund: undefined, auto: undefined, rathaus: undefined, buergermeister: undefined, schule: undefined, regierung: ohneCo2(st.regierung),
  aufgegeben: undefined, tech: techAlt(st.tech) });   // Version 9: ohne Rathaus, Bürgermeister und Schule; Teil 5: ohne die neuen Summen
const regierungAlt = (r) => (r ? { ...r, tagStart: ohneCo2(r.tagStart), gestern: ohneCo2(r.gestern) } : null);
// Version 9, Teil 4: die KI-Frist in Spielstunden gibt es vorher nicht (ohne Oberfläche steht sie fest auf R.KI_FRIST)
const kiAlt = (k) => (k ? { ...k, fristStunden: undefined } : k);
function spurRelativ(Sim, S) {
  const k = Sim.kennzahlen(S), K = S.karte || 96, M = S.mitte || 48;
  let h = 0, gb = 0;
  for (let c = 0; c < K * K; c++) if (S.feld[c] !== 0) h = (Math.imul(h, 31) + ((c % K) - M) * 1000 + (((c / K) | 0) - M) * 7 + S.feld[c]) | 0;
  for (let b = 0; b < S.gAnzahl; b++) gb = (Math.imul(gb, 17) + (S.g.x[b] - M) * 131 + (S.g.y[b] - M) + S.g.typ[b] * 7919) | 0;
  // Personen und Gebäude hängen nicht an Feldern (nur g.x und g.y): Byte für Byte, soweit belegt
  const hp = createHash('sha256'), teil = (a, n, kap) => { const w = kap > 0 ? a.length / kap : 1, u = a.subarray(0, n * w); hp.update(Buffer.from(u.buffer, u.byteOffset, u.byteLength)); };
  for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n]) && !OHNE_SICH.has(n)) { hp.update(n); teil(S.p[n], S.pMax, S.pKap); }
  for (const n of Object.keys(S.g).sort()) if (n !== 'x' && n !== 'y' && !OHNE_G.has(n) && ArrayBuffer.isView(S.g[n])) { hp.update(n); teil(S.g[n], S.gAnzahl, 0); }
  hp.update(JSON.stringify(statAlt(S.stat))); hp.update(JSON.stringify(kiAlt(S.ki))); hp.update(JSON.stringify(regierungAlt(S.regierung)));
  return JSON.stringify([k.tag, k.stunde, k.einwohner, k.gebaeude, k.budget, k.gruendungen, k.pleiten, k.freieWohnungen, k.freieStellen, k.zufriedenheit,
    k.arbeitslose, S.rs, h, gb, S.gAnzahl, S.stat.zuzuege, S.stat.geburten, S.stat.tode, S.stat.strassenFelder, S.bauplaetze, hp.digest('hex').slice(0, 16)]);
}

if (flag('speichertest')) {
  const seed = Number(arg('seed', '1')), tage = Number(arg('tage', '150'));
  const bis = (S, tag, stunde) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) Sim.stunde(S); };
  const A = Sim.neueStadt(seed); bis(A, tage, 13);
  const text = speichernAlsText(Sim, A);
  const B = ladenAusText(Sim, text);
  console.log(`Seed ${seed}: gespeichert an Tag ${A.tag}, ${A.stunde} Uhr; Spielstand ${(text.length / 1e6).toFixed(2)} MB (${A.einwohner} Einwohner)`);
  console.log(`  direkt nach dem Laden gleich: ${fingerabdruck(Sim, A) === fingerabdruck(Sim, B) ? 'ja' : 'NEIN'}`);
  bis(A, tage + 60, 13); bis(B, tage + 60, 13);
  const fa = fingerabdruck(Sim, A), fb = fingerabdruck(Sim, B);
  console.log(`  60 Tage weiter: ununterbrochen ${fa} (${A.einwohner} Einw.), geladen ${fb} (${B.einwohner} Einw.) → ${fa === fb ? 'bitgleich' : 'UNTERSCHIEDLICH'}`);
  // Sicherheit (Version 7): ein Stand mit Untersuchungshaft, offenen Verfahren, Gefangenen in der Anstalt in der Stadt und einem Kind in Obhut.
  // Gesucht wird ein Tag, an dem jemand in U-Haft sitzt (13 Uhr, ab Tag 250); die Anstalt belegt der Test zusätzlich mit einer Strafhaft, das
  // Kind kommt in Obhut, wenn der einzige Erwachsene seines Haushalts in Haft geht. Vergleich auch über sortierte Schlüssel (JSON-Reihenfolge egal)
  const kanon = (o) => JSON.stringify(o, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) && !ArrayBuffer.isView(v) ? Object.fromEntries(Object.keys(v).sort().map(x => [x, v[x]])) : v));
  const sortiert = (S) => { const d = Sim.exportZustand(S), h = createHash('sha256');
    for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
    h.update(kanon(d.werte)); h.update(kanon(d.json)); return h.digest('hex').slice(0, 16); };
  const C = Sim.neueStadt(seed);
  bis(C, 250, 13);
  const uhaft = (S) => { for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.haftBis[p] && S.p.haftArt[p] === Sim.HAFT_U) return p; return -1; };
  // alle Erwachsenen eines Haushalts mit Kind, ohne Betrieb, gehen in Strafhaft (gesucht wird ein Tag, an dem es auch so einen Haushalt gibt;
  // seit Teil 3 gibt es an Seed 1 am ersten Tag mit U-Haft keinen)
  const elternVon = (C) => { const P = C.p, erw = C.tag - Sim.R.ERWACHSEN * Sim.R.JAHR;
    for (let k = 0; k < C.pMax; k++) {
      if (!P.lebt[k] || P.hh[k] !== k || !C.hhKinder[k] || P.wohnung[k] < 0) continue;
      const e = C.bewohner[P.wohnung[k]].filter(m => P.hh[m] === k && P.geb[m] <= erw);
      const kind = C.bewohner[P.wohnung[k]].some(m => P.hh[m] === k && P.geb[m] > erw);   // hhKinder zählt von der letzten Nacht (wer heute 18 ist, noch mit)
      if (e.length && kind && e.every(m => P.besitz[m] < 0 && !P.haftBis[m])) return e;   // mindestens ein Erwachsener und ein Kind
    }
    return null; };
  while (C.tag < 700 && (uhaft(C) < 0 || !C.sicherheit.verfahren.length || !Sim.sicherheitInfo(C).jvaOffen || !elternVon(C))) bis(C, C.tag + 1, 13);
  const eltern = elternVon(C);
  if (eltern) { for (const m of eltern) Sim._sich.haftAntritt(C, m, 8, Sim.HAFT_STRAF); Sim._sich.obhutPruefen(C); }
  const iC = Sim.sicherheitInfo(C), textC = speichernAlsText(Sim, C), D = ladenAusText(Sim, textC);
  const gleich0 = fingerabdruck(Sim, C) === fingerabdruck(Sim, D) && sortiert(C) === sortiert(D);
  console.log(`Sicherheit: gespeichert an Tag ${C.tag}, ${C.stunde} Uhr: ${iC.uhaft} in U-Haft, ${iC.hier} in der Anstalt in der Stadt, ${iC.haft} in Haft, ${iC.verfahren} offene Verfahren, `
    + `${iC.obhut} Kind(er) in Obhut; direkt nach dem Laden gleich: ${gleich0 ? 'ja' : 'NEIN'}`);
  bis(C, C.tag + 60, 13); bis(D, D.tag + 60, 13);
  const fc = fingerabdruck(Sim, C), fd = fingerabdruck(Sim, D), sc = sortiert(C), sd = sortiert(D);
  const ok2 = gleich0 && iC.uhaft > 0 && iC.hier > 0 && iC.verfahren > 0 && iC.obhut > 0 && fc === fd && sc === sd;
  console.log(`  60 Tage weiter: ${fc} / ${fd}, sortiert ${sc} / ${sd} → ${fc === fd && sc === sd ? 'bitgleich' : 'UNTERSCHIEDLICH'}${ok2 ? '' : ' (FEHL: Fall nicht vollständig oder verschieden)'}`);
  // Bund (Version 7, Teil 3): ein Stand mit Wehr- und Ersatzdienst, verpflichteten Soldaten und offener Dienststelle (13 Uhr, ab Tag 400;
  // an Tag 150 gibt es noch keine Kaserne, Befund 1 der Gegenprüfung „militaer“)
  const E = Sim.neueStadt(seed);
  const bundDa = (S) => { const i = Sim.bundInfo(S); return i.wehr >= 1 && i.ersatz >= 1 && i.verpflichtet >= 1 && i.dienstOffen && i.nachrichtendienst >= 1; };
  bis(E, 400, 13);
  while (E.tag < 700 && !bundDa(E)) bis(E, E.tag + 1, 13);
  const iE = Sim.bundInfo(E), F = ladenAusText(Sim, speichernAlsText(Sim, E));
  const gleich3 = fingerabdruck(Sim, E) === fingerabdruck(Sim, F) && sortiert(E) === sortiert(F);
  console.log(`Bund: gespeichert an Tag ${E.tag}, ${E.stunde} Uhr: ${iE.soldaten} Soldaten (${iE.verpflichtet} verpflichtet), ${iE.zivil} Zivil, ${iE.wehr} im Wehr-, ${iE.ersatz} im Ersatzdienst, `
    + `${iE.nachrichtendienst} im Nachrichtendienst; direkt nach dem Laden gleich: ${gleich3 ? 'ja' : 'NEIN'}`);
  bis(E, E.tag + 60, 13); bis(F, F.tag + 60, 13);
  const fe = fingerabdruck(Sim, E), ff = fingerabdruck(Sim, F), se = sortiert(E), sf = sortiert(F);
  const ok3 = gleich3 && iE.wehr > 0 && iE.ersatz > 0 && iE.verpflichtet > 0 && fe === ff && se === sf;
  console.log(`  60 Tage weiter: ${fe} / ${ff}, sortiert ${se} / ${sf} → ${fe === ff && se === sf ? 'bitgleich' : 'UNTERSCHIEDLICH'}${ok3 ? '' : ' (FEHL: Fall nicht vollständig oder verschieden)'}`);
  process.exit(fa === fb && ok2 && ok3 ? 0 : 1);
}
if (flag('kitest')) {
  // Ohne Sprachmodell: ein Test-Beantworter mit eigenem Zufall antwortet gültig, ungültig oder gar nicht.
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  let t = 12345;
  const tz = () => { t = (t + 0x6D2B79F5) | 0; let x = Math.imul(t ^ (t >>> 15), 1 | t); x ^= x + Math.imul(x ^ (x >>> 7), 61 | x); return ((x ^ (x >>> 14)) >>> 0) / 4294967296; };
  for (const seed of [1, 2, 3]) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed);
    pruef(S.ki.haupt.length === Sim.R.HAUPT_START, `${S.ki.haupt.length} Hauptfiguren beim Start`);
    // 1. Das normale Gehirn wählt nie etwas, das erlaubteAktionen nicht kennt
    let geprueft = 0, abweichend = 0;
    while (S.tag < 200) {
      if (S.stunde === 7 || S.stunde === 18) {
        for (let p = 0; p < S.pMax; p += 3) {
          if (!S.p.lebt[p] || S.tag - S.p.geb[p] < Sim.R.ERWACHSEN * Sim.R.JAHR) continue;
          const erlaubt = Sim.erlaubteAktionen(S, p, S.stunde);
          const a = Sim.entscheide(S, p, S.stunde);
          geprueft++;
          if (a && !erlaubt.includes(Sim.AKTIONSNAMEN[a])) { abweichend++; if (abweichend < 4) console.log(`    Gehirn wählt ${Sim.AKTIONSNAMEN[a]}, erlaubt: ${erlaubt.join(', ')}`); }
        }
      }
      Sim.stunde(S);
    }
    pruef(abweichend === 0, `Gehirn ⊆ erlaubte Aktionen (${geprueft} Entscheidungen geprüft, ${abweichend} abweichend)`);
    // 1b. Der Lagesatz fürs Sprachmodell erkennt Arbeit nur an „arbeitet …“ / „besitzt …“ / „leistet gemeinnützige Arbeit …“ am Anfang;
    //     Bund (Teil 3): „leistet Wehrdienst …“ / „leistet Ersatzdienst …“ (der Lagesatz macht daraus „Du leistest …“)
    {
      let n = 0, falsch = 0, bau = 0, bauFalsch = 0, tech = 0, techFalsch = 0, dienst = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p] || S.tag - S.p.geb[p] < Sim.R.ERWACHSEN * Sim.R.JAHR || (S.p.arbeit[p] < 0 && S.p.besitz[p] < 0)) continue;
        const i = Sim.personInfo(S, p);
        n++; if (!/^(arbeitet als |besitzt |leistet gemeinnützige Arbeit |leistet (Wehrdienst|Ersatzdienst) )/.test(i.arbeit)) { falsch++; if (falsch < 3) console.log('    ' + i.arbeit); }
        if (S.p.bund[p] >= Sim.WEHRDIENST) { dienst++; if (!i.bund || !new RegExp('^leistet ' + (S.p.bund[p] === Sim.WEHRDIENST ? 'Wehrdienst in der Kaserne ' : 'Ersatzdienst beim Bauhof ')).test(i.arbeit)) falsch++; }
        // Wer schon einen eigenen Betrieb hat, der noch gebaut wird, arbeitet bis dahin weiter im Bauhof: Text „besitzt …“.
        // Gemeinnützige Arbeit (Stadtregierung) steht als „leistet gemeinnützige Arbeit beim Bauhof …“ da (prüft --regierung).
        if (S.p.arbeit[p] === S.bauhof && S.p.besitz[p] < 0) {
          bau++;
          if (!(S.p.gemein[p] ? /^leistet gemeinnützige Arbeit beim Bauhof / : S.p.bund[p] === Sim.ERSATZDIENST ? /^leistet Ersatzdienst beim Bauhof /
            : /^arbeitet als Bauarbeiter(in)? beim Bauhof /).test(i.arbeit)) bauFalsch++;
        }
        if (S.p.arbeit[p] >= 0 && S.g.typ[S.p.arbeit[p]] === Sim.TECH && S.p.besitz[p] < 0) { tech++; if (!/^arbeitet als Programmierer(in)? bei /.test(i.arbeit)) techFalsch++; }
      }
      pruef(n > 50 && falsch === 0 && bau > 0 && bauFalsch === 0 && techFalsch === 0, `Arbeitstext beginnt mit „arbeitet als“ oder „besitzt“ (${n} Leute mit Arbeit, davon ${bau} im Bauhof, ${tech} in Tech-Firmen, ${dienst} im Wehr- oder Ersatzdienst, ${falsch + bauFalsch + techFalsch} falsch)`);
    }
    // 2. 60 Tage mit Test-Beantworter
    S.ki.an = true;
    let anfragen = 0, gueltig = 0, ungueltig = 0, ohne = 0, maxProTag = 0, zuSpaet = 0, tbFalsch = 0, tbGeklappt = 0, freiJa = 0;
    const gesehen = new Set(), proTag = {};
    while (S.tag < 260) {
      for (const a of S.ki.anfragen.slice()) {
        if (gesehen.has(a.nr)) continue;
        gesehen.add(a.nr); anfragen++;
        const k = a.id + '/' + a.gen + '/' + a.tag;
        proTag[k] = (proTag[k] || 0) + 1; maxProTag = Math.max(maxProTag, proTag[k]);
        const r = tz();
        if (r < 0.7) {
          const aktion = a.erlaubt[(tz() * a.erlaubt.length) | 0];
          const ziel = tz() < 0.2 ? Sim.ZIELNAMEN[1 + ((tz() * 6) | 0)] : null;
          const e = Sim.kiEntscheidung(S, a.id, a.gen, aktion, ziel, 'Ich nehme ' + aktion + '.');
          if (e.ok) gueltig++; else zuSpaet++;
          // Befund Bedienung der Schlussprüfung: Das Tagebuch trägt, ob die Aktion geklappt hat (vorher immer „klappte nicht“)
          const tb = S.p.lebt[a.id] && S.p.gen[a.id] === a.gen ? S.ki.tagebuch[a.id + '/' + a.gen] : null, te = tb && tb[tb.length - 1];
          if (e.ok && te) { if (te.art !== 'gedanke' || te.geklappt !== e.ausgefuehrt) tbFalsch++; if (te.geklappt) tbGeklappt++; if (aktion === 'freinehmen' && te.geklappt) freiJa++; }
        } else if (r < 0.8) { Sim.kiVerwerfen(S, a.id, a.gen); ungueltig++; }
        else ohne++;                                          // keine Antwort: Frist läuft ab
      }
      Sim.stunde(S);
    }
    S.ki.an = false;
    pruef(anfragen > 50, `${anfragen} Anfragen in 60 Tagen (gültig ${gueltig}, ungültig ${ungueltig}, ohne Antwort ${ohne}, abgelaufen ${S.ki.abgelaufen})`);
    pruef(maxProTag <= Sim.R.KI_PRO_TAG, `höchstens ${maxProTag} Anfragen je Figur und Tag`);
    pruef(zuSpaet === 0, `keine Antwort auf eine nicht mehr offene Anfrage (${zuSpaet})`);
    pruef(tbFalsch === 0 && tbGeklappt > 0 && freiJa > 0, `Tagebuch: „geklappt“ steht im gespeicherten Eintrag (${tbGeklappt} geklappt, davon ${freiJa}× freinehmen; ${tbFalsch} falsch)`);
    const buecher = Object.values(S.ki.tagebuch);
    pruef(buecher.every(b => b.length <= Sim.R.TAGEBUCH), `Tagebücher höchstens ${Sim.R.TAGEBUCH} Einträge (${buecher.map(b => b.length).join(', ')})`);
    // 2b. Eine späte Antwort (Anfrage schon abgelaufen) darf keine neuere Anfrage derselben Figur beantworten
    {
      S.ki.an = true;
      while (S.stunde !== 18) Sim.stunde(S);
      Sim.stunde(S);
      const alt = S.ki.anfragen[0];
      if (alt) {
        Sim.stunde(S); Sim.stunde(S);                                  // Frist abgelaufen
        S.p.jetzt[alt.id] = 1; Sim.stunde(S);                          // Ereignis → neue Anfrage derselben Figur
        const neu = S.ki.anfragen.find(x => x.id === alt.id);
        const e = Sim.kiEntscheidung(S, alt.id, alt.gen, alt.erlaubt[0], null, 'spät', alt.nr);
        pruef(!e.ok && (!neu || S.ki.anfragen.includes(neu)), `späte Antwort auf Anfrage ${alt.nr} verworfen, neue Anfrage ${neu ? neu.nr : '–'} bleibt offen`);
        if (neu) Sim.kiVerwerfen(S, neu.id, neu.gen, neu.nr);
      }
      S.ki.an = false;
    }
    // 2c. Eine Anfrage, die die Oberfläche nicht mehr losschickt (keine Antwort vor der Frist möglich): Das normale Gehirn entscheidet sofort, statt
    //     bis zur Frist zu warten, und sie zählt als „zu spät“ (Befund Technik der Schlussprüfung)
    {
      S.ki.an = true;
      while (S.stunde !== 7) Sim.stunde(S);
      Sim.stunde(S);
      const a = S.ki.anfragen[0], ab0 = S.ki.abgelaufen;
      const ok = a ? Sim.kiVerwerfen(S, a.id, a.gen, a.nr, true) : false;
      pruef(!!a && ok && S.ki.abgelaufen === ab0 + 1 && !S.ki.anfragen.includes(a) && !S.ki.anfragen.some(x => x.id === a.id),
        `nicht gesendete Anfrage ${a ? a.nr : '–'}: sofort normal entschieden, „zu spät“ ${ab0} → ${S.ki.abgelaufen}, keine Anfrage der Figur mehr offen`);
      for (const x of S.ki.anfragen.slice()) Sim.kiVerwerfen(S, x.id, x.gen, x.nr);
      S.ki.an = false;
    }
    // 3. Hauptfiguren setzen und Grenzen
    const erw = []; for (let p = 0; p < S.pMax && erw.length < 20; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] >= 18 * Sim.R.JAHR && !Sim.istHaupt(S, p)) erw.push(p);
    for (const p of erw) if (S.ki.haupt.length < Sim.R.HAUPT_MAX) Sim.hauptSetzen(S, p, S.p.gen[p], true);
    const elf = erw.find(p => !Sim.istHaupt(S, p));
    pruef(!Sim.hauptSetzen(S, elf, S.p.gen[elf], true) && S.ki.haupt.length === Sim.R.HAUPT_MAX, `11. Hauptfigur wird abgelehnt (${S.ki.haupt.length} Hauptfiguren)`);
    // 4. Gespräch: Erinnerung, neues Ziel, Tagebuch
    const h = S.ki.haupt[0];
    const zielVor = S.p.ziel[h.id];
    const neuZiel = Sim.ZIELNAMEN[zielVor === 5 ? 2 : 5];          // freunde bzw. besserer_job: nie „schon erreicht“
    Sim.kiGespraech(S, h.id, h.gen, 'Wie geht es dir?', 'Gut, danke.', neuZiel);
    const info = Sim.personInfo(S, h.id, h.gen);
    pruef(Sim.ZIELNAMEN[S.p.ziel[h.id]] === neuZiel && info.gedaechtnis.at(-1).text === 'mit Noah geredet' && info.tagebuch.at(-1).art === 'gespraech',
      `Gespräch: Ziel ${Sim.ZIELNAMEN[zielVor]} → ${neuZiel}, Erinnerung „${info.gedaechtnis.at(-1).text}“, Tagebuch „${info.tagebuch.at(-1).noah}“`);
    // 4b. Ein Ziel, das schon erreicht ist, übernimmt die Figur nicht (sonst sofort „Ziel erreicht“)
    const erreicht = S.ki.haupt.map(x => x.id).find(p => S.p.bFreizeit[p] >= 70 && S.p.zuf[p] >= 55 && S.p.ziel[p] !== 6);
    if (erreicht !== undefined) {
      const zv = S.p.ziel[erreicht];
      Sim.kiGespraech(S, erreicht, S.p.gen[erreicht], 'Ruh dich aus.', 'Mach ich doch schon.', 'ruhe');
      pruef(S.p.ziel[erreicht] === zv, `schon erreichtes Ziel „ruhe“ abgelehnt (Ziel bleibt ${Sim.ZIELNAMEN[zv]})`);
    }
    // 4c. Code ins Tagebuch: nur wer in einer Tech-Firma arbeitet oder eine besitzt; bleibt nach Speichern/Laden erhalten
    {
      let prog = -1, anders = -1;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p] || S.tag - S.p.geb[p] < 18 * Sim.R.JAHR) continue;
        if (prog < 0 && Sim.techFirmaVon(S, p) >= 0) prog = p;
        if (anders < 0 && Sim.techFirmaVon(S, p) < 0) anders = p;
      }
      if (prog >= 0) {
        const nein = Sim.kiCode(S, anders, S.p.gen[anders], 'Test', 'JavaScript', 'let a = 1;', 'Ich teste.');
        const ja = Sim.kiCode(S, prog, S.p.gen[prog], 'Warenkorb zählen', 'JavaScript', 'const summe = preise.reduce((a, b) => a + b, 0);\nconsole.log(summe);', 'Das klappt.');
        const e = (S.ki.tagebuch[prog + '/' + S.p.gen[prog]] || []).at(-1);
        const B2 = ladenAusText(Sim, speichernAlsText(Sim, S));
        const e2 = (B2.ki.tagebuch[prog + '/' + B2.p.gen[prog]] || []).at(-1);
        pruef(!nein && ja && e.art === 'code' && e.code.includes('reduce') && e2 && e2.code === e.code, `Code nur für Programmierende (${Sim.name(S, prog)}), bleibt nach Speichern/Laden`);
      } else pruef(false, 'niemand arbeitet in einer Tech-Firma');
    }
    // 5. Tod einer Hauptfigur: Verlust mit Vorschlägen; Speichern und Laden behält alles
    while (S.tag < 900 && S.ki.verlust.length === 0) Sim.stunde(S);
    const v = S.ki.verlust[0];
    pruef(!!v, v ? `Verlust gemeldet: ${v.name} (${v.grund}), Vorschläge: ${v.vorschlaege.map(x => x.name + ' (' + x.rolle + ')').join(', ') || 'keine'}` : 'kein Verlust bis Tag 900');
    const B = ladenAusText(Sim, speichernAlsText(Sim, S));
    pruef(JSON.stringify(B.ki) === JSON.stringify(S.ki) && fingerabdruck(Sim, B) === fingerabdruck(Sim, S), 'Speichern/Laden behält Hauptfiguren, Tagebücher, Anfragen');
    // 6. Kitas (Schritt 2), erzwungen: Eine Hauptfigur hat ein Kind unter 6 im Haushalt und keine Stelle, der Partner arbeitet, sonst ist
    //    niemand da; das Kind hat keinen Platz und die Kitas in der Nähe sind voll (gebunden). Dann fehlen job_suchen und laden_gruenden in den erlaubten Aktionen und in der Anfrage ans
    //    Sprachmodell; die Personenkarte nennt den Grund. Ist in der Nähe ein Platz frei, ist job_suchen wieder dabei
    {
      const P = S.p, R = Sim.R, erw = S.tag - R.ERWACHSEN * R.JAHR, dist = (a, b) => Math.abs(S.g.x[a] - S.g.x[b]) + Math.abs(S.g.y[a] - S.g.y[b]);
      const offenK = (b) => S.g.typ[b] === Sim.KITA && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === Sim.KITA;
      while (S.stunde !== 6) Sim.stunde(S);
      let p = -1, kind = -1;
      for (let k = 0; k < S.pMax && p < 0; k++) {
        if (!P.lebt[k] || !P.kita[k] || S.tag - P.geb[k] < R.KRIPPE_BIS || S.tag + 1 - P.geb[k] >= R.KITA_ENDE) continue;
        const v = P.hh[k], pa = v >= 0 ? P.partner[v] : -1;
        if (v < 0 || pa < 0 || P.hh[pa] !== v || P.arbeit[v] < 0) continue;                        // Vorstand arbeitet, Partner im Haushalt
        if (P.besitz[pa] >= 0 || P.gemein[pa] || Sim.anspruch(S, pa) || S.tag - P.geb[pa] >= 60 * R.JAHR) continue;
        if (S.bewohner[P.wohnung[k]].some(m => m !== v && m !== pa && P.hh[m] === v && P.geb[m] <= erw)) continue;   // sonst niemand Erwachsenes
        p = pa; kind = k;
      }
      if (p < 0) pruef(false, 'Kita: kein Kind mit Platz bei einem Paar ohne weitere Erwachsene gefunden');
      else {
        if (P.arbeit[p] >= 0) { const L = S.belegschaft[P.arbeit[p]]; L.splice(L.indexOf(p), 1); P.arbeit[p] = -1; P.einsatz[p] = 0; }
        P.kita[kind] = 0;
        const nah = [];
        for (let b = 0; b < S.gAnzahl; b++) if (offenK(b) && dist(b, P.wohnung[p]) <= R.REICH_KITA) { nah.push(b); S.g.bedient[b] = S.g.kapaz[b]; }   // voll
        if (!Sim.istHaupt(S, p)) { if (S.ki.haupt.length >= R.HAUPT_MAX) S.ki.haupt.pop(); Sim.hauptSetzen(S, p, P.gen[p], true); }
        S.freieStellen = Math.max(1, S.freieStellen);
        const erl = Sim.erlaubteAktionen(S, p, 7), info = Sim.personInfo(S, p);
        S.ki.an = true; S.ki.anfragen.length = 0; S.ki.heute = {}; P.jetzt[p] = 1;
        Sim.stunde(S);                                         // 6 Uhr: Ereignis → Anfrage
        const a = S.ki.anfragen.find(x => x.id === p);
        S.ki.an = false;
        if (a) Sim.kiVerwerfen(S, a.id, a.gen, a.nr);
        const frei = nah.length ? nah[0] : -1;
        if (frei >= 0) S.g.bedient[frei] = Math.max(0, S.g.kapaz[frei] - 1);   // ein Platz frei (das Kind ist über 3: eine Einheit)
        S.freieStellen = Math.max(1, S.freieStellen);
        const erl2 = Sim.erlaubteAktionen(S, p, 7);
        pruef(Sim.istHaupt(S, p) && nah.length > 0 && !erl.includes('job_suchen') && !erl.includes('laden_gruenden') && (a ? !a.erlaubt.includes('job_suchen') : !erl.length)
          && info.gebunden && info.gebunden.id === kind && /kein Kita-Platz frei/.test(Sim.klartext(info.arbeit)) && erl2.includes('job_suchen'),
          `Hauptfigur ${Sim.name(S, p)} ohne Kita-Platz für ${Sim.name(S, kind)}: erlaubt ${erl.join(', ') || 'nichts'}; Anfrage ${a ? a.erlaubt.join(', ') : 'keine (nichts erlaubt)'}; „${Sim.klartext(info.arbeit)}“; mit freiem Platz: ${erl2.includes('job_suchen') ? 'job_suchen wieder erlaubt' : 'kein job_suchen'}`);
      }
    }
  }
  // Sicherheit (Version 7): die Anweisungen ans Sprachmodell (Code aus dem module-Block von stadt.html, Abschnitt „Anweisungen auf Deutsch“,
  // mit der echten Simulation ausgeführt). Nur Tatsachen der Figur (Haft, Verfahren); ein Opfer weiß nicht, wer es war, und verdächtigt
  // niemanden; jede Figur beurteilt andere nur nach dem, was sie mit ihnen erlebt hat (keine Aufzählung von Merkmalen, die sie erst darauf
  // bringt). Der Name des Täters steht nie in der Anweisung des Opfers, keine Anweisung nennt die Stadtregierung. Dazu die Prüfung der
  // Antworten (Abschnitt „Antworten prüfen“): Verdacht gegen einen Namen oder nach Herkunft wird verworfen
  {
    const m = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
    const a = m.indexOf('// ─── Anweisungen auf Deutsch'), e = m.indexOf('// ─── Der KI-Takt');
    const S = Sim.neueStadt(2); while (S.tag < 300 || S.stunde < 13) Sim.stunde(S);
    const zahl = (v) => Math.round(v).toLocaleString('de-DE');
    const A = new Function('Sim', 'S', 'zahl', 'STADTNAME', m.slice(a, e) + '\nreturn { beschreibung, gespraechsAnweisung, aufholAnweisung, lageSatz, verdachtFrei, pruefeEntscheidung, obhutGrund, amtFrei };')(Sim, S, zahl, 'Neustadt');
    const R = Sim.R, P = S.p, erw = S.tag - R.ERWACHSEN * R.JAHR;
    // ohne das Bürgermeisteramt: Seine Anweisung nennt die Stadtregierung mit Absicht („leitet die Verwaltung nach den Regeln der Stadtregierung“, Teil 1);
    // hier geht es um gewöhnliche Figuren (seit dem Haushalt läuft Seed 2 anders, und der Bürgermeister wäre sonst „nie Opfer gewesen“)
    const frei = []; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.geb[p] <= erw && !P.haftBis[p] && P.besitz[p] < 0 && !S.sicherheit.verfahren.some(v => v.id === p) && !Sim.istBm(S, p)) frei.push(p);
    const t = frei[0];
    for (let i = 0; i < 400 && !S.sicherheit.verfahren.some(v => v.id === t); i++) { P.geld[t] = 0; Sim._sich.tatBegehen(S, t, Sim.DIEBSTAHL); }
    const opfer = []; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.opferTag[p] === S.tag) opfer.push(p);
    const verwandt = (i, x) => [i.partner, ...i.eltern, ...i.kinder, ...i.freunde].some(r => r && r.id === x);
    const OPFER_SATZ = 'weißt du nicht, und du verdächtigst niemanden', ALLE_SATZ = 'beurteilst andere nur nach dem, was du mit ihnen erlebt hast';
    let geprueft = 0, nameDrin = 0, satzFehlt = 0;
    for (const o of opfer) {
      const i = Sim.personInfo(S, o);
      for (const text of [A.gespraechsAnweisung(i), A.aufholAnweisung(i, S.tag - 3, 3)]) {
        geprueft++;
        if (!text.includes(OPFER_SATZ) || !text.includes(ALLE_SATZ)) satzFehlt++;
        if (!verwandt(i, t) && text.includes(Sim.name(S, t))) nameDrin++;
      }
    }
    const it = Sim.personInfo(S, t), tv = A.gespraechsAnweisung(it);
    Sim._sich.haftAntritt(S, t, R.VERFAHREN, Sim.HAFT_U);
    const tu = A.gespraechsAnweisung(Sim.personInfo(S, t));
    const s2 = frei[5]; Sim._sich.haftAntritt(S, s2, 8, Sim.HAFT_STRAF);
    const ts = A.gespraechsAnweisung(Sim.personInfo(S, s2));
    const nie = frei.find(p => p !== t && p !== s2 && !Sim.personInfo(S, p).opfer);   // nie Opfer gewesen (im Gedächtnis)
    const normal = A.gespraechsAnweisung(Sim.personInfo(S, nie));
    const alle = [tv, tu, ts, normal];
    pruef(opfer.length > 0 && geprueft > 0 && !satzFehlt && !nameDrin && /Strafverfahren wegen Diebstahls; das Urteil kommt an Tag \d+/.test(tv)
      && /Du bist in Untersuchungshaft in (der Justizvollzugsanstalt in der Stadt|einer Anstalt des Landes außerhalb der Stadt), bis das Gericht urteilt/.test(tu)
      && alle.every(x => !/Herkunft|Religion|Sprache/.test(x))
      && /Du bist in Strafhaft .*noch bis Tag \d+; du arbeitest dort/.test(ts) && alle.every(x => x.includes(ALLE_SATZ)) && !normal.includes(OPFER_SATZ) && alle.every(x => !/Stadtregierung|AfD/.test(x)),
      `Anweisungen ans Sprachmodell (Sicherheit): ${opfer.length} Opfer, ${geprueft} Anweisungen mit „…${OPFER_SATZ}“ (${satzFehlt} ohne), Name des Täters ${nameDrin}-mal darin; `
      + `Täter: „${tv.match(/Gegen dich[^.]*\./)?.[0] || '–'}“, U-Haft: „${tu.match(/Du bist in Untersuchungshaft[^.]*\./)?.[0] || '–'}“, Strafhaft: „${ts.match(/Du bist in Strafhaft[^.]*\./)?.[0] || '–'}“`);
    // Antworten prüfen (Befund der Gegenprüfung): Ein Opfer, dessen Antwort einen anderen Namen der Stadt mit einem Verdacht verbindet, wird
    // verworfen, ebenso jede Antwort, die einen Verdacht mit Herkunft, Religion oder Sprache verbindet, und bei jeder Figur ein Name mit einem
    // Wort einer Tat (Nachprüfung: auch Wortformen wie Einbrecher, klaut, stahl, stiehlt; „fremd“; „<Name> ist ein Dieb“). Erlaubt bleibt, was
    // nichts unterstellt, auch Nachnamen, die gewöhnliche Wörter sind („Klein war der Schaden nicht“, „der Richter“)
    const io = Sim.personInfo(S, opfer[0]), inormal = Sim.personInfo(S, nie), eigen = io.name.split(' '), beide = eigen.concat(inormal.name.split(' '));
    const anderer = Sim.name(S, frei.find(p => p !== opfer[0] && !Sim.name(S, p).split(' ').some(w => eigen.includes(w))));
    const vorn = (w) => Sim.VORNAMEN_M.concat(Sim.VORNAMEN_W).filter(n => !beide.includes(n) && n !== 'Klaus').sort((x, y) => (x === w ? -1 : y === w ? 1 : 0));
    const nachn = (w) => Sim.NACHNAMEN.filter(n => !beide.includes(n)).sort((x, y) => (x === w ? -1 : y === w ? 1 : 0));
    const [fremdVor, vor2, vor3] = vorn('Mehmet'), [fremdNach, nach2, nach3] = nachn('Koch');
    const faelle = [
      [io, `Ich glaube, ${fremdVor} ${fremdNach} hat mich bestohlen.`, false], [io, `Bestimmt war es ${anderer}, der hat mich doch betrogen!`, false],
      [io, `Herr ${fremdNach} ist verdächtig.`, false], [io, 'Das waren sicher Ausländer, die bei mir eingebrochen haben.', false],
      [inormal, 'Die Zugezogenen sind schuld an den Diebstählen.', false], [inormal, 'Ich glaube, Muslime klauen, das war es.', false],
      [io, `Der Einbrecher war bestimmt ${vor2} ${nach2}.`, false], [io, `${vor2} ${nach2} stahl meine Uhr.`, false],
      [io, `${vor3} ${nach3} klaut bestimmt, das weiß ich.`, false], [io, `Ich vermute, dass ${vor3} ${nach3} mein Geld genommen hat.`, false],
      [io, `Sicher steckt ${vor2} ${nach2} dahinter.`, false], [io, `Es war ${anderer}, der mich bestohlen hat.`, false],
      [inormal, `Ich glaube, ${fremdVor} ${fremdNach} ist ein Dieb.`, false], [inormal, `${vor2} ${nach2} stiehlt.`, false],
      [inormal, 'Die Fremden hier sind alle Diebe.', false], [inormal, 'Leute mit ausländischen Namen stehlen.', false],
      [inormal, 'Leute mit komischen Namen klauen.', false], [inormal, 'Wer kein Deutsch spricht, stiehlt eher.', false],
      [io, 'Ich weiß nicht, wer mich bestohlen hat, und ich verdächtige niemanden.', true], [io, `Ich wurde bestohlen. ${anderer} hat mir geholfen.`, true],
      [io, `Ich, ${io.name}, wurde bestohlen und bin wütend.`, true], [inormal, `${anderer} hat mich beim Kartenspiel betrogen, aber wir sind Freunde.`, true],
      [inormal, 'Heute gehe ich arbeiten und spare Geld.', true], [io, 'Klein war der Schaden nicht, bestohlen zu werden tut weh.', true],
      [io, `Ich habe mir frei genommen und treffe ${anderer}.`, true], [inormal, 'Der Richter hat mich wegen Diebstahls verurteilt.', true],
      [inormal, `Mit ${anderer} war es heute lustig.`, true], [inormal, 'Er ist fremdgegangen und hat mich betrogen.', true],
      [inormal, 'Klaus hilft mir heute beim Umzug.', true]];
    const falsch = faelle.filter(([i, t, soll]) => A.verdachtFrei(t, i) !== soll).map(([, t]) => t);
    const erl = ['job_suchen'], jz = (g) => JSON.stringify({ aktion: 'job_suchen', gedanke: g, neues_ziel: null });
    const ent = [A.pruefeEntscheidung(jz(`${fremdVor} ${fremdNach} hat mich bestohlen.`), erl, io), A.pruefeEntscheidung(jz('Ich suche mir Arbeit.'), erl, io)];
    const og = [A.obhutGrund([{ weib: true, haushalt: 7, erwachsene: 1 }]), A.obhutGrund([{ weib: false, haushalt: 7, erwachsene: 2 }, { weib: true, haushalt: 7, erwachsene: 2 }])];
    pruef(!falsch.length && ent[0] === null && ent[1] && ent[1].gedanke === 'Ich suche mir Arbeit.' && io.opfer && !inormal.opfer
      && og[0].wer === 'der einzige Erwachsene in ihrem Haushalt' && og[0].ist === 'ist' && og[1].wer === 'alle Erwachsenen in ihrem Haushalt' && og[1].ist === 'sind',
      `Antworten ans Sprachmodell: ${faelle.length} Fälle (Opfer ${io.name}), ${falsch.length} falsch beurteilt${falsch.length ? ': ' + falsch.join(' | ') : ''}; „${fremdVor} ${fremdNach} hat mich bestohlen“ als Entscheidung verworfen: ${ent[0] === null}; `
      + `Obhut: „${og[0].wer} ${og[0].ist} in Haft“, „${og[1].wer} ${og[1].ist} in Haft“`);
    // Bürgermeister (Befund Texte der Schlussprüfung): Jeder Text der Amtsperson ohne Gruppen und ohne Parteien (amtFrei, auch in Gespräch,
    // Entscheidung, Tagebuch und Code); gewöhnliche Figuren prüft nur verdachtFrei. Die Anweisung sagt es der Amtsperson
    const ib = Sim.personInfo(S, S.buergermeister.p), bmFaelle = [['Ich wähle die CDU.', false], ['Die Grünen haben recht.', false], ['Parteien interessieren mich nicht.', false],
      ['Die Zugezogenen machen mir Sorgen.', false], ['Wir brauchen mehr Deutsch in der Schule.', false], ['Ich bin parteilos und leite die Verwaltung.', true],
      ['Heute gehe ich ins Grüne und ruhe mich aus.', true], ['Ich arbeite im Rathaus und treffe abends Freunde.', true]];
    const bmFalsch = bmFaelle.filter(([t, soll]) => A.amtFrei(t, ib) !== soll).map(([t]) => t);
    const entBm = A.pruefeEntscheidung(jz('Ich wähle die CDU.'), erl, ib), entNormal = A.pruefeEntscheidung(jz('Ich wähle die CDU.'), erl, inormal);
    pruef(!!ib && !!ib.amt && !bmFalsch.length && entBm === null && !!entNormal && A.amtFrei('Ich wähle die CDU.', inormal)
      && A.beschreibung(ib).includes('sprichst du nicht für oder gegen Parteien oder Gruppen von Bewohnern'),
      `Bürgermeister: ${bmFaelle.length} Sätze, ${bmFalsch.length} falsch beurteilt${bmFalsch.length ? ': ' + bmFalsch.join(' | ') : ''}; „Ich wähle die CDU.“ als Entscheidung `
      + `beim Amt verworfen, bei anderen nicht; Anweisung nennt die Neutralität`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle KI-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('migrationstest')) {
  let fehler = 0;
  Sim.R.RATHAUS = 0;                                         // Rathaus: hier aus (Zeilen und Verlauf wie vorher); die Übernahme mit Rathaus prüft --rathaus (D)
  Sim.R.SCHULEN = 0;                                         // Schule (Version 9): ebenso; die Übernahme mit Schulen prüft --schule (E)
  Sim.R.HH_VORHABEN = 0; Sim.R.HH_STEUER = 0;                // Haushalt (Version 9, Teil 3): nur Buchführung (Verlauf und Zeilen wie vorher); die Übernahme mit Haushalt prüft --haushalt (F)
  Sim.R.ANLAUF_STUFE = 0;                                    // Wachstum (Version 9, Teil 4): kein Anlauf (Verlauf wie vorher); die Übernahme prüft --wachstum
  Sim.R.TECH_FRUEH = 0; Sim.R.WELT = 0;                      // Tech früher und Weltmarkt (Version 9, Teil 5): aus (Verlauf wie vorher); die Übernahme prüft --techfrueh (D)
  Sim.R.ZUZUG_GENAU = 0;                                     // Zuzug genau nach R10 (Befund der Schlussprüfung von Version 9): aus (Verlauf wie vorher)
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  // Stadt erweitern (jede Version → 7): Stufe aus den Einwohnern am Übernahmetag, alle bebauten Stadtteile ab Kleinstadt mit verschiedenen
  // Namen, Karte mindestens 96 und mit Vorlauf, die neue Zeile („sie ist eine …“) als letzte
  const erweiterungUebernommen = (S, A) => {
    const e = S.erweiterung, soll = Sim.R.STUFE_AB.filter(v => A.einwohner >= v).length - 1, z = S.buch.at(-2), info = Sim.erweiterungInfo(S);   // Version 8: vor der Zeile der Autos
    const bebaut = new Set(); for (let b = 0; b < S.gAnzahl; b++) bebaut.add(Sim.teilVon(S, S.g.x[b], S.g.y[b]));
    const namen = e.teile.map(([t]) => Sim.teilName(S, t));
    pruef(S.version === Sim.VERSION && e.stufe === soll && e.stufenTage.length === soll + 1 && e.stufenTage.every(t => t === A.tag)
      && (soll === 0 ? e.teile.length === 0 : e.teile.length === bebaut.size && [...bebaut].every(t => Sim.teilName(S, t))) && new Set(namen).size === namen.length
      && S.karte >= 96 && info.rand >= Sim.RAND + Sim.R.KARTE_VORLAUF && e.wachsen.length === (S.karte > 96 ? 1 : 0)
      && z.art === 'stufe' && z.tag === A.tag && z.text.includes(`sie ist ${['ein Dorf', 'eine Kleinstadt', 'eine Stadt', 'eine Großstadt'][soll]}.`),
      `Stadt erweitern: ${A.einwohner} Einwohner → ${Sim.STUFEN[e.stufe]}, ${e.teile.length} Stadtteile, Karte ${S.karte} × ${S.karte} (Rand ${info.rand} Felder); „${Sim.klartext(z.text).slice(0, 120)}…“`);
  };
  // Sicherheit (jede Version → 7): ab dem Übernahmetag, noch keine Wache und keine Anstalt, niemand in Haft, vorbestraft, Opfer oder in Obhut,
  // alle Summen 0, eigener Zufallsstrom; die Zeile „Ab heute gibt es in der Stadt Diebstahl …“ steht vor „Bund“ und „Stadt erweitern“
  const sicherheitUebernommen = (S, A) => {
    const Si = S.sicherheit, st = S.stat.sicherheit, z = S.buch.at(-4), P = S.p;
    const soll = (n) => (n === 'opferTag' || n === 'entlassenTag' ? -9999 : n === 'obhutBei' ? -1 : 0);
    const falsch = Sim.PF_SICHERHEIT.filter(n => { for (let p = 0; p < S.pMax; p++) if (P[n][p] !== soll(n)) return true; return false; });
    pruef(Si && Si.start === A.tag && Si.wache === -1 && Si.jva === -1 && !Si.verfahren.length && Si.landGestern === null && Number.isInteger(S.rsSich)
      && st && Object.values(st).every(v => (Array.isArray(v) ? v.every(x => x === 0) : v === 0)) && !falsch.length
      && z.art === 'sicherheit' && z.tag === A.tag && /^Ab heute gibt es in der Stadt Diebstahl, Wohnungseinbruch und Betrug/.test(z.text),
      `Sicherheit ab Tag ${Si && Si.start}: noch keine Wache und Anstalt, Summen 0, Personenfelder leer (falsch: ${falsch.join(', ') || 'keine'}); „${Sim.klartext(z.text).slice(0, 90)}…“`);
  };
  // Bund (jede Version → 7, Teil 3): ab dem Übernahmetag, noch keine Kaserne und keine Dienststelle, niemand im Dienst oder Soldat, alle Summen 0;
  // die Zeile „Ab heute baut der Bund …“ ist die vorletzte (vor „Stadt erweitern“)
  const bundUebernommen = (S, A) => {
    const B = S.bund, st = S.stat.bund, z = S.buch.at(-3), P = S.p;
    const falsch = Sim.PF_BUND.filter(n => { for (let p = 0; p < S.pMax; p++) if (P[n][p] !== 0) return true; return false; });
    pruef(B && B.start === A.tag && B.kaserne === -1 && B.dienst === -1 && !B.kOffen && !B.dOffen && B.jahr.join() === '0,0' && B.gestern === null
      && st && Object.values(st).every(v => v === 0) && !falsch.length && z.art === 'bund' && z.tag === A.tag && /^Ab heute baut der Bund in der Stadt: eine Kaserne der Bundeswehr/.test(z.text),
      `Bund ab Tag ${B && B.start}: noch keine Kaserne und Dienststelle, Summen 0, Personenfelder leer (falsch: ${falsch.join(', ') || 'keine'}); „${Sim.klartext(z.text).slice(0, 90)}…“`);
  };
  // Autos (jede Version → 8): niemand hat ein Auto, kein Werk, alle neuen Felder und Summen 0 (auch CO₂ in der Stadtregierung), eigener
  // Zufallsstrom; die Zeile „Ab heute wachsen Tech-Firmen weiter …“ ist die letzte
  const autosUebernommen = (S, A) => {
    const z = S.buch.at(-1), P = S.p, g = S.g, st = S.stat.auto, r = S.regierung;
    const pf = Sim.PF_AUTO.filter(n => { for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P[n][p]) return true; return false; });
    const gf = Sim.GF_AUTO.filter(n => { for (let b = 0; b < S.gAnzahl; b++) if (g[n][b]) return true; return false; });
    pruef(S.version === Sim.VERSION && st && Object.values(st).every(v => v === 0) && Number.isInteger(S.rsAuto) && !pf.length && !gf.length
      && S.stat.regierung.co2 === 0 && r.tagStart.co2 === 0 && (r.gestern === null || r.gestern.co2 === 0)
      && z.art === 'auto' && z.tag === A.tag && /^Ab heute wachsen Tech-Firmen weiter/.test(z.text),
      `Autos ab Tag ${A.tag}: niemand hat eins, kein Werk, Summen 0, Felder leer (falsch: ${[...pf, ...gf].join(', ') || 'keine'}); „${Sim.klartext(z.text).slice(0, 80)}…“`);
  };
  // Version 7 → 8: Alles andere bleibt (Stadt erweitern, Sicherheit, Bund, Stadtregierung, Summen, Stadtbuch bis auf die neue Zeile, Zufall),
  // und die Stadt läuft 60 Tage lang genau wie in Version 7 weiter, wenn die Autos aus sind (niemand kauft, Tech-Firmen bis Stufe 3, keine
  // Werke, 40-%-Grenze wie vorher; spurRelativ jeden Tag); danach bitgleich, mit Autos
  const v7Weiter = (Alt, A, S) => {
    const ohneNeu = S.buch.slice(0, -1), altBuch = A.buch.slice(A.buch.length - ohneNeu.length);
    pruef(S.einwohner === A.einwohner && S.buchNr === A.buchNr + 1 && JSON.stringify(ohneNeu) === JSON.stringify(altBuch) && JSON.stringify(regierungAlt(S.regierung)) === JSON.stringify(A.regierung)
      && JSON.stringify(statAlt(S.stat)) === JSON.stringify(statAlt(A.stat)) && JSON.stringify(S.stat.sicherheit) === JSON.stringify(A.stat.sicherheit) && JSON.stringify(S.stat.bund) === JSON.stringify(A.stat.bund)
      && S.rs === A.rs && S.rsSich === A.rsSich && JSON.stringify(kiAlt(S.ki)) === JSON.stringify(A.ki) && JSON.stringify(S.erweiterung) === JSON.stringify(A.erweiterung)
      && JSON.stringify(S.sicherheit) === JSON.stringify(A.sicherheit) && JSON.stringify(S.bund) === JSON.stringify(A.bund) && S.karte === A.karte,
      'Version 7 → 8: Stadt erweitern, Sicherheit, Bund, Stadtregierung, Summen, Hauptfiguren, Stadtbuch und Zufall bleiben, eine Zeile dazu (Autos)');
    let erst = -1;
    const an = sicherheitAus(Sim, true);
    for (let t = 0; t < 60; t++) {
      const z = A.tag + 1; while (A.tag < z) Alt.stunde(A); while (S.tag < z) Sim.stunde(S);
      if (erst < 0 && (spurRelativ(Alt, A) !== spurRelativ(Sim, S) || JSON.stringify(A.sicherheit) !== JSON.stringify(S.sicherheit) || JSON.stringify(A.bund) !== JSON.stringify(S.bund))) erst = A.tag;
    }
    an();
    pruef(erst < 0, `60 Tage weiter ohne Autos (Tag ${S.tag}, ${S.einwohner} Einw., Karte ${S.karte}): Kennzahlen, Zufall, Felder, Gebäude, Sicherheit und Bund ${erst < 0 ? 'jeden Tag wie in Version 7' : 'VERSCHIEDEN ab Tag ' + erst}`);
    const L = ladenAusText(Sim, speichernAlsText(Sim, S));
    const z = S.tag + 20; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
    pruef(fingerabdruck(Sim, S) === fingerabdruck(Sim, L) && Sim.autoKennzahlen(S).autos > 0, `danach mit Autos (${Sim.autoKennzahlen(S).autos} nach 20 Tagen) als Version ${Sim.VERSION} gespeichert und geladen: läuft bitgleich weiter`);
  };
  // Version 6 → 7: Alles andere bleibt (Stadtregierung, Schritt 2, Summen, Stadtbuch bis auf die neuen Zeilen, Zufall), und die Stadt läuft
  // 60 Tage lang genau wie in Version 6 weiter (spurRelativ: Kennzahlen, Zufall, Felder und Gebäude relativ zur Mitte, alle Personen- und
  // Gebäudefelder, jeden Tag; dafür ist die Sicherheit ausgeschaltet: keine Taten, das Land baut nicht); danach bitgleich, mit Sicherheit
  const v6Weiter = (Alt, A, S) => {
    const ohneNeu = S.buch.slice(0, -4), altBuch = A.buch.slice(A.buch.length - ohneNeu.length);
    pruef(S.einwohner === A.einwohner && S.buchNr === A.buchNr + 4 && JSON.stringify(ohneNeu) === JSON.stringify(altBuch) && JSON.stringify(regierungAlt(S.regierung)) === JSON.stringify(A.regierung)
      && JSON.stringify(statAlt(S.stat)) === JSON.stringify(A.stat) && S.rs === A.rs && JSON.stringify(kiAlt(S.ki)) === JSON.stringify(A.ki),
      'Version 6 → 8: Stadtregierung, Schritt 2, Summen, Hauptfiguren, Stadtbuch und Zufall bleiben, vier Zeilen dazu (Sicherheit, Bund, Stadt erweitern, Autos)');
    let erst = -1;
    const an = sicherheitAus(Sim);
    for (let t = 0; t < 60; t++) {
      const z = A.tag + 1; while (A.tag < z) Alt.stunde(A); while (S.tag < z) Sim.stunde(S);
      if (erst < 0 && spurRelativ(Alt, A) !== spurRelativ(Sim, S)) erst = A.tag;
    }
    an();
    pruef(erst < 0, `60 Tage weiter ohne Sicherheit und Autos (Tag ${S.tag}, ${S.einwohner} Einw., Karte ${S.karte}): Kennzahlen, Zufall, Felder und Gebäude ${erst < 0 ? 'jeden Tag wie in Version 6' : 'VERSCHIEDEN ab Tag ' + erst}`);
    const L = ladenAusText(Sim, speichernAlsText(Sim, S));
    const z = S.tag + 20; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
    pruef(fingerabdruck(Sim, S) === fingerabdruck(Sim, L), `danach als Version ${Sim.VERSION} gespeichert und geladen: läuft bitgleich weiter`);
  };
  // Alte Fassungen: mit --alt genau diese Datei, sonst aus git 39c405b (Version 2), 2b821c2 (Version 3), 1c8d40b (Version 4), 414ebab
  // (Version 5, Stadtregierung ohne Schritt 2) und bc7247a (Version 6, Schritt 2, feste Karte 96 × 96). --git <ordner>: Repository für
  // git show (Standard: der Ordner dieses Werkzeugs)
  const quellen = arg('alt') ? [[arg('alt'), readFileSync(arg('alt'), 'utf8')]]
    : ['39c405b', '2b821c2', '1c8d40b', '414ebab', 'bc7247a', 'ffa1d88'].map(c => [`git ${c}`, execFileSync('git', ['show', c + ':stadt/stadt.html'], { cwd: arg('git', hier), encoding: 'utf8', maxBuffer: 1 << 26 })]);
  // Neue Zeilen im Stadtbuch: Bauhof bzw. Tech-Firmen, dazu je eine Zeile der Stadtregierung; von Version 5 eine Zeile zu Schritt 2;
  // aus jeder Version eine Zeile „Stadt erweitern“ (Größe, Stufe, Stadtteile, Karte; Art „stufe“, immer die letzte) und davor je eine Zeile
  // „Sicherheit“ und „Bund“ (Version 7)
  const NEU_ZEILEN = { 2: 6, 3: 6, 4: 5, 5: 5, 6: 4, 7: 1 };   // Version 8: dazu je eine Zeile „Autos“ (die letzte)
  for (const [herkunft, altHtml] of quellen) {
    const ctx = vm.createContext({});
    vm.runInContext(altHtml.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], ctx);
    const Alt = ctx.StadtSim;
    console.log(`Alte Fassung: ${herkunft}`);
    pruef([2, 3, 4, 5, 6, 7].includes(Alt.VERSION) && Alt.VERSION < Sim.VERSION, `alte Simulation hat Version ${Alt.VERSION}, neue ${Sim.VERSION}`);
    const v5 = Alt.VERSION === 5, v6 = Alt.VERSION === 6, v7 = Alt.VERSION === 7;
    for (const [seed, tage, stunde] of [[1, 150, 13], [2, 300, 5], [3, 400, 20]]) {
      const A = Alt.neueStadt(seed);
      while (A.tag < tage || A.stunde < stunde || !A.baustellen.length) Alt.stunde(A);   // ein Moment mit laufenden Baustellen
      const text = speichernAlsText(Alt, A);
      let abgelehnt = null;
      try { ladenAusText(Sim, text); } catch (e) { abgelehnt = e; }
      pruef(abgelehnt && abgelehnt.andereVersion && abgelehnt.migrierbar, `Seed ${seed}, Tag ${A.tag} ${A.stunde} Uhr (${A.einwohner} Einw., ${A.baustellen.length} Baustellen): ohne Übernehmen abgelehnt, als übernehmbar markiert`);
      const roh = (t) => { const d = JSON.parse(t); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
      // Version 5 mit fehlender Summe des Kerns: abgelehnt wie in Version 5 selbst, nicht still mit 0 ergänzt
      if (v5) {
        const meld = [];
        for (const [was, weg] of [['stat.regierung.gs', d => { delete d.json.stat.regierung.gs; }], ['regierung.tagStart.lohnsteuer', d => { delete d.json.regierung.tagStart.lohnsteuer; }],
          ['stat.regierung.rentenkasse als Text', d => { d.json.stat.regierung.rentenkasse = '5'; }]]) {
          const d = roh(text); weg(d);
          let e = null; try { Sim.importZustand(d, true); } catch (x) { e = x; }
          meld.push(`${was}: ${e ? e.message : 'angenommen'}`);
          if (!e || !/^Spielstand beschädigt: (Regierungs-Statistik|Stadtregierung)$/.test(e.message)) fehler++;
        }
        console.log((meld.every(m => /beschädigt/.test(m)) ? '  ok   ' : '  FEHL ') + 'beschädigte Stände der Version 5 abgelehnt: ' + meld.join('; '));
      }
      const d = roh(text);
      const S = Sim.importZustand(d, true);
      const B = S.bauhof, g = S.g;
      autosUebernommen(S, A);                                // Version 8: Autos leer ab dem Übernahmetag, letzte Zeile
      if (v7) { v7Weiter(Alt, A, S); continue; }            // Version 7 → 8: nur die Autos neu, sonst läuft alles weiter
      erweiterungUebernommen(S, A);                          // Stadt erweitern: Stufe, Stadtteile, Karte, vorletzte Zeile
      sicherheitUebernommen(S, A);                           // Sicherheit: leer ab dem Übernahmetag, drittletzte Zeile
      bundUebernommen(S, A);                                 // Bund: leer ab dem Übernahmetag, vorletzte Zeile
      if (v6) { v6Weiter(Alt, A, S, text); continue; }      // Version 6 → 7: nur „Stadt erweitern“ neu, sonst läuft alles weiter
      pruef(B === 2 && g.typ[B] === Sim.WERKSTATT && g.besitzer[B] < 0, `Bauhof = Gebäude ${B} (die Werkstatt der Stadt vom Start)`);
      pruef(S.baustellen.every(b => g.bauRest[b] > 0 && g.bauRest[b] <= Sim.bauGesamt(S, b)), `Baustellen mit Arbeitstagen: ${S.baustellen.map(b => g.bauRest[b] + '/' + Sim.bauGesamt(S, b)).join(', ') || 'keine'}`);
      const dazu = NEU_ZEILEN[Alt.VERSION];
      pruef(S.einwohner === A.einwohner && S.buchNr === A.buchNr + dazu, `Einwohner (${S.einwohner}) und Stadtbuch bleiben, ${dazu} ${dazu === 1 ? 'Zeile' : 'Zeilen'} dazu: `
        + S.buch.slice(-dazu).map(e => `„${Sim.klartext(e.text).slice(0, 70)}…“`).join(' '));
      const regZeile = S.buch.filter(e => e.art === 'regierung').at(-1);
      if (!v5) pruef(S.version === Sim.VERSION && S.regierung.start === A.tag && S.regierung.schritt2 === A.tag && Object.values(S.stat.regierung).every(v => v === 0) && regZeile && regZeile.tag === A.tag && S.buch.at(-5) === regZeile
        && S.p.gsTage.every(v => v === 0) && S.p.gemein.every(v => v === 0) && S.regierung.gestern === null && Object.values(S.regierung.tagStart).every(v => v === 0),
        `Stadtregierung und Schritt 2 ab dem Übernahmetag ${S.regierung.start}, Summen 0, niemand in Grundsicherung, noch kein „gestern“`);
      // Version 5 → 6: die Stadtregierung läuft weiter (Start, Summen, gestern bleiben), Schritt 2 ab dem Übernahmetag, neue Summen 0
      else pruef(S.version === Sim.VERSION && S.regierung.start === A.regierung.start && S.regierung.schritt2 === A.tag
        && Object.entries(A.stat.regierung).every(([k, v]) => S.stat.regierung[k] === v) && ['kaeufe', 'ruhestand', 'rentnerEntlastung', 'miete', 'kitaPlatzTage', 'kitaLuecke', 'kitaKosten'].every(k => S.stat.regierung[k] === 0)
        && JSON.stringify(Object.fromEntries(Object.keys(A.regierung.gestern || {}).map(k => [k, S.regierung.gestern[k]]))) === JSON.stringify(A.regierung.gestern || {})
        && S.buch.at(-5) === regZeile && /^Ab heute können Mieter ihre Wohnung/.test(regZeile.text) && /Die Stadt baut Kitas; bis kein Kind mehr auf einen Platz wartet \(mindestens bis Tag \d+, höchstens bis Tag \d+\), muss niemand/.test(regZeile.text),
        `Stadtregierung läuft weiter (seit Tag ${S.regierung.start}, Summen und „gestern“ wie vorher), Schritt 2 ab Tag ${S.regierung.schritt2}, neue Summen 0`);
      // Schritt 2 für alle gleich: niemand besitzt schon eine Wohnung, Beitragsjahre nur aus dem Alter
      let bfehl = 0;
      for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.beitrag[p] !== Math.round(Sim.R.BEITRAG_START * Math.max(0, S.tag - S.p.geb[p] - Sim.R.ERWACHSEN * Sim.R.JAHR))) bfehl++;
      pruef(!bfehl && S.p.eigen.every(v => v === 0), `Beitragsjahre aus dem Alter (${bfehl} Fehler), noch niemand im Eigentum`);
      // Kitas: noch keine, niemand hat einen Platz, das Bauamt hat keine gebaut; Übergangsfrist bis Tag Übernahme + KITA_FRIST
      pruef(S.p.kita.every(v => v === 0) && S.stat.bauamt.kitas === 0 && Sim.kitaFrist(S) && S.regierung.schritt2 === S.tag && S.regierung.kitaAb === -1,
        `Kitas: noch kein Platz, ${S.stat.bauamt.kitas} gebaut, Übergangsfrist läuft (mindestens bis Tag ${S.regierung.schritt2 + Sim.R.KITA_FRIST}, höchstens bis Tag ${S.regierung.schritt2 + Sim.R.KITA_FRIST_MAX})`);
      { const t = S.tag, k0 = S.stat.regierung.kaeufe; while (S.tag === t) Sim.stunde(S);
        const z = S.buch.filter(e => e.tag === t && e.art === 'regierung').map(e => Sim.klartext(e.text)).find(x => x.startsWith('In der ersten Nacht nach der Übernahme'));
        pruef(S.stat.regierung.kaeufe > k0 && !!z, `erste Nacht: ${S.stat.regierung.kaeufe - k0} Käufe; „${z ? z.slice(0, 90) + '…' : '–'}“`); }
      const offen = new Set(S.baustellen);
      const ziel = S.tag + 59;                                 // mit der ersten Nacht oben 60 Tage
      // In der Übergangsfrist (mindestens 30 Tage und bis kein Kind wartet, höchstens 90) gibt niemand wegen eines fehlenden Platzes die
      // Stelle auf; danach gilt die Regel (Zeile im Stadtbuch am letzten Tag der Frist)
      const s2 = S.regierung.schritt2;
      while (Sim.kitaFrist(S) && S.tag <= s2 + Sim.R.KITA_FRIST_MAX) Sim.stunde(S);
      const ab = S.regierung.kitaAb, lueckeFrist = S.stat.regierung.kitaLuecke, gebautFrist = S.stat.bauamt.kitas;
      const fristZeile = S.buch.find(e => e.art === 'kita' && /^Die Übergangsfrist für die Kitas endet/.test(e.text));
      pruef(lueckeFrist === 0 && gebautFrist > 0 && !!fristZeile && fristZeile.tag === ab - 1 && ab >= s2 + Sim.R.KITA_FRIST && ab <= s2 + Sim.R.KITA_FRIST_MAX,
        `Übergangsfrist ${ab - s2} Tage (${Sim.R.KITA_FRIST} bis ${Sim.R.KITA_FRIST_MAX}): niemand gab die Stelle auf, ${gebautFrist} Kitas gebaut; Stadtbuch Tag ${fristZeile ? fristZeile.tag : '–'}: „${fristZeile ? Sim.klartext(fristZeile.text).slice(0, 110) + '…' : '–'}“`);
      // Kein Kündigungsschock nach der Frist: in der ersten Nacht höchstens 2, in den 10 Nächten danach höchstens 4 je Nacht (Schwelle, wie
      // in ffa1d88). Dazu (Version 8): Jede Stellenaufgabe der ersten Nacht hat ihr Kind im Gedächtnis (KITA_FEHLT, Bezug = Kind); gezeigt
      // wird, wie viele dieser Kinder schon vor dem Ende der Frist lebten
      { const je = [], ab = S.regierung.kitaAb, P = S.p, MEM = Sim.R.MEM;
        let rueck = -1, neuGeb = 0;
        for (let n = 0; n < 11; n++) {
          const t = S.tag, l0 = S.stat.regierung.kitaLuecke; while (S.tag === t) Sim.stunde(S); je.push(S.stat.regierung.kitaLuecke - l0);
          if (n) continue;
          const kinder = [];
          for (let i = 0; i < S.pMax * MEM; i++) if (P.memCode[i] === Sim.M.KITA_FEHLT && P.memTag[i] >= t) kinder.push(P.memRef[i]);
          rueck = kinder.filter(k => P.geb[k] < ab).length; neuGeb = kinder.length - rueck;
          if (kinder.length !== je[0]) rueck = 99;             // jede Stellenaufgabe muss ihr Kind im Gedächtnis haben
        }
        pruef(je[0] <= 2 && Math.max(...je.slice(1)) <= 4 && rueck !== 99, `nach der Frist: erste Nacht ${je[0]} (${rueck === 99 ? 'nicht jede mit ihrem Kind im Gedächtnis' : `${rueck} für Kinder, die vor dem Ende der Frist lebten, ${neuGeb} danach geboren`}), `
          + `Nächte 2–11 höchstens ${Math.max(...je.slice(1))} Stellenaufgaben (Schwelle 2 und 4): ${je.join(' ')}`); }
      while (S.tag < ziel) Sim.stunde(S);
      let nan = 0;
      for (const [n, a] of Object.entries(S.p)) if (a instanceof Float32Array || a instanceof Float64Array) for (let i = 0; i < S.pMax; i++) if (!Number.isFinite(a[i])) nan++;
      for (const k of ['budget', 'exportPreis', 'kistenpreis', 'zufMittel']) if (!Number.isFinite(S[k])) nan++;
      for (const v of Object.values(S.stat.regierung)) if (!Number.isFinite(v)) nan++;
      const k = Sim.kennzahlen(S);
      pruef(nan === 0 && Object.values(k).every(v => typeof v !== 'number' || Number.isFinite(v)), `60 Tage weiter (Tag ${S.tag}, ${S.einwohner} Einw.): keine NaN/Infinity`);
      pruef([...offen].every(b => !S.baustellen.includes(b) || S.g.auf[b]), `alle übernommenen Baustellen fertig (${offen.size})`);
      const gs = S.regierung.gestern;
      pruef(!!gs && Object.entries(gs).every(([k, v]) => Number.isFinite(v) && v >= 0 && v <= S.stat.regierung[k]),
        `„gestern“ nach 60 Tagen: Rentenkasse ${gs ? gs.rentenkasse : '–'}, Bund ${gs ? gs.praemie + gs.betreuung + gs.gs : '–'} Taler`);
      const ri = Sim.regierungInfo(S), stufe2 = S.buch.find(e => e.art === 'regierung' && e.tag === S.regierung.start + Sim.R.RENTE_STUFE_TAGE - 1 && e.text.includes('Rentenkasse'));
      // Stufe nach den Tagen seit der Übernahme (60, mit einer langen Kita-Frist bis 101)
      const stufeSoll = Math.min(Sim.R.RENTE_STUFEN.length, 1 + Math.floor((S.tag - S.regierung.start) / Sim.R.RENTE_STUFE_TAGE));
      if (!v5) pruef(ri.stufe === stufeSoll && ri.rente === Sim.R.RENTE_STUFEN[stufeSoll - 1] && (S.stat.regierung.rentenkasse > 0 || ri.rentner === 0) && !!stufe2,
        `Rente nach ${S.tag - S.regierung.start} Tagen auf Stufe ${ri.stufe} (${ri.rente} Taler), Rentenkasse bisher ${S.stat.regierung.rentenkasse} Taler (${ri.rentner} bekommen Rente); Stadtbuch Tag ${stufe2 ? stufe2.tag : '–'}: „${stufe2 ? Sim.klartext(stufe2.text) : ''}“`);
      else pruef(ri.stufe === Math.min(3, 1 + Math.floor((S.tag - S.regierung.start) / Sim.R.RENTE_STUFE_TAGE)) && S.stat.regierung.rentenkasse > A.stat.regierung.rentenkasse,
        `Rente weiter auf Stufe ${ri.stufe} (${ri.rente} Taler), Rentenkasse seit Tag ${S.regierung.start} ${S.stat.regierung.rentenkasse} Taler`);
      pruef(ri.kita.offen > 0 && ri.kita.kinder > 0,
        `Kitas nach 60 Tagen: ${ri.kita.offen} offen, ${ri.kita.kinder} Kinder mit Platz, ${ri.kita.warten} warten, ${S.stat.regierung.kitaLuecke}-mal Stelle aufgegeben (nach der Frist), ${ri.kita.gebunden} gebunden`);
      pruef(ri.eigentuemer > 0 && S.stat.regierung.kaeufe > 0,
        `Schritt 2 nach 60 Tagen: ${ri.eigentuemer} von ${ri.haushalte} Haushalten im Eigentum, ${S.stat.regierung.ruhestand} Renteneintritte (davon ${S.stat.regierung.fruehRuhestand} vor 67), ${ri.vor67} heute vor 67 in Rente`);
      // Bund nach 60 Tagen: ab der Stufe Stadt steht die Kaserne (oder es gibt kein Gelände), sonst noch nicht
      { const e = S.erweiterung, K = S.bund.kaserne, i = Sim.bundInfo(S);
        const ohneGelaende = !Sim.gelaendeSuchen(S, 3, 2, true) && !Sim.gelaendeSuchen(S, 2, 3, true);
        pruef(e.stufe >= Sim.R.KASERNE_STUFE ? K >= 0 || ohneGelaende : K < 0,
          `Bund nach 60 Tagen (${Sim.STUFEN[e.stufe]}): ${K >= 0 ? `Kaserne ${i.kaserneOffen ? `offen seit Tag ${i.kOffen}, ${S.stat.bund.wehrdienst + S.stat.bund.ersatzdienst} Einberufungen` : 'im Bau'}` : 'keine Kaserne' + (ohneGelaende ? ' (kein Gelände)' : '')}`); }
      if (S.stat.tech) pruef(S.version === Sim.VERSION && Array.isArray(S.angebot), `Version ${S.version}, Tech-Firmen danach: ${S.stat.tech.gruendungen} gegründet, ${S.stat.tech.kaeufe.reduce((a, b) => a + b, 0)} Käufe`);
      const L = ladenAusText(Sim, speichernAlsText(Sim, S));
      const z = S.tag + 20; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
      pruef(fingerabdruck(Sim, S) === fingerabdruck(Sim, L), `danach als Version ${Sim.VERSION} gespeichert und geladen: läuft bitgleich weiter`);
    }
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Migrations-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('regierung')) {
  // Stadtregierung: Lohnsteuer mit Freibetrag und Familiensplitting, Rente aus der Rentenkasse, Betreuungsgehalt, Grundsicherung
  // und gemeinnützige Arbeit (kommt im normalen Spiel fast nie vor, deshalb hier erzwungen), Speicherformat; Schritt 2: Beitragstage,
  // Renteneintritt, Rentner-Freibetrag, Mieterkauf (Erbe, Rückkauf, Buchungen), Übernahme eines Stands der Version 5.
  // Eine Kopie der Simulation mit Testhilfen: globalThis.__ohneJob sucht keine Stelle (Seit Schritt 2 gehen um 7 Uhr oft Leute in
  // Rente und machen in derselben Stunde eine Stelle frei; ein fester Stellenmarkt je Stunde reicht dann nicht), __buchung zählt jede
  // Budgetbuchung des Mieterkaufs mit; __ohneTat begeht keine Tat (Sicherheit: ohne Geld steigt die Tatneigung, eine Haft beendete den
  // erzwungenen Fall der gemeinnützigen Arbeit vorzeitig). Sonst gleich.
  const { Sim, ctx: ctxR } = ladeSimMit([
    ['  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p)) {\n',
      '  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p) && p !== globalThis.__ohneJob) {\n'],
    ['    if (zufallSich(S) >= tatRisiko(S, p)) continue;\n', '    if (zufallSich(S) >= tatRisiko(S, p) || p === globalThis.__ohneTat) continue;\n'],
    ['    S.budget += a; hhBuch(S, HK.WOHNUNGSKAUF, a);\n', '    S.budget += a; hhBuch(S, HK.WOHNUNGSKAUF, a); globalThis.__buchung += a;\n'],   // Haushalt (Teil 3): mit Buchung
    ['        if (r > 0) { P.geld[p] -= r; S.budget += r;', '        if (r > 0) { P.geld[p] -= r; S.budget += r; globalThis.__buchung += r;'],
    ['  S.budget -= z; hhBuch(S, HK.RUECKKAUF, -z); P.geld[x] += z;\n', '  S.budget -= z; hhBuch(S, HK.RUECKKAUF, -z); P.geld[x] += z; globalThis.__buchung -= z;\n'],
  ]);
  ctxR.__ohneJob = -1; ctxR.__buchung = 0; ctxR.__ohneTat = -1;
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR;
  const offenB = (S, b) => S.feld[S.g.y[b] * S.karte + S.g.x[b]] === S.g.typ[b] && !S.g.leer[b];
  // Schritt 2 unabhängig nachgebaut: Rente bekommt, wer 67 ist oder ohne Arbeitsplatz und Betrieb 45 Beitragsjahre hat
  const bekommtRente = (S, p) => S.tag - S.p.geb[p] >= R.RENTE * J || (S.p.arbeit[p] < 0 && S.p.besitz[p] < 0 && S.p.beitrag[p] >= 45 * J);
  // Die Regeln R01/R02 hier noch einmal unabhängig nachgerechnet: Steuer eines Steuerhaushalts mit Löhnen L, K Köpfen und
  // Rentner-Freibeträgen X (Schritt 2: je Rentner mit Lohn höchstens 23, höchstens der eigene Lohn)
  // Haushalt (Version 9, Teil 3): Satz q (Standard: der Satz vom Start, R.STEUER); in der Stadt der Satz des Haushalts (Sim.steuerSatz)
  const steuer = (L, K, X = 0, q = R.STEUER) => { const E = L.reduce((a, b) => a + b, 0); return L.map(b => Math.round(q * Math.max(0, E - R.FREIBETRAG * K - X) * b / E)); };
  const summe = (a) => a.reduce((x, y) => x + y, 0);
  pruef(R.KAUF_RESERVE === 600 && R.EIGEN_RESERVE === 40 && R.RENTNER_FREIBETRAG === 23 && R.BEITRAG_JAHRE === 45,
    `Reserve beim Gerätekauf weiter ${R.KAUF_RESERVE} Taler, Rücklage beim Wohnungskauf ${R.EIGEN_RESERVE} Tageskosten (eigene Namen)`);
  // Beispiele aus dem README und dem Fenster „Stadtregierung“ (alte Regel: 10 % je Lohn); die letzten beiden mit Rentner-Freibetrag
  for (const [was, L, K, soll, alt, X] of [['allein, 100 Taler', [100], 1, 7, 10], ['Paar, beide 100, zwei Kinder', [100, 100], 4, 8, 20],
    ['ein Verdienst 100, Partner, zwei Kinder', [100], 4, 0, 10], ['alleinerziehend 100, ein Kind', [100], 2, 4, 10], ['Paar ohne Kinder, beide 100', [100, 100], 2, 14, 20],
    ['Rentnerin allein, 100 Taler Lohn', [100], 1, 5, 10, 23], ['Paar ohne Kinder, 114 und 109, einer ist Rentner', [114, 109], 2, 14, 22, 23]]) {
    pruef(summe(steuer(L, K, X)) === soll && summe(L.map(b => b - Math.round(b * (1 - R.STEUER)))) === alt, `Lohnsteuer ${was}: ${summe(steuer(L, K, X))} statt ${alt} Taler am Tag`);
  }
  // Was um Mitternacht passieren muss, aus dem Stand um 23 Uhr (Entscheidungen der letzten Stunde vorher ausgeschaltet)
  function erwartet(S) {
    const P = S.p, g = S.g, erw = S.tag - R.ERWACHSEN * J, hk = new Map(), brutto = new Map();
    for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.hh[p] >= 0 && P.geb[p] > erw) hk.set(P.hh[p], (hk.get(P.hh[p]) || 0) + 1);
    for (let b = 0; b < S.gAnzahl; b++) {
      const t = g.typ[b];
      if ((t !== Sim.WERKSTATT && t !== Sim.LADEN && t !== Sim.TECH && t !== Sim.KITA && t !== Sim.WACHE && t !== Sim.JVA && t !== Sim.KASERNE && t !== Sim.DIENSTSTELLE && t !== Sim.RATHAUS && t !== Sim.SCHULE)
        || !offenB(S, b)) continue;   // Kita (Schritt 2): Lohn aus dem Budget; Wache, Anstalt und Schule (Lehrkräfte): Lohn vom Land; Kaserne und Dienststelle: Lohn vom Bund; Lohnsteuer wie jeder Lohn
      // Bund (Teil 3): Wehrdienst (Kaserne) und Ersatzdienst (Bauhof) bekommen den Sold brutto, Lohnsteuer wie jeder Lohn (B7)
      for (const w of S.belegschaft[b]) if (!P.frei[w] && !P.gemein[w]) brutto.set(w, P.bund[w] >= Sim.WEHRDIENST ? R.SOLD : g.lohn[b]);
    }
    const kopf = (w) => { const k = P.hh[w]; return k >= 0 && (k === w || k === P.partner[w]) ? k : w; };
    const mit = (x) => (P.besitz[x] >= 0 && offenB(S, P.besitz[x]) ? 0 : 1);
    const koepfe = (k) => { if (P.hh[k] !== k) return 1; const pa = P.partner[k]; return mit(k) + (pa >= 0 && P.hh[pa] === k ? mit(pa) : 0) + (hk.get(k) || 0); };
    const haushalte = new Map(), frei = new Map();
    for (const [w, b] of brutto) {
      const k = kopf(w); if (!haushalte.has(k)) { haushalte.set(k, []); frei.set(k, 0); } haushalte.get(k).push(b);
      if (bekommtRente(S, w)) frei.set(k, frei.get(k) + Math.min(b, R.RENTNER_FREIBETRAG));   // Schritt 2: Rentner mit Lohn
    }
    let lohnsteuer = 0, alt = 0, rentner = 0, betreuung = 0, lohnsumme = 0, rentnerLohn = 0, krippe = 0;
    for (const [k, L] of haushalte) lohnsteuer += summe(steuer(L, Math.max(1, koepfe(k)), frei.get(k), Sim.steuerSatz(S)));
    for (const [w, b] of brutto) { alt += b - Math.round(b * (1 - R.STEUER)); lohnsumme += b; if (bekommtRente(S, w)) rentnerLohn++; }
    for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.geb[p] <= erw && bekommtRente(S, p)) rentner++;
    // Betreuungsgehalt: je Haushalt mit Kind unter 3 ohne Kita-Platz (Schritt 2) der Vorstand, sonst sein Partner, wenn 18–66, ohne Stelle,
    // ohne Betrieb, ohne Rente
    const kann = (p) => { const a = S.tag - P.geb[p]; return a >= R.ERWACHSEN * J && a < R.RENTE * J && P.arbeit[p] < 0 && P.besitz[p] < 0 && !bekommtRente(S, p); };
    for (let k = 0; k < S.pMax; k++) {
      if (!P.lebt[k] || P.hh[k] !== k || !hk.get(k) || P.wohnung[k] < 0) continue;
      const pa = P.partner[k], klein = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === k && P.geb[m] > S.tag - R.BETREUUNG_ALTER);
      if (!klein.length || !(kann(k) || (pa >= 0 && P.hh[pa] === k && kann(pa)))) continue;
      if (klein.some(m => !P.kita[m])) betreuung++; else krippe++;   // alle Kinder unter 3 mit Kita-Platz: kein Betreuungsgehalt
    }
    return { lohnsteuer, alt, rentner, betreuung, lohnsumme, rentnerLohn, krippe };
  }
  const bisStunde = (S, tag, h) => { while (S.tag < tag || (S.tag === tag && S.stunde < h)) Sim.stunde(S); };
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), P = () => S.p;
    // 1. Summen an 60 Abenden (ab Tag 300, bis 30 Nächte ohne Wechsel dabei sind): Lohnsteuer, alte Regel, Rentenkasse, Betreuungsgehalt;
    //    Rente ohne Budget
    let naechte = 0, fehlSteuer = 0, fehlAlt = 0, fehlRente = 0, fehlBetr = 0, uebersprungen = 0, mitKind = 0, steuerSumme = 0, altSumme = 0, rlTage = 0, krippe = 0;
    bisStunde(S, 300, 23);
    for (let i = 0; i < 150 && (i < 60 || naechte < 30); i++) {         // bis mindestens 30 Nächte ohne Wechsel nachgerechnet sind
      bisStunde(S, 300 + i, 23);
      for (let p = 0; p < S.pMax; p++) S.p.jetzt[p] = 0;          // keine Entscheidung mehr bis Mitternacht
      // Haushalt (Version 9, Teil 3): ab Tag 300 ist der Satz meist 0 %; damit die Formel mit Satz geprüft wird, setzt der Test ihn je Nacht auf
      // 3 bis 10 % (die Stadt ändert ihn sonst nur am Jahresende)
      S.haushalt.satz = 3 + (i % 8);
      const e = erwartet(S), st = { ...S.stat.regierung }, fertig = S.stat.bau.fertig, pleiten = S.stat.pleiten, stufe = Sim.regierungInfo(S).rente;
      Sim.stunde(S);
      // Übersprungen: Ein fertiger Betrieb stellt seinen Besitzer um (Lohn anders); nach einer Pleite in der Nacht hat der Besitzer
      // keinen Betrieb mehr (Freibetrag) und die Leute keine Stelle (Betreuungsgehalt schon in derselben Nacht)
      if (S.stat.bau.fertig !== fertig || S.stat.pleiten !== pleiten) { uebersprungen++; continue; }
      naechte++;
      const d = (k) => S.stat.regierung[k] - st[k];
      if (d('lohnsteuer') !== e.lohnsteuer) fehlSteuer++;
      if (d('lohnsteuerAlt') !== e.alt) fehlAlt++;
      if (d('rentenkasse') !== e.rentner * stufe) fehlRente++;
      if (d('betreuungTage') !== e.betreuung || d('betreuung') !== e.betreuung * R.NETTO_STANDARD) fehlBetr++;
      if (d('rentnerLohnTage') !== e.rentnerLohn) fehlSteuer++;
      if (e.betreuung) mitKind++;
      krippe += e.krippe;
      rlTage += e.rentnerLohn;
      steuerSumme += d('lohnsteuer'); altSumme += d('lohnsteuerAlt');
    }
    pruef(naechte >= 20 && !fehlSteuer && !fehlAlt, `Lohnsteuer = Summe über alle Steuerhaushalte, mit Rentner-Freibetrag (${naechte} Nächte, ${uebersprungen} übersprungen, ${rlTage} Lohntage von Rentnern): ${steuerSumme} Taler, nach der alten Regel ${altSumme} (${fehlSteuer + fehlAlt} Fehler)`);
    pruef(!fehlRente, `Rentenkasse = alle, die Rente bekommen (ab 67, auch mit Arbeit oder Betrieb; vor 67 mit 45 Beitragsjahren ohne Arbeitsplatz) × Stufe (${fehlRente} Fehler)`);
    pruef(!fehlBetr && mitKind > 0, `Betreuungsgehalt je Haushalt mit Kleinkind ohne Kita-Platz (${mitKind} Nächte mit Betreuungsgehalt, ${krippe} Haushaltsnächte mit `
      + `Krippenplatz und jemandem, der es bekommen könnte, ohne Betreuungsgehalt; ${fehlBetr} Fehler)`);
    {                                                          // Rente kommt auch bei leerem Budget voll (nicht aus dem Budget)
      bisStunde(S, S.tag, 23);
      const rentner = []; for (let p = 0; p < S.pMax; p++) if (P().lebt[p] && S.tag - P().geb[p] >= R.RENTE * J && P().arbeit[p] < 0 && P().geb[p] > S.tag - R.ALT * J) rentner.push(p);   // ohne Lohn
      const vor = rentner.map(p => P().geld[p]), rk = S.stat.regierung.rentenkasse, stufe = Sim.regierungInfo(S).rente;
      budgetSetzen(S, 0);
      for (let p = 0; p < S.pMax; p++) S.p.jetzt[p] = 0;
      Sim.stunde(S);
      // Geld danach = vorher + Rente − Einkauf − Miete (+ nichts sonst): die Rente kam, obwohl das Budget leer war
      const bekommen = S.stat.regierung.rentenkasse - rk;
      pruef(rentner.length > 0 && bekommen >= rentner.length * stufe, `leeres Budget: ${rentner.length} Rentnerinnen und Rentner unter 80 bekommen trotzdem ${stufe} Taler (Rentenkasse +${bekommen})`);
    }
    // 2. Gemeinnützige Arbeit, erzwungen: eine allein lebende Person ohne Stelle, ohne Geld, seit 4 Tagen in Grundsicherung
    // Tag des Falls: 400, oder der nächste Tag, wenn Abschnitt 1 (bis 30 Nächte ohne Wechsel) schon weiter gelaufen ist (Teil 3: Seed 2)
    const T0 = Math.max(400, S.tag + 1);
    bisStunde(S, T0, 20);
    const B = S.bauhof;
    let c = -1;
    for (let p = 0; p < S.pMax; p++) {
      const a = S.tag - P().geb[p];
      if (!P().lebt[p] || a < 200 || a >= 600 || P().besitz[p] >= 0 || P().hh[p] !== p || S.hhGroesse[p] !== 1 || P().partner[p] >= 0 || P().arbeit[p] === B) continue;
      if (P().bund[p] || P().haftBis[p]) continue;             // Bund: nicht aus Kaserne oder Dienst (das Austragen unten kennt die Rolle nicht); nicht in Haft
      c = p; break;
    }
    pruef(c >= 0, `Person gefunden: ${c >= 0 ? Sim.name(S, c) : '–'}`);
    if (c < 0) continue;
    const alt = P().arbeit[c];
    if (alt >= 0) { const L = S.belegschaft[alt]; L.splice(L.indexOf(c), 1); P().arbeit[c] = -1; P().einsatz[c] = 0; }   // Stelle weg (zählt um Mitternacht neu)
    P().geld[c] = 0; P().gsTage[c] = R.GS_PFLICHT - 1; P().jetzt[c] = 0;
    P().ziel[c] = Sim.Z.JOB; P().zielSeit[c] = S.tag; P().zielWert[c] = 0;   // Ziel „besserer Job“ (ohne Stelle: Ausgangswert 0)
    P().getrenntTag[c] = S.tag;   // 30 Tage keine Partnersuche, niemand wählt c (sonst endet die Grundsicherung mit dem Einkommen des Partners)
    // Fester Stellenmarkt bis zum Test von job_suchen: niemand findet eine Stelle (freieStellen je Stunde auf 0, und c sucht nicht)
    ctxR.__ohneJob = c; ctxR.__ohneTat = c;
    const fest = (tag, h) => { while (S.tag < tag || (S.tag === tag && S.stunde < h)) { S.freieStellen = 0; Sim.stunde(S); } };
    fest(T0, 23);
    const gemVor = S.stat.regierung.gemeinnuetzig;
    fest(T0 + 1, 0);
    const gem = () => S.belegschaft[B].filter(w => P().gemein[w]).length;
    const dienst = () => S.belegschaft[B].filter(w => P().bund[w] === Sim.ERSATZDIENST).length;   // Bund: Ersatzdienst, außerhalb der Obergrenze
    const stellenB = Sim.stellen(S, B), bel = S.belegschaft[B].length, ed = dienst();
    pruef(P().gemein[c] === 1 && P().arbeit[c] === B && S.belegschaft[B].includes(c) && P().gsTage[c] === R.GS_PFLICHT && S.stat.regierung.gemeinnuetzig === gemVor + 1,
      `nach ${R.GS_PFLICHT} Tagen Grundsicherung gemeinnützige Arbeit im Bauhof: gemein ${P().gemein[c]}, gsTage ${P().gsTage[c]}`);
    pruef(stellenB - ed <= R.BAU_MAX && bel - ed <= R.BAU_MAX && stellenB === R.STELLEN_STADT + S.bauZuschlag + gem() + ed && S.g.offeneStellen[B] === stellenB - bel,
      `Bauhof: ${bel} Leute, davon ${gem()} gemeinnützig und ${ed} im Ersatzdienst, ${stellenB} Stellen (ohne Ersatzdienst ≤ ${R.BAU_MAX}); freie Stellen ${S.g.offeneStellen[B]} wie ohne sie`);
    const zeile = S.buch.filter(e => e.tag === T0 && e.art === 'regierung').at(-1);
    pruef(!!zeile && zeile.text.includes(`\u0001${c}/`) && /gemeinnütziger Arbeit im Bauhof herangezogen/.test(zeile.text), `Stadtbuch: „${zeile ? Sim.klartext(zeile.text) : '–'}“`);
    const info = Sim.personInfo(S, c);
    // Gemeinnützige Arbeit ist keine Stelle: kein „Ziel erreicht: besserer Job“ (Lebenslauf, Sprachmodell, Statistik)
    const zielFalsch = info.gedaechtnis.filter(m => m.tag >= T0 && m.text.includes('Ziel erreicht: ' + Sim.ZIELTEXT[Sim.Z.JOB]));
    pruef(!zielFalsch.length && P().ziel[c] === Sim.Z.JOB, `gemeinnützige Arbeit erfüllt das Ziel „${Sim.ZIELTEXT[Sim.Z.JOB]}“ nicht (Ziel jetzt ${Sim.ZIELTEXT[P().ziel[c]] || '–'})`);
    pruef(/^leistet gemeinnützige Arbeit beim Bauhof /.test(info.arbeit) && info.leistung && info.leistung.art === 'grundsicherung' && info.leistung.gemein,
      `Personenkarte: „${Sim.klartext(info.arbeit)}“, Leistung ${JSON.stringify(info.leistung)}`);
    fest(T0 + 1, 7);
    const erl = Sim.erlaubteAktionen(S, c, 7);
    pruef(!erl.includes('kuendigen') && !erl.includes('freinehmen') && !erl.includes('job_wechseln') && !erl.includes('job_suchen'), `erlaubt um 7 Uhr ohne freie Stellen: ${erl.join(', ')}`);
    S.freieStellen = 1;
    const erl2 = Sim.erlaubteAktionen(S, c, 7);
    pruef(erl2.includes('job_suchen') && !erl2.includes('kuendigen'), `mit freier Stelle erlaubt: ${erl2.join(', ')}`);
    fest(T0 + 1, 23);
    const g0 = P().geld[c], gs0 = S.stat.regierung.gemeinTage, tage0 = P().gsTage[c], bedarf = Sim.personInfo(S, c).leistung.betrag;
    fest(T0 + 2, 0);
    pruef(P().gemein[c] === 1 && S.stat.regierung.gemeinTage === gs0 + 1 && P().gsTage[c] === tage0 + 1,
      `am nächsten Abend noch gemeinnützig, Grundsicherung läuft weiter (gsTage ${P().gsTage[c]})`);
    pruef(P().geld[c] - g0 <= bedarf && P().geld[c] - g0 < R.LOHN_STADT / 2, `kein Lohn: Geld ${g0} → ${P().geld[c]} (nur Grundsicherung ${bedarf} minus Einkauf und Miete)`);
    // Speichern und Laden mit gemeinnütziger Arbeit: bitgleich
    {
      const L = ladenAusText(Sim, speichernAlsText(Sim, S));
      const A2 = ladenAusText(Sim, speichernAlsText(Sim, S));
      for (let i = 0; i < 24 * 3; i++) { Sim.stunde(L); Sim.stunde(A2); }
      pruef(L.p.gemein[c] === A2.p.gemein[c] && fingerabdruck(Sim, L) === fingerabdruck(Sim, A2), 'Speichern/Laden mit gemeinnütziger Arbeit: läuft bitgleich weiter');
    }
    // job_suchen: eine richtige Stelle geht vor, die gemeinnützige Arbeit endet
    ctxR.__ohneJob = -1;
    P().jetzt[c] = 1;
    let h = 0; while (P().gemein[c] && P().lebt[c] && h < 72) { Sim.stunde(S); h++; }
    pruef(!P().gemein[c] && P().arbeit[c] >= 0 && P().arbeit[c] !== B, `nach ${h} Stunden eine richtige Stelle: ${P().arbeit[c] >= 0 ? Sim.klartext(Sim.personInfo(S, c).arbeit) : '–'}`);
    bisStunde(S, S.tag + 1, 0);
    pruef(Sim.stellen(S, B) === R.STELLEN_STADT + S.bauZuschlag + gem() + dienst() && S.g.offeneStellen[B] === Sim.stellen(S, B) - S.belegschaft[B].length, 'danach stimmen die Stellen im Bauhof');
    ctxR.__ohneTat = -1;
    // 3. Elternzeit zählt nicht als arbeitslos, gemeinnützige Arbeit schon (Quote für den Zuzug)
    {
      let los = 0;
      S.tag--;                                                  // Stand von kennzahlenRechnen: vor dem Tageswechsel
      const erw = S.tag - R.ERWACHSEN * J, rente = S.tag - R.RENTE * J;
      for (let p = 0; p < S.pMax; p++) {
        if (!P().lebt[p] || P().geb[p] > erw || P().geb[p] <= rente || P().besitz[p] >= 0) continue;
        if (Sim.betreuer(S, P().hh[p]) === p || bekommtRente(S, p) || Sim.gebunden(S, p)) continue;     // Elternzeit, Rente vor 67, ohne Kita-Platz (Schritt 2)
        if (P().haftBis[p]) continue;                          // Sicherheit: in Haft nicht verfügbar, zählt nicht als arbeitslos (wie in Abschnitt 6)
        if (P().arbeit[p] < 0 || P().gemein[p]) los++;
      }
      S.tag++;
      pruef(los === S.arbeitslose, `Arbeitslose ohne Eltern mit Betreuungsgehalt, ohne Rente vor 67 und ohne Eltern, die ohne Kita-Platz nicht arbeiten können: ${los} = ${S.arbeitslose}`);
    }
  }
  // 4. Speicherformat: ein Stand der Version 6 ohne gültige Stadtregierung wird abgelehnt (sonst Absturz um Mitternacht); seit Schritt 2
  //    auch ohne Tag von Schritt 2, ohne die neuen Summen, ohne die neuen Personenfelder oder mit Wohneigentum, das es so nicht gibt
  {
    const S = Sim.neueStadt(1); while (S.tag < 50) Sim.stunde(S);
    const faelle = [['ohne regierung', j => { delete j.regierung; }], ['ohne stat.regierung', j => { delete j.stat.regierung; }],
      ['stat.regierung leer', j => { j.stat.regierung = {}; }], ['Summe null', j => { j.stat.regierung.rentenkasse = null; }],
      ['Start nach heute', j => { j.regierung.start = S.tag + 1; }], ['ohne tagStart', j => { delete j.regierung.tagStart; }],
      ['gestern als Text', j => { j.regierung.gestern = 'viel'; }], ['gestern ohne Summe', j => { delete j.regierung.gestern.gs; }],
      ['ohne schritt2', j => { delete j.regierung.schritt2; }], ['schritt2 vor dem Start', j => { j.regierung.start = 3; j.regierung.schritt2 = 2; }],
      ['schritt2 als Text', j => { j.regierung.schritt2 = '0'; }], ['ohne Summe der Käufe', j => { delete j.stat.regierung.kaeufe; }],
      ['Summe der Renteneintritte als Text', j => { j.stat.regierung.ruhestand = '1'; }], ['gestern ohne Raten', j => { delete j.regierung.gestern.tilgung; }],
      ['ohne kitaAb (Ende der Kita-Frist)', j => { delete j.regierung.kitaAb; }], ['kitaAb nach heute', j => { j.regierung.kitaAb = S.tag + 5; }],
      ['kitaAb als Text', j => { j.regierung.kitaAb = '0'; }]];
    for (const [was, kaputt] of faelle) {
      const d = JSON.parse(speichernAlsText(Sim, S)); kaputt(d.json);
      let meldung = null;
      try { ladenAusText(Sim, JSON.stringify(d)); } catch (e) { meldung = e.message; }
      pruef(meldung && /Stadtregierung|Regierungs-Statistik/.test(meldung), `${was}: abgelehnt („${meldung}“)`);
    }
    // Personenfelder von Schritt 2: fehlen sie in einem Stand der Version 6, ist er unvollständig; Wohneigentum nur beim Vorstand, der dort wohnt
    const feld = (d, name, f) => { const a = d.arrays.find(x => x.name === name), u8 = Buffer.from(a.b64, 'base64');
      const w = new Uint16Array(u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)); f(w); a.b64 = Buffer.from(w.buffer).toString('base64'); };
    let kind = -1, mieter = -1;                              // mieter: jemand, auf den ein Haushalt läuft (gekauft oder nicht)
    for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p]) { if (kind < 0 && S.p.hh[p] >= 0 && S.p.hh[p] !== p) kind = p; if (mieter < 0 && S.p.hh[p] === p && S.p.wohnung[p] >= 0) mieter = p; }
    const arrFaelle = [['ohne p.beitrag', d => { d.arrays = d.arrays.filter(a => a.name !== 'p.beitrag'); }, /unvollständig: p\.beitrag/],
      ['ohne p.eigen', d => { d.arrays = d.arrays.filter(a => a.name !== 'p.eigen'); }, /unvollständig: p\.eigen/],
      ['Eigentum bei jemandem, auf den der Haushalt nicht läuft', d => feld(d, 'p.eigen', w => { w[kind] = S.p.wohnung[kind] + 1; }), /Wohneigentum/],
      ['Eigentum an einer anderen Wohnung', d => { feld(d, 'p.eigen', w => { w[mieter] = S.bauhof + 1; }); feld(d, 'p.kaufPreis', w => { w[mieter] = 2400; }); }, /Wohneigentum/],
      ['Rest größer als der Kaufpreis', d => { feld(d, 'p.eigen', w => { w[mieter] = S.p.wohnung[mieter] + 1; }); feld(d, 'p.kaufPreis', w => { w[mieter] = 2400; }); feld(d, 'p.schuld', w => { w[mieter] = 2401; }); }, /Wohneigentum/]];
    for (const [was, kaputt, soll] of arrFaelle) {
      const d = JSON.parse(speichernAlsText(Sim, S)); kaputt(d);
      let meldung = null;
      try { ladenAusText(Sim, JSON.stringify(d)); } catch (e) { meldung = e.message; }
      pruef(kind >= 0 && mieter >= 0 && meldung && soll.test(meldung), `${was}: abgelehnt („${meldung}“)`);
    }
    const heil = ladenAusText(Sim, speichernAlsText(Sim, S));
    pruef(fingerabdruck(Sim, heil) === fingerabdruck(Sim, S) && JSON.stringify(heil.regierung.gestern) === JSON.stringify(S.regierung.gestern)
      && heil.regierung.gestern !== null, 'unveränderter Stand lädt, „gestern“ ist gleich nach dem Laden da');
  }
  // 5. Tageswerte „gestern“, Willkommensprämie und Wohnungsvorbehalt beim Zuzug (je Stunde bzw. Nacht bis Tag 150), danach
  //    Grundsicherung erzwungen (10 Nächte), Bauhof voll und Betreuungsgehalt aus der gemeinnützigen Arbeit heraus. Der Zuzug wird
  //    mit einer Kopie der Simulation gemessen, die in zuzug() mitschreibt (sonst gleich)
  const { Sim: SimZ, ctx } = ladeSimMit([
    ['  if (vorbehalt) { rs.vorbehaltTage++; rs.vorbehalten += vorbehalt; }\n',
      '  if (vorbehalt) { rs.vorbehaltTage++; rs.vorbehalten += vorbehalt; }\n  globalThis.__zuzug = { frei: S.freieWohnungen, such: S.wohnungSuchende, vorbehalt, fw, n: -1 };\n'],
    ['  S.anfragen = Math.max(0,', '  globalThis.__zuzug.n = n;\n  S.anfragen = Math.max(0,'],
    ['  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p)) {\n',
      '  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p) && p !== globalThis.__ohneJob) {\n'],
  ]);
  ctx.__ohneJob = -1;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}: gestern, Prämie, Vorbehalt, Grundsicherung erzwungen`);
    const S = SimZ.neueStadt(seed), P = () => S.p;
    let geburten = 0, praemFehl = 0, zuTage = 0, zuVorb = 0, zuFehl = 0, gestFehl = 0, naechte = 0, aussen = 0, ankunft = 0, ankunftFehl = 0;
    // Schritt 2: Beitragsjahre der Startbevölkerung nur aus dem Alter (95 % der Tage seit dem 18. Geburtstag)
    const startFehl = [...Array(S.pMax).keys()].filter(p => S.p.lebt[p] && S.p.beitrag[p] !== Math.round(R.BEITRAG_START * Math.max(0, S.tag - S.p.geb[p] - R.ERWACHSEN * J))).length;
    let ende = { ...S.stat.regierung };                        // Summen am Ende des letzten Tagesabschlusses
    pruef(S.regierung.gestern === null, 'neue Stadt: noch kein „gestern“ (Anzeige „–“)');
    while (S.tag < 150) {
      const g0 = S.stat.geburten, pr0 = S.stat.regierung.praemie, n0 = S.stat.regierung.praemien, tag0 = S.tag, zu0 = S.stat.zuzuege;
      ctx.__zuzug = null;
      SimZ.stunde(S);
      const d = S.stat.geburten - g0;
      if (d) { geburten += d; if (S.stat.regierung.praemie - pr0 !== d * R.PRAEMIE || S.stat.regierung.praemien - n0 !== d) praemFehl++; }
      if (S.tag === tag0) continue;
      naechte++;                                               // Tagesabschluss: gestern = Summen jetzt − Summen am Ende des Vortags
      const st = S.stat.regierung, gs = S.regierung.gestern;
      if (!gs || Object.keys(st).some(k => gs[k] !== st[k] - ende[k])) gestFehl++;
      else aussen += gs.rentenkasse + gs.praemie + gs.betreuung + gs.gs;
      ende = { ...st };
      // Wer letzte Nacht zugezogen ist, hat Beitragsjahre nur aus dem Alter (am Ankunftstag gab es noch keinen Beitragstag)
      for (let p = 0; p < S.pMax; p++) {
        if (S.tag === 1 || !P().lebt[p] || P().einzug[p] !== S.tag - 1 || S.tag - 1 - P().geb[p] < R.ERWACHSEN * J || P().elternA[p] >= 0) continue;   // Tag 1: Startbevölkerung (einzug 0)
        ankunft++;
        if (P().beitrag[p] !== Math.round(R.BEITRAG_START * (S.tag - 1 - P().geb[p] - R.ERWACHSEN * J))) ankunftFehl++;
      }
      const z = ctx.__zuzug;                                   // Zuzug höchstens freie Wohnungen minus Vorbehalt
      if (z) {
        zuTage++; if (z.vorbehalt) zuVorb++;
        if (z.vorbehalt !== Math.min(z.frei, z.such) || z.fw !== z.frei - z.vorbehalt || z.n > z.fw || S.stat.zuzuege - zu0 > Math.max(0, z.n)) zuFehl++;
      }
    }
    pruef(!gestFehl && naechte === 150, `„gestern“ = Summen minus Summen am Ende des Vortags (${naechte} Nächte, ${gestFehl} Fehler); von außen im Mittel ${Math.round(aussen / naechte)} Taler am Tag`);
    pruef(!praemFehl && geburten > 0, `Willkommensprämie: ${geburten} Geburten, je ${R.PRAEMIE} Taler (${praemFehl} Fehler)`);
    pruef(!zuFehl && zuTage === naechte, `Zuzug: ${zuTage} Nächte, ${zuVorb} mit Vorbehalt; Zuzüge ≤ freie Wohnungen − Vorbehalt, Vorbehalt = min(frei, suchend) (${zuFehl} Fehler)`);
    pruef(!startFehl && ankunft > 20 && !ankunftFehl, `Beitragsjahre von außen nur aus dem Alter: Start 10 Leute, ${ankunft} Zuzügler am Ankunftstag (${startFehl + ankunftFehl} Fehler)`);
    // Grundsicherung erzwungen: um 23 Uhr bei jeder 7. erwachsenen Person ohne Betrieb Stelle weg und Geld 0. Erwartung unabhängig
    // aus dem Stand um 23 Uhr: 18–66, ohne Stelle, ohne Betrieb, kein Betreuungsgehalt, niemand sonst im Haushalt mit Einkommen
    // Nächte mit fertigem Bau, Pleite oder Todesfall zählen nicht; es wird weitergemacht, bis 10 Nächte gezählt sind (höchstens 40)
    let faelle = 0, bezogen = 0, abw = 0, betragFehl = 0, betragNaechte = 0, gezaehlt = 0, haftFaelle = 0, haftNaechte = 0;
    for (let runde = 0; runde < 40 && gezaehlt < 10; runde++) {
      while (S.stunde !== 23) SimZ.stunde(S);
      const T = S.tag, p0 = P(), erz = [];
      for (let p = 0; p < S.pMax; p++) p0.jetzt[p] = 0;       // keine Entscheidung mehr bis Mitternacht
      let i = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!p0.lebt[p] || T - p0.geb[p] < R.ERWACHSEN * J || p0.besitz[p] >= 0 || p0.gemein[p] || (i++ + runde) % 7) continue;
        const b = p0.arbeit[p];
        if (b >= 0) { const L = S.belegschaft[b]; L.splice(L.indexOf(p), 1); p0.arbeit[p] = -1; p0.einsatz[p] = 0; }   // Stelle weg (zählt um Mitternacht neu)
        p0.geld[p] = 0; erz.push(p);
      }
      const alter = (x) => T - p0.geb[x];
      const rente = (x) => alter(x) >= R.RENTE * J || (p0.arbeit[x] < 0 && p0.besitz[x] < 0 && p0.beitrag[x] >= R.BEITRAG_JAHRE * J);   // Schritt 2
      const kann = (x) => alter(x) >= R.ERWACHSEN * J && alter(x) < R.RENTE * J && (p0.arbeit[x] < 0 || p0.gemein[x]) && p0.besitz[x] < 0 && !rente(x);
      const klein = (k) => { const w = p0.wohnung[k]; return w >= 0 && S.bewohner[w].some(m => p0.lebt[m] && p0.hh[m] === k && p0.geb[m] > T - R.BETREUUNG_ALTER && !p0.kita[m]); };
      const betr = (k) => { if (k < 0 || p0.hh[k] !== k || !klein(k)) return -1; if (kann(k)) return k; const pa = p0.partner[k]; return pa >= 0 && p0.hh[pa] === k && kann(pa) ? pa : -1; };
      const verdient = (p) => { const k = p0.hh[p], w = p0.wohnung[p]; if (k < 0 || w < 0) return false; const bt = betr(k);
        return S.bewohner[w].some(m => m !== p && p0.hh[m] === k && alter(m) >= R.ERWACHSEN * J
          && ((p0.arbeit[m] >= 0 && !p0.gemein[m]) || p0.besitz[m] >= 0 || rente(m) || bt === m)); };
      // Sicherheit: in Haft keine Grundsicherung (§ 7 Abs. 4 SGB II), der Stand um 23 Uhr entscheidet (Haft beginnt und endet erst danach)
      const soll = new Map(erz.map(p => [p, !p0.haftBis[p] && !rente(p) && betr(p0.hh[p]) !== p && !verdient(p)]));
      const inHaft = new Set(erz.filter(p => p0.haftBis[p])); haftFaelle += inHaft.size;   // Stand um 23 Uhr (p0 ist dasselbe Feld wie danach)
      const bedarf23 = new Map(erz.map(p => [p, SimZ.tageskosten(S, p)]));   // Tagesbedarf, wie er um Mitternacht gezahlt wird
      const f0 = S.stat.bau.fertig, pl0 = S.stat.pleiten, t0 = S.stat.tode, gs0 = S.stat.regierung.gs;
      SimZ.stunde(S);
      if (S.stat.bau.fertig !== f0 || S.stat.pleiten !== pl0 || S.stat.tode !== t0) continue;   // Stelle, Betrieb oder Haushalt anders
      // Sicherheit: Wer in dieser Nacht in Haft kommt (nach der Zahlung, z. B. nach einer Tat ohne Geld), dessen Grundsicherung endet
      // gleich wieder (gsTage 0); diese Nächte zählen nicht (das Ende der Grundsicherung prüft --sicherheit)
      if (erz.some(p => !inHaft.has(p) && P().haftBis[p])) { haftNaechte++; continue; }
      gezaehlt++;
      let summe = 0, nurErz = true;
      for (let p = 0; p < S.pMax; p++) if (P().lebt[p] && P().gsTage[p] && !soll.has(p)) nurErz = false;
      for (const [p, e] of soll) {
        faelle++;
        const ist = P().gsTage[p] > 0;
        if (ist) { bezogen++; summe += bedarf23.get(p); }
        if (ist !== e) { abw++; if (abw < 4) console.log(`    Tag ${T}: ${SimZ.name(S, p)} erwartet ${e}, bekommt ${ist}`); }
      }
      if (nurErz) { betragNaechte++; if (S.stat.regierung.gs - gs0 !== summe) betragFehl++; }
    }
    pruef(faelle > 0 && bezogen > 0 && !abw, `Grundsicherung erzwungen: ${faelle} Fälle, ${bezogen} bekommen sie, ${faelle - bezogen} nicht (Betreuungsgehalt, Rente, Einkommen im Haushalt, ${haftFaelle} in Haft; ${haftNaechte} Nächte mit Haftantritt nicht gezählt); ${abw} Abweichungen`);
    pruef(betragNaechte > 0 && !betragFehl, `Betrag = Tagesbedarf (Einkauf, beim Vorstand Miete und Kinder): ${betragNaechte} Nächte nachgerechnet, ${betragFehl} falsch`);
    // Bauhof voll: nach 5 Tagen Grundsicherung keine gemeinnützige Arbeit, die Grundsicherung läuft weiter; mit Platz in der Nacht danach.
    // Zieht die Person im Tag dazwischen mit jemandem zusammen (dann verdient jemand im Haushalt), gilt der Fall nicht: nächste Person
    {
      const B = S.bauhof, probiert = new Set(), allein = (c) => P().lebt[c] && P().hh[c] === c && P().partner[c] < 0 && S.hhGroesse[c] === 1;
      let fertig = false;
      for (let versuch = 0; versuch < 5 && !fertig; versuch++) {
        while (S.stunde !== 23) SimZ.stunde(S);
        let c = -1;
        for (let p = 0; p < S.pMax; p++) {
          const a = S.tag - P().geb[p];
          if (P().lebt[p] && !probiert.has(p) && a >= 200 && a < 600 && P().besitz[p] < 0 && P().hh[p] === p && S.hhGroesse[p] === 1 && P().partner[p] < 0 && P().arbeit[p] !== B && !P().gsTage[p]) { c = p; break; }
        }
        if (c < 0) { pruef(false, 'Bauhof voll: keine allein lebende Person gefunden'); break; }
        probiert.add(c);
        for (let p = 0; p < S.pMax; p++) P().jetzt[p] = 0;
        const alt = P().arbeit[c];
        if (alt >= 0) { const L = S.belegschaft[alt]; L.splice(L.indexOf(c), 1); P().arbeit[c] = -1; P().einsatz[c] = 0; }
        P().geld[c] = 0; P().gsTage[c] = R.GS_PFLICHT - 1;
        const zuschlag = S.bauZuschlag, gem0 = S.stat.regierung.gemeinnuetzig;
        S.bauZuschlag = R.BAU_MAX - R.STELLEN_STADT;           // 40 Stellen: der Bauhof ist voll (bauhofStellen rechnet es in der Nacht neu)
        SimZ.stunde(S);
        // Sicherheit: ohne Geld steigt die Tatneigung; kommt die Person in dieser Nacht in Haft, endet die Grundsicherung (nächster Versuch)
        if (P().haftBis[c]) { console.log(`       (${SimZ.name(S, c)} ist in Haft gekommen, nächster Versuch)`); continue; }
        pruef(!P().gemein[c] && P().arbeit[c] < 0 && P().gsTage[c] === R.GS_PFLICHT && S.stat.regierung.gemeinnuetzig === gem0,
          `Bauhof voll (Zuschlag ${zuschlag} → ${R.BAU_MAX - R.STELLEN_STADT}): ${SimZ.name(S, c)} bezieht Grundsicherung seit ${P().gsTage[c]} Tagen, keine gemeinnützige Arbeit`);
        ctx.__ohneJob = c;
        while (S.stunde !== 0 || P().gsTage[c] === R.GS_PFLICHT) { S.freieStellen = 0; P().jetzt[c] = 0; SimZ.stunde(S); if (allein(c)) continue; break; }
        ctx.__ohneJob = -1;
        if (!allein(c)) { console.log(`       (${SimZ.name(S, c)} lebt nicht mehr allein, nächster Versuch)`); continue; }
        while (S.stunde !== 0) SimZ.stunde(S);
        if (P().haftBis[c]) { console.log(`       (${SimZ.name(S, c)} ist in Haft gekommen, nächster Versuch)`); continue; }
        pruef(P().gemein[c] === 1 && P().arbeit[c] === B && S.stat.regierung.gemeinnuetzig === gem0 + 1,
          `mit Platz im Bauhof (${SimZ.stellen(S, B)} Stellen) in der Nacht danach herangezogen (gsTage ${P().gsTage[c]})`);
        fertig = true;
      }
      if (!fertig && probiert.size >= 5) pruef(false, 'Bauhof voll: in 5 Versuchen kein Fall, der allein blieb');
    }
    // Betreuungsgehalt aus der gemeinnützigen Arbeit heraus: Wer sie leistet und ein Kind unter 3 im Haushalt hat, bekommt
    // Betreuungsgehalt; die gemeinnützige Arbeit endet in derselben Nacht
    {
      const B = S.bauhof, bis = S.tag + 200;
      let m = -1;
      while (m < 0 && S.tag < bis) {                           // nächster Abend mit Betreuungsgehalt (Kind noch mindestens 2 Tage unter 3)
        SimZ.stunde(S);
        if (S.stunde !== 23) continue;
        for (let k = 0; k < S.pMax && m < 0; k++) {
          if (!P().lebt[k] || P().hh[k] !== k || !S.hhKinder[k] || SimZ.betreuer(S, k) < 0) continue;
          if (S.bewohner[P().wohnung[k]].some(x => P().hh[x] === k && P().geb[x] > S.tag + 2 - R.BETREUUNG_ALTER)) m = SimZ.betreuer(S, k);
        }
      }
      if (m < 0) pruef(false, 'Betreuungsgehalt aus gemeinnütziger Arbeit: kein Haushalt mit Kleinkind gefunden');
      else {
        for (let p = 0; p < S.pMax; p++) P().jetzt[p] = 0;
        P().arbeit[m] = B; S.belegschaft[B].push(m); P().gemein[m] = 1; P().gsTage[m] = R.GS_PFLICHT + 2;   // wie herangezogen
        const k = P().hh[m], wer = SimZ.betreuer(S, k), bt0 = S.stat.regierung.betreuung, g0 = P().geld[m];
        SimZ.stunde(S);
        pruef(wer === m && !P().gemein[m] && P().arbeit[m] < 0 && !P().gsTage[m] && !S.belegschaft[B].includes(m) && S.stat.regierung.betreuung - bt0 >= R.NETTO_STANDARD
          && SimZ.personInfo(S, m).leistung.art === 'betreuung',
          `${SimZ.name(S, m)}: mit Kleinkind Betreuungsgehalt statt gemeinnütziger Arbeit (betreuer ${wer === m ? 'ja' : 'nein'}, Geld ${Math.round(g0)} → ${Math.round(P().geld[m])})`);
      }
    }
  }
  // 6. Schritt 2, Renteneintritt: Beitragstage über Mitternacht, Anspruch mit 45 Beitragsjahren, Renteneintritt vor 67 (erzwungen),
  //    67 mit Stelle (Rente und Rentner-Freibetrag). Andere arbeitende Rentner haben an dem Tag frei, damit die Zähler genau prüfbar sind
  const arbeitslosZaehlen = (S) => {                          // wie in Abschnitt 3: Stand von kennzahlenRechnen vor dem Tageswechsel
    let los = 0; const P = S.p;
    S.tag--;
    const erw = S.tag - R.ERWACHSEN * J, rente = S.tag - R.RENTE * J;
    for (let p = 0; p < S.pMax; p++) {
      if (!P.lebt[p] || P.geb[p] > erw || P.geb[p] <= rente || P.besitz[p] >= 0) continue;
      if (Sim.betreuer(S, P.hh[p]) === p || bekommtRente(S, p) || Sim.gebunden(S, p)) continue;
      if (P.haftBis[p]) continue;                              // Sicherheit: in Haft nicht verfügbar, zählt nicht als arbeitslos
      if (P.arbeit[p] < 0 || P.gemein[p]) los++;
    }
    S.tag++;
    return los;
  };
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}: Schritt 2, Renteneintritt`);
    const S = Sim.neueStadt(seed), P = () => S.p;
    const ruhig = () => { for (let p = 0; p < S.pMax; p++) S.p.jetzt[p] = 0; };
    bisStunde(S, 250, 23);
    {                                                          // a) Beitragstage über Mitternacht
      let n = 0, mitArbeit = 0, betr = 0, ohne = 0, fehl = 0;
      for (let v = 0; v < 8; v++) {
        bisStunde(S, S.tag, 23); ruhig();
        const vor = [], P0 = P(), stellen = (p) => { const k = P0.hh[p], pa = k >= 0 ? P0.partner[k] : -1; return k < 0 ? '' : P0.arbeit[k] + '/' + (pa >= 0 ? P0.arbeit[pa] : '') + '/' + P0.hh[p]; };
        for (let p = 0; p < S.pMax; p++) if (P0.lebt[p] && S.tag - P0.geb[p] >= R.ERWACHSEN * J)
          vor.push([p, P0.gen[p], P0.beitrag[p], P0.arbeit[p], P0.gemein[p], Sim.betreuer(S, P0.hh[p]) === p, stellen(p)]);
        Sim.stunde(S);
        n++;
        for (const [p, gen, b, arb, gem, bt, st] of vor) {
          if (!P().lebt[p] || P().gen[p] !== gen || P().arbeit[p] !== arb || P().gemein[p] !== gem) continue;   // weg oder Stelle anders
          const k = P().hh[p], pa = k >= 0 ? P().partner[k] : -1;
          if (k < 0 ? st !== '' : P().arbeit[k] + '/' + (pa >= 0 ? P().arbeit[pa] : '') + '/' + k !== st) continue;   // im Haushalt Stelle weg (Pleite): anderer Betreuer
          if (arb >= 0 && !gem) mitArbeit++; else if (bt) betr++; else ohne++;
          if (P().beitrag[p] !== Math.min(65535, b + ((arb >= 0 && !gem) || bt ? 1 : 0))) fehl++;
        }
      }
      pruef(n === 8 && mitArbeit > 0 && betr > 0 && ohne > 0 && !fehl,
        `Beitragstage über ${n} Mitternächte: ${mitArbeit}-mal mit Arbeitsplatz +1, ${betr}-mal mit Betreuungsgehalt +1, ${ohne}-mal ohne beides +0 (${fehl} Fehler)`);
    }
    // b) 64 Jahre, angestellt, kein Erspartes: mit 449 Beitragstagen kein „kündigen“, mit 450 schon; das Gehirn wählt es und geht in Rente
    bisStunde(S, S.tag, 7);
    let c = -1;
    for (let p = 0; p < S.pMax; p++) {
      const a = S.tag - P().geb[p];
      if (P().lebt[p] && a >= 300 && a < 600 && P().arbeit[p] >= 0 && P().besitz[p] < 0 && !P().gemein[p] && !Sim.istHaupt(S, p)) { c = p; break; }
    }
    if (c < 0) pruef(false, 'Renteneintritt: keine angestellte Person gefunden');
    else {
      P().geb[c] = S.tag - 64 * J; P().geld[c] = 0;
      P().beitrag[c] = R.BEITRAG_JAHRE * J - 1;
      const e449 = Sim.erlaubteAktionen(S, c, 7);
      P().beitrag[c] = R.BEITRAG_JAHRE * J;
      const e450 = Sim.erlaubteAktionen(S, c, 7), satz = Sim.kiAktionen(S, c, ['kuendigen'])[0].satz;
      pruef(!e449.includes('kuendigen') && e450.includes('kuendigen') && /ohne Abschlag/.test(satz),
        `64 Jahre, kein Erspartes: mit 449 Beitragstagen kein „kündigen“, mit 450 schon („${satz}“)`);
      // Seit drei Jahren Anspruch (Ruhestandswunsch 40), Fleiß und Ehrgeiz 0, unzufrieden, sonst alles gut: das Gehirn wählt „kündigen“
      P().beitrag[c] = R.BEITRAG_JAHRE * J + 3 * J;
      P().fleiss[c] = 0; P().ehrgeiz[c] = 0; P().zuf[c] = 5; P().bFreizeit[c] = 100; P().bKontakt[c] = 100; P().bWohnen[c] = 100; P().elend[c] = 0;
      P().ziel[c] = Sim.Z.RUHE; P().zielSeit[c] = S.tag;
      const st0 = { ...S.stat.regierung }, a = Sim.entscheide(S, c, 7), info = Sim.personInfo(S, c);
      S.freieStellen = Math.max(1, S.freieStellen);
      const nachher = Sim.erlaubteAktionen(S, c, 7);
      pruef(Sim.AKTIONSNAMEN[a] === 'kuendigen' && P().arbeit[c] < 0 && S.stat.regierung.ruhestand === st0.ruhestand + 1
        && S.stat.regierung.fruehRuhestand === st0.fruehRuhestand + 1 && S.stat.regierung.fruehAlter === st0.fruehAlter + 64 * J
        && info.arbeit === 'in Rente' && info.rente.bezieht && info.gedaechtnis.at(-1).text.startsWith('in Rente gegangen') && !nachher.includes('job_suchen'),
        `Gehirn wählt „${Sim.AKTIONSNAMEN[a]}“: ${Sim.name(S, c)} ist mit 64 in Rente („${Sim.klartext(info.gedaechtnis.at(-1).text)}“), sucht keine Stelle (erlaubt: ${nachher.join(', ')})`);
      bisStunde(S, S.tag, 23); ruhig();
      const e = erwartet(S), rk0 = S.stat.regierung.rentenkasse, stufe = Sim.regierungInfo(S).rente, drin = bekommtRente(S, c);
      Sim.stunde(S);
      pruef(drin && S.stat.regierung.rentenkasse - rk0 === e.rentner * stufe && arbeitslosZaehlen(S) === S.arbeitslose,
        `um Mitternacht Rente aus der Rentenkasse (${e.rentner} Leute × ${stufe}), zählt nicht als arbeitslos (${S.arbeitslose} ohne Arbeit)`);
    }
    // c) 67 mit Stelle: bleibt angestellt, bekommt Rente, Rentner-Freibetrag auf den eigenen Lohn
    bisStunde(S, S.tag, 23);
    let d = -1;
    for (let p = 0; p < S.pMax; p++) {
      const a = S.tag - P().geb[p];
      if (P().lebt[p] && a >= 300 && a < 600 && P().arbeit[p] >= 0 && P().besitz[p] < 0 && !P().gemein[p] && !P().frei[p] && P().hh[p] === p
          && S.hhGroesse[p] === 1 && P().partner[p] < 0 && !Sim.istHaupt(S, p) && P().arbeit[p] !== S.bauhof) { d = p; break; }
    }
    if (d < 0) pruef(false, '67 mit Stelle: keine allein lebende angestellte Person gefunden');
    else {
      ruhig();
      P().geb[d] = S.tag - R.RENTE * J;                        // heute 67
      for (let p = 0; p < S.pMax; p++) if (p !== d && P().lebt[p] && S.tag - P().geb[p] >= R.RENTE * J && P().arbeit[p] >= 0) P().frei[p] = 1;
      const b = P().arbeit[d], L = S.g.lohn[b], st0 = { ...S.stat.regierung }, e = erwartet(S), stufe = Sim.regierungInfo(S).rente;
      Sim.stunde(S);
      const dd = (k) => S.stat.regierung[k] - st0[k];
      const q = Sim.steuerSatz(S), ohneF = Math.round(q * Math.max(0, L - R.FREIBETRAG)), mitF = Math.round(q * Math.max(0, L - R.FREIBETRAG - R.RENTNER_FREIBETRAG));   // Haushalt: heutiger Satz
      // Eine Pleite anderswo in derselben Nacht ändert an d nichts (Löhne sind vorher gezahlt); ging d's Betrieb pleite, fehlt arbeit
      pruef(P().arbeit[d] === b && dd('rentnerLohnTage') === 1 && dd('rentnerEntlastung') === ohneF - mitF
        && dd('rentenkasse') === e.rentner * stufe && Sim.personInfo(S, d).rente.bezieht && Sim.erlaubteAktionen(S, d, 7).includes('kuendigen'),
        `67 mit Stelle (${Sim.name(S, d)}, Lohn ${L}): bleibt angestellt, bekommt ${stufe} Taler Rente, zahlt ${mitF} statt ${ohneF} Taler Steuer (Entlastung ${dd('rentnerEntlastung')}), darf aufhören`);
    }
  }
  // 7. Schritt 2, Mieterkauf (Seeds wie oben, bis Tag 250): Käufe mit Anzahlung, Invariante jede Nacht, Rate, Erbe, Auflösung, Umzug,
  //    Zusammenziehen, Wegzug der Eltern mit erwachsenem Kind, 60 Tage weiter, Buchungen im Budget
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}: Schritt 2, Mieterkauf`);
    ctxR.__buchung = 0;
    const S = Sim.neueStadt(seed), P = () => S.p, rs = () => S.stat.regierung;
    const inv = () => { let f = 0; for (let x = 0; x < S.pMax; x++) { const e = P().eigen[x]; if (!e) continue;
      if (!P().lebt[x] || P().hh[x] !== x || P().wohnung[x] !== e - 1 || P().schuld[x] > P().kaufPreis[x] || S.g.typ[e - 1] !== Sim.WOHNHAUS) f++; } return f; };
    let invFehl = 0, anFehl = 0, neu = 0, erste = null, jahre = 0;
    while (S.tag < 250) {
      const t = S.tag, vor = Uint8Array.from({ length: S.pMax }, (_, x) => (P().eigen[x] ? 1 : 0));
      while (S.tag === t) Sim.stunde(S);
      invFehl += inv();
      for (let x = 0; x < S.pMax; x++) if (!(x < vor.length && vor[x]) && P().eigen[x]) {
        neu++; if (P().kaufPreis[x] - P().schuld[x] < Math.ceil(R.EIGEN_ANZAHLUNG * P().kaufPreis[x])) anFehl++;
      }
      const zeilen = S.buch.filter(e => e.tag === t && e.art === 'regierung').map(e => Sim.klartext(e.text));
      if (!erste && rs().kaeufe) erste = zeilen.find(z => /^Als erste(r Haushalt kauft| Haushalte kaufen)/.test(z)) || '–';
      if (zeilen.some(z => z.startsWith('Im letzten Jahr')) && (t + 1) % J === 0) jahre++;
    }
    const eig = []; for (let x = 0; x < S.pMax; x++) if (P().lebt[x] && Sim.eigentuemer(S, x)) eig.push(x);
    pruef(neu > 0 && eig.length > 0 && !invFehl && !anFehl && erste !== '–' && jahre > 0,
      `bis Tag 250: ${rs().kaeufe} Käufe, ${eig.length} Eigentümer; jede Nacht Eigentum nur beim Vorstand in seiner Wohnung (${invFehl} Verstöße), `
      + `Anzahlung ≥ ${R.EIGEN_ANZAHLUNG * 100} % (${anFehl} Fehler); Stadtbuch „${erste}“, ${jahre} Jahreszeilen`);
    const frei = (x) => P().lebt[x] && !Sim.istHaupt(S, x) && P().besitz[x] < 0;
    const alleinE = eig.filter(x => frei(x) && S.hhGroesse[x] === 1 && P().partner[x] < 0);
    // Rate = Kaufpreis / 200 bis zur Tilgung, danach 0
    {
      const m = eig.find(x => P().schuld[x] > 0), s0 = P().schuld[m], rate = Math.min(s0, Math.round(P().kaufPreis[m] / 200));
      const r1 = Sim.miete(S, m), tk1 = Sim.tageskosten(S, m);
      P().schuld[m] = 0; const r2 = Sim.miete(S, m), tk2 = Sim.tageskosten(S, m); P().schuld[m] = s0;
      pruef(m !== undefined && r1 === rate && r2 === 0 && tk1 - tk2 === rate, `Rate ${r1} Taler (Kaufpreis ${P().kaufPreis[m]} / 200), nach der Tilgung 0; Tageskosten ${tk1} → ${tk2}`);
    }
    // Erbe: Der Vorstand stirbt, der Partner übernimmt Wohnung, Rest und Rate; das Budget bleibt gleich
    {
      const k = eig.find(x => frei(x) && P().partner[x] >= 0 && P().hh[P().partner[x]] === x && frei(P().partner[x]));
      if (k === undefined) pruef(false, 'Erbe: kein Eigentümer-Paar gefunden');
      else {
        const pa = P().partner[k], e0 = [P().eigen[k], P().kaufPreis[k], P().schuld[k]], b0 = S.budget, ef0 = rs().erbfaelle;
        Sim._pruef.sterben(S, k);
        pruef(P().eigen[pa] === e0[0] && P().kaufPreis[pa] === e0[1] && P().schuld[pa] === e0[2] && Sim.eigentuemer(S, pa) && S.budget === b0
          && rs().erbfaelle === ef0 + 1 && !P().eigen[k], `Erbe: ${Sim.name(S, pa)} übernimmt die Wohnung (${e0[1]} Taler, Rest ${e0[2]}), Budget unverändert`);
      }
    }
    // Auflösung: ein allein lebender Eigentümer stirbt; die Stadt kauft zum bezahlten Betrag zurück, die Wohnung ist wieder frei
    {
      const k = alleinE[0];
      if (k === undefined) pruef(false, 'Auflösung: kein allein lebender Eigentümer gefunden');
      else {
        const w = P().wohnung[k], bez = P().kaufPreis[k] - P().schuld[k], b0 = S.budget, bel0 = S.g.belegt[w], fw0 = S.freieWohnungen, ra0 = rs().rkAufgeloest, su0 = rs().rueckkaufSumme;
        Sim._pruef.sterben(S, k);
        pruef(S.budget === b0 - bez && S.g.belegt[w] === bel0 - 1 && S.freieWohnungen === fw0 + 1 && rs().rkAufgeloest === ra0 + 1 && rs().rueckkaufSumme === su0 + bez,
          `Auflösung: Rückkauf für ${bez} Taler aus dem Budget, die Wohnung ist wieder frei (belegt ${bel0} → ${S.g.belegt[w]})`);
      }
    }
    // Umzug: der Haushalt eines Eigentümers zieht um; das Geld kommt zurück, die neue Wohnung ist gemietet
    {
      // der erste allein lebende Eigentümer, für den es in der Nähe eine freie Wohnung gibt
      const frei = (x) => { const w = P().wohnung[x]; return Sim._pruef.freieWohnungNahe(S, S.g.x[w], S.g.y[w], w, 1); };
      const k = alleinE.find(x => P().lebt[x] && Sim.eigentuemer(S, x) && frei(x) >= 0);
      const b = k === undefined ? -1 : frei(k);
      if (b < 0) pruef(false, 'Umzug: kein Eigentümer mit freier Wohnung in der Nähe');
      else {
        const bez = P().kaufPreis[k] - P().schuld[k], g0 = P().geld[k], ru0 = rs().rkUmzug;
        Sim._pruef.haushaltUmziehen(S, k, b);
        pruef(P().geld[k] === g0 + bez && rs().rkUmzug === ru0 + 1 && !P().eigen[k] && P().wohnung[k] === b && Sim.miete(S, k) === R.MIETE[S.g.stufe[b]],
          `Umzug: ${bez} Taler zurück, neue Wohnung zur Miete (${Sim.miete(S, k)} Taler)`);
      }
    }
    // Zusammenziehen: zwei Eigentümer – wer zieht, behält seine Wohnung, die andere kauft die Stadt zurück; gehört nur einem eine, zieht
    // das Paar dorthin (kein Rückkauf)
    {
      const L = alleinE.filter(x => P().lebt[x] && Sim.eigentuemer(S, x) && P().partner[x] < 0);
      if (L.length < 3) pruef(false, `Zusammenziehen: zu wenige allein lebende Eigentümer (${L.length})`);
      else {
        const [p, q] = L, bq = P().kaufPreis[q] - P().schuld[q], gq = P().geld[q], rz0 = rs().rkZusammen, ep = P().eigen[p];
        P().partner[p] = q; P().partner[q] = p;
        Sim._pruef.aktZusammen(S, p);
        const ok1 = P().eigen[p] === ep && Sim.eigentuemer(S, p) && !P().eigen[q] && P().geld[q] === gq + bq && rs().rkZusammen === rz0 + 1
          && P().wohnung[q] === P().wohnung[p] && P().hh[q] === p;
        let m = -1;
        for (let x = 0; x < S.pMax; x++) if (frei(x) && P().hh[x] === x && S.hhGroesse[x] === 1 && P().partner[x] < 0 && !P().eigen[x] && S.tag - P().geb[x] >= R.ERWACHSEN * J) { m = x; break; }
        const q2 = L[2], wq = P().wohnung[q2];
        P().partner[m] = q2; P().partner[q2] = m;
        Sim._pruef.aktZusammen(S, m);
        const ok2 = m >= 0 && P().hh[m] === q2 && P().wohnung[m] === wq && Sim.eigentuemer(S, q2) && rs().rkZusammen === rz0 + 1;
        pruef(ok1 && ok2, `Zusammenziehen: zwei Eigentümer → ${Sim.name(S, q)} bekommt ${bq} Taler zurück; Mieter zu Eigentümer → ${m >= 0 ? Sim.name(S, m) : '–'} zieht in die gekaufte Wohnung`);
      }
    }
    // Wegzug der Eltern mit erwachsenem Kind im Haushalt: das Kind übernimmt die Wohnung (sonst gezielt hergestellt)
    {
      let k = -1, m = -1, gestellt = false;
      for (const x of eig) {
        if (!P().lebt[x] || !Sim.eigentuemer(S, x) || !frei(x)) continue;
        const kind = S.bewohner[P().wohnung[x]].find(y => P().hh[y] === x && y !== x && y !== P().partner[x] && S.tag - P().geb[y] >= R.ERWACHSEN * J);
        if (kind !== undefined) { k = x; m = kind; break; }
      }
      if (k < 0) {
        k = eig.find(x => P().lebt[x] && Sim.eigentuemer(S, x) && frei(x) && P().partner[x] >= 0 && P().hh[P().partner[x]] === x) ?? -1;
        for (let x = 0; x < S.pMax && k >= 0; x++) if (frei(x) && P().hh[x] === x && S.hhGroesse[x] === 1 && P().partner[x] < 0 && !P().eigen[x] && S.tag - P().geb[x] >= R.ERWACHSEN * J) { m = x; break; }
        if (k >= 0 && m >= 0) { Sim._pruef.einzelnZu(S, m, k); gestellt = true; }
      }
      if (k < 0 || m < 0) pruef(false, 'Wegzug mit erwachsenem Kind: kein Fall');
      else {
        const e0 = [P().eigen[k], P().kaufPreis[k], P().schuld[k]], b0 = S.budget, ef0 = rs().erbfaelle;
        Sim._pruef.aktWegziehen(S, k);
        pruef(!P().lebt[k] && P().eigen[m] === e0[0] && P().kaufPreis[m] === e0[1] && P().schuld[m] === e0[2] && Sim.eigentuemer(S, m) && S.budget === b0 && rs().erbfaelle === ef0 + 1,
          `Wegzug der Eltern: ${Sim.name(S, m)} bleibt und übernimmt die Wohnung${gestellt ? ' (Fall gezielt hergestellt: erwachsene Person im Haushalt)' : ' (erwachsenes Kind)'}`);
      }
    }
    // 60 Tage weiter: Invariante jede Nacht, keine NaN, Rückkauf nie gekürzt, jede Budgetbuchung des Mieterkaufs gezählt
    {
      const ziel = S.tag + 60;
      let f = 0;
      while (S.tag < ziel) { const t = S.tag; while (S.tag === t) Sim.stunde(S); f += inv(); }
      const nan = !Number.isFinite(S.budget) || Object.values(S.stat.regierung).some(v => !Number.isFinite(v));
      const soll = rs().anzahlung + rs().tilgung - rs().rueckkaufSumme;
      pruef(!f && !nan && rs().rueckkaufFehlt === 0 && ctxR.__buchung === soll,
        `60 Tage weiter (Tag ${S.tag}): Invariante ${f} Verstöße, keine NaN, Rückkauf nie gekürzt; Budget: Anzahlungen ${rs().anzahlung} + Raten ${rs().tilgung} − Rückkäufe ${rs().rueckkaufSumme} = ${soll} = gebucht ${ctxR.__buchung}`);
    }
  }
  // Version 8 (Befund 4 der Gegenprüfung „sim“): Jedes Programmzitat steht im Fenster nur an einer Stelle (Regelkarte, „gilt schon“ oder
  // „nicht“), damit derselbe Satz nicht einmal „gilt schon“ und einmal „wirkt“ heißt. Ausnahme seit Version 7: die Gruppe „Grenze der Stadt“
  // wiederholt die Sätze der Bund-Karten, deren Forderung die Stadt nicht übernimmt (Wehrdienst nur für Deutsche, Aufgaben des BND)
  {
    const a = html.indexOf('const REGIERUNG = '), b = html.indexOf('// Ende REGIERUNG');
    const REG = new Function(html.slice(a, b).replace('const REGIERUNG = ', 'return ').replace(/;\s*$/, ''))();
    const orte = new Map(), dazu = (t, wo) => { const k = String(t).trim(); orte.set(k, [...(orte.get(k) || []), wo]); };
    for (const [, regeln] of REG.gruppen) for (const r of regeln) for (const [t] of r.zitate) dazu(t, 'Karte ' + r.titel);
    for (const [t] of REG.giltSchon) dazu(t, 'gilt schon');
    for (const g of REG.nicht) for (const [t] of g.punkte) dazu(t, 'nicht: ' + g.titel);
    const doppelt = [...orte].filter(([, w]) => w.length > 1), erlaubt = doppelt.filter(([, w]) => w.length === 2 && w.some(x => x === 'nicht: Grenze der Stadt') && w.some(x => x.startsWith('Karte ')));
    const auto = ['Abschaffung der CO₂-Abgabe', 'Subvention von Techniken', 'Verbrenner', 'Individualverkehr'];
    const autoOrte = auto.map(s => [...orte].filter(([t]) => t.includes(s)).map(([, w]) => w.join(' + ')).join('; '));
    pruef(a > 0 && b > a && orte.size > 100 && doppelt.length === erlaubt.length,
      `Fenster: ${orte.size} Programmzitate, jedes an einer Stelle (erlaubt doppelt: ${erlaubt.length}, „Grenze der Stadt“)`
      + (doppelt.length > erlaubt.length ? '; DOPPELT: ' + doppelt.filter(d => !erlaubt.includes(d)).map(([t, w]) => `„${t.slice(0, 50)}…“ (${w.join(', ')})`).join('; ') : '')
      + `; Autos: ${autoOrte.join(' | ')}`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen der Stadtregierung bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('kita')) {
  // Kitas (Schritt 2). Eine Kopie der Simulation mit Testhilfen, die nur mitlesen: __kitaVergabe (nach der Vergabe, vor den
  // Betreuungslücken), __kitaEnde (am Ende von kitaTag), __betr (jeder Haushalt, der in bundesGeld Betreuungsgehalt bekommt), dazu
  // __ohneJob (diese Person sucht keine Stelle, für den erzwungenen Fall g). Sonst gleich.
  const { Sim, ctx } = ladeSimMit([
    ['  // Betreuungslücke (Annahme der Stadt)', '  if (globalThis.__kitaVergabe) globalThis.__kitaVergabe(S, L, rang, warten, frist);\n  // Betreuungslücke (Annahme der Stadt)'],
    ['  return { warten, bedarf };', '  if (globalThis.__kitaEnde) globalThis.__kitaEnde(S, neu, bedarf, frist);\n  return { warten, bedarf };'],
    ['      P.geld[m] += R.NETTO_STANDARD; rs.betreuung += R.NETTO_STANDARD; rs.betreuungTage++;\n',
      '      P.geld[m] += R.NETTO_STANDARD; rs.betreuung += R.NETTO_STANDARD; rs.betreuungTage++; if (globalThis.__betr) globalThis.__betr(S, k);\n'],
    ['  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p)) {\n',
      '  if (erwerb && (arb < 0 || gem) && !istBesitzer && S.freieStellen > 0 && !rentner(S, p) && !gebunden(S, p) && p !== globalThis.__ohneJob) {\n'],
  ]);
  ctx.__ohneJob = -1;
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, KITA = Sim.KITA;
  const dist = (S, a, b) => Math.abs(S.g.x[a] - S.g.x[b]) + Math.abs(S.g.y[a] - S.g.y[b]);
  const einh = (S, k) => (S.tag - S.p.geb[k] < R.KRIPPE_BIS ? 2 : 1);
  const offenK = (S, b) => S.g.typ[b] === KITA && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === KITA;
  const tagWeiter = (S) => { const t = S.tag; while (S.tag === t) Sim.stunde(S); };
  // Personal einer Kita entfernen (wie eine Kündigung aller, die Stellen zählen nachts neu)
  const personalWeg = (S, b) => { for (const w of S.belegschaft[b]) { S.p.arbeit[w] = -1; S.p.einsatz[w] = 0; } const n = S.belegschaft[b].length; S.belegschaft[b] = []; return n; };
  let summeOhne = 0, summeKitaOhne = 0;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed);
    let vor = new Uint16Array(0), vorB = new Uint8Array(0);  // Kita-Plätze und belegte Einheiten vor der Nacht (Kopie um 23 Uhr)
    const z = { naechte: 0, plaetze: 0, altersFehl: 0, weitFehl: 0, summeFehl: 0, kapFehl: 0, personalFehl: 0, lohnFehl: 0, vorrangFehl: 0, vorrang: 0,
      luecke: 0, lueckeFehl: 0, ohne: 0, fern: 0, betr: 0, betrFehl: 0, gebunden: 0, gebundenFehl: 0, zeilenFehl: 0, maxKitas: 0, maxWarten: 0,
      halten: 0, endeFehl: 0, weniger: 0, obhut: 0 };
    // Bestand (Annahme): belegt ≤ halt = max(möglich, belegt gestern − 8), solange die Kita Personal hat, sonst 0
    const halt = (S, b) => S.g.kapaz[b] > 0 ? Math.max(S.g.kapaz[b], (vorB[b] || 0) - R.KITA_JE_KRAFT) : 0;
    let personalStart = new Map();
    ctx.__kitaVergabe = (S, L, rang, warten) => {
      const P = S.p, g = S.g, summe = new Map();
      personalStart = new Map();
      // (a) Plätze nur im Kita-Alter, in einer Kita höchstens 12 Felder von der Wohnung; Summe der Einheiten = belegt ≤ halt,
      //     möglich ≤ min(40, 8 × Personal); mehr belegt als möglich nur im Bestand, wenn Personal ging
      for (let k = 0; k < S.pMax; k++) {
        if (!P.lebt[k] || !P.kita[k]) continue;
        const b = P.kita[k] - 1;
        z.plaetze++;
        if (S.tag - P.geb[k] >= R.KITA_ENDE) z.altersFehl++;
        if (g.typ[b] !== KITA || dist(S, b, P.wohnung[k]) > R.REICH_KITA) z.weitFehl++;
        summe.set(b, (summe.get(b) || 0) + einh(S, k));
      }
      let kitas = 0;
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== KITA) continue;
        if (offenK(S, b)) kitas++;
        personalStart.set(b, S.belegschaft[b].length);
        if ((summe.get(b) || 0) !== g.bedient[b]) z.summeFehl++;
        if (g.bedient[b] > halt(S, b) || g.kapaz[b] > Math.min(R.KITA_PLAETZE, R.KITA_JE_KRAFT * S.belegschaft[b].length)) z.kapFehl++;
        if (g.bedient[b] > g.kapaz[b]) z.halten++;
        if (S.belegschaft[b].length > R.KITA_STELLEN || g.soll[b] > R.KITA_STELLEN) z.personalFehl++;
        if (offenK(S, b) && (g.lohn[b] < R.LOHN_STADT || g.lohn[b] > R.BAU_LOHN_MAX)) z.lohnFehl++;
      }
      z.maxKitas = Math.max(z.maxKitas, kitas); z.maxWarten = Math.max(z.maxWarten, warten.length);
      // (e) Vorrang: Kein Kind der Stufe 2 bekommt heute einen neuen Platz in Kita b, während ein Kind der Stufe 1 in Reichweite von b
      // wartet, das dort ohne die neuen Kinder der Stufe 2 Platz gehabt hätte
      const neu2 = new Map();
      for (const k of L) if (rang.get(k) === 2 && P.kita[k] && P.kita[k] !== (vor[k] || 0)) neu2.set(P.kita[k] - 1, (neu2.get(P.kita[k] - 1) || 0) + einh(S, k));
      for (const k of warten) {
        if (rang.get(k) !== 1) continue;
        z.vorrang++;
        for (const [b, e] of neu2) if (dist(S, b, P.wohnung[k]) <= R.REICH_KITA && g.kapaz[b] - g.bedient[b] + e >= einh(S, k)) z.vorrangFehl++;
      }
    };
    ctx.__kitaEnde = (S, neu, bedarf, frist) => {
      // (c) Nach der Nacht hat jedes Kind unter 6 ohne Platz einen Erwachsenen des Haushalts ohne Stelle zu Hause; sonst arbeiten von
      // Vorstand und Partner nur Besitzer oder gemeinnützig, oder in der Nähe ist gar keine Kita offen (beides nur gezählt). In der
      // Übergangsfrist nach einer Übernahme gilt das nicht
      const P = S.p, erw = S.tag - R.ERWACHSEN * J, gesehen = new Set(), g = S.g;
      // (a) auch am Ende der Nacht: Wer unten aufhört und in einer Kita arbeitet, fehlt ihr erst ab der nächsten Nacht (Plätze der Nacht bleiben)
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== KITA) continue;
        const n0 = personalStart.get(b) || 0;
        if (g.bedient[b] > halt(S, b) || g.kapaz[b] > Math.min(R.KITA_PLAETZE, R.KITA_JE_KRAFT * n0)) z.endeFehl++;
        if (S.belegschaft[b].length < n0) z.weniger++;
      }
      for (let k = 0; k < S.pMax; k++) {
        if (!P.lebt[k] || P.kita[k] || S.tag - P.geb[k] >= R.KITA_ENDE || P.hh[k] < 0 || P.wohnung[k] < 0) continue;
        if (P.obhut[k]) { z.obhut++; continue; }              // Sicherheit: in Obhut (Angehörige oder Jugendamt), der Haushalt ist in Haft
        const kopf = P.hh[k];
        if (gesehen.has(kopf)) continue;
        gesehen.add(kopf);
        let heim = false, angestellt = false;
        for (const m of S.bewohner[P.wohnung[k]]) {
          if (P.hh[m] !== kopf || P.geb[m] > erw) continue;
          if (P.arbeit[m] < 0 && !P.haftBis[m]) heim = true;   // Sicherheit: in Haft ist niemand zu Hause
          // Bund (B10): wer Wehr- oder Ersatzdienst leistet oder als Soldat verpflichtet ist, muss nicht aufhören (wie Besitzer, gezählt)
          // Bürgermeister (Version 9, Teil 1): im Amt gebunden wie im Dienst des Bundes (kitaTag: !istBm); der Fall kam erst mit Teil 5 in der Teststadt vor
          else if ((m === kopf || m === P.partner[kopf]) && P.besitz[m] < 0 && !P.gemein[m] && P.bund[m] < Sim.WEHRDIENST && !Sim.verpflichtet(S, m) && !Sim.istBm(S, m)) angestellt = true;
        }
        z.luecke++;
        if (heim) continue;
        let nah = false;                                     // wie in kitaTag: erst „keine Kita mit Plätzen in der Nähe“, dann „nur Besitzer“
        for (let b = 0; b < S.gAnzahl && !nah; b++) if (offenK(S, b) && S.g.kapaz[b] > 0 && dist(S, b, P.wohnung[k]) <= R.REICH_KITA) nah = true;
        if (!nah) { if (!frist) z.fern++; continue; }
        if (!angestellt) { if (!frist) z.ohne++; continue; }
        if (!frist) z.lueckeFehl++;
      }
    };
    // (b) Betreuungsgehalt nur, wenn im Haushalt ein Kind unter 3 ohne Kita-Platz lebt (Stand in bundesGeld, vor der Vergabe der Nacht)
    let bezahlt = new Set();
    ctx.__betr = (S, k) => {
      const P = S.p; z.betr++; bezahlt.add(k);
      if (!S.bewohner[P.wohnung[k]].some(m => P.hh[m] === k && S.tag - P.geb[m] < R.BETREUUNG_ALTER && !P.kita[m])) z.betrFehl++;
    };
    while (S.tag < 400) {
      if (S.stunde === 7 || S.stunde === 18) {                // (d) wer gebunden ist, bekommt kein job_suchen und kein laden_gruenden
        for (let p = 0; p < S.pMax; p++) {
          if (!S.p.lebt[p] || !Sim.gebunden(S, p)) continue;
          z.gebunden++;
          const L = Sim.erlaubteAktionen(S, p, S.stunde);
          if (L.includes('job_suchen') || L.includes('laden_gruenden')) z.gebundenFehl++;
        }
      }
      if (S.stunde === 23) { vor = S.p.kita.slice(0, S.pMax); vorB = S.g.bedient.slice(0, S.gAnzahl); bezahlt = new Set(); }
      const t = S.tag, nr0 = S.buchNr;
      Sim.stunde(S);
      if (S.tag !== t) { z.naechte++; if (S.buch.filter(e => e.nr > nr0 && e.art === 'kita').length > 1) z.zeilenFehl++; }
    }
    const rs = S.stat.regierung;
    pruef(z.naechte === 400 && z.plaetze > 0 && !z.altersFehl && !z.weitFehl, `(a) ${z.plaetze} Kindnächte mit Platz: nur unter ${R.KITA_ENDE / J} Jahren, höchstens ${R.REICH_KITA} Felder (${z.altersFehl + z.weitFehl} Fehler)`);
    pruef(!z.summeFehl && !z.kapFehl && !z.personalFehl && !z.lohnFehl && z.maxKitas > 0,
      `(a) je Kita: Einheiten = belegt ≤ max(möglich, belegt gestern − ${R.KITA_JE_KRAFT}), möglich ≤ min(${R.KITA_PLAETZE}, ${R.KITA_JE_KRAFT} × Personal), Personal und Stellen ≤ ${R.KITA_STELLEN}, Lohn ${R.LOHN_STADT}–${R.BAU_LOHN_MAX} `
      + `(bis ${z.maxKitas} Kitas offen, ${S.stat.bauamt.kitas} gebaut; ${z.halten} Kita-Nächte mit mehr belegt als möglich; ${z.summeFehl + z.kapFehl + z.personalFehl + z.lohnFehl} Fehler)`);
    pruef(!z.endeFehl, `(a) dasselbe am Ende der Nacht, nach den Stellenaufgaben (${z.weniger}-mal hatte eine Kita danach weniger Personal; ${z.endeFehl} Fehler)`);
    pruef(z.betr > 0 && !z.betrFehl, `(b) Betreuungsgehalt nur mit Kind unter 3 ohne Platz: ${z.betr} Haushaltstage (${z.betrFehl} Fehler)`);
    pruef(z.luecke > 0 && !z.lueckeFehl && z.fern === rs.kitaFern, `(c) nach jeder Nacht: ${z.luecke} Haushaltsnächte mit Kind ohne Platz, alle mit jemandem zu Hause, nur Besitzern, gemeinnützig oder im Dienst des Bundes `
      + `(${z.ohne}, gezählt ${rs.kitaOhne}) oder ohne Kita mit Plätzen (offen, mit Personal) in der Nähe (${z.fern}, gezählt ${rs.kitaFern}); ${rs.kitaLuecke}-mal gab ein Elternteil die Stelle auf; ${z.obhut} Kindnächte in Obhut (${z.lueckeFehl} Fehler)`);
    pruef(!z.gebundenFehl, `(d) ${z.gebunden}-mal gebunden um 7 oder 18 Uhr, nie job_suchen oder laden_gruenden erlaubt (${z.gebundenFehl} Fehler)`);
    pruef(z.vorrang > 0 && !z.vorrangFehl, `(e) Vorrang: ${z.vorrang} wartende Kinder der Stufe 1 geprüft, keins hinter einem neuen Platz der Stufe 2 (${z.vorrangFehl} Fehler; bis ${z.maxWarten} Kinder warteten)`);
    pruef(!z.zeilenFehl, `Stadtbuch: höchstens eine Zeile „Kita“ je Nacht (${S.buch.filter(e => e.art === 'kita').length} im Buch, ${z.zeilenFehl} Fehler)`);
    summeOhne += z.ohne; summeKitaOhne += rs.kitaOhne;
    // Speichern und Laden mit Kitas: bitgleich
    {
      const L = ladenAusText(Sim, speichernAlsText(Sim, S)), A2 = ladenAusText(Sim, speichernAlsText(Sim, S));
      for (let i = 0; i < 24 * 20; i++) { Sim.stunde(L); Sim.stunde(A2); }
      pruef(fingerabdruck(Sim, L) === fingerabdruck(Sim, A2) && L.p.kita.some(v => v > 0), 'Speichern/Laden mit Kita-Plätzen: 20 Tage weiter bitgleich');
    }
    ctx.__kitaVergabe = null; ctx.__kitaEnde = null; ctx.__betr = null;
    const kitaStand = speichernAlsText(Sim, S);                // für (h): die Stadt vor den erzwungenen Fällen (g) und (f), die Kitas Personal nehmen
    // (g) Erzwungen: Ein Elternteil eines Kindes unter 3 mit Krippenplatz verliert um 23 Uhr die Stelle (niemand sonst zu Hause). In der Nacht
    //     verliert das Kind den Platz, Betreuungsgehalt gibt es erst in der Nacht danach (bundesGeld kommt vor der Vergabe)
    {
      while (S.stunde !== 23) Sim.stunde(S);
      const P = S.p, erw = S.tag - R.ERWACHSEN * J;
      let fall = null;
      for (let k = 0; k < S.pMax && !fall; k++) {
        if (!P.lebt[k] || !P.kita[k] || S.tag + 2 - P.geb[k] >= R.KRIPPE_BIS || P.hh[k] < 0) continue;
        const kopf = P.hh[k], pa = P.partner[kopf], ms = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === kopf && P.geb[m] <= erw);
        if (ms.some(m => P.arbeit[m] < 0) || P.besitz[kopf] >= 0 || P.gemein[kopf] || Sim.anspruch(S, kopf)) continue;
        const m = pa >= 0 && P.hh[pa] === kopf ? pa : kopf;
        if (P.besitz[m] >= 0 || P.gemein[m] || Sim.anspruch(S, m) || Sim.istHaupt(S, m)) continue;
        fall = { k, kopf, m };
      }
      if (!fall) pruef(false, '(g) kein Kind unter 3 mit Krippenplatz, dessen Eltern beide arbeiten');
      else {
        const { k, kopf, m } = fall, b = P.arbeit[m];
        for (let p = 0; p < S.pMax; p++) P.jetzt[p] = 0;
        S.belegschaft[b].splice(S.belegschaft[b].indexOf(m), 1); P.arbeit[m] = -1; P.einsatz[m] = 0;
        ctx.__ohneJob = m;
        const betr1 = new Set(); ctx.__betr = (S, h) => betr1.add(h);
        Sim.stunde(S);                                         // Nacht 1
        const nacht1 = { platz: S.p.kita[k], bezahlt: betr1.has(kopf) };
        const betr2 = new Set(); ctx.__betr = (S, h) => betr2.add(h);
        tagWeiter(S);                                          // Tag danach und Nacht 2
        ctx.__betr = null; ctx.__ohneJob = -1;
        const ok = nacht1.platz === 0 && !nacht1.bezahlt && S.p.lebt[k] && S.p.kita[k] === 0 && betr2.has(kopf) && Sim.betreuer(S, kopf) >= 0;
        pruef(ok || (S.p.arbeit[m] >= 0), `(g) ${Sim.name(S, m)} ohne Stelle: Nacht 1 Platz ${nacht1.platz ? 'noch da' : 'weg'}, Betreuungsgehalt ${nacht1.bezahlt ? 'ja' : 'nein'}; `
          + `Nacht 2 Betreuungsgehalt ${betr2.has(kopf) ? 'ja' : 'nein'} (an ${Sim.betreuer(S, kopf) >= 0 ? Sim.name(S, Sim.betreuer(S, kopf)) : '–'})${S.p.arbeit[m] >= 0 ? ', hat inzwischen wieder Arbeit' : ''}`);
      }
    }
    // (f1) Erzwungen: Alle Leute einer Kita und der Kitas bis 24 Felder weiter sind um 23 Uhr weg (die Kitas bleiben offen). In der Nacht hat
    //      dort niemand mehr einen Platz, und weil in der Nähe keine Kita mehr Plätze anbietet, muss deshalb niemand aufhören (nur gezählt)
    {
      while (S.stunde !== 23) Sim.stunde(S);
      let kb = -1;
      for (let b = 0; b < S.gAnzahl; b++) if (offenK(S, b) && S.belegschaft[b].length && S.g.bedient[b] > 0) { kb = b; break; }
      if (kb < 0) pruef(false, '(f1) keine Kita mit Personal und Kindern');
      else {
        const kinder = []; for (let k = 0; k < S.pMax; k++) if (S.p.lebt[k] && S.p.kita[k] === kb + 1) kinder.push(k);
        for (let p = 0; p < S.pMax; p++) S.p.jetzt[p] = 0;
        let n = 0;
        for (let b = 0; b < S.gAnzahl; b++) if (offenK(S, b) && dist(S, b, kb) <= 2 * R.REICH_KITA) n += personalWeg(S, b);
        const f0 = S.stat.regierung.kitaFern;
        let aufgegeben = [];
        ctx.__kitaEnde = (S, neu) => { aufgegeben = neu.map(([, k]) => k); };
        Sim.stunde(S);
        ctx.__kitaEnde = null;
        const P = S.p, erw = S.tag - R.ERWACHSEN * J, set = new Set(kinder);
        let heim = 0, fern = 0, gross = 0, falsch = 0;
        for (const k of kinder) {
          if (!P.lebt[k] || P.hh[k] < 0) continue;
          if (S.tag - 1 - P.geb[k] >= R.KITA_ENDE) { gross++; continue; }   // in dieser Nacht 6 geworden
          if (P.kita[k]) { falsch++; continue; }
          const ms = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === P.hh[k] && P.geb[m] <= erw);
          if (ms.some(m => P.arbeit[m] < 0)) heim++; else fern++;
        }
        const wegen = aufgegeben.filter(k => set.has(k)).length;
        pruef(!falsch && !wegen && S.stat.regierung.kitaFern - f0 >= fern, `(f1) Kita ${kb} und Kitas in der Nähe ohne ihre ${n} Leute: ${kinder.length} Kinder hatten dort Platz, jetzt keins mehr; `
          + `${heim} mit jemandem zu Hause, ${fern} ohne Kita-Angebot in der Nähe (gezählt ${S.stat.regierung.kitaFern - f0})${gross ? `, ${gross} jetzt 6 Jahre alt` : ''}; wegen dieser Kinder gab niemand die Stelle auf (${falsch + wegen} Fehler)`);
      }
    }
    // (f2) Erzwungen (auf einer Kopie): Eine Kita mit mindestens 17 belegten Einheiten verliert um 23 Uhr alle Fachkräfte bis auf eine. In der
    //      Nacht fallen höchstens 8 belegte Einheiten weg (Bestand, Annahme wie eine Kündigungsfrist), kein Kind bekommt dort neu einen
    //      Platz, die Kita schreibt Stellen aus; in der Nacht danach wieder höchstens 8 weniger
    {
      let kb = -1;
      for (let versuch = 0; versuch < 60 && kb < 0; versuch++) {
        while (S.stunde !== 23) Sim.stunde(S);
        for (let b = 0; b < S.gAnzahl; b++) if (offenK(S, b) && S.belegschaft[b].length >= 3 && S.g.bedient[b] >= 17) { kb = b; break; }
        if (kb < 0) Sim.stunde(S);
      }
      if (kb < 0) pruef(false, '(f2) keine Kita mit mindestens 3 Fachkräften und 17 belegten Einheiten');
      else {
        const S2 = ladenAusText(Sim, speichernAlsText(Sim, S)), P = S2.p, g = S2.g, b0 = g.bedient[kb];
        for (let p = 0; p < S2.pMax; p++) P.jetzt[p] = 0;
        const L = S2.belegschaft[kb];
        while (L.length > 1) { const w = L.pop(); P.arbeit[w] = -1; P.einsatz[w] = 0; }
        const vorher = new Set(); for (let k = 0; k < S2.pMax; k++) if (P.lebt[k] && P.kita[k] === kb + 1) vorher.add(k);
        Sim.stunde(S2);
        let verloren = 0, neuDa = 0;
        for (let k = 0; k < S2.pMax; k++) {
          if (!P.lebt[k]) continue;
          if (P.kita[k] === kb + 1 && !vorher.has(k)) neuDa++;
          if (vorher.has(k) && P.kita[k] !== kb + 1 && S2.tag - 1 - P.geb[k] < R.KITA_ENDE) verloren += S2.tag - 1 - P.geb[k] < R.KRIPPE_BIS ? 2 : 1;
        }
        const b1 = g.bedient[kb], cap1 = g.kapaz[kb], soll1 = g.soll[kb];
        let b2 = -1, ok2 = true;
        if (S2.belegschaft[kb].length) { const t = S2.tag; while (S2.tag === t) Sim.stunde(S2); b2 = g.bedient[kb]; ok2 = b2 <= Math.max(g.kapaz[kb], b1 - R.KITA_JE_KRAFT); }
        pruef(cap1 === R.KITA_JE_KRAFT && b1 <= Math.max(cap1, b0 - R.KITA_JE_KRAFT) && verloren <= R.KITA_JE_KRAFT + 1 && b1 > cap1 && !neuDa && soll1 > 1 && ok2,
          `(f2) Kita ${kb}: ${b0} Einheiten belegt, alle Fachkräfte bis auf eine weg → Nacht 1: ${b1} belegt bei ${cap1} möglich (${verloren} Einheiten verloren, ${neuDa} Kinder neu), `
          + `${soll1} Stellen; Nacht 2: ${b2 < 0 ? 'keine Fachkraft mehr' : `${b2} belegt`}`);
      }
    }
    // (h) Erzwungen (auf Kopien): Ein Kind unter 6 zieht zu jemandem, der nur seinen eigenen Betrieb hat (kein Partner, sonst niemand); die
    //     Kitas in der Nähe mit mindestens 17 belegten Einheiten behalten eine Fachkraft (dann voll), die übrigen verlieren alle. Niemand gibt
    //     etwas auf, es wird nur gezählt (kitaOhne). Besitzer und Kind werden der Reihe nach probiert, bis ein Fall passt; gibt es an Tag 400
    //     keinen Besitzer mit so einer Kita in der Nähe, am nächsten Abend wieder (höchstens 60 Tage; Version 8: anderer Verlauf der Städte).
    //     Version 9, Teil 3: gesucht wird in der Stadt vor (g) und (f) (kitaStand): Deren erzwungene Fälle nehmen Kitas das Personal, danach fand
    //     sich in Seed 1 bis Tag 560 kein allein wohnender Besitzer mehr mit einer vollen Kita in der Nähe
    let fall = null, versuche = 0, besitzerN = 0, suchTag = -1;
    { const S = ladenAusText(Sim, kitaStand);
    for (let tage = 0; !fall && tage < 60 && versuche < 40; tage++) {
      while (S.stunde !== 23) Sim.stunde(S);
      if (tage) { Sim.stunde(S); while (S.stunde !== 23) Sim.stunde(S); }
      suchTag = S.tag;
      const P0 = S.p, text0 = speichernAlsText(Sim, S), besitzer = [], kinder = [];
      for (let p = 0; p < S.pMax; p++) {
        const b = P0.besitz[p];
        if (P0.lebt[p] && b >= 0 && P0.arbeit[p] === b && P0.hh[p] === p && S.hhGroesse[p] === 1 && P0.partner[p] < 0 && P0.wohnung[p] >= 0 && !Sim.istHaupt(S, p)) besitzer.push(p);
      }
      for (let x = 0; x < S.pMax; x++) if (P0.lebt[x] && S.tag - P0.geb[x] >= R.KRIPPE_BIS && S.tag + 1 - P0.geb[x] < R.KITA_ENDE && P0.hh[x] >= 0 && P0.hh[x] !== x) kinder.push(x);
      besitzerN = besitzer.length;
      for (const o of besitzer) {
        if (fall || versuche >= 40) break;
        const w = P0.wohnung[o];
        let nah = 0;
        for (let b = 0; b < S.gAnzahl; b++) if (offenK(S, b) && dist(S, b, w) <= R.REICH_KITA && S.belegschaft[b].length && S.g.bedient[b] >= 17) nah++;
        if (!nah) continue;
        for (const k of kinder.filter(x => !P0.kita[x] || dist(S, P0.kita[x] - 1, w) > R.REICH_KITA).slice(0, 3)) {
          versuche++;
          const T = ladenAusText(Sim, text0), P = T.p;
          Sim._pruef.einzelnZu(T, k, o);
          for (let b = 0; b < T.gAnzahl; b++) if (offenK(T, b) && dist(T, b, w) <= R.REICH_KITA) {
            const L = T.belegschaft[b], bleiben = T.g.bedient[b] >= 17 ? 1 : 0;
            while (L.length > bleiben) { const m = L.pop(); P.arbeit[m] = -1; P.einsatz[m] = 0; }
          }
          for (let p = 0; p < T.pMax; p++) P.jetzt[p] = 0;
          const oh0 = T.stat.regierung.kitaOhne, b0 = P.besitz[o];
          Sim.stunde(T);
          if (T.p.kita[k] === 0 && T.stat.regierung.kitaOhne > oh0) { fall = { T, o, k, b0, oh0 }; break; }
        }
      }
    }
    }
    {
      if (!fall) pruef(false, `(h) kein Fall gefunden (${besitzerN} Besitzer allein, ${versuche} Versuche, bis Tag ${suchTag})`);
      else {
        const { T, o, k, b0, oh0 } = fall;
        pruef(T.p.besitz[o] === b0 && T.p.arbeit[o] === b0 && !Sim.gebunden(T, o),
          `(h) ${Sim.name(T, o)} hat nur den eigenen Betrieb, ${Sim.name(T, k)} (${Math.floor((T.tag - T.p.geb[k]) / J)} Jahre) hat keinen Platz, die Kitas in der Nähe sind voll: `
          + `Betrieb bleibt, gezählt ${T.stat.regierung.kitaOhne - oh0} (Tag ${suchTag}, nach ${versuche} ${versuche === 1 ? 'Versuch' : 'Versuchen'})`);
      }
    }
  }
  pruef(summeOhne === summeKitaOhne, `ohne Platz nur mit Besitzern, gemeinnützig oder im Dienst des Bundes: Test zählt ${summeOhne}, die Stadt ${summeKitaOhne} Haushaltsnächte (Seeds zusammen, bis Tag 400)`);
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Kita-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('bau')) {
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), P = () => S.p, B = S.bauhof;
    const start = new Map(), dauer = [];
    let einteilFehl = 0, fortschrittFehl = 0, fertigFehl = 0, stillFehl = 0, geprueft = 0, uebersprungen = 0;
    let maxStellen = 0, maxLeute = 0, lohnMin = 999, lohnMax = 0;
    while (S.tag < 365) {
      for (const b of start.keys()) if (!S.baustellen.includes(b)) start.delete(b);   // fertig (auch in übersprungenen Nächten)
      for (const b of S.baustellen) if (!start.has(b)) start.set(b, S.tag);
      if (S.stunde === 8) {                                     // Einteilung von 7 Uhr
        const je = new Map();
        for (let p = 0; p < S.pMax; p++) {
          const e = P().einsatz[p];
          if (!P().lebt[p] || !e) continue;
          if (P().arbeit[p] !== B || !S.baustellen.includes(e - 1)) einteilFehl++;
          je.set(e - 1, (je.get(e - 1) || 0) + 1);
        }
        for (const [b, n] of je) if (n > R.BAU_PRO_STELLE || n > S.g.bauRest[b]) einteilFehl++;
        // niemand bleibt im Bauhof übrig, solange eine Baustelle noch Leute braucht
        const frei = S.belegschaft[B].filter(p => !P().einsatz[p] && !P().frei[p]).length;
        const braucht = S.baustellen.some(b => (je.get(b) || 0) < Math.min(R.BAU_PRO_STELLE, S.g.bauRest[b]));
        if (frei > 0 && braucht) einteilFehl++;
      }
      if (S.stunde === 23) {                                    // Fortschritt um Mitternacht = Leute, die heute da waren
        const vor = new Map(), erwartet = new Map(), stillVor = new Map(), aufVor = new Map();
        for (const b of S.baustellen) { vor.set(b, S.g.bauRest[b]); erwartet.set(b, 0); stillVor.set(b, S.g.still[b]); aufVor.set(b, S.g.auf[b]); }
        for (const p of S.belegschaft[B]) { const e = P().einsatz[p]; if (e && !P().frei[p]) erwartet.set(e - 1, erwartet.get(e - 1) + 1); }
        const beleg = S.belegschaft[B].slice();
        const tag = S.tag;
        Sim.stunde(S);
        // Nur vergleichen, wenn sich im Bauhof in der letzten Stunde nichts geändert hat (Kündigung, Tod, Freinehmen)
        const gleich = beleg.length === S.belegschaft[B].length && beleg.every((p, i) => S.belegschaft[B][i] === p);
        if (!gleich) { uebersprungen++; continue; }
        for (const [b, r] of vor) {
          geprueft++;
          const n = erwartet.get(b);
          // Noch dieselbe Baustelle? (Ein gerade fertiges Haus kann in derselben Nacht gleich wieder aufgestockt werden.)
          if (S.baustellen.includes(b) && S.g.auf[b] === aufVor.get(b)) {
            if (S.g.bauRest[b] !== r - n) { fortschrittFehl++; if (flag("v")) console.log("   Fortschritt", tag, b, r, n, S.g.bauRest[b], S.g.typ[b], S.g.auf[b], S.g.bauLeute[b]); }
            if (n === 0 && S.g.still[b] !== Math.min(255, stillVor.get(b) + 1)) { stillFehl++; if (flag("v")) console.log("   still", tag, b); }
          } else {
            if (r > n) { fertigFehl++; if (flag("v")) console.log("   fertig", tag, b, r, n); }
            dauer.push(tag + 1 - start.get(b));
            if (S.baustellen.includes(b)) start.set(b, tag + 1);   // gleich wieder aufgestockt: neue Baustelle
          }
        }
        // mit gemeinnützig Arbeitenden (Stadtregierung), ohne Ersatzdienst (Bund): der zählt nach der Regel nicht zur Obergrenze (stellen,
        // bauhofStellen; Version 8: Seed 1 hat im neuen Verlauf schon vor Tag 365 Ersatzdienst im Bauhof)
        const ed = Sim._bund.dienstZahl(S, B);
        maxStellen = Math.max(maxStellen, Sim.stellen(S, B) - ed);
        maxLeute = Math.max(maxLeute, S.belegschaft[B].length - ed);
        lohnMin = Math.min(lohnMin, S.g.lohn[B]); lohnMax = Math.max(lohnMax, S.g.lohn[B]);
        continue;
      }
      Sim.stunde(S);
    }
    const alt = [...start].filter(([b, t]) => t <= 300 && S.baustellen.includes(b));
    const st = S.stat.bau;
    pruef(einteilFehl === 0, `Einteilung um 7 Uhr: nur Leute aus dem Bauhof, höchstens ${R.BAU_PRO_STELLE} je Baustelle, keiner übrig wenn Bedarf (${einteilFehl} Fehler)`);
    pruef(fortschrittFehl === 0 && stillFehl === 0 && fertigFehl === 0, `Fortschritt = Leute, die da waren: ${geprueft} Baustellentage geprüft (${uebersprungen} Nächte mit Wechsel im Bauhof übersprungen), ${fortschrittFehl + stillFehl + fertigFehl} Fehler`);
    pruef(alt.length === 0, `jede Baustelle bis Tag 300 ist an Tag 365 fertig (${st.fertig} fertig, offen seit ≤ Tag 300: ${alt.length})`);
    pruef(maxStellen <= R.BAU_MAX && maxLeute <= R.BAU_MAX, `Bauhof höchstens ${R.BAU_MAX} (ohne Ersatzdienst): Stellen bis ${maxStellen}, Leute bis ${maxLeute}`);
    pruef(lohnMin >= R.LOHN_STADT && lohnMax <= R.BAU_LOHN_MAX, `Lohn ${lohnMin}–${lohnMax} (Ø ${(st.lohnSumme / S.tag).toFixed(1)})`);
    dauer.sort((a, b) => a - b);
    console.log(`       Bauzeit Ø ${(dauer.reduce((a, b) => a + b, 0) / dauer.length).toFixed(1)} Tage, Median ${dauer[dauer.length >> 1]}, längste ${dauer.at(-1)}; ohne Bauarbeiter ${(st.still / st.tage * 100).toFixed(1)} % der Baustellentage`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Bau-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('waren')) {
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  // Version 9, Teil 3: Wird ein Laden in der Nacht seiner Pleite zur Kita oder Schule umgebaut (kitaUmbau), fallen seine Kisten des Tages mit dem
  // Umbau weg; die Messkopie merkt sie sich, damit „geliefert = bekommen“ auch in dieser Nacht genau aufgeht (zuerst Seed 3, Tag 233)
  const { Sim, ctx: wc } = ladeSimMit([['function kitaUmbau(S, b, neuTyp, arbeit) {                  // Schule (Version 9): neuTyp SCHULE mit eigener Bauzeit, sonst Kita\n  const g = S.g, t = g.typ[b], P = S.p;\n',
    'function kitaUmbau(S, b, neuTyp, arbeit) {                  // Schule (Version 9): neuTyp SCHULE mit eigener Bauzeit, sonst Kita\n  const g = S.g, t = g.typ[b], P = S.p;\n  if (globalThis.__umbau) globalThis.__umbau(S, b);\n']]);
  let umbauW = 0, umbauL = 0, umbauten = 0;
  wc.__umbau = (S, b) => { const g = S.g; umbauten++; if (g.typ[b] === Sim.WERKSTATT) umbauW += g.kistenStadt[b]; else if (g.typ[b] === Sim.LADEN || (g.typ[b] === Sim.TECH && g.werk[b])) umbauL += g.kistenStadt[b]; };
  const R = Sim.R;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), g = S.g;
    while (S.tag < 100) Sim.stunde(S);
    umbauten = 0;
    let mehrAlsGemacht = 0, summeFehl = 0, weitFehl = 0, aussenFehl = 0, kistenFehl = 0, einnahmenFehl = 0, einnahmenGeprueft = 0, tage = 0;
    let gemacht = 0, anLaeden = 0, ladenStadt = 0, ladenAussen = 0, ersatzTage = 0, teileFehl = 0;
    const tageBis = Number(arg('tage', '300'));
    while (S.tag < tageBis) {
      if (S.stunde !== 23) { Sim.stunde(S); continue; }
      const P = S.p, vor = [];
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== Sim.WERKSTATT || S.feld[g.y[b] * S.karte + g.x[b]] !== Sim.WERKSTATT || g.leer[b]) continue;
        const L = S.belegschaft[b];
        vor.push({ b, o: g.besitzer[b], kasse: g.kasse[b], lohn: g.lohn[b], L: L.slice(),
          n: L.filter(w => !P.frei[w]).length, da: L.filter(w => !P.frei[w] && !P.einsatz[w] && P.bund[w] !== Sim.ERSATZDIENST).length,
          ed: L.filter(w => !P.frei[w] && !P.einsatz[w] && P.bund[w] === Sim.ERSATZDIENST).length });   // Bund: Ersatzdienst macht keine Kisten
      }
      umbauW = 0; umbauL = 0;
      Sim.stunde(S);
      tage++;
      let sw = umbauW, sl = umbauL;
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] === Sim.WERKSTATT) {
          if (g.kistenStadt[b] > g.kisten[b]) mehrAlsGemacht++;
          sw += g.kistenStadt[b]; gemacht += g.kisten[b]; anLaeden += g.kistenStadt[b];
        } else if (g.typ[b] === Sim.LADEN || (g.typ[b] === Sim.TECH && g.werk[b])) {   // Version 8: Autowerke holen Teile wie Läden
          sl += g.kistenStadt[b]; ladenStadt += g.kistenStadt[b]; ladenAussen += g.kistenAussen[b];
          if (g.typ[b] === Sim.TECH && g.kistenStadt[b] + g.kistenAussen[b] !== g.verkauft[b] * R.AUTO_KISTEN) teileFehl++;
          const l = g.lieferant[b] - 1;
          if (l >= 0 && Math.abs(g.x[l] - g.x[b]) + Math.abs(g.y[l] - g.y[b]) > R.REICH_LIEFER) weitFehl++;
          // Von außerhalb nur, wenn keine Werkstatt in Reichweite noch Kisten übrig hatte
          if (g.kistenAussen[b] > 0) for (let w = 0; w < S.gAnzahl; w++) {
            if (g.typ[w] === Sim.WERKSTATT && g.kisten[w] > g.kistenStadt[w] && Math.abs(g.x[w] - g.x[b]) + Math.abs(g.y[w] - g.y[b]) <= R.REICH_LIEFER) { aussenFehl++; break; }
          }
        }
      }
      if (sw !== sl) summeFehl++;
      for (const v of vor) {
        const L = S.belegschaft[v.b];
        if (L.length !== v.L.length || !L.every((w, i) => w === v.L[i])) continue;   // Wechsel in der letzten Stunde
        if (g.kisten[v.b] !== Math.min(65535, v.da * R.KISTEN_PRO_TAG)) kistenFehl++;
        ersatzTage += v.ed;
        // Einnahmen wie vor den Kisten: Arbeitstage × Umlandpreis. Nachrechnen über die Kasse, solange nichts ausgezahlt wurde.
        if (v.o < 0 || g.besitzer[v.b] !== v.o || g.kasse[v.b] >= R.POLSTER || g.leer[v.b]) continue;
        const einnahmen = g.kasse[v.b] - v.kasse + R.FIX_WERKSTATT + v.lohn * v.n;
        einnahmenGeprueft++;
        if (einnahmen !== Math.round(v.da * S.exportPreis)) einnahmenFehl++;
      }
    }
    pruef(mehrAlsGemacht === 0, `keine Werkstatt liefert mehr Kisten, als sie gemacht hat (${tage} Tage)`);
    pruef(summeFehl === 0 && teileFehl === 0, `geliefert = bekommen (Werkstätten, Läden und Autowerke, ${summeFehl} Abweichungen; ${umbauten} Umbauten zur Kita oder Schule mitgezählt); je Auto aus einem Werk der Stadt ${R.AUTO_KISTEN} Kisten Teile (${teileFehl} Fehler)`);
    pruef(weitFehl === 0 && aussenFehl === 0, `Lieferant höchstens ${R.REICH_LIEFER} Felder weit; von außen nur, wenn in Reichweite nichts übrig war (${weitFehl + aussenFehl} Fehler)`);
    pruef(kistenFehl === 0, `je anwesender Kraft ${R.KISTEN_PRO_TAG} Kisten, Bauarbeiter auf der Baustelle nicht, Ersatzdienst nicht (${ersatzTage} Tage im Ersatzdienst ohne Baustelle; ${kistenFehl} Fehler)`);
    pruef(einnahmenGeprueft > 100 && einnahmenFehl === 0, `Werkstatt-Einnahmen = Arbeitstage × Umlandpreis wie vorher (${einnahmenGeprueft} Werkstatt-Tage nachgerechnet, ${einnahmenFehl} Fehler)`);
    console.log(`       Tag 100–${tageBis}: ${(anLaeden / gemacht * 100).toFixed(0)} % der Kisten gehen an Läden und Autowerke der Stadt, sie bekommen ${(ladenStadt / (ladenStadt + ladenAussen) * 100).toFixed(0)} % aus der Stadt`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Kisten-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('tech')) {
  // Tech-Firmen: Arbeitstage an der Version, Käufe im Laden, Anbau über den Bauhof (Seeds 1–3, 730 Tage)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  // Version 9, Teil 4: Wird ein Laden in der Nacht seiner Pleite zur Schule (oder Kita) umgebaut (kitaUmbau), fällt mit dem Umbau auch sein Zähler
  // „verkauft“ des Tages weg; die Messkopie merkt ihn sich, damit „verkauft in Läden = Käufe“ auch in dieser Nacht genau aufgeht (wie --waren
  // für die Kisten; mit dem Anlauf zuerst Seed 1, Tag 318 und 373)
  const { Sim, ctx: tc } = ladeSimMit([['function kitaUmbau(S, b, neuTyp, arbeit) {                  // Schule (Version 9): neuTyp SCHULE mit eigener Bauzeit, sonst Kita\n  const g = S.g, t = g.typ[b], P = S.p;\n',
    'function kitaUmbau(S, b, neuTyp, arbeit) {                  // Schule (Version 9): neuTyp SCHULE mit eigener Bauzeit, sonst Kita\n  const g = S.g, t = g.typ[b], P = S.p;\n  if (globalThis.__umbau) globalThis.__umbau(S, b);\n']]);
  let umbauVerkauft = 0, umbauLaeden = 0;
  tc.__umbau = (S, b) => { if (S.g.typ[b] === Sim.LADEN) { umbauVerkauft += S.g.verkauft[b]; if (S.g.verkauft[b]) umbauLaeden++; } };
  const R = Sim.R, T = Sim.TECH;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), g = S.g;
    umbauLaeden = 0;
    const offenT = (b) => g.typ[b] === T && !g.leer[b] && S.feld[g.y[b] * S.karte + g.x[b]] === T;
    let arbeitGeprueft = 0, arbeitFehl = 0, uebersprungen = 0, versionen = 0, produktFehl = 0;
    let kaufTage = 0, kaufFehl = 0, angebotFehl = 0, reserveFehl = 0, umsatzFehl = 0, kaeufe = 0;
    let anbauBestellt = 0, anbauFehl = 0, anbauFertig = 0, stellenFehl = 0, rueckFehl = 0, anbauOhneSuchende = 0;
    const stufenBestellt = [0, 0, 0, 0, 0, 0, 0];
    let schulKaeufe = 0;
    const zaehl = () => S.stat.tech.kaeufe.reduce((a, b) => a + b, 0);
    while (S.tag < 730) {
      if (S.stunde !== 23) { Sim.stunde(S); continue; }
      // vor Mitternacht: wer ist heute in welcher Tech-Firma da (Belegschaft ohne frei, Besitzer wenn er dort arbeitet)?
      const P = S.p, vor = [];
      for (let b = 0; b < S.gAnzahl; b++) {
        if (!offenT(b)) continue;
        const o = g.besitzer[b];
        const n = S.belegschaft[b].filter(w => !P.frei[w]).length + (o >= 0 && P.arbeit[o] === b && !P.frei[o] ? 1 : 0);
        vor.push({ b, n, projekt: g.projekt[b], version: g.version[b], L: S.belegschaft[b].slice(), stufe: g.stufe[b], auf: g.auf[b], rueck: g.ruecklage[b] });
      }
      const k0 = zaehl(), u0 = S.stat.tech.umsatz, arbl = S.arbeitslose, weg0 = S.stat.tode + S.stat.wegzuegePersonen;
      const sc0 = S.stat.schule.itGeraete - (S.stat.schule.itAussen || 0);   // Teil 5: Computer der Schulen aus einem Laden der Stadt
      umbauVerkauft = 0;
      const geldVor = new Map();
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p]) geldVor.set(p, P.geld[p]);
      Sim.stunde(S);                                         // Mitternacht: Tagesabschluss
      const tag = S.tag - 1;                                 // der Tag, der gerade abgeschlossen wurde
      for (const v of vor) {
        const b = v.b;
        if (!offenT(b) || S.belegschaft[b].length !== v.L.length || !S.belegschaft[b].every((w, i) => w === v.L[i])) { uebersprungen++; continue; }
        arbeitGeprueft++;
        const soll = R.VERSION_TAGE[g.produkt[b]];
        const erwartet = v.projekt + v.n;
        const ok = erwartet < soll ? g.projekt[b] === erwartet && g.version[b] === v.version
          : g.version[b] === v.version + 1 && g.projekt[b] === Math.min(erwartet - soll, soll - 1) && g.neuTag[b] === tag;
        if (!ok) { arbeitFehl++; if (flag('v')) console.log('   Arbeit', tag, b, v, g.projekt[b], g.version[b]); }
        if (g.version[b] > v.version) versionen++;
        if (!(g.produkt[b] >= 1 && g.produkt[b] <= (g.werk[b] ? 4 : 3)) || (g.produkt[b] === 4) !== !!g.werk[b]) produktFehl++;   // Version 8: Autos nur im Werk
        if (g.ruecklage[b] < 0) rueckFehl++;
        if (g.besitzer[b] >= 0 && g.kasse[b] > R.POLSTER) rueckFehl++;
        // Anbau bestellt: Stufe + 1 als Baustelle, Rücklage bezahlt, genug Leute suchten Arbeit
        if (!v.auf && g.auf[b]) {
          anbauBestellt++;
          if (g.auf[b] !== v.stufe + 1 || !S.baustellen.includes(b) || g.bauRest[b] !== R.BAU_ANBAU[g.auf[b]]) anbauFehl++;
          if (arbl < R.TECH_STELLEN[g.auf[b]] - R.TECH_STELLEN[v.stufe]) anbauOhneSuchende++;
          if (g.auf[b] > (g.werk[b] ? R.WERK_STUFE_MAX : R.TECH_STUFE_MAX)) anbauFehl++;
          stufenBestellt[g.auf[b]]++;
        }
        if (v.auf && !g.auf[b]) {                            // Anbau fertig: mehr Stufe, mehr Stellen, freie Stellen stimmen
          anbauFertig++;
          if (g.stufe[b] !== v.auf) anbauFehl++;
        }
        if (g.offeneStellen[b] !== R.TECH_STELLEN[g.stufe[b]] - g.ruht[b] - S.belegschaft[b].length) stellenFehl++;   // Version 8: Stellen je Stufe
      }
      // Käufe: nur, was angeboten wurde (neueste Version je Produkt); niemand unter der Reserve; Geld = Umsatz der Firmen + Läden
      const neu = zaehl() - k0;
      kaeufe += neu; kaufTage++;
      let verkauftLaden = umbauVerkauft, verkauftFirma = 0;       // umgebaute Läden dieser Nacht (siehe oben) mitgezählt
      for (let b = 0; b < S.gAnzahl; b++) { if (g.typ[b] === Sim.LADEN) verkauftLaden += g.verkauft[b]; if (g.typ[b] === T && g.produkt[b] !== Sim.AUTO) verkauftFirma += g.verkauft[b]; }   // Autos zählen nicht zu den Geräten
      // Version 9, Teil 5: Die Schulen kaufen ihre Computer im Laden wie die Leute; das zählt als verkauft (Laden und Firma), nicht als Kauf der Leute
      const schule = S.stat.schule.itGeraete - (S.stat.schule.itAussen || 0) - sc0; schulKaeufe += schule;
      if (verkauftLaden !== neu + schule || verkauftFirma !== neu + schule) { kaufFehl++; if (flag("v")) console.log("   verkauft", tag, neu, schule, verkauftLaden, verkauftFirma); }
      let summe = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p]) continue;
        for (const [art, tagF, marke, ver] of [['g', 'geraetTag', 'geraetMarke', 'geraetVersion'], ['a', 'appTag', 'appMarke', 'appVersion']]) {
          const hat = art === 'g' ? S.p.geraet[p] : S.p.app[p];
          if (!hat || S.p[tagF][p] !== tag) continue;
          const was = art === 'g' ? S.p.geraet[p] : Sim.SOFTWARE, f = S.angebot[was];
          summe += R.PREIS[was];
          if (f < 0 || g.marke[f] !== S.p[marke][p] || g.version[f] !== S.p[ver][p]) angebotFehl++;
          if (geldVor.has(p) && geldVor.get(p) - R.PREIS[was] < R.KAUF_RESERVE) reserveFehl++;   // gekauft wird nach dem Einkauf: vorher war mindestens Preis + Reserve da
        }
      }
      // Wer in derselben Nacht stirbt oder wegzieht, ist danach nicht mehr zu sehen: dann nur „nicht mehr als bezahlt“
      const wegHeute = S.stat.tode + S.stat.wegzuegePersonen > weg0;
      if (wegHeute ? summe > S.stat.tech.umsatz - u0 : summe !== S.stat.tech.umsatz - u0) { umsatzFehl++; if (flag("v")) console.log("   Umsatz", tag, summe, S.stat.tech.umsatz - u0); }
    }
    const t = S.stat.tech;
    pruef(t.gruendungen > 0 && produktFehl === 0, `${t.gruendungen} Tech-Firmen gegründet, jede macht Software, Handys oder Computer (${produktFehl} Fehler)`);
    pruef(arbeitGeprueft > 1000 && arbeitFehl === 0, `Arbeitstage = Leute, die da waren (Besitzer zählt mit): ${arbeitGeprueft} Firmentage geprüft (${uebersprungen} mit Wechsel übersprungen), ${versionen} Versionen erschienen, ${arbeitFehl} Fehler`);
    pruef(kaeufe > 0 && kaufFehl === 0 && umsatzFehl === 0, `Käufe: ${kaeufe} in ${kaufTage} Tagen (${(kaeufe / kaufTage).toFixed(1)} am Tag), verkauft in Läden = verkauft von Firmen = Käufe (dazu ${schulKaeufe} Computer der Schulen aus dem Laden), bezahlt = Preise (${kaufFehl + umsatzFehl} Fehler; ${umbauLaeden} Läden mit Verkäufen in der Nacht ihres Umbaus mitgezählt)`);
    pruef(angebotFehl === 0 && reserveFehl === 0, `gekauft wird nur die neueste Version im Angebot, niemand zahlt sich unter die Reserve (${angebotFehl + reserveFehl} Fehler)`);
    pruef(anbauFehl === 0 && stellenFehl === 0 && rueckFehl === 0 && anbauOhneSuchende === 0,
      `Anbau: ${anbauBestellt} bestellt (auf Stufe 2–6: ${stufenBestellt.slice(2).join('/')}), ${anbauFertig} fertig; Stufe (höchstens 5, im Werk 6) und freie Stellen stimmen, Rücklage ≥ 0, Kasse ≤ Polster, nur wenn so viele Leute Arbeit suchten, wie Stellen dazukommen (${anbauFehl + stellenFehl + rueckFehl + anbauOhneSuchende} Fehler)`);
  }
  // Speichern und Laden mit Tech-Firmen: bitgleich (Seed 1, Tag 500)
  {
    const A = Sim.neueStadt(1); while (A.tag < 500 || A.stunde !== 11) Sim.stunde(A);
    const B = ladenAusText(Sim, speichernAlsText(Sim, A));
    for (let i = 0; i < 24 * 30; i++) { Sim.stunde(A); Sim.stunde(B); }
    pruef(fingerabdruck(Sim, A) === fingerabdruck(Sim, B) && A.stat.tech.gruendungen > 0, `Speichern/Laden an Tag 500, 11 Uhr, mit ${A.stat.tech.gruendungen} Tech-Gründungen: 30 Tage weiter bitgleich`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Tech-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('aufholtest')) {
  const seed = Number(arg('seed', '1')), start = Number(arg('tage', '200')), n = Number(arg('aufholen', '90'));
  const S0 = Sim.neueStadt(seed); while (S0.tag < start) Sim.stunde(S0);
  const text = speichernAlsText(Sim, S0);
  const A = ladenAusText(Sim, text), B = ladenAusText(Sim, text);
  let t0 = performance.now(); while (A.tag < start + n) Sim.stunde(A); const msStd = performance.now() - t0;
  t0 = performance.now(); while (B.tag < start + n) Sim.tagSchritt(B); const msTag = performance.now() - t0;
  const ka = Sim.kennzahlen(A), kb = Sim.kennzahlen(B);
  console.log(`Seed ${seed}, Tag ${start} → ${start + n}:   stündlich ${f0(msStd)} ms   in Tagesschritten ${f0(msTag)} ms (${(msStd / msTag).toFixed(1)}× schneller)`);
  for (const k of ['einwohner', 'gebaeude', 'gruendungen', 'pleiten', 'freieStellen', 'zufriedenheit', 'arbeitslosenquote']) {
    console.log(`  ${k.padEnd(18)} stündlich ${pad(typeof ka[k] === 'number' && ka[k] % 1 ? ka[k].toFixed(2) : ka[k], 9)}   Tagesschritte ${pad(typeof kb[k] === 'number' && kb[k] % 1 ? kb[k].toFixed(2) : kb[k], 9)}`);
  }
  process.exit(0);
}

if (flag('erweiterung')) {
  // Stadt erweitern (Version 7): die Karte wächst in Ringen, Stufen, Stadtteile, Gelände. Alte Fassung (Version 6, feste Karte 96 × 96)
  // zum Vergleich: --v6 <datei> oder git bc7247a (--git <ordner>). Mit --gross zusätzlich die große Stadt (UMLAND 300000, Seed 2, 750 Tage).
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const v6Html = arg('v6') ? readFileSync(arg('v6'), 'utf8')
    : execFileSync('git', ['show', 'bc7247a:stadt/stadt.html'], { cwd: arg('git', hier), encoding: 'utf8', maxBuffer: 1 << 26 });
  const ladeAlt = () => { const ctx = vm.createContext({}); vm.runInContext(v6Html.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], ctx); return ctx.StadtSim; };
  const Alt = ladeAlt();
  pruef(Alt.VERSION === 6 && Sim.VERSION >= 7, `alte Fassung Version ${Alt.VERSION}, neue ${Sim.VERSION}`);   // Version 8: die Autos sind für den Vergleich aus (sicherheitAus)

  // 1. Statisch: Der Abschnitt „Stadt erweitern“ würfelt nicht und liest von Personen nur lebt und wohnung (auch nicht über Namen, Einzug,
  //    Eltern oder Gedächtnis); Stadtteile (teilVon, teilName, stadtteilZaehlen, erweiterungInfo) nutzt außerhalb des Abschnitts nur, was
  //    anzeigt oder benennt (neuesGebaeude: Name beim ersten Gebäude; personInfo, gebaeudeInfo: Anzeige), nie eine Regel, die Personen wählt
  {
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const roh = SIM_CODE, a = roh.indexOf('// ─── Stadt erweitern (Version 7)'), e = roh.indexOf('// Ende Stadt erweitern');
    const teil = roh.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const zufall = teil.match(/\b(zufall|zInt)\s*\(/g) || [];
    const personen = [...teil.matchAll(/\bS\.p\b(\.\w+|\[[^\]]*\])?/g)].map(m => m[0]).filter(x => x !== 'S.p.lebt' && x !== 'S.p.wohnung');
    const aliasP = teil.match(/\bP\b/g) || [];
    const namen = teil.match(/\b(name|vorname|nr|namePack|nameAusPack|personInfo|ref)\s*\(/g) || [];
    pruef(a > 0 && e > a && !zufall.length && !personen.length && !aliasP.length && !namen.length,
      `Abschnitt „Stadt erweitern“ (${teil.split('\n').length} Zeilen): kein Zufall (${zufall.length}), von Personen nur lebt und wohnung (anderes: ${personen.join(', ') || 'nichts'}; P: ${aliasP.length}), keine Namen (${namen.join(', ') || 'keine'})`);
    // Funktion, in der eine Stelle steht (oberste Ebene: Zeile „function x(“ davor)
    const ausserhalb = code.slice(0, code.indexOf('function karteMasse(')) + code.slice(code.indexOf('function migriereV6('));
    const funktionen = [...ausserhalb.matchAll(/^function (\w+)\(/gm)];
    const in_ = (i) => { let f = '(oben)'; for (const m of funktionen) { if (m.index > i) break; f = m[1]; } return f; };
    const erlaubt = new Set(['neuesGebaeude', 'gebaeudeSetzen', 'personInfo', 'gebaeudeInfo', 'migriereV6']);   // Version 9: gebaeudeSetzen ist der Teil von neuesGebaeude, den auch das Rathaus nutzt
    const nutzer = [...ausserhalb.matchAll(/\b(teilVon|teilName|teilIndex|stadtteilZaehlen|erweiterungInfo)\s*\(/g)].map(m => in_(m.index) + ':' + m[1]);
    pruef(nutzer.every(n => erlaubt.has(n.split(':')[0])), `Stadtteile außerhalb des Abschnitts nur zum Benennen und Anzeigen: ${[...new Set(nutzer)].join(', ')}`);
  }

  // 2. Seeds 1–3 je 730 Tage neben der alten Fassung: jeden Tag dieselben Kennzahlen, derselbe Zufall, dieselben Felder und Gebäude
  //    relativ zur Mitte. Eine Kopie der Simulation zählt, wie oft die Grenze der Karte eine Straße aufhielte (endeVerlaengern und
  //    abzweigen); soll 0 sein. Täglich geprüft: Vorlauf, Ausdehnung = Straßen, Wachsen je eine Zeile, Stufe genau am ersten Tag mit genug
  //    Einwohnern (nie zurück, je Aufstieg eine Zeile), Stadtteile (Dorf ohne, ab Kleinstadt alle bebauten, Namen verschieden, Reihenfolge
  //    des ersten Gebäudes), Zähler je Stadtteil
  const { Sim: Z, ctx: zc } = ladeSimMit([
    ["    if (!imRand(S, nx, ny) || S.feld[zelle(S, nx, ny)] !== LEER) { S.enden.splice(i, 1); break; }",
     "    if (!imRand(S, nx, ny)) globalThis.__grenze++;\n    if (!imRand(S, nx, ny) || S.feld[zelle(S, nx, ny)] !== LEER) { S.enden.splice(i, 1); break; }"],
    ["    if (imRand(S, e.x + ndx, e.y + ndy) && S.feld[zelle(S, e.x + ndx, e.y + ndy)] === LEER) { e.dx = ndx; e.dy = ndy; }",
     "    if (!imRand(S, e.x + ndx, e.y + ndy)) globalThis.__grenze++;\n    if (imRand(S, e.x + ndx, e.y + ndy) && S.feld[zelle(S, e.x + ndx, e.y + ndy)] === LEER) { e.dx = ndx; e.dy = ndy; }"],
    ["      if (!imRand(S, x + dx, y + dy) || S.feld[zelle(S, x + dx, y + dy)] !== LEER) continue;",
     "      if (!imRand(S, x + dx, y + dy)) globalThis.__grenze++;\n      if (!imRand(S, x + dx, y + dy) || S.feld[zelle(S, x + dx, y + dy)] !== LEER) continue;"],
  ]);
  zc.__grenze = 0;
  const R = Sim.R, VOR = Sim.RAND + R.KARTE_VORLAUF;
  const tagesPruefung = (S, fehl) => {
    const e = S.erweiterung, K = S.karte, a = e.ausdehnung;
    let x0 = 1e9, x1 = -1, y0 = 1e9, y1 = -1;
    for (let c = 0; c < K * K; c++) if (S.feld[c] === Sim.STRASSE) { const x = c % K, y = (c / K) | 0; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    for (const r of e.gelaende) { x0 = Math.min(x0, r[0]); y0 = Math.min(y0, r[1]); x1 = Math.max(x1, r[2]); y1 = Math.max(y1, r[3]); }
    if (a[0] !== x0 || a[1] !== x1 || a[2] !== y0 || a[3] !== y1) fehl.ausdehnung++;
    if (!(K >= R.KARTE_MAX || (x0 >= VOR && y0 >= VOR && K - 1 - x1 >= VOR && K - 1 - y1 >= VOR))) fehl.vorlauf++;
    if (S.mitte !== K / 2 || S.feld.length !== K * K || S.vHaus.length !== S.vn * S.vn) fehl.masse++;
    // Stufe: genau so viele Schwellen wie die höchste Einwohnerzahl am Tagesende bisher, Tag des Aufstiegs = erster Tag darüber
    let soll = 0; const tage = [0];
    for (let n = 1; n < R.STUFE_AB.length; n++) { const t = S.reihe.findIndex(v => v >= R.STUFE_AB[n]); if (t < 0) break; soll = n; tage.push(t); }
    if (e.stufe !== soll || JSON.stringify(e.stufenTage) !== JSON.stringify(tage)) fehl.stufe++;
    // Stadtteile: ab Kleinstadt alle bebauten benannt, in der Reihenfolge ihres ersten Gebäudes, verschiedene Namen
    const erst = new Map(); for (let b = 0; b < S.gAnzahl; b++) { const t = Sim.teilVon(S, S.g.x[b], S.g.y[b]); if (!erst.has(t)) erst.set(t, b); }
    const namen = e.teile.map(([t]) => Sim.teilName(S, t));
    const reihe = e.teile.map(([t]) => erst.get(t));
    if (e.stufe === 0 ? e.teile.length !== 0 : (e.teile.length !== erst.size || reihe.some((b, i) => b === undefined || (i && b < reihe[i - 1])) || new Set(namen).size !== namen.length)) fehl.teile++;
  };
  const ergebnis = {};
  const zAn = sicherheitAus(Z);                              // Sicherheit (Version 7) aus: Vergleich mit Version 6 (Abschnitte 3 und 5 mit)
  for (const seed of [1, 2, 3]) {
    const A = Alt.neueStadt(seed), S = Z.neueStadt(seed), fehl = { ausdehnung: 0, vorlauf: 0, masse: 0, stufe: 0, teile: 0 };
    let erst = -1, buchNr = 0, zeilenKarte = 0, zeilenStufe = 0, kMin = S.karte, zaehlerFehl = 0, infoFehl = 0;
    const karteZeilen = new Map();                            // Tag → Text der Zeile „Bauland“ (eine je Nacht, auch bei mehrmaligem Wachsen)
    const grenze0 = zc.__grenze;
    for (let d = 0; d < 730; d++) {
      const z = A.tag + 1; while (A.tag < z) Alt.stunde(A); while (S.tag < z) Z.stunde(S);
      if (erst < 0 && spurRelativ(Alt, A) !== spurRelativ(Z, S)) erst = A.tag;
      tagesPruefung(S, fehl);
      for (const e of S.buch) if (e.nr > buchNr) { if (e.art === 'karte') { zeilenKarte++; karteZeilen.set(e.tag, (karteZeilen.has(e.tag) ? '<doppelt> ' : '') + e.text); } if (e.art === 'stufe') zeilenStufe++; }
      buchNr = S.buchNr;
      if (S.karte < kMin) kMin = -1; kMin = Math.max(kMin, S.karte);
      if (S.tag % 73 === 0 && S.erweiterung.stufe >= 1) {       // Zähler und Karten
        const z = Z.stadtteilZaehlen(S), k = Z.kennzahlen(S);
        let mitWohnung = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.wohnung[p] >= 0) mitWohnung++;
        if (z.reduce((s, t) => s + t.einwohner, 0) !== mitWohnung || z.reduce((s, t) => s + t.wohnhaeuser, 0) !== k.haeuser) zaehlerFehl++;
        const b = S.gAnzahl - 1, p = S.p.wohnung.findIndex((w, i) => i < S.pMax && S.p.lebt[i] && w >= 0);
        const gi = Z.gebaeudeInfo(S, b), pi = Z.personInfo(S, p);
        if (gi.stadtteil !== Z.teilName(S, Z.teilVon(S, S.g.x[b], S.g.y[b])) || !gi.stadtteil || !pi.stadtteil) infoFehl++;
      }
    }
    const e = S.erweiterung, w = e.wachsen;
    ergebnis[seed] = { karte: S.karte, wachsen: w.length, tage: w.map(x => x[0]) };
    pruef(erst < 0, `Seed ${seed}: 730 Tage jeden Tag wie die alte Fassung (Kennzahlen, Zufall, Felder und Gebäude relativ zur Mitte, alle Personen- und Gebäudefelder, Statistik, Hauptfiguren)${erst < 0 ? '' : ', VERSCHIEDEN ab Tag ' + erst}; ${S.einwohner} Einwohner`);
    pruef(zc.__grenze === grenze0 && !fehl.vorlauf && !fehl.ausdehnung && !fehl.masse, `Seed ${seed}: Grenze hielt ${zc.__grenze - grenze0}-mal eine Straße auf; Vorlauf ${VOR} Felder an ${730 - fehl.vorlauf} von 730 Tagen, Ausdehnung = Straßen (${fehl.ausdehnung} Fehler), Maße (${fehl.masse})`);
    // Je Nacht mit Wachsen genau eine Zeile: von der Größe vor dem ersten bis nach dem letzten Wachsen der Nacht, Abstand bis zum Rand der
    // Karte unter RAND + KARTE_VORLAUF (so steht die Regel im Fenster)
    const naechte = [...new Set(w.map(x => x[0]))], zeileFalsch = naechte.filter(t => { const i0 = w.findIndex(x => x[0] === t), i1 = w.map(x => x[0]).lastIndexOf(t);
      const vor = i0 ? w[i0 - 1][1] : R.KARTE_START, z = karteZeilen.get(t) || '', ab = [...z.matchAll(/bis (\d+) Felder/g)].map(m => +m[1]);
      return !z.includes(`von ${vor} × ${vor} auf ${w[i1][1]} × ${w[i1][1]} Felder`) || ab.length !== i1 - i0 + 1 || ab.some(a => a >= VOR); });
    pruef(w.length >= 2 && zeilenKarte === naechte.length && !zeileFalsch.length && kMin > 0 && w.every((x, i) => (x[1] - (i ? w[i - 1][1] : R.KARTE_START)) % (2 * R.KARTE_RING) === 0 && x[1] > (i ? w[i - 1][1] : R.KARTE_START)),
      `Seed ${seed}: Karte ${R.KARTE_START} → ${S.karte}, ${w.length}-mal gewachsen (Tag ${w.map(x => x[0] + ': ' + x[1]).join(', ')}), ${zeilenKarte} Zeilen im Stadtbuch (eine je Nacht, Größen und Abstand passen${zeileFalsch.length ? ', FALSCH an Tag ' + zeileFalsch.join(', ') : ''})`);
    pruef(!fehl.stufe && zeilenStufe === e.stufe && e.stufe === 3, `Seed ${seed}: Stufe jeden Tag richtig (${fehl.stufe} Fehler), Aufstieg genau am ersten Tag über der Schwelle (Tag ${e.stufenTage.slice(1).join(', ')}), ${zeilenStufe} Zeilen`);
    pruef(!fehl.teile && !zaehlerFehl && !infoFehl, `Seed ${seed}: Stadtteile jeden Tag richtig benannt (${e.teile.length}: ${e.teile.map(([t]) => Z.teilName(S, t)).join(', ')}); Zähler ${zaehlerFehl}, Karten ${infoFehl} Fehler`);
  }
  zAn();
  // Stadtbuch: „Neu:“ nennt nur, was STUFE_NEU enthält; im Dorf keine Stadtteilzeile, Stadtteilzeile ohne Personennamen. Sicherheit
  // (Version 7): Kleinstadt „Stadtteile mit Namen und eine Polizeiwache des Landes“, Stadt „eine Justizvollzugsanstalt des Landes für die Region“;
  // Bund (Teil 3): Stadt dazu „eine Kaserne der Bundeswehr mit Wehrpflicht“, Großstadt „eine Dienststelle des Bundesnachrichtendienstes“
  {
    // Version 8: die Zeilen werden beim Entstehen gesammelt (das Buch hält nur die letzten BUCH_MAX; mit Autos ist die Stadt eine andere)
    const S = Sim.neueStadt(2), st = [], tz = [], gesehen = new Set();
    while (S.tag < 200) { Sim.stunde(S); for (const e of S.buch) if (!gesehen.has(e)) { gesehen.add(e); if (e.art === 'stufe') st.push(e); else if (e.art === 'stadtteil') tz.push(e); } }
    const neu = Sim.erweiterungInfo(S).neu;
    const aufz = (l) => (l.length < 2 ? l.join('') : l.slice(0, -1).join(', ') + ' und ' + l.at(-1));
    pruef(st.length === 2 && neu[1][0] === 'Stadtteile mit Namen' && st[0].text.endsWith(` Neu: ${aufz(neu[1])}.`) && st[1].text.endsWith(` Neu: ${aufz(neu[2])}.`)
      && neu[2].includes('eine Kaserne der Bundeswehr mit Wehrpflicht') && neu[3].join() === 'eine Dienststelle des Bundesnachrichtendienstes' && tz.length >= 1 && tz.every(e => !/\u0001/.test(e.text)) && tz.every(e => e.tag >= st[0].tag),
      `Stadtbuch: Stufen „${Sim.klartext(st[0].text).slice(-40)}“ / „…${Sim.klartext(st[1].text).slice(-50)}“, ${tz.length} Stadtteilzeilen ohne Personennamen, keine vor der Kleinstadt`);
  }

  // 3. Speichern und Laden mitten am Tag vor einem Wachsen: beide wachsen am selben Tag und laufen bitgleich weiter
  {
    // Tag des ersten Wachsens mit Sicherheit (in Abschnitt 2 war sie aus; Taten und Haft verschieben den Zuzug)
    const V = Sim.neueStadt(2); while (!V.erweiterung.wachsen.length && V.tag < 730) Sim.stunde(V);
    const t = V.erweiterung.wachsen.length ? V.erweiterung.wachsen[0][0] : ergebnis[2].tage[0], A = Sim.neueStadt(2);
    {                                                         // Wächst Seed 2 in einer Nacht zweimal: eine Zeile („zweimal“). Version 8: mit Autos
      // ist das nicht mehr die erste Nacht (Tag 93 einmal), sondern die erste Nacht mit zwei Ringen; weiterlaufen, bis es eine gibt
      // Haushalt (Version 9, Teil 3): Seed 2 wächst jetzt bis Tag 730 nie zweimal in einer Nacht; dann dieselbe Suche in Seed 1, 3, 4, 5 …
      const zwei = (X) => { const w = X.erweiterung.wachsen; return w.findIndex((x, i) => i > 0 && w[i - 1][0] === x[0]); };
      let W = V, sd2 = 2;
      for (const sd of [2, 1, 3, 4, 5, 6, 7, 8]) {
        W = sd === 2 ? V : Sim.neueStadt(sd); sd2 = sd;
        while (zwei(W) < 0 && W.tag < 730) Sim.stunde(W);
        if (zwei(W) >= 0) break;
      }
      const i = zwei(W), w = W.erweiterung.wachsen, t2 = i > 0 ? w[i][0] : -1, vor = i > 1 ? w[i - 2][1] : R.KARTE_START;
      const wt = w.filter(x => x[0] === t2), zt = W.buch.filter(e => e.tag === t2 && e.art === 'karte'), z = zt.length ? Sim.klartext(zt[0].text) : '';
      pruef(wt.length === 2 && zt.length === 1 && z.includes(`zweimal nah an den Rand der Karte`) && z.includes(`von ${vor} × ${vor} auf ${wt[1][1]} × ${wt[1][1]} Felder`),
        `Seed ${sd2}, Tag ${t2}: ${wt.length}-mal gewachsen in einer Nacht (${wt.map(x => x[1]).join(', ')}), ${zt.length} Zeile im Stadtbuch: „${z}“`);
    }
    while (A.tag < t - 1 || A.stunde < 13) Sim.stunde(A);
    const text = speichernAlsText(Sim, A), B = ladenAusText(Sim, text), k0 = A.karte;
    while (A.tag < t + 30) Sim.stunde(A); while (B.tag < t + 30) Sim.stunde(B);
    pruef(A.karte > k0 && B.karte === A.karte && JSON.stringify(A.erweiterung.wachsen) === JSON.stringify(B.erweiterung.wachsen) && fingerabdruck(Sim, A) === fingerabdruck(Sim, B),
      `Speichern an Tag ${t - 1}, 13 Uhr (Karte ${k0}), geladen und weiter: beide wachsen an denselben Tagen (${B.erweiterung.wachsen.map(x => x[0] + ': ' + x[1]).join(', ')}), 30 Tage später bitgleich (${fingerabdruck(Sim, A)})`);
    // Beschädigte Stände der Version 7 werden abgelehnt
    const roh = () => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
    const meld = [];
    for (const [was, kaputt, soll] of [['Karte 100', d => { d.werte.karte = 100; }], ['Mitte falsch', d => { d.werte.mitte++; }], ['Karte zu groß', d => { d.werte.karte = 512; }],
      ['Stufe 7', d => { d.json.erweiterung.stufe = 7; }], ['Stadtteil doppelt', d => { d.json.erweiterung.teile.push(d.json.erweiterung.teile[0]); }],
      ['Stadtteil als Text', d => { d.json.erweiterung.teile[0][0] = '<b>'; }], ['Ausdehnung außerhalb', d => { d.json.erweiterung.ausdehnung[1] = d.werte.karte; }],
      ['Gelände ohne Gebäude', d => { d.json.erweiterung.gelaende.push([4, 4, 6, 6, 99999]); }], ['Viertel fehlt', d => { d.json.vHaus.pop(); }],
      ['Feld zu kurz', d => { const a = d.arrays.find(x => x.name === 'feld'); a.daten = a.daten.subarray(0, 100); }], ['ohne erweiterung', d => { delete d.json.erweiterung; }],
      // Lage der Gebäude und Gelände (Befund der Gegenprüfung: vorher angenommen, die Stadt lief weiter)
      ['Gebäude außerhalb der Karte', d => { d.arrays.find(x => x.name === 'g.x').daten[0] = d.werte.karte + 3; }, 'Lage der Gebäude'],
      ['Feld zeigt auf ein anderes Gebäude', d => { const K = d.werte.karte, g = (n) => d.arrays.find(x => x.name === n).daten; g('feldGeb')[g('g.y')[0] * K + g('g.x')[0]] = 1; }, 'Lage der Gebäude'],
      ['Gelände-Feld leer', d => { const K = d.werte.karte, r = d.json.erweiterung.gelaende[0], f = d.arrays.find(x => x.name === 'feld').daten; f[r[1] * K + r[0]] = 0; f[r[3] * K + r[2]] = 0; }, 'Gelände'],
      ['Gelände-Feld ohne Gebäude', d => { const K = d.werte.karte, r = d.json.erweiterung.gelaende[0], f = d.arrays.find(x => x.name === 'feldGeb').daten; f[r[1] * K + r[0]] = -1; f[r[3] * K + r[2]] = -1; }, 'Gelände']]) {
      const d = roh(); kaputt(d);
      let e = null; try { Sim.importZustand(d); } catch (x) { e = x; }
      meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
      if (!e || !/^Spielstand beschädigt/.test(e.message) || (soll && !e.message.includes(soll))) fehler++;
    }
    pruef(meld.every(m => /beschädigt/.test(m)) && meld.length === 15 && JSON.parse(text).json.erweiterung.gelaende.length > 0, 'beschädigte Stände der Version 7 abgelehnt: ' + meld.join('; '));
  }

  // 4. Übernahme von Version 6 (alte Fassung): Dorf (unter 40 Einwohnern), Seed 1/2/3 an Tag 150/300/400 (Seed 2 kommt an die alte
  //    Grenze: die Karte wächst beim Übernehmen). Danach 60 Tage jeden Tag wie in Version 6
  const simAn = sicherheitAus(Sim);                          // Sicherheit aus: 60 Tage wie Version 6 (die Übernahme selbst prüft --migrationstest)
  for (const [seed, tag] of [[1, 15], [1, 150], [2, 300], [3, 400]]) {
    const A = Alt.neueStadt(seed);
    while (A.tag < tag || A.stunde < 13) Alt.stunde(A);
    const text = speichernAlsText(Alt, A);
    let S = null, fehlerText = '';
    try { ladenAusText(Sim, text); fehlerText = 'ohne Übernehmen angenommen'; } catch (e) { if (!e.migrierbar) fehlerText = e.message; }
    const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; });
    S = Sim.importZustand(d, true);
    const e = S.erweiterung, z = S.buch.at(-2), soll = R.STUFE_AB.filter(v => A.einwohner >= v).length - 1;   // Version 8: die Zeile der Autos ist die letzte
    const kopf = `Übernahme Version 6, Seed ${seed}, Tag ${tag} (${A.einwohner} Einw.)`;
    pruef(!fehlerText && e.stufe === soll && z.art === 'stufe' && z.text.includes(`sie ist ${Sim.STUFEN[soll] === 'Dorf' ? 'ein Dorf' : 'eine ' + Sim.STUFEN[soll]}.`) && (soll > 0 || !/Stadtteile/.test(z.text)),
      `${kopf}: ${Sim.STUFEN[e.stufe]}, Karte ${S.karte}, ${e.teile.length} Stadtteile; „${Sim.klartext(z.text).slice(0, 150)}…“${fehlerText ? ' ' + fehlerText : ''}`);
    let erst = -1;
    for (let t = 0; t < 60; t++) { const q = A.tag + 1; while (A.tag < q) Alt.stunde(A); while (S.tag < q) Sim.stunde(S); if (erst < 0 && spurRelativ(Alt, A) !== spurRelativ(Sim, S)) erst = A.tag; }
    pruef(erst < 0, `${kopf}: 60 Tage jeden Tag wie Version 6${erst < 0 ? '' : ', VERSCHIEDEN ab Tag ' + erst} (Karte jetzt ${S.karte}, Stufe ${Sim.STUFEN[S.erweiterung.stufe]})`);
  }
  simAn();

  // 5. Gelände (Schnittstelle für andere Bausteine): 3 × 2 Blöcke am Stadtrand und 1 Block nah an der Mitte; Test mit einem großen Park
  //    (PARK, sofort fertig), damit die Stadt danach normal weiterlaufen kann. Danach: alle Felder belegt, keine Bauplätze darin, Vorlauf
  //    gilt (die Karte wächst, wenn nötig), 60 Tage weiter ohne Grenzstopp, Speichern und Laden bitgleich
  {
    zc.__grenze = 0;
    const S = Z.neueStadt(2);
    while (S.tag < 300) Z.stunde(S);
    // Ein ganzer freier Block an einer Straße ist in der Stadt selten (die Häuser säumen die Straßen): Findet sich keiner, verlängert ein
    // Baustein erst eine Straße. Hier: weiterlaufen, bis das Bauamt eine Straße verlängert hat und nah ein Block frei ist
    let nah = Z.gelaendeSuchen(S, 1, 1, false), tage = 0;
    while (!nah && tage < 60) { const q = S.tag + 1; while (S.tag < q) Z.stunde(S); tage++; nah = Z.gelaendeSuchen(S, 1, 1, false); }
    const k0 = S.karte, rand = Z.gelaendeSuchen(S, 3, 2, true);
    const dM = (r) => Math.hypot((r.x0 + r.x1) / 2 - S.mitte, (r.y0 + r.y1) / 2 - S.mitte);
    let frei = true, anStrasse = false;
    for (let y = rand.y0; y <= rand.y1; y++) for (let x = rand.x0; x <= rand.x1; x++) frei = frei && S.feld[y * S.karte + x] === Sim.LEER;
    const [dx, dy] = [[-1, 0], [1, 0], [0, -1], [0, 1]][rand.seite];
    anStrasse = S.feld[(rand.torY + dy) * S.karte + rand.torX + dx] === Sim.STRASSE;
    pruef(rand && nah && frei && anStrasse && rand.x1 - rand.x0 + 1 === 11 && rand.y1 - rand.y0 + 1 === 7 && dM(rand) > dM(nah),
      `Gelände gesucht (Tag ${S.tag}, ${tage} Tage gewartet): 3 × 2 Blöcke am Rand (${rand.x0}–${rand.x1}, ${rand.y0}–${rand.y1}, Tor ${rand.torX}/${rand.torY} zur Straße im ${['Westen', 'Osten', 'Norden', 'Süden'][rand.seite]}, ${dM(rand).toFixed(1)} von der Mitte), 1 Block nah an der Mitte (${dM(nah).toFixed(1)})`);
    const b = Z.gelaendeBauen(S, rand, Sim.PARK, 0, -1), off = (S.karte - k0) / 2, g = S.erweiterung.gelaende.at(-1);
    let belegt = true, plaetze = 0;
    for (let y = g[1]; y <= g[3]; y++) for (let x = g[0]; x <= g[2]; x++) { const c = y * S.karte + x; belegt = belegt && S.feld[c] === Sim.PARK && S.feldGeb[c] === b; plaetze += S.platz[c]; }
    const fehl = { ausdehnung: 0, vorlauf: 0, masse: 0, stufe: 0, teile: 0 };
    tagesPruefung(S, fehl);
    pruef(belegt && !plaetze && g[0] === rand.x0 + off && !fehl.vorlauf && !fehl.ausdehnung, `Gelände gebaut (Gebäude ${b}): alle ${(g[2] - g[0] + 1) * (g[3] - g[1] + 1)} Felder belegt, ${plaetze} Bauplätze darin, Karte ${k0} → ${S.karte}, Vorlauf und Ausdehnung stimmen`);
    const text = speichernAlsText(Z, S), L = ladenAusText(Z, text);
    for (let t = 0; t < 60; t++) { const q = S.tag + 1; while (S.tag < q) Z.stunde(S); while (L.tag < q) Z.stunde(L); tagesPruefung(S, fehl); }
    pruef(zc.__grenze === 0 && !fehl.vorlauf && !fehl.ausdehnung && fingerabdruck(Z, S) === fingerabdruck(Z, L),
      `60 Tage weiter mit Gelände: Grenze hielt ${zc.__grenze}-mal eine Straße auf, Vorlauf ${fehl.vorlauf} Fehler, gespeichert und geladen bitgleich; Karte ${S.karte}`);
  }

  // 6. Große Stadt (nur mit --gross): UMLAND 300000, Seed 2, 750 Tage; die Karte wächst deutlich über 96, nie eine Straße am Rand
  if (flag('gross')) {
    zc.__grenze = 0;
    const alt = Z.R.UMLAND; Z.R.UMLAND = 300000; Alt.R.UMLAND = 300000;
    const an = sicherheitAus(Z);
    const A = Alt.neueStadt(2), S = Z.neueStadt(2), fehl = { ausdehnung: 0, vorlauf: 0, masse: 0, stufe: 0, teile: 0 };
    let erst = -1;
    for (let d = 0; d < 750; d++) { const z = A.tag + 1; while (A.tag < z) Alt.stunde(A); while (S.tag < z) Z.stunde(S); tagesPruefung(S, fehl); if (erst < 0 && spurRelativ(Alt, A) !== spurRelativ(Z, S)) erst = A.tag; }
    Z.R.UMLAND = alt; Alt.R.UMLAND = alt; an();
    const w = S.erweiterung.wachsen;
    pruef(S.karte >= 112 && zc.__grenze === 0 && !fehl.vorlauf && !fehl.stufe && !fehl.teile && erst < 0,
      `große Stadt (UMLAND 300000, Seed 2, 750 Tage): ${S.einwohner} Einwohner, Karte ${S.karte} × ${S.karte} (${w.length}-mal gewachsen: ${w.map(x => x[0] + ': ' + x[1]).join(', ')}), Grenzstopp ${zc.__grenze}, ${erst < 0 ? 'jeden Tag wie die alte Fassung' : 'VERSCHIEDEN ab Tag ' + erst}`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zu „Stadt erweitern“ bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('sicherheit')) {
  // Sicherheit (Version 7): Kriminalität, Polizei, Gericht, Gefängnis, Obhut. 1. statisch: Zufall, gelesene Personenfelder je Regel, Löhne des
  // Landes nicht aus dem Budget; Namenstausch (andere Namenslisten, sonst gleich: die Stadt läuft bitgleich). 2. Invarianten nach jeder Nacht
  // (Seeds 1–3, 730 Tage). 3. Erzwungene Fälle (Urteile, Ersatzfreiheitsstrafe, Anrechnung, Tilgung, Widerruf, Randfall U-Haft, volle
  // Anstalt, Obhut, Grundsicherung, Arbeitsentgelt). 4. Speichern und Laden mit Haft, Verfahren und Obhut; beschädigte Stände.
  // 5. Messung: Taten je 1.000 Einwohner und Jahr gegen die PKS 2024; Gruppen (nur gemessen, keine Regel liest sie). Seeds mit --seeds
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, X = Sim._sich;
  const erwachsen = (S, p) => S.tag - S.p.geb[p] >= R.ERWACHSEN * J;
  const lebtNoch = (S, id, gen) => id >= 0 && S.p.lebt[id] && S.p.gen[id] === gen;
  // Kopie der Simulation mit Messpunkten (liest nur mit): jede Tat mit Opfer, jedes Urteil, Budget im Zweig der Landeslöhne
  const { Sim: M, ctx: mc } = ladeSimMit([
    ['function tatBegehen(S, p, typ) {\n  const P = S.p, Si = S.sicherheit, st = S.stat.sicherheit;\n  const o = opferWaehlen(S, p, typ);\n',
      'function tatBegehen(S, p, typ) {\n  const P = S.p, Si = S.sicherheit, st = S.stat.sicherheit;\n  const o = opferWaehlen(S, p, typ);\n  if (globalThis.__tat) globalThis.__tat(S, p, typ, o);\n'],
    ['function urteilen(S, v) {\n', 'function urteilen(S, v) {\n  if (globalThis.__urteil) globalThis.__urteil(S, v);\n'],
    ['    if (istLand(t)) {                                        // Sicherheit: Polizei und Justizvollzug, Löhne zahlt das Land (von außen)\n',
      '    if (istLand(t)) {                                        // Sicherheit: Polizei und Justizvollzug, Löhne zahlt das Land (von außen)\n      const __b0 = S.budget;\n'],
    ['      g.umsatz[b] = 0;\n      continue;\n    }\n    if (istBund(t)) {', '      g.umsatz[b] = 0;\n      if (S.budget !== __b0) globalThis.__landBudget++;\n      continue;\n    }\n    if (istBund(t)) {'],
  ]);
  mc.__landBudget = 0;

  // 1. Statisch
  {
    const roh = SIM_CODE, a = roh.indexOf('// ─── Sicherheit (Version 7)'), e = roh.indexOf('// Ende Sicherheit');
    const teil = roh.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const fremd = teil.match(/\b(zufall|zInt)\s*\(/g) || [];
    pruef(a > 0 && e > a && !fremd.length && /zufallSich\(S\)/.test(teil), `Abschnitt „Sicherheit“ (${teil.split('\n').length} Zeilen): Zufall nur aus dem eigenen Strom (zufallSich), sonst ${fremd.length}`);
    // Körper einer Funktion (oberste Ebene) aus dem ganzen sim-Block, ohne Kommentare
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const koerper = (f) => {                                  // bis zur passenden schließenden Klammer (auch einzeilig)
      const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return null;
      let t = 0, j = code.indexOf('{', i);
      for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; }
      return code.slice(i, j + 1); };
    const felder = (k) => [...new Set([...k.matchAll(/\bP\.(\w+)/g)].map(m => m[1]))].sort();
    // Je Regel, die über Menschen entscheidet: welche Personenfelder sie lesen darf. Nie: Namen (vor, nach, Eltern-Namen), Einzugstag,
    // Gedächtnis, Heimatliebe; das Geschlecht nur für die Grammatik (alterWort, Pronomen im Urteil)
    const ERLAUBT = {
      tatTeile: ['ehrgeiz', 'geld', 'zuf'], erwerbslos: ['arbeit', 'besitz', 'gemein', 'geb', 'hh'], tatRisiko: [], polizeiFaktor: [], aufklaerung: [],
      opferWaehlen: ['geb', 'haftBis', 'hh', 'lebt', 'wohnung'], haushaltErwachsene: ['geb', 'hh', 'wohnung'],
      tatBegehen: ['gen', 'geld', 'haftBis', 'opferArt', 'opferTag', 'tilgungBis', 'vorstrafen', 'wohnung'],
      urteilen: ['bewaehrungBis', 'bewaehrungRest', 'entlassenTag', 'freiheitReg', 'geld', 'haftArt', 'haftBis', 'haftNach', 'tilgungBis', 'vorstrafen', 'weib'],
      einkommenTag: ['arbeit', 'besitz', 'bund', 'gemein'], haftAntritt: ['arbeit', 'besitz', 'bund', 'gemein', 'gsTage', 'haftArt', 'haftBis', 'haftNach', 'haftOrt'],
      obhutKandidat: ['geb', 'haftBis', 'hh', 'lebt', 'wohnung'], obhutSuchen: ['elternA', 'elternAGen', 'elternB', 'elternBGen', 'gen', 'lebt'],
      landStellen: [], landStelleFrei: [], insassen: ['haftBis', 'haftOrt', 'lebt'],
    };
    const zuViel = [];
    for (const [f, ok] of Object.entries(ERLAUBT)) {
      const k = koerper(f);
      if (!k) { zuViel.push(f + ': fehlt'); continue; }
      for (const x of felder(k)) if (!ok.includes(x)) zuViel.push(`${f}: P.${x}`);
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo)\s*\(/.test(k)) zuViel.push(`${f}: Name`);
    }
    // Geschlecht im Urteil nur für das Pronomen (sie/er), nie in einer Bedingung
    const u = koerper('urteilen'), weibZeilen = u.split('\n').filter(z => /P\.weib/.test(z));
    const nurPronomen = weibZeilen.every(z => /sie = P\.weib\[p\] \? 'sie' : 'er'/.test(z));
    pruef(!zuViel.length && nurPronomen, `Regeln lesen nur ihre Personenfelder (${Object.keys(ERLAUBT).length} Funktionen), keine Namen; Geschlecht nur fürs Pronomen im Urteil`
      + (zuViel.length ? ': ' + zuViel.join(', ') : ''));
    const w = code.slice(code.indexOf('    if (istLand(t)) {'), code.indexOf('    if (istBund(t)) {', code.indexOf('    if (istLand(t)) {')));
    pruef(w.length > 0 && !/S\.budget/.test(w), 'wirtschaft: der Zweig der Landeslöhne berührt das Budget der Stadt nicht (Löhne von außen)');
    // Namenstausch: andere Namen (Listen umgedreht), sonst gleich. Keine Regel liest Namen, also läuft die Stadt bitgleich (Felder, Summen,
    // Zufall, Budget; das Stadtbuch nur in der Art der Zeilen)
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(1), B = T.neueStadt(1);
    while (A.tag < 365) Sim.stunde(A); while (B.tag < 365) T.stunde(B);
    const spur = (S) => { const h = createHash('sha256'); for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n])) { const a = S.p[n], w = a.length / S.pKap; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) if (ArrayBuffer.isView(S.g[n])) { const a = S.g[n]; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      h.update(JSON.stringify(S.stat)); h.update(JSON.stringify(S.sicherheit)); h.update(String(S.rs) + '/' + S.rsSich + '/' + S.budget); h.update(S.buch.map(e => e.art).join()); return h.digest('hex').slice(0, 16); };
    const nA = Sim.name(A, 5), nB = T.name(B, 5);
    pruef(nA !== nB && spur(A) === spur(B), `Namenstausch (Seed 1, 365 Tage): „${nA}“ heißt dort „${nB}“, die Stadt läuft trotzdem bitgleich (${spur(A)})`);
  }

  // 2. Invarianten nach jeder Nacht
  const ueber = { taten: 0, opfer: 0, urteile: 0 };
  const seeds = arg('seeds', '1,2,3').split(',').map(Number);
  for (const seed of seeds) {
    const S = M.neueStadt(seed), P = S.p, fehl = {};
    const f = (k) => { fehl[k] = (fehl[k] || 0) + 1; };
    let naechte = 0, tatFehl = 0, opferFehl = 0, haftNaechte = 0, hofFehl = 0, kinderObhut = 0, zeilen = 0, stufeWache = -1, stufeJva = -1;
    mc.__tat = (S, p, typ, o) => { ueber.taten++; if (!erwachsen(S, p) || S.p.haftBis[p]) tatFehl++;
      if (o >= 0) { ueber.opfer++; if (o === p || !erwachsen(S, o) || S.p.haftBis[o] || (S.p.hh[p] >= 0 && S.p.hh[o] === S.p.hh[p])) opferFehl++; } };
    mc.__urteil = () => { ueber.urteile++; };
    const lb0 = mc.__landBudget;
    let buchNr = S.buchNr;
    while (S.tag < 730) {
      const t = S.tag;
      M.stunde(S);
      // Hofzeiten: nur Gefangene in der Anstalt in der Stadt, nur zu den Zeiten ihrer Abteilung, Abteilungen nie zugleich
      const H = S.stunde;
      const imHof = [0, 0, 0];
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && M.imHof(S, p, H)) {
        const a = M.abteilung(S, p); imHof[a]++;
        if (!P.haftBis[p] || P.haftOrt[p] !== 1 || !M.HOFZEITEN[a].includes(H) || (P.haftArt[p] === M.HAFT_U) !== (a === 2)) hofFehl++;
      }
      if (imHof.filter(Boolean).length > 1) hofFehl++;
      if (S.tag === t) continue;
      naechte++;
      const Si = S.sicherheit, e = S.erweiterung, erwTag = S.tag - R.ERWACHSEN * J;
      // Wache ab der Kleinstadt, Anstalt ab der Stadt, beide auf eigenem Gelände (1 Block; 2 Blöcke), vom Land bezahlt
      if (Si.wache >= 0 && stufeWache < 0) stufeWache = e.stufe;
      if (Si.jva >= 0 && stufeJva < 0) stufeJva = e.stufe;
      for (const [b, typ, fl] of [[Si.wache, M.WACHE, [9]], [Si.jva, M.JVA, [21]]]) {
        if (b < 0) continue;
        const r = e.gelaende.find(x => x[4] === b);
        if (!r || S.g.typ[b] !== typ || !fl.includes((r[2] - r[0] + 1) * (r[3] - r[1] + 1))) f('gelaende');
      }
      if (e.stufe >= R.WACHE_STUFE + 0 && Si.wache < 0 && S.tag - e.stufenTage[R.WACHE_STUFE] > 30) f('wacheFehlt');
      if (e.stufe >= R.JVA_STUFE && Si.jva < 0 && S.tag - e.stufenTage[R.JVA_STUFE] > 30) f('jvaFehlt');
      // Haft: Art, Ort, keine Stelle, in keiner Belegschaft, keine Grundsicherung; U-Haft hat ein offenes Verfahren; Plätze reichen
      const inBeleg = new Set(); for (let b = 0; b < S.gAnzahl; b++) for (const w of S.belegschaft[b]) inBeleg.add(w);
      let hier = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p]) continue;
        if (P.haftBis[p]) {
          haftNaechte++;
          if (!(P.haftArt[p] >= 1 && P.haftArt[p] <= 3) || !(P.haftOrt[p] === 1 || P.haftOrt[p] === 2) || P.arbeit[p] >= 0 || inBeleg.has(p) || P.gsTage[p]) f('haft');
          if (P.haftOrt[p] === 1) { hier++; if (Si.jva < 0) f('ortOhneAnstalt'); }
          if (P.haftArt[p] === M.HAFT_U && !Si.verfahren.some(v => v.id === p && v.gen === P.gen[p] && v.uhaft >= 0)) f('uhaftOhneVerfahren');
          if (P.haftArt[p] !== M.HAFT_U && P.haftBis[p] <= S.tag - 1) f('nichtEntlassen');
        } else if (P.haftArt[p] || P.haftOrt[p] || P.haftNach[p]) f('haftReste');
      }
      if (hier > R.JVA_PLAETZE || Si.aussen < 0 || hier + Si.aussen > R.JVA_PLAETZE) f('plaetze');
      // Kinder: Ist kein Erwachsener ihres Haushalts frei, leben sie in Obhut (Angehörige oder Jugendamt), sonst nicht
      const frei = new Set(); for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.hh[p] >= 0 && P.geb[p] <= erwTag && !P.haftBis[p]) frei.add(P.hh[p]);
      for (let k = 0; k < S.pMax; k++) {
        if (!P.lebt[k] || P.geb[k] <= erwTag || P.hh[k] < 0) continue;
        const allein = !frei.has(P.hh[k]);
        if (allein !== (P.obhut[k] > 0)) f('obhut');
        if (P.obhut[k]) kinderObhut++;
        const q = P.obhutBei[k];
        if (P.obhut[k] === 1 && !(q >= 0 && P.lebt[q] && !P.haftBis[q] && erwachsen(S, q) && P.hh[q] !== P.hh[k] && P.gen[q] === P.obhutGen[k])) f('obhutBei');
      }
      // Stadtbuch: Zeilen zur Sicherheit ohne Namen
      for (const z of S.buch) if (z.nr > buchNr && z.art === 'sicherheit') { zeilen++; if (/\u0001/.test(z.text)) f('buchName'); }
      buchNr = S.buchNr;
    }
    const st = S.stat.sicherheit;
    pruef(!Object.keys(fehl).length && !tatFehl && !opferFehl && !hofFehl && mc.__landBudget === lb0,
      `Seed ${seed}, ${naechte} Nächte: ${haftNaechte} Haftnächte, ${kinderObhut} Kindernächte in Obhut, ${zeilen} Zeilen im Stadtbuch ohne Namen; Wache ab ${M.STUFEN[stufeWache] || '–'}, `
      + `Anstalt ab ${M.STUFEN[stufeJva] || '–'} auf eigenem Gelände; Täter erwachsen und frei, Opfer aus einem anderen Haushalt (${tatFehl + opferFehl} Fehler); Hof nur zur eigenen Zeit (${hofFehl}); `
      + `Landeslöhne nie aus dem Budget (${mc.__landBudget - lb0}); weitere Fehler: ${JSON.stringify(fehl)}`);
    pruef(stufeWache >= R.WACHE_STUFE && stufeJva >= R.JVA_STUFE && st.haftAntritte > 0 && st.urteile > 0,
      `Seed ${seed}: ${st.taten.slice(1).join('/')} Taten, ${st.urteile} Urteile, ${st.haftAntritte} Haftantritte (${st.haftAussen} außerhalb), ${st.obhutFamilie}+${st.obhutJugendamt} Obhut, ${st.getilgt} getilgt`);
  }
  mc.__tat = null; mc.__urteil = null;

  // 3. Erzwungene Fälle an einer Kopie der Stadt (Seed 2, Tag 300, 13 Uhr)
  {
    const basis = (() => { const S = Sim.neueStadt(2); while (S.tag < 300 || S.stunde < 13) Sim.stunde(S); return speichernAlsText(Sim, S); })();
    const neu = () => ladenAusText(Sim, basis);
    // Erwachsene ohne Haft, Betrieb, Verfahren, Bewährung; gut bei Kasse oder pleite
    const kandidat = (S, n = 0) => { let k = 0; for (let p = 0; p < S.pMax; p++) {
      const P = S.p; if (!P.lebt[p] || !erwachsen(S, p) || S.tag - P.geb[p] >= R.RENTE * J || P.haftBis[p] || P.besitz[p] >= 0 || P.vorstrafen[p] || P.bewaehrungBis[p] > S.tag
        || S.sicherheit.verfahren.some(v => v.id === p)) continue;
      if (k++ === n) return p; } return -1; };
    const opfer = (S, p) => { for (let q = 0; q < S.pMax; q++) if (q !== p && S.p.lebt[q] && erwachsen(S, q) && S.p.hh[q] !== S.p.hh[p]) return q; return -1; };
    const verf = (S, p, typ, uhaft) => ({ id: p, gen: S.p.gen[p], typ, beute: 0, opfer: opfer(S, p), opferGen: S.p.gen[opfer(S, p)], urteil: S.tag, uhaft });
    const letzte = (S) => S.buch.filter(e => e.art === 'sicherheit').at(-1);
    const ET = 365 / J;
    // a) Geldstrafe nicht bezahlbar: Ersatzfreiheitsstrafe, 2 Tagessätze = 1 Tag, auf Spieltage aufgerundet
    for (const [n, ts] of [[0, 30], [1, 90]]) {
      const S = neu(), p = kandidat(S), st = S.stat.sicherheit, e0 = st.ersatz, b0 = S.buchNr;
      if (n) { S.p.vorstrafen[p] = 1; S.p.tilgungBis[p] = S.tag + 50; }
      S.p.geld[p] = 0;
      X.urteilen(S, verf(S, p, Sim.DIEBSTAHL, -1));
      const echt = Math.ceil(ts / 2), spiel = Math.max(1, Math.ceil(echt / ET)), z = letzte(S);
      pruef(st.ersatz === e0 + 1 && S.p.haftBis[p] === S.tag + spiel && S.p.haftArt[p] === Sim.HAFT_KURZ && S.buchNr > b0 && z.text.includes(`${ts} Tagessätzen`) && z.text.includes(`${echt} Tage Ersatzfreiheitsstrafe`)
        && !/\u0001/.test(z.text), `${ts} Tagessätze, kein Geld: ${echt} Tage Ersatzfreiheitsstrafe (§ 43 StGB: 2 Tagessätze = 1 Tag), ${spiel} Spieltag(e), kurze Haft; „${Sim.klartext(z.text).slice(0, 150)}…“`);
    }
    // b) teilweise bezahlt: nur der Rest wird Ersatzfreiheitsstrafe; ganz bezahlt: keine Haft, Tilgung nach 5 Jahren
    {
      const S = neu(), p = kandidat(S), q = kandidat(S, 1), st = S.stat.sicherheit;
      S.p.geld[q] = 1e6; const g0 = st.geldSumme, gq = S.p.geld[q];
      X.urteilen(S, verf(S, q, Sim.BETRUG, -1));
      const bez = st.geldSumme - g0;
      pruef(!S.p.haftBis[q] && bez > 0 && S.p.geld[q] === gq - bez && S.p.tilgungBis[q] === S.tag + R.TILGUNG[0] && S.p.vorstrafen[q] === 1,
        `Geldstrafe bezahlt (${bez} Taler an das Land): keine Haft, im Register bis Tag ${S.p.tilgungBis[q]} (5 Jahre, § 46 Abs. 1 Nr. 1a BZRG)`);
      const T = neu(), p2 = kandidat(T);
      // Betrag = 30 Tagessätze zu je Tagesnetto / 36,5; mit der Hälfte davon bleiben 15 Tagessätze offen
      const satz = Math.max(0.1, (T.p.arbeit[p2] >= 0 && !T.p.gemein[p2] ? T.g.lohn[T.p.arbeit[p2]] * (1 - Sim.steuerSatz(T)) : Sim.tageskosten(T, p2)) / ET);   // Haushalt: Nettolohn zum heutigen Satz
      const voll = Math.max(1, Math.round(30 * satz)); T.p.geld[p2] = Math.floor(voll / 2);
      X.urteilen(T, verf(T, p2, Sim.BETRUG, -1));
      const offen = Math.ceil(30 * (voll - Math.floor(voll / 2)) / voll);
      pruef(T.p.haftBis[p2] === T.tag + Math.max(1, Math.ceil(Math.ceil(offen / 2) / ET)) && letzte(T).text.includes(`${offen} davon nicht`),
        `halb bezahlt: ${offen} von 30 Tagessätzen offen → ${Math.ceil(offen / 2)} Tage Ersatzfreiheitsstrafe („${Sim.klartext(letzte(T).text).slice(0, 120)}…“)`);
    }
    // c) Wohnungseinbruch, erste Freiheitsstrafe, 3 Tage U-Haft: die Hälfte (5 Tage) absitzen, 3 angerechnet, Rest 5 Tage zur Bewährung
    {
      const S = neu(), p = kandidat(S), st = S.stat.sicherheit;
      X.haftAntritt(S, p, R.VERFAHREN, Sim.HAFT_U);
      const v = verf(S, p, Sim.EINBRUCH, S.tag - 3);
      X.urteilen(S, v);
      pruef(S.p.haftBis[p] === S.tag + 2 && S.p.haftArt[p] === Sim.HAFT_KURZ && S.p.bewaehrungRest[p] === 5 && S.p.bewaehrungBis[p] === S.tag + 2 + R.BEWAEHRUNG
        && S.p.tilgungBis[p] === S.tag + R.TILGUNG[1] && S.p.freiheitReg[p] === 1 && st.freiheit >= 1 && /1 Jahr Freiheitsstrafe; (er|sie) sitzt die Hälfte ab/.test(letzte(S).text) && /; 110 Tage Untersuchungshaft \(in der Stadt 3 Spieltage\) werden angerechnet/.test(letzte(S).text),
        `Wohnungseinbruch, erstes Mal, 3 Tage U-Haft: noch 2 Tage Haft, 5 Tage Rest auf Bewährung bis Tag ${S.p.bewaehrungBis[p]}, Tilgung nach 10 Jahren (§ 46 Abs. 1 Nr. 2b BZRG)`);
      // d) Widerruf: in der Bewährungszeit wieder verurteilt (Diebstahl, jetzt 2 Vorstrafen: Mehrfachtäter, 6 Monate) → zwei Drittel + Rest
      X.haftEnde(S, p); S.tag += 3;                           // drei Tage später (nur die Kopie)
      S.p.geld[p] = 1e6; S.p.vorstrafen[p] = 2;               // mit zwei Einträgen: Mehrfachtäter
      const w0 = st.widerrufe;
      X.urteilen(S, verf(S, p, Sim.DIEBSTAHL, -1));
      pruef(st.widerrufe === w0 + 1 && S.p.haftBis[p] === S.tag + Math.ceil(5 * 2 / 3) + 5 && S.p.haftArt[p] === Sim.HAFT_STRAF && S.p.tilgungBis[p] === S.tag + R.TILGUNG[2] + 5,
        `Widerruf: zweite Freiheitsstrafe (6 Monate, zwei Drittel = 4 Tage) und der Rest der ersten (5 Tage): ${S.p.haftBis[p] - S.tag} Tage Strafhaft, Tilgung nach 15 Jahren plus Dauer`);
    }
    // e) Tilgung: Einträge älter als die Frist sind beim nächsten Urteil weg (dann wieder erste Geldstrafe, 30 Tagessätze)
    {
      const S = neu(), p = kandidat(S), st = S.stat.sicherheit, t0 = st.getilgt;
      S.p.vorstrafen[p] = 2; S.p.freiheitReg[p] = 1; S.p.tilgungBis[p] = S.tag; S.p.geld[p] = 1e6;
      X.urteilen(S, verf(S, p, Sim.DIEBSTAHL, -1));
      pruef(st.getilgt === t0 + 1 && S.p.vorstrafen[p] === 1 && !S.p.haftBis[p] && S.p.tilgungBis[p] === S.tag + R.TILGUNG[0], 'Tilgung: zwei getilgte Einträge zählen nicht mehr, wieder eine Geldstrafe (kein Mehrfachtäter)');
    }
    // f) Anrechnung bei Geldstrafe (§ 51 Abs. 4 StGB: 1 Tag U-Haft = 1 Tagessatz): 1 Spieltag U-Haft = 37 echte Tage > 30 Tagessätze → keine Geldstrafe
    {
      const S = neu(), p = kandidat(S), st = S.stat.sicherheit, g0 = st.geldSumme;
      X.haftAntritt(S, p, 1, Sim.HAFT_U);
      X.urteilen(S, verf(S, p, Sim.DIEBSTAHL, S.tag - 1));
      const S2 = neu(), p2 = kandidat(S2); S2.p.vorstrafen[p2] = 1; S2.p.tilgungBis[p2] = S2.tag + 50; S2.p.geld[p2] = 0;
      X.haftAntritt(S2, p2, 1, Sim.HAFT_U);
      X.urteilen(S2, verf(S2, p2, Sim.DIEBSTAHL, S2.tag - 1));
      const rest = 90 - Math.round(ET), echt = Math.ceil(rest / 2);
      pruef(st.geldSumme === g0 && !S.p.haftBis[p] && S2.p.haftBis[p2] === S2.tag + Math.ceil(echt / ET) && letzte(S2).text.includes(`${rest} Tagessätzen`),
        `Anrechnung: 1 Spieltag U-Haft gleicht 30 Tagessätze aus (frei); bei 90 bleiben ${rest}, kein Geld → ${echt} Tage Ersatzfreiheitsstrafe`);
    }
    // g) Randfall: in U-Haft (Verfahren B) eine Ersatzfreiheitsstrafe aus Verfahren A: bleibt U-Haft bis zum Urteil B, danach folgt A
    {
      const S = neu(), p = kandidat(S);
      X.haftAntritt(S, p, R.VERFAHREN, Sim.HAFT_U);
      const vB = verf(S, p, Sim.EINBRUCH, S.tag); vB.urteil = S.tag + R.VERFAHREN; S.sicherheit.verfahren.push(vB);
      const bis0 = S.p.haftBis[p], t0 = S.tag;
      X.haftAntritt(S, p, 1, Sim.HAFT_KURZ);                   // Ersatzfreiheitsstrafe aus A
      const u = S.p.haftArt[p] === Sim.HAFT_U && S.p.haftBis[p] === bis0 && S.p.haftNach[p] === 1;
      let frei = false;
      while (S.sicherheit.verfahren.some(v => v.id === p)) { Sim.stunde(S); if (!S.p.haftBis[p]) frei = true; }
      // Urteil in der Nacht von Tag t0 + 3: 1 Jahr, die Hälfte (5) minus 3 Tage U-Haft = 2, dazu 1 Tag aus A → bis Tag t0 + 3 + 3, kurze Haft
      pruef(u && !frei && S.p.haftBis[p] === t0 + R.VERFAHREN + 3 && S.p.haftArt[p] === Sim.HAFT_KURZ && !S.p.haftNach[p],
        `Randfall: Ersatzfreiheitsstrafe während U-Haft ändert die U-Haft nicht (haftNach 1), niemand kommt vor dem Urteil frei; danach Strafe und Anschluss bis Tag ${S.p.haftBis[p]}`);
    }
    // h) Volle Anstalt: 12 Plätze, der 13. Gefangene kommt nach außerhalb; Strafe während Strafhaft wird angehängt
    {
      const S = neu();
      if (!Sim.sicherheitInfo(S).jvaOffen) { const T = S; while (!Sim.sicherheitInfo(T).jvaOffen && T.tag < 700) Sim.stunde(T); }
      const L = []; for (let n = 0; L.length < R.JVA_PLAETZE + 1 && n < 500; n++) { const p = kandidat(S, n); if (p >= 0 && !L.includes(p)) L.push(p); }
      for (const p of L) if (!S.p.haftBis[p]) X.haftAntritt(S, p, 10, Sim.HAFT_STRAF);
      const orte = L.map(p => S.p.haftOrt[p]), hier = X.insassen(S);
      const bis0 = S.p.haftBis[L[0]]; X.haftAntritt(S, L[0], 4, Sim.HAFT_KURZ);
      pruef(Sim.sicherheitInfo(S).jvaOffen && hier === R.JVA_PLAETZE && orte.filter(o => o === 2).length >= 1 && S.p.haftBis[L[0]] === bis0 + 4 && S.p.haftArt[L[0]] === Sim.HAFT_STRAF,
        `volle Anstalt (Tag ${S.tag}): ${hier} von ${R.JVA_PLAETZE} Plätzen, der nächste sitzt außerhalb; eine neue Strafe in Strafhaft wird angehängt`);
      Sim.stunde(S); while (S.stunde) Sim.stunde(S);
      const i = Sim.sicherheitInfo(S);
      pruef(i.aussen === 0 && i.jvaStellen === Math.ceil(R.JVA_JE_GEFANGENEM * R.JVA_PLAETZE), `volle Anstalt: keine Gefangenen von außerhalb mehr (${i.aussen}), ${i.jvaStellen} Stellen (0,65 je Gefangenem)`);
    }
    // i) Obhut: einziger Erwachsener mit Kind kommt in Haft → Angehörige oder Jugendamt; nach der Entlassung wieder zu Hause.
    //    Gibt es an Tag 300 keinen solchen Haushalt (seit Teil 3: Seed 2), läuft die Kopie Tag für Tag weiter (13 Uhr), höchstens bis Tag 500.
    //    Version 8: Im neuen Verlauf hat Seed 2 bis Tag 730 keinen (gemessen); dann dieselbe Suche in Seed 1 und 3 ab Tag 300
    {
      let S = neu(), P = S.p, kopf = -1, erwT = 0, seedO = 2;
      for (const sd of [2, 1, 3]) {
        if (sd !== 2) { seedO = sd; S = Sim.neueStadt(sd); while (S.tag < 300 || S.stunde < 13) Sim.stunde(S); P = S.p; }
        while (kopf < 0 && S.tag <= 500) {
          erwT = S.tag - R.ERWACHSEN * J;
          for (let k = 0; k < S.pMax && kopf < 0; k++) {
            if (!P.lebt[k] || P.hh[k] !== k || !S.hhKinder[k] || P.besitz[k] >= 0) continue;
            const erw = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === k && P.geb[m] <= erwT);
            if (erw.length === 1) kopf = k;
          }
          if (kopf < 0) { const z = S.tag + 1; while (S.tag < z || S.stunde < 13) Sim.stunde(S); }
        }
        if (kopf >= 0) break;
      }
      if (kopf < 0) pruef(false, 'Obhut: bis Tag 500 kein Haushalt mit nur einem Erwachsenen und Kindern gefunden (Seeds 2, 1, 3)');
      else {
        console.log(`       Obhut: Fall in Seed ${seedO}, Tag ${S.tag}`);
        const kinder = S.bewohner[P.wohnung[kopf]].filter(m => P.hh[m] === kopf && P.geb[m] > erwT), st = S.stat.sicherheit, b0 = S.buchNr;
        const stand = speichernAlsText(Sim, S);                // derselbe Stand für den Fall ohne Angehörige
        X.haftAntritt(S, kopf, 5, Sim.HAFT_STRAF); X.obhutPruefen(S);
        const arten = kinder.map(k => P.obhut[k]), zeile = S.buch.filter(e => e.nr > b0 && e.art === 'sicherheit').at(-1);
        const karte = Sim.gebaeudeInfo(S, P.wohnung[kopf]).personen.filter(x => kinder.includes(x.id)).map(x => x.weg);
        const pk = Sim.personInfo(S, kinder[0]);
        pruef(arten.every(a => a > 0) && zeile && !/\u0001/.test(zeile.text) && karte.every(w => /bei Angehörigen|beim Jugendamt/.test(w)) && pk.obhut && pk.gedaechtnis.length,
          `Obhut: ${kinder.length} Kind(er) von ${Sim.name(S, kopf)} ${arten[0] === 1 ? 'bei Angehörigen' : 'beim Jugendamt'} („${Sim.klartext(zeile ? zeile.text : '').slice(0, 110)}“); Hauskarte „${karte[0]}“`);
        // Ohne Angehörige (Eltern-Verweise weg): Jugendamt, der Kita-Platz wird frei
        const T = ladenAusText(Sim, stand), Q = T.p, k0 = kinder[0], ja0 = T.stat.sicherheit.obhutJugendamt;   // Haushalt (Teil 3): Seed 2 hatte schon einen Fall vorher
        for (const k of kinder) { Q.elternA[k] = -1; Q.elternB[k] = -1; }
        X.haftAntritt(T, kopf, 5, Sim.HAFT_STRAF); X.obhutPruefen(T);
        pruef(kinder.every(k => Q.obhut[k] === 2 && !Q.kita[k]) && T.stat.sicherheit.obhutJugendamt - ja0 === kinder.length && /Jugendamt/.test(T.buch.filter(e => e.art === 'sicherheit').at(-1).text),
          `Obhut ohne Angehörige: das Jugendamt nimmt die Kinder in Obhut (§ 42 SGB VIII), Pflegefamilie außerhalb, Kita-Platz frei (${T.stat.sicherheit.obhutJugendamt - ja0} neu, ${ja0} vorher)`);
        X.haftEnde(T, kopf); X.obhutPruefen(T);
        pruef(kinder.every(k => !Q.obhut[k] && Q.obhutBei[k] === -1) && Q.hh[k0] === kopf, 'nach der Entlassung: die Kinder sind wieder zu Hause, Obhut beendet');
      }
    }
    // j) Grundsicherung endet mit der Haft, Arbeitsentgelt nur in Strafhaft (nicht in U-Haft), Rente läuft weiter
    {
      const S = neu(), p = kandidat(S), q = kandidat(S, 3);
      S.p.gsTage[p] = 3;
      X.haftAntritt(S, p, 5, Sim.HAFT_STRAF); X.haftAntritt(S, q, 5, Sim.HAFT_U);
      while (S.stunde !== 23) Sim.stunde(S);
      let straf = 0; for (let x = 0; x < S.pMax; x++) if (S.p.lebt[x] && S.p.haftBis[x] && S.p.haftArt[x] !== Sim.HAFT_U) straf++;
      const h0 = S.stat.sicherheit.haftLohn;
      Sim.stunde(S);
      const lohn = S.stat.sicherheit.haftLohn - h0;
      pruef(S.p.gsTage[p] === 0 && S.p.gsTage[q] === 0 && lohn === straf * R.HAFT_LOHN && straf >= 1,
        `in Haft keine Grundsicherung (§ 7 Abs. 4 SGB II); Arbeitsentgelt nur in Strafhaft und kurzer Haft: ${straf} Gefangene × ${R.HAFT_LOHN} = ${lohn} Taler, U-Haft nichts`);
    }
    // k) Speichern und Laden mit Gefangenen (Strafhaft, kurze Haft, U-Haft mit Anschluss), offenen Verfahren, Bewährung, Obhut: bitgleich
    {
      const S = neu(), a = kandidat(S), b = kandidat(S, 1), c = kandidat(S, 2);
      X.haftAntritt(S, a, 8, Sim.HAFT_STRAF); X.haftAntritt(S, b, 2, Sim.HAFT_KURZ);
      X.haftAntritt(S, c, R.VERFAHREN, Sim.HAFT_U); const v = verf(S, c, Sim.EINBRUCH, S.tag); v.urteil = S.tag + 2; S.sicherheit.verfahren.push(v); X.haftAntritt(S, c, 1, Sim.HAFT_KURZ);
      const d = kandidat(S, 4); S.p.bewaehrungBis[d] = S.tag + 20; S.p.bewaehrungRest[d] = 3; S.p.vorstrafen[d] = 1; S.p.tilgungBis[d] = S.tag + 100; S.p.freiheitReg[d] = 1;
      const L = ladenAusText(Sim, speichernAlsText(Sim, S));
      const f0 = fingerabdruck(Sim, S) === fingerabdruck(Sim, L);
      const z = S.tag + 30; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
      pruef(f0 && fingerabdruck(Sim, S) === fingerabdruck(Sim, L) && S.stat.sicherheit.urteile > 0,
        `Speichern mit Strafhaft, kurzer Haft, U-Haft mit Anschluss, offenem Verfahren und Bewährung: geladen gleich, 30 Tage später bitgleich (${fingerabdruck(Sim, S)})`);
    }
    // l) Beschädigte Stände der Version 7 werden abgelehnt
    {
      const S = neu(), p = kandidat(S); X.haftAntritt(S, p, 5, Sim.HAFT_STRAF);
      const text = speichernAlsText(Sim, S);
      const roh = () => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
      const feld = (d, n) => d.arrays.find(a => a.name === 'p.' + n).daten;
      const meld = [];
      for (const [was, kaputt] of [['Haftart 5', d => { feld(d, 'haftArt')[p] = 5; }], ['Haftort 3', d => { feld(d, 'haftOrt')[p] = 3; }],
        ['Obhut 3', d => { feld(d, 'obhut')[kandidat(S, 1)] = 3; }], ['Verfahren Tatart 9', d => { d.json.sicherheit.verfahren.push({ id: 1, gen: 0, typ: 9, beute: 0, opfer: 2, opferGen: 0, urteil: 5, uhaft: -1 }); }],
        ['ohne sicherheit', d => { delete d.json.sicherheit; }], ['Summe Taten zu kurz', d => { d.json.stat.sicherheit.taten.pop(); }],
        ['Wache zeigt auf ein Wohnhaus', d => { d.json.sicherheit.wache = 0; }], ['Zufall negativ', d => { d.werte.rsSich = -1; }],
        ['Geld vom Land als Text', d => { d.json.sicherheit.landGestern = 'x'; }], ['13 von außerhalb', d => { d.json.sicherheit.aussen = 13; }],
        ['Personenfeld fehlt', d => { d.arrays = d.arrays.filter(a => a.name !== 'p.tilgungBis'); }]]) {
        const d = roh(); kaputt(d);
        let e = null; try { Sim.importZustand(d); } catch (x) { e = x; }
        meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
        if (!e || !/^Spielstand (beschädigt|unvollständig)/.test(e.message)) fehler++;
      }
      console.log((meld.every(m => /: Spielstand (beschädigt|unvollständig)/.test(m)) ? '  ok   ' : '  FEHL ') + 'beschädigte Stände abgelehnt: ' + meld.join('; '));
    }
  }

  // 4. Messung: Taten gegen die PKS 2024 (Seeds wie oben, Tag 366–730); nach Gruppen (Seeds 1–6, Tag 200–730), nur gemessen
  {
    const ziel = [0, 22.3, 0.94, 8.9];
    const sum = [0, 0, 0, 0], auf = [0, 0, 0, 0];
    let ewTage = 0;
    for (const seed of seeds) {
      const S = Sim.neueStadt(seed);
      while (S.tag < 366) Sim.stunde(S);
      const t0 = S.stat.sicherheit.taten.slice(), a0 = S.stat.sicherheit.aufgeklaert.slice();
      while (S.tag < 730) { const t = S.tag; Sim.stunde(S); if (S.tag !== t) ewTage += S.einwohner; }
      for (let k = 1; k <= 3; k++) { sum[k] += S.stat.sicherheit.taten[k] - t0[k]; auf[k] += S.stat.sicherheit.aufgeklaert[k] - a0[k]; }
    }
    const je = (k) => sum[k] / (ewTage / J) * 1000, alle = je(1) + je(2) + je(3);
    pruef(alle > 24 && alle < 40, `Taten je 1.000 Einwohner und Jahr (Seeds ${seeds.join(', ')}, Tag 366–730): Diebstahl ${je(1).toFixed(1)}, Wohnungseinbruch ${je(2).toFixed(2)}, `
      + `Betrug ${je(3).toFixed(1)}, zusammen ${alle.toFixed(1)} (PKS 2024: ${ziel[1]} / ${ziel[2]} / ${ziel[3]}, zusammen 32,1); aufgeklärt ${[1, 2, 3].map(k => Math.round(100 * auf[k] / Math.max(1, sum[k])) + ' %').join(' / ')} (PKS 31,4 / 15,3 / 58)`);
    // Gruppen: je Gruppe Erwachsenen-Nächte, Verurteilungen, Opfer; Verhältnis zur Rate aller. Keine Regel liest diese Merkmale
    const G = new Map(); const g = (n) => { if (!G.has(n)) G.set(n, { n: 0, urt: 0, opf: 0 }); return G.get(n); };
    const gruppen = (S, p) => { const P = S.p, a = (S.tag - P.geb[p]) / J;
      return ['alle', P.elternA[p] >= 0 ? 'in der Stadt geboren' : 'zugezogen oder vom Start', P.nach[p] >= 30 && P.nach[p] <= 36 ? 'Nachnamen Kaya bis Kowalski (Liste 31–37)' : 'übrige Nachnamen',
        P.weib[p] ? 'Frauen' : 'Männer', a < 25 ? 'Alter 18–24' : a < 45 ? 'Alter 25–44' : a < 67 ? 'Alter 45–66' : 'Alter 67+']; };
    mc.__urteil = (S, v) => { if (S.tag >= 200 && lebtNoch(S, v.id, v.gen)) for (const n of gruppen(S, v.id)) g(n).urt++; };
    mc.__tat = (S, p, typ, o) => { if (S.tag >= 200 && o >= 0) for (const n of gruppen(S, o)) g(n).opf++; };
    for (const seed of [1, 2, 3, 4, 5, 6]) {
      const S = M.neueStadt(seed), P = S.p;
      while (S.tag < 730) { const t = S.tag; M.stunde(S);
        if (S.tag !== t && S.tag >= 200) for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && erwachsen(S, p)) for (const n of gruppen(S, p)) g(n).n++; }
    }
    mc.__urteil = null; mc.__tat = null;
    const b = G.get('alle');
    console.log('  Messung nach Gruppen (Seeds 1–6, Tag 200–730; relativ zu allen, nur gemessen):');
    const REIHE = ['alle', 'in der Stadt geboren', 'zugezogen oder vom Start', 'Nachnamen Kaya bis Kowalski (Liste 31–37)', 'übrige Nachnamen', 'Frauen', 'Männer',
      'Alter 18–24', 'Alter 25–44', 'Alter 45–66', 'Alter 67+'];
    for (const [n, x] of REIHE.filter(n => G.has(n)).map(n => [n, G.get(n)])) console.log(`       ${n.padEnd(44)} ${String(x.n).padStart(8)} Erwachsenen-Nächte  verurteilt ${(x.urt / x.n / (b.urt / b.n)).toFixed(2)} (${x.urt})  Opfer ${(x.opf / x.n / (b.opf / b.n)).toFixed(2)} (${x.opf})`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zur Sicherheit bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('militaer')) {
  // Bund (Version 7, Teil 3): Kaserne der Bundeswehr, Wehrpflicht mit Ersatzdienst, Dienststelle des Bundesnachrichtendienstes.
  // 1. statisch: kein Zufall im Abschnitt „Bund“, gelesene Personenfelder je Regel (nie Namen, Geschlecht, Herkunft, Einzugstag, Eltern,
  //    Gedächtnis, Heimatliebe), Löhne und Sold nicht aus dem Budget, Ersatzdienst macht keine Kisten, die Dienststelle liest nirgends
  //    Personen (Grenze); Namenstausch. 2. Invarianten nach jeder Nacht (Seeds 1–3, 730 Tage). 3. Erzwungene Fälle (Tod, Haft, Wegzug im
  //    Dienst; Bindung; Einberufung erst ab der Eröffnung; Bauhof voll; leeres Budget; ausgeschaltet). 4. Speichern und Laden, beschädigte
  //    Stände. 5. Messung (nur gemessen, keine Regel liest es): Einberufungen nach Geschlecht und Herkunft, Besetzung. Seeds mit --seeds
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, X = Sim._bund;
  const offenB = (S, b) => b >= 0 && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === S.g.typ[b] && !S.g.leer[b];
  const tausender = (v) => String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const bisStunde = (S, tag, h) => { while (S.tag < tag || (S.tag === tag && S.stunde < h)) Sim.stunde(S); };
  // Kopie mit Messpunkten (liest nur mit): Budget im Zweig der Bundeslöhne, jede Einberufung (Alter, Tag), jedes Dienstende
  const { Sim: M, ctx: mc } = ladeSimMit([
    ['    if (istBund(t)) {                                        // Bund: Kaserne und Dienststelle, Löhne und Wehrsold zahlt der Bund (von außen)\n',
      '    if (istBund(t)) {                                        // Bund: Kaserne und Dienststelle, Löhne und Wehrsold zahlt der Bund (von außen)\n      const __b1 = S.budget;\n'],
    ['      g.umsatz[b] = 0;\n      continue;\n    }\n    let da = 0;', '      g.umsatz[b] = 0;\n      if (S.budget !== __b1) globalThis.__bundBudget++;\n      continue;\n    }\n    let da = 0;'],
    ['  if (ersatz) { S.stat.bund.ersatzdienst++; B.jahr[1]++; } else { S.stat.bund.wehrdienst++; B.jahr[0]++; }\n',
      '  if (ersatz) { S.stat.bund.ersatzdienst++; B.jahr[1]++; } else { S.stat.bund.wehrdienst++; B.jahr[0]++; }\n  if (globalThis.__einb) globalThis.__einb(S, p);\n'],
  ]);
  mc.__bundBudget = 0;
  const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
  const koerper = (f) => {                                    // Körper einer Funktion (oberste Ebene), ohne Kommentare
    const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return null;
    let t = 0, j = code.indexOf('{', i);
    for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; }
    return code.slice(i, j + 1); };
  const felder = (k) => [...new Set([...k.matchAll(/\b(?:P|S\.p)\.(\w+)/g)].map(m => m[1]))].sort();

  // 1. Statisch
  {
    const a = SIM_CODE.indexOf('// ─── Bund (Version 7, Teil 3)'), e = SIM_CODE.indexOf('// Ende Bund');
    const teil = SIM_CODE.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const zuf = teil.match(/\b(zufall|zInt|zufallSich|zufallsCharakter|zufallsName)\s*\(/g) || [];
    pruef(a > 0 && e > a && !zuf.length, `Abschnitt „Bund“ (${teil.split('\n').length} Zeilen): kein Zufall (${zuf.length}); Wehr- oder Ersatzdienst aus einem festen Wert je Person (dienstWahl)`);
    // Je Regel, die über Menschen entscheidet: welche Personenfelder sie lesen darf. Nie: Namen, Geschlecht, Einzugstag, Eltern, Gedächtnis, Heimatliebe
    const ERLAUBT = {
      verpflichtet: ['bund', 'dienstBis'], dienstZahl: ['bund'], dienstWahl: ['geb', 'gen'],
      einberufen: ['arbeit', 'besitz', 'bund', 'dienstBis', 'haftBis'], dienstEnde: ['dienstBis', 'jetzt'], bundStelleFrei: [], bundTag: ['bund'],
      anstellen: ['arbeit', 'bund', 'dienstBis'], austreten: ['arbeit', 'besitz', 'bund', 'dienstBis', 'einsatz', 'gemein'],
    };
    const zuViel = [];
    for (const [f, ok] of Object.entries(ERLAUBT)) {
      const k = koerper(f);
      if (!k) { zuViel.push(f + ': fehlt'); continue; }
      for (const x of felder(k)) if (!ok.includes(x)) zuViel.push(`${f}: P.${x}`);
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo|zufallsName)\s*\(/.test(k)) zuViel.push(`${f}: Name`);
    }
    // In entscheide und erlaubteAktionen: die Zeilen des Bundes lesen nur die Rolle (imDienst) und verpflichtet
    for (const f of ['entscheide', 'erlaubteAktionen']) {
      const z = (koerper(f) || '').split('\n').filter(l => /imDienst|verpflichtet\(/.test(l) && /const imDienst/.test(l));
      for (const l of z) for (const x of felder(l)) if (x !== 'bund') zuViel.push(`${f}: P.${x}`);
      if (z.length !== 1) zuViel.push(`${f}: Zeile imDienst ${z.length}-mal`);
    }
    const w = koerper('wirtschaft') || '', wb = w.slice(w.indexOf('    if (istBund(t)) {'), w.indexOf('    let da = 0;'));
    const ers = w.slice(w.indexOf('if (P.bund[w] === ERSATZDIENST) {'), w.indexOf('continue;', w.indexOf('if (P.bund[w] === ERSATZDIENST) {')));
    // Teil 5: der Umlandpreis zählt die Arbeitstage je Betrieb (n) und teilt sie nach dem Markt (Umland oder Welt) auf
    const kisten = (SIM_CODE.match(/if \(!P\.frei\[w\] && !P\.einsatz\[w\] && P\.bund\[w\] !== ERSATZDIENST\) (exportArbeiter|da|n)\+\+;/g) || []).length;
    pruef(!zuViel.length, `Regeln lesen nur ihre Personenfelder (${Object.keys(ERLAUBT).length} Funktionen und die Bund-Zeilen in entscheide und erlaubteAktionen), keine Namen, kein Geschlecht`
      + (zuViel.length ? ': ' + zuViel.join(', ') : ''));
    pruef(wb.length > 100 && !/S\.budget/.test(wb) && ers.length > 20 && !/S\.budget/.test(ers) && kisten === 3,
      `wirtschaft: Löhne und Sold des Bundes (Kaserne, Dienststelle, Ersatzdienst im Bauhof) berühren das Budget nicht; Ersatzdienst zählt an ${kisten} von 3 Stellen nicht als Kisten-Arbeiter (Umlandpreis, Werkstatt, Kisten)`);
    // Grenze: Die Dienststelle beobachtet niemanden. Nur diese Funktionen nennen sie (Bau, Stellen, Texte, Prüfung); wer eine dazunimmt, prüft die Grenze neu
    const NENNEN = ['istBetrieb', 'istBund', 'stellen', 'betriebWort', 'bauName', 'bundLeer', 'bundStelleFrei', 'bundTag', 'bundInfo', 'bundPruefen', 'betriebText',
      'erinnerungText', 'berufWort', 'bauGesamt', 'bauArt', 'heuteArbeit'];   // Version 8: der Arbeitstext steht in heuteArbeit (heuteText hängt nur die Autofahrt an)
    const alle = [...code.matchAll(/^function (\w+)\(/gm)].map(m => m[1]).filter(f => /\bDIENSTSTELLE\b|\bB\.dienst\b|\bbund\.dienst\b|\bdOffen\b/.test(koerper(f)));
    const neuN = alle.filter(f => !NENNEN.includes(f)), wegN = NENNEN.filter(f => !alle.includes(f));
    const ueber = /function (\w*([Üü]berwach|[Uu]eberwach|[Bb]eobacht|[Vv]erdacht|[Dd]ossier)\w*|\w*Akten?)\(/.test(code) || Sim.PF_BUND.join() !== 'bund,dienstBis';
    pruef(!neuN.length && !wegN.length && !ueber && Sim.bundInfo(Sim.neueStadt(1)).ueberwacht === 0,
      `Grenze: die Dienststelle nennen nur ${alle.length} Funktionen (Bau, Stellen, Texte, Prüfung), keine liest Personen für sie; keine Funktion und kein Personenfeld zum Überwachen`
      + (neuN.length || wegN.length ? `; neu: ${neuN.join(', ')}; weg: ${wegN.join(', ')}` : ''));
    // Namenstausch (andere Namen, sonst gleich; Seed 2, 400 Tage, Kaserne offen): keine Regel liest Namen, also läuft die Stadt bitgleich
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(2), B = T.neueStadt(2);
    while (A.tag < 400) Sim.stunde(A); while (B.tag < 400) T.stunde(B);
    const spur = (S) => { const h = createHash('sha256'); for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n])) { const a = S.p[n], w = a.length / S.pKap; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) if (ArrayBuffer.isView(S.g[n])) { const a = S.g[n]; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      h.update(JSON.stringify(S.stat)); h.update(JSON.stringify(S.bund)); h.update(String(S.rs) + '/' + S.rsSich + '/' + S.budget); h.update(S.buch.map(e => e.art).join()); return h.digest('hex').slice(0, 16); };
    const iA = Sim.bundInfo(A), nA = Sim.name(A, 5), nB = T.name(B, 5);
    pruef(nA !== nB && spur(A) === spur(B) && iA.kaserneOffen && A.stat.bund.wehrdienst + A.stat.bund.ersatzdienst > 0,
      `Namenstausch (Seed 2, 400 Tage, ${A.stat.bund.wehrdienst} + ${A.stat.bund.ersatzdienst} Einberufungen): „${nA}“ heißt dort „${nB}“, die Stadt läuft trotzdem bitgleich (${spur(A)})`);
  }

  // 2. Invarianten nach jeder Nacht
  const seeds = arg('seeds', '1,2,3').split(',').map(Number);
  const mess = { wehr: [0, 0], ersatz: [0, 0], einb: 0, tageSoldat: 0, tageZivil: 0, tageDienst: 0, naechte: 0, kOffen: [], dOffen: [] };
  for (const seed of seeds) {
    const S = M.neueStadt(seed), P = S.p, fehl = {};
    const f = (k) => { fehl[k] = (fehl[k] || 0) + 1; };
    const dienst = new Map();                                  // p → { gen, start, bis, art, wohnung }
    const gebunden = new Map();                                // verpflichtete Soldaten der letzten Nacht: p → gen
    let naechte = 0, einbHook = 0, buchNr = S.buchNr, zeilen = 0, summeVor = 0, stufeK = -1, stufeD = -1, gezaehlt = 0, verpasst = 0, vorOeffnung = 0, wartenK = 0, wartenD = 0;
    let vorher = new Set();                                    // wer vor dieser Nacht schon da war (Zuzug in der Nacht wurde nicht hier 18)
    const bb0 = mc.__bundBudget;
    mc.__einb = (S, p) => { einbHook++; const P = S.p;
      if (S.tag - P.geb[p] !== R.ERWACHSEN * J || S.tag < S.bund.kOffen || !S.bund.kOffen) f('einbAlter');
      mess[P.bund[p] === M.WEHRDIENST ? 'wehr' : 'ersatz'][P.weib[p] ? 1 : 0]++;   // nur gemessen
      mess.einb++; };
    let freiFehl = 0, aktFehl = 0, aktGeprueft = 0;
    while (S.tag < 730) {
      const t = S.tag;
      M.stunde(S);
      // Tagsüber: niemand im Dienst hat frei; erlaubte Aktionen um 7 und 18 Uhr (im Dienst: kein Wechsel, keine Kündigung, kein freier Tag,
      // keine Gründung, kein Wegzug; verpflichtet: kein Wechsel, keine Kündigung, keine Gründung). entscheide zieht Zufall und prüft Fall 3 d
      if (S.tag === t && (S.stunde === 7 || S.stunde === 18)) {
        for (let p = 0; p < S.pMax; p++) {
          if (!P.lebt[p] || !P.bund[p]) continue;
          const im = P.bund[p] >= M.WEHRDIENST, vp = M.verpflichtet(S, p);
          if (im && P.frei[p]) freiFehl++;
          if (!im && !vp) continue;
          aktGeprueft++;
          const erl = M.erlaubteAktionen(S, p, S.stunde);
          const verb = im ? ['job_wechseln', 'kuendigen', 'freinehmen', 'laden_gruenden', 'wegziehen', 'job_suchen'] : ['job_wechseln', 'kuendigen', 'laden_gruenden'];
          if (erl.some(x => verb.includes(x))) aktFehl++;
        }
      }
      if (S.tag === t) continue;
      naechte++;
      const B = S.bund, e = S.erweiterung, K = B.kaserne, D = B.dienst, g = S.g, nacht = S.tag - 1;
      if (K >= 0 && stufeK < 0) stufeK = e.stufe;
      if (D >= 0 && stufeD < 0) stufeD = e.stufe;
      // Kaserne ab der Stadt, Dienststelle ab der Großstadt, auf eigenem Gelände (3 × 2 Blöcke = 11 × 7 Felder; 1 Block = 3 × 3). Der Bund
      // wartet nur, solange es kein Gelände gibt (Teil 1: ganz freie Blöcke an einer Straße; gesucht nach dem Bauamt, danach wächst höchstens
      // die Karte): war die Stufe schon vor dieser Nacht erreicht und steht noch nichts, findet gelaendeSuchen auch jetzt nichts
      if (e.stufe >= R.KASERNE_STUFE && K < 0 && e.stufenTage[R.KASERNE_STUFE] < nacht) {
        wartenK++; if (M.gelaendeSuchen(S, R.KASERNE_BLOECKE[0], R.KASERNE_BLOECKE[1], true) || M.gelaendeSuchen(S, R.KASERNE_BLOECKE[1], R.KASERNE_BLOECKE[0], true)) f('kaserneTrotzGelaende'); }
      if (e.stufe >= R.DIENST_STUFE && D < 0 && e.stufenTage[R.DIENST_STUFE] < nacht) {
        wartenD++; if (M.gelaendeSuchen(S, R.DIENST_BLOECKE[0], R.DIENST_BLOECKE[1], true)) f('dienstTrotzGelaende'); }
      for (const [b, typ, fl] of [[K, M.KASERNE, 77], [D, M.DIENSTSTELLE, 9]]) {
        if (b < 0) continue;
        const r = e.gelaende.find(x => x[4] === b);
        if (!r || g.typ[b] !== typ || (r[2] - r[0] + 1) * (r[3] - r[1] + 1) !== fl || g.besitzer[b] !== -1) f('gelaende');
      }
      if (offenB(S, K) && (!B.kOffen || B.kOffen > S.tag)) f('kOffen');
      if (offenB(S, D) && (!B.dOffen || B.dOffen > S.tag)) f('dOffen');
      // Rollen, Stellen, Obergrenzen
      let soldaten = 0, zivil = 0, wehr = 0, ersatz = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p]) continue;
        const r = P.bund[p], a = P.arbeit[p];
        if (r === M.SOLDAT) soldaten++; else if (r === M.ZIVIL) zivil++; else if (r === M.WEHRDIENST) wehr++; else if (r === M.ERSATZDIENST) ersatz++;
        if (r >= 1 && r <= 3 && a !== K) f('rolleOrt');
        if (r === 4 && a !== S.bauhof) f('rolleOrt');
        if (a >= 0 && a === K && !(r >= 1 && r <= 3)) f('ohneRolle');
        if (a >= 0 && a === D && r) f('dienstRolle');
        if (r >= 3 && (P.gemein[p] || P.dienstBis[p] < S.tag || P.dienstBis[p] > nacht + R.DIENST_TAGE)) f('dienstBis');
        if (r === M.SOLDAT && !P.dienstBis[p]) f('soldatBis');
        if ((r === 0 || r === M.ZIVIL) && P.dienstBis[p]) f('restBis');
        if (r >= 3 && P.haftBis[p]) f('dienstHaft');
      }
      if (soldaten > R.STELLEN_SOLDAT || zivil > R.STELLEN_ZIVIL || (D >= 0 && S.belegschaft[D].length > R.STELLEN_DIENST)) f('obergrenze');
      for (const b of [K, D, S.bauhof]) if (offenB(S, b) && g.offeneStellen[b] !== M.stellen(S, b) - S.belegschaft[b].length) f('offeneStellen');
      if (K >= 0 && M.stellen(S, K) !== R.STELLEN_SOLDAT + R.STELLEN_ZIVIL + wehr) f('stellenK');
      const ed = X.dienstZahl(S, S.bauhof);
      if (ed !== ersatz || M.stellen(S, S.bauhof) - ed > R.BAU_MAX || S.belegschaft[S.bauhof].length - ed > R.BAU_MAX) f('bauhofGrenze');
      // Dienst: neu (einberufen, in dieser Nacht mit 18, ab dem Tag nach der Eröffnung, wohnt weiter wo vorher), vorbei (genau 5 Tage,
      // sonst abgebrochen: Tod, Haft oder Wegzug mit dem Haushalt)
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p] || P.bund[p] < M.WEHRDIENST) continue;
        const d = dienst.get(p);
        if (d && d.gen === P.gen[p]) continue;
        if (nacht < B.kOffen || !B.kOffen) vorOeffnung++;
        if (nacht - P.geb[p] !== R.ERWACHSEN * J || P.dienstBis[p] !== nacht + R.DIENST_TAGE) f('neu');
        dienst.set(p, { gen: P.gen[p], start: nacht, bis: P.dienstBis[p], art: P.bund[p] });
      }
      for (const [p, d] of [...dienst]) {
        const noch = P.lebt[p] && P.gen[p] === d.gen && P.bund[p] === d.art;
        if (noch) continue;
        dienst.delete(p);
        if (P.lebt[p] && P.gen[p] === d.gen && !P.haftBis[p]) {       // normal zu Ende: in der Nacht des letzten Tages, genau 5 Diensttage
          if (nacht !== d.bis || nacht - d.start !== R.DIENST_TAGE) f('dauer');
          gezaehlt += R.DIENST_TAGE;
        } else if (P.lebt[p] && P.gen[p] === d.gen) gezaehlt += nacht - d.start;   // Haft in dieser Nacht (nach dem Diensttag)
        else gezaehlt += nacht - 1 - d.start;                       // Wegzug mit dem Haushalt (tagsüber) oder Tod: bis zur letzten Nacht
      }
      // Einberufung vollständig: wer in dieser Nacht 18 wurde, ab dem Tag nach der Eröffnung, ohne Haft und Betrieb, ist im Dienst
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p] || nacht - P.geb[p] !== R.ERWACHSEN * J || !vorher.has(p + '/' + P.gen[p])) continue;
        if (B.kOffen && nacht >= B.kOffen && offenB(S, K) && P.bund[p] < M.WEHRDIENST && !P.haftBis[p] && P.besitz[p] < 0) verpasst++;
        if ((!B.kOffen || nacht < B.kOffen) && P.bund[p]) vorOeffnung++;
      }
      // Soldaten auf Zeit bleiben, solange sie verpflichtet sind (außer Tod, Haft, Wegzug, Rente)
      for (const [p, gen] of gebunden) if (P.lebt[p] && P.gen[p] === gen && !P.haftBis[p] && P.bund[p] !== M.SOLDAT && !M.anspruch(S, p)) f('gebunden');
      gebunden.clear();
      vorher = new Set(); for (let p = 0; p < S.pMax; p++) if (P.lebt[p]) vorher.add(p + '/' + P.gen[p]);
      if (S.stat.bund.wehrdienst + S.stat.bund.ersatzdienst !== S.stat.bund.beendet + S.stat.bund.abgebrochen + wehr + ersatz) f('bilanz');
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && M.verpflichtet(S, p)) gebunden.set(p, P.gen[p]);
      // Geld vom Bund: gestern = Zuwachs der Summen in dieser Nacht; Budget nie berührt
      const st = S.stat.bund, summe = st.lohnKaserne + st.lohnDienst + st.sold + st.soldErsatz + st.bau;
      if (B.gestern !== summe - summeVor) f('gestern');
      summeVor = summe;
      // Stadtbuch: Zeilen des Bundes ohne Namen
      for (const z of S.buch) if (z.nr > buchNr && z.art === 'bund') { zeilen++; if (/\u0001/.test(z.text)) f('buchName'); }
      buchNr = S.buchNr;
      if (nacht >= 365) { mess.tageSoldat += soldaten; mess.tageZivil += zivil; mess.tageDienst += D >= 0 ? S.belegschaft[D].length : 0; mess.naechte++; }
    }
    mc.__einb = null;
    for (const d of dienst.values()) gezaehlt += S.tag - 1 - d.start;   // noch im Dienst
    const st = S.stat.bund, i = M.bundInfo(S);
    mess.kOffen.push(S.bund.kOffen); mess.dOffen.push(S.bund.dOffen);
    pruef(!Object.keys(fehl).length && !verpasst && !vorOeffnung && !freiFehl && !aktFehl && einbHook === st.wehrdienst + st.ersatzdienst && mc.__bundBudget === bb0
      && gezaehlt === st.dienstTage,
      `Seed ${seed}, ${naechte} Nächte: Kaserne ab ${M.STUFEN[stufeK] || '–'} (offen ab Tag ${S.bund.kOffen}, ${wartenK} Nächte ohne Gelände gewartet), Dienststelle ab ${M.STUFEN[stufeD] || '–'} `
      + `(offen ab Tag ${S.bund.dOffen || '–'}, ${wartenD} Nächte ohne Gelände gewartet), je auf eigenem Gelände; Einberufene = beendet + abgebrochen + im Dienst; ${st.wehrdienst} Wehr- und ${st.ersatzdienst} Ersatzdienste, alle mit 18 in der Nacht des Geburtstags ab dem Tag nach der Eröffnung `
      + `(${verpasst} verpasst, ${vorOeffnung} vorher), ${st.dienstTage} Diensttage = nachgezählt ${gezaehlt}, ${st.beendet} beendet, ${st.abgebrochen} abgebrochen; `
      + `${aktGeprueft} Entscheidungen im Dienst oder verpflichtet ohne Verbotenes (${aktFehl + freiFehl}); ${zeilen} Zeilen im Stadtbuch ohne Namen; `
      + `Löhne und Sold nie aus dem Budget (${mc.__bundBudget - bb0}); weitere Fehler: ${JSON.stringify(fehl)}`);
    pruef(S.bund.kaserne >= 0 && i.kaserneOffen && st.wehrdienst > 0 && st.ersatzdienst > 0 && st.beendet > 0 && st.lohnKaserne > 0 && st.sold > 0 && st.soldErsatz > 0 && st.bau >= R.K_KASERNE,
      `Seed ${seed}: heute ${i.soldaten} Soldaten (${i.verpflichtet} verpflichtet), ${i.zivil} Zivil, ${i.wehr} im Wehr-, ${i.ersatz} im Ersatzdienst, ${i.nachrichtendienst} im Nachrichtendienst; `
      + `vom Bund bis Tag 730: Löhne ${tausender(st.lohnKaserne + st.lohnDienst)}, Sold ${tausender(st.sold + st.soldErsatz)}, Bau ${tausender(st.bau)} Taler`);
  }
  const wehrN = mess.wehr[0] + mess.wehr[1], ersN = mess.ersatz[0] + mess.ersatz[1], anteil = ersN / Math.max(1, wehrN + ersN);
  pruef(wehrN + ersN > 100 && anteil > 0.6 && anteil < 0.8, `Ersatzdienst-Anteil ${(100 * anteil).toFixed(1)} % (${ersN} von ${wehrN + ersN}; Annahme ${Math.round(100 * R.ERSATZ_ANTEIL)} %, Spanne 60–80 %)`);

  // 3. Erzwungene Fälle an einer Kopie der Stadt (Seed 2, erster Tag ab 300 um 13 Uhr mit Wehr- und Ersatzdienst und verpflichteten Soldaten)
  let basis = null;
  {
    const S = Sim.neueStadt(2);
    bisStunde(S, 300, 13);
    const da = (S) => { const i = Sim.bundInfo(S); return i.wehr >= 1 && i.ersatz >= 2 && i.verpflichtet >= 1; };
    while (!da(S) && S.tag < 700) bisStunde(S, S.tag + 1, 13);
    basis = speichernAlsText(Sim, S);
  }
  const neu = () => ladenAusText(Sim, basis);
  const wer = (S, rolle, n = 0) => { let k = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.bund[p] === rolle && (rolle !== Sim.SOLDAT || Sim.verpflichtet(S, p)) && k++ === n) return p; return -1; };
  {
    const S = neu();
    pruef(Sim.bundInfo(S).wehr >= 1, `Stand für die Fälle: Tag ${S.tag}, ${Sim.bundInfo(S).wehr} im Wehr-, ${Sim.bundInfo(S).ersatz} im Ersatzdienst, ${Sim.bundInfo(S).verpflichtet} verpflichtete Soldaten`);
  }
  // a) Tod im Wehrdienst: Rolle weg, keine Stelle frei, abgebrochen
  {
    const S = neu(), p = wer(S, Sim.WEHRDIENST), K = S.bund.kaserne, st = S.stat.bund, ab = st.abgebrochen, of = S.g.offeneStellen[K], sk = Sim.stellen(S, K), fs = S.freieStellen;
    Sim._pruef.sterben(S, p);
    pruef(p >= 0 && !S.p.lebt[p] && !S.belegschaft[K].includes(p) && st.abgebrochen === ab + 1 && S.g.offeneStellen[K] === of && Sim.stellen(S, K) === sk - 1 && S.freieStellen === fs,
      `Tod im Wehrdienst: nicht mehr in der Kaserne, abgebrochen ${ab} → ${st.abgebrochen}, keine Stelle frei (${of} offen, Stellen ${sk} → ${Sim.stellen(S, K)})`);
  }
  // b) Haft im Ersatzdienst: Dienst endet (vereinfacht), keine Stelle frei, keine Erinnerung „Stelle verloren“
  {
    const S = neu(), p = wer(S, Sim.ERSATZDIENST), B = S.bauhof, st = S.stat.bund, ab = st.abgebrochen, of = S.g.offeneStellen[B];
    const m0 = Sim.personInfo(S, p).gedaechtnis.length;
    Sim._sich.haftAntritt(S, p, 5, Sim.HAFT_STRAF);
    const info = Sim.personInfo(S, p);
    pruef(p >= 0 && S.p.haftBis[p] && !S.p.bund[p] && !S.p.dienstBis[p] && S.p.arbeit[p] < 0 && !S.belegschaft[B].includes(p) && st.abgebrochen === ab + 1 && S.g.offeneStellen[B] === of
      && !info.gedaechtnis.slice(0, info.gedaechtnis.length - m0 + 1).some(m => /Stelle verloren|verliert/.test(m.text)),
      `Haft im Ersatzdienst: Dienst endet, Rolle 0, nicht mehr im Bauhof, abgebrochen ${ab} → ${st.abgebrochen}, keine Stelle frei`);
  }
  // c) Wegzug im Dienst: nur mit dem Haushalt (selbst nicht erlaubt); abgebrochen
  {
    const S = neu(), P = S.p;
    let kind = -1;
    for (let p = 0; p < S.pMax && kind < 0; p++) if (P.lebt[p] && P.bund[p] >= Sim.WEHRDIENST && P.hh[p] >= 0 && P.hh[p] !== p) kind = p;
    if (kind < 0) pruef(true, 'Wegzug im Dienst: niemand im Dienst lebt noch im Haushalt der Eltern (Fall entfällt)');
    else {
      const kopf = P.hh[kind], gen = P.gen[kind], ab = S.stat.bund.abgebrochen, erl = Sim.erlaubteAktionen(S, kind, 7);
      // Version 9: Wer vorher im Dienst war (mit Ende), zählt als abgebrochen, wenn er mit weggeht (auch der Partner des Haushaltsvorstands,
      // wenn beide dienen: in Seed 2 seit dem Rathaus so; vorher war es genau eine Person)
      const imDienst = []; for (let q = 0; q < S.pMax; q++) if (P.lebt[q] && P.bund[q] >= Sim.WEHRDIENST && P.dienstBis[q]) imDienst.push([q, P.gen[q]]);
      // wer 18 ist, geht nicht mit (nur Kinder unter 18): der Dienst läuft weiter
      Sim._pruef.aktWegziehen(S, kopf);
      const bleibt = P.lebt[kind] && P.gen[kind] === gen, weg = imDienst.filter(([q, g]) => !(P.lebt[q] && P.gen[q] === g)).length;
      pruef(!erl.includes('wegziehen') && (bleibt ? P.bund[kind] >= Sim.WEHRDIENST : weg >= 1) && S.stat.bund.abgebrochen === ab + weg,
        `Wegzug: im Dienst selbst nicht erlaubt; zieht der Haushalt weg, ${bleibt ? 'bleibt die erwachsene Person und dient weiter' : 'endet der Dienst (abgebrochen)'}; `
        + `abgebrochen ${ab} → ${S.stat.bund.abgebrochen} (${weg} im Dienst mit weggezogen)`);
    }
  }
  // d) Bindung: verpflichtete Soldaten dürfen nicht wechseln, kündigen oder gründen; mit Rentenanspruch oder nach dem Ende der Verpflichtung schon
  {
    const S = neu(), P = S.p, p = wer(S, Sim.SOLDAT);
    S.freieStellen = 5; P.geld[p] = 1e6;
    const vor = Sim.erlaubteAktionen(S, p, 7), text = Sim.klartext(Sim.personInfo(S, p).arbeit);
    const bis = P.dienstBis[p]; P.dienstBis[p] = S.tag;
    const nach = Sim.erlaubteAktionen(S, p, 7);
    P.dienstBis[p] = bis; const b0 = P.beitrag[p]; P.beitrag[p] = 45 * J + 1;
    const rente = Sim.verpflichtet(S, p); P.beitrag[p] = b0;
    pruef(p >= 0 && !vor.includes('kuendigen') && !vor.includes('job_wechseln') && !vor.includes('laden_gruenden') && nach.includes('kuendigen') && !rente
      && new RegExp(`verpflichtet bis Tag ${bis}`).test(text) && bis - S.tag <= R.VERPFLICHTUNG,
      `Soldat auf Zeit („${text}“): erlaubt ${vor.join(', ') || 'nichts'}; nach dem Ende der Verpflichtung auch kündigen (${nach.join(', ')}); mit Rentenanspruch nicht mehr verpflichtet`);
  }
  // d2) Das normale Gehirn wählt im Dienst oder verpflichtet nichts Verbotenes (48 Stunden an der Kopie, jede Stunde)
  {
    const S = neu(), P = S.p;
    let n = 0, falsch = 0;
    for (let h = 0; h < 48; h++) {
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p] || !P.bund[p] || S.tag - P.geb[p] < R.ERWACHSEN * J) continue;
        const im = P.bund[p] >= Sim.WEHRDIENST;
        if (!im && !Sim.verpflichtet(S, p)) continue;
        const verb = im ? ['job_wechseln', 'kuendigen', 'freinehmen', 'laden_gruenden', 'wegziehen', 'job_suchen'] : ['job_wechseln', 'kuendigen', 'laden_gruenden'];
        const a = Sim.entscheide(S, p, S.stunde); n++;
        if (a && verb.includes(Sim.AKTIONSNAMEN[a])) falsch++;
      }
      Sim.stunde(S);
    }
    pruef(n > 100 && !falsch, `Gehirn: ${n} Entscheidungen im Dienst oder verpflichtet, ${falsch} verboten (Wechsel, Kündigung, Gründung; im Dienst auch frei, Wegzug, Stellensuche)`);
  }
  // e) Kita-Lücke: Wer im Dienst ist oder verpflichtet, hört dafür nicht auf (B10); statisch in kitaTag
  {
    const k = koerper('kitaTag') || '';
    pruef(/P\.bund\[c\] < WEHRDIENST && !verpflichtet\(S, c\)/.test(k), 'Betreuungslücke (Kita): wer im Dienst oder als Soldat verpflichtet ist, hört dafür nicht auf');
  }
  // f) Einberufung erst ab dem Tag nach der Eröffnung; nicht mit Haft, Betrieb oder Stelle; ausgeschaltet nie
  {
    const S = neu(), P = S.p, B = S.bund;
    let q = -1; for (let p = 0; p < S.pMax && q < 0; p++) if (P.lebt[p] && !P.bund[p] && P.arbeit[p] < 0 && P.besitz[p] < 0 && !P.haftBis[p] && S.tag - P.geb[p] < R.ERWACHSEN * J) q = p;
    const ok = [];
    const k0 = B.kOffen; B.kOffen = S.tag + 1; X.einberufen(S, q); ok.push(!P.bund[q]); B.kOffen = k0;   // Eröffnung erst morgen
    R.WEHRPFLICHT = 0; X.einberufen(S, q); ok.push(!P.bund[q]); R.WEHRPFLICHT = 1;
    P.haftBis[q] = S.tag + 3; X.einberufen(S, q); ok.push(!P.bund[q]); P.haftBis[q] = 0;
    const ed0 = X.dienstZahl(S, S.bauhof), zu0 = S.bauZuschlag; S.bauZuschlag = R.BAU_MAX - R.STELLEN_STADT;   // Bauhof voll: Ersatzdienst trotzdem
    X.einberufen(S, q); ok.push(P.bund[q] >= Sim.WEHRDIENST && P.dienstBis[q] === S.tag + R.DIENST_TAGE);
    const ersatz = P.bund[q] === Sim.ERSATZDIENST, ort = P.arbeit[q];
    ok.push(ersatz === (Sim.dienstWahl(S, q) < R.ERSATZ_ANTEIL) && ort === (ersatz ? S.bauhof : B.kaserne));
    if (ersatz) ok.push(X.dienstZahl(S, S.bauhof) === ed0 + 1 && Sim.stellen(S, S.bauhof) - X.dienstZahl(S, S.bauhof) <= R.BAU_MAX);
    S.bauZuschlag = zu0;
    pruef(q >= 0 && ok.every(Boolean), `Einberufung: nicht vor dem Tag nach der Eröffnung, nicht ohne Wehrpflicht, nicht in Haft; ${ersatz ? 'Ersatzdienst auch bei vollem Bauhof (außerhalb der 40)' : 'Wehrdienst'}; `
      + `Wehr oder Ersatz nur nach dienstWahl (${Sim.dienstWahl(S, q).toFixed(3)}) (${ok.map(x => (x ? '1' : '0')).join('')})`);
  }
  // g) Leeres Budget: Ersatzdienst bekommt den Sold trotzdem (vom Bund), Wehrdienst auch; Löhne der Kaserne auch
  {
    const S = neu(); bisStunde(S, S.tag, 23);
    for (let p = 0; p < S.pMax; p++) S.p.jetzt[p] = 0;
    const P = S.p, K = S.bund.kaserne, D = S.bund.dienst, st = S.stat.bund, v = { ...st };
    let soll = { lohnKaserne: 0, lohnDienst: 0, sold: 0, soldErsatz: 0 };
    for (const b of [K, D]) if (offenB(S, b)) for (const w of S.belegschaft[b]) if (!P.frei[w]) {
      if (P.bund[w] === Sim.WEHRDIENST) soll.sold += R.SOLD; else if (b === K) soll.lohnKaserne += S.g.lohn[b]; else soll.lohnDienst += S.g.lohn[b]; }
    for (const w of S.belegschaft[S.bauhof]) if (!P.frei[w] && !P.gemein[w] && P.bund[w] === Sim.ERSATZDIENST) soll.soldErsatz += R.SOLD;
    budgetSetzen(S, 0);
    Sim.stunde(S);
    const ist = Object.fromEntries(Object.keys(soll).map(k => [k, st[k] - v[k]]));
    pruef(JSON.stringify(ist) === JSON.stringify(soll) && soll.soldErsatz > 0 && soll.lohnKaserne > 0,
      `leeres Budget: der Bund zahlt trotzdem, wie nachgerechnet: ${JSON.stringify(ist)}`);
  }
  // h) Ausgeschaltet (BUND_BAUT = 0): keine Kaserne, keine Dienststelle, niemand dient
  {
    const alt = R.BUND_BAUT; R.BUND_BAUT = 0;
    const S = Sim.neueStadt(2); while (S.tag < 400) Sim.stunde(S);
    R.BUND_BAUT = alt;
    let r = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.bund[p]) r++;
    pruef(S.bund.kaserne < 0 && S.bund.dienst < 0 && !r && !S.stat.bund.wehrdienst && S.erweiterung.stufe >= R.KASERNE_STUFE,
      `ohne Bund (BUND_BAUT = 0, Seed 2, 400 Tage, Stufe ${Sim.STUFEN[S.erweiterung.stufe]}): keine Kaserne, keine Dienststelle, niemand dient`);
  }

  // 4. Speichern und Laden mit Wehr- und Ersatzdienst, verpflichteten Soldaten, offener Dienststelle; beschädigte Stände
  {
    const S = Sim.neueStadt(2);
    bisStunde(S, 400, 13);
    const da = (S) => { const i = Sim.bundInfo(S); return i.wehr >= 1 && i.ersatz >= 1 && i.verpflichtet >= 1 && i.dienstOffen && i.nachrichtendienst >= 1; };
    while (!da(S) && S.tag < 700) bisStunde(S, S.tag + 1, 13);
    const i = Sim.bundInfo(S), text = speichernAlsText(Sim, S), L = ladenAusText(Sim, text);
    const kanon = (o) => JSON.stringify(o, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) && !ArrayBuffer.isView(v) ? Object.fromEntries(Object.keys(v).sort().map(x => [x, v[x]])) : v));
    const gleich0 = fingerabdruck(Sim, S) === fingerabdruck(Sim, L) && kanon(S.bund) === kanon(L.bund) && kanon(S.stat.bund) === kanon(L.stat.bund);
    const z = S.tag + 60; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
    pruef(da(ladenAusText(Sim, text)) && gleich0 && fingerabdruck(Sim, S) === fingerabdruck(Sim, L),
      `Speichern an Tag ${z - 60} mit ${i.wehr} im Wehr-, ${i.ersatz} im Ersatzdienst, ${i.verpflichtet} verpflichteten Soldaten, ${i.nachrichtendienst} im Nachrichtendienst: geladen gleich, 60 Tage später bitgleich (${fingerabdruck(Sim, S)})`);
    const roh = () => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
    const T = ladenAusText(Sim, text), feld = (d, n) => d.arrays.find(a => a.name === 'p.' + n).daten;
    let wohnhaus = -1; for (let b = 0; b < T.gAnzahl && wohnhaus < 0; b++) if (T.g.typ[b] === Sim.WOHNHAUS) wohnhaus = b;
    let frei = -1, w = -1; for (let p = 0; p < T.pMax; p++) if (T.p.lebt[p]) { if (frei < 0 && !T.p.bund[p] && T.p.arbeit[p] !== T.bund.kaserne) frei = p; if (w < 0 && T.p.bund[p] === Sim.WEHRDIENST) w = p; }
    const meld = [];
    for (const [was, kaputt] of [['ohne bund', d => { delete d.json.bund; }], ['ohne stat.bund', d => { delete d.json.stat.bund; }], ['Summe Sold als Text', d => { d.json.stat.bund.sold = 'viel'; }],
      ['Kaserne zeigt auf ein Wohnhaus', d => { d.json.bund.kaserne = wohnhaus; }], ['Eröffnung nach morgen', d => { d.json.bund.kOffen = T.tag + 5; }],
      ['Einberufungen im Jahr zu kurz', d => { d.json.bund.jahr = [0]; }], ['Geld vom Bund als Text', d => { d.json.bund.gestern = 'x'; }],
      ['Start nach heute', d => { d.json.bund.start = T.tag + 1; }], ['Dienststelle offen ohne Dienststelle', d => { d.json.bund.dienst = -1; }],
      ['Rolle 5', d => { feld(d, 'bund')[frei] = 5; }], ['Wehrdienst ohne Kaserne als Arbeit', d => { feld(d, 'bund')[frei] = Sim.WEHRDIENST; }],
      ['Wehrdienst und gemeinnützig', d => { feld(d, 'gemein')[w] = 1; }], ['Wehrdienst bis gestern', d => { feld(d, 'dienstBis')[w] = T.tag - 1; }],
      ['Zivil mit Verpflichtung', d => { let z = -1; for (let p = 0; p < T.pMax && z < 0; p++) if (T.p.lebt[p] && T.p.bund[p] === Sim.ZIVIL) z = p; feld(d, 'dienstBis')[z] = T.tag + 3; }],
      ['Personenfeld bund fehlt', d => { d.arrays = d.arrays.filter(a => a.name !== 'p.bund'); }], ['Personenfeld dienstBis fehlt', d => { d.arrays = d.arrays.filter(a => a.name !== 'p.dienstBis'); }]]) {
      const d = roh(); kaputt(d);
      let e = null; try { Sim.importZustand(d); } catch (x) { e = x; }
      meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
      if (!e || !/^Spielstand (beschädigt|unvollständig)/.test(e.message)) fehler++;
    }
    console.log((meld.every(m => /: Spielstand (beschädigt|unvollständig)/.test(m)) && wohnhaus >= 0 && frei >= 0 && w >= 0 ? '  ok   ' : '  FEHL ') + 'beschädigte Stände abgelehnt: ' + meld.join('; '));
  }

  // 5. Messung (Seeds wie oben): Einberufungen nach Geschlecht (keine Regel liest es), Besetzung Tag 366–730, Eröffnung
  {
    const q = (a) => (100 * a[1] / Math.max(1, a[0] + a[1])).toFixed(1);
    console.log(`  Messung: Einberufungen ${mess.einb}: Wehrdienst ${mess.wehr[0]} Männer / ${mess.wehr[1]} Frauen (${q(mess.wehr)} % Frauen), Ersatzdienst ${mess.ersatz[0]} / ${mess.ersatz[1]} (${q(mess.ersatz)} % Frauen)`);
    console.log(`  Messung: Besetzung Tag 366–730 Ø Soldaten ${(mess.tageSoldat / mess.naechte).toFixed(2)} von ${R.STELLEN_SOLDAT}, Zivil ${(mess.tageZivil / mess.naechte).toFixed(2)} von ${R.STELLEN_ZIVIL}, `
      + `Nachrichtendienst ${(mess.tageDienst / mess.naechte).toFixed(2)} von ${R.STELLEN_DIENST}; Kaserne offen ab Tag ${mess.kOffen.join(', ')}, Dienststelle ab ${mess.dOffen.join(', ')}`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zum Bund bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('autos')) {
  // Tech-Firmen und Autos (Version 8). 1. statisch: Zufall nur aus S.rsAuto, gelesene Personenfelder je Regel, keine Namen (nur in Zeilen des
  // Stadtbuchs); Namenstausch bitgleich. 2. Invarianten nach jeder Nacht und je Stunde (Seeds 1–3, 730 Tage): höchstens AUTO_MAX Werke, Werk
  // auf eigenem Gelände, Stufen und Stellen, 40-%-Grenze nach jeder Nacht, Umzug, Fertigung, Käufe (Reserve, Wahl: Werk vor Umland, von
  // außerhalb ab Tag 0), Teile, laufende Kosten und CO₂ je Nacht, Verschrotten, Geldnot, Eröffnung, Grundregel (Auto nur mit Ortswechsel und
  // nur dort, wo der Besitzer war), Testfahrt, faire Reihenfolge. 3. Erzwungen: AUTO_MAX bei Übernahme, Erbe, Geldnot, Haft. 4. Speichern mitten
  // im Werksbau bitgleich, beschädigte Stände. 5. Messung (nur gemessen). Seeds mit --seeds
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, T = Sim.TECH, AUSSEN = Sim.AUSSEN;
  const erwGrenze = (S) => S.tag - R.ERWACHSEN * R.JAHR;
  const kostenHeute = (tag) => { const k = R.AUTO_KOSTEN - (R.CO2_ABGABE_WEG ? R.AUTO_CO2_SPRIT + R.AUTO_CO2_STEUER : 0); return Math.floor((tag + 1) * k / 100) - Math.floor(tag * k / 100); };
  const co2Tag = R.CO2_ABGABE_WEG ? R.AUTO_CO2_SPRIT + R.AUTO_CO2_STEUER : 0;
  // Kopie mit Messpunkten (liest nur mit): jeder Autokauf (Geld vorher, freie Autos der Werke) und jede Nacht der Autos (Summen vorher)
  const { Sim: M, ctx: mc } = ladeSimMit([
    ['function autoKauf(S, p, werke) {\n', 'function autoKauf(S, p, werke) {\n  const __g0 = S.p.geld[p], __frei = werke.filter(w => S.g.gebaut[w] > S.g.verkauft[w]);\n'
      + '  __autoKauf(S, p, werke);\n  if (globalThis.__kauf && S.p.auto[p]) globalThis.__kauf(S, p, __g0, __frei, werke);\n}\nfunction __autoKauf(S, p, werke) {\n'],
    ['function autosTag(S) {\n', 'function autosTag(S) {\n  const __k0 = S.stat.auto.kosten, __c0 = S.stat.regierung.co2;\n  __autosTag(S);\n  if (globalThis.__nacht) globalThis.__nacht(S, __k0, __c0);\n}\nfunction __autosTag(S) {\n'],
    ['G.StadtSim = {', 'G.StadtSim = { __offen: offen, __istBetrieb: istBetrieb,'],
  ]);

  // 1. Statisch
  {
    const roh = SIM_CODE, a = roh.indexOf('// ─── Tech-Firmen wachsen, Autowerke, Autos der Bewohner (Version 8)'), e = roh.indexOf('// Ende Autos');
    const teil = roh.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const fremd = teil.match(/\b(zufall|zInt|zufallSich)\s*\(/g) || [];
    pruef(a > 0 && e > a && !fremd.length && /zufallAuto\(S\)/.test(teil), `Abschnitt „Autos“ (${teil.split('\n').length} Zeilen): Zufall nur aus dem eigenen Strom (zufallAuto), sonst ${fremd.length}`);
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const koerper = (f) => {
      const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return null;
      let t = 0, j = code.indexOf('{', i);
      for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; }
      return code.slice(i, j + 1); };
    const ohneBuch = (k) => {                                 // Zeilen des Stadtbuchs (buch(S, …)) herausnehmen: dort stehen Namen und Pronomen
      let out = '', i = 0;
      for (;;) {
        const j = k.indexOf('buch(S,', i); if (j < 0) { out += k.slice(i); break; }
        out += k.slice(i, j);
        let t = 0, m = j + 4;
        for (; m < k.length; m++) { if (k[m] === '(') t++; else if (k[m] === ')' && --t === 0) break; }
        i = m + 1;
      }
      return out; };
    const felder = (k) => [...new Set([...k.matchAll(/\b(?:S\.)?P\.(\w+)|\bS\.p\.(\w+)/g)].map(m => m[1] || m[2]))].sort();
    // Je Regel, die über Menschen entscheidet: welche Personenfelder sie lesen darf. Nie: Namen, Geschlecht, Einzugstag, Eltern, Gedächtnis, Heimatliebe
    const ERLAUBT = {
      autoKauf: ['auto', 'autoBis', 'autoFarbe', 'autoMarke', 'autoMinus', 'autoModell', 'autoTag', 'autoVersion', 'bFreizeit', 'besitz', 'geld', 'haftBis', 'spar', 'ziel'],
      autoBedarf: ['wohnung'], arbeitsweg: ['arbeit', 'gemein', 'wohnung'], hhHatAuto: ['auto', 'hh', 'wohnung'],
      autosTag: ['auto', 'autoBis', 'geb', 'gemein', 'geld', 'haftBis', 'lebt'], autoGeldnot: ['auto', 'autoMinus', 'geld', 'lebt'], autoRestwert: ['autoBis', 'autoTag'],
      autoErbe: ['auto', 'autoBis', 'autoFarbe', 'autoMarke', 'autoMinus', 'autoModell', 'autoTag', 'autoVersion', 'lebt', 'partner'],
      autoWegMin: ['spar'], mitAuto: ['auto', 'haftBis'], pendeltMitAuto: ['wohnung'], arbeitsOrtHeute: ['arbeit', 'einsatz', 'frei', 'haftBis'],
      // Version 9 (Schule): ortZurStunde liest dazu das Alter (Kind oder erwachsen, dieselbe Grenze wie stunde()) und den Schulplatz (am 18. Geburtstag
      // noch Schulkind); wo ein Kind ist, sagt kindOrt: Schule zur Unterrichtszeit, sonst die Wohnung, in Obhut die der Angehörigen, beim Jugendamt nirgends
      ortZurStunde: ['arbeit', 'besuch', 'einsatz', 'frei', 'geb', 'haftBis', 'schule', 'stammladen', 'wohnung'], autoOrt: ['auto', 'wohnung'], testfahrer: [],
      kindOrt: [], schulOrt: ['schule'], kindWohnung: ['gen', 'lebt', 'obhut', 'obhutBei', 'obhutGen', 'wohnung'],
      autoWillig: ['ehrgeiz'], wachsZiel: [], werkKapital: ['geld'], werkAuftrag: ['geld'], umzugInsWerk: ['arbeit', 'besitz'], autosBauen: [],
      techGrenzeHalten: [], anbauAuftraege: [], anbauWillig: [], techPlaetzeVon: [], leeresWerk: [], werkeZahl: [],
      autoFaehrt: [], autoFaehrtJetzt: ['auto'], autoFahrtWohin: ['besuch', 'wohnung'], mischSchritt: [], mischStart: [], testStundenRest: [],
    };
    const zuViel = [];
    for (const [f, ok] of Object.entries(ERLAUBT)) {
      const k0 = koerper(f);
      if (!k0) { zuViel.push(f + ': fehlt'); continue; }
      const k = ohneBuch(k0);
      for (const x of felder(k)) if (!ok.includes(x)) zuViel.push(`${f}: P.${x}`);
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo)\s*\(/.test(k)) zuViel.push(`${f}: Name`);
    }
    pruef(!zuViel.length, `Regeln lesen nur ihre Personenfelder (${Object.keys(ERLAUBT).length} Funktionen), keine Namen, kein Geschlecht (Stadtbuch-Zeilen ausgenommen)` + (zuViel.length ? ': ' + zuViel.join(', ') : ''));
    // Reihenfolge der Käufer: jeden Tag gemischt (mischSchritt), nicht nach Personennummer; die Mischung trifft jede Nummer genau einmal
    const at = koerper('autosTag') || '';
    let perm = true;
    for (const n of [1, 2, 3, 97, 1000, 1024, 2310, 4096, 30030]) for (const t of [0, 1, 17, 365, 729, 5000]) {
      const a = Sim.mischSchritt(n, t), b = Sim.mischStart(n, t), seen = new Uint8Array(n);
      for (let i = 0; i < n; i++) seen[(a * i + b) % n]++;
      if (!seen.every(x => x === 1)) perm = false;
    }
    let nachbar = 0, paare = 0;                              // benachbarte Nummern stehen in der Reihe selten nebeneinander
    for (let t = 0; t < 200; t++) { const n = 1200, a = Sim.mischSchritt(n, t); paare++; if (a === 1 || a === n - 1) nachbar++; }
    pruef(/mischSchritt\(n, S\.tag\)/.test(at) && /\(schritt \* i \+ start\) % n/.test(at) && perm && nachbar <= 4,
      `Reihenfolge der Käufer je Tag gemischt (mischSchritt, jede Nummer genau einmal: ${perm}; an ${nachbar} von ${paare} Tagen reine Rotation)`);
    const weib = koerper('autoKaufZeile');
    pruef(!!weib && [...new Set(felder(weib))].every(x => x === 'weib' || x === 'autoModell'), 'Geschlecht nur fürs Pronomen in der Zeile zum ersten Auto (autoKaufZeile)');
    // Namenstausch: andere Namen (Listen umgedreht), sonst gleich: die Stadt läuft bitgleich (auch Autos, Werke, Zufall der Autos)
    const { Sim: N } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(2), B = N.neueStadt(2);
    while (A.tag < 450) Sim.stunde(A); while (B.tag < 450) N.stunde(B);
    const spur = (S) => { const h = createHash('sha256'); for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n])) { const a = S.p[n], w = a.length / S.pKap; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) if (ArrayBuffer.isView(S.g[n])) { const a = S.g[n]; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      h.update(JSON.stringify(S.stat)); h.update(String(S.rs) + '/' + S.rsSich + '/' + S.rsAuto + '/' + S.budget); h.update(S.buch.map(e => e.art).join()); return h.digest('hex').slice(0, 16); };
    const nA = Sim.name(A, 5), nB = N.name(B, 5), autos = Sim.autoKennzahlen(A).autos;
    pruef(nA !== nB && autos > 0 && spur(A) === spur(B), `Namenstausch (Seed 2, 450 Tage, ${autos} Autos): „${nA}“ heißt dort „${nB}“, die Stadt läuft trotzdem bitgleich (${spur(A)})`);
  }

  // 2. Invarianten
  const seeds = arg('seeds', '1,2,3').split(',').map(Number);
  const mess = [], rang = { eigen: [], aussen: [] };
  for (const seed of seeds) {
    const S = M.neueStadt(seed), g = S.g, fehl = {};
    const f = (k, n = 1) => { fehl[k] = (fehl[k] || 0) + n; };
    let naechte = 0, stunden = 0, fahrten = 0, spruenge = 0, stelleNah = 0, werkKarten = 0, testfahrten = 0, kaeufe = 0, aussenKaeufe = 0, ersterKauf = -1, erstesWerk = -1, umzuege = 0, eroeffnungen = 0, grenzeRuht = 0;
    let ausverkauftTage = 0, maxWerke = 0;
    const kaufHeute = [];
    mc.__kauf = (S, p, g0, frei, werke) => {
      kaeufe++; kaufHeute.push(p);
      if (ersterKauf < 0) ersterKauf = S.tag;
      if (g0 - R.AUTO_PREIS < R.AUTO_RESERVE || S.p.geld[p] !== g0 - R.AUTO_PREIS) f('Reserve oder Preis');
      const aussen = S.p.autoMarke[p] === AUSSEN;
      if (aussen) { aussenKaeufe++; if (frei.length) f('Umland gekauft, obwohl ein Werk der Stadt noch Autos hatte'); }
      else if (!frei.some(w => S.g.marke[w] === S.p.autoMarke[p])) f('Marke ohne freies Auto');
      const d = S.p.autoBis[p] - S.tag;
      if (d < Math.round(R.AUTO_ALT * 0.5) || d > Math.round(R.AUTO_ALT * 1.5)) f('Lebensdauer');
      if (werke.length) (aussen ? rang.aussen : rang.eigen).push(p / S.pMax);   // mit Werk: wer das eigene, wer eins von außen bekommt
    };
    mc.__nacht = (S, k0, c0) => {                            // laufende Kosten und CO₂ genau je zahlendem Auto
      const P = S.p, erw = erwGrenze(S);
      let zahlt = 0;
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.geb[p] <= erw && P.auto[p] && !P.haftBis[p] && P.autoTag[p] !== S.tag) zahlt++;
      // gerade gekauft zahlt erst morgen; geerbt: autoTag ist der Kauftag des Erblassers (nie heute)
      if (S.stat.auto.kosten - k0 !== zahlt * kostenHeute(S.tag)) f('laufende Kosten');
      if (S.stat.regierung.co2 - c0 !== zahlt * co2Tag) f('CO₂-Summe');
    };
    let vorher = null;                                       // Stand vor Mitternacht je Werk (Fertigung, Umzug) und je Tech-Firma (Eröffnung)
    const orte = new Int32Array(1 << 17).fill(-2), autoOrte = new Int32Array(1 << 17).fill(-2), gens = new Int32Array(1 << 17).fill(-1), wohnungen = new Int32Array(1 << 17).fill(-2);
    let umzugMitAuto = 0;
    while (S.tag < 730) {
      const H = S.stunde, P = S.p;
      // Grundregel (jede Stunde): das Auto ist dort, wo der Besitzer ist, oder an der Wohnung; es bewegt sich nur, wenn der Besitzer den Ort
      // wechselt und mitAuto ja sagt; dann stand es vorher beim Besitzer. mitAuto ist symmetrisch, pendeltMitAuto = mitAuto(Wohnung, Arbeitsort)
      if (S.tag >= 1) {
        stunden++;
        for (let p = 0; p < S.pMax; p++) {
          if (!P.lebt[p]) { orte[p] = -2; continue; }
          if (gens[p] !== P.gen[p]) { gens[p] = P.gen[p]; orte[p] = -2; autoOrte[p] = -2; }   // ein neuer Mensch auf demselben Platz
          const o = M.ortZurStunde(S, p, H), ao = M.autoOrt(S, p, H);
          if (P.auto[p]) {
            if (ao !== P.wohnung[p] && ao !== o) f('Auto weder beim Besitzer noch zu Hause');
            const o0 = orte[p], a0 = autoOrte[p], umzug = wohnungen[p] >= -1 && wohnungen[p] !== P.wohnung[p];
            if (umzug) { if (a0 >= 0 && a0 !== ao) umzugMitAuto++; }   // Umzug: das Auto zieht mit an die neue Wohnung (gezählt, Ausnahme)
            else {
              // Wechselt das Auto den Ort, fährt es nach Sim.autoFaehrt (Besitzer in der Vorstunde beim Auto, jetzt an dessen Ziel, mitAuto);
              // sonst springt es ohne Fahrt (neue Stelle mitten am Tag), gezählt. Unten (2b) dasselbe über mehr Seeds
              if (o0 >= -1 && a0 >= 0 && ao >= 0 && a0 !== ao) {
                if (M.autoFaehrt(S, p, a0, o0, H)) { fahrten++; if (a0 !== o0 || ao !== o || o0 === o || !M.mitAuto(S, p, o0, o)) f('Fahrt ohne den Weg des Besitzers'); }
                else { spruenge++; if (a0 === o0 && ao === o && M.mitAuto(S, p, a0, ao)) f('Sprung, obwohl der Besitzer fährt'); }
              }
              if (o0 >= 0 && a0 === o0 && M.mitAuto(S, p, o0, o) && ao !== o) {
                // Ausnahme wie beim Umzug: neue Stelle mitten am Tag, die zu nah an der Wohnung liegt, um hinzufahren (autoOrt ohne Zustand):
                // das Auto steht ab jetzt zu Hause (Sprung ohne Fahrt, gezählt), der Besitzer geht zu Fuß
                if (ao === P.wohnung[p] && !M.mitAuto(S, p, P.wohnung[p], o) && M.arbeitsOrtHeute(S, p) === o) stelleNah++;
                else f('Fahrt ohne Auto am Ziel');
              }
            }
            if (o >= 0 && P.wohnung[p] >= 0 && M.mitAuto(S, p, P.wohnung[p], o) !== M.mitAuto(S, p, o, P.wohnung[p])) f('mitAuto nicht symmetrisch');
            if (M.pendeltMitAuto(S, p) !== M.mitAuto(S, p, P.wohnung[p], M.arbeitsOrtHeute(S, p))) f('pendeltMitAuto');
          } else if (ao !== -1) f('autoOrt ohne Auto');
          orte[p] = o; autoOrte[p] = ao; wohnungen[p] = P.wohnung[p];
        }
        if (R.TEST_STUNDEN.includes(H)) {                     // Testfahrt: jemand aus der Belegschaft, heute da, in dieser Stunde im Werk
          const schon = new Set();
          for (let w = 0; w < S.gAnzahl; w++) {
            const t = M.testfahrtStunde(S, w, H);
            if (t < 0) { if (g.werk[w] && g.produkt[w] === Sim.AUTO && !g.leer[w] && S.feld[g.y[w] * S.karte + g.x[w]] === T && S.belegschaft[w].some(x => !P.frei[x] && !P.einsatz[x])) f('Werk ohne Testfahrt'); continue; }
            testfahrten++;
            if (!S.belegschaft[w].includes(t) || P.frei[t] || P.einsatz[t] || M.ortZurStunde(S, t, H) !== w || schon.has(t)) f('Testfahrer');
            schon.add(t);
          }
        } else for (let w = 0; w < S.gAnzahl; w++) if (g.werk[w] && M.testfahrtStunde(S, w, H) >= 0) f('Testfahrt außerhalb der Stunden');
      }
      if (S.stunde !== 23) { M.stunde(S); continue; }
      // vor Mitternacht merken
      vorher = { werke: new Map(), firmen: new Map(), umzuege: S.stat.auto.umzuege };
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== T) continue;
        if (g.werk[b] && g.produkt[b] === Sim.AUTO && g.version[b] && !g.leer[b]) vorher.werke.set(b, { rest: g.fertigRest[b], gesamt: g.autosGesamt[b], L: S.belegschaft[b].slice() });
        vorher.firmen.set(b, { offen: !g.leer[b] && g.besitzer[b] >= 0 && S.feld[g.y[b] * S.karte + g.x[b]] === T, besitzer: g.besitzer[b], marke: g.marke[b], umzug: g.umzug[b], L: S.belegschaft[b].slice() });
      }
      kaufHeute.length = 0;
      M.stunde(S);                                           // Mitternacht
      naechte++;
      const P2 = S.p;
      // Werke: höchstens AUTO_MAX in Betrieb oder im Bau; jedes auf seinem Gelände (9 Felder, feld TECH oder das Tor im Bau, kein Bauplatz)
      let werke = 0;
      for (let w = 0; w < S.gAnzahl; w++) {
        if (g.typ[w] !== T) continue;
        const st = g.stufe[w], sollSt = R.TECH_STELLEN[st] - g.ruht[w];
        if (M.stellen(S, w) !== sollSt) f('Stellen je Stufe');
        if (!g.werk[w]) { if (st < 1 || st > R.TECH_STUFE_MAX || g.produkt[w] === Sim.AUTO) f('Stufe einer Tech-Firma'); continue; }
        if (st < R.AUTO_AB_STUFE || st > R.WERK_STUFE_MAX) f('Stufe eines Werks');
        if (!g.leer[w]) werke++;
        if (erstesWerk < 0) erstesWerk = S.tag;
        const r = S.erweiterung.gelaende.find(q => q[4] === w);
        if (!r) { f('Werk ohne Gelände'); continue; }
        let zellen = 0;
        for (let y = r[1]; y <= r[3]; y++) for (let x = r[0]; x <= r[2]; x++) {
          const c = y * S.karte + x; zellen++;
          if (S.feldGeb[c] !== w || S.platz[c] || (S.feld[c] !== T && !(S.feld[c] === Sim.BAUSTELLE && x === g.x[w] && y === g.y[w]))) f('Gelände des Werks');
        }
        if (zellen !== 9) f('Gelände nicht 3 × 3');
      }
      if (werke > R.AUTO_MAX) f('mehr Werke als AUTO_MAX');
      maxWerke = Math.max(maxWerke, werke);
      // 40-%-Grenze nach jeder Nacht (ruhende Stellen zählen nicht)
      if (S.techPlaetze > R.TECH_ANTEIL * S.werkstattPlaetze + 1e-9) f('Tech-Anteil über 40 %');
      for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T && g.ruht[b]) { grenzeRuht++; break; }
      // Umzug ins Werk: altes Haus leer mit −(Werk + 1), Belegschaft und Besitz im Werk, Marke gleich, erstes Modell, Eröffnung am neuen Tag
      if (S.stat.auto.umzuege > vorher.umzuege) {
        for (let w = 0; w < S.gAnzahl; w++) {
          if (g.typ[w] !== T || !g.werk[w] || g.eroeffnetArt[w] !== Sim.ERST_WERK || g.eroeffnet[w] !== S.tag) continue;
          umzuege++;
          const alt = [...vorher.firmen.entries()].find(([b, v]) => g.umzug[b] === -(w + 1) && v.umzug >= 0 && v.besitzer === g.besitzer[w]);
          if (!alt) { f('Umzug: altes Haus'); continue; }
          const [b, v] = alt;
          if (!g.leer[b] || g.besitzer[b] >= 0 || S.belegschaft[b].length || g.marke[w] !== v.marke || g.version[w] !== 1 || g.produkt[w] !== Sim.AUTO
            || P2.besitz[g.besitzer[w]] !== w || !v.L.every(x => !P2.lebt[x] || P2.arbeit[x] === w || P2.arbeit[x] === -1)) f('Umzug: Werk');
        }
      }
      // Fertigung (Werke ohne Wechsel): gebaut × 1000 + Rest = Rest vorher + Anwesende × 575; verkauft ≤ gebaut; Teile = verkauft × AUTO_KISTEN
      for (const [w, v] of vorher.werke) {
        if (!g.werk[w] || g.produkt[w] !== Sim.AUTO || g.leer[w] || (g.eroeffnetArt[w] === Sim.ERST_WERK && g.eroeffnet[w] === S.tag)) continue;
        if (g.gebaut[w] * 1000 + g.fertigRest[w] !== v.rest + g.dran[w] * R.AUTO_PRO_ARBEITSTAG || g.autosGesamt[w] !== v.gesamt + g.gebaut[w]) f('Fertigung');
        if (g.verkauft[w] > g.gebaut[w]) f('mehr verkauft als gebaut');
        if (g.kistenStadt[w] + g.kistenAussen[w] !== g.verkauft[w] * R.AUTO_KISTEN) f('Teile je Auto');
        if (g.verkauft[w] === g.gebaut[w] && g.gebaut[w]) ausverkauftTage++;
      }
      // Autos: Verschrotten pünktlich, Geldnot, nur Erwachsene, gültige Marke
      const erw = erwGrenze(S);
      for (let p = 0; p < S.pMax; p++) {
        if (!P2.lebt[p] || !P2.auto[p]) continue;
        if (P2.autoBis[p] < S.tag) f('nicht verschrottet');
        if (P2.autoMinus[p] >= R.AUTO_MINUS_TAGE) f('Geldnot: Auto behalten');
        if (S.tag - P2.geb[p] < R.ERWACHSEN * R.JAHR) f('Kind mit Auto');
        if (P2.autoMarke[p] !== AUSSEN && P2.autoMarke[p] >= Sim.MARKEN.length) f('Marke');
      }
      // Eröffnung: jede Tech-Firma, die seit gestern mit neuem Besitz offen ist, hat ihren Abend (gestern bei Übernahme am Tag, heute bei Nacht)
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== T || g.leer[b] || g.besitzer[b] < 0 || S.feld[g.y[b] * S.karte + g.x[b]] !== T) continue;
        const v = vorher.firmen.get(b);
        if (v && v.offen && v.besitzer === g.besitzer[b]) continue;
        eroeffnungen++;
        if (!(g.eroeffnet[b] === S.tag || g.eroeffnet[b] === S.tag - 1) || !g.eroeffnetArt[b]) f('Eröffnung ohne Abend');
      }
    }
    // Werkskarten (Schlussprüfung Texte): „Hauptlieferant ist …“ statt „kamen von die …“, so viele Hallen wie im Bild (Stufe − 1)
    for (let w = 0; w < S.gAnzahl; w++) {
      if (g.typ[w] !== T || !g.werk[w] || g.leer[w] || g.besitzer[w] < 0) continue;
      const i = M.gebaeudeInfo(S, w), t = i.mehr.join(' ');
      if (/kamen von|von die |von der Bauhof/.test(t) || (g.kistenStadt[w] + g.kistenAussen[w] && g.lieferant[w] && !/Hauptlieferant ist /.test(t))) f('Werkskarte: Lieferant');
      if (!new RegExp('^' + (g.stufe[w] - 1) + ' Hallen, ').test(i.zeile)) f('Werkskarte: Hallen');
      werkKarten++;
    }
    const a = M.autoInfo(S);
    mess.push({ seed, autos: a.autos, dichte: a.pkwJe1000, hh: a.haushalteMitAuto, je100: a.autosJe100Haushalte, pendel: a.pendlerAnteil, st: S.stat.auto, stufen: a.techStufen, ersterKauf, erstesWerk });
    const fl = Object.entries(fehl).map(([k, n]) => `${k}: ${n}`);
    pruef(!fl.length, `Seed ${seed}: ${naechte} Nächte, ${stunden} Stunden: ${kaeufe} Käufe (${aussenKaeufe} aus dem Umland, der erste an Tag ${ersterKauf}), ${fahrten} Fahrten (${umzugMitAuto} Umzüge mit Auto, ${spruenge} Sprünge ohne Umzug, davon ${stelleNah} neue Stelle nah der Wohnung), ${testfahrten} Testfahrten, `
      + `${umzuege} Umzüge ins Werk, ${eroeffnungen} Eröffnungen, höchstens ${maxWerke} Werke (AUTO_MAX ${R.AUTO_MAX}), an ${grenzeRuht} Nächten ruhende Stellen, ${werkKarten} Werkskarten an Tag 730` + (fl.length ? ' — ' + fl.join(', ') : ''));
    pruef(ersterKauf >= 0 && (erstesWerk < 0 || ersterKauf < erstesWerk), `Seed ${seed}: Autos aus dem Umland ab Tag 0, das erste lange vor dem ersten Werk (Tag ${ersterKauf}, Werk ${erstesWerk < 0 ? 'keins' : 'ab Tag ' + erstesWerk})`);
  }
  mc.__kauf = null; mc.__nacht = null;
  // 2b. Grundregel so, wie die Darstellung sie anwendet (Befund der Schlussprüfung: Umzug um 8 Uhr, neue Stelle mitten am Tag): Je Person
  // merken, wo das Auto zuletzt stand (wie aOrt im Bild) und wo der Besitzer in der Vorstunde war. Wechselt das Auto den Ort, fährt es nur,
  // wenn Sim.autoFaehrt ja sagt, und dann muss der Besitzer in der Vorstunde beim Auto gewesen und jetzt an dessen Ziel sein (mitAuto). Sonst
  // ist es ein Sprung ohne Fahrt, auch in Umzugsstunden gezählt nach Grund. Dazu: Testfahrer fahren in der Teststunde nicht mit dem eigenen
  // Auto, und niemand fährt zwei Autos. Über mehr Seeds (--regelseeds), weil die Fälle selten sind
  {
    const rseeds = arg('regelseeds', '1,2,3,4,5,6,7,8,9,10,11,12').split(',').map(Number);
    const sum = { fahrten: 0, umzugFahrten: 0, spruenge: 0, umzug: 0, stelle: 0, sonst: 0, test: 0 };
    const fehl = {}, bsp = [];
    const f = (k, t) => { fehl[k] = (fehl[k] || 0) + 1; if (t && bsp.length < 6) bsp.push(t); };
    for (const seed of rseeds) {
      const S = M.neueStadt(seed), P = S.p;
      const aOrt = new Int32Array(1 << 17).fill(-2), vor = new Int32Array(1 << 17).fill(-2), wVor = new Int32Array(1 << 17).fill(-2), aVor = new Int32Array(1 << 17).fill(-2), gen = new Int32Array(1 << 17).fill(-1);
      while (S.tag < 730) {
        M.stunde(S);
        const H = S.stunde, faehrt = new Uint8Array(S.pMax);
        for (let p = 0; p < S.pMax; p++) {
          if (!P.lebt[p] || !P.auto[p]) { aOrt[p] = -2; vor[p] = -2; continue; }
          if (gen[p] !== P.gen[p]) { gen[p] = P.gen[p]; aOrt[p] = -2; }
          const ziel = M.autoOrt(S, p, H), o = M.ortZurStunde(S, p, H);
          if (aOrt[p] >= 0 && ziel !== aOrt[p]) {
            const umzug = wVor[p] !== P.wohnung[p];
            if (M.autoFaehrt(S, p, aOrt[p], vor[p], H)) {
              sum.fahrten++; faehrt[p] = 1; if (umzug) sum.umzugFahrten++;
              if (vor[p] !== aOrt[p]) f('Abfahrt ohne Besitzer', `Seed ${seed} Tag ${S.tag} ${H} Uhr p${p}: Auto ${aOrt[p]}→${ziel}, Besitzer ${vor[p]}→${o}`);
              if (o !== ziel) f('Ziel ohne Besitzer', `Seed ${seed} Tag ${S.tag} ${H} Uhr p${p}: Auto ${aOrt[p]}→${ziel}, Besitzer ${vor[p]}→${o}`);
              if (vor[p] === o) f('Fahrt ohne Ortswechsel');
              if (!M.mitAuto(S, p, aOrt[p], ziel)) f('Fahrt ohne mitAuto');
            } else {
              sum.spruenge++;
              if (umzug) sum.umzug++; else if (aVor[p] !== M.arbeitsOrtHeute(S, p)) sum.stelle++; else sum.sonst++;
              if (vor[p] === aOrt[p] && o === ziel && M.mitAuto(S, p, aOrt[p], ziel)) f('Sprung, obwohl der Besitzer fährt');
            }
          }
          aOrt[p] = ziel; vor[p] = o; wVor[p] = P.wohnung[p]; aVor[p] = M.arbeitsOrtHeute(S, p);
        }
        if (R.TEST_STUNDEN.includes(H)) {
          const schon = new Set();
          for (let w = 0; w < S.gAnzahl; w++) {
            const t = M.testfahrtStunde(S, w, H);
            if (t < 0) continue;
            sum.test++;
            if (faehrt[t]) f('Testfahrer fährt zugleich das eigene Auto');
            if (schon.has(t)) f('Testfahrer in zwei Werken'); schon.add(t);
            if (M.ortZurStunde(S, t, H) !== w) f('Testfahrer nicht im Werk');
          }
        }
      }
    }
    const fl = Object.entries(fehl).map(([k, n]) => `${k}: ${n}`);
    pruef(!fl.length && sum.fahrten > 10000 && sum.stelle + sum.umzug > 0,
      `Grundregel wie im Bild (Seeds ${rseeds.join(', ')}, je 730 Tage stündlich, Autoort und Ort des Besitzers aus der Vorstunde gemerkt): ${sum.fahrten} Fahrten, alle mit `
      + `Abfahrt und Ziel beim Besitzer (davon ${sum.umzugFahrten} in Umzugsstunden); ${sum.spruenge} Sprünge ohne Fahrt (${sum.umzug} Umzug, ${sum.stelle} neue Stelle `
      + `oder Baustelle mitten am Tag, ${sum.sonst} sonst); ${sum.test} Testfahrten ohne eigenes Auto` + (fl.length ? ' — ' + fl.join(', ') + '\n        ' + bsp.join('\n        ') : ''));
  }
  {
    // Faire Reihenfolge: wer an einem ausverkauften Tag das Auto aus dem Werk bekommt und wer eins von außen, darf nicht an der
    // Personennummer hängen (die hängt am Einzug). Im natürlichen Lauf sind ausverkaufte Tage selten (zu wenige Käufe von außen für
    // eine Aussage, dann nur gemessen); deshalb erzwungen: ab dem ersten Werk 150 Tage mit fünffacher Kaufchance und einem Viertel der
    // Fertigung: fast jeden Tag ausverkauft.
    const m = (L) => L.length ? L.reduce((x, y) => x + y, 0) / L.length : NaN;
    const de0 = m(rang.eigen), da0 = m(rang.aussen), genug = rang.eigen.length > 50 && rang.aussen.length > 50;
    const text0 = `Faire Reihenfolge (natürlich, Tage mit Werk): mittlere Personennummer (Anteil) aus dem Werk ${de0.toFixed(3)} (${rang.eigen.length}), aus dem Umland ${da0.toFixed(3)} (${rang.aussen.length})`;
    if (genug) pruef(Math.abs(de0 - da0) < 0.1, text0); else console.log('       ' + text0 + ' — zu wenige Käufe von außen, nur gemessen');
    // Seeds 2 und 4 (--reiheseeds): je ab dem ersten Werk mit Modell 150 Tage erzwungen
    for (const seedR of arg('reiheseeds', '2,4').split(',').map(Number)) {
      const S = M.neueStadt(seedR), r2 = { eigen: [], aussen: [] }, MR = M.R, alt = MR.AUTO_CHANCE, altF = MR.AUTO_PRO_ARBEITSTAG;
      let werkTage = 0;
      const mitModell = () => { for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === T && S.g.produkt[b] === Sim.AUTO && S.g.version[b] && !S.g.leer[b]) return true; return false; };
      while (S.tag < 700 && (S.stunde || !mitModell())) M.stunde(S);
      const tA = S.tag;
      mc.__kauf = (S, p, g0, frei, werke) => { if (werke.length) (S.p.autoMarke[p] === AUSSEN ? r2.aussen : r2.eigen).push(p / S.pMax); };
      MR.AUTO_CHANCE = alt * 5; MR.AUTO_PRO_ARBEITSTAG = Math.round(altF / 4);
      try { while (S.tag < tA + 150) { M.stunde(S); if (S.stunde === 0 && M.werkeZahl(S) > 0) werkTage++; } } finally { MR.AUTO_CHANCE = alt; MR.AUTO_PRO_ARBEITSTAG = altF; mc.__kauf = null; }
      const de = m(r2.eigen), da = m(r2.aussen), n = Math.min(r2.eigen.length, r2.aussen.length);
      const se = 0.2887 * Math.sqrt(1 / Math.max(1, r2.eigen.length) + 1 / Math.max(1, r2.aussen.length));   // Standardfehler der Differenz (gleichverteilt)
      pruef(n > 200 && Math.abs(de - da) < Math.min(0.08, 3.5 * se),
        `Faire Reihenfolge (erzwungen ausverkauft, Seed ${seedR}, Tag ${tA}–${tA + 150}, ${werkTage} Tage mit Werk): mittlere Personennummer (Anteil) aus dem Werk ${de.toFixed(3)} (${r2.eigen.length}), `
        + `aus dem Umland ${da.toFixed(3)} (${r2.aussen.length}), erlaubt ±${Math.min(0.08, 3.5 * se).toFixed(3)}`);
    }
  }

  // 3. Erzwungen
  {
    const S = Sim.neueStadt(2), g = S.g, X = Sim._auto;
    const offenesWerk = () => { for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T && g.werk[b] && !g.leer[b] && S.feld[g.y[b] * S.karte + g.x[b]] === T) return b; return -1; };
    while (S.tag < 560 || (S.tag < 729 && offenesWerk() < 0)) Sim.stunde(S);
    const P = S.p;
    // Erbe: jemand mit Auto und Partner ohne Auto stirbt
    let q = -1;
    for (let p = 0; p < S.pMax && q < 0; p++) { const pa = P.partner[p]; if (P.lebt[p] && P.auto[p] && pa >= 0 && P.lebt[pa] && !P.auto[pa] && S.tag - P.geb[pa] >= R.ERWACHSEN * R.JAHR) q = p; }
    if (q >= 0) {
      const pa = P.partner[q], name = Sim.autoName(S, q), bis = P.autoBis[q];
      X.sterben(S, q);
      pruef(P.auto[pa] === 1 && Sim.autoName(S, pa) === name && P.autoBis[pa] === bis && !P.lebt[q], `Erbe: ${Sim.name(S, pa)} erbt den ${name} (verschrottet an Tag ${bis})`);
    } else pruef(false, 'Erbe: kein Fall gefunden');
    // Geldnot: 5 Nächte im Minus, dann verkauft; Restwert von außen
    let p = -1;
    for (let x = 0; x < S.pMax && p < 0; x++) if (P.lebt[x] && P.auto[x] && !P.haftBis[x] && P.autoBis[x] > S.tag + 20) p = x;
    const wert = X.autoRestwert(S, p);
    for (let n = 0; n < R.AUTO_MINUS_TAGE && P.auto[p]; n++) { P.geld[p] = -500; X.autoGeldnot(S); }
    pruef(!P.auto[p] && P.geld[p] === -500 + wert && wert > 0, `Geldnot: nach ${R.AUTO_MINUS_TAGE} Nächten im Minus verkauft, ${wert} Taler Restwert von außen`);
    // Haft: ein Auto in Haft kostet nichts
    let h = -1;
    for (let x = 0; x < S.pMax && h < 0; x++) if (P.lebt[x] && P.auto[x] && !P.haftBis[x] && P.besitz[x] < 0 && P.autoBis[x] > S.tag + 20) h = x;
    Sim._sich.haftAntritt(S, h, 5, Sim.HAFT_STRAF);
    const k0 = S.stat.auto.kosten, g0 = P.geld[h];
    const orte = [7, 8, 12, 20].map(H => Sim.autoOrt(S, h, H));
    X.autosTag(S);
    pruef(P.geld[h] === g0 && orte.every(o => o === P.wohnung[h]) && !Sim.mitAuto(S, h, P.wohnung[h], 0), `Haft: das Auto ruht an der Wohnung, ohne Kosten und ohne Fahrt`);
    void k0;
    // AUTO_MAX bei Übernahme: ein leeres Werk übernimmt niemand, solange AUTO_MAX Werke laufen (Gründung und Umzug)
    let w = -1;
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T && g.werk[b] && !g.leer[b] && S.feld[g.y[b] * S.karte + g.x[b]] === T) { w = b; break; }
    if (w >= 0) {
      X.schliessen(S, w, false);
      const alt = R.AUTO_MAX, n = Sim.werkeZahl(S);
      let t = -1;                                           // jemand mit viel Geld (eine Tech-Gründung)
      for (let x = 0; x < S.pMax && t < 0; x++) if (P.lebt[x] && P.besitz[x] < 0 && !P.haftBis[x] && S.tag - P.geb[x] >= 25 * R.JAHR) t = x;
      P.geld[t] = 60000;
      let fb = -1;                                          // eine große Handy- oder Computerfirma mit ehrgeizigem Besitz
      for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T && !g.werk[b] && !g.leer[b] && g.besitzer[b] >= 0 && g.stufe[b] >= 3 && (g.produkt[b] === Sim.HANDY || g.produkt[b] === Sim.COMPUTER)) { fb = b; break; }
      if (fb >= 0) P.ehrgeiz[g.besitzer[fb]] = 95;
      const grenze = S.techPlaetze, platz = S.werkstattPlaetze, welt = R.WELT;
      S.techPlaetze = 0;                                    // die 40-%-Grenze soll hier nicht entscheiden
      R.WELT = 1e9;                                         // der Markt (Umland oder Welt, Teil 5) auch nicht: Seit der Schlussprüfung (Zuzug genau nach R10)
                                                            // läuft Seed 2 anders, und an diesem Tag nahm weder Umland noch Welt Stellen ab
      R.AUTO_MAX = n;
      const zu = [X.uebernehmbar(S, t, w, T), fb >= 0 ? X.wachsZiel(S, fb) : -1];
      R.AUTO_MAX = n + 1;
      const auf = [X.uebernehmbar(S, t, w, T), fb >= 0 ? X.wachsZiel(S, fb) : -1];
      R.AUTO_MAX = alt; S.techPlaetze = grenze; S.werkstattPlaetze = platz; R.WELT = welt;
      pruef(!zu[0] && zu[1] !== 9 && auf[0] && (fb < 0 || auf[1] === 9), `AUTO_MAX bei Übernahme: Mit ${n} laufenden Werken und AUTO_MAX = ${n} nimmt weder eine Gründung (${zu[0]}) noch eine Firma`
        + ` das leere Werk (Ziel ${zu[1]}); mit einem Platz mehr ginge beides (${auf[0]}, Ziel ${auf[1]})`);
    } else pruef(false, 'AUTO_MAX bei Übernahme: kein offenes Werk bis Tag 729 (Seed 2)');
  }

  // 3b. Ruhende Stellen erzwungen (40-%-Grenze nach dem Auftrag, techGrenzeHalten): Seed 2 ab Tag 400 für 60 Tage mit einer Grenze von 70 %
  // des Anteils, den die Stadt dann hat (TECH_ANTEIL gesenkt, damit sie greift). Nach
  // jeder Nacht höchstens die Grenze, offeneStellen und freieStellen stimmen, niemand wird tagsüber in eine ruhende Stelle eingestellt;
  // danach wieder 40 %: nach 10 Tagen ruht keine Stelle mehr. Speichern mit ruhenden Stellen, 20 Tage weiter bitgleich
  {
    const MR = M.R, alt = MR.TECH_ANTEIL, S = M.neueStadt(2), g = S.g, fehl = {};
    const f = (k) => { fehl[k] = (fehl[k] || 0) + 1; };
    const ruhend = () => { let n = 0; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T) n += g.ruht[b]; return n; };
    while (S.tag < 400) M.stunde(S);
    const LIM = Math.round(700 * S.techPlaetze / S.werkstattPlaetze) / 1000;
    let maxRuht = 0, maxAnt = 0, naechte = 0, gespeichert = null, ruht2 = -1, bit = '–';
    try {
      MR.TECH_ANTEIL = LIM;
      while (S.tag < 460) {
        const vorher = new Map();
        for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === T && g.ruht[b]) vorher.set(b, S.belegschaft[b].length);
        const nacht = S.stunde === 23;
        M.stunde(S);
        for (const [b, n] of vorher) { const m = S.belegschaft[b].length; if (m > n && m > M.stellen(S, b)) f('in eine ruhende Stelle eingestellt'); }
        if (!nacht) continue;
        naechte++;
        const r = ruhend(); maxRuht = Math.max(maxRuht, r); maxAnt = Math.max(maxAnt, S.techPlaetze / S.werkstattPlaetze);
        if (S.techPlaetze > MR.TECH_ANTEIL * S.werkstattPlaetze + 1e-9) f('über der Grenze');
        let frei = 0;
        for (let b = 0; b < S.gAnzahl; b++) {
          if (!M.__istBetrieb(g.typ[b]) || !M.__offen(S, b)) continue;
          frei += Math.max(0, g.offeneStellen[b]);
          if (g.typ[b] === T && g.offeneStellen[b] !== M.stellen(S, b) - S.belegschaft[b].length) f('offeneStellen');
        }
        if (frei !== S.freieStellen) f('freieStellen');
        if (!gespeichert && r > 0 && S.tag >= 420) gespeichert = { text: speichernAlsText(M, S), tag: S.tag };
      }
      if (gespeichert) {                                     // weiter mit 10 %: geladen gegen durchgehend
        const A = ladenAusText(M, gespeichert.text), D = M.neueStadt(2);
        MR.TECH_ANTEIL = alt; while (D.tag < 400) M.stunde(D);
        MR.TECH_ANTEIL = LIM; while (D.tag < gespeichert.tag) M.stunde(D);
        const z = gespeichert.tag + 20;
        while (A.tag < z) M.stunde(A); while (D.tag < z) M.stunde(D);
        bit = fingerabdruck(M, A) === fingerabdruck(M, D) ? 'bitgleich' : `anders (${fingerabdruck(M, A)} / ${fingerabdruck(M, D)})`;
      }
      MR.TECH_ANTEIL = alt;
      while (S.tag < 470) M.stunde(S);
      ruht2 = ruhend();
    } finally { MR.TECH_ANTEIL = alt; }
    const fl = Object.entries(fehl).map(([k, n]) => `${k}: ${n}`);
    pruef(!fl.length && maxRuht > 0 && maxAnt <= LIM + 1e-9 && ruht2 === 0 && bit === 'bitgleich',
      `Ruhende Stellen erzwungen (Seed 2, Tag 400–460 mit ${(LIM * 100).toFixed(1)} % statt 40 %): bis ${maxRuht} ruhend, Anteil höchstens ${(maxAnt * 100).toFixed(1)} % in ${naechte} Nächten, `
      + `offene und freie Stellen stimmen, niemand in einer ruhenden Stelle; 10 Tage nach der Rückkehr auf 40 % ruhen ${ruht2}; Speichern mit ruhenden Stellen, `
      + `20 Tage weiter: ${bit}` + (fl.length ? ' — ' + fl.join(', ') : ''));
  }

  // 4. Speichern mitten im Werksbau und über den Umzug hinweg; beschädigte Stände
  {
    const S = Sim.neueStadt(2);
    const imBau = (S) => { for (let b = 0; b < S.gAnzahl; b++) if (S.g.werk[b] && S.g.werkVon[b]) return b; return -1; };
    while (S.tag < 729 && (imBau(S) < 0 || S.stunde !== 13)) Sim.stunde(S);
    const w = imBau(S);
    const B = ladenAusText(Sim, speichernAlsText(Sim, S));
    const gleich0 = fingerabdruck(Sim, S) === fingerabdruck(Sim, B);
    for (let i = 0; i < 24 * 60; i++) { Sim.stunde(S); Sim.stunde(B); }
    const umgezogen = w >= 0 && S.g.produkt[w] === Sim.AUTO && !S.g.werkVon[w];
    pruef(w >= 0 && gleich0 && umgezogen && fingerabdruck(Sim, S) === fingerabdruck(Sim, B),
      `Speichern mitten im Werksbau (Seed 2, Tag ${S.tag - 60}, 13 Uhr, Werk ${w}, ${Sim.autoKennzahlen(S).autos} Autos): direkt gleich, 60 Tage weiter über den Umzug hinweg bitgleich`);
    const text = speichernAlsText(Sim, S);
    const kaputt = (name, aendern) => { const d = JSON.parse(text); aendern(d); try { ladenAusText(Sim, JSON.stringify(d)); return false; } catch (e) { return /beschädigt|unvollständig/.test(e.message); } };
    const arr = (d, n) => d.arrays.find(a => a.name === n);
    const setze = (d, n, i, v) => { const a = arr(d, n), T = { Uint8Array, Uint16Array, Int32Array, Uint32Array }[a.typ], u = Buffer.from(a.b64, 'base64'), x = new T(u.buffer.slice(u.byteOffset, u.byteOffset + u.byteLength)); x[i] = v; a.b64 = Buffer.from(x.buffer).toString('base64'); };
    const mitAuto = (() => { for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.auto[p]) return p; return -1; })();
    const faelle = [
      ['Summe fehlt', (d) => { delete d.json.stat.auto.kosten; }],
      ['Summe NaN', (d) => { d.json.stat.auto.gebaut = null; }],
      ['Zufall der Autos fehlt', (d) => { delete d.werte.rsAuto; }],
      ['CO₂ fehlt', (d) => { delete d.json.stat.regierung.co2; }],
      ['Feld p.auto fehlt', (d) => { d.arrays = d.arrays.filter(a => a.name !== 'p.auto'); }],
      ['Feld g.werk fehlt', (d) => { d.arrays = d.arrays.filter(a => a.name !== 'g.werk'); }],
      ['Marke außerhalb der Liste', (d) => setze(d, 'p.autoMarke', mitAuto, 200)],
      ['Modell außerhalb der Liste', (d) => setze(d, 'p.autoModell', mitAuto, 99)],
      ['Werk ohne Gelände', (d) => { const b = (() => { for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === T && !S.g.werk[b]) return b; })(); setze(d, 'g.werk', b, 1); }],
      ['Art der Eröffnung', (d) => setze(d, 'g.eroeffnetArt', 0, 9)],
      ['Werk mit g.werk = 2', (d) => { const b = (() => { for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === T && S.g.werk[b]) return b; })(); setze(d, 'g.werk', b, 2); }],
    ];
    const falsch = faelle.filter(([, a]) => !kaputt('', a)).map(([n]) => n);
    pruef(!falsch.length, `Beschädigte Stände abgelehnt (${faelle.length} Fälle)` + (falsch.length ? ': nicht erkannt: ' + falsch.join(', ') : ''));
  }

  // 5. Messung (nur gemessen)
  for (const x of mess) {
    const s = x.st, gebaut = s.gebaut;
    console.log(`       Seed ${x.seed} an Tag 730: ${x.autos} Autos, ${x.dichte} je 1.000 Einwohner, ${(x.hh * 100).toFixed(1)} % der Haushalte, ${x.je100} je 100 Haushalte, `
      + `${(x.pendel * 100).toFixed(1)} % der Arbeitstage mit dem Auto; Werke bestellt ${s.werke}, übernommen ${s.werkUebernahmen + s.uebernommen}, Umzüge ${s.umzuege}; `
      + `gebaut ${gebaut}, davon ans Umland ${gebaut ? (s.export / gebaut * 100).toFixed(0) : '-'} %; aus dem Umland gekauft ${s.aussen}; Stufen ${x.stufen.join('/')}`);
  }
  console.log('       Vergleich: Destatis (22. 7. 2026) 593 Pkw je 1.000 Einwohner; Destatis (LWR 2024) 77,9 % der Haushalte, 111,5 je 100 Haushalte; Pendeln 2024: 65 % mit dem Auto; VDA 2025: 76 % Export');
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Auto-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('rathaus')) {
  // Rathaus (Version 9). A statisch; B neue Städte, Prüfung nach jeder Nacht (Seeds 1–3, 730 Tage): ein Rathaus an der Mitte, Ausbau zur Stufe,
  // Stellen, Belegschaft, Lohn, Kosten mit Gegenrechnung der Löhne, Haushalt-Schnittstelle, Stadtbuch ohne Namen; C Speichern und Laden mitten
  // im Ausbau; D Übernahme älterer Stände (Version 8 = stadt.orig.html, Version 7 aus git ffa1d88, Version 6 aus git bc7247a): nichts außer
  // Brache und höchstens einem Park wird genommen; E Park weicht dem Rathaus (erzwungen); F beschädigte Stände; G Namenstausch; H mit
  // R.RATHAUS = 0 Tag für Tag wie Version 8 (stadt.orig.html)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, RATHAUS = Sim.RATHAUS;
  const simCode = (h) => h.match(/<script id="sim">([\s\S]*?)<\/script>/)[1];
  const lade = (code) => { const ctx = vm.createContext({}); vm.runInContext(`Math.random = () => { throw new Error('Math.random'); };`, ctx); vm.runInContext(code, ctx); return ctx.StadtSim; };
  const speichern = (X, S) => speichernAlsText(X, S);
  const roh = (text) => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64');
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
  const laden = (X, text, migrieren) => X.importZustand(roh(text), migrieren);
  const abdruck = (X, S) => { const h = createHash('sha256'), d = X.exportZustand(S);
    for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
    h.update(JSON.stringify(d.werte)); h.update(JSON.stringify(d.json)); return h.digest('hex').slice(0, 16); };
  const bis = (X, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) X.stunde(S); };
  const klemme = (v, a, b) => (v < a ? a : v > b ? b : v);
  // Kopie mit Messpunkt: Belegschaft und Lohn des Rathauses unmittelbar vor wirtschaft() (für die Gegenrechnung der Löhne)
  const { Sim: M, ctx: mc } = ladeSimMit([['function wirtschaft(S) {\n', 'function wirtschaft(S) {\n  if (globalThis.__vorWirtschaft) globalThis.__vorWirtschaft(S);\n']]);

  console.log('A Statisch (Abschnitt „Rathaus“ im sim-Block)');
  {
    const a = SIM_CODE.indexOf('// ─── Rathaus (Version 9)'), e = SIM_CODE.indexOf('// Ende Rathaus');
    const teil = SIM_CODE.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    pruef(a > 0 && e > a && !/\b(zufall|zInt|zufallSich|zufallAuto)\s*\(/.test(teil), 'Abschnitt gefunden, kein Zufall');
    const felder = new Set([...teil.matchAll(/\b(?:P|S\.p)\.(\w+)/g)].map(m => m[1]));
    pruef([...felder].every(f => f === 'frei'), `Personenfelder nur zur Anzeige: ${[...felder].join(', ') || 'keine'} (erlaubt: frei)`);
    const koerper = (n) => { const i = teil.indexOf('function ' + n + '('); const t = teil.slice(i); const j = t.indexOf('\nfunction ', 10); return j > 0 ? t.slice(0, j) : t; };
    const regeln = ['rathausStellen', 'rathausStart', 'rathausSuchen', 'parkIn', 'rathausNeu', 'rathausTag', 'rathausNacht', 'haushaltKurz', 'migriereRathaus', 'rathausBezahlen'];
    const lesen = regeln.filter(n => /\bname\(|vorname\(|\bnr\(|\bref\(|belegschaft\[b\]\.(?!length)|\.weib|\.geb\b|\.einzug|\.eltern/.test(koerper(n)));
    pruef(!lesen.length, `Regeln lesen keine Namen, kein Geschlecht, kein Alter, keinen Einzugstag, keine Eltern, keine einzelnen Personen (${lesen.join(', ') || 'keine Treffer'})`);
    const geld = [...teil.matchAll(/S\.budget\s*[-+]?=/g)].length;
    pruef(geld === 1 && /function rathausBezahlen\(S, k\) \{ S\.budget -= k;/.test(teil), `Budget ändert der Abschnitt nur in rathausBezahlen (${geld} Stelle; dort bucht der Haushalt)`);
  }

  const seeds = arg('seeds', '1,2,3').split(',').map(Number), tage = Number(arg('tage', '730'));
  console.log(`B Neue Städte (Seeds ${seeds.join(', ')}, je ${tage} Tage stündlich), Prüfung nach jeder Nacht`);
  for (const seed of seeds) {
    const S = M.neueStadt(seed), mi0 = S.mitte;
    const z0 = S.buch.filter(e => e.art === 'rathaus');
    const b = S.rathaus.b, r0 = S.erweiterung.gelaende.find(r => r[4] === b);
    pruef(b === 4 && S.g.typ[b] === RATHAUS && r0 && r0[0] === mi0 - 3 && r0[1] === mi0 - 3 && r0[2] === mi0 + 3 && r0[3] === mi0 - 1
      && S.g.x[b] === mi0 && S.g.y[b] === mi0 - 1 && S.feld[mi0 * S.karte + mi0] === Sim.STRASSE && z0.length === 1 && S.g.stufe[b] === 1,
      `Seed ${seed}, Tag 0: Rathaus (Gebäude ${b}) auf 7 × 3 Feldern nördlich der Hauptstraße, Tor an der Mitte, ${S.rathaus.stellen} Stelle(n) der Verwaltung, Zeile „${M.klartext(z0[0] ? z0[0].text : '').slice(0, 60)}…“`);
    let probleme = [], minBudget = Infinity, ausbauTage = [], stufeVor = S.erweiterung.stufe, stufeTag = [], lohnMin = 999, lohnMax = 0, maxUeber = 0;
    let belegtVor = S.belegschaft[b].length, budgetVor = S.budget, plaetzeVor = M.stellen(S, b), buchNr = S.buchNr, neueZeilen = 0, lohnSoll = 0, lohnIst0 = S.stat.rathaus.lohn, gegen = 0, gegenTage = 0;
    mc.__vorWirtschaft = (X) => {                               // Gegenrechnung: wer heute da war (nicht frei), bekommt den Lohn des Rathauses (Budget reicht)
      const L = X.belegschaft[b]; let n = 0;
      for (const w of L) if (!X.p.frei[w] && !X.p.gemein[w]) n++;
      lohnSoll = X.budget > 20000 ? n * X.g.lohn[b] : NaN;          // bei knappem Budget kürzt wirtschaft() (Math.min), dann nicht nachrechnen
      lohnIst0 = X.stat.rathaus.lohn;
    };
    for (let d = 1; d <= tage; d++) {
      bis(M, S, d);
      const g = S.g, mi = S.mitte, K = S.karte, Ra = S.rathaus, st = g.stufe[b], L = S.belegschaft[b], plaetze = M.stellen(S, b);
      const p = (ok, was) => { if (!ok && probleme.length < 8) probleme.push(`Tag ${S.tag}: ${was}`); };
      if (!Number.isNaN(lohnSoll)) { gegenTage++; if (S.stat.rathaus.lohn - lohnIst0 === lohnSoll) gegen++; else p(false, `Löhne ${S.stat.rathaus.lohn - lohnIst0} statt ${lohnSoll}`); }
      p(Ra.b === b && g.typ[b] === RATHAUS, 'Rathaus-Nummer');
      let n = 0; for (let x = 0; x < S.gAnzahl; x++) if (g.typ[x] === RATHAUS) n++;
      p(n === 1, `${n} Rathäuser`);
      const r = S.erweiterung.gelaende.find(q => q[4] === b);
      p(r && r[0] - mi === -3 && r[1] - mi === -3 && r[2] - mi === 3 && r[3] - mi === -1, 'Gelände an der Mitte');
      if (r) for (let y = r[1]; y <= r[3]; y++) for (let x = r[0]; x <= r[2]; x++) p(S.feldGeb[y * K + x] === b && (S.feld[y * K + x] === RATHAUS || S.feld[y * K + x] === Sim.BAUSTELLE), 'Feld des Geländes');
      p(st >= 1 && st <= S.erweiterung.stufe + 1, `Ausbaustufe ${st} bei Stufe ${S.erweiterung.stufe}`);
      if (g.auf[b]) p(g.auf[b] === st + 1 && S.baustellen.includes(b), 'Ausbau läuft als Baustelle');
      p(Ra.stellen === klemme(Math.round(S.einwohner * R.VERWALTUNG_DICHTE), R.RATHAUS_MIN[st], R.RATHAUS_MAX[st]) || Math.abs(Ra.stellen - klemme(Math.round(S.einwohner * R.VERWALTUNG_DICHTE), R.RATHAUS_MIN[st], R.RATHAUS_MAX[st])) <= 1,
        `Stellen ${Ra.stellen} bei ${S.einwohner} Einwohnern, Stufe ${st}`);
      p(plaetze === Ra.stellen + (S.buergermeister.p >= 0 ? 1 : 0), `Plätze ${plaetze} = Verwaltung ${Ra.stellen} + Bürgermeisteramt`);
      p(L.every(x => S.p.lebt[x] && S.p.arbeit[x] === b && !S.p.haftBis[x] && S.tag - S.p.geb[x] >= R.ERWACHSEN * R.JAHR && !S.p.gemein[x] && !S.p.bund[x]), 'Belegschaft (lebt, erwachsen, nicht in Haft, keine gemeinnützige Arbeit, kein Dienst)');
      if (L.length > plaetze) maxUeber = Math.max(maxUeber, L.length - plaetze);
      p(L.length <= Math.max(plaetzeVor, belegtVor, plaetze), `${L.length} Leute bei ${plaetzeVor} Plätzen am Tag und ${plaetze} ab heute Nacht (vorher ${belegtVor})`);
      for (const e of S.buch) if (e.nr > buchNr && e.art === 'rathaus') { neueZeilen++; p(!/\u0001/.test(e.text), 'Name in einer Zeile zum Rathaus'); }
      buchNr = S.buchNr; plaetzeVor = plaetze;
      lohnMin = Math.min(lohnMin, g.lohn[b]); lohnMax = Math.max(lohnMax, g.lohn[b]);
      p(g.lohn[b] >= R.LOHN_STADT && g.lohn[b] <= R.BAU_LOHN_MAX, `Lohn ${g.lohn[b]}`);
      const hh = M.haushaltKurz(S);
      p(Ra.gestern && Math.abs(Ra.gestern.saldo - (S.budget - budgetVor)) < 1e-6, 'Saldo von gestern = Budget heute − gestern');
      // Haushalt (Teil 3): haushaltKurz aus den Konten; die Zeile des Rathauses (Löhne, laufende Kosten, Bau) = Kosten von gestern, Zeilen zusammen = Saldo
      const rz = hh.zeilen.find(z => /^Rathaus/.test(z[0]));
      p(hh.stand === 'gestern' && Math.abs(hh.saldo - Ra.gestern.saldo) < 1e-6 && Math.abs(hh.zeilen.reduce((a, z) => a + z[1], 0) - hh.saldo) < 1e-6
        && (rz ? Math.abs(rz[1] + Ra.gestern.kosten) < 1e-6 : Ra.gestern.kosten === 0) && hh.budget === S.budget && hh.fenster === true,
        'haushaltKurz: Budget, Saldo und Rathaus-Zeile wie gezählt');
      minBudget = Math.min(minBudget, S.budget);
      if (S.erweiterung.stufe > stufeVor) { stufeTag[S.erweiterung.stufe] = S.tag; stufeVor = S.erweiterung.stufe; }
      if (st > (ausbauTage.length + 1)) ausbauTage.push(S.tag);
      belegtVor = L.length; budgetVor = S.budget;
    }
    mc.__vorWirtschaft = null;
    const verz = ausbauTage.map((t, i) => t - (stufeTag[i + 1] || 0));
    pruef(!probleme.length && gegenTage > tage * 0.5, `Seed ${seed}: jede Nacht in Ordnung${probleme.length ? ': ' + probleme.join('; ') : ''}; Löhne nachgerechnet an ${gegen} von ${gegenTage} Tagen gleich;`
      + ` Ausbaustufe ${S.g.stufe[b]} (${Sim.STUFEN[S.erweiterung.stufe]}), Ausbau fertig an Tag ${ausbauTage.join(', ')} (${verz.join(', ')} Tage nach der Stufe), ${S.rathaus.stellen} Stellen + Amt, ${S.belegschaft[b].length} besetzt,`
      + ` Lohn ${lohnMin}–${lohnMax}, kleinstes Budget ${Math.round(minBudget)}, ${neueZeilen} Zeilen zum Rathaus nach Tag 0 (ohne Namen), höchstens ${maxUeber} mehr Leute als Plätze`);
    const rs = S.stat.rathaus;
    pruef(rs.ausbauten === ausbauTage.length + (S.g.auf[b] ? 1 : 0) && rs.bau === [2, 3, 4].slice(0, rs.ausbauten).reduce((s, z) => s + R.K_RATHAUS[z], 0) && rs.fix === R.FIX_RATHAUS * tage,
      `Seed ${seed}: ${rs.ausbauten} Ausbauten, Bau ${rs.bau} Taler aus dem Budget, Löhne ${rs.lohn}, laufende Kosten ${rs.fix} (${R.FIX_RATHAUS} je Tag)`);
  }

  console.log('C Speichern und Laden mitten im Ausbau; Aufholen');
  {
    const S = Sim.neueStadt(2);
    while (!(S.g.auf[S.rathaus.b] && S.stunde === 13)) Sim.stunde(S);
    const t = S.tag, L = laden(Sim, speichern(Sim, S));
    pruef(abdruck(Sim, S) === abdruck(Sim, L), `Seed 2, Tag ${t} 13 Uhr (Ausbau auf Stufe ${S.g.auf[S.rathaus.b]}, ${S.g.bauRest[S.rathaus.b]} Arbeitstage offen): direkt nach dem Laden gleich`);
    bis(Sim, S, t + 30); bis(Sim, L, t + 30);
    pruef(abdruck(Sim, S) === abdruck(Sim, L), `30 Tage weiter bitgleich (Ausbaustufe ${S.g.stufe[S.rathaus.b]})`);
    const A = Sim.neueStadt(3), B = Sim.neueStadt(3);
    bis(Sim, A, 90); while (B.tag < 90) Sim.tagSchritt(B);
    pruef(A.rathaus.b === B.rathaus.b && B.g.stufe[B.rathaus.b] >= 1 && B.buergermeister.p >= 0,
      `Aufholen (Seed 3, 90 Tage in Tagesschritten): Ausbaustufe ${B.g.stufe[B.rathaus.b]} (stündlich ${A.g.stufe[A.rathaus.b]}), Stellen ${B.rathaus.stellen} / ${A.rathaus.stellen}, Amt besetzt`);
  }

  console.log('D Übernahme älterer Stände (nur Brache und höchstens ein Park werden genommen)');
  // Version 8 und (mit --git) 7 und 6 mit sechs Ständen; 5, 4, 3 und 2 mit zwei (Gegenprüfung: die ganze Kette V2–V7 mit eingeschaltetem Rathaus)
  const STAENDE = [[1, 150, 13], [2, 300, 5], [3, 400, 20], [4, 30, 9], [2, 700, 11], [7, 700, 12]], KURZ = [[1, 150, 13], [4, 30, 9]];
  const quellen = [['Version 8 (stadt.orig.html)', readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8'), STAENDE]];
  if (arg('git')) for (const [c, v] of [['ffa1d88', 7], ['bc7247a', 6], ['414ebab', 5], ['1c8d40b', 4], ['2b821c2', 3], ['39c405b', 2]])
    quellen.push([`Version ${v} (git ${c})`, execFileSync('git', ['show', c + ':stadt/stadt.html'], { cwd: arg('git'), encoding: 'utf8', maxBuffer: 1 << 26 }), v >= 6 ? STAENDE : KURZ]);
  else console.log('  (ohne --git: nur Version 8)');
  const weiten = [];
  for (const [herkunft, altHtml, staende] of quellen) {
    const Alt = lade(simCode(altHtml));
    console.log(` ${herkunft}`);
    for (const [seed, tag, stunde] of staende) {
      const A = Alt.neueStadt(seed);
      bis(Alt, A, tag, stunde);
      const text = speichern(Alt, A);
      let abgelehnt = null; try { laden(Sim, text); } catch (e) { abgelehnt = e; }
      const S = laden(Sim, text, true), K = S.karte, KA = A.karte || 96, dm = S.mitte - (A.mitte || 48);
      // Nichts außer einem Park abgerissen: jedes alte Gebäude steht (Typ, Lage zur Mitte, Stufe), jedes alte belegte Feld ist gleich; ein Park,
      // der dem Rathaus weicht, wird das Rathaus (seine Nummer), sein Feld gehört zum Gelände
      const b = S.rathaus.b, r = b >= 0 ? S.erweiterung.gelaende.find(q => q[4] === b) : null;
      let weg = 0, feldAnders = 0, auf = 0, parkWeg = 0;
      for (let x = 0; x < A.gAnzahl; x++) {
        if (x === b && A.g.typ[x] === Sim.PARK) { parkWeg++; continue; }
        if (S.g.typ[x] !== A.g.typ[x] || S.g.x[x] !== A.g.x[x] + dm || S.g.y[x] !== A.g.y[x] + dm || S.g.stufe[x] !== A.g.stufe[x]) weg++;
      }
      const imGel = (x, y) => r && x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3];
      for (let y = 0; y < KA; y++) for (let x = 0; x < KA; x++) {
        const fa = A.feld[y * KA + x], fs = S.feld[(y + dm) * K + x + dm];
        if (fa !== 0 && fa !== fs && !(fa === Sim.PARK && imGel(x + dm, y + dm))) feldAnders++;
      }
      if (r) for (let y = r[1]; y <= r[3]; y++) for (let x = r[0]; x <= r[2]; x++) { const f = A.feld[(y - dm) * KA + x - dm]; if (f !== 0 && f !== Sim.PARK) auf++; }
      const weit = r ? Math.round(Math.abs((r[0] + r[2]) / 2 - S.mitte) + Math.abs((r[1] + r[3]) / 2 - S.mitte)) : -1;
      if (weit >= 0) weiten.push(weit);
      pruef(abgelehnt && abgelehnt.andereVersion && abgelehnt.migrierbar && S.version === Sim.VERSION && !weg && !feldAnders && !auf && parkWeg <= 1 && S.stat.rathaus.parks === parkWeg
        && (b < 0 || S.g.stufe[b] === S.erweiterung.stufe + 1) && S.buergermeister.p === -1,
        `Seed ${seed}, Tag ${A.tag} (${A.einwohner} Einw., ${Sim.STUFEN[S.erweiterung.stufe]}): ohne Übernehmen abgelehnt; ${weg} Gebäude und ${feldAnders} Felder anders,`
        + ` Rathaus ${b >= 0 ? `${r[2] - r[0] + 1} × ${r[3] - r[1] + 1} Felder, ${weit} Felder von der Mitte, Ausbaustufe ${S.g.stufe[b]}, ${auf} vorher bebaute Felder, ${parkWeg} Park genommen` : 'noch nicht gebaut'};`
        + ` noch kein Bürgermeister; Budget ${Math.round(A.budget)} → ${Math.round(S.budget)}`);
      const t0 = S.tag; let offenAb = -1, wahlAm = -1;
      for (let d = 1; d <= 60; d++) {
        bis(Sim, S, t0 + d);
        if (offenAb < 0 && S.rathaus.b >= 0 && S.feld[S.g.y[S.rathaus.b] * S.karte + S.g.x[S.rathaus.b]] === RATHAUS) offenAb = d;
        if (wahlAm < 0 && S.buergermeister.p >= 0) wahlAm = d;
      }
      const L = laden(Sim, speichern(Sim, S)); bis(Sim, S, S.tag + 10); bis(Sim, L, L.tag + 10);
      pruef(offenAb > 0 && wahlAm >= offenAb && wahlAm <= offenAb + 1 && abdruck(Sim, S) === abdruck(Sim, L),
        `  60 Tage weiter: Rathaus offen nach ${offenAb} Tagen, gewählt nach ${wahlAm} (in der ersten Nacht mit offenem Rathaus), ${S.belegschaft[S.rathaus.b].length} von ${Sim.stellen(S, S.rathaus.b)} Plätzen besetzt; gespeichert und geladen bitgleich`);
    }
  }
  console.log(`  Abstand des Rathauses zur Mitte bei Übernahmen: ${Math.min(...weiten)} bis ${Math.max(...weiten)} Felder (${weiten.length} Stände)`);

  console.log('E Park weicht dem Rathaus (erzwungen: Stand der Version 8, Park mitten auf dem nächsten freien Gelände)');
  {
    // Stand der Version 8 (Seed 2, Tag 200); ins nächste freie Gelände setzt die alte Sim einen fertigen Park (neuesGebaeude, Arbeit 0)
    const { Sim: AltM } = (() => { const code = simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')).replace('G.StadtSim = {', 'G.StadtSim = { neuesGebaeude,');
      const ctx = vm.createContext({}); vm.runInContext(code, ctx); return { Sim: ctx.StadtSim }; })();
    const A2 = AltM.neueStadt(2); bis(AltM, A2, 200, 3);
    const r2 = AltM.gelaendeSuchen(A2, 2, 1, false) || AltM.gelaendeSuchen(A2, 1, 2, false);
    const park = AltM.neuesGebaeude(A2, Sim.PARK, r2.x0 + 1, r2.y0 + 1, 0, -1);
    const S = laden(Sim, speichern(AltM, A2), true), b = S.rathaus.b, g = S.g, dm = S.mitte - A2.mitte;
    const zeile = S.buch.slice(-2).map(e => Sim.klartext(e.text)).join(' | ');
    pruef(b === park && g.typ[b] === RATHAUS && S.stat.rathaus.parks === 1 && S.feld[(r2.y0 + 1 + dm) * S.karte + r2.x0 + 1 + dm] === RATHAUS && !S.vPark.some(L => L.includes(b))
      && /weicht der Park/.test(zeile), `Park (Gebäude ${park}) wird das Rathaus am Tor, sein Feld gehört zum Gelände, aus der Parkliste; „${zeile.slice(0, 160)}…“`);
    bis(Sim, S, S.tag + 40);
    const L = laden(Sim, speichern(Sim, S)); bis(Sim, S, S.tag + 5); bis(Sim, L, L.tag + 5);
    pruef(abdruck(Sim, S) === abdruck(Sim, L) && S.buergermeister.p >= 0, `40 Tage weiter (Rathaus ${Sim.klartext(Sim.gebaeudeInfo(S, b).titel)}, Amt besetzt), gespeichert und geladen bitgleich`);
  }

  console.log('F Beschädigte Stände');
  {
    const S = Sim.neueStadt(1); bis(Sim, S, 120);
    const text = speichern(Sim, S), b = S.rathaus.b, meld = [];
    const faelle = [['Rathaus fehlt', d => { delete d.json.rathaus; }], ['Nummer zu groß', d => { d.json.rathaus.b = 99999; }], ['Nummer eines Wohnhauses', d => { d.json.rathaus.b = 0; }],
      ['Stellen negativ', d => { d.json.rathaus.stellen = -1; }], ['gestern kein Objekt', d => { d.json.rathaus.gestern = 'x'; }], ['Summe fehlt', d => { delete d.json.stat.rathaus.lohn; }],
      ['Summe Parks fehlt', d => { delete d.json.stat.rathaus.parks; }],
      // Teil 5: In Seed 1 wird das Rathaus an Tag 120 wirklich ausgebaut (Baustelle); deshalb hier auf der nächsten Stufe und ohne die Baustelle
      ['Ausbau ohne Baustelle', d => { d.arrays.find(a => a.name === 'g.auf').daten[b] = S.g.stufe[b] + 1; d.json.baustellen = d.json.baustellen.filter(x => x !== b); }], ['Stufe 7', d => { d.arrays.find(a => a.name === 'g.stufe').daten[b] = 7; }],
      ['zweites Rathaus', d => { const t = d.arrays.find(a => a.name === 'g.typ').daten; t[0] = RATHAUS; }], ['Start in der Zukunft', d => { d.json.rathaus.start = 99999; }],
      ['Stand der Version 9 ohne Summen des Rathauses', d => { delete d.json.stat.rathaus; }]];
    for (const [was, kaputt] of faelle) {
      const d = roh(text); kaputt(d);
      let e = null; try { Sim.importZustand(d); } catch (x) { e = x; }
      meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
      if (!e || !/^Spielstand beschädigt/.test(e.message)) fehler++;
    }
    console.log((meld.every(m => /beschädigt/.test(m)) ? '  ok   ' : '  FEHL ') + meld.join('; '));
  }

  console.log('G Namen tauschen (Seed 2, 365 Tage): die Stadt läuft gleich, bis auf Namen und Texte');
  {
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(2), B = T.neueStadt(2);
    bis(Sim, A, 365); bis(T, B, 365);
    const h = (S) => { const x = createHash('sha256'); for (const n of Object.keys(S.p).sort()) { const a = S.p[n]; x.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      for (const n of Object.keys(S.g).sort()) { const a = S.g[n]; x.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      x.update(JSON.stringify([S.budget, S.rs, S.rsSich, S.rsAuto, S.rathaus, S.stat, S.einwohner, S.buergermeister.p, S.buergermeister.seit, S.buergermeister.bis]));
      x.update(S.buch.map(e => e.art).join()); return x.digest('hex').slice(0, 16); };
    pruef(Sim.name(A, 3) !== T.name(B, 3) && h(A) === h(B), `„${Sim.name(A, 3)}“ heißt dort „${T.name(B, 3)}“; gleich (Tag 365, ${A.einwohner} Einwohner, Rathaus ${A.belegschaft[A.rathaus.b].length} besetzt, ${h(A)})`);
  }

  console.log('H Ohne Rathaus (R.RATHAUS = 0): Tag für Tag wie Version 8 (stadt.orig.html)');
  {
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const spur = (S) => { const x = createHash('sha256');
      for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n]) && n !== 'schule') { const a = S.p[n], w = a.length / S.pKap; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }   // Schulplatz: gibt es in Version 8 nicht
      for (const n of Object.keys(S.g).sort()) { if (n === 'markt' || n === 'kraft') continue; const a = S.g[n]; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.gAnzahl * a.BYTES_PER_ELEMENT)); }   // Teil 5: neue Felder
      x.update(Buffer.from(S.feld.buffer)); const st = { ...S.stat, tech: techAlt(S.stat.tech) }; delete st.rathaus; delete st.buergermeister; delete st.schule; delete st.aufgegeben;
      x.update(JSON.stringify([S.budget, S.rs, S.rsSich, S.rsAuto, S.tag, S.einwohner, st, kiAlt(S.ki), S.regierung, S.sicherheit, S.bund, S.erweiterung])); x.update(JSON.stringify(S.buch));   // Teil 4: ohne KI-Frist
      return x.digest('hex').slice(0, 16); };
    const alt = R.RATHAUS, altS = R.SCHULEN, altH = [R.HH_VORHABEN, R.HH_STEUER]; R.RATHAUS = 0; R.SCHULEN = 0;   // Schule (Version 9): für den Vergleich mit Version 8 ebenfalls aus
    R.HH_VORHABEN = 0; R.HH_STEUER = 0;                      // Haushalt (Teil 3): nur Buchführung (Lohnsteuer 10 %, keine Vorhaben), sonst liefe die Stadt anders
    const altA = R.ANLAUF_STUFE; R.ANLAUF_STUFE = 0;         // Wachstum (Teil 4): ohne Anlauf, sonst zögen am Anfang mehr Leute zu
    const altT = [R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU]; R.TECH_FRUEH = 0; R.WELT = 0; R.ZUZUG_GENAU = 0;   // Teil 5: ohne Tech früher und Weltmarkt; Zuzug wie vorher (Schlussprüfung)
    for (const seed of arg('gleichSeeds', '1,2').split(',').map(Number)) {
      const A = V8.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1, n = 0;
      const bisTag = Number(arg('gleichTage', '365'));
      for (let d = 1; d <= bisTag; d++) { bis(V8, A, d); bis(Sim, B, d); n++; if (erster < 0 && spur(A) !== spur(B)) erster = d; }
      pruef(erster < 0 && B.buergermeister.p === -1, `Seed ${seed}: ${n} Tage verglichen (Personen, Gebäude, Felder, Budget, Zufall, Summen, Hauptfiguren, Stadtbuch), ${erster < 0 ? 'jeden Tag gleich' : 'erster Unterschied an Tag ' + erster}`);
    }
    R.RATHAUS = alt; R.SCHULEN = altS; [R.HH_VORHABEN, R.HH_STEUER] = altH; R.ANLAUF_STUFE = altA; [R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU] = altT;
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zum Rathaus bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('buergermeister')) {
  // Bürgermeister (Version 9). 1. statisch: Wahl liest nur neutrale Personenfelder (keine Namen, keine Herkunft, kein Einzugstag, keine Eltern,
  // kein Geschlecht), Zufall nur aus wahlZufall; Namenstausch bitgleich. 2. Invarianten nach jeder Nacht (Seeds 1–3, 730 Tage). 3. Erzwungene
  // Fälle: Tod, Haft, Wegzug im Amt, Abwahl, Hauptfigur (eigener Platz, Grenze), Gehirn im Amt. 4. Rangfolge der Vorhaben (Schnittstelle zum
  // Haushalt) mit Testvorhaben: Anfrage, gültige und ungültige Antworten, Frist, Aufholen, KI aus. 5. Speichern und Laden, beschädigte Stände.
  // 6. Messung nach Gruppen (nur gemessen: keine Regel liest diese Merkmale)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, X = Sim._bm;
  const bis = (Y, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) Y.stunde(S); };
  const erwachsen = (S, p) => S.tag - S.p.geb[p] >= R.ERWACHSEN * J;
  const lebtNoch = (S, id, gen) => id >= 0 && S.p.lebt[id] && S.p.gen[id] === gen;
  // Kopie mit Messpunkt: jede Wahl (Kandidaten, Stimmen, Amtsinhaber vorher)
  const { Sim: M, ctx: mc } = ladeSimMit([['  const { n, waehler } = bmStimmen(S, K), alt = istBm(S, B.p) ? B.p : -1;\n',
    '  const { n, waehler } = bmStimmen(S, K), alt = istBm(S, B.p) ? B.p : -1;\n  if (globalThis.__wahl) globalThis.__wahl(S, K, n, waehler, alt);\n']]);

  console.log('1 Statisch');
  {
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const koerper = (f) => { const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return null;
      let t = 0, j = code.indexOf('{', i); for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; } return code.slice(i, j + 1); };
    const felder = (k) => [...new Set([...k.matchAll(/\bP\.(\w+)/g)].map(m => m[1]))].sort();
    const ERLAUBT = { waehlbar: ['besitz', 'bund', 'geb', 'haftBis', 'lebt'], bmKandidaten: [], bmBeste: ['ehrgeiz'], bmStimmen: ['geb', 'lebt', 'partner', 'zuf'], wahlZufall: [],
      freundeZahl: ['freunde'], sindFreunde: ['freunde'], verpflichtet: ['bund', 'dienstBis'], istBm: [] };
    const VERBOTEN = ['weib', 'vor', 'nach', 'einzug', 'elternA', 'elternB', 'elternAGen', 'elternBGen', 'elternNameA', 'elternNameB', 'memName', 'memCode', 'heimat'];
    const zuViel = [];
    for (const [f, ok] of Object.entries(ERLAUBT)) {
      const k = koerper(f); if (!k) { zuViel.push(f + ': fehlt'); continue; }
      for (const x of felder(k)) if (!ok.includes(x)) zuViel.push(`${f}: P.${x}`);
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo|zufall|zInt|zufallSich|zufallAuto)\s*\(/.test(k)) zuViel.push(`${f}: Name oder Zufallsstrom`);
    }
    for (const f of ['rentner', 'gebunden', 'anspruch', 'kitaFrei']) { const k = koerper(f) || ''; for (const x of felder(k)) if (VERBOTEN.includes(x)) zuViel.push(`${f}: P.${x}`); }
    pruef(!zuViel.length, `Wahl: Regeln lesen nur ihre Personenfelder (${Object.keys(ERLAUBT).join(', ')}; dazu rentner, gebunden: nichts aus ${VERBOTEN.join(', ')}); kein Name, kein Zufallsstrom`
      + (zuViel.length ? ': ' + zuViel.join(', ') : ''));
    const w = koerper('bmWahl'), weib = w.split('\n').filter(z => /P\.weib/.test(z));
    pruef(weib.length === 1 && /const wort = P\.weib\[neu\] \? 'zur Bürgermeisterin' : 'zum Bürgermeister';/.test(weib[0]), 'bmWahl liest das Geschlecht nur für das Wort im Stadtbuch (nach der Wahl)');
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(3), B = T.neueStadt(3);
    bis(Sim, A, 500); bis(T, B, 500);
    const spur = (S) => { const h = createHash('sha256'); for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n])) { const a = S.p[n], w = a.length / S.pKap; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      const bm = S.buergermeister; h.update(JSON.stringify([bm.p, bm.gen, bm.seit, bm.bis, bm.nr, bm.wahl.kandidaten.map(k => [k.id, k.stimmen]), S.stat.buergermeister, S.budget, S.rs]));
      h.update(S.buch.map(e => e.art).join()); return h.digest('hex').slice(0, 16); };
    pruef(Sim.name(A, 0) !== T.name(B, 0) && spur(A) === spur(B), `Namenstausch (Seed 3, 500 Tage, ${A.stat.buergermeister.wahlen} Wahlen): „${Sim.name(A, 0)}“ heißt dort „${T.name(B, 0)}“, Wahlen und Stadt bitgleich (${spur(A)})`);
  }

  console.log('2 Invarianten nach jeder Nacht');
  const seeds = arg('seeds', '1,2,3').split(',').map(Number), tage = Number(arg('tage', '730'));
  for (const seed of seeds) {
    const S = M.neueStadt(seed), P = S.p, B = S.buergermeister, fehl = {};
    const f = (k) => { fehl[k] = (fehl[k] || 0) + 1; };
    let wahlen = [], leerNaechte = 0, amtWechsel = 0, zeilen = S.buch.filter(e => e.art === 'wahl').length, buchNr = S.buchNr;
    mc.__wahl = (X2, K, n, waehler, alt) => {
      let erw = 0; for (let p = 0; p < X2.pMax; p++) if (X2.p.lebt[p] && erwachsen(X2, p)) erw++;
      if (waehler !== erw || n.reduce((a, b) => a + b, 0) !== waehler) f('Stimmen ≠ Wähler');
      if (K.length > R.BM_KANDIDATEN || new Set(K).size !== K.length) f('Kandidaten');
      if (!K.every(c => M._bm.waehlbar(X2, c))) f('Kandidat nicht wählbar');
      if (alt >= 0 && M._bm.waehlbar(X2, alt) && K[0] !== alt) f('Amtsinhaber tritt nicht an');
      wahlen.push({ tag: X2.tag, K: K.slice(), n: n.slice(), alt });
    };
    // Tag 0: vor dem Messpunkt gewählt
    if (!(B.p >= 0 && B.seit === 0 && B.bis === R.BM_AMTSZEIT && B.nr === 1 && P.arbeit[B.p] === S.rathaus.b && Sim.hauptListe(S)[0].id === B.p && !Sim.inHauptListe(S, B.p) && S.ki.haupt.length === R.HAUPT_START)) f('Tag 0');
    let vorher = { p: B.p, gen: B.gen, bis: B.bis };
    for (let d = 1; d <= tage; d++) {
      bis(M, S, d);
      const b = S.rathaus.b;
      if (B.p >= 0) {
        if (!lebtNoch(S, B.p, B.gen) || P.arbeit[B.p] !== b || !S.belegschaft[b].includes(B.p) || P.haftBis[B.p] || !erwachsen(S, B.p)) f('Amt: lebt, arbeitet im Rathaus, nicht in Haft');
        if (!Sim.istHaupt(S, B.p) || Sim.hauptListe(S)[0].id !== B.p) f('Hauptfigur auf eigenem Platz');
        if ((B.bis - B.seit) % R.BM_AMTSZEIT || B.bis - B.seit < R.BM_AMTSZEIT || B.bis <= S.tag) f('Amtszeit');   // seit: erster Amtsantritt, bis: Ende der laufenden Amtszeit
        if (Sim.stellen(S, b) !== S.rathaus.stellen + 1) f('Stelle des Amts');
        const erl = Sim.erlaubteAktionen(S, B.p, 7).concat(Sim.erlaubteAktionen(S, B.p, 18));
        if (erl.some(a => a === 'job_wechseln' || a === 'kuendigen' || a === 'laden_gruenden' || a === 'job_suchen')) f('Gehirn im Amt: wechseln, kündigen, gründen gesperrt');
      } else { leerNaechte++; if (S.rathaus.b >= 0 && Sim.stellen(S, b) !== S.rathaus.stellen) f('frei: keine Stelle für das Amt'); }
      if (Sim.hauptZahl(S) > R.HAUPT_MAX || Sim.hauptListe(S).length > R.HAUPT_MAX + 1) f('Grenze der Hauptfiguren');
      if (Sim.hauptListeZahl(S) !== Sim.hauptListe(S).length) f('hauptListeZahl ≠ Länge von hauptListe');   // Befund Technik: Zahl ohne neue Objekte
      if (B.p !== vorher.p) amtWechsel++;
      vorher = { p: B.p, gen: B.gen, bis: B.bis };
      for (const e of S.buch) if (e.nr > buchNr && e.art === 'wahl') zeilen++;
      buchNr = S.buchNr;
    }
    mc.__wahl = null;
    const st = S.stat.buergermeister;
    if (zeilen !== st.wahlen + st.vorzeitig) f(`Stadtbuch: ${zeilen} Zeilen, ${st.wahlen} Wahlen + ${st.vorzeitig} vorzeitig`);
    if (wahlen.length !== st.wahlen - 1) f('Zahl der Wahlen');
    for (const w of wahlen) { const m = Math.max(...w.n), s = w.n.indexOf(m); if (s < 0) f('Sieger'); }
    // Wahltage: alle BM_AMTSZEIT Tage, außer nach einem vorzeitigen Ende (dann in der Nacht danach)
    const regulaer = wahlen.filter(w => (w.tag + 1) % R.BM_AMTSZEIT === 0).length;
    pruef(!Object.keys(fehl).length && leerNaechte <= st.vorzeitig,
      `Seed ${seed}: ${st.wahlen} Wahlen (${regulaer + 1} regulär, ${st.wiederwahlen} Wiederwahlen, ${st.abgewaehlt} abgewählt, ${st.vorzeitig} vorzeitige Enden), ${amtWechsel} Wechsel im Amt,`
      + ` ${leerNaechte} Nächte ohne Amtsinhaber; zuletzt ${wahlen.length ? `${wahlen[wahlen.length - 1].n.join('/')} Stimmen` : '–'}${Object.keys(fehl).length ? '; FEHLER: ' + JSON.stringify(fehl) : ''}`);
  }

  console.log('3 Erzwungene Fälle');
  {
    // Tod im Amt: Zeile, Neuwahl in der nächsten Nacht, keine Nachfolge-Frage (nicht in Noahs Liste), Stelle fällt weg
    const S = Sim.neueStadt(2); bis(Sim, S, 30, 10);
    const B = S.buergermeister, p = B.p, b = S.rathaus.b, frei0 = S.freieStellen, v0 = S.ki.verlust.length;
    Sim._pruef.sterben(S, p);
    const zeile = Sim.klartext(S.buch[S.buch.length - 1].text);
    pruef(B.p === -1 && B.bis === S.tag + 1 && S.freieStellen === frei0 && S.ki.verlust.length === v0 && /ist nicht mehr Bürgermeister/.test(zeile) && /gestorben/.test(zeile),
      `Tod im Amt: „${zeile.slice(0, 110)}“; keine freie Stelle dazu (${frei0} → ${S.freieStellen}), keine Nachfolge-Frage`);
    bis(Sim, S, 32);
    pruef(B.p >= 0 && B.seit === 31 && B.bis === 31 + R.BM_AMTSZEIT && S.p.arbeit[B.p] === b, `Neuwahl in der Nacht danach: Amtsantritt Tag ${B.seit}, bis ${B.bis}`);
    // Haft im Amt
    const p2 = B.p; Sim._sich.haftAntritt(S, p2, 5, Sim.HAFT_STRAF);
    const z2 = Sim.klartext(S.buch[S.buch.length - 1].text);
    pruef(B.p === -1 && S.p.arbeit[p2] === -1 && /in Haft/.test(z2), `Haft im Amt: Amt endet („${z2.slice(0, 80)}“)`);
    bis(Sim, S, S.tag + 2);
    pruef(B.p >= 0 && B.p !== p2, 'Neuwahl nach der Haft; wer in Haft ist, ist nicht wählbar');
    // Wegzug im Amt (mit dem Haushalt): Amt endet; war er Noahs Hauptfigur, fragt die Stadt nach der Nachfolge
    const p3 = B.p; Sim.hauptSetzen(S, p3, S.p.gen[p3], true, R.HAUPT_MAX);
    const inListe = Sim.inHauptListe(S, p3), v1 = S.ki.verlust.length;
    Sim._pruef.aktWegziehen(S, p3);
    pruef(inListe && B.p === -1 && S.ki.verlust.length === v1 + 1 && !S.p.lebt[p3], `Wegzug im Amt: Amt endet; als Noahs Hauptfigur kommt die Nachfolge-Frage (${S.ki.verlust.length - v1})`);
    while (S.ki.verlust.length) Sim.verlustErledigt(S);
  }
  {
    // Eigener Platz: 10 Hauptfiguren und das Amt; das Amt zählt nicht mit; auch Noahs Hauptfigur kann er zusätzlich werden
    const S = Sim.neueStadt(1); bis(Sim, S, 200);
    const B = S.buergermeister, erw = [];
    for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && erwachsen(S, p) && p !== B.p && !Sim.inHauptListe(S, p)) erw.push(p);
    for (const p of erw) if (Sim.hauptZahl(S) < R.HAUPT_MAX) Sim.hauptSetzen(S, p, S.p.gen[p], true, R.HAUPT_MAX);
    const voll = Sim.hauptZahl(S), liste = Sim.hauptListe(S).length, noch = Sim.hauptSetzen(S, erw[erw.length - 1], S.p.gen[erw[erw.length - 1]], true, R.HAUPT_MAX);
    // Noah macht das Amt zusätzlich zu seiner Hauptfigur: geht nicht, solange 10 da sind; nach Freimachen eines Platzes schon, und dann belegt es
    // einen seiner Plätze (Befund Technik der Schlussprüfung: vorher zählte es nicht, und nach dem Amtsende waren es 11 gezählt und 12 in der Leiste)
    const amtVoll = Sim.hauptSetzen(S, B.p, B.gen, true, R.HAUPT_MAX);
    const h0 = S.ki.haupt[0]; Sim.hauptSetzen(S, h0.id, h0.gen, false);
    const ok2 = Sim.hauptSetzen(S, B.p, B.gen, true, R.HAUPT_MAX), z2 = Sim.hauptZahl(S), l2 = Sim.hauptListe(S).length;
    const weitere = erw.find(p => !Sim.inHauptListe(S, p)), noch2 = Sim.hauptSetzen(S, weitere, S.p.gen[weitere], true, R.HAUPT_MAX);
    pruef(voll === R.HAUPT_MAX && liste === R.HAUPT_MAX + 1 && !noch && !amtVoll && ok2 && z2 === R.HAUPT_MAX && l2 === R.HAUPT_MAX && !noch2 && Sim.hauptListeZahl(S) === l2,
      `Eigener Platz: ${voll} Hauptfiguren + Amt = ${liste} in der Leiste, eine elfte geht nicht, das Amt dazu auch nicht; nach Freimachen belegt das Amt als Noahs `
      + `Hauptfigur einen Platz (${z2} gezählt, ${l2} in der Leiste), danach geht keine weitere`);
    // Abwahl erzwingen: alle unzufrieden → der Amtsinhaber verliert (Stimmen hängen an der Zufriedenheit)
    const alt = B.p;
    for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p]) S.p.zuf[p] = 0;
    B.bis = S.tag + 1; X.buergermeisterTag(S);
    const w = B.wahl;
    pruef(B.p !== alt && S.p.arbeit[alt] === -1 && w.kandidaten[0].id === alt && w.kandidaten[0].amt && Sim.inHauptListe(S, alt) && S.stat.buergermeister.abgewaehlt >= 1
      && S.p.memCode.some((c, i) => c === Sim.M.AMT_ENDE && ((i / R.MEM) | 0) === alt),
      `Abwahl bei Unzufriedenheit: ${w.kandidaten.map(k => k.stimmen).join('/')} Stimmen, der alte Amtsinhaber verliert Amt und Stelle, bleibt Noahs Hauptfigur, erinnert sich („Bürgermeisterwahl verloren“)`);
    // Liste voll, das alte Amt darin, neuer Amtsinhaber auf eigenem Platz: Grenze gehalten (höchstens 10 gezählt, 11 in der Leiste = Plätze der Figuren)
    const z3 = Sim.hauptZahl(S), l3 = Sim.hauptListe(S).length, neu3 = B.p, frei3 = Sim.hauptSetzen(S, neu3, B.gen, true, R.HAUPT_MAX);
    pruef(z3 === R.HAUPT_MAX && l3 === R.HAUPT_MAX + 1 && !frei3 && Sim.hauptListeZahl(S) === l3,
      `Nach dem Amtsende bei voller Liste: ${z3} gezählt (Grenze ${R.HAUPT_MAX}), ${l3} in der Leiste (Plätze der Oberfläche: ${R.HAUPT_MAX + 1}); das neue Amt kann nicht zusätzlich Noahs Hauptfigur werden`);
    // Wahlgang: Hat der Sieger nicht mehr als die Hälfte der Stimmen, nennt das Stadtbuch den zweiten Wahlgang (§ 44a KomWG Sachsen, vereinfacht)
    const zw = S.buch.filter(e => e.art === 'wahl').pop(), mehr = 2 * Math.max(...w.kandidaten.map(k => k.stimmen)) > w.waehler;
    pruef(/im zweiten Wahlgang/.test(zw.text) === !mehr, `Stadtbuch nennt den zweiten Wahlgang genau dann, wenn niemand mehr als die Hälfte hat (${Math.max(...w.kandidaten.map(k => k.stimmen))} von ${w.waehler})`);
  }
  {
    // Wählbar: Alter, Haft, Betrieb, Dienst (erzwungen an einer Person)
    const S = Sim.neueStadt(4); bis(Sim, S, 120);
    const P = S.p; let q = -1; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && erwachsen(S, p) && X.waehlbar(S, p)) { q = p; break; }
    const g0 = P.geb[q], w0 = X.waehlbar(S, q);
    P.geb[q] = S.tag - 65 * J; const alt = X.waehlbar(S, q); P.geb[q] = S.tag - 17 * J; const jung = X.waehlbar(S, q); P.geb[q] = g0;
    P.haftBis[q] = S.tag + 3; const haft = X.waehlbar(S, q); P.haftBis[q] = 0;
    pruef(w0 && !alt && !jung && !haft, 'Wählbar: 18 bis unter 65, nicht in Haft (erzwungen an einer Person)');
  }

  console.log('4 Rangfolge der Vorhaben (Schnittstelle zum Haushalt, mit Testvorhaben)');
  {
    // Haushalt (Teil 3): Die Liste hat Vorhaben (seit Teil 5 drei: die Computer der Schulen sind Bedarf davor); für diese Prüfungen stehen dort die
    // drei Testvorhaben, danach wieder die echten
    const V = Sim.VORHABEN, echt = V.splice(0); V.push({ id: 'a', name: 'Vorhaben A', satz: 'A.' }, { id: 'b', name: 'Vorhaben B', satz: 'B.' }, { id: 'c', name: 'Vorhaben C', satz: 'C.' });
    try {
      const S = Sim.neueStadt(2); Sim.kiSchalten(S, true); bis(Sim, S, 9, 7);
      const B = S.buergermeister;
      const a0 = B.anfrage; bis(Sim, S, 9, 8);
      const a = Sim.bmAnfrage(S);
      pruef(!a0 && a && a.jahr === 1 && a.id === B.p && a.vorhaben.length === 3 && a.von === 10 && a.bis === 19, `Anfrage am letzten Tag des Jahres um 7 Uhr: Jahr ${a && a.jahr}, Tag ${a && a.von}–${a && a.bis}, ${a && a.vorhaben.length} Vorhaben`);
      const falsch1 = Sim.bmRangfolge(S, a.id, a.gen, a.nr + 1, ['c', 'a', 'b'], 'x');
      const ok = Sim.bmRangfolge(S, a.id, a.gen, a.nr, ['c', 'a'], 'Ich will zuerst C, dann A.');
      const tb = S.ki.tagebuch[a.id + '/' + a.gen], e = tb[tb.length - 1];
      pruef(!falsch1.ok && ok.ok && B.rangfolge.von === 'ki' && B.rangfolge.liste.join() === 'c,a,b' && e.art === 'amt' && e.rangfolge.join() === 'c,a,b' && e.jahr === 1
        && Sim.vorhabenRangfolge(S, 1).join() === 'c,a,b' && Sim.vorhabenRangfolge(S).join() === 'a,b,c',
        `gültige Antwort (fehlende hinten): ${B.rangfolge.liste.join(', ')}, Tagebuch „${e.text}“; im Jahr 0 noch die Regel (${Sim.vorhabenRangfolge(S).join(', ')}); falsche Nummer abgelehnt`);
      bis(Sim, S, 12);
      pruef(Sim.vorhabenRangfolge(S).join() === 'c,a,b' && S.stat.buergermeister.rangKi === 1, `im Jahr 1 gilt sie (${Sim.vorhabenRangfolge(S).join(', ')})`);
      // ungültig: unbekanntes Vorhaben, doppelt, leer → Regel
      bis(Sim, S, 19, 8);
      const a2 = Sim.bmAnfrage(S), r2 = Sim.bmRangfolge(S, a2.id, a2.gen, a2.nr, ['a', 'a'], 'x');
      pruef(!r2.ok && B.rangfolge.jahr === 2 && B.rangfolge.von === 'regel' && B.anfrage === null && ['x'].every(() => X.rangfolgeAus(['z']) === null && X.rangfolgeAus([]) === null),
        'ungültige Antwort (doppelt; auch unbekannt oder leer) → Regel fürs Jahr 2');
      // Frist: keine Antwort → nach R.KI_FRIST Stunden die Regel
      bis(Sim, S, 29, 8); const a3 = Sim.bmAnfrage(S); bis(Sim, S, 29, 7 + R.KI_FRIST + 1);
      pruef(a3 && B.anfrage === null && B.rangfolge.jahr === 3 && B.rangfolge.von === 'regel', `ohne Antwort: nach ${R.KI_FRIST} Spielstunden die Regel`);
      // KI aus: keine Anfrage, in der letzten Nacht des Jahres die Regel
      Sim.kiSchalten(S, false); bis(Sim, S, 39, 9);
      const keine = !S.buergermeister.anfrage; bis(Sim, S, 40);
      pruef(keine && B.rangfolge.jahr === 4 && B.rangfolge.von === 'regel', 'KI aus: keine Anfrage, die Regel ab der letzten Nacht');
      // Aufholen (Tagesschritte): keine Anfrage an die KI, in der letzten Nacht die Regel
      Sim.kiSchalten(S, true); bis(Sim, S, 50); let a5 = false;
      while (S.tag < 60) { Sim.tagSchritt(S); if (S.buergermeister.anfrage) a5 = true; }
      pruef(!a5 && B.rangfolge.jahr === 6 && B.rangfolge.von === 'regel', 'Aufholen in Tagesschritten: keine Anfrage an die KI, die Regel fürs Jahr 6');
      // Speichern und Laden mit offener Anfrage bitgleich
      bis(Sim, S, 69, 8);
      const L = ladenAusText(Sim, speichernAlsText(Sim, S)), offen = !!L.buergermeister.anfrage;
      bis(Sim, S, 75); bis(Sim, L, 75);
      pruef(offen && fingerabdruck(Sim, S) === fingerabdruck(Sim, L) && JSON.stringify(S.buergermeister) === JSON.stringify(L.buergermeister), 'Speichern und Laden mit offener Anfrage (Tag 69, 8 Uhr): 6 Tage weiter bitgleich');
    } finally { V.length = 0; }
    const S0 = Sim.neueStadt(2); Sim.kiSchalten(S0, true); bis(Sim, S0, 12);
    pruef(!S0.buergermeister.anfrage && S0.buergermeister.rangfolge === null, 'ohne Vorhaben (leere Liste): keine Anfrage, keine Rangfolge');
    V.push(...echt);
    const S1 = Sim.neueStadt(2); Sim.kiSchalten(S1, true); bis(Sim, S1, 9, 8);
    const a1 = Sim.bmAnfrage(S1); bis(Sim, S1, 12);
    pruef(a1 && a1.vorhaben.map(v => v.id).join() === 'wohnungen,rathaus,parks' && S1.buergermeister.rangfolge && S1.buergermeister.rangfolge.jahr === 1
      && S1.buergermeister.rangfolge.von === 'regel' && S1.haushalt.plan.rang.join() === S1.buergermeister.rangfolge.liste.join() && !Sim.bmRangfolge(S1, 0, 0, -1, ['computer'], '').ok,
      `mit den drei Vorhaben des Haushalts (Teil 5: die Computer der Schulen sind Bedarf, nicht in der Rangfolge): Anfrage an Tag 9 um 7 Uhr (${a1 ? a1.vorhaben.map(v => v.name).join(', ') : '–'}); ohne Antwort die Regel, der Plan fürs Jahr 1 folgt ihr`);
  }

  console.log('5 Speichern, Laden, beschädigte Stände, Übernahme');
  {
    const S = Sim.neueStadt(1); bis(Sim, S, 69, 23);                 // kurz vor der Wahl in der Nacht
    const L = ladenAusText(Sim, speichernAlsText(Sim, S)); bis(Sim, S, 100); bis(Sim, L, 100);
    pruef(fingerabdruck(Sim, S) === fingerabdruck(Sim, L) && JSON.stringify(S.buergermeister) === JSON.stringify(L.buergermeister), 'Speichern vor der Wahlnacht (Tag 69, 23 Uhr), 31 Tage weiter bitgleich');
    const text = speichernAlsText(Sim, S), meld = [];
    const roh = (t) => { const d = JSON.parse(t); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64');
      return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
    const faelle = [['Amt fehlt', d => { delete d.json.buergermeister; }], ['Person außerhalb', d => { d.json.buergermeister.p = 999999; }],
      ['falsche Generation', d => { d.json.buergermeister.gen += 1; }], ['nicht im Rathaus', d => { const a = d.arrays.find(x => x.name === 'p.arbeit').daten; a[d.json.buergermeister.p] = -1; }],
      ['Wahl ohne Kandidaten-Liste', d => { d.json.buergermeister.wahl.kandidaten = 'x'; }], ['Rangfolge von wem', d => { d.json.buergermeister.rangfolge = { jahr: 1, liste: [], von: 'noah', tag: 1 }; }],
      ['Anfrage ohne Frist', d => { d.json.buergermeister.anfrage = { nr: 1, id: 0, gen: 1, jahr: 1, tag: 1, stunde: 7, erlaubt: [] }; }],
      ['Summe fehlt', d => { delete d.json.stat.buergermeister.wahlen; }], ['Summen fehlen', d => { delete d.json.stat.buergermeister; }],
      ['Tagebuch mit Rangfolge ohne Jahr', d => { const k = Object.keys(d.json.ki.tagebuch)[0] || '0/1'; (d.json.ki.tagebuch[k] = d.json.ki.tagebuch[k] || []).push({ tag: 1, stunde: 7, art: 'amt', text: 'x', rangfolge: ['a'] }); }]];
    for (const [was, kaputt] of faelle) {
      const d = roh(text); kaputt(d);
      let e = null; try { Sim.importZustand(d); } catch (x) { e = x; }
      meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
      if (!e || !/^Spielstand beschädigt/.test(e.message)) fehler++;
    }
    console.log((meld.every(m => /beschädigt/.test(m)) ? '  ok   ' : '  FEHL ') + meld.join('; '));
  }

  console.log(`6 Messung nach Gruppen (Seeds ${arg('gruppenSeeds') ? arg('gruppenSeeds') : '1–10'}, 730 Tage; nur gemessen, keine Regel liest diese Merkmale)`);
  {
    // Anteile je Wahl gemittelt (die Zahl der Wählbaren wächst mit der Stadt; Kinder der Stadt gibt es erst spät): wählbar, Anteil am Losgewicht
    // (1 + Freundschaften) × (1 + BM_EHRGEIZ × Ehrgeiz / 100) ohne den Amtsinhaber, dann Herausforderer und Gewählte wie gezählt
    const G = new Map(); const g = (n) => { if (!G.has(n)) G.set(n, { waehlbar: 0, los: 0, kand: 0, sieg: 0, offen: 0, freunde: 0, fn: 0 }); return G.get(n); };
    const gruppen = (S, p) => { const P = S.p, a = (S.tag - P.geb[p]) / J;
      return ['alle', P.elternA[p] >= 0 ? 'in der Stadt geboren' : 'zugezogen oder vom Start', P.nach[p] >= 30 && P.nach[p] <= 36 ? 'Nachnamen Kaya bis Kowalski (Liste 31–37)' : 'übrige Nachnamen',
        P.weib[p] ? 'Frauen' : 'Männer', a < 30 ? 'Alter 18–29' : a < 45 ? 'Alter 30–44' : 'Alter 45–64']; };
    let wahlen = 0, offeneWahlen = 0;
    mc.__wahl = (S, K, n, w, alt) => {
      wahlen++;
      const zahl = new Map(), los = new Map(); let alleZ = 0, alleL = 0;
      for (let p = 0; p < S.pMax; p++) if (M._bm.waehlbar(S, p)) { let fz = 0; for (let j = 0; j < 5; j++) if (S.p.freunde[p * 5 + j] >= 0) fz++;
        const w = p === alt ? 0 : (1 + fz) * (1 + R.BM_EHRGEIZ * S.p.ehrgeiz[p] / 100); alleZ++; alleL += w;
        for (const x of gruppen(S, p)) { zahl.set(x, (zahl.get(x) || 0) + 1); los.set(x, (los.get(x) || 0) + w); g(x).freunde += fz; g(x).fn++; } }
      for (const [x, z] of zahl) { g(x).waehlbar += z / alleZ; g(x).los += (los.get(x) || 0) / Math.max(1e-9, alleL); }
      for (const c of K) if (c !== alt) for (const x of gruppen(S, c)) g(x).kand++;          // Herausforderer (ohne Amtsinhaber)
      const s = n.indexOf(Math.max(...n)); for (const x of gruppen(S, K[s])) g(x).sieg++;
      if (!K.includes(alt)) { offeneWahlen++; for (const x of gruppen(S, K[s])) g(x).offen++; }
    };
    for (const seed of arg('gruppenSeeds', '1,2,3,4,5,6,7,8,9,10').split(',').map(Number)) { const S = M.neueStadt(seed); bis(M, S, 730); }
    mc.__wahl = null;
    const a = G.get('alle');
    console.log(`       ${wahlen} Wahlen (ohne Tag 0), davon ${offeneWahlen} ohne Amtsinhaber; Anteil an Wählbaren und am Losgewicht (je Wahl gemittelt), an`
      + ' Herausforderern (ohne Amtsinhaber), Gewählten und Gewählten ohne Amtsinhaber; Freundschaften je Wählbarem:');
    for (const n of ['alle', 'in der Stadt geboren', 'zugezogen oder vom Start', 'Nachnamen Kaya bis Kowalski (Liste 31–37)', 'übrige Nachnamen', 'Frauen', 'Männer', 'Alter 18–29', 'Alter 30–44', 'Alter 45–64']) {
      const x = G.get(n); if (!x) continue;
      const pz = (v, w) => (w ? (100 * v / w).toFixed(1) : '–').padStart(5);
      console.log(`       ${n.padEnd(44)} wählbar ${pz(x.waehlbar, a.waehlbar)} %  Los ${pz(x.los, a.los)} %  Herausforderer ${pz(x.kand, a.kand)} %  gewählt ${pz(x.sieg, a.sieg)} % (${x.sieg})`
        + `  ohne Amtsinhaber ${pz(x.offen, a.offen)} % (${x.offen})  Freunde ${(x.freunde / Math.max(1, x.fn)).toFixed(2)}`);
    }
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zum Bürgermeister bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('schule')) {
  // Schule (Version 9, Teil 2). A statisch: Regeln lesen nur Alter, Wohnung, Obhut, Schulplatz (Nummer, Generation), keine Namen, keinen
  // Charakter, keine Eltern, kein Geschlecht; kein Zufall; Budget nur in schuleBezahlen, schulITBestellen und dem Sachaufwand in wirtschaft().
  // B neue Städte (Seeds 1–3, 730 Tage), nach jeder Nacht: Plätze, Lehrkräfte, Geld, Lebenslauf, Bauamt erst ab einer Klasse, Stadtbuch, Kita,
  // Wehrdienst, Jugendstrafrecht, Autos, Grundregel (ortZurStunde), Karten. C IT-Ausstattung (Schnittstelle zum Haushalt), erzwungen. D Speichern
  // und Laden, beschädigte Stände. E Übernahme älterer Stände (Version 8, mit --git 7 bis 2). F Namenstausch. G ausgeschaltet. H Gruppen (nur gemessen)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, SCHULE = Sim.SCHULE;
  const simCode = (h) => h.match(/<script id="sim">([\s\S]*?)<\/script>/)[1];
  const lade = (code) => { const ctx = vm.createContext({}); vm.runInContext(`Math.random = () => { throw new Error('Math.random'); };`, ctx); vm.runInContext(code, ctx); return ctx.StadtSim; };
  const roh = (text) => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64');
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
  const speichern = (X, S) => speichernAlsText(X, S), laden = (X, text, migrieren) => X.importZustand(roh(text), migrieren);
  const abdruck = (X, S) => { const h = createHash('sha256'), d = X.exportZustand(S);
    for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
    h.update(JSON.stringify(d.werte)); h.update(JSON.stringify(d.json)); return h.digest('hex').slice(0, 16); };
  const bis = (X, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) X.stunde(S); };
  const artVon = (a) => (a < R.GRUNDSCHULE_BIS ? Sim.GRUNDSCHULE : Sim.WEITER);   // a: Alter in der Nacht der Vergabe
  const offenS = (S, b) => S.g.typ[b] === SCHULE && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === SCHULE;
  const abst = (S, b, c) => Math.abs(S.g.x[b] - S.g.x[c]) + Math.abs(S.g.y[b] - S.g.y[c]);

  console.log('A Statisch (Abschnitt „Schule“ im sim-Block, Bauamt Regel 7, Zweig „Schule“ in wirtschaft, ortZurStunde)');
  {
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const a = SIM_CODE.indexOf('// ─── Schule (Version 9, Teil 2)'), e = SIM_CODE.indexOf('// Ende Schule');
    const teil = SIM_CODE.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    pruef(a > 0 && e > a && !/\b(zufall|zInt|zufallSich|zufallAuto|wahlZufall)\s*\(/.test(teil), `Abschnitt gefunden (${teil.split('\n').length} Zeilen), kein Zufall`);
    const koerper = (f) => { const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return '';
      let t = 0, j = code.indexOf('{', i); for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; } return code.slice(i, j + 1); };
    const ohneBuch = (k) => { let out = '', i = 0;                 // Zeilen des Stadtbuchs (buch(S, …)) heraus: dort stehen Namen
      for (;;) { const j = k.indexOf('buch(S,', i); if (j < 0) { out += k.slice(i); break; } out += k.slice(i, j); let t = 0, m = j + 4;
        for (; m < k.length; m++) { if (k[m] === '(') t++; else if (k[m] === ')' && --t === 0) break; } i = m + 1; } return out; };
    const ba = koerper('bauamt'), r7a = ba.indexOf('if (sb) for (const art of [GRUNDSCHULE, WEITER])'), r7e = ba.indexOf('Die Notbremse');
    const zweig = code.slice(code.indexOf('    if (t === SCHULE) {'), code.indexOf('    if (istLand(t)) {'));
    // Je Regel die Personenfelder, die sie lesen darf (Anzeige ausgenommen: schulKarte, schuleInfo, schulStand lesen nur für Karten)
    const ERLAUBT = { schulTag: ['geb', 'gen', 'lebt', 'schule'], kindWohnung: ['gen', 'lebt', 'obhut', 'obhutBei', 'obhutGen', 'wohnung'], schulOrt: ['schule'],
      kindOrt: [], klasseVon: ['geb'], schulStelleFrei: [], schulITSoll: [], schulITBestand: [], itLieferanten: [], schulITBedarf: [], schulITBestellen: [],
      schuleBezahlen: [], migriereSchule: [], schulStartZeile: [], klasseGroesse: [], kinderJeLehrkraft: [], schulPlaetze: [], schulOffen: [] };
    const teile = Object.fromEntries(Object.keys(ERLAUBT).map(f => [f, koerper(f)]));
    teile.regel7 = r7a > 0 ? ba.slice(r7a, r7e) : ''; ERLAUBT.regel7 = [];
    teile.wirtschaftSchule = zweig; ERLAUBT.wirtschaftSchule = ['frei', 'geld'];   // Lohn an Anwesende (wie jeder Betrieb)
    const zuViel = [];
    for (const [f, k0] of Object.entries(teile)) {
      if (!k0) { zuViel.push(f + ': fehlt'); continue; }
      const k = ohneBuch(k0);
      for (const m of k.matchAll(/\b(?:S\.)?P\.(\w+)|\bS\.p\.(\w+)/g)) { const x = m[1] || m[2]; if (!ERLAUBT[f].includes(x)) zuViel.push(`${f}: P.${x}`); }
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo)\s*\(|NACHNAMEN|VORNAMEN|\.weib\b|\.einzug\b|\.eltern|\.ehrgeiz\b|\.heimat\b|\.fleiss\b|\.spar\b|\.gesellig\b|\.mem/.test(k)) zuViel.push(f + ': Name, Charakter, Eltern oder Gedächtnis');
    }
    pruef(!zuViel.length, `Regeln lesen nur ihre Personenfelder (${Object.keys(teile).length} Stellen: Alter, Wohnung, Obhut, Schulplatz, Nummer und Generation), keine Namen, keinen Charakter, keine Eltern, kein Geschlecht (Stadtbuch-Zeilen ausgenommen)`
      + (zuViel.length ? ': ' + [...new Set(zuViel)].join(', ') : ''));
    const geldTeil = [...teil.matchAll(/S\.budget\s*[-+]?=/g)].length, geldR7 = [...teile.regel7.matchAll(/S\.budget\s*[-+]?=/g)].length, geldZweig = [...zweig.matchAll(/S\.budget\s*[-+]?=/g)].length;
    // Teil 5: schulITKaufen (wie die Leute aus einem Laden der Stadt): Kauf und der Anteil des Ladens der Stadt, je mit Buchung
    pruef(geldTeil === 4 && /function schuleBezahlen\(S, k\) \{ S\.budget -= k;/.test(teil) && (teil.match(/S\.budget -= aus\.taler; hhBuch\(S, HK\.COMPUTER, -aus\.taler\);/g) || []).length === 2
      && /if \(stadtLaden\) \{ S\.budget \+= stadtLaden; hhBuch\(S, HK\.BETRIEBE, stadtLaden\); \}/.test(teil) && geldR7 === 0 && /schuleBezahlen\(S, preis\)/.test(teile.regel7)
      && geldZweig === 1 && /S\.budget -= sach;/.test(zweig) && !/lohn[^;]*S\.budget|S\.budget[^;]*lohn/.test(zweig),
      `Budget: im Abschnitt nur schuleBezahlen, schulITBestellen und schulITKaufen (${geldTeil}; der Anteil des Ladens der Stadt kommt zurück), Regel 7 über schuleBezahlen (${geldR7} direkte Stellen), wirtschaft nur der Sachaufwand (${geldZweig}); Löhne der Lehrkräfte vom Land`);
    const oz = koerper('ortZurStunde');
    pruef(/if \(P\.schule\[p\] \|\| S\.tag - P\.geb\[p\] < R\.ERWACHSEN \* R\.JAHR\) return kindOrt\(S, p, H\);/.test(oz) && oz.indexOf('kindOrt') > oz.indexOf('haftBis') && oz.indexOf('kindOrt') < oz.indexOf('arbeitet'),
      'ortZurStunde: Kinder (Alter wie in stunde(), Schulplatz am 18. Geburtstag) über kindOrt, nach der Haft, vor der Arbeit');
  }

  // Messkopie: Stand direkt vor wirtschaft() (Schüler der letzten Nacht, Löhne der Anwesenden) und vor bauamt() (Kinder ohne Platz)
  const { Sim: M, ctx: mc } = ladeSimMit([['function wirtschaft(S) {\n', 'function wirtschaft(S) {\n  if (globalThis.__vorW) globalThis.__vorW(S);\n'],
    ['function bauamt(S, kb, sb) {\n', 'function bauamt(S, kb, sb) {\n  if (globalThis.__vorB) globalThis.__vorB(S, sb);\n'],
    ['  const sb = R.SCHULEN ? schulTag(S) : null;', '  const sb = R.SCHULEN ? schulTag(S) : null;\n  if (globalThis.__nachS) globalThis.__nachS(S);']]);
  const seeds = arg('seeds', '1,2,3').split(',').map(Number), tage = Number(arg('tage', '730'));
  console.log(`B Neue Städte (Seeds ${seeds.join(', ')}, je ${tage} Tage stündlich), Prüfung nach jeder Nacht`);
  const alleMess = [];
  for (const seed of seeds) {
    const S = M.neueStadt(seed), f = {}, F = (k, n = 1) => { f[k] = (f[k] || 0) + n; };
    let vor = null, fehltVor = null, naechte = 0, karten = 0, jahrZeilen = 0, buchNr = S.buchNr, einOk = 0, abOk = 0, gebautVor = 0, grund = 0, bauZeilen = 0;
    const erst = { gs: -1, ws: -1 }, stunden = { schule: 0, heim: 0, erw: 0 };
    mc.__vorW = (X) => { vor = []; for (let b = 0; b < X.gAnzahl; b++) if (X.g.typ[b] === SCHULE && X.feld[X.g.y[b] * X.karte + X.g.x[b]] === SCHULE) {
      let l = 0; for (const w of X.belegschaft[b]) if (!X.p.frei[w]) l += X.g.lohn[b]; vor.push([b, X.g.bedient[b], l, X.budget]); } };
    mc.__vorB = (X, sb) => { fehltVor = sb ? [sb.fehlt[1].length, sb.fehlt[2].length] : null; };
    // Direkt nach schulTag (Plätze gelten ab hier; spätere Schritte der Nacht wie Obhut oder Wegzug ändern Wohnungen, das holt die nächste Nacht nach)
    mc.__nachS = (X) => {
      const P = X.p, g = X.g, frei = new Map();
      for (let b = 0; b < X.gAnzahl; b++) {
        if (g.typ[b] !== SCHULE || !offenS(X, b)) continue;
        let n = 0; for (let k = 0; k < X.pMax; k++) if (P.lebt[k] && P.schule[k] === b + 1) n++;
        if (n !== g.bedient[b]) F('zaehler');
        if (g.kapaz[b] !== M._schule.schulPlaetze(g.stufe[b]) || n > g.kapaz[b]) F('kapazitaet');
        if (g.soll[b] !== (n ? Math.ceil(n / M._schule.kinderJeLehrkraft(g.stufe[b]) - 1e-9) : 0)) F('lehrkraefte');
        frei.set(b, g.kapaz[b] - n);
      }
      for (let k = 0; k < X.pMax; k++) {
        if (!P.lebt[k]) continue;
        const a = X.tag - P.geb[k], b = P.schule[k] - 1, art = artVon(a), w = M.kindWohnung(X, k);
        if (b >= 0) {
          if (a < R.SCHULE_AB || a >= R.SCHULE_BIS) F('alter');
          if (!offenS(X, b)) F('keineOffeneSchule');
          if (g.stufe[b] !== art) F('falscheArt');
          if (w < 0 || abst(X, b, w) > R.REICH_SCHULE[art]) F('reichweite');
        } else if (a >= R.SCHULE_AB && a < R.SCHULE_BIS && w >= 0) {
          for (const [s, fr] of frei) if (fr > 0 && g.stufe[s] === art && abst(X, s, w) <= R.REICH_SCHULE[art]) { F('ohnePlatzTrotzFrei'); break; }
        }
      }
    };
    const altOrt = (X, p, H) => { const P = X.p, w = P.wohnung[p], arb = P.arbeit[p], bes = P.besuch[p], st = P.stammladen[p];   // ortZurStunde ohne Schule (Version 8)
      if (P.haftBis[p]) return M.imHof(X, p, H) ? X.sicherheit.jva : -1;
      const arbeitet = arb >= 0 && !P.frei[p];
      if (arbeitet && H >= 8 && H < 17) return P.einsatz[p] ? P.einsatz[p] - 1 : arb;
      if (bes >= 0 && bes !== w && H >= 19 && H < 22) return bes;
      if (!arbeitet && st >= 0 && H === 10) return st;
      return w; };
    for (let d = 0; d < tage; d++) {
      const sach0 = S.stat.schule.sach, lohn0 = S.stat.schule.lohn, P0 = S.p, sechs = [], achtzehn = [];
      for (let p = 0; p < S.pMax; p++) if (P0.lebt[p]) { const a = S.tag - P0.geb[p]; if (a === R.SCHULE_AB) sechs.push([p, P0.gen[p]]); if (a === R.SCHULE_BIS) achtzehn.push([p, P0.gen[p]]); }
      // Grundregel (jede Stunde eines Tages im Monat): Schulkinder 8–13 Uhr in ihrer Schule, sonst wo sie wohnen; Erwachsene wie in Version 8
      const stundlich = d % 30 === 15;
      while (S.stunde !== 23) {
        if (stundlich) {
          const P = S.p, H = S.stunde;
          for (let p = 0; p < S.pMax; p++) {
            if (!P.lebt[p]) continue;
            const a = S.tag - P.geb[p], o = M.ortZurStunde(S, p, H);
            if (P.schule[p] || a < R.ERWACHSEN * J) {
              const b = P.schule[p] - 1, soll = b >= 0 && H >= 8 && H < 13 && offenS(S, b) ? b : M.kindWohnung(S, p);
              if (o !== soll) F('grundregelKind');
              if (b >= 0 && H >= 8 && H < 13) stunden.schule++; else stunden.heim++;
              if (P.auto[p] || M.mitAuto(S, p, P.wohnung[p], o)) F('kindImAuto');
            } else { if (o !== altOrt(S, p, H)) F('grundregelErwachsen'); stunden.erw++; }
          }
        }
        M.stunde(S);
      }
      M.stunde(S); naechte++;                                // Mitternacht: Tagesabschluss
      const P = S.p, g = S.g, st = S.stat.schule;
      // Geld dieser Nacht: Sachaufwand 2,7 je Schüler der letzten Nacht aus dem Budget (höchstens was da ist), Löhne der Anwesenden vom Land
      let sachSoll = 0, lohnSoll = 0, knapp = false;
      for (const [, n, l, bud] of vor || []) { sachSoll += Math.round(R.SACH_JE_SCHUELER * n); lohnSoll += l; if (bud < sachSoll + 1e4) knapp = true; }
      if (knapp) grund++; else if (st.sach - sach0 !== sachSoll) F('sachaufwand');
      if (st.lohn - lohn0 !== lohnSoll) F('lohnVomLand');
      // Plätze, Zähler, Kapazität, Lehrkräfte
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== SCHULE) continue;
        const art = g.stufe[b];
        if (art !== 1 && art !== 2) F('schulart');
        if (g.besitzer[b] !== -1 || g.leer[b] || g.lohn[b] !== R.LOHN_LEHRKRAFT) F('gebaeude');
        if (!offenS(S, b)) { if (g.bedient[b] || g.kapaz[b]) F('bauMitPlatz'); continue; }
        if (art === 1 && erst.gs < 0) erst.gs = S.tag; if (art === 2 && erst.ws < 0) erst.ws = S.tag;
        for (const w of S.belegschaft[b]) if (P.arbeit[w] !== b || S.tag - P.geb[w] < R.ERWACHSEN * J || P.haftBis[w]) F('belegschaft');
      }
      for (let k = 0; k < S.pMax; k++) {
        if (!P.lebt[k]) continue;
        const a = S.tag - P.geb[k], b = P.schule[k] - 1;     // a: Alter heute (nach der Nacht); vergeben wurde mit a − 1
        if (b >= 0) {
          if (a <= R.SCHULE_AB || a > R.SCHULE_BIS) F('alter');
          if (!offenS(S, b)) F('keineOffeneSchule');
          if (P.kita[k]) F('kitaUndSchule');
          if (P.arbeit[k] >= 0 || P.besitz[k] >= 0 || P.bund[k] || P.haftBis[k] || S.sicherheit.verfahren.some(v => v.id === k && v.gen === P.gen[k])) F('arbeitDienstHaft');
        }
        if (a < R.ERWACHSEN * J && (P.auto[k] || P.haftBis[k] || P.bund[k])) F('kindAutoHaftDienst');   // Kinder: kein Auto, keine Haft (Taten nur ab 18), kein Dienst
      }
      // Lebenslauf: Einschulung in der Nacht des 6., Abschluss in der Nacht des 18. Geburtstags
      const hat = (p, code) => { for (let j = 0; j < R.MEM; j++) { const i = p * R.MEM + j; if (P.memCode[i] === code && P.memTag[i] === S.tag - 1) return true; } return false; };
      for (const [p, gn] of sechs) { if (!P.lebt[p] || P.gen[p] !== gn) continue; if (hat(p, M.M.SCHULE_EIN)) einOk++; else F('einschulung'); }
      for (const [p, gn] of achtzehn) { if (!P.lebt[p] || P.gen[p] !== gn) continue; if (hat(p, M.M.SCHULE_AB)) abOk++; else F('abschluss'); }
      // Bauamt Regel 7: gebaut wird nur mit mindestens SCHUL_MIN Kindern ohne Platz in Reichweite des neuen Hauses; je Art eine Baustelle
      if (st.gebaut > gebautVor) {
        for (const b of S.baustellen) {
          if (g.typ[b] !== SCHULE || g.seit[b] !== S.tag - 1) continue;
          const art = g.stufe[b];
          let nah = 0;
          for (let k = 0; k < S.pMax; k++) { if (!P.lebt[k] || P.schule[k]) continue; const a = S.tag - P.geb[k], w = M.kindWohnung(S, k);
            if (a > R.SCHULE_AB && a <= R.SCHULE_BIS && artVon(a - 1) === art && w >= 0 && abst(S, b, w) <= R.REICH_SCHULE[art]) nah++; }
          // Haushalt (Teil 3): Schulen baut nur das Bauamt (Noahs Entscheidung: ab einer ganzen Klasse); jede neue Schule hat ihre Zeile im Stadtbuch
          const ort = M.gebaeudeInfo(S, b).ort, zeile = S.buch.find(e => e.nr > buchNr && e.art === 'bauamt' && /Schule/.test(e.text) && e.text.includes(ort));
          if (!zeile || /Vorhaben aus dem Haushalt/.test(zeile.text)) F('bauOhneZeile');
          if (nah < R.SCHUL_MIN[art] || !fehltVor || fehltVor[art - 1] < R.SCHUL_MIN[art]) F('gebautOhneKlasse');
          if (S.baustellen.filter(x => g.typ[x] === SCHULE && g.stufe[x] === art).length > 1) F('zweiBaustellen');
        }
        gebautVor = st.gebaut;
      }
      // Stadtbuch: höchstens eine Schulzeile je Schuljahr, am letzten Tag; Bauzeilen nennen eine Zahl ≥ Mindestzahl
      for (const e of S.buch) if (e.nr > buchNr) {
        if (e.art === 'schule') { jahrZeilen++; if ((e.tag + 1) % J !== 0) F('zeilenTag'); }
        if (e.art === 'bauamt' && /Schule/.test(e.text)) { bauZeilen++; const m = /haben (\d+) Kinder keinen Platz/.exec(e.text); if (!m || +m[1] < R.SCHUL_MIN[/Grundschule/.test(e.text) ? 1 : 2]) F('bauZeile'); }
      }
      buchNr = S.buchNr;
      // Computer: Bedarf = Soll − Bestand je offener Schule, Lieferanten = offene Computerfirmen der Stadt
      if (d % 10 === 0) {
        const it = M.schulITBedarf(S); let n = 0;
        for (let b = 0; b < S.gAnzahl; b++) if (offenS(S, b)) n += Math.max(0, Math.ceil(S.belegschaft[b].length * R.IT_JE_LEHRKRAFT + g.bedient[b] * R.IT_JE_SCHUELER[g.stufe[b]] - 1e-9) - M._schule.schulITBestand(S, b));
        let l = 0; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === M.TECH && g.produkt[b] === M.COMPUTER && !g.werk[b] && g.version[b] > 0 && S.feld[g.y[b] * S.karte + g.x[b]] === M.TECH && !g.leer[b]) l++;
        if (it.geraete !== n || it.lieferanten !== l || it.taler !== n * R.PREIS[M.COMPUTER]) F('itBedarf');
      }
      // Karten ohne Fehler (alle 20 Tage)
      if (S.tag % 20 === 0) {
        try {
          for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === SCHULE) { const i = M.gebaeudeInfo(S, b); if (!i.titel || /undefined|NaN/.test(JSON.stringify(i))) F('hauskarte'); karten++; }
          for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && S.tag - P.geb[p] <= R.SCHULE_BIS) { const i = M.personInfo(S, p); if (/undefined|NaN/.test(i.arbeit + JSON.stringify(i.schule) + JSON.stringify(i.gedaechtnis))) F('personenkarte'); karten++; }
          if (/NaN|undefined/.test(JSON.stringify(M.regierungInfo(S).schule))) F('fenster');
        } catch (e) { F('ausnahme: ' + e.message); }
      }
    }
    const s = S.stat.schule, i = M.schuleInfo(S);
    pruef(!Object.keys(f).length, `Seed ${seed}, ${naechte} Nächte: Plätze direkt nach der Vergabe (Alter, Art, offene Schule, Reichweite, Kapazität, Zähler), ohne Platz nur ohne freien Platz in Reichweite, Lehrkräfte nach Formel, `
      + `Sachaufwand und Löhne vom Land je Nacht, kein Kind mit Kita und Schule, Stelle, Dienst, Haft, Verfahren oder Auto, Bau nur ab einer Klasse (${bauZeilen} Bauzeilen), `
      + `Grundregel (${stunden.schule} Schul-, ${stunden.heim} Heim- und ${stunden.erw} Erwachsenenstunden), Computerbedarf`
      + (grund ? ` (${grund}-mal reichte das Budget nicht ganz, dann zählt der Sachaufwand nicht)` : '') + (Object.keys(f).length ? ': ' + JSON.stringify(f) : ''));
    pruef(einOk > 0 && abOk > 0 && einOk === s.eingeschult && abOk === s.abschluesse, `Lebenslauf: ${einOk} Einschulungen am 6. und ${abOk} Abschlüsse am 18. Geburtstag (Summen ${s.eingeschult} / ${s.abschluesse})`);
    pruef(jahrZeilen > 0 && jahrZeilen <= Math.ceil(tage / J) && karten > 0, `Stadtbuch: ${jahrZeilen} Schulzeilen in ${tage} Tagen (je Schuljahr höchstens eine); erste Grundschule offen an Tag ${erst.gs}, `
      + `erste weiterführende an Tag ${erst.ws}; an Tag ${S.tag} ${i.offen[1]} + ${i.offen[2]} Schulen, ${i.schueler[1]} + ${i.schueler[2]} Schüler, ${i.nachbarort} im Nachbarort, ${i.lehrkraefte} Lehrkräfte (Bedarf ${i.bedarf}); ${karten} Karten ohne Fehler`);
    alleMess.push({ seed, erst, i, s });
  }
  delete mc.__vorW; delete mc.__vorB; delete mc.__nachS;

  console.log('C Computer für die Schulen (Schnittstelle zum Haushalt, erzwungen; seit Teil 5 wie die Leute aus einem Laden der Stadt, sonst von außerhalb)');
  {
    // Haushalt (Teil 3): Vorhaben aus, sonst kaufte er die Computer jede Nacht selbst und es bliebe kein Bedarf für die erzwungene Bestellung
    // (seine Käufe prüft --haushalt)
    const hhAlt = R.HH_VORHABEN; R.HH_VORHABEN = 0;
    const S = Sim.neueStadt(1);
    let t = 300; bis(Sim, S, t, 12);
    while ((Sim.schulITBedarf(S).geraete < 6 || Sim.schulITBedarf(S).regal < 0) && S.tag < 700) { t += 10; bis(Sim, S, t, 12); }
    const B0 = Sim.schulITBedarf(S), preis = R.PREIS[Sim.COMPUTER], anteil = Math.round(preis * R.LADEN_ANTEIL), text = speichern(Sim, S), f = B0.regal, g = S.g;
    const kassen = () => { let k = 0; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.LADEN) k += g.kasse[b]; return k; };
    const um0 = g.umsatz[f], bud0 = S.budget, k0 = kassen(), st0 = { ...S.stat.schule };
    const n0 = Sim.schulITBestellen(S, 0), n1 = Sim.schulITBestellen(S, preis - 1);
    pruef(B0.geraete >= 6 && f >= 0 && !n0.geraete && !n1.geraete && S.budget === bud0, `Seed 1, Tag ${S.tag}: Bedarf ${B0.geraete} Computer (${B0.taler} Taler), im Regal der neueste von Firma ${f}; für 0 oder weniger als einen Preis wird nichts bestellt`);
    const r1 = Sim.schulITBestellen(S, 3 * preis + 5), B1 = Sim.schulITBedarf(S), stadt = S.budget - (bud0 - 3 * preis), laeden = kassen() - k0;
    pruef(r1.geraete === 3 && r1.taler === 3 * preis && !r1.aussen && g.umsatz[f] - um0 === 3 * (preis - anteil) && stadt + laeden === 3 * anteil && stadt >= 0 && laeden >= 0
      && B1.geraete === B0.geraete - 3 && S.stat.schule.it === st0.it + 3 * preis && S.stat.schule.itGeraete === st0.itGeraete + 3 && S.stat.schule.itAussen === st0.itAussen
      && r1.firmen.length === 1 && r1.firmen[0][0] === f && r1.firmen[0][1] === 3,
      `3 Computer für ${r1.taler} Taler im Laden: Budget −${bud0 - S.budget}, Firma +${g.umsatz[f] - um0} (Umsatz), Läden +${laeden}, Laden der Stadt +${stadt} (Anteil ${anteil} je Gerät), Bedarf ${B0.geraete} → ${B1.geraete}, Summen gezählt`);
    const r2 = Sim.schulITBestellen(S, 1e9), B2 = Sim.schulITBedarf(S), r3 = Sim.schulITBestellen(S, 1e9);
    pruef(r2.geraete === B1.geraete && B2.geraete === 0 && !r3.geraete, `Rest: ${r2.geraete} Computer, danach Bedarf 0 und keine Bestellung mehr (nie mehr, als die Schulen brauchen)`);
    const K = laden(Sim, text); budgetSetzen(K, 2.5 * preis);
    const r4 = Sim.schulITBestellen(K, 1e9);
    pruef(r4.geraete === 2 && K.budget >= 0.5 * preis && K.budget <= 0.5 * preis + 2 * anteil, `wenig Budget (${2.5 * preis} Taler): ${r4.geraete} Computer, ${K.budget} Taler bleiben (nie unter 0; der Anteil des Ladens der Stadt kommt zurück)`);
    const K2 = laden(Sim, text); K2.angebot[Sim.COMPUTER] = -1;
    const b5 = K2.budget, a5 = K2.stat.schule.itAussen, r5 = Sim.schulITBestellen(K2, 3 * preis), um5 = K2.g.umsatz.slice(0, K2.gAnzahl).reduce((x, y) => x + y, 0), um5a = laden(Sim, text).g.umsatz.slice(0, K2.gAnzahl).reduce((x, y) => x + y, 0);
    pruef(r5.geraete === 3 && r5.aussen === 3 && K2.budget === b5 - 3 * preis && K2.stat.schule.itAussen === a5 + 3 && um5 === um5a && !r5.firmen.length,
      'ohne Computer einer Firma der Stadt im Regal: von außerhalb (3 Computer, Budget −' + (b5 - K2.budget) + ', kein Umsatz in der Stadt, als „von außerhalb“ gezählt)');
    const K3 = laden(Sim, text), K4 = laden(Sim, text), r6 = Sim.schulITBestellen(K3, 10 * preis), r7 = Sim.schulITBestellen(K4, 10 * preis);
    bis(Sim, K3, K3.tag + 1); bis(Sim, K4, K4.tag + 1);
    pruef(JSON.stringify(r6) === JSON.stringify(r7) && abdruck(Sim, K3) === abdruck(Sim, K4) && K3.g.umsatz[f] === 0, `gleich bestellt, gleich weiter (${abdruck(Sim, K3)}); der Umsatz ist in der Nacht verbucht`);
    const L2 = laden(Sim, speichern(Sim, S)); bis(Sim, S, S.tag + 10); bis(Sim, L2, L2.tag + 10);
    pruef(S.schule.it.length > 0 && abdruck(Sim, S) === abdruck(Sim, L2), `gespeichert mit ${S.schule.it.length} Lieferungen: 10 Tage bitgleich`);
    const tLief = S.tag - 10; bis(Sim, S, tLief + R.IT_ALT + 1);
    pruef(!S.schule.it.some(([, , t]) => t <= tLief) && Sim.schulITBedarf(S).geraete > 0, `nach ${R.IT_ALT} Tagen ausgemustert: keine Lieferung von Tag ${tLief} mehr, Bedarf wieder ${Sim.schulITBedarf(S).geraete}`);
    R.HH_VORHABEN = hhAlt;
  }

  console.log('D Speichern und Laden, beschädigte Stände');
  {
    const S = Sim.neueStadt(2);
    bis(Sim, S, 330, 13);
    let plaetze = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.p.schule[p]) plaetze++;
    const text = speichern(Sim, S), L = laden(Sim, text), gleich0 = abdruck(Sim, S) === abdruck(Sim, L);
    bis(Sim, S, 350); bis(Sim, L, 350);
    pruef(gleich0 && plaetze > 0 && abdruck(Sim, S) === abdruck(Sim, L), `Seed 2, gespeichert an Tag 330 um 13 Uhr mit ${plaetze} Schulplätzen: gleich nach dem Laden, 20 Tage weiter bitgleich (${abdruck(Sim, S)})`);
    const kaputt = (fn) => { const d = JSON.parse(text); fn(d); try { laden(Sim, JSON.stringify(d)); return 'geladen'; } catch (e) { return e.message; } };
    const feld = (d, n, T, fn) => { const a = d.arrays.find(x => x.name === n), u8 = Buffer.from(a.b64, 'base64'), u = new T(u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)); fn(u); a.b64 = Buffer.from(u.buffer).toString('base64'); };
    const faelle = [
      ['Schulplatz in einem Wohnhaus', /Schulplatz$/, (d) => { let k = -1; feld(d, 'p.lebt', Uint8Array, (l) => { k = l.findIndex(v => v); }); feld(d, 'p.schule', Uint16Array, (u) => { u[k] = 1; }); }],
      ['Summe fehlt', /Schul-Statistik$/, (d) => { delete d.json.stat.schule.lohn; }],
      ['Schuljahr kaputt', /: Schule$/, (d) => { d.json.schule.jahr.ein = 'x'; }],
      ['Computer an einem Wohnhaus', /Computer der Schulen$/, (d) => { d.json.schule.it.push([0, 3, 100]); }],
      ['Computer in der Zukunft', /Computer der Schulen$/, (d) => { const b = d.arrays.find(x => x.name === 'g.typ'); const u8 = Buffer.from(b.b64, 'base64'); const s = [...u8].findIndex(v => v === SCHULE); d.json.schule.it.push([s, 3, 99999]); }],
      ['Schulart 3', /Schulart$/, (d) => { let s = -1; feld(d, 'g.typ', Uint8Array, (u) => { s = u.findIndex(v => v === SCHULE); }); feld(d, 'g.stufe', Uint8Array, (u) => { u[s] = 3; }); }],
      ['Schule fehlt (Version 9)', /: Schule$/, (d) => { delete d.json.schule; }],
      ['Schulplätze fehlen (Version 9)', /unvollständig: p\.schule$/, (d) => { d.arrays = d.arrays.filter(a => a.name !== 'p.schule'); }],
    ];
    const erg = faelle.map(([n, re, fn]) => [n, kaputt(fn), re]);
    pruef(erg.every(([, m, re]) => re.test(m)), `${erg.length} beschädigte Stände abgelehnt: ` + erg.map(([n, m]) => `${n}: „${m}“`).join('; '));
  }

  console.log('E Übernahme älterer Stände (Schulen und Rathaus eingeschaltet)');
  {
    const quellen = [['Version 8 (stadt.orig.html)', readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8'), [[1, 300, 13], [3, 420, 5], [2, 700, 20], [4, 60, 9]]]];
    if (arg('git')) for (const [c, v] of [['ffa1d88', 7], ['bc7247a', 6], ['414ebab', 5], ['1c8d40b', 4], ['2b821c2', 3], ['39c405b', 2]])
      quellen.push([`Version ${v} (git ${c})`, execFileSync('git', ['show', c + ':stadt/stadt.html'], { cwd: arg('git'), encoding: 'utf8', maxBuffer: 1 << 26 }), v >= 7 ? [[1, 300, 13], [3, 420, 5]] : [[1, 300, 13]]]);
    else console.log('  (ohne --git: nur Version 8)');
    for (const [herkunft, altHtml, staende] of quellen) {
      const Alt = lade(simCode(altHtml));
      console.log(` ${herkunft}`);
      for (const [seed, tag, stunde] of staende) {
        const A = Alt.neueStadt(seed);
        bis(Alt, A, tag, stunde);
        const S = laden(Sim, speichern(Alt, A), true), neu = S.buch.slice(A.buch.length >= R.BUCH_MAX ? 0 : A.buch.length);
        const iz = S.buch.findIndex(e => e.art === 'schule' && e.tag === tag && /^Ab heute baut die Stadt Schulen/.test(e.text)), ir = S.buch.findIndex(e => e.art === 'rathaus' && e.tag === tag);
        let kinder = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p]) { const a = S.tag - S.p.geb[p]; if (a > R.SCHULE_AB && a <= R.SCHULE_BIS) kinder++; }
        pruef(iz >= 0 && ir > iz && S.buch.filter(e => e.art === 'schule').length === 1 + A.buch.filter(e => e.art === 'schule').length && S.schule.start === tag
          && Object.values(S.stat.schule).every(v => v === 0) && S.p.schule.every(v => v === 0) && S.schule.gestern === null && S.version === Sim.VERSION,
          `Seed ${seed}, Tag ${tag} (${A.einwohner} Einw.): Zeile „${Sim.klartext(S.buch[iz] ? S.buch[iz].text : '').slice(0, 44)}…“ vor denen des Rathauses (${neu.length} neue Zeilen), Summen 0, ${kinder} Schulkinder noch ohne Platz`);
        bis(Sim, S, S.tag + 1);
        const i1 = Sim.schuleInfo(S);
        kinder = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p]) { const a = S.tag - S.p.geb[p]; if (a > R.SCHULE_AB && a <= R.SCHULE_BIS) kinder++; }
        bis(Sim, S, S.tag + 60);
        const i = Sim.schuleInfo(S), L = laden(Sim, speichern(Sim, S)), rohT = JSON.stringify([i, Sim.kennzahlen(S)]);
        bis(Sim, S, S.tag + 5); bis(Sim, L, L.tag + 5);
        const genug = i1.nachbarort >= R.SCHUL_MIN[1];
        pruef(i1.nachbarort + i1.aussen === kinder && (!genug || i.offen[1] + i.bau[1] + i.offen[2] + i.bau[2] > 0) && !/NaN/.test(rohT) && abdruck(Sim, L) === abdruck(Sim, S),
          `erste Nacht ${i1.nachbarort} im Nachbarort; nach 60 Tagen ${i.offen[1]} + ${i.offen[2]} Schulen offen, ${i.bau[1] + i.bau[2]} im Bau, ${i.schueler[1] + i.schueler[2]} Schüler, ${i.nachbarort} im Nachbarort; ohne NaN; gespeichert und geladen gleich`);
      }
    }
  }

  console.log('F Namenstausch');
  {
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(1), B = T.neueStadt(1);
    bis(Sim, A, 400); bis(T, B, 400);
    const h = (X, S) => { const x = createHash('sha256');
      for (const a of X.exportZustand(S).arrays.sort((p, q) => (p.name < q.name ? -1 : 1))) { x.update(a.name); x.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
      x.update(JSON.stringify(S.stat)); x.update(JSON.stringify(S.schule)); x.update(String(S.budget) + '/' + S.rs); x.update(S.buch.map(e => e.art).join()); return x.digest('hex').slice(0, 16); };
    pruef(Sim.name(A, 3) !== T.name(B, 3) && h(Sim, A) === h(T, B) && A.stat.schule.eingeschult > 0,
      `„${Sim.name(A, 3)}“ heißt dort „${T.name(B, 3)}“; 400 Tage gleich (Felder, Summen, Zufall, Budget, Arten der Zeilen, ${h(Sim, A)}), ${A.stat.schule.eingeschult} Einschulungen`);
  }

  console.log('G Ausgeschaltet');
  {
    const alt = R.SCHULEN; R.SCHULEN = 0;
    const S = Sim.neueStadt(2); bis(Sim, S, 400);
    let kind = 0, falsch = 0; for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] < R.ERWACHSEN * J) { kind++; for (const H of [9, 10, 20]) if (Sim.ortZurStunde(S, p, H) !== Sim.kindWohnung(S, p)) falsch++; }
    pruef(!Sim.schuleInfo(S).offen[1] && !S.stat.schule.gebaut && S.p.schule.every(v => v === 0) && !S.buch.some(e => e.art === 'schule') && !falsch && kind > 0,
      `R.SCHULEN = 0 (Seed 2, 400 Tage): keine Schule, kein Schulplatz, keine Zeile; ${kind} Kinder immer dort, wo sie wohnen`);
    R.SCHULEN = alt;
    // Mit Schulen und Rathaus aus: Tag für Tag wie Version 8 (wie --rathaus H), hier nur Seed 3 und 200 Tage
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const altR = R.RATHAUS, altH = [R.HH_VORHABEN, R.HH_STEUER]; R.RATHAUS = 0; R.SCHULEN = 0; R.HH_VORHABEN = 0; R.HH_STEUER = 0;   // Haushalt: nur Buchführung
    const altA = R.ANLAUF_STUFE; R.ANLAUF_STUFE = 0;         // Wachstum (Teil 4): ohne Anlauf
    const altT = [R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU]; R.TECH_FRUEH = 0; R.WELT = 0; R.ZUZUG_GENAU = 0;   // Teil 5: ohne Tech früher und Weltmarkt; Zuzug wie vorher (Schlussprüfung)
    const A = V8.neueStadt(3), B = Sim.neueStadt(3); let erster = -1;
    const spur = (X, S) => { const k = X.kennzahlen(S); return JSON.stringify([k.einwohner, k.budget, k.freieStellen, k.zufriedenheit, S.rs, S.buchNr, S.buch.slice(-3).map(e => e.text)]); };
    for (let d = 1; d <= 200 && erster < 0; d++) { bis(V8, A, d); bis(Sim, B, d); if (spur(V8, A) !== spur(Sim, B)) erster = d; }
    R.RATHAUS = altR; R.SCHULEN = alt; [R.HH_VORHABEN, R.HH_STEUER] = altH; R.ANLAUF_STUFE = altA; [R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU] = altT;
    pruef(erster < 0, `R.SCHULEN = 0 und R.RATHAUS = 0, Haushalt nur Buchführung, ohne Anlauf, ohne Tech früher und Weltmarkt (Seed 3): 200 Tage jeden Tag wie Version 8${erster < 0 ? '' : ', VERSCHIEDEN ab Tag ' + erster}`);
  }

  console.log('H Gruppen (nur gemessen; keine Regel liest diese Merkmale): Schülertage in der Stadt und im Nachbarort');
  {
    const gr = {}, add = (n, platz) => { const x = gr[n] || (gr[n] = { platz: 0, nb: 0 }); if (platz) x.platz++; else x.nb++; };
    for (const seed of seeds.slice(0, 3)) {
      const S = Sim.neueStadt(seed);
      for (let d = 0; d < 730; d++) {
        bis(Sim, S, S.tag + 1);
        if (d % 5) continue;
        const P = S.p;
        for (let k = 0; k < S.pMax; k++) {
          if (!P.lebt[k]) continue;
          const a = S.tag - P.geb[k];
          if (a <= R.SCHULE_AB || a > R.SCHULE_BIS || Sim.kindWohnung(S, k) < 0) continue;
          const platz = P.schule[k] > 0;
          add('alle', platz); add(P.weib[k] ? 'Mädchen' : 'Jungen', platz); add(P.nach[k] >= 30 && P.nach[k] <= 36 ? 'Nachnamen Kaya bis Kowalski (Liste 31–37)' : 'übrige Nachnamen', platz);
        }
      }
    }
    for (const [n, x] of Object.entries(gr)) console.log(`  ${n.padEnd(44)} ${String(x.platz + x.nb).padStart(7)} Schülertage, im Nachbarort ${(100 * x.nb / Math.max(1, x.platz + x.nb)).toFixed(1).padStart(5)} %`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zur Schule bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('haushalt')) {
  // Haushalt (Version 9, Teil 3). A statisch: der Abschnitt liest keine Personen, keinen Zufall, keine Namen; jede Änderung des Budgets im sim-Block
  // bucht auf ein Konto; die Lohnsteuer rechnet mit dem Satz des Haushalts. B neue Städte (Seeds 1–3, 730 Tage stündlich): jede Stunde Summe der
  // Buchungen = Änderung des Budgets; jede Nacht Konten von gestern, Vorhaben (Bedarf, Rücklage, Bauhof, je Vorhaben höchstens eins, Vorrat), am
  // Jahresende Plan und Lohnsteuer unabhängig nachgerechnet, Jahreszeilen, Stadtbuch. C Rangfolge: Bürgermeister (KI) und Vorrang in der Nacht
  // (erzwungen). D Lohnsteuer erzwungen (senken, anheben, Grenzen). E Speichern und Laden (mitten am Tag, in der letzten Nacht des Jahres).
  // F Übernahme älterer Stände (Version 8, mit --git 7 bis 2), beschädigte Stände. G ausgeschaltet. H Namenstausch
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, HK = Sim.HK, J = R.JAHR;
  const simCode = (h) => h.match(/<script id="sim">([\s\S]*?)<\/script>/)[1];
  const lade = (code) => { const ctx = vm.createContext({}); vm.runInContext(`Math.random = () => { throw new Error('Math.random'); };`, ctx); vm.runInContext(code, ctx); return ctx.StadtSim; };
  const roh = (text) => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64');
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
  const speichern = (X, S) => speichernAlsText(X, S), laden = (X, text, migrieren) => X.importZustand(roh(text), migrieren);
  const abdruck = (X, S) => { const h = createHash('sha256'), d = X.exportZustand(S);
    for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
    h.update(JSON.stringify(d.werte)); h.update(JSON.stringify(d.json)); return h.digest('hex').slice(0, 16); };
  const bis = (X, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) X.stunde(S); };
  const kontenSumme = (h) => { let s = 0; for (let k = 0; k < Sim.HK_ZAHL; k++) s += h.summe[k] + h.ist[k]; return s; };
  const summe = (a, ks) => ks.reduce((x, k) => x + a[k], 0);

  console.log('A Statisch (Abschnitt „Haushalt“, alle Änderungen des Budgets, Lohnsteuer)');
  {
    const code = SIM_CODE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const a = SIM_CODE.indexOf('// ─── Haushalt (Version 9, Teil 3)'), e = SIM_CODE.indexOf('// Ende Haushalt');
    const teil = SIM_CODE.slice(a, e).replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    pruef(a > 0 && e > a && !/\b(zufall|zInt|zufallSich|zufallAuto|wahlZufall)\s*\(/.test(teil), `Abschnitt gefunden (${teil.split('\n').length} Zeilen), kein Zufall`);
    const felder = [...teil.matchAll(/\b(?:P|S\.p)\.(\w+)/g)].map(m => m[1]);
    pruef(!felder.length && !/\b(name|vorname|nr|namePack|ref|personInfo)\s*\(|NACHNAMEN|VORNAMEN|\.weib\b|\.einzug\b|\.eltern|\.geb\b/.test(teil),
      `liest keine Personen (keine Personenfelder: ${felder.join(', ') || 'keine'}), keine Namen, kein Geschlecht, kein Alter, keinen Einzugstag, keine Eltern`);
    // Jede Änderung des Budgets im sim-Block steht mit ihrer Buchung in derselben Zeile; Ausnahme: Betriebe der Stadt (Math.max, gebucht in den Zeilen danach)
    const zeilen = code.split('\n'), stellen = [], ohne = [];
    zeilen.forEach((z, i) => { if (/S\.budget\s*[-+]?=[^=]/.test(z)) { stellen.push(i); if (!/hhBuch\(S, [^;]*HK\.[A-Z_]+[^;]*\);/.test(z)) ohne.push(i); } });
    const max = ohne.length === 1 && /S\.budget = Math\.max\(0, S\.budget \+ einnahmen - fix\);/.test(zeilen[ohne[0]])
      && /if \(einnahmen\) hhBuch\(S, HK\.BETRIEBE, einnahmen\);/.test(zeilen.slice(ohne[0], ohne[0] + 6).join('\n'))
      && /hhBuch\(S, t === KITA \? HK\.KITAS : t === RATHAUS \? HK\.RATHAUS : HK\.FIX, S\.budget - vor - einnahmen\);/.test(zeilen.slice(ohne[0], ohne[0] + 6).join('\n'));
    pruef(stellen.length >= 25 && max, `${stellen.length} Stellen ändern das Budget, jede bucht in derselben Zeile; die eine Ausnahme (Betriebe der Stadt, Math.max) bucht Verkauf und laufende Kosten gleich danach`);
    const ls = (() => { const i = code.search(/^function lohnsteuer\(/m); return code.slice(i, code.indexOf('\n}\n', i)); })();
    pruef(/q = steuerSatz\(S\)/.test(ls) && /const t = Math\.round\(q \* Math\.max\(0, E\[k\] - R\.FREIBETRAG \* K - X\[k\]\) \* brutto\[w\] \/ E\[k\]\);/.test(ls)
      && (ls.match(/R\.STEUER/g) || []).length === 2 && /if \(q < R\.STEUER\) h\.erlassen\[0\] \+=/.test(ls)
      && /function steuerSatz\(S\) \{ return S\.haushalt\.satz \/ 100; \}/.test(teil), 'Lohnsteuer mit dem Satz des Haushalts (steuerSatz: ein Satz für alle, keine Person); R.STEUER nur noch für „was die Senkung lässt“');
    const schritt = (() => { const i = code.search(/^function hhSchritt\(/m); return code.slice(i, code.indexOf('\n}\n', i)); })();
    // Schulen baut nur das Bauamt (Regel 7, ab einer ganzen Klasse: Noahs Entscheidung vom 28.09.); kein Vorhaben baut eine Schule
    // Teil 5 (Befund der Gegenprüfung „tech“): Computer der Schulen sind Bedarf vor den Vorhaben (hhComputer), nicht in der Rangfolge
    const vh = (() => { const i = code.search(/^function hhVorhaben\(/m); return code.slice(i, code.indexOf('\n}\n', i)); })();
    pruef(['wohnungen', 'rathaus', 'parks'].every(id => schritt.includes(`id === '${id}'`)) && Sim.VORHABEN.map(v => v.id).join() === 'wohnungen,rathaus,parks'
      && vh.indexOf('hhComputer(S, frei, p)') > 0 && vh.indexOf('hhComputer(S, frei, p)') < vh.indexOf('p.rang.length')
      && !/neuesGebaeude\(S, SCHULE|schuleBezahlen|SCHUL_MIN|kitaUmbau/.test(teil),
      `drei Vorhaben, jedes mit eigenem Schritt: ${Sim.VORHABEN.map(v => v.name).join(', ')}; die Computer der Schulen davor als Bedarf (hhComputer, nicht in der Rangfolge); keins baut Schulen (das Bauamt ab einer ganzen Klasse)`);
  }

  // Messkopie: jeder Schritt eines Vorhabens (Budget vorher, Bauhof, Lücke), jede Nacht am Ende, jeder Jahresabschluss (Satz vorher, Änderung, Plan)
  const { Sim: M, ctx: mc } = ladeSimMit([
    ['    const id = p.rang[i], r = hhSchritt(S, id, sb, frei, i + 1, p);\n',
      '    const __b0 = S.budget, __bf = hhBauhofFrei(S), __l = hhWohnungLuecke(S), __n = S.gAnzahl, __it = S.stat.schule.itGeraete;\n    const id = p.rang[i], r = hhSchritt(S, id, sb, frei, i + 1, p);\n'
      + '    if (globalThis.__schritt) globalThis.__schritt(S, id, r, __b0, __bf, __l, frei, p.ruecklage, sb, __n, __it);\n'],
    ['    const r = hhComputer(S, frei, p);\n',
      '    const __b0 = S.budget, __bf = hhBauhofFrei(S), __l = hhWohnungLuecke(S), __n = S.gAnzahl, __it = S.stat.schule.itGeraete, __be = S.haushalt.ist[HK.BETRIEBE];\n    const r = hhComputer(S, frei, p);\n'
      + '    if (globalThis.__schritt) globalThis.__schritt(S, \'computer\', r, __b0, __bf, __l, frei, p.ruecklage, sb, __n, __it, S.haushalt.ist[HK.BETRIEBE] - __be);\n'],
    ['function hhNacht(S, sb) {\n', 'function hhNacht(S, sb) {\n  if (globalThis.__nacht) globalThis.__nacht(S, sb);\n'],
    ['  const alt = h.satz, d = hhSteuer(S), q = h.plan;\n', '  const __vj = h.vorjahr.slice(), __b = S.budget;\n  const alt = h.satz, d = hhSteuer(S), q = h.plan;\n  if (globalThis.__jahr) globalThis.__jahr(S, alt, d, q, __vj, __b, j);\n'],
    ['function rathausAusbauen(S, b, ziel, zusatz) {\n', 'function rathausAusbauen(S, b, ziel, zusatz) {\n  if (globalThis.__ausbau) globalThis.__ausbau(S, zusatz);\n'],
  ]);
  const seeds = arg('seeds', '1,2,3').split(',').map(Number), tage = Number(arg('tage', '730'));
  console.log(`B Neue Städte (Seeds ${seeds.join(', ')}, je ${tage} Tage stündlich)`);
  const MX = M.R;
  for (const seed of seeds) {
    const S = M.neueStadt(seed), F = {}, f = (k, text) => { if (!F[k]) F[k] = text || true; };
    const zahl = { stunden: 0, naechte: 0, jahre: 0, schritte: 0, gestartet: 0, gesenkt: 0, angehoben: 0, gehalten: 0, bauamtAusbau: 0, ausbau: 0, zeilen: 0 };
    const jeNacht = new Map(); let budgetNacht = S.budget, kasseJahr = S.budget, erste0 = -1, satzTag = [];
    mc.__schritt = (X, id, r, b0, bf, l, frei, rl, sb, n0, it0, laden = 0) => {
      zahl.schritte++;
      // Teil 5: Kaufen die Schulen im Laden der Stadt, bekommt die Stadt dessen Anteil zurück (Konto „Bauhof und Laden der Stadt: Verkauf“)
      if (Math.abs(b0 - X.budget - (r.aus - laden)) > 1e-6 || laden < 0 || (id !== 'computer' && laden)) f('aus', `Tag ${X.tag}: ${id} gab ${b0 - X.budget} aus, gemeldet ${r.aus} (Laden der Stadt ${laden})`);
      if (r.aus > 0) {
        zahl.gestartet++;
        const k = id; jeNacht.set(k, (jeNacht.get(k) || 0) + 1);
        if (jeNacht.get(k) > 1) f('eins', `Tag ${X.tag}: ${id} zweimal in einer Nacht`);
        if (X.budget - laden < rl - 1e-6) f('ruecklage', `Tag ${X.tag}: ${id} unter die Rücklage (${Math.round(X.budget)} < ${rl})`);
        if (r.aus > frei + 1e-6) f('frei', `Tag ${X.tag}: ${id} gab ${r.aus} aus, frei waren ${frei}`);
        if (id !== 'computer' && !bf) f('bauhof', `Tag ${X.tag}: ${id} ohne freien Bauhof`);
        if (id === 'wohnungen' && l <= 0) f('luecke', `Tag ${X.tag}: Wohnungen ohne Lücke`);
        if (id === 'computer' && X.stat.schule.itGeraete - it0 !== r.aus / R.PREIS[Sim.COMPUTER]) f('it', `Tag ${X.tag}: Computer ${r.aus} Taler, ${X.stat.schule.itGeraete - it0} Geräte`);
        if (X.gAnzahl > n0 && X.g.typ[X.gAnzahl - 1] === Sim.SCHULE) f('schule', `Tag ${X.tag}: ${id} baut eine Schule`);   // Schulen baut nur das Bauamt
      }
      if (r.halten > 0) zahl.gehalten++;
    };
    mc.__ausbau = (X, zusatz) => { zahl.ausbau++; if (!/Vorhaben aus dem Haushalt/.test(zusatz)) zahl.bauamtAusbau++; };
    mc.__jahr = (X, alt, d, q, vj, b, j) => {
      zahl.jahre++;
      // Plan unabhängig nachgerechnet: Rücklage aus den laufenden Kosten des Vorjahres, Rahmen, Schätzungen in der Rangfolge, nicht verplant
      const pflicht = Math.max(0, Math.round(-summe(vj, Sim.HK_PFLICHT))), rl = Math.max(R.START_BUDGET, pflicht) + 2 * R.K_HAUS + R.K_SCHULE[2];
      const rahmen = Math.max(0, Math.floor(b) - rl), sch = Object.values(q.schaetzung).reduce((x, y) => x + y, 0);
      if (q.ruecklage !== rl || q.pflicht !== pflicht || q.rahmen !== rahmen || sch + q.unverplant !== rahmen || q.jahr !== j + 1) f('plan', `Jahr ${j + 1}: Rücklage ${q.ruecklage}/${rl}, Rahmen ${q.rahmen}/${rahmen}, Schätzung ${sch} + ${q.unverplant}`);
      if (q.rang.join() !== M.vorhabenRangfolge(X, j + 1).join()) f('rang', `Jahr ${j + 1}: Rangfolge ${q.rang.join()}`);
      // Lohnsteuer: senken, wenn nicht verplant ≥ Lohnsteuer des Jahres (und Kasse ≥ Rücklage), anheben bei Kasse < Rücklage, sonst gleich
      const L = vj[HK.STEUER], soll = b < q.ruecklage ? (alt < 10 ? 1 : 0) : (alt > 0 && q.unverplant > 0 && q.unverplant >= L ? -1 : 0);
      if (d !== soll || X.haushalt.satz !== alt + d) f('steuer', `Jahr ${j + 1}: Satz ${alt} → ${X.haushalt.satz} (${d}), erwartet ${soll}`);
      if (d < 0) zahl.gesenkt++; if (d > 0) zahl.angehoben++;
    };
    mc.__nacht = (X) => { jeNacht.clear(); };
    let buchNr = S.buchNr, stunde0 = S.budget;
    for (let d = 1; d <= tage; d++) {
      while (S.tag < d) {
        M.stunde(S); zahl.stunden++;
        const h = S.haushalt;
        if (Math.abs(kontenSumme(h) - (S.budget - h.kasseStart)) > 1e-6) f('konten', `Tag ${S.tag} ${S.stunde} Uhr: Konten ${kontenSumme(h)} statt ${S.budget - h.kasseStart}`);
      }
      zahl.naechte++;
      const h = S.haushalt;
      const gs = h.gestern.reduce((x, y) => x + y, 0);
      if (Math.abs(gs - (S.budget - budgetNacht)) > 1e-6) f('gestern', `Tag ${S.tag}: gestern ${gs}, Budget ${S.budget - budgetNacht}`);
      budgetNacht = S.budget;
      if (h.satz < 0 || h.satz > 10 || !Number.isInteger(h.satz)) f('satz', `Satz ${h.satz}`);
      if (erste0 < 0 && h.satz === 0) erste0 = S.tag;
      if (S.tag % J === 0) {                                  // nach dem Jahresabschluss: Zeile der Jahre = Änderung der Kasse
        const r = h.jahre[h.jahre.length - 1];
        if (!r || r[0] !== S.tag / J - 1 || Math.abs(r[1] - r[2] - (S.budget - kasseJahr)) > 1e-6 || r[4] !== Math.floor(S.budget)) f('jahre', `Jahr ${S.tag / J - 1}: ${JSON.stringify(r)}`);
        if (h.jahre.length > R.HH_JAHRE) f('jahre10', `${h.jahre.length} Jahre`);
        kasseJahr = S.budget; satzTag.push(h.satz);
      }
      if (M.haushaltKurz(S).saldo !== gs || !M.haushaltKurz(S).fenster) f('kurz', `Tag ${S.tag}: haushaltKurz`);
      // fest: nicht an Zuzug oder Größe gekoppelt (Teil 3: 6; seit Teil 4, Wachstum: 0)
      if (M._hh.hhVorrat(S) !== R.HH_VORRAT || R.HH_VORRAT !== 0) f('vorrat', `Vorrat ${M._hh.hhVorrat(S)} bei ${S.einwohner}`);
      for (const e of S.buch) if (e.nr > buchNr && e.art === 'haushalt') { zahl.zeilen++; if (/\u0001/.test(e.text)) f('name', 'Name in einer Zeile zum Haushalt'); }
      buchNr = S.buchNr;
    }
    const h = S.haushalt, fe = Object.entries(F);
    pruef(!fe.length && zahl.jahre === Math.floor(tage / J) && zahl.zeilen === zahl.jahre && zahl.bauamtAusbau === 0,
      `Seed ${seed}: ${zahl.stunden} Stunden Konten = Budget, ${zahl.naechte} Nächte (gestern, Vorhaben, Vorrat, Kurzfassung), ${zahl.jahre} Jahresabschlüsse mit Plan und Lohnsteuer nachgerechnet, ${zahl.zeilen} Jahreszeilen ohne Namen`
      + (fe.length ? ': ' + fe.map(([k, v]) => `${k}: ${v}`).join('; ') : ''));
    pruef(zahl.gestartet > 10 && h.satz <= 10 && erste0 > 0 && zahl.ausbau === 3,
      `Seed ${seed}: ${zahl.schritte} Schritte, ${zahl.gestartet} Vorhaben gestartet (nie zwei gleiche in einer Nacht, nie unter die Rücklage, Bau nur mit freiem Bauhof), ${zahl.gehalten}-mal Geld für ein höheres Vorhaben festgehalten;`
      + ` Rathaus ${zahl.ausbau}-mal ausgebaut, alle als Vorhaben; Lohnsteuer ${zahl.gesenkt}-mal gesenkt, ${zahl.angehoben}-mal angehoben, 0 % ab Tag ${erste0}, an Tag ${S.tag} ${h.satz} %;`
      + ` seit dem Start ${Object.entries(h.seit).map(([k, v]) => `${k} ${v}`).join(', ')} Taler; den Leuten gelassen ${Math.round(h.erlassen[0] + h.erlassen[2])} Taler`);
  }
  mc.__schritt = mc.__ausbau = mc.__jahr = mc.__nacht = null;

  console.log('C Rangfolge: Bürgermeister (KI) und Vorrang in der Nacht (erzwungen)');
  {
    const S = Sim.neueStadt(2); Sim.kiSchalten(S, true); bis(Sim, S, 9, 8);
    const a = Sim.bmAnfrage(S), liste = ['parks', 'rathaus', 'wohnungen'];
    const r = a && Sim.bmRangfolge(S, a.id, a.gen, a.nr, liste, 'Zuerst die Parks, dann das Rathaus.');
    bis(Sim, S, 10);
    const zl = S.buch.filter(e => e.art === 'haushalt').pop();
    pruef(a && r.ok && a.vorhaben.length === 3 && S.haushalt.plan.rang.join() === liste.join() && S.haushalt.plan.von === 'ki' && zl && /Bürgermeisteramt festgelegt/.test(zl.text),
      `Anfrage am letzten Tag des Jahres 0 mit ${a ? a.vorhaben.length : 0} Vorhaben; Antwort gilt fürs Jahr 1: ${S.haushalt.plan.rang.join(', ')} (${S.haushalt.plan.von}); Jahreszeile nennt das Bürgermeisteramt`);
    // Vorrang (erzwungen): Stand mit freiem Bauhof, Computerfirmen und Schulen ohne Bedarf an Computern; das Rathaus wird eine Stufe zurückgesetzt
    // (Bedarf beim Rathaus). Das Geld über der Rücklage reicht genau für den Ausbau: Rathaus vorn → Ausbau; Wohnungen vorn mit Bedarf (60 Anfragen)
    // → ein Wohnhaus, das Rathaus hält den Rest fest. Teil 5: Die Computer der Schulen sind Bedarf vor allen Vorhaben (Lieferungen gestrichen):
    // Sie kommen zuerst, egal wie die Rangfolge ist, und halten fest, was ihnen fehlt
    const T = Sim.neueStadt(1);
    let gefunden = false;
    while (T.tag < 600 && !gefunden) { bis(Sim, T, T.tag + 1, 1); gefunden = Sim._hh.hhBauhofFrei(T) && T.schule.it.length > 0 && Sim.schulITBedarf(T).lieferanten > 0 && Sim.schulITBedarf(T).geraete === 0 && T.g.stufe[T.rathaus.b] >= 2 && !T.g.auf[T.rathaus.b]; }
    const probe = (rang, frei, vorher) => { const X = laden(Sim, speichern(Sim, T)), p = X.haushalt.plan;
      if (vorher) vorher(X);
      p.rang = rang; budgetSetzen(X, p.ruecklage + frei);   // Kasse auf die Probe gesetzt (Konten nachgezogen)
      const vor = Object.assign({}, p.verbraucht); Sim._hh.hhVorhaben(X, null);
      return Object.fromEntries(Object.keys(p.verbraucht).map(k => [k, p.verbraucht[k] - (vor[k] || 0)])); };
    const rathausBedarf = (X) => { X.g.stufe[X.rathaus.b]--; X.anfragen += 60; };
    const ziel = T.g.stufe[T.rathaus.b], kr = R.K_RATHAUS[ziel], eins = R.PREIS[Sim.COMPUTER];
    const x1 = probe(['rathaus', 'wohnungen', 'parks'], kr, rathausBedarf), x2 = probe(['wohnungen', 'rathaus', 'parks'], kr, rathausBedarf);
    pruef(gefunden && x1.rathaus === kr && !x1.wohnungen && !x1.computer && x2.wohnungen > 0 && !x2.rathaus,
      `Seed 1, Tag ${T.tag}, ${kr} Taler über der Rücklage, Rathaus eine Stufe zurück, 60 Anfragen: Rathaus vorn → Ausbau ${x1.rathaus || 0}, Wohnungen ${x1.wohnungen || 0}; Wohnungen vorn → Wohnungen ${x2.wohnungen || 0}, Rathaus ${x2.rathaus || 0} (hält fest)`);
    const bedarf = (X) => { X.schule.it = []; X.g.stufe[X.rathaus.b]--; };
    const x3 = probe(['rathaus', 'wohnungen', 'parks'], kr, bedarf), x4 = probe(['wohnungen', 'parks', 'rathaus'], eins, (X) => { X.schule.it = []; X.anfragen += 60; });
    pruef(x3.computer > 0 && x3.computer <= kr && !x3.rathaus && x4.computer === eins && !x4.wohnungen,
      `Computer gestrichen (Bedarf vor den Vorhaben): mit Rathaus vorn → Computer ${x3.computer || 0}, Rathaus ${x3.rathaus || 0} (hält fest); ${eins} Taler und 60 Anfragen, Wohnungen vorn → Computer ${x4.computer || 0}, Wohnungen ${x4.wohnungen || 0}`);
    const U = laden(Sim, speichern(Sim, T)); budgetSetzen(U, U.haushalt.plan.ruecklage - 1);
    const vorU = Object.values(U.haushalt.plan.verbraucht).reduce((a, b) => a + b, 0); Sim._hh.hhVorhaben(U, null);
    pruef(Object.values(U.haushalt.plan.verbraucht).reduce((a, b) => a + b, 0) === vorU, 'Kasse unter der Rücklage: kein Vorhaben');
  }

  console.log('D Lohnsteuer erzwungen (Jahresabschluss mit gesetzter Kasse)');
  {
    const T = Sim.neueStadt(3); bis(Sim, T, 199, 23);
    const probe = (satz, kasse) => { const X = laden(Sim, speichern(Sim, T)); X.haushalt.satz = satz; budgetSetzen(X, kasse); bis(Sim, X, 200); return X; };
    const rl = T.haushalt.plan.ruecklage;
    const a = probe(5, 10), b = probe(10, 10), c = probe(5, 5e6), d0 = probe(0, 5e6), e = probe(10, 5e6);
    pruef(a.haushalt.satz === 6 && b.haushalt.satz === 10 && c.haushalt.satz === 4 && d0.haushalt.satz === 0 && e.haushalt.satz === 9,
      `Tag 199 → 200 (Rücklage etwa ${rl}): Kasse 10 Taler: 5 → ${a.haushalt.satz} %, 10 → ${b.haushalt.satz} % (nicht über 10); 5 Mio.: 5 → ${c.haushalt.satz} %, 0 → ${d0.haushalt.satz} % (nicht unter 0), 10 → ${e.haushalt.satz} %`);
    // Die Steuer eines Lohns folgt dem Satz (ein Satz für alle): 100 Taler Lohn allein, Freibetrag 29 → 71 × Satz
    const X = laden(Sim, speichern(Sim, T)), P = X.p;
    let w = -1; for (let p = 0; p < X.pMax; p++) if (P.lebt[p] && P.arbeit[p] >= 0 && P.besitz[p] < 0 && X.tag - P.geb[p] >= 180 && X.tag - P.geb[p] < 600) { w = p; break; }
    const br = new Float64Array(X.pMax); br[w] = 100; const vor = P.geld[w], hh = X.haushalt.erlassen[0];
    X.haushalt.satz = 4; Sim._auto.kennzahlenRechnen(X);
    const K = Math.max(1, Sim.betreuer ? 1 : 1);
    const ls = ladeSimMit([['G.StadtSim = {', 'G.StadtSim = { __lohnsteuer: lohnsteuer, __koepfe: koepfe,']]).Sim;
    const Y = ls.importZustand(roh(speichern(Sim, X))); Y.haushalt.satz = 4;
    const g0 = Y.p.geld[w], k = ls.__koepfe(Y, w), br2 = new Float64Array(Y.pMax); br2[w] = 100;
    ls.__lohnsteuer(Y, br2);
    const t = g0 - Y.p.geld[w], soll = Math.round(0.04 * Math.max(0, 100 - 29 * k)), voll = Math.round(0.1 * Math.max(0, 100 - 29 * k));
    pruef(Y.p.hh[w] !== w || t === soll, `Lohnsteuer bei 4 %: ${t} Taler auf 100 Taler Lohn (${k} Köpfe, erwartet ${soll}); den Leuten gelassen ${Y.haushalt.erlassen[0] - hh} (erwartet ${voll - soll})`);
    void vor; void K;
  }

  console.log('E Speichern und Laden (mitten am Tag, in der letzten Nacht des Jahres)');
  for (const [seed, tag, st] of [[1, 155, 13], [2, 159, 23], [3, 309, 23]]) {
    const S = Sim.neueStadt(seed); bis(Sim, S, tag, st);
    const L = ladenAusText(Sim, speichernAlsText(Sim, S));
    bis(Sim, S, tag + 60); bis(Sim, L, tag + 60);
    pruef(abdruck(Sim, S) === abdruck(Sim, L) && JSON.stringify(S.haushalt) === JSON.stringify(L.haushalt), `Seed ${seed}, Tag ${tag} ${st} Uhr: 60 Tage weiter bitgleich (Satz ${S.haushalt.satz} %)`);
  }
  {
    const S = Sim.neueStadt(1); bis(Sim, S, 100); const A = Sim.neueStadt(1); bis(Sim, A, 50); while (A.tag < 100) Sim.tagSchritt(A);
    pruef(Math.abs(kontenSumme(A.haushalt) - (A.budget - A.haushalt.kasseStart)) < 1e-6 && A.haushalt.jahre.length === 10,
      `Aufholen (Tag 50–100 in Tagesschritten): Konten = Budget, ${A.haushalt.jahre.length} Jahre, Satz ${A.haushalt.satz} % (stündlich ${S.haushalt.satz} %)`);
  }

  console.log('F Übernahme älterer Stände, beschädigte Stände');
  {
    const quellen = [['Version 8 (stadt.orig.html)', readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')]];
    if (arg('git')) for (const [c, v] of [['ffa1d88', 7], ['bc7247a', 6], ['414ebab', 5], ['1c8d40b', 4], ['2b821c2', 3], ['39c405b', 2]])
      quellen.push([`Version ${v} (git ${c})`, execFileSync('git', ['show', c + ':stadt/stadt.html'], { cwd: arg('git'), encoding: 'utf8', maxBuffer: 1 << 26 })]);
    else console.log('  (ohne --git: nur Version 8)');
    for (const [herkunft, html] of quellen) {
      const Alt = lade(simCode(html));
      const A = Alt.neueStadt(4); while (A.tag < 150 || A.stunde < 13) Alt.stunde(A);
      const text = speichernAlsText(Alt, A);
      let S = null, grund = '';
      try { S = laden(Sim, text, true); } catch (e) { grund = e.message; }
      const h = S && S.haushalt, z = S ? S.buch.filter(e => e.art === 'haushalt') : [];
      // die Zeile des Haushalts steht vor denen von Schule und Rathaus (deren Zeilen bleiben die letzten der Übernahme; der Bau des Rathauses kann
      // noch eine Zeile zu Karte oder Stadtteil schreiben)
      const idx = S ? S.buch.findIndex(e => e.art === 'haushalt') : -1, danach = S ? S.buch.slice(idx + 1).map(e => e.art) : [];
      let ok = !!h && h.start === 150 && h.satz === 10 && z.length === 1 && /Ab heute führt die Stadt einen Haushalt/.test(z[0].text) && danach[0] === 'schule' && danach.includes('rathaus')
        && S.buch.slice(idx).every(e => e.tag === 150);
      if (S) { bis(Sim, S, 190); ok = ok && Math.abs(kontenSumme(S.haushalt) - (S.budget - S.haushalt.kasseStart)) < 1e-6 && S.haushalt.jahre.length === 4; }
      let gleich = false;
      if (S) { const L = ladenAusText(Sim, speichernAlsText(Sim, S)); bis(Sim, S, 200); bis(Sim, L, 200); gleich = abdruck(Sim, S) === abdruck(Sim, L); }
      pruef(ok && gleich, `${herkunft}, Seed 4, Tag 150: Haushalt ab Tag 150, Zeile vor denen von Schule und Rathaus, 40 Tage Konten = Budget, ${S ? S.haushalt.jahre.length : 0} Jahre, danach gespeichert und geladen gleich${grund ? ' – ' + grund : ''}`);
    }
    const S = Sim.neueStadt(2); bis(Sim, S, 120, 5);
    const text = speichernAlsText(Sim, S), meld = [];
    const faelle = [['Haushalt fehlt', d => { delete d.json.haushalt; }], ['Satz über 10', d => { d.json.haushalt.satz = 11; }], ['Satz keine Zahl', d => { d.json.haushalt.satz = 'x'; }],
      ['Konten zu kurz', d => { d.json.haushalt.ist.pop(); }], ['Konto NaN', d => { d.json.haushalt.summe[3] = null; }], ['Konten passen nicht zum Budget', d => { d.werte.budget += 1000; }],
      ['Plan fürs falsche Jahr', d => { d.json.haushalt.plan.jahr += 1; }], ['Plan ohne Rangfolge', d => { d.json.haushalt.plan.rang = 'x'; }],
      ['Plan von wem', d => { d.json.haushalt.plan.von = 'noah'; }], ['Jahre zu viele', d => { d.json.haushalt.jahre = new Array(11).fill([1, 1, 1, 1, 1, 1]); }],
      ['Jahr kaputt', d => { d.json.haushalt.jahre = [[1, 2]]; }], ['erlassen negativ', d => { d.json.haushalt.erlassen = [-1, 0, 0]; }],
      ['Start in der Zukunft', d => { d.json.haushalt.start = 999; }], ['gestern kaputt', d => { d.json.haushalt.gestern = [1]; }]];
    for (const [was, kaputt] of faelle) {
      const d = roh(text); kaputt(d);
      try { Sim.importZustand(d); meld.push(was + ': angenommen'); } catch (e) { if (!/beschädigt|unvollständig/.test(e.message)) meld.push(was + ': ' + e.message); }
    }
    pruef(!meld.length, `${faelle.length} beschädigte Stände abgelehnt` + (meld.length ? ': ' + meld.join('; ') : ''));
  }

  console.log('G Ausgeschaltet (nur Buchführung)');
  {
    const alt = [R.HH_VORHABEN, R.HH_STEUER]; R.HH_VORHABEN = 0; R.HH_STEUER = 0;
    const S = Sim.neueStadt(2); bis(Sim, S, 400);
    const h = S.haushalt, aus = Object.values(h.seit).reduce((a, b) => a + b, 0), ra = S.buch.filter(e => e.art === 'rathaus' && /baut ihr Rathaus .* aus/.test(e.text));
    pruef(h.satz === 10 && !aus && !S.buch.some(e => e.art === 'haushalt') && Math.abs(kontenSumme(h) - (S.budget - h.kasseStart)) < 1e-6 && S.g.stufe[S.rathaus.b] === S.erweiterung.stufe + 1 && ra.every(e => !/Haushalt/.test(e.text)),
      `R.HH_VORHABEN = 0, R.HH_STEUER = 0 (Seed 2, 400 Tage): Satz 10 %, keine Vorhaben, keine Zeile, Konten = Budget; das Rathaus baut nach RA6 aus (Stufe ${S.g.stufe[S.rathaus.b]})`);
    [R.HH_VORHABEN, R.HH_STEUER] = alt;
  }

  console.log('H Namenstausch (der Haushalt liest keine Namen)');
  {
    const { Sim: T } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(3), B = T.neueStadt(3); bis(Sim, A, 300); bis(T, B, 300);
    const ohneText = (S) => JSON.stringify([S.haushalt.ist, S.haushalt.summe, S.haushalt.satz, S.haushalt.seit, S.haushalt.plan.rang, S.budget, S.einwohner]);
    pruef(ohneText(A) === ohneText(B), `Seed 3, 300 Tage: mit umgedrehten Namenslisten gleiche Konten, gleicher Satz (${A.haushalt.satz} %), gleiche Vorhaben`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zum Haushalt bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('wachstum')) {
  // Wachstum, Tempo und KI (Version 9, Teil 4). A statisch (Abschnitt „Wachstum“ und die Zählung in zuzug() würfeln nicht und lesen keine Person).
  // B Ohne Anlauf (R.ANLAUF_STUFE = 0) und mit ausgeschalteten Bausteinen von Version 9 Tag für Tag wie Version 8 (stadt.orig.html); mit --alt <datei>
  // (Fassung vor Teil 4) ohne Anlauf, sonst alles an, Tag für Tag wie diese. C Anlauf je Nacht (Seeds 1–3, 400 Tage): jeder Zuzug mit Stelle
  // nach der Regel (Laden und Bauhof nur im Dorf, nie Kita, Schule nur mit SCHUL_ZUZUG), höchstens die Grenze des Tages, Zählung der Stellen,
  // Anfragen fürs Bauamt mit der Grundzahl ohne Anlauf; dasselbe mit SCHUL_ZUZUG = 0. D Schalter: setzen, Stadtbuch, ungültige Werte, Speichern
  // und Laden bitgleich, Übernahme älterer Stände, beschädigte Stände, „schnell“ wirkt. E KI-Frist: Klemmen, Verlängern, späte Antwort, Rangfolge
  // bis 23 Uhr. F Kapazität der Warteschlange bei 10 Hauptfiguren und Bürgermeister je Tempo und Antwortzeit (nur gemessen)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, J = R.JAHR, X = Sim._wachstum;
  const simCode = (h) => h.match(/<script id="sim">([\s\S]*?)<\/script>/)[1];
  const lade = (code) => { const ctx = vm.createContext({}); vm.runInContext(`Math.random = () => { throw new Error('Math.random'); };`, ctx); vm.runInContext(code, ctx); return ctx.StadtSim; };
  const roh = (text) => { const d = JSON.parse(text); d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64');
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; }); return d; };
  const bis = (Y, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) Y.stunde(S); };

  console.log('A Statisch');
  {
    const ohneKomm = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const a = SIM_CODE.indexOf('// ─── Wachstum (Version 9, Teil 4)'), e = SIM_CODE.indexOf('// Ende Wachstum');
    const teil = ohneKomm(SIM_CODE.slice(a, e));
    const zuf = teil.match(/\b(zufall|zInt|zufallSich|zufallAuto|wahlZufall)\s*\(/g) || [], pers = teil.match(/\bS\.p\b|\bP\.|\b(name|vorname|nr|personInfo|bmWort)\s*\(/g) || [];
    pruef(a > 0 && e > a && !zuf.length && !pers.length, `Abschnitt „Wachstum“: würfelt nicht (${zuf.length}), liest keine Person (${pers.length})`);
    const z0 = SIM_CODE.indexOf('function zuzug(S)'), z1 = SIM_CODE.indexOf('  const neu = [];', z0);
    const zaehl = ohneKomm(SIM_CODE.slice(z0, z1));
    const zp = zaehl.match(/\bS\.p\b|\bP\.|\b(name|vorname|nr|personInfo)\s*\(/g) || [], zz = zaehl.match(/\bzufall\s*\(/g) || [];
    pruef(z0 > 0 && z1 > z0 && !zp.length && zz.length === 1 && /wachstumJetzt\(S\)/.test(zaehl) && /basis0/.test(zaehl),
      `zuzug(), Zählung bis zur Suche: liest keine Person (${zp.length}), ein Zufallszug wie vorher (${zz.length}), Anlauf über wachstumJetzt, Anfragen mit der Grundzahl ohne Anlauf`);
    // Die Oberfläche setzt die Frist nur über kiSchalten; die Simulation kennt kein Tempo
    pruef(!/\btempo\b/.test(ohneKomm(SIM_CODE)), 'die Simulation kennt kein Tempo (nur die Frist in Spielstunden über kiSchalten)');
    // Die Karte R10 im Fenster „Stadtregierung“ nennt die Zahlen fest (REGIERUNG ist reiner Text): Sie müssen zu R passen
    const a0 = html.indexOf('const REGIERUNG = '), b0 = html.indexOf('// Ende REGIERUNG');
    const REG = new Function(html.slice(a0, b0).replace('const REGIERUNG = ', 'return ').replace(/;\s*$/, ''))();
    let r10 = null; for (const [, regeln] of REG.gruppen) for (const r of regeln) if (/^Zuzug nur für eine freie Stelle/.test(r.titel)) r10 = r;
    const P = R.ANLAUF_PLUS.slice(0, R.ANLAUF_STUFE), gleich = P.every(x => x === P[0]);
    const soll = [`höchstens 1 + ${Math.round(R.ZUZUG_MAX * 100)} % der Einwohner am Tag`, `Bis die Stadt ${R.STUFE_AB[R.ANLAUF_STUFE]} Einwohner hat, dürfen am Tag bis zu ${P[0]} mehr kommen`];
    pruef(!!r10 && gleich && soll.every(t => r10.stadt.includes(t)) && r10.hinweis.includes(`(bis zu 1 + ${Math.round(R.SCHNELL_ZUZUG_MAX * 100)} % am Tag)`)
      && r10.hinweis.includes('keine Maßnahme der Stadtregierung') && r10.live === 'wachstum',
      `Karte R10: Zahlen im Text passen zu R (1 + ${R.ZUZUG_MAX * 100} %, Anlauf bis ${R.STUFE_AB[R.ANLAUF_STUFE]} Einwohner +${P[0]}, schnell 1 + ${R.SCHNELL_ZUZUG_MAX * 100} %), Schalter keine Maßnahme der Stadtregierung, Live-Zeile`);
  }

  console.log('B Ohne Anlauf wie vorher');
  {
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const spur = (S) => { const x = createHash('sha256');
      for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n]) && n !== 'schule') { const a = S.p[n], w = a.length / S.pKap; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) { if (n === 'markt' || n === 'kraft') continue; const a = S.g[n]; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.gAnzahl * a.BYTES_PER_ELEMENT)); }   // Teil 5: neue Felder
      x.update(Buffer.from(S.feld.buffer)); const st = { ...S.stat, tech: techAlt(S.stat.tech) }; delete st.rathaus; delete st.buergermeister; delete st.schule; delete st.aufgegeben;
      x.update(JSON.stringify([S.budget, S.rs, S.rsSich, S.rsAuto, S.tag, S.einwohner, st, kiAlt(S.ki), S.regierung, S.sicherheit, S.bund, S.erweiterung])); x.update(JSON.stringify(S.buch));
      return x.digest('hex').slice(0, 16); };
    const alt = AUS.slice(7).map(k => R[k]);                   // Rathaus, Schulen, Vorhaben, Lohnsteuer des Haushalts, Anlauf, Tech früher und Weltmarkt (Teil 5)
    R.RATHAUS = 0; R.SCHULEN = 0; R.HH_VORHABEN = 0; R.HH_STEUER = 0; R.ANLAUF_STUFE = 0; R.TECH_FRUEH = 0; R.WELT = 0; R.ZUZUG_GENAU = 0;
    for (const seed of [1, 2, 3]) {
      const A = V8.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1;
      for (let d = 1; d <= 200 && erster < 0; d++) { bis(V8, A, d); bis(Sim, B, d); if (spur(A) !== spur(B)) erster = d; }
      pruef(erster < 0, `Seed ${seed}, ohne Anlauf und ohne die Bausteine von Version 9: 200 Tage ${erster < 0 ? 'jeden Tag wie Version 8' : 'VERSCHIEDEN ab Tag ' + erster} (${B.einwohner} Einwohner)`);
    }
    AUS.slice(7).forEach((k, i) => { R[k] = alt[i]; });
    if (arg('alt')) {                                         // die Fassung vor Teil 4 (alles an): ohne Anlauf und mit ihrem Vorrat (6) Tag für Tag gleich
      const V = lade(simCode(readFileSync(arg('alt'), 'utf8')));
      // Teil 5: ohne die neuen Felder (Markt, Kraft, freie Tech-Stellen, Weltmarkt, neue Summen) und ohne Plan und Rangfolge (die Liste der Vorhaben ist
      // kürzer, die Computer der Schulen sind Bedarf davor); die Zeilen der Vorhaben nennen ihren Rang, der hier fehlt. Die ersten 200 Tage kaufen die
      // Schulen noch keine Computer (die erste Schule öffnet ohne Anlauf später), sonst liefe die Stadt ab dort anders
      const f = (Y, S) => { const d = Y.exportZustand(S), h = createHash('sha256');
        for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { if (a.name === 'g.markt' || a.name === 'g.kraft') continue; h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
        const w = { ...d.werte }; delete w.wachstum; delete w.techFrei; delete w.weltPlaetze; delete w.weltPreis; h.update(JSON.stringify(w));
        const hh = d.json.haushalt, bm = d.json.buergermeister, st = d.json.stat;
        const j = { ...d.json, ki: kiAlt(d.json.ki), haushalt: hh ? { ...hh, plan: undefined, vorjahrPlan: undefined, seit: undefined } : hh, buergermeister: bm ? { ...bm, rangfolge: undefined, anfrage: undefined } : bm,
          buch: d.json.buch.map(e => ({ ...e, text: textAlt(e.text.replace(/Vorhaben aus dem Haushalt \(\d\. /, 'Vorhaben aus dem Haushalt (')) })),
          stat: { ...st, aufgegeben: undefined, tech: techAlt(st.tech), schule: st.schule ? { ...st.schule, itAussen: undefined } : st.schule } };
        h.update(JSON.stringify(j)); return h.digest('hex').slice(0, 16); };
      const merk = [R.ANLAUF_STUFE, R.HH_VORRAT, R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU]; R.ANLAUF_STUFE = 0; R.HH_VORRAT = V.R.HH_VORRAT; R.TECH_FRUEH = 0; R.WELT = 0; R.ZUZUG_GENAU = 0;   // Teil 3: Vorrat 6 (seit Teil 4: 0, W8)
      for (const seed of [1, 2, 3]) {
        const A = V.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1;
        for (let d = 1; d <= 200 && erster < 0; d++) { bis(V, A, d); bis(Sim, B, d); if (f(V, A) !== f(Sim, B)) erster = d; }
        pruef(erster < 0 && !B.stat.schule.itGeraete, `Seed ${seed}, ohne Anlauf und mit Vorrat ${R.HH_VORRAT}, ohne Tech früher und Weltmarkt (Teil 5), sonst alles an: 200 Tage ${erster < 0 ? 'jeden Tag wie ' + arg('alt') : 'VERSCHIEDEN ab Tag ' + erster} (${B.einwohner} Einwohner, noch keine Computer der Schulen)`);
      }
      [R.ANLAUF_STUFE, R.HH_VORRAT, R.TECH_FRUEH, R.WELT, R.ZUZUG_GENAU] = merk;
    } else console.log('  (ohne --alt: kein Vergleich mit der Fassung vor Teil 4)');
  }

  console.log('C Anlauf je Nacht (Seeds 1–3, 400 Tage)');
  {
    const { Sim: W, ctx } = ladeSimMit([
      ['    anstellen(S, p, stelle); erinnere(S, p, M.JOB, stelle);',
        '    anstellen(S, p, stelle); erinnere(S, p, M.JOB, stelle);\n    globalThis.__zu.push([stelle, g.typ[stelle], stelle === S.bauhof ? 1 : 0, w.dorf ? 1 : 0, w.anlauf ? 1 : 0, w.grenze, S.erweiterung.stufe, S.p.arbeit[p], w.basis]);'],
      ['  S.anfragen = Math.max(0, Math.round((fs / (fs + 3)) * zf * basis0) - n);',
        '  S.anfragen = Math.max(0, Math.round((fs / (fs + 3)) * zf * basis0) - n);\n  globalThis.__zaehl(S, { fs, zf, basis0, basis, n, fw, dorf: w.dorf, bh, laden, stadtEigen });'],
    ]);
    for (const schulZuzug of [R.SCHUL_ZUZUG, 0]) {
      const merk = W.R.SCHUL_ZUZUG; W.R.SCHUL_ZUZUG = schulZuzug;
      let n = 0, anlaufN = 0, dorfN = 0, danach = 0, falsch = 0, ueber = 0, zaehlFalsch = 0, anfrFalsch = 0, tage = 0, dorfTage = 0, schulStellen = 0, fsUeber = 0;
      const beispiele = [];
      ctx.__zaehl = (S, z) => {
        tage++; if (z.dorf) dorfTage++;
        if (z.n > z.fs) fsUeber++;                             // R10 genau (Befund Technik der Schlussprüfung): nie mehr als freie Stellen ohne Arbeitsuchende der Stadt
        // Stellen unabhängig gezählt: frei in Kitas und (ohne Zuzug) Schulen locken nie, im Dorf locken Laden und Bauhof
        const g = S.g; let kita = 0, laden = 0;
        for (let b = 0; b < S.gAnzahl; b++) {
          const t = g.typ[b];
          if (g.offeneStellen[b] <= 0 || g.leer[b] || S.feld[g.y[b] * S.karte + g.x[b]] !== t) continue;   // offen wie offen(): fertig und nicht leer
          if (t === W.KITA || (t === W.SCHULE && !W.R.SCHUL_ZUZUG)) kita += g.offeneStellen[b];
          else if (t === W.LADEN) laden += g.offeneStellen[b];
        }
        const bh = S.bauhof >= 0 ? Math.max(0, g.offeneStellen[S.bauhof]) : 0;
        const soll = Math.max(0, S.freieStellen - (z.dorf ? kita : bh + laden + kita) - S.arbeitslose);
        if (soll !== z.fs) { zaehlFalsch++; if (beispiele.length < 3) beispiele.push(`Tag ${S.tag}: fs ${z.fs} statt ${soll}`); }
        if (S.anfragen !== Math.max(0, Math.round((z.fs / (z.fs + 3)) * z.zf * z.basis0) - z.n) || z.basis0 !== 2 + S.einwohner * 0.02) anfrFalsch++;
      };
      for (const seed of [1, 2, 3]) {
        const S = W.neueStadt(seed);
        while (S.tag < 400) {
          ctx.__zu = [];
          const z = S.tag + 1; while (S.tag < z) W.stunde(S);
          const L = ctx.__zu;
          if (L.length && L.length > L[0][5]) ueber++;
          for (const [st, typ, bh, dorf, anlauf, grenze, stufe, arbeit, basis] of L) {
            n++; if (anlauf) anlaufN++; else danach++;
            if (typ === W.SCHULE) schulStellen++;
            const regel = (typ === W.WERKSTATT && !bh) || typ === W.TECH || typ === W.RATHAUS || typ === W.WACHE || typ === W.JVA || typ === W.KASERNE
              || typ === W.DIENSTSTELLE || (typ === W.SCHULE && W.R.SCHUL_ZUZUG);
            if ((typ === W.LADEN || bh) && dorf) dorfN++;
            if (arbeit !== st || typ === W.KITA || !(regel || (dorf && (typ === W.LADEN || bh)))) falsch++;
            if (anlauf !== (stufe < R.ANLAUF_STUFE ? 1 : 0) || dorf !== (stufe === 0 && R.ANLAUF_DORF ? 1 : 0) || basis !== (anlauf ? R.ANLAUF_BASIS[stufe] : 1)
              || grenze < 1 + (anlauf ? R.ANLAUF_PLUS[stufe] : 0)) falsch++;
          }
        }
      }
      W.R.SCHUL_ZUZUG = merk;
      pruef(n > 0 && anlaufN > 0 && dorfN > 0 && danach > 0 && !falsch && !ueber && !fsUeber && (schulZuzug || !schulStellen),
        `SCHUL_ZUZUG ${schulZuzug}: ${n} Zuzüge (${anlaufN} im Anlauf, davon ${dorfN} für Laden oder Bauhof im Dorf; ${danach} danach; ${schulStellen} für Schulen), alle mit Stelle nach der Regel, nie Kita; falsch ${falsch}, Tage über der Grenze ${ueber}, Tage mit mehr als den freien Stellen ohne Arbeitsuchende der Stadt ${fsUeber}`);
      pruef(tage > 0 && dorfTage > 0 && !zaehlFalsch && !anfrFalsch,
        `SCHUL_ZUZUG ${schulZuzug}: ${tage} Nächte (${dorfTage} im Dorf): freie Stellen gezählt wie die Regel (Kitas${schulZuzug ? '' : ' und Schulen'} nie, Laden und Bauhof nur im Dorf; falsch ${zaehlFalsch}${beispiele.length ? ': ' + beispiele.join(', ') : ''}), Anfragen fürs Bauamt mit der Grundzahl ohne Anlauf (falsch ${anfrFalsch})`);
    }
    // Wirkung (gemessen): erster Zuzug und Einwohner an Tag 60 und 120, mit und ohne Anlauf (Seeds 1–3)
    const wirk = (an) => { const merk = R.ANLAUF_STUFE; if (!an) R.ANLAUF_STUFE = 0; const e = [];
      for (const seed of [1, 2, 3]) { const S = Sim.neueStadt(seed); let erst = -1; const w = [];
        for (let d = 1; d <= 120; d++) { bis(Sim, S, d); if (erst < 0 && S.stat.zuzuege) erst = d; if (d === 60 || d === 120) w.push(S.einwohner); } e.push(`Seed ${seed}: erster Zuzug Tag ${erst}, Tag 60/120 ${w.join('/')}`); }
      R.ANLAUF_STUFE = merk; return e.join('; '); };
    console.log('  gemessen mit Anlauf:  ' + wirk(true));
    console.log('  gemessen ohne Anlauf: ' + wirk(false));
  }

  console.log('D Schalter „Wachstum“');
  {
    const S = Sim.neueStadt(4);
    bis(Sim, S, 60);
    const nr = S.buchNr, a = Sim.wachstumSetzen(S, 1), b = Sim.wachstumSetzen(S, 1);
    const c = [2, '1', null, undefined, -1, 0.5, true, 'schnell'].map(v => Sim.wachstumSetzen(S, v));
    const zeile = S.buch.filter(e => e.nr > nr);
    pruef(a && !b && c.every(x => !x) && S.wachstum === 1 && zeile.length === 1 && zeile[0].art === 'wachstum' && /schneller/.test(zeile[0].text) && !/\u0001/.test(zeile[0].text),
      `an: ${a}, noch einmal: ${b}, ungültige Werte abgelehnt ${c.filter(x => !x).length} von ${c.length}; eine Zeile im Stadtbuch ohne Namen: „${zeile[0] ? zeile[0].text.slice(0, 80) : '–'} …“`);
    bis(Sim, S, 61, 13);
    const text = speichernAlsText(Sim, S), B = ladenAusText(Sim, text);
    let gleich = B.wachstum === 1 && fingerabdruck(Sim, B) === fingerabdruck(Sim, S);
    for (let i = 0; i < 30 && gleich; i++) { bis(Sim, S, S.tag + 1, 13); bis(Sim, B, B.tag + 1, 13); gleich = fingerabdruck(Sim, B) === fingerabdruck(Sim, S); }
    pruef(gleich, `Speichern und Laden mit „schnell“ um 13 Uhr: 30 Tage bitgleich weiter (bis Tag ${S.tag}, ${S.einwohner} Einwohner)`);
    const zurueck = Sim.wachstumSetzen(S, 0), z2 = S.buch[S.buch.length - 1];
    pruef(zurueck && S.wachstum === 0 && z2.art === 'wachstum' && /wieder normal/.test(z2.text), `zurück auf normal: eine Zeile „${z2.text.slice(0, 60)} …“`);
    // Übernahme: Version 8 (stadt.orig.html) → normal, Frist 2 Spielstunden, Zähler bleiben; keine eigene Zeile
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const A = V8.neueStadt(4); bis(V8, A, 150, 13);
    const U = Sim.importZustand(roh(speichernAlsText(V8, A)), true);
    pruef(U.wachstum === 0 && U.ki.fristStunden === R.KI_FRIST && U.ki.abgelaufen === A.ki.abgelaufen && U.ki.angewandt === A.ki.angewandt && !U.buch.some(e => e.art === 'wachstum'),
      `Version 8 übernommen: Schalter normal, KI-Frist ${U.ki.fristStunden} Spielstunden, Zähler übernommen (${U.ki.abgelaufen} zu spät, ${U.ki.angewandt} angewandt), keine Zeile`);
    const L = ladenAusText(Sim, speichernAlsText(Sim, U)); bis(Sim, U, 170); bis(Sim, L, 170);
    pruef(fingerabdruck(Sim, U) === fingerabdruck(Sim, L), 'danach als Version 9 gespeichert und geladen: 20 Tage bitgleich');
    // Beschädigte Stände (Version 9): jedes neue Feld ist Pflicht
    const faelle = [['Schalter fehlt', d => { delete d.werte.wachstum; }], ['Schalter 2', d => { d.werte.wachstum = 2; }], ['Schalter Text', d => { d.werte.wachstum = '1'; }],
      ['Schalter null', d => { d.werte.wachstum = null; }], ['Frist fehlt', d => { delete d.json.ki.fristStunden; }], ['Frist 1', d => { d.json.ki.fristStunden = 1; }],
      ['Frist über der Obergrenze', d => { d.json.ki.fristStunden = R.KI_FRIST_MAX + 1; }], ['Frist 2,5', d => { d.json.ki.fristStunden = 2.5; }], ['Frist Text', d => { d.json.ki.fristStunden = '7'; }],
      ['zu spät negativ', d => { d.json.ki.abgelaufen = -1; }], ['zu spät keine ganze Zahl', d => { d.json.ki.abgelaufen = 1.5; }], ['angewandt fehlt', d => { delete d.json.ki.angewandt; }]];
    const meld = [];
    for (const [was, kaputt] of faelle) {
      const d = roh(text); kaputt(d);
      try { Sim.importZustand(d); meld.push(was + ': angenommen'); } catch (e) { if (!/beschädigt|unvollständig/.test(e.message)) meld.push(was + ': ' + e.message); }
    }
    pruef(!meld.length, `${faelle.length} beschädigte Stände abgelehnt` + (meld.length ? ': ' + meld.join('; ') : ''));
    // „schnell“ wirkt: mehr Einwohner, Grenze 1 + 3 %, Grundzahl und Bauamt doppelt
    const N = Sim.neueStadt(5), Q = Sim.neueStadt(5);
    Sim.wachstumSetzen(Q, 1);
    bis(Sim, N, 150); bis(Sim, Q, 150);
    const wN = X.wachstumJetzt(N), wQ = X.wachstumJetzt(Q);
    const plus = (X, w) => (w.anlauf ? R.ANLAUF_PLUS[X.erweiterung.stufe] : 0);
    pruef(Q.einwohner > N.einwohner && wQ.grenze === 1 + Math.floor(Q.einwohner * R.SCHNELL_ZUZUG_MAX) + plus(Q, wQ)
      && wN.grenze === 1 + Math.floor(N.einwohner * R.ZUZUG_MAX) + plus(N, wN) && wQ.bauamt === R.SCHNELL_BAUAMT && wN.bauamt === 1
      && wQ.basis === (wQ.anlauf ? R.ANLAUF_BASIS[Q.erweiterung.stufe] : 1) * R.SCHNELL_BASIS,
      `schnell (Seed 5, Tag 150): ${Q.einwohner} Einwohner gegen ${N.einwohner} normal; Grenze am Tag ${wQ.grenze} gegen ${wN.grenze}; Grundzahl ×${wQ.basis}, Bauamt ×${wQ.bauamt}`);
    const I = Sim.wachstumInfo(Q);
    pruef(I.schnell && I.zuzugMax === R.SCHNELL_ZUZUG_MAX && I.anlaufBis === R.STUFE_AB[R.ANLAUF_STUFE] && I.fristStunden === R.KI_FRIST, `wachstumInfo: schnell, ${I.zuzugMax * 100} %, Anlauf bis ${I.anlaufBis} Einwohner, Frist ${I.fristStunden} h`);
  }

  console.log('E KI-Frist');
  {
    const S = Sim.neueStadt(2);
    bis(Sim, S, 30);
    const f = (st) => { Sim.kiSchalten(S, true, st); return S.ki.fristStunden; };
    const k = [f(0), f(1), f(7), f(34), f(99), f(2.2), f(NaN), f(-5)];
    Sim.kiSchalten(S, true);
    pruef(JSON.stringify(k) === JSON.stringify([2, 2, 7, 34, R.KI_FRIST_MAX, 3, 2, 2]) && S.ki.fristStunden === 2 && R.KI_FRIST_MAX === 36,
      `Frist in Spielstunden aus 0, 1, 7, 34, 99, 2,2, NaN, −5: ${k.join(', ')} (höchstens ${R.KI_FRIST_MAX}); ohne Angabe bleibt ${S.ki.fristStunden}`);
    const probe = (stunden) => {
      const T = ladenAusText(Sim, speichernAlsText(Sim, S));
      Sim.kiSchalten(T, true, stunden);
      while (T.stunde !== 7) Sim.stunde(T);
      Sim.stunde(T);                                          // 7 Uhr: Hauptfiguren fragen
      const a = T.ki.anfragen[0];
      if (!a) return null;
      const ab0 = T.ki.abgelaufen;
      for (let i = 0; i < 10; i++) Sim.stunde(T);
      const e = Sim.kiEntscheidung(T, a.id, a.gen, a.erlaubt[0], null, 'Test', a.nr);
      return { ok: e.ok, frist: a.frist - (a.tag * 24 + a.stunde), abgelaufen: T.ki.abgelaufen - ab0 };
    };
    const lang = probe(17), kurz = probe(2);
    pruef(!!lang && !!kurz && lang.ok && lang.frist === 17 && !kurz.ok && kurz.frist === 2 && kurz.abgelaufen > 0,
      `Antwort nach 10 Spielstunden: Frist 17 → ${lang && lang.ok ? 'gilt' : 'VERWORFEN'}; Frist 2 → ${kurz && !kurz.ok ? `zu spät (${kurz.abgelaufen} als „zu spät“ gezählt)` : 'FALSCH'}`);
    const T = ladenAusText(Sim, speichernAlsText(Sim, S));
    Sim.kiSchalten(T, true, 2);
    while (T.stunde !== 7) Sim.stunde(T);
    Sim.stunde(T);
    const rest = () => T.ki.anfragen.map(a => a.frist - a.tag * 24 - a.stunde);
    const vor = rest(); Sim.kiSchalten(T, true, 34); const hoch = rest(); Sim.kiSchalten(T, true, 2); const runter = rest();
    pruef(vor.length > 0 && vor.every(x => x === 2) && hoch.every(x => x === 34) && runter.every(x => x === 34) && T.ki.fristStunden === 2,
      `offene Anfragen (${vor.length}): Frist ${vor[0]} → hochgeschaltet ${hoch[0]} → heruntergeschaltet bleibt ${runter[0]} (neue Anfragen wieder ${T.ki.fristStunden})`);
    // Rangfolge des Bürgermeisters: am letzten Tag eines Jahres um 7 Uhr; Frist höchstens bis 23 Uhr (danach plant der Haushalt)
    const rang = (stunden, antwortUm) => {
      const Q = ladenAusText(Sim, speichernAlsText(Sim, S));
      Sim.kiSchalten(Q, true, stunden);
      while (!(Q.tag % J === J - 1 && Q.stunde === 8)) Sim.stunde(Q);   // nach 7 Uhr am letzten Tag des Jahres
      const r = Q.buergermeister.anfrage;
      if (!r) return null;
      const jahr = r.jahr, frist = r.frist - r.tag * 24;
      while (Q.stunde < antwortUm && Q.tag === r.tag) Sim.stunde(Q);
      const e = Sim.bmRangfolge(Q, r.id, r.gen, r.nr, ['parks', 'wohnungen'], 'Test');
      bis(Sim, Q, Q.tag + 1, 1);
      const rf = Q.buergermeister.rangfolge;
      return { frist, ok: e.ok, von: rf && rf.jahr === jahr ? rf.von : '–', plan: Q.haushalt.plan.von, rang: Q.haushalt.plan.rang[0] };
    };
    const r20 = rang(7, 13), r100 = rang(34, 22), spaet = rang(34, 24), kurzR = rang(2, 13);
    pruef(r20 && r20.frist === 14 && r20.ok && r20.plan === 'ki' && r20.rang === 'parks', `Rangfolge mit Frist 7 (20×): bis ${r20 && r20.frist} Uhr, Antwort um 13 Uhr gilt (Plan: ${r20 && r20.plan}, zuerst ${r20 && r20.rang})`);
    pruef(r100 && r100.frist === 23 && r100.ok && r100.plan === 'ki', `Rangfolge mit Frist 34 (100×): höchstens bis ${r100 && r100.frist} Uhr, Antwort um 22 Uhr gilt (Plan: ${r100 && r100.plan})`);
    pruef(spaet && !spaet.ok && spaet.plan === 'regel' && spaet.von === 'regel', `Antwort nach dem Plan (nach 23 Uhr) wird abgelehnt: Regel (${spaet && spaet.plan}, ${spaet && spaet.von})`);
    pruef(kurzR && kurzR.frist === 9 && !kurzR.ok && kurzR.plan === 'regel', `Rangfolge mit Frist 2 (1×): bis ${kurzR && kurzR.frist} Uhr, Antwort um 13 Uhr zu spät (Regel)`);
  }

  console.log('F Kapazität der Warteschlange (nur gemessen): 10 Hauptfiguren und der Bürgermeister, Seed 2 ab Tag 250, 20 Spieltage');
  {
    // Nachbau des KI-Takts der Oberfläche (kiSchritt): ein Aufruf zur Zeit, Rangfolge zuerst, dann die Anfragen der Reihe nach; eine Anfrage geht
    // nicht mehr raus, wenn ihre Restzeit in echter Zeit kürzer ist als min(10 s, Antwortzeit), und wird dann gleich verworfen (Rangfolge: Regel;
    // Entscheidung: normales Gehirn, zählt als „zu spät“; Befund Technik der Schlussprüfung); Frist aus kiFristStunden (mindestens 20 s, bei
    // 11 Figuren 11 × Antwortzeit × 1,2, in Spielstunden 2 bis 36). Jede Antwort ist gültig (erste erlaubte Aktion)
    const B0 = Sim.neueStadt(2); bis(Sim, B0, 250);
    const P = B0.p; B0.ki.haupt = [];
    for (let p = 0; p < B0.pMax && B0.ki.haupt.length < R.HAUPT_MAX; p++) if (P.lebt[p] && B0.tag - P.geb[p] >= 20 * J && B0.tag - P.geb[p] < 60 * J && !Sim.istBm(B0, p)) B0.ki.haupt.push({ id: p, gen: P.gen[p] });
    const basis = speichernAlsText(Sim, B0);
    const zeilen = [];
    for (const tempo of [1, 5, 20, 100]) {
      const z = [];
      for (const t of [1, 2, 3, 5, 10]) {
        const S = ladenAusText(Sim, basis), n = Sim.hauptListe(S).length;
        const fristSek = Math.max(20, n * t * 1.2), stunden = Math.ceil(fristSek * tempo / 60), h = 60 / tempo;   // echte Sekunden je Spielstunde
        Sim.kiSchalten(S, true, stunden);
        const gesendet = new Set(); let frei = 0, arbeit = null, uhr = 0, gueltig = 0, zuSpaetAntw = 0, ungesendet = 0;
        const ab0 = S.ki.abgelaufen, an0 = S.ki.angewandt, ende = S.tag + 20;
        while (S.tag < ende) {
          const naechste = uhr + h;
          while (true) {                                      // alles, was bis zur nächsten Stunde fertig wird oder rausgeht
            if (arbeit && arbeit.fertig <= naechste) {
              const a = arbeit; arbeit = null; frei = a.fertig;
              if (a.rang) { if (Sim.bmRangfolge(S, a.id, a.gen, a.nr, ['wohnungen'], 'Test').ok) gueltig++; else zuSpaetAntw++; }
              else { const e = Sim.kiErlaubtJetzt(S, a.id, a.gen); if (!e.length) Sim.kiVerwerfen(S, a.id, a.gen, a.nr); else if (Sim.kiEntscheidung(S, a.id, a.gen, e[0], null, 'Test', a.nr).ok) gueltig++; else zuSpaetAntw++; }
            }
            if (arbeit) break;
            const jetzt = Math.max(frei, uhr), jetztH = S.tag * 24 + S.stunde + (jetzt - uhr) / h;
            const reicht = (x) => (x.frist + 1 - jetztH) * h >= Math.min(10, t);
            const r = S.buergermeister.anfrage;
            let q = null;
            if (r && !gesendet.has(r.nr)) { gesendet.add(r.nr); if (reicht(r)) q = { rang: true, id: r.id, gen: r.gen, nr: r.nr }; else Sim.bmRangfolge(S, r.id, r.gen, r.nr, null, ''); }
            if (!q) for (const x of S.ki.anfragen.slice()) { if (gesendet.has(x.nr)) continue; gesendet.add(x.nr); if (reicht(x)) { q = { id: x.id, gen: x.gen, nr: x.nr }; break; } Sim.kiVerwerfen(S, x.id, x.gen, x.nr, true); ungesendet++; }
            if (!q) break;
            q.fertig = jetzt + t; arbeit = q;
            if (q.fertig > naechste) break;
          }
          Sim.stunde(S); uhr += h; frei = Math.max(frei, 0);
        }
        const ki = S.ki.angewandt - an0, spaet = S.ki.abgelaufen - ab0;
        z.push(`${t} s: ${ki} KI / ${spaet} zu spät, davon ${ungesendet} ungesendet (Frist ${S.ki.fristStunden} h = ${Math.round(S.ki.fristStunden * h)} s)`);
      }
      zeilen.push(`  ${String(tempo).padStart(3)}×  ` + z.join(' | '));
    }
    console.log(zeilen.join('\n'));
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zu „Wachstum, Tempo und KI“ bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('techfrueh')) {
  // Tech-Firmen früher und mehr (Version 9, Teil 5). A statisch: die Regeln des Bausteins würfeln nicht und lesen von Personen nur Fleiß, Ehrgeiz,
  // Geld und Wohnung (gruendungsTyp); die Zahlen der Karten im Fenster „Stadtregierung“ passen zu R. B ausgeschaltet (TECH_FRUEH 0, WELT 0) und ohne
  // die übrigen Bausteine von Version 9 Tag für Tag wie 31ce452 (stadt.orig.html); mit --alt <Fassung vor Teil 5>: ausgeschaltet und ohne Vorhaben
  // des Haushalts Tag für Tag wie diese, mit Vorhaben gleich bis zum ersten Computerkauf der Schulen (der ist jetzt Bedarf vor den Vorhaben).
  // C Seeds 1–3, 730 Tage stündlich: je Gründung (Stufe, Bremse, Preis, Markt, Tüftler im Dorf), je Nacht (freie Tech-Stellen und Stellen in der Welt
  // unabhängig nachgezählt, Preis der Welt, Grenze der Welt, 40 % nur im Umland, Markt nur bei Tech-Firmen, nichts ruht in der Welt), jede Pleite
  // (Zeile „gibt auf“ genau dann, wenn der Betrieb nie eine Kraft hatte), jeder Computerkauf der Schulen (Laden der Stadt oder außerhalb, Geld).
  // D Speichern mit Firmen in der Welt bitgleich; beschädigte Stände; Übernahme von Version 8 (alle im Umland, Bremse gleich gezählt). E Namenstausch.
  // F Messung und Gruppen (nur gemessen)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, T = Sim._tech9, TECH = Sim.TECH, WERKSTATT = Sim.WERKSTATT, LADEN = Sim.LADEN;
  const simCode = (h) => h.match(/<script id="sim">([\s\S]*?)<\/script>/)[1];
  const lade = (code) => { const ctx = vm.createContext({}); vm.runInContext(`Math.random = () => { throw new Error('Math.random'); };`, ctx); vm.runInContext(code, ctx); return ctx.StadtSim; };
  const bis = (Y, S, tag, stunde = 0) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) Y.stunde(S); };
  const tsd = (v) => String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const kanon = (o) => JSON.stringify(o, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) && !ArrayBuffer.isView(v) ? Object.fromEntries(Object.keys(v).sort().map(x => [x, v[x]])) : v));
  const drittel = (v) => { const n = Math.round(v * 3), g = Math.floor(n / 3), r = n % 3; return tsd(g) + (r === 1 ? '⅓' : r === 2 ? '⅔' : ''); };

  console.log('A Statisch');
  {
    const ohneKomm = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
    const code = ohneKomm(SIM_CODE);
    const koerper = (f) => {
      const i = code.search(new RegExp('^function ' + f + '\\(', 'm')); if (i < 0) return null;
      let t = 0, j = code.indexOf('{', i);
      for (; j < code.length; j++) { if (code[j] === '{') t++; else if (code[j] === '}' && --t === 0) break; }
      return code.slice(i, j + 1); };
    const ohneBuch = (k) => { let out = '', i = 0;
      for (;;) { const j = k.indexOf('buch(S,', i); if (j < 0) { out += k.slice(i); break; }
        out += k.slice(i, j); let t = 0, m = j + 4;
        for (; m < k.length; m++) { if (k[m] === '(') t++; else if (k[m] === ')' && --t === 0) break; }
        i = m + 1; }
      return out; };
    const felder = (k) => [...new Set([...k.matchAll(/\b(?:S\.)?P\.(\w+)|\bS\.p\.(\w+)/g)].map(m => m[1] || m[2]))].sort();
    // Je Funktion des Bausteins: welche Personenfelder sie lesen darf (Stadtbuch-Zeilen ausgenommen: dort stehen Namen und Pronomen)
    const ERLAUBT = { gruendungsTyp: ['ehrgeiz', 'fleiss', 'geld', 'wohnung'], techWeltAussicht: ['ehrgeiz', 'fleiss'], gruendungsKosten: [], techGruendungJetzt: [],
      techMarkt: [], weltPlatzFuer: [], anbauKosten: [], anbauMarkt: [], marktPlaetzeDazu: [], techFreiZaehlen: [], migriereTech9: [],
      tech9Pruefen: [], schulITKaufen: [], ladenNaechst: [], hhComputer: [], techInfo: [], marktSatz: [], pleite: [], techGrenzeHalten: [] };
    const zuViel = [];
    for (const [f, ok] of Object.entries(ERLAUBT)) {
      const k0 = koerper(f);
      if (!k0) { zuViel.push(f + ': fehlt'); continue; }
      const k = ohneBuch(k0);
      for (const x of felder(k)) if (!ok.includes(x)) zuViel.push(`${f}: P.${x}`);
      if (/\b(name|vorname|nr|namePack|nameAusPack|ref|personInfo)\s*\(/.test(k)) zuViel.push(`${f}: Name`);
      if (/\b(zufall|zInt|zufallSich|zufallAuto|zIntAuto|wahlZufall)\s*\(/.test(k)) zuViel.push(`${f}: Zufall`);
    }
    pruef(!zuViel.length, `${Object.keys(ERLAUBT).length} Funktionen würfeln nicht und lesen von Personen nur Fleiß, Ehrgeiz, Geld und Wohnung (gruendungsTyp, techWeltAussicht), `
      + 'keine Namen, kein Geschlecht, keine Herkunft (Stadtbuch-Zeilen ausgenommen)' + (zuViel.length ? ': ' + zuViel.join(', ') : ''));
    // Die Karten im Fenster „Stadtregierung“ nennen die Zahlen fest (REGIERUNG ist reiner Text): Sie müssen zu R passen
    const a0 = html.indexOf('const REGIERUNG = '), b0 = html.indexOf('// Ende REGIERUNG');
    const REG = new Function(html.slice(a0, b0).replace('const REGIERUNG = ', 'return ').replace(/;\s*$/, ''))();
    const karte = (re) => { for (const [, regeln] of REG.gruppen) for (const r of regeln) if (re.test(r.titel)) return r; return null; };
    const kt = karte(/^Tech-Firmen wachsen, Autowerke, Autos$/), kw = karte(/^Weltmarkt für Software, Handys und Computer$/), k5 = karte(/^R-A5 /);
    const preis = (z) => tsd(Math.round(R.BAU_ANBAU[z] * R.TECH_SATZ));
    const sollT = [`ab ${R.TECH_TUEFTLER})`, `ab der ${['Dorf', 'Kleinstadt', 'Stadt', 'Großstadt'][R.TECH_AB_STUFE]}`, `zusammen ${R.TECH_FREI_MAX} oder mehr Stellen`,
      `${drittel(R.TECH_SATZ)} Taler je Arbeitstag`, `Gründung (${tsd(Math.round(R.BAU_TECH * R.TECH_SATZ))} Taler)`, `Stufe 2 und 3 ${preis(2)} und ${preis(3)}`,
      `Campus ${preis(4)}, Hochhaus ${preis(5)} Taler`];
    const sollW = [`zusammen ${tsd(R.WELT)} Taler am Tag`, `höchstens ${R.EXPORT_MAX} Taler`, `danach noch ${R.LOHN_TECH + 8} Taler bringt (Lohn und 8 Taler`];
    const sollWA = [`${tsd(R.WELT)} Taler am Tag reichen für rund ${Math.floor(R.WELT / (R.LOHN_TECH + 8))} Stellen`];
    const sollA5 = [`kostet ${drittel(R.TECH_SATZ)} Taler je Arbeitstag`, `Campus kostet damit ${preis(4)} statt ${tsd(R.K_ANBAU[4])}`, `Hochhaus ${preis(5)} statt ${tsd(R.K_ANBAU[5])}`];
    // Teil 5: die Preise stehen im aufklappbaren Teil der Karte (mehr), die übrigen Zahlen im Text
    const ktText = kt ? kt.stadt + ' ' + (kt.mehr || []).map(m => m[1]).join(' ') : '';
    const fehlt = [...sollT.filter(t => !kt || !ktText.includes(t)), ...sollW.filter(t => !kw || !kw.stadt.includes(t)), ...sollWA.filter(t => !kw || !kw.annahme.includes(t)),
      ...sollA5.filter(t => !k5 || !k5.hinweis.includes(t))];
    pruef(!!kt && !!kw && !!k5 && !fehlt.length && kw.status === 'Spielregel' && k5.status === 'Auslegung' && kw.live === 'welt' && kw.zitate.length === 1 && kw.zitate[0][1] === 11,
      `Karten „Tech-Firmen wachsen …“, „Weltmarkt …“ (Spielregel, Live-Zeile, ein Zitat S. 11) und R-A5 (Auslegung): Zahlen passen zu R` + (fehlt.length ? ` – fehlt: ${fehlt.join(' | ')}` : ''));
    const s16 = (REG.nicht || []).flatMap(x => x.punkte || []).find(x => Array.isArray(x) && x[1] === 16 && /Unternehmensgründungen/.test(x[0]));
    pruef(!!s16 && /Spielregeln für Gründer, keine Vorschriften/.test(s16[2]), 'S. 16 unter „nicht“: Kleinstadt und Bremse als Spielregeln für Gründer, keine Vorschriften der Stadt');
  }

  console.log('B Ausgeschaltet wie vorher');
  {
    const spur = (S, ohneG) => { const x = createHash('sha256');
      for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n]) && n !== 'schule') { const a = S.p[n], w = a.length / S.pKap; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) { if (ohneG.has(n)) continue; const a = S.g[n]; x.update(n); x.update(Buffer.from(a.buffer, a.byteOffset, S.gAnzahl * a.BYTES_PER_ELEMENT)); }
      x.update(Buffer.from(S.feld.buffer)); const st = statAlt(S.stat);
      x.update(JSON.stringify([S.budget, S.rs, S.rsSich, S.rsAuto, S.tag, S.einwohner, st, kiAlt(S.ki), S.regierung, S.sicherheit, S.bund, S.erweiterung])); x.update(JSON.stringify(S.buch));
      return x.digest('hex').slice(0, 16); };
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const V9 = ['RATHAUS', 'SCHULEN', 'HH_VORHABEN', 'HH_STEUER', 'ANLAUF_STUFE', 'TECH_FRUEH', 'WELT', 'ZUZUG_GENAU'], alt = V9.map(k => R[k]);   // alle Bausteine von Version 9 aus
    for (const k of V9) R[k] = 0;
    let techGr = 0;                                          // über die drei Seeds muss es Tech-Gründungen geben
    for (const seed of [1, 2, 3]) {
      const A = V8.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1;
      for (let d = 1; d <= 200 && erster < 0; d++) { bis(V8, A, d); bis(Sim, B, d); if (spur(A, new Set()) !== spur(B, new Set(Sim.GF_TECH9))) erster = d; }
      techGr += B.stat.tech.gruendungen;
      pruef(erster < 0 && (seed < 3 || techGr > 0), `Seed ${seed}, TECH_FRUEH 0 und WELT 0, ohne die übrigen Bausteine von Version 9: 200 Tage ${erster < 0 ? 'jeden Tag wie 31ce452' : 'VERSCHIEDEN ab Tag ' + erster}`
        + ` (${B.einwohner} Einwohner, ${B.stat.tech.gruendungen} Tech-Gründungen)`);
    }
    V9.forEach((k, i) => { R[k] = alt[i]; });
    if (arg('alt')) {                                         // die Fassung vor Teil 5
      const V = lade(simCode(readFileSync(arg('alt'), 'utf8')));
      const f = (Y, S, ohneBuch) => { const d = Y.exportZustand(S), h = createHash('sha256');
        for (const a of d.arrays.sort((x, y) => (x.name < y.name ? -1 : 1))) { if (a.name === 'g.markt' || a.name === 'g.kraft') continue; h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
        const w = { ...d.werte }; delete w.techFrei; delete w.weltPlaetze; delete w.weltPreis;
        // Haushalt und Rangfolge ohne Vergleich: die Liste der Vorhaben ist jetzt kürzer (Computer sind Bedarf); das Budget steht in werte
        const bm = d.json.buergermeister, j = { ...d.json, haushalt: undefined, buch: ohneBuch ? undefined : d.json.buch.map(e => ({ ...e, text: textAlt(e.text) })), buergermeister: bm ? { ...bm, rangfolge: undefined, anfrage: undefined } : bm,
          stat: { ...statAlt(d.json.stat), sicherheit: d.json.stat.sicherheit, bund: d.json.stat.bund, auto: d.json.stat.auto, rathaus: d.json.stat.rathaus,
            buergermeister: d.json.stat.buergermeister, schule: d.json.stat.schule ? { ...d.json.stat.schule, itAussen: undefined } : undefined, regierung: d.json.stat.regierung } };
        h.update(JSON.stringify(w)); h.update(kanon(j)); return h.digest('hex').slice(0, 16); };
      const merk = [R.TECH_FRUEH, R.WELT, R.HH_VORHABEN, R.ZUZUG_GENAU], vh = V.R.HH_VORHABEN;
      R.TECH_FRUEH = 0; R.WELT = 0; R.HH_VORHABEN = 0; V.R.HH_VORHABEN = 0; R.ZUZUG_GENAU = 0;   // Zuzug wie in der Fassung vor Teil 5 (Schlussprüfung)
      for (const seed of [1, 2, 3]) {
        const A = V.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1;
        for (let d = 1; d <= 200 && erster < 0; d++) { bis(V, A, d); bis(Sim, B, d); if (f(V, A) !== f(Sim, B)) erster = d; }
        pruef(erster < 0, `Seed ${seed}, TECH_FRUEH 0, WELT 0, Vorhaben aus (in beiden): 200 Tage ${erster < 0 ? 'jeden Tag wie ' + arg('alt') : 'VERSCHIEDEN ab Tag ' + erster} (${B.einwohner} Einwohner)`);
      }
      R.HH_VORHABEN = merk[2]; V.R.HH_VORHABEN = vh;
      // Mit Vorhaben: gleich bis zur ersten Nacht, in der die Schulen Computer kaufen (vorher Vorhaben 3 in der Rangfolge, jetzt Bedarf davor)
      for (const seed of [2]) {
        const A = V.neueStadt(seed), B = Sim.neueStadt(seed); let erster = -1, kauf = -1;
        for (let d = 1; d <= 400 && erster < 0; d++) { bis(V, A, d); bis(Sim, B, d); if (kauf < 0 && (A.stat.schule.itGeraete || B.stat.schule.itGeraete)) kauf = d; if (f(V, A, true) !== f(Sim, B, true)) erster = d; }
        pruef(kauf > 0 && (erster < 0 || erster >= kauf), `Seed ${seed}, TECH_FRUEH 0, WELT 0, mit Vorhaben: gleich bis Tag ${erster < 0 ? 400 : erster - 1}, der erste Computerkauf der Schulen war an Tag ${kauf}`
          + ' (ohne Plan, Rangfolge und Stadtbuch verglichen: die Liste der Vorhaben ist jetzt kürzer, die Zeilen nennen den Rang)');
      }
      [R.TECH_FRUEH, R.WELT, R.HH_VORHABEN, R.ZUZUG_GENAU] = merk;
    } else console.log('  (ohne --alt: kein Vergleich mit der Fassung vor Teil 5)');
  }

  console.log('C Je Gründung, je Nacht, je Pleite, je Computerkauf (Seeds 1–3, 730 Tage stündlich)');
  const { Sim: M, ctx: mc } = ladeSimMit([
    ['G.StadtSim = {', 'G.StadtSim = { __offen: offen,'],
    ['function aktGruenden(S, p) {', 'function aktGruenden(S, p) {\n  const __v = globalThis.__vor ? globalThis.__vor(S, p) : null, __r = __aktGruenden(S, p);\n  if (__v) globalThis.__nach(S, p, __v, __r);\n  return __r;\n}\nfunction __aktGruenden(S, p) {'],
    ['  S.freieWohnungen = fw; S.freieStellen = fs; S.leerstand = leer; S.werkstattPlaetze = wp; S.techPlaetze = tp; S.weltPlaetze = wt; S.techFrei = tf;',
      '  S.freieWohnungen = fw; S.freieStellen = fs; S.leerstand = leer; S.werkstattPlaetze = wp; S.techPlaetze = tp; S.weltPlaetze = wt; S.techFrei = tf;\n  if (globalThis.__kz) globalThis.__kz(S);'],
    ['  S.weltPreis = R.WELT > 0 ? Math.min(R.EXPORT_MAX, R.WELT / Math.max(1, weltArbeiter)) : 0;',
      '  S.weltPreis = R.WELT > 0 ? Math.min(R.EXPORT_MAX, R.WELT / Math.max(1, weltArbeiter)) : 0;\n  if (globalThis.__preis) globalThis.__preis(S, exportArbeiter, weltArbeiter);'],
    ['function pleite(S, b) {', 'function pleite(S, b) {\n  if (globalThis.__pleite) globalThis.__pleite(S, b);'],
    ['  S.p.arbeit[p] = b; S.belegschaft[b].push(p);', '  S.p.arbeit[p] = b; S.belegschaft[b].push(p);\n  if (globalThis.__an) globalThis.__an(S, b);'],
    ['function schliessen(S, b, pleite) {', 'function schliessen(S, b, pleite) {\n  if (globalThis.__zu) globalThis.__zu(S, b);'],
    ['function umzugInsWerk(S, alt, w) {', 'function umzugInsWerk(S, alt, w) {\n  if (globalThis.__umzug) globalThis.__umzug(S, alt, w);'],
    ['function schulITKaufen(S, taler) {', 'function schulITKaufen(S, taler) {\n  const __v = globalThis.__itVor ? globalThis.__itVor(S) : null, __r = __schulITKaufen(S, taler);\n  if (__v) globalThis.__itNach(S, __v, __r);\n  return __r;\n}\nfunction __schulITKaufen(S, taler) {'],
  ]);
  const MT = M._tech9;
  const Z = { gr: 0, tech: 0, welt: 0, uebern: 0, dorfTuef: 0, nachte: 0, aufgabe: 0, pleiteMit: 0, it: 0, itLaden: 0, itAussen: 0, preis: 0, kleinstadtZeile: 0 };
  const F = new Map(), fehl = (k, t) => { if (!F.has(k)) F.set(k, []); if (F.get(k).length < 3) F.get(k).push(t); F.get(k).n = (F.get(k).n || 0) + 1; };
  let kraft = new Set();                                     // unabhängig: Betriebe mit Besitz, die seit Gründung oder Übernahme eine Kraft hatten
  const tuef = (S, p) => S.p.fleiss[p] + S.p.ehrgeiz[p] >= R.TECH_TUEFTLER;
  mc.__vor = (S, p) => ({ typ: MT.gruendungsTyp(S, p), stufe: S.erweiterung.stufe, frei: S.techFrei, geld: S.p.geld[p], tuef: tuef(S, p), lohnt: R.UMLAND / (S.werkstattPlaetze + R.STELLEN_WERKSTATT) >= R.LOHN_WERKSTATT + 8,
    wp: S.werkstattPlaetze, tp: S.techPlaetze, wt: S.weltPlaetze, leerTech: S.leerTyp[TECH] });
  mc.__nach = (S, p, v, ok) => {
    if (!ok) return;
    const b = S.p.besitz[p], g = S.g; Z.gr++;
    if (v.tuef && v.stufe < R.TECH_AB_STUFE && v.typ !== LADEN) fehl('dorf', `Tag ${S.tag}: Tüftler gründet im Dorf (${v.typ})`);
    if (v.tuef && v.stufe < R.TECH_AB_STUFE) Z.dorfTuef++;
    kraft.delete(b);
    if (g.typ[b] !== TECH) return;
    Z.tech++; const st = Sim.stellen(S, b), neu = S.baustellen.includes(b) && !g.auf[b], werk = !!g.werk[b];
    if (!neu) Z.uebern++;
    if (v.stufe < R.TECH_AB_STUFE) fehl('stufe', `Tag ${S.tag}: Tech-Firma im Dorf`);
    if (v.frei >= R.TECH_FREI_MAX) fehl('bremse', `Tag ${S.tag}: ${v.frei} Stellen frei, trotzdem gegründet`);
    if (S.techFrei !== v.frei + st) fehl('frei', `Tag ${S.tag}: techFrei ${S.techFrei} statt ${v.frei} + ${st}`);
    const kosten = MT.gruendungsKosten(TECH, !neu, werk && !neu);
    if (v.geld - S.p.geld[p] !== kosten) fehl('preis', `Tag ${S.tag}: bezahlt ${v.geld - S.p.geld[p]} statt ${kosten}`);
    if (neu && kosten !== Math.round(R.BAU_TECH * R.TECH_SATZ) + R.KASSE_START) fehl('preis', `Tag ${S.tag}: Gründung ${kosten}`);
    // Im Markt belegt die Firma die Stellen des Hauses samt einem offenen Anbau (übernommenes leeres Haus, dessen Anbau noch läuft), wie die
    // Zählung der Nacht (Befund der Schlussprüfung: vorher nur die Stufe, danach lag der Weltmarkt über seiner Grenze); freie Stellen nach der Stufe
    const mp = R.TECH_STELLEN[g.auf[b] || g.stufe[b]] - g.ruht[b];
    if (g.auf[b] && !neu) Z.mitAnbau = (Z.mitAnbau || 0) + 1;
    const umland = v.lohnt && v.tp + mp <= R.TECH_ANTEIL * (v.wp + mp), welt = R.WELT / (v.wt + mp) >= R.LOHN_TECH + 8;
    if (g.markt[b] === 0 && !umland) fehl('markt', `Tag ${S.tag}: Umland ohne Platz (wp ${v.wp}, tp ${v.tp}, +${mp})`);
    if (g.markt[b] === 1 && (umland || !welt)) fehl('markt', `Tag ${S.tag}: Welt, obwohl ${umland ? 'das Umland Platz hatte' : 'die Welt keinen Platz hatte'} (wt ${v.wt}, +${mp})`);
    if (g.markt[b] === 1) { Z.welt++; if (S.weltPlaetze !== v.wt + mp) fehl('markt', `Tag ${S.tag}: weltPlaetze ${S.weltPlaetze} statt ${v.wt} + ${mp}`); }
    else if (S.techPlaetze !== v.tp + mp || S.werkstattPlaetze !== v.wp + mp) fehl('markt', `Tag ${S.tag}: Umland-Stellen nicht mitgezählt`);
  };
  mc.__an = (S, b) => { const g = S.g; if ((g.typ[b] === WERKSTATT || g.typ[b] === TECH) && g.besitzer[b] >= 0) kraft.add(b); };
  mc.__zu = (S, b) => { kraft.delete(b); };
  mc.__umzug = (S, alt, w) => { if (kraft.has(alt)) kraft.add(w); kraft.delete(alt); };
  let pleiten = [];
  mc.__pleite = (S, b) => { const g = S.g; pleiten.push({ b, nr: S.buchNr, ohne: (g.typ[b] === WERKSTATT || g.typ[b] === TECH) && !kraft.has(b), typ: g.typ[b], kraft: g.kraft[b] }); };
  mc.__preis = (S, ea, wa) => {
    const g = S.g, P = S.p; let e = 0, w = 0;
    for (let b = 0; b < S.gAnzahl; b++) { const t = g.typ[b]; if ((t !== WERKSTATT && t !== TECH) || g.leer[b] || S.feld[g.y[b] * S.karte + g.x[b]] !== t) continue;
      let n = 0; for (const q of S.belegschaft[b]) if (!P.frei[q] && !P.einsatz[q] && P.bund[q] !== Sim.ERSATZDIENST) n++;
      if (t === TECH && g.markt[b]) w += n; else e += n; }
    Z.preis++;
    if (e !== ea || w !== wa || S.weltPreis !== (R.WELT > 0 ? Math.min(R.EXPORT_MAX, R.WELT / Math.max(1, w)) : 0)) fehl('weltpreis', `Tag ${S.tag}: Arbeitstage ${ea}/${wa} statt ${e}/${w}, Preis ${S.weltPreis}`);
  };
  mc.__kz = (S) => {
    const g = S.g; let tf = 0, wt = 0, tp = 0, wp = 0;
    for (let b = 0; b < S.gAnzahl; b++) { const t = g.typ[b];
      if (t === WERKSTATT && !g.leer[b]) wp += b === S.bauhof ? R.STELLEN_STADT : Sim.stellen(S, b);
      if (t !== TECH) { if (g.markt[b]) fehl('feld', `Tag ${S.tag}: Markt bei Typ ${t}`); continue; }
      if (g.markt[b] && g.ruht[b]) fehl('ruht', `Tag ${S.tag}: Firma in der Welt mit ruhenden Stellen`);
      if (g.leer[b]) continue;
      const n = Sim.techPlaetzeVon(S, b); if (g.markt[b]) wt += n; else { tp += n; wp += n; }
      if (g.besitzer[b] >= 0) tf += Math.max(0, R.TECH_STELLEN[g.stufe[b]] - g.ruht[b] - S.belegschaft[b].length); }
    Z.nachte++;
    if (tf !== S.techFrei || wt !== S.weltPlaetze || tp !== S.techPlaetze || wp !== S.werkstattPlaetze) fehl('zaehl', `Tag ${S.tag}: frei ${S.techFrei}/${tf}, Welt ${S.weltPlaetze}/${wt}, Tech ${S.techPlaetze}/${tp}, Umland ${S.werkstattPlaetze}/${wp}`);
    if (wt > 0 && R.WELT / wt < R.LOHN_TECH + 8 - 1e-9) fehl('weltgrenze', `Tag ${S.tag}: ${wt} Stellen in der Welt, ein Arbeitstag ${(R.WELT / wt).toFixed(1)}`);
  };
  let it = null;
  mc.__itVor = (S) => { const g = S.g, f = S.angebot[Sim.COMPUTER] >= 0 && M.__offen(S, S.angebot[Sim.COMPUTER]) ? S.angebot[Sim.COMPUTER] : -1, kassen = new Map();
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === LADEN) kassen.set(b, g.kasse[b]);
    return { f, umsatz: f >= 0 ? g.umsatz[f] : 0, budget: S.budget, kassen, bedarf: M.schulITBedarf(S) }; };
  mc.__itNach = (S, v, r) => {
    const g = S.g, anteil = Math.round(R.PREIS[Sim.COMPUTER] * R.LADEN_ANTEIL); Z.it += r.geraete;
    if (!r.geraete) return;
    let kasse = 0; for (const [b, k] of v.kassen) kasse += g.kasse[b] - k;
    const stadtAnteil = S.budget - (v.budget - r.taler);
    if (r.taler !== r.geraete * R.PREIS[Sim.COMPUTER]) fehl('it', `Tag ${S.tag}: ${r.taler} Taler für ${r.geraete} Computer`);
    if (v.f < 0) { Z.itAussen += r.geraete; if (r.aussen !== r.geraete || stadtAnteil !== 0 || kasse !== 0) fehl('it', `Tag ${S.tag}: ohne Computer der Stadt im Regal, aber Geld an Läden oder Firmen`); return; }
    Z.itLaden += r.geraete - r.aussen;
    const imLaden = r.geraete - r.aussen;
    if (r.aussen || g.umsatz[v.f] - v.umsatz !== imLaden * (R.PREIS[Sim.COMPUTER] - anteil) || kasse + stadtAnteil !== imLaden * anteil)
      fehl('it', `Tag ${S.tag}: ${r.geraete} Computer, Firma +${g.umsatz[v.f] - v.umsatz}, Läden +${kasse}, Laden der Stadt +${stadtAnteil}`);
    for (const [b, n] of v.bedarf.schulen) { void n; const l = MT.ladenNaechst(S, g.x[b], g.y[b]);
      let best = -1, bd = 1e9; for (let q = 0; q < S.gAnzahl; q++) if (g.typ[q] === LADEN && M.__offen(S, q)) { const d = Math.abs(g.x[q] - g.x[b]) + Math.abs(g.y[q] - g.y[b]); if (d < bd) { bd = d; best = q; } }
      if (l !== best) fehl('it', `Tag ${S.tag}: Laden ${l} statt ${best}`); }
  };
  for (const seed of [1, 2, 3]) {
    const S = M.neueStadt(seed); kraft = new Set(); let buchNr = 0;
    while (S.tag < 730) {
      const t0 = S.tag; M.stunde(S);
      for (const pl of pleiten) {                            // die Zeile jeder Pleite: „gibt auf“ genau ohne je eine Kraft
        const e = S.buch.find(x => x.nr > pl.nr && (x.art === 'pleite' || x.art === 'aufgabe'));
        if (!e) { fehl('aufgabe', `Tag ${S.tag}: keine Zeile zur Pleite`); continue; }
        if (e.art === 'aufgabe') Z.aufgabe++; else Z.pleiteMit++;
        if ((e.art === 'aufgabe') !== pl.ohne || (pl.ohne && pl.kraft) || (!pl.ohne && pl.typ !== LADEN && !pl.kraft)) fehl('aufgabe', `Tag ${S.tag}: ${e.art} bei ${pl.ohne ? 'nie' : 'schon'} einer Kraft (Feld ${pl.kraft})`);
        if (e.art === 'aufgabe' && !/fand keine Leute/.test(e.text)) fehl('aufgabe', 'Text');
      }
      pleiten = [];
      if (S.tag !== t0) {
        for (const e of S.buch) if (e.nr > buchNr && e.art === 'stufe' && /Kleinstadt/.test(e.text)) { Z.kleinstadtZeile++; if (!/Tech-Firmen, sobald Tüftler sie gründen/.test(e.text)) fehl('stufe', 'Zeile der Kleinstadt ohne Tech-Firmen'); }
        buchNr = S.buchNr;
        if (S.techPlaetze > R.TECH_ANTEIL * S.werkstattPlaetze + 1e-9) fehl('grenze', `Tag ${S.tag}: Tech im Umland ${S.techPlaetze} von ${S.werkstattPlaetze}`);
        try { T.tech9Pruefen(S, true); } catch (e) { fehl('pruefen', `Tag ${S.tag}: ${e.message}`); }
      }
    }
  }
  for (const k of ['dorf', 'stufe', 'bremse', 'frei', 'preis', 'markt']) pruef(!F.has(k), `Gründungen (${Z.gr}, davon ${Z.tech} Tech-Firmen, ${Z.uebern} Übernahmen, ${Z.mitAnbau || 0} davon mit offenem Anbau, ${Z.welt} in die Welt; Tüftler im Dorf: ${Z.dorfTuef}): ${k}` + (F.has(k) ? ` ${F.get(k).n}× – ${F.get(k).join('; ')}` : ' ok'));
  pruef(!F.has('zaehl') && !F.has('weltgrenze') && !F.has('feld') && !F.has('ruht') && !F.has('grenze') && !F.has('pruefen'), `${Z.nachte} Nächte: freie Tech-Stellen, Stellen in der Welt, Tech- und Umland-Stellen unabhängig nachgezählt, Grenze der Welt, 40 % nur im Umland, Markt nur bei Tech-Firmen, nichts ruht in der Welt, tech9Pruefen`
    + ['zaehl', 'weltgrenze', 'feld', 'ruht', 'grenze', 'pruefen'].filter(k => F.has(k)).map(k => ` – ${k}: ${F.get(k).join('; ')}`).join(''));
  pruef(!F.has('weltpreis') && Z.preis > 0, `${Z.preis} Nächte: Preis je Arbeitstag in der Welt = min(${R.EXPORT_MAX}, ${R.WELT} / Arbeitstage in der Welt), Arbeitstage unabhängig gezählt` + (F.has('weltpreis') ? ' – ' + F.get('weltpreis').join('; ') : ''));
  pruef(!F.has('aufgabe') && Z.aufgabe > 0 && Z.pleiteMit > 0, `Pleiten: ${Z.aufgabe}-mal „gibt auf, fand keine Leute“ (nie eine Kraft), ${Z.pleiteMit}-mal „pleite“ (mit Kraft oder Laden)` + (F.has('aufgabe') ? ' – ' + F.get('aufgabe').join('; ') : ''));
  pruef(!F.has('it') && Z.it > 0 && Z.itLaden > 0, `Computer der Schulen: ${Z.it} gekauft, ${Z.itLaden} aus einem Laden der Stadt (nächster Laden, Anteil des Ladens, Rest an die Firma), ${Z.itAussen} von außerhalb (nur ohne Computer der Stadt im Regal)`
    + (F.has('it') ? ' – ' + F.get('it').join('; ') : ''));
  pruef(!F.has('stufe') && Z.kleinstadtZeile === 3, `Stadtbuch: die Zeile zur Kleinstadt nennt „Tech-Firmen, sobald Tüftler sie gründen“ (${Z.kleinstadtZeile} von 3)`);

  console.log('D Speichern, beschädigte Stände, Übernahme von Version 8');
  {
    const A = Sim.neueStadt(1); bis(Sim, A, 420, 13);
    const welt = Sim.techInfo(A).weltFirmen, text = speichernAlsText(Sim, A), B = ladenAusText(Sim, text);
    const g0 = fingerabdruck(Sim, A) === fingerabdruck(Sim, B);
    bis(Sim, A, 450, 13); bis(Sim, B, 450, 13);
    pruef(welt > 0 && g0 && fingerabdruck(Sim, A) === fingerabdruck(Sim, B), `Seed 1, gespeichert an Tag 420 um 13 Uhr mit ${welt} Firmen in der Welt: 30 Tage bitgleich (${fingerabdruck(Sim, A)})`);
    const kaputt = [
      ['Markt 2', (d) => { const a = d.arrays.find(x => x.name === 'g.markt'); const u = Buffer.from(a.b64, 'base64'); const b = A.g.typ.findIndex((t, i) => i < A.gAnzahl && t === TECH); u[b] = 2; a.b64 = u.toString('base64'); }],
      ['Markt bei einer Werkstatt', (d) => { const a = d.arrays.find(x => x.name === 'g.markt'); const u = Buffer.from(a.b64, 'base64'); u[A.bauhof] = 1; a.b64 = u.toString('base64'); }],
      ['Kraft bei einem Laden', (d) => { const a = d.arrays.find(x => x.name === 'g.kraft'); const u = Buffer.from(a.b64, 'base64'); const b = A.g.typ.findIndex((t, i) => i < A.gAnzahl && t === LADEN); u[b] = 1; a.b64 = u.toString('base64'); }],
      ['techFrei −1', (d) => { d.werte.techFrei = -1; }], ['techFrei 1,5', (d) => { d.werte.techFrei = 1.5; }], ['techFrei fehlt', (d) => { delete d.werte.techFrei; }],
      ['weltPreis 150', (d) => { d.werte.weltPreis = 150; }], ['weltPreis fehlt', (d) => { delete d.werte.weltPreis; }], ['weltPlaetze fehlt', (d) => { delete d.werte.weltPlaetze; }],
      ['Summe welt fehlt', (d) => { delete d.json.stat.tech.welt; }], ['aufgegeben mehr als Pleiten', (d) => { d.json.stat.aufgegeben = d.json.stat.pleiten + 1; }],
      ['Feld g.markt fehlt', (d) => { d.arrays = d.arrays.filter(x => x.name !== 'g.markt'); }], ['Feld g.kraft fehlt', (d) => { d.arrays = d.arrays.filter(x => x.name !== 'g.kraft'); }],
    ];
    const meld = [];
    for (const [was, f] of kaputt) {
      const d = JSON.parse(text); f(d); let e = null;
      try { ladenAusText(Sim, JSON.stringify(d)); } catch (x) { e = x; }
      meld.push(`${was}: ${e ? e.message : 'ANGENOMMEN'}`);
      if (!e || !/^Spielstand (beschädigt|unvollständig)/.test(e.message)) fehler++;
    }
    console.log((meld.every(m => /beschädigt|unvollständig/.test(m)) ? '  ok   ' : '  FEHL ') + `${kaputt.length} beschädigte Stände abgelehnt: ` + meld.join('; '));
    // Übernahme von Version 8 (stadt.orig.html): alle im Umland, Bremse gleich gezählt, „hatte eine Kraft“ nach heute, Summen 0; gründet am selben Tag
    const V8 = lade(simCode(readFileSync(join(hier, '..', 'stadt.orig.html'), 'utf8')));
    const Q = V8.neueStadt(2); bis(V8, Q, 250, 10);
    const d8 = V8.exportZustand(Q), kopie8 = () => ({ ...d8, werte: JSON.parse(JSON.stringify(d8.werte)), json: JSON.parse(JSON.stringify(d8.json)), arrays: d8.arrays.map(a => ({ ...a, daten: a.daten.slice() })) });
    const U = Sim.importZustand(kopie8(), true), g = U.g;
    let tf = 0, markt = 0, kraftFalsch = 0;
    for (let b = 0; b < U.gAnzahl; b++) { if (g.markt[b]) markt++;
      const soll = (g.typ[b] === WERKSTATT || g.typ[b] === TECH) && U.belegschaft[b].length > 0 ? 1 : 0; if (g.kraft[b] !== soll) kraftFalsch++;
      if (g.typ[b] === TECH && !g.leer[b] && g.besitzer[b] >= 0) tf += Math.max(0, Sim.stellen(U, b) - U.belegschaft[b].length); }
    const vor = U.stat.tech.gruendungen; bis(Sim, U, 280, 10);
    pruef(markt === 0 && U.techFrei >= 0 && kraftFalsch === 0 && U.stat.aufgegeben >= 0 && Number.isFinite(U.budget) && Number.isFinite(U.weltPreis),
      `Version 8 (Seed 2, Tag 250) übernommen: alle Tech-Firmen im Umland, Bremse gleich gezählt (${tf}), „hatte eine Kraft“ nach heute; 30 Tage weiter ohne NaN, ${U.stat.tech.gruendungen - vor} Tech-Gründungen`);
    const U2 = Sim.importZustand(kopie8(), true);
    pruef(U2.techFrei === tf && typeof T.techGruendungJetzt(U2) === 'boolean', `direkt nach der Übernahme: techFrei ${U2.techFrei} (nachgezählt ${tf}), Gründungen nicht bis Mitternacht gesperrt (Befund der Gegenprüfung)`);
  }

  console.log('E Namenstausch (Seed 2, 450 Tage)');
  {
    const { Sim: N } = ladeSimMit([['const STRASSEN = [', 'NACHNAMEN.reverse(); VORNAMEN_W.reverse(); VORNAMEN_M.reverse();\nconst STRASSEN = [']]);
    const A = Sim.neueStadt(2), B = N.neueStadt(2); bis(Sim, A, 450); bis(N, B, 450);
    const spur = (S) => { const h = createHash('sha256'); for (const n of Object.keys(S.p).sort()) if (ArrayBuffer.isView(S.p[n])) { const a = S.p[n], w = a.length / S.pKap; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, S.pMax * w * a.BYTES_PER_ELEMENT)); }
      for (const n of Object.keys(S.g).sort()) if (ArrayBuffer.isView(S.g[n])) { const a = S.g[n]; h.update(n); h.update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)); }
      h.update(JSON.stringify(S.stat)); h.update(String(S.rs) + '/' + S.rsSich + '/' + S.rsAuto + '/' + S.budget + '/' + S.techFrei + '/' + S.weltPlaetze); h.update(S.buch.map(e => e.art).join()); return h.digest('hex').slice(0, 16); };
    const i = Sim.techInfo(A);
    pruef(Sim.name(A, 5) !== N.name(B, 5) && spur(A) === spur(B) && i.weltFirmen > 0, `Namen getauscht („${Sim.name(A, 5)}“ heißt dort „${N.name(B, 5)}“): ${i.umlandFirmen} Tech-Firmen im Umland, ${i.weltFirmen} in der Welt, bitgleich (${spur(A)})`);
  }

  console.log('F Messung und Gruppen (nur gemessen, keine Regel liest diese Merkmale)');
  {
    const seeds = arg('gruppenSeeds', '1,2,3').split(',').map(Number), G = new Map(), g = (n) => { if (!G.has(n)) G.set(n, { erw: 0, gr: 0, tech: 0, welt: 0, techTage: 0, arbTage: 0 }); return G.get(n); };
    const gruppen = (S, p) => { const P = S.p; return ['alle', P.elternA[p] >= 0 ? 'in der Stadt geboren' : 'zugezogen oder vom Start', P.nach[p] >= 30 && P.nach[p] <= 36 ? 'Nachnamen Kaya bis Kowalski (Liste 31–37)' : 'übrige Nachnamen', P.weib[p] ? 'Frauen' : 'Männer']; };
    const erste = [];
    mc.__vor = (S, p) => ({ typ: MT.gruendungsTyp(S, p), g: gruppen(S, p) }); mc.__nach = (S, p, v, ok) => { if (!ok) return; const b = S.p.besitz[p]; for (const x of v.g) { g(x).gr++; if (S.g.typ[b] === TECH) { g(x).tech++; if (S.g.markt[b]) g(x).welt++; } } };
    for (const k of ['__kz', '__preis', '__pleite', '__an', '__zu', '__umzug', '__itVor', '__itNach']) mc[k] = null;
    for (const seed of seeds) {
      const S = M.neueStadt(seed); let e = -1;
      while (S.tag < 730) { const t0 = S.tag; M.stunde(S); if (S.tag === t0) continue; if (e < 0 && S.stat.tech.gruendungen) e = S.tag;
        if (S.tag < 200) continue;
        const P = S.p, erw = S.tag - R.ERWACHSEN * R.JAHR;
        for (let p = 0; p < S.pMax; p++) { if (!P.lebt[p] || P.geb[p] > erw) continue; const a = P.arbeit[p], t = a >= 0 && S.g.typ[a] === TECH;
          for (const x of gruppen(S, p)) { const o = g(x); o.erw++; if (a >= 0) { o.arbTage++; if (t) o.techTage++; } } } }
      erste.push(`Seed ${seed}: erste Tech-Gründung Tag ${e}, ${Sim.techInfo(S).umlandFirmen} + ${Sim.techInfo(S).weltFirmen} Tech-Firmen an Tag 730`);
    }
    mc.__vor = null; mc.__nach = null;
    console.log('       ' + erste.join('; '));
    const a = G.get('alle');
    console.log('       Gründungen ab Tag 0, Erwachsenen- und Arbeitstage ab Tag 200: Anteil an Tech-Gründungen (in die Welt) und an Tech-Arbeitstagen, geteilt durch den Anteil an allen Gründungen bzw. Arbeitstagen');
    for (const n of ['alle', 'in der Stadt geboren', 'zugezogen oder vom Start', 'Nachnamen Kaya bis Kowalski (Liste 31–37)', 'übrige Nachnamen', 'Frauen', 'Männer']) {
      const x = G.get(n); if (!x) continue;
      const v = (z, nn, za, na) => (nn && za ? ((z / nn) / (za / na)).toFixed(2) : '–');
      console.log(`       ${n.padEnd(44)} Gründungen ${String(x.gr).padStart(4)}  Tech ${v(x.tech, x.gr, a.tech, a.gr)} (Welt ${v(x.welt, x.gr, a.welt, a.gr)})  Tech-Arbeitstage ${v(x.techTage, x.arbTage, a.techTage, a.arbTage)}`);
    }
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Prüfungen zu „Tech-Firmen früher und mehr“ bestanden');
  process.exit(fehler ? 1 : 0);
}

if (flag('kipolicy')) {
  // KI-Policy (Etappe 1, Version 9): Regression (Policy aus = bitgleich zu --orig, jeden Tag), Beobachtung ohne verbotene Felder (statisch, durch
  // Verändern und je Personenfeld für die Person selbst und für alle anderen), Namenstausch (Regeln, Policy in neuer und in gewachsener
  // Stadt), Maske nie verletzt (Zufall, Policy, Regelarm; verbotene Aktion abgelehnt), Fokus-ID und Generation, Wegzug und Tod,
  // Schnappschuss, beschädigte oder fremde Policy-Dateien (Sim-Version, Inhalts-Hash), Rückfall zur Laufzeit, Policy nur im
  // Trainingsbereich (ab R.RENTE, Hauptfiguren und Bürgermeister: Regeln), Policy für alle deterministisch.
  // Policy zum Prüfen: --policy datei (z. B. ki/policy_<lauf>.json; nicht freigegebene sind nicht eingebettet), sonst die eingebettete, sonst künstlich
  const kern = await import('./simkern.mjs');
  const { Umgebung, mische, BELOHNUNG } = await import('./kiepisode.mjs');
  const K = Sim.KI;
  let fehl = 0;
  const ok = (b, t) => { console.log((b ? 'ok   ' : 'FEHL ') + t); if (!b) fehl++; };
  const tage = Number(arg('tage', '730')), seeds = arg('seeds', '1,2,3').split(',').map(Number), t0 = performance.now();
  // Policy zum Prüfen: die eingebettete, sonst eine künstliche (feste Gewichte aus einem Hash, kein Zufall)
  const kuenstlich = (skala = 0.5, extra = null, neuHash = false) => {
    const n = K.MERKMALE.length, na = K.AKTIONEN.length, w = (a, b, k) => ((mische(a * 131 + b, k) / 4294967296) * 2 - 1) * skala;
    const schicht = (nIn, nOut, akt, k) => ({ gewichte: Array.from({ length: nOut }, (_, j) => Array.from({ length: nIn }, (_, i) => Math.fround(w(j, i, k)))),
      bias: Array.from({ length: nOut }, (_, j) => Math.fround(w(j, 999, k))), aktivierung: akt });
    const d = { format: 'stadt-policy', formatVersion: K.FORMAT, name: 'kuenstlich', status: 'test', simVersion: Sim.VERSION, schemaHash: K.schemaHash(),
      beobachtung: { schemaVersion: K.SCHEMA, laenge: n, merkmale: K.MERKMALE.map(m => m[0]) }, aktionen: { liste: K.AKTIONEN.slice() },
      normalisierung: { mittel: new Array(n).fill(0.4), streuung: new Array(n).fill(0.3), clip: 5 },
      netz: { schichten: [schicht(n, 16, 'tanh', 1), schicht(16, na, 'linear', 2)] } };
    d.hash = K.policyHash(d);                                // Inhalts-Hash wie training/exportiere.py; extra ändert danach (Hash dann alt)
    if (extra) extra(d);
    if (neuHash) d.hash = K.policyHash(d);
    return d;
  };
  const polText = arg('policy') ? readFileSync(arg('policy'), 'utf8') : kern.policyTextAusHtml(html);
  const polD = polText ? JSON.parse(polText) : kuenstlich();
  const pol = K.policyPruefen(polD);
  console.log(`Policy zum Prüfen: ${arg('policy') ? 'Datei ' + arg('policy') : polText ? 'eingebettet' : 'künstlich'} „${pol.name}“ (${pol.status}), Stadt-Version ${pol.simVersion}, Hash ${pol.hash}, Schema ${K.schemaHash()}, `
    + `${K.MERKMALE.length} Merkmale, ${K.AKTIONEN.length} Aktionen`);
  if (polText) ok(polD.hash === K.policyHash(polD), `Policy-Datei: Inhalts-Hash aus training/exportiere.py (Python) = Sim.KI.policyHash (JS) = ${polD.hash}`);

  // 1. Regression: ohne Policy und ohne Fokus jeden Tag bitgleich zur ungepatchten Fassung; S bekommt keine neuen Schlüssel
  let origHtml = null;
  if (arg('orig')) origHtml = readFileSync(arg('orig'), 'utf8');
  else if (arg('git')) origHtml = execFileSync('git', ['-C', arg('git'), 'show', arg('rev', 'HEAD') + ':stadt/stadt.html'], { encoding: 'utf8', maxBuffer: 1 << 26 });
  if (!origHtml) ok(false, 'Regression: --orig datei oder --git ordner [--rev] angeben');
  else {
    const Orig = kern.ladeSimAusHtml(origHtml).Sim;
    for (const seed of seeds) {
      const A = Orig.neueStadt(seed), N = Sim.neueStadt(seed);
      let ab = -1, d = 0;
      for (; d < tage && ab < 0; d++) {
        const z = A.tag + 1;
        while (A.tag < z) Orig.stunde(A);
        while (N.tag < z) Sim.stunde(N);
        if (fingerabdruck(Orig, A) !== fingerabdruck(Sim, N)) ab = A.tag;
      }
      const gleicheSchluessel = Object.keys(A).join() === Object.keys(N).join();
      ok(ab < 0 && gleicheSchluessel, `Regression Seed ${seed}: Policy aus, ${d} Tage, jeden Tag bitgleich zu ${arg('orig') || arg('git') + ' ' + arg('rev', 'HEAD')} `
        + `(${N.einwohner} Einwohner, Fingerabdruck ${fingerabdruck(Sim, N)})${ab >= 0 ? `, ab Tag ${ab} VERSCHIEDEN` : ''}${gleicheSchluessel ? '' : ', S hat andere Schlüssel'}`);
    }
  }

  // 2. Beobachtung: welche Personenfelder liest sie (mit ihren Hilfsfunktionen)? Keine Namen, Herkunft, Einzug, Eltern, Gedächtnisbezüge
  const quelle = (name) => {
    const i = SIM_CODE.indexOf('function ' + name + '(');
    if (i < 0) return '';
    let j = SIM_CODE.indexOf('{', i), tiefe = 0;
    for (; j < SIM_CODE.length; j++) { if (SIM_CODE[j] === '{') tiefe++; else if (SIM_CODE[j] === '}' && --tiefe === 0) break; }
    return SIM_CODE.slice(i, j + 1);
  };
  const HILFEN = ['kiEingabe', 'tageskosten', 'einkauf', 'miete', 'eigentuemer', 'kaufRate', 'eigeneWohnung', 'gebunden', 'kitaFrist', 'kitaFrei',
    'rentner', 'anspruch', 'verpflichtet', 'freundeZahl', 'besterFreierLohn', 'steuerSatz'];
  const VERBOTEN_P = ['vor', 'nach', 'weib', 'gen', 'elternA', 'elternB', 'elternAGen', 'elternBGen', 'elternNameA', 'elternNameB', 'memRef', 'memGen',
    'memName', 'einzug', 'sparSeit', 'stammladen', 'besuch', 'obhutBei', 'obhutGen'];
  const gelesen = new Set(), fehlt = [];
  for (const h of HILFEN) { const q = quelle(h); if (!q) fehlt.push(h); for (const m of q.matchAll(/(?:\bP|S\.p)\.([A-Za-z]+)\b/g)) gelesen.add(m[1]); }
  const verboten = [...gelesen].filter(n => VERBOTEN_P.includes(n));
  ok(!fehlt.length && !verboten.length, `Beobachtung (statisch): liest ${[...gelesen].sort().join(', ')}${verboten.length ? ' – VERBOTEN: ' + verboten.join(', ') : ''}${fehlt.length ? ' – Quelle fehlt: ' + fehlt.join(', ') : ''}`);
  {
    const S = Sim.neueStadt(1);
    while (S.tag < 200) Sim.stunde(S);
    const P = S.p, J = Sim.R.JAHR, leute = [];
    for (let p = 0; p < S.pMax && leute.length < 60; p++) if (P.lebt[p] && S.tag - P.geb[p] >= 18 * J) leute.push(p);
    const beob = () => leute.map(p => [K.beobachtung(S, p, 7, 0), K.beobachtung(S, p, 18, 1)]);
    const vorher = beob(), sich = {};
    for (const n of VERBOTEN_P) sich[n] = P[n].slice();
    for (let p = 0; p < S.pMax; p++) {
      P.vor[p] = (P.vor[p] + 7) % 30; P.nach[p] = (P.nach[p] + 11) % 50; P.weib[p] ^= 1; P.einzug[p] += 999; P.sparSeit[p] -= 77;
      P.elternA[p] = -1; P.elternB[p] = -1; P.elternAGen[p] ^= 3; P.elternNameA[p] ^= 0x5555; P.elternNameB[p] ^= 0x2222; P.stammladen[p] = -1; P.besuch[p] = -1;
      for (let k = 0; k < Sim.R.MEM; k++) { P.memRef[p * Sim.R.MEM + k] = -1; P.memGen[p * Sim.R.MEM + k] ^= 1; P.memName[p * Sim.R.MEM + k] ^= 0xff; }
    }
    const nachher = beob();
    for (const n of VERBOTEN_P) P[n].set(sich[n]);
    const gleich = vorher.every((v, k) => v.every((x, j) => x.every((w, i) => Object.is(w, nachher[k][j][i]))));
    ok(gleich && vorher[0][0].length === K.MERKMALE.length && vorher.every(v => v.every(x => x.every(Number.isFinite))),
      `Beobachtung (verändert): Namen, Geschlecht, Einzug, Sparbeginn, Eltern, Gedächtnisbezüge aller Personen verändert → Beobachtung von ${leute.length} Personen bitgleich, alle Werte endlich`);
  }
  // Namenstausch: ganze Stadt mit anderen Namen läuft gleich (Regeln und Policy für alle); verglichen ohne Namensfelder und Stadtbuch
  {
    const NAMEN = new Set(['p.vor', 'p.nach', 'p.memName', 'p.elternNameA', 'p.elternNameB']);
    const ohneNamen = (S) => { const h = createHash('sha256'), d = Sim.exportZustand(S);
      for (const a of d.arrays.slice().sort((x, y) => (x.name < y.name ? -1 : 1))) if (!NAMEN.has(a.name)) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
      h.update(JSON.stringify(S.stat)); h.update(String(S.rs)); return h.digest('hex').slice(0, 16); };
    for (const mitPolicy of [false, true]) {
      K.policySetzen(mitPolicy ? pol : null);
      const A = Sim.neueStadt(2), B = Sim.neueStadt(2);
      for (let p = 0; p < B.pMax; p++) { B.p.vor[p] = (B.p.vor[p] + 13) % 30; B.p.nach[p] = (B.p.nach[p] + 17) % 50; }
      while (A.tag < 120) Sim.stunde(A);
      while (B.tag < 120) Sim.stunde(B);
      const st = K.policyStand();
      ok(ohneNamen(A) === ohneNamen(B), `Namenstausch ${mitPolicy ? 'mit Policy für alle' : 'mit Regeln'}: 120 Tage, ohne Namensfelder bitgleich (${ohneNamen(A)}, ${A.einwohner} Einwohner`
        + `${mitPolicy ? `, ${st.entscheidungen} Policy-Entscheidungen` : ''})`);
    }
    // gewachsene Stadt: 200 Tage Regeln, dann 60 Tage Policy für alle (die neue Stadt oben wächst mit der Policy kaum)
    K.policySetzen(null);
    const A = Sim.neueStadt(2), B = Sim.neueStadt(2);
    for (let p = 0; p < B.pMax; p++) { B.p.vor[p] = (B.p.vor[p] + 13) % 30; B.p.nach[p] = (B.p.nach[p] + 17) % 50; }
    while (A.tag < 200) Sim.stunde(A);
    while (B.tag < 200) Sim.stunde(B);
    const ew = A.einwohner;
    K.policySetzen(pol);
    while (A.tag < 260) Sim.stunde(A);
    while (B.tag < 260) Sim.stunde(B);
    const st = K.policyStand();
    ok(ohneNamen(A) === ohneNamen(B) && st.entscheidungen > 1000, `Namenstausch in gewachsener Stadt: 200 Tage Regeln (${ew} Einwohner), dann 60 Tage Policy für alle, `
      + `ohne Namensfelder bitgleich (${ohneNamen(A)}, ${A.einwohner} Einwohner, ${st.entscheidungen} Policy-Entscheidungen, ${st.regeln} nach Regeln)`);
    K.policySetzen(null);
  }
  // Jedes Personenfeld einzeln verändert, einmal nur bei der Person selbst, einmal bei allen anderen: Fremdes wirkt nur als Haushaltswissen
  // (hh, wohnung, eigen), Eigenes nie über verbotene Felder
  {
    const S = Sim.neueStadt(1);
    while (S.tag < 220) Sim.stunde(S);
    const P = S.p, J = Sim.R.JAHR, ziel = [];
    for (let p = 0; p < S.pMax && ziel.length < 80; p++) if (P.lebt[p] && S.tag - P.geb[p] >= 18 * J && !P.haftBis[p]) ziel.push(p);
    const beob = (p) => [K.beobachtung(S, p, 7, 0), K.beobachtung(S, p, 18, 1)];
    const gleich = (a, b) => a.every((x, j) => x.every((w, i) => Object.is(w, b[j][i])));
    const felder = Object.keys(P).filter(k => ArrayBuffer.isView(P[k]) && Number.isInteger(P[k].length / S.pKap) && P[k].length >= S.pKap);
    const eigen = new Set(), fremd = new Set(), ausnahmen = [];
    const fp0 = fingerabdruck(Sim, S);
    for (const f of felder) {
      const arr = P[f], k = arr.length / S.pKap, sich = arr.slice();
      const stoer = (i) => { const v = arr[i]; arr[i] = (arr instanceof Float32Array || arr instanceof Float64Array) ? v * 1.37 + 3.1 : (v >= 0 ? v + 1 : v - 1); if (arr[i] === v) arr[i] = v ^ 1; };
      for (const p of ziel) {
        const vor = beob(p);
        for (let i = 0; i < arr.length; i++) if (Math.floor(i / k) !== p) stoer(i);
        try { if (!gleich(vor, beob(p))) fremd.add(f); } catch (e) { ausnahmen.push(f + ' (fremd)'); }
        arr.set(sich);
        for (let i = p * k; i < (p + 1) * k; i++) stoer(i);
        try { if (!gleich(vor, beob(p))) eigen.add(f); } catch (e) { ausnahmen.push(f + ' (eigen)'); }
        arr.set(sich);
      }
    }
    const fremdErlaubt = ['hh', 'wohnung', 'eigen'], fremdZuviel = [...fremd].filter(f => !fremdErlaubt.includes(f)), eigenVerboten = [...eigen].filter(f => VERBOTEN_P.includes(f));
    ok(!fremdZuviel.length && !eigenVerboten.length && fingerabdruck(Sim, S) === fp0,
      `Beobachtung je Personenfeld (${felder.length} Felder, ${ziel.length} Personen, Seed 1 Tag 220): von anderen wirken nur ${[...fremd].sort().join(', ') || '–'} `
      + `(Haushaltswissen), eigene wirken ${eigen.size}, keines davon verboten${fremdZuviel.length ? ' – FREMD ZU VIEL: ' + fremdZuviel.join(', ') : ''}`
      + `${eigenVerboten.length ? ' – VERBOTEN: ' + eigenVerboten.join(', ') : ''}${ausnahmen.length ? ` (Ausnahmen bei verstümmelten Werten: ${ausnahmen.length})` : ''}`);
  }

  // 3. Maske nie verletzt (Trainingsumgebung): Zufall aus der Maske, Policy, Regelarm; verbotene Aktion wird abgelehnt und ändert nichts
  const U = new Umgebung(Sim);
  {
    let entsch = 0, verletzt = 0, regelAusserhalb = 0, ausgef = 0;
    for (const arm of ['zufall', 'policy', 'regel']) {
      for (let k = 0; k < 5; k++) {
        let r = U.reset({ seed: 10000 + k, nr: k, tage: 20 }), z = mische(k, 77);
        while (!r.beendet && !r.abgeschnitten) {
          let a;
          if (arm === 'regel') a = 'regel';
          else if (arm === 'policy') a = K.policyRechnen(pol, Float32Array.from(r.beob), Uint8Array.from(r.maske)).aktion;
          else { const L = r.maske.map((v, i) => (v ? i : -1)).filter(i => i >= 0); z = mische(z, 5); a = L[z % L.length]; }
          if (a !== 'regel' && !r.maske[a]) verletzt++;
          r = U.step(a); entsch++;
          if (r.info.wirkung && r.info.wirkung.maskeOk === false) regelAusserhalb++;
          if (r.info.wirkung && r.info.wirkung.art === 'ausgefuehrt') ausgef++;
        }
        verletzt += U.epi.metrik.maskeVerletzt;
      }
    }
    ok(verletzt === 0 && regelAusserhalb === 0 && entsch > 500, `Maske: ${entsch} Entscheidungen (Zufall, Policy, Regelarm je 5 Episoden), ${ausgef} ausgeführt, 0 außerhalb der Maske `
      + `(gezählt ${verletzt}, Regelarm außerhalb ${regelAusserhalb})`);
    let r = U.reset({ seed: 10001, nr: 3, tage: 10 });
    const fa = kern.fingerabdruck(Sim, U.S), schlecht = r.maske.indexOf(0);
    let code = '';
    try { U.step(schlecht); } catch (e) { code = e.code; }
    ok(code === 'maske_verletzt' && kern.fingerabdruck(Sim, U.S) === fa && U.observe().entscheidung && U.epi.metrik.maskeVerletzt === 1,
      `Maske: verbotene Aktion ${K.AKTIONEN[schlecht]} abgelehnt (${code}), Stadt unverändert, Entscheidung bleibt offen, gezählt`);
    r = U.step(0, { vorspulen: false });
    while (r.info.entscheidung && !r.beendet && !r.abgeschnitten) r = U.step(0, { vorspulen: false });
    code = '';
    const fb = kern.fingerabdruck(Sim, U.S);
    try { U.step(1, { vorspulen: false }); } catch (e) { code = e.code; }
    ok(code === 'maske_verletzt' && kern.fingerabdruck(Sim, U.S) === fb, 'Maske: zwischen Entscheidungszeitpunkten nur warten (Aktion abgelehnt, nichts geändert)');
  }

  // 4. Fokus-ID und Generation, Wegzug und Tod
  {
    let r = U.reset({ seed: 10002, nr: 1, tage: 30 });
    const S = U.S, id = U.epi.id, gen = U.epi.gen, f = K.fokus();
    Sim._pruef.aktWegziehen(S, id);                            // erzwungen, wie ein Ereignis zwischen zwei Stunden
    r = U.step(0);
    const rest = U.epi.maxStunden - U.epi.stunden, m = r.info.metrik;
    ok(r.beendet && !r.abgeschnitten && r.grund === 'wegzug' && Math.abs(r.teile.wegzug - rest * BELOHNUNG.wegzugJeStunde) < 1e-9
      && Math.abs(m.defizitMittel - (m.defizit + 100 * rest) / (m.stunden + rest)) < 1e-9,
      `Wegzug: echtes Ende (Grund wegzug), ${rest} fehlende Stunden kosten ${r.teile.wegzug.toFixed(3)} und zählen im Defizit mit 100 (Ø ${m.defizitMittel.toFixed(1)})`);
    ok(BELOHNUNG.wegzugJeStunde <= BELOHNUNG.notstandJeStunde + BELOHNUNG.umkehr / 24 + 1e-15,
      'Wegzug: jede fehlende Stunde kostet mindestens so viel wie die schlechteste gelebte Stunde (Notstand und Umkehr, höchstens eine je Tag)');
    // gemessen: erzwungener Wegzug an der 5. Entscheidung gegen Weiterleben nach Regeln, gleiche Ausgangslage
    let schlechter = 0, n = 0;
    for (let k = 0; k < 6; k++) {
      const summe = (weg) => { let r2 = U.reset({ seed: 10010 + k, nr: k, tage: 20 }), s = r2.belohnung, e = 0;
        while (!r2.beendet && !r2.abgeschnitten) { if (weg && ++e === 5) Sim._pruef.aktWegziehen(U.S, U.epi.id); r2 = U.step('regel'); s += r2.belohnung; } return s; };
      const a = summe(false), b = summe(true);
      n++; if (b < a) schlechter++;
    }
    ok(schlechter === n, `Wegzug verbessert nie: in ${schlechter} von ${n} Ausgangslagen bringt erzwungener Wegzug weniger als Weiterleben`);
    // ID wird wieder vergeben: die neue Person (andere Generation) ist nicht die Fokusperson
    let d = 0;
    while (!(S.p.lebt[id] && S.p.gen[id] !== gen) && d < 24 * 200) { Sim.stunde(S); d++; }
    const zahl = f.zahl;
    const wieder = S.p.lebt[id] && S.p.gen[id] !== gen;
    if (wieder) { Sim.entscheide(S, id, 7); Sim.entscheide(S, id, 18); for (let h = 0; h < 48; h++) Sim.stunde(S); }
    ok(wieder && f.zahl === zahl && !f.faellig, `ID ${wieder ? 'nach ' + d + ' Stunden' : 'NICHT'} neu vergeben (Generation ${gen} → ${S.p.gen[id]}): die neue Person entscheidet nach Regeln, der Fokus greift nicht`);
    r = U.reset({ seed: 10003, nr: 2, tage: 30 });
    Sim._pruef.sterben(U.S, U.epi.id);
    r = U.step(0);
    ok(r.beendet && r.grund === 'tod' && r.teile.wegzug === 0, 'Tod: echtes Ende (Grund tod), ohne Abzug');
    r = U.reset({ seed: 10003, nr: 2, tage: 2 });
    while (!r.beendet && !r.abgeschnitten) r = U.step(0);
    ok(r.abgeschnitten && !r.beendet && r.grund === 'zeitlimit' && U.epi.stunden === 48, 'Zeitlimit: abgeschnitten (nicht beendet) nach genau 48 Stunden');
    K.fokusLoesen();
  }

  // 5. Schnappschuss und Wiederherstellen: gleiche Aktionen → gleiche Beobachtungen, Belohnungen und Stadt
  {
    let r = U.reset({ seed: 10004, nr: 0, tage: 20 });
    for (let k = 0; k < 5; k++) r = U.step(K.policyRechnen(pol, Float32Array.from(r.beob), Uint8Array.from(r.maske)).aktion);
    const snap = U.snapshot();
    const spur = () => { const L = []; for (let k = 0; k < 25 && !r.beendet && !r.abgeschnitten; k++) {
      r = U.step(K.policyRechnen(pol, Float32Array.from(r.beob), Uint8Array.from(r.maske)).aktion); L.push([r.beob, r.maske, r.belohnung, r.stunden]); }
      return JSON.stringify(L) + kern.fingerabdruck(Sim, U.S); };
    const a = spur();
    U.restore(snap); r = { ...U.observe(), beendet: false, abgeschnitten: false };
    const b = spur();
    ok(a === b, `Schnappschuss: nach dem Wiederherstellen 25 Schritte bitgleich (Beobachtung, Maske, Belohnung, Stadt)`);
    K.fokusLoesen();
  }

  // 6. Beschädigte Policy-Dateien werden abgelehnt (mit Grund), nichts wird gesetzt
  {
    const faelle = [
      ['kein Objekt', null], ['Text', 'kaputt'], ['leeres Objekt', {}], ['falsches Format', kuenstlich(0.5, d => { d.format = 'x'; })],
      ['Formatversion 1 (vor der Prüfung)', kuenstlich(0.5, d => { d.formatVersion = 1; }, true)], ['Formatversion 3', kuenstlich(0.5, d => { d.formatVersion = 3; }, true)],
      ['Schema-Version ' + (K.SCHEMA - 1) + ' (Version 8)', kuenstlich(0.5, d => { d.beobachtung.schemaVersion = K.SCHEMA - 1; })],
      ['andere Stadt-Version', kuenstlich(0.5, d => { d.simVersion = Sim.VERSION - 1; }, true)], ['ohne Stadt-Version', kuenstlich(0.5, d => { delete d.simVersion; })],
      ['Hash einer anderen Policy', kuenstlich(0.5, d => { d.hash = kuenstlich(0.4).hash; })], ['ohne Hash', kuenstlich(0.5, d => { delete d.hash; })],
      ['ein Gewicht geändert, Hash alt', kuenstlich(0.5, d => { d.netz.schichten[1].gewichte[4][7] = Math.fround(d.netz.schichten[1].gewichte[4][7] + 0.001); })],
      ['Normalisierung geändert, Hash alt', kuenstlich(0.5, d => { d.normalisierung.mittel[3] += 0.01; })],
      ['Merkmale vertauscht', kuenstlich(0.5, d => { const m = d.beobachtung.merkmale; [m[0], m[1]] = [m[1], m[0]]; })],
      ['ein Merkmal fehlt', kuenstlich(0.5, d => { d.beobachtung.merkmale.pop(); })],
      ['Aktionen vertauscht', kuenstlich(0.5, d => { const a = d.aktionen.liste; [a[1], a[2]] = [a[2], a[1]]; })],
      ['Schema-Hash falsch', kuenstlich(0.5, d => { d.schemaHash = '00000000'; })],
      ['NaN-Gewicht (JSON null)', kuenstlich(0.5, d => { d.netz.schichten[0].gewichte[3][4] = null; })],
      ['Gewicht als Text', kuenstlich(0.5, d => { d.netz.schichten[1].gewichte[0][0] = '0.1'; })],
      ['unendliches Gewicht', kuenstlich(0.5, d => { d.netz.schichten[0].gewichte[0][0] = Infinity; })],
      ['NaN-Bias', kuenstlich(0.5, d => { d.netz.schichten[1].bias[2] = NaN; })],
      ['Streuung 0', kuenstlich(0.5, d => { d.normalisierung.streuung[5] = 0; })], ['Streuung negativ', kuenstlich(0.5, d => { d.normalisierung.streuung[0] = -1; })],
      ['Mittel NaN', kuenstlich(0.5, d => { d.normalisierung.mittel[0] = NaN; })], ['clip 0', kuenstlich(0.5, d => { d.normalisierung.clip = 0; })],
      ['Normalisierung zu kurz', kuenstlich(0.5, d => { d.normalisierung.mittel.pop(); })],
      ['Zeile zu kurz', kuenstlich(0.5, d => { d.netz.schichten[0].gewichte[2].pop(); })], ['Bias zu kurz', kuenstlich(0.5, d => { d.netz.schichten[0].bias.pop(); })],
      ['Aktivierung sigmoid', kuenstlich(0.5, d => { d.netz.schichten[0].aktivierung = 'sigmoid'; })],
      ['letzte Schicht tanh', kuenstlich(0.5, d => { d.netz.schichten[1].aktivierung = 'tanh'; })],
      ['12 statt 13 Ausgaben', kuenstlich(0.5, d => { d.netz.schichten[1].gewichte.pop(); d.netz.schichten[1].bias.pop(); })],
      ['keine Schichten', kuenstlich(0.5, d => { d.netz.schichten = []; })],
      ['7 Schichten', kuenstlich(0.5, d => { d.netz.schichten = new Array(7).fill(d.netz.schichten[1]); })],
      ['600 Einheiten', kuenstlich(0.5, d => { d.netz.schichten[0].gewichte = new Array(600).fill(d.netz.schichten[0].gewichte[0]); d.netz.schichten[0].bias = new Array(600).fill(0); })],
    ];
    let abgelehnt = 0;
    const nicht = [];
    for (const [was, d] of faelle) {
      try { K.policyPruefen(d); nicht.push(was); } catch (e) { if (/^Policy ungültig/.test(e.message)) abgelehnt++; else nicht.push(was + ' (' + e.message + ')'); }
    }
    let gesetzt = true;
    try { K.policySetzen({ schichten: [], schemaHash: 'x' }); } catch { gesetzt = false; }
    ok(abgelehnt === faelle.length && !gesetzt && !K.policyAktiv(), `Beschädigte oder fremde Policy-Dateien: ${abgelehnt} von ${faelle.length} abgelehnt mit Grund${nicht.length ? ' – NICHT: ' + nicht.join(', ') : ''}; `
      + 'Ungeprüftes lässt sich nicht setzen');
    // Gegenprobe: mit nachgerechnetem Hash wird dieselbe Änderung angenommen, und der Hash folgt dem Inhalt
    const geaendert = kuenstlich(0.5, d => { d.netz.schichten[1].gewichte[4][7] = Math.fround(d.netz.schichten[1].gewichte[4][7] + 0.001); }, true);
    let grund = '';
    try { K.policyPruefen(geaendert); } catch (e) { grund = e.message; }
    ok(!grund && geaendert.hash !== kuenstlich(0.5).hash, `Inhalts-Hash folgt dem Inhalt: ein Gewicht geändert → neuer Hash ${geaendert.hash} (vorher ${kuenstlich(0.5).hash}), mit ihm angenommen${grund ? ' – ' + grund : ''}`);
  }

  // 7. Rückfall zur Laufzeit: eine Policy, deren Logits überlaufen (gültige Datei, Rechnung ergibt keine Zahl) → Regeln; die Stadt läuft
  // dann genau wie mit Regeln (die erste Entscheidung fällt schon nach Regeln)
  {
    const d = kuenstlich(0.5, x => {                          // verdeckte Schicht sättigt (tanh = 1), Ausgabe 1e308 × 16 + 1e308 → unendlich
      x.netz.schichten[0].gewichte = x.netz.schichten[0].gewichte.map(z => z.map(() => 0)); x.netz.schichten[0].bias = x.netz.schichten[0].bias.map(() => 50);
      x.netz.schichten[1].gewichte = x.netz.schichten[1].gewichte.map(z => z.map(() => 1e308)); x.netz.schichten[1].bias = x.netz.schichten[1].bias.map(() => 1e308); }, true);
    K.policySetzen(K.policyPruefen(d));
    const A = Sim.neueStadt(3);
    while (A.tag < 40) Sim.stunde(A);
    const st = K.policyStand();
    K.policySetzen(null);
    const B = Sim.neueStadt(3);
    while (B.tag < 40) Sim.stunde(B);
    ok(!st.aktiv && st.rueckfall === 1 && /keine Zahl/.test(st.fehler) && fingerabdruck(Sim, A) === fingerabdruck(Sim, B),
      `Rückfall: überlaufende Logits → Policy aus („${st.fehler}“), 40 Tage bitgleich zu Regeln (${fingerabdruck(Sim, A)})`);
  }

  // 7b. Policy nur, wofür sie trainiert ist: ab R.RENTE Jahren und Hauptfiguren entscheiden die Regeln (auch wenn die Policy an ist)
  {
    const S = Sim.neueStadt(1);
    while (S.tag < 300) Sim.stunde(S);
    const P = S.p, J = Sim.R.JAHR;
    let alt = -1, haupt = -1, jung = -1, bm = -1;
    for (let p = 0; p < S.pMax; p++) {
      if (!P.lebt[p] || P.haftBis[p] || S.tag - P.geb[p] < Sim.R.ERWACHSEN * J) continue;
      if (Sim.istBm(S, p)) bm = p;                               // Version 9: istHaupt zählt den Bürgermeister mit
      else if (Sim.istHaupt(S, p)) { if (haupt < 0) haupt = p; } else if (S.tag - P.geb[p] >= Sim.R.RENTE * J) { if (alt < 0) alt = p; } else if (jung < 0) jung = p;
    }
    // dieselbe Entscheidung (18 Uhr) in zwei Kopien der Stadt: einmal mit Policy für alle, einmal mit Regeln
    const probe = (p) => { const T = ladenAusText(Sim, speichernAlsText(Sim, S)), R0 = ladenAusText(Sim, speichernAlsText(Sim, S));
      K.policySetzen(pol); const a = Sim.entscheide(T, p, 18); const st = K.policyStand(); K.policySetzen(null); const b = Sim.entscheide(R0, p, 18);
      return { st, gleich: a === b && fingerabdruck(Sim, T) === fingerabdruck(Sim, R0) }; };
    const pa = alt >= 0 ? probe(alt) : null, ph = haupt >= 0 ? probe(haupt) : null, pj = jung >= 0 ? probe(jung) : null, pb = bm >= 0 ? probe(bm) : null;
    ok(pa && ph && pj && pb && pa.st.entscheidungen === 0 && pa.st.regeln === 1 && pa.gleich && ph.st.entscheidungen === 0 && ph.st.regeln === 1 && ph.gleich
      && pb.st.entscheidungen === 0 && pb.st.regeln === 1 && pb.gleich && pj.st.entscheidungen === 1 && pj.st.regeln === 0,
      `Trainingsbereich: Person ab ${Sim.R.RENTE} (ID ${alt}), Hauptfigur (ID ${haupt}) und Bürgermeister (ID ${bm}) entscheiden mit Policy genau wie mit Regeln `
      + `(0 Policy-Entscheidungen), eine Person unter ${Sim.R.RENTE} (ID ${jung}) nach der Policy`);
    K.policySetzen(pol);
    const T = ladenAusText(Sim, speichernAlsText(Sim, S));
    while (T.tag < 302) Sim.stunde(T);
    const st = K.policyStand();
    K.policySetzen(null);
    ok(st.entscheidungen > 0 && st.regeln > 0, `Trainingsbereich, 2 Tage Policy für alle ab Tag 300 (${T.einwohner} Einwohner): ${st.entscheidungen} Policy-Entscheidungen, `
      + `${st.regeln} nach Regeln (ab ${Sim.R.RENTE} oder Hauptfigur)`);
  }

  // 8. Policy für alle: deterministisch, entscheidet wirklich, S ohne neue Schlüssel, Spielstand lädt bitgleich weiter
  {
    const lauf = () => { K.policySetzen(pol); const S = Sim.neueStadt(1); while (S.tag < 90) Sim.stunde(S); const st = K.policyStand(); return { S, st }; };
    const a = lauf(), b = lauf();
    K.policySetzen(null);
    const R0 = Sim.neueStadt(1);
    while (R0.tag < 90) Sim.stunde(R0);
    ok(fingerabdruck(Sim, a.S) === fingerabdruck(Sim, b.S) && a.st.entscheidungen > 0 && a.st.rueckfall === 0 && fingerabdruck(Sim, a.S) !== fingerabdruck(Sim, R0)
      && Object.keys(a.S).join() === Object.keys(R0).join(),
      `Policy für alle: 90 Tage zweimal bitgleich (${fingerabdruck(Sim, a.S)}, ${a.S.einwohner} Einwohner; Regeln: ${R0.einwohner}), ${a.st.entscheidungen} Entscheidungen `
      + `(${a.st.ausgefuehrt} ausgeführt, ${a.st.fehlgeschlagen} ohne Erfolg, ${a.st.warten}× gewartet), kein Rückfall, keine neuen Schlüssel in S`);
    K.policySetzen(pol);
    const S = Sim.neueStadt(1);
    while (S.tag < 60 || S.stunde !== 13) Sim.stunde(S);
    const T = ladenAusText(Sim, speichernAlsText(Sim, S));
    while (S.tag < 90) Sim.stunde(S);
    while (T.tag < 90) Sim.stunde(T);
    ok(fingerabdruck(Sim, S) === fingerabdruck(Sim, T), `Policy für alle: Speichern und Laden mitten am Tag (Tag 60, 13 Uhr), 30 Tage weiter bitgleich`);
    K.policySetzen(null);
  }
  console.log(`\n${fehl ? fehl + ' FEHL' : 'Alle KI-Policy-Prüfungen bestanden'} (${((performance.now() - t0) / 1000).toFixed(0)} s)`);
  process.exit(fehl ? 1 : 0);
}
if (flag('gate')) {
  const seeds = arg('seeds', '1,2,3').split(',').map(Number);
  let alleOk = true;
  for (const seed of seeds) {
    const reihe = [], budgets = [];
    let ms365 = 0, c365 = null, k365 = null, fehler = null, S = null, buchNr = 0, arbeitZeilen = 0, kauf365 = 0, techZeilen = 0, reg700 = null, budget700 = 0;
    const zeilen = [];
    try {
      S = lauf(Sim, seed, 730, (S, k, ms) => {
        reihe.push(k.einwohner); budgets.push(k.budget);
        for (const e of S.buch) if (e.nr > buchNr && (e.art === 'fertig' || e.art === 'stillstand' || e.art === 'bauhof')) arbeitZeilen++;
        for (const e of S.buch) if (e.nr > buchNr && (e.art === 'version' || e.art === 'auftrag')) techZeilen++;
        buchNr = S.buchNr;
        if (k.tag % 30 === 0 || k.tag === 365 || k.tag === 730) zeilen.push(tabelleZeile(k, ms));
        if (k.tag === 365) { ms365 = ms; c365 = charakter(S); k365 = k; kauf365 = S.stat.tech ? S.stat.tech.kaeufe.reduce((a, b) => a + b, 0) : 0; }
        if (k.tag === 700) { reg700 = { ...S.stat.regierung }; budget700 = S.budget; }
      });
    } catch (e) { fehler = e; }
    console.log(`\n═══ Seed ${seed} ═══`);
    console.log(tabelleKopf());
    console.log(zeilen.join('\n'));
    if (fehler) { console.log('  FEHLER:', fehler.stack); alleOk = false; continue; }
    // 2: nie 0, nie > 30 % Einbruch in 30 Tagen
    let minPop = Infinity, schlimmsterEinbruch = 0, einbruchTag = 0;
    for (let d = 0; d < reihe.length; d++) {
      minPop = Math.min(minPop, reihe[d]);
      let max = 0; for (let e = Math.max(0, d - 30); e <= d; e++) max = Math.max(max, reihe[e]);
      const drop = max ? 1 - reihe[d] / max : 0;
      if (drop > schlimmsterEinbruch) { schlimmsterEinbruch = drop; einbruchTag = d + 1; }
    }
    const minBudget = Math.min(...budgets);
    // Gate 4 „pendelt sich ein“: Schwankungsband der Einwohner über die letzten 180 Tage (Tag 551–730).
    const band = reihe.slice(550, 730), bandMax = Math.max(...band), bandMin = Math.min(...band);
    const bandFaktor = bandMax / bandMin;
    // „unterhalb der Kartengrenze“: Straßen dürfen bis zur äußersten Rasterlinie im Rand. Hat eine sie erreicht,
    // stößt die Stadt an die Karte. Abstand = Felder zwischen äußerster Straße und dieser Grenze.
    // Seit „Stadt erweitern“ (Version 7) wächst die Karte mit (S.karte): Straßen stehen zum Vergleich wie auf der alten Karte 96 × 96
    // (relativ zur Mitte, + 48), dazu der Abstand zur alten Baugrenze und zur Baugrenze der heutigen Karte (entscheidet das Gate).
    const K = S.karte, alt = 48 - S.mitte, G = (k) => [Math.ceil(Sim.RAND / Sim.RASTER) * Sim.RASTER, Math.floor((k - 1 - Sim.RAND) / Sim.RASTER) * Sim.RASTER];
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (let c = 0; c < K * K; c++) {
      if (S.feld[c] !== Sim.STRASSE) continue;
      const x = c % K, y = (c / K) | 0;
      x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
    }
    const [G0, G1] = G(K), [A0, A1] = G(96);
    const grenzAbstand = Math.min(x0 - G0, y0 - G0, G1 - x1, G1 - y1);
    const altAbstand = Math.min(x0 + alt - A0, y0 + alt - A0, A1 - x1 - alt, A1 - y1 - alt);
    const c730 = charakter(S);
    const g = [
      [k365.einwohner >= 300, `1  Einwohner an Tag 365: ${k365.einwohner} (≥ 300)`],
      [minPop > 0 && schlimmsterEinbruch <= 0.3, `2  Minimum ${minPop}, schlimmster 30-Tage-Einbruch ${(schlimmsterEinbruch * 100).toFixed(1)} % (Tag ${einbruchTag}) (nie 0, ≤ 30 %)`],
      [minBudget >= 0, `3  kleinstes Budget ${f0(minBudget)} (≥ 0)`],
      [bandFaktor <= 1.15 && grenzAbstand > 0, `4  läuft 730 Tage; Einwohner Tag 551–730 zwischen ${bandMin} und ${bandMax} (Faktor ${bandFaktor.toFixed(2)}, ≤ 1,15); Straßen wie auf der Karte 96 x ${x0 + alt}–${x1 + alt}, y ${y0 + alt}–${y1 + alt}, Abstand zur alten Baugrenze ${altAbstand}; Karte ${K} × ${K} (${S.erweiterung.wachsen.length}-mal gewachsen), Abstand zur Baugrenze ${grenzAbstand} (> 0)`],
      [c365.grN >= 5, `5  Gründungen durch Bewohner bis Tag 365: ${c365.grN} (≥ 5)`],
      [c365.grE - c365.erwE >= 15, `6  Gründer-Ehrgeiz ${c365.grE.toFixed(1)} vs. alle ${c365.erwE.toFixed(1)}: ${(c365.grE - c365.erwE).toFixed(1)} (≥ +15)`],
      [c365.erwH - c365.wzH >= 15, `7  Wegzieher-Heimatliebe ${c365.wzH.toFixed(1)} vs. alle ${c365.erwH.toFixed(1)}: −${(c365.erwH - c365.wzH).toFixed(1)} (n=${c365.wzN}) (≥ 15 weniger)`],
      [ms365 < 5000, `T  365 Tage in ${f0(ms365)} ms (< 5000)`],
      [arbeitZeilen / S.tag <= 0.5, `B  Stadtbuch ${(S.buchNr / S.tag).toFixed(2)} Zeilen am Tag, davon Bauhof ${(arbeitZeilen / S.tag).toFixed(2)} (≤ 0,5; kein Spec-Gate)`],
    ];
    for (const [ok, t] of g) { console.log(`  ${ok ? '✓' : '✗'} ${t}`); if (!ok) alleOk = false; }
    if (S.stat.tech) {                                        // Tech-Firmen (kein Gate): wie viele, wie groß, was die Leute kaufen
      const t = S.stat.tech, st = [0, 0, 0, 0];
      let erw = 0, mitGeraet = 0;
      for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.TECH && !S.g.leer[b] && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === Sim.TECH) st[S.g.stufe[b]]++;
      for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] >= 18 * Sim.R.JAHR) { erw++; if (S.p.geraet[p]) mitGeraet++; }
      const kaeufe = t.kaeufe.reduce((a, b) => a + b, 0);
      console.log(`  Tech: gegründet ${t.gruendungen}, offen an Tag 730 ${st[1] + st[2] + st[3]} (Stufe 2: ${st[2]}, Stufe 3: ${st[3]}), Anteil an den Umland-Stellen ${(S.techPlaetze / Math.max(1, S.werkstattPlaetze) * 100).toFixed(1)} %,`
        + ` Versionen ${t.versionen}, Käufe je Tag ${((kaeufe - kauf365) / 365).toFixed(1)} (Tag 366–730), Anbauten ${t.anbauten}, Tech-Pleiten ${t.pleiten}, Erwachsene mit Gerät ${(mitGeraet / Math.max(1, erw) * 100).toFixed(0)} %, Tech-Zeilen im Stadtbuch ${(techZeilen / S.tag).toFixed(2)} am Tag`);
    }
    if (S.stat.regierung) {                                   // Stadtregierung (kein Gate): Tageswerte an Tag 700–730, Summen seit Tag 0
      const r = S.stat.regierung, d = (k) => Math.round((r[k] - reg700[k]) / 30);
      console.log(`  Stadtregierung, am Tag (Tag 700–730): Lohnsteuer ${d('lohnsteuer')} (alte Regel ${d('lohnsteuerAlt')}), Budget ${Math.round((S.budget - budget700) / 30) >= 0 ? '+' : ''}${Math.round((S.budget - budget700) / 30)};`
        + ` von außen: Rentenkasse ${d('rentenkasse')}, Bund ${d('praemie') + d('betreuung') + d('gs')} (Prämien ${d('praemie')}, Betreuungsgehalt ${d('betreuung')}, Grundsicherung ${d('gs')})`);
      console.log(`  bis Tag 730: ${r.praemien} Prämien, ${r.betreuungTage} Tage Betreuungsgehalt, ${r.gsTage} Tage Grundsicherung, gemeinnützige Arbeit ${r.gemeinnuetzig}-mal,`
        + ` ${r.vorbehaltTage} Tage mit Wohnungsvorbehalt (${r.vorbehalten} Wohnungstage), Budget ${Math.round(S.budget)}, Notwerkstätten ${S.stat.bauamt.notwerkstaetten}`);
      if (r.kaeufe !== undefined) {                          // Schritt 2 (kein Gate): Mieterkauf und Renteneintritt bis Tag 730
        const ri = Sim.regierungInfo(S);
        console.log(`  Schritt 2 bis Tag 730: ${ri.eigentuemer} von ${ri.haushalte} Haushalten im Eigentum (${ri.abbezahlt} abbezahlt), ${r.kaeufe} Käufe, ${r.rueckkaeufe} Rückkäufe,`
          + ` ${r.erbfaelle} Erbfälle; ${r.ruhestand} Renteneintritte durch Kündigung, davon ${r.fruehRuhestand} vor 67 (Ø ${r.fruehRuhestand ? (r.fruehAlter / r.fruehRuhestand / Sim.R.JAHR).toFixed(1) : '–'} Jahre),`
          + ` ${r.fruehSchluss} vor 67 durch Schließung; ${r.rentnerLohnTage} Lohntage von Rentnern, Freibetrag ${r.rentnerEntlastung} Taler`);
      }
      if (r.kitaPlatzTage !== undefined) {                   // Schritt 2, Kitas (kein Gate)
        const k = Sim.regierungInfo(S).kita;
        console.log(`  Kitas an Tag 730: ${k.offen} offen (${S.stat.bauamt.kitas} gebaut), ${k.personal} Fachkräfte (Bedarf ${k.stellen}), Lohn ${k.lohn}, ${k.kinder} Kinder mit Platz (${k.krippe} unter 3), ${k.warten} warten`
          + ` (${k.fern} ohne Kita-Angebot in der Nähe), ${k.zuhause} unter 3 zu Hause betreut, ${k.gebunden} gebunden; bis Tag 730: ${r.kitaLuecke}-mal Stelle aufgegeben,`
          + ` ${r.kitaOhne} Haushaltsnächte nur mit Besitzern, ${r.kitaFern} ohne Kita-Angebot in der Nähe, Kosten ${Math.round(r.kitaKosten / 730)} Taler am Tag`);
      }
    }
    if (S.stat.sicherheit) {                                  // Sicherheit (Version 7, kein Gate)
      const s = S.stat.sicherheit, i = Sim.sicherheitInfo(S), t = s.taten[1] + s.taten[2] + s.taten[3], a = s.aufgeklaert[1] + s.aufgeklaert[2] + s.aufgeklaert[3];
      console.log(`  Sicherheit bis Tag 730: ${t} Taten (Diebstahl ${s.taten[1]}, Einbruch ${s.taten[2]}, Betrug ${s.taten[3]}), aufgeklärt ${a} (${(100 * a / Math.max(1, t)).toFixed(0)} %),`
        + ` ${s.urteile} Urteile (Geldstrafe ${s.geldstrafen}, Ersatzfreiheitsstrafe ${s.ersatz}, Freiheitsstrafe ${s.freiheit}), U-Haft ${s.uHaft}, Haftantritte ${s.haftAntritte}, Widerrufe ${s.widerrufe},`
        + ` Obhut ${s.obhutFamilie} Familie / ${s.obhutJugendamt} Jugendamt; an Tag 730 in Haft ${i.haft} (Anstalt in der Stadt ${i.hier}, von außerhalb ${i.aussen}), Polizei ${i.polizei}/${i.wacheStellen},`
        + ` Vollzug ${i.vollzug}/${i.jvaStellen}; Wache ${i.wache >= 0 ? 'ja' : 'nein'}, Anstalt ${i.jva >= 0 ? 'ja' : 'nein'}; vom Land ${Math.round((s.landLohn + s.haftLohn) / 730)} Taler am Tag, Bauten ${s.landBau}`);
    }
    if (S.stat.bund) {                                        // Bund (Version 7, Teil 3, kein Gate)
      const s = S.stat.bund, i = Sim.bundInfo(S), n = s.wehrdienst + s.ersatzdienst;
      console.log(`  Bund bis Tag 730: Kaserne offen ab Tag ${i.kOffen || '–'}, Dienststelle ab Tag ${i.dOffen || '–'}; ${n} einberufen (Wehrdienst ${s.wehrdienst}, Ersatzdienst ${s.ersatzdienst},`
        + ` ${Math.round(100 * s.ersatzdienst / Math.max(1, n))} %), ${s.dienstTage} Diensttage, ${s.beendet} beendet, ${s.abgebrochen} abgebrochen; an Tag 730 ${i.soldaten}/${i.stellen.soldat} Soldaten`
        + ` (${i.verpflichtet} verpflichtet), ${i.zivil}/${i.stellen.zivil} Zivil, ${i.nachrichtendienst}/${i.stellen.dienst} Nachrichtendienst, ${i.wehr} im Wehr-, ${i.ersatz} im Ersatzdienst;`
        + ` vom Bund ${Math.round((s.lohnKaserne + s.lohnDienst + s.sold + s.soldErsatz) / 730)} Taler am Tag (Sold ${Math.round((s.sold + s.soldErsatz) / 730)}), Bauten ${s.bau}`);
    }
    console.log('  Tag 730:\n' + charakterText(c730));
  }
  console.log(`\nGate Phase 0: ${alleOk ? 'BESTANDEN' : 'NICHT BESTANDEN'}`);
  process.exit(alleOk ? 0 : 1);
} else {
  const seed = Number(arg('seed', '1')), tage = Number(arg('tage', '365')), alle = Number(arg('alle', '30'));
  console.log(`Seed ${seed}, ${tage} Spieltage`);
  console.log(tabelleKopf());
  let vor = null;
  const S = lauf(Sim, seed, tage, (S, k, ms) => {
    if (k.tag % alle === 0 || k.tag === tage) {
      let z = tabelleZeile(k, ms);
      if (flag('fluss')) {
        const st = S.stat, jetzt = { zu: st.zuzuege, weg: st.wegzuegePersonen, geb: st.geburten, tod: st.tode, gr: st.gruendungen, pl: st.pleiten };
        if (vor) z += `   | zu ${jetzt.zu - vor.zu}, weg ${jetzt.weg - vor.weg}, geb ${jetzt.geb - vor.geb}, tod ${jetzt.tod - vor.tod}, arbl ${(k.arbeitslosenquote * 100).toFixed(0)}%, ohneEK ${(k.unversorgt * 100).toFixed(0)}%, Läden ${k.laeden} Werkst ${k.werkstaetten} leer ${k.leerstand}`;
        vor = jetzt;
      }
      console.log(z);
    }
  });
  const k = Sim.kennzahlen(S), st = S.stat;
  console.log(`\nCharakter-Auswertung (Tag ${S.tag}):\n` + charakterText(charakter(S)));
  console.log(`\nStadt an Tag ${S.tag}: ${k.haeuser} Wohnhäuser, ${k.werkstaetten} Werkstätten, ${k.laeden} Läden, ${k.techfirmen} Tech-Firmen, ${k.kitas} Kitas`
    + ` (Betriebe: ${k.leerstand} leer, ${k.stadtBetriebe} städtisch, mit Kitas), ${k.parks} Parks, ${k.baustellen} Baustellen`);
  console.log(`  Arbeitslos ${k.arbeitslose} (${(k.arbeitslosenquote * 100).toFixed(1)} %), Umlandpreis ${k.exportPreis.toFixed(1)}, ohne Einkauf ${(k.unversorgt * 100).toFixed(1)} %`);
  console.log(`  Zuzüge ${st.zuzuege}, Wegzüge ${st.wegzuege} (Personen ${st.wegzuegePersonen}), Geburten ${st.geburten}, Tode ${st.tode}`);
  console.log(`  Paare ${st.paare}, Hochzeiten ${st.hochzeiten}, Trennungen ${st.trennungen}, Freundschaften ${st.freundschaften}`);
  console.log(`  Ziele erreicht ${st.zieleErreicht}, aufgegeben ${st.zieleAufgegeben}; Übernahmen ${st.uebernahmen}`);
  console.log(`  Bauamt: ${JSON.stringify(st.bauamt)}`);
  if (flag('diag')) {
    const P = S.p, J = Sim.R.JAHR, hist = [0, 0, 0, 0, 0], bed = [0, 0, 0, 0];
    let n = 0, elend = 0, kinder = 0, rentner = 0, obdach = 0, beiEltern = 0, schulden = 0;
    for (let p = 0; p < S.pMax; p++) {
      if (!P.lebt[p]) continue;
      const a = S.tag - P.geb[p];
      if (a < 18 * J) { kinder++; continue; }
      if (a >= 67 * J) rentner++;
      n++; hist[Math.min(4, Math.floor(P.zuf[p] / 20))]++;
      bed[0] += P.bGeld[p]; bed[1] += P.bWohnen[p]; bed[2] += P.bKontakt[p]; bed[3] += P.bFreizeit[p];
      if (P.elend[p] >= 7) elend++;
      if (P.wohnung[p] < 0) obdach++; else if (P.hh[p] !== p && P.hh[p] !== P.partner[p]) beiEltern++;
      if (P.geld[p] < 0) schulden++;
    }
    console.log(`  Zufriedenheit <20/<40/<60/<80/≥80: ${hist.join(' / ')}   (≥7 Tage elend: ${elend})`);
    console.log(`  Bedürfnisse Ø Geld ${(bed[0] / n).toFixed(0)}, Wohnen ${(bed[1] / n).toFixed(0)}, Kontakt ${(bed[2] / n).toFixed(0)}, Freizeit ${(bed[3] / n).toFixed(0)}`);
    console.log(`  Kinder ${kinder}, Rentner ${rentner}, ohne Wohnung ${obdach}, wohnt bei anderen ${beiEltern}, Schulden ${schulden}`);
  }
  if (flag('aktionen')) {
    console.log('  Aktionen (gewählt / ausgeführt):');
    for (let a = 1; a < Sim.AKTIONSNAMEN.length; a++) console.log(`    ${Sim.AKTIONSNAMEN[a].padEnd(16)} ${pad(st.gewaehlt[a], 8)} ${pad(st.ausgefuehrt[a], 8)}`);
  }
  const nb = Number(arg('buch', '0'));
  if (nb) { console.log(`\nStadtbuch (letzte ${nb}):`); for (const e of S.buch.slice(-nb)) console.log(`  Tag ${e.tag} — ${Sim.klartext(e.text)}`); }
}
