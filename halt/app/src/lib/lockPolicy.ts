// Brute-force lockout policy for the app PIN — pure and testable.
//
// A 6-digit PIN has only a million combinations, so the KDF is NOT what protects
// it. The real defence is: (1) the hash lives in the hardware keychain, and
// (2) this escalating lockout makes online guessing hopeless. After too many
// failures we wipe the local secret and fall back to full account login.

export interface LockState {
  failedAttempts: number;
  /** Epoch ms until which entry is blocked, or null if not currently blocked. */
  lockedUntil: number | null;
}

export const FREE_ATTEMPTS = 3;
export const MAX_ATTEMPTS = 10;

export const EMPTY_LOCK_STATE: LockState = { failedAttempts: 0, lockedUntil: null };

/** Escalating backoff once the free attempts are used up. */
export function backoffMs(failedAttempts: number): number {
  if (failedAttempts <= FREE_ATTEMPTS) return 0;
  const step = failedAttempts - FREE_ATTEMPTS; // 1, 2, 3, ...
  const schedule = [30_000, 60_000, 300_000, 900_000]; // 30s, 1m, 5m, 15m
  return schedule[Math.min(step - 1, schedule.length - 1)];
}

export interface Gate {
  allowed: boolean;
  /** ms the user must still wait before another attempt. */
  remainingMs: number;
  /** True once the local PIN must be wiped and the user sent to full login. */
  mustReset: boolean;
}

export function evaluate(state: LockState, now: number): Gate {
  if (state.failedAttempts >= MAX_ATTEMPTS) {
    return { allowed: false, remainingMs: 0, mustReset: true };
  }
  if (state.lockedUntil && now < state.lockedUntil) {
    return { allowed: false, remainingMs: state.lockedUntil - now, mustReset: false };
  }
  return { allowed: true, remainingMs: 0, mustReset: false };
}

export function registerFailure(state: LockState, now: number): LockState {
  const failedAttempts = state.failedAttempts + 1;
  const wait = backoffMs(failedAttempts);
  return { failedAttempts, lockedUntil: wait > 0 ? now + wait : null };
}

export function registerSuccess(): LockState {
  return { ...EMPTY_LOCK_STATE };
}
