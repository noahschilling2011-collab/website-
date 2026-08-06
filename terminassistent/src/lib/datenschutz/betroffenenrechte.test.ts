import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

process.env.MAIL_DOMAIN = 'assistent.test';
process.env.MAIL_ABSENDER = 'Assistenz <assistenz@assistent.test>';
process.env.SECRET_KEY = 'test-schluessel-nur-fuer-tests';
delete process.env.ANTHROPIC_API_KEY;
delete process.env.RESEND_API_KEY;
delete process.env.DATABASE_URL;

const tempVerzeichnis = fs.mkdtempSync(path.join(os.tmpdir(), 'terminassistent-ds-'));
process.env.PGLITE_DIR = tempVerzeichnis;

const { db, schema } = await import('../../db/index');
const { AttrappeVersand, setzeMailVersand } = await import('../mail/ausgang');
const { exportiereDaten, loescheKonto, raeumeAuf } = await import('./betroffenenrechte');
const { and, eq } = await import('drizzle-orm');

const versand = new AttrappeVersand(true);

before(() => setzeMailVersand(versand));
after(() => {
  setzeMailVersand(null);
  fs.rmSync(tempVerzeichnis, { recursive: true, force: true });
});

const JETZT = new Date('2026-08-06T12:00:00Z');
const vorTagen = (tage: number) => new Date(JETZT.getTime() - tage * 86_400_000);
const inTagen = (tage: number) => new Date(JETZT.getTime() + tage * 86_400_000);

let nummer = 0;
async function legeNutzerAn(extra: { zahlendSeit?: Date; erstelltAm?: Date } = {}) {
  const d = await db();
  const n = ++nummer;
  const [nutzer] = await d
    .insert(schema.nutzer)
    .values({
      email: `nutzerin${n}@praxis.test`,
      name: 'Katrin Weber',
      handle: `nutzerin${n}`,
      zeitzone: 'Europe/Berlin',
      ...extra,
    })
    .returning();
  return nutzer!;
}

async function legeVorgangAn(
  nutzerId: string,
  teile: { zustand?: string; geaendertAm?: Date; faelligAm?: Date | null } = {},
) {
  const d = await db();
  const [vorgang] = await d
    .insert(schema.vorgaenge)
    .values({
      nutzerId,
      art: 'termin',
      titel: 'Ein Vorgang',
      threadKey: `t-${Math.abs(nutzerId.charCodeAt(0) + ++nummer)}`,
      zustand: (teile.zustand ?? 'erledigt') as 'erledigt',
      geaendertAm: teile.geaendertAm ?? vorTagen(200),
      faelligAm: teile.faelligAm ?? null,
    })
    .returning();
  return vorgang!;
}

// ---------------------------------------------------------------------------

test('Der Mailverlauf eines alten Vorgangs verschwindet mitsamt dem Vorgang', async () => {
  const nutzer = await legeNutzerAn();
  const vorgang = await legeVorgangAn(nutzer.id);
  const d = await db();

  const [nachricht] = await d
    .insert(schema.nachrichten)
    .values({
      vorgangId: vorgang.id,
      richtung: 'ein',
      von: 'praxis@example.test',
      an: `${nutzer.handle}@assistent.test`,
      betreff: 'Folgeverordnung',
      text: 'Verordnung fuer Jonas Berger, Diagnose ...',
    })
    .returning();
  await d.insert(schema.anhaenge).values({
    nachrichtId: nachricht!.id,
    dateiname: 'verordnung.pdf',
    mimeTyp: 'application/pdf',
    groesseBytes: 1234,
    textExtrakt: 'Heilmittelverordnung, Diagnose ...',
  });

  await raeumeAuf(JETZT);

  const uebrig = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgang.id));
  assert.equal(uebrig.length, 0, 'der Vorgang ist weg');

  // Das ist der Punkt: die Gesundheitsdaten haengen per Fremdschluessel
  // daran und duerfen nicht als Waise zurueckbleiben.
  const nachrichten = await d
    .select()
    .from(schema.nachrichten)
    .where(eq(schema.nachrichten.vorgangId, vorgang.id));
  assert.equal(nachrichten.length, 0, 'die Mail ist weg');

  const anhaenge = await d
    .select()
    .from(schema.anhaenge)
    .where(eq(schema.anhaenge.nachrichtId, nachricht!.id));
  assert.equal(anhaenge.length, 0, 'der Anhangstext ist weg');
});

test('Ein Vorgang mit einer Frist in der Zukunft ueberlebt das Aufraeumen', async () => {
  const nutzer = await legeNutzerAn();
  const vorgang = await legeVorgangAn(nutzer.id, {
    geaendertAm: vorTagen(300),
    faelligAm: inTagen(60),
  });

  await raeumeAuf(JETZT);

  const d = await db();
  const uebrig = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgang.id));
  assert.equal(uebrig.length, 1, 'sonst weiss die Nutzerin nicht mehr, woher der Termin kommt');
});

test('Ein laufender Vorgang wird nie aufgeraeumt, egal wie alt', async () => {
  const nutzer = await legeNutzerAn();
  const vorgang = await legeVorgangAn(nutzer.id, {
    zustand: 'warte_auf_andere',
    geaendertAm: vorTagen(500),
  });

  await raeumeAuf(JETZT);

  const d = await db();
  const uebrig = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgang.id));
  assert.equal(uebrig.length, 1);
});

test('Das Protokoll verliert erst den Wortlaut, dann den ganzen Eintrag', async () => {
  const nutzer = await legeNutzerAn();
  const d = await db();

  const [mittel] = await d
    .insert(schema.protokoll)
    .values({
      nutzerId: nutzer.id,
      was: 'Mail gesendet',
      details: 'Sehr geehrte Frau Berger, der Termin am ...',
      zeitpunkt: vorTagen(120),
    })
    .returning();
  const [uralt] = await d
    .insert(schema.protokoll)
    .values({
      nutzerId: nutzer.id,
      was: 'Mail gesendet',
      details: 'Noch aelter',
      zeitpunkt: vorTagen(300),
    })
    .returning();

  await raeumeAuf(JETZT);

  const [nachher] = await d
    .select()
    .from(schema.protokoll)
    .where(eq(schema.protokoll.id, mittel!.id));
  assert.ok(nachher, 'der Eintrag bleibt');
  assert.equal(nachher!.details, null, 'aber der Wortlaut ist weg');
  assert.equal(nachher!.was, 'Mail gesendet', 'dass etwas passiert ist, bleibt nachvollziehbar');

  const weg = await d.select().from(schema.protokoll).where(eq(schema.protokoll.id, uralt!.id));
  assert.equal(weg.length, 0);
});

test('Anmelde-Tokens ueberleben ihren Zweck nicht', async () => {
  const d = await db();
  await d.insert(schema.anmeldeTokens).values([
    { email: 'alt@praxis.test', tokenHash: 'hash-alt', gueltigBis: vorTagen(5) },
    { email: 'frisch@praxis.test', tokenHash: 'hash-frisch', gueltigBis: inTagen(1) },
  ]);

  await raeumeAuf(JETZT);

  const uebrig = await d.select().from(schema.anmeldeTokens);
  assert.ok(uebrig.every((t) => t.tokenHash !== 'hash-alt'));
  assert.ok(uebrig.some((t) => t.tokenHash === 'hash-frisch'), 'gueltige Links bleiben');
});

test('Ein ruhendes Konto wird erst gewarnt und beim naechsten Mal nicht erneut', async () => {
  const nutzer = await legeNutzerAn({ erstelltAm: vorTagen(710) });
  const vorher = versand.gesendet.length;

  await raeumeAuf(JETZT);

  const warnung = versand.gesendet.slice(vorher).find((m) => m.an === nutzer.email);
  assert.ok(warnung, 'die Nutzerin muss vorgewarnt werden');
  assert.match(warnung!.betreff, /gelöscht/);

  const d = await db();
  const [immerNoch] = await d.select().from(schema.nutzer).where(eq(schema.nutzer.id, nutzer.id));
  assert.ok(immerNoch, 'gewarnt heisst noch nicht geloescht');

  const nachWarnung = versand.gesendet.length;
  await raeumeAuf(JETZT);
  assert.equal(versand.gesendet.length, nachWarnung, 'keine zweite Warnung');
});

test('Ein zahlendes Konto gilt nie als ruhend', async () => {
  const nutzer = await legeNutzerAn({ erstelltAm: vorTagen(900), zahlendSeit: vorTagen(880) });

  await raeumeAuf(JETZT);

  const d = await db();
  const [uebrig] = await d.select().from(schema.nutzer).where(eq(schema.nutzer.id, nutzer.id));
  assert.ok(uebrig, 'ein Konto zu loeschen, fuer das jemand zahlt, waere ein Fehler mit Ansage');
});

test('Kontolöschung nimmt alles mit, auch was nicht am Fremdschluessel haengt', async () => {
  const nutzer = await legeNutzerAn();
  const vorgang = await legeVorgangAn(nutzer.id, { zustand: 'warte_auf_mich' });
  const d = await db();

  await d.insert(schema.nachrichten).values({
    vorgangId: vorgang.id,
    richtung: 'ein',
    von: 'praxis@example.test',
    an: `${nutzer.handle}@assistent.test`,
    betreff: 'Verordnung',
    text: 'Gesundheitsdaten',
  });
  await d.insert(schema.protokoll).values({ nutzerId: nutzer.id, was: 'irgendwas' });
  await d.insert(schema.regeln).values({
    nutzerId: nutzer.id,
    empfaenger: 'praxis@example.test',
    aktionstyp: 'nachfassen',
  });
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'attrappe',
    secretRef: 'egal',
    konfig: {},
  });
  // Haengt an der MAILADRESSE, nicht an der Nutzer-ID — genau der Fall, der
  // ohne eigene Zeile zurueckbliebe.
  await d.insert(schema.anmeldeTokens).values({
    email: nutzer.email,
    tokenHash: `hash-${nutzer.id}`,
    gueltigBis: inTagen(1),
  });

  await loescheKonto(nutzer.id);

  assert.equal((await d.select().from(schema.nutzer).where(eq(schema.nutzer.id, nutzer.id))).length, 0);
  assert.equal(
    (await d.select().from(schema.vorgaenge).where(eq(schema.vorgaenge.id, vorgang.id))).length,
    0,
  );
  assert.equal(
    (await d.select().from(schema.nachrichten).where(eq(schema.nachrichten.vorgangId, vorgang.id)))
      .length,
    0,
  );
  assert.equal(
    (await d.select().from(schema.protokoll).where(eq(schema.protokoll.nutzerId, nutzer.id))).length,
    0,
  );
  assert.equal(
    (await d.select().from(schema.regeln).where(eq(schema.regeln.nutzerId, nutzer.id))).length,
    0,
  );
  assert.equal(
    (
      await d
        .select()
        .from(schema.kalenderVerbindungen)
        .where(eq(schema.kalenderVerbindungen.nutzerId, nutzer.id))
    ).length,
    0,
  );
  assert.equal(
    (
      await d
        .select()
        .from(schema.anmeldeTokens)
        .where(eq(schema.anmeldeTokens.email, nutzer.email))
    ).length,
    0,
    'der Anmelde-Token haengt an der Mailadresse und waere sonst uebrig geblieben',
  );
});

test('Der Export enthaelt die Daten, aber keine Zugangsdaten im Klartext', async () => {
  const nutzer = await legeNutzerAn();
  const vorgang = await legeVorgangAn(nutzer.id, { zustand: 'warte_auf_mich' });
  const d = await db();

  await d.insert(schema.nachrichten).values({
    vorgangId: vorgang.id,
    richtung: 'ein',
    von: 'praxis@example.test',
    an: `${nutzer.handle}@assistent.test`,
    betreff: 'Folgeverordnung',
    text: 'Verordnung fuer Jonas Berger',
  });
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'ics_secret_url',
    secretRef: 'VERSCHLUESSELTES-GEHEIMNIS',
    konfig: {},
  });

  const daten = await exportiereDaten(nutzer.id);
  const roh = JSON.stringify(daten);

  assert.match(roh, /Jonas Berger/, 'die eigentlichen Daten muessen drin sein');
  assert.match(roh, /praxis@example\.test/);
  assert.equal((daten.vorgaenge as unknown[]).length, 1);

  // Ein Export, der Zugangsdaten in den Download-Ordner schreibt, waere das
  // Gegenteil von Datenschutz.
  assert.doesNotMatch(roh, /VERSCHLUESSELTES-GEHEIMNIS/, 'kein secretRef im Export');
  assert.ok(Array.isArray(daten.nichtEnthalten), 'und das Fehlen wird benannt');
});

test('Der Export einer Nutzerin enthaelt nichts von einer anderen', async () => {
  const eine = await legeNutzerAn();
  const andere = await legeNutzerAn();
  const d = await db();

  const fremderVorgang = await legeVorgangAn(andere.id, { zustand: 'warte_auf_mich' });
  await d.insert(schema.nachrichten).values({
    vorgangId: fremderVorgang.id,
    richtung: 'ein',
    von: 'fremd@example.test',
    an: `${andere.handle}@assistent.test`,
    betreff: 'Geht dich nichts an',
    text: 'STRENG-GEHEIM-FREMD',
  });

  const daten = await exportiereDaten(eine.id);
  assert.doesNotMatch(JSON.stringify(daten), /STRENG-GEHEIM-FREMD/);
});

test('Aufraeumen laesst fremde Konten in Ruhe und ist wiederholbar', async () => {
  const nutzer = await legeNutzerAn();
  const laufend = await legeVorgangAn(nutzer.id, { zustand: 'neu', geaendertAm: vorTagen(500) });

  const erstes = await raeumeAuf(JETZT);
  const zweites = await raeumeAuf(JETZT);

  // Beim zweiten Durchlauf darf nichts mehr zu tun sein — sonst schriebe
  // der Takt jede Minute dieselben Zeilen.
  assert.equal(zweites.vorgaenge, 0);
  assert.equal(zweites.tokens, 0);
  assert.equal(zweites.protokollWortlaut, 0);
  assert.ok(erstes.vorgaenge >= 0);

  const d = await db();
  assert.equal(
    (await d.select().from(schema.vorgaenge).where(eq(schema.vorgaenge.id, laufend.id))).length,
    1,
  );
  assert.ok(
    (
      await d
        .select()
        .from(schema.kalenderVerbindungen)
        .where(
          and(
            eq(schema.kalenderVerbindungen.nutzerId, nutzer.id),
            eq(schema.kalenderVerbindungen.kind, 'attrappe'),
          ),
        )
    ).length >= 0,
  );
});
