import { useEffect, useRef } from 'react';
import maplibregl, { type Map as MlMap, Marker } from 'maplibre-gl';
import { demoStyle } from '../lib/mapStyle';
import { decodePolyline } from '../lib/polyline';
import type { LonLat, Route } from '../lib/api';

interface Props {
  from?: LonLat;
  to?: LonLat;
  route?: Route;
  onPick?: (lonlat: LonLat) => void;
}

export function MapView({ from, to, route, onPick }: Props) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<MlMap | null>(null);
  const markers = useRef<Marker[]>([]);

  useEffect(() => {
    if (!container.current || map.current) return;
    const m = new maplibregl.Map({
      container: container.current,
      style: demoStyle,
      center: [10.45, 51.16], // Deutschland
      zoom: 5.4,
      attributionControl: { compact: true },
    });
    m.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'bottom-right');
    m.addControl(new maplibregl.GeolocateControl({ trackUserLocation: true, positionOptions: { enableHighAccuracy: true } }), 'bottom-right');
    m.on('click', (e) => onPick?.([e.lngLat.lng, e.lngLat.lat]));
    map.current = m;
    return () => {
      m.remove();
      map.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Marker aktualisieren
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    markers.current.forEach((mk) => mk.remove());
    markers.current = [];
    for (const [pt, color] of [
      [from, '#0a84ff'],
      [to, '#ff3b30'],
    ] as const) {
      if (pt) markers.current.push(new maplibregl.Marker({ color }).setLngLat(pt).addTo(m));
    }
  }, [from, to]);

  // Route zeichnen
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const draw = () => {
      const src = m.getSource('route') as maplibregl.GeoJSONSource | undefined;
      const geojson = {
        type: 'Feature' as const,
        properties: {},
        geometry: { type: 'LineString' as const, coordinates: route ? decodePolyline(route.geometry) : [] },
      };
      if (src) {
        src.setData(geojson);
      } else {
        m.addSource('route', { type: 'geojson', data: geojson });
        m.addLayer({
          id: 'route-line',
          type: 'line',
          source: 'route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#0a84ff', 'line-width': 6, 'line-opacity': 0.85 },
        });
      }
      if (route && geojson.geometry.coordinates.length > 1) {
        const coords = geojson.geometry.coordinates;
        const b = coords.reduce(
          (acc, c) => acc.extend(c as [number, number]),
          new maplibregl.LngLatBounds(coords[0] as [number, number], coords[0] as [number, number]),
        );
        m.fitBounds(b, { padding: 80, duration: 600 });
      }
    };
    if (m.isStyleLoaded()) draw();
    else m.once('load', draw);
  }, [route]);

  return <div ref={container} className="map" />;
}
