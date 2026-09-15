// Bildstatistik statt Bauchgefühl.
//
// Drei Zahlen je Blick, alle aus dem fertigen Bild und damit unabhängig
// davon, was im Shader steht:
//
//   Sättigung        mittleres (max-min)/max über die Kanäle
//   örtlicher        mittlerer Betrag der Helligkeitsdifferenz zu den vier
//   Kontrast         Nachbarn zwei Bildpunkte weiter — misst Struktur, nicht
//                    Gesamthelligkeit
//   Mittel           mittlere Leuchtdichte, 0 bis 255
//
// Der örtliche Kontrast ist die Zahl, die "sieht aus wie Plastik" beziffert:
// eine glatte Farbfläche hat ihn nahe null, eine fotografierte Straße liegt
// im zweistelligen Bereich. Er ist aber kein Ziel für sich — Rauschen hebt
// ihn ebenso, und zwar auf Kosten der mittleren Helligkeit, weil eine zu
// stark gestörte Normale im Mittel von der Sonne wegkippt. Beide Spalten
// gehören deshalb zusammen gelesen.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';

const BLICKE = [
 ['Innenstadt 13 Uhr', 'view', [-100, 20, 1.3, .15]],
 ['Strand 13 Uhr', 'view', [100, 250, 1.4, .1]],
 ['Küste 13 Uhr', 'view', [140, 120, -1.5, .05]],
 ['Skyline aus 300 m', 'luft', [-260, 120, 180, -120, 0, -120]]
];

const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const p = await b.newPage({viewport: {width: 900, height: 500}});
const fehler = [];
p.on('pageerror', e => fehler.push(String(e.message)));
p.on('console', m => {if (m.type() === 'error') fehler.push(m.text());});
await p.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await p.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
await p.click('#startBtn');
await p.waitForTimeout(1200);

console.log('Blick                  Sättigung   örtl. Kontrast   Mittel');
for (const [name, art, a] of BLICKE) {
 await p.evaluate(([art, a]) => {
  const L = window.LOWTIDE; L.sim.hour = 13; L.sim.weather = 'clear';
  if (art === 'view') L.view(a[0], a[1], a[2], a[3]); else L.luftbild(...a);
 }, [art, a]);
 const n = await p.evaluate(() => window.LOWTIDE.frames);
 await p.waitForFunction(k => window.LOWTIDE.frames > k + 3, n, {timeout: 120000});
 const r = await p.evaluate(() => {
  const w = window.LOWTIDE.world;
  w.zeichne();
  const gl = w.renderer.getContext();
  const bw = gl.drawingBufferWidth, bh = gl.drawingBufferHeight;
  const buf = new Uint8Array(bw * bh * 4);
  gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, buf);
  const L = i => buf[i] * .2126 + buf[i + 1] * .7152 + buf[i + 2] * .0722;
  let sat = 0, mit = 0, n = 0, kontrast = 0, k = 0;
  for (let y = 2; y < bh - 2; y += 3) for (let x = 2; x < bw - 2; x += 3) {
   const i = (y * bw + x) * 4;
   const mx = Math.max(buf[i], buf[i + 1], buf[i + 2]), mn = Math.min(buf[i], buf[i + 1], buf[i + 2]);
   sat += mx ? (mx - mn) / mx : 0;
   const c = L(i);
   mit += c; n++;
   kontrast += Math.abs(c - L(i - 8)) + Math.abs(c - L(i + 8))
             + Math.abs(c - L(i - bw * 8)) + Math.abs(c - L(i + bw * 8));
   k += 4;
  }
  return {sat: sat / n * 100, kon: kontrast / k, m: mit / n};
 });
 console.log(`${name.padEnd(22)} ${r.sat.toFixed(1).padStart(7)} %  ${r.kon.toFixed(2).padStart(12)}   ${r.m.toFixed(1).padStart(6)}`);
}
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
