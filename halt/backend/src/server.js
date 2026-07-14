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
import { fileURLToPath } from 'node:url';
import { config, twilioConfigured, gocardlessConfigured, googleConfigured, appleConfigured, isDryRun } from './config.js';
import { twilioSender, dryRunSender } from './twilio.js';
import { createGoCardlessClient } from './gocardless.js';
import { mapGoCardlessResponse } from './mapTransactions.js';
import { runScan } from './notify.js';
import { createAuth } from './auth.js';
import { createUserData } from './userData.js';
import { createOAuth } from './oauth.js';
import { SEED } from './seed.js';

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false })); // Apple posts the callback as a form

const auth = createAuth(new URL('../data/users.json', import.meta.url).pathname);
const userData = createUserData(new URL('../data/userdata.json', import.meta.url).pathname);
const oauth = createOAuth(config);

// Every data endpoint derives the userId from the verified token — NEVER from the
// request body. This is the row-level-security boundary.
function requireAuth(req, res, next) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const email = auth.verify(token);
  if (!email) return res.status(401).json({ error: 'Nicht angemeldet.' });
  req.userId = email;
  next();
}

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
const gc = gocardlessConfigured() ? createGoCardlessClient(config.gocardless) : null;

const wrap = (fn) => (req, res) => fn(req, res).catch((e) => {
  console.error(e);
  res.status(500).json({ error: e.message });
});

app.get('/favicon.ico', (_req, res) => res.sendStatus(204));

// ── Account sign-up / login (real, server-side) ──────────────────────────────
const authRoute = (fn) => (req, res) => {
  try {
    res.json(fn(req.body?.email, req.body?.password));
  } catch (e) {
    res.status(e.status || 400).json({ error: e.message });
  }
};
app.post('/auth/signup', authRoute((email, password) => auth.signup(email, password)));
app.post('/auth/login', authRoute((email, password) => auth.login(email, password)));
app.get('/auth/me', (req, res) => {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const email = auth.verify(token);
  if (!email) return res.status(401).json({ error: 'Nicht angemeldet.' });
  res.json({ email });
});
app.post('/auth/logout', (req, res) => {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  auth.logout(token);
  res.json({ ok: true });
});

// Which login methods this deployment offers — the app shows only these buttons.
app.get('/auth/providers', (_req, res) => {
  res.json({ password: true, google: googleConfigured(), apple: appleConfigured() });
});

// After social login we bounce back to the app with the token in the URL fragment
// (never a query string — fragments aren't sent to servers or logged).
const backToApp = (res, params) =>
  res.redirect(`${config.appUrl}/#${new URLSearchParams(params).toString()}`);

// ── Google ────────────────────────────────────────────────────────────────────
app.get('/auth/google/start', (_req, res) => {
  if (!googleConfigured()) return res.status(400).json({ error: 'Google-Login ist nicht konfiguriert.' });
  const state = oauth.newState(Date.now());
  res.redirect(oauth.googleStartUrl(state));
});

app.get('/auth/google/callback', wrap(async (req, res) => {
  if (!googleConfigured()) return res.status(400).json({ error: 'Google-Login ist nicht konfiguriert.' });
  const { code, state } = req.query;
  if (!code || !oauth.consumeState(state, Date.now())) {
    return backToApp(res, { error: 'Anmeldung abgelaufen oder ungültig. Bitte erneut.' });
  }
  try {
    const { email, provider } = await oauth.googleExchange(String(code), Date.now());
    const { token } = auth.upsertOAuth(email, provider);
    backToApp(res, { token, email });
  } catch (e) {
    backToApp(res, { error: e.message });
  }
}));

// ── Apple (scaffold; needs a paid Apple Developer account) ───────────────────
app.get('/auth/apple/start', (_req, res) => {
  if (!appleConfigured()) return res.status(400).json({ error: 'Apple-Login braucht ein Apple-Developer-Konto und ist nicht konfiguriert.' });
  const state = oauth.newState(Date.now());
  res.redirect(oauth.appleStartUrl(state));
});
app.post('/auth/apple/callback', (req, res) => {
  // Apple posts { code, state, ... }. Exchanging it needs an ES256 client secret
  // signed with your Apple key — intentionally not shipped untested.
  backToApp(res, { error: 'Apple-Login ist noch nicht fertig eingerichtet.' });
});

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    dryRun: isDryRun(),
    twilio: twilioConfigured(),
    gocardless: gocardlessConfigured(),
    alertChannel: config.alertChannel,
    alertPhoneSet: Boolean(config.alertPhone),
    users: auth.count(),
  });
});

// ── Per-user profile (protected person + trusted contacts) ───────────────────
app.get('/me/profile', requireAuth, (req, res) => {
  res.json(userData.getProfile(req.userId));
});
app.put('/me/profile', requireAuth, (req, res) => {
  res.json(userData.setProfile(req.userId, req.body || {}));
});
app.get('/me/alerts', requireAuth, (req, res) => {
  res.json({ alerts: userData.getAlerts(req.userId) });
});

// Where THIS user's alerts go: their own first trusted contact, else the
// operator's ALERT_PHONE fallback. (On a Twilio trial the number must be verified.)
const destFor = (uid) => userData.alertPhone(uid) || config.alertPhone || null;

// Prove the alarm path works — rings the user's own trusted contact.
app.post('/test-alert', requireAuth, wrap(async (req, res) => {
  const to = destFor(req.userId);
  if (!to) return res.status(400).json({ error: 'Keine Zielnummer: trag eine Vertrauensperson ein (oder ALERT_PHONE).' });
  const message = req.body?.message || 'Test von HALT: Wenn du das bekommst, funktioniert dein Alarm.';
  const results = {};
  if (config.alertChannel !== 'call') results.sms = await sender.sms(to, message);
  if (config.alertChannel !== 'sms') results.call = await sender.call(to, message);
  res.json({ sent: true, dryRun: isDryRun(), to, results });
}));

// Full alert path on the seed history (includes an ongoing crypto scam).
app.post('/demo-scan', requireAuth, wrap(async (req, res) => {
  const result = await runScan(SEED, {
    sender, seen: userData.seenStore(req.userId), to: destFor(req.userId), channel: config.alertChannel,
  });
  userData.setAlerts(req.userId, result.alerts);
  res.json({ dryRun: isDryRun(), ...result });
}));

// ── Real bank connection (GoCardless) ─────────────────────────────────────────
app.post('/connect/start', requireAuth, wrap(async (req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert (siehe .env)' });
  const r = await gc.createRequisition({
    institutionId: config.gocardless.institutionId,
    redirect: config.gocardless.redirectUrl,
  });
  userData.setRequisition(req.userId, r.id);
  res.json({ requisitionId: r.id, link: r.link, status: r.status });
}));

app.get('/connect/status/:id', requireAuth, wrap(async (req, res) => {
  // Ownership first — reject a requisition this user didn't create, regardless
  // of provider config (don't even leak whether GoCardless is set up).
  if (userData.getRequisition(req.userId) !== req.params.id) {
    return res.status(403).json({ error: 'Kein Zugriff auf diese Verbindung.' });
  }
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert' });
  const r = await gc.getRequisition(req.params.id);
  res.json({ status: r.status, accounts: r.accounts ?? [] });
}));

app.post('/scan/:accountId', requireAuth, wrap(async (req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert' });
  const raw = await gc.getTransactions(req.params.accountId);
  const transactions = mapGoCardlessResponse(raw);
  const result = await runScan(transactions, {
    sender, seen: userData.seenStore(req.userId), to: destFor(req.userId), channel: config.alertChannel,
  });
  userData.setAlerts(req.userId, result.alerts);
  res.json({ dryRun: isDryRun(), ...result });
}));

app.get('/connect/callback', (_req, res) => {
  res.type('html').send(
    `<meta charset="utf8"><body style="font-family:sans-serif;background:#0b0d12;color:#eef1f7;display:grid;place-items:center;height:100vh;margin:0">
     <div style="text-align:center"><h2>✅ Konto verbunden</h2><p>Du kannst dieses Fenster schließen und zu HALT zurückkehren.</p></div></body>`,
  );
});

// Only bind a port when run directly (node src/server.js) — not when imported by
// a test, which starts its own ephemeral listener.
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const port = config.port;
  app.listen(port, () => {
    console.log(`HALT backend läuft auf http://localhost:${port}`);
    console.log(`  Twilio:     ${twilioConfigured() ? 'konfiguriert' : 'DRY_RUN (keine Zugangsdaten)'}`);
    console.log(`  GoCardless: ${gocardlessConfigured() ? 'konfiguriert' : 'nicht konfiguriert'}`);
  });
}

export { app };
