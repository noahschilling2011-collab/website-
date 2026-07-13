import { useState } from 'react';
import { MapView } from './components/MapView';
import { search, route as routeApi, type LonLat, type Place, type RouteResponse } from './lib/api';

const MODES = [
  { id: 'auto', label: 'Auto', icon: '🚗' },
  { id: 'bicycle', label: 'Rad', icon: '🚲' },
  { id: 'pedestrian', label: 'Fuß', icon: '🚶' },
  { id: 'transit', label: 'ÖPNV', icon: '🚆' },
];
const PREFS = [
  { id: 'fastest', label: 'Schnellste' },
  { id: 'comfortable', label: 'Angenehmste' },
  { id: 'eco', label: 'Eco' },
  { id: 'scenic', label: 'Landschaft' },
];

function fmtDuration(s: number): string {
  const h = Math.floor(s / 3600);
  const m = Math.round((s % 3600) / 60);
  return h > 0 ? `${h} h ${m} min` : `${m} min`;
}

export function App() {
  const [from, setFrom] = useState<Place | undefined>();
  const [to, setTo] = useState<Place | undefined>();
  const [mode, setMode] = useState('auto');
  const [pref, setPref] = useState('fastest');
  const [resp, setResp] = useState<RouteResponse | undefined>();
  const [picking, setPicking] = useState<'from' | 'to' | null>(null);
  const [loading, setLoading] = useState(false);

  async function plan() {
    if (!from || !to) return;
    setLoading(true);
    try {
      const r = await routeApi({
        mode,
        preference: pref,
        waypoints: [from.center, to.center],
        alternatives: 3,
        include: ['weather', 'poi:fuel', 'poi:charging'],
      });
      setResp(r);
    } finally {
      setLoading(false);
    }
  }

  function onPick(ll: LonLat) {
    const place: Place = { id: 'pin', name: `${ll[1].toFixed(4)}, ${ll[0].toFixed(4)}`, center: ll };
    if (picking === 'from') setFrom(place);
    else if (picking === 'to') setTo(place);
    setPicking(null);
  }

  const rec = resp?.routes[resp.recommended];

  return (
    <div className="app">
      <div className="panel">
        <header className="brand">
          <span className="logo">◎</span> Meridian
        </header>

        <PlaceField label="Start" value={from} onSelect={setFrom} onPin={() => setPicking('from')} active={picking === 'from'} />
        <PlaceField label="Ziel" value={to} onSelect={setTo} onPin={() => setPicking('to')} active={picking === 'to'} />

        <div className="segment">
          {MODES.map((m) => (
            <button key={m.id} className={mode === m.id ? 'seg on' : 'seg'} onClick={() => setMode(m.id)}>
              <span>{m.icon}</span>
              {m.label}
            </button>
          ))}
        </div>

        <div className="prefs">
          {PREFS.map((p) => (
            <button key={p.id} className={pref === p.id ? 'chip on' : 'chip'} onClick={() => setPref(p.id)}>
              {p.label}
            </button>
          ))}
        </div>

        <button className="go" disabled={!from || !to || loading} onClick={plan}>
          {loading ? 'Berechne …' : 'Route berechnen'}
        </button>

        {resp && (
          <div className="results">
            {resp.explanation && <p className="explain">💡 {resp.explanation}</p>}
            {resp.routes.map((r, i) => (
              <div key={r.id} className={i === resp.recommended ? 'route on' : 'route'}>
                <div className="route-head">
                  <strong>{fmtDuration(r.duration)}</strong>
                  <span>{(r.distance / 1000).toFixed(1)} km</span>
                  {i === resp.recommended && <span className="badge">Empfohlen</span>}
                </div>
                {r.eta && <div className="eta">Ankunft ~ {new Date(r.eta).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}</div>}
                {r.warnings.map((w, k) => (
                  <div key={k} className="warn">⚠ {w}</div>
                ))}
              </div>
            ))}

            {resp.weather && resp.weather.length > 0 && (
              <div className="ctx">
                <h4>Wetter auf der Strecke</h4>
                <div className="wrow">
                  {resp.weather.map((w, i) => (
                    <span key={i} className={`wc ${w.risk}`} title={new Date(w.time).toLocaleTimeString('de-DE')}>
                      {Number.isNaN(w.tempC) ? '–' : `${Math.round(w.tempC)}°`}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {rec?.legs?.[0]?.maneuvers && (
              <div className="ctx">
                <h4>Wegbeschreibung</h4>
                <ol className="steps">
                  {rec.legs.flatMap((l) => l.maneuvers).slice(0, 25).map((m, i) => (
                    <li key={i}>
                      {m.instruction}
                      {m.distance > 0 && <em> · {(m.distance / 1000).toFixed(1)} km</em>}
                    </li>
                  ))}
                </ol>
              </div>
            )}
          </div>
        )}

        <footer className="attrib">© OpenStreetMap-Mitwirkende · Meridian</footer>
      </div>

      <MapView from={from?.center} to={to?.center} route={rec} onPick={onPick} />
    </div>
  );
}

function PlaceField({
  label,
  value,
  onSelect,
  onPin,
  active,
}: {
  label: string;
  value?: Place;
  onSelect: (p: Place) => void;
  onPin: () => void;
  active: boolean;
}) {
  const [q, setQ] = useState('');
  const [opts, setOpts] = useState<Place[]>([]);

  async function onChange(v: string) {
    setQ(v);
    if (v.length < 2) return setOpts([]);
    try {
      const r = await search(v);
      setOpts(r.results);
    } catch {
      setOpts([]);
    }
  }

  return (
    <div className="field">
      <label>{label}</label>
      <div className="field-row">
        <input
          placeholder={value?.name ?? 'Ort suchen …'}
          value={q}
          onChange={(e) => onChange(e.target.value)}
        />
        <button className={active ? 'pin on' : 'pin'} title="Auf Karte wählen" onClick={onPin}>
          📍
        </button>
      </div>
      {opts.length > 0 && (
        <ul className="opts">
          {opts.map((o) => (
            <li
              key={o.id}
              onClick={() => {
                onSelect(o);
                setQ(o.name);
                setOpts([]);
              }}
            >
              <strong>{o.name}</strong>
              {o.address && <span>{o.address}</span>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
