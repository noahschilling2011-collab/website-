// Hashing helpers for the local PIN / credential store.
//
// The actual digest is injected (expo-crypto at runtime, node:crypto in tests)
// so the composition logic is pure and verifiable. We deliberately do NOT roll
// our own primitive: we build a salted input and hand it to a vetted SHA-256.
//
// IMPORTANT: this protects a LOCAL device secret only. Account passwords must be
// hashed server-side with a memory-hard KDF (Argon2id / scrypt / bcrypt) — the
// client is never the authority. See SECURITY.md.

export type Sha256Hex = (input: string) => Promise<string>;

const VERSION = 'halt$v1';

/** Deterministic, collision-resistant salted input for the digest. */
export function buildSaltedInput(salt: string, secret: string): string {
  return `${VERSION}$${salt}$${secret}`;
}

/** Hash a secret with a per-secret salt using the injected digest. */
export async function hashSecret(
  secret: string,
  salt: string,
  sha256: Sha256Hex,
): Promise<string> {
  return sha256(buildSaltedInput(salt, secret));
}

/**
 * Constant-time string comparison — avoids leaking how many leading characters
 * matched via timing. Length is allowed to differ (hashes are fixed-length).
 */
export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** Verify a candidate secret against a stored salt+hash. */
export async function verifySecret(
  candidate: string,
  salt: string,
  expectedHash: string,
  sha256: Sha256Hex,
): Promise<boolean> {
  const actual = await hashSecret(candidate, salt, sha256);
  return constantTimeEqual(actual, expectedHash);
}
