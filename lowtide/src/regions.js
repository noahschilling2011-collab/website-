import {groundAt, waterAt, locations, roadSegments} from './content.js';
// Der Rest von Solvara.
// Port Mercy war ausgebaut, alles andere bestand aus Andeutungen: sechs
// Kisten für die Vororte, ein Feld mit Strichen für Bellweather, 155
// Baumkisten für den Nationalpark, eine graue Bahn für das Flugfeld, eine
// leere Platte für Isla Serena. Hier bekommt jede Region das, was sie
// glaubwürdig macht — alles über World.box, also instanziert.

function zufall(seed = 5501) {
 return () => {seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296;};
}

// sim.blocked kennt nur Gebäude. Straßen sind reine Geometrie — ohne diese
// Prüfung landete die Scheune mitten auf dem Highway.
function aufStrasse(x, z, rand = 6) {
 for (const r of roadSegments) {
  const minX = Math.min(r.x1, r.x2) - r.w / 2 - rand, maxX = Math.max(r.x1, r.x2) + r.w / 2 + rand;
  const minZ = Math.min(r.z1, r.z2) - r.w / 2 - rand, maxZ = Math.max(r.z1, r.z2) + r.w / 2 + rand;
  if (x > minX && x < maxX && z > minZ && z < maxZ) return true;
 }
 return false;
}

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

// Nadelbaum aus drei gestapelten Lagen; als eine Kiste sah der Wald aus
// wie ein Regal.
function nadelbaum(w, x, z, hoehe, farbe = 0x3d5f47) {
 const y = groundAt(x, z);
 w.box(x, y + hoehe * .24, z, hoehe * .035, hoehe * .5, hoehe * .035, 0x5f5039);
 for (let k = 0; k < 4; k++) {
  const t = k / 4, breite = hoehe * (.30 - t * .062);
  w.box(x, y + hoehe * (.42 + t * .17), z, breite, hoehe * .2, breite, farbe);
 }
}

function laubbaum(w, x, z, hoehe, farbe = 0x4d6f4a) {
 const y = groundAt(x, z);
 w.box(x, y + hoehe * .3, z, hoehe * .055, hoehe * .6, hoehe * .055, 0x63523c);
 w.box(x, y + hoehe * .76, z, hoehe * .46, hoehe * .34, hoehe * .44, farbe);
 w.box(x + hoehe * .13, y + hoehe * .62, z - hoehe * .08, hoehe * .3, hoehe * .24, hoehe * .28, farbe);
 w.box(x - hoehe * .1, y + hoehe * .66, z + hoehe * .1, hoehe * .26, hoehe * .2, hoehe * .24, farbe);
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
  w.box(x, -.6 + h * .78, z, h * .95, h * .5, h * .9, rng() < .5 ? 0x3f6047 : 0x4a6d4a);
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
 // Schwellenmarkierung, Mittellinie und Randbefeuerung.
 for (const ende of [242, 388]) {
  for (let e = -9; e <= 9; e += 3) w.box(bahnX + e, .19, ende + (ende < 300 ? 6 : -6), 1.6, .02, 12, 0xd2d0af);
 }
 for (const seite of [-1, 1]) {
  for (let z = 240; z < 392; z += 12) {
   w.box(bahnX + seite * 12.5, .28, z, .3, .5, .3, 0xd8cf9a, 0, true);
  }
  w.box(bahnX + seite * 13.5, .1, 315, 3, .16, 155, 0x6f7a6a);
 }
 w.text('27', bahnX, .22, 250, 12, '#d8d6b8');
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
 w.box(bahnX + 34, 3.2, 400, 46, 6.4, 16, 0xbcb9a8);
 satteldach(w, bahnX + 34, 6.5, 400, 47, 17, 2.4, 0x5e6a68, true);
 w.text('MERCY AIRFIELD', bahnX + 34, 5.6, 391.4, 22, '#e0d3a8', Math.PI);
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
 const mx = 250, mz = 245;
 w.box(mx, .55, mz, 5, .3, 66, 0x9a8158);
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
 w.box(mx, 1.6, mz + 36, 7, 2.4, 6, 0xb09a6f);
 satteldach(w, mx, 2.9, mz + 36, 8, 7, 1.4, 0x6a7a6a, true);
 w.text('SERENA MARINA', mx, 4.3, mz + 32.6, 12, '#efd9a4', Math.PI);

 // Resortvillen mit Pools, an einer Ringstraße.
 w.box(297, .06, 222, 88, .14, 6, 0x8d8877);
 for (let k = 0; k < 6; k++) {
  const vx = 268 + (k % 3) * 30, vz = k < 3 ? 196 : 254;
  if (w.sim.blocked({x: vx, z: vz}, 12)) continue;
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
 const fx = -150, fz = -250;
 w.box(fx, .05, fz, 52, .12, 44, 0x5f7549);
 for (let r = 0; r < 6; r++) for (let k = 0; k < 11; k++) {
  const x = fx - 22 + k * 4.4, z = fz - 16 + r * 6.4;
  w.box(x, .45, z, 1, .9, .28, 0x9a9a92);
  w.box(x, .95, z, 1, .22, .34, 0x8d8d86);
 }
 w.box(fx, 2.6, fz + 20, 10, 5.2, 8, 0xc0b7a3);
 satteldach(w, fx, 5.3, fz + 20, 11, 9, 2.6, 0x5f6663, true);
 w.box(fx, 8.4, fz + 20, .3, 2.4, .3, 0x8d8d86);
 w.box(fx, 8.4, fz + 20, 1.2, .3, .3, 0x8d8d86);
 for (const [x1, z1, x2, z2] of [[fx - 26, fz - 22, fx + 26, fz - 22], [fx - 26, fz + 22, fx + 26, fz + 22], [fx - 26, fz - 22, fx - 26, fz + 22], [fx + 26, fz - 22, fx + 26, fz + 22]]) {
  const laenge = Math.hypot(x2 - x1, z2 - z1);
  w.box((x1 + x2) / 2, .8, (z1 + z2) / 2, Math.abs(x2 - x1) || 1.4, 1.6, Math.abs(z2 - z1) || 1.4, 0x3f5c3c);
 }
 w.text('MERCY REST', fx, 3.2, fz - 23, 14, '#d5dcc8', Math.PI);

 // Solarfeld an der Nordstraße.
 const px = -60, pz = -250;
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
}
