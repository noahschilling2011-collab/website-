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

