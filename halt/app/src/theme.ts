// Brand tokens — kept in sync with the landing page so the app and the site
// read as one product.

export const colors = {
  bg: '#0b0d12',
  bgSoft: '#12151d',
  card: '#161a24',
  border: '#232838',
  text: '#eef1f7',
  muted: '#9aa3b5',
  brand: '#ff5a4d',
  brandSoft: '#ff8a80',
  accent: '#4dd4ac',
  // Risk level colors
  ok: '#4dd4ac',
  watch: '#f5b74d',
  alert: '#ff5a4d',
};

export const levelColor = (level: 'ok' | 'watch' | 'alert') =>
  level === 'alert' ? colors.alert : level === 'watch' ? colors.watch : colors.ok;

export const levelLabel = (level: 'ok' | 'watch' | 'alert') =>
  level === 'alert' ? 'Alarm' : level === 'watch' ? 'Beobachten' : 'Unauffällig';

export const radius = 16;
export const spacing = (n: number) => n * 8;
