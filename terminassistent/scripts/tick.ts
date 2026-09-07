import { takt } from '../src/lib/vorgang/engine';

/**
 * Der Takt von Hand — fuer die Entwicklung, wenn kein Cron laeuft.
 *
 * Sendet abgelaufene Haltezeiten und legt faellige Erinnerungen an.
 * In Betrieb macht das ein Cloudflare Cron Trigger gegen /api/takt.
 *
 * Aufruf:  npm run tick
 *          npm run tick -- --vor 2h    (so tun, als waeren 2 Stunden vergangen)
 */

process.env.MAIL_DOMAIN ??= 'assistent.localhost';
process.env.SECRET_KEY ??= 'entwicklungsschluessel-nicht-produktiv';

const argument = process.argv.indexOf('--vor');
let jetzt = new Date();

if (argument !== -1) {
  const wert = process.argv[argument + 1] ?? '0';
  const treffer = /^(\d+)([smhd])$/.exec(wert);
  if (!treffer) {
    console.error('Format: --vor 90s | 5m | 2h | 1d');
    process.exit(1);
  }
  const faktor = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[treffer[2]!]!;
  jetzt = new Date(Date.now() + Number(treffer[1]) * faktor);
  console.log(`Takt zum simulierten Zeitpunkt ${jetzt.toISOString()}`);
}

const ergebnis = await takt(jetzt);
console.log(
  `Gesendet: ${ergebnis.gesendet} · Erinnerungen: ${ergebnis.erinnerungen} · Fehler: ${ergebnis.fehler}`,
);
process.exit(0);
