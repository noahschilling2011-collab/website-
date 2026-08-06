import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

process.env.MAIL_DOMAIN = 'assistent.test';
process.env.MAIL_ABSENDER = 'Assistenz <assistenz@assistent.test>';
process.env.SECRET_KEY = 'test-schluessel-nur-fuer-tests';
process.env.APP_URL = 'https://assistent.test';
delete process.env.ANTHROPIC_API_KEY;
delete process.env.RESEND_API_KEY;
delete process.env.DATABASE_URL;

const tempVerzeichnis = fs.mkdtempSync(path.join(os.tmpdir(), 'terminassistent-auth-'));
process.env.PGLITE_DIR = tempVerzeichnis;

const { db, schema } = await import('../db/index');
const { AttrappeVersand, setzeMailVersand } = await import('./mail/ausgang');
const { MAX_VERSUCHE, loeseCodeEin, loeseTokenEin, sendeAnmeldeCode } = await import('./sitzung');
const { eq } = await import('drizzle-orm');

const versand = new AttrappeVersand(true);

before(() => setzeMailVersand(versand));
after(() => {
  setzeMailVersand(null);
  fs.rmSync(tempVerzeichnis, { recursive: true, force: true });
});

let nummer = 0;
const neueAdresse = () => `anmeldung${++nummer}@praxis.test`;

/** Liest den Code aus der zuletzt verschickten Mail. */
function letzterCode(): string {
  const mail = versand.gesendet.at(-1)!;
  const treffer = mail.text.match(/\n {4}(\d{6})\n/);
  assert.ok(treffer, 'die Mail muss einen sechsstelligen Code enthalten');
  return treffer![1]!;
}

function letzterLinkToken(): string {
  const mail = versand.gesendet.at(-1)!;
  const treffer = mail.text.match(/https:\/\/assistent\.test\/anmelden\/(\S+)/);
  assert.ok(treffer, 'die Mail muss einen Link enthalten');
  return treffer![1]!;
}

/** Der Code steckt im Betreff, damit man ihn in der Vorschau sieht. */
test('Die Mail traegt den Code im Betreff und im Text', async () => {
  const email = neueAdresse();
  assert.deepEqual(await sendeAnmeldeCode(email), { ok: true });

  const mail = versand.gesendet.at(-1)!;
  assert.equal(mail.an, email);
  const code = letzterCode();
  assert.match(mail.betreff, new RegExp(`^${code} `));
  assert.match(mail.text, /gilt 15 Minuten/);
});

test('Der richtige Code meldet an und legt die Nutzerin beim ersten Mal an', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email);

  const ergebnis = await loeseCodeEin(email, letzterCode());
  assert.equal(ergebnis.ok, true);
  assert.equal((ergebnis as { nutzer: { email: string } }).nutzer.email, email);

  const d = await db();
  const [nutzer] = await d.select().from(schema.nutzer).where(eq(schema.nutzer.email, email));
  assert.ok(nutzer, 'Anmeldung ist zugleich Registrierung');
  assert.ok(nutzer!.handle, 'die Weiterleitungsadresse entsteht dabei');
});

test('Derselbe Code gilt nur einmal', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email);
  const code = letzterCode();

  assert.equal((await loeseCodeEin(email, code)).ok, true);
  const zweitens = await loeseCodeEin(email, code);
  assert.equal(zweitens.ok, false);
  assert.equal((zweitens as { grund: string }).grund, 'abgelaufen');
});

test('Ein falscher Code wird nach fuenf Versuchen gesperrt — auch der richtige', async () => {
  // Das ist die eigentliche Schutzmassnahme. Sechs Ziffern sind nur sicher,
  // solange sie nicht beliebig oft geraten werden duerfen.
  const email = neueAdresse();
  await sendeAnmeldeCode(email);
  const echt = letzterCode();
  const falsch = echt === '000000' ? '111111' : '000000';

  for (let i = 1; i < MAX_VERSUCHE; i++) {
    const ergebnis = await loeseCodeEin(email, falsch);
    assert.equal((ergebnis as { grund: string }).grund, 'falsch', `Versuch ${i}`);
  }

  const letzter = await loeseCodeEin(email, falsch);
  assert.equal((letzter as { grund: string }).grund, 'zu_viele_versuche');

  // Und jetzt zaehlt auch der echte Code nicht mehr.
  const mitEchtem = await loeseCodeEin(email, echt);
  assert.equal(mitEchtem.ok, false, 'ein aufgebrauchter Eintrag bleibt tot');
});

test('Der Code einer Nutzerin oeffnet kein fremdes Konto', async () => {
  // Gesucht wird ueber die Mailadresse, nicht ueber den Codewert — sonst
  // traefe ein geratener Code irgendeinen gerade offenen Code.
  const eine = neueAdresse();
  const andere = neueAdresse();

  await sendeAnmeldeCode(eine);
  const codeVonEiner = letzterCode();
  await sendeAnmeldeCode(andere);

  const ergebnis = await loeseCodeEin(andere, codeVonEiner);
  assert.equal(ergebnis.ok, false);
});

test('Unsinnige Eingaben stuerzen nicht ab und zaehlen als Fehlversuch', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email);

  for (const eingabe of ['', 'abcdef', '12345', '1234567']) {
    const ergebnis = await loeseCodeEin(email, eingabe);
    assert.equal(ergebnis.ok, false, `Eingabe ${JSON.stringify(eingabe)}`);
  }
});

test('Leerzeichen und Bindestriche im Code werden verziehen', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email);
  const code = letzterCode();
  const zerlegt = `${code.slice(0, 3)} ${code.slice(3)}`;

  assert.equal((await loeseCodeEin(email, zerlegt)).ok, true);
});

test('Die Grossschreibung der Adresse ist egal', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email.toUpperCase());
  assert.equal((await loeseCodeEin(email, letzterCode())).ok, true);
});

test('Ohne angeforderten Code passiert nichts', async () => {
  const ergebnis = await loeseCodeEin(neueAdresse(), '123456');
  assert.equal(ergebnis.ok, false);
  assert.equal((ergebnis as { grund: string }).grund, 'abgelaufen');
});

test('Zwei Anfragen kurz hintereinander schicken nur eine Mail', async () => {
  // Sonst entwertete der zweite Klick den Code, den die Nutzerin gerade
  // aus der ersten Mail abtippt.
  const email = neueAdresse();
  assert.deepEqual(await sendeAnmeldeCode(email), { ok: true });
  const code = letzterCode();
  const anzahl = versand.gesendet.length;

  const zweitens = await sendeAnmeldeCode(email);
  assert.deepEqual(zweitens, { ok: false, grund: 'zu_haeufig' });
  assert.equal(versand.gesendet.length, anzahl, 'keine zweite Mail');
  assert.equal((await loeseCodeEin(email, code)).ok, true, 'der erste Code gilt weiter');
});

test('Der Link aus derselben Mail meldet ebenfalls an und verbraucht den Code mit', async () => {
  const email = neueAdresse();
  await sendeAnmeldeCode(email);
  const code = letzterCode();
  const token = letzterLinkToken();

  const nutzer = await loeseTokenEin(token);
  assert.ok(nutzer, 'der Link funktioniert weiterhin');
  assert.equal(nutzer!.email, email);

  // Beide gehoeren zu EINEM Eintrag: wer eins benutzt, verbraucht das andere.
  assert.equal(
    (await loeseCodeEin(email, code)).ok,
    false,
    'der Code der schon benutzten Mail darf nicht mehr gelten',
  );
});

test('Nach fuenf Codes in einer Stunde ist Schluss', async () => {
  const email = neueAdresse();
  const d = await db();

  // Fuenf Anfragen, jeweils kuenstlich gealtert, damit nicht die
  // 60-Sekunden-Sperre zuerst greift.
  for (let i = 0; i < 5; i++) {
    const ergebnis = await sendeAnmeldeCode(email);
    assert.deepEqual(ergebnis, { ok: true }, `Anfrage ${i + 1}`);
    await d
      .update(schema.anmeldeTokens)
      .set({ erstelltAm: new Date(Date.now() - 5 * 60_000) })
      .where(eq(schema.anmeldeTokens.email, email));
  }

  assert.deepEqual(await sendeAnmeldeCode(email), { ok: false, grund: 'zu_haeufig' });
});
