// Kontaktbogen: jedes Fahrzeugmodell aus derselben Kamera, gleiche Uhrzeit,
// gleicher Abstand. Damit lässt sich prüfen, ob sich die Formen ohne
// Beschriftung unterscheiden lassen — das ist die Abnahme für neue Karosserien.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const datei = process.argv[2] || fileURLToPath(new URL('../LOWTIDE.html', import.meta.url));
const ordner = process.argv[3] || 'shots/kontakt';
mkdirSync(ordner, {recursive: true});
const browser = await chromium.launch({executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']});
const page = await browser.newPage({viewport: {width: 640, height: 400}});
await page.goto('file://' + datei, {waitUntil: 'load'});
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 240000});
await page.click('#startBtn');
await page.waitForFunction(() => window.LOWTIDE.frames > 2, null, {timeout: 120000});
// Oberfläche aus: sie verdeckte im ersten Anlauf das halbe Fahrzeug.
await page.evaluate(() => {
 for (const id of ['hud', 'ui', 'overlay', 'toast', 'hinweis', 'minimap', 'steuerung'])
  {const e = document.getElementById(id); if (e) e.style.display = 'none';}
 for (const e of document.querySelectorAll('body > *:not(canvas)'))
  if (!e.querySelector('canvas')) e.style.display = 'none';
});
const modelle = await page.evaluate(() => {
 const L = window.LOWTIDE;
 L.sim.paused = true; L.sim.hour = 13; L.sim.weather = 'clear';
 const gesehen = new Map();
 L.sim.cars.forEach((c, i) => {if (!gesehen.has(c.model) && L.world.cars[i]) gesehen.set(c.model, i);});
 return [...gesehen.entries()];
});
for (const [modell, i] of modelle) {
 await page.evaluate(([i]) => {
  const L = window.LOWTIDE, c = L.sim.cars[i];
  // Das Fahrzeug an einen freien Platz stellen statt die anderen auszublenden:
  // world.update setzt die Sichtbarkeit jedes Bild neu aus der Entfernung, und
  // der erste Anlauf zeigte deshalb dreimal denselben fremden Wagen, der
  // zufällig vor der Kamera stand.
  // Jedes Modell auf seinen eigenen Platz: beim ersten Anlauf bekamen alle
  // denselben, und auf dem Bild stapelten sich Bus, Flugzeug und Lieferwagen
  // übereinander.
  c.x = -300 + (L.__platz = (L.__platz || 0) + 22); c.z = 300;
  c.yaw = 0; c.speed = 0; c.wait = 99;
  L.sim.player.car = null;
  L.luftbild(c.x + 9.5, 3.6, c.z + 9.5, c.x, 1.1, c.z);
 }, [i]);
 const f0 = await page.evaluate(() => window.LOWTIDE.frames);
 await page.waitForFunction(k => window.LOWTIDE.frames > k + 2, f0, {timeout: 180000});
 // Kurz vor der Aufnahme noch einmal festnageln: der Verkehr fährt den Wagen
 // sonst zwischen Kamerasetzung und Bild wieder auf seine Route zurück, und
 // im Bild steht dann irgendein anderes Fahrzeug.
 await page.evaluate(([i]) => {
  const L = window.LOWTIDE, c = L.sim.cars[i], m = L.world.cars[i];
  c.speed = 0; c.wait = 999; c.route = [{x: c.x, z: c.z}]; c.target = 0;
  m.position.set(c.x, m.position.y, c.z); m.rotation.y = 0;
  L.luftbild(c.x + 9.5, 3.6, c.z + 9.5, c.x, 1.1, c.z);
  L.world.zeichne();
 }, [i]);
 // Nur die Zeichenfläche, ohne Oberfläche — die HUD verdeckte das halbe Auto.
 writeFileSync(`${ordner}/${modell}.png`, await page.locator('canvas').first().screenshot());
 console.log(modell);
}
await browser.close();
