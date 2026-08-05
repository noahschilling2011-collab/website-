/**
 * Entscheidung 5 aus dem Anbindungsdokument: Zeit ist immer ein UTC-Instant
 * plus eine IANA-TZID. Nie ein Offset, nie ein nackter lokaler String.
 *
 * Der ICS-Feed liefert VTIMEZONE-Bloecke, die Calendar API RFC-3339-Strings
 * mit Offset. Beide muessen hier durch, bevor Anwendungscode sie sieht —
 * sonst ist der Providerwechsel eine Datenmigration.
 *
 * Bewusst ohne Zeitzonenbibliothek: Node 22 bringt volles ICU mit, und
 * Intl.DateTimeFormat kennt die IANA-Datenbank inklusive Sommerzeit.
 */

/** Offset der Zone gegenueber UTC, in Minuten, zum gegebenen Instant. */
export function offsetMinuten(instant: Date, zone: string): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const teile = Object.fromEntries(
    formatter.formatToParts(instant).map((p) => [p.type, p.value]),
  );
  // 'hour' kann bei hour12:false als "24" kommen; Date.UTC normalisiert das.
  const alsUtc = Date.UTC(
    Number(teile.year),
    Number(teile.month) - 1,
    Number(teile.day),
    Number(teile.hour),
    Number(teile.minute),
    Number(teile.second),
  );
  return (alsUtc - instant.getTime()) / 60000;
}

/**
 * Wandelt eine lokale Wandzeit in der angegebenen Zone in einen UTC-Instant.
 *
 * Zwei Durchgaenge, weil der Offset selbst vom Ergebnis abhaengt: der erste
 * Versuch schaetzt mit dem Offset zur geratenen Zeit, der zweite korrigiert.
 * Das ist das Standardverfahren und deckt auch die Umstellungstage ab.
 *
 * An der Sprung-vorwaerts-Luecke (in Europe/Berlin 02:00-03:00 im Maerz)
 * existiert die Wandzeit nicht; das Ergebnis rutscht dann auf den ersten
 * gueltigen Instant danach. Fuer Arbeitszeiten am Vormittag irrelevant,
 * aber bewusst dokumentiert statt stillschweigend falsch.
 */
export function lokalZuUtc(
  jahr: number,
  monat: number,
  tag: number,
  stunde: number,
  minute: number,
  zone: string,
): Date {
  const naiv = Date.UTC(jahr, monat - 1, tag, stunde, minute, 0);
  const ersterVersuch = new Date(naiv - offsetMinuten(new Date(naiv), zone) * 60000);
  const korrigiert = new Date(naiv - offsetMinuten(ersterVersuch, zone) * 60000);
  return korrigiert;
}

/** Kalenderdatum in der Zone, als {jahr, monat, tag, wochentag}. */
export function datumInZone(
  instant: Date,
  zone: string,
): { jahr: number; monat: number; tag: number; wochentag: number } {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  });
  const teile = Object.fromEntries(
    formatter.formatToParts(instant).map((p) => [p.type, p.value]),
  );
  const wochentage: Record<string, number> = {
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
    Sun: 7,
  };
  return {
    jahr: Number(teile.year),
    monat: Number(teile.month),
    tag: Number(teile.day),
    wochentag: wochentage[teile.weekday as string] ?? 1,
  };
}

/** "08:30" -> {stunde: 8, minute: 30}. Wirft bei Unsinn statt zu raten. */
export function parseUhrzeit(hhmm: string): { stunde: number; minute: number } {
  const treffer = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (!treffer) throw new Error(`Ungueltige Uhrzeit: ${hhmm}`);
  const stunde = Number(treffer[1]);
  const minute = Number(treffer[2]);
  if (stunde > 23 || minute > 59) throw new Error(`Ungueltige Uhrzeit: ${hhmm}`);
  return { stunde, minute };
}

/** Fuer die Mail an den Dritten: "Dienstag, 18. August, 14:00 Uhr". */
export function formatiereDeutsch(instant: Date, zone: string): string {
  return new Intl.DateTimeFormat('de-DE', {
    timeZone: zone,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    hour: '2-digit',
    minute: '2-digit',
  }).format(instant);
}

export function formatiereKurz(instant: Date, zone: string): string {
  return new Intl.DateTimeFormat('de-DE', {
    timeZone: zone,
    day: 'numeric',
    month: 'long',
  }).format(instant);
}
