import type { FastifyInstance } from 'fastify';
import { config } from '../config.js';

// Liefert MapLibre-Styles mit korrekter Attribution. Der Vektor-Tile-Server
// (Martin/PMTiles) liefert die eigentlichen Kacheln direkt (CDN).
export async function styleRoutes(app: FastifyInstance): Promise<void> {
  app.get('/v1/style/streets.json', async () => streetsStyle());
  app.get('/v1/style/satellite.json', async () => satelliteStyle());
}

const OSM_ATTRIB = '© OpenStreetMap-Mitwirkende';

function streetsStyle() {
  return {
    version: 8,
    name: 'Meridian Streets',
    glyphs: `${config.tiles.vector}/fonts/{fontstack}/{range}.pbf`,
    sources: {
      meridian: {
        type: 'vector',
        // OpenMapTiles-Schema; TileJSON vom Martin/PMTiles-Server
        url: `${config.tiles.vector}/meridian.json`,
        attribution: OSM_ATTRIB,
      },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': '#f4f2ee' } },
      {
        id: 'water',
        type: 'fill',
        source: 'meridian',
        'source-layer': 'water',
        paint: { 'fill-color': '#a9d0f5' },
      },
      {
        id: 'roads',
        type: 'line',
        source: 'meridian',
        'source-layer': 'transportation',
        paint: { 'line-color': '#ffffff', 'line-width': ['interpolate', ['linear'], ['zoom'], 6, 0.5, 16, 6] },
      },
      {
        id: 'buildings-3d',
        type: 'fill-extrusion',
        source: 'meridian',
        'source-layer': 'building',
        minzoom: 14,
        paint: {
          'fill-extrusion-color': '#d9d4cc',
          'fill-extrusion-height': ['coalesce', ['get', 'render_height'], ['get', 'height'], 5],
          'fill-extrusion-opacity': 0.85,
        },
      },
    ],
  };
}

function satelliteStyle() {
  const sat = config.tiles.satellite || 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  return {
    version: 8,
    name: 'Meridian Satellite',
    sources: {
      sat: { type: 'raster', tiles: [sat], tileSize: 256, attribution: 'Imagery: Esri, Maxar, Earthstar Geographics' },
    },
    layers: [{ id: 'sat', type: 'raster', source: 'sat' }],
  };
}
