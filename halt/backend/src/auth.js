// Real account sign-up / login — server-side, so registering "in the app" creates
// a genuine account that works across devices.
//
// Passwords are hashed with scrypt (memory-hard) + a per-user salt, and only the
// hash is stored — never the password. Login issues an opaque bearer token.
// Users persist to a JSON file; tokens live in memory (a restart just requires
// re-login). Swap the file store for Postgres/Supabase when you outgrow one box.

import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function validate(email, password) {
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim())) {
    throw httpError(400, 'Bitte eine gültige E-Mail eingeben.');
  }
  if (!password || password.length < 10) throw httpError(400, 'Passwort: mindestens 10 Zeichen.');
  if (!/[a-zA-Z]/.test(password) || !/[0-9]/.test(password)) {
    throw httpError(400, 'Passwort braucht mindestens einen Buchstaben und eine Zahl.');
  }
}

function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  const [salt, hash] = String(stored).split(':');
  if (!salt || !hash) return false;
  const expected = Buffer.from(hash, 'hex');
  const actual = scryptSync(password, salt, 64);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export function createAuth(usersPath) {
  let users = {};
  if (usersPath && existsSync(usersPath)) {
    try {
      users = JSON.parse(readFileSync(usersPath, 'utf8'));
    } catch {
      users = {};
    }
  }
  const tokens = new Map(); // token -> email

  const persist = () => {
    if (!usersPath) return;
    mkdirSync(dirname(usersPath), { recursive: true });
    writeFileSync(usersPath, JSON.stringify(users, null, 2));
  };
  const issueToken = (email) => {
    const token = randomBytes(32).toString('hex');
    tokens.set(token, email);
    return token;
  };

  return {
    signup(email, password) {
      validate(email, password);
      const key = email.trim().toLowerCase();
      if (users[key]) throw httpError(409, 'Diese E-Mail ist bereits registriert.');
      users[key] = { passwordHash: hashPassword(password) };
      persist();
      return { email: key, token: issueToken(key) };
    },

    login(email, password) {
      const key = String(email || '').trim().toLowerCase();
      const user = users[key];
      // Verify even when the user is missing, to avoid a timing oracle.
      const ok = user
        ? verifyPassword(password, user.passwordHash)
        : verifyPassword(password, `${'0'.repeat(32)}:${'0'.repeat(128)}`) && false;
      if (!ok) throw httpError(401, 'E-Mail oder Passwort ist falsch.');
      return { email: key, token: issueToken(key) };
    },

    verify(token) {
      return tokens.get(token) || null;
    },

    logout(token) {
      tokens.delete(token);
    },

    /** Number of registered users — handy for /health. */
    count() {
      return Object.keys(users).length;
    },
  };
}
