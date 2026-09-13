// Wolkenschatten messen statt behaupten.
//
// Zwei Fragen, die ein Bildschirmfoto allein nicht beantwortet: liegt
// überhaupt ein Schattenfeld auf der Karte, und wandert es mit dem Wind?
// Gemessen wird die Helligkeit desselben Bodenausschnitts über drei Versätze
// der Decke, und einmal mit abgeschalteter Decke als Bezug.
//
// Gelesen wird direkt aus dem Zeichenpuffer (readPixels), nicht aus einer
// PNG-Datei: pngjs liegt hier nicht, und der Umweg über die Platte bringt
// für zwei Kennzahlen nichts.
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

// Luftbild übers Hinterland: große zusammenhängende Bodenfläche, wenig
// Geometrie, deren Eigenschatten die Messung verfälschen würde.
await p.evaluate(() => {const L = window.LOWTIDE; L.sim.hour = 13; L.sim.weather = 'clear';
  L.luftbild(-620, 260, 420, -620, 0, 60);});
const n0 = await p.evaluate(() => window.LOWTIDE.frames);
await p.waitForFunction(k => window.LOWTIDE.frames > k + 3, n0, {timeout: 90000});

// update() setzt Stärke und Versatz jedes Bild aus Wetter und Wind neu.
// Deshalb: Werte setzen, selbst zeichnen, sofort auslesen — ohne die
// Spielschleife dazwischen.
async function messe(staerke, vx, vy) {
  return await p.evaluate(([s, x, y]) => {
    const L = window.LOWTIDE, w = L.wolken;
    w.staerke.value = s; w.versatz.value.set(x, y);
    L.world.zeichne();
    const gl = L.world.renderer.getContext();
    const bw = gl.drawingBufferWidth, bh = gl.drawingBufferHeight;
    // readPixels zählt von unten. Der Boden steht im unteren Drittel des
    // Bildes, also in den unteren 38 % des Puffers.
    const hoehe = Math.floor(bh * .38);
    const puffer = new Uint8Array(bw * hoehe * 4);
    gl.readPixels(0, 0, bw, hoehe, gl.RGBA, gl.UNSIGNED_BYTE, puffer);
    let summe = 0, quadrate = 0, n = 0;
    for (let i = 0; i < puffer.length; i += 16) {
      const l = puffer[i] * .2126 + puffer[i + 1] * .7152 + puffer[i + 2] * .0722;
      summe += l; quadrate += l * l; n++;
    }
    const mittel = summe / n;
    return {mittel, streuung: Math.sqrt(Math.max(0, quadrate / n - mittel * mittel))};
  }, [staerke, vx, vy]);
}

const aus = await messe(0, 0, 0);
const an = [];
for (const [vx, vy] of [[0, 0], [1.7, 1.2], [3.4, 2.4]]) an.push(await messe(.55, vx, vy));

console.log('Decke   Versatz   mittlere Helligkeit   Streuung');
console.log(`aus     —         ${aus.mittel.toFixed(2).padStart(10)}   ${aus.streuung.toFixed(2).padStart(8)}`);
an.forEach((a, i) => console.log(`an      ${i}         ${a.mittel.toFixed(2).padStart(10)}   ${a.streuung.toFixed(2).padStart(8)}`));

// Nicht jeder einzelne Versatz muss dunkler sein: ein Schattenfeld kann in
// einem Moment neben dem gemessenen Ausschnitt liegen — genau das ist der
// Sinn der Sache. Verlangt wird deshalb der Schnitt über die drei Lagen und
// eine deutliche Spanne zwischen ihnen.
const schnitt = an.reduce((a, x) => a + x.mittel, 0) / an.length;
const spanne = Math.max(...an.map(a => a.mittel)) - Math.min(...an.map(a => a.mittel));
console.log(`\nSchnitt mit Decke ${schnitt.toFixed(2)} gegen ${aus.mittel.toFixed(2)} ohne, Spanne ${spanne.toFixed(2)}`);
const dunkler = schnitt < aus.mittel - 1;
const bewegt = spanne > 1;
console.log('Decke verdunkelt den Boden:            ', dunkler ? 'ja' : 'NEIN');
console.log('Schattenfeld wandert mit dem Versatz:  ', bewegt ? 'ja' : 'NEIN');
if (!dunkler || !bewegt) process.exitCode = 1;
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
