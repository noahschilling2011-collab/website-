import { useEffect, useRef, useState } from 'react';
import type { LonLat } from '../lib/api';

interface Props {
  location: LonLat | null;
  token?: string;
  onClose: () => void;
}

// Street-View-ähnliche Ansicht über Mapillary (offene Straßenbilder).
// mapillary-js wird erst beim Öffnen geladen (dynamischer Import).
export function StreetView({ location, token, onClose }: Props) {
  const container = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<{ remove: () => void } | null>(null);
  const [status, setStatus] = useState<'idle' | 'loading' | 'ready' | 'none' | 'notoken'>('idle');

  useEffect(() => {
    let cancelled = false;
    async function open() {
      if (!location) return;
      if (!token) {
        setStatus('notoken');
        return;
      }
      setStatus('loading');
      try {
        // Nächstes Straßenbild in einer kleinen Bounding-Box finden.
        const d = 0.0006; // ~60 m
        const [lon, lat] = location;
        const bbox = `${lon - d},${lat - d},${lon + d},${lat + d}`;
        const res = await fetch(
          `https://graph.mapillary.com/images?access_token=${token}&fields=id&bbox=${bbox}&limit=1`,
        );
        const data = (await res.json()) as { data?: { id: string }[] };
        const imageId = data.data?.[0]?.id;
        if (cancelled) return;
        if (!imageId) {
          setStatus('none');
          return;
        }
        const { Viewer } = await import('mapillary-js');
        await import('mapillary-js/dist/mapillary.css');
        if (cancelled || !container.current) return;
        viewerRef.current?.remove();
        viewerRef.current = new Viewer({
          accessToken: token,
          container: container.current,
          imageId,
        }) as unknown as { remove: () => void };
        setStatus('ready');
      } catch {
        if (!cancelled) setStatus('none');
      }
    }
    open();
    return () => {
      cancelled = true;
      viewerRef.current?.remove();
      viewerRef.current = null;
    };
  }, [location, token]);

  if (!location) return null;

  return (
    <div className="sv">
      <div className="sv-bar">
        <span>Street View · Mapillary</span>
        <button onClick={onClose}>✕</button>
      </div>
      <div ref={container} className="sv-canvas" />
      {status === 'loading' && <div className="sv-msg">Suche Straßenbild …</div>}
      {status === 'none' && <div className="sv-msg">Hier gibt es (noch) kein Straßenbild. Anderen Punkt wählen.</div>}
      {status === 'notoken' && (
        <div className="sv-msg">
          Für Street View einen kostenlosen Mapillary-Token setzen
          (<code>VITE_MAPILLARY_TOKEN</code>). Token unter{' '}
          <a href="https://www.mapillary.com/dashboard/developers" target="_blank" rel="noreferrer">
            mapillary.com/dashboard/developers
          </a>
          .
        </div>
      )}
    </div>
  );
}
