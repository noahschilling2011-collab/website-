// Auth + app-lock state, kept separate from the domain data store.

import { create } from 'zustand';
import { auth, type Session } from '../lib/authService';
import { isPinSet, clearPin } from '../lib/appLock';
import { wipeAll } from '../lib/secureStore';

interface SessionState {
  bootstrapped: boolean;
  session: Session | null;
  pinEnabled: boolean;
  /** True when a PIN is set and the app currently needs unlocking. */
  locked: boolean;

  bootstrap: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<string | null>;
  signUp: (email: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;

  refreshPinState: () => Promise<void>;
  lock: () => void;
  unlock: () => void;
  /** Full local wipe (logout everywhere / account deletion). */
  wipe: () => Promise<void>;
}

const now = () => new Date().getTime();

export const useSession = create<SessionState>((set, get) => ({
  bootstrapped: false,
  session: null,
  pinEnabled: false,
  locked: false,

  bootstrap: async () => {
    const session = await auth.currentSession();
    const pinEnabled = await isPinSet();
    set({
      bootstrapped: true,
      session,
      pinEnabled,
      // If a PIN exists, start locked — the user must unlock on every cold start.
      locked: !!session && pinEnabled,
    });
  },

  signIn: async (email, password) => {
    const res = await auth.signIn(email, password, now());
    if (!res.ok) return res.error ?? 'Anmeldung fehlgeschlagen.';
    const pinEnabled = await isPinSet();
    set({ session: res.session!, pinEnabled, locked: pinEnabled });
    return null;
  },

  signUp: async (email, password) => {
    const res = await auth.signUp(email, password, now());
    if (!res.ok) return res.error ?? 'Registrierung fehlgeschlagen.';
    set({ session: res.session!, pinEnabled: false, locked: false });
    return null;
  },

  signOut: async () => {
    await auth.signOut();
    set({ session: null, locked: false });
  },

  refreshPinState: async () => set({ pinEnabled: await isPinSet() }),

  lock: () => {
    if (get().pinEnabled && get().session) set({ locked: true });
  },
  unlock: () => set({ locked: false }),

  wipe: async () => {
    await clearPin();
    await wipeAll();
    set({ session: null, pinEnabled: false, locked: false });
  },
}));
