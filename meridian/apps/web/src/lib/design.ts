// Premium: eigene Karten-Designs. Umgesetzt als GPU-günstige CSS-Filter auf dem
// Karten-Canvas — funktioniert mit jeder Tile-Quelle. (Produktion: zusätzlich
// echte MapLibre-Style-Themes je Design für pixelgenaue Kontrolle.)
export interface Preset {
  id: string;
  name: string;
  filter: string;
  swatch: string; // Vorschaufarbe
}

export const PRESETS: Preset[] = [
  { id: 'standard', name: 'Standard', filter: 'none', swatch: 'linear-gradient(135deg,#a9d0f5,#f4f2ee)' },
  { id: 'night', name: 'Nacht', filter: 'invert(0.92) hue-rotate(180deg) brightness(0.95) contrast(0.9)', swatch: 'linear-gradient(135deg,#0b1a2b,#12263a)' },
  { id: 'mono', name: 'Mono', filter: 'grayscale(1) contrast(1.05)', swatch: 'linear-gradient(135deg,#9a9a9a,#e0e0e0)' },
  { id: 'retro', name: 'Retro', filter: 'sepia(0.55) saturate(1.3) hue-rotate(-15deg)', swatch: 'linear-gradient(135deg,#c8a26a,#efe0c0)' },
  { id: 'nature', name: 'Natur', filter: 'saturate(1.5) hue-rotate(8deg) brightness(1.02)', swatch: 'linear-gradient(135deg,#4a9d5b,#bfe6a0)' },
  { id: 'contrast', name: 'Kontrast', filter: 'contrast(1.35) saturate(1.25)', swatch: 'linear-gradient(135deg,#2b6fff,#ff9f0a)' },
  { id: 'blueprint', name: 'Blaupause', filter: 'invert(1) hue-rotate(180deg) saturate(2.2) brightness(0.85)', swatch: 'linear-gradient(135deg,#0a3b8c,#2b6fff)' },
];

export interface CustomParams {
  hue: number; // 0..360
  saturation: number; // 0..200 (%)
  brightness: number; // 50..150 (%)
  contrast: number; // 50..150 (%)
  invert: number; // 0..1
}
export const DEFAULT_CUSTOM: CustomParams = { hue: 0, saturation: 100, brightness: 100, contrast: 100, invert: 0 };

export function paramsToFilter(p: CustomParams): string {
  return `hue-rotate(${p.hue}deg) saturate(${p.saturation}%) brightness(${p.brightness}%) contrast(${p.contrast}%) invert(${p.invert})`;
}

interface Stored {
  label: string;
  filter: string;
  custom?: CustomParams;
}
const KEY = 'meridian_design';

export function loadDesign(): Stored {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return JSON.parse(raw) as Stored;
  } catch {
    /* ignore */
  }
  return { label: 'Standard', filter: 'none' };
}
export function saveDesign(s: Stored): void {
  localStorage.setItem(KEY, JSON.stringify(s));
}
