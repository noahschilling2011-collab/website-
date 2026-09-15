import * as T from './vendor/three.module.js';
// Fasst alle Meshes eines Vorbilds nach Material zusammen und liefert je Material
// eine gebackene Geometrie. Damit werden aus einem Auto aus 40 Teilen ein paar
// InstancedMeshes statt 40 Draw Calls pro Exemplar.
export function backeNachMaterial(vorbild) {
 vorbild.updateMatrixWorld(true);
 const eimer = new Map();
 vorbild.traverse(o => {
  if (!o.isMesh || !o.geometry?.attributes?.position) return;
  const geo = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone();
  geo.applyMatrix4(o.matrixWorld);
  if (!geo.attributes.normal) geo.computeVertexNormals();
  const key = o.material.uuid;
  if (!eimer.has(key)) eimer.set(key, {material: o.material, teile: []});
  eimer.get(key).teile.push(geo);
 });
 const gebacken = [];
 for (const {material, teile} of eimer.values()) {
  let punkte = 0;
  for (const g of teile) punkte += g.attributes.position.count;
  const pos = new Float32Array(punkte * 3), nor = new Float32Array(punkte * 3);
  let versatz = 0;
  for (const g of teile) {
   pos.set(g.attributes.position.array, versatz * 3);
   nor.set(g.attributes.normal.array, versatz * 3);
   versatz += g.attributes.position.count;
   g.dispose();
  }
  const zusammen = new T.BufferGeometry();
  zusammen.setAttribute('position', new T.BufferAttribute(pos, 3));
  zusammen.setAttribute('normal', new T.BufferAttribute(nor, 3));
  zusammen.computeBoundingSphere();
  gebacken.push({geometry: zusammen, material});
 }
 return gebacken;
}


// Ein Modell an Ort und Stelle backen, ohne die beweglichen Teile anzufassen.
//
// backeNachMaterial() oben erwartet ein Vorbild, aus dem Instanzen werden. Für
// den fahrenden Verkehr geht das nicht: Räder drehen und lenken, Scheinwerfer
// und Rücklichter schalten pro Fahrzeug. Diese Fassung sammelt alle **übrigen**
// Meshes eines Modells ein, verschmilzt sie nach Material und hängt das
// Ergebnis anstelle der Einzelteile zurück in dieselbe Gruppe.
//
// Die Matrizen werden relativ zur Wurzel gerechnet, nicht in Weltkoordinaten —
// das Modell steht sonst beim ersten Bild doppelt so weit vom Ursprung weg.
// Der Cache ist nicht optional, er ist der Unterschied zwischen einer
// Optimierung und einem Tausch: ohne ihn bekommt jede Figur und jeder Wagen
// eine eigene gebackene Geometrie, und der Prüflauf meldet zu Recht "Figuren
// teilen sich ihre Geometrie — 6 von 13". Gleiche Bauteile mit gleichen
// Materialien ergeben dieselbe Geometrie; der Schlüssel muss nur alles
// enthalten, was die Form oder das Material ändert.
export function backeImModell(wurzel, beweglich = [], cache = null, schluessel = null) {
 wurzel.updateMatrixWorld(true);
 const aus = new Set();
 for (const o of beweglich) {
  if (!o) continue;
  if (o.traverse) o.traverse(c => aus.add(c)); else aus.add(o);
 }
 const invers = wurzel.matrixWorld.clone().invert();
 const eimer = new Map(), alt = [];
 wurzel.traverse(o => {
  if (!o.isMesh || aus.has(o) || !o.geometry?.attributes?.position) return;
  // Scheitelpunktfarben werden nicht mitgebacken — das Gesicht trägt seinen
  // Hautton in den Eckpunkten, und ohne das Attribut wäre es schwarz. Solche
  // Meshes bleiben, wie sie sind.
  if (o.geometry.attributes.color) return;
  // Ein Mesh unter einem beweglichen Teil bleibt ebenfalls draußen.
  for (let p = o.parent; p; p = p.parent) if (aus.has(p)) return;
  alt.push(o);
  const geo = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone();
  geo.applyMatrix4(invers.clone().multiply(o.matrixWorld));
  if (!geo.attributes.normal) geo.computeVertexNormals();
  if (!eimer.has(o.material)) eimer.set(o.material, []);
  eimer.get(o.material).push(geo);
 });
 if (alt.length < 2) return wurzel;
 for (const o of alt) o.parent.remove(o);
 // Gespeichert werden nur die Geometrien, nicht die Materialien: die Form
 // eines Wagens hängt nicht an seiner Lackfarbe. Beim Wiederverwenden kommen
 // die Materialien aus dem Exemplar selbst — in derselben Reihenfolge, in der
 // sie beim Durchlaufen aufgetreten sind, und die ist bei gleichem Aufbau
 // dieselbe. Stimmt die Zahl der Töpfe nicht, wird neu gebacken statt falsch
 // zusammengesetzt.
 const stoffe = [...eimer.keys()];
 if (cache && schluessel && cache.get(schluessel)?.length === stoffe.length) {
  cache.get(schluessel).forEach((geometry, i) => {
   const netz = new T.Mesh(geometry, stoffe[i]);
   netz.castShadow = false;
   netz.receiveShadow = true;
   wurzel.add(netz);
  });
  for (const g of eimer.values()) for (const teil of g) teil.dispose();
  return wurzel;
 }
 const gebacken = [];
 for (const [material, teile] of eimer) {
  let punkte = 0;
  for (const g of teile) punkte += g.attributes.position.count;
  // Texturkoordinaten müssen mit, sobald ein Teil welche hat: das Kennzeichen
  // holt sich seinen Ausschnitt aus dem Atlas allein über die UVs, und ohne
  // sie zeigt jedes Schild der Stadt denselben Fleck. Teile ohne UV bekommen
  // Nullen — sie tragen ohnehin keine Textur.
  const mitUV = teile.some(g => g.attributes.uv);
  const pos = new Float32Array(punkte * 3), nor = new Float32Array(punkte * 3);
  const uvs = mitUV ? new Float32Array(punkte * 2) : null;
  let versatz = 0;
  for (const g of teile) {
   pos.set(g.attributes.position.array, versatz * 3);
   nor.set(g.attributes.normal.array, versatz * 3);
   if (uvs && g.attributes.uv) uvs.set(g.attributes.uv.array, versatz * 2);
   versatz += g.attributes.position.count;
   g.dispose();
  }
  const zusammen = new T.BufferGeometry();
  zusammen.setAttribute('position', new T.BufferAttribute(pos, 3));
  zusammen.setAttribute('normal', new T.BufferAttribute(nor, 3));
  if (uvs) zusammen.setAttribute('uv', new T.BufferAttribute(uvs, 2));
  zusammen.computeBoundingSphere();
  const netz = new T.Mesh(zusammen, material);
  netz.castShadow = false;
  netz.receiveShadow = true;
  wurzel.add(netz);
  gebacken.push(zusammen);
 }
 if (cache && schluessel) cache.set(schluessel, gebacken);
 return wurzel;
}
