import {locations} from './content.js';
// Innenräume.
// Die acht Servicegebäude hatten drei Wände, einen Bodenfleck und zwei
// namenlose Klötze darin. Man konnte hineinlaufen und stand in einer leeren
// Box. Hier bekommt jeder Raum Boden, Decke, Beleuchtung und Einrichtung.
//
// Die Vorderseite bleibt offen: eine Schnittdarstellung statt Ladetüren.
// Der Spieler läuft ohne Übergang hinein, die Kamera hat freie Sicht.

const BREITE = id => id === 'garage' ? 22 : 16;

// Der Raum reicht von der Rückwand bei l.z-12 bis zur offenen Front bei l.z+4.
function raum(id) {
 const l = locations[id], b = BREITE(id);
 return {l, links: l.x - b / 2 + .6, rechts: l.x + b / 2 - .6, hinten: l.z - 11.4, vorn: l.z + 3.6, breite: b};
}

const LAMPEN = [];
function grundriss(w, id, bodenFarbe, wandFarbe) {
 const r = raum(id);
 w.box(r.l.x, .06, r.l.z - 4, r.breite - .8, .12, 15.2, bodenFarbe);
 // Decke mit Kante nach vorn, damit der Schnitt eine Oberkante hat.
 w.box(r.l.x, 4.92, r.l.z - 4, r.breite, .3, 15.6, wandFarbe);
 w.box(r.l.x, 4.6, r.vorn + .4, r.breite, .9, .4, wandFarbe);
 // Innenseite der Wände etwas heller als die Fassade.
 for (const s of [-1, 1]) w.box(r.l.x + s * (r.breite / 2 - .55), 2.5, r.l.z - 4, .18, 4.8, 15.2, wandFarbe);
 w.box(r.l.x, 2.5, r.hinten - .5, r.breite - .8, 4.8, .18, wandFarbe);
 // Deckenleuchten: nachts von außen sichtbar, weil die Front offen ist.
 for (let z = r.hinten + 2; z < r.vorn - 1; z += 4.6)
  for (const ox of id === 'garage' ? [-5, 5] : [0]) {
   w.box(r.l.x + ox, 4.72, z, 2.6, .12, .5, 0xf2e6c0, 0, true);
   // Die leuchtende Fläche allein erhellt nichts. Die Positionen gehen an
   // den Lichtvorrat der Welt, der sich zum nächstgelegenen Raum bewegt.
   LAMPEN.push({x: r.l.x + ox, y: 4.4, z,
    farbe: id === 'club' ? 0xc06a9a : id === 'clinic' ? 0xdfeaf2 : 0xffdcae,
    // Der Club bleibt dunkler als die übrigen Räume, aber lesbar.
    // Der Club hat kein Tageslicht durch die offene Front und sehr dunkle
    // Flächen; ohne kräftige Lampen bleibt er ein schwarzes Loch.
    staerke: id === 'club' ? 105 : id === 'garage' ? 72 : 76});
  }
 return r;
}

const EINRICHTUNG = {
 garage(w, r) {
  // Hebebühne mit Wagen, Werkbank, Reifenstapel, Ölfässer, Werkzeugwand.
  const hx = r.l.x - 4, hz = r.l.z - 6;
  w.box(hx, .3, hz, 4.4, .5, 6, 0x4a5257);
  for (const oz of [-2.1, 2.1]) w.box(hx, .9, hz + oz, 3.6, .7, .5, 0x7a838a);
  w.box(hx, 1.35, hz, 4.6, .3, 5.6, 0x6a747a);
  w.box(hx, 1.9, hz, 1.9, .8, 4.4, 0x7d5a52);
  w.box(hx, 2.5, hz - .3, 1.7, .55, 2.4, 0x36505c);
  for (const ox of [-1.05, 1.05]) for (const oz of [-1.7, 1.7]) w.box(hx + ox, 1.75, hz + oz, .25, .8, .8, 0x24292c);
  const bx = r.rechts - 1.2;
  w.box(bx, .5, r.l.z - 6, 1.6, 1, 8, 0x6b7276);
  w.box(bx, 1.05, r.l.z - 6, 1.7, .12, 8.2, 0x9aa39b);
  w.box(bx - .1, 2.6, r.l.z - 6, .12, 2.4, 7.6, 0x54646c);
  for (let z = -9; z < -2; z += 1.1) {
   w.box(bx - .3, 2.2 + (z % 2 ? .6 : 0), r.l.z + z, .35, .5, .12, [0xb0764a, 0x8f9aa2, 0x6f8f6a][Math.abs(Math.round(z)) % 3]);
  }
  for (let k = 0; k < 4; k++) w.box(r.links + 1.3, .35 + k * .34, r.hinten + 1.4, 1.5, .32, 1.5, 0x22282b);
  for (const ox of [0, 1.1]) w.box(r.links + 1.2 + ox, .55, r.hinten + 4, .85, 1.1, .85, 0x8a6a3f);
  w.box(r.l.x, 3.6, r.hinten - .3, 7, 1, .15, 0x2d3a40);
 },
 shop(w, r) {
  // Tresen, Vitrinen, Kleiderständer, Regalwand.
  w.box(r.l.x + 2.6, .55, r.l.z - 2, 6.4, 1.1, 1.1, 0x6d5a44);
  w.box(r.l.x + 2.6, 1.16, r.l.z - 2, 6.8, .12, 1.4, 0x9a8560);
  w.box(r.l.x + 4.6, 1.35, r.l.z - 2.2, .8, .3, .5, 0x2b3338);
  for (const oz of [-9.5, -7.5]) {
   w.box(r.links + 1.6, 1.5, r.l.z + oz + 3, 2.6, 3, .3, 0x5b6a6f);
   for (let y = .6; y < 2.9; y += .7) w.box(r.links + 1.6, y, r.l.z + oz + 3.2, 2.4, .1, .5, 0x8f9a92);
   for (let y = .95; y < 2.9; y += .7) for (let ox = -.8; ox <= .8; ox += .8)
    w.box(r.links + 1.6 + ox, y, r.l.z + oz + 3.3, .45, .5, .35, [0x9a5f52, 0x4d6f7a, 0xa8944f][Math.round(y * 3) % 3]);
  }
  for (const ox of [-1.5, 1.5]) {
   w.box(r.l.x + ox, 1.9, r.l.z - 7, .1, .1, 3.2, 0x8a938c);
   for (const oz of [-1.2, -.4, .4, 1.2]) w.box(r.l.x + ox, 1.35, r.l.z - 7 + oz, .7, 1, .22, [0x7a5a62, 0x4f6a5f, 0x6a6a7a, 0x8a7250][Math.abs(Math.round(oz * 2)) % 4]);
   for (const oz of [-1.6, 1.6]) w.box(r.l.x + ox, .95, r.l.z - 7 + oz, .1, 1.9, .1, 0x8a938c);
  }
  w.box(r.l.x, 1.1, r.hinten + .6, 3, 2.2, .5, 0x3c4a52);
 },
 clinic(w, r) {
  // Empfang, zwei Betten mit Vorhang, Schränke, Wartebank.
  w.box(r.l.x - 4, .55, r.l.z + 1, 5, 1.1, 1.2, 0xa9b2ad);
  w.box(r.l.x - 4, 1.16, r.l.z + 1, 5.4, .12, 1.5, 0xd0d6cf);
  for (const oz of [-9, -5.6]) {
   w.box(r.rechts - 3, .5, r.l.z + oz + 2, 2.2, .5, 4.2, 0xd6dad2);
   w.box(r.rechts - 3, .85, r.l.z + oz + 2, 2, .25, 4, 0xb9ccd2);
   w.box(r.rechts - 3, 1.15, r.l.z + oz + .3, 1.9, .35, .7, 0xeef1ea);
   w.box(r.rechts - 4.4, 1.6, r.l.z + oz + 2, .12, 3.2, 4.2, 0x8fa9ad);
   w.box(r.rechts - 1.6, 1, r.l.z + oz + .4, .7, 2, .7, 0x9aa39b);
  }
  for (let k = 0; k < 3; k++) w.box(r.links + 1.4, 1.4 + k * 1.1, r.hinten + 3, 1.6, 1, 3.4, 0xc2cac3);
  w.box(r.links + 2.2, .4, r.l.z + 1.4, .6, .8, 3.2, 0x7f8a86);
  w.box(r.links + 2.2, .72, r.l.z + 1.4, .8, .12, 3.4, 0x9aa39b);
  w.box(r.l.x, 3.5, r.hinten - .3, 4, .9, .15, 0x93b2a8);
 },
 home(w, r) {
  // Sofa, Fernseher, Bett, Küchenzeile, Tisch.
  w.box(r.links + 2.6, .4, r.l.z - 1, 3.2, .8, 1.6, 0x5f6a63);
  w.box(r.links + 2.6, .85, r.l.z - 1.7, 3.2, .9, .35, 0x6b766e);
  for (const oz of [-1.7, 1.7]) w.box(r.links + 2.6 + (oz > 0 ? 1.5 : -1.5), .7, r.l.z - 1, .3, .6, 1.6, 0x6b766e);
  w.box(r.links + 2.6, .35, r.l.z + 1.4, 1.8, .7, .9, 0x7a6247);
  w.box(r.links + 2.6, 1.1, r.l.z + 2.6, 2.6, 1.5, .18, 0x22282b);
  w.box(r.links + 2.6, 1.1, r.l.z + 2.5, 2.3, 1.2, .06, 0x3f5e6a, 0, true);
  w.box(r.rechts - 2.4, .3, r.hinten + 2.6, 3.2, .6, 4.4, 0x6a5a48);
  w.box(r.rechts - 2.4, .72, r.hinten + 2.6, 3.4, .3, 4.6, 0xb8bcae);
  w.box(r.rechts - 2.4, .95, r.hinten + .9, 3, .3, .8, 0xd6dad2);
  w.box(r.l.x, .45, r.hinten + 1.4, 5.4, .9, 1.1, 0x8a8073);
  w.box(r.l.x, .95, r.hinten + 1.4, 5.6, .12, 1.3, 0x5f6a63);
  w.box(r.l.x - 1.6, 1.02, r.hinten + 1.4, .9, .12, .8, 0x9aa39b);
  w.box(r.l.x + 1.8, 1.5, r.hinten + 1.2, 1, 1.2, .8, 0xa9b2ad);
  w.box(r.l.x + 1, .38, r.l.z - 3.5, 1.5, .76, 1.5, 0x7a6247);
  for (const [ox, oz] of [[-1.4, 0], [1.4, 0]]) {
   w.box(r.l.x + 1 + ox, .25, r.l.z - 3.5 + oz, .5, .5, .5, 0x6b766e);
   w.box(r.l.x + 1 + ox, .7, r.l.z - 3.5 + oz + (ox > 0 ? .25 : -.25), .5, .6, .1, 0x6b766e);
  }
 },
 club(w, r) {
  // Bar, Tanzfläche mit farbigen Feldern, Boxen, Sitznischen.
  w.box(r.links + 2.4, .6, r.l.z - 4, 2.4, 1.2, 8, 0x4a4157);
  w.box(r.links + 2.4, 1.26, r.l.z - 4, 2.8, .14, 8.4, 0x7a5f6f);
  w.box(r.links + 1.4, 2.4, r.l.z - 4, .5, 3, 7, 0x3a3149);
  for (let z = -7; z < -1; z += 1.4) w.box(r.links + 1.3, 2 + (z % 2 ? .8 : 0), r.l.z + z, .35, .55, .3, 0x8a6f4a);
  for (const oz of [-2, 0, 2, 4]) w.box(r.links + 4.2, .55, r.l.z + oz - 4, .5, 1.1, .5, 0x4a3f52);
  for (let ix = 0; ix < 4; ix++) for (let iz = 0; iz < 4; iz++)
   w.box(r.l.x + 2.2 + (ix - 1.5) * 1.7, .13, r.l.z - 6 + (iz - 1.5) * 1.7, 1.6, .06, 1.6,
    [0x8a3f5a, 0x2f5f7a, 0x6a4f8a, 0x3f7a6a][(ix + iz) % 4], 0, true);
  for (const ox of [-1.2, 1.2]) {
   w.box(r.l.x + 2.2 + ox * 2.6, 1.2, r.hinten + 1.2, 1.1, 2.4, 1, 0x1d1a24);
   w.box(r.l.x + 2.2 + ox * 2.6, 1.7, r.hinten + 1.75, .7, .7, .1, 0x33303a);
  }
  for (const oz of [-1, 2.2]) {
   w.box(r.rechts - 1.6, .4, r.l.z + oz, 2, .8, 2.2, 0x54455f);
   w.box(r.rechts - 1.6, .95, r.l.z + oz, 2.2, .9, .3, 0x62506e);
  }
  w.box(r.l.x, 3.7, r.hinten - .3, 6, 1, .15, 0xb05f7a, 0, true);
  // Hinterzimmer: Akt 4 verlangt einen Tresor an einer bestimmten Stelle
  // (story.js, TRESOR). Ohne Möbel wäre das ein unsichtbares Ziel auf dem
  // nackten Boden — also steht hier, was dort stehen muss.
  const tx = r.l.x + 6, tz = r.l.z - 9;
  w.box(tx, .7, tz, 1.1, 1.4, .9, 0x33343a);
  w.box(tx - .58, .7, tz, .08, 1.3, .84, 0x4a4c53);
  w.box(tx - .63, .78, tz, .06, .34, .34, 0x8d8f96);
  w.box(tx - .66, .78, tz, .05, .1, .1, 0xc7c2a8, 0, true);
  w.box(tx, 1.46, tz, 1.2, .1, 1, 0x45474d);
  // Schreibtisch daneben, Aktenschrank an der Wand.
  w.box(tx - 2.4, .38, tz + .4, 1.9, .08, 1, 0x5f4c3c);
  for (const ox of [-.8, .8]) for (const oz of [-.4, .4])
   w.box(tx - 2.4 + ox, .19, tz + .4 + oz, .08, .38, .08, 0x4a3c30);
  w.box(tx - 2.4, .46, tz + .4, .5, .06, .36, 0xd8cfb4);
  w.box(tx - .4, 1, tz + 2.6, .5, 2, 1.4, 0x4e5057);
  for (const h of [.5, 1.1, 1.7]) w.box(tx - .67, h, tz + 2.6, .06, .38, 1.2, 0x676a71);
 },
 diner(w, r) {
  // Tresen mit Hockern, Nischen, Durchreiche zur Küche.
  w.box(r.l.x - 2, .55, r.l.z - 3, 1.4, 1.1, 9, 0x8a5f4a);
  w.box(r.l.x - 2, 1.16, r.l.z - 3, 1.8, .12, 9.4, 0xc9b98e);
  for (let z = -7; z < 2; z += 1.5) {
   w.box(r.l.x - .6, .45, r.l.z + z, .16, .9, .16, 0x9aa39b);
   w.box(r.l.x - .6, .95, r.l.z + z, .55, .12, .55, 0xa8544c);
  }
  w.box(r.l.x - 4.2, 1.4, r.l.z - 3, 2.4, 2.8, 8.6, 0xa9b2ad);
  w.box(r.l.x - 3.2, 1.6, r.l.z - 3, .4, 1.2, 3.4, 0x2b3338);
  for (const oz of [-8, -4.6, -1.2]) {
   w.box(r.rechts - 2.4, .4, r.l.z + oz + 3, 3.4, .8, .8, 0x7a4f4a);
   w.box(r.rechts - 2.4, 1, r.l.z + oz + 2.7, 3.4, 1.4, .25, 0x8a5f56);
   w.box(r.rechts - 2.4, 1, r.l.z + oz + 3.3, 3.4, 1.4, .25, 0x8a5f56);
   w.box(r.rechts - 2.4, .75, r.l.z + oz + 3, 3, .12, 1.5, 0xc9b98e);
  }
  w.box(r.l.x, 3.6, r.hinten - .3, 5, 1, .15, 0xd8a24f, 0, true);
 },
 motel(w, r) {
  // Rezeption, Schlüsselbrett, Sitzecke, Automat.
  w.box(r.l.x - 2, .55, r.l.z - 2, 5, 1.1, 1.3, 0x6d5a44);
  w.box(r.l.x - 2, 1.16, r.l.z - 2, 5.4, .12, 1.6, 0x9a8560);
  w.box(r.l.x - 2, 1.4, r.l.z - 2.2, .55, .35, .4, 0x2b3338);
  w.box(r.l.x - 2, 2.4, r.hinten - .3, 3.4, 1.8, .2, 0x54453a);
  for (let ix = 0; ix < 8; ix++) for (let iy = 0; iy < 3; iy++)
   w.box(r.l.x - 3.5 + ix * .42, 1.9 + iy * .5, r.hinten - .15, .2, .3, .1, 0xb8a26a);
  w.box(r.rechts - 1.6, 1, r.l.z - 8, 1.6, 2, 1, 0x3f5560);
  w.box(r.rechts - 1.6, 1.3, r.l.z - 7.55, 1.2, 1.2, .08, 0x8ac0c8, 0, true);
  for (const oz of [1, 2.6]) {
   w.box(r.rechts - 2.2, .35, r.l.z + oz, 1.6, .7, 1.4, 0x5f6a63);
   w.box(r.rechts - 1.6, .8, r.l.z + oz, .3, .9, 1.4, 0x6b766e);
  }
  w.box(r.l.x, 3.6, r.hinten - .3, 5, 1, .15, 0xd0b47a, 0, true);
 },
 records(w, r) {
  // Aktenregale in Reihen, Lesetische, Terminal, Tresen.
  for (let ix = 0; ix < 3; ix++) {
   const x = r.links + 2.2 + ix * 3.4;
   w.box(x, 1.6, r.hinten + 3.4, 1.2, 3.2, 6.4, 0x6d6152);
   for (let y = .6; y < 3.1; y += .62) for (let z = -2.8; z <= 2.8; z += 1.2)
    w.box(x, y, r.hinten + 3.4 + z, 1.3, .42, 1,
     [0x9a8f72, 0x8a7f66, 0xa89a78][Math.abs(Math.round(y * 4 + z)) % 3]);
  }
  w.box(r.l.x + 1, .38, r.l.z + .6, 4.4, .76, 1.6, 0x5f5648);
  w.box(r.l.x + 1, .8, r.l.z + .6, 4.6, .1, 1.8, 0x7d7360);
  for (const ox of [-1.4, 1.4]) {
   w.box(r.l.x + 1 + ox, .25, r.l.z + 1.9, .5, .5, .5, 0x4a4a44);
   w.box(r.l.x + 1 + ox, .72, r.l.z + 2.15, .5, .6, .1, 0x4a4a44);
  }
  w.box(r.rechts - 1.4, .9, r.l.z - 1, 1, 1.8, 1.4, 0x3f4a52);
  w.box(r.rechts - 1.9, 1.5, r.l.z - 1, .08, .8, 1.1, 0x6fa8b0, 0, true);
  w.box(r.l.x, 3.6, r.hinten - .3, 5, 1, .15, 0xa8b8b0);
 }
};

const BODEN = {garage: 0x4b5155, shop: 0x7a7266, clinic: 0xb6bdb6, home: 0x7d6b53,
 club: 0x453a56, diner: 0x9a9382, motel: 0x6f6355, records: 0x6a6a5e};
const WAND = {garage: 0x6e7674, shop: 0x8d8a7a, clinic: 0xc4ccc4, home: 0x9a8f7c,
 club: 0x453b58, diner: 0xa89a7e, motel: 0x8a7f6c, records: 0x83837a};

export function dressInteriors(world) {
 LAMPEN.length = 0;
 for (const id of Object.keys(EINRICHTUNG)) {
  if (!locations[id]) continue;
  const r = grundriss(world, id, BODEN[id], WAND[id]);
  EINRICHTUNG[id](world, r);
 }
 return LAMPEN.slice();
}
