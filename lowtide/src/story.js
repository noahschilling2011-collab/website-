// Akt 3 bis 5 der Kampagne.
//
// Die ersten beiden Akte liegen in simulation.js (Auftrag am Lager) und in
// campaign.js (Relais, Archiv, Zeugin, Entscheidung). Danach war Schluss:
// stage 4 hieß "Kampagne abgeschlossen". Hier kommen die drei fehlenden Akte
// dazu, jeder mit einer eigenen Mechanik statt einer weiteren Laufaufgabe:
//
//   Akt 3  Ein Transport fährt eine feste Route zur Luftfracht. Er lässt sich
//          nur rammen — erreicht er das Ziel, startet er neu.
//   Akt 4  Der Tresor im Hinterzimmer des Undertow. Nur nachts, nur geduckt,
//          und das Knacken bricht ab, sobald eine Wache Sichtkontakt hat.
//   Akt 5  Reyes flieht mit dem Boot Richtung Isla Serena. Verfolgung auf
//          dem Wasser, drei mögliche Ausgänge.
//
// Alle Zustände hängen an sim.campaign und werden dadurch mitgespeichert.
// Die Fahrzeuge und Wachen entstehen beim Weltaufbau, nicht erst beim
// Missionsstart: die Renderer legen ihre Meshes einmalig nach Indizes an,
// später eingefügte Fahrzeuge blieben unsichtbar.

import {distance, clamp, lineClear} from './simulation.js';
import {locations, waterAt} from './content.js';

export const AKT3 = 5, AKT4 = 6, AKT5 = 7, ENDE = 8;

// Route des Transports: Industriegelände im Osten, Highway nach Westen,
// Nord-Süd-Achse hinunter, zuletzt der Abzweig zur Luftfracht.
export const KONVOI_ROUTE = [
 {x: 60, z: -320}, {x: -100, z: -320}, {x: -340, z: -320},
 {x: -340, z: 40}, {x: -340, z: 200}, {x: -340, z: 262}, {x: -390, z: 270}
];
export const KONVOI_START = {x: 78, z: -320, yaw: -Math.PI / 2};
export const KONVOI_TEMPO = 15, KONVOI_VORLAUF = 30;

// Tresorraum im Undertow. Die Raumwände stehen bei club.x ± 8 und club.z − 12;
// der Punkt liegt an der Rückwand, also wirklich innen.
export const TRESOR = {x: locations.club.x + 6, z: locations.club.z - 9};
export const TRESOR_DAUER = 6.5;

// Fluchtroute des Bootes. Jeder Punkt liegt im Wasser — sonst würde das Boot
// im Ufer stecken bleiben; getestet in tools/regression.mjs.
// Die Punkte werden in tools/regression.mjs gegen waterAt geprüft: mit den
// Keys kamen Inseln dazu, und der erste Punkt lag danach auf der Anchor Bank.
export const FLUCHT_ROUTE = [
 {x: 138, z: 96}, {x: 196, z: -46}, {x: 268, z: 62}, {x: 380, z: 176},
 {x: 300, z: 336}, {x: 226, z: 320}, {x: 136, z: 232}
];
export const FLUCHT_START = {x: 138, z: 118};
export const FLUCHT_TEMPO = 17, FANG_ABSTAND = 8, FANG_DAUER = 2.2;

// Wird am Ende von expandWorld gerufen. Legt Transport, Boot und die vier
// Wachen an, alle zunächst untätig.
export function storyAufbau(sim) {
 sim.cars.push({
  id: 'CAL-TRANSPORT', model: 'truck', x: KONVOI_START.x, z: KONVOI_START.z, yaw: KONVOI_START.yaw,
  speed: 0, health: 100, fuel: 100, tires: 100, glass: 100, lights: 100, alt: 0,
  type: 'konvoi', color: 0x36414c, upgrades: {}, owner: 'caldera'
 });
 sim.cars.push({
  id: 'CAL-BOOT', model: 'boat', x: FLUCHT_START.x, z: FLUCHT_START.z, yaw: 0,
  speed: 0, health: 100, fuel: 100, tires: 100, glass: 100, lights: 100, alt: 0,
  type: 'flucht', color: 0x22303a, upgrades: {}, owner: 'caldera'
 });
 // Zwei Begleiter am Transport, zwei Wachen am Undertow. aktWache hält sie
 // aus updateGuards heraus; sie reagieren nur im jeweiligen Akt.
 const wachen = [
  ['konvoi', KONVOI_START.x - 6, KONVOI_START.z + 4],
  ['konvoi', KONVOI_START.x - 6, KONVOI_START.z - 4],
  ['club', locations.club.x - 5, locations.club.z + 6],
  ['club', locations.club.x + 2, locations.club.z - 9]
 ];
 wachen.forEach(([rolle, x, z], k) => {
  // Die innere Clubwache läuft quer durchs Hinterzimmer und damit am Tresor
  // vorbei; alle anderen gehen einen kurzen Posten auf und ab.
  const weg = rolle === 'club' && k === 3
   ? [{x: locations.club.x + 2, z: locations.club.z - 9}, {x: locations.club.x - 6, z: locations.club.z - 9}]
   : [{x, z}, {x, z: z + 7}];
  sim.npcs.push({
   id: 900 + k, x, z, yaw: 0, state: 'normal', timer: 0, health: 100,
   path: weg, target: 1, personality: 'guard', pace: rolle === 'club' ? 2.1 : 1.4,
   report: null, stun: 0, guard: true, aktWache: rolle, schedule: 'street',
   home: {x, z}, work: {x, z}, originalPath: weg.map(q => ({...q})), shot: 0
  });
 });
}

// Nach restore(): Spielstände von vor Akt 3 kennen Transport, Boot und die
// Aktwachen nicht. Sie standen beim Aufbau am Ende beider Listen, also stellt
// ein Anhängen die ursprüngliche Reihenfolge — und damit die Mesh-Indizes —
// wieder her.
export function storyReparieren(sim) {
 const fehlen = !sim.cars.some(c => c.type === 'konvoi') || !sim.cars.some(c => c.type === 'flucht')
  || !sim.npcs.some(n => n.aktWache);
 if (!fehlen) return false;
 sim.cars = sim.cars.filter(c => c.type !== 'konvoi' && c.type !== 'flucht');
 sim.npcs = sim.npcs.filter(n => !n.aktWache);
 storyAufbau(sim);
 return true;
}

const transport = sim => sim.cars.find(c => c.type === 'konvoi');
const fluchtboot = sim => sim.cars.find(c => c.type === 'flucht');

// Startet einen Akt. nr ist 3, 4 oder 5.
export function starteAkt(sim, nr) {
 const k = sim.campaign;
 if (nr === 3) {
  k.stage = AKT3;
  k.konvoi = {phase: 'wartet', vorlauf: KONVOI_VORLAUF, punkt: 0, versuche: 0};
  konvoiZuruecksetzen(sim);
  sim.notify('Der Transport rollt in ' + KONVOI_VORLAUF + ' Sekunden los. Besorg dir ein Fahrzeug.');
  sim.post('@pm_funkverkehr', 'Schwertransport ohne Frachtpapiere auf der Nordumgehung gemeldet.');
 }
 if (nr === 4) {
  k.stage = AKT4;
  k.tresor = {fortschritt: 0, alarme: 0};
 }
 if (nr === 5) {
  k.stage = AKT5;
  k.jagd = {punkt: 0, naehe: 0, gestartet: false};
  const b = fluchtboot(sim);
  if (b) {Object.assign(b, {x: FLUCHT_START.x, z: FLUCHT_START.z, speed: 0, health: 100});}
  sim.post('@tideline_lokal', 'Ein Boot verlässt die Marina mit Kurs auf Isla Serena. Ohne Licht.');
 }
}

function konvoiZuruecksetzen(sim) {
 const c = transport(sim);
 if (!c) return;
 Object.assign(c, {x: KONVOI_START.x, z: KONVOI_START.z, yaw: KONVOI_START.yaw, speed: 0, health: 100});
 for (const n of sim.npcs) if (n.aktWache === 'konvoi') {
  n.health = 100; n.stun = 0; n.state = 'normal';
  n.x = KONVOI_START.x - 6; n.z = KONVOI_START.z + (n.id % 2 ? -4 : 4);
 }
}

// Markerziel. null bedeutet: die Kampagne hat hier nichts vorzugeben.
export function storyZiel(sim) {
 const k = sim.campaign;
 if (k.stage === 4) return locations.diner;
 if (k.stage === AKT3) {
  const c = transport(sim);
  return k.konvoi?.phase === 'gestoppt' && c ? c : c || locations.aircargo;
 }
 if (k.stage === AKT4) return TRESOR;
 if (k.stage === AKT5) return fluchtboot(sim) || locations.ferry;
 return null;
}

export function storyTitel(sim) {
 const k = sim.campaign;
 if (k.stage === 4) return 'Akt 3 · Treffen bei Nora’s Diner';
 if (k.stage === AKT3) {
  if (k.konvoi?.phase === 'gestoppt') return 'Akt 3 · Transport steht — hol das Kassenbuch';
  const v = Math.ceil(k.konvoi?.vorlauf || 0);
  return v > 0 ? 'Akt 3 · Transport startet in ' + v + ' s' : 'Akt 3 · Ramme den Transport von der Straße';
 }
 if (k.stage === AKT4) {
  const t = k.tresor || {};
  if (t.arbeitet && t.blockiert) return 'Akt 4 · Wache am Tresor — warten';
  if (t.fortschritt > 0) return 'Akt 4 · Tresor ' + Math.round(t.fortschritt / TRESOR_DAUER * 100) + ' %';
  return 'Akt 4 · Undertow, Hinterzimmer — nachts und geduckt';
 }
 if (k.stage === AKT5) return k.jagd?.naehe > 0 ? 'Akt 5 · Bleib dran (' + (FANG_DAUER - k.jagd.naehe).toFixed(1) + ' s)' : 'Akt 5 · Setz Reyes auf dem Wasser nach';
 if (k.stage === ENDE) return 'Kampagne abgeschlossen · ' + (k.ausgang || '');
 return null;
}

// Rückgabewert ist ein Dialogschlüssel für game.js oder null.
export function storyAktion(sim) {
 const k = sim.campaign, p = sim.player;
 if (k.stage === 4 && !p.car && distance(p, locations.diner) < 6) return 'akt3';
 if (k.stage === AKT3 && k.konvoi?.phase === 'gestoppt' && !p.car) {
  const c = transport(sim);
  if (c && distance(p, c) < 4.5) {
   k.konvoi.phase = 'geborgen';
   sim.award(900);
   sim.notify('Kassenbuch gesichert.');
   // Der Zustand rückt hier vor und nicht erst im Dialog: wer den Dialog
   // wegklickt oder in diesem Moment speichert, säße sonst in Akt 3 fest,
   // mit einem geborgenen Kassenbuch und ohne Ziel.
   starteAkt(sim, 4);
   return 'akt4start';
  }
 }
 if (k.stage === AKT4 && !p.car && distance(p, TRESOR) < 2.6) {
  k.tresor ||= {fortschritt: 0, alarme: 0};
  if (!nachts(sim)) {sim.notify('Zu früh. Der Laden ist erst nach 22 Uhr leer genug.'); return null;}
  if (!p.sneak) {sim.notify('Nicht aufrecht. Geduckt (Strg / Schleichen) sieht dich niemand von der Tür aus.'); return null;}
  if (k.tresor.fortschritt >= TRESOR_DAUER) return null;
  k.tresor.arbeitet = true;
  sim.notify('Du setzt am Schloss an. Bleib geduckt und steh still.');
  return null;
 }
 return null;
}

const nachts = sim => sim.hour >= 22 || sim.hour < 5;

// Pro Bild aus campaign.tick gerufen.
export function storyTick(sim, dt) {
 const k = sim.campaign;
 // Ein Spielstand kann in einem Akt liegen, dessen Zustandsobjekt fehlt —
 // etwa nach einem Absturz zwischen starteAkt und dem ersten Speichern.
 if (k.stage === AKT3 && !k.konvoi) k.konvoi = {phase: 'wartet', vorlauf: KONVOI_VORLAUF, punkt: 0, versuche: 0};
 if (k.stage === AKT4 && !k.tresor) k.tresor = {fortschritt: 0, alarme: 0};
 if (k.stage === AKT5 && !k.jagd) k.jagd = {punkt: 0, naehe: 0, gestartet: false};
 if (k.stage === AKT3) konvoiTick(sim, dt);
 else if (k.stage === AKT4) tresorTick(sim, dt);
 else if (k.stage === AKT5) jagdTick(sim, dt);
}

function konvoiTick(sim, dt) {
 const k = sim.campaign.konvoi, c = transport(sim);
 if (!k || !c) return;
 k.sperre = Math.max(0, (k.sperre || 0) - dt);
 if (k.phase === 'gestoppt' || k.phase === 'geborgen') {
  c.speed = 0;
  if (k.phase === 'gestoppt') wachenTick(sim, dt, 'konvoi', 22);
  return;
 }
 if (k.vorlauf > 0) {
  k.vorlauf -= dt;
  if (k.vorlauf > 0) return;
  sim.notify('Der Transport fährt los.');
 }
 // Nicht nur beim Nulldurchgang setzen: ein von außen gesetzter Vorlauf
 // (Spielstand, Prüfwerkzeug) ließe den Wagen sonst dauerhaft in 'wartet'
 // fahren, und konvoiRammen greift nur in 'faehrt'.
 k.phase = 'faehrt';
 // Wegpunkt für Wegpunkt, ohne Ausweichlogik: der Transport hält sich an die
 // Trasse und lässt sich genau deshalb abpassen.
 const ziel = KONVOI_ROUTE[k.punkt];
 if (!ziel) {
  k.punkt = 0; k.versuche++;
  konvoiZuruecksetzen(sim);
  k.vorlauf = KONVOI_VORLAUF; k.phase = 'wartet';
  sim.notify('Der Transport ist durch. Ein zweiter fährt in ' + KONVOI_VORLAUF + ' Sekunden.');
  return;
 }
 const d = distance(c, ziel);
 if (d < 6) {k.punkt++; return;}
 const soll = Math.atan2(ziel.x - c.x, ziel.z - c.z);
 let diff = ((soll - c.yaw + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
 c.yaw += clamp(diff, -dt * 1.6, dt * 1.6);
 c.speed = KONVOI_TEMPO * (c.health > 45 ? 1 : .55);
 c.x += Math.sin(c.yaw) * c.speed * dt;
 c.z += Math.cos(c.yaw) * c.speed * dt;
}

// Aufprall aus driveVehicle. Nur der Transport nimmt hier Schaden; ein
// normaler Rempler kostet ihn deutlich mehr als ein Zivilfahrzeug.
export function konvoiRammen(sim, wucht) {
 const k = sim.campaign.konvoi, c = transport(sim);
 if (!k || !c || k.phase !== 'faehrt') return;
 // Ohne Sperre zählt jedes Bild als eigener Treffer: nebenherfahren hätte den
 // Aufbau in einer Viertelsekunde zerlegt. So sind es vier klare Rammstöße.
 if ((k.sperre || 0) > 0) return;
 k.sperre = 1.2;
 c.health = Math.max(0, c.health - wucht * 1.9 - 6);
 if (c.health <= 0) {
  k.phase = 'gestoppt';
  c.speed = 0;
  for (const n of sim.npcs) if (n.aktWache === 'konvoi' && n.health > 0) {
   n.x = c.x + (n.id % 2 ? 3.5 : -3.5); n.z = c.z + 2.5; n.state = 'aggressiv'; n.shot = 1.2;
  }
  sim.notify('Der Transport steht. Zwei Begleiter steigen aus.');
 } else sim.notify('Treffer. Aufbau ' + Math.round(c.health) + ' %.');
}

// Wachen der Akte. Eigene Routine, damit die allgemeine Wachlogik aus
// campaign.js hier nicht mitredet.
function wachenTick(sim, dt, rolle, sicht) {
 const p = sim.player;
 for (const n of sim.npcs) {
  if (n.aktWache !== rolle || n.health <= 0 || n.stun > 0) continue;
  n.shot = (n.shot || 0) - dt;
  const d = distance(n, p);
  if (d > sicht || !lineClear(n, p, sim.solids)) continue;
  n.yaw = Math.atan2(p.x - n.x, p.z - n.z);
  if (d > 3.5) {sim.move(n, Math.sin(n.yaw) * dt * 3.2, Math.cos(n.yaw) * dt * 3.2, .5);}
  if (n.shot <= 0) {
   n.shot = 1.9;
   p.health -= p.cover ? 3 : 8;
   sim.tracers.push({x: n.x, z: n.z, end: {x: p.x, z: p.z}, life: .12});
  }
 }
}

function tresorTick(sim, dt) {
 const k = sim.campaign.tresor, p = sim.player;
 if (!k) return;
 // Die beiden Wachen laufen ihre zwei Punkte ab. updateRoutines lässt
 // Wachen aus, sonst stünden sie wie Pfosten herum — und ohne Bewegung wäre
 // der Tresor eine reine Wartezeit statt einer Frage des Zeitpunkts.
 let nah = false;
 for (const n of sim.npcs) {
  if (n.aktWache !== 'club' || n.health <= 0) continue;
  if (n.stun <= 0) {
   const ziel = n.path[n.target] || n.path[0];
   const d = distance(n, ziel);
   if (d < 1) n.target = (n.target + 1) % n.path.length;
   else {
    n.yaw = Math.atan2(ziel.x - n.x, ziel.z - n.z);
    sim.move(n, Math.sin(n.yaw) * dt * n.pace, Math.cos(n.yaw) * dt * n.pace, .45);
   }
  }
  if (distance(n, TRESOR) < 7) nah = true;
  if (distance(n, p) < 14 && !p.sneak && lineClear(n, p, sim.solids) && k.fortschritt > 0) {
   k.fortschritt = 0; k.arbeitet = false; k.alarme++;
   sim.report(2, p);
   sim.notify('Gesehen. Der Versuch ist aufgeflogen.');
  }
 }
 k.blockiert = nah;
 if (!k.arbeitet) return;
 if (distance(p, TRESOR) > 2.8 || p.car || !p.sneak || sim.stars) {
  if (k.fortschritt > 0) sim.notify('Abgebrochen.');
  k.arbeitet = false; k.fortschritt = 0; return;
 }
 // Steht eine Wache neben dem Tresor, ruht die Hand. Das ist der eigentliche
 // Takt des Akts: arbeiten, wenn sie weg ist, warten, wenn sie kommt.
 if (nah) return;
 // Mara arbeitet an Sicherungen schneller — das ist ihr Merkmal seit Akt 2.
 k.fortschritt += dt * (sim.active === 1 ? 1.45 : 1);
 if (k.fortschritt >= TRESOR_DAUER) {
  k.arbeitet = false;
  sim.award(1400);
  sim.notify('Der Tresor ist offen. Kontobewegungen über zwölf Jahre.');
  sim.post('@tideline_lokal', 'Im Undertow soll heute Nacht jemand am Büro gewesen sein.');
  starteAkt(sim, 5);
  sim.aktDialog = 'akt5start';
 }
}

function jagdTick(sim, dt) {
 const k = sim.campaign.jagd, b = fluchtboot(sim), p = sim.player;
 if (!k || !b) return;
 const ziel = FLUCHT_ROUTE[k.punkt % FLUCHT_ROUTE.length];
 const soll = Math.atan2(ziel.x - b.x, ziel.z - b.z);
 let diff = ((soll - b.yaw + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
 b.yaw += clamp(diff, -dt * 1.1, dt * 1.1);
 // Er fährt schneller, wenn der Verfolger weit weg ist, und langsamer, wenn
 // er nah dran ist: die Jagd bleibt so ohne Gummiband auf beiden Seiten fair.
 const weg = distance(b, p);
 b.speed = FLUCHT_TEMPO * (weg > 90 ? .78 : 1);
 const nx = b.x + Math.sin(b.yaw) * b.speed * dt, nz = b.z + Math.cos(b.yaw) * b.speed * dt;
 if (waterAt(nx, nz)) {b.x = nx; b.z = nz;} else k.punkt++;
 if (distance(b, ziel) < 14) k.punkt++;

 if (weg < FANG_ABSTAND && p.car) {
  k.naehe = (k.naehe || 0) + dt;
  if (k.naehe >= FANG_DAUER) {
   b.speed = 0;
   sim.paused = true;
   sim.aktDialog = 'ende';
  }
 } else if (k.naehe > 0) k.naehe = Math.max(0, k.naehe - dt * .8);
}

// Die drei Ausgänge. Jeder verschiebt Geld, Vertrauen und den Ticker anders.
export const AUSGAENGE = {
 polizei: {
  titel: 'Übergabe', ausgang: 'Übergabe',
  geld: 1500, vertrauen: 15, fahndung: 0,
  text: 'Reyes sitzt in Handschellen an der Mole, als der erste Streifenwagen kommt. Das Kassenbuch geht mit. Es wird Jahre dauern, und es wird nicht alles herauskommen — aber es fängt an.',
  ticker: 'Festnahme an der Mole. Die Staatsanwaltschaft bestätigt Ermittlungen gegen Caldera Freight.'
 },
 geld: {
  titel: 'Abfindung', ausgang: 'Abfindung',
  geld: 25000, vertrauen: -30, fahndung: 0,
  text: 'Er zahlt bar, aus einem Koffer, der zu ordentlich gepackt ist, um improvisiert zu sein. Das Boot fährt weiter Richtung Süden. Mara schreibt nichts mehr zurück.',
  ticker: 'Das Verfahren gegen Caldera Freight wird mangels Beweisen eingestellt.'
 },
 abrechnung: {
  titel: 'Abrechnung', ausgang: 'Abrechnung',
  geld: 0, vertrauen: -10, fahndung: 4,
  text: 'Danach ist es sehr still auf dem Wasser. Das Kassenbuch treibt irgendwo zwischen den Bojen. Zwei Boote der Küstenwache drehen bei und nehmen Kurs auf dich.',
  ticker: 'Schüsse vor Isla Serena. Die Küstenwache sucht ein Boot ohne Kennung.'
 }
};

export function beendeKampagne(sim, welcher) {
 const a = AUSGAENGE[welcher];
 if (!a) return null;
 sim.campaign.stage = ENDE;
 sim.campaign.ausgang = a.ausgang;
 if (a.geld) sim.award(a.geld);
 sim.relationship = clamp(sim.relationship + a.vertrauen, 0, 100);
 if (a.fahndung) sim.report(a.fahndung * 2, sim.player);
 sim.post('@tideline_lokal', a.ticker);
 const b = fluchtboot(sim);
 if (b) b.speed = 0;
 return a;
}
