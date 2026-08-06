import crypto from 'node:crypto';

/**
 * Zugangsdaten liegen nie im Klartext in der Datenbank.
 *
 * AES-256-GCM mit einem Schluessel aus SECRET_KEY. Das Format ist
 * v1.<iv>.<tag>.<ciphertext>, alles base64url — versioniert, damit ein
 * spaeterer Schluesselwechsel migrierbar ist statt ein Bruch.
 */

const PRAEFIX = 'v1';

function schluessel(): Buffer {
  const roh = process.env.SECRET_KEY;
  if (!roh) {
    throw new Error(
      'SECRET_KEY fehlt. Erzeugen mit: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'base64\'))"',
    );
  }
  // Beliebig langer Eingabewert wird auf 32 Byte normalisiert.
  return crypto.createHash('sha256').update(roh).digest();
}

export function verschluessle(klartext: string): string {
  const iv = crypto.randomBytes(12);
  const chiffre = crypto.createCipheriv('aes-256-gcm', schluessel(), iv);
  const daten = Buffer.concat([chiffre.update(klartext, 'utf8'), chiffre.final()]);
  const tag = chiffre.getAuthTag();
  return [PRAEFIX, b64(iv), b64(tag), b64(daten)].join('.');
}

export function entschluessle(gespeichert: string): string {
  const teile = gespeichert.split('.');
  if (teile.length !== 4 || teile[0] !== PRAEFIX) {
    throw new Error('Unbekanntes Format eines gespeicherten Geheimnisses.');
  }
  const iv = unb64(teile[1]!);
  const tag = unb64(teile[2]!);
  const daten = unb64(teile[3]!);
  const dechiffre = crypto.createDecipheriv('aes-256-gcm', schluessel(), iv);
  dechiffre.setAuthTag(tag);
  return Buffer.concat([dechiffre.update(daten), dechiffre.final()]).toString('utf8');
}

/** Zeitkonstanter Vergleich fuer Tokens aus URLs. */
export function gleich(a: string, b: string): boolean {
  const pa = Buffer.from(a);
  const pb = Buffer.from(b);
  if (pa.length !== pb.length) return false;
  return crypto.timingSafeEqual(pa, pb);
}

export function zufallsToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function hashe(wert: string): string {
  return crypto.createHash('sha256').update(wert).digest('base64url');
}

/**
 * Wie `hashe`, aber mit dem SECRET_KEY als Schluessel.
 *
 * Fuer den sechsstelligen Anmeldecode ist der Unterschied nicht kosmetisch:
 * ein blosser SHA-256 ueber sechs Ziffern ist offline in Sekunden
 * durchprobiert — es gibt nur eine Million Moeglichkeiten. Wer die Datenbank
 * in die Haende bekaeme, koennte jeden offenen Code zurueckrechnen. Mit
 * Schluessel geht das nur, wenn er auch den Schluessel hat, und dann ist der
 * Code das kleinste Problem.
 *
 * Fuer den 32-Byte-Zufallstoken des Anmeldelinks waere das unnoetig; dort
 * bleibt es bei `hashe`.
 */
export function hasheMitSchluessel(wert: string): string {
  const geheim = process.env.SECRET_KEY;
  if (!geheim) throw new Error('SECRET_KEY fehlt.');
  return crypto.createHmac('sha256', geheim).update(wert).digest('base64url');
}

/**
 * Ein sechsstelliger Code, gleichverteilt.
 *
 * `crypto.randomInt` und nicht `Math.random`: der Code ist ein Zugangsmittel.
 * Fuehrende Nullen bleiben erhalten, sonst waeren manche Codes kuerzer und
 * damit leichter zu raten.
 */
export function zufallsCode(): string {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

const b64 = (b: Buffer) => b.toString('base64url');
const unb64 = (s: string) => Buffer.from(s, 'base64url');
