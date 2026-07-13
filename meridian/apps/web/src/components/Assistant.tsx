import { useEffect, useRef, useState } from 'react';
import {
  assistantCommand,
  planTrip,
  briefing,
  type AssistantAction,
  type Place,
  type LonLat,
} from '../lib/api';
import { listenOnce, speak, sttSupported } from '../lib/speech';

export interface AssistantHandlers {
  from?: Place;
  to?: Place;
  hasRoute: boolean;
  near?: LonLat;
  onNavigate: (to: Place, opts: { preference?: string; avoid?: string[]; mode?: string }) => void;
  onUi: (ui: NonNullable<AssistantAction['ui']>) => void;
  onSetPref: (opts: { preference?: string; avoid?: string[]; mode?: string }) => void;
}

interface Msg {
  role: 'user' | 'assistant';
  text: string;
}

const EXAMPLES = [
  'Bring mich ohne Autobahn nach Köln',
  'Finde den günstigsten Supermarkt auf dem Weg',
  'Plane einen Zwischenstopp zum Essen',
  'Zeig mir die Satellitenansicht in 3D',
  'Plane einen Tagesausflug',
];

export function Assistant(props: AssistantHandlers) {
  const [open, setOpen] = useState(false);
  const [msgs, setMsgs] = useState<Msg[]>([
    { role: 'assistant', text: 'Hallo! Ich bin dein Meridian-Assistent. Sag mir, wohin es gehen soll.' },
  ]);
  const [input, setInput] = useState('');
  const [listening, setListening] = useState(false);
  const [busy, setBusy] = useState(false);
  const scroller = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: 'smooth' });
  }, [msgs, open]);

  function push(role: Msg['role'], text: string) {
    setMsgs((m) => [...m, { role, text }]);
  }

  async function run(text: string) {
    if (!text.trim() || busy) return;
    push('user', text);
    setInput('');
    setBusy(true);
    try {
      const res = await assistantCommand(text, {
        near: props.near,
        from: props.from,
        to: props.to,
        hasRoute: props.hasRoute,
      });
      let reply = res.reply;
      const a = res.action;

      if (a.type === 'navigate' && a.place) {
        props.onNavigate(a.place, { preference: a.preference, avoid: a.avoid, mode: a.mode });
      } else if (a.type === 'navigate' && a.destinationQuery === 'Zuhause') {
        reply = 'Bitte lege zuerst deinen Heimatort fest (Favorit „Zuhause").';
      } else if (a.type === 'ui' && a.ui) {
        props.onUi(a.ui);
      } else if (a.type === 'set_pref') {
        props.onSetPref({ preference: a.preference, avoid: a.avoid, mode: a.mode });
      } else if (a.type === 'plan_trip') {
        if (props.from && props.to) {
          const plan = await planTrip([props.from.center, props.to.center]);
          reply =
            `Tagesausflug (${plan.summary.distanceKm} km, ~${Math.round(plan.summary.drivingMinutes / 60)} h Fahrt):\n` +
            plan.items.map((i) => `• ${fmtMin(i.etaMinutes)} — ${i.title}`).join('\n');
        } else {
          reply = 'Für die Reiseplanung bitte Start und Ziel setzen.';
        }
      } else if (a.type === 'briefing') {
        if (props.from && props.to) {
          const b = await briefing(props.from, props.to);
          reply = b.message;
        } else {
          reply = 'Für ein Briefing bitte Start und Ziel setzen.';
        }
      }

      push('assistant', reply);
      speak(reply.replace(/•/g, '').replace(/\n/g, '. '));
    } catch {
      push('assistant', 'Es gab ein Problem bei der Verarbeitung. Bitte erneut versuchen.');
    } finally {
      setBusy(false);
    }
  }

  async function mic() {
    if (listening) return;
    setListening(true);
    try {
      const { promise } = listenOnce('de-DE');
      const text = await promise;
      setListening(false);
      await run(text);
    } catch {
      setListening(false);
      push('assistant', 'Ich habe dich nicht verstanden. Versuch es noch einmal oder tippe.');
    }
  }

  if (!open) {
    return (
      <button className="fab" onClick={() => setOpen(true)} title="Assistent">
        🎙 Assistent
      </button>
    );
  }

  return (
    <div className="assistant">
      <div className="as-head">
        <strong>◎ Assistent</strong>
        <button onClick={() => setOpen(false)}>▾</button>
      </div>
      <div className="as-msgs" ref={scroller}>
        {msgs.map((m, i) => (
          <div key={i} className={`as-msg ${m.role}`}>
            {m.text.split('\n').map((line, k) => (
              <div key={k}>{line}</div>
            ))}
          </div>
        ))}
        {busy && <div className="as-msg assistant dim">…</div>}
      </div>
      {msgs.length <= 1 && (
        <div className="as-examples">
          {EXAMPLES.map((e) => (
            <button key={e} onClick={() => run(e)}>
              {e}
            </button>
          ))}
        </div>
      )}
      <div className="as-input">
        {sttSupported() && (
          <button className={listening ? 'as-mic on' : 'as-mic'} onClick={mic} title="Sprechen">
            {listening ? '●' : '🎙'}
          </button>
        )}
        <input
          value={input}
          placeholder="Sag oder tippe etwas …"
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && run(input)}
        />
        <button className="as-send" onClick={() => run(input)} disabled={busy || !input.trim()}>
          ↑
        </button>
      </div>
    </div>
  );
}

function fmtMin(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h}:${String(m).padStart(2, '0')} h` : `${m} min`;
}
