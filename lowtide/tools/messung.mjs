// Hardwareunabhängige Kennzahlen: Draw Calls, Dreiecke, Geometrien, Texturen.
// Software-Rendering sagt nichts über die Bildrate auf echter Hardware aus,
// die Szenenkomplexität dagegen schon.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';
const orte = [['Kreuzung Downtown', -100, 20, 1.3, .3], ['Hafen', -40, 60, 2.35, .3], ['Strand', 100, 250, 1.4, .22]];
const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const p = await b.newPage({viewport: {width: 1280, height: 720}});
const fehler = [];
p.on('pageerror', e => fehler.push(String(e.message)));
p.on('console', m => {if (m.type() === 'error') fehler.push(m.text());});
await p.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await p.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
await p.click('#startBtn');
await p.waitForTimeout(1500);
console.log('Ort                    Uhr   Draw Calls   Dreiecke   Geometrien  Texturen');
for (const [name, x, z, yaw, pitch] of orte) for (const h of [13, 22]) {
  await p.evaluate(([x, z, yaw, pitch, h]) => {window.LOWTIDE.sim.hour = h; window.LOWTIDE.view(x, z, yaw, pitch, 0);}, [x, z, yaw, pitch, h]);
  const n = await p.evaluate(() => window.LOWTIDE.frames);
  await p.waitForFunction(k => window.LOWTIDE.frames > k + 2, n, {timeout: 90000});
  const m = await p.evaluate(() => {const i = window.LOWTIDE.world.renderer.info; return {c: i.render.calls, t: i.render.triangles, g: i.memory.geometries, x: i.memory.textures};});
  console.log(`${name.padEnd(22)} ${String(h).padStart(3)}   ${String(m.c).padStart(10)}   ${m.t.toLocaleString('de-DE').padStart(8)}   ${String(m.g).padStart(10)}  ${String(m.x).padStart(8)}`);
}
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
