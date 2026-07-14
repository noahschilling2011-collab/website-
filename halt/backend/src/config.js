// Central config — reads everything from the environment. No secrets in code.
// If Twilio credentials are missing, the backend runs in DRY_RUN: it does all
// the logic and LOGS what it would send, instead of calling out. That keeps the
// whole thing runnable (and testable) without any accounts.

import 'dotenv/config';

const e = process.env;

export const config = {
  port: Number.parseInt(e.PORT ?? '8080', 10),

  twilio: {
    accountSid: e.TWILIO_ACCOUNT_SID || '',
    authToken: e.TWILIO_AUTH_TOKEN || '',
    from: e.TWILIO_FROM || '', // your Twilio number, e.g. +49...
  },

  gocardless: {
    secretId: e.GOCARDLESS_SECRET_ID || '',
    secretKey: e.GOCARDLESS_SECRET_KEY || '',
    // Fixed test bank with fake data — use this to test end-to-end safely.
    institutionId: e.GOCARDLESS_INSTITUTION_ID || 'SANDBOXFINANCE_SFIN0000',
    redirectUrl: e.GOCARDLESS_REDIRECT_URL || 'http://localhost:8080/connect/callback',
    country: e.GOCARDLESS_COUNTRY || 'DE',
  },

  // Where alerts go. Your OWN (verified) number for testing.
  alertPhone: e.ALERT_PHONE || '',

  // Notify channel: 'sms', 'call', or 'both'.
  alertChannel: (e.ALERT_CHANNEL || 'both').toLowerCase(),
};

export const twilioConfigured = () =>
  Boolean(config.twilio.accountSid && config.twilio.authToken && config.twilio.from && config.alertPhone);

export const gocardlessConfigured = () =>
  Boolean(config.gocardless.secretId && config.gocardless.secretKey);

/** DRY_RUN when we can't actually send — logic still runs, nothing goes out. */
export const isDryRun = () => !twilioConfigured();
