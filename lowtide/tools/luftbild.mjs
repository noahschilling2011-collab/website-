// Luftbilder über die ganze Karte. Eine Bodenperspektive zeigt zehn Meter,
// ein Luftbild eine Region — für die Kontrolle der Weltendichte ist das
// deutlich aussagekräftiger.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
// [Name, Kamera x/y/z, Blickziel x/y/z]
const BILDER = {
  gesamt:    [-100, 900, 620, -100, 0, -60],
  stadt:     [-60, 300, 330, -140, 0, -20],
  nordwest:  [-330, 330, 60, -450, 0, -300],
  vororte:   [-40, 240, -60, -40, 0, -330],
  sued:      [180, 260, 470, 210, 0, 230],
  hafen:     [40, 190, 180, 130, 0, -30],
};
const arg = (n, f) => {const i = process.argv.indexOf('--' + n); return i > -1 ? process.argv[i + 1] : f;};
const namen = arg('bilder', Object.keys(BILDER).join(',')).split(',');
const stunde = Number(arg('hour', 13));
const outDir = arg('shots', 'shots'); mkdirSync(outDir, {recursive: true});
const browser = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const page = await browser.newPage({viewport: {width: 1280, height: 720}});
const probleme = [];
page.on('console', m => {if (m.type() === 'error') probleme.push(m.text());});
page.on('pageerror', e => probleme.push(String(e.stack || e)));
await page.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 180000});
await page.click('#startBtn');
await page.waitForFunction(() => window.LOWTIDE.frames > 1, null, {timeout: 180000});
await page.evaluate(h => {window.LOWTIDE.sim.hour = h; window.LOWTIDE.sim.paused = true;
  for (const el of ['hud','objective','radar','vitals','desktopHelp','quick','toast','prompt','debug']) {
    const n = document.getElementById(el); if (n) n.style.display = 'none';}}, stunde);
for (const name of namen) {
  const [x, y, z, zx, zy, zz] = BILDER[name];
  await page.evaluate(a => window.LOWTIDE.luftbild(...a), [x, y, z, zx, zy, zz]);
  const n0 = await page.evaluate(() => window.LOWTIDE.frames);
  await page.waitForFunction(k => window.LOWTIDE.frames > k + 1, n0, {timeout: 180000});
  const datei = `${outDir}/luft-${name}.png`;
  await page.screenshot({path: datei});
  console.log(datei);
}
await browser.close();
if (probleme.length) {console.log('Fehler:'); for (const p of [...new Set(probleme)]) console.log(' -', p.slice(0, 300)); process.exitCode = 1;}
