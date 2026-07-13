import type { StyleSpecification } from 'maplibre-gl';

// Vektor-Basiskarte mit echten Straßen, Labels UND Gebäudehöhen — kostenlos,
// ohne API-Key (OpenFreeMap, OpenMapTiles-Schema). Enthält die Quelle
// "openmaptiles" mit dem Layer "building" (render_height) für 3D.
// In Produktion durch den eigenen Tile-Server (docs/DATA_SOURCES.md) ersetzen:
//   VITE_STREETS_STYLE=/v1/style/streets.json
export const STREETS_STYLE: string =
  import.meta.env.VITE_STREETS_STYLE ?? 'https://tiles.openfreemap.org/styles/liberty';

// Freies 3D-Gelände (Terrarium-DEM, AWS Open Data, kein Key).
export const TERRAIN_SOURCE = {
  type: 'raster-dem' as const,
  tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],
  encoding: 'terrarium' as const,
  tileSize: 256,
  maxzoom: 15,
  attribution: 'Höhendaten: Mapzen/Tilezen (AWS Open Data)',
};

// Satellitenansicht (Esri World Imagery, kein Key). Für Produktion ggf.
// Sentinel-2 oder MapTiler Satellite (siehe docs/DATA_SOURCES.md).
export function satelliteStyle(): StyleSpecification {
  const sat =
    import.meta.env.VITE_SATELLITE_TILES ??
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  return {
    version: 8,
    sources: {
      sat: {
        type: 'raster',
        tiles: [sat],
        tileSize: 256,
        attribution: 'Imagery © Esri, Maxar, Earthstar Geographics',
      },
    },
    layers: [{ id: 'sat', type: 'raster', source: 'sat' }],
  };
}

// Reiner Offline-/Fallback-Style (OSM-Raster), falls Vektor-Tiles nicht erreichbar.
export const demoStyle: StyleSpecification = {
  version: 8,
  sources: {
    osm: {
      type: 'raster',
      tiles: ['https://a.tile.openstreetmap.org/{z}/{x}/{y}.png'],
      tileSize: 256,
      attribution: '© OpenStreetMap-Mitwirkende',
    },
  },
  layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
};
