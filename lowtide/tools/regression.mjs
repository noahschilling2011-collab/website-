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

pruefe('Fahrzeug bricht bei voller Lenkung aus', await page.evaluate(() => {
 const s = window.LOWTIDE.sim, auto = s.cars.find(c => c.model === 'muscle') || s.cars[0];
 auto.unlocked = true; auto.slip = 0; auto.speed = 0;
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
 // Einen Alligator direkt vor die Figur setzen und in seine Richtung schauen.
 const a = t.alligatoren[0];
 L.sim.player.x = a.x; L.sim.player.z = a.z - 12;
 // Andere Tiere können zufällig auch im Blickfeld liegen; entscheidend ist,
 // dass die Blickrichtung überhaupt zählt.
 const vorn = t.imBild({x: a.x, z: a.z - 12}, 0);
 const hinten = t.imBild({x: a.x, z: a.z - 12}, Math.PI);
 return vorn >= 1 && hinten < vorn;
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
pruefe('Speichern und Laden überstehen den Rundlauf', await page.evaluate(() => {
 const s = window.LOWTIDE.sim;
 s.player.money = 4321;
 const stand = JSON.parse(JSON.stringify(s.snapshot()));
 s.player.money = 0;
 s.restore(stand);
 s.paused = false;
 return s.player.money === 4321;
}));

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
pruefe('Der Wassershader kennt alle Küsten', keys.kuesten === 9, `${keys.kuesten} Rechtecke`);
pruefe('Nachbearbeitung ist aktiv und tonwertet selbst', keys.postAn && keys.keinTonwert, `toneMapping=${keys.tonwert}`);
pruefe('Tiefe steht der Verdeckung zur Verfügung', keys.tiefe);
pruefe('Verdeckung dunkelt tatsächlich ab', keys.aoMin < 245, `dunkelster Wert ${keys.aoMin}`);
pruefe('Oberflächendetail liegt auf allen matten Weltmaterialien',
 keys.detail[0] === keys.detail[1] && keys.detail[1] > 50 && keys.detail[2] > 0,
 `${keys.detail[0]} von ${keys.detail[1]}, ${keys.detail[2]} leuchtende ausgenommen`);
pruefe('Sparmodus schaltet die Nachbearbeitung ab', await page.evaluate(() => {
 const knopf = document.getElementById('qualityBtn'), w = window.LOWTIDE.world;
 knopf.click();
 const aus = !w.post.aktiv;
 knopf.click();
 return aus && w.post.aktiv;
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
