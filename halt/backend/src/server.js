// HALT backend — the real thing.
//
// Endpoints:
//   GET  /health                     status + whether Twilio/GoCardless are configured
//   POST /test-alert                 send a test SMS/call to ALERT_PHONE (prove your phone rings)
//   POST /demo-scan                  run the seed history through engine + escalation (no bank needed)
//   POST /connect/start              create a GoCardless requisition -> returns hosted consent link
//   GET  /connect/status/:id         requisition status + connected account ids
//   POST /scan/:accountId            fetch real transactions, assess, escalate
//   GET  /connect/callback           landing page after consent

import express from 'express';
import { config, twilioConfigured, gocardlessConfigured, isDryRun } from './config.js';
import { twilioSender, dryRunSender } from './twilio.js';
import { createGoCardlessClient } from './gocardless.js';
import { mapGoCardlessResponse } from './mapTransactions.js';
import { runScan } from './notify.js';
import { fileSeenStore } from './store.js';
import { SEED } from './seed.js';

const app = express();
app.use(express.json());

// CORS — so the HALT web app can call this backend from anywhere (incl. a file://
// page during testing). The API holds no data that isn't already the caller's.
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// Serve the HALT web app itself, so the deployed backend URL *is* the whole app.
// Open that URL on your phone and everything works — no terminal, no separate host.
app.use(express.static(new URL('../../demo', import.meta.url).pathname));

const sender = twilioConfigured() ? twilioSender(config.twilio) : dryRunSender();
const seen = fileSeenStore(new URL('../data/notified.json', import.meta.url).pathname);
const gc = gocardlessConfigured() ? createGoCardlessClient(config.gocardless) : null;

const wrap = (fn) => (req, res) => fn(req, res).catch((e) => {
  console.error(e);
  res.status(500).json({ error: e.message });
});

app.get('/favicon.ico', (_req, res) => res.sendStatus(204));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    dryRun: isDryRun(),
    twilio: twilioConfigured(),
    gocardless: gocardlessConfigured(),
    alertChannel: config.alertChannel,
    alertPhoneSet: Boolean(config.alertPhone),
  });
});

// Prove the alarm path works — rings/texts YOUR phone. The first thing to try.
app.post('/test-alert', wrap(async (req, res) => {
  if (!config.alertPhone) return res.status(400).json({ error: 'ALERT_PHONE fehlt in .env' });
  const message = req.body?.message || 'Test von HALT: Wenn du das bekommst, funktioniert dein Alarm.';
  const results = {};
  if (config.alertChannel !== 'call') results.sms = await sender.sms(config.alertPhone, message);
  if (config.alertChannel !== 'sms') results.call = await sender.call(config.alertPhone, message);
  res.json({ sent: true, dryRun: isDryRun(), to: config.alertPhone, results });
}));

// Full alert path on the seed history (includes an ongoing crypto scam).
app.post('/demo-scan', wrap(async (_req, res) => {
  const result = await runScan(SEED, {
    sender, seen, to: config.alertPhone, channel: config.alertChannel,
  });
  res.json({ dryRun: isDryRun(), ...result });
}));

// ── Real bank connection (GoCardless) ─────────────────────────────────────────
app.post('/connect/start', wrap(async (_req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert (siehe .env)' });
  const r = await gc.createRequisition({
    institutionId: config.gocardless.institutionId,
    redirect: config.gocardless.redirectUrl,
  });
  res.json({ requisitionId: r.id, link: r.link, status: r.status });
}));

app.get('/connect/status/:id', wrap(async (req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert' });
  const r = await gc.getRequisition(req.params.id);
  res.json({ status: r.status, accounts: r.accounts ?? [] });
}));

app.post('/scan/:accountId', wrap(async (req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert' });
  const raw = await gc.getTransactions(req.params.accountId);
  const transactions = mapGoCardlessResponse(raw);
  const result = await runScan(transactions, {
    sender, seen, to: config.alertPhone, channel: config.alertChannel,
  });
  res.json({ dryRun: isDryRun(), ...result });
}));

app.get('/connect/callback', (_req, res) => {
  res.type('html').send(
    `<meta charset="utf8"><body style="font-family:sans-serif;background:#0b0d12;color:#eef1f7;display:grid;place-items:center;height:100vh;margin:0">
     <div style="text-align:center"><h2>✅ Konto verbunden</h2><p>Du kannst dieses Fenster schließen und zu HALT zurückkehren.</p></div></body>`,
  );
});

const port = config.port;
app.listen(port, () => {
  console.log(`HALT backend läuft auf http://localhost:${port}`);
  console.log(`  Twilio:     ${twilioConfigured() ? 'konfiguriert' : 'DRY_RUN (keine Zugangsdaten)'}`);
  console.log(`  GoCardless: ${gocardlessConfigured() ? 'konfiguriert' : 'nicht konfiguriert'}`);
});

export { app };
