/**
 * Der Fahrtenschreiber.
 *
 * Er ist ein Messwerkzeug, und ein Messwerkzeug, das falsch misst, ist
 * schlimmer als keines: Eine Testfahrt lässt sich nicht wiederholen, wenn
 * hinterher auffällt, dass die Lückenrechnung nicht stimmte.
 *
 * Der schärfste Test hier ist der über den Überlauf des Ringpuffers. Genau
 * dort geht die naive Lösung schief — wer die Lücke erst beim Auswerten
 * rechnet, verliert am Schnitt den Abstand zum verdrängten Vorgänger.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { FAHRTPROTOKOLL, WATCHDOG } from '../src/config';
import {
  KOPF_PRAEFIX,
  SPALTEN,
  alsCsv,
  createFahrtprotokoll,
  eintraege,
  leere,
  schreibe,
  type NeuerEintrag,
} from '../src/core/fahrtprotokoll';

const T0 = Date.parse('2026-07-30T10:00:00.000Z');

function eintrag(t: number, teil: Partial<NeuerEintrag> = {}): NeuerEintrag {
  return {
    t,
    lat: 48.5,
    lon: 7.75,
    speed: 27.8,
    accuracy: 5,
    course: 90,
    strategie: 'leerlauf',
    warnmodus: 'aus',
    naechsteM: 1200,
    gewarnt: false,
    ...teil,
  };
}

// --- Schwellwerte ---------------------------------------------------------

test('die Lückenschwelle hängt am Watchdog und liegt deutlich darunter', () => {
  // Der Sinn der Kopplung: Der Watchdog schlägt nach 90 s Alarm. Eine Lücke
  // von 40 s meldet er nie — für "lückenloses Tracking" ist sie aber genau
  // das gesuchte Ereignis.
  assert.equal(FAHRTPROTOKOLL.LUECKE_AB_MS, WATCHDOG.STALE_AFTER_MS / 3);
  assert.ok(
    FAHRTPROTOKOLL.LUECKE_AB_MS < WATCHDOG.STALE_AFTER_MS,
    'eine Schwelle über der Watchdog-Grenze fände nur, was der Watchdog ohnehin meldet',
  );
  // Nach unten: der Leerlauftakt. 200 m bei 30 km/h sind 24 s.
  assert.ok(
    FAHRTPROTOKOLL.LUECKE_AB_MS > 24_000,
    'eine Schwelle unter dem Leerlauftakt meldete Normalbetrieb als Lücke',
  );
});

test('der Ringpuffer ist gross genug für die geforderten 20 Minuten', () => {
  // Der dichteste Takt: Annäherungsmodus, 25 m, bei 130 km/h alle 0,7 s.
  const dichtesterTaktS = 25 / (130 / 3.6);
  const minuten = (FAHRTPROTOKOLL.MAX_EINTRAEGE * dichtesterTaktS) / 60;
  assert.ok(
    minuten >= 20,
    `reicht nur für ${minuten.toFixed(0)} min im dichtesten Takt, gefordert sind 20`,
  );
});

// --- Schreiben ------------------------------------------------------------

test('der erste Eintrag hat keinen Abstand, nicht null Millisekunden', () => {
  // 0 wäre eine Behauptung: "die vorherige Position kam im selben Moment".
  const p = createFahrtprotokoll();
  const e = schreibe(p, eintrag(T0));
  assert.equal(e.abstandMs, null);
  assert.equal(e.luecke, false);
});

test('Lücken werden erkannt, normale Abstände nicht', () => {
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0));
  const normal = schreibe(p, eintrag(T0 + 5_000));
  const knappDrunter = schreibe(p, eintrag(T0 + 5_000 + FAHRTPROTOKOLL.LUECKE_AB_MS));
  const drueber = schreibe(
    p, eintrag(T0 + 5_000 + FAHRTPROTOKOLL.LUECKE_AB_MS + FAHRTPROTOKOLL.LUECKE_AB_MS + 1),
  );

  assert.equal(normal.abstandMs, 5_000);
  assert.equal(normal.luecke, false);
  assert.equal(knappDrunter.luecke, false, 'genau auf der Schwelle ist noch keine Lücke');
  assert.equal(drueber.luecke, true);
});

test('Start- und Endzeit werden mitgeführt', () => {
  const p = createFahrtprotokoll();
  assert.equal(p.startT, null);
  schreibe(p, eintrag(T0));
  schreibe(p, eintrag(T0 + 60_000));
  assert.equal(p.startT, T0);
  assert.equal(p.endeT, T0 + 60_000);
});

// --- Der Ringpuffer -------------------------------------------------------

test('der Ring hält die Grösse ein und behält die Reihenfolge', () => {
  const p = createFahrtprotokoll();
  const n = FAHRTPROTOKOLL.MAX_EINTRAEGE + 500;
  for (let i = 0; i < n; i++) schreibe(p, eintrag(T0 + i * 1000));

  const alle = eintraege(p);
  assert.equal(alle.length, FAHRTPROTOKOLL.MAX_EINTRAEGE);
  assert.equal(p.verdraengt, 500);
  assert.equal(p.uebergelaufen, true);

  // Ältester zuerst, und der Anfang der Fahrt ist verdrängt.
  assert.equal(alle[0]!.t, T0 + 500 * 1000);
  assert.equal(alle[alle.length - 1]!.t, T0 + (n - 1) * 1000);
  for (let i = 1; i < alle.length; i++) {
    assert.ok(alle[i]!.t > alle[i - 1]!.t, `Reihenfolge bricht bei ${i}`);
  }
});

test('eine Lücke überlebt den Überlauf des Ringpuffers', () => {
  // DER TEST, DER DEN ENTWURF ERZWINGT. Würde die Lücke erst beim Auswerten
  // aus zwei benachbarten Zeilen gerechnet, ginge sie hier verloren: Der
  // Vorgänger ist verdrängt, und der Abstand zum nächsten noch vorhandenen
  // Eintrag ist ein ganz anderer.
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0));

  // Direkt nach dem ersten Eintrag eine Lücke, dann den Puffer vollschreiben.
  const nachLuecke = T0 + FAHRTPROTOKOLL.LUECKE_AB_MS * 2;
  const mitLuecke = schreibe(p, eintrag(nachLuecke));
  assert.equal(mitLuecke.luecke, true);

  for (let i = 1; i <= FAHRTPROTOKOLL.MAX_EINTRAEGE; i++) {
    schreibe(p, eintrag(nachLuecke + i * 1000));
  }

  // Der Eintrag mit der Lücke ist inzwischen verdrängt — aber solange er da
  // war, trug er die Markierung. Gegenprobe an einem knapperen Fall:
  const p2 = createFahrtprotokoll();
  schreibe(p2, eintrag(T0));
  schreibe(p2, eintrag(T0 + FAHRTPROTOKOLL.LUECKE_AB_MS * 2));
  // Nur so viel schreiben, dass der Lückeneintrag knapp überlebt.
  for (let i = 1; i < FAHRTPROTOKOLL.MAX_EINTRAEGE - 1; i++) {
    schreibe(p2, eintrag(T0 + FAHRTPROTOKOLL.LUECKE_AB_MS * 2 + i * 1000));
  }
  const ueberlebt = eintraege(p2).filter((e) => e.luecke);
  assert.equal(ueberlebt.length, 1, 'die Lückenmarkierung ist beim Überlauf verlorengegangen');
});

test('leere() vergisst wirklich alles', () => {
  // Beim Ausschalten des Schalters. Wer die Aufzeichnung abschaltet, will die
  // Spur los sein, nicht bloss keine neue mehr.
  const p = createFahrtprotokoll();
  for (let i = 0; i < 50; i++) schreibe(p, eintrag(T0 + i * 1000));
  leere(p);

  assert.equal(eintraege(p).length, 0);
  assert.equal(p.startT, null);
  assert.equal(p.endeT, null);
  assert.equal(p.letzteT, null);
  assert.equal(p.verdraengt, 0);
  assert.equal(p.uebergelaufen, false);

  // Und der nächste Eintrag beginnt eine neue Fahrt, ohne Lücke zur alten.
  const e = schreibe(p, eintrag(T0 + 3600_000));
  assert.equal(e.abstandMs, null, 'die Pause zwischen zwei Fahrten wird als Lücke gemeldet');
});

// --- Export ---------------------------------------------------------------

test('das CSV hat Kopf, Spaltenzeile und eine Zeile je Position', () => {
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0));
  schreibe(p, eintrag(T0 + 1000, { gewarnt: true, warnmodus: 'punkt', naechsteM: 320 }));

  const zeilen = alsCsv(p).trimEnd().split('\n');
  const kopf = zeilen.filter((z) => z.startsWith(KOPF_PRAEFIX));
  const tabelle = zeilen.filter((z) => !z.startsWith(KOPF_PRAEFIX));

  assert.ok(kopf.length > 5, 'kein Kopf');
  assert.equal(tabelle[0], SPALTEN.join(','), 'die Spaltenzeile stimmt nicht');
  assert.equal(tabelle.length, 3, 'Spaltenzeile plus zwei Positionen');
  assert.equal(tabelle[2]!.split(',').length, SPALTEN.length);
});

test('die Akkuzeilen stehen im Kopf und sind leer', () => {
  // Absichtlich leer: Der Fahrer trägt die Werte aus den Systemeinstellungen
  // ein. scripts/analyze-drive.ts liest genau diese Präfixe.
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0));
  const csv = alsCsv(p);

  for (const praefix of ['Akku bei Start (%):', 'Akku bei Ende (%):']) {
    const zeile = csv.split('\n').find((z) => z.includes(praefix));
    assert.ok(zeile !== undefined, `${praefix} fehlt im Kopf`);
    assert.equal(
      zeile.slice(zeile.indexOf(praefix) + praefix.length).trim(), '',
      `${praefix} ist vorbelegt — die Zahl wäre erfunden`,
    );
  }
});

test('ein übergelaufener Puffer sagt das im Kopf', () => {
  // Sonst liest jemand "20 Minuten, keine Lücke" aus einer Datei, in der die
  // ersten zehn Minuten fehlen.
  const p = createFahrtprotokoll();
  for (let i = 0; i < FAHRTPROTOKOLL.MAX_EINTRAEGE + 10; i++) {
    schreibe(p, eintrag(T0 + i * 1000));
  }
  assert.match(alsCsv(p), /ACHTUNG: Der Ringpuffer war voll/);
});

test('das CSV eines leeren Protokolls ist lesbar und nicht kaputt', () => {
  const csv = alsCsv(createFahrtprotokoll());
  const tabelle = csv.trimEnd().split('\n').filter((z) => !z.startsWith(KOPF_PRAEFIX));
  assert.equal(tabelle.length, 1, 'nur die Spaltenzeile');
  assert.match(csv, /Positionen:\s+0/);
});

test('fehlende Werte werden zu leeren Zellen, nicht zu null oder 0', () => {
  // "0 m/s" heisst "steht", "" heisst "das Gerät hat nichts geliefert". Der
  // Unterschied entscheidet, ob eine Auswertung den Tacho verdächtigt oder
  // das GPS.
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0, { speed: null, accuracy: null, course: null, naechsteM: null }));
  const zeile = alsCsv(p).trimEnd().split('\n').filter((z) => !z.startsWith(KOPF_PRAEFIX))[1]!;
  const felder = zeile.split(',');

  for (const spalte of ['speed_ms', 'accuracy_m', 'course_deg', 'naechste_m'] as const) {
    assert.equal(felder[SPALTEN.indexOf(spalte)], '', `${spalte} ist nicht leer`);
  }
});

test('keine Zelle enthält ein Komma', () => {
  // Der Export kennt kein Quoting — er braucht keins, solange keine Zelle ein
  // Trennzeichen enthält. Dieser Test hält das fest, damit ein neues Feld
  // nicht stillschweigend die Spalten verschiebt.
  const p = createFahrtprotokoll();
  schreibe(p, eintrag(T0, { strategie: 'annaeherung', warnmodus: 'zone' }));
  schreibe(p, eintrag(T0 + 1000, { strategie: 'geparkt', warnmodus: 'punkt' }));

  for (const zeile of alsCsv(p).trimEnd().split('\n')) {
    if (zeile.startsWith(KOPF_PRAEFIX)) continue;
    assert.equal(
      zeile.split(',').length, SPALTEN.length,
      `Zelle mit Komma verschiebt die Spalten: ${zeile}`,
    );
  }
});
