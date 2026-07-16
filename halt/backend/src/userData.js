// Per-user data store — the heart of row-level security.
//
// Every slice of data (the protected person, the trusted contacts, the seen
// set, the alerts) is keyed by userId. The server ALWAYS derives userId from the
// caller's verified token, never from the request body — so one user can never
// read or write another user's rows. File-backed for the MVP; the same interface
// maps directly onto a Postgres table with an RLS policy later.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

function emptyUser() {
  return { profile: { person: null, contacts: [] }, requisitionId: null, seen: [], alerts: [], verifiedPhones: [] };
}

const normPhone = (p) => String(p || '').replace(/[\s\-()/]/g, '');

export function createUserData(path) {
  let db = {};
  if (path && existsSync(path)) {
    try {
      db = JSON.parse(readFileSync(path, 'utf8'));
    } catch {
      db = {};
    }
  }
  const persist = () => {
    if (!path) return;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(db, null, 2));
  };
  const row = (uid) => {
    if (!db[uid]) db[uid] = emptyUser();
    return db[uid];
  };

  return {
    getProfile: (uid) => row(uid).profile,

    setProfile: (uid, profile) => {
      const r = row(uid);
      r.profile = {
        person: profile?.person ?? null,
        contacts: Array.isArray(profile?.contacts) ? profile.contacts : [],
      };
      persist();
      return r.profile;
    },

    /** First VERIFIED trusted contact's phone — where this user's alerts go.
     *  Unverified numbers never receive anything (abuse prevention). */
    alertPhone: (uid) => {
      const r = row(uid);
      const verified = new Set((r.verifiedPhones || []).map(normPhone));
      const hit = (r.profile.contacts || []).find((c) => verified.has(normPhone(c.phone)));
      return hit?.phone || null;
    },

    markPhoneVerified: (uid, phone) => {
      const r = row(uid);
      if (!r.verifiedPhones) r.verifiedPhones = [];
      const p = normPhone(phone);
      if (!r.verifiedPhones.map(normPhone).includes(p)) {
        r.verifiedPhones.push(p);
        persist();
      }
    },

    isPhoneVerified: (uid, phone) =>
      (row(uid).verifiedPhones || []).map(normPhone).includes(normPhone(phone)),

    getVerifiedPhones: (uid) => [...(row(uid).verifiedPhones || [])],

    setRequisition: (uid, id) => {
      row(uid).requisitionId = id;
      persist();
    },
    getRequisition: (uid) => row(uid).requisitionId,

    getAlerts: (uid) => row(uid).alerts,
    setAlerts: (uid, alerts) => {
      row(uid).alerts = alerts;
      persist();
    },

    /** A seen-store scoped to one user, shaped for notify.runScan(). */
    seenStore: (uid) => ({
      has: (k) => row(uid).seen.includes(k),
      add: (k) => {
        const r = row(uid);
        if (!r.seen.includes(k)) {
          r.seen.push(k);
          persist();
        }
      },
    }),

    /** Total users with data — for diagnostics only. */
    count: () => Object.keys(db).length,
  };
}
