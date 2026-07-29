import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  parseDirection,
  parseMaxspeed,
  parseType,
  normalize,
  dedupe,
  buildGrid,
  cellKey,
  neighbourKeys,
  haversine,
  bearingDelta,
  CELL_SIZE,
  type RawCamera,
} from './normalize.js';
import type { OverpassElement } from './overpass.js';

test('parseDirection: Gradzahlen', () => {
  assert.equal(parseDirection({ direction: '135' }), 135);
  assert.equal(parseDirection({ direction: '135.5' }), 135.5);
  assert.equal(parseDirection({ direction: '0' }), 0);
  assert.equal(parseDirection({ direction: '370' }), 10, 'Überlauf wird normalisiert');
  assert.equal(parseDirection({ direction: '-90' }), 270, 'negative Winkel werden normalisiert');
});

test('parseDirection: camera:direction hat Vorrang vor direction', () => {
  assert.equal(parseDirection({ 'camera:direction': '90', direction: '270' }), 90);
});

test('parseDirection: Kompassangaben', () => {
  assert.equal(parseDirection({ direction: 'N' }), 0);
  assert.equal(parseDirection({ direction: 'nw' }), 315);
  assert.equal(parseDirection({ direction: 'SSW' }), 202.5);
});

test('parseDirection: unauflösbare Angaben werden zu null', () => {
  // forward/backward ist relativ zur Way-Richtung — ohne Geometrie nicht
  // auflösbar. Lieber null als eine geratene Zahl: null heisst "warne
  // richtungsunabhängig", eine falsche Zahl heisst "warne nicht".
  assert.equal(parseDirection({ direction: 'forward' }), null);
  assert.equal(parseDirection({ direction: 'backward' }), null);
  assert.equal(parseDirection({ direction: '' }), null);
  assert.equal(parseDirection({}), null);
});

test('parseMaxspeed: km/h und mph', () => {
  assert.equal(parseMaxspeed({ maxspeed: '50' }), 50);
  assert.equal(parseMaxspeed({ maxspeed: '50 km/h' }), 50);
  assert.equal(parseMaxspeed({ maxspeed: '30 mph' }), 48);
  assert.equal(parseMaxspeed({ maxspeed: 'DE:urban' }), null);
  assert.equal(parseMaxspeed({ maxspeed: 'none' }), null);
  assert.equal(parseMaxspeed({ maxspeed: '999' }), null, 'unplausible Werte verwerfen');
  assert.equal(parseMaxspeed({}), null);
});

test('parseType: Blitzertypen', () => {
  assert.equal(parseType({ highway: 'speed_camera' }), 'speed');
  assert.equal(parseType({ enforcement: 'maxspeed' }), 'speed');
  assert.equal(parseType({ enforcement: 'average_speed' }), 'speed');
  assert.equal(parseType({ enforcement: 'traffic_signals' }), 'red_light');
  assert.equal(parseType({ enforcement: 'maxspeed;traffic_signals' }), 'both');
});

test('normalize: Nodes und Relationen mit center', () => {
  const elements: OverpassElement[] = [
    { type: 'node', id: 1, lat: 48.775123456, lon: 9.182987654, tags: { highway: 'speed_camera', maxspeed: '50' } },
    { type: 'relation', id: 2, center: { lat: 48.9, lon: 9.2 }, tags: { type: 'enforcement', enforcement: 'maxspeed' } },
  ];
  const cams = normalize(elements);
  assert.equal(cams.length, 2);
  assert.equal(cams[0].lat, 48.77512, 'auf 5 Nachkommastellen gerundet');
  assert.equal(cams[0].lon, 9.18299);
  assert.equal(cams[0].max, 50);
});

test('normalize: Elemente ohne Koordinate werden übersprungen', () => {
  const cams = normalize([{ type: 'relation', id: 1, tags: { type: 'enforcement', enforcement: 'maxspeed' } }]);
  assert.equal(cams.length, 0);
});

test('normalize: Relation nutzt den device-Node, nicht den Mittelpunkt', () => {
  // Der Mittelpunkt einer Enforcement-Relation ist der Schwerpunkt aller
  // Mitglieder — inklusive der überwachten Straße — und liegt damit oft
  // deutlich neben der Kamera.
  const cams = normalize([
    {
      type: 'relation', id: 1,
      center: { lat: 48.780, lon: 9.180 },
      tags: { type: 'enforcement', enforcement: 'maxspeed', maxspeed: '80' },
      members: [
        { type: 'node', ref: 100, role: 'device' },
        { type: 'way', ref: 200, role: 'from' },
      ],
    },
    { type: 'node', id: 100, lat: 48.775, lon: 9.180, tags: { 'camera:direction': '90' } },
  ]);
  assert.equal(cams.length, 1, 'device-Node ist kein eigener speed_camera-Node');
  assert.equal(cams[0].lat, 48.775, 'Position kommt vom device-Node');
  assert.equal(cams[0].dir, 90, 'Richtung vom Node');
  assert.equal(cams[0].max, 80, 'maxspeed ergänzt aus der Relation');
  assert.equal(cams[0].src, 'relation');
});

test('normalize: Abschnittskontrolle mit zwei Kameras ergibt zwei Einträge', () => {
  const cams = normalize([
    {
      type: 'relation', id: 1,
      center: { lat: 48.78, lon: 9.18 },
      tags: { type: 'enforcement', enforcement: 'average_speed' },
      members: [
        { type: 'node', ref: 100, role: 'device' },
        { type: 'node', ref: 101, role: 'device' },
      ],
    },
    { type: 'node', id: 100, lat: 48.770, lon: 9.18 },
    { type: 'node', id: 101, lat: 48.790, lon: 9.18 },
  ]);
  assert.equal(cams.length, 2, 'an beiden Enden muss gewarnt werden');
  assert.deepEqual(cams.map((c) => c.lat).sort(), [48.77, 48.79]);
});

test('normalize: Mittelpunkt nur als Notbehelf ohne device-Node', () => {
  const cams = normalize([
    {
      type: 'relation', id: 1,
      center: { lat: 48.78, lon: 9.18 },
      tags: { type: 'enforcement', enforcement: 'maxspeed' },
      members: [{ type: 'way', ref: 200, role: 'from' }],
    },
  ]);
  assert.equal(cams.length, 1);
  assert.equal(cams[0].lat, 48.78);
});

test('normalize: device-Node ohne Koordinate fällt auf den Mittelpunkt zurück', () => {
  // Kommt vor, wenn der referenzierte Node nicht mitgeliefert wurde.
  const cams = normalize([
    {
      type: 'relation', id: 1,
      center: { lat: 48.78, lon: 9.18 },
      tags: { type: 'enforcement', enforcement: 'maxspeed' },
      members: [{ type: 'node', ref: 999, role: 'device' }],
    },
  ]);
  assert.equal(cams.length, 1);
  assert.equal(cams[0].lat, 48.78);
});

test('normalize: device-Nodes ohne speed_camera-Tag zählen nicht doppelt', () => {
  // Der device-Node wird von der Query mitgeliefert, ist aber selbst kein
  // highway=speed_camera. Er darf nur über seine Relation eingehen.
  const cams = normalize([
    {
      type: 'relation', id: 1,
      center: { lat: 48.78, lon: 9.18 },
      tags: { type: 'enforcement', enforcement: 'maxspeed' },
      members: [{ type: 'node', ref: 100, role: 'device' }],
    },
    { type: 'node', id: 100, lat: 48.775, lon: 9.18, tags: { man_made: 'surveillance' } },
  ]);
  assert.equal(cams.length, 1);
});

test('normalize: device-Node MIT speed_camera-Tag ergibt zwei deckungsgleiche Einträge', () => {
  // Beide Einträge liegen exakt aufeinander; der Dedupe fasst sie zusammen.
  const elements: OverpassElement[] = [
    {
      type: 'relation', id: 1,
      center: { lat: 48.78, lon: 9.18 },
      tags: { type: 'enforcement', enforcement: 'maxspeed', maxspeed: '80' },
      members: [{ type: 'node', ref: 100, role: 'device' }],
    },
    { type: 'node', id: 100, lat: 48.775, lon: 9.18, tags: { highway: 'speed_camera' } },
  ];
  const cams = normalize(elements);
  assert.equal(cams.length, 2);
  assert.deepEqual([...new Set(cams.map((c) => c.src))].sort(), ['node', 'relation']);
  const merged = dedupe(cams);
  assert.equal(merged.length, 1, 'deckungsgleich -> eine Anlage');
  assert.equal(merged[0].max, 80);
});

test('normalize: irrelevante Enforcement-Relationen werden verworfen', () => {
  // type=enforcement gibt es auch für Maut, Zufahrtsbeschränkungen usw.
  const cams = normalize([
    { type: 'relation', id: 1, center: { lat: 48, lon: 9 }, tags: { type: 'enforcement', enforcement: 'toll' } },
    { type: 'relation', id: 2, center: { lat: 48, lon: 9 }, tags: { type: 'enforcement', enforcement: 'access' } },
  ]);
  assert.equal(cams.length, 0);
});

const cam = (lat: number, lon: number, extra: Partial<RawCamera> = {}): RawCamera => ({
  lat, lon, dir: null, max: null, type: 'speed', src: 'node', ...extra,
});

test('dedupe: Node und Relation derselben Anlage werden zusammengefasst', () => {
  // ~11 m auseinander
  const result = dedupe([
    cam(48.77500, 9.18000, { max: 50, src: 'node' }),
    cam(48.77510, 9.18000, { dir: 90, src: 'relation' }),
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].max, 50, 'Informationen werden zusammengeführt');
  assert.equal(result[0].dir, 90, 'Node+Relation = dieselbe Anlage, Richtung gilt');
});

test('dedupe: Bau-Interna landen nicht im Datensatz', () => {
  const [result] = dedupe([cam(48.775, 9.18)]);
  assert.deepEqual(Object.keys(result).sort(), ['dir', 'lat', 'lon', 'max', 'type']);
});

test('dedupe: Richtung wird bei gleicher Herkunft NICHT übernommen', () => {
  // Zwei getrennt erfasste Nodes am selben Ort, nur einer mit Richtung.
  // Das können zwei Kameras für beide Fahrtrichtungen sein — würde die
  // Richtung übernommen, bliebe eine Fahrtrichtung ungewarnt.
  const result = dedupe([
    cam(48.77500, 9.18000, { src: 'node' }),
    cam(48.77505, 9.18000, { dir: 90, src: 'node' }),
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].dir, null, 'im Zweifel richtungsunabhängig warnen');
});

test('dedupe: ab dem dritten Eintrag am selben Ort keine Richtungsübernahme', () => {
  const result = dedupe([
    cam(48.77500, 9.18000, { src: 'node' }),
    cam(48.77502, 9.18000, { src: 'relation' }),
    cam(48.77504, 9.18000, { dir: 90, src: 'relation' }),
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].dir, null);
});

test('dedupe: verändert die Eingabe nicht', () => {
  // Sonst liefert ein zweiter Lauf über dieselben Objekte — etwa für die
  // Statistik pro Bundesland — andere Zahlen als der erste.
  const input = [
    cam(48.77500, 9.18000, { max: 50, src: 'node' }),
    cam(48.77510, 9.18000, { dir: 90, src: 'relation' }),
  ];
  const before = JSON.stringify(input);
  const first = dedupe(input);
  assert.equal(JSON.stringify(input), before, 'Eingabe muss unverändert bleiben');
  const second = dedupe(input);
  assert.deepEqual(second, first, 'zweiter Lauf muss dasselbe liefern');
});

test('dedupe: getrennte Anlagen bleiben getrennt', () => {
  // ~111 m auseinander, deutlich über dem 30-m-Radius
  const result = dedupe([cam(48.77500, 9.18000), cam(48.77600, 9.18000)]);
  assert.equal(result.length, 2);
});

test('dedupe: Gegenrichtung wird nicht zusammengefasst', () => {
  // Zwei Kameras derselben Anlage für beide Fahrtrichtungen sind zwei
  // Einträge — sonst würde eine Fahrtrichtung nie gewarnt.
  const result = dedupe([
    cam(48.77500, 9.18000, { dir: 90 }),
    cam(48.77505, 9.18000, { dir: 270 }),
  ]);
  assert.equal(result.length, 2);
});

test('dedupe: Typen werden beim Zusammenfassen kombiniert', () => {
  const result = dedupe([
    cam(48.77500, 9.18000, { type: 'speed' }),
    cam(48.77505, 9.18000, { type: 'red_light' }),
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].type, 'both');
});

test('dedupe: funktioniert über Bucket-Grenzen hinweg', () => {
  // Punkte direkt links und rechts einer 0.005°-Bucket-Grenze, ~5 m auseinander.
  const result = dedupe([cam(48.77499, 9.18000), cam(48.77501, 9.18000)]);
  assert.equal(result.length, 1, 'Nachbar-Buckets müssen mitgeprüft werden');
});

test('cellKey: Zellenzuordnung ohne Float-Artefakte', () => {
  assert.equal(cellKey(48.775, 9.8123), '48.75,9.80');
  assert.equal(cellKey(48.75, 9.80), '48.75,9.80', 'Zellgrenze gehört zur Zelle');
  assert.equal(cellKey(48.7999, 9.8499), '48.75,9.80');
  // 48.80/0.05 ergibt in double-Arithmetik 975.9999999999999 — ohne
  // Ganzzahlrechnung landet dieser Punkt eine Zelle zu weit unten.
  assert.equal(cellKey(48.80, 9.85), '48.80,9.85');
  assert.equal(cellKey(48.85, 9.90), '48.85,9.90');
  assert.equal(cellKey(0, 0), '0.00,0.00');
  assert.equal(cellKey(-0.01, -0.01), '-0.05,-0.05', 'negative Koordinaten runden nach unten');
  for (const key of [cellKey(48.775, 9.8), cellKey(52.5, 13.4), cellKey(47.6, 7.6)]) {
    assert.match(key, /^-?\d+\.\d{2},-?\d+\.\d{2}$/, `unsauberer Schlüssel: ${key}`);
  }
});

test('cellKey: jede Zellgrenze in einem realistischen Bereich ist stabil', () => {
  // Systematisch alle Zellgrenzen über Deutschland abklappern: jeder Punkt
  // minimal oberhalb einer Grenze muss in der oberen Zelle landen.
  for (let u = 47_00_000; u <= 55_00_000; u += 5000) {
    const boundary = u / 1e5;
    assert.equal(
      cellKey(boundary, 9.8),
      `${boundary.toFixed(2)},9.80`,
      `Grenze ${boundary} falsch zugeordnet`,
    );
  }
});

test('neighbourKeys: 3x3-Nachbarschaft passt zum Gitter', () => {
  const keys = neighbourKeys(48.77, 9.82);
  assert.equal(keys.length, 9);
  assert.ok(keys.includes(cellKey(48.77, 9.82)), 'eigene Zelle ist enthalten');
  assert.ok(keys.includes('48.70,9.75'));
  assert.ok(keys.includes('48.80,9.85'));
  assert.equal(new Set(keys).size, 9, 'keine Duplikate');
});

test('neighbourKeys: findet eine Kamera in der Nachbarzelle', () => {
  // Fahrer kurz vor der Zellgrenze, Kamera knapp dahinter.
  const grid = buildGrid([cam(48.80001, 9.85001)]);
  const keys = neighbourKeys(48.79995, 9.84995);
  const found = keys.flatMap((k) => grid[k] ?? []);
  assert.equal(found.length, 1, 'Kamera hinter der Zellgrenze muss gefunden werden');
});

test('buildGrid: jede Kamera landet in ihrer Zelle', () => {
  const cams = [cam(48.775, 9.81), cam(48.776, 9.82), cam(48.81, 9.86)];
  const grid = buildGrid(cams);
  assert.equal(Object.keys(grid).length, 2);
  assert.equal(grid['48.75,9.80'].length, 2);
  assert.equal(grid['48.80,9.85'].length, 1);
  for (const [key, list] of Object.entries(grid)) {
    for (const c of list) assert.equal(cellKey(c.lat, c.lon), key);
  }
});

test('buildGrid: Ausgabe ist deterministisch', () => {
  const cams = [cam(48.776, 9.82), cam(48.775, 9.81), cam(48.81, 9.86)];
  const a = JSON.stringify(buildGrid(cams));
  const b = JSON.stringify(buildGrid([...cams].reverse()));
  assert.equal(a, b, 'gleiche Daten müssen byte-identisches JSON ergeben');
});

test('haversine: bekannte Distanzen', () => {
  // 0.01° Breite ≈ 1111 m
  assert.ok(Math.abs(haversine(48.0, 9.0, 48.01, 9.0) - 1111) < 5);
  assert.equal(haversine(48.0, 9.0, 48.0, 9.0), 0);
});

test('bearingDelta: kürzeste Differenz über den Nullpunkt', () => {
  assert.equal(bearingDelta(10, 350), 20);
  assert.equal(bearingDelta(0, 180), 180);
  assert.equal(bearingDelta(90, 90), 0);
  assert.equal(bearingDelta(350, 10), 20);
});

test('CELL_SIZE passt zum Schlüsselformat', () => {
  // cellKey nutzt toFixed(2) — das ist nur exakt, solange CELL_SIZE ein
  // Vielfaches von 0.01 ist.
  assert.equal(Math.round(CELL_SIZE * 100) / 100, CELL_SIZE);
});
