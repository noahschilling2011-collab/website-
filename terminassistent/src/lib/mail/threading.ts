import crypto from 'node:crypto';

/**
 * Threading nach RFC 5322.
 *
 * Ein Nachfassen, das beim Empfaenger einen neuen Thread aufmacht, ist ein
 * anderes Produkt. Deshalb ist das hier keine Kuer: In-Reply-To zeigt auf
 * die zuletzt beantwortete Nachricht, References enthaelt die ganze Kette
 * von der Wurzel bis dorthin.
 */

/** "<abc@x.de>" -> "abc@x.de"; toleriert fehlende spitze Klammern. */
export function normalisiereMessageId(roh: string | null | undefined): string | null {
  if (!roh) return null;
  const wert = roh.trim();
  const treffer = /<([^>]+)>/.exec(wert);
  return (treffer?.[1] ?? wert).trim() || null;
}

/** References ist eine leerzeichengetrennte Liste von Message-IDs. */
export function parseReferenzen(roh: string | null | undefined): string[] {
  if (!roh) return [];
  return [...roh.matchAll(/<([^>]+)>/g)].map((m) => m[1]!.trim()).filter(Boolean);
}

export function formatiereReferenzen(ids: string[]): string {
  return ids.map((id) => `<${id}>`).join(' ');
}

/**
 * Der Schluessel, der alle Nachrichten eines Vorgangs zusammenhaelt.
 *
 * Bevorzugt die Wurzel der References-Kette: die bleibt ueber den ganzen
 * Thread stabil, auch wenn Betreffzeilen sich aendern ("Re: Re: AW:").
 * Erst wenn es keine Kette gibt, ist die eigene Message-ID die Wurzel.
 */
export function threadSchluessel(kopf: {
  messageId?: string | null;
  inReplyTo?: string | null;
  referenzen?: string | null;
}): string {
  const kette = parseReferenzen(kopf.referenzen);
  const wurzel =
    kette[0] ??
    normalisiereMessageId(kopf.inReplyTo) ??
    normalisiereMessageId(kopf.messageId);
  if (wurzel) return wurzel;
  // Ohne jeden Header: ein zufaelliger, aber stabiler Schluessel.
  return `ohne-header-${crypto.randomUUID()}`;
}

/**
 * Header fuer eine Antwort auf `aufNachricht`, mit der bisherigen Kette.
 *
 * Cloudflares reply() lehnt References mit mehr als 100 Eintraegen ab, und
 * lange Ketten helfen ohnehin nicht. Bei Ueberlaenge bleiben Wurzel und die
 * letzten Glieder erhalten — das ist die Empfehlung aus RFC 5322 fuer
 * genau diesen Fall.
 */
export function antwortHeader(
  aufNachricht: { messageId?: string | null; referenzen?: string | null },
  maxEintraege = 50,
): { inReplyTo: string | null; referenzen: string | null } {
  const ziel = normalisiereMessageId(aufNachricht.messageId);
  if (!ziel) return { inReplyTo: null, referenzen: aufNachricht.referenzen ?? null };

  const kette = [...parseReferenzen(aufNachricht.referenzen), ziel];
  const gekuerzt =
    kette.length <= maxEintraege
      ? kette
      : [kette[0]!, ...kette.slice(kette.length - (maxEintraege - 1))];

  return { inReplyTo: ziel, referenzen: formatiereReferenzen(gekuerzt) };
}

/** Betreff einer Antwort, ohne "Re: Re: Re:" zu stapeln. */
export function antwortBetreff(betreff: string): string {
  const ohnePraefix = betreff.replace(/^((re|aw|antw|fwd|wg)\s*(\[\d+\])?:\s*)+/i, '');
  return `Re: ${ohnePraefix}`.trim();
}
