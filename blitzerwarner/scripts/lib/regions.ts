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


/**
 * Grosse Länder werden pro Subregion abgefragt.
 *
 * Nicht aus Ordnungsliebe: Eine landesweite Overpass-Query läuft bei diesen
 * Ländern zuverlässig in den Timeout. Deutschland zeigt es — pro Bundesland
 * geht es durch, am Stück nicht. Nebeneffekt: Ein einzelnes fehlgeschlagenes
 * Gebiet lässt sich nachziehen, ohne alles neu zu holen.
 *
 * Die Codes sind ISO 3166-2. Ob ein Gebiet über ISO3166-2 oder ISO3166-1
 * abgefragt wird, entscheidet queryFor() am Bindestrich im Code.
 */
const SUBREGIONEN: Record<string, [code: string, name: string][]> = {
  IT: [
    ['IT-21', 'Piemont'], ['IT-23', 'Aostatal'], ['IT-25', 'Lombardei'],
    ['IT-32', 'Trentino-Südtirol'], ['IT-34', 'Venetien'],
    ['IT-36', 'Friaul-Julisch Venetien'], ['IT-42', 'Ligurien'],
    ['IT-45', 'Emilia-Romagna'], ['IT-52', 'Toskana'], ['IT-55', 'Umbrien'],
    ['IT-57', 'Marken'], ['IT-62', 'Latium'], ['IT-65', 'Abruzzen'],
    ['IT-67', 'Molise'], ['IT-72', 'Kampanien'], ['IT-75', 'Apulien'],
    ['IT-77', 'Basilikata'], ['IT-78', 'Kalabrien'], ['IT-82', 'Sizilien'],
    ['IT-88', 'Sardinien'],
  ],
  FR: [
    ['FR-ARA', 'Auvergne-Rhône-Alpes'], ['FR-BFC', 'Bourgogne-Franche-Comté'],
    ['FR-BRE', 'Bretagne'], ['FR-CVL', 'Centre-Val de Loire'],
    ['FR-COR', 'Korsika'], ['FR-GES', 'Grand Est'],
    ['FR-HDF', 'Hauts-de-France'], ['FR-IDF', 'Île-de-France'],
    ['FR-NOR', 'Normandie'], ['FR-NAQ', 'Nouvelle-Aquitaine'],
    ['FR-OCC', 'Okzitanien'], ['FR-PDL', 'Pays de la Loire'],
    ['FR-PAC', "Provence-Alpes-Côte d'Azur"],
  ],
  GB: [
    ['GB-ENG', 'England'], ['GB-SCT', 'Schottland'],
    ['GB-WLS', 'Wales'], ['GB-NIR', 'Nordirland'],
  ],
  ES: [
    ['ES-AN', 'Andalusien'], ['ES-AR', 'Aragonien'], ['ES-AS', 'Asturien'],
    ['ES-CN', 'Kanaren'], ['ES-CB', 'Kantabrien'], ['ES-CL', 'Kastilien und León'],
    ['ES-CM', 'Kastilien-La Mancha'], ['ES-CT', 'Katalonien'],
    ['ES-EX', 'Extremadura'], ['ES-GA', 'Galicien'], ['ES-IB', 'Balearen'],
    ['ES-RI', 'La Rioja'], ['ES-MD', 'Madrid'], ['ES-MC', 'Murcia'],
    ['ES-NC', 'Navarra'], ['ES-PV', 'Baskenland'], ['ES-VC', 'Valencia'],
  ],
  PL: [
    ['PL-02', 'Niederschlesien'], ['PL-04', 'Kujawien-Pommern'],
    ['PL-06', 'Lublin'], ['PL-08', 'Lebus'], ['PL-10', 'Łódź'],
    ['PL-12', 'Kleinpolen'], ['PL-14', 'Masowien'], ['PL-16', 'Oppeln'],
    ['PL-18', 'Karpatenvorland'], ['PL-20', 'Podlachien'], ['PL-22', 'Pommern'],
    ['PL-24', 'Schlesien'], ['PL-26', 'Heiligkreuz'], ['PL-28', 'Ermland-Masuren'],
    ['PL-30', 'Grosspolen'], ['PL-32', 'Westpommern'],
  ],
};

/**
 * Länder, die am Stück abgefragt werden. Klein genug für eine Query.
 *
 * RUSSLAND UND BELARUS FEHLEN ABSICHTLICH. Russland allein hat über 18.000
 * erfasste Anlagen, überwiegend Rotlicht, und würde den Datensatz für ein
 * Gebiet verdoppeln, in das aus diesem Nutzerkreis niemand fährt.
 */
const GANZE_LAENDER: [code: string, name: string][] = [
  ['AT', 'Österreich'], ['CH', 'Schweiz'], ['NL', 'Niederlande'],
  ['BE', 'Belgien'], ['LU', 'Luxemburg'], ['DK', 'Dänemark'],
  ['CZ', 'Tschechien'], ['SK', 'Slowakei'], ['HU', 'Ungarn'],
  ['SI', 'Slowenien'], ['HR', 'Kroatien'], ['BA', 'Bosnien und Herzegowina'],
  ['RS', 'Serbien'], ['ME', 'Montenegro'], ['MK', 'Nordmazedonien'],
  ['AL', 'Albanien'], ['GR', 'Griechenland'], ['BG', 'Bulgarien'],
  ['RO', 'Rumänien'], ['PT', 'Portugal'], ['SE', 'Schweden'],
  ['NO', 'Norwegen'], ['FI', 'Finnland'], ['EE', 'Estland'],
  ['LV', 'Lettland'], ['LT', 'Litauen'], ['IE', 'Irland'],
  ['IS', 'Island'], ['LI', 'Liechtenstein'], ['AD', 'Andorra'],
  ['MC', 'Monaco'], ['SM', 'San Marino'], ['MT', 'Malta'],
  ['CY', 'Zypern'], ['MD', 'Moldau'], ['UA', 'Ukraine'],
  ['XK', 'Kosovo'], ['TR', 'Türkei'],
];

/**
 * Alle Gebiete für Europa.
 *
 * WICHTIG: Die Ländermenge des DATENSATZES ist unabhängig von der des GATES.
 * Kartieren ist überall legal, warnen nicht. Ein Land kommt in den Datensatz,
 * weil man dort fahren kann; ob dort gewarnt wird, entscheidet allein die
 * Tabelle in app/src/config.ts. Diese Trennung ist Absicht — sie erlaubt, ein
 * Land aufzunehmen, dessen Rechtslage noch ungeklärt ist, ohne dort zu warnen.
 */
export const EUROPA: Region[] = [
  ...GERMANY,
  ...Object.entries(SUBREGIONEN).flatMap(([land, gebiete]) =>
    gebiete.map(([code, name]) => ({ code, name, country: land })),
  ),
  ...GANZE_LAENDER.map(([code, name]) => ({ code, name, country: code })),
];

export function regionsFor(countries: string[]): Region[] {
  const out: Region[] = [];
  for (const c of countries) {
    if (c === 'EU' || c === 'EUROPA') { out.push(...EUROPA); continue; }
    if (c === 'DE') { out.push(...GERMANY); continue; }

    const subregionen = SUBREGIONEN[c];
    if (subregionen) {
      out.push(...subregionen.map(([code, name]) => ({ code, name, country: c })));
      continue;
    }

    const ganz = GANZE_LAENDER.find(([code]) => code === c);
    if (ganz) { out.push({ code: ganz[0], name: ganz[1], country: c }); continue; }

    const alt = OPTIONAL_COUNTRIES.find((r) => r.country === c);
    if (!alt) throw new Error(`Unbekanntes Land: ${c}`);
    out.push(alt);
  }
  // Doppelte entfernen: EUROPA enthält Gebiete, die einzeln auch genannt
  // werden können. Zweimal abfragen wäre Verschwendung fremder Rechenzeit.
  const gesehen = new Set<string>();
  return out.filter((r) => (gesehen.has(r.code) ? false : (gesehen.add(r.code), true)));
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
