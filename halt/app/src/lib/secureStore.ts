// Thin, typed wrapper over expo-secure-store.
//
// SecureStore is backed by the iOS Keychain and Android Keystore (hardware-backed
// where available). We store ONLY small secrets here: the PIN hash/salt, the
// lockout state, and the session token. Bulk data (transactions) is never written
// to disk in the MVP — see SECURITY.md for the encrypted-persistence plan.
//
// On web, SecureStore is unavailable; we fall back to an in-memory map so the app
// still runs in a browser for demos (clearly NOT secure — web is demo-only).

import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';

const memoryFallback = new Map<string, string>();
const isWeb = Platform.OS === 'web';

export const KEYS = {
  pinHash: 'halt.pin.hash',
  pinSalt: 'halt.pin.salt',
  lockState: 'halt.lock.state',
  session: 'halt.session',
  credential: 'halt.credential', // local demo auth only
} as const;

export async function setItem(key: string, value: string): Promise<void> {
  if (isWeb) {
    memoryFallback.set(key, value);
    return;
  }
  await SecureStore.setItemAsync(key, value, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  });
}

export async function getItem(key: string): Promise<string | null> {
  if (isWeb) return memoryFallback.get(key) ?? null;
  return SecureStore.getItemAsync(key);
}

export async function deleteItem(key: string): Promise<void> {
  if (isWeb) {
    memoryFallback.delete(key);
    return;
  }
  await SecureStore.deleteItemAsync(key);
}

export async function setJSON(key: string, value: unknown): Promise<void> {
  await setItem(key, JSON.stringify(value));
}

export async function getJSON<T>(key: string): Promise<T | null> {
  const raw = await getItem(key);
  if (raw == null) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

/** Wipe every HALT secret — used on full logout / lockout reset / account delete. */
export async function wipeAll(): Promise<void> {
  await Promise.all(Object.values(KEYS).map((k) => deleteItem(k)));
}
