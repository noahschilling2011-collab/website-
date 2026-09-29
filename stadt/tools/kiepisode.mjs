// Episoden der Trainingsumgebung (Etappe 1): eine lernende Fokusperson, die übrige Stadt entscheidet nach Regeln. Genutzt von
// tools/kiumgebung.mjs (JSONL-Server für Python), tools/werte_aus.mjs (Vergleich Regeln gegen Policy), tools/paritaet.mjs und
// simtest --kipolicy. Entwicklungswerkzeug, nicht Teil des Produkts; dieselbe Simulation wie im Spiel (tools/simkern.mjs).
//
// Zeitschritt: 1 Spielstunde (Sim.stunde). Die Fokusperson entscheidet nur an ihren normalen Entscheidungszeitpunkten (7 und 18 Uhr oder
// nach einem Ereignis, genau wo stunde() entscheide() aufruft). Dort hält die Sim sie an (Sim.KI, Haken in entscheide) und merkt sich
// Beobachtung und Maske; nach dieser Stunde liefert die Umgebung die Aktion, ausgeführt mit erneuter Prüfung (Sim.KI.fokusAusfuehren).
// Zwischen Entscheidungszeitpunkten ist nur „warten“ erlaubt. vorspulen = true rechnet diese Stunden in einem Schritt durch und summiert
// die Belohnung (dasselbe Entscheidungsproblem mit weniger Schritten ohne Wahl); vorspulen = false hält nach jeder Stunde.
// Ist an einem Entscheidungszeitpunkt nur „warten“ erlaubt (z. B. in Haft), wartet die Umgebung selbst (gezählt als autoWarten).
// Version 9: Die Fokusperson ist bei der Auswahl kein Bürgermeister (istHaupt zählt ihn mit). Wird sie während der Episode gewählt, bleibt sie
// Fokusperson (die Maske sperrt dann Wechsel, Kündigen und Gründen wie bei den Regeln); gezählt als amtStunden. Im Spiel entscheidet der
// Bürgermeister nie nach der Policy.
import { zustandKopie, zustandLaden } from './simkern.mjs';

export const PROTOKOLL = 1;
// Belohnung v1 (training/BELOHNUNG.md): je gelebte Stunde Zufriedenheit/100/24; Notstand (Zufriedenheit unter 20) −0,5/24 je Stunde;
// Umkehr (Kündigen und wieder Suchen, Dauerumzug, Wiederholgründen, schnelle Trennung) −0,25, höchstens einmal je Spieltag; Wegzug: jede
// fehlende Stunde bis zum Zeitlimit zählt wie die schlechteste mögliche Stunde (−0,5/24 − 0,25/24), so kann Weggehen die Summe nie
// verbessern. Tod: echtes Ende ohne Abzug (nur ab 80 Jahren möglich, Entscheidungen ändern daran nichts).
// Belohnung v2 = v1 + Teil „treffen“ gegen leere Sozialereignisse: ein ausgeführtes freunde_treffen ohne Gegenüber (vorher und nachher
// keine Freunde) kostet 0,65, eines ohne Bedarf (Kontakt der Person steigt um weniger als 10, oder schon ein Treffen an diesem Tag) 0,3.
// Das hebt auf, was die Sim für ein leeres Treffen trotzdem gibt (+12 Kontakt ohne Gegenüber, +6 Freizeit immer): Beträge = 90-%-Wert
// des gemessenen Nutzens eines solchen Treffens (tools/ki_fallen.mjs --kalibrieren, Seeds 10000–10031; training/BELOHNUNG.md).
// v1 bleibt wählbar (--belohnung belohnung_v1), für alte Läufe.
const UMKEHR_FENSTER = { kuendigen: [['job_suchen', 'job_wechseln'], 30], job_suchen: [['kuendigen'], 30], job_wechseln: [['kuendigen', 'job_wechseln'], 30],
  wohnung_suchen: [['wohnung_suchen'], 30], trennen: [['zusammenziehen', 'partner_suchen'], 30], laden_gruenden: [['laden_gruenden'], 180] };
const V1 = { zufJeStunde: 1 / 24, notstandGrenze: 20, notstandJeStunde: -0.5 / 24, umkehr: -0.25, wegzugJeStunde: -0.75 / 24, umkehrFenster: UMKEHR_FENSTER,
  treffenOhneGegenueber: 0, treffenOhneBedarf: 0, treffenMinGewinn: 10 };
export const BELOHNUNGEN = {
  belohnung_v1: { version: 'belohnung_v1', ...V1 },
  belohnung_v2: { version: 'belohnung_v2', ...V1, treffenOhneGegenueber: -0.65, treffenOhneBedarf: -0.3 },
};
export const BELOHNUNG = BELOHNUNGEN.belohnung_v2;          // Standard für neue Läufe
// Szenarien (Lehrplan-Stufe 1): gewachsene kleine Stadt, keine Eingriffe. Start um 6 Uhr, damit die erste Entscheidung um 7 Uhr fällt
export const SZENARIEN = {
  stabil: { name: 'stabil', beschreibung: 'Lehrplan 1: Stadt nach 150 bis 230 Tagen Regeln, keine Eingriffe', startTag: (seed) => 150 + (seed % 5) * 20, startStunde: 6, tage: 30 },
};
// Ausgangslagen (Gruppen der Auswertung). Nur Lage und Persönlichkeit, nie Herkunft, Namen oder Einzug
const freunde = (S, p) => { let n = 0; for (let j = 0; j < 5; j++) if (S.p.freunde[p * 5 + j] >= 0) n++; return n; };
export const GRUPPEN = {
  alle: () => true,
  ohne_arbeit: (Sim, S, p) => S.p.arbeit[p] < 0 && S.p.besitz[p] < 0 && !Sim.rentner(S, p),
  mit_kind: (Sim, S, p) => (S.p.arbeit[p] >= 0 || S.p.besitz[p] >= 0) && S.p.kinder[p] > 0,
  wenig_kontakt: (Sim, S, p) => S.p.partner[p] < 0 && freunde(S, p) <= 1,
  gruendungsnah: (Sim, S, p) => S.p.ehrgeiz[p] >= 70 && S.p.besitz[p] < 0,
  rentennah: (Sim, S, p) => (S.tag - S.p.geb[p]) / Sim.R.JAHR >= 60,
};
// Feste neutrale Auswahl: Kandidaten nach ID aufsteigend, Index aus Seed und Episodennummer (Hash, kein Zufall der Stadt)
export function mische(a, b) {
  let h = (Math.imul((a >>> 0) ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(((b >>> 0) + 0x632be5ab) >>> 0, 0xc2b2ae35)) >>> 0;
  h ^= h >>> 16; h = Math.imul(h, 0x7feb352d) >>> 0; h ^= h >>> 15; h = Math.imul(h, 0x846ca68b) >>> 0; h ^= h >>> 16;
  return h >>> 0;
}
export function kandidaten(Sim, S, gruppe = 'alle') {
  const P = S.p, J = Sim.R.JAHR, pruef = GRUPPEN[gruppe];
  if (!pruef) throw new Error('unbekannte Gruppe ' + gruppe);
  const L = [];
  for (let p = 0; p < S.pMax; p++) {
    if (!P.lebt[p] || P.haftBis[p] || Sim.istHaupt(S, p)) continue;
    const a = S.tag - P.geb[p];
    if (a < Sim.R.ERWACHSEN * J || a >= Sim.R.RENTE * J) continue;
    if (pruef(Sim, S, p)) L.push(p);
  }
  return L;
}

export class Umgebung {
  constructor(Sim, opt = {}) {
    this.B = BELOHNUNGEN[opt.belohnung || BELOHNUNG.version];
    if (!this.B) throw new Error('unbekannte Belohnung ' + opt.belohnung + ' (bekannt: ' + Object.keys(BELOHNUNGEN).join(', ') + ')');
    this.Sim = Sim; this.cache = new Map(); this.cacheMax = opt.cacheMax || 40;
    this.S = null; this.f = null; this.epi = null;
    this.N = Sim.KI.MERKMALE.length; this.NA = Sim.KI.AKTIONEN.length;
  }
  // Ausgangslage je Seed und Szenario, einmal gerechnet und als Kopie gehalten (LRU)
  startZustand(seed, szen) {
    const Sim = this.Sim, tag = szen.startTag(seed), key = `${seed}/${szen.name}/${tag}/${szen.startStunde}`;
    let k = this.cache.get(key);
    if (k) { this.cache.delete(key); this.cache.set(key, k); return k; }
    Sim.KI.fokusLoesen();
    const S = Sim.neueStadt(seed);
    Sim.kiSchalten(S, false);                               // keine Sprachmodell-Anfragen: Hauptfiguren entscheiden nach Regeln
    while (S.tag < tag || (S.tag === tag && S.stunde < szen.startStunde)) Sim.stunde(S);
    k = { kopie: zustandKopie(Sim, S), tag: S.tag, stunde: S.stunde, einwohner: S.einwohner };
    this.cache.set(key, k);
    while (this.cache.size > this.cacheMax) this.cache.delete(this.cache.keys().next().value);
    return k;
  }
  reset({ seed, nr = 0, szenario = 'stabil', gruppe = 'alle', tage } = {}) {
    const Sim = this.Sim, szen = SZENARIEN[szenario];
    if (!Number.isInteger(seed) || seed <= 0) throw new Error('reset: seed muss eine positive ganze Zahl sein');
    if (!szen) throw new Error('reset: unbekanntes Szenario ' + szenario);
    const k = this.startZustand(seed, szen);
    Sim.KI.fokusLoesen();
    const S = zustandLaden(Sim, k.kopie);
    const kand = kandidaten(Sim, S, gruppe);
    if (!kand.length) { const e = new Error(`keine Fokusperson (Seed ${seed}, Gruppe ${gruppe})`); e.code = 'keine_fokusperson'; throw e; }
    const id = kand[mische(seed, nr) % kand.length], gen = S.p.gen[id];
    this.S = S;
    this.f = Sim.KI.fokusSetzen(S, id, gen, mische(seed ^ 0x5bd1e995, nr) || 1);
    const P = S.p;
    this.epi = { seed, nr, szenario, gruppe, id, gen, kandidaten: kand.length, einwohner: S.einwohner, startTag: S.tag, startStunde: S.stunde,
      maxStunden: (tage || szen.tage) * 24, stunden: 0, beendet: false, abgeschnitten: false, ende: '',
      summe: { zufriedenheit: 0, notstand: 0, umkehr: 0, wegzug: 0, treffen: 0 }, gemacht: [], log: [], zieleGesehen: [], umkehrTag: -1, treffenTag: -1,
      metrik: { stunden: 0, defizit: 0, bedarf: [0, 0, 0, 0], notstand: 0, rest: 0, entscheidungen: 0, autoWarten: 0, jeAktion: new Array(this.NA).fill(0),
        warten: 0, ausgefuehrt: 0, fehlgeschlagen: 0, abgelehnt: 0, maskeVerletzt: 0, umkehr: 0, zieleErreicht: 0, zieleAufgegeben: 0, verpasst: 0,
        treffenOhneGegenueber: 0, treffenOhneBedarf: 0, amtStunden: 0,
        // Auswertung V9 (nur Messung): ausgeführte Aktionen je Art (Gründungen, Kinder), Betrieb am Anfang (am Ende: metrikFertig)
        ausgefuehrtJeAktion: new Array(this.NA).fill(0), betriebStart: P.besitz[id] >= 0 ? 1 : 0,
        persoenlichkeit: { fleiss: P.fleiss[id], gesellig: P.gesellig[id], ehrgeiz: P.ehrgeiz[id], spar: P.spar[id], heimat: P.heimat[id] },
        kontrolle: { zugezogen: P.elternA[id] < 0 ? 1 : 0 } } };   // nur Messung (Gruppenvergleich), nie Eingabe der Policy
    const r = this.laufen(true);
    return this.antwort(r, null);
  }
  lebt() { const P = this.S.p, e = this.epi; return P.lebt[e.id] === 1 && P.gen[e.id] === e.gen; }
  // Stunden rechnen bis zum nächsten Entscheidungszeitpunkt mit Wahl (oder eine Stunde), Belohnung je Stunde
  laufen(vorspulen) {
    const Sim = this.Sim, S = this.S, f = this.f, e = this.epi, B = this.B, m = e.metrik;
    const teile = { zufriedenheit: 0, notstand: 0, umkehr: 0, wegzug: 0, treffen: 0 };
    let stunden = 0;
    for (;;) {
      if (e.stunden >= e.maxStunden) { e.abgeschnitten = true; break; }
      Sim.stunde(S);
      e.stunden++; stunden++;
      if (f.ende || !this.lebt()) {                          // Tod oder Wegzug (auch mit dem Partner): echtes Ende
        e.beendet = true; e.ende = f.ende || 'weg';
        if (e.ende !== 'tod') { m.rest = e.maxStunden - e.stunden; teile.wegzug += m.rest * B.wegzugJeStunde; }
        break;
      }
      const P = S.p, p = e.id, zuf = P.zuf[p];
      teile.zufriedenheit += zuf / 100 * B.zufJeStunde;
      if (zuf < B.notstandGrenze) { teile.notstand += B.notstandJeStunde; m.notstand++; }
      m.stunden++; m.defizit += 100 - zuf;
      m.bedarf[0] += 100 - P.bGeld[p]; m.bedarf[1] += 100 - P.bWohnen[p]; m.bedarf[2] += 100 - P.bKontakt[p]; m.bedarf[3] += 100 - P.bFreizeit[p];
      this.zieleZaehlen();
      if (Sim.istBm(S, p)) m.amtStunden++;                   // Version 9: Fokusperson ist Bürgermeister (selten, nur gezählt)
      if (f.faellig) {
        let n = 0; for (let a = 0; a < this.NA; a++) n += f.faellig.maske[a];
        if (n <= 1) { Sim.KI.fokusAusfuehren(S, 0); m.autoWarten++; }   // keine Wahl: nur warten
        else break;
      }
      if (!vorspulen) break;
    }
    return { teile, stunden };
  }
  zieleZaehlen() {
    const P = this.S.p, e = this.epi, M = this.Sim.M, o = e.id * this.Sim.R.MEM;
    for (let i = o; i < o + this.Sim.R.MEM; i++) {
      const c = P.memCode[i];
      if ((c !== M.ZIEL_ERREICHT && c !== M.ZIEL_AUFGEGEBEN) || P.memTag[i] < e.startTag) continue;
      const key = `${i}:${P.memTag[i]}:${c}:${P.memRef[i]}`;
      if (e.zieleGesehen.includes(key)) continue;
      e.zieleGesehen.push(key);
      if (c === M.ZIEL_ERREICHT) e.metrik.zieleErreicht++; else e.metrik.zieleAufgegeben++;
    }
  }
  // aktion: Index in Sim.KI.AKTIONEN (0 = warten) oder 'regel' (Vergleichsarm: das normale Gehirn entscheidet an derselben Stelle)
  step(aktion, { vorspulen = true } = {}) {
    const Sim = this.Sim, S = this.S, f = this.f, e = this.epi, m = e && e.metrik;
    if (!e) throw new Error('step: erst reset');
    if (e.beendet || e.abgeschnitten) throw new Error('step: Episode ist vorbei');
    const fa = f.faellig;
    let wirkung = null, umkehr = 0, treffen = 0;
    const regel = aktion === 'regel';
    if (!regel && !(Number.isInteger(aktion) && aktion >= 0 && aktion < this.NA && (fa ? fa.maske[aktion] : aktion === 0))) {
      m.maskeVerletzt++;                                     // harte Invariante: abgelehnt, nichts geändert, Entscheidung bleibt offen
      const err = new Error(`Maske verletzt: Aktion ${aktion} ist ${fa ? 'nicht erlaubt' : 'ohne Entscheidungszeitpunkt nicht erlaubt (nur warten)'}`);
      err.code = 'maske_verletzt'; throw err;
    }
    if (fa) {
      const vor = this.folge(), kontaktVor = vor ? S.p.bKontakt[e.id] : 0;   // Kontakt direkt vor dem Ausführen (Belohnung v2: leere Treffen)
      wirkung = regel ? Sim.KI.fokusRegeln(S) : Sim.KI.fokusAusfuehren(S, aktion);
      const a = wirkung.aktion, name = Sim.KI.AKTIONEN[a];
      m.entscheidungen++; m.jeAktion[a]++;
      if (wirkung.art === 'warten') m.warten++;
      else if (wirkung.art === 'ausgefuehrt') { m.ausgefuehrt++; m.ausgefuehrtJeAktion[a]++; }
      else if (wirkung.art === 'fehlgeschlagen') m.fehlgeschlagen++;
      else if (wirkung.art === 'abgelehnt') m.abgelehnt++;
      else if (wirkung.art === 'maske_verletzt') { m.maskeVerletzt++; throw new Error('Maske verletzt (Sim)'); }
      if (wirkung.art === 'ausgefuehrt') {
        const fenster = this.B.umkehrFenster[name];
        if (fenster && e.gemacht.some(g => fenster[0].includes(g.name) && S.tag - g.tag <= fenster[1])) {
          m.umkehr++;                                        // gezählt jedes Mal, abgezogen höchstens einmal je Spieltag
          if (e.umkehrTag !== S.tag) { umkehr = this.B.umkehr; e.umkehrTag = S.tag; }
        }
        if (name === 'freunde_treffen' && vor) treffen = this.treffenPruefen(vor, kontaktVor, fa.tag);
        e.gemacht.push({ name, tag: S.tag });
        if (e.gemacht.length > 40) e.gemacht.shift();
      }
      let bits = 0; for (let k = 0; k < this.NA; k++) if (fa.maske[k]) bits |= 1 << k;
      e.log.push({ tag: fa.tag, h: fa.h, anlass: fa.anlass, maske: bits, aktion: name, art: wirkung.art, grund: wirkung.grund || '',
        folge: this.folgeDiff(vor, this.folge()) });
      if (e.log.length > 200) e.log.shift();
    }
    // Die Person kann durch die eigene Aktion weg sein (wegziehen): dann endet die Episode ohne weitere Stunde
    let r;
    if (f.ende || !this.lebt()) {
      e.beendet = true; e.ende = f.ende || 'weg';
      const teile = { zufriedenheit: 0, notstand: 0, umkehr: 0, wegzug: 0, treffen: 0 };
      if (e.ende !== 'tod') { m.rest = e.maxStunden - e.stunden; teile.wegzug = m.rest * this.B.wegzugJeStunde; }
      r = { teile, stunden: 0 };
    } else r = this.laufen(vorspulen);
    r.teile.umkehr += umkehr;
    r.teile.treffen += treffen;
    return this.antwort(r, wirkung);
  }
  // Belohnung v2: war das ausgeführte Treffen leer? Ohne Gegenüber: vorher und nachher keine Freunde (die Sim gibt trotzdem +12 Kontakt).
  // Ohne Bedarf: der eigene Kontakt stieg um weniger als treffenMinGewinn (war fast voll) oder es ist schon das zweite Treffen dieses Tages
  // (die Sim gibt trotzdem +6 Freizeit). Gezählt in jeder Version (Metrik), abgezogen nur mit Beträgen ≠ 0 (v2)
  treffenPruefen(vor, kontaktVor, tag) {
    const S = this.S, e = this.epi, m = e.metrik, B = this.B;
    if (!this.lebt()) return 0;
    const zweites = e.treffenTag === tag;
    e.treffenTag = tag;
    if (vor.freunde === 0 && freunde(S, e.id) === 0) { m.treffenOhneGegenueber++; return B.treffenOhneGegenueber; }
    if (zweites || S.p.bKontakt[e.id] - kontaktVor < B.treffenMinGewinn) { m.treffenOhneBedarf++; return B.treffenOhneBedarf; }
    return 0;
  }
  folge() {
    const P = this.S.p, p = this.epi.id;
    if (!this.lebt()) return null;
    return { geld: P.geld[p], arbeit: P.arbeit[p] >= 0 ? 1 : 0, wohnung: P.wohnung[p] >= 0 ? 1 : 0, partner: P.partner[p] >= 0 ? 1 : 0, freunde: freunde(this.S, p), zuf: +P.zuf[p].toFixed(2) };
  }
  folgeDiff(a, b) {
    if (!a || !b) return { weg: true };
    const d = {};
    for (const k of Object.keys(a)) if (a[k] !== b[k]) d[k] = [a[k], b[k]];
    return d;
  }
  // Harte Invarianten der Fokusperson (unabhängig von der Belohnung): Zahlen endlich, Bezüge in beide Richtungen
  invarianten(beob) {
    const S = this.S, P = S.p, p = this.epi.id, F = [];
    for (let i = 0; i < beob.length; i++) if (!Number.isFinite(beob[i])) F.push('Beobachtung ' + this.Sim.KI.MERKMALE[i][0] + ' nicht endlich');
    if (!this.lebt()) return F;
    if (!Number.isFinite(P.geld[p]) || !Number.isFinite(P.zuf[p])) F.push('Geld oder Zufriedenheit nicht endlich');
    const arb = P.arbeit[p];
    if (arb >= 0 && P.besitz[p] !== arb && !S.belegschaft[arb].includes(p)) F.push('arbeitet, steht aber nicht in der Belegschaft');
    const w = P.wohnung[p];
    if (w >= 0 && !S.bewohner[w].includes(p)) F.push('wohnt, steht aber nicht bei den Bewohnern');
    const pa = P.partner[p];
    if (pa >= 0 && (!P.lebt[pa] || P.partner[pa] !== p)) F.push('Partner nicht gegenseitig');
    return F;
  }
  antwort(r, wirkung) {
    const Sim = this.Sim, S = this.S, f = this.f, e = this.epi, B = this.B;
    let beob, maske;
    if (!e.beendet && !e.abgeschnitten && f.faellig) { beob = f.faellig.beob; maske = f.faellig.maske; }
    else {
      beob = this.lebt() ? Sim.KI.beobachtung(S, e.id, S.stunde, 0) : new Float32Array(this.N);
      maske = new Uint8Array(this.NA); maske[0] = 1;
    }
    const inv = this.invarianten(beob);
    if (inv.length) { const err = new Error('Invariante verletzt: ' + inv.join('; ')); err.code = 'invariante'; throw err; }
    const t = r.teile;
    for (const k of Object.keys(t)) e.summe[k] += t[k];
    const belohnung = t.zufriedenheit + t.notstand + t.umkehr + t.wegzug + t.treffen;
    const ende = e.beendet || e.abgeschnitten;
    if (ende) e.metrik.verpasst = f.verpasst;
    return { beob: Array.from(beob), maske: Array.from(maske), belohnung, teile: t, stunden: r.stunden,
      beendet: e.beendet, abgeschnitten: e.abgeschnitten && !e.beendet, grund: e.beendet ? e.ende : e.abgeschnitten ? 'zeitlimit' : '',
      info: { tag: S.tag, stunde: S.stunde, entscheidung: !ende && f.faellig ? { tag: f.faellig.tag, h: f.faellig.h, anlass: f.faellig.anlass } : null,
        wirkung, episodeStunden: e.stunden, ...(ende ? { metrik: this.metrikFertig(), summe: e.summe, belohnungVersion: B.version } : {}) } };
  }
  // Kennzahlen einer Episode (Auswertung): Mittel je gelebte Stunde; bei Wegzug zählen die fehlenden Stunden als volles Defizit (100)
  metrikFertig() {
    const m = this.epi.metrik, n = m.stunden, nm = n + m.rest;
    return { ...m, defizitMittel: nm ? (m.defizit + 100 * m.rest) / nm : 0, bedarfMittel: m.bedarf.map(v => (n ? v / n : 0)),
      notstandAnteil: nm ? (m.notstand + m.rest) / nm : 0, ende: this.epi.ende || (this.epi.abgeschnitten ? 'zeitlimit' : ''),
      betriebEnde: this.lebt() && this.S.p.besitz[this.epi.id] >= 0 ? 1 : 0,   // Auswertung V9: Betrieb besteht am Episodenende
      seed: this.epi.seed, nr: this.epi.nr, gruppe: this.epi.gruppe, kandidaten: this.epi.kandidaten, einwohner: this.epi.einwohner };
  }
  observe() {
    const e = this.epi;
    if (!e) throw new Error('observe: erst reset');
    const f = this.f;
    if (f.faellig && !e.beendet && !e.abgeschnitten) return { beob: Array.from(f.faellig.beob), maske: Array.from(f.faellig.maske), entscheidung: true };
    const beob = this.lebt() ? this.Sim.KI.beobachtung(this.S, e.id, this.S.stunde, 0) : new Float32Array(this.N);
    const maske = new Uint8Array(this.NA); maske[0] = 1;
    return { beob: Array.from(beob), maske: Array.from(maske), entscheidung: false };
  }
  // Schnappschuss nur an Haltepunkten (nach einer vollen Stunde): Zustand, Fokus (mit eigenem Zufallsstrom und offener Entscheidung), Episode
  snapshot() {
    const f = this.f, fa = f.faellig;
    return { zustand: zustandKopie(this.Sim, this.S),
      fokus: { id: f.id, gen: f.gen, rs: f.rs, verpasst: f.verpasst, zahl: f.zahl, ende: f.ende,
        faellig: fa ? { tag: fa.tag, h: fa.h, anlass: fa.anlass, beob: Array.from(fa.beob), maske: Array.from(fa.maske) } : null },
      epi: JSON.parse(JSON.stringify(this.epi)) };
  }
  restore(k) {
    const Sim = this.Sim;
    Sim.KI.fokusLoesen();
    const S = zustandLaden(Sim, k.zustand), q = k.fokus;
    let f;
    if (S.p.lebt[q.id] && S.p.gen[q.id] === q.gen) f = Sim.KI.fokusSetzen(S, q.id, q.gen, q.rs);
    else f = { S, id: q.id, gen: q.gen, rs: q.rs, innen: false };   // Episode war schon vorbei: nichts mehr anmelden
    Object.assign(f, { verpasst: q.verpasst, zahl: q.zahl, ende: q.ende,
      faellig: q.faellig ? { tag: q.faellig.tag, h: q.faellig.h, anlass: q.faellig.anlass, beob: Float32Array.from(q.faellig.beob), maske: Uint8Array.from(q.faellig.maske) } : null });
    this.S = S; this.f = f; this.epi = JSON.parse(JSON.stringify(k.epi));
  }
}
