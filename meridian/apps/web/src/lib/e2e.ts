// Ende-zu-Ende-Verschlüsselung für sensible Daten (z. B. Zuhause/Arbeit).
// Schlüssel wird aus einer Passphrase via PBKDF2 abgeleitet und verlässt NIE das
// Gerät. Der Server speichert ausschließlich das AES-256-GCM-Chiffrat.
const enc = new TextEncoder();
const dec = new TextDecoder();

async function deriveKey(passphrase: string, salt: Uint8Array): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey('raw', enc.encode(passphrase) as BufferSource, 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: salt as BufferSource, iterations: 210_000, hash: 'SHA-256' },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

function b64(buf: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf)));
}
function unb64(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

// Gibt ein transportierbares Chiffrat zurück (salt.iv.data, base64).
export async function encryptJSON(passphrase: string, data: unknown): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt);
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv as BufferSource }, key, enc.encode(JSON.stringify(data)) as BufferSource);
  return `${b64(salt.buffer)}.${b64(iv.buffer)}.${b64(ct)}`;
}

export async function decryptJSON<T>(passphrase: string, blob: string): Promise<T> {
  const [s, i, c] = blob.split('.');
  const key = await deriveKey(passphrase, unb64(s));
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(i) as BufferSource }, key, unb64(c) as BufferSource);
  return JSON.parse(dec.decode(pt)) as T;
}
