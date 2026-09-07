import { eq } from 'drizzle-orm';
import { db, schema } from '../src/db/index';
import { verschluessle } from '../src/lib/krypto';
import { setzeAnalysator } from '../src/lib/llm/extraktion';
import { verarbeiteEingang } from '../src/lib/vorgang/engine';

/**
 * Legt Katrin aus Abschnitt 2 des Entwurfs an und spielt ihren Dienstag
 * ein: die verfallene Verordnung und die Mutter, die zum vierten Mal
 * wegen eines Verlegungstermins schreibt.
 *
 * Aufruf: npm run seed
 */

process.env.MAIL_DOMAIN ??= 'assistent.localhost';
process.env.SECRET_KEY ??= 'entwicklungsschluessel-nicht-produktiv';

const EMAIL = 'katrin@praxis-weber.example';
const HANDLE = 'katrin';

const d = await db();

let [nutzer] = await d.select().from(schema.nutzer).where(eq(schema.nutzer.email, EMAIL));
if (!nutzer) {
  [nutzer] = await d
    .insert(schema.nutzer)
    .values({
      email: EMAIL,
      name: 'Katrin Weber',
      handle: HANDLE,
      zeitzone: 'Europe/Berlin',
      // Montag bis Donnerstag 8-17 Uhr, Freitag Abrechnung.
      arbeitszeiten: {
        '1': [{ von: '08:00', bis: '17:00' }],
        '2': [{ von: '08:00', bis: '17:00' }],
        '3': [{ von: '08:00', bis: '17:00' }],
        '4': [{ von: '08:00', bis: '17:00' }],
      },
    })
    .returning();
  console.log(`Nutzerin angelegt: ${EMAIL}`);
} else {
  console.log(`Nutzerin existiert bereits: ${EMAIL}`);
}

const vorhandene = await d
  .select()
  .from(schema.kalenderVerbindungen)
  .where(eq(schema.kalenderVerbindungen.nutzerId, nutzer!.id));

if (vorhandene.length === 0) {
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer!.id,
    kind: 'attrappe',
    secretRef: verschluessle('attrappe'),
    konfig: {},
  });
  console.log('Demo-Kalender verbunden (Attrappe).');
}

// Ohne ANTHROPIC_API_KEY liefert die echte Analyse absichtlich immer
// "vertrauen: niedrig". Fuer die Demo setzen wir plausible Ergebnisse,
// damit der ganze Ablauf sichtbar wird statt nur die Rueckfrage.
if (!process.env.ANTHROPIC_API_KEY) {
  setzeAnalysator(async (mail) => {
    const istFrist = /verordnung/i.test(mail.betreff + mail.text);
    return {
      art: istFrist ? 'frist' : 'termin',
      titel: istFrist
        ? 'Verordnung Dr. Kaufmann'
        : `Termin mit ${mail.vonName ?? mail.von}`,
      gegenueberName: mail.vonName,
      fristDatum: istFrist ? '2026-08-18' : null,
      betragEuro: istFrist ? 312 : null,
      istZusage: false,
      zugesagterVorschlag: null,
      vertrauen: 'hoch',
      begruendung: 'Seed-Daten fuer die Demo.',
    };
  });
  console.log('Hinweis: Analyse wird fuer die Demo simuliert (kein ANTHROPIC_API_KEY).');
}

const mails = [
  {
    von: 'Sabine Berger <s.berger@example.test>',
    betreff: 'Termin Jonas am Donnerstag',
    text: 'Guten Tag Frau Weber,\n\nleider muss ich den Termin von Jonas am Donnerstag absagen. Haetten Sie in den naechsten zwei Wochen noch etwas frei? Am besten vormittags.\n\nViele Gruesse\nSabine Berger',
  },
  {
    von: 'Praxis Dr. Kaufmann <praxis@kaufmann.test>',
    betreff: 'Folgeverordnung Jonas Berger',
    text: 'Guten Tag,\n\nanbei die Folgeverordnung fuer Jonas Berger. Die Behandlung muss bis zum 18.08.2026 begonnen werden, Betrag 312,00 EUR.\n\nMit freundlichen Gruessen\nPraxis Dr. Kaufmann',
  },
  {
    von: 'Pflegedienst Lindenhof <team@lindenhof.test>',
    betreff: 'Hausbesuch Frau Ostermann',
    text: 'Guten Tag,\n\nkoennten Sie den Hausbesuch bei Frau Ostermann in den naechsten zwei Wochen einplanen?\n\nBeste Gruesse\nPflegedienst Lindenhof',
  },
];

for (const [index, mail] of mails.entries()) {
  const roh = [
    `From: ${mail.von}`,
    `To: ${HANDLE}@${process.env.MAIL_DOMAIN}`,
    `Subject: ${mail.betreff}`,
    `Message-ID: <seed-${index}-${Date.now()}@example.test>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    '',
    mail.text,
  ].join('\r\n');

  const ergebnis = await verarbeiteEingang(roh);
  console.log(
    'abgelehnt' in ergebnis
      ? `  abgelehnt: ${ergebnis.abgelehnt}`
      : `  Vorgang angelegt: ${mail.betreff}`,
  );
}

console.log('');
console.log('Fertig. Jetzt `npm run dev` starten und auf http://localhost:3000 gehen.');
console.log(`Anmelden mit: ${EMAIL}`);
console.log('Der Anmeldecode erscheint auf dieser Konsole, weil nichts versendet wird.');
process.exit(0);
