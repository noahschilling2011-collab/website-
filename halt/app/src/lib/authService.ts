// Account authentication — an abstraction with a swappable backend.
//
// ┌─ MVP (this file): a LOCAL demo implementation so the whole flow runs offline.
// │  Credentials are salted-hashed and kept in the keychain. This is fine for a
// │  demo, but the client is NOT the authority.
// └─ PRODUCTION: replace `localAuthProvider` with `supabaseAuthProvider`
//    (see the commented stub). Then passwords are hashed server-side with a
//    memory-hard KDF, sessions are real JWTs, and email is verified. See SECURITY.md.
//
// Either way the app only ever holds an opaque session token, never the password.

import * as Crypto from 'expo-crypto';
import { KEYS, getJSON, setJSON, getItem, setItem, deleteItem } from './secureStore';
import { hashSecret, verifySecret, type Sha256Hex } from './hash';
import { validateEmail, validatePassword } from './validation';

const sha256: Sha256Hex = (input) =>
  Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, input);

export interface Session {
  email: string;
  token: string;
  issuedAt: number;
}

export interface AuthResult {
  ok: boolean;
  session?: Session;
  error?: string;
}

export interface AuthProvider {
  signUp(email: string, password: string, now: number): Promise<AuthResult>;
  signIn(email: string, password: string, now: number): Promise<AuthResult>;
  signOut(): Promise<void>;
  currentSession(): Promise<Session | null>;
}

function randomToken(): string {
  const bytes = Crypto.getRandomBytes(32);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

interface StoredCredential {
  email: string;
  salt: string;
  hash: string;
}

// ── Local demo provider ──────────────────────────────────────────────────────
const localAuthProvider: AuthProvider = {
  async signUp(email, password, now) {
    const e = validateEmail(email);
    if (!e.ok) return { ok: false, error: e.error };
    const p = validatePassword(password);
    if (!p.ok) return { ok: false, error: p.error };

    const salt = Array.from(Crypto.getRandomBytes(16), (b) =>
      b.toString(16).padStart(2, '0'),
    ).join('');
    const hash = await hashSecret(password, salt, sha256);
    const cred: StoredCredential = { email: email.trim().toLowerCase(), salt, hash };
    await setJSON(KEYS.credential, cred);

    const session: Session = { email: cred.email, token: randomToken(), issuedAt: now };
    await setJSON(KEYS.session, session);
    return { ok: true, session };
  },

  async signIn(email, password, now) {
    const cred = await getJSON<StoredCredential>(KEYS.credential);
    // Constant-ish response regardless of whether the account exists.
    if (!cred || cred.email !== email.trim().toLowerCase()) {
      // still spend a hash to avoid a trivial timing oracle
      await hashSecret(password, 'decoy-salt', sha256);
      return { ok: false, error: 'E-Mail oder Passwort ist falsch.' };
    }
    const matches = await verifySecret(password, cred.salt, cred.hash, sha256);
    if (!matches) return { ok: false, error: 'E-Mail oder Passwort ist falsch.' };

    const session: Session = { email: cred.email, token: randomToken(), issuedAt: now };
    await setJSON(KEYS.session, session);
    return { ok: true, session };
  },

  async signOut() {
    await deleteItem(KEYS.session);
  },

  async currentSession() {
    return getJSON<Session>(KEYS.session);
  },
};

// ── Production provider (integration point) ──────────────────────────────────
//
// import { createClient } from '@supabase/supabase-js';
// const supabase = createClient(URL, ANON_KEY);   // anon key only; RLS enforced server-side
// export const supabaseAuthProvider: AuthProvider = {
//   async signUp(email, password) { const { data, error } = await supabase.auth.signUp({ email, password }); ... },
//   async signIn(email, password) { const { data, error } = await supabase.auth.signInWithPassword({ email, password }); ... },
//   async signOut() { await supabase.auth.signOut(); },
//   async currentSession() { const { data } = await supabase.auth.getSession(); ... },
// };

export const auth: AuthProvider = localAuthProvider;
