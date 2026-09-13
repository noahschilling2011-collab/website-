import * as T from './vendor/three.module.js';
import {groundAt, waterAt, onRoad} from './content.js';
// Bodenbewuchs.
//
// Die Grünflächen der Karte sind Platten in einem Grünton. Aus Augenhöhe
// sieht man deshalb auf lackiertes Papier: keine Halme, keine Kante, kein
// Übergang zum Boden. Das fällt bei jedem Schritt außerhalb der Innenstadt
// auf, und es ist die Fläche, die man am längsten sieht.
//
// Gelöst als ein einziger InstancedMesh, der dem Spieler folgt: Halme
// entstehen nicht in der ganzen Welt, sondern in einem Ring um ihn herum und
// werden neu gesetzt, sobald er ihn verlässt. Ein Draw Call, feste
// Speichergröße, unabhängig von der Kartengröße.

const ANZAHL = 3400, RADIUS = 46, NEUSETZEN = 14;
// Halme je Bild bei einer Umsetzung. Achteinhalb Bilder für den ganzen Ring;
// die alten Halme bleiben derweil stehen, sichtbar ist der Übergang nicht.
const JE_BILD = 400;

// Ein Büschel aus drei gekreuzten Blättern. Eine einzelne Fläche verschwindet,
// sobald man seitlich draufsieht.
function halmGeometrie() {
 const pos = [], uv = [], idx = [];
 const blaetter = 3;
 for (let b = 0; b < blaetter; b++) {
  const a = b / blaetter * Math.PI, c = Math.cos(a) * .5, s = Math.sin(a) * .5;
  const basis = pos.length / 3;
  // Ein Blatt: unten breit, oben spitz, leicht geneigt.
  pos.push(-c, 0, -s, c, 0, s, c * .55, 1, s * .55 + .18, -c * .55, 1, -s * .55 + .18);
  uv.push(0, 0, 1, 0, 1, 1, 0, 1);
  idx.push(basis, basis + 1, basis + 2, basis, basis + 2, basis + 3);
 }
 const g = new T.BufferGeometry();
 g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
 g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
 // Weiße Eckenfarben. Die Farbe je Büschel kommt aus instanceColor, aber
 // three multipliziert vColor nur, wenn vertexColors an ist — und dann liest
 // der Shader ein color-Attribut, das ohne diese Zeile fehlt und schwarz
 // gelesen wird. Genau das war die erste Fassung: ein Feld schwarzer Scherben.
 g.setAttribute('color', new T.Float32BufferAttribute(new Array(pos.length).fill(1), 3));
 // Normalen zeigen nach oben statt aus der Fläche. Geometrisch ist das
 // falsch, aber ein senkrechtes Blatt mit waagerechter Normale bekommt von
 // einer hochstehenden Sonne null Diffusanteil und wird schwarz — genau so
 // sah das Feld im ersten Versuch aus. Nach oben gerichtet nimmt der Halm
 // dasselbe Licht wie der Boden, auf dem er steht.
 const oben = [];
 for (let i = 0; i < pos.length / 3; i++) oben.push(0, 1, 0);
 g.setAttribute('normal', new T.Float32BufferAttribute(oben, 3));
 g.setIndex(idx);
 return g;
}

// Wind. Die Halme sind Instanzen, also muss die Bewegung in den Vertexshader:
// die Matrizen jedes Bild neu zu schreiben wäre 2600 Mal Trigonometrie auf
// der CPU.
function windAufsetzen(material) {
 material.onBeforeCompile = shader => {
  shader.uniforms.gZeit = material.userData.gZeit = {value: 0};
  shader.uniforms.gStaerke = material.userData.gStaerke = {value: .12};
  shader.vertexShader = shader.vertexShader
   .replace('#include <common>', '#include <common>\nuniform float gZeit, gStaerke;')
   .replace('#include <begin_vertex>', `#include <begin_vertex>
   {
    // Nur die Spitze bewegt sich, der Fuß steht. Die Phase kommt aus der
    // Weltposition der Instanz, sonst wogt das ganze Feld im Gleichtakt.
    vec3 wurzel = vec3(instanceMatrix[3][0], instanceMatrix[3][1], instanceMatrix[3][2]);
    float phase = wurzel.x * 0.21 + wurzel.z * 0.17;
    float schwung = sin(gZeit * 1.7 + phase) * 0.6 + sin(gZeit * 2.9 + phase * 1.7) * 0.4;
    transformed.x += schwung * gStaerke * transformed.y * transformed.y;
    transformed.z += schwung * gStaerke * 0.6 * transformed.y * transformed.y;
   }`);
 };
 material.needsUpdate = true;
}

export class Grasfeld {
 constructor(scene, sim) {
  this.sim = sim;
  const material = new T.MeshLambertMaterial({color: 0xffffff, side: T.DoubleSide, vertexColors: true});
  windAufsetzen(material);
  this.material = material;
  this.netz = new T.InstancedMesh(halmGeometrie(), material, ANZAHL);
  this.netz.instanceColor = new T.InstancedBufferAttribute(new Float32Array(ANZAHL * 3), 3);
  this.netz.castShadow = false;
  this.netz.receiveShadow = true;
  this.netz.frustumCulled = false;
  scene.add(this.netz);
  this.hilfe = new T.Object3D();
  this.mitte = {x: 1e9, z: 1e9};
  this.aufgabe = null;
  this.zufall = (() => {let z = 20260912; return () => {z = (z * 1664525 + 1013904223) >>> 0; return z / 4294967296;};})();
 }

 // Wo darf Gras stehen? Nicht auf Fahrbahn, nicht im Wasser, nicht in der
 // Innenstadt (dort ist alles gepflastert) und nicht am Sandstrand.
 erlaubt(x, z) {
  if (waterAt(x, z)) return false;
  if (onRoad(x, z, 9)) return false;
  if (x > 92 && x < 128) return false;                       // Strandstreifen
  if (x > 119) return z > 366 && z < 434 ? false : true;      // Keys: Damm frei
  if (x > -360 && x < 112 && z > -132 && z < 162) return false; // Innenstadt
  // Die Wohnstraßen der Vororte stehen nicht in roadSegments — sie sind reine
  // Erschließung ohne Verkehr. onRoad kennt sie also nicht.
  if (x > -132 && x < 82) for (const sz of [-260, -305, -350, -395]) if (Math.abs(z - sz) < 8) return false;
  return groundAt(x, z) < 1.5;
 }

 // Beginnt eine Umsetzung. Sie läuft über mehrere Bilder, siehe arbeite().
 setzen(px, pz, sofort = false) {
  this.aufgabe = {
   px, pz, i: 0,
   // Nur die Hindernisse in Reichweite prüfen; über alle Solids der Welt zu
   // laufen wäre bei tausenden Halmen je Umsetzung sechsstellig.
   nahe: this.sim.solids.filter(b =>
    Math.abs(b.x - px) < RADIUS + 20 && Math.abs(b.z - pz) < RADIUS + 20)
  };
  // Sofort merken, wo umgesetzt wird: sonst stellt update() im nächsten Bild
  // fest, dass der Spieler immer noch weit von der alten Mitte weg ist, und
  // fängt von vorn an.
  this.mitte = {x: px, z: pz};
  if (sofort) while (this.aufgabe) this.arbeite(ANZAHL);
 }

 // Ein Stück Arbeit. Alle 3400 Halme in einem Bild zu setzen hieß bei 14 m
 // Auslöseabstand: im Auto alle halbe Sekunde ein sichtbarer Hänger.
 arbeite(menge) {
  const a = this.aufgabe;
  if (!a) return;
  const o = this.hilfe, r = this.zufall, {px, pz, nahe} = a;
  const farben = this.netz.instanceColor.array;
  const ende = Math.min(ANZAHL, a.i + menge);
  for (let i = a.i; i < ende; i++) {
   let x = 0, z = 0, gut = false;
   for (let versuch = 0; versuch < 4 && !gut; versuch++) {
    // winkel statt a: a ist hier oben schon die laufende Aufgabe.
    const winkel = r() * Math.PI * 2, d = Math.sqrt(r()) * RADIUS;
    x = px + Math.cos(winkel) * d; z = pz + Math.sin(winkel) * d;
    gut = this.erlaubt(x, z) && !nahe.some(b =>
     Math.abs(x - b.x) < b.w / 2 + .4 && Math.abs(z - b.z) < b.d / 2 + .4);
   }
   // Erste Fassung: halbmetergroße Büschel. Neben einer 1,80-m-Figur sah das
   // aus wie Schilf im Vorgarten.
   // Abgelehnte Plätze wurden zuerst auf Höhe null gesetzt. Eine Matrix mit
   // Skalierung null ist singulär; die daraus berechnete Normalenmatrix wird
   // NaN, und statt zu verschwinden zeichnete three große schwarze Flächen.
   // Sie wandern deshalb unter den Boden statt auf Größe null.
   const hoehe = .17 + r() * .21, breite = .13 + r() * .11;
   o.position.set(x, gut ? groundAt(x, z) : -60, z);
   o.rotation.set(0, r() * Math.PI, 0);
   o.scale.set(breite, hoehe, breite);
   o.updateMatrix();
   this.netz.setMatrixAt(i, o.matrix);
   // Farbe leicht streuen: ein Feld aus einem einzigen Grün sieht gedruckt aus.
   const t = r();
   farben[i * 3] = .28 + t * .16;
   farben[i * 3 + 1] = .40 + t * .20;
   farben[i * 3 + 2] = .22 + t * .12;
  }
  a.i = ende;
  this.netz.instanceMatrix.needsUpdate = true;
  this.netz.instanceColor.needsUpdate = true;
  if (a.i >= ANZAHL) this.aufgabe = null;
 }

 update(dt, zeit, spieler, wind = 1) {
  if (!this.aufgabe && Math.hypot(spieler.x - this.mitte.x, spieler.z - this.mitte.z) > NEUSETZEN)
   this.setzen(spieler.x, spieler.z);
  this.arbeite(JE_BILD);
  const u = this.material.userData;
  if (u.gZeit) u.gZeit.value = zeit;
  if (u.gStaerke) u.gStaerke.value = .09 + wind * .16;
 }
}
