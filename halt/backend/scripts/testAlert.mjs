// `npm run test-alert` — the very first thing to try once you've filled in .env.
// Sends a real SMS/call to YOUR verified number so you can confirm the alarm
// path works end to end. Without Twilio creds it runs in DRY_RUN and just logs.

import { config, twilioConfigured } from '../src/config.js';
import { twilioSender, dryRunSender } from '../src/twilio.js';

const sender = twilioConfigured() ? twilioSender(config.twilio) : dryRunSender();
const to = config.alertPhone;

if (!to) {
  console.error('❌ ALERT_PHONE fehlt in .env — trag deine eigene (verifizierte) Nummer ein.');
  process.exit(1);
}

const message = process.argv.slice(2).join(' ') ||
  'Test von HALT: Wenn du das bekommst, funktioniert dein Alarm.';

try {
  if (config.alertChannel !== 'call') await sender.sms(to, message);
  if (config.alertChannel !== 'sms') await sender.call(to, message);
  console.log(
    twilioConfigured()
      ? `✅ Gesendet an ${to} (Kanal: ${config.alertChannel}). Schau auf dein Handy.`
      : 'ℹ️  DRY_RUN — keine Twilio-Zugangsdaten in .env. Es wurde nichts wirklich gesendet.',
  );
} catch (e) {
  console.error('❌', e.message);
  process.exit(1);
}
