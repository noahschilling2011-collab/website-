/**
 * Welche Gebiete abgefragt werden.
 *
 * Deutschland wird bewusst pro Bundesland abgefragt, nicht am Stück:
 * - Overpass läuft bei DE-weiten Queries regelmässig in den Timeout.
 * - Ein fehlgeschlagenes Bundesland lässt sich einzeln nachziehen.
 * - Die Zahlen pro Bundesland fallen als Nebenprodukt ab (Phase-1-DoD).
 */

export type Region = {
  /** ISO-3166-2-Code, z. B. "DE-BW" */
  code: string;
  name: string;
  country: string;
};

export const GERMANY: Region[] = [
  ['DE-BW', 'Baden-Württemberg'],
  ['DE-BY', 'Bayern'],
  ['DE-BE', 'Berlin'],
  ['DE-BB', 'Brandenburg'],
  ['DE-HB', 'Bremen'],
  ['DE-HH', 'Hamburg'],
  ['DE-HE', 'Hessen'],
  ['DE-MV', 'Mecklenburg-Vorpommern'],
  ['DE-NI', 'Niedersachsen'],
  ['DE-NW', 'Nordrhein-Westfalen'],
  ['DE-RP', 'Rheinland-Pfalz'],
  ['DE-SL', 'Saarland'],
  ['DE-SN', 'Sachsen'],
  ['DE-ST', 'Sachsen-Anhalt'],
  ['DE-SH', 'Schleswig-Holstein'],
  ['DE-TH', 'Thüringen'],
].map(([code, name]) => ({ code, name, country: 'DE' }));

/**
 * Optionale Nachbarländer. Werden am Stück abgefragt (kleiner als DE bzw.
 * geringere Blitzerdichte in OSM), Ausnahme Frankreich/Spanien.
 */
export const OPTIONAL_COUNTRIES: Region[] = [
  { code: 'AT', name: 'Österreich', country: 'AT' },
  { code: 'CH', name: 'Schweiz', country: 'CH' },
  { code: 'NL', name: 'Niederlande', country: 'NL' },
  { code: 'FR', name: 'Frankreich', country: 'FR' },
  { code: 'ES', name: 'Spanien', country: 'ES' },
];

export function regionsFor(countries: string[]): Region[] {
  const out: Region[] = [];
  for (const c of countries) {
    if (c === 'DE') out.push(...GERMANY);
    else {
      const found = OPTIONAL_COUNTRIES.find((r) => r.country === c);
      if (!found) throw new Error(`Unbekanntes Land: ${c}`);
      out.push(found);
    }
  }
  return out;
}

/**
 * Overpass-Query für ein Gebiet.
 *
 * Geliefert werden drei Dinge:
 *  1. alle `highway=speed_camera`-Nodes,
 *  2. alle Enforcement-Relationen mit Mitgliederliste (`body`) und
 *     Mittelpunkt (`center`),
 *  3. die als `device` referenzierten Nodes dieser Relationen.
 *
 * Punkt 3 ist der Grund für die zweite Zeile am Ende. Der Mittelpunkt einer
 * Enforcement-Relation ist NICHT der Kamerastandort, sondern der Schwerpunkt
 * aller Mitglieder — inklusive der überwachten Straßenabschnitte. Gemessen an
 * Baden-Württemberg liegt er im Median 12 m daneben, bei 263 von 1565
 * Relationen aber mehr als 30 m, im Extremfall 1394 m. Solche Einträge
 * werden vom Dedupe nicht mehr mit der echten Kamera zusammengefasst und
 * erzeugen Warnungen an Stellen, an denen nichts steht.
 *
 * Mit den device-Nodes sitzt der Eintrag exakt auf der Kamera.
 */
export function queryFor(region: Region, timeoutSec = 900): string {
  const areaSelector = region.code.includes('-')
    ? `area["ISO3166-2"="${region.code}"]`
    : `area["ISO3166-1"="${region.code}"][admin_level=2]`;

  return `[out:json][timeout:${timeoutSec}];
${areaSelector}->.a;
(
  node["highway"="speed_camera"](area.a);
  relation["type"="enforcement"](area.a);
);
out body center;
node(r:"device");
out body;`;
}
