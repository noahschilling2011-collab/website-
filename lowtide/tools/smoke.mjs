// Startet LOWTIDE headless, spielt ein paar Sekunden und meldet Konsolenfehler + FPS.
// Aufruf: node tools/smoke.mjs [--hour 22] [--shots out/dir] [--seconds 6]
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const arg = (name, fallback) => {
  const i = process.argv.indexOf('--' + name);
  return i > -1 ? process.argv[i + 1] : fallback;
};
const hours = arg('hours', '8,13,18.6,22').split(',').map(Number);
const seconds = Number(arg('seconds', 5));
const outDir = arg('shots', 'shots');
mkdirSync(outDir, {recursive: true});
const file = 'file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url));

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox'],
});
const page = await browser.newPage({viewport: {width: 1280, height: 720}});
const problems = [];
page.on('console', m => {if (m.type() === 'error' || m.type() === 'warning') problems.push(m.type() + ': ' + m.text());});
page.on('pageerror', e => problems.push('pageerror: ' + (e.stack || e.message)));

await page.goto(file, {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
console.log('Ladezustand:', await page.textContent('#loadState'));
await page.click('#startBtn');
await page.waitForTimeout(1500);

// Frames zählen, um zu sehen, dass die Schleife wirklich läuft.
for (const hour of hours) {
  await page.evaluate(h => {
    // Zugriff über das Modul ist gekapselt; die Uhrzeit hängt am Sim-Objekt,
    // das der Debug-Hook window.LOWTIDE bereitstellt.
    if (window.LOWTIDE?.sim) window.LOWTIDE.sim.hour = h;
  }, hour);
  const before = await page.evaluate(() => window.LOWTIDE?.frames ?? -1);
  await page.waitForTimeout(seconds * 1000);
  const after = await page.evaluate(() => window.LOWTIDE?.frames ?? -1);
  const fps = before < 0 ? 'kein Zähler' : ((after - before) / seconds).toFixed(1) + ' fps';
  const name = `${outDir}/hour-${String(hour).replace('.', '_')}.png`;
  await page.screenshot({path: name});
  console.log(`${String(hour).padStart(5)} Uhr → ${name}  (${fps})`);
}

await browser.close();
if (problems.length) {
  console.log('\nProbleme:');
  for (const p of [...new Set(problems)]) console.log(' -', p.slice(0, 400));
  process.exitCode = 1;
} else console.log('\nKeine Konsolenfehler.');
