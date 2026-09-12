import {groundAt} from './content.js';
// Fassaden für Port Mercy.
// Die Gebäude waren Kisten mit aufgemalten Fensterquadraten: aus Augenhöhe
// die deutlichste Erinnerung daran, dass man in einer Demo steht. Alles hier
// läuft über World.box und landet damit in den vorhandenen InstancedMeshes.

const SOCKEL = [0x6d6a60, 0x5d6668, 0x736659, 0x5f6b66];
const MARKISEN = [0x9c5b52, 0x4e6f74, 0x8a7546, 0x51704f, 0x7a5470];
const LADEN = ['CAFÉ', 'LAVANDERÍA', 'MERCADO', 'BARBER', 'PHARMACY', 'TACOS',
 'LIQUOR', 'PAWN', 'NAILS', 'BODEGA', 'CAMBIO', 'DELI'];

function zufall(seed = 2207) {
 return () => {seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296;};
}

// Ein Fensterrahmen, der die Scheibe zurücksetzt. Die Vertiefung erzeugt am
// Rand echten Schatten — das ist der Unterschied zwischen aufgemalt und gebaut.
function fensterRahmen(w, x, y, z, breite, hoehe, achse, farbe) {
 const t = .22;
 if (achse === 'z') {
  w.box(x, y + hoehe / 2 + t / 2, z, breite + t * 2, t, .26, farbe);
  w.box(x, y - hoehe / 2 - t / 2, z, breite + t * 2, t * 1.4, .34, farbe);   // Sims steht weiter vor
  for (const s of [-1, 1]) w.box(x + s * (breite / 2 + t / 2), y, z, t, hoehe, .26, farbe);
 } else {
  w.box(x, y + hoehe / 2 + t / 2, z, .26, t, breite + t * 2, farbe);
  w.box(x, y - hoehe / 2 - t / 2, z, .34, t * 1.4, breite + t * 2, farbe);
  for (const s of [-1, 1]) w.box(x, y, z + s * (breite / 2 + t / 2), .26, hoehe, t, farbe);
 }
}

export function dressBuildings(world, gebaeude) {
 // Rückgabe: nichts. Alles landet in den Instanz-Sammlern von World.
 const rng = zufall();
 for (const [i, b] of gebaeude.entries()) {
  const basis = groundAt(b.x, b.z);
  const hoch = b.h > 14;
  const sockelFarbe = SOCKEL[i % SOCKEL.length];
  const sockelHoehe = hoch ? 4.6 : Math.min(3.2, b.h * .45);

  // Sockelgeschoss: springt vor und trägt Läden statt Fensterreihen.
  world.box(b.x, basis + sockelHoehe / 2, b.z, b.w + .7, sockelHoehe, b.d + .7, sockelFarbe);
  world.box(b.x, basis + sockelHoehe + .12, b.z, b.w + 1.1, .24, b.d + 1.1, 0x3f4a4a);

  for (const seite of [-1, 1]) {
   const z = b.z + seite * (b.d / 2 + .4);
   // Schaufensterband mit Pfosten dazwischen.
   world.box(b.x, basis + 1.75, z, b.w * .86, 2.3, .12, 0x2c4149);
   for (let u = -b.w * .43; u <= b.w * .43; u += 2.4) world.box(b.x + u, basis + 1.75, z + seite * .06, .16, 2.4, .18, sockelFarbe);
   world.box(b.x, basis + .32, z + seite * .05, b.w * .88, .64, .22, sockelFarbe);
   // Eingang, versetzt, damit die Front nicht symmetrisch bleibt.
   const tx = b.x + (rng() - .5) * b.w * .45;
   world.box(tx, basis + 1.15, z + seite * .16, 1.5, 2.3, .14, 0x35302a);
   world.box(tx, basis + 1.15, z + seite * .24, .12, .5, .1, 0xb6a37c);
   // Markise über dem Eingang.
   const markise = MARKISEN[(i * 3 + (seite > 0 ? 1 : 0)) % MARKISEN.length];
   world.box(tx, basis + 2.85, z + seite * .75, 3.4, .16, 1.5, markise);
   for (const e of [-1.6, 1.6]) world.box(tx + e, basis + 2.6, z + seite * 1.4, .07, .5, .07, 0x4c5354);
   // Ladenname über dem Schaufenster. Ohne Beschriftung bleibt jedes
   // Erdgeschoss austauschbar.
   world.text(LADEN[(i * 2 + (seite > 0 ? 1 : 0)) % LADEN.length], b.x, basis + 3.5, z + seite * .18,
    Math.min(7, b.w * .5), '#e8d3a4', seite > 0 ? 0 : Math.PI);
  }

  // Senkrechte Lisenen gliedern die sonst fugenlose Wand.
  for (const seite of [-1, 1]) {
   const x = b.x + seite * (b.w / 2 + .12);
   for (let u = -b.d * .4; u <= b.d * .4; u += 4.5)
    world.box(x, basis + b.h / 2, b.z + u, .22, b.h, .5, sockelFarbe);
   const z = b.z + seite * (b.d / 2 + .12);
   for (let u = -b.w * .4; u <= b.w * .4; u += 4.5)
    world.box(b.x + u, basis + b.h / 2, z, .5, b.h, .22, sockelFarbe);
  }

  // Fensterrahmen über die vorhandenen Scheiben legen. Die Scheiben selbst
  // setzt World.build; hier kommt nur die Laibung dazu.
  for (let y = 5; y < b.h - 1; y += 3.7) {
   if (y < sockelHoehe + 1.2) continue;
   for (let u = -6; u <= 6; u += 4) for (const seite of [-1, 1])
    fensterRahmen(world, b.x + u, basis + y, b.z + seite * (b.d / 2 + .09), 2, 1.9, 'z', sockelFarbe);
   for (let u = -15; u <= 15; u += 5) for (const seite of [-1, 1])
    fensterRahmen(world, b.x + seite * (b.w / 2 + .09), basis + y, b.z + u, 2, 1.9, 'x', sockelFarbe);
  }

  // Feuertreppe an einer Längsseite der höheren Häuser.
  if (hoch && i % 2 === 0) {
   const x = b.x + (b.w / 2 + .55) * (i % 4 < 2 ? 1 : -1);
   for (let y = sockelHoehe + 2.6; y < b.h - 2; y += 3.7) {
    world.box(x, basis + y, b.z + 4, 1.5, .12, 3.4, 0x4c5450);
    world.box(x + .7, basis + y + .55, b.z + 4, .07, 1.1, 3.4, 0x4c5450);
    for (const e of [-1.6, 1.6]) world.box(x, basis + y + .55, b.z + 4 + e, 1.5, 1.1, .07, 0x4c5450);
    world.box(x - .2, basis + y - 1.85, b.z + 5.9, 1.1, 3.6, .1, 0x565d58, .5);
   }
  }

  // Dachaufbauten. Ohne sie endet jedes Haus als saubere Kante gegen den Himmel.
  const dach = basis + b.h + .7;
  world.box(b.x, dach + .55, b.z, b.w + 1.2, 1.1, .32, 0x555f60);
  world.box(b.x, dach + .55, b.z + b.d / 2 + .5, b.w + 1.2, 1.1, .32, 0x555f60);
  world.box(b.x, dach + .55, b.z - b.d / 2 - .5, b.w + 1.2, 1.1, .32, 0x555f60);
  for (const s of [-1, 1]) world.box(b.x + s * (b.w / 2 + .5), dach + .55, b.z, .32, 1.1, b.d + 1.2, 0x555f60);
  const geraete = hoch ? 5 : 2;
  for (let k = 0; k < geraete; k++) {
   const gx = b.x + (rng() - .5) * (b.w - 3), gz = b.z + (rng() - .5) * (b.d - 4);
   const art = rng();
   if (art < .5) {                                   // Lüftungsgerät
    world.box(gx, dach + .75, gz, 2.2, 1.5, 1.7, 0x8d9490);
    world.box(gx, dach + 1.56, gz, 1.5, .12, 1.2, 0x6b7472);
   } else if (art < .78) {                           // Abluftkamin
    world.box(gx, dach + 1.1, gz, .55, 2.2, .55, 0x77706a);
    world.box(gx, dach + 2.3, gz, .8, .18, .8, 0x5d5852);
   } else {                                          // Wassertank auf Stelzen
    for (const ox of [-.7, .7]) for (const oz of [-.7, .7]) world.box(gx + ox, dach + .8, gz + oz, .16, 1.6, .16, 0x6a6055);
    world.box(gx, dach + 2.5, gz, 2.1, 1.8, 2.1, 0x7d6c56);
   }
  }
  if (hoch) {
   world.box(b.x + b.w * .28, dach + 1.4, b.z - b.d * .3, .1, 2.8, .1, 0x6d7472);
   world.box(b.x + b.w * .28, dach + 2.7, b.z - b.d * .3, 1.1, .55, 1.1, 0xa8aca2);  // Satellitenschüssel
  }

  // Zum Schluss: der Kollisionskörper wächst auf das Sockelgeschoss mit,
  // sonst läuft die Figur in das Schaufenster hinein. b ist dasselbe Objekt,
  // das die Simulation als solid führt — die sichtbare Grundgeometrie steht
  // zu diesem Zeitpunkt schon und ändert sich dadurch nicht mehr.
  b.w += .8; b.d += .8;
 }
}
