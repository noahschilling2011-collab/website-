import type { KalenderVerbindung } from '../../db/schema';
import { entschluessle } from '../krypto';
import { AttrappeSink, AttrappeSource } from './attrappe';
import { GoogleCalendarSink, GoogleCalendarSource, type GoogleZugang } from './google';
import { IcsFeedSource, IcsPublishSink } from './ics';
import { ImipMailSink, type EinladungsKanal } from './imip';
import type { CalendarSink, CalendarSource } from './types';

/**
 * Der einzige Ort im Programm, an dem der Kanalname vorkommen darf.
 *
 * Sobald irgendwo sonst `if (kind === 'google_oauth')` steht, ist die
 * Abstraktion tot. Anwendungscode fragt `capabilities`, nie `kind`.
 */

export function baueSource(verbindung: KalenderVerbindung): CalendarSource {
  switch (verbindung.kind) {
    case 'google_oauth':
      return new GoogleCalendarSource(verbindung.id, googleZugang(verbindung));

    case 'ics_secret_url':
      return new IcsFeedSource(verbindung.id, {
        url: entschluessle(verbindung.secretRef),
        pollIntervallSekunden: Number(verbindung.konfig.pollIntervallSekunden ?? 900),
      });

    case 'attrappe':
      return new AttrappeSource(verbindung.id, []);

    default:
      throw new Error(
        `Die Verbindungsart "${verbindung.kind}" kann keine Verfuegbarkeit lesen.`,
      );
  }
}

/**
 * @param einladungsKanal Wird nur fuer 'imip_mail' gebraucht. Der Sink darf
 *   nicht selbst versenden — sonst haette er die Faehigkeit, an der
 *   60-Sekunden-Haltezeit vorbei Post an einen echten Menschen zu schicken.
 */
export function baueSink(
  verbindung: KalenderVerbindung,
  einladungsKanal?: EinladungsKanal,
): CalendarSink {
  switch (verbindung.kind) {
    case 'google_oauth':
      return new GoogleCalendarSink(verbindung.id, googleZugang(verbindung));

    case 'ics_publish':
      return new IcsPublishSink(verbindung.id);

    case 'imip_mail':
      if (!einladungsKanal) {
        throw new Error(
          'Der iMIP-Weg braucht einen Versandkanal; ohne ihn wuerde die Einladung nirgends landen.',
        );
      }
      return new ImipMailSink(verbindung.id, einladungsKanal);

    case 'attrappe':
      return new AttrappeSink(verbindung.id);

    default:
      throw new Error(
        `Die Verbindungsart "${verbindung.kind}" kann keine Termine schreiben.`,
      );
  }
}

function googleZugang(verbindung: KalenderVerbindung): GoogleZugang {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    throw new Error(
      'GOOGLE_CLIENT_ID und GOOGLE_CLIENT_SECRET fehlen. Siehe .env.example.',
    );
  }
  return {
    refreshToken: entschluessle(verbindung.secretRef),
    clientId,
    clientSecret,
    kalenderId: verbindung.konfig.kalenderId ?? 'primary',
  };
}
