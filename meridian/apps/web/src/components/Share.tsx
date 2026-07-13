import { useEffect, useState } from 'react';
import * as S from '../lib/social';
import { isLoggedIn } from '../lib/auth';

export function Share({ onClose, onSharingChange }: { onClose: () => void; onSharingChange: (active: boolean) => void }) {
  const [friends, setFriends] = useState<S.Person[]>([]);
  const [requests, setRequests] = useState<S.FriendRequest[]>([]);
  const [share, setShare] = useState<S.ShareInfo | null>(null);
  const [email, setEmail] = useState('');
  const [msg, setMsg] = useState('');

  const authed = isLoggedIn();

  async function load() {
    if (!authed) return;
    const [f, s] = await Promise.all([S.getFriends(), S.myShare()]);
    setFriends(f.friends);
    setRequests(f.requests);
    setShare(s.share);
    onSharingChange(Boolean(s.share));
  }
  useEffect(() => {
    load().catch(() => {});
    const t = setInterval(() => load().catch(() => {}), 5000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function addFriend() {
    const r = await S.requestFriend(email);
    setMsg(
      r.status === 'sent' ? 'Anfrage gesendet.' : r.status === 'not_found' ? 'Keine Person mit dieser E-Mail.' : r.status === 'already' ? 'Ihr seid bereits Freunde.' : 'Das bist du selbst.',
    );
    setEmail('');
    load();
  }
  async function accept(id: string) {
    await S.acceptFriend(id);
    load();
  }
  async function toggleShare() {
    if (share) {
      await S.stopShare();
      setShare(null);
      onSharingChange(false);
    } else {
      const s = await S.startShare(60);
      setShare(s);
      onSharingChange(true);
    }
  }

  if (!authed) {
    return (
      <div className="modal-backdrop" onClick={onClose}>
        <div className="modal" onClick={(e) => e.stopPropagation()}>
          <div className="modal-head"><strong>Teilen & Freunde</strong><button onClick={onClose}>✕</button></div>
          <div className="modal-body"><p className="dim">Bitte zuerst anmelden, um Standort zu teilen und Freunde hinzuzufügen.</p></div>
        </div>
      </div>
    );
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head"><strong>Teilen & Freunde</strong><button onClick={onClose}>✕</button></div>
        <div className="modal-body">
          <div className={share ? 'share-box on' : 'share-box'}>
            <div className="row2">
              <span><strong>Live-Standort teilen</strong></span>
              <button className={share ? 'switch on' : 'switch'} onClick={toggleShare}><span className="knob" /></button>
            </div>
            {share && (
              <div className="share-active">
                <p className="small dim">Jeder mit diesem Link sieht deinen Standort live (bis {new Date(share.expiresAt).toLocaleTimeString('de-DE')}):</p>
                <div className="share-link">
                  <code>{share.url}</code>
                  <button onClick={() => navigator.clipboard?.writeText(share.url)}>Kopieren</button>
                </div>
              </div>
            )}
          </div>

          <h4>Freund hinzufügen</h4>
          <div className="add-friend">
            <input placeholder="E-Mail des Freundes" value={email} onChange={(e) => setEmail(e.target.value)} />
            <button className="primary sm" onClick={addFriend} disabled={!email}>Einladen</button>
          </div>
          {msg && <p className="small dim">{msg}</p>}

          {requests.length > 0 && (
            <>
              <h4>Anfragen</h4>
              {requests.map((r) => (
                <div key={r.id} className="device">
                  <strong>{r.from.name}</strong>
                  <button className="primary sm" onClick={() => accept(r.id)}>Annehmen</button>
                </div>
              ))}
            </>
          )}

          <h4>Freunde {friends.length > 0 && `(${friends.length})`}</h4>
          {friends.length === 0 && <p className="small dim">Noch keine Freunde. Lade jemanden per E-Mail ein.</p>}
          {friends.map((f) => (
            <div key={f.id} className="device">
              <div>
                <strong><span className="fdot" style={{ background: f.color }} /> {f.name}</strong>
                <em>{f.sharing ? '📍 teilt Standort live' : 'offline / teilt nicht'}</em>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
