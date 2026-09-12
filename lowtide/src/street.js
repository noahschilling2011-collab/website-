import * as T from './vendor/three.module.js';
import {detailedCar} from './art-direction.js';
import {backeNachMaterial} from './bake.js';
// Erkennungsfarbe: nur das Lackmaterial des Vorbilds trägt sie.
const LACK_MARKE=0x00ff2a;
import {roadSegments, groundAt, waterAt, intersections, ampelFrei, AMPEL_TAKT, onRoad, locations} from './content.js';
// Die Serviceräume sind vorn offen und haben nur drei Wände als Körper.
// sim.blocked meldet ihr Inneres deshalb als frei — dort standen Laternen
// und Masten mitten im Laden.
const RAEUME=['garage','shop','clinic','home','club','diner','motel','records']
 .map(id=>({x:locations[id].x, z:locations[id].z-4, w:(id==='garage'?22:16)/2+2, d:10}));
function imRaum(x,z){return RAEUME.some(r=>Math.abs(x-r.x)<r.w&&Math.abs(z-r.z)<r.d);}
// Straßenmöblierung für Port Mercy.
// Vorher standen an den Straßen Laternen nur im Hafenbecken; der Rest der Stadt
// war leere Fahrbahn zwischen leeren Grundstücken. Alles hier läuft über die
// InstancedMesh-Sammlung von World.box oder über eigene InstancedMeshes —
// hunderte Objekte kosten dadurch eine Handvoll Draw Calls, nicht hunderte.

const ABSTAND_LATERNE = 36;
const ABSTAND_KLEINKRAM = 27;
const ABSTAND_MAST = 48;

// Ein deterministischer Generator, damit die Stadt bei jedem Start gleich aussieht.
function zufall(seed = 9137) {
 return () => {seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296;};
}

// Achsparallele Segmente: die Ausrichtung ergibt sich aus der längeren Seite.
function segmentInfo(r) {
 const laenge = Math.hypot(r.x2 - r.x1, r.z2 - r.z1);
 const senkrecht = Math.abs(r.z2 - r.z1) >= Math.abs(r.x2 - r.x1);
 return {laenge, senkrecht, dx: (r.x2 - r.x1) / laenge, dz: (r.z2 - r.z1) / laenge};
}

const LACKE = [0x8d9aa2, 0x3d4a55, 0xb5b0a4, 0x6d4f48, 0x2f4a52, 0x9c8858, 0x54666b, 0xa8544c];

export class Street {
 constructor(world) {
  this.world = world;
  this.rng = zufall();
  this.ampelPhase = 0;
  this.parkplaetze = [];
  this.kreuzungsListe = intersections;
 }

 frei(x, z, radius = 2) {
  if (waterAt(x, z) || imRaum(x, z)) return false;
  return !this.world.sim.blocked({x, z}, radius);
 }

 // Für Strandmöbel: alles, was am Wasser steht, muss zusätzlich von der
 // Fahrbahn weg. Die Uferstraße bei z = 200 kreuzt den Strand.
 freiAmStrand(x, z, radius = 2) {
  return this.frei(x, z, radius) && !onRoad(x, z, 9);
 }

 // Wird aus ExpandedWorld.build gerufen, also noch vor World.flush.
 bauen() {
  const w = this.world, rng = this.rng;
  for (const r of roadSegments) {
   const {laenge, senkrecht, dx, dz} = segmentInfo(r);
   if (laenge < 30) continue;
   const halb = r.w / 2;
   // Bordstein und Gehweg begleiten jede Straße auf beiden Seiten.
   for (const seite of [-1, 1]) {
    const ox = senkrecht ? seite * (halb + .5) : 0, oz = senkrecht ? 0 : seite * (halb + .5);
    const mx = (r.x1 + r.x2) / 2 + ox, mz = (r.z1 + r.z2) / 2 + oz;
    w.box(mx, .13, mz, senkrecht ? 1 : laenge, .26, senkrecht ? laenge : 1, 0x8e8b7f);
    const gx = senkrecht ? seite * (halb + 2.6) : 0, gz = senkrecht ? 0 : seite * (halb + 2.6);
    w.box((r.x1 + r.x2) / 2 + gx, .09, (r.z1 + r.z2) / 2 + gz,
     senkrecht ? 4.2 : laenge, .18, senkrecht ? laenge : 4.2, 0x82806f);
   }

   for (let s = 12; s < laenge - 12; s += ABSTAND_LATERNE) {
    const seite = (Math.floor(s / ABSTAND_LATERNE) % 2) ? 1 : -1;
    const bx = r.x1 + dx * s + (senkrecht ? seite * (halb + 1.6) : 0);
    const bz = r.z1 + dz * s + (senkrecht ? 0 : seite * (halb + 1.6));
    if (this.frei(bx, bz, 1.2)) w.lamp(bx, bz);
   }

   // Gullis in der Rinne, an beiden Seiten versetzt.
   for (let s = 20; s < laenge - 10; s += 31) {
    for (const seite of [-1, 1]) {
     const gx = r.x1 + dx * s + (senkrecht ? seite * (halb - .8) : 0);
     const gz = r.z1 + dz * s + (senkrecht ? 0 : seite * (halb - .8));
     w.box(gx, .085, gz, .8, .04, .8, 0x4a4f4c);
    }
   }

   // Kleinkram am Gehwegrand: Hydranten, Tonnen, Bänke, Zeitungskästen, Poller.
   for (let s = 18; s < laenge - 12; s += ABSTAND_KLEINKRAM) {
    const seite = rng() < .5 ? -1 : 1;
    const x = r.x1 + dx * s + (senkrecht ? seite * (halb + 2.4) : 0);
    const z = r.z1 + dz * s + (senkrecht ? 0 : seite * (halb + 2.4));
    if (!this.frei(x, z, 1)) continue;
    const dreh = senkrecht ? 0 : Math.PI / 2;
    const art = rng();
    if (art < .17) {                                   // Hydrant
     w.box(x, .38, z, .3, .76, .3, 0xb2564b);
     w.box(x, .78, z, .44, .12, .44, 0xb2564b);
     w.box(x, .5, z, .72, .14, .18, 0xb2564b, dreh);
    } else if (art < .40) {                            // Mülltonne
     w.box(x, .55, z, .74, 1.1, .74, 0x3e5750, dreh);
     w.box(x, 1.13, z, .82, .08, .82, 0x2b3c38, dreh);
    } else if (art < .56) {                            // Bank
     w.box(x, .42, z, senkrecht ? .55 : 2.1, .1, senkrecht ? 2.1 : .55, 0x7d6247);
     w.box(x + (senkrecht ? -.24 : 0), .72, z + (senkrecht ? 0 : -.24),
      senkrecht ? .1 : 2.1, .55, senkrecht ? 2.1 : .1, 0x7d6247);
     for (const e of [-.85, .85]) w.box(x + (senkrecht ? 0 : e), .21, z + (senkrecht ? e : 0), .16, .42, .16, 0x39443f);
    } else if (art < .70) {                            // Zeitungskästen
     for (let k = 0; k < 2; k++) {
      const ox = senkrecht ? 0 : (k - .5) * .62, oz = senkrecht ? (k - .5) * .62 : 0;
      w.box(x + ox, .55, z + oz, .5, 1.1, .42, [0xb0864a, 0x4a6f86][k], dreh);
     }
    } else if (art < .80) {                            // Fahrradständer
     for (let k = 0; k < 3; k++) {
      const ox = senkrecht ? 0 : (k - 1) * .7, oz = senkrecht ? (k - 1) * .7 : 0;
      w.box(x + ox, .45, z + oz, senkrecht ? .07 : .6, .9, senkrecht ? .6 : .07, 0x707a76);
     }
    } else if (art < .88) {                            // Poller
     for (let k = 0; k < 3; k++) {
      const ox = senkrecht ? 0 : (k - 1) * 1.4, oz = senkrecht ? (k - 1) * 1.4 : 0;
      w.box(x + ox, .43, z + oz, .2, .86, .2, 0x8d9089);
     }
    } else {                                           // Straßenschild
     w.box(x, 1.25, z, .09, 2.5, .09, 0x6a736f);
     w.box(x, 2.35, z, senkrecht ? .07 : .95, .34, senkrecht ? .95 : .07, 0x54707c);
    }
   }

   // Holzmasten mit gespannten Leitungen — nur an den Nebenstraßen.
   if (r.w <= 15) {
    let vorher = null;
    for (let s = 10; s < laenge - 10; s += ABSTAND_MAST) {
     const seite = 1;
     const x = r.x1 + dx * s + (senkrecht ? seite * (halb + 4.2) : 0);
     const z = r.z1 + dz * s + (senkrecht ? 0 : seite * (halb + 4.2));
     if (!this.frei(x, z, 1)) {vorher = null; continue;}
     w.box(x, 4.4, z, .3, 8.8, .3, 0x6b5c48);
     w.box(x, 8.2, z, senkrecht ? 2.6 : .16, .16, senkrecht ? .16 : 2.6, 0x6b5c48);
     if (vorher) {
      const spanne = Math.hypot(x - vorher.x, z - vorher.z);
      for (const versatz of [-1, 1]) {
       const wx = (x + vorher.x) / 2 + (senkrecht ? versatz : 0);
       const wz = (z + vorher.z) / 2 + (senkrecht ? 0 : versatz);
       // Ein durchhängendes Kabel ginge nur mit eigener Geometrie; hier bleibt
       // es eine gerade Spanne, die aus Straßenhöhe nicht auffällt.
       w.box(wx, 8.05, wz, senkrecht ? .05 : spanne, .05, senkrecht ? spanne : .05, 0x2b2f31);
      }
     }
     vorher = {x, z};
    }
   }

   // Parkbuchten am Bordstein sammeln; die Fahrzeuge kommen später als Instanzen.
   for (let s = 24; s < laenge - 20; s += 6.4) {
    if (rng() > .34) continue;
    const seite = rng() < .5 ? -1 : 1;
    const x = r.x1 + dx * s + (senkrecht ? seite * (halb - 2.1) : 0);
    const z = r.z1 + dz * s + (senkrecht ? 0 : seite * (halb - 2.1));
    if (!this.frei(x, z, 1.6) || Math.abs(groundAt(x, z)) > .2) continue;
    // Nicht in die Kreuzung und nicht ineinander parken.
    if (this.kreuzungsListe.some(k => Math.abs(k.x - x) < 15 && Math.abs(k.z - z) < 15)) continue;
    if (this.parkplaetze.some(p => (p.x - x) ** 2 + (p.z - z) ** 2 < 34)) continue;
    this.parkplaetze.push({x, z, yaw: (senkrecht ? 0 : Math.PI / 2) + (seite < 0 ? Math.PI : 0), lack: LACKE[Math.floor(rng() * LACKE.length)]});
   }
  }

  this.ampelnBauen();
 }

 ampelnBauen() {
  const w = this.world;
  this.ampeln = this.kreuzungsListe.filter(k => Math.abs(groundAt(k.x, k.z)) < .3);
  const nordSued = [], ostWest = [];
  for (const k of this.ampeln) {
   const a = k.breite / 2 + 2.2;
   // Vier Masten je Kreuzung. Der Ausleger zeigt in die Fahrtrichtung, die er regelt.
   for (const [ox, oz, achse, dreh] of [[-a, -a, 0, 0], [a, a, 0, Math.PI], [-a, a, 1, Math.PI / 2], [a, -a, 1, -Math.PI / 2]]) {
    const x = k.x + ox, z = k.z + oz;
    w.box(x, 2.9, z, .18, 5.8, .18, 0x3f4a4d);
    w.box(x + Math.sin(dreh) * 1.6, 5.6, z + Math.cos(dreh) * 1.6, .16, .16, 3.2, 0x3f4a4d, dreh);
    const kx = x + Math.sin(dreh) * 3.1, kz = z + Math.cos(dreh) * 3.1;
    w.box(kx, 4.85, kz, .42, 1.25, .34, 0x27302f, dreh);
    (achse ? ostWest : nordSued).push({x: kx, z: kz, yaw: dreh});
   }
  }
  this.lichtGruppen = [nordSued, ostWest].map(liste => this.ampelLichter(liste));
 }

 // Drei InstancedMeshes je Achse: rot, gelb, grün. Geschaltet wird über
 // emissiveIntensity, damit kein Matrixaufbau pro Bild nötig ist.
 ampelLichter(liste) {
  const geo = new T.SphereGeometry(.13, 10, 8);
  const hoehen = [5.24, 4.85, 4.46];
  const farben = [0xd8453c, 0xe0a844, 0x5fbe72];
  const netze = [];
  const objekt = new T.Object3D();
  for (let i = 0; i < 3; i++) {
   // Die Linse ist im Ruhezustand dunkles Glas; erst emissive macht sie hell.
   const material = new T.MeshStandardMaterial({color: 0x141a19, emissive: farben[i], emissiveIntensity: 0, roughness: .32});
   material.userData.grundfarbe = farben[i];
   const netz = new T.InstancedMesh(geo, material, Math.max(1, liste.length));
   for (let k = 0; k < liste.length; k++) {
    objekt.position.set(liste[k].x + Math.sin(liste[k].yaw) * .2, hoehen[i], liste[k].z + Math.cos(liste[k].yaw) * .2);
    objekt.rotation.set(0, liste[k].yaw, 0);
    objekt.updateMatrix();
    netz.setMatrixAt(k, objekt.matrix);
   }
   netz.count = liste.length;
   netz.instanceMatrix.needsUpdate = true;
   netz.frustumCulled = false;
   this.world.scene.add(netz);
   netze.push({netz, material});
  }
  return netze;
 }

 // Geparkte Fahrzeuge. Ein einziges Vorbild wird nach Material gebacken und
 // als Instanzen verteilt — dieselbe Karosserie wie bei fahrbaren Autos,
 // aber ein paar Draw Calls statt tausend.
 parkendeAutosBauen() {
  if (!this.parkplaetze.length) return;
  // Sparsames Vorbild: geparkte Wagen sind Kulisse. Der Unterschied zum
 // vollen Modell ist aus zwei Metern zu sehen, aus fünf nicht mehr — und es
 // stehen vierhundertvierundsiebzig davon auf der Karte.
 const vorbild = detailedCar(LACK_MARKE, false, true);
  const gebacken = backeNachMaterial(vorbild);
  const objekt = new T.Object3D();
  this.parkendeNetze = [];
  for (const {geometry, material} of gebacken) {
   const eigen = material.clone();
   // Der Lack bekommt Instanzfarben, alles andere behält seinen Ton.
   const istLack = material.color?.getHex() === LACK_MARKE;
   if (istLack) eigen.color.setHex(0xffffff);
   const netz = new T.InstancedMesh(geometry, eigen, this.parkplaetze.length);
   netz.castShadow = true;
   netz.receiveShadow = true;
   this.parkplaetze.forEach((p, i) => {
    objekt.position.set(p.x, groundAt(p.x, p.z), p.z);
    objekt.rotation.set(0, p.yaw, 0);
    objekt.updateMatrix();
    netz.setMatrixAt(i, objekt.matrix);
    if (istLack) netz.setColorAt(i, new T.Color(p.lack));
   });
   netz.instanceMatrix.needsUpdate = true;
   if (netz.instanceColor) netz.instanceColor.needsUpdate = true;
   netz.computeBoundingSphere();
   this.world.scene.add(netz);
   this.parkendeNetze.push(netz);
  }
 }

 // Mercy Beach war eine leere Sandfläche von 24 auf 300 Metern.
 // Promenade, Liegen, Schirme, Rettungstürme, Netze und eine Strandbar.
 strandBauen() {
  const w = this.world, rng = this.rng;
  // Holzpromenade zwischen Straße und Sand.
  w.box(96, .28, 280, 5.5, .3, 300, 0x8a6f4e);
  for (let z = 132; z < 428; z += 2.2) w.box(96, .45, z, 5.5, .06, .9, 0x9a7d58);
  for (let z = 134; z < 428; z += 11) {
   for (const x of [93.5, 98.5]) {
    w.box(x, .78, z, .13, 1, .13, 0x6f5a41);
    w.box(x, 1.2, z, .16, .1, 11, 0x6f5a41);
   }
  }
  for (let z = 140; z < 425; z += 46) {
   // Rettungsturm auf Stelzen, mit Leiter und Flagge.
   const x = 108;
   if (!this.freiAmStrand(x, z, 6)) continue;
   for (const ox of [-1.6, 1.6]) for (const oz of [-1.6, 1.6]) w.box(x + ox, 1.5, z + oz, .2, 3, .2, 0x8a6a4c);
   w.box(x, 3.15, z, 4.2, .3, 4.2, 0xb08a5e);
   w.box(x, 4.1, z, 4, 1.6, 4, 0xd8c193);
   w.box(x, 5.05, z, 4.6, .3, 4.6, 0xa9533f);
   w.box(x - 2.6, 2.9, z, .1, 3.2, .1, 0x8a6a4c);
   w.box(x + 2.6, 5.9, z, .08, 1.6, .08, 0x77726a);
   w.box(x + 3.1, 6.4, z, 1, .6, .05, 0xc9553f);
   // Duschsäule und Abfalltonne an der Promenade.
   w.box(99.5, 1.2, z + 8, .16, 2.4, .16, 0x8b938d);
   w.box(99.5, 2.3, z + 8, .5, .12, .5, 0x8b938d);
   w.box(100.5, .55, z + 12, .74, 1.1, .74, 0x3e5750);
  }
  // Liegen mit Schirmen, paarweise, leicht gedreht.
  for (let z = 138; z < 426; z += 9) {
   if (rng() > .78) continue;
   const gx = 104 + rng() * 9, dreh = (rng() - .5) * .7;
   if (!this.freiAmStrand(gx, z, 4)) continue;
   for (const versatz of [-1.3, 1.3]) {
    const lx = gx + Math.cos(dreh) * versatz, lz = z + Math.sin(dreh) * versatz;
    w.box(lx, .3, lz, .75, .12, 2, 0xd6cdb4, dreh);
    for (const e of [-.85, .85]) w.box(lx, .14, lz + e, .6, .28, .1, 0x9aa39b, dreh);
    w.box(lx, .52, lz - .78, .72, .5, .12, 0xd6cdb4, dreh + .35);
   }
   const schirmFarbe = [0xc9603f, 0x3f7a86, 0xd4a54a, 0xb0526e][Math.floor(rng() * 4)];
   w.box(gx, 1.15, z, .09, 2.3, .09, 0x8f8a7c);
   w.box(gx, 2.16, z, 3.4, .1, 3.4, schirmFarbe, dreh + .78);
   w.box(gx, 2.3, z, 2.5, .1, 2.5, schirmFarbe, dreh + .4);
   w.box(gx, 2.42, z, 1.4, .1, 1.4, schirmFarbe, dreh);
   w.box(gx, 2.5, z, .3, .16, .3, 0x8f8a7c);
  }
  // Beachvolleyball: zwei Felder mit Netz.
  for (const z of [214, 340]) {
   if (!this.freiAmStrand(112, z, 10)) continue;
   for (const ox of [-4.5, 4.5]) w.box(112 + ox, 1.2, z, .12, 2.4, .12, 0x7f776a);
   w.box(112, 1.9, z, 9, .9, .05, 0xdcd7c4);
   for (const e of [[-4.5, -8], [4.5, -8], [-4.5, 8], [4.5, 8]]) w.box(112 + e[0], .09, z + e[1], .3, .1, .3, 0xc9c2a6);
  }
  // Strandbar mit Tresen, Hockern und Schilfdach.
  const bx = 103, bz = 262;
  // Offene Bauweise: Pfosten und Rückwand, damit man hindurchsieht.
  for (const ox of [-3.2, 3.2]) for (const oz of [-2.3, 0, 2.3]) w.box(bx + ox, 1.65, bz + oz, .24, 3.3, .24, 0x7d6446);
  w.box(bx - 3.3, 1.65, bz, .3, 3.3, 5, 0xa8845c);
  w.box(bx, 1.05, bz + 2.5, 6.6, .2, 1.1, 0x8d6f4c);
  w.box(bx, .55, bz + 2.5, 6.4, 1.1, .7, 0x9a7a52);
  for (let e = -2.4; e <= 2.4; e += 1.2) w.box(bx + e, .5, bz + 3.6, .42, 1, .42, 0x6f5a41);
  w.box(bx, 1.9, bz - 2.2, 6.2, 1.4, .3, 0x6d5b3f);
  w.box(bx, 3.55, bz, 8.6, .4, 6.6, 0x8d7a4e);
  w.box(bx, 3.9, bz, 7.4, .35, 5.6, 0x9c8a5c);
  w.text('LOW TIDE BAR', bx, 4.6, bz + 3.4, 6.5, '#f0d49a');
 }

 // Ampelphasen: grün, gelb, rot je Achse, versetzt zueinander.
 update(zeit, nacht) {
  if (!this.lichtGruppen) return;
  const t = zeit % AMPEL_TAKT;
  for (let achse = 0; achse < 2; achse++) {
   const versetzt = achse ? (t + AMPEL_TAKT / 2) % AMPEL_TAKT : t;
   // 0 = rot oben, 1 = gelb, 2 = grün unten. ampelFrei in content.js deckt
   // grün und gelb ab und wird vom Verkehr gelesen.
   const leuchtet = versetzt < 10 ? 2 : versetzt < 12.5 ? 1 : 0;
   this.lichtGruppen[achse].forEach((eintrag, i) => {
    const an = i === leuchtet;
    eintrag.material.emissiveIntensity = an ? 1.7 + nacht * 1.5 : 0;
    eintrag.material.color.setHex(an ? eintrag.material.userData.grundfarbe : 0x141a19);
   });
  }
 }
}
