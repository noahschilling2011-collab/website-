import * as T from './vendor/three.module.js';
import {backeNachMaterial} from './bake.js';
// Detailstufe für die Ferne.
// Eine Figur besteht aus 34, ein Auto aus 55 Einzelmeshes. Aus vierzig Metern
// ist davon nichts mehr zu unterscheiden, gezeichnet werden sie trotzdem alle.
// Hier wird ein Vorbild einmal nach Material zusammengebacken und danach als
// InstancedMesh verteilt: beliebig viele ferne Exemplare kosten so viele Draw
// Calls, wie das Vorbild Materialien hat — nicht mehr.

// Grobe Vorbilder für die Ferne. Das volle Modell zu instanzieren spart zwar
// Draw Calls, schleppt aber weiterhin Fingerglieder und Felgenspeichen mit.
// Diese Silhouetten haben dieselben Umrisse bei einem Bruchteil der Dreiecke.
const stoff = (farbe, rauheit = .7) => new T.MeshStandardMaterial({color: farbe, roughness: rauheit});

function teil(gruppe, geo, material, x, y, z, sx = 1, sy = 1, sz = 1) {
 const m = new T.Mesh(geo, material);
 m.position.set(x, y, z);
 m.scale.set(sx, sy, sz);
 gruppe.add(m);
 return m;
}

export function grobesAuto(farbe = 0x9aa2a6) {
 const g = new T.Group(), wuerfel = new T.BoxGeometry(1, 1, 1);
 const lack = stoff(farbe, .35), glas = stoff(0x35505e, .2), gummi = stoff(0x22282c, .95);
 teil(g, wuerfel, lack, 0, .62, 0, 1.92, .62, 4.3);
 teil(g, wuerfel, lack, 0, 1.02, -.1, 1.7, .3, 2.6);
 teil(g, wuerfel, glas, 0, 1.32, -.15, 1.58, .58, 2.2);
 teil(g, wuerfel, lack, 0, 1.62, -.2, 1.6, .12, 2.1);
 const rad = new T.CylinderGeometry(.36, .36, .26, 8);
 for (const x of [-.92, .92]) for (const z of [-1.35, 1.37]) {
  const r = teil(g, rad, gummi, x, .38, z);
  r.rotation.z = Math.PI / 2;
 }
 return g;
}

export function grobeFigur(hemd = 0x8f9a8a, hose = 0x39424c) {
 const g = new T.Group(), wuerfel = new T.BoxGeometry(1, 1, 1);
 const kugel = new T.SphereGeometry(1, 8, 6);
 // Die Materialien einmal anlegen: stoff() gibt sonst je Aufruf ein neues
 // Objekt zurück, und jedes davon wird beim Backen zu einer eigenen Gruppe.
 const haut = stoff(0xb98d70, .8), stoffHemd = stoff(hemd, .92),
  stoffHose = stoff(hose, .95), haar = stoff(0x2f2a24, .95), schuh = stoff(0x23292c, .8);
 teil(g, wuerfel, stoffHemd, 0, 1.2, 0, .46, .66, .28);
 teil(g, kugel, haut, 0, 1.66, .01, .105, .13, .1);
 teil(g, kugel, haar, 0, 1.72, -.01, .11, .1, .105);
 for (const s of [-1, 1]) {
  teil(g, wuerfel, stoffHose, s * .12, .55, 0, .19, .84, .21);
  teil(g, wuerfel, schuh, s * .12, .07, .05, .21, .12, .32);
  teil(g, wuerfel, stoffHemd, s * .29, 1.14, 0, .15, .62, .18);
 }
 return g;
}

export class Fernstufe {
 constructor(scene, vorbild, maximal) {
  this.maximal = maximal;
  this.hilfe = new T.Object3D();
  this.netze = backeNachMaterial(vorbild).map(({geometry, material}) => {
   const netz = new T.InstancedMesh(geometry, material.clone(), maximal);
   netz.castShadow = true;
   netz.receiveShadow = true;
   netz.frustumCulled = false;
   netz.count = 0;
   scene.add(netz);
   return netz;
  });
  this.anzahl = 0;
 }

 beginn() {this.anzahl = 0;}

 hinzu(x, y, z, yaw, skalierung = 1) {
  if (this.anzahl >= this.maximal) return;
  const o = this.hilfe;
  o.position.set(x, y, z);
  o.rotation.set(0, yaw, 0);
  o.scale.setScalar(skalierung);
  o.updateMatrix();
  for (const netz of this.netze) netz.setMatrixAt(this.anzahl, o.matrix);
  this.anzahl++;
 }

 ende() {
  for (const netz of this.netze) {
   netz.count = this.anzahl;
   netz.instanceMatrix.needsUpdate = true;
  }
 }

 // Wie viele Draw Calls diese Stufe kostet, unabhängig von der Zahl der
 // Exemplare. Für die Messwerte im Debug-Overlay.
 get kosten() {return this.anzahl ? this.netze.length : 0;}
}
