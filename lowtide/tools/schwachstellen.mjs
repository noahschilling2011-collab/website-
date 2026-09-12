// Wo sieht die Karte noch nach Prototyp aus?
//
// Bis hierher habe ich Mängel durch Hinsehen gesucht und geraten, was der
// nächste Schritt sein müsste. Die Trefferquote war schlecht: auf fünf
// belegte Verbesserungen kamen sieben widerlegte Vermutungen. Diese Prüfung
// dreht das um — sie fährt jede Region an, misst dort dasselbe wie
// statistik.mjs und sortiert nach dem schwächsten Wert.
//
// Niedriger örtlicher Kontrast heißt: große glatte Flächen ohne Struktur,
// also unfertig. Sehr niedrige Sättigung heißt: einfarbige Kisten. Die
// Liste unten ist die Arbeitsliste, nicht eine Bewertung.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';

const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const p = await b.newPage({viewport: {width: 640, height: 400}});
const fehler = [];
p.on('pageerror', e => fehler.push(String(e.message)));
p.on('console', m => {if (m.type() === 'error') fehler.push(m.text());});
await p.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await p.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
await p.click('#startBtn');
await p.waitForTimeout(1200);

const regionen = await p.evaluate(() => window.LOWTIDE.regionen.map(r => ({name: r.name, x: r.x, z: r.z})));
const messe = async (x, z, blick) => {
 await p.evaluate(([x, z, blick]) => {
  const L = window.LOWTIDE; L.sim.hour = 13; L.sim.weather = 'clear';
  L.view(x, z, blick, .12);
 }, [x, z, blick]);
 const n = await p.evaluate(() => window.LOWTIDE.frames);
 await p.waitForFunction(k => window.LOWTIDE.frames > k + 3, n, {timeout: 120000});
 return await p.evaluate(() => {
  const w = window.LOWTIDE.world;
  w.zeichne();
  const gl = w.renderer.getContext();
  const bw = gl.drawingBufferWidth, bh = gl.drawingBufferHeight;
  const buf = new Uint8Array(bw * bh * 4);
  gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, buf);
  const L = i => buf[i] * .2126 + buf[i + 1] * .7152 + buf[i + 2] * .0722;
  // Nur die untere Bildhälfte: oben steht Himmel, der überall gleich ist und
  // die Zahl sonst verwässert.
  let sat = 0, mit = 0, n = 0, kon = 0, k = 0;
  for (let y = Math.floor(bh * .5); y < bh - 2; y += 2) for (let x = 2; x < bw - 2; x += 2) {
   const i = (y * bw + x) * 4;
   const mx = Math.max(buf[i], buf[i + 1], buf[i + 2]), mn = Math.min(buf[i], buf[i + 1], buf[i + 2]);
   sat += mx ? (mx - mn) / mx : 0;
   const c = L(i); mit += c; n++;
   kon += Math.abs(c - L(i - 8)) + Math.abs(c - L(i + 8))
        + Math.abs(c - L(i - bw * 8)) + Math.abs(c - L(i + bw * 8));
   k += 4;
  }
  return {sat: sat / n * 100, kon: kon / k, m: mit / n};
 });
};

const zeilen = [];
for (const r of regionen) {
 // Zwei Blickrichtungen je Region, damit nicht eine zufällig leere Ecke
 // über die ganze Gegend entscheidet. Gewertet wird die bessere.
 const a = await messe(r.x, r.z, 0.7);
 const c = await messe(r.x, r.z, 0.7 + Math.PI);
 const best = a.kon >= c.kon ? a : c;
 zeilen.push({name: r.name, ...best});
}
zeilen.sort((u, v) => u.kon - v.kon);
console.log('Region                     örtl. Kontrast   Sättigung   Mittel');
for (const z of zeilen)
 console.log(`${z.name.padEnd(26)} ${z.kon.toFixed(2).padStart(9)}   ${z.sat.toFixed(1).padStart(8)} %  ${z.m.toFixed(1).padStart(6)}`);
const schnitt = zeilen.reduce((s, z) => s + z.kon, 0) / zeilen.length;
console.log(`\nSchnitt ${schnitt.toFixed(2)} — die obersten drei sind die Arbeitsliste.`);
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
