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
import { createPhoneVerify } from './phoneVerify.js';
import { securityHeaders, cors, rateLimit } from './security.js';
import { SEED } from './seed.js';

const app = express();
app.set('trust proxy', 1); // correct client IP behind Render's proxy (for rate limiting)
app.use(securityHeaders);
const corsOrigins = (process.env.CORS_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
app.use(cors(corsOrigins));
app.use(express.json({ limit: '32kb' }));
app.use(express.urlencoded({ extended: false, limit: '32kb' })); // Apple posts the callback as a form

// Throttle the account endpoints against brute force / abuse.
const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 30, message: 'Zu viele Anmeldeversuche. Bitte in ein paar Minuten erneut.' });
// Throttle anything that can trigger an outbound SMS/call, per user, so the
// backend can't be turned into an SMS/robocall relay.
const outboundLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 12, key: (req) => `u:${req.userId}`, message: 'Zu viele Alarm-Aktionen. Bitte später erneut.' });

const UUID_RE = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;

const auth = createAuth(new URL('../data/users.json', import.meta.url).pathname);
const userData = createUserData(new URL('../data/userdata.json', import.meta.url).pathname);
const oauth = createOAuth(config);
const phoneVerify = createPhoneVerify();

// Every data endpoint derives the userId from the verified token — NEVER from the
// request body. This is the row-level-security boundary.
function requireAuth(req, res, next) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const email = auth.verify(token);
  if (!email) return res.status(401).json({ error: 'Nicht angemeldet.' });
  req.userId = email;
  next();
}

// Serve the HALT web app itself, so the deployed backend URL *is* the whole app.
// Open that URL on your phone and everything works — no terminal, no separate host.
app.use(express.static(new URL('../../demo', import.meta.url).pathname));

const sender = twilioConfigured() ? twilioSender(config.twilio) : dryRunSender();
const gc = gocardlessConfigured() ? createGoCardlessClient(config.gocardless) : null;

const wrap = (fn) => (req, res) => fn(req, res).catch((e) => {
  // Intentional 4xx errors carry a safe, user-facing message.
  if (e.status && e.status < 500) return res.status(e.status).json({ error: e.message });
  console.error(e); // full detail server-side only
  res.status(500).json({ error: 'Serverfehler. Bitte später erneut.' }); // generic to client
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
app.post('/auth/signup', authLimiter, authRoute((email, password) => auth.signup(email, password)));
app.post('/auth/login', authLimiter, authRoute((email, password) => auth.login(email, password)));
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
  res.json({ ...userData.getProfile(req.userId), verifiedPhones: userData.getVerifiedPhones(req.userId) });
});
app.put('/me/profile', requireAuth, (req, res) => {
  res.json(userData.setProfile(req.userId, req.body || {}));
});
app.get('/me/alerts', requireAuth, (req, res) => {
  res.json({ alerts: userData.getAlerts(req.userId) });
});

// ── Contact phone verification (abuse prevention) ─────────────────────────────
// A number only ever receives alerts after its owner proved control via SMS code.
app.post('/me/verify-phone/request', requireAuth, outboundLimiter, wrap(async (req, res) => {
  const phone = req.body?.phone;
  const code = phoneVerify.requestCode(req.userId, phone, Date.now());
  await sender.sms(phone, `HALT-Bestätigungscode: ${code}. Gilt 10 Minuten.`);
  // In DRY_RUN (no Twilio yet) return the code so the flow is testable in-app.
  res.json({ sent: true, dryRun: isDryRun(), ...(isDryRun() ? { devCode: code } : {}) });
}));

app.post('/me/verify-phone/confirm', requireAuth, wrap(async (req, res) => {
  phoneVerify.verifyCode(req.userId, req.body?.phone, req.body?.code, Date.now());
  userData.markPhoneVerified(req.userId, req.body?.phone);
  res.json({ verified: true });
}));

// Where THIS user's alerts go: their own first trusted contact, else the
// operator's ALERT_PHONE fallback. (On a Twilio trial the number must be verified.)
const destFor = (uid) => userData.alertPhone(uid) || config.alertPhone || null;

// Prove the alarm path works — rings the user's own trusted contact.
// Message is fixed server-side (not client-controlled) to prevent abuse.
app.post('/test-alert', requireAuth, outboundLimiter, wrap(async (req, res) => {
  const to = destFor(req.userId);
  if (!to) return res.status(400).json({ error: 'Keine Zielnummer: trag eine Vertrauensperson ein (oder ALERT_PHONE).' });
  const message = 'Test von HALT: Wenn du das bekommst, funktioniert dein Alarm.';
  const results = {};
  if (config.alertChannel !== 'call') results.sms = await sender.sms(to, message);
  if (config.alertChannel !== 'sms') results.call = await sender.call(to, message);
  res.json({ sent: true, dryRun: isDryRun(), to, results });
}));

// Full alert path on the seed history (includes an ongoing crypto scam).
app.post('/demo-scan', requireAuth, outboundLimiter, wrap(async (req, res) => {
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

app.post('/scan/:accountId', requireAuth, outboundLimiter, wrap(async (req, res) => {
  if (!gc) return res.status(400).json({ error: 'GoCardless nicht konfiguriert' });
  const accountId = req.params.accountId;
  if (!UUID_RE.test(accountId)) return res.status(400).json({ error: 'Ungültige Konto-ID.' });
  // Authorize: the account must belong to THIS user's own requisition (no IDOR).
  const reqId = userData.getRequisition(req.userId);
  if (!reqId) return res.status(403).json({ error: 'Kein verbundenes Konto.' });
  const requisition = await gc.getRequisition(reqId);
  if (!(requisition.accounts || []).includes(accountId)) {
    return res.status(403).json({ error: 'Kein Zugriff auf dieses Konto.' });
  }
  const raw = await gc.getTransactions(accountId);
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
