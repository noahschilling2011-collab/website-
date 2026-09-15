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
 // Licht auch in der Ferne. Die Scheinwerfer des vollen Modells schaltet
 // expanded-world.js mit dem Sonnenstand hoch — jenseits von 52 Metern gibt
 // es dieses Modell aber nicht mehr, und damit war eine nächtliche Straße
 // ab dieser Entfernung unbeleuchtet. Bei Nacht ist von fernem Verkehr fast
 // nur das Licht zu sehen; ohne es wirkt die Stadt tot.
 //
 // Zwei zusätzliche Materialien heißen zwei zusätzliche Draw Calls für die
 // gesamte ferne Flotte, unabhängig von ihrer Zahl.
 const vorn = new T.MeshStandardMaterial({color: 0xf4e4bb, emissive: 0xffd9a4, emissiveIntensity: 0});
 const hinten = new T.MeshStandardMaterial({color: 0xa73833, emissive: 0xd33a30, emissiveIntensity: 0});
 for (const x of [-.62, .62]) {
  teil(g, wuerfel, vorn, x, .74, 2.14, .5, .16, .1);
  teil(g, wuerfel, hinten, x, .8, -2.16, .56, .14, .1);
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
   // Kein Schattenwurf für die Ferne. Der Schattendurchgang war mit 586 von
   // 900 Zeichenaufrufen und einer Million Dreiecken der mit Abstand teuerste
   // Posten des Bildes — und diese Netze stehen mit frustumCulled = false
   // darin, also immer, egal wo die Sonne steht. Ab vierzig Metern ist der
   // Schatten einer Figur oder eines Autos ohnehin ein grauer Fleck.
   netz.castShadow = false;
   netz.receiveShadow = true;
   netz.frustumCulled = false;
   netz.count = 0;
   scene.add(netz);
   return netz;
  });
  this.anzahl = 0;
 }

 beginn() {this.anzahl = 0;}

 // Nachts leuchten die Lampenflächen der Vorbilder. Betroffen ist nur, was
 // im Vorbild eine Eigenfarbe trägt — Lack, Glas und Gummi bleiben, wie sie
 // sind. Der Faktor ist derselbe Nachtanteil, mit dem das volle Modell
 // seine Scheinwerfer hochfährt.
 leuchten(nacht) {
  for (const netz of this.netze) {
   const m = netz.material;
   if (!m.emissive || m.emissive.getHex() === 0) continue;
   // Rücklicht oder Scheinwerfer? Über Rot gegen Grün ginge es knapp
   // daneben: das warme Scheinwerferweiß 0xffd9a4 hat linear r = 1,00 und
   // g = 0,71 und wäre damit auch "rot". Der Blauanteil trennt sauber —
   // 0,37 gegen 0,03.
   const rot = m.emissive.b < .12;
   m.emissiveIntensity = nacht * (rot ? 1.6 : 3.2);
  }
 }

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

// Schattenkörper. Der Schattendurchgang war mit 576 von 890 Zeichenaufrufen
// der teuerste Posten des Bildes, und die Aufschlüsselung zeigte, woher:
// **294 Aufrufe für Figuren und 115 für Fahrzeuge bei zusammen 80.000
// Dreiecken**. Das ist kein Geometrieproblem, sondern reiner Aufruf-Overhead —
// jede nahe Figur wirft ihren Schatten aus 34 Einzelnetzen, jedes Auto aus 20.
//
// Ein Mensch wirft aus fünf Metern Entfernung keinen Schatten, in dem man
// Finger zählt. Ein Kapselkörper je Figur, ein Quader je Auto, alle Exemplare
// in **einem** Instanzennetz: der ganze Personen- und Fahrzeugschatten kostet
// danach zwei Aufrufe.
//
// Das Netz muss sichtbar bleiben — was unsichtbar ist, wirft in three.js auch
// keinen Schatten. Ein Material ohne Farb- und Tiefenschreiben zeichnet im
// Farbdurchgang nichts und kostet dort einen Aufruf.
export class Schattenkoerper {
 constructor(scene, geometrie, maximal, hoehe = 0) {
  const material = new T.MeshBasicMaterial({colorWrite: false, depthWrite: false});
  this.netz = new T.InstancedMesh(geometrie, material, maximal);
  this.netz.castShadow = true;
  this.netz.receiveShadow = false;
  this.netz.frustumCulled = false;
  this.netz.count = 0;
  this.hoehe = hoehe;
  this.hilfe = new T.Object3D();
  this.n = 0;
  scene.add(this.netz);
 }
 beginn() {this.n = 0;}
 hinzu(x, y, z, yaw = 0, skalierung = 1) {
  if (this.n >= this.netz.instanceMatrix.count) return;
  const h = this.hilfe;
  h.position.set(x, y + this.hoehe * skalierung, z);
  h.rotation.set(0, yaw, 0);
  h.scale.setScalar(skalierung);
  h.updateMatrix();
  this.netz.setMatrixAt(this.n++, h.matrix);
 }
 ende() {this.netz.count = this.n; this.netz.instanceMatrix.needsUpdate = true;}
}
