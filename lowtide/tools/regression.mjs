// Regressionsprüfung: die Funktionen, die nie kaputtgehen dürfen.
// Eingaben laufen als echte Tastaturereignisse durch dieselbe Kette wie im
// Spiel; alles, was ohne WebGL prüfbar ist, geht direkt an die Simulation.
import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
import {fileURLToPath} from 'node:url';

const browser = await chromium.launch({
 executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']
});
const page = await browser.newPage({viewport: {width: 900, height: 520}});
const konsole = [];
page.on('pageerror', e => konsole.push('pageerror: ' + (e.stack || e.message)));
page.on('console', m => {if (m.type() === 'error') konsole.push('console: ' + m.text());});

let bestanden = 0, gefallen = 0;
const pruefe = (name, ok, zusatz = '') => {
 if (ok) {bestanden++; console.log('  ok      ' + name);}
 else {gefallen++; console.log('  FEHLER  ' + name + (zusatz ? ' — ' + zusatz : ''));}
};
// Auf echte Bilder warten statt auf Zeit: im Software-Rendering dauert
// ein Bild über eine Sekunde.
const bilder = async n => {
 const start = await page.evaluate(() => window.LOWTIDE.frames);
 await page.waitForFunction(k => window.LOWTIDE.frames > k, start + n - 1, {timeout: 90000});
};

await page.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});

console.log('Start');
await page.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 180000});
pruefe('Ladezustand meldet bereit', (await page.textContent('#loadState')).includes('bereit'));
pruefe('window.LOWTIDE vorhanden', await page.evaluate(() => !!window.LOWTIDE?.sim));
await page.click('#startBtn');
await bilder(2);
pruefe('Bildschleife läuft', await page.evaluate(() => window.LOWTIDE.frames) > 1);
pruefe('Spiel nicht pausiert', await page.evaluate(() => !window.LOWTIDE.sim.paused));

console.log('Steuerung');
const vorher = await page.evaluate(() => ({x: window.LOWTIDE.sim.player.x, z: window.LOWTIDE.sim.player.z}));
await page.keyboard.down('w');
await bilder(4);
await page.keyboard.up('w');
const nachher = await page.evaluate(() => ({x: window.LOWTIDE.sim.player.x, z: window.LOWTIDE.sim.player.z}));
pruefe('W bewegt die Figur', Math.hypot(nachher.x - vorher.x, nachher.z - vorher.z) > .3,
 `Δ=${Math.hypot(nachher.x - vorher.x, nachher.z - vorher.z).toFixed(2)}`);

const kameraVor = await page.evaluate(() => window.LOWTIDE.world.camera.position.toArray().map(v => +v.toFixed(2)));
await page.mouse.move(450, 260);
await page.mouse.down();
await page.mouse.move(620, 260, {steps: 6});
await page.mouse.up();
await bilder(2);
const kameraNach = await page.evaluate(() => window.LOWTIDE.world.camera.position.toArray().map(v => +v.toFixed(2)));
pruefe('Maus dreht die Kamera', kameraVor.some((v, i) => Math.abs(v - kameraNach[i]) > .2));

console.log('Figurenwechsel');
const figurVor = await page.evaluate(() => window.LOWTIDE.sim.player.name);
await page.keyboard.press('Tab');
await bilder(1);
const figurNach = await page.evaluate(() => window.LOWTIDE.sim.player.name);
pruefe('Tab wechselt die Figur', figurVor !== figurNach, `${figurVor} → ${figurNach}`);
await page.keyboard.press('Tab');
await bilder(1);
pruefe('Tab wechselt zurück', await page.evaluate(() => window.LOWTIDE.sim.player.name) === figurVor);

console.log('Waffen');
await page.keyboard.press('q');
await bilder(1);
pruefe('Q zieht die Waffe', await page.evaluate(() => window.LOWTIDE.sim.player.armed));
const munitionVor = await page.evaluate(() => window.LOWTIDE.sim.player.ammo);
await page.evaluate(() => {window.LOWTIDE.sim.player.cooldown = 0; window.LOWTIDE.sim.shoot();});
pruefe('Schuss verbraucht Munition', await page.evaluate(() => window.LOWTIDE.sim.player.ammo) === munitionVor - 1);
// Nachladen dauert 1,4 Sekunden Simulationszeit. Im Software-Rendering
// wären das dutzende Bilder, also wird die Zeit direkt vorgespult.
pruefe('Nachladen füllt das Magazin', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.player.ammo = 2; s.reloadJob = null; s.player.cooldown = 0;
 s.reload();
 for (let i = 0; i < 40; i++) s.tick(.05, {});
 return s.player.ammo > 2;
}));
await page.keyboard.press('q');
await bilder(1);

console.log('Fahrzeuge');
const eingestiegen = await page.evaluate(() => {
 const s = window.LOWTIDE.sim, auto = s.cars.find(c => c.model === 'sedan' && c.health > 0);
 s.player.x = auto.x + 1.5; s.player.z = auto.z; s.player.y = 0;
 auto.unlocked = true;
 s.enterExit();
 return !!s.player.car;
});
pruefe('Einsteigen funktioniert', eingestiegen);
await page.keyboard.down('w');
await bilder(4);
await page.keyboard.up('w');
pruefe('Fahrzeug beschleunigt', await page.evaluate(() => Math.abs(window.LOWTIDE.sim.player.car?.speed || 0)) > .5);
const ausgestiegen = await page.evaluate(() => {
 const s = window.LOWTIDE.sim; s.player.car.speed = 0; s.enterExit(); return !s.player.car;
});
pruefe('Aussteigen funktioniert', ausgestiegen);

console.log('Fortbewegung');
// Erst ausschwingen lassen: direkt nach dem Aussteigen steht das Bein noch
// im letzten Schritt.
await bilder(3);
const beinRuhe = await page.evaluate(() => window.LOWTIDE.world.player.userData.legs[0].rotation.x);
await bilder(3);
pruefe('Beine stehen still, solange die Figur steht',
 Math.abs(await page.evaluate(() => window.LOWTIDE.world.player.userData.legs[0].rotation.x) - beinRuhe) < .02);
await page.keyboard.down('w');
const winkel = [];
for (let i = 0; i < 5; i++) {await bilder(1); winkel.push(await page.evaluate(() => window.LOWTIDE.world.player.userData.legs[0].rotation.x));}
await page.keyboard.up('w');
pruefe('Beim Gehen schwingen die Beine', Math.max(...winkel) - Math.min(...winkel) > .1,
 `Spanne ${(Math.max(...winkel) - Math.min(...winkel)).toFixed(3)}`);
pruefe('Die Schrittphase folgt der Strecke, nicht der Uhr', await page.evaluate(() => {
 const u = window.LOWTIDE.world.player.userData;
 return typeof u.strecke === 'number' && u.strecke > 0;
}));
await bilder(4);
pruefe('Nach dem Loslassen kommen die Beine zur Ruhe',
 Math.abs(await page.evaluate(() => window.LOWTIDE.world.player.userData.legs[0].rotation.x)) < .06);

console.log('Ampeln und Licht');
pruefe('Verkehr hält bei Rot und fährt bei Grün', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 // Kreuzung des Rasters bei x = -100, z = 20; das Fahrzeug steht zwölf Meter
 // davor und fährt Richtung +z, also auf der Nord-Süd-Achse.
 const auto = {x: -100, z: 8, yaw: 0};
 const merk = s.time;
 s.time = 20; const beiRot = s.haeltVorAmpel(auto);
 s.time = 5;  const beiGruen = s.haeltVorAmpel(auto);
 s.time = merk;
 return beiRot && !beiGruen;
}));
pruefe('Quer stehende Achse hat gleichzeitig frei', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, merk = s.time;
 const laengs = {x: -112, z: 20, yaw: Math.PI / 2};
 s.time = 20; const frei = !s.haeltVorAmpel(laengs);
 s.time = merk;
 return frei;
}));
pruefe('Scheinwerfer schalten sich nachts ein', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 s.hour = 22;
 const auto = s.cars.find(c => c.model === 'sedan' && c.health > 0);
 auto.unlocked = true; auto.lights = 100;
 s.player.x = auto.x + 1.5; s.player.z = auto.z; s.player.y = 0;
 if (!s.player.car) s.enterExit();
 return !!s.player.car;
}));
await bilder(3);
pruefe('Scheinwerferkegel leuchtet', await page.evaluate(() =>
 window.LOWTIDE.world.fahrlicht.every(l => l.visible && l.intensity > 10)));
await page.evaluate(() => {const s = window.LOWTIDE.sim; s.player.car.speed = 0; s.enterExit(); s.hour = 13;});
await bilder(2);
pruefe('Scheinwerfer aus, sobald niemand fährt', await page.evaluate(() =>
 window.LOWTIDE.world.fahrlicht.every(l => !l.visible)));

console.log('Fahndung');
await page.evaluate(() => window.LOWTIDE.sim.report(4));
pruefe('Meldung erzeugt Sterne', await page.evaluate(() => window.LOWTIDE.sim.stars) > 0);
await bilder(2);
pruefe('Polizei rückt aus', await page.evaluate(() => window.LOWTIDE.sim.cops.some(c => c.active)));
await page.evaluate(() => {const s = window.LOWTIDE.sim; s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;});

console.log('Oberfläche');
await page.keyboard.press('m');
await bilder(1);
pruefe('M öffnet die Karte', await page.evaluate(() => document.getElementById('bigMap').open));
await page.click('#closeMap');
await bilder(1);
pruefe('Karte schließt und Spiel läuft weiter', await page.evaluate(() => !document.getElementById('bigMap').open && !window.LOWTIDE.sim.paused));
pruefe('Minimap wird gezeichnet', await page.evaluate(() => {
 const c = document.getElementById('map'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
 for (let i = 0; i < d.length; i += 4) if (d[i] || d[i + 1] || d[i + 2]) return true;
 return false;
}));
await page.keyboard.press('Escape');
await bilder(1);
pruefe('Escape pausiert', await page.evaluate(() => document.getElementById('pause').open && window.LOWTIDE.sim.paused));
await page.click('#resume');
await bilder(1);
pruefe('Weiterspielen hebt die Pause auf', await page.evaluate(() => !window.LOWTIDE.sim.paused));
await page.keyboard.press('F3');
pruefe('F3 blendet die Messwerte ein', await page.evaluate(() => !document.getElementById('debug').hidden));
await page.keyboard.press('F3');

console.log('Spielstand');
pruefe('Speichern und Laden überstehen den Rundlauf', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.player.money = 4321;
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 s.player.money = 0;
 s.restore(stand);
 s.paused = false;
 return s.player.money === 4321;
}));

console.log('Rendern');
const info = await page.evaluate(() => {const i = window.LOWTIDE.world.renderer.info; return {c: i.render.calls, t: i.render.triangles};});
pruefe('Es wird tatsächlich gezeichnet', info.c > 100, `${info.c} Draw Calls, ${info.t.toLocaleString('de-DE')} Dreiecke`);

// Die Touch-Oberfläche hängt an `@media(pointer:coarse)` und ist auf einem
// Zeigergerät ausgeblendet. Dafür braucht es einen eigenen Browser mit
// Berührungsemulation, sonst prüft man nur unsichtbare Knöpfe. Der erste
// Browser wird vorher geschlossen: zwei Seiten gleichzeitig im
// Software-Rendering bringen jede Playwright-Zeitgrenze zum Platzen.
await browser.close();

console.log('Berührungssteuerung');
const mobilBrowser = await chromium.launch({
 executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
 args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox']
});
const mobil = await mobilBrowser.newContext({viewport: {width: 430, height: 860}, hasTouch: true, isMobile: true});
const handy = await mobil.newPage();
handy.on('pageerror', e => konsole.push('mobil pageerror: ' + (e.stack || e.message)));
handy.on('console', m => {if (m.type() === 'error') konsole.push('mobil console: ' + m.text());});
await handy.goto('file://' + fileURLToPath(new URL('../LOWTIDE.html', import.meta.url)), {waitUntil: 'load'});
await handy.waitForFunction(() => !document.getElementById('startBtn').disabled, null, {timeout: 180000});
pruefe('Startknopf liegt im Bild', await handy.evaluate(() => {
 const r = document.getElementById('startBtn').getBoundingClientRect();
 return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth;
}));
await handy.evaluate(() => document.getElementById('startBtn').click());
await handy.waitForFunction(() => window.LOWTIDE.frames > 1, null, {timeout: 180000});
pruefe('Touch-Oberfläche wird eingeblendet', await handy.evaluate(() =>
 getComputedStyle(document.getElementById('touch')).display !== 'none'));
pruefe('Alle Touch-Knöpfe vorhanden', await handy.evaluate(() => document.querySelectorAll('#actions [data-key]').length >= 6));
pruefe('Kein waagerechtes Überlaufen', await handy.evaluate(() =>
 document.documentElement.scrollWidth <= innerWidth + 1));
const stickKasten = await handy.evaluate(() => {
 const r = document.getElementById('stick').getBoundingClientRect();
 return {x: r.x, y: r.y, w: r.width, h: r.height};
});
pruefe('Stick ist groß genug zum Treffen', stickKasten.w >= 60, `${Math.round(stickKasten.w)} px`);
pruefe('Stick nimmt Berührungen an', await handy.evaluate(k => {
 const stick = document.getElementById('stick');
 const mitteX = k.x + k.w / 2, mitteY = k.y + k.h / 2;
 stick.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, pointerId: 7, clientX: mitteX, clientY: k.y + 4}));
 stick.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, pointerId: 7, clientX: mitteX, clientY: k.y + 4}));
 const versetzt = getComputedStyle(document.getElementById('knob')).transform !== 'none';
 stick.dispatchEvent(new PointerEvent('pointerup', {bubbles: true, pointerId: 7}));
 return versetzt;
}, stickKasten));
pruefe('Aktionsknopf löst aus', await handy.evaluate(() => {
 const knopf = document.querySelector('[data-key="q"]');
 const vor = window.LOWTIDE.sim.player.armed;
 knopf.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, pointerId: 1}));
 knopf.dispatchEvent(new PointerEvent('pointerup', {bubbles: true, pointerId: 1}));
 return window.LOWTIDE.sim.player.armed !== vor;
}));
await handy.screenshot({path: 'shots/mobil.png'});
await mobilBrowser.close();

console.log(`\n${bestanden} bestanden, ${gefallen} gefallen`);
if (konsole.length) {
 console.log('Konsolenausgaben:');
 for (const k of [...new Set(konsole)]) console.log('  -', k.slice(0, 300));
}
process.exitCode = gefallen || konsole.length ? 1 : 0;
