import { describe, it, expect } from 'vitest';
import {
  hashPassword,
  verifyPassword,
  signJwt,
  verifyJwt,
  generateTotpSecret,
  totpNow,
  verifyTotp,
  otpauthUri,
} from './crypto.js';

describe('Passwort-Hashing (scrypt)', () => {
  it('verifiziert korrektes Passwort und lehnt falsches ab', () => {
    const stored = hashPassword('Sup3r-Geheim!');
    expect(verifyPassword('Sup3r-Geheim!', stored)).toBe(true);
    expect(verifyPassword('falsch', stored)).toBe(false);
  });
  it('erzeugt unterschiedliche Hashes (Salt)', () => {
    expect(hashPassword('x')).not.toBe(hashPassword('x'));
  });
});

describe('JWT (HS256)', () => {
  it('signiert und verifiziert', () => {
    const t = signJwt({ sub: 'u1', typ: 'access' }, 'secret', 60);
    const p = verifyJwt(t, 'secret');
    expect(p?.sub).toBe('u1');
    expect(p?.typ).toBe('access');
  });
  it('lehnt manipulierte/falsch signierte Token ab', () => {
    const t = signJwt({ sub: 'u1' }, 'secret', 60);
    expect(verifyJwt(t, 'anderes-secret')).toBeNull();
    expect(verifyJwt(t + 'x', 'secret')).toBeNull();
  });
  it('lehnt abgelaufene Token ab', () => {
    const t = signJwt({ sub: 'u1' }, 'secret', -1);
    expect(verifyJwt(t, 'secret')).toBeNull();
  });
});

describe('TOTP (RFC 6238)', () => {
  it('verifiziert den aktuellen Code', () => {
    const secret = generateTotpSecret();
    expect(verifyTotp(secret, totpNow(secret))).toBe(true);
  });
  it('lehnt falschen Code ab', () => {
    const secret = generateTotpSecret();
    expect(verifyTotp(secret, '000000')).toBe(totpNow(secret) === '000000'); // praktisch false
  });
  it('otpauth-URI enthält Secret und Issuer', () => {
    const secret = generateTotpSecret();
    const uri = otpauthUri(secret, 'a@b.de', 'Meridian');
    expect(uri).toContain('otpauth://totp/');
    expect(uri).toContain(secret);
    expect(uri).toContain('Meridian');
  });
});
