// Tiny file-backed set for "already alerted" transaction ids, so a re-scan does
// not call the trusted person twice for the same movement. Good enough for the
// MVP; swap for Postgres/Supabase when there is more than one user.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export function fileSeenStore(path) {
  let set = new Set();
  if (existsSync(path)) {
    try {
      set = new Set(JSON.parse(readFileSync(path, 'utf8')));
    } catch {
      set = new Set();
    }
  }
  const persist = () => {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify([...set]));
  };
  return {
    has: (k) => set.has(k),
    add: (k) => {
      set.add(k);
      persist();
    },
  };
}

/** In-memory store for tests. */
export function memorySeenStore() {
  const set = new Set();
  return { has: (k) => set.has(k), add: (k) => set.add(k) };
}
