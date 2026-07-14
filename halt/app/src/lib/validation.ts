// Input validation — pure, deterministic, testable.
// First line of defence: never trust input, reject early, give clear feedback.

export interface FieldResult {
  ok: boolean;
  /** Human-readable, plain German — shown directly to the user. */
  error?: string;
}

const ok: FieldResult = { ok: true };

/** RFC-5322-lite: good enough to catch typos, not a substitute for a verify email. */
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function validateEmail(value: string): FieldResult {
  const v = value.trim();
  if (!v) return { ok: false, error: 'Bitte E-Mail-Adresse eingeben.' };
  if (v.length > 254) return { ok: false, error: 'E-Mail-Adresse ist zu lang.' };
  if (!EMAIL_RE.test(v)) return { ok: false, error: 'Das sieht nicht wie eine gültige E-Mail aus.' };
  return ok;
}

/**
 * Password policy for the account login. Length is the dominant factor, so we
 * require a real minimum and reward length rather than demanding a zoo of
 * symbols that pushes people to "Passwort1!".
 */
export function validatePassword(value: string): FieldResult {
  if (value.length < 10) return { ok: false, error: 'Mindestens 10 Zeichen.' };
  if (value.length > 128) return { ok: false, error: 'Höchstens 128 Zeichen.' };
  if (!/[a-zA-Z]/.test(value)) return { ok: false, error: 'Mindestens ein Buchstabe.' };
  if (!/[0-9]/.test(value)) return { ok: false, error: 'Mindestens eine Zahl.' };
  if (/^(.)\1+$/.test(value)) return { ok: false, error: 'Kein sinnvolles Passwort.' };
  return ok;
}

/** A 6-digit device PIN for the quick app-lock (defended by lockout + secure enclave). */
export function validatePin(value: string): FieldResult {
  if (!/^\d{6}$/.test(value)) return { ok: false, error: 'Der PIN muss aus 6 Ziffern bestehen.' };
  if (/^(\d)\1{5}$/.test(value)) return { ok: false, error: 'Keine 6 gleichen Ziffern.' };
  if (value === '123456' || value === '654321') return { ok: false, error: 'Zu leicht zu erraten.' };
  return ok;
}

/** Loosely validate a phone number (E.164-ish). Kept permissive on formatting. */
export function validatePhone(value: string): FieldResult {
  const v = value.replace(/[\s\-()/]/g, '');
  if (!v) return { ok: false, error: 'Bitte Telefonnummer eingeben.' };
  if (!/^\+?\d{6,15}$/.test(v)) return { ok: false, error: 'Bitte eine gültige Telefonnummer eingeben.' };
  return ok;
}

/** Strip control characters and clamp length — for any free-text we store/display. */
export function sanitizeText(value: string, maxLen = 500): string {
  // eslint-disable-next-line no-control-regex
  return value.replace(/[\x00-\x1F\x7F]/g, '').trim().slice(0, maxLen);
}
