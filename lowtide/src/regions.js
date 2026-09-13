import {groundAt, waterAt, locations, onRoad, roadSegments, INSELN, DAEMME, TANKSTELLE, SEEN} from './content.js';
// Der Rest von Solvara.
// Port Mercy war ausgebaut, alles andere bestand aus Andeutungen: sechs
// Kisten für die Vororte, ein Feld mit Strichen für Bellweather, 155
// Baumkisten für den Nationalpark, eine graue Bahn für das Flugfeld, eine
// leere Platte für Isla Serena. Hier bekommt jede Region das, was sie
// glaubwürdig macht — alles über World.box, also instanziert.

function zufall(seed = 5501) {
 return () => {seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296;};
}

const aufStrasse = onRoad;

// Eine waagerechte Platte auf einem Hang steht mit einer Kante in der Luft
// und mit der anderen im Boden. Auf Talon Ridge lag ein Feldweg als Reihe
// schwebender Rhomben den Hang hinunter — 32 Platten, gut sichtbar aus
// zweihundert Metern. Hier wird die Neigung aus dem Geländeanstieg genommen.
function bodenPlatte(w, x, z, breite, tiefe, farbe, dicke = .08) {
 const e = 2.5;
 const steigungZ = (groundAt(x, z + e) - groundAt(x, z - e)) / (2 * e);
 const steigungX = (groundAt(x + e, z) - groundAt(x - e, z)) / (2 * e);
 w.box(x, groundAt(x, z) + dicke, z, breite, dicke, tiefe, farbe, 0, false,
  -Math.atan(steigungZ), Math.atan(steigungX));
}

// Passt ein Bauwerk dieser Grundfläche hierhin, ohne eine Fahrbahn zu
// berühren? aufStrasse() prüft einen Punkt mit einem Zuschlag, und der
// Zuschlag war überall geraten. In Rosalind stand er auf 13 — bei einem
// Abstand von 16 Metern zwischen Straßenachse und Hausmitte hieß das:
// **alle zweiundzwanzig Läden der Hauptstraße wurden übersprungen**, und die
// zweite Stadt bestand aus Straßen, Laternen, Ampeln und leeren Blöcken.
// Gefunden nicht am Bild, sondern beim Nachrechnen der Bedingung.
// Der Zuschlag ist ein halber Meter, nicht mehr: in einer Kleinstadt steht
// die Ladenzeile direkt am Gehweg, und das Vordach ragt darüber. Verboten
// ist die Fahrbahn, nicht der Bürgersteig.
function passtNebenStrasse(x, z, breite, tiefe, luft = .5) {
 const x1 = x - breite / 2 - luft, x2 = x + breite / 2 + luft;
 const z1 = z - tiefe / 2 - luft, z2 = z + tiefe / 2 + luft;
 return !roadSegments.some(r =>
  x1 < Math.max(r.x1, r.x2) + r.w / 2 && x2 > Math.min(r.x1, r.x2) - r.w / 2 &&
  z1 < Math.max(r.z1, r.z2) + r.w / 2 && z2 > Math.min(r.z1, r.z2) - r.w / 2);
}
const RAEUME = ['garage','shop','clinic','home','club','diner','motel','records']
 .filter(id => locations[id])
 .map(id => ({x: locations[id].x, z: locations[id].z - 4, w: (id === 'garage' ? 22 : 16) / 2 + 2, d: 10}));
// Wie in street.js: die offenen Läden zählen für sim.blocked nicht als belegt.
const imRaum = (x, z) => RAEUME.some(r => Math.abs(x - r.x) < r.w && Math.abs(z - r.z) < r.d);

// Satteldach aus zwei geneigten Platten. Erst damit hört ein Haus auf,
// eine Kiste mit Deckel zu sein.
function satteldach(w, x, y, z, breite, tiefe, hoehe, farbe, quer = false) {
 const spanne = (quer ? tiefe : breite) / 2;
 const winkel = Math.atan2(hoehe, spanne);
 const laenge = Math.hypot(spanne, hoehe);
 for (const seite of [-1, 1]) {
  const ox = quer ? 0 : seite * spanne / 2, oz = quer ? seite * tiefe / 4 : 0;
  w.box(x + ox, y + hoehe / 2, z + oz,
   quer ? breite : laenge, .16, quer ? laenge : tiefe, farbe, 0,
   false, quer ? -seite * winkel : 0, quer ? 0 : seite * winkel);
 }
 // Giebeldreieck grob als schmaler Keil, damit unter dem Dach nichts durchscheint.
 for (const seite of [-1, 1]) {
  const gx = quer ? x + seite * breite / 2 : x, gz = quer ? z : z + seite * tiefe / 2;
  w.box(gx, y + hoehe / 3, gz, quer ? .2 : breite * .72, hoehe * .66, quer ? tiefe * .72 : .2, farbe);
 }
}

// Nadelbaum. Erst waren es drei gestapelte Kisten — aus zwanzig Metern sah
// der Wald aus wie ein Regal. Jetzt gehen beide Baumarten an das Laubwerk in
// foliage.js: gekreuzte Flächen mit Alphakarte, zwei InstancedMeshes für die
// ganze Karte statt fünf Kisten je Baum.
function nadelbaum(w, x, z, hoehe, farbe = 0x3d5f47) {
 w.baum(x, z, hoehe, 'nadel', farbe);
}

function laubbaum(w, x, z, hoehe, farbe = 0x4d6f4a) {
 w.baum(x, z, hoehe, 'laub', farbe);
}

function zaun(w, x1, z1, x2, z2, hoehe = 1.2, farbe = 0x8a7a5e, abstand = 2.4) {
 const laenge = Math.hypot(x2 - x1, z2 - z1);
 if (laenge < .5) return;
 const dx = (x2 - x1) / laenge, dz = (z2 - z1) / laenge, dreh = Math.atan2(dx, dz);
 for (let s = 0; s <= laenge; s += abstand) {
  const x = x1 + dx * s, z = z1 + dz * s;
  w.box(x, groundAt(x, z) + hoehe / 2, z, .12, hoehe, .12, farbe);
 }
 for (const h of [hoehe * .35, hoehe * .8]) {
  const mx = (x1 + x2) / 2, mz = (z1 + z2) / 2;
  w.box(mx, groundAt(mx, mz) + h, mz, .06, .12, laenge, farbe, dreh);
 }
}

// ---------------------------------------------------------------- Vororte
function sunsetSuburbs(w, rng) {
 const DAECHER = [0x8c5a4c, 0x6d7a72, 0x9a7d52, 0x5f6b7c, 0x7d6a55];
 const WAENDE = [0xc3b8a0, 0xb0bcb4, 0xd0c3a8, 0xa8b4bc, 0xc9bda6];
 let n = 0;
 for (const strasseZ of [-260, -305, -350, -395]) {
  // Wohnstraße mit Rinne, ohne sie in roadSegments aufzunehmen: hier fährt
  // kein Verkehr, es ist reine Erschließung.
  w.box(-25, .04, strasseZ, 210, .1, 8, 0x3d494f);
  for (let x = -125; x < 78; x += 12) w.box(x, .09, strasseZ, 3, .02, .14, 0xc4bb97);
  for (const seite of [-1, 1]) w.box(-25, .12, strasseZ + seite * 5, 210, .24, 2, 0x8e8b7f);

  for (let hausX = -118; hausX < 74; hausX += 24) {
   for (const seite of [-1, 1]) {
    const x = hausX + rng() * 3, z = strasseZ + seite * (14 + rng() * 3);
    if (w.sim.blocked({x, z}, 9) || aufStrasse(x, z, 11)) continue;
    n++;
    const breite = 11 + rng() * 4, tiefe = 9 + rng() * 3, wand = WAENDE[n % WAENDE.length];
    w.box(x, 1.7, z, breite, 3.4, tiefe, wand);
    satteldach(w, x, 3.45, z, breite + 1.2, tiefe + 1.2, 1.7, DAECHER[n % DAECHER.length], rng() < .5);
    // Veranda zur Straße.
    const vz = z - seite * (tiefe / 2 + 1.4);
    w.box(x, .18, vz, breite * .8, .36, 2.8, 0xa8a08c);
    w.box(x, 2.8, vz, breite * .8, .16, 3.2, DAECHER[n % DAECHER.length]);
    for (const e of [-1, 1]) w.box(x + e * breite * .35, 1.5, vz + 1.4, .14, 2.6, .14, wand);
    w.box(x + (rng() - .5) * 2, 1.2, z - seite * (tiefe / 2 + .1), 1.1, 2.2, .16, 0x4a3a2c);
    // Fenster mit Rahmen.
    for (const ox of [-breite * .3, breite * .3]) {
     w.box(x + ox, 2, z - seite * (tiefe / 2 + .08), 1.7, 1.3, .1, 0x36505c);
     w.box(x + ox, 2, z - seite * (tiefe / 2 + .14), 1.95, 1.55, .08, wand);
    }
    // Auffahrt, Garage, Briefkasten, Hecke, Baum.
    const ax = x + breite / 2 + 2.2;
    w.box(ax, .06, (z + strasseZ) / 2, 4, .12, Math.abs(z - strasseZ) - 4, 0x8f8c83);
    w.box(ax, 1.5, z, 5.2, 3, tiefe * .7, wand);
    satteldach(w, ax, 3.05, z, 5.6, tiefe * .7 + .8, 1.1, DAECHER[(n + 2) % DAECHER.length], true);
    w.box(ax, 1.1, z - seite * (tiefe * .35 + .1), 4.4, 2.2, .14, 0x6e6a60);
    w.box(x - breite / 2 - 2, .6, strasseZ + seite * 7.5, .12, 1.2, .12, 0x6b5f4c);
    w.box(x - breite / 2 - 2, 1.28, strasseZ + seite * 7.5, .5, .3, .8, 0x9aa39b);
    zaun(w, x - breite / 2 - 3, z - seite * tiefe, x - breite / 2 - 3, z + seite * tiefe, 1.1, 0x9a8a6a, 2.2);
    if (rng() < .55) laubbaum(w, x - breite / 2 - 5, z + seite * 3, 5 + rng() * 3);
    else w.palm(x - breite / 2 - 5, z + seite * 3, 6 + rng() * 2);
    // Pool hinterm Haus für jedes vierte Grundstück.
    if (rng() < .28) {
     const pz = z + seite * (tiefe / 2 + 5);
     w.box(x, .1, pz, 8, .16, 5.5, 0xcfc7b2);
     w.box(x, .14, pz, 7, .12, 4.5, 0x3f8fa0);
     for (const ox of [-4.6, 4.6]) {
      w.box(x + ox, .3, pz, 1.9, .12, .75, 0xe0dcd0);
      w.box(x + ox - .7, .5, pz, .5, .5, .75, 0xe0dcd0, 0, false, 0, .55);
     }
    }
   }
  }
 }
 // Spielplatz und kleiner Park in einer Lücke.
 const px = -95, pz = -327;
 w.box(px, .05, pz, 26, .1, 22, 0x6f8a5e);
 w.box(px - 4, 1.3, pz, .16, 2.6, .16, 0x8d5f4e);
 w.box(px + 4, 1.3, pz, .16, 2.6, .16, 0x8d5f4e);
 w.box(px, 2.5, pz, 8.4, .16, .16, 0x8d5f4e);
 for (const e of [-2, 2]) {
  w.box(px + e, 1.6, pz, .05, 1.6, .05, 0x50565a);
  w.box(px + e, .78, pz, .8, .1, .3, 0x3f5d68);
 }
 w.box(px + 8, .9, pz - 5, 3.4, 1.8, 3.4, 0xb0724f);
 satteldach(w, px + 8, 1.85, pz - 5, 4, 4, .9, 0x7d4f3c);
 for (const e of [-8, 8]) {
  w.box(px + e, .42, pz + 8, 2.1, .1, .55, 0x7d6247);
  w.box(px + e, .72, pz + 8.24, 2.1, .55, .1, 0x7d6247);
 }
 for (let k = 0; k < 7; k++) laubbaum(w, px - 11 + k * 3.6, pz + 9.5, 5 + (k % 3));
}

// ------------------------------------------------------------- Bellweather
function bellweather(w, rng) {
 // Der Highway läuft bei x = -340 durch; der Hof muss westlich davon liegen,
 // aber östlich des Hangs, der ab etwa x = -430 ansteigt.
 const hofX = -400, hofZ = -248;
 const boden = (x, z) => groundAt(x, z);

 // Scheune mit Satteldach und Toranlage.
 const bx = hofX, bz = hofZ, by = boden(bx, bz);
 w.box(bx, by + 4, bz, 20, 8, 14, 0x8e4f42);
 satteldach(w, bx, by + 8.1, bz, 21.5, 15.5, 4, 0x5a4a41, true);
 w.box(bx, by + 2.6, bz + 7, 6, 5.2, .3, 0x6a3f36);
 for (const e of [-3, 3]) w.box(bx + e, by + 2.6, bz + 7.15, .3, 5.2, .35, 0xc9bda6);
 w.box(bx, by + 6.4, bz + 7.2, 3.2, 1.9, .3, 0xd8cbaa);
 w.text('BELLWEATHER', bx, by + 6.4, bz + 7.4, 9, '#7a4a3a');

 // Zwei Silos mit Kegeldach und ein Wasserturm.
 for (const [sx, sz, h] of [[hofX + 16, hofZ - 8, 15], [hofX + 23, hofZ - 8, 12]]) {
  const y = boden(sx, sz);
  w.box(sx, y + h / 2, sz, 6, h, 6, 0xa7aca4);
  for (let ry = 2; ry < h; ry += 2.4) w.box(sx, y + ry, sz, 6.3, .12, 6.3, 0x8d938c);
  w.box(sx, y + h + .8, sz, 5, 1.6, 5, 0x7d837d);
 }
 const tx = hofX - 22, tz = hofZ + 26, ty = boden(tx, tz);
 for (const ox of [-3, 3]) for (const oz of [-3, 3]) w.box(tx + ox, ty + 6, tz + oz, .3, 12, .3, 0x6d6a5e);
 w.box(tx, ty + 13.5, tz, 8, 3.6, 8, 0x93a09b);
 w.box(tx, ty + 15.6, tz, 6.4, .9, 6.4, 0x74807c);

 // Felder mit Furchen und Zaun. Alles bleibt vom Highway weg.
 for (const [fx, fz, fw, fd, farbe] of [
  [hofX - 5, hofZ + 62, 86, 56, 0x6e7b45],
  [hofX + 6, hofZ - 62, 72, 58, 0x84783f],
  [hofX - 34, hofZ - 6, 46, 62, 0x627545]]) {
  if (aufStrasse(fx, fz, 2)) continue;
  w.box(fx, boden(fx, fz) + .05, fz, fw, .1, fd, farbe);
  for (let u = -fw / 2 + 2; u < fw / 2; u += 3.6)
   w.box(fx + u, boden(fx + u, fz) + .14, fz, .7, .1, fd - 2, farbe === 0x84783f ? 0x9a8d48 : 0x54663d);
  zaun(w, fx - fw / 2, fz - fd / 2, fx + fw / 2, fz - fd / 2, 1.3, 0x8a7a5e, 4);
  zaun(w, fx - fw / 2, fz + fd / 2, fx + fw / 2, fz + fd / 2, 1.3, 0x8a7a5e, 4);
  zaun(w, fx - fw / 2, fz - fd / 2, fx - fw / 2, fz + fd / 2, 1.3, 0x8a7a5e, 4);
  zaun(w, fx + fw / 2, fz - fd / 2, fx + fw / 2, fz + fd / 2, 1.3, 0x8a7a5e, 4);
 }
 for (let k = 0; k < 16; k++) {
  const x = hofX - 40 + rng() * 74, z = hofZ + 34 + rng() * 54;
  if (aufStrasse(x, z, 4)) continue;
  w.box(x, boden(x, z) + .9, z, 2.4, 1.8, 2.4, 0xc0a860, rng() * 3);
 }
 // Traktor: grob, aber als Silhouette eindeutig.
 const trx = hofX + 13, trz = hofZ + 10, try_ = boden(trx, trz);
 w.box(trx, try_ + 1.1, trz, 2.2, 1.4, 4, 0x4f7a45);
 w.box(trx, try_ + 2.1, trz - .8, 1.8, 1.6, 1.8, 0x2f4f30);
 for (const [ox, oz, r] of [[-1.3, 1.3, .7], [1.3, 1.3, .7], [-1.4, -1.4, 1.1], [1.4, -1.4, 1.1]])
  w.box(trx + ox, try_ + r, trz + oz, .5, r * 2, r * 2, 0x23282a);
 // Feldweg vom Highway zum Hof.
 w.box(hofX + 27, boden(hofX + 27, hofZ) + .04, hofZ, 46, .1, 7, 0x8a7a58, Math.PI / 2);
 for (let k = 0; k < 30; k++) {
  const x = hofX - 46 + rng() * 100, z = hofZ - 80 + rng() * 150;
  if (w.sim.blocked({x, z}, 5) || aufStrasse(x, z, 8)) continue;
  laubbaum(w, x, z, 6 + rng() * 4);
 }
}

// -------------------------------------------------------- Cypress-Nationalpark
function cypressPark(w, rng) {
 // Der Hang aus groundAt bekommt Wald in Höhenbändern, Felsen, Wege,
 // Zeltplätze, eine Rangerstation und eine Aussichtsplattform.
 for (let k = 0; k < 620; k++) {
  const x = -580 + rng() * 200, z = -540 + rng() * 300;
  const y = groundAt(x, z);
  if (waterAt(x, z) || w.sim.blocked({x, z}, 3)) continue;
  const hoch = y > 26;
  if (hoch) nadelbaum(w, x, z, 7 + rng() * 7, rng() < .5 ? 0x36573f : 0x2f4c3a);
  else if (rng() < .62) nadelbaum(w, x, z, 8 + rng() * 8);
  else laubbaum(w, x, z, 7 + rng() * 6, 0x557a4c);
 }
 for (let k = 0; k < 90; k++) {
  const x = -575 + rng() * 190, z = -535 + rng() * 290, y = groundAt(x, z);
  const s = 1.2 + rng() * 3.4;
  w.box(x, y + s * .32, z, s, s * .7, s * .85, rng() < .5 ? 0x7c7d75 : 0x6a6d67, rng() * 3, false, rng() * .3, rng() * .3);
 }
 // Umgestürzte Stämme: erst mit geneigten Quadern wirkt der Wald benutzt.
 for (let k = 0; k < 22; k++) {
  const x = -560 + rng() * 170, z = -520 + rng() * 260, y = groundAt(x, z);
  w.box(x, y + .4, z, .55, .55, 5 + rng() * 5, 0x5c4d38, rng() * 3, false, .06, rng() * .12);
 }
 // Serpentine als Schotterweg über den Hang.
 let wx = -400, wz = -250;
 for (let k = 0; k < 34; k++) {
  const nx = wx - 4 - rng() * 3, nz = wz - 5 - rng() * 4;
  const mx = (wx + nx) / 2, mz = (wz + nz) / 2;
  const len = Math.hypot(nx - wx, nz - wz);
  w.box(mx, groundAt(mx, mz) + .1, mz, 5.5, .16, len + 2, 0x8d8064, Math.atan2(nx - wx, nz - wz));
  wx = nx; wz = nz;
 }
 // Rangerstation am Parkeingang.
 const r = locations.ranger, ry = groundAt(r.x, r.z);
 w.box(r.x, ry + 2, r.z, 14, 4, 10, 0x7a6a4e);
 satteldach(w, r.x, ry + 4.1, r.z, 15.4, 11.4, 2.2, 0x4f5a4a, true);
 w.box(r.x, ry + .3, r.z + 6, 15, .6, 3, 0x8d7a58);
 for (const e of [-6, -2, 2, 6]) w.box(r.x + e, ry + 2.2, r.z + 7.3, .18, 3.8, .18, 0x6b5c44);
 w.box(r.x, ry + 4.4, r.z + 7.3, 15.4, .18, 3.4, 0x4f5a4a);
 w.box(r.x + 9, ry + 1.4, r.z + 2, .14, 2.8, .14, 0x6b5c44);
 w.box(r.x + 9, ry + 2.6, r.z + 2, 2.6, .9, .1, 0x8a6a44);
 // Zeltplätze mit Feuerstelle und Bänken.
 for (const [cx, cz] of [[-505, -330], [-455, -455], [-540, -415]]) {
  const cy = groundAt(cx, cz);
  w.box(cx, cy + .06, cz, 22, .12, 22, 0x7d7458);
  w.box(cx, cy + .2, cz, 2.4, .4, 2.4, 0x5d5751);
  for (let f = 0; f < 5; f++) w.box(cx + Math.sin(f) * .8, cy + .5, cz + Math.cos(f) * .8, .18, .18, 1.4, 0x4a3a2a, f);
  // Zelt: zwei geneigte Platten plus Giebel.
  const ZELTE = [0x9a6a45, 0x46685f, 0x8a5a5a];
  [[-6, -3], [6, 4], [-2, 7]].forEach(([ox, oz], i) =>
   satteldach(w, cx + ox, cy + .1, cz + oz, 2.8, 3.6, 1.6, ZELTE[i]));
  for (const [ox, oz] of [[-3.5, 2.5], [3.5, -2.5]]) {
   w.box(cx + ox, cy + .45, cz + oz, 1.9, .1, .5, 0x7d6247);
   w.box(cx + ox, cy + .78, cz + oz, 1.9, .08, 1.5, 0x7d6247);
  }
 }
 // Aussichtsplattform auf der Kuppe.
 const ax = -486, az = -418, ay = groundAt(ax, az);
 for (const ox of [-3, 3]) for (const oz of [-3, 3]) w.box(ax + ox, ay + 2.5, az + oz, .32, 5, .32, 0x6b5c44);
 w.box(ax, ay + 5.1, az, 8.4, .3, 8.4, 0x8d7a58);
 for (const [ox, oz, bw, bd] of [[0, 4.2, 8.4, .12], [0, -4.2, 8.4, .12], [4.2, 0, .12, 8.4], [-4.2, 0, .12, 8.4]])
  w.box(ax + ox, ay + 5.7, az + oz, bw, 1.1, bd, 0x6b5c44);
 w.text('MOUNT CYPRESS', ax, ay + 7.4, az + 4.4, 10, '#d8e0cc');
}

// ------------------------------------------------------------- Salzsumpf
function saltMarsh(w, rng) {
 // Über dem Wasser: Mangroven auf Stelzen, Stege, Pfahlbauten, Schilf.
 for (let k = 0; k < 260; k++) {
  const x = -543 + rng() * 141, z = -18 + rng() * 146;
  if (!waterAt(x, z)) continue;
  const h = 3.5 + rng() * 3;
  for (let s = 0; s < 4; s++) {
   const a = s * Math.PI / 2 + rng();
   w.box(x + Math.sin(a) * .8, -.6 + h * .22, z + Math.cos(a) * .8, .22, h * .8, .22, 0x5b4c39, 0, false, Math.sin(a) * .22, Math.cos(a) * .22);
  }
  // Die Krone war eine einzige Kiste von h·0,95 auf h·0,5 auf h·0,9 — bei
  // 260 Stück las sich der Sumpf aus jeder Nähe als Lagerplatz für grüne
  // Paletten auf Stelzen. Sie geht jetzt über dasselbe Laubwerk wie jeder
  // andere Baum: gekreuzte Flächen mit Alphakarte, ein Instanzennetz für die
  // ganze Karte, also kein zusätzlicher Draw Call. Die Art heißt 'mangrove',
  // damit die Prüfung „kein Baum steht im Wasser" sie auslässt.
  w.baum(x, z, h * 1.15, 'mangrove', rng() < .5 ? 0x3f6047 : 0x4a6d4a);
 }
 for (let k = 0; k < 340; k++) {
  const x = -545 + rng() * 145, z = -20 + rng() * 150;
  if (!waterAt(x, z)) continue;
  w.box(x, -.5, z, .5, 1.7, .5, 0x7c8352, rng() * 3, false, .1, .1);
 }
 // Bohlensteg quer durch den Sumpf, mit Geländer und Laternen.
 let sx = -400;
 for (let z = 10; z < 116; z += 3) {
  const x = sx + Math.sin(z * .05) * 22;
  w.box(x, .35, z, 3.2, .22, 3.1, 0x8a7250);
  for (const e of [-1.7, 1.7]) {
   w.box(x + e, -.2, z, .16, 1.4, .16, 0x6b5a40);
   w.box(x + e, .95, z, .1, .1, 3.1, 0x6b5a40);
  }
  if (z % 24 < 3) w.lamp(x + 2.4, z);
 }
 // Pfahlbauten am Steg.
 for (const [hx, hz] of [[-420, 40], [-388, 78], [-436, 100]]) {
  for (const ox of [-3.5, 3.5]) for (const oz of [-3, 3]) w.box(hx + ox, -.2, hz + oz, .3, 3, .3, 0x6b5a40);
  w.box(hx, 1.5, hz, 9, .3, 8, 0x8a7250);
  w.box(hx, 3.3, hz, 8, 3.2, 7, 0xa79470);
  satteldach(w, hx, 4.85, hz, 9, 8, 1.8, 0x5f6a5c, true);
  w.box(hx, 3, hz + 3.6, 1.2, 2.2, .14, 0x50432f);
  w.box(hx + 2.4, 3.6, hz + 3.6, 1.6, 1.2, .12, 0x38525c);
  w.box(hx, 1.6, hz - 5.5, 3, .2, 4, 0x8a7250);   // Bootsanleger
 }
 // Airboat am Anleger.
 const bx = -420, bz = 34;
 w.box(bx, .1, bz, 3.2, .5, 6.4, 0x9aa39b);
 w.box(bx, .8, bz - .6, 1.6, 1, 2.4, 0x50606a);
 w.box(bx, 2.1, bz - 2.6, 2.6, 2.6, .3, 0x6d757a);
 w.box(bx, 2.1, bz - 2.8, .3, .3, .6, 0x3f484c);
 w.text('SALT MARSH', -440, 3.4, 120, 14, '#a9c4a8');
}

// ------------------------------------------------------------ Mercy Airfield
function airfield(w, rng) {
 const bahnX = -315;
 // Die Kennung '27' stand als drei Meter hohes Brett quer über der Bahn,
 // weil text() nur senkrechte Tafeln kannte. Jetzt liegt sie flach, und am
 // anderen Ende steht die Gegenrichtung.
 //
 // Hier lag zwischendurch auch ein Belag von mir — ein Fehler: die Bahn hat
 // längst einen, er wird in expanded-world.js gebaut (`box(-315,.09,315,25,
 // .15,155)`), zusammen mit ihrer Mittellinie. Ich hatte nur airfield()
 // gelesen, dort Markierungen ohne Fahrbahn gefunden und daraus geschlossen,
 // es gäbe keine. Zwei Decken auf derselben Höhe flimmern gegeneinander,
 // zwei Strichfolgen mit verschiedenem Abstand liegen sichtbar übereinander.
 // Der Belag steht dort, wo er stand.
 // Schwellenmarkierung, Randbefeuerung, Schultern.
 for (const ende of [242, 388]) {
  for (let e = -9; e <= 9; e += 3) w.box(bahnX + e, .19, ende + (ende < 300 ? 6 : -6), 1.6, .02, 12, 0xd2d0af);
 }
 for (const seite of [-1, 1]) {
  for (let z = 240; z < 392; z += 12) {
   w.box(bahnX + seite * 12.5, .28, z, .3, .5, .3, 0xd8cf9a, 0, true);
  }
  w.box(bahnX + seite * 13.5, .1, 315, 3, .16, 155, 0x6f7a6a);
 }
 w.text('27', bahnX, .19, 252, 12, '#d8d6b8', 0, true);
 w.text('09', bahnX, .19, 378, 12, '#d8d6b8', Math.PI, true);
 // Rollweg und Vorfeld.
 w.box(bahnX + 34, .1, 315, 40, .16, 120, 0x4a565a);
 w.box(bahnX + 18, .1, 300, 34, .16, 12, 0x4a565a);
 for (let z = 268; z < 366; z += 14) w.box(bahnX + 34, .19, z, 22, .02, .4, 0xc9c49a);

 // Drei Hangars mit Tonnendach-Andeutung und Toren.
 for (let k = 0; k < 3; k++) {
  const hx = bahnX + 56, hz = 272 + k * 32;
  w.box(hx, 5, hz, 30, 10, 24, 0x9aa2a0);
  satteldach(w, hx, 10.1, hz, 31, 25, 2.6, 0x77817f, true);
  w.box(hx - 15.2, 4.2, hz, .35, 8.4, 18, 0x6e7876);
  for (let u = -8; u <= 8; u += 2.2) w.box(hx - 15.4, 4.2, hz + u, .2, 8.4, .3, 0x8b9492);
  w.box(hx, 8.6, hz - 12.2, 8, 1.4, .3, 0xc7cdc6);
  w.text('HANGAR ' + (k + 1), hx, 8.6, hz - 12.4, 9, '#3d4a48', Math.PI);
 }
 // Kontrollturm.
 const tx = bahnX + 56, tz = 372;
 w.box(tx, 8, tz, 8, 16, 8, 0xa9b0ab);
 for (let y = 3; y < 15; y += 3) w.box(tx, y, tz + 4.1, 5, 1.4, .12, 0x3d5b66);
 w.box(tx, 17.4, tz, 12, 3.2, 12, 0x8f9793);
 w.box(tx, 17.4, tz, 12.6, 2.4, 12.6, 0x2f4a55);
 w.box(tx, 19.4, tz, 13, .5, 13, 0x6c7370);
 w.box(tx, 21.2, tz, .2, 3, .2, 0x8f9793);
 w.box(tx, 22.8, tz, .5, .5, .5, 0xd85a4a, 0, true);
 // Windsack, Tanklager, Terminal, Zaun.
 w.box(bahnX + 22, 2.5, 250, .16, 5, .16, 0xb0b6ae);
 w.box(bahnX + 23.6, 4.5, 250, 3, 1.1, 1.1, 0xd8823f, .2);
 for (const ox of [0, 9]) {
  w.box(bahnX + 74 + ox, 3, 250, 7, 6, 7, 0xb6bcb2);
  w.box(bahnX + 74 + ox, 6.3, 250, 7.4, 1, 7.4, 0x8d938a);
 }
 w.text('AVGAS', bahnX + 78, 7.6, 246, 8, '#d8b25a');
 // Die Abfertigung stand auf z = 400 — genau auf der Ost-West-Achse, die
 // dort mit sechzehn Metern Breite entlangläuft. 46 mal 16 Meter Gebäude
 // quer über der Fahrbahn. Fünfundzwanzig Meter nach Süden, innerhalb des
 // Zauns, ist frei.
 w.box(bahnX + 34, 3.2, 375, 46, 6.4, 16, 0xbcb9a8);
 satteldach(w, bahnX + 34, 6.5, 375, 47, 17, 2.4, 0x5e6a68, true);
 w.text('MERCY AIRFIELD', bahnX + 34, 5.6, 366.4, 22, '#e0d3a8', Math.PI);
 zaun(w, bahnX - 40, 235, bahnX + 100, 235, 2.2, 0x808780, 5);
 zaun(w, bahnX - 40, 235, bahnX - 40, 410, 2.2, 0x808780, 5);
 zaun(w, bahnX + 100, 235, bahnX + 100, 410, 2.2, 0x808780, 5);
 for (let k = 0; k < 26; k++) {
  const x = bahnX - 34 + rng() * 24, z = 240 + rng() * 165;
  w.palm(x, z, 5 + rng() * 3);
 }
}

// ------------------------------------------------------------- Isla Serena
function islaSerena(w, rng) {
 // Damm über das Wasser: Pfeiler, Geländer, Laternen.
 for (let x = 124; x < 252; x += 8) {
  for (const seite of [-1, 1]) {
   w.box(x, -1.4, 200 + seite * 4.2, 1.4, 3, 1.4, 0x7f8580);
   w.box(x, 1.35, 200 + seite * 5.1, 8, .16, .18, 0xb0b6ac);
  }
  if (x % 40 < 8) w.lamp(x, 206);
 }
 // Strand rundum, Marina, Villen, Pier, Leuchtturm.
 for (const [sx, sz, sw, sd] of [[297, 152, 125, 15], [297, 292, 125, 13], [238, 222, 13, 145], [356, 222, 11, 145]])
  w.box(sx, .07, sz, sw, .16, sd, 0x9c8a63);
 // Grünflächen zwischen Sand und Bebauung, damit die Insel nicht aus einer
 // einzigen Fläche besteht.
 for (const [gx, gz, gw, gd] of [[290, 172, 96, 22], [290, 272, 96, 22], [258, 222, 26, 68]])
  w.box(gx, .05, gz, gw, .12, gd, 0x5d7048);
 for (let z = 158; z < 290; z += 13) {w.palm(241, z, 6 + rng() * 3); w.palm(354, z, 6 + rng() * 3);}
 for (let x = 246; x < 356; x += 15) {w.palm(x, 156, 6 + rng() * 3); w.palm(x, 289, 6 + rng() * 2);}

 // Marina: Hauptsteg mit Fingerstegen und vertäuten Booten.
 //
 // Der Hauptsteg stand bei x = 250, die Fingerstege reichten bis 234, die
 // Boote lagen bei 238. Die Westküste von Isla Serena ist eine gerade Linie
 // bei x = 235 — die ganze Anlage lag an Land, und die vertäuten Boote
 // standen auf Sand und Wiese. Auf dem Luftbild ist es nicht zu übersehen,
 // sobald man einmal hinsieht. Der Steg liegt jetzt im Wasser bei x = 226,
 // über einen Landgang mit dem Ufer verbunden; die Boote schwimmen bei 214.
 // Das Hafenhaus bleibt an Land.
 const mx = 226, mz = 245;
 w.box(mx, .55, mz, 5, .3, 66, 0x9a8158);
 // Landgang vom Ufer auf den Steg.
 w.box(mx + 7.5, .55, mz, 15, .3, 4, 0x9a8158);
 for (const oz of [-2, 2]) for (let x = mx + 3; x < mx + 15; x += 4)
  w.box(x, -.3, mz + oz, .22, 1.8, .22, 0x6b5b41);
 for (let z = mz - 28; z <= mz + 28; z += 11) {
  w.box(mx - 9, .55, z, 14, .3, 2.6, 0x9a8158);
  for (const oz of [-3.4, 3.4]) {
   if (rng() < .35) continue;
   const bx2 = mx - 12, bz2 = z + oz;
   w.box(bx2, .05, bz2, 6.4, 1.1, 2.4, [0xd6d2c4, 0xc0cad0, 0xd8c9a8][Math.floor(rng() * 3)]);
   w.box(bx2 - .8, .95, bz2, 2.6, .9, 1.8, 0xa9b2b6);
   w.box(bx2 - .6, 2.6, bz2, .12, 2.6, .12, 0xc7ccc6);
  }
  w.box(mx - 16.4, .9, z, .2, .9, .2, 0x6d6357);
 }
 // Hafenhaus an Land, am Kopf des Landgangs.
 w.box(mx + 20, 1.6, mz + 12, 7, 2.4, 6, 0xb09a6f);
 satteldach(w, mx + 20, 2.9, mz + 12, 8, 7, 1.4, 0x6a7a6a, true);
 w.text('SERENA MARINA', mx + 20, 4.3, mz + 8.6, 12, '#efd9a4', Math.PI);

 // Resortvillen mit Pools, an einer Ringstraße.
 w.box(297, .06, 222, 88, .14, 6, 0x8d8877);
 for (let k = 0; k < 6; k++) {
  // Die nördliche Reihe stand auf z = 196; der Damm nach Isla Serena läuft
  // auf z = 200 mit zwölf Metern Breite, die Villen ragten also mit ihrer
  // halben Tiefe in die Fahrbahn. sim.blocked kennt nur registrierte
  // Gebäude und hat davon nichts gewusst.
  const vx = 268 + (k % 3) * 30, vz = k < 3 ? 180 : 254;
  if (w.sim.blocked({x: vx, z: vz}, 12) || aufStrasse(vx, vz, 10)) continue;
  w.box(vx, 2.6, vz, 15, 5.2, 12, 0xd8d0be);
  w.box(vx, 5.4, vz, 16.4, .5, 13.4, 0xc0b7a3);
  for (const ox of [-4.4, 0, 4.4]) w.box(vx + ox, 3.4, vz + 6.1, 3.2, 2.4, .12, 0x3d5f6b);
  w.box(vx, 5.9, vz, 8, .5, 8, 0xd8d0be);
  w.box(vx + 10, .05, vz, 5, .12, 9, 0x3f8fa0);
  w.box(vx + 10, .18, vz, 6, .1, 10, 0xcfc7b2);
  for (const [ox, oz] of [[13, -2], [13, 2]]) {
   w.box(vx + ox, .3, vz + oz, 2, .12, .8, 0xe0dcd0);
   w.box(vx + ox - .8, .5, vz + oz, .5, .5, .8, 0xe0dcd0, 0, false, 0, .5);
  }
  w.palm(vx - 10, vz + 5, 7 + rng() * 2);
 }
 // Pier mit Bar am Südufer.
 for (let z = 292; z < 316; z += 3) {
  w.box(300, .5, z, 6, .26, 2.9, 0x9a8158);
  for (const e of [-3.1, 3.1]) w.box(300 + e, -.4, z, .22, 2, .22, 0x6b5a40);
 }
 w.box(300, 1.7, 318, 9, 2.2, 7, 0xa9895e);
 satteldach(w, 300, 2.9, 318, 10, 8, 1.6, 0x71604a, true);
 // Leuchtturm an der Nordspitze.
 const lx = 352, lz = 158;
 w.box(lx, 7, lz, 5.2, 14, 5.2, 0xd8d4c6);
 for (let y = 2; y < 14; y += 3.4) w.box(lx, y, lz, 5.5, 1.2, 5.5, 0xb8564a);
 w.box(lx, 14.6, lz, 6.4, 1.2, 6.4, 0x6c7370);
 w.box(lx, 16, lz, 3.4, 2.4, 3.4, 0xf0e2ae, 0, true);
 w.box(lx, 17.6, lz, 4.4, 1, 4.4, 0x4a5350);
 w.text('ISLA SERENA', 297, 5, 150, 20, '#e6dcb8', Math.PI);
}

// ------------------------------------------------- Hafen und Industriegürtel
function harborIndustry(w, rng) {
 // Containerstapel mit Nummern, Tanklager, Gleise, Krananlage ergänzen.
 const FARBEN = [0x7c4c44, 0x3f5b63, 0x8a7444, 0x44634e, 0x74746f, 0x5a4f63];
 for (let reihe = 0; reihe < 5; reihe++) {
  for (let k = 0; k < 7; k++) {
   const x = 126 + reihe * 8.5, z = -104 + k * 13;
   const stapel = 1 + Math.floor(rng() * 3);
   for (let s = 0; s < stapel; s++) {
    const farbe = FARBEN[Math.floor(rng() * FARBEN.length)];
    w.box(x, 1.4 + s * 2.7, z, 7.4, 2.6, 11.6, farbe);
    for (let u = -5; u <= 5; u += 1.6) w.box(x + 3.75, 1.4 + s * 2.7, z + u, .14, 2.5, .16, farbe === 0x8a8a86 ? 0x74746f : 0x2f3a3e);
   }
  }
 }
 // Tanklager hinter dem Hafenbecken.
 for (let k = 0; k < 4; k++) {
  const x = 150 + (k % 2) * 22, z = 20 + Math.floor(k / 2) * 26;
  w.box(x, 5, z, 16, 10, 16, 0xb2b7ae);
  w.box(x, 10.4, z, 16.8, 1, 16.8, 0x8d938a);
  for (let y = 2.5; y < 10; y += 2.5) w.box(x, y, z, 16.4, .16, 16.4, 0x939890);
  w.box(x + 9, 1, z, 2, 1.2, 1.2, 0x7d837c);
 }
 w.text('CALDERA TANK FARM', 161, 12.4, 8, 26, '#c8d2c0');
 // Gleisanlage entlang der Kaikante.
 for (const gz of [-6, -2]) {
  w.box(138, .09, gz, 52, .1, 1.4, 0x5a5348);
  for (const e of [-.55, .55]) w.box(138, .18, gz + e, 52, .12, .16, 0x8e938c);
  for (let x = 114; x < 164; x += 2.2) w.box(x, .12, gz, .3, .14, 2.4, 0x4e463a);
 }
 // Portalkran über den Gleisen.
 for (const ox of [-14, 14]) {
  w.box(138 + ox, 9, -18, 1.2, 18, 1.2, 0xc08a52);
  w.box(138 + ox, 9, 6, 1.2, 18, 1.2, 0xc08a52);
 }
 w.box(138, 18.6, -6, 32, 1.6, 3.4, 0xc08a52);
 w.box(132, 16.4, -6, 4, 3, 4, 0x4e5a5e);
 // Lagerhallen mit Toren und Rampen.
 for (let k = 0; k < 3; k++) {
  const x = 124 + k * 0, z = 62 + k * 34;
  w.box(x + 14, 5, z, 34, 10, 22, 0x8e9490);
  satteldach(w, x + 14, 10.1, z, 35, 23, 2.4, 0x6a726f, true);
  for (const tor of [-9, 0, 9]) {
   w.box(x - 3.1, 2.4, z + tor, .3, 4.8, 6, 0x54605e);
   w.box(x - 4.4, .6, z + tor, 2.6, 1.2, 6.4, 0x7d837c);
  }
  w.text('PIER ' + (k + 4), x + 14, 8.8, z - 11.2, 10, '#cfd8cb', Math.PI);
 }
}

// -------------------------------------------------- Baulücken in der Innenstadt
function stadtLuecken(w, rng) {
 // Zwischen den Blöcken lagen leere Betonflächen. Parkplätze, kleine Plätze
 // und eingezäunte Brachen füllen sie.
 const felder = [];
 for (const x of [-310, -250, -190, -130]) for (const z of [-130, -70, -10, 50]) felder.push([x, z]);
 for (const [i, [fx, fz]] of felder.entries()) {
  if (w.sim.blocked({x: fx, z: fz}, 16)) continue;
  const art = i % 3;
  if (art === 0) {                                   // Parkplatz mit Markierung
   w.box(fx, .05, fz, 34, .12, 30, 0x4d565a);
   for (let u = -15; u < 15; u += 2.8) {
    w.box(fx + u, .13, fz - 7, .16, .02, 11, 0xc5c0a4);
    w.box(fx + u, .13, fz + 7, .16, .02, 11, 0xc5c0a4);
   }
   w.box(fx, .13, fz, 33, .02, .2, 0xc5c0a4);
   for (const e of [-16, 16]) w.box(fx + e, .5, fz, .3, 1, 30, 0x8b9089);
   w.box(fx - 15, 1.4, fz - 14, 1.4, 2.8, 1.4, 0x5d6a6c);
   w.box(fx - 15, 2.9, fz - 14, 2, .5, 2, 0x8a9490);
  } else if (art === 1) {                            // Platz mit Brunnen
   w.box(fx, .06, fz, 32, .14, 28, 0x9a9382);
   for (let u = -14; u <= 14; u += 3.5) w.box(fx + u, .15, fz, .18, .04, 27, 0x8a8474);
   w.box(fx, .35, fz, 7, .7, 7, 0x8d8a7c);
   w.box(fx, .55, fz, 6, .5, 6, 0x3f6f7a);
   w.box(fx, 1.2, fz, 1, 2, 1, 0x8d8a7c);
   w.box(fx, 2.3, fz, 2.2, .4, 2.2, 0x8d8a7c);
   for (const [ox, oz] of [[-10, -8], [10, -8], [-10, 8], [10, 8]]) laubbaum(w, fx + ox, fz + oz, 7);
   for (const oz of [-11, 11]) for (const ox of [-6, 0, 6]) {
    w.box(fx + ox, .42, fz + oz, 2.1, .1, .55, 0x7d6247);
    w.box(fx + ox, .72, fz + oz + (oz < 0 ? -.24 : .24), 2.1, .55, .1, 0x7d6247);
   }
  } else {                                           // Brache mit Bauzaun
   w.box(fx, .04, fz, 32, .1, 28, 0x7c7466);
   zaun(w, fx - 16, fz - 14, fx + 16, fz - 14, 2, 0x8a9089, 3);
   zaun(w, fx - 16, fz + 14, fx + 16, fz + 14, 2, 0x8a9089, 3);
   zaun(w, fx - 16, fz - 14, fx - 16, fz + 14, 2, 0x8a9089, 3);
   zaun(w, fx + 16, fz - 14, fx + 16, fz + 14, 2, 0x8a9089, 3);
   for (let k = 0; k < 7; k++) {
    const x = fx + (rng() - .5) * 26, z = fz + (rng() - .5) * 22;
    if (rng() < .5) w.box(x, .6, z, 2.6, 1.2, 2.2, 0x86794f, rng() * 3);
    else w.box(x, .35, z, 3.4, .7, 1.6, 0x6d6a5e, rng() * 3, false, .1, 0);
   }
   w.box(fx + 12, 1.4, fz - 10, 2.6, 2.8, 2.4, 0x9a7a45);
  }
 }
}


// ------------------------------------------- Flächen südlich und nördlich
// Zwischen Stadt, Flugfeld und Sümpfen lagen leere Grünflächen von mehreren
// hundert Metern Kantenlänge. Das ist der größte Teil der Karte, den man
// im Vorbeifahren sieht.
function suedFlaechen(w, rng) {
 // Sportpark: Rasen, Laufbahn, Tribüne, Flutlicht.
 const sx = -268, sz = 252;
 w.box(sx, .05, sz, 76, .12, 58, 0x5f7a44);
 w.box(sx, .07, sz, 62, .14, 40, 0x54703c);
 for (const [ox, oz, bw, bd] of [[0, -20, 62, .25], [0, 20, 62, .25], [-31, 0, .25, 40], [31, 0, .25, 40]])
  w.box(sx + ox, .16, sz + oz, bw, .04, bd, 0xd8d4be);
 for (const seite of [-1, 1]) {
  w.box(sx + seite * 29, 1.2, sz, .16, 2.4, 7.4, 0xe0dcd0);
  w.box(sx + seite * 29, 2.4, sz, .16, .16, 7.4, 0xe0dcd0);
 }
 for (let r = 0; r < 4; r++) w.box(sx, .3 + r * .45, sz - 25 - r * 1.4, 42, .45, 1.4, 0x9aa39b);
 for (const [ox, oz] of [[-36, -26], [36, -26], [-36, 26], [36, 26]]) {
  w.box(sx + ox, 7, sz + oz, .5, 14, .5, 0x6f7772);
  w.box(sx + ox, 14.4, sz + oz, 3.6, 1, 1.2, 0x4a5250);
  for (const e of [-1.2, 0, 1.2]) w.box(sx + ox + e, 14.4, sz + oz + .7, 1, .8, .12, 0xf0e8c4, 0, true);
 }
 // Basketballfeld daneben.
 w.box(sx + 48, .06, sz - 16, 18, .14, 26, 0x5c6f74);
 for (const oz of [-11, 11]) {
  w.box(sx + 48, 2, sz - 16 + oz, .16, 4, .16, 0x49535a);
  w.box(sx + 48, 3.4, sz - 16 + oz + (oz < 0 ? .5 : -.5), 2.2, 1.4, .12, 0xd5d2bd);
 }
 zaun(w, sx + 38, sz - 30, sx + 58, sz - 30, 3, 0x7f867f, 3);
 zaun(w, sx + 38, sz - 2, sx + 58, sz - 2, 3, 0x7f867f, 3);

 // Trailer Park: Reihen von Wohnwagen mit Vordach, Auto und Propantank.
 const tx = -178, tz = 258;
 w.box(tx, .04, tz, 70, .1, 62, 0x7d7a63);
 for (let reihe = 0; reihe < 3; reihe++) {
  w.box(tx, .06, tz - 22 + reihe * 22, 68, .12, 5, 0x5f5a4c);
  for (let k = 0; k < 5; k++) {
   const x = tx - 28 + k * 14, z = tz - 22 + reihe * 22 + 9;
   const farbe = [0xc4bda8, 0xb0b8ae, 0xc8b79a, 0xa9b4bc][k % 4];
   w.box(x, 1.5, z, 10, 2.8, 4.4, farbe);
   w.box(x, 3, z, 10.4, .3, 4.8, 0x8d938c);
   w.box(x, .5, z, 9.4, 1, 4, 0x6e6a5e);
   for (const ox of [-3.6, 3.6]) w.box(x + ox, .3, z, .8, .6, 3.6, 0x4a4a44);
   w.box(x, 3.05, z - 3.4, 9, .12, 3, farbe);
   for (const ox of [-3.8, 3.8]) w.box(x + ox, 1.6, z - 4.8, .1, 3, .1, 0x7f867f);
   w.box(x - 2, 1.2, z - 2.3, 1, 2, .14, 0x4a3a2c);
   w.box(x + 2.6, 1.9, z - 2.3, 1.8, 1, .12, 0x3a545e);
   w.box(x + 5.6, .5, z + 1, .8, 1, 1.6, 0xd8d2c0);
   if (rng() < .5) w.box(x, .05, z + 5, 6, .1, 3.6, 0x6a675c);
  }
 }
 w.text('LOW TIDE TRAILER PARK', tx, 4.6, tz - 32, 24, '#e4d3a0', Math.PI);

 // Autokino: Leinwand, Projektorhaus, Lautsprecherpfosten, Wälle.
 const ax = -268, az = 344;
 w.box(ax, .04, az, 80, .1, 62, 0x5a564a);
 w.box(ax, 9, az - 28, 40, 18, 1.2, 0xd8d6c8);
 for (const ox of [-19, 19]) w.box(ax + ox, 9, az - 27, 1.6, 18, 2.4, 0x6d7472);
 for (let r = 0; r < 5; r++) {
  const z = az - 18 + r * 9;
  w.box(ax, .25, z, 74, .5, 3.4, 0x6d6a5a);
  for (let k = -6; k <= 6; k++) w.box(ax + k * 6, .9, z + 2.4, .12, 1.4, .12, 0x53595a);
 }
 w.box(ax + 30, 2, az + 26, 8, 4, 6, 0xa89a78);
 satteldach(w, ax + 30, 4.1, az + 26, 9, 7, 1.4, 0x6a6250, true);
 w.text('SUNSET DRIVE-IN', ax, 12, az - 28.8, 26, '#2f3a3c', Math.PI);

 // Schrottplatz: Stapel, Kran, Baracke, Zaun mit Tor.
 const kx = -160, kz = 344;
 w.box(kx, .04, kz, 56, .1, 48, 0x6b6553);
 for (let k = 0; k < 22; k++) {
  const x = kx - 22 + rng() * 44, z = kz - 18 + rng() * 36, h = 1 + Math.floor(rng() * 3);
  for (let s = 0; s < h; s++)
   w.box(x, .6 + s * 1.15, z, 4.2, 1.1, 1.9, [0x7a4c46, 0x4a5c63, 0x6f6a4a, 0x5a5f5c][Math.floor(rng() * 4)], rng() * 3, false, 0, (rng() - .5) * .12);
 }
 w.box(kx + 20, 6, kz + 14, 1.2, 12, 1.2, 0xb08040);
 w.box(kx + 14, 11.4, kz + 14, 13, 1, 1, 0xb08040);
 w.box(kx + 8, 9, kz + 14, .12, 4, .12, 0x3a4144);
 w.box(kx + 8, 6.6, kz + 14, 1.8, .9, 1.8, 0x4a5250);
 w.box(kx - 20, 1.6, kz + 18, 10, 3.2, 6, 0x8a8f88);
 satteldach(w, kx - 20, 3.3, kz + 18, 11, 7, 1.2, 0x5f6663, true);
 for (const [x1, z1, x2, z2] of [[kx - 28, kz - 24, kx + 28, kz - 24], [kx - 28, kz + 24, kx + 28, kz + 24], [kx - 28, kz - 24, kx - 28, kz + 24], [kx + 28, kz - 24, kx + 28, kz + 24]])
  zaun(w, x1, z1, x2, z2, 2.6, 0x77807a, 3);
 w.text('CALDERA SALVAGE', kx, 4.4, kz - 24.6, 18, '#d8c48c', Math.PI);

 // Driving Range mit Abschlagshütte und Fangnetz.
 const dx = -58, dz = 300;
 w.box(dx, .05, dz, 64, .12, 90, 0x5f7d44);
 for (let k = 0; k < 8; k++) {
  const x = dx - 24 + k * 7;
  w.box(x, .16, dz - 40, 3.4, .1, 3.4, 0x76914f);
  w.box(x, 2.6, dz - 44, 5, .16, 6, 0x7a6a4e);
  for (const ox of [-2.2, 2.2]) w.box(x + ox, 1.3, dz - 46.6, .14, 2.6, .14, 0x6b5c44);
 }
 for (let z = dz - 20; z < dz + 44; z += 22) {
  w.box(dx + (z % 44 ? -14 : 12), .2, z, 5, .16, 5, 0x86a35a);
  w.box(dx + (z % 44 ? -14 : 12), 1.2, z, .07, 2.4, .07, 0xdedbcb);
  w.box(dx + (z % 44 ? -13.4 : 12.6), 2.2, z, 1.1, .6, .05, 0xd06a4c);
 }
 for (const ox of [-32, 32]) for (let z = dz - 44; z < dz + 46; z += 10) {
  w.box(dx + ox, 6, z, .18, 12, .18, 0x5f6663);
  w.box(dx + ox, 6, z + 5, .06, 11, 10, 0x38443f);
 }
 w.text('MERCY GREENS', dx, 4.2, dz - 48, 20, '#dfe6c4', Math.PI);

 // Gewerbehallen an der Südstraße.
 for (let k = 0; k < 3; k++) {
  const x = 20 + k * 0, z = 250 + k * 46;
  w.box(x, 4, z, 44, 8, 26, 0x8f9691);
  satteldach(w, x, 8.1, z, 45, 27, 2.2, 0x6a716e, true);
  for (const tor of [-12, 0, 12]) {
   w.box(x - 22.2, 2.2, z + tor, .3, 4.4, 5.4, 0x54605e);
   w.box(x - 24, .5, z + tor, 3.4, 1, 5.8, 0x7d837c);
  }
  w.box(x + 22.4, 3.4, z, .2, 3, 12, 0x3d5560);
  w.text(['SOLVARA FREIGHT', 'PELICAN FOODS', 'TIDEWORKS'][k], x, 6.6, z - 13.2, 16, '#d2dacf', Math.PI);
  w.box(x - 32, .05, z, 18, .12, 30, 0x4d565a);
  for (let u = -13; u < 13; u += 2.8) w.box(x - 32, .13, z + u, 17, .02, .16, 0xc5c0a4);
 }
}

function nordFlaechen(w, rng) {
 // Orangenhain in Reihen.
 const ox0 = -250, oz0 = -250;
 w.box(ox0, .04, oz0, 96, .1, 74, 0x6d7c48);
 for (let r = 0; r < 8; r++) for (let k = 0; k < 12; k++) {
  const x = ox0 - 44 + k * 8, z = oz0 - 32 + r * 9.5;
  if (w.sim.blocked({x, z}, 3) || aufStrasse(x, z, 7)) continue;
  laubbaum(w, x, z, 4.6 + rng() * 1.4, 0x466b3f);
 }
 zaun(w, ox0 - 48, oz0 - 37, ox0 + 48, oz0 - 37, 1.3, 0x8a7a5e, 5);
 zaun(w, ox0 - 48, oz0 + 37, ox0 + 48, oz0 + 37, 1.3, 0x8a7a5e, 5);
 w.text('GROVE 12', ox0 + 30, 3, oz0 - 38, 12, '#dfd0a0', Math.PI);

 // Friedhof mit Kapelle und Hecke.
 const fx = -184, fz = -250;
 w.box(fx, .05, fz, 52, .12, 44, 0x5f7549);
 for (let r = 0; r < 6; r++) for (let k = 0; k < 11; k++) {
  const x = fx - 22 + k * 4.4, z = fz - 16 + r * 6.4;
  w.box(x, .45, z, 1, .9, .28, 0x9a9a92);
  w.box(x, .95, z, 1, .22, .34, 0x8d8d86);
 }
 // Das Vereinsheim lag auf fz + 20 = -230 und damit im Nordring (z = -228,
 // sechzehn Meter breit). Jetzt auf der abgewandten Seite des Feldes.
 w.box(fx, 2.6, fz - 20, 10, 5.2, 8, 0xc0b7a3);
 satteldach(w, fx, 5.3, fz - 20, 11, 9, 2.6, 0x5f6663, true);
 w.box(fx, 8.4, fz - 20, .3, 2.4, .3, 0x8d8d86);
 w.box(fx, 8.4, fz - 20, 1.2, .3, .3, 0x8d8d86);
 for (const [x1, z1, x2, z2] of [[fx - 26, fz - 22, fx + 26, fz - 22], [fx - 26, fz + 22, fx + 26, fz + 22], [fx - 26, fz - 22, fx - 26, fz + 22], [fx + 26, fz - 22, fx + 26, fz + 22]]) {
  const laenge = Math.hypot(x2 - x1, z2 - z1);
  w.box((x1 + x2) / 2, .8, (z1 + z2) / 2, Math.abs(x2 - x1) || 1.4, 1.6, Math.abs(z2 - z1) || 1.4, 0x3f5c3c);
 }
 w.text('MERCY REST', fx, 3.2, fz - 23, 14, '#d5dcc8', Math.PI);

 // Solarfeld im Nordwesten. Am ursprünglichen Platz lag es mitten in einer
 // Wohnstraße der Vororte.
 const px = -280, pz = -400;
 w.box(px, .04, pz, 70, .1, 50, 0x6b6a54);
 for (let r = 0; r < 5; r++) for (let k = 0; k < 9; k++) {
  const x = px - 32 + k * 8, z = pz - 20 + r * 10;
  if (aufStrasse(x, z, 6)) continue;
  for (const e of [-2.6, 2.6]) w.box(x + e, .9, z, .14, 1.8, .14, 0x777f7b);
  w.box(x, 1.7, z, 7, .14, 3.4, 0x2b3a55, 0, false, .42, 0);
 }
 zaun(w, px - 36, pz - 26, px + 36, pz - 26, 2.2, 0x7f867f, 4);
 zaun(w, px - 36, pz + 26, px + 36, pz + 26, 2.2, 0x7f867f, 4);
}

// ------------------------------------------------------ Die Keys im Osten
// Östlich der Küste lagen dreißig Kartenzellen blankes Wasser: eine Insel,
// ein Damm, sonst nichts. Jetzt eine Kette aus fünf Keys und einer Sandbank,
// drei davon über den Keys Highway erreichbar, zwei nur mit dem Boot. Das
// Layout ist eigenes; Vorbild ist die Bauweise einer Küstenkette — Damm auf
// Pfeilern, Mangrovensaum, Stelzenhäuser, Leuchtfeuer.
function key(name){return INSELN.find(r => r.name === name);}

// Mangrove: Stelzwurzeln unter einer flachen, breiten Krone. Als eine Kiste
// sah der Saum aus wie eine Hecke.
function mangrove(w, x, z, hoehe, rng) {
 const y = groundAt(x, z);
 for (let k = 0; k < 5; k++) {
  const a = k / 5 * Math.PI * 2, r = hoehe * .22;
  w.box(x + Math.cos(a) * r, y + hoehe * .18, z + Math.sin(a) * r,
   .09, hoehe * .38, .09, 0x4b4030, 0, false, Math.sin(a) * .3, -Math.cos(a) * .3);
 }
 w.box(x, y + hoehe * .36, z, hoehe * .1, hoehe * .3, hoehe * .1, 0x54452f);
 // Die Krone bestand aus drei flachen Kisten von je einem Sechstel der Höhe.
 // Aus der Nähe las sich der Sumpf damit als Lagerplatz für grüne Paletten
 // auf Stelzen — hunderte davon, und es fällt in jedem Bild sofort auf.
 // Sie geht jetzt über dasselbe Laubwerk wie jeder andere Baum: gekreuzte
 // Flächen mit Alphakarte, ein Instanzennetz für die ganze Karte. Die Art
 // heißt 'mangrove', damit die Prüfung „kein Baum steht im Wasser" sie
 // auslässt — ein Mangrovenwald steht genau dort.
 w.baum(x + (rng() - .5) * hoehe * .12, z + (rng() - .5) * hoehe * .12,
  hoehe * 1.2, 'mangrove', [0x33562f, 0x3c6234, 0x2c4a29][Math.floor(rng() * 3)]);
}

// Steg auf Pfählen, wie ihn jede dieser Inseln zum Wasser hat.
function steg(w, x1, z1, x2, z2, breite = 2.4) {
 const laenge = Math.hypot(x2 - x1, z2 - z1);
 const dx = (x2 - x1) / laenge, dz = (z2 - z1) / laenge, dreh = Math.atan2(dx, dz);
 w.box((x1 + x2) / 2, .62, (z1 + z2) / 2, breite, .16, laenge, 0x8a7856, dreh);
 for (let t = 0; t <= laenge; t += 3.2) {
  for (const seite of [-1, 1]) {
   const px = x1 + dx * t - dz * seite * breite * .42, pz = z1 + dz * t + dx * seite * breite * .42;
   w.box(px, -.4, pz, .22, 2.2, .22, 0x6b5b41);
   w.box(px, 1.1, pz, .12, .8, .12, 0x7d6c4e);
  }
  if (t > 0) w.box(x1 + dx * (t - 1.6), 1.42, z1 + dz * (t - 1.6), breite + .2, .08, .1, 0x8f7d5c, dreh);
 }
}

// Stelzenhaus. Auf einer Sandbank baut niemand ebenerdig.
function stelzenhaus(w, x, z, breite, tiefe, farbe, dach, rng) {
 const boden = 2.1;
 for (const ox of [-1, 1]) for (const oz of [-1, 1])
  w.box(x + ox * breite * .42, boden / 2, z + oz * tiefe * .42, .26, boden, .26, 0x6b5b41);
 w.box(x, boden + .12, z, breite + .6, .24, tiefe + .6, 0x8a7856);
 w.box(x, boden + 1.6, z, breite, 2.8, tiefe, farbe);
 satteldach(w, x, boden + 3.0, z, breite + .9, tiefe + .9, 1.4, dach, rng() < .5);
 // Veranda mit Geländer zur Wasserseite.
 w.box(x, boden + .3, z + tiefe * .62, breite * .9, .18, 1.8, 0x8a7856);
 for (const ox of [-.4, .4]) w.box(x + ox * breite, boden + .8, z + tiefe * .62, .12, 1, .12, farbe);
 w.box(x, boden + 1.2, z + tiefe * .78, breite * .9, .1, .12, 0x9a8865);
 // Fenster und Tür.
 for (const ox of [-.28, .28]) w.box(x + ox * breite, boden + 1.9, z + tiefe / 2 + .06, breite * .2, 1.1, .1, 0x35505c);
 w.box(x, boden + 1.35, z + tiefe / 2 + .06, 1, 2.1, .12, 0x4b3a2c);
 // Treppe ins Wasser.
 for (let k = 0; k < 5; k++)
  w.box(x + breite * .5 + .6, boden - .1 - k * .42, z + tiefe * .62, 1.2, .12, .8, 0x7d6c4e);
}

function keysHighway(w, rng) {
 const damm = DAEMME[1];
 const z = (damm.z1 + damm.z2) / 2;
 // Fahrbahn, Mittelstreifen, Randsteine.
 w.box((damm.x1 + damm.x2) / 2, .05, z, damm.x2 - damm.x1, .12, 13.6, 0x3c4043);
 for (let x = damm.x1 + 4; x < damm.x2; x += 9) w.box(x, .12, z, 4, .03, .18, 0xc4b98e);
 for (const seite of [-1, 1]) {
  w.box((damm.x1 + damm.x2) / 2, .22, z + seite * 7.4, damm.x2 - damm.x1, .44, 1.1, 0x8e8b7f);
 }
 // Pfeiler und Geländer nur dort, wo der Damm über Wasser führt — über den
 // Inseln steht er auf Land, da wären Pfeiler falsch.
 for (let x = damm.x1 + 3; x < damm.x2; x += 7.5) {
  if (!waterAt(x, z + 12) && !waterAt(x, z - 12)) continue;
  for (const seite of [-1, 1]) {
   w.box(x, -1.6, z + seite * 7.2, 1.5, 3.4, 1.5, 0x7f8580);
   w.box(x, 1.15, z + seite * 8.1, 7.5, .14, .16, 0xb0b6ac);
   w.box(x, .72, z + seite * 8.1, .14, .9, .14, 0x9aa09a);
  }
  if ((x - damm.x1) % 45 < 7.5) {w.lamp(x, z + 8.6); w.lamp(x, z - 8.6);}
 }
 w.text('KEYS HIGHWAY', 132, 4.2, z - 10, 16, '#e6d6a8', Math.PI / 2);
}

function inselkette(w, rng) {
 keysHighway(w, rng);
 const damm = DAEMME[1], strasse = (damm.z1 + damm.z2) / 2;

 // --- Pelican Key: Fischerdorf auf Stelzen.
 const p = key('Pelican Key');
 w.box((p.x1 + p.x2) / 2, .06, (p.z1 + p.z2) / 2, p.x2 - p.x1, .14, p.z2 - p.z1, 0x9c8a63);
 w.box((p.x1 + p.x2) / 2, .09, (p.z1 + p.z2) / 2 + 14, (p.x2 - p.x1) * .7, .1, 16, 0x5f7048);
 for (let k = 0; k < 4; k++)
  stelzenhaus(w, p.x1 + 10 + k * 12, p.z1 + 8, 8, 7, [0xc9b89a, 0xa8bcb4, 0xd0bca0, 0xb4a894][k], [0x7a6a55, 0x5f6b72][k % 2], rng);
 steg(w, p.x1 + 16, p.z1 + 2, p.x1 + 16, p.z1 - 16);
 steg(w, p.x2 - 12, p.z2 - 4, p.x2 + 14, p.z2 - 4);
 for (let k = 0; k < 26; k++) {
  const x = p.x1 + rng() * (p.x2 - p.x1), z = p.z1 + rng() * (p.z2 - p.z1);
  if (Math.abs(z - strasse) < 12) continue;
  if (rng() < .55) w.palm(x, z, 6 + rng() * 4); else mangrove(w, x, z, 3.4 + rng() * 2, rng);
 }
 // Reusen, Netze, Bojen am Ufer.
 for (let k = 0; k < 10; k++) {
  const x = p.x1 + 4 + rng() * (p.x2 - p.x1 - 8), z = p.z2 - 3 - rng() * 5;
  w.box(x, .5, z, 1.1, .8, .9, 0x6f6247);
  w.box(x, .95, z, 1.2, .1, 1, 0x8a7f60);
 }
 w.text('PELICAN KEY', (p.x1 + p.x2) / 2, 3.4, p.z1 - 3, 15, '#e8dcbc');

 // --- Halcyon Key: Marina, Tankstelle am Wasser, Barackenreihe.
 const h = key('Halcyon Key');
 w.box((h.x1 + h.x2) / 2, .06, (h.z1 + h.z2) / 2, h.x2 - h.x1, .14, h.z2 - h.z1, 0x9c8a63);
 w.box((h.x1 + h.x2) / 2, .09, (h.z1 + h.z2) / 2 - 12, (h.x2 - h.x1) * .8, .1, 18, 0x5f7048);
 for (let k = 0; k < 3; k++) steg(w, h.x1 + 8 + k * 16, h.z2 - 2, h.x1 + 8 + k * 16, h.z2 + 20);
 w.box(h.x1 + 12, 1.8, h.z1 + 10, 14, 3.6, 9, 0xb9ae96);
 satteldach(w, h.x1 + 12, 3.6, h.z1 + 10, 15, 10, 1.8, 0x6b6f68, true);
 w.text('HALCYON MARINE', h.x1 + 12, 2.7, h.z1 + 15.2, 13, '#dfe6d6');
 // Zapfsäulen am Steg.
 for (const ox of [-1.6, 1.6]) {
  w.box(h.x1 + 24 + ox, 1, h.z2 + 4, .8, 2, .7, 0xc45f4a);
  w.box(h.x1 + 24 + ox, 1.9, h.z2 + 4, .5, .3, .5, 0x2c3238);
 }
 for (let k = 0; k < 22; k++) {
  const x = h.x1 + rng() * (h.x2 - h.x1), z = h.z1 + rng() * (h.z2 - h.z1);
  if (Math.abs(z - strasse) < 12) continue;
  if (rng() < .5) w.palm(x, z, 6 + rng() * 3.5); else mangrove(w, x, z, 3 + rng() * 2, rng);
 }
 w.text('HALCYON KEY', (h.x1 + h.x2) / 2, 3.4, h.z1 - 3, 15, '#e8dcbc');

 // --- Sable Key: Leuchtturm am Ende der Straße.
 const s = key('Sable Key');
 w.box((s.x1 + s.x2) / 2, .06, (s.z1 + s.z2) / 2, s.x2 - s.x1, .14, s.z2 - s.z1, 0x9c8a63);
 w.box((s.x1 + s.x2) / 2, .09, (s.z1 + s.z2) / 2 + 10, (s.x2 - s.x1) * .75, .1, 20, 0x5f7048);
 const lx = s.x2 - 14, lz = s.z2 - 12;
 for (let k = 0; k < 7; k++) w.box(lx, 2 + k * 3.4, lz, 5.2 - k * .42, 3.4, 5.2 - k * .42, k % 2 ? 0xd8d2c4 : 0xb44a3f);
 w.box(lx, 25.6, lz, 3.4, 1.6, 3.4, 0x2f3840);
 w.box(lx, 26.6, lz, 2.4, .8, 2.4, 0xf2e2a8, 0, true);
 w.box(lx, 27.4, lz, 1.4, 1, 1.4, 0x3a444c);
 w.box(lx - 6, 1.6, lz + 2, 7, 3.2, 6, 0xc6bda8);
 satteldach(w, lx - 6, 3.2, lz + 2, 8, 7, 1.5, 0x6b6f68);
 zaun(w, s.x1 + 6, s.z2 - 4, s.x2 - 6, s.z2 - 4, 1.1, 0x9a8f78, 3);
 for (let k = 0; k < 20; k++) {
  const x = s.x1 + rng() * (s.x2 - s.x1), z = s.z1 + rng() * (s.z2 - s.z1);
  if (Math.abs(z - strasse) < 12 || Math.hypot(x - lx, z - lz) < 12) continue;
  if (rng() < .45) w.palm(x, z, 5 + rng() * 4); else mangrove(w, x, z, 3 + rng() * 2.4, rng);
 }
 w.text('SABLE KEY', (s.x1 + s.x2) / 2, 3.4, s.z1 - 3, 14, '#e8dcbc');

 // --- Windward Key: nur mit dem Boot. Wrack am Strand, Hütte, Feuer.
 const wk = key('Windward Key');
 w.box((wk.x1 + wk.x2) / 2, .06, (wk.z1 + wk.z2) / 2, wk.x2 - wk.x1, .14, wk.z2 - wk.z1, 0x9c8a63);
 w.box((wk.x1 + wk.x2) / 2, .09, (wk.z1 + wk.z2) / 2, (wk.x2 - wk.x1) * .55, .1, (wk.z2 - wk.z1) * .5, 0x5f7048);
 // Gestrandeter Kutter, zur Seite gekippt.
 const kx = wk.x1 + 9, kz = wk.z2 - 8;
 w.box(kx, 1.4, kz, 4.4, 2.6, 12, 0x6d7a72, .35, false, 0, .42);
 w.box(kx + 1, 3.4, kz + 2, 2.6, 2, 3.4, 0x9aa398, .35, false, 0, .42);
 w.box(kx + 2.6, 5.6, kz - 3, .3, 6, .3, 0x8a7d62, 0, false, 0, .5);
 stelzenhaus(w, wk.x2 - 12, wk.z1 + 12, 6, 6, 0xbcae95, 0x6a5c4a, rng);
 steg(w, wk.x2 - 12, wk.z1 + 8, wk.x2 - 12, wk.z1 - 12);
 for (let k = 0; k < 18; k++) {
  const x = wk.x1 + rng() * (wk.x2 - wk.x1), z = wk.z1 + rng() * (wk.z2 - wk.z1);
  if (rng() < .5) w.palm(x, z, 5 + rng() * 4); else mangrove(w, x, z, 3 + rng() * 2, rng);
 }
 w.text('WINDWARD KEY', (wk.x1 + wk.x2) / 2, 3.2, wk.z1 - 3, 13, '#e8dcbc');

 // --- Bone Key: Mangroveninsel mit Bake, sonst nichts. Nicht jede Insel
 // muss bebaut sein; leere Inseln machen die bebauten glaubwürdig.
 const b = key('Bone Key');
 w.box((b.x1 + b.x2) / 2, .05, (b.z1 + b.z2) / 2, b.x2 - b.x1, .12, b.z2 - b.z1, 0x8e8560);
 w.box((b.x1 + b.x2) / 2, .08, (b.z1 + b.z2) / 2, (b.x2 - b.x1) * .6, .1, (b.z2 - b.z1) * .6, 0x4f6440);
 for (let k = 0; k < 34; k++) {
  const x = b.x1 + rng() * (b.x2 - b.x1), z = b.z1 + rng() * (b.z2 - b.z1);
  mangrove(w, x, z, 2.6 + rng() * 2.6, rng);
 }
 const bx = (b.x1 + b.x2) / 2, bz = b.z1 + 6;
 for (let k = 0; k < 4; k++) w.box(bx, 1.4 + k * 2.6, bz, 1.6 - k * .22, 2.6, 1.6 - k * .22, k % 2 ? 0xd6d0c2 : 0x3c4650);
 w.box(bx, 12, bz, 1, .7, 1, 0xf0c96e, 0, true);

 // --- Anchor Bank: Sandbank knapp über Wasser, ein Wrackrest, Möwenposten.
 const a = key('Anchor Bank');
 w.box((a.x1 + a.x2) / 2, .02, (a.z1 + a.z2) / 2, a.x2 - a.x1, .08, a.z2 - a.z1, 0xa89a72);
 w.box((a.x1 + a.x2) / 2 + 4, .28, (a.z1 + a.z2) / 2, 6, .5, 2.6, 0x6b6152, .6);
 for (let k = 0; k < 5; k++) {
  const x = a.x1 + 5 + rng() * (a.x2 - a.x1 - 10), z = a.z1 + 4 + rng() * (a.z2 - a.z1 - 8);
  w.box(x, .5, z, .16, 1, .16, 0x6b5b41);
 }

 // --- Zwei Bojenreihen als Fahrrinne zwischen Küste und Insel.
 for (let z = 120; z < 380; z += 26) for (const x of [176, 214]) {
  if (!waterAt(x, z)) continue;
  w.box(x, .3, z, .7, 1.5, .7, x < 200 ? 0xc4553f : 0x2f5f8a);
  w.box(x, 1.2, z, .3, .5, .3, 0x2c3238);
 }
}

// ------------------------------------------------------- Ränder der Karte
// tools/abdeckung.mjs zählt die Bauteile je 100-Meter-Zelle. Zehn Landzellen
// waren praktisch leer: der Nordrand über den Vororten, ein Streifen westlich
// des Nationalparks und die Südwestecke hinter dem Sumpf. Wer dort hinfuhr,
// stand auf einer grauen Platte. Sie bekommen keine Siedlungen — dort gehört
// nichts hin — aber Gelände, an dem man sich orientieren kann.
function randgebiete(w, rng) {
 // Freileitung quer über den Norden. Masten sind das, was leere Landschaft
 // maßstäblich macht: man sieht an ihnen, wie weit die nächste noch weg ist.
 const mastZ = -470;
 let vorher = null;
 for (let x = -300; x <= 80; x += 62) {
  const y = groundAt(x, mastZ);
  for (const seite of [-1, 1]) {
   w.box(x + seite * 2.6, y + 9, mastZ, .5, 18, .5, 0x6d7176);
   w.box(x + seite * 1.3, y + 18.6, mastZ, .38, 4.4, .38, 0x6d7176);
  }
  for (const h of [7, 12, 17]) w.box(x, y + h, mastZ, 6.2, .34, .34, 0x6d7176);
  w.box(x, y + 20.6, mastZ, 3.2, .3, .3, 0x6d7176);
  for (const h of [8.2, 13.2, 18.2]) w.box(x, y + h, mastZ, .9, 1.3, .22, 0x2c3033);
  // Durchhängende Leitung in drei Segmenten je Feld.
  if (vorher !== null) {
   const spanne = x - vorher;
   for (const versatz of [-2.6, 0, 2.6]) for (let k = 0; k < 3; k++) {
    const t = (k + .5) / 3, mx = vorher + spanne * t;
    const durchhang = Math.sin(t * Math.PI) * 2.1;
    w.box(mx, groundAt(mx, mastZ) + 18.2 - durchhang, mastZ + versatz,
     spanne / 3, .1, .1, 0x35393c, 0, false, 0, (k - 1) * .09);
   }
  }
  vorher = x;
 }
 // Trockenes Buschland darunter. Erster Versuch: flache helle Platten als
 // Fels und Gras — die lagen wie weggeworfene Matratzen auf der Wiese.
 // Fels ist jetzt höher als breit, Gras ist niedrig und in der Farbe des
 // Bodens, und die Kiefern tragen den Maßstab.
 for (let i = 0; i < 520; i++) {
  const x = -320 + rng() * 420, z = -540 + rng() * 105;
  if (aufStrasse(x, z, 9) || w.sim.blocked({x, z}, 3)) continue;
  const y = groundAt(x, z), r = rng();
  if (r < .44) {
   // Büschel aus zwei versetzten niedrigen Kissen.
   const t = [0x6a7546, 0x5d6c40, 0x74794b][i % 3];
   w.box(x, y + .16, z, .7 + rng() * .8, .32, .6 + rng() * .7, t);
   w.box(x + (rng() - .5) * .8, y + .1, z + (rng() - .5) * .8, .5 + rng() * .6, .2, .5 + rng() * .5, t);
  } else if (r < .62) {
   const h = .9 + rng() * 1.5, b = h * (.5 + rng() * .35);
   w.box(x, y + h / 2, z, b, h, b * (.7 + rng() * .5), [0x807a6d, 0x6f6a60, 0x8b8477][i % 3], rng() * 3);
  } else if (r < .74) {
   // Bare Erde: bodennah und in Bodennähe gefärbt, damit sie nicht auffällt.
   // Gedreht, sonst liegen lauter achsparallele Rechtecke in der Wiese.
   w.box(x, y + .03, z, 2 + rng() * 3.5, .06, 1.8 + rng() * 3, 0x77704f, rng() * 3.1);
  } else nadelbaum(w, x, z, 6 + rng() * 6, 0x4a5f44);
 }
 // Entwässerungsgraben mit Betonkante, wie sie in flachem Land überall liegen.
 for (let x = -300; x < 80; x += 14) {
  w.box(x, -.45, -505, 14, .9, 5.5, 0x5c5a48);
  w.box(x, .12, -507.9, 14, .24, .5, 0x9b968a);
  w.box(x, .12, -502.1, 14, .24, .5, 0x9b968a);
 }
 // Schotterpiste vom Highway hinauf zur Leitungstrasse.
 // Schotter, nicht Beton: der erste Anlauf mit 0x8d8574 stand unter der
 // ACES-Belichtung fast weiß in der Wiese.
 for (let z = -420; z > -510; z -= 6) {
  bodenPlatte(w, -160, z, 5.4, 6, 0x6e6852, .06);
  w.box(-160, .05, z + 3, 5.8, .04, .5, 0x7b7460);
 }

 // Westrand: Vorland des Nationalparks, x um -540, z um -140.
 for (let i = 0; i < 260; i++) {
  const x = -580 + rng() * 120, z = -190 + rng() * 100;
  if (waterAt(x, z)) continue;
  const y = groundAt(x, z), r = rng();
  if (r < .62) nadelbaum(w, x, z, 7 + rng() * 8, [0x3a5740, 0x44614a, 0x33513c][i % 3]);
  else if (r < .84) {
   const h = 1.1 + rng() * 2.2, b = h * (.55 + rng() * .4);
   w.box(x, y + h / 2, z, b, h, b * (.7 + rng() * .5), [0x76715f, 0x848070, 0x6a6659][i % 3], rng() * 3);
  } else w.box(x, y + .14, z, .8 + rng() * 1, .28, .7 + rng() * .9, 0x4f6340);
 }

 // Südwestecke: Kiefernheide auf Sand, dazwischen alte Fundamente.
 for (let i = 0; i < 520; i++) {
  const x = -580 + rng() * 180, z = 200 + rng() * 250;
  if (waterAt(x, z) || aufStrasse(x, z, 10)) continue;
  const y = groundAt(x, z), r = rng();
  if (r < .5) nadelbaum(w, x, z, 6 + rng() * 7, [0x47603f, 0x3d5539, 0x506a44][i % 3]);
  else if (r < .72) laubbaum(w, x, z, 5 + rng() * 4, 0x5a7048);
  else if (r < .9) {
   // Sandblöße: die Heide steht auf Sand, aber flach und gedeckt, nicht als
   // helle Platte auf der Wiese.
   w.box(x, y + .03, z, 2.4 + rng() * 4, .06, 2 + rng() * 3.4, [0x7d7455, 0x736b4e, 0x847b5c][i % 3], rng() * 3.1);
   if (rng() < .5) w.box(x + (rng() - .5) * 3, y + .14, z + (rng() - .5) * 3, .8, .28, .7, 0x5c6b41);
  } else {
   const h = .8 + rng() * 1.3, b = h * (.6 + rng() * .4);
   w.box(x, y + h / 2, z, b, h, b * (.8 + rng() * .4), 0x7d776a, rng() * 3);
  }
 }
 // Vier Fundamentreste einer nie fertig gebauten Siedlung.
 for (const [fx, fz] of [[-520, 250], [-470, 320], [-545, 385], [-430, 415]]) {
  const b = 12 + rng() * 6, t = 9 + rng() * 5;
  w.box(fx, .12, fz, b, .24, t, 0xa9a290);
  for (const seite of [-1, 1]) {
   w.box(fx + seite * b / 2, .6, fz, .3, 1.2, t, 0x9a9382);
   w.box(fx, .6, fz + seite * t / 2, b, 1.2, .3, 0x9a9382);
  }
  for (let k = 0; k < 4; k++) w.box(fx - b / 2 + rng() * b, .9, fz - t / 2 + rng() * t, .34, 1.8, .34, 0x8d8776);
  zaun(w, fx - b, fz - t, fx + b, fz - t, 1, 0x8b8271, 3.2);
 }
 // Sandweg, der die Heide erschließt.
 for (let z = 210; z < 450; z += 7) {
  const x = -500 + Math.sin(z * .012) * 42;
  w.box(x, .04, z, 6.6, .07, 7, 0x74694f);
 }
}

// ---------------------------------------------------------- Der Westen
// Die Karte war knapp ein Quadratkilometer. Verdoppelt bringt Fläche allein
// nichts — leeres Land ist schlimmer als keins. Der neue Raum bekommt drei
// Dinge, die ihn tragen: eine zweite Stadt mit eigenem Charakter, eine
// Landmarke, die man von weit sieht, und dazwischen Wirtschaft statt Wiese.

// Kleinstadthaus mit Vorgarten und Einfahrt. Rosalind ist niedriger und
// älter als Port Mercy; keine Sockelgeschosse, keine Glasfronten.
function kleinstadthaus(w, x, z, rng, richtung) {
 const WAND = [0xc9c0aa, 0xb6bfb6, 0xd2c2a6, 0xa9b6bd, 0xc4b09c, 0xbdb7a2];
 const DACH = [0x7b5a4c, 0x5f6b6c, 0x8a7350, 0x63594e, 0x6d7566];
 const i = Math.floor(rng() * 6);
 const breite = 9 + rng() * 4, tiefe = 8 + rng() * 3;
 const wand = WAND[i], dach = DACH[i % 5];
 w.box(x, 1.6, z, breite, 3.2, tiefe, wand);
 satteldach(w, x, 3.25, z, breite + 1, tiefe + 1, 1.5, dach, rng() < .5);
 // Veranda zur Straße, Tür, zwei Fenster.
 const vz = z + richtung * (tiefe / 2 + 1.2);
 w.box(x, .16, vz, breite * .75, .32, 2.4, 0xa79f8c);
 w.box(x, 2.6, vz, breite * .75, .14, 2.8, dach);
 for (const e of [-.36, .36]) w.box(x + e * breite, 1.4, vz + richtung * 1.2, .12, 2.4, .12, wand);
 w.box(x, 1.1, z + richtung * (tiefe / 2 + .08), 1, 2.2, .14, 0x4a3a2c);
 for (const ox of [-.3, .3]) w.box(x + ox * breite, 1.9, z + richtung * (tiefe / 2 + .06), 1.5, 1.2, .1, 0x35505c);
 // Einfahrt und Briefkasten.
 w.box(x + breite * .55, .04, z + richtung * (tiefe / 2 + 5), 3, .08, 10, 0x6f6a5e);
 w.box(x + breite * .55, .6, z + richtung * (tiefe / 2 + 9.5), .12, 1.2, .12, 0x5d5548);
 w.box(x + breite * .55, 1.25, z + richtung * (tiefe / 2 + 9.5), .5, .3, .32, 0x8a8578);
 if (rng() < .45) laubbaum(w, x - breite * .6, z + richtung * (tiefe / 2 + 6), 5 + rng() * 3, 0x4e6b45);
}

function rosalind(w, rng) {
 // Hauptstraße: zwei Reihen zweigeschossiger Geschäftshäuser mit Vordach.
 const hz = 340;
 for (let x = -1000; x < -760; x += 22) {
   for (const seite of [-1, 1]) {
    const z = hz + seite * 16;
    if (w.sim.blocked({x, z}, 10) || !passtNebenStrasse(x, z, 21, 14)) continue;
    const h = 6.5 + rng() * 3;
    const wand = [0xb9a98c, 0xa6b0ab, 0xc2b294, 0x9fa9ad][Math.floor(rng() * 4)];
    w.box(x, h / 2, z, 20, h, 13, wand);
    w.box(x, h + .3, z, 21, .6, 14, 0x4e5a58);
    // Vordach über dem Bürgersteig, auf Stützen.
    const vz = z - seite * 7.5;
    w.box(x, 3.4, vz, 20, .2, 3, [0x8a5a4c, 0x4e6f74, 0x7d6a46][Math.floor(rng() * 3)]);
    for (const e of [-8, 0, 8]) w.box(x + e, 1.7, vz + -seite * 1.3, .14, 3.4, .14, 0x585f5c);
    // Schaufenster und Tür.
    w.box(x, 1.8, z - seite * 6.6, 14, 2.6, .12, 0x2f4650);
    w.box(x + (rng() - .5) * 8, 1.15, z - seite * 6.5, 1.4, 2.3, .16, 0x3d3228);
    // Obergeschossfenster.
    for (const ox of [-6, -2, 2, 6]) w.box(x + ox, 5.4, z - seite * 6.6, 1.5, 1.6, .1, 0x3a5462);
    w.text(['FEED & SEED', 'ROSALIND DINER', 'HARDWARE', 'GARAGE', 'POST', 'CLINIC', 'BANK', 'BARBER'][Math.floor(rng() * 8)],
     x, 4.1, z - seite * 6.9, 9, '#e8dcbc', seite > 0 ? Math.PI : 0);
   }
 }
 // Wohnstraßen im Raster, das in content.js als Straßen liegt.
 //
 // Nur auf der von der Hauptstraße abgewandten Seite. Der Block zwischen
 // z = 300 und z = 340 ist vierzig Meter tief; die Ladenzeile steht bei 324
 // und ist vierzehn Meter tief, die Häuser standen bei 320 und sind zwölf
 // tief — sie steckten ineinander. Elf solche Paare, gemessen, nachdem die
 // Läden zum ersten Mal überhaupt gebaut wurden. Jetzt Geschäfte an der
 // Hauptstraße, Wohnen an den äußeren Seiten der Nebenstraßen.
 for (const [strassenZ, seite] of [[300, -1], [380, 1]]) for (let x = -996; x < -764; x += 26) {
  const z = strassenZ + seite * 20;
  if (w.sim.blocked({x, z}, 9) || !passtNebenStrasse(x, z, 14, 12)) continue;
  kleinstadthaus(w, x + rng() * 4, z, rng, -seite);
 }
 // Hinterhöfe zwischen Ladenzeile und Nebenstraße: Garage, Schuppen, Zaun,
 // Beet. Der Block ist dort noch zwölf Meter tief, mehr als eine Reihe
 // flacher Anbauten passt nicht hinein — und mehr steht in einer Kleinstadt
 // hinter der Hauptstraße auch nicht.
 // Bis x = -762, nicht weiter: dahinter steht die Kirche mit ihrem
 // Grundstück, und der letzte Hof lag mit sechzehn Quadratmetern darin.
 for (const [zHof, richtung] of [[311, -1], [369, 1]]) for (let x = -1002; x < -762; x += 17) {
  const z = zHof + (rng() - .5) * 2;
  if (w.sim.blocked({x, z}, 6) || !passtNebenStrasse(x, z, 12, 9)) continue;
  const art = rng();
  if (art < .34) {                                   // Garage mit Tor
   w.box(x, 1.5, z, 7.5, 3, 6, [0xa8a293, 0xb4ab97, 0x9fa8a4][Math.floor(rng() * 3)]);
   w.box(x, 3.15, z, 8, .35, 6.5, 0x5f6663);
   w.box(x, 1.2, z - richtung * 3.06, 5.4, 2.4, .12, 0x4e5a58);
  } else if (art < .58) {                            // Geräteschuppen mit Pultdach
   const h = 2.2 + rng() * .8;
   w.box(x, h / 2, z, 4.4, h, 3.6, [0x8a7a5e, 0x7d6f56][Math.floor(rng() * 2)]);
   w.box(x, h + .2, z, 4.8, .25, 4, 0x5c5548, 0, false, 0, .12);
  } else if (art < .78) {                            // Beet mit Stangen
   w.box(x, .12, z, 8, .2, 5, 0x6a5a3e);
   for (let k = -3; k <= 3; k += 1.5) w.box(x + k, .8, z + (rng() - .5) * 3, .07, 1.6, .07, 0x7f7a5e);
  } else {                                           // Hof mit Fässern und Palette
   for (let k = 0; k < 3; k++)
    w.box(x + (rng() - .5) * 5, .55, z + (rng() - .5) * 4, .8, 1.1, .8, [0x4e6f74, 0x8a5a4c][k % 2]);
   w.box(x + 2, .16, z - 1.5, 2.2, .28, 1.8, 0x9a8258);
  }
  zaun(w, x - 8, z + richtung * 4.5, x + 8, z + richtung * 4.5, 1.5, 0x8a7a5e, 2.6);
 }
 // Wasserturm auf Stelzen — die Landmarke jeder Kleinstadt.
 // Stand bis zuletzt auf z = 340, also mitten auf der Hauptstraße: vier
 // Stelzen in der Fahrbahn, der Tank elf Meter breit darüber. Aufgefallen
 // ist es keinem Auge, sondern der Prüfung auf Fahrbahnhöhe — die fand ein
 // flaches breites Teil fünfzehn Meter über einer Straße und hat damit auf
 // den Kirchturm gezeigt, der dasselbe Problem hatte.
 const tx = -1020, tz = 360;
 for (const ox of [-1, 1]) for (const oz of [-1, 1]) {
  w.box(tx + ox * 4, 9, tz + oz * 4, .45, 18, .45, 0x7d837f);
  w.box(tx + ox * 4, 9, tz, .3, .3, 8.4, 0x7d837f, 0, false, 0, .5);
 }
 w.box(tx, 20, tz, 11, 7, 11, 0xb9bdb2);
 w.box(tx, 24.2, tz, 9, 2.4, 9, 0x9aa098);
 w.box(tx, 25.8, tz, .3, 1.6, .3, 0x6f7570);
 w.text('ROSALIND', tx, 20.5, tz - 5.7, 12, '#5c6b62');
 // Kirche mit Turm am Ostende. Sie stand mit ihrer nördlichen Hälfte in der
 // Hauptstraße — 20 m tief um z = 342, während die Fahrbahn von 332 bis 348
 // reicht. Jetzt nördlich davon, wie das Straßenraster es hergibt.
 const kx = -734, kz = 368;
 w.box(kx, 3.4, kz, 14, 6.8, 20, 0xd0c8b4);
 satteldach(w, kx, 6.8, kz, 15, 21, 3.2, 0x6b6f68, true);
 w.box(kx - 8, 6, kz - 7, 7, 12, 7, 0xd0c8b4);
 satteldach(w, kx - 8, 12, kz - 7, 7.6, 7.6, 5, 0x5f6663, true);
 w.box(kx - 8, 18.5, kz - 7, .25, 3, .25, 0x8d8d86);
 w.box(kx - 8, 18.2, kz - 7, 1.3, .25, .25, 0x8d8d86);
 w.text('FIRST LIGHT', kx, 3.2, kz - 10.3, 11, '#e0d6bc');
 // Tankstelle und Getreidesilos an der Ausfallstraße.
 for (let k = 0; k < 3; k++) {
  const sx = -1040 + k * 15, sz = 470;
  w.box(sx, 9, sz, 11, 18, 11, 0xb6b2a4);
  w.box(sx, 18.6, sz, 12, 1.4, 12, 0x8a877c);
  for (let y = 3; y < 18; y += 4) w.box(sx, y, sz + 5.6, 11.2, .18, .2, 0x8f8c80);
 }
 w.box(-1000, .06, 470, 26, .14, 22, 0x6b675c);
 w.text('CANE CO-OP', -1010, 21, 462, 14, '#d8cfae');
}

// Stausee mit Damm. Wasser, das nicht Meer ist — und ein Bauwerk, das man
// befahren kann.
function stausee(w, rng) {
 // Halbachsen zwei Meter größer als die Wasserfläche in content.js: die
 // Böschung liegt außen herum, nicht darin.
 const mx = SEEN[0].x, mz = SEEN[0].z, rx = SEEN[0].rx + 2, rz = SEEN[0].rz + 2;
 // Uferböschung als Ring aus Kisten, innen das Wasser.
 for (let a = 0; a < Math.PI * 2; a += .09) {
  const x = mx + Math.cos(a) * rx, z = mz + Math.sin(a) * rz;
  w.box(x, .5, z, 9, 1, 9, 0x6f6a52, a);
  // Der Baum sitzt acht Meter radial nach außen. Bei einer Ellipse ist das
  // nicht dasselbe wie senkrecht zur Uferlinie — sechzehn Fichten standen
  // dadurch im See. waterAt() entscheidet, nicht die Rechnung.
  if (Math.floor(a * 6) % 5 === 0) {
   const bx = x + Math.cos(a) * 8, bz = z + Math.sin(a) * 8;
   if (!waterAt(bx, bz)) nadelbaum(w, bx, bz, 7 + rng() * 5, 0x3d5a3f);
  }
 }
 // Die Wasserfläche war hier eine dunkle Platte mit sechsundzwanzig helleren
 // Kisten darauf. Sie liegt jetzt als Wassershader in world.js, und der See
 // steht in waterAt() — man läuft nicht mehr darüber, man schwimmt.
 // Staumauer im Süden, mit Straßenkrone und Überlauf.
 const dz = mz + rz + 4;
 w.box(mx, 6, dz, 190, 12, 9, 0x9a9a92);
 w.box(mx, 12.4, dz, 192, .8, 11, 0x82827b);
 for (let x = mx - 90; x <= mx + 90; x += 10) w.box(x, 13.4, dz + 5, 1, 1.2, .3, 0xa8a89f);
 for (const ox of [-30, 0, 30]) {
  w.box(mx + ox, 4, dz + 5.5, 7, 8, 3, 0x8a8a82);
  w.box(mx + ox, 8.6, dz + 5.5, 7.6, .5, 3.6, 0x6f6f68);
 }
 w.box(mx + 78, 15, dz - 2, 4, 6, 4, 0xb0b0a6);
 w.box(mx + 78, 18.6, dz - 2, 4.6, 1.2, 4.6, 0x6f7570);
 w.text('MERCY RESERVOIR', mx, 16, dz + 7, 26, '#dfe2d2');
 // Zufahrt von der Westumgehung auf die Krone.
 for (let x = mx - 110; x < mx - 88; x += 6) w.box(x, .06, dz, 6, .12, 9, 0x40474b);
}

// Der Bergrücken: Windpark auf dem Kamm, Steinbruch an der Flanke,
// Serpentine hinauf.
function talonRidge(w, rng) {
 for (let k = 0; k < 7; k++) {
  const x = -960 + k * 24, z = -230 + k * 26;
  const y = groundAt(x, z);
  if (y < 25) continue;
  w.box(x, y + 26, z, 2.2, 52, 2.2, 0xdcdcd4);
  w.box(x, y + 52, z, 4, 3, 4, 0xcfcfc6);
  // Drei Blätter als flache Balken, in unterschiedlichen Stellungen.
  const dreh = rng() * 2;
  for (let b = 0; b < 3; b++) {
   const a = dreh + b * Math.PI * 2 / 3;
   w.box(x + Math.cos(a) * 12, y + 52 + Math.sin(a) * 12, z + 2.6,
    24, 1.4, .35, 0xe4e4dc, 0, false, 0, a);
  }
 }
 // Steinbruch: Terrassen in die Flanke, Förderband, Haufen.
 const qx = -700, qz = -300;
 for (let k = 0; k < 5; k++) {
  const r = 46 - k * 8;
  w.box(qx, groundAt(qx, qz) - 1 + k * 3, qz, r * 2, 3, r * 1.5, [0x9a9184, 0x8e857a][k % 2]);
 }
 w.box(qx + 40, groundAt(qx + 40, qz) + 6, qz, 42, 1.2, 3, 0x6f6a5e, 0, false, 0, -.22);
 // Neun Betriebsgebäude, vorher frei gewürfelt in einem Feld von 80 auf 60
 // Metern — acht Paare davon standen ineinander. Jetzt ein Raster von drei
 // mal drei mit Versatz: dieselbe Unordnung im Bild, aber kein Bauwerk im
 // anderen.
 for (let k = 0; k < 9; k++) {
  const x = qx - 27 + (k % 3) * 27 + (rng() - .5) * 6;
  const z = qz - 20 + Math.floor(k / 3) * 20 + (rng() - .5) * 5;
  w.box(x, groundAt(x, z) + 1.6, z, 7 + rng() * 4, 3.2, 6 + rng() * 3, 0x8a8175);
 }
 w.text('TALON QUARRY', qx, groundAt(qx, qz) + 12, qz - 40, 22, '#e2dcc8');
 // Bewuchs am Hang, dichter im Tal.
 for (let i = 0; i < 620; i++) {
  const x = -1090 + rng() * 520, z = -530 + rng() * 620;
  // Der Streubereich reicht im Südosten bis x = -570 und z = 90 und damit in
  // den Stausee hinein: sechzehn Fichten standen im Wasser. Gefunden nicht
  // mit dem Auge, sondern beim Zählen der Kulisse über waterAt().
  if (waterAt(x, z) || aufStrasse(x, z, 10) || w.sim.blocked({x, z}, 3)) continue;
  const y = groundAt(x, z);
  // Über 62 m wächst kein Baum mehr — das stand hier von Anfang an, war
  // aber als "gar nichts" umgesetzt. Die obersten 26 Meter des Rückens
  // waren dadurch eine glatte grüne Kuppel; die Regionsvermessung in
  // tools/schwachstellen.mjs hat TALON RIDGE mit Abstand als flachste
  // Gegend der Karte ausgewiesen (örtlicher Kontrast 6,03 gegen 13,25 im
  // Schnitt). Oberhalb der Baumgrenze steht jetzt Fels.
  if (y > 62) {
   const art = rng();
   if (art < .30) {
    // Findling: zwei versetzte Blöcke, damit die Silhouette nicht würfelt.
    const b = 1.6 + rng() * 3.4;
    w.box(x, y + b * .34, z, b, b * .72, b * .86, [0x8a8175, 0x7b7368, 0x948b7d][i % 3], rng() * 3.1);
    w.box(x + b * .22, y + b * .78, z - b * .18, b * .62, b * .5, b * .58,
     [0x7b7368, 0x8a8175][i % 2], rng() * 3.1);
   } else if (art < .52) {
    // Aufragende Felsrippe, quer zum Hang.
    const l = 4 + rng() * 9, hh = 1.4 + rng() * 3.2;
    w.box(x, y + hh * .42, z, l, hh, 1.2 + rng() * 2, 0x827a6e, rng() * 3.1, false, 0, (rng() - .5) * .3);
   } else if (art < .74) {
    // Geröllfeld: flach, breit, kaum höher als der Boden.
    const r = 3 + rng() * 6;
    w.box(x, y + .16, z, r, .32, r * .7, [0x968d7f, 0x877f72][i % 2], rng() * 3.1);
    for (let k = 0; k < 3; k++)
     w.box(x + (rng() - .5) * r, y + .3, z + (rng() - .5) * r, .5 + rng(), .5, .5 + rng(), 0x9d9486, rng() * 3.1);
   } else {
    // Windgebeugter Krüppelstrauch. Auf dem Kamm steht nichts aufrecht.
    const h = .7 + rng() * 1.1;
    w.box(x, y + h / 2, z, h * 1.9, h, h * 1.5, [0x4c5a44, 0x5a6349][i % 2], rng() * 3.1);
   }
   continue;
  }
  if (rng() < .62) nadelbaum(w, x, z, 6 + rng() * 9, y > 30 ? 0x36523c : 0x40603f);
  else {
   const h = 1 + rng() * 2.4, b = h * (.6 + rng() * .4);
   w.box(x, y + h / 2, z, b, h, b, [0x847d70, 0x736c60][i % 2], rng() * 3);
  }
 }
 // Der Streuwurf oben deckt 520 mal 620 Meter mit 620 Stück ab — ein Objekt
 // je 520 Quadratmeter, also alle dreiundzwanzig Meter eines. Auf dem Kamm
 // ist das nicht zu sehen: nach dem ersten Anlauf stand der Kontrast
 // unverändert bei 6,04. Die Regel war richtig, die Dichte war es nicht.
 //
 // Deshalb ein eigener Wurf nur für die Kuppe. Sie ist die Ellipse, auf der
 // groundAt über 60 m liegt: Mittelpunkt -900/-160, Halbachsen 92 und 120,
 // rund 35.000 Quadratmeter. 900 Stück darauf sind eines je vierzig
 // Quadratmeter.
 for (let i = 0; i < 900; i++) {
  const t = rng() * Math.PI * 2, r = Math.sqrt(rng());
  const x = -900 + Math.cos(t) * r * 96, z = -160 + Math.sin(t) * r * 126;
  if (aufStrasse(x, z, 9) || w.sim.blocked({x, z}, 3)) continue;
  const y = groundAt(x, z);
  if (y < 58) continue;
  const art = rng();
  if (art < .34) {
   const b = .9 + rng() * 2.6;
   w.box(x, y + b * .3, z, b, b * .64, b * .8, [0x8a8175, 0x7b7368, 0x948b7d][i % 3], rng() * 3.1);
  } else if (art < .58) {
   const l = 2.5 + rng() * 7, hh = .8 + rng() * 2.4;
   w.box(x, y + hh * .4, z, l, hh, .9 + rng() * 1.8, 0x827a6e, rng() * 3.1, false, 0, (rng() - .5) * .34);
  } else if (art < .82) {
   const rr = 2 + rng() * 4.5;
   w.box(x, y + .14, z, rr, .28, rr * .7, [0x968d7f, 0x877f72][i % 2], rng() * 3.1);
  } else {
   const h = .5 + rng() * .9;
   w.box(x, y + h / 2, z, h * 2.1, h, h * 1.6, [0x4c5a44, 0x5a6349][i % 2], rng() * 3.1);
  }
 }
}

// Cane Hollow: Zuckerrohr, Entwässerungsgräben, ein paar Höfe. Der Süden ist
// Landwirtschaft, nicht Wildnis.
function caneHollow(w, rng) {
 for (let fx = -1040; fx < 60; fx += 120) for (let fz = 500; fz < 880; fz += 90) {
  if (aufStrasse(fx, fz, 22)) continue;
  w.box(fx, .05, fz, 108, .1, 78, [0x6d7a3f, 0x788446, 0x627339][Math.floor(rng() * 3)]);
  // Reihen im Feld, längs oder quer.
  const quer = rng() < .5;
  for (let u = -50; u < 50; u += 4.5) {
   if (quer) w.box(fx + u, .5, fz, 1.4, .9, 74, [0x7f8c4a, 0x8b9752][Math.abs(u) % 9 < 4.5 ? 0 : 1]);
   else w.box(fx, .5, fz + u * .74, 104, .9, 1.4, [0x7f8c4a, 0x8b9752][Math.abs(u) % 9 < 4.5 ? 0 : 1]);
  }
  // Graben am Feldrand.
  w.box(fx, -.3, fz + 42, 108, .6, 4, 0x4c5545);
 }
 // Drei Höfe an der Südtangente.
 for (const [hx, hz] of [[-940, 700], [-620, 730], [-300, 690]]) {
  if (w.sim.blocked({x: hx, z: hz}, 20)) continue;
  w.box(hx, 2.2, hz, 16, 4.4, 12, 0xc4b79c);
  satteldach(w, hx, 4.4, hz, 17, 13, 2.4, 0x7a5a4c, true);
  w.box(hx + 24, 4.5, hz + 4, 22, 9, 16, 0x8a4f42);
  satteldach(w, hx + 24, 9, hz + 4, 23, 17, 4.5, 0x5f5347, true);
  for (const oz of [-6, 6]) w.box(hx + 24, 4, hz + 4 + oz, 23.2, 6, .3, 0x7a4438);
  w.box(hx - 18, 6, hz - 6, 8, 12, 8, 0xb6b2a4);
  w.box(hx - 18, 12.6, hz - 6, 9, 1.2, 9, 0x8a877c);
  zaun(w, hx - 30, hz + 18, hx + 40, hz + 18, 1.2, 0x8a7a5e, 3.2);
  for (let k = 0; k < 6; k++) laubbaum(w, hx - 34 + k * 3, hz - 16 - (k % 2) * 4, 5 + rng() * 3, 0x4e6b45);
 }
 // Sandpisten zwischen den Feldern.
 for (let z = 500; z < 880; z += 90) for (let x = -1050; x < 60; x += 8)
  w.box(x, .04, z + 44, 8, .08, 6, 0x6e6853);
}

// Hinterland. Nach dem Ausbau blieben dreizehn Landzellen praktisch leer —
// Ecken zwischen den gebauten Gebieten, für die keine eigene Region sinnvoll
// ist. Eine breite, dünne Streuung schließt sie, ohne dass irgendwo etwas
// Erfundenes steht: Gehölz, Findlinge, Weidezäune, Feldwege.
function hinterland(w, rng) {
 const erlaubt = (x, z) => {
  if (waterAt(x, z) || aufStrasse(x, z, 11)) return false;
  if (x > -370 && x < 130 && z > -140 && z < 170) return false;   // Innenstadt
  if (x > 88 && x < 130) return false;                             // Strand
  if (x > -1010 && x < -730 && z > 270 && z < 410) return false;   // Rosalind
  if (Math.hypot((x + 700) / 130, (z - 80) / 100) < 1.05) return false; // Stausee
  return true;
 };
 for (let i = 0; i < 4200; i++) {
  const x = -1095 + rng() * 1215, z = -535 + rng() * 1430;
  if (!erlaubt(x, z) || w.sim.blocked({x, z}, 4)) continue;
  const y = groundAt(x, z), r = rng();
  if (r < .30) nadelbaum(w, x, z, 6 + rng() * 8, y > 30 ? 0x3a5540 : 0x44603f);
  else if (r < .52) laubbaum(w, x, z, 5 + rng() * 5, [0x4e6b45, 0x577248, 0x455f3d][i % 3]);
  else if (r < .70) {
   const h = .9 + rng() * 1.8, b = h * (.55 + rng() * .45);
   w.box(x, y + h / 2, z, b, h, b * (.8 + rng() * .4), [0x847d70, 0x736c60, 0x8d867a][i % 3], rng() * 3);
  } else if (r < .86) {
   const t = [0x66713f, 0x5c6a3a, 0x717a46][i % 3];
   w.box(x, y + .18, z, .8 + rng() * .9, .36, .7 + rng() * .8, t);
   w.box(x + (rng() - .5) * .9, y + .11, z + (rng() - .5) * .9, .6, .22, .55, t);
  } else w.box(x, y + .03, z, 2 + rng() * 4, .06, 1.8 + rng() * 3.4, 0x77704f, rng() * 3.1);
 }
 // Weidezäune quer durchs Hinterland: sie geben der Fläche einen Maßstab.
 for (let k = 0; k < 22; k++) {
  const x = -1060 + rng() * 900, z = -480 + rng() * 1300;
  if (!erlaubt(x, z) || aufStrasse(x, z, 18)) continue;
  const laenge = 40 + rng() * 90, quer = rng() < .5;
  zaun(w, x, z, quer ? x + laenge : x, quer ? z : z + laenge, 1.15, 0x8a7a5e, 3.4);
 }
 // Feldwege, die irgendwo anfangen und irgendwo aufhören — so sieht
 // Erschließung aus, die älter ist als die Straße daneben.
 for (let k = 0; k < 9; k++) {
  const x0 = -1040 + rng() * 860, z0 = -460 + rng() * 1280, quer = rng() < .5;
  for (let t = 0; t < 140; t += 7) {
   const x = quer ? x0 + t : x0 + Math.sin(t * .03) * 14;
   const z = quer ? z0 + Math.sin(t * .03) * 14 : z0 + t;
   if (!erlaubt(x, z)) continue;
   bodenPlatte(w, x, z, 6.4, 7, 0x6e6853);
  }
 }
}

// Northstar Fuel. Der Ort hatte einen Namen, eine Tankfunktion und keinen
// einzigen Klotz. Hier steht er: Vorplatz, Vordach auf vier Stützen mit
// Deckenlicht, zwei Zapfinseln mit vier Säulen, Kiosk und Preistotem an der
// Straße. Die Maße kommen aus content.js, damit Hindernis und Kulisse
// zusammenbleiben.
function tankstelle(w) {
 const T = TANKSTELLE, fx = T.x, fz = T.z;
 const hof = T.hof;
 // Vorplatz mit Bordkante, damit er nicht als graues Rechteck im Gras liegt.
 // Der Hof lag zuerst in 0x565e60. Im Schatten des Vordachs beleuchtet ihn
 // nur noch der Himmel, und ein blaustichiges Grau wird darunter zu einer
 // blauen Fläche — auf dem ersten Bild sah der Vorplatz aus wie ein Becken.
 // Jetzt ein warmes Betongrau, das auch unter reinem Himmelslicht Beton bleibt.
 baumfrei(w, fx + hof.versatzX - hof.breite / 2, fz + hof.versatzZ - hof.tiefe / 2,
  fx + hof.versatzX + hof.breite / 2, fz + hof.versatzZ + hof.tiefe / 2);
 w.box(fx + hof.versatzX, .05, fz + hof.versatzZ, hof.breite, .12, hof.tiefe, 0x6b665c);
 for (const s of [-1, 1]) {
  w.box(fx + hof.versatzX, .16, fz + hof.versatzZ + s * hof.tiefe / 2, hof.breite, .22, .5, 0x8e8b7f);
  w.box(fx + hof.versatzX + s * hof.breite / 2, .16, fz + hof.versatzZ, .5, .22, hof.tiefe, 0x8e8b7f);
 }
 // Vordach. Die Unterseite trägt drei Leuchtbänder — nachts ist eine
 // Tankstelle vor allem das: eine helle Decke über dunklem Beton.
 const d = T.dach;
 w.box(fx, d.hoehe + .4, fz, d.breite, .8, d.tiefe, 0xd9d5c7);
 w.box(fx, d.hoehe - .05, fz, d.breite - .6, .3, d.tiefe - .6, 0xb4b0a2);
 for (const oz of [-4.4, 0, 4.4])
  w.box(fx, d.hoehe - .22, fz + oz, d.breite - 3, .12, .7, 0xfff1d2, 0, true);
 // Die leuchtenden Bänder erhellen nichts — sie sind nur helle Flächen. Eine
 // Tankstelle ist nachts aber vor allem eine helle Decke über dunklem Beton,
 // und ohne echtes Licht blieb der Vorplatz schwarz. Vier Lampen gehen an
 // denselben Vorrat, aus dem sich die Innenräume bedienen: fünf Punktlichter
 // wandern zu den nächstgelegenen Einträgen im Umkreis von zwanzig Metern.
 (w.zusatzLampen ||= []).push(
  ...[-7, 0, 7].map(ox => ({x: fx + ox, y: d.hoehe - .5, z: fz, farbe: 0xffeccb, staerke: 88})),
  {x: fx + T.kiosk.versatzX, y: 3.4, z: fz + T.kiosk.versatzZ - T.kiosk.tiefe / 2 - 1.5, farbe: 0xdfe7ea, staerke: 46});
 w.box(fx, d.hoehe + .95, fz - d.tiefe / 2 + .1, d.breite, .3, .3, 0xc4553f);
 w.text('NORTHSTAR FUEL', fx, d.hoehe + .4, fz - d.tiefe / 2 - .05, 15, '#f0ead2');
 for (const ox of [-1, 1]) for (const oz of [-1, 1])
  w.box(fx + ox * (d.breite / 2 - 1.5), d.hoehe / 2, fz + oz * (d.tiefe / 2 - 1.5), .7, d.hoehe, .7, 0xb9b5a6);
 // Zapfinseln. Je Insel zwei Säulen mit dunklem Kopf und Schlauchbügel.
 for (const s of [-1, 1]) {
  const ix = fx + s * T.insel.versatzX;
  w.box(ix, .2, fz, T.insel.breite, .32, T.insel.tiefe, 0x8e8b7f);
  w.sim.addSolid(ix, fz, T.insel.breite, T.insel.tiefe, 'zapfinsel', 1.9);
  for (const oz of [-1.05, 1.05]) {
   w.box(ix, 1.25, fz + oz, .95, 1.8, .62, 0xc9553f);
   w.box(ix, 2.22, fz + oz, .66, .34, .5, 0x2c3238);
   w.box(ix, 2.24, fz + oz - .26, .34, .16, .04, 0xe9dfae, 0, true);
   w.box(ix + .58, 1.5, fz + oz, .12, 1.1, .12, 0x3a4145);
  }
 }
 // Kiosk mit Fensterband und Vordachlippe.
 const k = T.kiosk, kx = fx + k.versatzX, kz = fz + k.versatzZ;
 w.box(kx, k.hoehe / 2, kz, k.breite, k.hoehe, k.tiefe, 0xcfcabb);
 w.box(kx, k.hoehe + .18, kz, k.breite + .8, .36, k.tiefe + .8, 0x8d9490);
 w.box(kx, 2.5, kz - k.tiefe / 2 - .06, k.breite - 2.4, 1.9, .12, 0x9fc3cc, 0, true);
 w.box(kx + k.breite / 2 - 1.6, 1.1, kz - k.tiefe / 2 - .07, 1.1, 2.2, .1, 0x5f6a6c);
 w.text('SHOP', kx - k.breite / 2 + 2.4, 3.9, kz - k.tiefe / 2 - .1, 3.4, '#3d4a4e');
 w.sim.addSolid(kx, kz, k.breite, k.tiefe, 'kiosk', k.hoehe);
 // Luft und Wasser an der Kioskecke, zwei Mülleimer, vier Poller.
 w.box(kx + k.breite / 2 + 1.4, .9, kz + 1, .7, 1.8, .7, 0x4f5a5e);
 for (const oz of [-1.6, 1.6]) w.box(kx - k.breite / 2 - 1.2, .55, kz + oz, .7, 1.1, .7, 0x3f484a);
 for (const ox of [-2.4, 2.4]) for (const s of [-1, 1])
  w.box(fx + s * (T.insel.versatzX + T.insel.breite / 2 + .9), .5, fz + ox, .22, 1, .22, 0xc9b45f);
 // Preistotem zur Fahrbahn hin.
 const tx = fx + 12, tz = fz - 9;
 w.box(tx, 3.2, tz, .5, 6.4, .5, 0x6f7570);
 w.box(tx, 6.3, tz, 4.4, 2.6, .45, 0xe4e0d2);
 w.box(tx, 6.9, tz - .25, 3.6, 1, .05, 0xc4553f, 0, true);
 w.text('NORTHSTAR', tx, 6.9, tz - .3, 3.2, '#f4efdc', Math.PI);
 w.text('4.29', tx, 5.7, tz - .3, 2.2, '#2f3a3e', Math.PI);
}

// Bäume werden während dressRegions gesammelt und erst danach gesetzt. Wer
// spät ein Gebäude auf eine Fläche stellt, bekommt sie durchs Dach — auf dem
// ersten Bild der Luftfracht wuchsen Bäume durch die Halle. Diese Funktion
// nimmt die Einträge im Rechteck wieder aus der Liste, bevor sie gebaut wird.
function baumfrei(w, x1, z1, x2, z2) {
 const liste = w.laubwerk?.liste;
 if (!liste) return 0;
 const vorher = liste.length;
 w.laubwerk.liste = liste.filter(t => t.x < x1 || t.x > x2 || t.z < z1 || t.z > z2);
 return vorher - w.laubwerk.liste.length;
}

// Was im Bahnprofil steht, kommt weg. Solange die Welt gebaut wird, liegen
// alle Klötze noch als Liste in world.groups — erst flush() macht daraus
// InstancedMeshes. Bis dahin lässt sich nachträglich aussortieren.
//
// Nötig wurde das, als die Landebahn ihren Belag bekam: auf dem Asphalt
// standen ein vierzehn Meter hoher Mast, fünf Pfosten und ein Kasten, alle
// aus Funktionen, die nach airfield() laufen und von der Bahn nichts wissen.
// Auf der unbefestigten Wiese davor fiel es nicht auf.
// Maßgeblich ist die Oberkante, nicht die Dicke: zwei Bleche von zehn und
// zwanzig Zentimetern Stärke hingen in anderthalb Metern Höhe über der
// Bahnschwelle und blieben bei einer Prüfung auf Bauteilhöhe stehen.
function bahnRaeumen(w, x1, z1, x2, z2, oberkante = .6) {
 let weg = 0;
 for (const g of w.groups.values()) {
  const rest = g.items.filter(i => !(i.x > x1 && i.x < x2 && i.z > z1 && i.z < z2 && i.y + i.h / 2 >= oberkante));
  weg += g.items.length - rest.length;
  g.items = rest;
 }
 return weg;
}

// Mercy Dragstrip. Der Marker liegt an der Schwelle der Landebahn — das
// Rennen fährt über die Bahn, und das ist auch richtig so: Beschleunigungs-
// rennen auf einer Piste gibt es wirklich. Es fehlte nur alles, was ein
// Rennen daraus macht. Der erste Versuch legte eine zweite, eigene Fahrbahn
// darüber, samt Leitplanken auf der Randbefeuerung — das war doppelt
// gebaut, weil ich die Bahn für unbefestigt hielt (sie hatte tatsächlich
// keinen Belag, aber der gehört zur Bahn, nicht zum Rennen). Hier steht
// jetzt nur, was zum Rennen gehört, und alles Feste liegt neben der Bahn.
function dragstrip(w) {
 const l = locations.drag, bx = l.x, start = l.z + 14, ziel = l.z + 136;
 // Westlich der Bahn liegt die Nord-Süd-Achse bei x = -340 mit achtzehn
 // Metern Breite; zwischen Bahnrand (-327) und Fahrbahnrand (-331) sind vier
 // Meter. Zeitnahme und Tribüne standen dort mitten auf der Straße — gefunden
 // von der Prüfung, die zwei Commits vorher für die Läden dazukam. Alles
 // Feste steht deshalb östlich, auf dem Vorfeld bei x = -301 bis -261.
 baumfrei(w, bx + 10, start - 16, bx + 34, ziel);
 // Aufgemalt: Startlinie, Ziellinie, Startfelder, Entfernungsangabe.
 w.box(bx, .18, start, 22, .02, 1.2, 0xe8e3c8);
 w.box(bx, .18, ziel, 22, .02, 1.2, 0xe8e3c8);
 for (const ox of [-5, 5]) {
  for (const oz of [-3.2, -1.6]) w.box(bx + ox, .18, start + oz, 3.6, .02, .5, 0xcfcaa8);
  w.box(bx + ox, .18, start - 8, .35, .02, 9, 0xcfcaa8);
 }
 // Ein 'STAGE' auf den Asphalt lag genau über der Bahnkennung '27' — beides
 // flach, beides bei z = 252. Die Kennung gehört der Bahn, also fällt es weg.
 w.text('1/8 MILE', bx + 5, .19, ziel - 9, 6.6, '#e8e3c8', 0, true);
 // Startbaum am westlichen Bahnrand, nicht zwischen den Spuren: auf einer
 // Piste steht dort nichts Festes.
 const sx = bx + 15.5;
 w.box(sx, .35, start - 4, 2.2, .7, 1.4, 0x39444a);
 w.box(sx, 3.1, start - 4, .7, 6.2, .7, 0x2f3a3e);
 for (const oz of [-.42, .42]) {
  for (let k = 0; k < 3; k++) w.box(sx - .38, 4.6 - k * .62, start - 4 + oz, .1, .3, .3, 0xe0a844, 0, true);
  w.box(sx - .38, 2.68, start - 4 + oz, .1, .3, .3, 0x5fbe72, 0, true);
  w.box(sx - .38, 2.06, start - 4 + oz, .1, .3, .3, 0xd8453c, 0, true);
 }
 // Zeitnahmehütte und kleine Tribüne, beide westlich der Bahn und innerhalb
 // des Flugplatzzauns bei x = bahnX - 40.
 const hx = bx + 22;
 w.box(hx, 1.8, start - 2, 6, 3.6, 5, 0xc2bcae);
 w.box(hx, 3.75, start - 2, 6.6, .35, 5.6, 0x8d9490);
 w.box(hx - 3.06, 2.3, start - 2, .12, 1.3, 3.4, 0x9fc3cc, 0, true);
 w.text('ZEITNAHME', hx, 3.1, start - 4.6, 5.4, '#3d4a4e', Math.PI);
 w.sim.addSolid(hx, start - 2, 6, 5, 'zeitnahme', 3.6);
 const gx = bx + 30;
 for (let k = 0; k < 4; k++) {
  w.box(gx + k * 1.5, .45 + k * .75, start + 26, 1.5, .9 + k * 1.5, 26, 0xb4b0a2);
  w.box(gx + k * 1.5, .9 + k * .75, start + 26, 1.4, .12, 25, 0x8a8f88);
 }
 for (let z = start + 14; z <= start + 38; z += 4) w.box(gx + 6, 3.9, z, .1, 1.1, .1, 0x6f7570);
 w.box(gx + 6, 4.4, start + 26, .12, .1, 25, 0x6f7570);
 w.sim.addSolid(gx + 2.5, start + 26, 8, 26, 'tribuene', 3.6);
 // Reifenstapel und Absperrung entlang der Zuschauerseite.
 for (let k = 0; k < 8; k++) w.box(bx + 17.5, .45, start - 6 + k * 5, 1.2, .9, 1.2, 0x2c3236);
 for (let z = start + 8; z <= start + 46; z += 5) w.box(bx + 18.5, .55, z, .12, 1.1, .12, 0x8b9089);
 w.box(bx + 18.5, .95, start + 27, .1, .1, 40, 0xb0b6ac);
 // Zielmarke: zwei Pfosten mit Fahnen, weit außerhalb des Bahnprofils.
 for (const ox of [-16, 16]) {
  w.box(bx + ox, 2.6, ziel, .3, 5.2, .3, 0x4b5457);
  w.box(bx + ox - Math.sign(ox) * .9, 4.6, ziel, 1.8, 1.2, .1, 0xd8453c);
 }
 (w.zusatzLampen ||= []).push(
  {x: bx + 12, y: 6, z: start + 6, farbe: 0xffeccb, staerke: 62});
}

// Iron Tide Gym. Zwei stehende Teile im Umkreis von achtzehn Metern, und
// beide gehörten zum Nachbarn. Der Bau steht westlich der alten Markierung,
// wo das nächste freie Rechteck von 26 mal 20 Metern liegt; die Front zeigt
// zur Straße im Westen.
function gym(w) {
 // Der Marker steht vor dem Eingang; das Haus liegt dreizehn Meter dahinter.
 const l = locations.gym, gx = l.x + 13, gz = l.z - 1;
 baumfrei(w, gx - 14, gz - 11, gx + 14, gz + 11);
 w.box(gx, .05, gz, 26, .12, 20, 0x6b665c);
 w.box(gx, 3.5, gz + 1, 22, 7, 14, 0xb0a597);
 w.box(gx, 7.2, gz + 1, 23, .5, 15, 0x8d9490);
 // Glasfront nach Westen, nachts von innen hell.
 w.box(gx - 11.08, 3.1, gz + 1, .16, 4.2, 10, 0x9fc3cc, 0, true);
 w.box(gx - 11.1, 1.15, gz - 4.4, .2, 2.3, 1.5, 0x4a5457);
 w.box(gx - 11.6, 2.9, gz - 4.4, 1.4, .25, 2.6, 0x8d9490);
 // Dachschild und Beschriftung an der Fassade.
 w.box(gx - 11.3, 9.1, gz + 1, .5, 3.2, 13, 0x2f3a3e);
 w.text('IRON TIDE GYM', gx - 11.6, 9.1, gz + 1, 13, '#e2ecec', -Math.PI / 2);
 // Draußen: Klimmzuggerüst, zwei Bänke, ein Reifenstapel.
 for (const oz of [-1, 1]) w.box(gx - 15.5, 1.2, gz + 1 + oz * 2.2, .16, 2.4, .16, 0x50595c);
 w.box(gx - 15.5, 2.34, gz + 1, .12, .12, 4.8, 0x50595c);
 for (const oz of [-6.5, 7.5]) {
  w.box(gx - 15.2, .45, gz + oz, 1.9, .16, .5, 0x8a7856);
  for (const ox of [-.7, .7]) w.box(gx - 15.2 + ox, .22, gz + oz, .12, .45, .45, 0x50595c);
 }
 for (let k = 0; k < 3; k++) w.box(gx + 8, .35 + k * .55, gz - 8.5, 1.5, .5, 1.5, 0x2c3236);
 w.sim.addSolid(gx, gz + 1, 22, 14, 'gym', 7);
 (w.zusatzLampen ||= []).push({x: gx - 8, y: 3.4, z: gz + 1, farbe: 0xdfe7ea, staerke: 54});
}

// Mercy Air Cargo. Ein Marker mit einer einzigen Instanz daneben, obwohl
// Akt 2 die Zeugin genau dorthin bringt. Jetzt Halle, Vorfeld, Container,
// Paletten, Zaun und Windsack.
function luftfracht(w) {
 // Der Marker steht an der Hallenfront, das Vorfeld sechzehn Meter dahinter.
 const l = locations.aircargo, ax = l.x - 2, az = l.z + 16;
 baumfrei(w, ax - 22, az - 16, ax + 22, az + 16);
 w.box(ax, .05, az, 42, .12, 30, 0x63625b);
 for (let u = -18; u <= 18; u += 6) w.box(ax + u, .13, az + 8, .18, .02, 12, 0xc8c2a0);
 // Halle mit Tonnendach und offenem Tor nach Süden.
 w.box(ax, 4.5, az + 4, 26, 9, 18, 0xa8ada6);
 w.box(ax, 9.4, az + 4, 27, 1, 19, 0x7c837e);
 w.box(ax, 10.4, az + 4, 20, 1.1, 14, 0x6e756f);
 w.box(ax, 3.2, az - 5.1, 12, 6.4, .3, 0x3f4a4d);
 for (let u = -5; u <= 5; u += 2.5) w.box(ax + u, 3.2, az - 5.25, .18, 6.2, .12, 0x59656a);
 w.text('MERCY AIR CARGO', ax, 7.6, az - 5.3, 22, '#e6ead8', Math.PI);
 w.box(ax, 6.6, az - 5.4, 26.4, .5, .5, 0xc4553f);
 w.sim.addSolid(ax, az + 4, 26, 18, 'halle', 9);
 // Container in zwei Reihen, Paletten und eine Waage davor.
 const farben = [0xc4553f, 0x4d6f8a, 0x7d8a5a, 0xb08c4a];
 for (let k = 0; k < 6; k++) {
  const cx = ax - 16 + (k % 3) * 7.4, cz = az + 11 - Math.floor(k / 3) * 3.2;
  w.box(cx, 1.3, cz, 6.8, 2.6, 2.6, farben[k % 4]);
  if (k % 2 === 0) w.box(cx, 3.9, cz, 6.8, 2.6, 2.6, farben[(k + 2) % 4]);
 }
 for (let k = 0; k < 4; k++) w.box(ax + 12 + (k % 2) * 2.6, .5, az - 10 - Math.floor(k / 2) * 2.4, 2.2, .9, 2, 0x9a8258);
 w.box(ax - 14, .45, az - 11, 3.4, .8, 3.4, 0x50595c);
 w.box(ax - 14, 1.5, az - 12.6, 3.4, 1.3, .2, 0x2c3236);
 // Windsack am Zaun, damit das Vorfeld zum Flugfeld gehört.
 w.box(ax + 20, 3.2, az - 12, .22, 6.4, .22, 0xb0b5ae);
 w.box(ax + 21.4, 6, az - 12, 2.6, .9, .9, 0xd8763f);
 zaun(w, ax - 21, az - 15, ax + 21, az - 15, 2.2, 0x808780, 5);
 zaun(w, ax - 21, az - 15, ax - 21, az + 15, 2.2, 0x808780, 5);
 zaun(w, ax + 21, az - 15, ax + 21, az + 15, 2.2, 0x808780, 5);
 (w.zusatzLampen ||= []).push({x: ax, y: 5.4, z: az - 7, farbe: 0xffeccb, staerke: 62});
}

// Der Fähranleger von Isla Serena. Der Marker lag vierzig Meter im
// Landesinneren; die Westküste der Insel ist eine gerade Linie bei x = 235.
// Kai, Steg auf Pfählen, Wartedach, Kassenhaus, Poller — und eine
// festgemachte Fähre, weil ein Anleger ohne Schiff daran nur ein Steg ist.
function faehre(w) {
 // Kaikante bei x = 235, der Marker steht auf dem Kai.
 const kx = locations.ferry.x + 1, kz = locations.ferry.z;
 baumfrei(w, kx - 8, kz - 19, kx + 16, kz + 19);
 w.box(kx + 4, .06, kz, 20, .14, 34, 0x6b665c);
 w.box(235.6, .35, kz, 1.4, .7, 34, 0x8e8b7f);
 steg(w, 235, kz - 5, 219, kz - 5, 3.2);
 steg(w, 235, kz + 6, 223, kz + 6, 3.2);
 // Wartedach über dem Kai.
 for (const ox of [-1, 1]) for (const oz of [-1, 1])
  w.box(kx + 1 + ox * 5, 1.6, kz + oz * 6, .3, 3.2, .3, 0x8a8f88);
 w.box(kx + 1, 3.4, kz, 12.5, .35, 14, 0xcfcabb);
 w.box(kx + 1, 3.05, kz, 11.5, .35, 13, 0x9aa39c);
 for (const oz of [-4.5, 0, 4.5]) {
  w.box(kx + 1, .5, kz + oz, 2.2, .18, .55, 0x8a7856);
  for (const ox of [-.8, .8]) w.box(kx + 1 + ox, .25, kz + oz, .14, .5, .5, 0x50595c);
 }
 w.box(kx + 1, 3.15, kz - 7.1, 12.5, .5, .5, 0x3f6f7a, 0, true);
 w.text('ISLA SERENA · FÄHRE', kx + 1, 3.15, kz - 7.25, 12, '#e6f0ee', Math.PI);
 // Kassenhaus mit Schalterfenster.
 w.box(kx + 12, 1.9, kz + 10, 7, 3.8, 6, 0xc2bcae);
 w.box(kx + 12, 3.95, kz + 10, 7.6, .35, 6.6, 0x8d9490);
 w.box(kx + 8.45, 2.1, kz + 10, .12, 1.5, 3.4, 0x9fc3cc, 0, true);
 w.text('TICKETS', kx + 8.35, 3.3, kz + 10, 4.4, '#3d4a4e', -Math.PI / 2);
 w.sim.addSolid(kx + 12, kz + 10, 7, 6, 'kasse', 3.8);
 // Poller entlang der Kante, Rettungsring, Fahrplantafel.
 for (let z = kz - 14; z <= kz + 14; z += 5.6) w.box(236.4, .55, z, .55, 1.1, .55, 0x4b5457);
 w.box(237.4, 1.35, kz - 9, .2, .9, .9, 0xc4553f);
 w.box(kx - 3, 1.5, kz + 13, .18, 3, .18, 0x6f7570);
 w.box(kx - 3, 2.7, kz + 13, .12, 1.6, 2.4, 0xe4e0d2);
 // Festgemachte Fähre am nördlichen Steg.
 const fx = 224, fz = kz - 11;
 w.box(fx, .55, fz, 9, 1.9, 22, 0xcdd3cd);
 w.box(fx, 1.75, fz, 8.4, .5, 21, 0x4f5f68);
 w.box(fx, 3.1, fz + 3, 6, 2.2, 9, 0xdfe3dc);
 w.box(fx, 4.35, fz + 3, 6.4, .35, 9.4, 0x8d9490);
 for (const oz of [-2, 0, 2]) w.box(fx - 3.06, 3.3, fz + 3 + oz, .12, 1.1, 2.2, 0x9fc3cc, 0, true);
 w.box(fx, 5.4, fz + 5, .6, 2, .6, 0xb8bdb6);
 w.box(fx, 6.6, fz + 5, 1.6, .6, 1.6, 0x3f4a4d);
 w.text('SERENA LINE', fx - 4.6, 3.2, fz - 3, 9, '#dfe7e2', -Math.PI / 2);
 (w.zusatzLampen ||= []).push({x: kx + 1, y: 3, z: kz, farbe: 0xffeccb, staerke: 58});
}

export function dressRegions(world) {
 const rng = zufall();
 sunsetSuburbs(world, rng);
 bellweather(world, rng);
 cypressPark(world, rng);
 saltMarsh(world, rng);
 airfield(world, rng);
 islaSerena(world, rng);
 harborIndustry(world, rng);
 stadtLuecken(world, rng);
 suedFlaechen(world, rng);
 nordFlaechen(world, rng);
 randgebiete(world, rng);
 inselkette(world, rng);
 rosalind(world, rng);
 stausee(world, rng);
 talonRidge(world, rng);
 caneHollow(world, rng);
 hinterland(world, rng);
 // Zum Schluss die vier Orte, die vorher nur Marker waren. Sie stehen hier
 // und nicht weiter oben, weil baumfrei() nur Bäume entfernen kann, die
 // schon gemeldet sind — bei einem früheren Aufruf pflanzten die Funktionen
 // danach wieder in die Halle hinein. Gemessen: drei Bäume blieben stehen.
 // Erst räumen, dann bauen: sonst nimmt die Räumung die eigene Ausstattung
 // gleich wieder mit.
 bahnRaeumen(world, -327.5, 238, -302.5, 392);
 tankstelle(world);
 gym(world);
 dragstrip(world);
 luftfracht(world);
 faehre(world);
}
