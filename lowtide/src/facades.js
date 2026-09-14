import {groundAt} from './content.js';
// Fassaden für Port Mercy.
// Die Gebäude waren Kisten mit aufgemalten Fensterquadraten: aus Augenhöhe
// die deutlichste Erinnerung daran, dass man in einer Demo steht. Alles hier
// läuft über World.box und landet damit in den vorhandenen InstancedMeshes.

const SOCKEL = [0x6d6a60, 0x5d6668, 0x736659, 0x5f6b66];
const MARKISEN = [0x9c5b52, 0x4e6f74, 0x8a7546, 0x51704f, 0x7a5470];
const LADEN = ['CAFÉ', 'LAVANDERÍA', 'MERCADO', 'BARBER', 'PHARMACY', 'TACOS',
 'LIQUOR', 'PAWN', 'NAILS', 'BODEGA', 'CAMBIO', 'DELI'];
// Neon. Emissive Flächen landen in leuchtMaterialien und werden von world.js
// zentral mit der Nacht hochgefahren — tagsüber sind es matte Röhren, nachts
// tragen sie die Straße. Bisher leuchteten nur Wohnungsfenster; eine
// Geschäftsstraße ohne Schrift bleibt nachts eine Reihe dunkler Kisten.
const NEON = [0xff5f8a, 0x4fd6ff, 0xffd166, 0x8affc1, 0xb08cff, 0xff8a5f];

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

// Eine Ladenzeile an einer Wand. achse 'z' heißt: die Wand steht quer zu z und
// die Zeile läuft in x; bei 'x' umgekehrt. Alle Maße stehen als (laengs, hoehe,
// dick) da — laengs entlang der Wand, dick durch sie hindurch —, damit dieselbe
// Beschreibung für beide Achsen gilt und nicht zwei Fassungen auseinanderlaufen.
function ladenzeile(w, rng, i, basis, mx, mz, wand, laenge, achse, seite, sockelFarbe) {
 const inZ = achse === 'z';
 const kasten = (u, y, tiefe, laengs, hoehe, dick, farbe, leucht = false) => {
  const x = inZ ? mx + u : mx + seite * (wand + tiefe);
  const z = inZ ? mz + seite * (wand + tiefe) : mz + u;
  w.box(x, y, z, inZ ? laengs : dick, hoehe, inZ ? dick : laengs, farbe, 0, leucht);
 };
 // Schaufensterband mit Pfosten dazwischen.
 kasten(0, basis + 1.75, 0, laenge * .86, 2.3, .12, 0x2c4149);
 for (let u = -laenge * .43; u <= laenge * .43; u += 2.4) kasten(u, basis + 1.75, .06, .16, 2.4, .18, sockelFarbe);
 kasten(0, basis + .32, .05, laenge * .88, .64, .22, sockelFarbe);
 // Eingang, versetzt, damit die Front nicht symmetrisch bleibt.
 const tu = (rng() - .5) * laenge * .45;
 kasten(tu, basis + 1.15, .16, 1.5, 2.3, .14, 0x35302a);
 kasten(tu, basis + 1.15, .24, .12, .5, .1, 0xb6a37c);
 // Markise über dem Eingang.
 const kennung = i * 2 + (seite > 0 ? 1 : 0) + (inZ ? 0 : 6);
 kasten(tu, basis + 2.85, .75, 3.4, .16, 1.5, MARKISEN[kennung % MARKISEN.length]);
 for (const e of [-1.6, 1.6]) kasten(tu + e, basis + 2.6, 1.4, .07, .5, .07, 0x4c5354);
 // Ladenname über dem Schaufenster. Ohne Beschriftung bleibt jedes
 // Erdgeschoss austauschbar.
 const dreh = inZ ? (seite > 0 ? 0 : Math.PI) : (seite > 0 ? Math.PI / 2 : -Math.PI / 2);
 const s0 = inZ ? {x: mx, z: mz + seite * (wand + .18)} : {x: mx + seite * (wand + .18), z: mz};
 w.text(LADEN[kennung % LADEN.length], s0.x, basis + 3.5, s0.z, Math.min(7, laenge * .5), '#e8d3a4', dreh);
 // Neonröhre unter der Markise und ein Band über dem Schaufenster.
 const ton = NEON[(i * 5 + (seite > 0 ? 2 : 0) + (inZ ? 0 : 3)) % NEON.length];
 kasten(tu, basis + 2.72, 1.42, 3.1, .1, .1, ton, true);
 kasten(0, basis + 2.98, .2, laenge * .84, .12, .1, ton, true);
 // Jede dritte Wand bekommt ein hochkantes Auslegerschild. Sie ragen in die
 // Straße und sind das, was eine Geschäftszeile nachts von einer Wohnzeile
 // unterscheidet.
 if (kennung % 3 === 0) {
  const su = laenge * .38 * (seite > 0 ? 1 : -1);
  const zweit = NEON[(i * 7 + 3) % NEON.length];
  kasten(su, basis + 4.9, .55, .18, 3.4, 1.05, 0x2b3136);
  for (const e of [-.11, .11]) kasten(su + e, basis + 4.9, .55, .04, 3.0, .8, zweit, true);
  kasten(su, basis + 6.72, .55, .3, .3, .3, 0x39424a);
  kasten(su, basis + 3.1, .3, .1, .1, .6, 0x39424a);
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

  // Ladenzeilen. Bis hierher lief diese Schleife nur über die beiden
  // z-Seiten — und die Innenstadthäuser sind 18 mal 38 Meter, ihre langen
  // Seiten zeigen also in x. Genau die standen als fugenlose Platten an der
  // Straße: kein Schaufenster, keine Tür, kein Schild, kein Neon. Vom
  // Boulevard aus war das die auffälligste leere Fläche auf Augenhöhe.
  //
  // Gebaut wird jetzt an jeder Wand, vor der Platz ist. Der Zwilling eines
  // Innenstadtpaares steht vier Meter neben seinem Partner; eine Ladenzeile
  // in einem vier Meter breiten Spalt wäre falsch, deshalb die Platzprobe
  // drei Meter vor der Wand.
  const belegt = (px, pz) => gebaeude.some(o => o !== b &&
   Math.abs(px - o.x) < o.w / 2 + 2.5 && Math.abs(pz - o.z) < o.d / 2 + 2.5);
  for (const [achse, laenge] of [['z', b.w], ['x', b.d]])
   for (const seite of [-1, 1]) {
    const halb = (achse === 'z' ? b.d : b.w) / 2;
    const px = achse === 'z' ? b.x : b.x + seite * (halb + 3);
    const pz = achse === 'z' ? b.z + seite * (halb + 3) : b.z;
    if (belegt(px, pz)) continue;
    ladenzeile(world, rng, i, basis, b.x, b.z, halb + .4, laenge, achse, seite, sockelFarbe);
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
  // Die Rahmen liefen über feste Bereiche: -6 bis 6 auf den z-Seiten und
  // **-15 bis 15** auf den x-Seiten, unabhängig von b.w und b.d. Gemessen an
  // den 36 Gebäuden, die Rahmen bekommen: keines ist schmaler als 14 Meter,
  // aber **zwölf sind flacher als 32** — bei denen hing die Laibung neben der
  // Wand in der Luft. Die Laibung ist zwei Meter breit, also bleibt ein Meter
  // plus ein Sicherheitsabstand Rand.
  for (let y = 5; y < b.h - 1; y += 3.7) {
   if (y < sockelHoehe + 1.2) continue;
   // Über dem Rücksprung ist die Wand schmaler; die Laibung muss mit.
   const f = b.absatz && y > b.absatz.ab ? b.absatz.faktor : 1;
   const spanneBreite = Math.max(0, b.w * f / 2 - 2.2), spanneTiefe = Math.max(0, b.d * f / 2 - 2.2);
   for (let u = -spanneBreite; u <= spanneBreite; u += 4) for (const seite of [-1, 1])
    fensterRahmen(world, b.x + u, basis + y, b.z + seite * (b.d * f / 2 + .09), 2, 1.9, 'z', sockelFarbe);
   for (let u = -spanneTiefe; u <= spanneTiefe; u += 5) for (const seite of [-1, 1])
    fensterRahmen(world, b.x + seite * (b.w * f / 2 + .09), basis + y, b.z + u, 2, 1.9, 'x', sockelFarbe);
  }

  // Feuertreppe an einer Längsseite der höheren Häuser.
  if (hoch && i % 2 === 0) {
   const x = b.x + (b.w / 2 + .55) * (i % 4 < 2 ? 1 : -1);
   // Nicht über den Rücksprung hinaus: dort steht keine Wand mehr, an der
   // eine Feuertreppe hängen könnte.
   const obergrenze = Math.min(b.h - 2, b.absatz ? b.absatz.ab - 1 : b.h);
   for (let y = sockelHoehe + 2.6; y < obergrenze; y += 3.7) {
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


// Balkone und Wäscheleinen an den Wohnzeilen.
//
// Die elf Wohnhäuser der Karte (im Mittel 8,5 Meter hoch, 25,7 breit) waren
// bisher nackte Quader: dressBuildings lässt kind === 'house' aus, weil
// Sockelgeschoss, Markise und Feuertreppe an ein Wohnhaus nicht gehören. Ein
// Balkon gehört dahin, und zwar versetzt statt in Reih und Glied — eine
// Fassade mit gleichmäßigem Raster sieht aus wie ein Bürogebäude.
export function dressHouses(world, haeuser) {
 let balkone = 0;
 for (const [i, b] of haeuser.entries()) {
  const basis = groundAt(b.x, b.z);
  const etagen = Math.max(1, Math.floor((b.h - 2.6) / 3.1));
  for (let e = 0; e < etagen; e++) {
   const y = basis + 2.9 + e * 3.1;
   if (y > basis + b.h - 1.1) break;
   for (const seite of [-1, 1]) {
    // Zwei bis drei je Fassade, die Lage hängt an Haus, Etage und Seite.
    const anzahl = 2 + ((i + e) % 2);
    for (let k = 0; k < anzahl; k++) {
     // Gleichmäßig über die Wand verteilt, mit einem kleinen Versatz je
     // Etage. Die erste Fassung rechnete k / (anzahl - 1) und schob damit den
     // ersten Balkon genau auf die Wandkante und den zweiten daneben ins
     // Freie — auf dem Bild war die Fassade leer, weil der einzige gesetzte
     // Balkon hinter der Minikarte lag.
     const spanne = Math.max(0, b.w / 2 - 2.4);
     const versatz = spanne * (2 * (k + .5) / anzahl - 1) + ((i + e + k) % 3 - 1) * .9;
     if (Math.abs(versatz) > spanne) continue;
     const z = b.z + seite * (b.d / 2 + .62);
     balkone++;
     world.box(b.x + versatz, y, z, 2.5, .16, 1.25, 0xb9ab93);
     world.box(b.x + versatz, y + .52, z + seite * .55, 2.5, .88, .11, 0x8d8471);
     for (const rand of [-1, 1])
      world.box(b.x + versatz + rand * 1.2, y + .52, z, .11, .88, 1.25, 0x8d8471);
     // Wäscheleine zwischen zwei Balkonen derselben Etage, nicht überall.
     if (k > 0 && (i + e) % 3 === 0)
      world.box(b.x + versatz - 1.4, y + 1.3, z - seite * .2, 2.4, .04, .04, 0xd8d2c2);
    }
   }
  }
 }
 return balkone;
}

// Eckhäuser. In einem Raster liegt fast jedes Gebäude irgendwie an einer
// Kreuzung — gemessen 33 von 36 im weiten Umkreis. Behandelt wird deshalb nur
// die **eine** Ecke, die tatsächlich an der Kreuzungsfläche liegt: eine um 45
// Grad gedrehte Schräge über die volle Höhe und der Ladeneingang genau dort.
export function dressCorners(world, gebaeude, kreuzungen) {
 let behandelt = 0;
 for (const b of gebaeude) {
  let beste = null, bestD = 1e9;
  for (const k of kreuzungen) {
   for (const ex of [-1, 1]) for (const ez of [-1, 1]) {
    const cx = b.x + ex * b.w / 2, cz = b.z + ez * b.d / 2;
    const d = Math.hypot(k.x - cx, k.z - cz) - k.breite / 2;
    if (d < bestD) {bestD = d; beste = {ex, ez, cx, cz};}
   }
  }
  if (!beste || bestD > 7) continue;
  behandelt++;
  const basis = groundAt(b.x, b.z);
  const hoehe = b.absatz ? b.absatz.ab : b.h;
  const winkel = Math.atan2(beste.ex, beste.ez);
  // Die Schräge sitzt auf der Ecke und ist so breit wie die Fase tief ist.
  world.box(beste.cx - beste.ex * 1.1, basis + hoehe / 2, beste.cz - beste.ez * 1.1,
   3.4, hoehe, .5, 0x7c8b8c, winkel);
  // Ladeneingang genau dort: Rahmen, Glas, Vordach.
  world.box(beste.cx - beste.ex * 1.15, basis + 1.5, beste.cz - beste.ez * 1.15,
   2.6, 3, .3, 0x2f3b40, winkel);
  world.box(beste.cx - beste.ex * 1.25, basis + 1.45, beste.cz - beste.ez * 1.25,
   2.1, 2.5, .12, 0x53707a, winkel);
  world.box(beste.cx - beste.ex * 1.5, basis + 3.25, beste.cz - beste.ez * 1.5,
   3.6, .22, 1.4, 0x3f4a4a, winkel);
 }
 return behandelt;
}
