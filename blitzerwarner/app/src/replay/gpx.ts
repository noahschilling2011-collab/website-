/**
 * Minimaler GPX-Leser und -Schreiber.
 *
 * Absichtlich ohne XML-Bibliothek: Gebraucht wird genau ein Elementtyp
 * (`trkpt`), und eine Abhängigkeit, die im App-Bundle landet, ist das nicht
 * wert. Der Leser ist bewusst nachsichtig — GPX-Dateien aus der Praxis
 * enthalten alles Mögliche an Zusatzelementen, die uns nicht interessieren.
 */
import type { Fix } from '../types';
import { bearing, haversine } from '../core/geo';

export type GpxPoint = {
  lat: number;
  lon: number;
  /** ms seit Epoch, falls im Track vorhanden. */
  t?: number;
  /** m/s, falls vorhanden (Garmin/Strava-Erweiterung). */
  speed?: number;
  /** Grad, falls vorhanden. */
  course?: number;
};

const TRKPT = /<trkpt\b[^>]*\blat\s*=\s*"([-\d.]+)"[^>]*\blon\s*=\s*"([-\d.]+)"[^>]*>([\s\S]*?)<\/trkpt>|<trkpt\b[^>]*\blat\s*=\s*"([-\d.]+)"[^>]*\blon\s*=\s*"([-\d.]+)"[^>]*\/>/g;

function tagValue(block: string, tag: string): string | null {
  const m = block.match(new RegExp(`<${tag}[^>]*>([^<]*)</${tag}>`));
  return m?.[1]?.trim() ?? null;
}

/** GPX-Text in Punkte zerlegen. */
export function parseGpx(xml: string): GpxPoint[] {
  const punkte: GpxPoint[] = [];

  for (const m of xml.matchAll(TRKPT)) {
    // Zwei Alternativen im Muster: mit Inhalt und selbstschliessend.
    const lat = Number(m[1] ?? m[4]);
    const lon = Number(m[2] ?? m[5]);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;

    const block = m[3] ?? '';
    const punkt: GpxPoint = { lat, lon };

    const zeit = tagValue(block, 'time');
    if (zeit) {
      const ms = Date.parse(zeit);
      if (Number.isFinite(ms)) punkt.t = ms;
    }

    // speed/course stehen je nach Erzeuger direkt oder in <extensions>.
    const speed = tagValue(block, 'speed');
    if (speed != null && speed !== '') {
      const v = Number(speed);
      if (Number.isFinite(v)) punkt.speed = v;
    }
    const course = tagValue(block, 'course') ?? tagValue(block, 'heading');
    if (course != null && course !== '') {
      const c = Number(course);
      if (Number.isFinite(c)) punkt.course = c;
    }

    punkte.push(punkt);
  }

  return punkte;
}

/**
 * Punkte in Fixes überführen und fehlende Kurs- und
 * Geschwindigkeitsangaben aus dem Verlauf ergänzen.
 *
 * Aufgezeichnete Tracks tragen oft nur Position und Zeit. Der Kurs des
 * ersten Punktes ist dabei prinzipiell unbestimmt — es gibt keinen
 * Vorgänger. Er wird deshalb aus dem Nachfolger genommen; bei einem
 * einzelnen Punkt bleibt er null, was die Warnlogik korrekt als
 * "Richtungsfilter aus" behandelt.
 */
export function toFixes(punkte: GpxPoint[], startzeit = 0, intervalMs = 1000): Fix[] {
  const fixes: Fix[] = punkte.map((p, i) => ({
    lat: p.lat,
    lon: p.lon,
    course: p.course ?? null,
    speed: p.speed ?? null,
    accuracy: 5,
    t: p.t ?? startzeit + i * intervalMs,
  }));

  for (let i = 0; i < fixes.length; i++) {
    const hier = fixes[i]!;

    if (hier.course == null) {
      const naechster = fixes[i + 1];
      const vorheriger = fixes[i - 1];
      if (naechster) {
        hier.course = bearing(hier.lat, hier.lon, naechster.lat, naechster.lon);
      } else if (vorheriger) {
        hier.course = bearing(vorheriger.lat, vorheriger.lon, hier.lat, hier.lon);
      }
    }

    if (hier.speed == null) {
      const vorheriger = fixes[i - 1];
      const bezug = vorheriger ?? fixes[i + 1];
      if (bezug) {
        const dt = Math.abs(hier.t - bezug.t) / 1000;
        const ds = haversine(hier.lat, hier.lon, bezug.lat, bezug.lon);
        hier.speed = dt > 0 ? ds / dt : 0;
      }
    }
  }

  return fixes;
}

/** Punkte als GPX schreiben — für erzeugte Fixtures. */
export function writeGpx(punkte: GpxPoint[], beschreibung: string): string {
  const zeilen = punkte.map((p) => {
    const teile = [`      <trkpt lat="${p.lat.toFixed(6)}" lon="${p.lon.toFixed(6)}">`];
    if (p.t != null) teile.push(`        <time>${new Date(p.t).toISOString()}</time>`);
    if (p.speed != null) teile.push(`        <speed>${p.speed.toFixed(2)}</speed>`);
    if (p.course != null) teile.push(`        <course>${p.course.toFixed(1)}</course>`);
    teile.push('      </trkpt>');
    return teile.join('\n');
  });

  return `<?xml version="1.0" encoding="UTF-8"?>
<!--
${beschreibung}

Synthetisch erzeugt von src/replay/make-fixtures.ts — nicht von Hand ändern,
sondern den Generator anpassen und neu erzeugen.
-->
<gpx version="1.1" creator="static-blitzerwarner-fixtures">
  <trk>
    <trkseg>
${zeilen.join('\n')}
    </trkseg>
  </trk>
</gpx>
`;
}
