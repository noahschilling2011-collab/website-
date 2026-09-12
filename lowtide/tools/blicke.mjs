// Vergleichsbilder von festen Standorten und Uhrzeiten.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const STANDORTE = {
  hafen:      [-40, 60, 2.35, .30, 0],
  downtown:   [-280, 20, 2.20, .34, 0],
  kreuzung:   [-100, 20, 1.30, .30, 0],
  strand:     [100, 250, 1.40, .22, 0],
  fassade:    [-100, -10, 1.57, .02, 0],
  boulevard:  [-40, -8, 0.05, .10, 0],
  vorort:     [-60, -305, 1.60, .28, 0],
  farm:       [-372, -248, 4.60, .30, 0],
  park:       [-470, -400, 2.20, .30, 0],
  sumpf:      [-400, 60, 3.10, .24, 0],
  flugfeld:   [-300, 300, 1.30, .32, 0],
  insel:      [232, 246, 1.60, .26, 0],
  marina:     [268, 250, 4.60, .26, 0],
  industrie:  [116, -40, 1.90, .34, 0],
  nordrand:   [-160, -470, 1.60, .20, 0],
  westrand:   [-540, -150, 1.90, .24, 0],
  heide:      [-500, 320, 2.60, .22, 0],
  undertow:   [-210, 16, 3.10, .12, 0],
  leitung:    [-145, -500, 0.30, -.08, 0],
};
const arg = (n, f) => {const i = process.argv.indexOf('--' + n); return i > -1 ? process.argv[i + 1] : f;};
const orte = arg('orte', Object.keys(STANDORTE).join(',')).split(',');
const stunden = arg('hours', '13,19,22').split(',').map(Number);
const wetter = arg('wetter', 'clear');
const outDir = arg('shots', 'shots'); mkdirSync(outDir, {recursive: true});
const browser = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const page = await browser.newPage({viewport: {width: 1280, height: 720}});
const probleme = [];
page.on('console', m => {if (m.type() === 'error') probleme.push(m.text());});
page.on('pageerror', e => probleme.push(String(e.stack || e)));
await page.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
await page.click('#startBtn');
await page.waitForTimeout(1200);
await page.evaluate(() => {for (const el of ['hud','objective','radar','vitals','desktopHelp','quick','toast','prompt','debug']) {const n = document.getElementById(el); if (n) n.style.display = 'none';}});
for (const ort of orte) for (const h of stunden) {
  const [x, z, yaw, pitch, hoehe] = STANDORTE[ort];
  await page.evaluate(([x, z, yaw, pitch, hoehe, h, w]) => {const L = window.LOWTIDE; L.sim.hour = h; L.sim.weather = w; L.view(x, z, yaw, pitch, hoehe);}, [x, z, yaw, pitch, hoehe, h, wetter]);
  // Zwei Bilder abwarten: eines setzt die Kamera, das zweite rendert sie.
  // Im Software-Rendering dauert ein Bild über eine Sekunde.
  const start = await page.evaluate(() => window.LOWTIDE.frames);
  await page.waitForFunction(n => window.LOWTIDE.frames > n + 2, start, {timeout: 60000});
  const name = `${outDir}/${ort}-${String(h).replace('.', '_')}-${wetter}.png`;
  await page.screenshot({path: name});
  console.log(name);
}
await browser.close();
if (probleme.length) {console.log('Fehler:'); for (const p of [...new Set(probleme)]) console.log(' -', p.slice(0, 300)); process.exitCode = 1;}
