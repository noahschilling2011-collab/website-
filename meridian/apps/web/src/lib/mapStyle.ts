import type { StyleSpecification } from 'maplibre-gl';

// Dev-Style mit OSM-Raster, damit die Karte ohne eigenen Tile-Server rendert.
// In Produktion stattdessen den Vektor-Style vom Gateway laden:
//   const style = await (await fetch('/v1/style/streets.json')).json();
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
