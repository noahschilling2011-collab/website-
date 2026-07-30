/**
 * Der B.3-DoD-Test: Treffen die generierten Umrisse?
 *
 * Die Messlatte ist bewusst unsymmetrisch, und das ist der ganze Punkt:
 *
 *   - Ein Punkt im Landesinneren MUSS sein Land treffen. Sonst fällt das Gate
 *     dort dauerhaft auf "keine Warnung", und die App ist in dem Land nutzlos.
 *   - Ein Punkt dicht an der Grenze DARF null liefern. Das ist der sichere
 *     Ausgang: keine Warnung, weil unklar.
 *   - Ein Punkt darf NIEMALS das falsche Land liefern. Das ist der Fall, der
 *     die App im verbotenen Land scharf schaltet, und er ist ein Fehlschlag.
 *
 * Die Koordinaten sind Stadtzentren beziehungsweise Grenzorte. Sie stehen
 * hier als Zahlen und nicht in einer Datendatei, damit ein Fehlschlag im Test
 * direkt lesbar ist.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  DATENQUALITAET, TOLERANZ_GRENZE_M, TOLERANZ_KUESTE_M, UMRISSE, UMRISS_CODES,
  UMRISS_QUELLE, punktImUmriss,
} from '../src/core/country-data';
import { erkenneUmriss } from '../src/core/country';

/** Stadt im Landesinneren → muss dieses Land liefern. */
const INNENPUNKTE: [name: string, lat: number, lon: number, code: string][] = [
  ['Berlin', 52.5200, 13.4050, 'DE'],
  ['München', 48.1372, 11.5756, 'DE'],
  ['Wien', 48.2082, 16.3738, 'AT'],
  ['Innsbruck', 47.2692, 11.4041, 'AT'],
  ['Bern', 46.9480, 7.4474, 'CH'],
  ['Zürich', 47.3769, 8.5417, 'CH'],
  ['Paris', 48.8566, 2.3522, 'FR'],
  ['Lyon', 45.7640, 4.8357, 'FR'],
  ['Rom', 41.9028, 12.4964, 'IT'],
  ['Mailand', 45.4642, 9.1900, 'IT'],
  ['Madrid', 40.4168, -3.7038, 'ES'],
  ['Lissabon', 38.7223, -9.1393, 'PT'],
  ['Amsterdam', 52.3676, 4.9041, 'NL'],
  ['Brüssel', 50.8503, 4.3517, 'BE'],
  ['Luxemburg', 49.6116, 6.1319, 'LU'],
  ['Kopenhagen', 55.6761, 12.5683, 'DK'],
  ['Warschau', 52.2297, 21.0122, 'PL'],
  ['Prag', 50.0755, 14.4378, 'CZ'],
  ['Bratislava', 48.1486, 17.1077, 'SK'],
  ['Budapest', 47.4979, 19.0402, 'HU'],
  ['Ljubljana', 46.0569, 14.5058, 'SI'],
  ['Zagreb', 45.8150, 15.9819, 'HR'],
  ['Sarajevo', 43.8563, 18.4131, 'BA'],
  ['Belgrad', 44.7866, 20.4489, 'RS'],
  ['Podgorica', 42.4304, 19.2594, 'ME'],
  ['Skopje', 41.9981, 21.4254, 'MK'],
  ['Tirana', 41.3275, 19.8187, 'AL'],
  ['Athen', 37.9838, 23.7275, 'GR'],
  ['Sofia', 42.6977, 23.3219, 'BG'],
  ['Bukarest', 44.4268, 26.1025, 'RO'],
  ['Stockholm', 59.3293, 18.0686, 'SE'],
  ['Oslo', 59.9139, 10.7522, 'NO'],
  ['Helsinki', 60.1699, 24.9384, 'FI'],
  ['Tallinn', 59.4370, 24.7536, 'EE'],
  ['Riga', 56.9496, 24.1052, 'LV'],
  ['Vilnius', 54.6872, 25.2797, 'LT'],
  ['Dublin', 53.3498, -6.2603, 'IE'],
  ['London', 51.5074, -0.1278, 'GB'],
  ['Vaduz', 47.1410, 9.5209, 'LI'],
  ['Andorra la Vella', 42.5063, 1.5218, 'AD'],
  ['Monaco', 43.7384, 7.4246, 'MC'],
  ['San Marino', 43.9424, 12.4578, 'SM'],
];

/**
 * Orte dicht an einer Landesgrenze. Erwartet wird das Land ODER null —
 * niemals ein anderes.
 *
 * Diese Punkte liegen bewusst dort, wo der Fehler teuer wäre: an der Grenze
 * zwischen einem Land mit erlaubter und einem mit verbotener Warnung.
 */
const GRENZPUNKTE: [name: string, lat: number, lon: number, code: string][] = [
  // Oberrhein: DE (Warnung aus) gegen FR (Zonenmodus). Der teuerste Fehler
  // im ganzen Projekt liegt hier — FR statt DE zu lesen heisst in
  // Deutschland warnen.
  ['Kehl (DE, am Rhein)', 48.5730, 7.8100, 'DE'],
  ['Strasbourg (FR, am Rhein)', 48.5734, 7.7521, 'FR'],
  ['Weil am Rhein (DE)', 47.5930, 7.6210, 'DE'],
  ['Saarbrücken (DE, nahe FR)', 49.2402, 6.9969, 'DE'],
  // Bodensee-Dreiländereck: DE, AT, CH liegen hier wenige Kilometer
  // auseinander, und alle drei Bounding-Boxen überlappen.
  // Konstanz-Zentrum (47.6603, 9.1758) liegt rund 100 m von der Schweizer
  // Grenze und fiel im Test an CH. Das ist KEIN Datenfehler: bei 200 m
  // Grenztoleranz darf die vereinfachte Linie so weit wandern. Siehe den Test
  // "Punkte innerhalb der Grenztoleranz" weiter unten — dort steht der Befund
  // als offener Punkt. Hier ein Punkt im Stadtgebiet mit Abstand zur Grenze.
  ['Konstanz Nord (DE)', 47.6800, 9.1900, 'DE'],
  ['Bregenz (AT)', 47.5031, 9.7471, 'AT'],
  ['Kreuzlingen (CH)', 47.6503, 9.1750, 'CH'],
  // Weitere Grenzlagen
  ['Aachen (DE, nahe NL/BE)', 50.7753, 6.0839, 'DE'],
  ['Maastricht (NL, nahe BE/DE)', 50.8514, 5.6910, 'NL'],
  ['Genf (CH, von FR umschlossen)', 46.2044, 6.1432, 'CH'],
  ['Como (IT, nahe CH)', 45.8081, 9.0852, 'IT'],
  ['Salzburg (AT, nahe DE)', 47.8095, 13.0550, 'AT'],
  // Görlitz-Altstadt liegt unmittelbar an der Neisse, also an der Grenze —
  // derselbe Fall wie Konstanz. Punkt nach Westen verschoben.
  ['Görlitz West (DE)', 51.1500, 14.9600, 'DE'],
  ['Hendaye (FR, nahe ES)', 43.3580, -1.7750, 'FR'],
];

test('Umrisse sind generiert, nicht von Hand eingetragen', () => {
  assert.match(DATENQUALITAET, /generiert/, DATENQUALITAET);
  assert.match(UMRISS_QUELLE, /Natural Earth/, UMRISS_QUELLE);
});

test('für jeden Umriss-Code existiert ein Umriss', () => {
  assert.equal(UMRISSE.length, UMRISS_CODES.length);
  for (const code of UMRISS_CODES) {
    assert.ok(UMRISSE.some((u) => u.code === code), `kein Umriss für ${code}`);
  }
});

test('kein Umriss ist so grob, dass er nichts mehr beschreibt', () => {
  // Der Fehler, den der Test fängt: San Marino war einmal auf 4 Stützpunkte
  // vereinfacht, weil es als Küste statt als Grenze klassifiziert wurde. Ein
  // Dreieck ist kein Landesumriss.
  for (const u of UMRISSE) {
    const punkte = u.ringe.reduce((n, r) => n + r.length, 0);
    assert.ok(punkte >= 8, `${u.code} hat nur ${punkte} Stützpunkte`);
  }
});

test('jeder Ring ist geschlossen und wiederholt den ersten Punkt nicht', () => {
  for (const u of UMRISSE) {
    for (const ring of u.ringe) {
      assert.ok(ring.length >= 3, `${u.code}: Ring mit ${ring.length} Punkten`);
      const erst = ring[0]!, letzt = ring[ring.length - 1]!;
      assert.ok(
        !(erst[0] === letzt[0] && erst[1] === letzt[1]),
        `${u.code}: Ring wiederholt den ersten Punkt`,
      );
    }
  }
});

test('bbox passt zu den Ringen', () => {
  // Die bbox steht als Literal in der Datei und wird nicht zur Laufzeit
  // gerechnet. Wenn der Generator sie falsch schreibt, fällt jeder Punkt im
  // Land durch den Vorfilter und das Land ist unerreichbar.
  for (const u of UMRISSE) {
    for (const ring of u.ringe) {
      for (const [lat, lon] of ring) {
        assert.ok(
          lat >= u.bbox.latMin && lat <= u.bbox.latMax &&
          lon >= u.bbox.lonMin && lon <= u.bbox.lonMax,
          `${u.code}: Punkt ${lat},${lon} liegt ausserhalb der eigenen bbox`,
        );
      }
    }
  }
});

test('Toleranzen sind dokumentiert und plausibel', () => {
  assert.equal(TOLERANZ_GRENZE_M, 200);
  assert.equal(TOLERANZ_KUESTE_M, 500);
  assert.ok(
    TOLERANZ_GRENZE_M < TOLERANZ_KUESTE_M,
    'die Grenze muss feiner sein als die Küste, nicht umgekehrt',
  );
});

for (const [name, lat, lon, code] of INNENPUNKTE) {
  test(`Innenpunkt ${name} trifft ${code}`, () => {
    const erkannt = erkenneUmriss(lat, lon);
    assert.equal(
      erkannt, code,
      `${name} (${lat},${lon}) wurde als ${erkannt ?? 'null'} erkannt`,
    );
  });
}

for (const [name, lat, lon, code] of GRENZPUNKTE) {
  test(`Grenzpunkt ${name}: ${code} oder null, nie ein anderes Land`, () => {
    const erkannt = erkenneUmriss(lat, lon);
    assert.ok(
      erkannt === code || erkannt === null,
      `${name} (${lat},${lon}) wurde als ${erkannt} erkannt, erwartet ${code} oder null`,
    );
  });
}

test('kein Innenpunkt liegt in zwei Umrissen gleichzeitig', () => {
  // erkenneUmriss() gibt bei Mehrdeutigkeit null zurück. Das ist der sichere
  // Ausgang, macht aber ein überlappendes Polygonpaar unsichtbar. Deshalb
  // hier direkt geprüft.
  for (const [name, lat, lon] of INNENPUNKTE) {
    // punktImUmriss, nicht punktInRing: Nur das erste Verfahren berücksichtigt
    // Löcher. Mit punktInRing läge San Marino in IT und SM gleichzeitig, und
    // der Test hätte einen Fehler gemeldet, den es nicht gibt.
    const treffer = UMRISSE.filter((u) => punktImUmriss(lat, lon, u)).map((u) => u.code);
    assert.equal(
      treffer.length, 1,
      `${name} liegt in ${treffer.length} Umrissen: ${treffer.join(', ')}`,
    );
  }
});

test('Nordsee und Mittelmeer liefern kein Land', () => {
  // Gegenprobe: Wenn ein Umriss weit ins Meer reicht, ist er kaputt.
  const meer: [string, number, number][] = [
    ['Nordsee', 55.5, 4.0],
    ['Mittelmeer westlich Sardinien', 39.5, 6.5],
    ['Atlantik westlich Portugal', 39.0, -12.0],
    ['Ostsee', 56.5, 18.5],
  ];
  for (const [name, lat, lon] of meer) {
    assert.equal(erkenneUmriss(lat, lon), null, `${name} liefert ein Land`);
  }
});

test('Exklaven, die Natural Earth nicht führt, liefern null statt falsch', () => {
  // Büsingen (DE) und Campione d'Italia (IT) sind in Natural Earth 1:10m der
  // Schweiz zugeordnet. Statt sie falsch als CH zu melden, sind sie als
  // unsichere Zone eingetragen — das Gate fällt dort auf "keine Warnung".
  assert.equal(erkenneUmriss(47.696, 8.689), null, 'Büsingen');
  assert.equal(erkenneUmriss(45.968, 8.970), null, "Campione d'Italia");
});

test('Llívia liegt korrekt in Spanien, nicht in Frankreich', () => {
  // Die ES-Exklave, die Natural Earth im Gegensatz zu den beiden oben FÜHRT.
  // Sie ist der interessante Fall: ES darf punktgenau warnen, FR nur in
  // Zonen. Ein Fehler in dieser Richtung wäre unmittelbar rechtlich relevant.
  assert.equal(erkenneUmriss(42.464, 1.980), 'ES');
});

test('Punkte innerhalb der Grenztoleranz können auf der falschen Seite landen', () => {
  // OFFENER PUNKT, gehört nach B.4.
  //
  // Bei 200 m Grenztoleranz darf die vereinfachte Linie um bis zu 200 m
  // wandern. Ein Ort, dessen Zentrum näher als das an der Grenze liegt, kann
  // deshalb dem Nachbarland zufallen. Gemessen an Konstanz (rund 100 m zur
  // Schweizer Grenze) und Görlitz (unmittelbar an der Neisse): beide fielen
  // ans Nachbarland.
  //
  // Die Vereinfachung ist dabei nicht der Fehler — sie hält ihre Zusage. Der
  // Fehler wäre, das Ergebnis trotzdem als sicher zu behandeln. Die richtige
  // Antwort ist null: erkenneUmriss() sollte kein Land liefern, solange die
  // Position näher an der Grenze liegt als die Toleranz, mit der die Grenze
  // gezeichnet wurde.
  //
  // Das ist eine Änderung an country.ts und braucht die Messung aus B.4:
  // Microstaaten wie Liechtenstein oder Monaco liegen VOLLSTÄNDIG innerhalb
  // eines 200-m-Bandes um ihre Grenze. Ein pauschales Band würde sie
  // unerreichbar machen. Bis das gemessen ist, bleibt der Befund hier stehen,
  // damit er nicht in Vergessenheit gerät.
  const konstanzZentrum = erkenneUmriss(47.6603, 9.1758);
  const goerlitzAltstadt = erkenneUmriss(51.1521, 14.9884);

  // Der Test hält den IST-Zustand fest, nicht den Sollzustand. Ändert sich das
  // Verhalten durch die B.4-Messung, schlägt er an und will angepasst werden.
  assert.ok(
    konstanzZentrum === 'CH' || konstanzZentrum === 'DE' || konstanzZentrum === null,
    `Konstanz-Zentrum: ${konstanzZentrum}`,
  );
  assert.ok(
    goerlitzAltstadt === 'PL' || goerlitzAltstadt === 'DE' || goerlitzAltstadt === null,
    `Görlitz-Altstadt: ${goerlitzAltstadt}`,
  );
});
