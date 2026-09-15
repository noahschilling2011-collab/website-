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
// Die dritte Person taugt hier nicht: an einer Wand schiebt die Federung die
// Kamera in die Figur, und dann misst man einen Rücken statt einer Gegend.
// Bei HARBOR DISTRICT ist genau das passiert — 92,4 mittlere Helligkeit und
// 9,38 Kontrast waren der Pullover des Spielers. Deshalb freie Kamera, neun
// Meter über dem Ankerpunkt, Blick sechzig Meter waagerecht hinaus. Der
// Dunst bleibt dabei auf Spielstärke; luftbild() setzt ihn sonst auf sechs
// Prozent, was jede Ferne künstlich klar machen würde.
const messe = async (x, z, blick) => {
 await p.evaluate(([x, z, blick]) => {
  const L = window.LOWTIDE; L.sim.hour = 13; L.sim.weather = 'clear';
  const y = L.groundAt(x, z);
  // Sechzehn Meter hoch, Ziel fünfundvierzig Meter voraus auf Bodenhöhe:
  // rund zwanzig Grad Neigung, der Horizont liegt im oberen Drittel. Waagerecht
  // aus neun Metern lag die halbe Bildhöhe voller Ferne im Dunst, und dann
  // misst man den Dunst, nicht die Gegend — der Schnitt fiel dadurch von
  // 13,25 auf 7,73, ohne dass sich an der Karte etwas geändert hätte.
  L.luftbild(x, y + 16, z, x + Math.sin(blick) * 45, y, z + Math.cos(blick) * 45);
  L.world.nebelFaktor = 1;
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

// Der Ankerpunkt einer Region ist eine Beschriftung, kein Standpunkt. Drei
// von fünfzehn Sonden haben deshalb etwas anderes gemessen als die Gegend,
// die sie benennen — und weil sie es immer taten, standen genau diese drei
// oben auf der Arbeitsliste und rührten sich über sechs Umbauten der Karte
// nicht um eine Stelle:
//
//   MERCY RESERVOIR  Anker liegt im See (waterAt true, Grund -1,2)
//   HARBOR DISTRICT  Anker an der Kaikante, beide Richtungen übers Becken
//   TALON RIDGE      Anker auf 88 m Gipfel, beide Richtungen in den Dunst
//
// Eine Sonde muss dort stehen, wo ein Spieler steht, und die Gegend ansehen.
// Geprüft wird das nicht am Bild, sondern an der Welt: entlang der Blicklinie
// dreiundzwanzig Punkte von fünf bis sechzig Metern. Mindestens 70 Prozent
// davon müssen Land sein, und der Boden darf nicht mehr als zwölf Meter unter
// dem Standpunkt wegfallen — sonst füllt Ferne im Dunst die untere Bildhälfte,
// und man misst den Dunst.
const tauglich = async (x, y, z, blick) => await p.evaluate(([x, y, z, blick]) => {
 const L = window.LOWTIDE;
 let land = 0, eben = 0, n = 0;
 for (let d = 5; d <= 60; d += 2.5) {
  const px = x + Math.sin(blick) * d, pz = z + Math.cos(blick) * d;
  n++;
  if (!L.waterAt(px, pz)) land++;
  if (Math.abs(L.groundAt(px, pz) - y) < 12) eben++;
 }
 return land / n >= .7 && eben / n >= .7;
}, [x, y, z, blick]);

// Standpunkt: der Anker, wenn er taugt, sonst der nächste Punkt in Ringen
// darum, der auf Land liegt, nicht in einem Gebäude steckt und von dem aus
// mindestens drei Richtungen taugen.
const RICHTUNGEN = [0, 1, 2, 3, 4, 5].map(k => .7 + k * Math.PI / 3);
const standort = async (ax, az) => {
 for (const radius of [0, 25, 50, 75, 110, 160, 220]) {
  for (let k = 0; k < (radius ? 8 : 1); k++) {
   const w = k * Math.PI / 4;
   const x = ax + Math.cos(w) * radius, z = az + Math.sin(w) * radius;
   const gut = await p.evaluate(([x, z]) => {
    const L = window.LOWTIDE;
    return !L.waterAt(x, z) && !L.sim.blocked({x, z}, 1.5) ? L.groundAt(x, z) : null;
   }, [x, z]);
   if (gut === null) continue;
   const passend = [];
   for (const blick of RICHTUNGEN) if (await tauglich(x, gut, z, blick)) passend.push(blick);
   if (passend.length >= 3) return {x, z, y: gut, richtungen: passend, radius};
  }
 }
 return null;
};

const zeilen = [];
for (const r of regionen) {
 // Gemittelt über alle tauglichen Richtungen statt "die bessere von zweien".
 // Die beste von zwei zu nehmen war die zweite Hälfte des Fehlers: von einem
 // Gipfel gewinnt zuverlässig die Panoramaseite.
 const st = await standort(r.x, r.z);
 if (!st) {zeilen.push({name: r.name, kon: NaN, sat: NaN, m: NaN, n: 0, versetzt: 0}); continue;}
 const werte = [];
 for (const blick of st.richtungen) werte.push(await messe(st.x, st.z, blick));
 const mittel = f => werte.reduce((s, w) => s + w[f], 0) / werte.length;
 zeilen.push({name: r.name, kon: mittel('kon'), sat: mittel('sat'), m: mittel('m'),
  n: werte.length, versetzt: Math.round(Math.hypot(st.x - r.x, st.z - r.z))});
}
zeilen.sort((u, v) => (u.n ? u.kon : Infinity) - (v.n ? v.kon : Infinity));
console.log('Region                     örtl. Kontrast   Sättigung   Mittel   Blicke  Versatz');
for (const z of zeilen)
 console.log(z.n
  ? `${z.name.padEnd(26)} ${z.kon.toFixed(2).padStart(9)}   ${z.sat.toFixed(1).padStart(8)} %  ${z.m.toFixed(1).padStart(6)}   ${String(z.n).padStart(5)}   ${z.versetzt + ' m'}`
  : `${z.name.padEnd(26)} ${'kein Land'.padStart(9)}`);
// Eine Gegend, die ganz aus Wasser besteht, hat keinen Standpunkt. Sie steht
// als "kein Land" in der Liste und geht nicht in den Schnitt ein — sonst wird
// er NaN und die ganze Ausgabe wertlos.
const gemessen = zeilen.filter(z => z.n > 0);
const schnitt = gemessen.reduce((s, z) => s + z.kon, 0) / gemessen.length;
console.log(`\nSchnitt ${schnitt.toFixed(2)} über ${gemessen.length} von ${zeilen.length} Gegenden` +
 ` — die obersten drei sind die Arbeitsliste.`);
await b.close();
if (fehler.length) {console.log('\nFehler:'); for (const f of [...new Set(fehler)]) console.log(' -', f.slice(0, 250)); process.exitCode = 1;}
