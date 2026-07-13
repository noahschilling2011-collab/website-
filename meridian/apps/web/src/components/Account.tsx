import { useEffect, useState } from 'react';
import * as A from '../lib/auth';

export function Account({ onClose, onAuthChange }: { onClose: () => void; onAuthChange: () => void }) {
  const [me, setMe] = useState<A.Me | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (A.isLoggedIn()) A.me().then(setMe).catch(() => A.clearTokens()).finally(() => setLoading(false));
    else setLoading(false);
  }, []);

  function refresh() {
    A.me().then(setMe).catch(() => setMe(null));
    onAuthChange();
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <strong>{me ? 'Konto & Sicherheit' : 'Anmelden'}</strong>
          <button onClick={onClose}>✕</button>
        </div>
        <div className="modal-body">
          {loading ? <p className="dim">…</p> : me ? <LoggedIn me={me} onChange={refresh} onLogout={() => { A.logout().then(() => { setMe(null); onAuthChange(); }); }} /> : <AuthForms onDone={refresh} />}
        </div>
      </div>
    </div>
  );
}

function AuthForms({ onDone }: { onDone: () => void }) {
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [totp, setTotp] = useState('');
  const [need2fa, setNeed2fa] = useState(false);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    setErr('');
    setBusy(true);
    try {
      if (mode === 'register') {
        await A.register(email, password, name);
      } else {
        const res = await A.login(email, password, need2fa ? totp : undefined);
        if (res.status === '2fa_required') {
          setNeed2fa(true);
          setBusy(false);
          return;
        }
        if (res.newDevice) alert('Hinweis: Anmeldung von einem neuen Gerät erkannt.');
      }
      onDone();
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function oauth(p: 'google' | 'apple' | 'microsoft') {
    const r = await A.oauthStart(p);
    if (r.url) location.href = r.url;
    else alert(r.message ?? `${p}-Login ist nicht konfiguriert.`);
  }

  return (
    <div className="auth">
      <div className="tabs">
        <button className={mode === 'login' ? 'on' : ''} onClick={() => setMode('login')}>Anmelden</button>
        <button className={mode === 'register' ? 'on' : ''} onClick={() => setMode('register')}>Registrieren</button>
      </div>

      <div className="oauth">
        <button onClick={() => oauth('google')}>Weiter mit Google</button>
        <button onClick={() => oauth('apple')}>Weiter mit Apple</button>
        <button onClick={() => oauth('microsoft')}>Weiter mit Microsoft</button>
      </div>
      <div className="divider"><span>oder</span></div>

      {mode === 'register' && <input placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} />}
      <input placeholder="E-Mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
      <input placeholder="Passwort (min. 8 Zeichen)" type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
      {need2fa && <input placeholder="2FA-Code" value={totp} onChange={(e) => setTotp(e.target.value)} inputMode="numeric" />}
      {err && <div className="err">{err}</div>}
      <button className="primary" onClick={submit} disabled={busy || !email || !password}>
        {busy ? '…' : mode === 'register' ? 'Konto erstellen' : need2fa ? 'Code bestätigen' : 'Anmelden'}
      </button>
      <button className="ghost" onClick={() => A.guest().then(onDone)}>Als Gast fortfahren</button>
    </div>
  );
}

function LoggedIn({ me, onChange, onLogout }: { me: A.Me; onChange: () => void; onLogout: () => void }) {
  const [tab, setTab] = useState<'profil' | 'sicherheit' | 'geräte' | 'datenschutz'>('profil');
  return (
    <div className="account">
      <div className="profile-head">
        <div className="avatar" style={{ background: me.avatarColor }}>{me.name.charAt(0).toUpperCase()}</div>
        <div>
          <div className="pname">{me.name}{me.isGuest && ' (Gast)'}</div>
          <div className="pmail">{me.email || 'Gastmodus'}</div>
        </div>
      </div>
      <div className="acct-tabs">
        {(['profil', 'sicherheit', 'geräte', 'datenschutz'] as const).map((t) => (
          <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>{cap(t)}</button>
        ))}
      </div>
      {tab === 'profil' && <ProfileTab me={me} onChange={onChange} />}
      {tab === 'sicherheit' && <SecurityTab me={me} onChange={onChange} />}
      {tab === 'geräte' && <DevicesTab />}
      {tab === 'datenschutz' && <PrivacyTab onLogout={onLogout} />}
      <button className="ghost logout" onClick={onLogout}>Abmelden</button>
    </div>
  );
}

function ProfileTab({ me, onChange }: { me: A.Me; onChange: () => void }) {
  const [name, setName] = useState(me.name);
  return (
    <div className="tabpane">
      <label>Anzeigename</label>
      <input value={name} onChange={(e) => setName(e.target.value)} />
      <button className="primary" onClick={() => A.updateProfile({ name }).then(onChange)}>Speichern</button>
      <p className="dim small">Mitglied seit {new Date(me.createdAt).toLocaleDateString('de-DE')}</p>
    </div>
  );
}

function SecurityTab({ me, onChange }: { me: A.Me; onChange: () => void }) {
  const [setup, setSetup] = useState<{ secret: string; otpauthUri: string } | null>(null);
  const [code, setCode] = useState('');
  const [backup, setBackup] = useState<string[] | null>(null);
  const [log, setLog] = useState<A.SecurityEvent[]>([]);

  useEffect(() => { A.securityLog().then((r) => setLog(r.events)); }, []);

  return (
    <div className="tabpane">
      <div className="row2">
        <span>Zwei-Faktor-Authentifizierung</span>
        <span className={me.totpEnabled ? 'pill on' : 'pill'}>{me.totpEnabled ? 'Aktiv' : 'Inaktiv'}</span>
      </div>
      {!me.totpEnabled && !setup && <button className="primary" onClick={() => A.enroll2FA().then(setSetup)}>2FA einrichten</button>}
      {setup && (
        <div className="twofa">
          <p className="small">Secret in deine Authenticator-App eintragen:</p>
          <code className="secret">{setup.secret}</code>
          <input placeholder="6-stelliger Code" value={code} onChange={(e) => setCode(e.target.value)} inputMode="numeric" />
          <button className="primary" onClick={() => A.enable2FA(code).then((r) => { setBackup(r.backupCodes); setSetup(null); onChange(); })}>Aktivieren</button>
        </div>
      )}
      {backup && (
        <div className="backup">
          <p className="small">Backup-Codes (sicher aufbewahren, je einmalig):</p>
          <div className="codes">{backup.map((c) => <code key={c}>{c}</code>)}</div>
        </div>
      )}
      {me.totpEnabled && !setup && (
        <div className="twofa">
          <input placeholder="Code zum Deaktivieren" value={code} onChange={(e) => setCode(e.target.value)} inputMode="numeric" />
          <button className="ghost" onClick={() => A.disable2FA(code).then(onChange)}>2FA deaktivieren</button>
        </div>
      )}

      <h4>Sicherheitsprotokoll</h4>
      <ul className="log">
        {log.map((e, i) => (
          <li key={i}>
            <span className={`ev ${e.type}`}>{evLabel(e.type)}</span>
            <em>{new Date(e.at).toLocaleString('de-DE')}{e.device ? ` · ${e.device}` : ''}</em>
          </li>
        ))}
      </ul>
    </div>
  );
}

function DevicesTab() {
  const [sessions, setSessions] = useState<A.DeviceSession[]>([]);
  const load = () => A.listSessions().then((r) => setSessions(r.sessions));
  useEffect(() => { load(); }, []);
  return (
    <div className="tabpane">
      <p className="small dim">Alle Geräte, die bei deinem Konto angemeldet sind.</p>
      {sessions.map((s) => (
        <div key={s.id} className="device">
          <div>
            <strong>{s.device}{s.current && ' · dieses Gerät'}</strong>
            <em>{s.ip} · zuletzt {new Date(s.lastSeenAt).toLocaleString('de-DE')}</em>
          </div>
          {!s.current && <button className="ghost sm" onClick={() => A.revokeSession(s.id).then(load)}>Beenden</button>}
        </div>
      ))}
      <button className="ghost" onClick={() => A.logoutAll().then(load)}>Alle anderen Sitzungen beenden</button>
    </div>
  );
}

function PrivacyTab({ onLogout }: { onLogout: () => void }) {
  const [perms, setPerms] = useState<A.Permissions | null>(null);
  useEffect(() => { A.getPermissions().then((r) => setPerms(r.permissions)); }, []);
  const labels: Record<keyof A.Permissions, string> = {
    location: 'Standort', camera: 'Kamera', microphone: 'Mikrofon', notifications: 'Benachrichtigungen', analytics: 'Analytics (anonym)', personalization: 'Personalisierung',
  };
  function toggle(k: keyof A.Permissions) {
    if (!perms) return;
    const next = { ...perms, [k]: !perms[k] };
    setPerms(next);
    A.setPermissions({ [k]: next[k] });
  }
  async function exportData() {
    const data = await A.exportData();
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'meridian-daten-export.json';
    a.click();
    URL.revokeObjectURL(url);
  }
  return (
    <div className="tabpane">
      <p className="small dim">Berechtigungen einzeln steuern.</p>
      {perms &&
        (Object.keys(labels) as (keyof A.Permissions)[]).map((k) => (
          <div key={k} className="row2">
            <span>{labels[k]}</span>
            <button className={perms[k] ? 'switch on' : 'switch'} onClick={() => toggle(k)}>
              <span className="knob" />
            </button>
          </div>
        ))}
      <h4>Deine Daten</h4>
      <button className="ghost" onClick={exportData}>Daten exportieren (DSGVO)</button>
      <button className="danger" onClick={() => { if (confirm('Konto und alle Daten unwiderruflich löschen?')) A.deleteAccount().then(onLogout); }}>
        Konto löschen
      </button>
    </div>
  );
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
function evLabel(t: string): string {
  const m: Record<string, string> = {
    register: 'Registriert', login: 'Anmeldung', login_failed: 'Fehlanmeldung', logout: 'Abmeldung',
    new_device_login: '⚠ Neues Gerät', account_locked: '⚠ Konto gesperrt', refresh_reuse: '⚠ Token-Wiederverwendung',
    '2fa_enabled': '2FA aktiviert', '2fa_disabled': '2FA deaktiviert', session_revoked: 'Sitzung beendet',
    logout_all: 'Alle abgemeldet', permissions_changed: 'Berechtigungen geändert', oauth_login: 'Social-Login',
  };
  return m[t] ?? t;
}
