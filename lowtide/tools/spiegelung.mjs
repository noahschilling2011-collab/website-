// Spiegelt das Wasser die Stadt, und spiegelt trockener Asphalt nichts?
//
// Gezählt wird die Deckung im Spiegelziel: der Anteil der Bildpunkte, deren
// Alphawert nicht null ist. Gelesen wird der Puffer roh — bei HalfFloat ist
// 0,0 genau das Bitmuster 0x0000, für eine Deckungszahl reicht das, ohne
// dass Halbfließkomma in JS entpackt werden muss.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';

const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const p = await b.newPage({viewport: {width: 900, height: 560}});
const fehler = [];
p.on('pageerror', e => fehler.push(String(e.message)));
p.on('console', m => {if (m.type() === 'error') fehler.push(m.text());});
await p.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await p.waitForFunction(() => !document.getElementById('startBtn').disabled, {timeout: 120000});
await p.click('#startBtn');
await p.waitForTimeout(1200);

async function deckung(name, x, z, blick, neigung, wetter) {
  await p.evaluate(([x, z, blick, neigung, wetter]) => {
    const L = window.LOWTIDE;
    L.sim.hour = 13; L.sim.weather = wetter;
    L.view(x, z, blick, neigung);
    // Nässe folgt dem Wetter mit Nachlauf; für die Messung einschwingen lassen.
    for (let i = 0; i < 60; i++) L.world.applySky(.5);
  }, [x, z, blick, neigung, wetter]);
  const n = await p.evaluate(() => window.LOWTIDE.frames);
  await p.waitForFunction(k => window.LOWTIDE.frames > k + 3, n, {timeout: 90000});
  const r = await p.evaluate(() => {
    const w = window.LOWTIDE.world;
    // Wasseranteil aus der Marke im Szenenziel, Spiegelanteil aus der Deckung
    // im Spiegelziel. 0x3800 ist die Halbfließkommadarstellung von 0,5.
    const sz = w.post.szene, szb = new Uint16Array(sz.width * sz.height * 4);
    w.renderer.readRenderTargetPixels(sz, 0, 0, sz.width, sz.height, szb);
    let wasser = 0;
    for (let i = 3; i < szb.length; i += 4) if (szb[i] === 0x3800) wasser++;
    const zl = w.post.spiegelZiel, zb = new Uint16Array(zl.width * zl.height * 4);
    w.renderer.readRenderTargetPixels(zl, 0, 0, zl.width, zl.height, zb);
    let getroffen = 0;
    for (let i = 3; i < zb.length; i += 4) if (zb[i] !== 0) getroffen++;
    return {anteil: getroffen / (zb.length / 4), wasser: wasser / (szb.length / 4)};
  });
  console.log(`${name.padEnd(26)} ${wetter.padEnd(6)} ${(r.wasser * 100).toFixed(1).padStart(6)} % Wasser  ${(r.anteil * 100).toFixed(1).padStart(6)} % gespiegelt`);
  return r.anteil;
}

// Blick von der Küste aufs offene Wasser: die Fläche füllt zwei Drittel des
// Bildes, Stege und Skyline stehen darüber. Der erste Versuch stand an der
// Hafenmessstelle aus messung.mjs — dort ist gar kein Wasser im Bild, und die
// Prüfung meldete zu Recht null. Die Stelle war falsch, nicht der Shader.
const kueste = await deckung('Küste, klar', 140, 120, -1.5, .05, 'clear');
const strand = await deckung('Strand, klar', 100, 250, 1.4, .05, 'clear');
// Ohne Wasser und trocken: hier darf nichts gespiegelt werden.
const trocken = await deckung('Innenstadt, trocken', -300, -180, 1.2, .1, 'clear');
// Dieselbe Innenstadt im Regen: jetzt spiegelt der nasse Asphalt.
const nass = await deckung('Innenstadt, Regen', -300, -180, 1.2, .1, 'rain');

console.log('');
console.log('Wasser spiegelt auch bei klarem Wetter:', kueste > .05 && strand > .01 ? 'ja' : 'NEIN');
console.log('Trockener Asphalt spiegelt nichts:     ', trocken < .005 ? 'ja' : 'NEIN');
console.log('Nasser Asphalt spiegelt:               ', nass > .02 ? 'ja' : 'NEIN');
if (!(kueste > .05) || !(strand > .01) || !(trocken < .005) || !(nass > .02)) process.exitCode = 1;
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
