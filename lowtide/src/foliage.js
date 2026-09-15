import * as T from './vendor/three.module.js';
import {groundAt} from './content.js';
// Laub.
//
// Bäume waren gestapelte Kisten: drei bis vier Quader übereinander, als
// Instanzen im Weltraster. Aus der Ferne geht das durch, aus zwanzig Metern
// sieht man Regalbretter. Auf jedem Referenzbild ist Grün das Gegenteil
// davon — durchbrochen, unregelmäßig, mit Licht dazwischen.
//
// Gelöst mit gekreuzten Flächen und einer Alphakarte, wie es Vegetation seit
// jeher macht. Die Karte wird erzeugt, nicht geladen: die HTML soll
// eigenständig bleiben, und ein Blattbüschel ist einfacher zu zeichnen als
// zu beschreiben.
//
// Nebeneffekt, der nicht der Grund war, aber zählt: aus dreitausend Bäumen
// zu je fünf Kisten werden zwei InstancedMeshes.

const AUFLOESUNG = 256;

// Blattbüschel auf durchsichtigem Grund. Viele kleine Ellipsen in gestreuten
// Grüntönen, dichter zur Mitte, ausgefranst am Rand.
function blattKarte(basis) {
 const c = document.createElement('canvas');
 c.width = c.height = AUFLOESUNG;
 const g = c.getContext('2d');
 g.clearRect(0, 0, AUFLOESUNG, AUFLOESUNG);
 let z = 99991;
 const r = () => {z = (z * 1664525 + 1013904223) >>> 0; return z / 4294967296;};
 const grund = new T.Color(basis);
 for (let i = 0; i < 260; i++) {
  // Zur Mitte hin dichter: sonst wird das Büschel ein Rechteck.
  const a = r() * Math.PI * 2, d = Math.pow(r(), .55) * .43;
  const x = (.5 + Math.cos(a) * d) * AUFLOESUNG;
  const y = (.5 + Math.sin(a) * d * .92) * AUFLOESUNG;
  const gross = (10 + r() * 20) * (1 - d * .8);
  // Die Karte ist eine Maske mit leichter Aufhellung, kein Grünton: die
  // eigentliche Farbe kommt je Baum aus instanceColor. Im ersten Versuch war
  // die Karte selbst grün — Grün mal Grün ergab fast schwarze Kronen.
  const hell = .82 + r() * .34 - d * .18;
  const f = grund.clone().multiplyScalar(hell);
  g.fillStyle = `rgba(${f.r * 255 | 0},${f.g * 255 | 0},${f.b * 255 | 0},${.72 + r() * .28})`;
  g.beginPath();
  g.ellipse(x, y, gross, gross * (.5 + r() * .5), r() * Math.PI, 0, Math.PI * 2);
  g.fill();
 }
 const t = new T.CanvasTexture(c);
 t.colorSpace = T.SRGBColorSpace;
 t.anisotropy = 4;
 return t;
}

// Drei gekreuzte Flächen. Eine einzelne verschwindet, sobald man seitlich
// draufsieht; drei genügen, vier kosten ohne sichtbaren Gewinn.
function kroneGeometrie() {
 const pos = [], uv = [], nor = [], idx = [];
 for (let k = 0; k < 3; k++) {
  const a = k * Math.PI / 3, c = Math.cos(a) * .5, s = Math.sin(a) * .5;
  const b = pos.length / 3;
  pos.push(-c, 0, -s, c, 0, s, c, 1, s, -c, 1, -s);
  uv.push(0, 0, 1, 0, 1, 1, 0, 1);
  // Normalen nach außen und oben gemischt: eine senkrechte Fläche mit
  // waagerechter Normale bekommt von der Mittagssonne keinen Diffusanteil
  // und wird schwarz — derselbe Grund wie beim Bewuchs.
  for (let q = 0; q < 4; q++) nor.push(s * .5, .8, -c * .5);
  idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
 }
 const g = new T.BufferGeometry();
 g.setAttribute('position', new T.Float32BufferAttribute(pos, 3));
 g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
 g.setAttribute('normal', new T.Float32BufferAttribute(nor, 3));
 // Weiße Eckenfarben. Ohne sie liest three bei vertexColors ein fehlendes
 // Attribut als schwarz, und instanceColor kommt gar nicht erst zum Zug.
 // Derselbe Fehler wie beim Bewuchs — und beim ersten Anlauf hier trotzdem
 // wieder gemacht, obwohl er im Kommentar von grass.js steht.
 g.setAttribute('color', new T.Float32BufferAttribute(new Array(pos.length).fill(1), 3));
 g.setIndex(idx);
 return g;
}

function windAufsetzen(material) {
 material.onBeforeCompile = shader => {
  shader.uniforms.bZeit = material.userData.bZeit = {value: 0};
  shader.uniforms.bStaerke = material.userData.bStaerke = {value: .1};
  shader.vertexShader = shader.vertexShader
   .replace('#include <common>', '#include <common>\nuniform float bZeit, bStaerke;')
   .replace('#include <begin_vertex>', `#include <begin_vertex>
   {
    vec3 wurzel = vec3(instanceMatrix[3][0], instanceMatrix[3][1], instanceMatrix[3][2]);
    float phase = wurzel.x * 0.13 + wurzel.z * 0.11;
    float schwung = sin(bZeit * 1.1 + phase) * 0.7 + sin(bZeit * 2.1 + phase * 1.9) * 0.3;
    // Nur oben: der Stamm steht, die Krone geht mit.
    transformed.x += schwung * bStaerke * transformed.y;
    transformed.z += schwung * bStaerke * 0.7 * transformed.y;
   }`);
  // Rückseiten nicht umdrehen. Bei DoubleSide kehrt three die Normale für
  // die Rückseite um; bei drei gekreuzten Flächen sieht man aber immer die
  // Hälfte von hinten, und die stand dann im Schatten. Das war der Grund für
  // die fast schwarzen Kronen — nicht die Farbe, wie ich zuerst annahm.
  shader.fragmentShader = shader.fragmentShader
   .replace('#include <normal_fragment_begin>',
    '#include <normal_fragment_begin>\n normal = normalize(vNormal);');
 };
 material.needsUpdate = true;
}

// Zwei Bauformen: 'nadel' schmal und hoch, 'laub' breit und rund.
export class Laubwerk {
 constructor(scene) {
  this.scene = scene;
  this.liste = [];
 }
 // Von regions.js aufgerufen, solange die Welt gebaut wird.
 hinzu(x, z, hoehe, art = 'laub', farbe = 0x4a6b45) {
  this.liste.push({x, z, hoehe, art, farbe});
 }
 bauen() {
  if (!this.liste.length) return;
  const n = this.liste.length;
  const stamm = new T.CylinderGeometry(.07, .13, 1, 6);
  stamm.translate(0, .5, 0);
  this.staemme = new T.InstancedMesh(stamm,
   new T.MeshStandardMaterial({color: 0x6b5a41, roughness: 1}), n);
  const laub = new T.MeshStandardMaterial({
   map: blattKarte(0xe6f0d8), alphaTest: .42, side: T.DoubleSide,
   roughness: .92, metalness: 0, color: 0xffffff, vertexColors: true
  });
  windAufsetzen(laub);
  this.laubMaterial = laub;
  this.kronen = new T.InstancedMesh(kroneGeometrie(), laub, n);
  this.kronen.instanceColor = new T.InstancedBufferAttribute(new Float32Array(n * 3), 3);
  const o = new T.Object3D(), farbe = new T.Color();
  const farben = this.kronen.instanceColor.array;
  this.liste.forEach((b, i) => {
   const y = groundAt(b.x, b.z);
   const nadel = b.art === 'nadel';
   const breite = b.hoehe * (nadel ? .30 : .52);
   // Die Krone beginnt tiefer, als der Stamm hoch ist, und überdeckt ihn ein
   // Stück. Vorher saß sie oben auf und der Stamm stand als nackte Stange
   // darunter.
   const stammHoehe = b.hoehe * (nadel ? .30 : .46);
   const kronenFuss = b.hoehe * (nadel ? .17 : .28);
   o.position.set(b.x, y, b.z);
   o.rotation.set(0, 0, 0);
   o.scale.set(b.hoehe * .09, stammHoehe, b.hoehe * .09);
   o.updateMatrix();
   this.staemme.setMatrixAt(i, o.matrix);
   o.position.set(b.x, y + kronenFuss, b.z);
   o.rotation.set(0, (b.x * 7.1 + b.z * 3.3) % Math.PI, 0);
   o.scale.set(breite, b.hoehe - kronenFuss, breite);
   o.updateMatrix();
   this.kronen.setMatrixAt(i, o.matrix);
   // Die Baumfarben stammen aus der Zeit, als sie direkt auf eine Kiste
   // gingen. Als Faktor auf eine helle Maske sind sie zu dunkel; anheben
   // statt überall in regions.js nachzuziehen.
   farbe.setHex(b.farbe).multiplyScalar(1.55);
   farben[i * 3] = Math.min(1, farbe.r);
   farben[i * 3 + 1] = Math.min(1, farbe.g);
   farben[i * 3 + 2] = Math.min(1, farbe.b);
  });
  for (const netz of [this.staemme, this.kronen]) {
   netz.castShadow = true;
   netz.receiveShadow = true;
   netz.instanceMatrix.needsUpdate = true;
   netz.computeBoundingSphere();
   this.scene.add(netz);
  }
  this.kronen.instanceColor.needsUpdate = true;
 }
 update(zeit, staerke = 1) {
  const u = this.laubMaterial?.userData;
  if (!u?.bZeit) return;
  u.bZeit.value = zeit;
  u.bStaerke.value = .035 + staerke * .075;
 }
 get anzahl() {return this.liste.length;}
}
