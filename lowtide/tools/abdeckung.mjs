// Abdeckung der Karte: wie viele Bauteile stehen in jeder 100-Meter-Zelle?
// Die Welt liegt als InstancedMesh je Farbe und Zelle vor, also lassen sich
// die Instanzmatrizen direkt auszählen. Leere Landzellen sind Löcher in der
// Karte — Wasserzellen dürfen leer sein.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';

const browser = await chromium.launch({
 executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']
});
const page = await browser.newPage({viewport: {width: 640, height: 400}});
await page.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 180000});

const daten = await page.evaluate(() => {
 const L = window.LOWTIDE, welt = L.world, zellen = new Map();
 const m = new Float32Array(16);
 for (const mesh of welt.bloecke || []) {
  const feld = mesh.instanceMatrix.array;
  for (let i = 0; i < mesh.count; i++) {
   const x = feld[i * 16 + 12], z = feld[i * 16 + 14];
   const k = Math.floor(x / 100) + ':' + Math.floor(z / 100);
   zellen.set(k, (zellen.get(k) || 0) + 1);
  }
 }
 return {zellen: [...zellen], grenzen: L.debug?.bounds || null};
});

const zellen = new Map(daten.zellen);
const {waterAt} = await import('../src/content.js');
const bounds = {left: -580, right: 390, top: -540, bottom: 460};
let land = 0, leer = 0, gesamt = 0;
const zeilen = [];
for (let z = bounds.top; z < bounds.bottom; z += 100) {
 let zeile = String(z).padStart(5) + ' ';
 for (let x = bounds.left; x < bounds.right; x += 100) {
  const n = zellen.get(Math.floor(x / 100) + ':' + Math.floor(z / 100)) || 0;
  gesamt += n;
  const wasser = waterAt(x + 50, z + 50);
  if (!wasser) {land++; if (n < 12) leer++;}
  zeile += wasser ? ' ~~~ ' : n === 0 ? ' ··· ' : String(n).padStart(4) + ' ';
 }
 zeilen.push(zeile);
}
console.log('      ' + Array.from({length: Math.ceil((bounds.right - bounds.left) / 100)},
 (_, i) => String(bounds.left + i * 100).padStart(5)).join(''));
for (const z of zeilen) console.log(z);
console.log(`\n${gesamt.toLocaleString('de-DE')} Bauteile · ${land} Landzellen · ${leer} davon mit weniger als 12 Teilen`);
await browser.close();
