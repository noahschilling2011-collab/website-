import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

// Muss VOR den Imports stehen, die konfig lesen.
process.env.MAIL_DOMAIN = 'assistent.test';
process.env.MAIL_ABSENDER = 'Assistenz <assistenz@assistent.test>';
process.env.SECRET_KEY = 'test-schluessel-nur-fuer-tests';
process.env.HALTEZEIT_SEKUNDEN = '60';
delete process.env.ANTHROPIC_API_KEY;
delete process.env.RESEND_API_KEY;
delete process.env.DATABASE_URL;

const tempVerzeichnis = fs.mkdtempSync(path.join(os.tmpdir(), 'terminassistent-'));
process.env.PGLITE_DIR = tempVerzeichnis;

const { db, schema } = await import('../../db/index');
const { setzeAnalysator } = await import('../llm/extraktion');
const { AttrappeVersand, setzeMailVersand } = await import('../mail/ausgang');
const { haltezeitAbbrechen, sendenAusloesen, takt, verarbeiteEingang } = await import(
  './engine.js'
);
const { eq } = await import('drizzle-orm');

const versand = new AttrappeVersand(true);

before(() => {
  setzeMailVersand(versand);
});

after(() => {
  setzeAnalysator(null);
  setzeMailVersand(null);
  fs.rmSync(tempVerzeichnis, { recursive: true, force: true });
});

let laufendeNummer = 0;

async function legeNutzerAn() {
  const d = await db();
  const nummer = ++laufendeNummer;
  const [nutzer] = await d
    .insert(schema.nutzer)
    .values({
      email: `katrin${nummer}@praxis.test`,
      name: 'Katrin Weber',
      handle: `katrin${nummer}`,
      zeitzone: 'Europe/Berlin',
    })
    .returning();

  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer!.id,
    kind: 'attrappe',
    secretRef: 'egal',
    konfig: {},
  });

  return nutzer!;
}

function mime(teile: {
  von: string;
  an: string;
  betreff: string;
  text: string;
  messageId: string;
}): string {
  return [
    `From: ${teile.von}`,
    `To: ${teile.an}`,
    `Subject: ${teile.betreff}`,
    `Message-ID: <${teile.messageId}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    '',
    teile.text,
  ].join('\r\n');
}

// ---------------------------------------------------------------------------

test('Terminanfrage erzeugt Vorschlaege und einen Entwurf, der auf Freigabe wartet', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Frau Berger (Mutter von Jonas)',
    gegenueberName: 'Frau Berger',
    fristDatum: null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'Sabine Berger <berger@example.test>',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Termin Jonas verschieben',
      text: 'Guten Tag, koennen wir den Donnerstag verschieben?',
      messageId: 'a1@example.test',
    }),
  );
  assert.ok('vorgangId' in ergebnis, 'Vorgang muss angelegt werden');
  const vorgangId = ergebnis.vorgangId;

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  assert.equal(vorgang!.art, 'termin');
  assert.equal(vorgang!.titel, 'Termin mit Frau Berger (Mutter von Jonas)');
  // Ein Termin geht NIE ohne Klick raus.
  assert.equal(vorgang!.zustand, 'warte_auf_mich');

  const vorschlaege = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId));
  assert.equal(vorschlaege.length, 3, 'drei Vorschlaege, verteilt auf drei Tage');
  assert.ok(vorschlaege.every((t) => t.platzierungsStatus === 'offen'));
  assert.ok(
    vorschlaege.every((t) => t.uid.endsWith('@assistent.test')),
    'jeder Vorschlag traegt schon eine eigene UID',
  );

  const [entwurf] = await d
    .select()
    .from(schema.ausgang)
    .where(eq(schema.ausgang.vorgangId, vorgangId));
  assert.equal(entwurf!.status, 'entwurf', 'wartet auf Freigabe, ist nicht abgebrochen');
  assert.equal(versand.gesendet.length, 0, 'ohne Klick geht nichts raus');
});

test('Der Takt sendet erst nach Ablauf der Haltezeit', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Pflegedienst Lindenhof',
    gegenueberName: 'Pflegedienst Lindenhof',
    fristDatum: null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'lindenhof@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Terminwunsch',
      text: 'Wann haetten Sie Zeit?',
      messageId: 'b1@example.test',
    }),
  );
  const vorgangId = (ergebnis as { vorgangId: string }).vorgangId;
  const vorher = versand.gesendet.length;

  await sendenAusloesen(vorgangId);

  const [nachKlick] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  assert.equal(nachKlick!.zustand, 'gehalten');

  // Takt zum Jetzt-Zeitpunkt: die Haltezeit laeuft noch.
  await takt(new Date());
  assert.equal(versand.gesendet.length, vorher, 'waehrend der Haltezeit geht nichts raus');

  // Takt nach Ablauf der Haltezeit.
  await takt(new Date(Date.now() + 61_000));
  assert.equal(versand.gesendet.length, vorher + 1, 'danach genau eine Mail');

  const [nachher] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  assert.equal(nachher!.zustand, 'warte_auf_andere');
  assert.ok(nachher!.naechsteErinnerung, 'Nachfassen wird eingeplant');
});

test('Abbruch innerhalb der Haltezeit verhindert den Versand', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Herrn Klein',
    gegenueberName: 'Herr Klein',
    fristDatum: null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'klein@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Termin',
      text: 'Haetten Sie naechste Woche Zeit?',
      messageId: 'c1@example.test',
    }),
  );
  const vorgangId = (ergebnis as { vorgangId: string }).vorgangId;
  const vorher = versand.gesendet.length;

  await sendenAusloesen(vorgangId);
  const abgebrochen = await haltezeitAbbrechen(vorgangId);
  assert.equal(abgebrochen, true);

  await takt(new Date(Date.now() + 61_000));
  assert.equal(versand.gesendet.length, vorher, 'nach Abbruch geht nichts raus');

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  // Zurueck in die Hand der Nutzerin, nicht in den Papierkorb.
  assert.equal(vorgang!.zustand, 'warte_auf_mich');
});

test('Eine Frist wird ohne Klick in den Kalender eingetragen', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'frist',
    titel: 'Verordnung Dr. Kaufmann',
    gegenueberName: 'Dr. Kaufmann',
    fristDatum: '2026-08-18',
    betragEuro: 312,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'praxis@kinderarzt.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Folgeverordnung',
      text: 'Anbei die Verordnung, gueltig bis 18.08.2026.',
      messageId: 'd1@example.test',
    }),
  );
  const vorgangId = (ergebnis as { vorgangId: string }).vorgangId;

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  // Kalendereintraege sind umkehrbar und verlassen das System nicht:
  // kein Klick noetig, direkt erledigt.
  assert.equal(vorgang!.zustand, 'erledigt');
  assert.ok(vorgang!.faelligAm);

  const [termin] = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId));
  assert.equal(termin!.platzierungsStatus, 'published');
  assert.match(termin!.titel, /18\. August/);

  // 9:00 Berliner Sommerzeit = 07:00 UTC.
  assert.equal(termin!.von.toISOString(), '2026-08-18T07:00:00.000Z');
});

test('Geringes Vertrauen fuehrt zur Rueckfrage, nicht zur Handlung', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'frist',
    titel: 'Unklares Dokument',
    gegenueberName: null,
    fristDatum: '2026-09-01',
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'niedrig',
    begruendung: 'Datum koennte auch der 9. Januar sein.',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'unklar@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Dokument',
      text: 'siehe Anhang',
      messageId: 'e1@example.test',
    }),
  );
  const vorgangId = (ergebnis as { vorgangId: string }).vorgangId;

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId));
  assert.equal(vorgang!.zustand, 'warte_auf_mich');

  const termine = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId));
  assert.equal(termine.length, 0, 'bei Unsicherheit wird nichts eingetragen');
});

test('Eine Zusage waehlt den Vorschlag aus und behaelt dessen UID', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Frau Berger',
    gegenueberName: 'Frau Berger',
    fristDatum: null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ersteMail = await verarbeiteEingang(
    mime({
      von: 'berger@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Termin Jonas',
      text: 'Koennen wir verschieben?',
      messageId: 'f1@example.test',
    }),
  );
  const vorgangId = (ersteMail as { vorgangId: string }).vorgangId;

  const vorschlaege = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId));
  const zweiterVorschlag = [...vorschlaege].sort(
    (a, b) => a.von.getTime() - b.von.getTime(),
  )[1]!;

  await sendenAusloesen(vorgangId);
  await takt(new Date(Date.now() + 61_000));

  // Jetzt antwortet Frau Berger und sagt Vorschlag 2 zu.
  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Frau Berger',
    gegenueberName: 'Frau Berger',
    fristDatum: null,
    betragEuro: null,
    istZusage: true,
    zugesagterVorschlag: 2,
    vertrauen: 'hoch',
    begruendung: 'Zusage auf Vorschlag 2',
  }));

  await verarbeiteEingang(
    [
      'From: berger@example.test',
      `To: ${nutzer.handle}@assistent.test`,
      'Subject: Re: Termin Jonas',
      'Message-ID: <f2@example.test>',
      'In-Reply-To: <f1@example.test>',
      'References: <f1@example.test>',
      'Content-Type: text/plain; charset=utf-8',
      '',
      'Der zweite Termin passt.',
    ].join('\r\n'),
  );

  const uebrig = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId));
  assert.equal(uebrig.length, 1, 'die anderen Vorschlaege verfallen');
  assert.equal(
    uebrig[0]!.uid,
    zweiterVorschlag.uid,
    'der bestaetigte Termin behaelt die UID des Vorschlags',
  );
  assert.equal(uebrig[0]!.platzierungsStatus, 'published');
});

test('Alles landet im Protokoll, im Wortlaut', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  setzeAnalysator(async () => ({
    art: 'termin',
    titel: 'Termin mit Herrn Meier',
    gegenueberName: 'Herr Meier',
    fristDatum: null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'hoch',
    begruendung: 'Testanalyse',
  }));

  const ergebnis = await verarbeiteEingang(
    mime({
      von: 'meier@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Termin',
      text: 'Wann passt es?',
      messageId: 'g1@example.test',
    }),
  );
  const vorgangId = (ergebnis as { vorgangId: string }).vorgangId;

  await sendenAusloesen(vorgangId);
  await takt(new Date(Date.now() + 61_000));

  const eintraege = await d
    .select()
    .from(schema.protokoll)
    .where(eq(schema.protokoll.nutzerId, nutzer.id));

  const was = eintraege.map((e) => e.was);
  assert.ok(was.includes('Mail empfangen und analysiert'));
  assert.ok(was.includes('Termine vorgeschlagen'));
  assert.ok(was.includes('Senden ausgeloest'));
  assert.ok(was.includes('Mail gesendet'));

  const gesendet = eintraege.find((e) => e.was === 'Mail gesendet');
  assert.match(gesendet!.details ?? '', /An: meier@example\.test/);
  assert.match(
    gesendet!.details ?? '',
    /Assistenzsystem verfasst/,
    'der volle Wortlaut inklusive Signatur steht im Protokoll',
  );
});
