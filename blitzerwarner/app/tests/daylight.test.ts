import { test } from 'node:test';
import assert from 'node:assert/strict';

import { istNacht, sonnenhoehe } from '../src/core/daylight';

// Stuttgart, rund 48,77 N / 9,18 O.
const LAT = 48.7712;
const LON = 9.1834;

test('Sommer-Mittag ist hell, Sommer-Mitternacht ist Nacht', () => {
  // 21. Juni, 12:00 UTC — mitten am Tag in Mitteleuropa.
  const mittag = new Date('2026-06-21T12:00:00Z');
  assert.ok(sonnenhoehe(LAT, LON, mittag) > 55, `Höhe ${sonnenhoehe(LAT, LON, mittag)}`);
  assert.equal(istNacht(LAT, LON, mittag), false);

  const mitternacht = new Date('2026-06-21T23:00:00Z');
  assert.ok(sonnenhoehe(LAT, LON, mitternacht) < 0);
  assert.equal(istNacht(LAT, LON, mitternacht), true);
});

test('Winter-Mittag ist hell, aber deutlich tiefer', () => {
  const sommer = sonnenhoehe(LAT, LON, new Date('2026-06-21T11:00:00Z'));
  const winter = sonnenhoehe(LAT, LON, new Date('2026-12-21T11:00:00Z'));
  assert.ok(winter > 0, 'die Sonne steht auch im Winter über dem Horizont');
  assert.ok(sommer - winter > 40, `Sommer ${sommer}, Winter ${winter}`);
  assert.equal(istNacht(LAT, LON, new Date('2026-12-21T11:00:00Z')), false);
});

test('Winterabend ist früher Nacht als Sommerabend', () => {
  // 18:00 UTC = 19:00 MEZ bzw. 20:00 MESZ.
  assert.equal(istNacht(LAT, LON, new Date('2026-12-21T18:00:00Z')), true);
  assert.equal(istNacht(LAT, LON, new Date('2026-06-21T18:00:00Z')), false);
});

test('Sonnenhöhe bleibt im physikalisch möglichen Bereich', () => {
  // Über ein ganzes Jahr in Zwei-Stunden-Schritten: nichts darf ausbrechen.
  for (let tag = 0; tag < 365; tag += 7) {
    for (let stunde = 0; stunde < 24; stunde += 2) {
      const t = new Date(Date.UTC(2026, 0, 1 + tag, stunde));
      const h = sonnenhoehe(LAT, LON, t);
      assert.ok(Number.isFinite(h), `NaN bei ${t.toISOString()}`);
      assert.ok(h >= -90 && h <= 90, `${h} bei ${t.toISOString()}`);
    }
  }
});

test('Polarnacht und Polartag ergeben kein NaN', () => {
  // Der Fall, an dem eine Berechnung über Auf- und Untergangszeiten
  // scheitert: In Tromsø gibt es Tage ohne Sonnenaufgang. Über die
  // Sonnenhöhe ist die Frage trotzdem beantwortbar.
  const TROMSOE_LAT = 69.65;
  const TROMSOE_LON = 18.96;

  // Mittags in der Polarnacht steht die Sonne unter dem Horizont, aber nur
  // knapp: rund -4 Grad. Das ist bürgerliche Dämmerung, nicht Nacht — es ist
  // dort tatsächlich dämmrig hell. Die Schwelle von -6 Grad greift also
  // richtig, indem sie hier NICHT auf Nachtmodus schaltet.
  const polarMittag = new Date('2026-12-21T12:00:00Z');
  const h1 = sonnenhoehe(TROMSOE_LAT, TROMSOE_LON, polarMittag);
  assert.ok(Number.isFinite(h1));
  assert.ok(h1 < 0 && h1 > -6, `erwartet Dämmerung, gemessen ${h1.toFixed(1)} Grad`);
  assert.equal(istNacht(TROMSOE_LAT, TROMSOE_LON, polarMittag), false, 'Dämmerung ist nicht Nacht');

  // Ein paar Stunden später ist es dort echte Nacht.
  const polarNacht = new Date('2026-12-21T22:00:00Z');
  assert.equal(istNacht(TROMSOE_LAT, TROMSOE_LON, polarNacht), true);

  // Mitternachtssonne: Die Sonne steht über dem Horizont, obwohl es
  // Mitternacht ist. Eine Uhrzeit-basierte Prüfung würde hier falsch liegen.
  const mitternachtssonne = new Date('2026-06-21T00:00:00Z');
  const h2 = sonnenhoehe(TROMSOE_LAT, TROMSOE_LON, mitternachtssonne);
  assert.ok(Number.isFinite(h2));
  assert.ok(h2 > 0, `Mitternachtssonne über dem Horizont, gemessen ${h2.toFixed(1)}`);
  assert.equal(istNacht(TROMSOE_LAT, TROMSOE_LON, mitternachtssonne), false);
});

test('Äquator: der Tag ist rund um das Jahr etwa gleich lang', () => {
  const mittagJuni = sonnenhoehe(0, 0, new Date('2026-06-21T12:00:00Z'));
  const mittagDezember = sonnenhoehe(0, 0, new Date('2026-12-21T12:00:00Z'));
  // Beide über dem Horizont, Differenz durch die Achsneigung rund 47 Grad.
  assert.ok(mittagJuni > 60 && mittagDezember > 60);
});

test('Südhalbkugel: Jahreszeiten sind umgekehrt', () => {
  // Sydney, rund 33,9 S. Im Dezember steht die Sonne dort höher als im Juni.
  const dezember = sonnenhoehe(-33.87, 151.21, new Date('2026-12-21T02:00:00Z'));
  const juni = sonnenhoehe(-33.87, 151.21, new Date('2026-06-21T02:00:00Z'));
  assert.ok(dezember > juni, `Dezember ${dezember}, Juni ${juni}`);
});
