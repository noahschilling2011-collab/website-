// App lock — PIN + biometric gate over the sensitive data on the device.
//
// Composes the tested pure logic (hash.ts, lockPolicy.ts) with the hardware
// keychain (secureStore) and the OS biometric prompt (expo-local-authentication).
// The salt is random per install; the PIN hash never leaves the keychain.

import * as Crypto from 'expo-crypto';
import * as LocalAuthentication from 'expo-local-authentication';

import { KEYS, getItem, setItem, getJSON, setJSON, deleteItem } from './secureStore';
import { hashSecret, verifySecret, type Sha256Hex } from './hash';
import {
  EMPTY_LOCK_STATE,
  evaluate,
  registerFailure,
  registerSuccess,
  type Gate,
  type LockState,
} from './lockPolicy';

const sha256: Sha256Hex = (input) =>
  Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, input);

function randomSalt(): string {
  const bytes = Crypto.getRandomBytes(16);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function isPinSet(): Promise<boolean> {
  return (await getItem(KEYS.pinHash)) != null;
}

/** Create (or replace) the device PIN. Assumes the PIN already passed validation. */
export async function setupPin(pin: string): Promise<void> {
  const salt = randomSalt();
  const hash = await hashSecret(pin, salt, sha256);
  await setItem(KEYS.pinSalt, salt);
  await setItem(KEYS.pinHash, hash);
  await setJSON(KEYS.lockState, EMPTY_LOCK_STATE);
}

async function loadLockState(): Promise<LockState> {
  return (await getJSON<LockState>(KEYS.lockState)) ?? { ...EMPTY_LOCK_STATE };
}

/** Whether the user is currently allowed to attempt entry (respects lockout). */
export async function currentGate(now: number): Promise<Gate> {
  return evaluate(await loadLockState(), now);
}

export interface PinAttempt {
  ok: boolean;
  gate: Gate;
}

/** Verify a PIN, updating lockout state. On too many failures, wipes the PIN. */
export async function verifyPin(pin: string, now: number): Promise<PinAttempt> {
  const state = await loadLockState();
  const gate = evaluate(state, now);
  if (!gate.allowed) {
    if (gate.mustReset) await clearPin();
    return { ok: false, gate };
  }

  const salt = (await getItem(KEYS.pinSalt)) ?? '';
  const hash = (await getItem(KEYS.pinHash)) ?? '';
  const matches = salt && hash && (await verifySecret(pin, salt, hash, sha256));

  if (matches) {
    await setJSON(KEYS.lockState, registerSuccess());
    return { ok: true, gate: { allowed: true, remainingMs: 0, mustReset: false } };
  }

  const next = registerFailure(state, now);
  await setJSON(KEYS.lockState, next);
  const nextGate = evaluate(next, now);
  if (nextGate.mustReset) await clearPin();
  return { ok: false, gate: nextGate };
}

export async function clearPin(): Promise<void> {
  await deleteItem(KEYS.pinHash);
  await deleteItem(KEYS.pinSalt);
  await deleteItem(KEYS.lockState);
}

export interface BiometricInfo {
  available: boolean;
  enrolled: boolean;
}

export async function biometricInfo(): Promise<BiometricInfo> {
  const available = await LocalAuthentication.hasHardwareAsync();
  const enrolled = await LocalAuthentication.isEnrolledAsync();
  return { available, enrolled };
}

/** Prompt Face ID / fingerprint. Returns true only on a successful match. */
export async function authenticateBiometric(): Promise<boolean> {
  const { available, enrolled } = await biometricInfo();
  if (!available || !enrolled) return false;
  const res = await LocalAuthentication.authenticateAsync({
    promptMessage: 'HALT entsperren',
    cancelLabel: 'PIN verwenden',
    disableDeviceFallback: true,
  });
  return res.success;
}
