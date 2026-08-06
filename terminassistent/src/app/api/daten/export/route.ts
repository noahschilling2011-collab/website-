import { exportiereDaten } from '../../../../lib/datenschutz/betroffenenrechte';
import { aktuelleNutzerin } from '../../../../lib/sitzung';

export const dynamic = 'force-dynamic';

/**
 * Auskunft und Datenuebertragbarkeit (Art. 15, Art. 20 DSGVO) als Download.
 *
 * Kein Formular, kein Antrag, keine Bearbeitungsfrist — die Datei entsteht
 * beim Klick. Die Nutzerin ist ueber ihre Sitzung identifiziert, es gibt
 * also nichts nachzuweisen; und weil ausschliesslich das eigene Konto
 * exportiert werden kann, gibt es auch nichts zu verwechseln.
 */
export async function GET(): Promise<Response> {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) return new Response('Nicht angemeldet.', { status: 401 });

  const daten = await exportiereDaten(nutzer.id);
  const tag = new Date().toISOString().slice(0, 10);

  return new Response(JSON.stringify(daten, null, 2), {
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'content-disposition': `attachment; filename="terminassistent-${tag}.json"`,
      // Ein Export mit Gesundheitsdaten hat in keinem Cache etwas verloren.
      'cache-control': 'no-store, private',
    },
  });
}
