import { useEffect, useRef } from 'react';
import maplibregl, { type Map as MlMap, Marker } from 'maplibre-gl';
import { STREETS_STYLE, TERRAIN_SOURCE, satelliteStyle } from '../lib/mapStyle';
import { decodePolyline } from '../lib/polyline';
import type { LonLat, Route } from '../lib/api';

export type ViewMode = 'streets' | 'satellite';

export interface Person {
  id: string;
  name: string;
  color: string;
  lat: number;
  lon: number;
}

interface Props {
  from?: LonLat;
  to?: LonLat;
  route?: Route;
  viewMode: ViewMode;
  threeD: boolean;
  mapillaryToken?: string;
  people?: Person[];
  design?: string; // CSS-Filter für das Karten-Design
  onMapClick?: (lonlat: LonLat) => void;
}

export function MapView({ from, to, route, viewMode, threeD, mapillaryToken, people, design, onMapClick }: Props) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<MlMap | null>(null);
  const markers = useRef<Marker[]>([]);
  const peopleMarkers = useRef<Map<string, Marker>>(new Map());
  const clickCb = useRef(onMapClick);
  clickCb.current = onMapClick;

  // Karte einmalig erstellen
  useEffect(() => {
    if (!container.current || map.current) return;
    const m = new maplibregl.Map({
      container: container.current,
      style: STREETS_STYLE,
      center: [10.45, 51.16],
      zoom: 5.4,
      pitch: 0,
      maxPitch: 85,
      attributionControl: { compact: true },
    });
    m.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'bottom-right');
    m.addControl(
      new maplibregl.GeolocateControl({ trackUserLocation: true, positionOptions: { enableHighAccuracy: true } }),
      'bottom-right',
    );
    m.on('click', (e) => clickCb.current?.([e.lngLat.lng, e.lngLat.lat]));
    // Nach jedem Style-Load Zusatz-Layer (Gelände, 3D, Route, Mapillary) neu anlegen.
    m.on('styledata', () => {
      if (m.isStyleLoaded()) decorate(m);
    });
    map.current = m;
    return () => {
      m.remove();
      map.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Idempotente Ausstattung des aktuellen Styles
  function decorate(m: MlMap) {
    // Gelände-Quelle
    if (!m.getSource('terrain')) m.addSource('terrain', TERRAIN_SOURCE);
    // Himmel (nur v4+)
    try {
      (m as unknown as { setSky: (s: unknown) => void }).setSky({
        'sky-color': '#a9d0f5',
        'horizon-color': '#eaf2fb',
        'fog-color': '#ffffff',
        'sky-horizon-blend': 0.5,
      });
    } catch {
      /* Sky optional */
    }
    ensure3DBuildings(m);
    ensureRouteLayer(m);
    ensureMapillary(m, mapillaryToken);
    applyTerrain(m, threeD);
    setBuildingsVisible(m, threeD);
  }

  // Ansicht (Straße/Satellit) umschalten
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    m.setStyle(viewMode === 'satellite' ? satelliteStyle() : STREETS_STYLE);
    // decorate() läuft automatisch über den 'styledata'-Listener.
  }, [viewMode]);

  // 3D an/aus
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const run = () => {
      applyTerrain(m, threeD);
      setBuildingsVisible(m, threeD);
      m.easeTo({ pitch: threeD ? 60 : 0, bearing: threeD ? -18 : 0, duration: 700 });
    };
    if (m.isStyleLoaded()) run();
    else m.once('idle', run);
  }, [threeD]);

  // Marker
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

  // Karten-Design (CSS-Filter auf dem Canvas). Der Canvas existiert sofort nach
  // Konstruktion — unabhängig vom Tile-Load.
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    try {
      m.getCanvas().style.filter = design && design !== 'none' ? design : '';
    } catch {
      /* Canvas noch nicht bereit */
    }
  }, [design]);

  // Live-Positionen von Freunden (eigene Marker mit Initiale)
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const seen = new Set<string>();
    for (const p of people ?? []) {
      seen.add(p.id);
      let mk = peopleMarkers.current.get(p.id);
      if (!mk) {
        const el = document.createElement('div');
        el.className = 'friend-marker';
        el.style.background = p.color;
        el.textContent = p.name.charAt(0).toUpperCase();
        el.title = p.name;
        mk = new maplibregl.Marker({ element: el }).setLngLat([p.lon, p.lat]).addTo(m);
        peopleMarkers.current.set(p.id, mk);
      } else {
        mk.setLngLat([p.lon, p.lat]);
      }
    }
    for (const [id, mk] of peopleMarkers.current) {
      if (!seen.has(id)) {
        mk.remove();
        peopleMarkers.current.delete(id);
      }
    }
  }, [people]);

  // Route zeichnen + einpassen
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const draw = () => {
      ensureRouteLayer(m);
      const src = m.getSource('route') as maplibregl.GeoJSONSource | undefined;
      const coords = route ? decodePolyline(route.geometry) : [];
      src?.setData({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: coords } });
      if (coords.length > 1) {
        const b = coords.reduce(
          (acc, c) => acc.extend(c as [number, number]),
          new maplibregl.LngLatBounds(coords[0] as [number, number], coords[0] as [number, number]),
        );
        m.fitBounds(b, { padding: 90, duration: 700, pitch: threeD ? 55 : 0 });
      }
    };
    if (m.isStyleLoaded()) draw();
    else m.once('idle', draw);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route]);

  return <div ref={container} className="map" />;
}

// ---- Helfer (idempotent) ----
function ensureRouteLayer(m: MlMap) {
  if (!m.getSource('route')) {
    m.addSource('route', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [] } } });
  }
  if (!m.getLayer('route-casing')) {
    m.addLayer({ id: 'route-casing', type: 'line', source: 'route', layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': '#0060df', 'line-width': 9, 'line-opacity': 0.9 } });
  }
  if (!m.getLayer('route-line')) {
    m.addLayer({ id: 'route-line', type: 'line', source: 'route', layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': '#0a84ff', 'line-width': 5 } });
  }
}

function ensure3DBuildings(m: MlMap) {
  if (m.getLayer('meridian-3d')) return;
  // Existiert bereits eine Gebäude-Extrusion im Style? Dann diese nutzen.
  const has = (m.getStyle().layers ?? []).some((l) => l.type === 'fill-extrusion');
  if (has || !m.getSource('openmaptiles')) return;
  m.addLayer({
    id: 'meridian-3d',
    type: 'fill-extrusion',
    source: 'openmaptiles',
    'source-layer': 'building',
    minzoom: 14,
    paint: {
      'fill-extrusion-color': ['interpolate', ['linear'], ['coalesce', ['get', 'render_height'], 5], 0, '#e6e1d8', 60, '#c9c2b6', 200, '#a7a094'],
      'fill-extrusion-height': ['coalesce', ['get', 'render_height'], ['get', 'height'], 5],
      'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], 0],
      'fill-extrusion-opacity': 0.9,
    },
  });
}

function setBuildingsVisible(m: MlMap, visible: boolean) {
  for (const l of m.getStyle().layers ?? []) {
    if (l.type === 'fill-extrusion') {
      try {
        m.setLayoutProperty(l.id, 'visibility', visible ? 'visible' : 'none');
      } catch {
        /* Layer evtl. entfernt */
      }
    }
  }
}

function applyTerrain(m: MlMap, on: boolean) {
  try {
    if (on && m.getSource('terrain')) m.setTerrain({ source: 'terrain', exaggeration: 1.25 });
    else m.setTerrain(null);
  } catch {
    /* Terrain optional */
  }
}

function ensureMapillary(m: MlMap, token?: string) {
  if (!token || m.getSource('mapillary')) return;
  m.addSource('mapillary', {
    type: 'vector',
    tiles: [`https://tiles.mapillary.com/maps/vtp/mly1_public/2/{z}/{x}/{y}?access_token=${token}`],
    minzoom: 6,
    maxzoom: 14,
  });
  m.addLayer({
    id: 'mapillary-coverage',
    type: 'line',
    source: 'mapillary',
    'source-layer': 'sequence',
    paint: { 'line-color': '#05CB63', 'line-width': 2, 'line-opacity': 0.7 },
  });
}
