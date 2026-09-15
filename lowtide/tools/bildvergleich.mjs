// Zwei Stände, dieselben Standorte und Uhrzeiten, mittlerer Bildunterschied
// je Blick.
//
//   node tools/bildvergleich.mjs alt.html neu.html [orte] [stunden]
//
// Alles Bewegliche wird vorher aus der Szene genommen. Der erste Anlauf hat es
// nur auf visible=false gesetzt — wirkungslos: `sim.paused` hält die
// Simulationsschritte an, die Detailstufenschleife im Renderer läuft weiter
// und setzt die Sichtbarkeit jedes Bild neu. Gemessen wurde damit vor allem,
// dass in zwei Läufen verschieden viele Schritte vergangen waren: 1,735
// mittlerer Unterschied mit bloßem visible=false, 0,179 mit ausgeblendeten
// Figuren, und der Rest steckte in den Fahrzeugen, die trotzdem im Bild
// standen. Wer aus der Szene entfernt ist, kommt nicht wieder.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';
const ORTE = {
 hafen: [-40, 60, 2.35, .30, 0], downtown: [-280, 20, 2.20, .34, 0],
 boulevard: [-40, -8, 0.05, .10, 0], kreuzung: [-100, 20, 1.30, .30, 0],
 flugfeld: [-300, 300, 1.30, .32, 0], marina: [268, 250, 4.60, .26, 0],
 rosalind: [-880, 340, 1.55, .16, 0], fassade: [-100, -10, 1.57, .02, 0],
 industrie: [116, -40, 1.90, .34, 0], undertow: [-210, 16, 3.10, .12, 0],
 park: [-470, -400, 2.20, .30, 0], vorort: [-60, -305, 1.60, .28, 0],
};
const orte = (process.argv[4] || 'hafen,downtown,boulevard,kreuzung,fassade,industrie,undertow,marina').split(',');
const stunden = (process.argv[5] || '13,22').split(',').map(Number);
const pfad = p => p.startsWith('/') ? p : fileURLToPath(new URL('../' + p, import.meta.url));
const browser = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const bilder = async datei => {
 const page = await browser.newPage({viewport: {width: 900, height: 520}});
 await page.goto('file://' + datei, {waitUntil: 'load'});
 await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 240000});
 await page.click('#startBtn');
 await page.waitForFunction(() => window.LOWTIDE.frames > 2, null, {timeout: 120000});
 await page.evaluate(() => {
  const L = window.LOWTIDE, w = L.world;
  L.sim.paused = true; L.sim.weather = 'clear'; L.sim.time = 100;
  const weg = o => {if (o && o.parent) o.parent.remove(o);};
  for (const m of w.npcs || []) weg(m);
  for (const m of w.cars || []) weg(m);
  for (const m of w.cops || []) weg(m);
  weg(w.player);
  // Auch die geparkten Wagen und alles andere, was street.js bewegt oder
  // stellt: erkennbar daran, dass es Räder hat.
  for (const o of [...w.scene.children]) if (o.userData && (o.userData.wheels || o.userData.legs)) weg(o);
  for (const f of [w.figurFern, w.autoFern]) for (const n of f?.netze || []) weg(n);
  for (const k of [w.schattenFigur, w.schattenWagen]) weg(k?.netz);
  weg(w.gras?.netz);
  for (const el of ['hud', 'objective', 'radar', 'vitals', 'desktopHelp', 'quick', 'toast', 'prompt', 'debug'])
   {const n = document.getElementById(el); if (n) n.style.display = 'none';}
 });
 const out = {};
 for (const o of orte) for (const h of stunden) {
  await page.evaluate(([v, h]) => {const L = window.LOWTIDE; L.sim.hour = h; L.sim.time = 100; L.view(v[0], v[1], v[2], v[3], v[4]);}, [ORTE[o], h]);
  const f0 = await page.evaluate(() => window.LOWTIDE.frames);
  await page.waitForFunction(k => window.LOWTIDE.frames > k + 3, f0, {timeout: 180000});
  out[o + '@' + h] = await page.evaluate(() => {
   const L = window.LOWTIDE; L.sim.time = 100; L.world.zeichne();
   const gl = L.world.renderer.getContext(), w = gl.drawingBufferWidth, h = gl.drawingBufferHeight;
   const b = new Uint8Array(w * h * 4);
   gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, b);
   return {w, h, daten: Array.from(b)};
  });
 }
 await page.close();
 return out;
};
const A = await bilder(pfad(process.argv[2])), B = await bilder(pfad(process.argv[3]));
let gesamt = 0, zahl = 0;
for (const k of Object.keys(A)) {
 const a = A[k], b = B[k];
 let s = 0, max = 0, ueber = 0;
 for (let i = 0; i < a.daten.length; i += 4) {
  const d = (Math.abs(a.daten[i] - b.daten[i]) + Math.abs(a.daten[i + 1] - b.daten[i + 1]) +
   Math.abs(a.daten[i + 2] - b.daten[i + 2])) / 3;
  s += d; if (d > max) max = d; if (d > 12) ueber++;
 }
 const n = a.daten.length / 4;
 gesamt += s; zahl += n;
 console.log(`${k.padEnd(16)} mittel ${(s / n).toFixed(3).padStart(7)}  max ${max.toFixed(0).padStart(3)}  Anteil>12 ${(ueber / n * 100).toFixed(2)}%`);
}
console.log('gesamt mittel', (gesamt / zahl).toFixed(3));
await browser.close();
