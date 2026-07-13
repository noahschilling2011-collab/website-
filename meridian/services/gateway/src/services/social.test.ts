import { describe, it, expect } from 'vitest';
import * as auth from '../auth/service.js';
import * as social from './social.js';

const ctx = { ip: '1.1.1.1', device: 'Test', userAgent: 't' };
let n = 0;
const email = () => `s${++n}_${Math.round(performance.now())}@t.de`;

describe('Freunde & Live-Sharing', () => {
  it('Freundschaftsanfrage, Annahme und Live-Position-Broadcast', () => {
    const a = auth.register({ email: email(), password: 'passwort123', name: 'Anna' }, ctx).user;
    const bEmail = email();
    const b = auth.register({ email: bEmail, password: 'passwort123', name: 'Ben' }, ctx).user;

    const req = social.requestFriend(a.id, bEmail);
    expect(req.status).toBe('sent');
    expect(social.incomingRequests(b.id)).toHaveLength(1);
    expect(social.acceptFriend(b.id, req.requestId!).ok).toBe(true);

    // Ben abonniert; Anna sendet Position -> Ben empfängt sie
    const received: unknown[] = [];
    const unsub = social.subscribe(b.id, (event, data) => event === 'position' && received.push(data));
    social.updatePosition(a.id, 48.1, 11.5);
    unsub();
    expect(received).toHaveLength(1);
    expect((received[0] as { name: string }).name).toBe('Anna');
  });

  it('Standortfreigabe per Link ist öffentlich abrufbar', () => {
    const a = auth.register({ email: email(), password: 'passwort123', name: 'Cara' }, ctx).user;
    social.updatePosition(a.id, 52.5, 13.4);
    const share = social.startShare(a.id, 30);
    expect(share.code).toBeTruthy();
    const view = social.viewShare(share.code);
    expect(view?.name).toBe('Cara');
    expect(view?.position?.lat).toBeCloseTo(52.5, 3);
    // nach Stopp nicht mehr abrufbar
    social.stopShare(a.id);
    expect(social.viewShare(share.code)).toBeNull();
  });
});
