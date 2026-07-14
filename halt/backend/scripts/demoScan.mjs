// `npm run demo-scan` — runs the seed history (with an ongoing crypto scam)
// through the real engine + escalation. With Twilio configured, your phone
// rings/texts for each of the 3 fraud alerts. Without creds: DRY_RUN logs.

import { config, twilioConfigured, isDryRun } from '../src/config.js';
import { twilioSender, dryRunSender } from '../src/twilio.js';
import { fileSeenStore } from '../src/store.js';
import { runScan } from '../src/notify.js';
import { SEED } from '../src/seed.js';

const sender = twilioConfigured() ? twilioSender(config.twilio) : dryRunSender();
const seen = fileSeenStore(new URL('../data/notified.json', import.meta.url).pathname);

const result = await runScan(SEED, {
  sender,
  seen,
  to: config.alertPhone,
  channel: config.alertChannel,
});

console.log(`\nGeprüft: ${result.total} Bewegungen`);
console.log(`Verdächtig (Alarm): ${result.escalated}`);
console.log(`Neu benachrichtigt: ${result.newlyDelivered}${isDryRun() ? ' (DRY_RUN — nichts real gesendet)' : ''}`);
if (result.newlyDelivered === 0 && result.escalated > 0) {
  console.log('(Bereits zuvor benachrichtigt — dedupliziert. Lösche data/notified.json zum Zurücksetzen.)');
}
