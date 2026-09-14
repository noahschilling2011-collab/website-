// Vollständige Bestandsaufnahme der Szene, nach der Vorgabe des Auftrags:
// headless Chromium (SwiftShader), 1024×576, Startbildschirm, zwanzig Sekunden
// nach dem Laden — die Welt rendert dabei im Hintergrund.
//
// Diese Messung ist bewusst eine andere als die in tools/messung.mjs: dort
// wird im Spiel an festen Orten gemessen, hier die ganze Szene beim Start.
// Zahlen aus beiden Werkzeugen darf man nicht gegeneinander halten.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';
const datei = process.argv[2] || fileURLToPath(new URL('../LOWTIDE.html', import.meta.url));
const browser = await chromium.launch({
 executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']
});
const page = await browser.newPage({viewport: {width: 1024, height: 576}});
const fehler = [];
page.on('pageerror', e => fehler.push('pageerror: ' + (e.stack || e.message).split('\n')[0]));
page.on('console', m => {if (m.type() === 'error') fehler.push('console: ' + m.text().slice(0, 200));});
await page.goto('file://' + datei, {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 240000});
// Zwanzig Sekunden Hintergrundlauf, in Bildern gezählt statt in Sekunden:
// unter Software-Rendering dauert ein Bild mehrere Sekunden, eine Wartezeit
// in Sekunden misst deshalb je nach Maschinenlast etwas anderes.
const f0 = await page.evaluate(() => window.LOWTIDE.frames);
await page.waitForFunction(k => window.LOWTIDE.frames > k + 5, f0, {timeout: 300000});
const zahlen = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, r = w.renderer;
 r.info.reset(); w.zeichne();
 let objekte = 0, meshes = 0, instanzNetze = 0, instanzen = 0, lichter = 0, mitSchatten = 0;
 const materialien = new Set(), geometrien = new Set();
 w.scene.traverse(o => {
  objekte++;
  if (o.isInstancedMesh) {instanzNetze++; instanzen += o.count;}
  else if (o.isMesh) meshes++;
  if (o.isLight) {lichter++; if (o.castShadow) mitSchatten++;}
  if (o.material) for (const m of [].concat(o.material)) materialien.add(m.uuid);
  if (o.geometry) geometrien.add(o.geometry.uuid);
 });
 return {
  calls: r.info.render.calls, dreiecke: r.info.render.triangles,
  objekte, meshes, instanzNetze, instanzen, materialien: materialien.size,
  lichter, mitSchatten,
  geometrien: r.info.memory.geometries, texturen: r.info.memory.textures,
  programme: r.info.programs?.length ?? 0,
  autos: L.sim.cars.length, npcs: L.sim.npcs.length,
  bloecke: L.sim.buildings?.length ?? 0, strassen: L.strassen?.length ?? 0
 };
});
console.log(JSON.stringify({...zahlen, fehler: fehler.length, ersteFehler: fehler.slice(0, 3)}, null, 1));
await browser.close();
