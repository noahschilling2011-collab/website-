import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Arbeitszeiten } from '../db/schema';
import type { SourceCapabilities } from './calendar/types';
import { freieSlots, waehleVorschlaege } from './slots';
import { datumInZone, formatiereDeutsch, lokalZuUtc, offsetMinuten } from './zeit';

const ZONE = 'Europe/Berlin';

// Katrin aus Abschnitt 2 des Entwurfs: Mo-Do 8-17 Uhr.
const ARBEITSZEITEN: Arbeitszeiten = {
  '1': [{ von: '08:00', bis: '17:00' }],
  '2': [{ von: '08:00', bis: '17:00' }],
  '3': [{ von: '08:00', bis: '17:00' }],
  '4': [{ von: '08:00', bis: '17:00' }],
};

const OAUTH: SourceCapabilities = { push: false, detail: 'busy', maxStalenessSeconds: 0 };
const ICS: SourceCapabilities = { push: false, detail: 'full', maxStalenessSeconds: 900 };

/** Stunde in der Zone als Zahl, ohne die formatierte Zeichenkette zu parsen. */
function stundeIn(instant: Date): number {
  const teil = new Intl.DateTimeFormat('en-US', {
    timeZone: ZONE,
    hour: '2-digit',
    hour12: false,
  })
    .formatToParts(instant)
    .find((p) => p.type === 'hour');
  return Number(teil?.value ?? NaN);
}

test('Zeitzone: Sommerzeit und Winterzeit haben verschiedene Offsets', () => {
  assert.equal(offsetMinuten(new Date('2026-08-05T12:00:00Z'), ZONE), 120); // CEST
  assert.equal(offsetMinuten(new Date('2026-01-05T12:00:00Z'), ZONE), 60); // CET
});

test('lokalZuUtc trifft die Wandzeit ueber die Umstellung hinweg', () => {
  // 5. August, 09:00 Berliner Zeit = 07:00 UTC (Sommerzeit).
  assert.equal(lokalZuUtc(2026, 8, 5, 9, 0, ZONE).toISOString(), '2026-08-05T07:00:00.000Z');
  // 5. Januar, 09:00 Berliner Zeit = 08:00 UTC (Winterzeit).
  assert.equal(lokalZuUtc(2026, 1, 5, 9, 0, ZONE).toISOString(), '2026-01-05T08:00:00.000Z');
  // Direkt nach der Rueckstellung Ende Oktober.
  assert.equal(lokalZuUtc(2026, 10, 26, 9, 0, ZONE).toISOString(), '2026-10-26T08:00:00.000Z');
});

test('datumInZone liefert den ISO-Wochentag', () => {
  // 5. August 2026 ist ein Mittwoch.
  const d = datumInZone(new Date('2026-08-05T12:00:00Z'), ZONE);
  assert.deepEqual(d, { jahr: 2026, monat: 8, tag: 5, wochentag: 3 });
});

test('Slots liegen nur innerhalb der Arbeitszeiten', () => {
  const slots = freieSlots(
    [],
    {
      von: new Date('2026-08-10T00:00:00Z'), // Montag
      bis: new Date('2026-08-11T00:00:00Z'),
      dauerMinuten: 45,
      arbeitszeiten: ARBEITSZEITEN,
      zeitzone: ZONE,
      vorlaufStunden: 0,
      jetzt: new Date('2026-08-09T00:00:00Z'),
    },
    OAUTH,
  );
  assert.ok(slots.length > 0, 'es muss Slots geben');
  for (const slot of slots) {
    // Nicht die formatierte Zeichenkette parsen: de-DE schreibt "09 Uhr",
    // und Number("09 Uhr") ist NaN. formatToParts liefert den reinen Wert.
    assert.ok(stundeIn(slot.start) >= 8, `Slot beginnt vor 8 Uhr`);
    assert.ok(stundeIn(slot.ende) <= 17, `Slot endet nach 17 Uhr`);
  }
});

test('Freitag ist frei und liefert keine Slots', () => {
  const slots = freieSlots(
    [],
    {
      von: new Date('2026-08-14T00:00:00Z'), // Freitag
      bis: new Date('2026-08-15T00:00:00Z'),
      dauerMinuten: 45,
      arbeitszeiten: ARBEITSZEITEN,
      zeitzone: ZONE,
      vorlaufStunden: 0,
      jetzt: new Date('2026-08-13T00:00:00Z'),
    },
    OAUTH,
  );
  assert.equal(slots.length, 0);
});

test('Belegte Zeiten blockieren, inklusive Puffer davor und danach', () => {
  const belegt = [
    {
      start: new Date('2026-08-10T08:00:00Z'), // 10:00 Berliner Zeit
      end: new Date('2026-08-10T09:00:00Z'), // 11:00 Berliner Zeit
      source: 'test',
    },
  ];
  const slots = freieSlots(
    belegt,
    {
      von: new Date('2026-08-10T00:00:00Z'),
      bis: new Date('2026-08-11T00:00:00Z'),
      dauerMinuten: 45,
      pufferMinuten: 15,
      arbeitszeiten: ARBEITSZEITEN,
      zeitzone: ZONE,
      vorlaufStunden: 0,
      jetzt: new Date('2026-08-09T00:00:00Z'),
    },
    OAUTH,
  );
  const sperrVon = new Date('2026-08-10T07:45:00Z').getTime();
  const sperrBis = new Date('2026-08-10T09:15:00Z').getTime();
  for (const slot of slots) {
    const kollidiert = slot.start.getTime() < sperrBis && slot.ende.getTime() > sperrVon;
    assert.equal(kollidiert, false, `Slot ${slot.start.toISOString()} kollidiert mit Puffer`);
  }
});

test('maxStalenessSeconds haelt Slots frei, die gerade belegt worden sein koennten', () => {
  const jetzt = new Date('2026-08-10T06:00:00Z'); // 08:00 Berliner Zeit
  const anfrage = {
    von: new Date('2026-08-10T06:00:00Z'),
    bis: new Date('2026-08-10T22:00:00Z'),
    dauerMinuten: 45,
    arbeitszeiten: ARBEITSZEITEN,
    zeitzone: ZONE,
    vorlaufStunden: 0,
    jetzt,
  };

  const mitOauth = freieSlots([], anfrage, OAUTH);
  const mitIcs = freieSlots([], anfrage, ICS);

  assert.ok(mitOauth.length > 0 && mitIcs.length > 0);
  // Bei OAuth (Alter 0) darf der erste Slot sofort beginnen, bei einem
  // 15-Minuten-Feed erst 15 Minuten spaeter.
  const differenz = mitIcs[0]!.start.getTime() - mitOauth[0]!.start.getTime();
  assert.ok(
    differenz >= 15 * 60_000,
    `Der ICS-Weg muss mindestens 15 Minuten Abstand halten, hatte aber ${differenz / 60000} Minuten`,
  );
});

test('Vorschlaege verteilen sich auf verschiedene Tage', () => {
  const slots = freieSlots(
    [],
    {
      von: new Date('2026-08-10T00:00:00Z'),
      bis: new Date('2026-08-14T00:00:00Z'),
      dauerMinuten: 45,
      arbeitszeiten: ARBEITSZEITEN,
      zeitzone: ZONE,
      vorlaufStunden: 0,
      jetzt: new Date('2026-08-09T00:00:00Z'),
    },
    OAUTH,
  );
  const vorschlaege = waehleVorschlaege(slots, 3, ZONE);
  assert.equal(vorschlaege.length, 3);

  const tage = new Set(
    vorschlaege.map((s) => {
      const d = datumInZone(s.start, ZONE);
      return `${d.jahr}-${d.monat}-${d.tag}`;
    }),
  );
  assert.equal(tage.size, 3, 'jeder Vorschlag muss auf einem anderen Tag liegen');
});

test('Vorschlaege verteilen sich auch ueber den Tag, nicht nur ueber Tage', () => {
  // "Montag 8:00, Dienstag 8:00, Mittwoch 8:00" wirkt maschinell und trifft
  // niemanden, dem der Morgen nicht passt.
  const slots = freieSlots(
    [],
    {
      von: new Date('2026-08-10T00:00:00Z'),
      bis: new Date('2026-08-14T00:00:00Z'),
      dauerMinuten: 45,
      arbeitszeiten: ARBEITSZEITEN,
      zeitzone: ZONE,
      vorlaufStunden: 0,
      jetzt: new Date('2026-08-09T00:00:00Z'),
    },
    OAUTH,
  );

  const vorschlaege = waehleVorschlaege(slots, 3, ZONE);
  const stunden = vorschlaege.map((s) => stundeIn(s.start));
  assert.equal(new Set(stunden).size, 3, `alle drei zur selben Zeit: ${stunden.join(', ')}`);

  // Der erste liegt frueh, der letzte spaet am Tag.
  assert.ok(stunden[0]! < stunden[2]!, 'die Auswahl muss ueber den Tag wandern');
});

test('Formatierung fuer die Mail an den Dritten ist deutsch und lesbar', () => {
  const text = formatiereDeutsch(new Date('2026-08-18T12:00:00Z'), ZONE);
  assert.match(text, /Dienstag/);
  assert.match(text, /18\. August/);
  assert.match(text, /14:00/); // 12:00 UTC = 14:00 Berliner Sommerzeit
});
