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
// Jede Waffe trifft innerhalb ihrer Reichweite und dahinter nicht. Vierzig
// Schuss je Entfernung auf ein Ziel genau voraus. Der Taser richtet keinen
// Schaden an, er betäubt — eine Prüfung nur auf Lebenspunkte hielte ihn für
// wirkungslos.
const schuesse = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, q = s.player, aus = {};
 const merk = {x: q.x, z: q.z, waffe: q.weapon, armed: q.armed};
 for (const name of ['pistol', 'rifle', 'shotgun', 'taser']) {
  q.armed = true; q.weapon = name; q.car = null; s.stars = 0; s.heat = 0;
  q.inventory[name] = {ammo: 999, reserve: 999}; q.ammo = 999; q.reserve = 999;
  q.x = -100; q.z = 40; q.y = 0; q.yaw = 0;
  // Die Schusslinie muss frei sein. Mit 530 Figuren und Arbeitswegen quer
  // durch die Stadt stand irgendwann jemand zwischen Schütze und Ziel und
  // fing die Kugel ab — "Und dahinter nicht" fiel, ohne dass an den Waffen
  // etwas falsch war. Alle außer dem Opfer werden für die Dauer der Messung
  // beiseitegeschoben und danach zurückgesetzt.
  // Die Schusslinie muss frei sein. shoot() sucht das nächste Ziel unter
  // `npcs` **und den aktiven Streifen** innerhalb von 65 Metern mit dot > .987
  // — Wagen kommen darin nicht vor, die können nichts abfangen. Der erste
  // Anlauf räumte deshalb das Falsche weg.
  //
  // Der eigentliche Grund ist die Prüfung selbst: jeder Schuss ruft crime()
  // auf, vierzig Schüsse treiben die Fahndungsstufe hoch, und ab da stehen
  // Streifenwagen im Weg — die Pistole traf auf 60 Meter nur noch 37 von 40.
  // Also vor jedem Schuss die Fahndung zurücksetzen und beide Listen räumen.
  if (!s.__weggeraeumt) {
   s.__weggeraeumt = [];
   for (const o of [...s.npcs.slice(1), ...(s.cops || [])]) {
    if (Math.abs(o.x - q.x) < 10 && o.z > q.z - 10 && o.z < q.z + 90) {
     s.__weggeraeumt.push({o, x: o.x, z: o.z}); o.x += 300;
    }
   }
  }
  aus[name] = {};
  for (const dist of [10, 30, 60]) {
   const opfer = s.npcs[0];
   let n = 0;
   for (let k = 0; k < 40; k++) {
    opfer.x = q.x; opfer.z = q.z + dist; opfer.health = 100; opfer.state = 'normal'; opfer.stun = 0;
    q.cooldown = 0; s.reloadJob = null; q.ammo = 999;
    s.stars = 0; s.heat = 0; for (const c of s.cops || []) c.active = false;
    s.shoot();
    if (opfer.health < 100 || (opfer.stun || 0) > 0) n++;
   }
   aus[name][dist] = n;
  }
 }
 for (const e of s.__weggeraeumt || []) {e.o.x = e.x; e.o.z = e.z;}
 s.__weggeraeumt = null;
 q.x = merk.x; q.z = merk.z; q.weapon = merk.waffe; q.armed = merk.armed;
 s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;
 return aus;
});
pruefe('Jede Waffe trifft innerhalb ihrer Reichweite',
 schuesse.pistol[30] === 40 && schuesse.rifle[60] === 40 &&
 schuesse.shotgun[10] === 40 && schuesse.taser[10] === 40,
 Object.entries(schuesse).map(([k, v]) => `${k} ${v[10]}/${v[30]}/${v[60]}`).join(', '));
pruefe('Und dahinter nicht',
 schuesse.shotgun[30] === 0 && schuesse.taser[30] === 0 && schuesse.pistol[60] === 40,
 `Schrot 30 m ${schuesse.shotgun[30]}, Taser 30 m ${schuesse.taser[30]}, Pistole 60 m ${schuesse.pistol[60]}`);
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
// Zwei Kreuzungen auf demselben Fleck fallen im Spiel nicht als Zahl auf,
// sondern als Flimmern an den Ampelgehäusen. Die Liste wird aus den
// Straßensegmenten gerechnet, und dieselbe Achse besteht stellenweise aus
// zwei Segmenten — jede neue Straße kann den Fall zurückbringen.
pruefe('Keine zwei Ampeln auf demselben Platz', await page.evaluate(() => {
 const a = window.LOWTIDE.world.street.ampeln, m = new Set();
 for (const k of a) m.add(k.x + '|' + k.z);
 return m.size === a.length;
}), await page.evaluate(() => {
 const a = window.LOWTIDE.world.street.ampeln, m = new Set();
 for (const k of a) m.add(k.x + '|' + k.z);
 return `${a.length} Kreuzungen auf ${m.size} Plätzen`;
}));
pruefe('Jede Ampel steht an einer Fahrbahn und nicht im Wasser', await page.evaluate(() => {
 const L = window.LOWTIDE;
 return L.world.street.ampeln.every(k => L.onRoad(k.x, k.z, 0) && !L.waterAt(k.x, k.z));
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

// Nicken und Wanken der Karosserie. Bis hierher stand der Wagen starr auf der
// Straße: eine Vollbremsung aus hundert Sachen bewegte kein Grad.
const karosserie = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, w = L.world;
 const c = s.cars.find(x => x.model === 'sedan'), m = w.cars[s.cars.indexOf(c)];
 // Position der Figur merken und am Ende zurücksetzen: dieser Abschnitt
 // schickt sie auf die Südtangente, und die Kameraprüfung im Telefon
 // braucht sie später dort, wo Tiere sind.
 const heim = {x: s.player.x, z: s.player.z, y: s.player.y};
 const setzen = () => {c.x = -700; c.z = 620; c.yaw = Math.PI / 2; c.slip = 0; c.alt = 0;
  c.health = 100; c.fuel = 100; c.tires = 100; c.unlocked = true; s.weather = 'clear';
  s.player.car = c; s.player.x = c.x; s.player.z = c.z; s.player.y = 0; s.stars = 0;
  c._nick = 0; c._wank = 0; c._tempoVorher = undefined; c._gierVorher = undefined;};
 const grad = r => r * 180 / Math.PI;
 const aus = {};
 setzen(); c.speed = 0;
 for (let k = 0; k < 20; k++) {s.driveVehicle(.05, {forward: 1, turn: 0}); w.update(.05, 0, 0, true);}
 aus.gas = grad(m.rotation.x);
 c.speed = 100 / 3.6;
 for (let k = 0; k < 12; k++) {s.driveVehicle(.05, {forward: 0, brake: 1, turn: 0}); w.update(.05, 0, 0, true);}
 aus.bremse = grad(m.rotation.x);
 setzen(); c.speed = 60 / 3.6;
 for (let k = 0; k < 24; k++) {s.driveVehicle(.05, {forward: .6, turn: 1}); w.update(.05, 0, 0, true);}
 aus.rechts = grad(m.rotation.z);
 setzen(); c.speed = 60 / 3.6;
 for (let k = 0; k < 24; k++) {s.driveVehicle(.05, {forward: .6, turn: -1}); w.update(.05, 0, 0, true);}
 aus.links = grad(m.rotation.z);
 setzen(); c.speed = 0;
 for (let k = 0; k < 40; k++) {s.driveVehicle(.05, {forward: 0, turn: 0}); w.update(.05, 0, 0, true);}
 aus.stand = Math.abs(grad(m.rotation.x)) + Math.abs(grad(m.rotation.z));
 s.player.car = null;
 s.player.x = heim.x; s.player.z = heim.z; s.player.y = heim.y;
 return aus;
});
pruefe('Die Nase taucht beim Bremsen und hebt sich beim Gasgeben',
 karosserie.bremse > 1.5 && karosserie.gas < -1.5,
 `Bremse ${karosserie.bremse.toFixed(1)}°, Gas ${karosserie.gas.toFixed(1)}°`);
pruefe('Der Wagen legt sich in die Kurve, seitenrichtig',
 karosserie.rechts < -1.5 && karosserie.links > 1.5,
 `rechts ${karosserie.rechts.toFixed(1)}°, links ${karosserie.links.toFixed(1)}°`);
pruefe('Im Stand steht er waagerecht', karosserie.stand < .2, `${karosserie.stand.toFixed(2)}°`);

// Bremsweg und Ausrollen. Gemessen war der Weg aus 100 km/h 5,2 Meter beim
// Kestrel und 9,8 beim Atlas Hauler, und ohne Gas rollte jedes Fahrzeug in
// 41 Metern aus — das ist keine Motorbremse, das ist eine Handbremse.
const bremswege = await page.evaluate(() => {
 const s = window.LOWTIDE.sim, aus = {};
 const heim = {x: s.player.x, z: s.player.z, y: s.player.y};
 for (const modell of ['sedan', 'truck']) {
  const c = s.cars.find(x => x.model === modell);
  if (!c) continue;
  const setzen = () => {c.x = -700; c.z = 620; c.yaw = Math.PI / 2; c.slip = 0; c.alt = 0;
   c.health = 100; c.fuel = 100; c.tires = 100; c.unlocked = true;
   s.player.car = c; s.player.x = c.x; s.player.z = c.z; s.player.y = 0; s.stars = 0;
   s.weather = 'clear'; c.speed = 100 / 3.6;};
  setzen();
  let x0 = c.x, z0 = c.z;
  for (let i = 0; i < 400 && Math.abs(c.speed) > 1; i++) s.driveVehicle(.05, {forward: 0, brake: 1, turn: 0});
  aus[modell + 'Bremse'] = Math.hypot(c.x - x0, c.z - z0);
  setzen(); x0 = c.x; z0 = c.z;
  for (let i = 0; i < 900 && Math.abs(c.speed) > 1; i++) s.driveVehicle(.05, {forward: 0, turn: 0});
  aus[modell + 'Rollen'] = Math.hypot(c.x - x0, c.z - z0);
  s.player.car = null;
 }
 s.player.x = heim.x; s.player.z = heim.z; s.player.y = heim.y;
 return aus;
});
pruefe('Der Bremsweg aus 100 km/h ist der eines Autos',
 bremswege.sedanBremse > 30 && bremswege.sedanBremse < 60 && bremswege.truckBremse > bremswege.sedanBremse,
 `Kestrel ${bremswege.sedanBremse.toFixed(0)} m, Atlas Hauler ${bremswege.truckBremse.toFixed(0)} m`);
pruefe('Ohne Gas rollt der Wagen weit aus',
 bremswege.sedanRollen > 90, `${bremswege.sedanRollen.toFixed(0)} m`);
await page.evaluate(() => {const s = window.LOWTIDE.sim; if (s.player.car) {s.player.car.speed = 0; s.enterExit();}});

pruefe('Fahrzeug bricht bei voller Lenkung aus', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, auto = s.cars.find(c => c.model === 'muscle') || s.cars[0];
 auto.unlocked = true; auto.slip = 0; auto.speed = 0;
 // Der Wagen stand da, wo die Prüfungen davor ihn gelassen hatten. Bei
 // vollem Gas und vollem Einschlag sind das in drei Sekunden gut sechzig
 // Meter Bogen — und irgendwann steht dort ein Haus. Zuletzt fuhr er in
 // Supply & Style, blieb mit -0,7 m/s an der Wand kleben, und die Prüfung
 // meldete einen Fahrfehler, den es nicht gab. Jetzt ein fester Platz auf
 // der Südtangente: siebzig Meter in jede Richtung frei, trocken, eben.
 auto.x = -700; auto.z = 620; auto.yaw = Math.PI / 2;
 s.player.x = auto.x + 1.5; s.player.z = auto.z; s.player.y = 0;
 if (!s.player.car) s.enterExit();
 for (let i = 0; i < 60; i++) s.driveVehicle(.05, {forward: 1, turn: 1});
 const ausbruch = Math.abs(s.player.car.slip);
 // Geradeaus muss der Schlupf wieder abklingen.
 for (let i = 0; i < 60; i++) s.driveVehicle(.05, {forward: 1, turn: 0});
 const gerade = Math.abs(s.player.car.slip);
 s.player.car.speed = 0;
 return ausbruch > .5 && gerade < ausbruch * .3;
}));
await page.evaluate(() => {const s = window.LOWTIDE.sim; if (s.player.car) {s.player.car.speed = 0; s.enterExit();}});

pruefe('Suchscheinwerfer erst ab fünf Sternen', await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 return !w.suchlicht.visible;
}));
await page.evaluate(() => {const s = window.LOWTIDE.sim; s.stars = 5; s.heat = 10; s.policeHeli.alt = 40;
 s.policeHeli.x = s.player.x; s.policeHeli.z = s.player.z; s.lastSeen = {x: s.player.x, z: s.player.z};});
await bilder(2);
pruefe('Suchscheinwerfer leuchtet bei fünf Sternen', await page.evaluate(() =>
 window.LOWTIDE.world.suchlicht.visible && window.LOWTIDE.world.suchfleck.visible));
// dispatchTimer mit zurücksetzen: sonst steht die Ausrückungssperre aus
// diesem Abschnitt noch, wenn die Fahndungsprüfung gleich meldet.
await page.evaluate(() => {const s = window.LOWTIDE.sim; s.stars = 0; s.heat = 0; s.lastSeen = null;
 s.description = null; s.policeHeli.alt = 0; s.dispatchTimer = 0;
 for (const c of s.cops) {c.active = false; c.route = []; c.blockTarget = null; c.blocking = false;}});
await bilder(2);

// Vier von 34 Straßensegmenten hatten keinen Verkehr: die beiden Längsachsen
// des Westviertels und seine zwei Querstraßen. Ein Wohnviertel, das eigens
// für die größere Karte gebaut wurde, und keine einzige Runde fuhr hindurch.
const netz = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const routen = [...new Set(s.cars.filter(c => c.type === 'traffic' && c.route)
  .map(c => JSON.stringify(c.route)))].map(JSON.parse);
 const beruehrt = new Set();
 let neben = 0, proben = 0;
 for (const rt of routen) for (let i = 0; i < rt.length; i++) {
  const a = rt[i], b = rt[(i + 1) % rt.length];
  const laenge = Math.hypot(b.x - a.x, b.z - a.z);
  for (let t = 0; t <= 1; t += Math.max(.01, 4 / Math.max(laenge, 1))) {
   const x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t;
   proben++;
   if (!L.onRoad(x, z, 0)) neben++;
   L.strassen.forEach((r, k) => {
    if (x > Math.min(r.x1, r.x2) - r.w / 2 - 2 && x < Math.max(r.x1, r.x2) + r.w / 2 + 2 &&
        z > Math.min(r.z1, r.z2) - r.w / 2 - 2 && z < Math.max(r.z1, r.z2) + r.w / 2 + 2) beruehrt.add(k);
   });
  }
 }
 return {segmente: L.strassen.length, beruehrt: beruehrt.size, routen: routen.length, neben, proben};
});
pruefe('Auf jeder Straße fährt Verkehr', netz.beruehrt === netz.segmente,
 `${netz.beruehrt} von ${netz.segmente} Segmenten, ${netz.routen} Runden`);
pruefe('Keine Verkehrsrunde führt über die Wiese', netz.neben === 0,
 `${netz.neben} von ${netz.proben} Proben neben der Fahrbahn`);

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

console.log('Tierwelt');
pruefe('Möwen, Fische, Delfine und Alligatoren sind angelegt', await page.evaluate(() => {
 const w = window.LOWTIDE.world.tiere;
 return w.moewen.length > 40 && w.fische.length > 60 && w.delfine.length >= 5 && w.alligatoren.length >= 6;
}));
pruefe('Die Tiere bewegen sich', await page.evaluate(async () => {
 const w = window.LOWTIDE.world.tiere;
 const vorher = w.fische.slice(0, 5).map(f => f.x + f.z);
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 return w.fische.slice(0, 5).some((f, i) => Math.abs(f.x + f.z - vorher[i]) > 1e-4);
}));
pruefe('Fische bleiben im Wasser', await page.evaluate(() => {
 const w = window.LOWTIDE.world.tiere, wasser = window.LOWTIDE.waterAt;
 return w.fische.every(f => wasser(f.x, f.z));
}));
pruefe('Ein Schuss schreckt sie auf', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 L.world.tiere.scheu = 0;
 s.player.armed = true; s.player.cooldown = 0; s.player.ammo = 12; s.shoot();
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const geschreckt = L.world.tiere.scheu > .3;
 s.player.armed = false; s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;
 return geschreckt;
}));
pruefe('Die Kamera erkennt Tiere im Bild', await page.evaluate(() => {
 const L = window.LOWTIDE, t = L.world.tiere;
 // imBild() zählt alle Tiere im Sichtkegel. Die Prüfung verglich einfach
 // „nach vorn" gegen „nach hinten" und verließ sich darauf, dass hinter der
 // Figur zufällig weniger Möwen und Fische liegen als davor. Sobald ein
 // anderer Abschnitt die Tierwelt ein paar Sekunden weiterlaufen ließ, kippte
 // sie. Jetzt bleibt für die Dauer der Prüfung genau ein Alligator übrig.
 const merk = {m: t.moewen, f: t.fische, d: t.delfine, a: t.alligatoren};
 const einer = t.alligatoren[0];
 t.moewen = []; t.fische = []; t.delfine = []; t.alligatoren = [einer];
 const vorn = t.imBild({x: einer.x, z: einer.z - 12}, 0);
 const hinten = t.imBild({x: einer.x, z: einer.z - 12}, Math.PI);
 const weit = t.imBild({x: einer.x, z: einer.z - 90}, 0);
 t.moewen = merk.m; t.fische = merk.f; t.delfine = merk.d; t.alligatoren = merk.a;
 return vorn === 1 && hinten === 0 && weit === 0;
}));

console.log('Detailstufen');
pruefe('Ferne Figuren und Fahrzeuge laufen über die grobe Stufe', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 if (s.player.car) {s.player.car.speed = 0; s.enterExit();}
 s.player.x = -40; s.player.z = 60;
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const w = L.world;
 return w.figurFern.anzahl + w.autoFern.anzahl > 0;
}));
pruefe('Die grobe Stufe kostet wenige Draw Calls', await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 // Zwei Vorbilder mit je einer Handvoll Materialien, unabhängig von der Zahl
 // der Exemplare.
 return w.figurFern.netze.length <= 6 && w.autoFern.netze.length <= 6;
}));
pruefe('Nahe Exemplare bleiben detailliert', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim, w = L.world;
 const n = s.npcs.find(x => x.health > 0);
 s.player.x = n.x + 2; s.player.z = n.z + 2;
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const i = s.npcs.indexOf(n);
 return w.npcs[i].visible;
}));

console.log('Aktivitäten');
pruefe('Rennen verlangt das passende Fahrzeug', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.stars = 0; s.activity = null;
 if (s.player.car) {s.player.car.speed = 0; s.enterExit();}
 s.startActivity('race:boot');
 const ohneFahrzeug = !s.activity;
 const auto = s.cars.find(c => c.model === 'sedan' && c.health > 0);
 auto.unlocked = true;
 s.player.x = auto.x + 1.5; s.player.z = auto.z; s.player.y = 0;
 if (!s.player.car) s.enterExit();
 s.startActivity('race:boot');       // Landfahrzeug auf einer Wasserstrecke
 const falschesMedium = !s.activity;
 s.startActivity('race:west');
 const passt = s.activity?.kind === 'race' && s.activity.kurs === 'west';
 return ohneFahrzeug && falschesMedium && passt;
}));
pruefe('Die Strecke wird mit ihren Kontrollpunkten gefahren', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, a = s.activity;
 if (!a) return false;
 const punkte = a.points.length;
 for (const punkt of a.points) {
  if (!s.activity) break;
  s.player.x = punkt.x; s.player.z = punkt.z;
  if (s.player.car) {s.player.car.x = punkt.x; s.player.car.z = punkt.z;}
  s.tick(.05, {});
 }
 return punkte >= 4 && !s.activity && (s.highScores['race:west'] || 0) > 0;
}));
await page.evaluate(() => {const s = window.LOWTIDE.sim; if (s.player.car) {s.player.car.speed = 0; s.enterExit();}});
pruefe('Der Schießstand verlangt eine gezogene Waffe', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 // Die Streckenfahrt vorher kann Passanten erwischt und damit eine Fahndung
 // ausgelöst haben; startActivity verweigert dann jede Aktivität.
 s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;
 s.activity = null; s.player.armed = false;
 s.startActivity('range');
 const ohne = !s.activity;
 s.player.armed = true;
 s.startActivity('range');
 const mit = s.activity?.kind === 'range';
 s.activity = null; s.player.armed = false;
 return ohne && mit;
}));
pruefe('Der Bergungsauftrag zählt Fundstellen und zahlt aus', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, orte = window.LOWTIDE.schatzOrte;
 s.schatzIndex = 0; s.activity = null; s.stars = 0;
 s.startActivity('treasure');
 if (!s.activity) return false;
 const geld = s.player.money;
 const ziel = s.objective();
 s.player.x = ziel.x; s.player.z = ziel.z; s.player.car = null;
 s.action();
 return s.schatzIndex === 1 && s.player.money > geld && orte.length === 6;
}));
await page.evaluate(() => {window.LOWTIDE.sim.activity = null; window.LOWTIDE.sim.schatzIndex = 0;});

// Vier von fünf Rennen waren nicht zu starten. Der Dialog am Marker ging nur
// zu Fuß auf — im Fahrzeug zählten nur Werkstatt und Tankstelle —, und
// startActivity verlangt ein Fahrzeug. Beides zugleich ging nicht.
const rennstart = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, aus = {};
 const fahrzeug = {race: 'muscle', drag: 'muscle', moto: 'motorcycle', boat: 'boat', jet: 'jetski'};
 for (const [marke, modell] of Object.entries(fahrzeug)) {
  const l = L.orte[marke], c = s.cars.find(c => c.model === modell);
  if (!c) {aus[marke] = 'kein ' + modell; continue;}
  s.stars = 0; s.heat = 0; s.activity = null;
  c.health = 100; c.fuel = 100; c.unlocked = true; c.speed = 0;
  const wasser = ['boat', 'jetski'].includes(modell);
  let platz = null;
  for (let d = 0; d <= 12 && !platz; d += .5) for (let a = 0; a < 360; a += 8) {
   const x = l.x + Math.cos(a * Math.PI / 180) * d, z = l.z + Math.sin(a * Math.PI / 180) * d;
   if (wasser !== !!L.waterAt(x, z) || s.blocked({x, z}, .8)) continue;
   platz = {x, z}; break;
  }
  if (!platz) {aus[marke] = 'kein Platz für ' + modell; continue;}
  c.x = platz.x; c.z = platz.z;
  s.player.car = c; s.player.x = c.x; s.player.z = c.z; s.player.y = 0;
  const antwort = s.action();
  if (typeof antwort === 'string' && antwort.startsWith('place:')) s.startActivity(l.kind);
  aus[marke] = s.activity ? s.activity.kurs : 'kein Rennen (' + antwort + ')';
  s.activity = null; s.player.car = null;
 }
 return aus;
});
pruefe('Alle fünf Rennen lassen sich am Marker starten',
 rennstart.race === 'west' && rennstart.drag === 'drag' && rennstart.moto === 'moto' &&
 rennstart.boat === 'boot' && rennstart.jet === 'jet', JSON.stringify(rennstart));
// Ein Bootsrennen braucht Wasser in Reichweite des Markers, sonst kommt man
// mit dem Boot nie nah genug heran. Der Regattamarker lag achtzehn Meter
// landeinwärts.
pruefe('Die Wasserrennen haben Wasser am Marker', await page.evaluate(() => {
 const L = window.LOWTIDE;
 return ['boat', 'jet'].every(id => {
  const l = L.orte[id];
  for (let d = 0; d <= 8; d += .5) for (let a = 0; a < 360; a += 10)
   if (L.waterAt(l.x + Math.cos(a * Math.PI / 180) * d, l.z + Math.sin(a * Math.PI / 180) * d)) return true;
  return false;
 });
}));
// Die Marina lag mit Steg und Booten auf Sand und Wiese.
pruefe('Die Marina liegt im Wasser', await page.evaluate(() => {
 const L = window.LOWTIDE;
 // Hauptsteg, Fingerstege und Bootsreihe müssen über Wasser stehen.
 return [226, 217, 214].every(x => [220, 245, 270].every(z => L.waterAt(x, z)));
}));

console.log('Eigentum');
pruefe('Kaufen scheitert ohne Geld', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.besitz = {}; s.player.money = 10;
 return s.kaufeImmobilie('villa') === false && !s.besitz.villa;
}));
pruefe('Kaufen bucht ab und trägt ein', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.player.money = 5000;
 const ok = s.kaufeImmobilie('trailer');
 return ok && !!s.besitz.trailer && s.player.money === 4400 && s.ertraege() === 35;
}));
pruefe('Dasselbe Objekt lässt sich nicht zweimal kaufen', await page.evaluate(() =>
 window.LOWTIDE.sim.kaufeImmobilie('trailer') === false));
pruefe('Der Zahltag schreibt die Erträge gut', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const vorher = s.player.money;
 s.letzterZahltag = -1;
 s.zahltag();
 const einmal = s.player.money - vorher;
 s.zahltag();   // derselbe Tag darf nicht doppelt zahlen
 return einmal === 35 && s.player.money - vorher === 35;
}));
pruefe('Werkstattanteil senkt die Reparaturkosten', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, l = window.LOWTIDE.orte;
 s.player.money = 9000; s.besitz = {};
 s.player.x = l.garage.x; s.player.z = l.garage.z; s.serviceLocation = 'garage';
 const auto = s.cars.find(c => c.model === 'sedan');
 auto.x = l.garage.x; auto.z = l.garage.z; auto.health = 40;
 const vorOhne = s.player.money; s.buy('car:repair');
 const ohne = vorOhne - s.player.money;
 s.besitz.werkstatt = {seit: 0};
 auto.health = 40;
 const vorMit = s.player.money; s.buy('car:repair');
 const mit = vorMit - s.player.money;
 s.besitz = {};
 return ohne === 150 && mit < ohne;
}));
pruefe('Eigentum übersteht den Spielstand-Rundlauf', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.besitz = {loft: {seit: 1}};
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 s.besitz = {};
 s.restore(stand); s.paused = false;
 return !!s.besitz.loft && s.ertraege() === 110;
}));

console.log('Radio');
pruefe('Audiokontext läuft nach dem Start', await page.evaluate(() =>
 !!window.LOWTIDE.world && document.body.classList.contains('playing')));
pruefe('Radio ist eingerichtet und hat mehrere Sender', await page.evaluate(() => {
 const r = window.LOWTIDE.radio;
 return !!r && r.constructor.name === 'Radio' && window.LOWTIDE.sender.length >= 6;
}));
pruefe('N schaltet den Sender weiter', await page.evaluate(() => {
 const r = window.LOWTIDE.radio, vorher = r.index;
 window.dispatchEvent(new KeyboardEvent('keydown', {key: 'n', bubbles: true}));
 return r.index !== vorher;
}));
pruefe('Radio schweigt zu Fuß', await page.evaluate(async () => {
 const L = window.LOWTIDE;
 if (L.sim.player.car) {L.sim.player.car.speed = 0; L.sim.enterExit();}
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 return L.radio.laut < .01;
}));
pruefe('Im Fahrzeug läuft der Sender und plant Noten', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 L.radio.waehle(1);
 const auto = s.cars.find(c => c.model === 'sedan' && c.health > 0);
 auto.unlocked = true;
 s.player.x = auto.x + 1.5; s.player.z = auto.z; s.player.y = 0;
 if (!s.player.car) s.enterExit();
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const vorher = L.radio.schritt;
 for (let i = 0; i < 40; i++) L.radio.tick();
 await new Promise(r => setTimeout(r, 450));
 L.radio.tick();
 return L.radio.laut > .1 && L.radio.schritt !== vorher;
}));
await page.evaluate(() => {const s = window.LOWTIDE.sim; if (s.player.car) {s.player.car.speed = 0; s.enterExit();}});

console.log('Klang');
// Die Welt hatte zwei Geräusche: den Motor-Oszillator und einen Schuss —
// nachgezählt an den Aufrufstellen, `tone()` kam genau einmal vor. Wer zu Fuß
// ging, hörte nichts, obwohl Wetter, Wasser und Fahndungsstufe alle im
// Zustand stehen. Geprüft wird an den Reglerwerten der Audioknoten, nicht am
// Klang: hören kann diese Umgebung nichts, und das steht so im README.
const ton = await page.evaluate(async () => {
 const k = window.LOWTIDE.klang;
 if (!k) return null;
 const lies = () => ({wind: k.wind.regler.gain.value, regen: k.regen.regler.gain.value,
  brandung: k.brandung.regler.gain.value, sirene: k.sirenenRegler.gain.value});
 const grund = {wetter: 'clear', tempo: 0, geduckt: false, rennt: false, imWagen: false,
  wasserAbstand: 999, sterne: 0, polizeiAbstand: 999, pausiert: false};
 const fahre = (z, n) => {for (let i = 0; i < n; i++) k.update(1 / 60, z); return lies();};
 const aus = {};
 aus.klar = fahre(grund, 240);
 aus.regen = fahre({...grund, wetter: 'rain'}, 240);
 aus.sturm = fahre({...grund, wetter: 'storm'}, 240);
 aus.imWagen = fahre({...grund, wetter: 'storm', imWagen: true}, 240);
 aus.fern = fahre({...grund}, 240);
 aus.amWasser = fahre({...grund, wasserAbstand: 5}, 240);
 aus.ruhig = fahre({...grund}, 240);
 aus.fahndung = fahre({...grund, sterne: 3, polizeiAbstand: 40}, 240);
 const vorGehen = k.gebaut; fahre({...grund, tempo: 4.5}, Math.round(30 / 4.5 * 60));
 aus.schritteGehend = k.gebaut - vorGehen;
 const vorSchleichen = k.gebaut; fahre({...grund, tempo: 2, geduckt: true}, Math.round(30 / 2 * 60));
 aus.schritteGeduckt = k.gebaut - vorSchleichen;
 for (let i = 0; i < 40; i++) k.aufprall(10);
 await new Promise(r => setTimeout(r, 1400));
 aus.nochOffen = k.offen;
 fahre(grund, 240);
 return aus;
});
pruefe('Es gibt überhaupt einen Klang', !!ton);
pruefe('Der Ton kennt das Wetter',
 ton && ton.klar.wind < ton.regen.wind && ton.regen.wind < ton.sturm.wind &&
 ton.klar.regen < .001 && ton.sturm.regen > ton.regen.regen,
 ton && `Wind ${ton.klar.wind.toFixed(4)}/${ton.regen.wind.toFixed(4)}/${ton.sturm.wind.toFixed(4)}, Regen ${ton.regen.regen.toFixed(4)}/${ton.sturm.regen.toFixed(4)}`);
pruefe('Im Wagen ist es leiser als draußen',
 ton && ton.imWagen.wind < ton.sturm.wind * .6,
 ton && `${ton.imWagen.wind.toFixed(4)} gegen ${ton.sturm.wind.toFixed(4)}`);
pruefe('Am Wasser rauscht die Brandung, sonst nicht',
 ton && ton.fern.brandung < .002 && ton.amWasser.brandung > .02,
 ton && `${ton.fern.brandung.toFixed(4)} fern, ${ton.amWasser.brandung.toFixed(4)} nah`);
pruefe('Die Sirene heult nur bei Fahndung',
 ton && ton.ruhig.sirene < .001 && ton.fahndung.sirene > .008,
 ton && `${ton.ruhig.sirene.toFixed(4)} ohne, ${ton.fahndung.sirene.toFixed(4)} bei drei Sternen`);
pruefe('Schritte fallen nach zurückgelegtem Weg',
 ton && ton.schritteGehend >= 17 && ton.schritteGehend <= 24 &&
 ton.schritteGeduckt > ton.schritteGehend,
 ton && `${ton.schritteGehend} auf 30 m gehend, ${ton.schritteGeduckt} geduckt`);
pruefe('Einmalige Klänge räumen ihre Knoten wieder ab',
 ton && ton.nochOffen <= 4, ton && `${ton.nochOffen} von 80 Knoten noch offen, 1,4 s nach 40 Aufprallen`);
// Der Motor war ein einzelner Sägezahn: Frequenz = Grundton plus Tempo mal
// drei, Lautstärke fest. Linear, unbegrenzt, ohne Gänge und ohne Unterschied
// zwischen Lastwagen, Boot und Hubschrauber.
const motor = await page.evaluate(async () => {
 const L = window.LOWTIDE, k = L.klang, T = L.fahrzeuge;
 if (!k) return null;
 // Die Tonhöhe kommt aus setTargetAtTime und steht nicht sofort im Wert.
 // Gemessen wird deshalb die Kurve über die Sollformel — dieselbe, die
 // Klang.motor() rechnet — und die Regler über eine echte Wartezeit.
 const kurve = name => {
  const typ = T[name], medium = typ.medium || 'land', grund = typ.sound || 45, aus = [];
  for (let v = 0; v <= typ.max; v += typ.max / 24) {
   let h;
   if (medium === 'land') {
    const st = 5, sp = Math.max(4, typ.max / st), g = Math.min(st - 1, Math.floor(v / sp));
    const ig = Math.max(0, Math.min(1, (v - g * sp) / sp));
    h = grund * (.62 + ig * .78) * (1 + g * .07);
   } else {
    const ig = Math.max(0, Math.min(1, v / Math.max(6, typ.max)));
    h = grund * (.7 + ig * 1.5);
   }
   aus.push(h);
  }
  return aus;
 };
 const spruenge = a => {let n = 0; for (let i = 1; i < a.length; i++) if (a[i] < a[i - 1] - .5) n++; return n;};
 const land = ['sedan', 'super', 'truck'].map(n => spruenge(kurve(n)));
 const frei = ['boat', 'helicopter', 'plane'].map(n => spruenge(kurve(n)));
 const tiefe = {};
 for (const n of ['sedan', 'boat', 'helicopter']) {k.motor(1 / 60, T[n], 10, 1); tiefe[n] = k.pulsTiefe.gain.value;}
 // Gelesen wird der zuletzt befohlene Sollwert, nicht der Regler: der nähert
 // sich über setTargetAtTime, und die laufende Spielschleife schreibt jedes
 // Bild einen neuen hinein. Die erste Fassung setzte den Zustand und wartete
 // 420 ms — und maß dann den Wagen des Spielers statt den eigenen Befehl:
 // 0,0025 „mit Gas" gegen 0,0114 „ohne".
 k.motor(1 / 60, T.sedan, 15, 1); const mitGas = k.motorPegel;
 k.motor(1 / 60, T.sedan, 15, 0); const ohneGas = k.motorPegel;
 k.motor(1 / 60, null, 0, 0); const ohneWagen = k.motorPegel;
 let aufprallLaeuft = true;
 try {k.aufprall(8);} catch (e) {aufprallLaeuft = String(e.message);}
 return {land, frei, tiefe, mitGas, ohneGas, ohneWagen, aufprallLaeuft};
});
pruefe('Der Motor schaltet an Land und nicht auf dem Wasser',
 motor && motor.land.every(n => n === 4) && motor.frei.every(n => n === 0),
 motor && `Abwärtssprünge an Land ${motor.land.join('/')}, auf Wasser und in der Luft ${motor.frei.join('/')}`);
pruefe('Rotor und Schiffsschraube schlagen, ein Autoreifen nicht',
 motor && motor.tiefe.sedan === 0 && motor.tiefe.boat > 0 && motor.tiefe.helicopter > motor.tiefe.boat,
 motor && `Wagen ${motor.tiefe.sedan}, Boot ${motor.tiefe.boat}, Hubschrauber ${motor.tiefe.helicopter}`);
pruefe('Gas geben ist lauter als rollen', motor && motor.mitGas > motor.ohneGas * 1.2,
 motor && `${motor.mitGas.toFixed(4)} mit Gas, ${motor.ohneGas.toFixed(4)} ohne`);
pruefe('Ohne Fahrzeug ist der Motor still', motor && motor.ohneWagen < .002,
 motor && motor.ohneWagen.toFixed(5));
// schlag() ist die Methode für den dumpfen Teil eines Aufpralls. Der
// Modulationsoszillator des Motors hieß im ersten Anlauf genauso und hätte
// sie als Eigenschaft verdeckt — aufprall() wäre beim ersten laufenden Motor
// mit einem TypeError ausgestiegen.
pruefe('Der Aufprall überlebt einen laufenden Motor', motor && motor.aufprallLaeuft === true,
 motor && String(motor.aufprallLaeuft));

console.log('Innenräume');
pruefe('Alle acht Serviceräume sind eingerichtet', await page.evaluate(() =>
 (window.LOWTIDE.world.innenLampen || []).length >= 8));
pruefe('Innenlicht geht an, sobald man den Raum betritt', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 s.player.x = -270; s.player.z = 123;   // Nora’s Diner
 s.player.car = null; s.player.y = 0;
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 return L.world.innenLichter.some(l => l.visible && l.intensity > 10);
}));
pruefe('Innenlicht geht aus, wenn man weit weg ist', await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 s.player.x = -40; s.player.z = 60;
 await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 return L.world.innenLichter.every(l => !l.visible);
}));

console.log('Telefon');
await page.keyboard.press('p');
await bilder(1);
pruefe('P öffnet das Telefon', await page.evaluate(() => !document.getElementById('phone').hidden));
pruefe('Startseite zeigt alle Apps', await page.evaluate(() =>
 document.querySelectorAll('#phoneKacheln button').length >= 10));
// Jede App muss etwas anzeigen. Eine Kachel, die auf eine leere Seite führt,
// ist ein Menüpunkt und kein Programm — geprüft wird die Textlänge, die Zahl
// der Knöpfe und ob eine Leinwand darin steckt.
const appInhalte = await page.evaluate(() => {
 const namen = [...document.querySelectorAll('#phoneKacheln button')].map(b => b.textContent.trim());
 const aus = {};
 for (const n of namen) {
  const b = [...document.querySelectorAll('#phoneKacheln button')].find(x => x.textContent.trim() === n);
  b.click();
  const i = document.getElementById('phoneInhalt');
  const text = (i?.textContent || '').replace(/\s+/g, ' ').trim();
  aus[n] = {laenge: text.length, teile: i ? i.querySelectorAll('button, canvas, img').length : 0};
  document.getElementById('phoneHome')?.click();
 }
 return aus;
});
pruefe('Jede App des Telefons zeigt etwas an',
 Object.values(appInhalte).every(a => a.laenge >= 25 || a.teile > 0),
 Object.entries(appInhalte).map(([k, v]) => `${k} ${v.laenge}`).join(', '));
// Und die Kamera legt ihre Aufnahme wirklich in der Galerie ab.
pruefe('Die Kamera füllt die Galerie', await page.evaluate(async () => {
 const hin = n => {const b = [...document.querySelectorAll('#phoneKacheln button')].find(x => x.textContent.includes(n)); b && b.click();};
 hin('KAMERA');
 const vorher = (window.LOWTIDE.sim.fotos || []).length;
 document.querySelector('#phoneInhalt button')?.click();
 await new Promise(r => setTimeout(r, 400));
 const nachher = (window.LOWTIDE.sim.fotos || []).length;
 document.getElementById('phoneHome')?.click();
 hin('GALERIE');
 const bilder = document.getElementById('phoneInhalt')?.querySelectorAll('img, canvas').length || 0;
 document.getElementById('phoneHome')?.click();
 return nachher === vorher + 1 && bilder >= 1;
}));
pruefe('Telefon pausiert das Spiel', await page.evaluate(() => window.LOWTIDE.sim.paused));
pruefe('TIDELINE zeigt, was in der Welt passiert ist', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.post('@pruefung', 'Ein Beitrag aus dem Prüflauf.');
 [...document.querySelectorAll('#phoneKacheln button')].find(b => b.textContent.includes('TIDELINE')).click();
 return document.getElementById('phoneInhalt').textContent.includes('Ein Beitrag aus dem Prüflauf.');
}));
await page.click('#phoneHome');
pruefe('Bank zeigt Kontostand und Bewegungen', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.buchung('Prüflauf', -77);
 [...document.querySelectorAll('#phoneKacheln button')].find(b => b.textContent.includes('BANK')).click();
 const text = document.getElementById('phoneInhalt').textContent;
 return text.includes('Kontostand') && text.includes('Prüflauf');
}));
await page.click('#phoneHome');
pruefe('Kamera nimmt ein echtes Bild auf', await page.evaluate(() => {
 [...document.querySelectorAll('#phoneKacheln button')].find(b => b.textContent.includes('KAMERA')).click();
 [...document.querySelectorAll('#phoneInhalt button')].find(b => b.textContent === 'Aufnehmen').click();
 const f = window.LOWTIDE.sim.fotos?.[0];
 return !!f && f.daten.startsWith('data:image/jpeg') && f.daten.length > 4000;
}));
await page.keyboard.press('p');
await bilder(1);
pruefe('P schließt das Telefon und gibt das Spiel frei', await page.evaluate(() =>
 document.getElementById('phone').hidden && !window.LOWTIDE.sim.paused));

console.log('Akt 1: das Lagerhaus');
// Der erste Akt hatte keine Prüfung. Er läuft über vier feste Punkte im
// Lagerhaus — Tür, Sicherung, Festplatte, Treffpunkt —, und jeder davon
// muss betretbar sein und den nächsten Schritt auslösen. Ohne diese
// Prüfung wäre jede Verschiebung des Gebäudes ein Blindflug.
const akt1 = await page.evaluate(() => {
 const L = window.LOWTIDE, sim = L.sim, P = L.plaetze, out = {};
 sim.paused = false; sim.stars = 0; sim.heat = 0;
 const p = sim.player; p.car = null; p.y = 0;
 const hin = (o, dz = 0) => {p.x = o.x; p.z = o.z + dz; p.y = 0;};
 // Jeder Punkt muss frei stehen — eine Wand darin hieße: nicht erreichbar.
 out.freiTuer = !sim.blocked(P.door, .4);
 out.freiSicherung = !sim.blocked(P.fuse, .4);
 out.freiPlatte = !sim.blocked(P.disk, .4);
 out.freiTreff = !sim.blocked(P.safe, .4);
 sim.mission = 1; sim.doorOpen = false; sim.camera = true;
 hin(P.door, 2); out.tuer = sim.action();
 hin(P.fuse, 1); out.sicherung = sim.action(); out.nachSicherung = sim.mission;
 hin(P.disk, 1); out.platte = sim.action(); out.nachPlatte = sim.mission;
 hin(P.safe, 2); out.finale = sim.action();
 // Und der Weg vom Tor zur Festplatte darf nicht durch eine Wand gehen.
 const tor = L.world.sim.gate;
 let frei = true;
 for (let t = 0; t <= 1; t += .04) {
  const x = tor.x + (P.disk.x - tor.x) * t, z = tor.z + 2 + (P.disk.z - (tor.z + 2)) * t;
  if (sim.blocked({x, z}, .35)) {frei = false; break;}
 }
 out.wegFrei = frei;
 return out;
});
pruefe('Alle vier Punkte des ersten Akts sind betretbar',
 akt1.freiTuer && akt1.freiSicherung && akt1.freiPlatte && akt1.freiTreff,
 JSON.stringify([akt1.freiTuer, akt1.freiSicherung, akt1.freiPlatte, akt1.freiTreff]));
pruefe('Am Tor meldet sich der Wachmann', akt1.tuer === 'guard', String(akt1.tuer));
pruefe('Die Sicherung öffnet das Tor und schaltet auf Akt 2', akt1.nachSicherung === 2, String(akt1.nachSicherung));
pruefe('Die Festplatte schaltet auf Akt 3', akt1.nachPlatte === 3, String(akt1.nachPlatte));
pruefe('Am Bootshaus endet der erste Akt', akt1.finale === 'ending', String(akt1.finale));
pruefe('Vom Tor zur Festplatte steht keine Wand im Weg', akt1.wegFrei);

console.log('Akt 2: die Ratsakte');
// Akt 2 hatte keine Prüfung, und er hängt an vier Orten, von denen drei in
// dieser Runde umgezogen sind: Archiv, Fähranleger und Luftfracht. Ohne
// Prüfung wäre nach dem Umzug nicht zu sagen, ob die Kette noch läuft.
const akt2 = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, o = L.orte, aus = {};
 s.stars = 0; s.heat = 0; s.activity = null; s.mission = 4;
 s.campaign = {stage: 1, choice: null, relay: false, archive: false, witness: false, delivered: false};
 const hin = l => {const p = s.player; p.x = l.x; p.z = l.z + 2; p.y = 0; p.car = null;};
 aus.erreichbar = ['tower', 'records', 'ferry', 'aircargo', 'home'].every(id => !s.blocked({x: o[id].x, z: o[id].z + 2}, .4));
 hin(o.tower); s.active = 0; s.action();
 aus.eliKannNicht = !s.campaign.relay;         // das Relais gehört Mara
 s.active = 1; s.action(); aus.relais = s.campaign.relay;
 hin(o.records); s.active = 0; s.action();
 aus.archiv = s.campaign.archive; aus.stufe2 = s.campaign.stage;
 hin(o.ferry); s.action(); aus.zeugin = s.campaign.witness;
 hin(o.aircargo); s.action(); aus.stufe3 = s.campaign.stage;
 hin(o.home); aus.finale = s.action();
 return aus;
});
pruefe('Alle fünf Orte des zweiten Akts sind betretbar', akt2.erreichbar);
pruefe('Das Relais schaltet nur Mara ab', akt2.eliKannNicht && akt2.relais);
pruefe('Eli kommt mit der Karte ins Archiv', akt2.archiv && akt2.stufe2 === 2);
pruefe('Die Zeugin steigt am Fähranleger zu', akt2.zeugin);
pruefe('Die Übergabe an der Luftfracht schaltet auf Akt 3', akt2.stufe3 === 3, String(akt2.stufe3));
pruefe('Zu Hause öffnet sich die Entscheidung', akt2.finale === 'finale', String(akt2.finale));

console.log('Akt 3 bis 5');
// Die drei Akte laufen hier direkt gegen die Simulation: die Mechanik ist
// Physik und Zustand, kein Rendern. Ein Durchlauf im Spieltempo dauerte
// Minuten, deshalb werden Vorlauf und Position gesetzt statt abgefahren.
const akte = await page.evaluate(() => {
 const L = window.LOWTIDE, sim = L.sim, S = L.story, out = {};
 sim.paused = false;
 sim.campaign.stage = 4;
 const ziel = sim.objective();
 out.zielDiner = Math.hypot(ziel.x - L.orte.diner.x, ziel.z - L.orte.diner.z) < 1;
 sim.player.car = null; sim.player.x = L.orte.diner.x; sim.player.z = L.orte.diner.z + 2;
 out.aktion3 = sim.action();

 sim.starteAkt(3);
 const lkw = sim.cars.find(c => c.type === 'konvoi');
 out.lkwDa = !!lkw;
 out.titelVorlauf = sim.missionTitle();
 sim.campaign.konvoi.vorlauf = 0;
 const lkwVor = {x: lkw.x, z: lkw.z};
 for (let i = 0; i < 60; i++) sim.tick(.05);
 out.lkwFaehrt = Math.hypot(lkw.x - lkwVor.x, lkw.z - lkwVor.z);
 const auto = sim.cars.find(c => c.type === 'parked' && c.model === 'muscle') || sim.cars[0];
 // Für den Rammtest bleibt nur der Transport auf der Karte. Auf einer
 // belebten Straße trifft man beim Rammen zwangsläufig Zivilwagen und
 // Fußgänger, und beides ist zu Recht eine Straftat — geprüft werden soll
 // aber, dass der Transport selbst keine auslöst. Erster Versuch: nur die
 // Fahrzeuge beiseite. Es blieben die hundertsiebenundfünfzig Leute.
 out.beiseite = [];
 for (const c of sim.cars) {
  if (c === auto || c === lkw) continue;
  out.beiseite.push(['w', c.id, c.x, c.z]);
  c.x += 4000;
 }
 for (const n of sim.npcs) {
  out.beiseite.push(['n', n.id, n.x, n.z]);
  n.x += 4000;
 }
 sim.player.car = auto; Object.assign(auto, {yaw: lkw.yaw, speed: 22, health: 100, fuel: 100});
 // Fahndung zurücksetzen. Die Abschnitte über Polizei und Fahndung laufen
 // vorher und lassen Sterne stehen; ohne diese Zeile misst die Prüfung nicht
 // das Rammen, sondern den Rest des vorigen Abschnitts. Genau daran ist sie
 // zweimal gescheitert, während ich die Ursache bei Verkehr und Fußgängern
 // gesucht habe.
 sim.stars = 0; sim.heat = 0; sim.lastSeen = null; sim.description = null;
 for (const c of sim.cops) c.active = false;
 // Und die vorgemerkten Zeugenmeldungen. crime() hängt jedem Zeugen ein
 // report mit Zeitzünder an; die Abschnitte über Waffen und Nahkampf laufen
 // vorher, und deren Zeugen melden mitten im Rammtest. Das Protokoll hat sie
 // verraten: "report 1 bei -164/14" — ein Ort, an dem der Transport nie war.
 for (const n of sim.npcs) {n.report = null; n.timer = 0; if (n.state !== 'tanzend') n.state = 'normal';}
 sim.reported = new Set();
 // Eine Prüfung, die nur "rot" sagt, kostet je Anlauf eine halbe Stunde. Sie
 // schreibt jetzt mit, wer die Fahndung auslöst, und gibt es im Fehlertext
 // aus. Drei Anläufe lang habe ich die Ursache stattdessen geraten.
 out.ausloeser = [];
 const echtesReport = sim.report.bind(sim), echtesCrime = sim.crime.bind(sim);
 sim.report = function (sev, pos, inc) {
  out.ausloeser.push('report ' + sev + ' bei ' + Math.round(pos?.x ?? 0) + '/' + Math.round(pos?.z ?? 0));
  return echtesReport(sev, pos, inc);
 };
 sim.crime = function (sev) {out.ausloeser.push('crime ' + sev); return echtesCrime(sev);};
 let stoesse = 0;
 while (sim.campaign.konvoi.phase === 'faehrt' && stoesse++ < 400) {
  auto.x = lkw.x + 2.2; auto.z = lkw.z + 1.2; auto.speed = 22;
  sim.tick(.05, {forward: 1});
 }
 out.gestoppt = sim.campaign.konvoi.phase === 'gestoppt';
 out.stoesse = stoesse;
 sim.report = echtesReport; sim.crime = echtesCrime;
 out.fahndungNachRammen = sim.stars;
 out.ausloeser = out.ausloeser.slice(0, 6);
 out.bewaffnet = !!sim.player.armed;
 for (const [art, id, x, z] of out.beiseite) {
  const o = (art === 'w' ? sim.cars : sim.npcs).find(v => v.id === id);
  if (o) {o.x = x; o.z = z;}
 }
 delete out.beiseite;
 sim.player.car = null; sim.player.x = lkw.x + 1.5; sim.player.z = lkw.z + 1;
 const geld3 = sim.player.money;
 out.aktion4 = sim.action();
 out.lohn3 = sim.player.money - geld3;

 sim.starteAkt(4);
 sim.hour = 14; sim.player.car = null;
 sim.player.x = S.TRESOR.x; sim.player.z = S.TRESOR.z;
 sim.tick(.01, {sneak: true}); sim.action();
 out.tagsGesperrt = !sim.campaign.tresor.arbeitet;
 sim.hour = 23; sim.player.sneak = false; sim.action();
 out.aufrechtGesperrt = !sim.campaign.tresor.arbeitet;
 sim.stars = 0; sim.heat = 0;
 sim.tick(.01, {sneak: true}); sim.player.x = S.TRESOR.x; sim.player.z = S.TRESOR.z;
 sim.action();
 out.nachtsOffen = !!sim.campaign.tresor.arbeitet;
 const geld4 = sim.player.money;
 let takte = 0;
 for (; takte < 900 && sim.campaign.stage === S.AKT4; takte++) {
  sim.player.x = S.TRESOR.x; sim.player.z = S.TRESOR.z; sim.tick(.05, {sneak: true});
  if (sim.campaign.tresor.blockiert) out.wachePausiert = true;
 }
 out.takte4 = takte;
 out.lohn4 = sim.player.money - geld4;
 out.stageNach4 = sim.campaign.stage;
 out.dialog4 = sim.aktDialog;
 sim.aktDialog = null; sim.paused = false;

 const boot = sim.cars.find(c => c.type === 'flucht');
 out.bootDa = !!boot;
 out.routeWasser = S.FLUCHT_ROUTE.every(q => L.waterAt(q.x, q.z));
 const bootVor = {x: boot.x, z: boot.z};
 for (let i = 0; i < 40; i++) sim.tick(.05);
 out.bootFaehrt = Math.hypot(boot.x - bootVor.x, boot.z - bootVor.z);
 const eigenes = sim.cars.find(c => c.model === 'boat' && c !== boot);
 sim.player.car = eigenes;
 for (let i = 0; i < 300 && !sim.aktDialog; i++) {
  eigenes.x = boot.x + 3; eigenes.z = boot.z + 3;
  sim.player.x = eigenes.x; sim.player.z = eigenes.z;
  sim.tick(.05);
 }
 out.dialog5 = sim.aktDialog;
 sim.aktDialog = null; sim.paused = false;
 const geld5 = sim.player.money, ruf = sim.relationship;
 const ausgang = sim.beendeKampagne('polizei');
 out.ausgang = ausgang?.ausgang;
 out.endLohn = sim.player.money - geld5;
 out.endRuf = sim.relationship - ruf;
 out.stageEnde = sim.campaign.stage;
 out.ausgaenge = Object.keys(S.AUSGAENGE).length;
 sim.player.car = null; sim.stars = 0; sim.heat = 0;
 return out;
});
pruefe('Akt 3 wird am Diner angeboten', akte.zielDiner && akte.aktion3 === 'akt3');
pruefe('Transport existiert und fährt seine Route', akte.lkwDa && akte.lkwFaehrt > 30, `${akte.lkwFaehrt?.toFixed(1)} m in 3 s`);
pruefe('Vorlauf steht im Auftragstext', /startet in \d+ s/.test(akte.titelVorlauf || ''), akte.titelVorlauf);
pruefe('Rammen stoppt den Transport', akte.gestoppt, `${akte.stoesse} Stöße`);
pruefe('Rammen zählt nicht als Straftat', akte.fahndungNachRammen === 0,
 `${akte.fahndungNachRammen} Sterne, bewaffnet=${akte.bewaffnet}, Auslöser: ${akte.ausloeser.join(' | ') || 'keine'}`);
pruefe('Treffersperre verhindert Dauerschaden', akte.stoesse >= 3, `${akte.stoesse} Stöße`);
pruefe('Kassenbuch bringt Geld und startet Akt 4', akte.aktion4 === 'akt4start' && akte.lohn3 === 900);
pruefe('Tresor bleibt tagsüber zu', akte.tagsGesperrt);
pruefe('Tresor bleibt aufrecht zu', akte.aufrechtGesperrt);
pruefe('Tresor öffnet nachts und geduckt', akte.nachtsOffen);
pruefe('Akt 4 zahlt aus und führt in Akt 5', akte.lohn4 === 1400 && akte.stageNach4 === 7 && akte.dialog4 === 'akt5start');
pruefe('Wache am Tresor unterbricht die Arbeit', akte.wachePausiert === true);
pruefe('Tresor braucht länger als die reine Knackzeit', akte.takte4 * .05 > 6.5, `${(akte.takte4 * .05).toFixed(1)} s`);
pruefe('Fluchtroute liegt vollständig im Wasser', akte.routeWasser);
pruefe('Fluchtboot fährt', akte.bootDa && akte.bootFaehrt > 10, `${akte.bootFaehrt?.toFixed(1)} m in 2 s`);
pruefe('Verfolgung endet im Schlussdialog', akte.dialog5 === 'ende');
pruefe('Drei Ausgänge, Übergabe zahlt und hebt das Vertrauen',
 akte.ausgaenge === 3 && akte.ausgang === 'Übergabe' && akte.endLohn === 1500 && akte.endRuf === 15);
pruefe('Kampagne erreicht den Endzustand', akte.stageEnde === 8);
pruefe('Aktfahrzeuge überstehen Speichern und Laden', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 s.restore(stand); s.paused = false;
 return !!s.cars.find(c => c.type === 'konvoi') && !!s.cars.find(c => c.type === 'flucht')
  && s.npcs.filter(n => n.aktWache).length === 4;
}));
pruefe('Alter Spielstand bekommt die Aktfahrzeuge zurück', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 const autos = stand.cars.length, leute = stand.npcs.length;
 stand.cars = stand.cars.filter(c => c.type !== 'konvoi' && c.type !== 'flucht');
 stand.npcs = stand.npcs.filter(n => !n.aktWache);
 s.restore(stand); s.paused = false;
 return s.cars.length === autos && s.npcs.length === leute
  && s.cars[s.cars.length - 1].type === 'flucht';
}));

console.log('Spielstand');
// Die Prüfung stand auf einem einzigen Feld: Geld. Ein Spielstand trägt
// achtundzwanzig, und der Rundlauf ist erst dann etwas wert, wenn keines
// davon unterwegs verlorengeht.
const rundlauf = await page.evaluate(() => {
 const s = window.LOWTIDE.sim, q = s.player;
 const merkeAuto = s.cars.find(c => c.model === 'muscle');
 q.money = 4321; q.x = -317; q.z = -75; q.y = 0; q.health = 63; q.fitness = 4; q.fish = 3;
 q.weapon = 'shotgun'; q.inventory.shotgun = {ammo: 5, reserve: 20}; q.ammo = 5; q.reserve = 20;
 q.clothes = 'blue'; q.hair = 2; q.tattoo = true;
 s.hour = 21.5; s.weather = 'rain'; s.relationship = 71; s.mission = 4;
 s.campaign = {stage: 2, choice: null, relay: true, archive: true, witness: true, delivered: false};
 s.besitz = {motel: true}; s.motelOwned = true; s.highScores = {darts: 4, pool: 3};
 s.konto = [{text: 'Test', betrag: -50, stunde: 20}]; s.schatzIndex = 2;
 merkeAuto.upgrades = {engine: 2, tires: 1}; merkeAuto.health = 71; merkeAuto.fuel = 44;
 merkeAuto.unlocked = true; q.car = merkeAuto;
 const nimm = () => {
  const a = s.cars.find(c => c.id === merkeAuto.id), p = s.player;
  return JSON.stringify([p.money, Math.round(p.x), Math.round(p.z), p.health, p.weapon, p.ammo,
   p.reserve, p.clothes, p.hair, p.tattoo, p.fitness, p.fish, +s.hour.toFixed(2), s.weather,
   s.relationship, s.mission, s.campaign.stage, s.campaign.relay, JSON.stringify(s.besitz),
   s.motelOwned, JSON.stringify(s.highScores), s.konto.length, s.schatzIndex,
   JSON.stringify(a && a.upgrades), a && a.health, a && a.fuel, !!p.car, p.car && p.car.id]);
 };
 const vorher = nimm();
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 // Alles kaputtmachen, dann zurückholen.
 q.money = 0; q.x = 0; q.z = 0; q.health = 100; q.weapon = 'pistol'; q.clothes = 'orange';
 q.hair = 0; q.tattoo = false; q.fitness = 0; q.fish = 0; q.car = null;
 s.hour = 8; s.weather = 'clear'; s.relationship = 50; s.mission = 0;
 s.campaign = {stage: 0, choice: null, relay: false, archive: false, witness: false, delivered: false};
 s.besitz = {}; s.motelOwned = false; s.highScores = {}; s.konto = []; s.schatzIndex = 0;
 merkeAuto.upgrades = {}; merkeAuto.health = 100; merkeAuto.fuel = 100;
 s.restore(stand); s.paused = false;
 return {gleich: nimm() === vorher, vorher, nachher: nimm(), groesse: JSON.stringify(stand).length};
});
pruefe('Speichern und Laden überstehen den Rundlauf', rundlauf.gleich,
 rundlauf.gleich ? `${Math.round(rundlauf.groesse / 1024)} KB` : `${rundlauf.vorher} → ${rundlauf.nachher}`);

console.log('Keys und Bild');
const keys = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world;
 const out = {};
 out.inseln = L.inseln.map(r => ({name: r.name, trocken: !L.waterAt((r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2)}));
 // Der Keys Highway muss über die ganze Länge Land sein, sonst bricht das
 // Fahrzeug beim ersten Meter über Wasser ab.
 out.hoehle = [];
 for (let x = 124; x <= 358; x += 4) if (L.waterAt(x, 400)) out.hoehle.push(x);
 out.hoehe = L.groundAt(200, 400);
 out.region = L.regionAt({x: 266, z: 400});
 out.kuesten = w.waterUniforms.land.value.length;
 // Aus den Daten statt aus einer festen Zahl: die Liste ist gewachsen, als
 // die drei Dämme durch den Salzsumpf dazukamen, und eine hart notierte
 // Neun hätte nur gemeldet, dass sich etwas geändert hat — nicht, ob es
 // zusammenpasst.
 out.kuestenSoll = L.inseln.length + (L.daemme?.length ?? 0) + (L.westDaemme?.length ?? 0);
 // Nachbearbeitung
 out.postAn = !!w.post?.aktiv;
 out.tonwert = w.renderer.toneMapping;
 out.keinTonwert = w.renderer.toneMapping === 0;
 out.tiefe = !!w.post?.szene?.depthTexture;
 // Verdeckung: die Puffer müssen Werte unter Weiß enthalten.
 const t = w.post.ao1, buf = new Uint8Array(t.width * t.height * 4);
 w.renderer.readRenderTargetPixels(t, 0, 0, t.width, t.height, buf);
 let min = 255;
 for (let i = 0; i < buf.length; i += 4) min = Math.min(min, buf[i]);
 out.aoMin = min;
 // Oberflächendetail liegt auf den Weltmaterialien.
 // Leuchtflächen sind bewusst ausgenommen — ein Fenster, das von innen
 // leuchtet, hat keine Körnung. Geprüft wird alles andere.
 let mitDetail = 0, gesamt = 0, leucht = 0;
 for (const m of w.bloecke) {
  if (m.material.emissiveIntensity > 0) {leucht++; continue;}
  gesamt++; if (m.material.userData.detail) mitDetail++;
 }
 out.detail = [mitDetail, gesamt, leucht];
 return out;
});
pruefe('Alle Inseln sind trockenes Land', keys.inseln.every(i => i.trocken),
 keys.inseln.filter(i => !i.trocken).map(i => i.name).join(', '));
pruefe('Keys Highway hat keine Lücke im Damm', keys.hoehle.length === 0, keys.hoehle.join(' '));
pruefe('Der Damm liegt auf Fahrbahnhöhe', keys.hoehe === 0, String(keys.hoehe));
pruefe('Die Keys haben eine eigene Region', keys.region === 'THE LOWER KEYS', keys.region);
pruefe('Der Wassershader kennt alle Küsten', keys.kuesten === keys.kuestenSoll,
 `${keys.kuesten} im Shader gegen ${keys.kuestenSoll} in den Daten`);
pruefe('Nachbearbeitung ist aktiv und tonwertet selbst', keys.postAn && keys.keinTonwert, `toneMapping=${keys.tonwert}`);
pruefe('Tiefe steht der Verdeckung zur Verfügung', keys.tiefe);
pruefe('Verdeckung dunkelt tatsächlich ab', keys.aoMin < 245, `dunkelster Wert ${keys.aoMin}`);
pruefe('Oberflächendetail liegt auf allen matten Weltmaterialien',
 keys.detail[0] === keys.detail[1] && keys.detail[1] > 50 && keys.detail[2] > 0,
 `${keys.detail[0]} von ${keys.detail[1]}, ${keys.detail[2]} leuchtende ausgenommen`);
// Die Spiegelung lief früher nur bei Nässe; sie läuft jetzt auch auf Wasser,
// weil das Hafenbecken sonst nur zwei Himmelsfarben zeigt. Geprüft wird
// deshalb nicht mehr, ob der Durchgang angeschaltet ist, sondern was
// tatsächlich in seinem Ziel steht.
const spiegelDeckung = async (x, z, blick, wetter) => {
 await page.evaluate(([x, z, blick, wetter]) => {
  const L = window.LOWTIDE;
  L.sim.hour = 13; L.sim.weather = wetter;
  L.view(x, z, blick, .08);
  // Die Nässe klingt mit Nachlauf ab; für die Prüfung einschwingen lassen.
  for (let i = 0; i < 60; i++) L.world.applySky(.5);
 }, [x, z, blick, wetter]);
 await bilder(4);
 return await page.evaluate(() => {
  const w = window.LOWTIDE.world;
  const sz = w.post.szene, szb = new Uint16Array(sz.width * sz.height * 4);
  w.renderer.readRenderTargetPixels(sz, 0, 0, sz.width, sz.height, szb);
  let wasser = 0;                            // 0x3800 ist 0,5 als HalfFloat
  for (let i = 3; i < szb.length; i += 4) if (szb[i] === 0x3800) wasser++;
  const zl = w.post.spiegelZiel, zb = new Uint16Array(zl.width * zl.height * 4);
  w.renderer.readRenderTargetPixels(zl, 0, 0, zl.width, zl.height, zb);
  let sp = 0;
  for (let i = 3; i < zb.length; i += 4) if (zb[i] !== 0) sp++;
  const achse = w.post.spiegelU.hochAchse.value;
  return {wasser: wasser / (szb.length / 4), spiegel: sp / (zb.length / 4),
   nass: w.post.spiegelU.nass.value,
   gedreht: Math.abs(achse.y - 1) > 1e-4 || Math.abs(achse.z) > 1e-4};
 });
};
const kueste = await spiegelDeckung(140, 120, -1.5, 'clear');
const innenTrocken = await spiegelDeckung(-300, -180, 1.2, 'clear');
const innenNass = await spiegelDeckung(-300, -180, 1.2, 'storm');
await page.evaluate(() => {window.LOWTIDE.sim.weather = 'clear';});
pruefe('Wasser trägt seine Marke im Alphakanal', kueste.wasser > .3,
 `${(kueste.wasser * 100).toFixed(1)} % der Fläche`);
pruefe('Wasser spiegelt auch bei klarem Wetter', kueste.spiegel > .05,
 `${(kueste.spiegel * 100).toFixed(1)} % gespiegelt`);
pruefe('Trockener Asphalt spiegelt nichts', innenTrocken.spiegel < .005,
 `${(innenTrocken.spiegel * 100).toFixed(2)} % gespiegelt`);
pruefe('Nasser Asphalt spiegelt', innenNass.spiegel > .02 && innenNass.nass > .5,
 `${(innenNass.spiegel * 100).toFixed(1)} % bei Nässe ${innenNass.nass.toFixed(2)}`);
pruefe('Weltoben liegt im Blickraum, nicht auf der Einheitsachse', kueste.gedreht);
const wolken = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, u = L.wolken;
 // applySky rechnet Stärke, Versatz und Sonnenneigung jedes Bild neu.
 const lies = (stunde, wetter) => {
  L.sim.hour = stunde; L.sim.weather = wetter;
  w.applySky(1 / 60);
  return u.staerke.value;
 };
 const mittag = lies(13, 'clear');
 const nacht = lies(1, 'clear');
 const nebel = lies(13, 'fog');
 const sturm = lies(13, 'storm');
 // Wind: zwei Aufrufe, dazwischen muss der Versatz weitergelaufen sein.
 L.sim.hour = 13; L.sim.weather = 'clear';
 w.applySky(1 / 60);
 const v0 = u.versatz.value.x;
 for (let i = 0; i < 30; i++) w.applySky(1 / 60);
 const gewandert = u.versatz.value.x - v0;
 // Sonnenneigung: bei tiefer Sonne muss der Versatz zur Wolkenhöhe größer
 // sein als mittags. Sonst läge der Schatten eines Hochhauses falsch.
 L.sim.hour = 13; w.applySky(1 / 60);
 const neigungMittag = Math.hypot(u.sonne.value.x, u.sonne.value.y);
 L.sim.hour = 7.5; w.applySky(1 / 60);
 const neigungFlach = Math.hypot(u.sonne.value.x, u.sonne.value.y);
 L.sim.hour = 13; L.sim.weather = 'clear'; w.applySky(1 / 60);
 // Figuren und Fahrzeuge müssen im selben Schattenfeld liegen wie die Welt.
 const zaehle = wurzel => {
  let mit = 0, alle = 0;
  wurzel.traverse(o => {
   if (!o.material || o.material.emissive?.getHex()) return;
   alle++; if (o.material.userData.wolken) mit++;
  });
  return [mit, alle];
 };
 return {mittag, nacht, nebel, sturm, gewandert, neigungMittag, neigungFlach,
  figur: zaehle(w.npcs[0]), wagen: zaehle(w.cars[0])};
});
pruefe('Wolkenschatten liegt tagsüber auf der Karte', wolken.mittag > .05, String(wolken.mittag));
pruefe('Nachts wirft keine Wolke einen Schatten', wolken.nacht === 0, String(wolken.nacht));
pruefe('Nebel löst die Schattenkanten auf', wolken.nebel < wolken.mittag * .35,
 `Nebel ${wolken.nebel.toFixed(3)} gegen klar ${wolken.mittag.toFixed(3)}`);
pruefe('Unter geschlossener Decke bleibt kein einzelnes Feld übrig',
 wolken.sturm < wolken.mittag * .5, `Sturm ${wolken.sturm.toFixed(3)}`);
pruefe('Der Wind trägt die Decke weiter', wolken.gewandert > 1e-4, String(wolken.gewandert));
pruefe('Tiefe Sonne versetzt den Schatten stärker als hohe',
 wolken.neigungFlach > wolken.neigungMittag * 1.5,
 `${wolken.neigungFlach.toFixed(2)} gegen ${wolken.neigungMittag.toFixed(2)}`);
pruefe('Figuren stehen im selben Schattenfeld', wolken.figur[0] === wolken.figur[1] && wolken.figur[1] > 5,
 `${wolken.figur[0]} von ${wolken.figur[1]}`);
pruefe('Fahrzeuge stehen im selben Schattenfeld', wolken.wagen[0] === wolken.wagen[1] && wolken.wagen[1] > 5,
 `${wolken.wagen[0]} von ${wolken.wagen[1]}`);
// Fahrbahnen müssen dem Gelände folgen. Vorher lag jedes Segment als ein
// Quader auf y = 0,03 — auf dem Talon Ridge damit sechsundachtzig Meter
// unter der Kuppe, unsichtbar, aber für aufStrasse() trotzdem vorhanden.
//
// Gelesen wird aus world.bloecke, nicht aus world.groups: flush() leert die
// Sammler, sobald die Instanzennetze stehen. Der erste Anlauf dieser Prüfung
// hat genau das gemeldet — null Stücke gefunden, obwohl sie im Bild stehen.
const strassenHoehe = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world;
 let schlimmster = 0, wo = null, gezaehlt = 0, obenAufDemRuecken = 0, kuppe = 0;
 for (const netz of w.bloecke || []) {
  const arr = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16;
   const x = arr[o + 12], y = arr[o + 13], z = arr[o + 14];
   const sx = Math.hypot(arr[o], arr[o + 1], arr[o + 2]);
   const sy = Math.hypot(arr[o + 4], arr[o + 5], arr[o + 6]);
   const sz = Math.hypot(arr[o + 8], arr[o + 9], arr[o + 10]);
   if (y > 58 && y < 100 && Math.hypot(x + 900, (z + 160) * .76) < 140) kuppe++;
   // Fahrbahn wird nicht über die Materialfarbe erkannt — die Netze sind
   // nach Farbe und Kachel gebündelt, und die Suche nach dem Asphaltton kam
   // im zweiten Anlauf auf null Treffer. Stattdessen geometrisch: flach,
   // breit, und der Punkt liegt auf einer Fahrbahn.
   // Math.min statt Math.max: die Randlinien der Fahrbahn sind ebenso flach
   // und ebenso lang wie ein Deckenstück, aber sechzehn Zentimeter schmal.
   // Als Decke gezählt meldeten sie 3,46 Meter Abweichung — das ist die
   // Querneigung des Geländes am Fahrbahnrand, nicht die Höhe der Decke.
   if (sy > .2 || Math.min(sx, sz) < 6) continue;
   if (!L.onRoad(x, z, 0)) continue;
   // Nur, was auf der Fahrbahn liegt, nicht was darüber hängt: ein Vordach
   // oder ein Kirchendach ist flach und breit und stünde sonst als
   // Abweichung von fünfzehn Metern in der Statistik. Der ursprüngliche
   // Fehler — Fahrbahn auf Meereshöhe unter einem 86 m hohen Rücken — wird
   // davon nicht verdeckt: die läge unter dem Gelände, nicht darüber.
   if (y > L.groundAt(x, z) + 1) continue;
   gezaehlt++;
   if (y > 60) obenAufDemRuecken++;
   const ab = Math.abs(y - .03 - L.groundAt(x, z));
   if (ab > schlimmster) {schlimmster = ab; wo = [Math.round(x), Math.round(z), Math.round(y)];}
  }
 }
 return {schlimmster, wo, gezaehlt, obenAufDemRuecken, kuppe};
});
// Jedes Fahrbahnstück lag waagerecht. Am Hang steht damit die eine Kante in
// der Luft und die andere im Boden — auf dem Talon Ridge las sich die Straße
// aus zweihundert Metern als Treppe dunkler Platten. Die Höhenprüfung fand
// nichts, weil sie die Mitte misst, und die stimmt.
pruefe('Fahrbahnstücke am Hang sind geneigt', await page.evaluate(() => {
 const L = window.LOWTIDE;
 let geneigt = 0, flachAmHang = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, x = a[o + 12], y = a[o + 13], z = a[o + 14];
   const sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (Math.abs(sy - .08) > .01) continue;               // Deckenstärke
   if (!L.onRoad(x, z, 0)) continue;
   if (L.groundAt(x, z) < 6) continue;                   // nur am Hang
   const winkel = Math.acos(Math.min(1, Math.abs(a[o + 5] / sy))) * 180 / Math.PI;
   if (winkel > 1.5) geneigt++; else flachAmHang++;
  }
 }
 return geneigt > 20 && geneigt > flachAmHang;
}), await page.evaluate(() => {
 const L = window.LOWTIDE;
 let geneigt = 0, flach = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16;
   const sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (Math.abs(sy - .08) > .01 || !L.onRoad(a[o + 12], a[o + 14], 0)) continue;
   if (L.groundAt(a[o + 12], a[o + 14]) < 6) continue;
   (Math.acos(Math.min(1, Math.abs(a[o + 5] / sy))) * 180 / Math.PI > 1.5 ? geneigt++ : flach++);
  }
 }
 return `${geneigt} geneigt, ${flach} waagerecht`;
}));
pruefe('Fahrbahnen liegen auf dem Gelände', strassenHoehe.schlimmster < 1.2,
 `größte Abweichung ${strassenHoehe.schlimmster.toFixed(2)} m bei ${JSON.stringify(strassenHoehe.wo)}`);
pruefe('Die Straße über den Talon Ridge liegt auf dem Rücken',
 strassenHoehe.obenAufDemRuecken > 5, `${strassenHoehe.obenAufDemRuecken} Stücke über 60 m`);
pruefe('Die Fahrbahn ist in Stücke geteilt, nicht ein Quader je Segment',
 strassenHoehe.gezaehlt > 300, `${strassenHoehe.gezaehlt} Stücke`);
pruefe('Über der Baumgrenze steht Fels', strassenHoehe.kuppe > 200,
 `${strassenHoehe.kuppe} Teile auf der Kuppe`);
// Nichts Großes darf in einer Fahrbahn stehen. sim.blocked kennt nur
// registrierte Gebäude; Wasserturm, Kirche und anderes Beiwerk aus
// regions.js stehen dort nicht drin und sind bisher durch jedes Netz
// gefallen.
const hindernisse = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, treffer = [];
 for (const netz of w.bloecke || []) {
  const arr = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16;
   const x = arr[o + 12], y = arr[o + 13], z = arr[o + 14];
   const sx = Math.hypot(arr[o], arr[o + 1], arr[o + 2]);
   const sy = Math.hypot(arr[o + 4], arr[o + 5], arr[o + 6]);
   const sz = Math.hypot(arr[o + 8], arr[o + 9], arr[o + 10]);
   // Hoch genug, um ein Auto zu stoppen, und breit genug, um kein Pfosten
   // zu sein. Die Unterkante muss dabei unter Fahrzeughöhe liegen — eine
   // Brücke oder ein Ausleger darüber ist erlaubt.
   if (sy < 2.5 || Math.min(sx, sz) < 3) continue;
   if (y - sy / 2 > L.groundAt(x, z) + 2.6) continue;
   // Und was ganz unter der Fahrbahndecke liegt, ist kein Hindernis: der
   // Damm am Hang reicht seit dieser Runde bis unter die tiefere Seite und
   // ist damit bis zu 4,7 Meter hoch — nach oben endet er aber neun
   // Zentimeter unter dem Asphalt.
   if (y + sy / 2 < L.groundAt(x, z) + .5) continue;
   if (!L.onRoad(x, z, 0)) continue;
   treffer.push([Math.round(x), Math.round(z), Math.round(sx), Math.round(sz)]);
  }
 }
 return treffer;
});
pruefe('Nichts Großes steht in einer Fahrbahn', hindernisse.length === 0,
 `${hindernisse.length} Stück, zuerst ${JSON.stringify(hindernisse.slice(0, 4))}`);
// Die Prüfung oben greift nur bei dicken Klötzen. Die Zimmerwände der
// Servicegebäude sind einen Meter dick und sechzehn lang und fielen
// deshalb durch — vier von ihnen standen jahrelang quer über der
// Fahrbahn. Hier zählt die Fläche, nicht der Mittelpunkt.
const wandInStrasse = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, treffer = [];
 const strassen = L.strassen.map(r => ({
  x1: Math.min(r.x1, r.x2) - r.w / 2, x2: Math.max(r.x1, r.x2) + r.w / 2,
  z1: Math.min(r.z1, r.z2) - r.w / 2, z2: Math.max(r.z1, r.z2) + r.w / 2}));
 for (const o of s.solids) {
  const a = {x1: o.x - o.w / 2, x2: o.x + o.w / 2, z1: o.z - o.d / 2, z2: o.z + o.d / 2};
  for (const r of strassen) {
   const ux = Math.min(a.x2, r.x2) - Math.max(a.x1, r.x1);
   const uz = Math.min(a.z2, r.z2) - Math.max(a.z1, r.z1);
   if (ux > 0 && uz > 0 && ux * uz > 2) {treffer.push([o.kind, Math.round(o.x), Math.round(o.z), Math.round(ux * uz)]); break;}
  }
 }
 return treffer;
});
pruefe('Keine Hinderniswand liegt in einer Fahrbahn',
 wandInStrasse.length === 0,
 `${wandInStrasse.length} Stück, zuerst ${JSON.stringify(wandInStrasse.slice(0, 3))}`);
// Und die Marker der Innenräume bleiben in ihren Räumen.
pruefe('Dartscheibe und Billard stehen im Raum, der Schießstand daneben', await page.evaluate(() => {
 const o = window.LOWTIDE.orte;
 const drin = [['darts', 'diner', 16], ['pool', 'club', 16]].every(([z, w, b]) => {
  const m = o[z], l = o[w];
  return Math.abs(m.x - l.x) < b / 2 && m.z > l.z - 12 && m.z < l.z + 4;
 });
 // Der Schießstand liegt im Freien neben dem Laden, nicht darin. Für ihn
 // zählt: dicht am Gebäude und selbst nicht auf der Fahrbahn.
 const stand = Math.hypot(o.range.x - o.shop.x, o.range.z - o.shop.z) < 20 &&
  !window.LOWTIDE.onRoad(o.range.x, o.range.z, 0);
 return drin && stand;
}));
// Ein Ort mit Namen, Marker und Dienstleistung, aber ohne ein einziges
// Bauwerk, ist ein Versprechen ohne Deckung. Northstar Fuel war genau das:
// fünf stehende Instanzen im Umkreis von achtzehn Metern, und die gehörten
// zum Nachbarhaus. Der Marker lag dabei neun Meter tief im Boulevard.
const tanke = await page.evaluate(() => {
 const L = window.LOWTIDE, l = L.orte.fuel;
 let n = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, y = a[o + 13], sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (y + sy / 2 < 1.2) continue;
   if (Math.hypot(a[o + 12] - l.x, a[o + 14] - l.z) < 18) n++;
  }
 }
 return {n, aufStrasse: L.onRoad(l.x, l.z, 0), imWasser: L.waterAt(l.x, l.z),
  lampen: (L.world.zusatzLampen || []).length,
  imVorrat: (L.world.innenLampen || []).filter(x => Math.hypot(x.x - l.x, x.z - l.z) < 18).length};
});
pruefe('Northstar Fuel steht als Bauwerk in der Welt', tanke.n >= 20 && !tanke.aufStrasse && !tanke.imWasser,
 `${tanke.n} stehende Teile, auf Fahrbahn: ${tanke.aufStrasse}`);
pruefe('Das Vordach hat echtes Licht, nicht nur leuchtende Flächen',
 tanke.lampen >= 3 && tanke.imVorrat >= 3, `${tanke.lampen} Lampen, ${tanke.imVorrat} im Vorrat`);
// Dasselbe für die drei anderen Orte, die nur ein Name waren: Gym,
// Luftfracht und Fähranleger. Der Anleger muss zusätzlich am Wasser liegen —
// er lag vierzig Meter im Landesinneren.
const orteOhneHaus = await page.evaluate(() => {
 const L = window.LOWTIDE, aus = {};
 const teile = [];
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, y = a[o + 13], sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (y + sy / 2 < 1.2) continue;
   teile.push([a[o + 12], a[o + 14]]);
  }
 }
 for (const id of ['gym', 'aircargo', 'ferry']) {
  const l = L.orte[id];
  aus[id] = teile.filter(t => Math.hypot(t[0] - l.x, t[1] - l.z) < 18).length;
 }
 // Wasser in Rufweite des Anlegers, und kein Baum in den vier Grundrissen.
 const f = L.orte.ferry;
 aus.wasserAmKai = [10, 14, 18, 22].some(d => L.waterAt(f.x - d, f.z));
 const liste = L.world.laubwerk?.liste || [];
 aus.baeume = [[-413, 270, -369, 302], [-148, 107, -120, 129], [236, 153, 260, 191], [-145, 124, -111, 152]]
  .reduce((n, [x1, z1, x2, z2]) => n + liste.filter(t => t.x >= x1 && t.x <= x2 && t.z >= z1 && t.z <= z2).length, 0);
 return aus;
});
pruefe('Gym, Luftfracht und Fähranleger sind gebaut, nicht nur benannt',
 orteOhneHaus.gym >= 10 && orteOhneHaus.aircargo >= 10 && orteOhneHaus.ferry >= 10,
 `Gym ${orteOhneHaus.gym}, Luftfracht ${orteOhneHaus.aircargo}, Anleger ${orteOhneHaus.ferry}`);
pruefe('Der Fähranleger liegt am Wasser', orteOhneHaus.wasserAmKai);
pruefe('Kein Baum steht in den vier neuen Grundrissen', orteOhneHaus.baeume === 0,
 `${orteOhneHaus.baeume} Stück`);
// Die Landebahn hatte Schwellenbalken, Randbefeuerung und Grasschultern,
// aber keinen Belag — und auf dem unbefestigten Profil stand Kulisse aus
// Funktionen, die nach airfield() laufen: ein vierzehn Meter hoher Mast,
// fünf Pfosten, ein Kasten. Auf Wiese fiel das nicht auf, auf Asphalt schon.
const bahn = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const imProfil = (x, z) => Math.abs(x + 315) < 13 && z > 238 && z < 392;
 let belag = 0, steht = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, y = a[o + 13];
   const sx = Math.hypot(a[o], a[o + 1], a[o + 2]), sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]),
    sz = Math.hypot(a[o + 8], a[o + 9], a[o + 10]);
   if (!imProfil(a[o + 12], a[o + 14])) continue;
   if (sy < .4 && sx > 20 && sz > 100) belag++;      // die Bahndecke selbst
   if (y + sy / 2 >= 1.2) steht++;
  }
 }
 return {belag, steht};
});
pruefe('Die Landebahn hat einen Belag', bahn.belag >= 1, `${bahn.belag} Deckenteile`);
pruefe('Auf der Landebahn steht nichts', bahn.steht === 0, `${bahn.steht} stehende Teile`);
// Und der Dragstrip hat, was ein Rennen ausmacht.
pruefe('Der Dragstrip hat Startbaum, Zeitnahme und Tribüne', await page.evaluate(() => {
 const L = window.LOWTIDE, l = L.orte.drag;
 let n = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, y = a[o + 13], sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (y + sy / 2 < 1.2) continue;
   if (Math.hypot(a[o + 12] - l.x, a[o + 14] - l.z) < 45) n++;
  }
 }
 return n >= 25;
}));
// Steht ein Haus in einem anderen? Gezählt werden nur Baukörper: mindestens
// drei Meter hoch, mindestens sieben Meter in der kürzeren Kante und nicht
// flacher als ein Viertel davon (sonst wären Höfe und Vorfelder dabei), mit
// dem Fuß auf dem Boden. Teile desselben Hauses — Sockel, Turm, Anbau —
// liegen dicht beieinander und zählen nicht; erst ab zwölf Metern Abstand
// der Mittelpunkte sind es zwei Gebäude.
//
// Der Anlass: nachdem die Ladenzeile von Rosalind zum ersten Mal überhaupt
// gebaut wurde, steckte sie in der Wohnhausreihe — elf Paare. Übrig bleiben
// zwei alte Fälle, beide gewollt: der Kontrollturm des Flugplatzes steht in
// der Ecke der Abfertigung, und am Hafen lehnt ein Bau an einer Halle.
const ineinander = await page.evaluate(() => {
 const L = window.LOWTIDE, haus = [];
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, y = a[o + 13];
   const sx = Math.hypot(a[o], a[o + 1], a[o + 2]), sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]),
    sz = Math.hypot(a[o + 8], a[o + 9], a[o + 10]);
   if (sy < 3 || Math.min(sx, sz) < 7 || sy < .25 * Math.min(sx, sz)) continue;
   if (y - sy / 2 > L.groundAt(a[o + 12], a[o + 14]) + 2) continue;
   haus.push({x: a[o + 12], z: a[o + 14], w: sx, d: sz});
  }
 }
 const treffer = [];
 for (let i = 0; i < haus.length; i++) for (let j = i + 1; j < haus.length; j++) {
  const a = haus[i], b = haus[j];
  if (Math.hypot(a.x - b.x, a.z - b.z) < 12) continue;
  const ux = Math.min(a.x + a.w / 2, b.x + b.w / 2) - Math.max(a.x - a.w / 2, b.x - b.w / 2);
  const uz = Math.min(a.z + a.d / 2, b.z + b.d / 2) - Math.max(a.z - a.d / 2, b.z - b.d / 2);
  if (ux > 1 && uz > 1 && ux * uz > 12) treffer.push([Math.round(a.x), Math.round(a.z), Math.round(ux * uz)]);
 }
 return {haeuser: haus.length, treffer};
});
pruefe('Kein Haus steht in einem anderen',
 ineinander.treffer.length <= 2 && ineinander.treffer.every(t => t[2] <= 45),
 `${ineinander.haeuser} Baukörper, ${ineinander.treffer.length} Paare: ${JSON.stringify(ineinander.treffer)}`);
// Und die Ladenzeile von Rosalind steht überhaupt.
pruefe('Rosalind hat eine Ladenzeile', await page.evaluate(() => {
 const L = window.LOWTIDE;
 let n = 0;
 for (const netz of L.world.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, x = a[o + 12], z = a[o + 14];
   const sx = Math.hypot(a[o], a[o + 1], a[o + 2]), sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (sy < 6 || sx < 18) continue;
   if (x > -1010 && x < -750 && Math.abs(Math.abs(z - 340) - 16) < 3) n++;
  }
 }
 return n >= 8;
}));
// Leitplanken nur dort, wo es neben der Fahrbahn hinuntergeht.
const planken = await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 let hoch = 0, flach = 0;
 for (const netz of w.bloecke || []) {
  const f = netz.material.color?.getHexString();
  if (f !== 'b9bcb4' && f !== '8b8f88') continue;
  const arr = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const y = arr[i * 16 + 13];
   if (y > 20) hoch++; else if (y < 3) flach++;
  }
 }
 return {hoch, flach};
});
pruefe('Die Straße über den Rücken hat eine Leitplanke', planken.hoch > 50,
 `${planken.hoch} Teile über 20 m`);
pruefe('In der Ebene steht keine Leitplanke', planken.flach === 0,
 `${planken.flach} Teile unter 3 m`);
// Die Bildunterschrift der Minikarte stand fest in shell.html und meldete
// überall HARBOR DISTRICT — auf dem Talon Ridge, im Nationalpark, in
// Rosalind. Sichtbar auf jedem Bildschirmfoto dieser Sitzung, und trotzdem
// erst aufgefallen, als eines danebenlag.
const gegend = await page.evaluate(async () => {
 const L = window.LOWTIDE;
 const bild = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const lies = async (x, z) => {
  L.view(x, z, 0, .1);
  await bild(); await bild();
  return [document.getElementById('district').textContent,
          document.getElementById('mapDistrict').textContent];
 };
 const stadt = await lies(-60, 40);
 const ruecken = await lies(-880, -160);
 // Zurück in die Stadt und zwei Bilder abwarten. Ohne das Warten bleibt die
 // Kamera in der Luft über dem Rücken stehen, und die nächste Prüfung liest
 // die Nebeldichte in neunzig Metern Höhe statt am Boden — genau das ist
 // beim ersten Lauf passiert.
 L.view(-60, 40, 0, .1);
 await bild(); await bild();
 return {stadt, ruecken};
});
pruefe('Die Minikarte nennt dieselbe Gegend wie die Kopfzeile',
 gegend.stadt[0] === gegend.stadt[1] && gegend.ruecken[0] === gegend.ruecken[1],
 `${JSON.stringify(gegend.stadt)} / ${JSON.stringify(gegend.ruecken)}`);
pruefe('Die Gegend wechselt beim Ortswechsel', gegend.stadt[0] !== gegend.ruecken[0],
 `${gegend.stadt[0]} gegen ${gegend.ruecken[0]}`);
// Der Stausee war eine bemalte Platte: er sah aus wie Wasser und war für
// jede Abfrage trockener Boden. Jetzt steht er in waterAt().
const stausee = await page.evaluate(async () => {
 const L = window.LOWTIDE;
 const bild = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 L.view(-700, 80, 0, .1);
 await bild(); await bild(); await bild();
 const y = L.sim.player.y;
 // Geländekachel unter dem See muss eine Wanne sein, keine Ebene.
 const kachel = L.world.terrain.find(m => Math.abs(m.position.x + 700) < 60 && Math.abs(m.position.z - 80) < 60);
 let tiefste = 9;
 if (kachel) {const a = kachel.geometry.attributes.position;
  for (let i = 0; i < a.count; i++) tiefste = Math.min(tiefste, a.getY(i));}
 // Und die Ellipse muss enden: an der Böschung ist wieder Land.
 const ufer = L.waterAt(-700, -15) || L.waterAt(-700, 175) || L.waterAt(-840, 80);
 L.view(-60, 40, 0, .1);
 await bild(); await bild();
 return {mitte: L.waterAt(-700, 80), boden: L.groundAt(-700, 80), y, tiefste, ufer};
});
pruefe('Der Stausee ist Wasser, kein bemalter Boden', stausee.mitte && stausee.boden < -1,
 `waterAt ${stausee.mitte}, groundAt ${stausee.boden}`);
pruefe('Man schwimmt im Stausee, statt darauf zu stehen', stausee.y < -.2, `y = ${stausee.y.toFixed(2)}`);
pruefe('Unter dem See liegt eine Wanne', stausee.tiefste < -3, `tiefster Punkt ${stausee.tiefste}`);
pruefe('Die Böschung ist Land', !stausee.ufer);
// Die Bodenfarbe kannte nur die Frage "in welchem Rechteck liegt der Punkt".
// Die Kuppe von TALON RIDGE auf 88 Metern trug damit dasselbe Grün wie die
// Wiese auf Meereshöhe. Geprüft wird an den Scheitelfarben selbst, nicht am
// Bild: das ist von Grafikkarte und Uhrzeit unabhängig.
const boden = await page.evaluate(() => {
 const L = window.LOWTIDE;
 // Verglichen wird nur innerhalb desselben Rechtecks der Grundfarbe: x < -600
 // und z > -230 liefert überall dieselbe Ausgangsfarbe, also unterscheiden
 // sich hoch und tief allein durch Höhe und Neigung. Der Boden liegt auf
 // groundAt - 0.12; flaches Land steht damit bei -0,12, nicht bei 0.
 let hoch = {r: 0, g: 0, n: 0}, tief = {r: 0, g: 0, n: 0}, gleich = 0, paare = 0;
 for (const m of L.world.terrain) {
  const pos = m.geometry.attributes.position, col = m.geometry.attributes.color;
  for (let i = 0; i < col.count; i++) {
   const px = m.position.x + pos.getX(i), pz = m.position.z + pos.getZ(i);
   if (i) {paare++; if (Math.abs(col.getX(i) - col.getX(i - 1)) < 1e-5) gleich++;}
   if (px > -600 || pz < -230) continue;
   const y = pos.getY(i), r = col.getX(i), g = col.getY(i);
   if (y > 70) {hoch.r += r; hoch.g += g; hoch.n++;}
   else if (y > -1 && y < 6) {tief.r += r; tief.g += g; tief.n++;}
  }
 }
 // Grünstich = Grünkanal minus Rotkanal. Wiese ist positiv, Fels negativ.
 return {oben: hoch.n ? (hoch.g - hoch.r) / hoch.n : null, unten: tief.n ? (tief.g - tief.r) / tief.n : null,
  hochN: hoch.n, tiefN: tief.n, gleichAnteil: gleich / paare};
});
pruefe('Über der Baumgrenze ist der Boden Fels, nicht Wiese',
 boden.hochN > 150 && boden.tiefN > 500 && boden.oben < boden.unten - .004,
 `Grünstich oben ${boden.oben?.toFixed(4)} (${boden.hochN} Punkte), unten ${boden.unten?.toFixed(4)} (${boden.tiefN})`);
pruefe('Zwei Nachbarpunkte des Bodens haben nicht dieselbe Farbe',
 boden.gleichAnteil < .25, `${(boden.gleichAnteil * 100).toFixed(1)} % gleich`);
// Scheitel liegen 8,33 Meter auseinander — feiner als rund siebzehn Meter ist
// über Scheitelfarben nichts darstellbar. Die Struktur darunter kommt aus
// demselben Shader, den jede Kiste der Welt trägt; der Boden hatte ihn nicht.
pruefe('Der Boden trägt denselben Oberflächen-Shader wie alles andere',
 await page.evaluate(() => {
  const t = window.LOWTIDE.world.terrain;
  return t.length > 100 && t.every(m => m.material === t[0].material) && !!t[0].material.userData.detail;
 }));
// Die Innenstadt war leer: an der Hauptkreuzung standen vier Leute im
// Umkreis von sechzig Metern, am Strand vierundzwanzig.
const gehwege = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const umkreis = (x, z, r) => s.npcs.filter(n => Math.hypot(n.x - x, n.z - z) < r).length;
 // Wie viele stehen gerade in einer Fahrspur? "Keiner" wäre die falsche
 // Frage: ein Fußgänger, der eine Straße überquert, steht darauf, und das
 // soll er. Zwei Fassungen davor sind daran gescheitert — erst gegen
 // path[0] geprüft, was die Rundgänge aus simulation.js falsch trifft (die
 // setzen die Figur auf path[i%4]), dann gegen die Position zu einem
 // beliebigen Zeitpunkt, was jeden Überquerenden meldet. Die tragfähige
 // Frage ist der Anteil: ein paar Prozent sind Verkehr, ein Drittel wäre
 // eine Menge, die in den Fahrspuren wohnt.
 // Dritte Fassung. Die zweite zählte, wer gerade auf einer Fahrbahn steht —
 // und traf damit jeden, der eine Straße überquert. Solange ferne Figuren nur
 // jeden zwölften Tick und mit einem Zwölftel Tempo liefen, fiel das nicht
 // auf; seit sie richtig gehen, sind es 71 von 530. Nachgemessen haben davon
 // aber nur **13 überhaupt einen Wegpunkt auf der Fahrbahn** — die übrigen 58
 // sind unterwegs hinüber. Gefragt wird deshalb nach der Absicht, und die
 // bloße Anwesenheit bleibt als weiter gefasste zweite Schranke stehen.
 const aufStrasse = s.npcs.filter(n => L.onRoad(n.x, n.z, 0)).length;
 const zielAufStrasse = s.npcs.filter(n => {
  const z = n.path?.[n.target];
  return z && L.onRoad(z.x, z.z, 0);
 }).length;
 return {kreuzung: umkreis(-100, 20, 60), strand: umkreis(100, 250, 60),
  gesamt: s.npcs.length, aufStrasse, zielAufStrasse};
});
pruefe('Auf den Gehwegen der Innenstadt geht jemand', gehwege.kreuzung >= 8,
 `${gehwege.kreuzung} im Umkreis von 60 m an der Kreuzung`);
pruefe('Die Menge ist über die Stadt verteilt, nicht nur am Strand',
 gehwege.gesamt >= 250, `${gehwege.gesamt} Figuren`);
// Wo die Menge entsteht, stand als festes Rechteck da — die Innenstadt, bevor
// sich die Karte verdoppelt hat. Rosalind hatte dadurch null Einwohner, der
// nächste Mensch stand 528 Meter entfernt. Gefragt wird jetzt STADTGEBIETE,
// dieselbe Liste, die über Bordstein und Laterne entscheidet; geprüft wird
// gegen genau diese Liste und nicht gegen abgeschriebene Koordinaten.
const bewohner = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 return L.stadtgebiete.map((g, i) => ({i,
  leute: s.npcs.filter(q => q.x >= g.x1 && q.x <= g.x2 && q.z >= g.z1 && q.z <= g.z2).length}));
});
pruefe('In jedem Stadtgebiet wohnt jemand',
 bewohner.length >= 7 && bewohner.every(g => g.leute >= 10),
 bewohner.map(g => `${g.i}: ${g.leute}`).join(', '));
// updateRoutines schickt jede Figur um 8 Uhr zu n.work und um 20 Uhr zu
// n.home. Beide kamen aus demselben Weg: work war path[2], home path[0], und
// der Weg der Menge ist [{x,z}, ziel, {x,z}] — 382 von 530 Figuren hatten
// beides unter einem Meter auseinander, Median null. Die Routine lief und
// bewegte niemanden.
const wege = await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const d = s.npcs.filter(n => n.home && n.work)
  .map(n => Math.hypot(n.home.x - n.work.x, n.home.z - n.work.z)).sort((a, b) => a - b);
 return {n: d.length, median: d[Math.floor(d.length / 2)], gleich: d.filter(v => v < 1).length,
  laengster: Math.max(...d)};
});
pruefe('Arbeitsplatz und Wohnort liegen auseinander',
 wege.median > 100 && wege.gleich < wege.n * .35,
 `Median ${wege.median.toFixed(1)} m, ${wege.gleich} von ${wege.n} auf demselben Punkt`);
pruefe('Kein Arbeitsweg führt quer über die Karte', wege.laengster <= 400,
 `längster ${wege.laengster.toFixed(1)} m`);
pruefe('Niemand hat sein Ziel mitten auf der Fahrbahn',
 gehwege.zielAufStrasse / gehwege.gesamt < .06,
 `${gehwege.zielAufStrasse} von ${gehwege.gesamt} steuern einen Punkt auf der Fahrbahn an`);
pruefe('Die Menge wohnt nicht in den Fahrspuren',
 gehwege.aufStrasse / gehwege.gesamt < .25,
 `${gehwege.aufStrasse} von ${gehwege.gesamt} gerade auf einer Fahrbahn`);
// Verkehrsdichte. Vierundvierzig fahrende Wagen auf 15,7 Kilometern
// Straßennetz waren eines alle 357 Meter, und sie klumpten an den Ecken der
// Runden, weil der Startpunkt ein Wegpunkt war statt einer Stelle auf der
// Strecke.
const verkehr = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const fahrend = s.cars.filter(c => c.type === 'traffic');
 let laenge = 0;
 for (const r of L.strassen) laenge += Math.hypot(r.x2 - r.x1, r.z2 - r.z1);
 let zuNah = 0;
 for (let i = 0; i < fahrend.length; i++) for (let j = i + 1; j < fahrend.length; j++)
  if (Math.hypot(fahrend[i].x - fahrend[j].x, fahrend[i].z - fahrend[j].z) < 3.6) zuNah++;
 return {fahrend: fahrend.length, meterJeWagen: laenge / fahrend.length, zuNah};
});
pruefe('Der Verkehr ist dicht genug für eine Stadt', verkehr.meterJeWagen < 200,
 `ein Wagen alle ${Math.round(verkehr.meterJeWagen)} m`);
pruefe('Die Wagen klumpen nicht ineinander', verkehr.zuNah <= 3,
 `${verkehr.zuNah} Paare näher als 3,6 m bei ${verkehr.fahrend} Wagen`);
// Ferner Verkehr trägt nachts Licht. Das volle Fahrzeugmodell schaltet seine
// Scheinwerfer mit dem Sonnenstand — jenseits von 52 Metern gibt es dieses
// Modell aber nicht mehr, und damit war eine nächtliche Straße ab dieser
// Entfernung unbeleuchtet.
const fernlicht = await page.evaluate(async () => {
 const L = window.LOWTIDE, w = L.world;
 const lies = () => w.autoFern.netze
  .filter(n => n.material.emissive && n.material.emissive.getHex() !== 0)
  .map(n => +n.material.emissiveIntensity.toFixed(2));
 const bild = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 L.sim.hour = 13; await bild(); await bild();
 const tag = lies();
 L.sim.hour = 22; await bild(); await bild();
 const nacht = lies();
 L.sim.hour = 13; await bild();
 return {tag, nacht, lampen: tag.length, fern: w.autoFern.anzahl};
});
pruefe('Das grobe Fahrzeug hat Lampenflächen', fernlicht.lampen === 2,
 `${fernlicht.lampen} Materialien mit Eigenfarbe`);
pruefe('Tagsüber leuchtet der ferne Verkehr nicht', fernlicht.tag.every(v => v === 0),
 JSON.stringify(fernlicht.tag));
pruefe('Nachts leuchtet er', fernlicht.nacht.every(v => v > 1), JSON.stringify(fernlicht.nacht));
// Der Verkehr bremst für Fußgänger auf der Fahrbahn. Vorher fuhr er durch
// die Menge hindurch, ohne dass irgendetwas es bemerkte — keine Figur nahm
// Schaden, keine Kollision wurde gezählt.
//
// Gezielt statt statistisch: die erste Fassung zählte Bremsungen über
// sechshundert Ticks und meldete im Regressionslauf null, während derselbe
// Code einzeln zweihundertzehn ergab. Der Unterschied war der Zustand, den
// die vorherigen Prüfungen hinterlassen — eine Prüfung, die davon abhängt,
// prüft nicht das, was sie behauptet.
const bremsen = await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim;
 const bild = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 const c = s.cars.find(v => v.type === 'traffic');
 // Wagen auf eine freie Gerade setzen und geradeaus ausrichten.
 c.x = -100; c.z = 0; c.yaw = 0; c.speed = 9; c.wait = 0;
 c.route = [{x: -100, z: 60}, {x: -100, z: -60}]; c.target = 0;
 const n = s.npcs.find(v => v.health > 0 && !v.guard);
 const heim = {x: n.x, z: n.z};
 // Erst ohne jemanden davor: der Wagen muss fahren.
 n.x = -100; n.z = -400;
 s._aufFahrbahn = null;
 const a0 = {x: c.x, z: c.z};
 for (let k = 0; k < 12; k++) s.tick(1 / 60, {});
 const frei = Math.hypot(c.x - a0.x, c.z - a0.z);
 // Jetzt vier Meter voraus auf die Fahrbahn.
 c.x = -100; c.z = 0; c.yaw = 0;
 n.x = -100; n.z = 4;
 s._aufFahrbahn = null;
 const a1 = {x: c.x, z: c.z};
 for (let k = 0; k < 12; k++) s.tick(1 / 60, {});
 const gebremst = Math.hypot(c.x - a1.x, c.z - a1.z);
 n.x = heim.x; n.z = heim.z; s._aufFahrbahn = null;
 await bild();
 return {frei: +frei.toFixed(2), gebremst: +gebremst.toFixed(2),
  aufFahrbahn: L.onRoad(-100, 4, 0)};
});
pruefe('Die Teststelle liegt überhaupt auf einer Fahrbahn', bremsen.aufFahrbahn);
pruefe('Ohne Hindernis fährt der Wagen', bremsen.frei > .5, `${bremsen.frei} m in zwölf Ticks`);
pruefe('Mit einem Fußgänger vier Meter voraus hält er', bremsen.gebremst < .05,
 `${bremsen.gebremst} m in zwölf Ticks`);
// Figuren, die ineinander stehen. Sie kommen aus fünf Quellen, und keine
// kennt die Stellen der anderen: gemessen einundfünfzig Paare näher als 0,55
// Meter, engster Abstand 0,00.
//
// Kein Nullwert als Schwelle, sondern eine kleine Zahl: zwei Leute, die
// aneinander vorbeigehen, kommen sich zwangsläufig nahe, und die Prüfung
// läuft mitten im Spiel und nicht beim Aufbau.
// Zweite Fassung: gezählt wird, wer **dauerhaft** ineinandersteht. Zwei
// Proben im Abstand einer halben Sekunde, gewertet nur, wer in beiden
// überlappt. Der Grund steht in der Messung: beim Aufbau gibt es null Paare,
// nach vierhundert Ticks zehn — und nach zweitausend wieder zehn, aber
// **andere**. Das sind Leute, die aneinander vorbeigehen, und das war schon
// im Kommentar der ersten Fassung als zulässig benannt. Figuren weichen
// einander nicht aus; das steht als bekannte Vereinfachung im README.
const gedraenge = await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const nah = () => {
  const n = s.npcs.filter(v => v.health > 0), satz = new Set();
  let engster = 99;
  for (let i = 0; i < n.length; i++) for (let j = i + 1; j < n.length; j++) {
   const d = Math.hypot(n[i].x - n[j].x, n[i].z - n[j].z);
   if (d < .55) satz.add(n[i].id + '|' + n[j].id);
   if (d < engster) engster = d;
  }
  return {satz, engster, figuren: n.length};
 };
 const a = nah();
 for (let i = 0; i < 30; i++) s.tick(1 / 60, leer);
 const b = nah();
 const bleibend = [...a.satz].filter(k => b.satz.has(k));
 const wer = bleibend.slice(0, 5).map(k => {
  const [i, j] = k.split('|').map(Number);
  const x = s.npcs.find(v => v.id === i), y = s.npcs.find(v => v.id === j);
  return `${i}/${j} bei ${x.x.toFixed(0)}/${x.z.toFixed(0)} (${x.schedule}/${y.schedule})`;
 });
 return {paare: bleibend.length, fluechtig: a.satz.size - bleibend.length,
  engster: +Math.min(a.engster, b.engster).toFixed(2), figuren: b.figuren, wer};
});
pruefe('Keine Figuren stehen dauerhaft ineinander', gedraenge.paare < 5,
 `${gedraenge.paare} bleibende Paare unter 0,55 m (${gedraenge.fluechtig} flüchtige) bei ${gedraenge.figuren} Figuren, engster ${gedraenge.engster} m — ${(gedraenge.wer || []).join('; ')}`);
// Geparkte Wagen stehen zwei Meter innerhalb der Fahrbahnkante. Wo eine
// Verkehrsroute dort entlanglief, fuhr der Verkehr durch sie hindurch —
// wagenVoraus() kann davon nichts wissen, die Kulisse steht nicht in
// sim.cars.
const parken = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, w = L.world;
 const park = w.street?.parkplaetze || [];
 const strecken = [];
 for (const c of s.cars) {
  if (c.type !== 'traffic' || !c.route) continue;
  for (let i = 0; i < c.route.length; i++) {
   const a = c.route[i], b = c.route[(i + 1) % c.route.length];
   if (!strecken.some(t => t.a === a && t.b === b)) strecken.push({a, b});
  }
 }
 let aufDerLinie = 0, engster = 999;
 for (const q of park) {
  let m = 999;
  for (const t of strecken) {
   const dx = t.b.x - t.a.x, dz = t.b.z - t.a.z, l2 = dx * dx + dz * dz || 1;
   const u = Math.max(0, Math.min(1, ((q.x - t.a.x) * dx + (q.z - t.a.z) * dz) / l2));
   m = Math.min(m, Math.hypot(q.x - (t.a.x + dx * u), q.z - (t.a.z + dz * u)));
  }
  if (m < 2.6) aufDerLinie++;
  if (m < engster) engster = m;
 }
 return {park: park.length, aufDerLinie, engster: +engster.toFixed(2)};
});
// Bis zur Trennung von Stadt und Land waren es 503 Plätze, davon 306 weiter
// als 45 Meter vom nächsten Gebäude — Parkreihen entlang leerer Landstraßen.
// Jetzt entstehen Parkbuchten nur noch in bebautem Gebiet: 217. Die Zahl
// allein sagt nichts, deshalb kommt die Lage dazu.
pruefe('Es stehen genug Wagen am Bordstein', parken.park > 190, `${parken.park} Plätze`);
pruefe('Kein Wagen parkt an einer Landstraße', await page.evaluate(() => {
 const L = window.LOWTIDE;
 return (L.world.street.parkplaetze || []).every(o => L.imStadtgebiet(o.x, o.z));
}));
pruefe('Die Landstraße trägt keinen Gehweg', await page.evaluate(() => {
 const L = window.LOWTIDE;
 // Der Erbauer führt seine Gehwegläufe selbst mit: über das Maß allein ist
 // eine Platte nicht sicher zu erkennen — zwei Bootsstege in Pelican Key
 // haben zufällig dieselben 8,9 auf 4,2 Meter.
 return (L.world.street.gehwege || []).every(g => L.imStadtgebiet(g.x, g.z));
}), await page.evaluate(() => {
 const L = window.LOWTIDE, g = L.world.street.gehwege || [];
 return `${g.length} Läufe, ${g.filter(o => !L.imStadtgebiet(o.x, o.z)).length} davon im Land`;
}));
pruefe('Kein geparkter Wagen steht auf einer Fahrlinie', parken.aufDerLinie === 0,
 `${parken.aufDerLinie} Plätze, engster Abstand ${parken.engster} m`);
// Keine Fahrbahn über offenem Wasser. Drei Segmente liefen quer durch den
// Salzsumpf — sichtbar war davon nichts, weil groundAt über Wasser -1,2
// liefert und die Fahrbahn damit unter der Sumpffläche lag. Geblockt hat sie
// trotzdem: der Bewuchs mied einen Streifen, auf dem nichts lag.
const nasseStrassen = await page.evaluate(() => {
 const L = window.LOWTIDE;
 const schlecht = [];
 for (const r of L.strassen) {
  const laenge = Math.hypot(r.x2 - r.x1, r.z2 - r.z1);
  const schritte = Math.max(2, Math.round(laenge / 4));
  let nass = 0;
  for (let k = 0; k <= schritte; k++) {
   const t = k / schritte;
   if (L.waterAt(r.x1 + (r.x2 - r.x1) * t, r.z1 + (r.z2 - r.z1) * t)) nass++;
  }
  if (nass) schlecht.push([Math.round(r.x1), Math.round(r.z1), Math.round(nass / schritte * 100)]);
 }
 return schlecht;
});
pruefe('Keine Fahrbahn liegt über offenem Wasser', nasseStrassen.length === 0,
 `${nasseStrassen.length} Segmente, ${JSON.stringify(nasseStrassen.slice(0, 3))}`);
// Laternen und Leitungsmasten gehören an den Bordstein. Sie werden an sechs
// Stellen gesetzt, und nicht alle kannten die Fahrbahn: gemessen
// vierundachtzig Pfosten drei Meter oder tiefer in einer Spur, der tiefste
// mit neun Metern auf der Mittellinie einer achtzehn Meter breiten Straße.
const pfosten = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world;
 const tiefe = (x, z) => {
  let t = -99;
  for (const r of L.strassen) {
   const minx = Math.min(r.x1, r.x2) - r.w / 2, maxx = Math.max(r.x1, r.x2) + r.w / 2;
   const minz = Math.min(r.z1, r.z2) - r.w / 2, maxz = Math.max(r.z1, r.z2) + r.w / 2;
   if (x < minx || x > maxx || z < minz || z > maxz) continue;
   t = Math.max(t, Math.min(x - minx, maxx - x, z - minz, maxz - z));
  }
  return t;
 };
 let drin = 0, tiefster = 0;
 for (const netz of w.bloecke || []) {
  const f = netz.material.color?.getHexString();
  if (f !== '3a4a50' && f !== '6b5c48') continue;        // Laterne, Mast
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16;
   const sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   if (sy < 2) continue;                                  // nur die Masten selbst
   const t = tiefe(a[o + 12], a[o + 14]);
   if (t > 1.5) {drin++; tiefster = Math.max(tiefster, t);}
  }
 }
 return {drin, tiefster: +tiefster.toFixed(1)};
});
pruefe('Kein Mast steht in einer Fahrspur', pfosten.drin === 0,
 `${pfosten.drin} Masten, tiefster ${pfosten.tiefster} m innerhalb`);
// Jede Fundstelle der Schatzsuche muss erreichbar sein. Geborgen wird bei
// einem Abstand unter fünf Metern, und die Stellen kommen der Reihe nach —
// eine, an die man nicht herankommt, bricht die Kette ab. Die vierte lag in
// einem Haus, der nächste begehbare Punkt exakt fünf Meter entfernt.
const schaetze = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 return L.schatzOrte.map((o, i) => {
  // Reicht es, irgendwo im Umkreis von 4,5 Metern zu sein? Wasser zählt als
  // erreichbar — man schwimmt hin, und die zweite Fundstelle liegt bewusst
  // draußen im Meer. Die erste Fassung dieser Prüfung hat sie als Fehler
  // gemeldet und damit vor allem sich selbst.
  let erreichbar = !s.blocked(o, .5);
  for (let r = 1; r <= 4.5 && !erreichbar; r += .5)
   for (let k = 0; k < 12 && !erreichbar; k++) {
    const a = k * Math.PI / 6, x = o.x + Math.cos(a) * r, z = o.z + Math.sin(a) * r;
    if (!s.blocked({x, z}, .5)) erreichbar = true;
   }
  return {i, erreichbar};
 }).filter(q => !q.erreichbar).map(q => q.i);
});
pruefe('Jede Fundstelle ist erreichbar', schaetze.length === 0,
 `nicht erreichbar: ${JSON.stringify(schaetze)}`);
// Die acht Innenräume müssen begehbar bleiben. Ihre Front ist offen, der
// Raum reicht von l.z+3,6 bis l.z-11,4 — ein Solid, das sich davorschiebt,
// sperrt einen Laden aus, ohne dass irgendetwas es meldet. Bei einer Karte,
// die sich laufend ändert, ist das kein theoretischer Fall.
const innen = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 return ['garage', 'shop', 'clinic', 'home', 'club', 'diner', 'motel', 'records']
  .filter(k => L.orte[k])
  .map(k => {
   const l = L.orte[k];
   let blockiert = 0;
   for (let z = l.z + 8; z > l.z - 4; z -= .8) if (s.blocked({x: l.x, z}, .45)) blockiert++;
   return {k, blockiert, mitte: !s.blocked({x: l.x, z: l.z - 4}, .5)};
  });
});
pruefe('Alle acht Innenräume sind vorhanden', innen.length === 8, `${innen.length} gefunden`);
pruefe('In jeden Innenraum führt ein freier Weg',
 innen.every(q => q.blockiert === 0 && q.mitte),
 JSON.stringify(innen.filter(q => q.blockiert || !q.mitte)));
// Die Front war ganz offen — von der Straße aus acht Puppenstuben ohne
// vordere Wand. Jetzt steht dort eine Brüstung von 1,1 Metern mit einer
// mittigen Tür von 4,5 Metern. Beides muss gelten: durch das Schaufenster
// kommt niemand, durch die Tür jeder. Die Brüstung bleibt niedrig, damit die
// Verfolgerkamera darüber hinwegsieht — sie prüft Solids nur bis Kopfhöhe.
const front = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 return ['garage', 'shop', 'clinic', 'home', 'club', 'diner', 'motel', 'records']
  .filter(k => L.orte[k]).map(k => {
   const l = L.orte[k];
   const durch = [-6, -4, 4, 6].filter(ox => !s.blocked({x: l.x + ox, z: l.z + 4}, .45)).length;
   const tuer = [-1.5, 0, 1.5].filter(ox => !s.blocked({x: l.x + ox, z: l.z + 4}, .45)).length;
   const hoch = (s.roomWalls || []).filter(b => Math.abs(b.z - (l.z + 4)) < .6).map(b => b.h);
   return {k, durch, tuer, hoch};
  });
});
pruefe('Durch das Schaufenster kommt niemand',
 front.length === 8 && front.every(q => q.durch === 0),
 JSON.stringify(front.filter(q => q.durch)));
pruefe('Die Ladentür ist offen', front.every(q => q.tuer === 3),
 JSON.stringify(front.filter(q => q.tuer !== 3)));
pruefe('Die Brüstung bleibt unter Kamerahöhe',
 front.every(q => q.hoch.length === 2 && q.hoch.every(h => h <= 1.4)),
 JSON.stringify(front.map(q => q.hoch)));
// Ladenzeilen liefen früher nur über die beiden z-Seiten. Die Innenstadthäuser
// sind 18,8 mal 38,8 Meter — ihre langen Wände zeigen in x und standen als
// fugenlose Platten an der Straße. Gezählt werden die Schaufensterbänder
// (0x2c4149) an den Instanzmatrizen, nicht am Bild.
const zeilen = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, s = L.sim, bands = [];
 for (const im of w.bloecke) {
  if (im.material?.color?.getHexString() !== '2c4149') continue;
  const a = im.instanceMatrix.array;
  for (let i = 0; i < im.count; i++) bands.push({x: a[i * 16 + 12], z: a[i * 16 + 14]});
 }
 const H = [...s.buildings, ...s.worldBuildings].filter(b => b.kind !== 'house');
 // Freiraum: wie weit kommt man senkrecht von der Wand weg, bevor ein anderes
 // Gebäude im Weg steht? Eine Ladenzeile in einem Spalt wäre falsch.
 const frei = (px, pz, dx, dz) => {
  for (let t = .5; t <= 30; t += .5) {
   const x = px + dx * t, z = pz + dz * t;
   if (H.some(o => Math.abs(x - o.x) < o.w / 2 && Math.abs(z - o.z) < o.d / 2)) return t;
  }
  return 30;
 };
 let ohneX = 0, engste = 99;
 for (const h of H) {
  let xSeiten = 0;
  for (const [achse, seite] of [['x', -1], ['x', 1], ['z', -1], ['z', 1]]) {
   const wx = achse === 'x' ? h.x + seite * (h.w / 2 + .4) : h.x;
   const wz = achse === 'x' ? h.z : h.z + seite * (h.d / 2 + .4);
   const da = achse === 'x'
    ? bands.some(q => Math.abs(q.x - wx) < 1.2 && Math.abs(q.z - h.z) < h.d / 2)
    : bands.some(q => Math.abs(q.z - wz) < 1.2 && Math.abs(q.x - h.x) < h.w / 2);
   if (!da) continue;
   if (achse === 'x') xSeiten++;
   engste = Math.min(engste, frei(wx, wz, achse === 'x' ? seite : 0, achse === 'x' ? 0 : seite));
  }
  if (!xSeiten) ohneX++;
 }
 return {baender: bands.length, haeuser: H.length, ohneX, engste};
});
pruefe('Auch die langen Hauswände tragen eine Ladenzeile',
 zeilen.haeuser >= 30 && zeilen.ohneX === 0 && zeilen.baender > 100,
 `${zeilen.baender} Schaufensterbänder, ${zeilen.ohneX} von ${zeilen.haeuser} Häusern ohne`);
pruefe('Keine Ladenzeile steht in einem Spalt', zeilen.engste >= 8,
 `engster Freiraum ${zeilen.engste} m`);
// Tiere bleiben in ihrem Element. Der Sumpfbereich der Tierwelt ist ein
// festes Rechteck, das die neuen Dämme nicht kennt — die Bewegung prüft
// waterAt und dreht ab, statt an Land zu kriechen. Diese Prüfung hält fest,
// dass das so bleibt.
const tiere = await page.evaluate(async () => {
 const L = window.LOWTIDE, t = L.world.tiere;
 const bild = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
 let anLand = 0, gesamt = 0;
 for (let runde = 0; runde < 4; runde++) {
  await bild();
  for (const g of ['fische', 'delfine', 'alligatoren']) {
   for (const o of t[g] || []) {gesamt++; if (!L.waterAt(o.x, o.z)) anLand++;}
  }
 }
 return {anLand, gesamt};
});
pruefe('Kein Tier liegt an Land', tiere.anLand === 0,
 `${tiere.anLand} von ${tiere.gesamt} Beobachtungen`);
// Die fünf Rennstrecken haben feste Kontrollpunkte, und die Karte hat sich
// seither mehrfach geändert. Landrennen brauchen festen Boden, Wasserrennen
// Wasser — geprüft werden Punkte und die Strecke dazwischen alle acht Meter.
const strecken = await page.evaluate(() => {
 const L = window.LOWTIDE;
 const R = {
  west: {m: 'land', p: [{x:-280,z:-100},{x:-100,z:-100},{x:-100,z:200},{x:-340,z:200},{x:-340,z:80},{x:-280,z:80}]},
  drag: {m: 'land', p: [{x:-315,z:262},{x:-315,z:310},{x:-315,z:360},{x:-315,z:386}]},
  moto: {m: 'land', p: [{x:-418,z:-262},{x:-452,z:-300},{x:-486,z:-352},{x:-520,z:-410},{x:-470,z:-448},{x:-424,z:-396},{x:-402,z:-310},{x:-402,z:-248}]},
  boot: {m: 'water', p: [{x:158,z:306},{x:160,z:348},{x:300,z:352},{x:384,z:334},{x:388,z:302},{x:250,z:302}]},
  jet: {m: 'water', p: [{x:140,z:120},{x:138,z:60},{x:150,z:-10},{x:180,z:-70},{x:145,z:-120},{x:132,z:-40},{x:130,z:110}]}
 };
 const schlecht = [];
 for (const [k, r] of Object.entries(R)) {
  const falsch = (x, z) => r.m === 'land' ? L.waterAt(x, z) : !L.waterAt(x, z);
  r.p.forEach((q, i) => {if (falsch(q.x, q.z)) schlecht.push(k + ' P' + i);});
  for (let i = 0; i < r.p.length; i++) {
   const a = r.p[i], b = r.p[(i + 1) % r.p.length];
   const n = Math.max(1, Math.round(Math.hypot(b.x - a.x, b.z - a.z) / 8));
   for (let t = 0; t <= n; t++) {
    const x = a.x + (b.x - a.x) * t / n, z = a.z + (b.z - a.z) * t / n;
    if (falsch(x, z)) {schlecht.push(k + ' S' + i + '@' + Math.round(x) + '/' + Math.round(z)); break;}
   }
  }
 }
 return schlecht;
});
pruefe('Alle fünf Rennstrecken liegen im richtigen Element', strecken.length === 0,
 JSON.stringify(strecken.slice(0, 5)));
pruefe('Sparmodus schaltet die Nachbearbeitung ab', await page.evaluate(() => {
 const knopf = document.getElementById('qualityBtn'), w = window.LOWTIDE.world;
 knopf.click();
 const aus = !w.post.aktiv;
 knopf.click();
 return aus && w.post.aktiv;
}));

console.log('Die ganze Karte');
const karte = await page.evaluate(() => {
 const L = window.LOWTIDE, sim = L.sim, w = L.world, out = {};
 const b = L.bounds;
 out.flaeche = +(((b.right - b.left) * (b.bottom - b.top)) / 1e6).toFixed(2);
 // Erster Versuch: "kein Ankerpunkt im Wasser". Falsche Frage — SALT MARSH
 // ist ein Sumpf und OUTER KEYS eine Inselgruppe, deren Mitte zwischen den
 // Inseln liegt. Beides gehört ins Wasser. Die richtige Frage ist, ob es zu
 // jeder Region eine Stelle gibt, an der man stehen kann und an der regionAt
 // genau diesen Namen liefert. Eine Region, die man nie betreten kann, wäre
 // ein Name ohne Ort.
 out.unerreichbar = L.regionen.filter(r => {
  for (let dx = -200; dx <= 200; dx += 25) for (let dz = -200; dz <= 200; dz += 25) {
   const x = r.x + dx, z = r.z + dz;
   if (x < L.bounds.left || x > L.bounds.right || z < L.bounds.top || z > L.bounds.bottom) continue;
   if (!L.waterAt(x, z) && L.regionAt({x, z}) === r.name) return false;
  }
  return true;
 }).map(r => r.name);
 // Gelände deckt die ganze Karte ab, nicht nur den alten Ausschnitt.
 const kacheln = w.terrain.map(m => m.position);
 out.westlichste = Math.min(...kacheln.map(p => p.x));
 out.suedlichste = Math.max(...kacheln.map(p => p.z));
 // Die neuen Gebiete sind zu Fuß erreichbar, also nicht von Solids zugestellt.
 out.frei = [[-870, 340], [-700, 190], [-880, -120], [-620, 660]]
  .filter(([x, z]) => !sim.blocked({x, z}, .5)).length;
 // Rosalinds Hauptstraße ist eine echte Straße, keine gepflasterte Wiese.
 out.hauptstrasse = L.onRoad(-870, 340, 4);
 // Talon Ridge trägt Höhe.
 out.gipfel = Math.round(L.groundAt(-900, -160));
 // Dunst nimmt mit der Höhe ab.
 const unten = w.scene.fog.density;
 w.camera.position.y = 200; w.applySky(.016);
 const oben = w.scene.fog.density;
 w.camera.position.y = 3; w.applySky(.016);
 out.dunstUnten = +unten.toFixed(5);
 out.dunstOben = +oben.toFixed(5);
 return out;
});
pruefe('Die Karte ist über zwei Quadratkilometer groß', karte.flaeche > 2, `${karte.flaeche} km²`);
pruefe('Kein Gebäude steht in einer Fahrbahn', await page.evaluate(() => {
 // Ein Haus mitten auf der Straße fällt beim Spielen sofort auf, beim
 // Bauen aber nicht — die Blöcke werden nach Rastermaß gesetzt, die Straßen
 // getrennt davon. Diese Prüfung hat einen alten Fehler gefunden: ein Haus
 // ragte 5,5 m in die Nord-Süd-Achse bei x = -340.
 const L = window.LOWTIDE, sim = L.sim;
 const ueber = (b, r) => {
  const rx1 = Math.min(r.x1, r.x2) - r.w / 2, rx2 = Math.max(r.x1, r.x2) + r.w / 2;
  const rz1 = Math.min(r.z1, r.z2) - r.w / 2, rz2 = Math.max(r.z1, r.z2) + r.w / 2;
  const ox = Math.min(b.x + b.w / 2, rx2) - Math.max(b.x - b.w / 2, rx1);
  const oz = Math.min(b.z + b.d / 2, rz2) - Math.max(b.z - b.d / 2, rz1);
  return ox > 0 && oz > 0 ? Math.min(ox, oz) : 0;
 };
 const schlimmste = [...sim.buildings, ...sim.worldBuildings].reduce((m, b) =>
  Math.max(m, L.strassen.reduce((q, r) => Math.max(q, ueber(b, r)), 0)), 0);
 return schlimmste <= 1;
}));
pruefe('Keine zwei Gebäude stehen ineinander', await page.evaluate(() => {
 const alle = [...window.LOWTIDE.sim.buildings, ...window.LOWTIDE.sim.worldBuildings];
 for (let i = 0; i < alle.length; i++) for (let j = i + 1; j < alle.length; j++) {
  const a = alle[i], b = alle[j];
  if (Math.abs(a.x - b.x) < (a.w + b.w) / 2 - 1 && Math.abs(a.z - b.z) < (a.d + b.d) / 2 - 1) return false;
 }
 return true;
}));
pruefe('Jede Region hat eine Stelle, an der man stehen kann',
 karte.unerreichbar.length === 0, karte.unerreichbar.join(', '));
pruefe('Das Gelände reicht bis an den Westrand', karte.westlichste < -1000, `${karte.westlichste}`);
pruefe('Das Gelände reicht bis an den Südrand', karte.suedlichste > 800, `${karte.suedlichste}`);
pruefe('Die vier neuen Gebiete sind begehbar', karte.frei === 4, `${karte.frei} von 4`);
pruefe('Rosalinds Hauptstraße ist befahrbar', karte.hauptstrasse);
pruefe('Talon Ridge trägt Höhe', karte.gipfel > 70, `${karte.gipfel} m`);
pruefe('Dunst nimmt mit der Höhe ab', karte.dunstOben < karte.dunstUnten * .6,
 `${karte.dunstUnten} unten, ${karte.dunstOben} auf 200 m`);
pruefe('Geparkte Wagen nutzen das sparsame Vorbild', await page.evaluate(() => {
 // 796 statt 3084 Dreiecke je Wagen: keine Torusreifen, kein Innenraum,
 // keine Speichen. Prüfbar an der Dreieckszahl der gebackenen Instanzen.
 const w = window.LOWTIDE.world;
 let groesste = 0;
 w.scene.traverse(o => {
  if (!o.isInstancedMesh || o.count < 100 || !o.geometry) return;
  const g = o.geometry, n = (g.index ? g.index.count : g.attributes.position.count) / 3;
  groesste = Math.max(groesste, n);
 });
 return groesste < 400;
}));

console.log('Publikum und Neon');
const leute = await page.evaluate(() => {
 const L = window.LOWTIDE, sim = L.sim, w = L.world, out = {};
 out.anzahl = sim.npcs.length;
 out.imWasser = sim.npcs.filter(n => L.waterAt(n.x, n.z)).length;
 // Radius 0: geprüft wird, ob jemand wirklich in einer Wand steckt. Mit .5
 // schlug schon an, wer sich beim Vorbeigehen an eine Wand drückt.
 out.imHaus = sim.npcs.filter(n => sim.blocked(n, 0)).length;
 // Ohne originalPath, home und work stürzt updateRoutines beim Tageswechsel.
 out.ohneWeg = sim.npcs.filter(n => !n.guard && (!n.originalPath || !n.home || !n.work)).length;
 out.doppelt = sim.npcs.length - new Set(sim.npcs.map(n => n.id)).size;
 // Figurengeometrie wird geteilt; Gesichter nur je Hautton.
 const a = new Set(), b = new Set();
 w.npcs[0].traverse(o => o.isMesh && a.add(o.geometry.uuid));
 w.npcs[7].traverse(o => o.isMesh && b.add(o.geometry.uuid));
 out.geteilt = [...a].filter(u => b.has(u)).length;
 out.formen = a.size;
 out.gesichter = new Set(w.npcs.slice(0, 20).map(m => m.userData.face.geometry.uuid)).size;
 out.hauttoene = new Set(w.npcs.slice(0, 20)
  .map(m => m.userData.face.geometry.attributes.color.getX(10).toFixed(4))).size;
 // Neon: die Leuchtmaterialien werden mit der Nacht hochgefahren.
 sim.hour = 13; w.applySky(.016);
 const tags = L.leuchten.map(m => m.emissiveIntensity);
 sim.hour = 23; w.applySky(.016);
 const nachts = L.leuchten.map(m => m.emissiveIntensity);
 out.leuchten = tags.length;
 out.heller = nachts.filter((v, i) => v > tags[i] + .05).length;
 return out;
});
pruefe('Mindestens hundertfünfzig Leute in der Stadt', leute.anzahl >= 150, `${leute.anzahl}`);
pruefe('Niemand steht im Wasser oder in einer Wand', leute.imWasser === 0 && leute.imHaus === 0,
 `${leute.imWasser} im Wasser, ${leute.imHaus} in Wänden`);
pruefe('Jede Figur hat Weg, Wohnung und Arbeit', leute.ohneWeg === 0, `${leute.ohneWeg} ohne`);
pruefe('Keine doppelten Figurennummern', leute.doppelt === 0);
pruefe('Figuren teilen sich ihre Geometrie', leute.geteilt >= 8, `${leute.geteilt} von ${leute.formen}`);
pruefe('Gesichter gibt es je Hautton, nicht je Kopf',
 leute.gesichter === 5 && leute.hauttoene === 5, `${leute.gesichter} Formen, ${leute.hauttoene} Töne`);
pruefe('Figuren haben einen drehbaren Kopf', await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 return w.npcs.every(m => m.userData.kopf && m.userData.kopf.children.length > 4);
}));
pruefe('Im Stand sieht sich die Menge um, und nicht im Gleichtakt', await page.evaluate(async () => {
 const L = window.LOWTIDE, w = L.world;
 // Ein paar Bilder laufen lassen und die Kopfdrehungen einsammeln.
 for (let i = 0; i < 3; i++) await new Promise(r => requestAnimationFrame(r));
 const winkel = w.npcs.slice(0, 40).map(m => +m.userData.kopf.rotation.y.toFixed(3));
 const bewegt = winkel.filter(v => Math.abs(v) > .02).length;
 // Ein Gleichtakt wäre daran zu erkennen, dass alle denselben Wert haben.
 const verschieden = new Set(winkel).size;
 return bewegt > 8 && verschieden > 15;
}));

pruefe('Neon und Fenster gehen nachts an', leute.heller > 20,
 `${leute.heller} von ${leute.leuchten} Leuchtmaterialien heller`);

console.log('Verkehr, Bewuchs, Geometrie');
const dichte = await page.evaluate(() => {
 const L = window.LOWTIDE, sim = L.sim, w = L.world, out = {};
 const verkehr = sim.cars.filter(c => c.type === 'traffic');
 out.verkehr = verkehr.length;
 out.wegImWasser = verkehr.filter(c => c.route.some(p => L.waterAt(p.x, p.z))).length;
 out.wegImHaus = verkehr.filter(c => c.route.some(p => sim.blocked(p, 1.2))).length;
 // Bewuchs: keine Matrix mit Skalierung null — die wird singulär und
 // three zeichnet daraus große schwarze Flächen statt nichts.
 // Der Bewuchs wird um den Spieler gesetzt. In der Innenstadt steht
 // absichtlich kein Halm, also erst in den Vorort versetzen.
 const g = w.gras;
 g.setzen(-60, -320, true);
 const arr = g.netz.instanceMatrix.array;
 let null_ = 0, ueberBoden = 0;
 for (let i = 0; i < g.netz.count; i++) {
  const o = i * 16;
  const sy = Math.hypot(arr[o + 4], arr[o + 5], arr[o + 6]);
  if (sy < 1e-6) null_++;
  if (arr[o + 13] > -1) ueberBoden++;
 }
 out.halme = g.netz.count;
 out.nullSkalierung = null_;
 out.sichtbareHalme = ueberBoden;
 out.wind = !!g.material.userData.gStaerke;
 // Halme dürfen nicht auf der Fahrbahn stehen.
 let aufStrasse = 0;
 for (let i = 0; i < g.netz.count; i++) {
  const o = i * 16;
  if (arr[o + 13] < -1) continue;
  if (!g.erlaubt(arr[o + 12], arr[o + 14])) aufStrasse++;
 }
 out.aufStrasse = aufStrasse;
 // Fahrzeuggeometrie wird zwischen Exemplaren geteilt.
 const autos = w.cars.filter(m => m.userData.body && m.userData.rims);
 if (autos.length > 1) {
  const a = new Set(), b = new Set();
  autos[0].traverse(o => o.isMesh && a.add(o.geometry.uuid));
  autos[1].traverse(o => o.isMesh && b.add(o.geometry.uuid));
  out.geteilt = [...a].filter(u => b.has(u)).length;
  out.formen = a.size;
 }
 return out;
});
pruefe('Es fahren mindestens dreißig Wagen', dichte.verkehr >= 30, `${dichte.verkehr} Wagen`);
pruefe('Kein Verkehrsweg führt ins Wasser', dichte.wegImWasser === 0);
pruefe('Kein Verkehrsweg führt durch ein Gebäude', dichte.wegImHaus === 0);
pruefe('Bewuchs hat keine entartete Matrix', dichte.nullSkalierung === 0, `${dichte.nullSkalierung} von ${dichte.halme}`);
pruefe('Bewuchs steht nur auf erlaubtem Grund', dichte.aufStrasse === 0, `${dichte.aufStrasse} Halme daneben`);
pruefe('Ein Teil der Halme steht sichtbar über dem Boden', dichte.sichtbareHalme > 200,
 `${dichte.sichtbareHalme} von ${dichte.halme}`);
pruefe('Der Wind erreicht den Bewuchs', dichte.wind);
pruefe('Bäume laufen über zwei Instanzennetze mit Alphakarte', await page.evaluate(() => {
 const w = window.LOWTIDE.world, l = w.laubwerk;
 if (!l?.kronen || !l.staemme) return false;
 const g = l.kronen.geometry, m = l.kronen.material;
 return l.kronen.count > 800                       // die Bäume der ganzen Karte
  && !!g.attributes.color                          // sonst liest three schwarz
  && !!l.kronen.instanceColor                      // Farbe je Baum
  && !!m.map && m.alphaTest > .2                   // Alphakarte, nicht Kiste
  && (g.index ? g.index.count : 0) / 3 <= 8;       // drei gekreuzte Flächen
}));
pruefe('Kronen bleiben von hinten beleuchtet', await page.evaluate(() => {
 // Bei DoubleSide dreht three die Normale für Rückseiten um; bei gekreuzten
 // Flächen sieht man immer die Hälfte von hinten. Ohne den Eingriff im
 // Shader standen die Kronen zur Hälfte im Schatten.
 const m = window.LOWTIDE.world.laubwerk?.kronen?.material;
 return !!m && typeof m.onBeforeCompile === 'function'
  && String(m.onBeforeCompile).includes('normal_fragment_begin');
}));
pruefe('Fahrzeuge teilen sich ihre Geometrie', dichte.geteilt === dichte.formen && dichte.formen >= 8,
 `${dichte.geteilt} von ${dichte.formen}`);

console.log('Gang und Sichtweite');
const gang = await page.evaluate(() => {
 const L = window.LOWTIDE, welt = L.world, figur = welt.player, u = figur.userData;
 const out = {gelenke: u.ankles?.length || 0, sohle: [], hang: 0};
 // Einen Schrittzyklus durchfahren und die Sohlenneigung mitschreiben. Sie
 // ergibt sich aus Hüfte plus Knie plus Sprunggelenk; ohne Gelenk wäre sie
 // gleich der Kette und liefe bis ±1,1 rad auf.
 for (let k = 0; k < 24; k++) {
  figur.position.x += .09; figur.position.z += .09;
  welt.animateHuman(figur, 10 + k * .05, 1, false);
  out.sohle.push(u.legs[0].rotation.x + u.knees[0].rotation.x + (u.ankles?.[0]?.rotation.x || 0));
 }
 out.groesste = Math.max(...out.sohle.map(Math.abs));
 out.kette = Math.max(...u.legs.map(() => 0), ...out.sohle.map(() => 0));
 // Am Hang im Nationalpark muss die Neigung ungleich null sein.
 figur.position.set(-470, 0, -400); figur.rotation.y = 1.2;
 out.hang = Math.abs(welt.bodenNeigung(figur));
 figur.position.set(0, 0, 0);
 out.ebene = Math.abs(welt.bodenNeigung(figur));
 return out;
});
pruefe('Figuren haben Sprunggelenke', gang.gelenke === 2);
pruefe('Sohle bleibt im Schritt annähernd waagerecht', gang.groesste < .62, `max ${gang.groesste.toFixed(2)} rad`);
pruefe('Bodenneigung greift am Hang und nicht in der Ebene', gang.hang > .05 && gang.ebene < .001,
 `Hang ${gang.hang.toFixed(2)} rad, Ebene ${gang.ebene.toFixed(3)} rad`);
pruefe('Ferne Blöcke werden nach Entfernung verworfen', await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 window.LOWTIDE.view(-40, 60);
 w.bloeckeSichten(.0038);
 const versteckt = w.bloecke.filter(m => !m.visible).length;
 w.bloeckeSichten(.0002);          // Luftbilddichte: alles muss zurückkommen
 const wieder = w.bloecke.filter(m => !m.visible).length;
 return versteckt > 5 && wieder === 0;
}));

console.log('Rendern');
const info = await page.evaluate(() => {const i = window.LOWTIDE.world.renderer.info; return {c: i.render.calls, t: i.render.triangles};});
pruefe('Es wird tatsächlich gezeichnet', info.c > 100, `${info.c} Draw Calls, ${info.t.toLocaleString('de-DE')} Dreiecke`);

// Kein Moment des Tages darf dunkler sein als Mitternacht. Der Startpunkt des
// Spiels lag bei 18:40 Uhr genau in einer solchen Senke: mittlere Helligkeit
// 48,2 gegen 64,2 um Mitternacht, und 38,9 Prozent der Fläche unter 10 von
// 255. Die Sonne stand zu tief für die Straße, die Laternen waren noch aus.
// Belichtung, Dunst und Sonnenfarbe werden über die Zeit geglättet. Beide
// Bildmessungen warteten dafür auf **vier Bilder** — und ein Bild ist unter
// SwiftShader sechs Sekunden Wanduhr, aber nur dt = 0,05 s simulierte
// Glättung. Gemessen wurde also ein Zustand irgendwo auf halbem Weg, und das
// Ergebnis hing am Bildtakt: über drei Wiederholungen streuten die Werte um
// 1,8 bis 3,6 von 255. Mit deterministischem Einschwingen — 240 Aufrufe von
// applySky mit festem dt, also vier simulierte Sekunden — sind es 0,2 bis 0,8.
const einschwingen = () => page.evaluate(() => {
 for (let i = 0; i < 240; i++) window.LOWTIDE.world.applySky(1 / 60);
});
const tagesgang = {};
for (const h of [7, 13, 18, 18.7, 23]) {
 await page.evaluate(x => {const L = window.LOWTIDE; L.sim.hour = x; L.sim.weather = 'clear';
  L.luftbild(-24, 3.7, 86, -30, 1.6, 78);}, h);
 const n0 = await page.evaluate(() => window.LOWTIDE.frames);
 await page.waitForFunction(k => window.LOWTIDE.frames > k + 4, n0, {timeout: 60000});
 await einschwingen();
 tagesgang[h] = await page.evaluate(() => {
  const L = window.LOWTIDE; L.world.zeichne();
  const gl = L.world.renderer.getContext();
  const w = gl.drawingBufferWidth, h2 = gl.drawingBufferHeight;
  const px = new Uint8Array(w * h2 * 4);
  gl.readPixels(0, 0, w, h2, gl.RGBA, gl.UNSIGNED_BYTE, px);
  let sum = 0, dunkel = 0, n = 0;
  for (let i = 0; i < px.length; i += 4) {
   const g = .2126 * px[i] + .7152 * px[i + 1] + .0722 * px[i + 2];
   sum += g; n++; if (g < 10) dunkel++;
  }
  return {mittel: sum / n, dunkel: 100 * dunkel / n};
 });
}
pruefe('Keine Stunde ist dunkler als Mitternacht',
 [7, 13, 18, 18.7].every(h => tagesgang[h].mittel >= tagesgang[23].mittel),
 Object.entries(tagesgang).map(([h, m]) => `${h}h ${m.mittel.toFixed(0)}`).join(', '));
pruefe('Nirgends säuft ein Fünftel des Bildes ab',
 Object.values(tagesgang).every(m => m.dunkel < 12),
 Object.entries(tagesgang).map(([h, m]) => `${h}h ${m.dunkel.toFixed(1)} %`).join(', '));
pruefe('Am Mittag brennt keine Laterne', await page.evaluate(() => {
 const L = window.LOWTIDE;
 L.sim.hour = 13; L.world.sky.update(13, 'clear', L.world.camera.position, 0);
 const mittag = L.world.sky.lampen;
 L.world.sky.update(18.7, 'clear', L.world.camera.position, 0);
 const daemmerung = L.world.sky.lampen;
 return mittag === 0 && daemmerung > .5;
}));

// Auch dieser Abschnitt steht am Ende: er stellt Uhrzeit, Wetter und Kamera
// um. Weiter oben eingesetzt ließ er 'Akt 4 zahlt aus und führt in Akt 5'
// fallen, weil der vierte Akt bei Nacht spielt.
// Vier Wetter, die man auf einem Standbild auseinanderhalten kann. Gemessen
// an derselben Kreuzung um 13 Uhr lagen sie vorher zwischen 136,2 und 148,1
// mittlerer Helligkeit — zwölf von 255 zwischen wolkenlosem Mittag und
// Gewitter, weil die erhöhte Streuung fast genau aufhob, was die gedämpfte
// Sonne wegnahm.
const wetterHelligkeit = {}, wetterZweit = {};
for (const wetter of ['clear', 'rain', 'fog', 'storm']) {
 await page.evaluate(w => {const L = window.LOWTIDE; L.sim.hour = 13; L.sim.weather = w;
  L.luftbild(-175, 8, 20, -100, 4, 60);}, wetter);
 const n0 = await page.evaluate(() => window.LOWTIDE.frames);
 await page.waitForFunction(k => window.LOWTIDE.frames > k + 4, n0, {timeout: 60000});
 await einschwingen();
 wetterHelligkeit[wetter] = await page.evaluate(() => {
  const L = window.LOWTIDE; L.world.zeichne();
  const gl = L.world.renderer.getContext();
  const w = gl.drawingBufferWidth, h = gl.drawingBufferHeight;
  const px = new Uint8Array(w * h * 4);
  gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
  let sum = 0;
  for (let i = 0; i < px.length; i += 4) sum += .2126 * px[i] + .7152 * px[i + 1] + .0722 * px[i + 2];
  return sum / (px.length / 4);
 });
 // Zweite Messung nach weiterem Einschwingen. Ein eingeschwungener Zustand
 // ändert sich nicht mehr; tut er es doch, ist die Messung selbst unbrauchbar
 // und soll das melden, statt eine Zahl zu liefern, der man nicht trauen kann.
 // Einmal in dieser Sitzung meldete dieselbe Stelle für Sturm 165,0 statt der
 // üblichen 117 — ein Ausreißer, den die Streuung oben nicht erklärt.
 await einschwingen();
 wetterZweit[wetter] = await page.evaluate(() => {
  const L = window.LOWTIDE; L.world.zeichne();
  const gl = L.world.renderer.getContext();
  const w = gl.drawingBufferWidth, h = gl.drawingBufferHeight;
  const px = new Uint8Array(w * h * 4);
  gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
  let sum = 0;
  for (let i = 0; i < px.length; i += 4) sum += .2126 * px[i] + .7152 * px[i + 1] + .0722 * px[i + 2];
  return sum / (px.length / 4);
 });
}
await page.evaluate(() => {const L = window.LOWTIDE; L.sim.weather = 'clear'; L.world.freieKamera = false;});
await bilder(3);
pruefe('Gewitter ist deutlich dunkler als klarer Mittag',
 wetterHelligkeit.clear - wetterHelligkeit.storm > 25,
 Object.entries(wetterHelligkeit).map(([k, v]) => `${k} ${v.toFixed(1)}`).join(', '));
pruefe('Nebel nimmt Sicht, nicht Helligkeit',
 wetterHelligkeit.clear - wetterHelligkeit.fog < 25 && wetterHelligkeit.fog > wetterHelligkeit.storm);
pruefe('Die Helligkeitsmessung ist eingeschwungen',
 Object.keys(wetterHelligkeit).every(k => Math.abs(wetterHelligkeit[k] - wetterZweit[k]) <= 3),
 Object.keys(wetterHelligkeit).map(k =>
  `${k} ${wetterHelligkeit[k].toFixed(1)}/${wetterZweit[k].toFixed(1)}`).join(', '));
pruefe('Regen ist dichter als vorher', await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 // Tropfen je Quadratmeter im Feld um die Kamera.
 return w.rainTropfen / (46 * 46) > .8;
}));

// Die Routen liegen auf der Straße — fährt der Verkehr auch darauf? Dreißig
// Sekunden Simulation, jede Sekunde jeder fahrende Wagen geprüft.
//
// Dieser Abschnitt steht als letzter vor dem Schließen des Browsers, weil er
// die Simulation weiterlaufen lässt: Uhr, Wetter, Figurenzustände und
// Ereignisse wandern dabei mit. Weiter oben eingesetzt ließ er 'Akt 4 zahlt
// aus und führt in Akt 5' fallen — dieselbe Sorte Fehler wie damals bei der
// Bremsprüfung, nur diesmal von der neuen Prüfung verursacht statt gefunden.
await page.evaluate(() => {window.__fahrt = {proben: 0, neben: 0, nass: 0, steht: 0,
 leute: 0, leuteNass: 0, leuteImHaus: 0};});
// In zehn Abschnitten statt in einem, damit der Renderer zwischendurch
// drankommt.
for (let teil = 0; teil < 10; teil++) {
 await page.evaluate(() => {
  const L = window.LOWTIDE, s = L.sim, z = window.__fahrt;
  for (let i = 0; i < 60; i++) {
   s.tick(.05, {});
   if (i % 20) continue;
   for (const c of s.cars) {
    if (c.type !== 'traffic') continue;
    z.proben++;
    if (Math.abs(c.speed) < .5) z.steht++;
    if (L.waterAt(c.x, c.z)) z.nass++;
    if (!L.onRoad(c.x, c.z, 0)) {
     z.neben++;
     if (!z.nebenWo) z.nebenWo = [];
     if (z.nebenWo.length < 5) z.nebenWo.push(`${c.model} [${Math.round(c.x)},${Math.round(c.z)}] stau ${(c.stau || 0).toFixed(1)} yaw ${c.yaw.toFixed(2)}`);
    }
   }
   // Dieselbe Frage für die Figuren. Auf der Fahrbahn zu stehen ist erlaubt —
   // wer eine Straße überquert, tut genau das. Im Wasser oder in einer Wand
   // nicht.
   for (const n of (s._alleNpcs || s.npcs)) {
    if (n.health <= 0) continue;
    z.leute++;
    if (L.waterAt(n.x, n.z)) z.leuteNass++;
    if (s.blocked({x: n.x, z: n.z}, .2)) z.leuteImHaus++;
   }
  }
 });
}
const gefahren = await page.evaluate(() => window.__fahrt);
pruefe('Kein fahrender Wagen verlässt die Fahrbahn', gefahren.neben === 0,
 (gefahren.nebenWo || []).join('; ') + ' — ' +
 `${gefahren.neben} von ${gefahren.proben} Proben`);
pruefe('Kein fahrender Wagen steht im Wasser', gefahren.nass === 0,
 `${gefahren.nass} von ${gefahren.proben} Proben`);
pruefe('Keine Figur läuft ins Wasser', gefahren.leuteNass === 0,
 `${gefahren.leuteNass} von ${gefahren.leute} Proben`);
pruefe('Keine Figur läuft durch eine Wand', gefahren.leuteImHaus === 0,
 `${gefahren.leuteImHaus} von ${gefahren.leute} Proben`);
// Der Ridge Highway lag sechseinhalb Meter über der Westspitze des Stausees.
pruefe('Kein Baum steht im Wasser', await page.evaluate(() => {
 const L = window.LOWTIDE;
 // Mangroven stehen im Wasser, dafür sind sie Mangroven.
 return (L.world.laubwerk?.liste || []).filter(t => t.art !== 'mangrove')
  .every(t => !L.waterAt(t.x, t.z));
}), await page.evaluate(() => {
 const L = window.LOWTIDE, l = (L.world.laubwerk?.liste || []).filter(t => t.art !== 'mangrove');
 return `${l.filter(t => L.waterAt(t.x, t.z)).length} von ${l.length}`;
}));

// Streifenwagen fahren auf Straßen. findPath() kannte nur „frei" und
// „blockiert" und schickte sie quer über Plätze und Grünflächen: elf von
// fünfundneunzig Proben während einer Verfolgung lagen neben jeder Fahrbahn.
// Ein Gewicht statt einer Sperre — Straße kostet 1, alles andere 3,5 — hält
// sie darauf, ohne sie einzusperren.
const streife = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null; s.dispatchTimer = 0;
 for (const c of s.cops) {c.active = false; c.route = []; c.blockTarget = null; c.blocking = false;}
 s.player.car = null; s.player.x = -100; s.player.z = 40; s.player.y = 0; s.player.health = 100;
 s.crime(3);
 let proben = 0, neben = 0, nass = 0, aktiv = 0;
 for (let i = 0; i < 400; i++) {
  s.tick(.05, {});
  if (i % 10) continue;
  for (const c of s.cops) {
   if (!c.active || c.health <= 0) continue;
   proben++; aktiv = Math.max(aktiv, s.cops.filter(x => x.active).length);
   if (!L.onRoad(c.x, c.z, 0)) neben++;
   if (L.waterAt(c.x, c.z)) nass++;
  }
 }
 const sterne = s.stars;
 // Flucht: weit weg und lange genug, dann muss die Fahndung enden.
 s.player.x = -880; s.player.z = 340; s.spotted = false;
 for (let i = 0; i < 1600; i++) s.tick(.05, {});
 const danach = s.stars;
 s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;
 for (const c of s.cops) {c.active = false; c.route = [];}
 return {proben, neben, nass, aktiv, sterne, danach};
});
pruefe('Eine Straftat ruft Streifen und hebt die Fahndung',
 streife.aktiv >= 2 && streife.sterne >= 1, `${streife.aktiv} Streifen, ${streife.sterne} Sterne`);
pruefe('Streifenwagen fahren auf der Fahrbahn', streife.neben === 0 && streife.nass === 0,
 `${streife.neben} neben der Fahrbahn, ${streife.nass} im Wasser, von ${streife.proben} Proben`);
pruefe('Weit genug weg endet die Fahndung', streife.danach === 0, String(streife.danach));

// Windpark auf dem Kamm. Der Rotordurchmesser ist 48 Meter (Blattlänge 24,
// Wurzel an der Nabe); die Anlagen standen vorher 35,4 Meter auseinander und
// fuhren dadurch durcheinander hindurch. Steht am Ende des Laufs, weil die
// zweite Prüfung Bilder braucht und dafür die Pause aufheben muss.
const park = await page.evaluate(() => {
 const w = window.LOWTIDE.world, r = w.rotoren || [];
 let naechster = Infinity;
 for (let i = 0; i < r.length; i++) for (let k = i + 1; k < r.length; k++)
  naechster = Math.min(naechster, Math.hypot(r[i].x - r[k].x, r[i].z - r[k].z));
 return {anzahl: r.length, naechster, blaetter: w.rotorNetz ? w.rotorNetz.count : 0,
  gesichtet: !!(w.bloecke || []).includes(w.rotorNetz)};
});
pruefe('Die Windräder greifen nicht ineinander', park.anzahl >= 3 && park.naechster > 96,
 `${park.anzahl} Anlagen, nächster Abstand ${park.naechster} m bei 48 m Rotordurchmesser`);
pruefe('Die Rotoren werden mit den Türmen ausgeblendet', park.gesichtet && park.blaetter === park.anzahl * 3,
 `${park.blaetter} Blätter, in bloecke: ${park.gesichtet}`);
const dreht = await (async () => {
 await page.evaluate(() => {window.LOWTIDE.sim.paused = false;});
 const vorher = await page.evaluate(() => {
  const n = window.LOWTIDE.world.rotorNetz;
  return {winkel: window.LOWTIDE.world.rotorWinkel, m: [...n.instanceMatrix.array.slice(0, 4)]};
 });
 await bilder(2);
 return await page.evaluate(v => {
  const w = window.LOWTIDE.world, a = w.rotorNetz.instanceMatrix.array;
  let anders = 0;
  for (let i = 0; i < 4; i++) if (Math.abs(a[i] - v.m[i]) > 1e-4) anders++;
  return {zuwachs: w.rotorWinkel - v.winkel, anders};
 }, vorher);
})();
pruefe('Die Rotoren drehen sich', dreht.zuwachs > .001 && dreht.anders > 0,
 `Winkel +${dreht.zuwachs.toFixed(3)} rad, ${dreht.anders} von 4 Matrixwerten geändert`);

// Tageslauf. Steht am Ende, weil dafür zehntausende Ticks laufen und die Uhr
// verstellt wird. Zwei Fragen: bleibt der Tageswechsel bezahlbar, und bewegt
// er tatsächlich jemanden.
//
// Als alle Pendler ihren Weg im selben Tick suchten, stand das Spiel 1613 ms
// still. Die Schwelle liegt bei 120 ms — großzügig genug für einen langsamen
// Rechner, weit unter dem Fehlerfall.
const tageslauf = await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const pend = () => s.npcs.filter(n => n.id >= 200 && n.work &&
  Math.hypot(n.work.x - n.home.x, n.work.z - n.home.z) > 120);
 for (let i = 0; i < 120; i++) s.tick(1 / 60, leer);
 s.hour = 7.995;
 let teuerster = 0;
 for (let i = 0; i < 90; i++) {
  const t = performance.now(); s.tick(1 / 60, leer);
  teuerster = Math.max(teuerster, performance.now() - t);
 }
 const phase = (stunde, ticks) => {
  s.hour = stunde;
  for (let i = 0; i < ticks; i++) {s.tick(1 / 60, leer); s.hour = stunde;}
  const q = pend();
  return {naeherAmBuero: q.filter(n => Math.hypot(n.x - n.work.x, n.z - n.work.z) <
   Math.hypot(n.x - n.home.x, n.z - n.home.z)).length, von: q.length};
 };
 const tag = phase(9, 14000), nacht = phase(22, 14000);
 return {teuerster, tag, nacht};
});
pruefe('Der Tageswechsel hält das Spiel nicht an', tageslauf.teuerster < 120,
 `teuerster Tick ${tageslauf.teuerster.toFixed(1)} ms`);
// §69 des Pflichtenhefts verbietet Fake-Features. Nachgesehen, was der
// Spieler überhaupt kann: Nahkampf, Griff, Deckung, Ausweichen, Sprung,
// Waffenwechsel, Nachladen. Alle sieben tun etwas — und **keines davon war
// geprüft**. Das ist der Befund: nicht dass sie fehlen, sondern dass nichts
// sie hält. Steht am Ende, weil dafür der Spieler versetzt wird.
const verben = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, p = s.player;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const stelle = (x, z) => {p.x = x; p.z = z; p.y = 0; p.car = null; p.health = 100;
  p.stamina = 100; p.cooldown = 0; s.stars = 0; s.heat = 0; s.reloadJob = null;};
 const opfer = () => {
  const n = s.npcs[0];
  n.x = p.x + Math.sin(p.yaw) * 1.6; n.z = p.z + Math.cos(p.yaw) * 1.6;
  n.health = 100; n.state = 'normal'; n.stun = 0; return n;
 };
 const aus = {};
 stelle(-100, 20); let o = opfer();
 s.melee(); aus.nahkampf = 100 - o.health;
 stelle(-100, 20); o = opfer();
 s.grapple(); aus.griffStun = o.stun || 0;
 const b = s.solids.find(q => q.kind === 'building') || s.solids[0];
 stelle(b.x + b.w / 2 + 1, b.z); p.cover = false; s.cover(); aus.deckungAnDerWand = p.cover;
 stelle(-100, 300); p.cover = false; s.cover(); aus.deckungImFreien = p.cover;
 stelle(-100, 20);
 const xv = p.x, zv = p.z, av = p.stamina;
 s.dodge();
 aus.ausweichenStrecke = Math.hypot(p.x - xv, p.z - zv);
 aus.ausweichenAusdauer = av - p.stamina;
 stelle(-100, 20); p.vy = 0; s.jump(); aus.sprungVy = p.vy || 0;
 // Durchschalten braucht mehr als eine Waffe im Inventar — mit nur einer ist
 // ein Nicht-Wechsel richtig und kein Fehler.
 stelle(-100, 20);
 const merkInv = p.inventory, merkW = p.weapon;
 p.inventory = {pistol: {ammo: 12, reserve: 60}, shotgun: {ammo: 6, reserve: 24},
  rifle: {ammo: 30, reserve: 90}, taser: {ammo: 5, reserve: 10}};
 p.weapon = 'pistol';
 const folge = [p.weapon];
 for (let i = 0; i < 4; i++) {s.cycleWeapon(); folge.push(p.weapon);}
 aus.durchschalten = folge;
 p.inventory = merkInv; p.weapon = merkW;
 // Nachladen ist ein Auftrag über Zeit, kein sofortiger Sprung.
 stelle(-100, 20); p.weapon = 'pistol'; p.ammo = 3; p.reserve = 40;
 s.reload();
 aus.sofortNachRuf = {ammo: p.ammo, auftrag: !!s.reloadJob};
 for (let i = 0; i < 200; i++) s.tick(1 / 60, leer);
 aus.nachWartezeit = {ammo: p.ammo, reserve: p.reserve, auftrag: !!s.reloadJob};
 return aus;
});
// Möbel. Bänke, Liegen und Barhocker standen überall, und auf keinem einzigen
// saß jemand: jede Figur der Karte ging oder stand. Die Sitzplätze melden
// sich jetzt beim Bauen an, und ein Teil der Menge nimmt Platz — mit eigener
// Haltung, denn eine stehende Figur mitten in der Sitzfläche sähe schlechter
// aus als eine leere Bank.
const moebel = await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const plaetze = s.sitzplaetze || [];
 const arten = {};
 for (const q of plaetze) arten[q.art] = (arten[q.art] || 0) + 1;
 const sitzend = s.npcs.filter(n => n.state === 'sitzend');
 const daneben = sitzend.filter(n => !n.sitzplatz ||
  Math.hypot(n.x - n.sitzplatz.x, n.z - n.sitzplatz.z) > .1).length;
 const belegt = new Set();
 const doppelt = sitzend.filter(n => {
  const k = n.sitzplatz.x.toFixed(1) + '|' + n.sitzplatz.z.toFixed(1);
  if (belegt.has(k)) return true; belegt.add(k); return false;
 }).length;
 const vor = sitzend.map(n => ({id: n.id, x: n.x, z: n.z}));
 for (let i = 0; i < 300; i++) s.tick(1 / 60, leer);
 const gewandert = sitzend.filter(n => {
  const a = vor.find(v => v.id === n.id);
  return a && Math.hypot(n.x - a.x, n.z - a.z) > .05;
 }).length;
 // Wer sitzt, muss aufstehen, wenn jemand mit gezogener Waffe danebensteht.
 let aufgestanden = null;
 const opfer = sitzend[0];
 if (opfer) {
  const merk = {x: s.player.x, z: s.player.z, armed: s.player.armed, car: s.player.car};
  s.player.car = null; s.player.x = opfer.x + 2; s.player.z = opfer.z; s.player.armed = true;
  for (let i = 0; i < 240; i++) s.tick(1 / 60, leer);
  aufgestanden = opfer.state !== 'sitzend';
  s.player.x = merk.x; s.player.z = merk.z; s.player.armed = merk.armed; s.player.car = merk.car;
  s.stars = 0; s.heat = 0;
 }
 return {plaetze: plaetze.length, arten, sitzende: sitzend.length, daneben, doppelt,
  gewandert, aufgestanden};
});
pruefe('Auf Bänken, Liegen und Hockern sitzt jemand',
 moebel.plaetze >= 100 && moebel.sitzende >= 25,
 `${moebel.sitzende} Sitzende auf ${moebel.plaetze} Plätzen (${Object.entries(moebel.arten).map(([k, v]) => k + ' ' + v).join(', ')})`);
pruefe('Niemand sitzt neben dem Möbel oder auf jemandem',
 moebel.daneben === 0 && moebel.doppelt === 0,
 `${moebel.daneben} daneben, ${moebel.doppelt} doppelt belegt`);
pruefe('Wer sitzt, bleibt sitzen', moebel.gewandert === 0,
 `${moebel.gewandert} von ${moebel.sitzende} sind weggelaufen`);
pruefe('Wer sitzt, steht bei gezogener Waffe auf', moebel.aufgestanden === true,
 String(moebel.aufgestanden));

// Straßensperren. Die Stellen waren vier von Hand notierte Punkte, alle in
// der alten Innenstadt, und nur ein einziger Wagen (id === 2) bekam je einen
// Auftrag. Nachgemessen lag das Ziel in Rosalind 654 Meter entfernt, auf den
// Keys 386 — der Wagen fuhr quer über die Karte, während die Verfolgung
// woanders lief.
const sperren = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, q = s.player;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const orte = {Innenstadt: [-100, 20], Rosalind: [-880, 340], Keys: [230, 400], Flugfeld: [-360, 300]};
 const aus = {};
 const merk = {x: q.x, z: q.z, health: q.health, car: q.car};
 for (const [name, [x, z]] of Object.entries(orte)) {
  for (const b of s.barriers) s.solids = s.solids.filter(v => v !== b);
  s.barriers = [];
  for (const c of s.cops) {c.blockTarget = null; c.blocking = false; c.active = true;
   c.repath = 0; c.health = 100; c.stun = 0; c.x = x + 20; c.z = z;}
  q.x = x; q.z = z; q.y = 0; q.car = null; q.yaw = 0;
  // Fahndung, Gesundheit und Pause festhalten: ein wehrlos stehender Spieler
  // wird sonst nach einer Sekunde festgenommen, sim.paused wird gesetzt und
  // die ganze Simulation steht — das sieht aus, als bliebe die Streife stecken.
  let sperrenMax = 0;
  for (let i = 0; i < 1500; i++) {
   s.stars = 4; s.heat = 90; s.lastSeen = {x, z}; s.description = {clothes: q.clothes};
   q.health = 100; s.paused = false;
   s.tick(1 / 60, leer);
   q.health = 100; s.paused = false;
   sperrenMax = Math.max(sperrenMax, s.barriers.length);
  }
  const auftraege = s.cops.filter(c => c.blockTarget).length;
  const ziel = s.cops.find(c => c.blockTarget)?.blockTarget;
  aus[name] = {auftraege, sperrenMax,
   abstand: ziel ? Math.hypot(ziel.x - x, ziel.z - z) : null};
 }
 for (const b of s.barriers) s.solids = s.solids.filter(v => v !== b);
 s.barriers = [];
 for (const c of s.cops) {c.blockTarget = null; c.blocking = false;}
 s.stars = 0; s.heat = 0; s.lastSeen = null; s.description = null;
 q.x = merk.x; q.z = merk.z; q.health = merk.health; q.car = merk.car;
 return aus;
});
const orteListe = Object.entries(sperren);
pruefe('Straßensperren stehen dort, wo die Verfolgung ist',
 orteListe.every(([, v]) => v.abstand !== null && v.abstand <= 220),
 orteListe.map(([k, v]) => `${k} ${v.abstand === null ? '—' : Math.round(v.abstand) + ' m'}`).join(', '));
pruefe('Mehr als eine Streife kann sperren',
 orteListe.every(([, v]) => v.auftraege >= 2),
 orteListe.map(([k, v]) => `${k} ${v.auftraege}`).join(', '));
pruefe('Die Sperren werden auch wirklich aufgebaut',
 orteListe.every(([, v]) => v.sperrenMax >= 1),
 orteListe.map(([k, v]) => `${k} ${v.sperrenMax}`).join(', '));
pruefe('Nahkampf richtet Schaden an', verben.nahkampf > 0, `${verben.nahkampf} Schaden`);
pruefe('Der Griff betäubt', verben.griffStun > 1, `${verben.griffStun} s`);
pruefe('Deckung greift an einer Wand und nicht im Freien',
 verben.deckungAnDerWand === true && verben.deckungImFreien === false,
 `an der Wand ${verben.deckungAnDerWand}, im Freien ${verben.deckungImFreien}`);
pruefe('Ausweichen kostet Ausdauer und bringt Strecke',
 verben.ausweichenStrecke > 1 && verben.ausweichenAusdauer > 0,
 `${verben.ausweichenStrecke.toFixed(2)} m für ${verben.ausweichenAusdauer} Ausdauer`);
pruefe('Der Sprung hebt ab', verben.sprungVy > 1, `vy ${verben.sprungVy.toFixed(2)}`);
pruefe('Mit vollem Inventar schaltet die Waffe durch',
 new Set(verben.durchschalten).size >= 4 && verben.durchschalten[4] === verben.durchschalten[0],
 verben.durchschalten.join(' → '));
pruefe('Nachladen braucht Zeit und füllt danach auf',
 verben.sofortNachRuf.ammo === 3 && verben.sofortNachRuf.auftrag &&
 verben.nachWartezeit.ammo === 12 && verben.nachWartezeit.reserve === 31,
 `sofort ${verben.sofortNachRuf.ammo}, nach 200 Ticks ${verben.nachWartezeit.ammo} bei Reserve ${verben.nachWartezeit.reserve}`);

pruefe('Tagsüber ist die Stadt woanders als nachts',
 tageslauf.tag.naeherAmBuero > tageslauf.tag.von * .5 &&
 tageslauf.nacht.naeherAmBuero < tageslauf.tag.naeherAmBuero * .4,
 `am Arbeitsplatz: ${tageslauf.tag.naeherAmBuero} um 9 Uhr, ${tageslauf.nacht.naeherAmBuero} um 22 Uhr, von ${tageslauf.tag.von}`);

// Fahrbahnmarkierung. Fünfzehneinhalb Kilometer Fahrbahn trugen genau eine:
// den gestrichelten Mittelstreifen alle sechzehn Meter. Keine Randlinie, kein
// Fußgängerüberweg. Geprüft wird an den Instanzmatrizen der gebauten Welt,
// nicht an der Absicht im Quelltext.
const marken = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, U = L.ueberwege, onRoad = L.onRoad, s = L.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const treffer = [];
 for (const netz of w.bloecke || []) {
  if (netz.material?.color?.getHexString() !== 'c4bb97') continue;
  const m = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16;
   treffer.push({x: m[o + 12], z: m[o + 14],
    sx: Math.hypot(m[o], m[o + 1], m[o + 2]), sz: Math.hypot(m[o + 8], m[o + 9], m[o + 10])});
  }
 }
 // Randlinie und Strich sind schmal, der Überwegstreifen ist 72 cm breit.
 const art = t => {
  const a = Math.min(t.sx, t.sz), b = Math.max(t.sx, t.sz);
  return a > .5 ? 'überweg' : b < 6 ? 'strich' : 'randlinie';
 };
 const arten = {}, danebenArt = {};
 for (const t of treffer) {
  const k = art(t);
  arten[k] = (arten[k] || 0) + 1;
  if (!onRoad(t.x, t.z, 0)) danebenArt[k] = (danebenArt[k] || 0) + 1;
 }
 // Liegen die Enden jedes Überwegs auf der Fahrbahn, und liegt keiner in der
 // Kreuzungsfläche?
 let endenDaneben = 0, zuNah = 0;
 for (const u of U) {
  const h = u.breite / 2 - .9;
  for (const e of [-h, h]) {
   const x = u.x + (u.nordSued ? e : 0), z = u.z + (u.nordSued ? 0 : e);
   if (!onRoad(x, z, 0)) endenDaneben++;
  }
 }
 for (const k of L.kreuzungen || []) {
  for (const u of U) {
   const d = Math.hypot(u.x - k.x, u.z - k.z);
   if (d < k.breite / 2 + 2 && d > 0) zuNah++;
  }
 }
 // Wo betreten Fußgänger die Fahrbahn — am Überweg oder irgendwo?
 const quer = (x, z) => {
  let b = 1e9;
  for (const u of U) {
   const laengs = u.nordSued ? Math.abs(x - u.x) : Math.abs(z - u.z);
   if (laengs > u.breite / 2 + 1) continue;
   const d = u.nordSued ? Math.abs(z - u.z) : Math.abs(x - u.x);
   if (d < b) b = d;
  }
  return b;
 };
 // Die Welt hat an dieser Stelle zweihundert Prüfungen hinter sich: Sturm,
 // Fahndungsstufen, versetzte Spieler. Fahndung und Wetter werden deshalb
 // zurückgesetzt, sonst misst die Prüfung die Panik statt der Wegeführung.
 s.stars = 0; s.heat = 0; s.weather = 'clear';
 // Fünfzehn Sekunden Einlauf: wer vor dem Spieler geflohen ist, steht
 // irgendwo neben seinem Weg und quert auf dem Rückweg, wo er gerade steht.
 for (let i = 0; i < 900; i++) s.tick(1 / 60, leer);
 const war = new Map(), abstaende = [];
 // 2400 statt 900 Takte: mit siebzig gezählten Betretungen schwankte der
 // Anteil zwischen zwei Läufen um zehn Prozentpunkte, ohne dass sich am
 // Spiel etwas geändert hätte.
 for (let t = 0; t < 2400; t++) {
  s.tick(1 / 60, leer);
  for (const n of (s._alleNpcs || s.npcs)) {
   // Nur, wer einem Weg folgt. Wer flieht, rennt geradeaus vom Spieler weg
   // und quert dabei, wo er gerade steht — das ist richtig so und hat mit
   // den Überwegen nichts zu tun.
   if (n.health <= 0 || n.state !== 'normal') continue;
   const drauf = onRoad(n.x, n.z, 0), vor = war.get(n.id);
   if (drauf && vor === false) abstaende.push(quer(n.x, n.z));
   war.set(n.id, drauf);
  }
 }
 abstaende.sort((a, b) => a - b);
 return {arten, danebenArt, ueberwege: U.length, endenDaneben, zuNah,
  betretungen: abstaende.length,
  amUeberweg: abstaende.filter(d => d < 3).length,
  median: abstaende.length ? abstaende[Math.floor(abstaende.length / 2)] : null};
});
// Der Damm unter der Fahrbahn war eine halbe Meter dicke Platte. Die Decke
// ist quer waagerecht; auf einem Querhang liegt der Fahrbahnrand deshalb bis
// zu 4,12 Meter über dem Gelände, und die Platte schwebte mit.
const damm = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world;
 let anzahl = 0, schwebend = 0, groessterSpalt = 0, wo = null;
 for (const netz of w.bloecke || []) {
  if (netz.material?.color?.getHexString() !== '5c6350') continue;
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, x = a[o + 12], y = a[o + 13], z = a[o + 14];
   const sx = Math.hypot(a[o], a[o + 1], a[o + 2]);
   const sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   const sz = Math.hypot(a[o + 8], a[o + 9], a[o + 10]);
   anzahl++;
   const unten = y - sy / 2;
   // Nur quer zur Fahrbahn abtasten. Längs folgt der Damm der Neigung der
   // Decke und ist dort gekippt; die Mitte, die hier gemessen wird, läge
   // gegen den tiefsten Punkt der Längsrichtung immer im Rückstand.
   // Querachse ist die längere der beiden: der Damm ist Fahrbahnbreite plus
   // neun Meter breit und zwölf Meter lang.
   const quer = sx > sz ? [[sx / 2 - .5, 0], [-(sx / 2 - .5), 0]] : [[0, sz / 2 - .5], [0, -(sz / 2 - .5)]];
   let tief = 1e9;
   for (const [dx, dz] of quer) tief = Math.min(tief, L.groundAt(x + dx, z + dz));
   const spalt = unten - tief;
   if (spalt > groessterSpalt) {groessterSpalt = spalt; wo = [Math.round(x), Math.round(z)];}
   if (spalt > .5) schwebend++;
  }
 }
 return {anzahl, schwebend, groessterSpalt, wo};
});
pruefe('Der Damm unter der Fahrbahn reicht bis auf das Gelände',
 damm.anzahl > 50 && damm.schwebend === 0,
 `${damm.schwebend} von ${damm.anzahl} schweben, größter Spalt ${damm.groessterSpalt.toFixed(2)} m${damm.wo ? ' bei [' + damm.wo + ']' : ''}`);
pruefe('Jede Fahrbahn hat Randlinien',
 marken.arten.randlinie >= 2000 && !marken.danebenArt.randlinie,
 `${marken.arten.randlinie} Randlinien, ${marken.danebenArt.randlinie || 0} neben der Fahrbahn`);
pruefe('An den Kreuzungen liegen Fußgängerüberwege',
 marken.ueberwege >= 200 && marken.arten.überweg >= 2000 && !marken.danebenArt.überweg,
 `${marken.ueberwege} Überwege mit ${marken.arten.überweg} Streifen, ${marken.danebenArt.überweg || 0} neben der Fahrbahn`);
pruefe('Kein Überweg endet neben der Fahrbahn oder liegt in der Kreuzung',
 marken.endenDaneben === 0 && marken.zuNah === 0,
 `${marken.endenDaneben} Enden daneben, ${marken.zuNah} in der Kreuzungsfläche`);
pruefe('Fußgänger betreten die Fahrbahn dort, wo die Überwege liegen',
 marken.betretungen >= 30 && marken.amUeberweg / marken.betretungen > .55,
 `${marken.amUeberweg} von ${marken.betretungen} unter drei Metern, Median ${marken.median?.toFixed(1)} m`);
// Die Schwelle steht bei fünfundfünfzig und nicht bei achtzig Prozent, weil
// der Wert vom Zustand der Welt abhängt: in einer frisch gestarteten Karte
// sind es zu drei Tageszeiten 80, 80 und 82 Prozent, am Ende dieses Prüflaufs
// mit seinen Fahndungen, Stürmen und versetzten Figuren rund 60. Vor der
// Wegeführung über die Überwege waren es 77, 56, 62 und 43. Die Prüfung fängt
// den Rückfall, nicht die Schwankung.

// Kulisse auf der Fahrbahn. Die Prüfung „Nichts Großes steht in einer
// Fahrbahn" fängt nur, was mindestens drei Meter breit und zweieinhalb hoch
// ist. Darunter standen 268 Gegenstände mitten auf einer Fahrspur:
// Pflanzkübel aus einer Schleife mit festen Koordinaten aus der alten, halb
// so großen Karte, Papierkörbe und Parkuhren aus street.js, Zaunpfähle aus
// regions.js — und Baumstämme von fünf Metern Höhe.
const kulisse = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world;
 const treffer = [];
 for (const netz of w.bloecke || []) {
  const a = netz.instanceMatrix.array;
  for (let i = 0; i < netz.count; i++) {
   const o = i * 16, x = a[o + 12], y = a[o + 13], z = a[o + 14];
   const sx = Math.hypot(a[o], a[o + 1], a[o + 2]);
   const sy = Math.hypot(a[o + 4], a[o + 5], a[o + 6]);
   const sz = Math.hypot(a[o + 8], a[o + 9], a[o + 10]);
   // Schmal genug, um Kulisse zu sein, und mit dem Fuß im Fahrbahnbereich.
   if (Math.max(sx, sz) > 2.6) continue;
   if (y - sy / 2 > L.groundAt(x, z) + 2.2) continue;   // hängt darüber
   if (y + sy / 2 < L.groundAt(x, z) + .35) continue;   // liegt flach
   if (!L.onRoad(x, z, 0)) continue;
   treffer.push(`[${Math.round(x)},${Math.round(z)}] ${sx.toFixed(1)}×${sy.toFixed(1)}×${sz.toFixed(1)}`);
  }
 }
 return {rest: treffer.length, verworfen: w.verworfen || 0, beispiele: treffer.slice(0, 5)};
});
pruefe('Keine Kulisse steht in einer Fahrbahn', kulisse.rest === 0,
 `${kulisse.rest} übrig, ${kulisse.verworfen} beim Zusammenbau verworfen${kulisse.beispiele.length ? ': ' + kulisse.beispiele.join('; ') : ''}`);
pruefe('Und die Straße selbst steht noch da', kulisse.verworfen > 200 && kulisse.verworfen < 900,
 `${kulisse.verworfen} verworfen`);

// Gangart. Im Schrittzyklus stand jede Zahl als Konstante — Ausschlag der
// Beine .46, des Knies .72, der Arme .30, Auf- und Abbewegung .045. Bei
// gleichem Tempo lief damit jede Figur exakt gleich, und das Tempo selbst
// kannte nur fünf Werte. Gemessen am alten Stand, alle Figuren über dieselbe
// Strecke geführt: **ein** Beinausschlag, **eine** Auf- und Abbewegung, und
// die Armwerte streuten über 1,7 Prozent, also Rauschen der Abtastung.
const gangart = await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 const daten = [];
 for (let i = 0; i < w.npcs.length && daten.length < 40; i += 11) {
  const m = w.npcs[i], u = m?.userData;
  if (!u?.legs || !u.arms) continue;
  const merk = {x: m.position.x, strecke: u.strecke, zeit: u.letzteZeit};
  u.strecke = 0; u.letzteZeit = undefined; u.letzteX = undefined; u.letzteZ = undefined;
  let armMin = 9, armMax = -9, beinMin = 9, beinMax = -9, bobMax = 0;
  // Gleiche Strecke, gleiche Zeit für alle: was übrig bleibt, ist die Gangart.
  for (let k = 0; k < 160; k++) {
   m.position.x += .025;
   w.animateHuman(m, k * .0166, 1, false);
   const a = u.arms[0].rotation.x, b = u.legs[0].rotation.x;
   if (a < armMin) armMin = a; if (a > armMax) armMax = a;
   if (b < beinMin) beinMin = b; if (b > beinMax) beinMax = b;
   if ((u.bob || 0) > bobMax) bobMax = u.bob;
  }
  daten.push({arm: armMax - armMin, bein: beinMax - beinMin, bob: bobMax});
  m.position.x = merk.x; u.strecke = merk.strecke; u.letzteZeit = merk.zeit;
 }
 const verschieden = f => new Set(daten.map(d => d[f].toFixed(4))).size;
 const spanne = f => {
  const v = daten.map(d => d[f]);
  return Math.max(...v) / Math.max(1e-6, Math.min(...v));
 };
 return {figuren: daten.length, beinVerschieden: verschieden('bein'), bobVerschieden: verschieden('bob'),
  armSpanne: spanne('arm'), beinSpanne: spanne('bein')};
});
pruefe('Nicht jeder Mensch geht gleich',
 gangart.beinVerschieden > 20 && gangart.armSpanne > 1.3 && gangart.bobVerschieden > 10,
 `${gangart.beinVerschieden} Beinausschläge und ${gangart.bobVerschieden} Wiegebewegungen unter ${gangart.figuren} Figuren, Armausschlag Faktor ${gangart.armSpanne.toFixed(2)} (vorher 1 Beinausschlag, 1 Wiegebewegung, Arm Faktor 1,02)`);

// Körperbau. Die Körpergröße skaliert die ganze Figur gleichmäßig — damit war
// jedes Verhältnis für alle 530 Menschen dasselbe: Schulterabstand geteilt
// durch Größe lag bei jedem auf 0,249. Und beim Nachmessen kam heraus, dass
// Arme und Beine in der Kopfgruppe hingen: `slice(kopfAb)` nahm alles, was
// nach der Kopfmarke gebaut wird. Im Stand sah das richtig aus, weil die
// Höhenverschiebung die Weltlage erhält — sobald der Kopf sich drehte,
// drehten Arme und Beine mit.
const koerperbau = await page.evaluate(() => {
 const w = window.LOWTIDE.world;
 const werte = [], baue = [];
 for (let i = 0; i < w.npcs.length; i += 5) {
  const m = w.npcs[i], u = m?.userData;
  if (!u?.arms || !u.legs) continue;
  baue.push(u.bau ?? 0);
  // Schulterabstand im Eigensystem, geteilt durch die Körpergröße. Beides
  // ohne die Größenskalierung, also ein reines Verhältnis.
  werte.push(Math.abs(u.arms[1].position.x - u.arms[0].position.x) / 1.886);
 }
 // Dreht sich mit dem Kopf noch der Fuß mit?
 const m = w.npcs[0], u = m.userData;
 const merk = {x: m.position.x, y: m.position.y, z: m.position.z, ry: m.rotation.y, k: u.kopf.rotation.y};
 m.position.set(0, 0, 0); m.rotation.set(0, 0, 0);
 u.kopf.rotation.y = 0; m.updateMatrixWorld(true);
 const a = u.ankles[0].matrixWorld.elements;
 const vor = {x: a[12], z: a[14]};
 u.kopf.rotation.y = 1.2; m.updateMatrixWorld(true);
 const b = u.ankles[0].matrixWorld.elements;
 const versatz = Math.hypot(b[12] - vor.x, b[14] - vor.z);
 const drin = o => {let k = o; while (k) {if (k === u.kopf) return true; k = k.parent;} return false;};
 const beinImKopf = drin(u.legs[0]), armImKopf = drin(u.arms[0]);
 u.kopf.rotation.y = merk.k; m.position.set(merk.x, merk.y, merk.z); m.rotation.y = merk.ry;
 m.updateMatrixWorld(true);
 return {
  anzahl: werte.length,
  verschieden: new Set(werte.map(v => v.toFixed(3))).size,
  min: Math.min(...werte), max: Math.max(...werte),
  bauMin: Math.min(...baue), bauMax: Math.max(...baue),
  versatz, beinImKopf, armImKopf
 };
});
pruefe('Nicht jeder Mensch hat dieselben Proportionen',
 koerperbau.verschieden > 20 && koerperbau.max - koerperbau.min > .02,
 `${koerperbau.verschieden} Schulterbreiten unter ${koerperbau.anzahl} Figuren, ${koerperbau.min.toFixed(3)}–${koerperbau.max.toFixed(3)} der Körpergröße (vorher 0,249 bei allen)`);
pruefe('Die Kopfgruppe enthält nur den Kopf',
 !koerperbau.beinImKopf && !koerperbau.armImKopf && koerperbau.versatz < .001,
 `Bein im Kopf ${koerperbau.beinImKopf}, Arm im Kopf ${koerperbau.armImKopf}, Knöchelversatz bei 1,2 rad Kopfdrehung ${koerperbau.versatz.toFixed(3)} m`);

// Körpergröße und Sitzhöhe. Beide Werte wurden an den Meshes gemessen, nicht
// an der Simulation: die Sitzprüfungen weiter oben fragen nur den Zustand ab
// und hätten deshalb nicht gemerkt, dass die abgeleitete Klasse die Sitzhöhe
// wieder mit `groundAt` überschreibt. Jede Figur saß in Wahrheit auf dem
// Boden vor der Bank, mit waagerechten Oberschenkeln in der Luft.
const koerper = await page.evaluate(async () => {
 const L = window.LOWTIDE, s = L.sim, w = L.world;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 // Modellhöhe von der Sohle bis zur Haarspitze, aus den Geometrien gerechnet.
 const spanne = m => {
  m.updateMatrixWorld(true);
  let min = 1e9, max = -1e9;
  m.traverse(o => {
   if (!o.isMesh || !o.geometry) return;
   if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
   const bb = o.geometry.boundingBox, e = o.matrixWorld.elements;
   for (const y of [bb.min.y, bb.max.y]) for (const x of [bb.min.x, bb.max.x]) for (const z of [bb.min.z, bb.max.z]) {
    const wy = e[1] * x + e[5] * y + e[9] * z + e[13];
    if (wy < min) min = wy; if (wy > max) max = wy;
   }
  });
  return {unten: min, oben: max};
 };
 const groessen = w.npcs.map(m => (m.userData.groesse || 1) * 1.886).sort((a, b) => a - b);
 const mittel = groessen.reduce((a, b) => a + b, 0) / groessen.length;
 const aus = {
  anzahl: groessen.length,
  verschieden: new Set(groessen.map(g => g.toFixed(3))).size,
  kleinste: groessen[0], groesste: groessen[groessen.length - 1], mittel,
  spieler: null, sitz: null, hocker: null
 };
 // Der Spieler hängt an der aktiven Figur: Eli 1,80 m, Mara 1,68 m.
 aus.spieler = (w.player.scale.y * 1.886);
 const treffer = s.npcs.map((n, i) => ({n, i})).find(o => o.n.state === 'sitzend' && o.n.sitzplatz);
 if (treffer) {
  const n = treffer.n, m = w.npcs[treffer.i];
  // Ohne das Entwaffnen misst diese Prüfung eine stehende Figur: die
  // Waffentests weiter oben lassen den Spieler bewaffnet zurück, und wer
  // sitzt, steht auf, sobald jemand mit gezogener Waffe danebensteht.
  const merk = {x: s.player.x, z: s.player.z, car: s.player.car, armed: s.player.armed};
  s.player.car = null; s.player.armed = false; s.player.x = n.x + 3; s.player.z = n.z + 3;
  for (let i = 0; i < 6; i++) s.tick(1 / 60, leer);
  const f0 = L.frames;
  await new Promise(r => {const p = () => {L.frames > f0 + 1 ? r() : requestAnimationFrame(p);}; p();});
  const boden = L.groundAt(n.x, n.z), g = m.userData.groesse || 1;
  let sp = spanne(m);
  aus.sitz = {art: n.sitzplatz.art || 'bank', sichtbar: m.visible, zustand: n.state,
   sitzflaeche: boden + n.sitzplatz.y, becken: m.position.y + .86 * g,
   sohle: sp.unten, boden, kopf: sp.oben};
  // Derselbe Platz auf Hockerhöhe: dort dürfen die Beine baumeln.
  const echt = n.sitzplatz;
  n.sitzplatz = {...echt, y: 1};
  const f1 = L.frames;
  await new Promise(r => {const p = () => {L.frames > f1 + 1 ? r() : requestAnimationFrame(p);}; p();});
  sp = spanne(m);
  aus.hocker = {becken: m.position.y + .86 * g, sohle: sp.unten, boden};
  n.sitzplatz = echt;
  s.player.x = merk.x; s.player.z = merk.z; s.player.car = merk.car; s.player.armed = merk.armed;
 }
 return aus;
});
pruefe('Nicht jede Figur ist gleich groß',
 koerper.verschieden > 100 && koerper.kleinste > 1.45 && koerper.groesste < 1.99,
 `${koerper.verschieden} Größen unter ${koerper.anzahl} Figuren, ${koerper.kleinste.toFixed(2)}–${koerper.groesste.toFixed(2)} m`);
pruefe('Die Menge ist im Mittel normal groß',
 Math.abs(koerper.mittel - 1.72) < .04, `${koerper.mittel.toFixed(3)} m`);
pruefe('Der Spieler ist so groß wie die aktive Figur',
 Math.abs(koerper.spieler - 1.80) < .01, `${koerper.spieler.toFixed(2)} m`);
pruefe('Das Becken liegt auf der Sitzfläche',
 !!koerper.sitz && Math.abs(koerper.sitz.becken - koerper.sitz.sitzflaeche) < .02,
 koerper.sitz && `Becken ${koerper.sitz.becken.toFixed(3)}, Sitzfläche ${koerper.sitz.sitzflaeche.toFixed(3)} (${koerper.sitz.art}, ${koerper.sitz.zustand})`);
pruefe('Auf Bankhöhe stehen die Füße auf dem Boden',
 !!koerper.sitz && koerper.sitz.sohle - koerper.sitz.boden > -.05 && koerper.sitz.sohle - koerper.sitz.boden < .09,
 koerper.sitz && `Sohle ${(koerper.sitz.sohle - koerper.sitz.boden).toFixed(3)} über dem Boden`);
pruefe('Auf Hockerhöhe baumeln die Beine',
 !!koerper.hocker && koerper.hocker.sohle - koerper.hocker.boden > .3 &&
 Math.abs(koerper.hocker.becken - koerper.hocker.boden - 1) < .02,
 koerper.hocker && `Becken ${(koerper.hocker.becken - koerper.hocker.boden).toFixed(3)}, Sohle ${(koerper.hocker.sohle - koerper.hocker.boden).toFixed(3)}`);

// Verkehrsmischung. Der fahrende Verkehr bestand aus fünf Modellen, und vier
// davon — 112 von 127 Wagen — tragen dieselbe Karosserieform in anderer
// Größe. Bus, Lastwagen und Motorrad kamen auf der Straße nicht vor, obwohl
// alle drei als Typ und als Mesh vorhanden sind.
const mischung = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim, V = L.fahrzeuge, onRoad = L.onRoad;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 // Die vier Ecken im Eigensystem des Fahrzeugs.
 const ecken = c => {
  const t = V[c.model] || {}, l = (t.laenge || 4.5) / 2, b = (t.breite || 2.2) / 2;
  const sin = Math.sin(c.yaw), cos = Math.cos(c.yaw), aus = [];
  for (const dl of [-l, l]) for (const db of [-b, b])
   aus.push({x: c.x + sin * dl + cos * db, z: c.z + cos * dl - sin * db});
  return aus;
 };
 // Rechteck gegen Rechteck über die Trennachsen: vier Achsen genügen.
 // Zurück kommt die Eindringtiefe in Metern, null wenn sie sich nicht
 // berühren.
 const ueberlappt = (a, b) => {
  const ta = V[a.model] || {}, tb = V[b.model] || {};
  const la = (ta.laenge || 4.5) / 2, ba = (ta.breite || 2.2) / 2;
  const lb = (tb.laenge || 4.5) / 2, bb = (tb.breite || 2.2) / 2;
  const dx = b.x - a.x, dz = b.z - a.z;
  const achsen = [
   [Math.sin(a.yaw), Math.cos(a.yaw)], [Math.cos(a.yaw), -Math.sin(a.yaw)],
   [Math.sin(b.yaw), Math.cos(b.yaw)], [Math.cos(b.yaw), -Math.sin(b.yaw)]];
  let tief = Infinity;
  for (const [ux, uz] of achsen) {
   const d = Math.abs(dx * ux + dz * uz);
   const ra = la * Math.abs(Math.sin(a.yaw) * ux + Math.cos(a.yaw) * uz) +
              ba * Math.abs(Math.cos(a.yaw) * ux - Math.sin(a.yaw) * uz);
   const rb = lb * Math.abs(Math.sin(b.yaw) * ux + Math.cos(b.yaw) * uz) +
              bb * Math.abs(Math.cos(b.yaw) * ux - Math.sin(b.yaw) * uz);
   if (d > ra + rb) return 0;
   tief = Math.min(tief, ra + rb - d);
  }
  return tief;
 };
 const modelle = {}, abseits = {}, funde = [];
 let paare = 0, tiefste = 0;
 for (let i = 0; i < 900; i++) {
  s.tick(1 / 60, leer);
  if (i % 150) continue;
  const fahrend = s.cars.filter(c => c.type === 'traffic' && c.health > 0);
  for (const c of fahrend) {
   if (i === 0) modelle[c.model] = (modelle[c.model] || 0) + 1;
   // Wie weit ragt die äußerste Ecke über den Fahrbahnrand? Über wachsende
   // Ränder gesucht, weil onRoad nur ja oder nein sagt.
   let ueber = 0;
   for (const e of ecken(c)) {
    let r = 0;
    while (r <= 4 && !onRoad(e.x, e.z, r)) r += .25;
    if (r > ueber) ueber = r;
   }
   if (ueber > 0) abseits[c.model] = Math.max(abseits[c.model] || 0, ueber);
  }
  for (let a = 0; a < s.cars.length; a++) for (let b = a + 1; b < s.cars.length; b++) {
   const A = s.cars[a], B = s.cars[b];
   if (A.health <= 0 || B.health <= 0 || A === s.player.car || B === s.player.car) continue;
   if (Math.abs(A.x - B.x) + Math.abs(A.z - B.z) > 14) continue;
   const tief = ueberlappt(A, B);
   if (tief <= 0) continue;
   if (tief > tiefste) tiefste = tief;
   // Berührungen unter zwanzig Zentimetern an einem stehenden Ende einer
   // Schlange sind Streifen, kein Durchfahren: gemessen über fünf Minuten
   // drei Fälle mit höchstens 0,13 Metern, alle an Wagen, die warten, weil
   // der Spieler in der Spur steht.
   if (tief <= .2) continue;
   paare++;
   if (funde.length < 6) funde.push(`${A.model}/${A.type}${A.route ? '' : ' ohne Route'} auf ${B.model}/${B.type}${B.route ? '' : ' ohne Route'} bei [${Math.round(A.x)},${Math.round(A.z)}]`);
  }
 }
 const runde = c => {
  if (!c.route) return null;
  let l = 0;
  for (let i = 0; i < c.route.length; i++) {
   const a = c.route[i], b = c.route[(i + 1) % c.route.length];
   l += Math.hypot(b.x - a.x, b.z - a.z);
  }
  return l;
 };
 const kuerzeste = m => {
  const werte = s.cars.filter(c => c.model === m && c.type === 'traffic').map(runde).filter(Boolean);
  return werte.length ? Math.min(...werte) : null;
 };
 return {modelle, abseits, paare, formen: new Set(Object.keys(modelle).map(m => V[m]?.shape)).size,
  busRunde: kuerzeste('bus'), lkwRunde: kuerzeste('truck'), funde, tiefste};
});
pruefe('Auf der Straße fahren auch Busse, Lastwagen und Motorräder',
 (mischung.modelle.bus || 0) >= 4 && (mischung.modelle.truck || 0) >= 4 && (mischung.modelle.motorcycle || 0) >= 4,
 Object.entries(mischung.modelle).map(([k, v]) => k + ' ' + v).join(', '));
pruefe('Der Verkehr zeigt mehr als zwei Karosserieformen', mischung.formen >= 5,
 `${mischung.formen} Formen`);
pruefe('Busse und Lastwagen fahren nur auf langen Runden',
 (mischung.busRunde ?? 0) >= 800 && (mischung.lkwRunde ?? 0) >= 900,
 `kürzeste Busrunde ${Math.round(mischung.busRunde)} m, kürzeste Lastwagenrunde ${Math.round(mischung.lkwRunde)} m`);
// Kurze Fahrzeuge dürfen die Fahrbahn nie verlassen. Bus und Lastwagen
// schwenken an den Ecken aus: der Verkehr hat keinen Wendekreis, die
// Fahrtrichtung springt am Wegpunkt um neunzig Grad, und ein Achtmeterbus
// steht dabei kurz schräg. Gemessen über 150 Sekunden: Lastwagen höchstens
// 0,25 Meter über dem Rand, Bus 0,75. Alles darüber wäre neu.
// Seit der Verkehr gelenkt wird statt sich am Wegpunkt zu drehen, verlässt
// kein Fahrzeug mehr die Fahrbahn — auch der Achtmeterbus nicht, der vorher
// 0,75 Meter über den Bordstein schwenkte.
pruefe('Kein Fahrzeug verlässt die Fahrbahn', Object.keys(mischung.abseits).length === 0,
 JSON.stringify(mischung.abseits));
pruefe('Fahrzeuge fahren nicht ineinander', mischung.paare === 0,
 `${mischung.paare} Paare über 0,2 m, tiefste Berührung ${mischung.tiefste.toFixed(2)} m: ${mischung.funde.join('; ')}`);

// Gelenkt statt gedreht. Am Wegpunkt sprang die Fahrtrichtung in einem
// einzigen Takt um bis zu 102 Grad: gemessen 508 Sprünge in neunzig
// Sekunden, jeder einzelne über 45 Grad.
const lenkung = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const f = s.cars.filter(c => c.type === 'traffic');
 const vor = new Map(f.map(c => [c.id, c.yaw]));
 const anfang = f.map(c => ({x: c.x, z: c.z}));
 let groesster = 0, ueber5 = 0, ueber45 = 0;
 // Der Grund fürs Stehen wird zehnmal abgefragt. Ein Wagen, der in einer
 // Schlange kriecht, hat bei jeder Abfrage einen Grund; ein Wagen, der
 // festhängt, bei keiner. Nur der zweite Fall ist ein Fehler — ein Wagen an
 // einer roten Ampel oder hinter einem Stau steht zu Recht.
 const grundFrei = new Map(f.map(c => [c.id, 0]));
 const grundVon = c => {
  const p = s.player;
  return c.health <= 0 ? 'zerstört'
   : c.wait > 0 ? 'Pannenzeit'
   : !p.car && s.spielerImWeg(c, p) ? 'Spieler im Weg'
   : s.haeltVorAmpel(c) ? 'Ampel'
   : s.fussgaengerVoraus(c) ? 'Fußgänger'
   : s.wagenVoraus(c) ? 'Wagen voraus'
   : null;
 };
 for (let i = 0; i < 2700; i++) {
  s.tick(1 / 60, leer);
  for (const c of f) {
   const d = Math.abs(((c.yaw - vor.get(c.id)) * 180 / Math.PI + 540) % 360 - 180);
   vor.set(c.id, c.yaw);
   if (d > groesster) groesster = d;
   if (d > 5) ueber5++;
   if (d > 45) ueber45++;
  }
  if (i % 270 === 0) for (const c of f) if (!grundVon(c)) grundFrei.set(c.id, grundFrei.get(c.id) + 1);
 }
 const weg = f.map((c, i) => Math.hypot(c.x - anfang[i].x, c.z - anfang[i].z));
 // Festgehangen heißt: keine drei Meter in fünfundvierzig Sekunden und bei
 // keiner der zehn Abfragen ein Grund.
 const fest = f.filter((c, i) => weg[i] < 3 && grundFrei.get(c.id) === 10)
  .map(c => `${c.model} [${Math.round(c.x)},${Math.round(c.z)}]`);
 return {groesster, ueber5, ueber45, stehend: weg.filter(w => w < 3).length,
  mittel: weg.reduce((a, b) => a + b, 0) / weg.length, wagen: f.length, fest};
});
pruefe('Der Verkehr dreht sich nicht auf der Stelle',
 lenkung.groesster < 6 && lenkung.ueber45 === 0,
 `größter Sprung ${lenkung.groesster.toFixed(1)}° je Takt, ${lenkung.ueber5} über 5°, ${lenkung.ueber45} über 45°`);
pruefe('Und bleibt dabei in Fahrt',
 lenkung.mittel > 60 && lenkung.fest.length === 0,
 `${lenkung.mittel.toFixed(0)} m in 45 Sekunden, ${lenkung.stehend} von ${lenkung.wagen} kaum bewegt, davon ohne jeden Grund ${lenkung.fest.length}${lenkung.fest.length ? ': ' + lenkung.fest.join('; ') : ''}`);

// Wer dem Verkehr im Weg steht, wird nicht überfahren — und wer daneben
// steht, hält ihn nicht an. Vorher hielt jeder Wagen an, sobald der Spieler
// irgendwo in fünf Metern stand, auch seitlich auf dem Gehweg.
const imWeg = await page.evaluate(() => {
 const L = window.LOWTIDE, s = L.sim;
 const leer = {forward: 0, turn: 0, yaw: 0, sprint: false, sneak: false, brake: false, jump: false, interact: false};
 const merk = {x: s.player.x, z: s.player.z, car: s.player.car, health: s.player.health};
 const ziel = s.cars.find(c => c.type === 'traffic' && c.route && c.route.length === 4);
 const q = ziel.route[0];
 s.player.car = null;
 const fahrend = s.cars.filter(c => c.type === 'traffic');
 const messe = (px, pz) => {
  const anfang = fahrend.map(c => ({c, x: c.x, z: c.z}));
  let naechster = 99;
  for (let i = 0; i < 1800; i++) {
   s.tick(1 / 60, leer);
   s.player.x = px; s.player.z = pz; s.player.health = 100;
   for (const c of fahrend) {
    if (c.health <= 0) continue;
    const d = Math.hypot(c.x - px, c.z - pz);
    if (d < naechster) naechster = d;
   }
  }
  return {naechster, gefahren: anfang.filter(e => Math.hypot(e.c.x - e.x, e.c.z - e.z) > 20).length};
 };
 const inDerSpur = messe(q.x, q.z);
 // Und derselbe Punkt zehn Meter zur Seite, quer zur Straße.
 const daneben = messe(q.x, q.z + 10);
 s.player.x = merk.x; s.player.z = merk.z; s.player.car = merk.car; s.player.health = merk.health;
 return {inDerSpur, daneben, wagen: fahrend.length};
});
pruefe('Kein Wagen fährt den Spieler um',
 imWeg.inDerSpur.naechster > 2.5,
 `nächster Wagen ${imWeg.inDerSpur.naechster.toFixed(2)} m`);
pruefe('Neben der Spur hält der Verkehr nicht an',
 imWeg.daneben.gefahren > imWeg.wagen * .8,
 `${imWeg.daneben.gefahren} von ${imWeg.wagen} sind weitergefahren, in der Spur ${imWeg.inDerSpur.gefahren}`);

// Vier Karosserien statt einer. Kleinwagen, Limousine, Geländewagen und
// Muscle Car waren derselbe Körper in anderem Maßstab. Sichtbar wird das an
// den Verhältnissen entlang der Längsachse, die eine Achsenskalierung gar
// nicht ändern kann: gemessen am alten Stand lagen Radstand (0,610 der
// Länge), vorderer Überhang (0,200), Fahrgastzelle (0,583) und ihre Mitte
// (0,460) bei allen vier auf drei Stellen gleich.
const karosserien = await page.evaluate(() => {
 const L = window.LOWTIDE, w = L.world, s = L.sim, V = L.fahrzeuge;
 const spanne = (o, achse) => {
  o.updateMatrixWorld(true);
  let min = 1e9, max = -1e9;
  o.traverse(k => {
   if (!k.isMesh || !k.geometry) return;
   if (!k.geometry.boundingBox) k.geometry.computeBoundingBox();
   const bb = k.geometry.boundingBox, e = k.matrixWorld.elements;
   for (const x of [bb.min.x, bb.max.x]) for (const y of [bb.min.y, bb.max.y]) for (const z of [bb.min.z, bb.max.z]) {
    const v = achse === 0 ? e[0] * x + e[4] * y + e[8] * z + e[12]
      : achse === 1 ? e[1] * x + e[5] * y + e[9] * z + e[13]
      : e[2] * x + e[6] * y + e[10] * z + e[14];
    if (v < min) min = v; if (v > max) max = v;
   }
  });
  return [min, max];
 };
 const aus = {}, abweichung = {};
 for (const modell of ['compact', 'sedan', 'suv', 'muscle']) {
  const i = s.cars.findIndex(c => c.model === modell);
  const m = w.cars[i];
  if (!m) continue;
  const merk = {x: m.position.x, y: m.position.y, z: m.position.z, r: m.rotation.y};
  m.position.set(0, 0, 0); m.rotation.y = 0; m.updateMatrixWorld(true);
  const z = spanne(m, 2), y = spanne(m, 1), x = spanne(m, 0);
  const laenge = z[1] - z[0];
  const raeder = (m.userData.wheels || []).map(k => {k.updateMatrixWorld(true); return k.matrixWorld.elements[14];});
  const kab = m.userData.glass ? spanne(m.userData.glass, 2) : [0, 0];
  const kabY = m.userData.glass ? spanne(m.userData.glass, 1) : [0, 0];
  aus[modell] = {
   laenge, breite: x[1] - x[0], hoehe: y[1] - y[0],
   radstand: (Math.max(...raeder) - Math.min(...raeder)) / laenge,
   ueberhang: (z[1] - Math.max(...raeder)) / laenge,
   kabine: (kab[1] - kab[0]) / laenge,
   kabineMitte: ((kab[0] + kab[1]) / 2 - z[0]) / laenge,
   dach: kabY[1] / laenge
  };
  m.position.set(merk.x, merk.y, merk.z); m.rotation.y = merk.r; m.updateMatrixWorld(true);
 }
 // Und stimmen die Zahlen in vehicleTypes noch? Der Abstand des Verkehrs
 // hängt an ihnen.
 for (const [modell, v] of Object.entries(aus)) {
  const t = V[modell] || {};
  abweichung[modell] = Math.max(Math.abs((t.laenge || 0) - v.laenge), Math.abs((t.breite || 0) - v.breite));
 }
 const spreizung = feld => {
  const werte = Object.values(aus).map(v => v[feld]);
  return Math.max(...werte) - Math.min(...werte);
 };
 return {aus, abweichung,
  radstand: spreizung('radstand'), ueberhang: spreizung('ueberhang'),
  kabine: spreizung('kabine'), kabineMitte: spreizung('kabineMitte'), dach: spreizung('dach')};
});
pruefe('Die vier Autotypen haben eigene Karosserien',
 karosserien.radstand > .04 && karosserien.kabine > .08 && karosserien.kabineMitte > .04,
 `Radstand ${karosserien.radstand.toFixed(3)}, Zelle ${karosserien.kabine.toFixed(3)}, Zellenmitte ${karosserien.kabineMitte.toFixed(3)}, Dach ${karosserien.dach.toFixed(3)}`);
pruefe('Die Maße in vehicleTypes stimmen mit den Meshes überein',
 Math.max(...Object.values(karosserien.abweichung)) < .15,
 Object.entries(karosserien.abweichung).map(([k, v]) => k + ' ' + v.toFixed(2)).join(', '));

// Flügelschlag. Im Update der Tierwelt stand `o.scale.set(schlag, 1, 1)` mit
// der Begründung, einzelne Flügel gingen bei Instanzen nicht: die ganze Möwe
// wurde um bis zu 28 Prozent breiter und wieder schmaler, die Flügel selbst
// blieben unbewegt. Geprüft wird jetzt am Bild — bei stillgelegter Welt zwei
// Aufnahmen eine halbe Schlagperiode auseinander.
//
// Dieser Block steht am Ende, weil er die Simulation anhält und die Kamera
// freistellt. Alles danach liefe auf einer eingefrorenen Welt.
const schlag = await (async () => {
 const vorbereitet = await page.evaluate(() => {
  const L = window.LOWTIDE, t = L.world.tiere;
  if (!t?.moewenNetz) return null;
  // Ein Aufruf mit weit entferntem Spieler: sonst hebt die Möwe um neun
  // Meter ab, weil sie ihn in vierzig Metern für eine Störung hält.
  t.update(1 / 60, 0, {x: -900, z: 900});
  t.update = () => {};
  const a = t.moewenNetz.instanceMatrix.array;
  const x = a[12], y = a[13], z = a[14];
  // Von unten gegen den Himmel.
  L.luftbild(x - 2.2, y - 3.4, z - 2.2, x, y, z);
  L.sim.paused = true;
  return {attribut: !!t.moewenNetz.geometry.getAttribute('schlag'),
   uniform: !!t.moewenNetz.material.userData.vZeit, tiere: t.moewen.length};
 });
 if (!vorbereitet) return null;
 const aufnahme = async (wert, name) => {
  await page.evaluate(v => {window.LOWTIDE.world.tiere.moewenNetz.material.userData.vZeit.value = v;}, wert);
  const f0 = await page.evaluate(() => window.LOWTIDE.frames);
  await page.waitForFunction(k => window.LOWTIDE.frames > k + 1, f0, {timeout: 120000});
  await page.evaluate(n => {
   const w = window.LOWTIDE.world, g = w.renderer.getContext();
   w.zeichne();
   const b = new Uint8Array(900 * 520 * 4);
   g.readPixels(0, 0, 900, 520, g.RGBA, g.UNSIGNED_BYTE, b);
   (window.__schlag || (window.__schlag = {}))[n] = b;
  }, name);
 };
 await aufnahme(0, 'tief');
 await aufnahme(Math.PI, 'hoch');
 await aufnahme(0, 'wieder');
 const abstand = (p, q) => page.evaluate(([p, q]) => {
  const a = window.__schlag[p], b = window.__schlag[q];
  let d = 0, n = 0;
  for (let y = 160; y < 360; y++) for (let x = 330; x < 570; x++) {
   const i = (y * 900 + x) * 4;
   d += Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]);
   n += 3;
  }
  return d / n;
 }, [p, q]);
 return {...vorbereitet, bewegt: await abstand('tief', 'hoch'), stabil: await abstand('tief', 'wieder')};
})();
pruefe('Die Möwe hat einen Flügelschlag je Tier', !!schlag?.attribut && !!schlag?.uniform,
 schlag ? `${schlag.tiere} Möwen, Attribut ${schlag.attribut}, Uniform ${schlag.uniform}` : 'keine Tierwelt');
pruefe('Der Flügelschlag bewegt die Geometrie', (schlag?.bewegt ?? 0) > 1,
 `halbe Periode ${schlag?.bewegt.toFixed(3)}, gleiche Stellung ${schlag?.stabil.toFixed(3)}`);
pruefe('Bei gleicher Flügelstellung ist das Bild dasselbe', (schlag?.stabil ?? 9) < .05,
 `${schlag?.stabil.toFixed(4)}`);

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
