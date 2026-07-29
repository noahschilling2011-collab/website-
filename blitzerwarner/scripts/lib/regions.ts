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
 * `out center tags` liefert für Relationen den Mittelpunkt und für Nodes
 * die Koordinate — beides, was die Normalisierung braucht.
 */
export function queryFor(region: Region, timeoutSec = 600): string {
  const areaSelector = region.code.includes('-')
    ? `area["ISO3166-2"="${region.code}"]`
    : `area["ISO3166-1"="${region.code}"][admin_level=2]`;

  return `[out:json][timeout:${timeoutSec}];
${areaSelector}->.a;
(
  node["highway"="speed_camera"](area.a);
  relation["type"="enforcement"](area.a);
);
out center tags;`;
}
