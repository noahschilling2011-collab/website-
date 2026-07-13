import { describe, it, expect } from 'vitest';
import * as auth from './service.js';
import { totpNow } from './crypto.js';

const ctx = { ip: '1.2.3.4', device: 'Testgerät', userAgent: 'test' };

function unique() {
  return `u${Math.floor(performance.now() * 1000)}${Math.round(performance.timeOrigin)}@test.de`;
}

describe('Registrierung & Login', () => {
  it('registriert und liefert Tokens', () => {
    const r = auth.register({ email: unique(), password: 'geheim12345', name: 'Test' }, ctx);
    expect(r.tokens.accessToken.split('.')).toHaveLength(3);
    expect(r.user.name).toBe('Test');
  });

  it('lehnt zu kurze Passwörter und Doppel-Registrierung ab', () => {
    const email = unique();
    auth.register({ email, password: 'langgenug1' }, ctx);
    expect(() => auth.register({ email, password: 'x' }, ctx)).toThrow();
    expect(() => auth.register({ email, password: 'langgenug1' }, ctx)).toThrow(/registriert/);
  });

  it('sperrt das Konto nach zu vielen Fehlversuchen', () => {
    const email = unique();
    auth.register({ email, password: 'richtigesPW1' }, ctx);
    for (let i = 0; i < 4; i++) expect(() => auth.login({ email, password: 'falsch' }, ctx)).toThrow(/falsch/);
    // 5. Fehlversuch -> Sperre
    expect(() => auth.login({ email, password: 'falsch' }, ctx)).toThrow(/gesperrt/);
    // auch korrektes PW wird nun abgewiesen
    expect(() => auth.login({ email, password: 'richtigesPW1' }, ctx)).toThrow(/gesperrt/);
  });
});

describe('Refresh-Rotation & Reuse-Detection', () => {
  it('rotiert Refresh-Token und erkennt Wiederverwendung', () => {
    const email = unique();
    const r = auth.register({ email, password: 'rotationTest1' }, ctx);
    const first = r.tokens.refreshToken;
    const rotated = auth.refresh(first, ctx); // gibt neues Token
    expect(rotated.refreshToken).not.toBe(first);
    // altes Token erneut nutzen -> Reuse -> Fehler + Sitzung gesperrt
    expect(() => auth.refresh(first, ctx)).toThrow(/ungültig/);
    // auch das rotierte Token ist jetzt ungültig (Familie gesperrt)
    expect(() => auth.refresh(rotated.refreshToken, ctx)).toThrow(/ungültig/);
  });
});

describe('Zwei-Faktor (TOTP)', () => {
  it('verlangt nach Aktivierung einen 2FA-Code beim Login', () => {
    const email = unique();
    const r = auth.register({ email, password: 'zweiFaktor12' }, ctx);
    const { secret } = auth.enroll2FA(r.user.id);
    const enabled = auth.enable2FA(r.user.id, totpNow(secret));
    expect(enabled.backupCodes.length).toBeGreaterThan(0);

    // Login ohne Code -> 2fa_required
    const step1 = auth.login({ email, password: 'zweiFaktor12' }, ctx);
    expect(step1.status).toBe('2fa_required');
    // Login mit gültigem Code -> ok
    const step2 = auth.login({ email, password: 'zweiFaktor12', totp: totpNow(secret) }, ctx);
    expect(step2.status).toBe('ok');
  });
});

describe('Geräte & Fernabmeldung', () => {
  it('listet Sitzungen und meldet sie aus der Ferne ab', () => {
    const email = unique();
    const r = auth.register({ email, password: 'geraeteTest1' }, ctx);
    auth.login({ email, password: 'geraeteTest1', ...{} }, { ...ctx, device: 'Zweitgerät' });
    const list = auth.listSessions(r.user.id);
    expect(list.length).toBeGreaterThanOrEqual(2);
    auth.revokeSession(r.user.id, list[0].id, ctx);
    expect(auth.listSessions(r.user.id).length).toBe(list.length - 1);
  });
});
