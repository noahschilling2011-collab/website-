import PostalMime from 'postal-mime';
import { normalisiereMessageId, threadSchluessel } from './threading';

/**
 * Eingehende Mail: rohes MIME rein, strukturierter Vorgang raus.
 *
 * Cloudflare liefert die vollstaendige Rohnachricht als Stream
 * (ForwardableEmailMessage.raw) und empfiehlt selbst postal-mime zum
 * Zerlegen. Das ist der Grund, warum der Empfang ueber Cloudflare laeuft
 * und nicht ueber Resend: dessen Inbound-Webhook liefert ausdruecklich nur
 * Metadaten, keine Anhaenge — und die Fristen stecken in den Anhaengen.
 */

export interface EingehenderAnhang {
  dateiname: string;
  mimeTyp: string;
  groesseBytes: number;
  textExtrakt: string | null;
  extraktionFehlgeschlagen: boolean;
}

export interface EingehendeMail {
  messageId: string | null;
  inReplyTo: string | null;
  referenzen: string | null;
  threadKey: string;
  von: string;
  vonName: string | null;
  an: string[];
  betreff: string;
  text: string;
  anhaenge: EingehenderAnhang[];
}

/** Der lokale Teil der Empfaengeradresse: katrin@domain -> "katrin". */
export function handleAus(adressen: string[], mailDomain: string): string | null {
  for (const adresse of adressen) {
    const [lokal, domain] = adresse.toLowerCase().split('@');
    if (lokal && domain === mailDomain.toLowerCase()) return lokal;
  }
  return null;
}

export async function parseEingang(
  roh: ArrayBuffer | Uint8Array | string,
): Promise<EingehendeMail> {
  const mail = await PostalMime.parse(roh as never);

  const referenzen = mail.references ?? null;
  const messageId = normalisiereMessageId(mail.messageId);
  const inReplyTo = normalisiereMessageId(mail.inReplyTo);

  const anhaenge: EingehenderAnhang[] = [];
  for (const anhang of mail.attachments ?? []) {
    anhaenge.push(await verarbeiteAnhang(anhang));
  }

  return {
    messageId,
    inReplyTo,
    referenzen,
    threadKey: threadSchluessel({ messageId, inReplyTo, referenzen }),
    von: mail.from?.address ?? '',
    vonName: mail.from?.name || null,
    an: (mail.to ?? []).map((e) => e.address ?? '').filter(Boolean),
    betreff: mail.subject ?? '(kein Betreff)',
    text: (mail.text ?? entferneHtml(mail.html ?? '')).trim(),
    anhaenge,
  };
}

interface RoherAnhang {
  filename?: string | null;
  mimeType?: string | null;
  /** postal-mime liefert je nach Encoding string, ArrayBuffer oder Uint8Array. */
  content: ArrayBuffer | Uint8Array | string;
}

async function verarbeiteAnhang(anhang: RoherAnhang): Promise<EingehenderAnhang> {
  const inhalt =
    typeof anhang.content === 'string'
      ? new TextEncoder().encode(anhang.content)
      : anhang.content instanceof Uint8Array
        ? anhang.content
        : new Uint8Array(anhang.content);

  const basis = {
    dateiname: anhang.filename || 'ohne-namen',
    mimeTyp: anhang.mimeType || 'application/octet-stream',
    groesseBytes: inhalt.byteLength,
  };

  if (basis.mimeTyp === 'application/pdf' || basis.dateiname.toLowerCase().endsWith('.pdf')) {
    const ergebnis = await pdfText(inhalt);
    return { ...basis, ...ergebnis };
  }

  if (basis.mimeTyp.startsWith('text/')) {
    return {
      ...basis,
      textExtrakt: new TextDecoder().decode(inhalt),
      extraktionFehlgeschlagen: false,
    };
  }

  // Bilder, Office-Dokumente, alles andere: nicht raten.
  return { ...basis, textExtrakt: null, extraktionFehlgeschlagen: true };
}

/**
 * Kein OCR. Ein gescanntes PDF ohne Textschicht wird abgelehnt, nicht
 * geraten — eine falsch gelesene Frist ist der teuerste Irrtum des ganzen
 * Produkts (Entwurf, Abschnitt 3B).
 */
export async function pdfText(
  daten: Uint8Array,
): Promise<{ textExtrakt: string | null; extraktionFehlgeschlagen: boolean }> {
  try {
    const { extractText, getDocumentProxy } = await import('unpdf');
    const dokument = await getDocumentProxy(daten);
    const { text, totalPages } = await extractText(dokument, { mergePages: true });
    const sauber = (Array.isArray(text) ? text.join('\n') : text).trim();

    // Faustregel fuer "gescannt statt gesetzt": praktisch kein Text trotz
    // Seiten. Lieber einmal zu oft nachfragen als eine Frist erfinden.
    const seiten = Math.max(1, totalPages ?? 1);
    if (sauber.length < 20 * seiten) {
      return { textExtrakt: null, extraktionFehlgeschlagen: true };
    }
    return { textExtrakt: sauber, extraktionFehlgeschlagen: false };
  } catch {
    return { textExtrakt: null, extraktionFehlgeschlagen: true };
  }
}

function entferneHtml(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\n{3,}/g, '\n\n');
}
