// Phone-number verification: before a number can receive alerts, its owner must
// prove they control it by entering a 6-digit code sent via SMS.
//
// This closes the last abuse path (alerting arbitrary strangers' phones) and is
// pure/injectable: the RNG and clock come in from outside, so it's fully testable.

const CODE_TTL_MS = 10 * 60 * 1000; // 10 minutes
const MAX_ATTEMPTS = 5;             // wrong tries per code
const RESEND_COOLDOWN_MS = 60 * 1000; // min gap between code sends per user+phone
const MAX_SENDS_PER_DAY = 5;        // per user+phone

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

/** Normalise a phone number for keying: strip spaces/dashes/parens. */
export function normalizePhone(phone) {
  return String(phone || '').replace(/[\s\-()/]/g, '');
}

export function isValidPhone(phone) {
  return /^\+?\d{6,15}$/.test(normalizePhone(phone));
}

export function createPhoneVerify({ random6 } = {}) {
  // random6: () => '000000'..'999999' — injectable for tests.
  const gen = random6 || (() => String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0'));
  // key: `${userId}|${phone}` -> { code, exp, attempts, lastSent, sends: [timestamps] }
  const pending = new Map();

  const keyOf = (uid, phone) => `${uid}|${normalizePhone(phone)}`;

  return {
    /** Create a code to send. Throws on cooldown/quota. Returns the code. */
    requestCode(uid, phone, now) {
      if (!isValidPhone(phone)) throw httpError(400, 'Ungültige Telefonnummer.');
      const key = keyOf(uid, phone);
      const rec = pending.get(key);
      if (rec && now - rec.lastSent < RESEND_COOLDOWN_MS) {
        throw httpError(429, 'Bitte kurz warten, bevor du einen neuen Code anforderst.');
      }
      const sends = (rec?.sends || []).filter((t) => now - t < 24 * 3600 * 1000);
      if (sends.length >= MAX_SENDS_PER_DAY) {
        throw httpError(429, 'Tageslimit für Codes erreicht. Bitte morgen erneut.');
      }
      const code = gen();
      pending.set(key, { code, exp: now + CODE_TTL_MS, attempts: 0, lastSent: now, sends: [...sends, now] });
      return code;
    },

    /** Check a code. Returns true once; consumes the code on success. */
    verifyCode(uid, phone, code, now) {
      const key = keyOf(uid, phone);
      const rec = pending.get(key);
      if (!rec) throw httpError(400, 'Kein Code angefordert oder bereits verwendet.');
      if (now > rec.exp) {
        pending.delete(key);
        throw httpError(400, 'Der Code ist abgelaufen. Fordere einen neuen an.');
      }
      rec.attempts += 1;
      if (rec.attempts > MAX_ATTEMPTS) {
        pending.delete(key);
        throw httpError(429, 'Zu viele Fehlversuche. Fordere einen neuen Code an.');
      }
      if (String(code).trim() !== rec.code) {
        throw httpError(400, 'Falscher Code.');
      }
      pending.delete(key); // single-use
      return true;
    },
  };
}
