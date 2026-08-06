/**
 * Ausgehende Mail.
 *
 * Zwei Umsetzungen hinter einem Interface: Resend fuer den Betrieb, eine
 * Attrappe fuer Entwicklung und Tests. Die Attrappe existiert nicht aus
 * Bequemlichkeit — sie stellt sicher, dass in der Entwicklung niemals
 * versehentlich eine echte Mail an einen echten Patienten rausgeht.
 */

export interface AusgehendeMail {
  an: string;
  betreff: string;
  text: string;
  inReplyTo?: string | null;
  referenzen?: string | null;
  /** Optionaler iCalendar-Teil fuer den iMIP-Weg (Weg C). */
  ical?: { methode: 'REQUEST' | 'CANCEL'; inhalt: string } | null;
}

export interface Versandergebnis {
  messageId: string;
}

export interface MailVersand {
  sende(mail: AusgehendeMail): Promise<Versandergebnis>;
}

// ---------------------------------------------------------------------------

export class ResendVersand implements MailVersand {
  constructor(
    private readonly apiKey: string,
    private readonly absender: string,
  ) {}

  async sende(mail: AusgehendeMail): Promise<Versandergebnis> {
    const { Resend } = await import('resend');
    const resend = new Resend(this.apiKey);

    // Threading-Header. Ohne sie eroeffnet jedes Nachfassen beim Empfaenger
    // einen neuen Thread — siehe docs/kalender-anbindung-entscheidung.md,
    // Abschnitt 6, warum genau das die Anbieterwahl entschieden hat.
    const headers: Record<string, string> = {};
    if (mail.inReplyTo) headers['In-Reply-To'] = `<${mail.inReplyTo}>`;
    if (mail.referenzen) headers['References'] = mail.referenzen;

    const antwort = await resend.emails.send({
      from: this.absender,
      to: mail.an,
      subject: mail.betreff,
      text: mail.text,
      headers: Object.keys(headers).length ? headers : undefined,
      ...(mail.ical
        ? {
            attachments: [
              {
                filename: 'termin.ics',
                content: Buffer.from(mail.ical.inhalt, 'utf8').toString('base64'),
                contentType: `text/calendar; method=${mail.ical.methode}; charset=UTF-8; component=vevent`,
              },
            ],
          }
        : {}),
    });

    if (antwort.error) {
      throw new Error(`Resend hat den Versand abgelehnt: ${antwort.error.message}`);
    }
    return { messageId: antwort.data?.id ?? '' };
  }
}

// ---------------------------------------------------------------------------

/** Schreibt statt zu senden. Der Standard, solange RESEND_API_KEY fehlt. */
export class AttrappeVersand implements MailVersand {
  readonly gesendet: AusgehendeMail[] = [];

  constructor(private readonly leise = false) {}

  async sende(mail: AusgehendeMail): Promise<Versandergebnis> {
    this.gesendet.push(mail);
    if (!this.leise) {
      console.log(
        [
          '',
          '--- MAIL (Attrappe, nicht gesendet) ---------------------------',
          `An:      ${mail.an}`,
          `Betreff: ${mail.betreff}`,
          mail.inReplyTo ? `In-Reply-To: <${mail.inReplyTo}>` : null,
          mail.referenzen ? `References:  ${mail.referenzen}` : null,
          mail.ical ? `iCalendar:   METHOD=${mail.ical.methode}` : null,
          '',
          mail.text,
          '---------------------------------------------------------------',
        ]
          .filter((z) => z !== null)
          .join('\n'),
      );
    }
    return { messageId: `attrappe-${crypto.randomUUID()}@localhost` };
  }
}

// ---------------------------------------------------------------------------

let zwischenspeicher: MailVersand | null = null;

export function mailVersand(): MailVersand {
  if (zwischenspeicher) return zwischenspeicher;
  const key = process.env.RESEND_API_KEY;
  const absender = process.env.MAIL_ABSENDER;
  zwischenspeicher =
    key && absender ? new ResendVersand(key, absender) : new AttrappeVersand();
  return zwischenspeicher;
}

/** Nur fuer Tests. */
export function setzeMailVersand(versand: MailVersand | null): void {
  zwischenspeicher = versand;
}
