import * as T from './vendor/three.module.js';
import {waterAt, groundAt} from './content.js';
// Tierwelt.
// Über dem Wasser flog nichts, im Wasser schwamm nichts, im Sumpf bewegte
// sich nichts. Alles hier läuft über InstancedMesh: hunderte Tiere kosten
// eine Handvoll Draw Calls, und bewegt werden sie über Matrizen.
//
// Die Tiere reagieren auf den Spieler. Möwen steigen und beschleunigen, wenn
// er nahe kommt oder schießt; Fische stieben auseinander; Alligatoren drehen
// sich zu ihm hin, statt wegzuschwimmen.

const OZEAN = {minX: 126, maxX: 400, minZ: -380, maxZ: 420};
const SUMPF = {minX: -538, maxX: -406, minZ: -14, maxZ: 124};

function zufall(seed = 4711) {
 return () => {seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296;};
}

// Eine Möwe: Rumpf plus zwei Flügel, die über die Instanzmatrix nicht einzeln
// schlagen können — der Schlag steckt deshalb in der Skalierung des Ganzen.
function moewenGeometrie() {
 const teile = [];
 const rumpf = new T.SphereGeometry(1, 6, 4);
 rumpf.scale(.16, .12, .42);
 teile.push(rumpf);
 for (const s of [-1, 1]) {
  const fluegel = new T.BoxGeometry(1, 1, 1);
  fluegel.scale(.62, .03, .17);
  fluegel.translate(s * .38, .02, -.02);
  teile.push(fluegel);
 }
 return verschmelzen(teile);
}

function fischGeometrie() {
 const teile = [];
 const koerper = new T.SphereGeometry(1, 6, 4);
 koerper.scale(.10, .13, .30);
 teile.push(koerper);
 const flosse = new T.BoxGeometry(1, 1, 1);
 flosse.scale(.02, .16, .14);
 flosse.translate(0, .02, -.32);
 teile.push(flosse);
 return verschmelzen(teile);
}

function delfinGeometrie() {
 const teile = [];
 const koerper = new T.SphereGeometry(1, 8, 6);
 koerper.scale(.34, .38, 1.25);
 teile.push(koerper);
 const finne = new T.BoxGeometry(1, 1, 1);
 finne.scale(.06, .34, .28);
 finne.translate(0, .38, -.1);
 teile.push(finne);
 const fluke = new T.BoxGeometry(1, 1, 1);
 fluke.scale(.62, .05, .22);
 fluke.translate(0, 0, -1.3);
 teile.push(fluke);
 return verschmelzen(teile);
}

function alligatorGeometrie() {
 const teile = [];
 const ruecken = new T.BoxGeometry(1, 1, 1);
 ruecken.scale(.52, .22, 2.4);
 teile.push(ruecken);
 const kopf = new T.BoxGeometry(1, 1, 1);
 kopf.scale(.34, .16, .8);
 kopf.translate(0, .02, 1.5);
 teile.push(kopf);
 const schwanz = new T.BoxGeometry(1, 1, 1);
 schwanz.scale(.22, .14, 1.3);
 schwanz.translate(0, 0, -1.8);
 teile.push(schwanz);
 for (const s of [-1, 1]) {
  const auge = new T.BoxGeometry(1, 1, 1);
  auge.scale(.06, .06, .06);
  auge.translate(s * .11, .14, 1.35);
  teile.push(auge);
 }
 return verschmelzen(teile);
}

// Kleiner Zusammenführer für die Bauteile oben: eine Geometrie je Tierart.
function verschmelzen(teile) {
 let punkte = 0;
 const nichtIndiziert = teile.map(g => {
  const n = g.index ? g.toNonIndexed() : g;
  if (!n.attributes.normal) n.computeVertexNormals();
  punkte += n.attributes.position.count;
  return n;
 });
 const pos = new Float32Array(punkte * 3), nor = new Float32Array(punkte * 3);
 let versatz = 0;
 for (const g of nichtIndiziert) {
  pos.set(g.attributes.position.array, versatz * 3);
  nor.set(g.attributes.normal.array, versatz * 3);
  versatz += g.attributes.position.count;
 }
 const geo = new T.BufferGeometry();
 geo.setAttribute('position', new T.BufferAttribute(pos, 3));
 geo.setAttribute('normal', new T.BufferAttribute(nor, 3));
 geo.computeBoundingSphere();
 return geo;
}

function netz(scene, geo, farbe, anzahl, rauheit = .72) {
 const m = new T.InstancedMesh(geo, new T.MeshStandardMaterial({color: farbe, roughness: rauheit}), anzahl);
 m.frustumCulled = false;
 m.castShadow = false;
 m.receiveShadow = false;
 scene.add(m);
 return m;
}

export class Tierwelt {
 constructor(scene) {
  const rng = zufall();
  this.hilfe = new T.Object3D();
  this.scheu = 0;

  // Möwen in vier Schwärmen über der Küste.
  this.moewen = [];
  for (let s = 0; s < 4; s++) {
   const mx = 150 + rng() * 180, mz = -260 + s * 170, hoehe = 22 + rng() * 26;
   for (let k = 0; k < 16; k++)
    this.moewen.push({mx, mz, hoehe, r: 16 + rng() * 34, w: rng() * 6.3,
     tempo: .22 + rng() * .2, versatz: rng() * 6.3, flug: rng() * 6.3});
  }
  this.moewenNetz = netz(scene, moewenGeometrie(), 0xdfe4e0, this.moewen.length, .85);

  // Fischschwärme dicht unter der Oberfläche, im Meer und im Sumpf.
  this.fische = [];
  for (let k = 0; k < 90; k++) {
   const feld = k < 62 ? OZEAN : SUMPF;
   // Die Rechtecke enthalten auch Insel und Damm; dort darf kein Fisch
   // starten, sonst liegt er beim ersten Bild auf dem Trockenen.
   let x = 0, z = 0, versuche = 0;
   do {
    x = feld.minX + rng() * (feld.maxX - feld.minX);
    z = feld.minZ + rng() * (feld.maxZ - feld.minZ);
   } while (!waterAt(x, z) && ++versuche < 40);
   if (!waterAt(x, z)) continue;
   this.fische.push({x, z, yaw: rng() * 6.3, tempo: 1.4 + rng() * 2.2,
    wackeln: rng() * 6.3, tiefe: -.75 - rng() * .9, feld});
  }
  this.fischNetz = netz(scene, fischGeometrie(), 0x93a8a0, this.fische.length, .35);

  // Delfine springen in Bögen; die Bahn ist eine Sinuskurve über der Fläche.
  this.delfine = [];
  for (let k = 0; k < 7; k++) {
   let x = 0, z = 0, versuche = 0;
   do {x = 200 + rng() * 170; z = -300 + rng() * 620;} while (!waterAt(x, z) && ++versuche < 40);
   if (waterAt(x, z)) this.delfine.push({x, z, yaw: rng() * 6.3, tempo: 5 + rng() * 3, phase: rng() * 6.3});
  }
  this.delfinNetz = netz(scene, delfinGeometrie(), 0x6f8894, this.delfine.length, .4);

  // Alligatoren treiben im Sumpf und drehen sich zum Spieler.
  this.alligatoren = [];
  for (let k = 0; k < 9; k++) {
   let x = 0, z = 0, versuche = 0;
   do {
    x = SUMPF.minX + rng() * (SUMPF.maxX - SUMPF.minX);
    z = SUMPF.minZ + rng() * (SUMPF.maxZ - SUMPF.minZ);
   } while (!waterAt(x, z) && ++versuche < 40);
   if (waterAt(x, z)) this.alligatoren.push({x, z, yaw: rng() * 6.3, tempo: .35 + rng() * .5, wackeln: rng() * 6.3});
  }
  this.alligatorNetz = netz(scene, alligatorGeometrie(), 0x4a5740, this.alligatoren.length, .9);
 }

 // Wird aufgeschreckt, wenn geschossen wird. Klingt von selbst wieder ab.
 aufschrecken() {this.scheu = 1;}

 // Liefert zurück, wie viele Tiere gerade nah und vor dem Spieler sind —
 // die Kamera-App nutzt das für die Wildtieraufnahmen.
 imBild(p, yaw, weite = 45) {
  let n = 0;
  const sin = Math.sin(yaw), cos = Math.cos(yaw);
  const pruefe = liste => {
   for (const a of liste) {
    const dx = a.x - p.x, dz = a.z - p.z, d = Math.hypot(dx, dz);
    if (d > weite || d < .5) continue;
    if ((dx * sin + dz * cos) / d > .55) n++;
   }
  };
  pruefe(this.moewen.map(m => ({x: m.mx + Math.cos(m.w) * m.r, z: m.mz + Math.sin(m.w) * m.r})));
  pruefe(this.fische);
  pruefe(this.delfine);
  pruefe(this.alligatoren);
  return n;
 }

 update(dt, zeit, p) {
  const o = this.hilfe;
  this.scheu = Math.max(0, this.scheu - dt * .35);

  // Möwen: Kreisbahn, Höhe und Tempo steigen bei Störung.
  const stoerung = Math.min(1, this.scheu);
  this.moewen.forEach((m, i) => {
   m.w += dt * m.tempo * (1 + stoerung * 1.6);
   const x = m.mx + Math.cos(m.w) * m.r, z = m.mz + Math.sin(m.w) * m.r;
   const nah = Math.hypot(x - p.x, z - p.z) < 40 ? 1 : 0;
   const y = m.hoehe + Math.sin(zeit * .5 + m.versatz) * 2.4 + (stoerung + nah) * 9;
   o.position.set(x, y, z);
   o.rotation.set(0, -m.w + Math.PI / 2, Math.sin(zeit * 6 + m.flug) * .35);
   // Flügelschlag über die Breite: einzelne Flügel gehen bei Instanzen nicht.
   const schlag = 1 + Math.sin(zeit * (8 + stoerung * 6) + m.flug) * .28;
   o.scale.set(schlag, 1, 1);
   o.updateMatrix();
   this.moewenNetz.setMatrixAt(i, o.matrix);
  });
  this.moewenNetz.instanceMatrix.needsUpdate = true;

  this.fische.forEach((f, i) => {
   const dx = f.x - p.x, dz = f.z - p.z, d = Math.hypot(dx, dz);
   if (d < 14) f.yaw = Math.atan2(dx, dz);          // vom Spieler weg
   else f.yaw += Math.sin(zeit * .7 + f.wackeln) * dt * 1.2;
   const tempo = f.tempo * (d < 14 ? 3.2 : 1);
   let nx = f.x + Math.sin(f.yaw) * tempo * dt, nz = f.z + Math.cos(f.yaw) * tempo * dt;
   if (nx < f.feld.minX || nx > f.feld.maxX || nz < f.feld.minZ || nz > f.feld.maxZ || !waterAt(nx, nz)) {
    f.yaw += Math.PI * .6; nx = f.x; nz = f.z;
   }
   f.x = nx; f.z = nz;
   o.position.set(f.x, f.tiefe + Math.sin(zeit * 2 + f.wackeln) * .12, f.z);
   o.rotation.set(0, f.yaw, Math.sin(zeit * 9 + f.wackeln) * .22);
   o.scale.setScalar(1);
   o.updateMatrix();
   this.fischNetz.setMatrixAt(i, o.matrix);
  });
  this.fischNetz.instanceMatrix.needsUpdate = true;

  this.delfine.forEach((dl, i) => {
   dl.phase += dt * .55;
   dl.x += Math.sin(dl.yaw) * dl.tempo * dt;
   dl.z += Math.cos(dl.yaw) * dl.tempo * dt;
   if (!waterAt(dl.x, dl.z)) {dl.yaw += Math.PI * .7; dl.x += Math.sin(dl.yaw) * 4; dl.z += Math.cos(dl.yaw) * 4;}
   const bogen = Math.sin(dl.phase);
   o.position.set(dl.x, bogen > 0 ? bogen * 1.9 - .5 : -1.1, dl.z);
   o.rotation.set(Math.cos(dl.phase) * .8, dl.yaw, 0);
   o.scale.setScalar(1);
   o.updateMatrix();
   this.delfinNetz.setMatrixAt(i, o.matrix);
  });
  this.delfinNetz.instanceMatrix.needsUpdate = true;

  this.alligatoren.forEach((a, i) => {
   const dx = p.x - a.x, dz = p.z - a.z, d = Math.hypot(dx, dz);
   if (d < 30) a.yaw += Math.atan2(Math.sin(Math.atan2(dx, dz) - a.yaw), Math.cos(Math.atan2(dx, dz) - a.yaw)) * dt;
   else a.yaw += Math.sin(zeit * .3 + a.wackeln) * dt * .4;
   const nx = a.x + Math.sin(a.yaw) * a.tempo * dt, nz = a.z + Math.cos(a.yaw) * a.tempo * dt;
   if (waterAt(nx, nz)) {a.x = nx; a.z = nz;} else a.yaw += Math.PI * .5;
   o.position.set(a.x, -.52 + Math.sin(zeit * 1.1 + a.wackeln) * .05, a.z);
   o.rotation.set(0, a.yaw, Math.sin(zeit * 1.4 + a.wackeln) * .06);
   o.scale.setScalar(1);
   o.updateMatrix();
   this.alligatorNetz.setMatrixAt(i, o.matrix);
  });
  this.alligatorNetz.instanceMatrix.needsUpdate = true;
 }
}
