import * as T from './vendor/three.module.js';
import {wolkenAufsetzen} from './detail.js';
// Original, fully 3D models. No photographic billboards replace playable entities.
const materials=new Map();
const m=(c,roughness=.65,metalness=0)=>{const key=c+':'+roughness+':'+metalness;if(!materials.has(key))materials.set(key,wolkenAufsetzen(new T.MeshStandardMaterial({color:c,roughness,metalness})));return materials.get(key);};
function mesh(g,geo,material,x=0,y=0,z=0){const o=new T.Mesh(geo,material);o.position.set(x,y,z);o.castShadow=true;o.receiveShadow=true;g.add(o);return o;}
const sphere=new T.SphereGeometry(1,16,12);
function ellipsoid(g,x,y,z,sx,sy,sz,material){const o=mesh(g,sphere,material,x,y,z);o.scale.set(sx,sy,sz);return o;}
export function detailedHuman(color,pants){
 const g=new T.Group(),skin=m(0xb68c70,.85),cloth=m(color,.92),denim=m(pants,.93),shoe=m(0x253139,.55),hairMat=m(0x302c27,.92);
 const torso=mesh(g,new T.CapsuleGeometry(.24,.4,6,12),cloth,0,1.16,0);torso.scale.set(1.15,1,.66);
 const head=ellipsoid(g,0,1.75,.01,.17,.215,.16,skin);
 const hair=mesh(g,new T.SphereGeometry(.178,16,10,0,Math.PI*2,0,Math.PI*.55),hairMat,0,1.79,0);hair.scale.set(1,1.08,1);
 // Facial features are geometry and stay present from every camera angle.
 for(const side of [-1,1]){ellipsoid(head,side*.39,.1,.89,.22,.105,.055,m(0xded9cc));ellipsoid(head,side*.39,.1,.948,.083,.095,.025,m(0x394d45));ellipsoid(head,side*1.02,-.05,.05,.13,.26,.15,skin);}
 ellipsoid(head,0,-.05,.99,.16,.23,.19,skin);ellipsoid(head,0,-.43,.88,.29,.045,.065,m(0x815d4e));
 const legs=[],arms=[];
 for(const side of [-1,1]){const leg=new T.Group();leg.position.set(side*.145,.83,0);mesh(leg,new T.CapsuleGeometry(.115,.55,4,10),denim,0,-.33,0);ellipsoid(leg,0,-.73,.08,.125,.095,.235,shoe);g.add(leg);legs.push(leg);}
 for(const side of [-1,1]){const arm=new T.Group();arm.position.set(side*.31,1.43,0);mesh(arm,new T.CapsuleGeometry(.09,.32,4,10),cloth,side*.025,-.2,0);ellipsoid(arm,side*.025,-.49,0,.076,.12,.07,skin);g.add(arm);arms.push(arm);}
 // A separate tattoo decal geometry can be toggled without changing the face.
 const tattoo=mesh(arms[0],new T.PlaneGeometry(.07,.12),m(0x314643),-.04,-.48,.073);tattoo.visible=false;
 g.userData={legs,arms,body:torso,hair,tattoo};return g;
}
function shell(sections){const pos=[],idx=[],normals=12;for(const [z,w,bottom,top] of sections){const cy=(bottom+top)/2,ry=(top-bottom)/2;for(let i=0;i<normals;i++){const a=i/normals*Math.PI*2;pos.push(Math.cos(a)*w,cy+Math.sin(a)*ry,z);}}for(let k=0;k<sections.length-1;k++)for(let i=0;i<normals;i++){const a=k*normals+i,b=k*normals+(i+1)%normals,c=b+normals,d=a+normals;idx.push(a,b,d,b,c,d);}for(const end of [0,sections.length-1])for(let i=1;i<normals-1;i++)idx.push(end*normals,end*normals+i,end*normals+i+1);const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(pos,3));geo.setIndex(idx);geo.computeVertexNormals();return geo;}
// Verschmilzt mehrere indizierte Geometrien mit ihrer Lage zu einer einzigen.
// Ein Nahfahrzeug bestand aus 55 Meshes, davon über die Hälfte winzige
// Wiederholungen: fünf Speichen je Rad, sieben Kühlerstäbe, vier Zierleisten.
// Jede davon war ein eigener Draw Call. Zusammengelegt bleiben 23.
export function verschmelze(teile){
 let punkte=0,indizes=0,mitUV=true;
 for(const t of teile){
  const g=t.geometry;
  if(!g.index)throw new Error('verschmelze braucht indizierte Geometrien');
  punkte+=g.attributes.position.count;indizes+=g.index.count;
  if(!g.attributes.uv)mitUV=false;
 }
 const pos=new Float32Array(punkte*3),nor=new Float32Array(punkte*3);
 const uvs=mitUV?new Float32Array(punkte*2):null;
 const idx=punkte>65535?new Uint32Array(indizes):new Uint16Array(indizes);
 const v=new T.Vector3(),nm=new T.Matrix3();
 let po=0,io=0;
 for(const t of teile){
  t.updateMatrix();
  const g=t.geometry,p=g.attributes.position,n=g.attributes.normal,u=g.attributes.uv;
  nm.getNormalMatrix(t.matrix);
  for(let i=0;i<p.count;i++){
   v.fromBufferAttribute(p,i).applyMatrix4(t.matrix);
   pos[(po+i)*3]=v.x;pos[(po+i)*3+1]=v.y;pos[(po+i)*3+2]=v.z;
   if(n){v.fromBufferAttribute(n,i).applyMatrix3(nm).normalize();
    nor[(po+i)*3]=v.x;nor[(po+i)*3+1]=v.y;nor[(po+i)*3+2]=v.z;}
   if(uvs&&u){uvs[(po+i)*2]=u.getX(i);uvs[(po+i)*2+1]=u.getY(i);}
  }
  for(let i=0;i<g.index.count;i++)idx[io+i]=g.index.getX(i)+po;
  po+=p.count;io+=g.index.count;
 }
 const ziel=new T.BufferGeometry();
 ziel.setAttribute('position',new T.BufferAttribute(pos,3));
 ziel.setAttribute('normal',new T.BufferAttribute(nor,3));
 if(uvs)ziel.setAttribute('uv',new T.BufferAttribute(uvs,2));
 ziel.setIndex(new T.BufferAttribute(idx,1));
 ziel.computeBoundingSphere();
 return ziel;
}

// Hilfsobjekt für verschmelze: eine Geometrie mit Lage, ohne sie in die
// Szene zu hängen.
function teil(geometry,x=0,y=0,z=0,rx=0,ry=0,rz=0){
 const o=new T.Object3D();o.position.set(x,y,z);o.rotation.set(rx,ry,rz);
 o.geometry=geometry;return o;
}

function quad(g,points,material){const a=new T.BufferGeometry();a.setAttribute('position',new T.Float32BufferAttribute(points.flat(),3));a.setIndex([0,1,2,0,2,3]);a.computeVertexNormals();return mesh(g,a,material);}
// Die Geometrie eines Fahrzeugs ist für jedes Exemplar dieselbe; nur Lack,
// Scheinwerfer und Rücklichter gehören dem einzelnen Wagen. Vorher legte
// jeder Aufruf über fünfzig neue BufferGeometries an — bei dreißig Autos in
// der Stadt sind das eineinhalbtausend, alle mit identischem Inhalt.
// sparsam: das Vorbild für die geparkten Wagen. Vierhundertvierundsiebzig
// Stück stehen über die Karte verteilt und werden alle jedes Bild gezeichnet.
// Mit Torusreifen, Innenraum und fünf Speichen je Rad waren das 1,4 Millionen
// Dreiecke für Kulisse, in die niemand einsteigt.
const FORMEN={};
// Vier Karosserien statt einer. Von 127 fahrenden Fahrzeugen trugen 112
// dieselbe Silhouette: Kleinwagen, Limousine, Geländewagen und Muscle Car
// waren derselbe Körper in anderem Maßstab — ein Geländewagen war eine um
// vierzig Prozent in die Höhe gezogene Limousine, ein Kleinwagen dieselbe um
// fünfzehn Prozent geschrumpft. Dach, Radstand und Überhänge blieben dabei
// im selben Verhältnis, und genau daran erkennt man ein Auto.
//
// Die Maße sind Meter im Endzustand, nicht Faktoren: die Profile bauen den
// Wagen in seiner wirklichen Größe, und der Maßstab aus vehicleTypes entfällt
// für diese vier. Jede Zahl ist am fertigen Mesh nachgemessen und steht in
// content.js unter laenge und breite.
//
// Dass es vorher eine Karosserie war, sieht man an den Verhältnissen, die
// eine Achsenskalierung gar nicht ändern kann. Gemessen am alten Stand für
// alle vier Modelle: Radstand 0,610 der Länge, vorderer Überhang 0,200,
// Fahrgastzelle 0,583, ihre Mitte 0,460 — auf drei Stellen dieselbe Zahl.
const KAROSSERIEN={
 // Dreistufig: Motorhaube, Fahrgastzelle, Kofferraum. 4,4 Meter.
 limousine:{
  profil:[[-2.2,.68,.48,.88],[-1.9,.91,.39,1.04],[-1.25,.99,.36,1.08],[.75,.99,.36,1.07],[1.7,.9,.43,.91],[2.2,.72,.5,.77]],
  kabine:[[-1.45,.82,.88,1.0],[-.85,.76,.94,1.58],[.5,.75,.94,1.58],[1.15,.84,.9,1.03]],
  spiegel:[.99,1.22,.69], griff:{x:.965,y:1.01,z:[-.05,-.85]}, leiste:{x:.77,y:1.28,z:[-.48,.63]},
  dach:[-.9,.73,1.49,1.6,.48], licht:{x:.54,y:.76,z:2.14}, rueck:{x:.54,y:.81,z:-2.16},
  grill:{y:.56,z:2.2,breite:1.05}, rad:{x:.96,z:[-1.35,1.37],y:.44,r:1}
 },
 // Schrägheck: die Zelle reicht fast bis ans Ende, der hintere Überhang ist
 // kurz. 3,7 Meter, schmal, verhältnismäßig hohes Dach.
 kompakt:{
  profil:[[-1.78,.60,.46,.90],[-1.55,.79,.38,1.02],[-1.0,.85,.36,1.06],[.62,.85,.36,1.05],[1.42,.78,.43,.92],[1.88,.62,.48,.78]],
  kabine:[[-1.52,.72,.88,1.03],[-1.05,.68,.94,1.60],[.30,.67,.94,1.56],[.92,.74,.88,1.02]],
  spiegel:[.86,1.18,.55], griff:{x:.83,y:.99,z:[-.1,-.7]}, leiste:{x:.66,y:1.24,z:[-.38,.5]},
  dach:[-.75,.63,1.47,1.57,.35], licht:{x:.46,y:.74,z:1.82}, rueck:{x:.46,y:.79,z:-1.74},
  grill:{y:.54,z:1.88,breite:.9}, rad:{x:.82,z:[-1.22,1.23],y:.40,r:.88}
 },
 // Kastenförmig, hoher Boden, langes Dach bis über die hintere Sitzreihe,
 // größere Räder. 4,9 Meter und einen halben Meter höher als die Limousine.
 gelaende:{
  profil:[[-2.45,.78,.62,1.14],[-2.1,1.0,.54,1.30],[-1.35,1.06,.52,1.34],[.9,1.06,.52,1.34],[1.9,.98,.58,1.18],[2.46,.82,.64,1.02]],
  kabine:[[-2.0,.94,1.16,1.32],[-1.35,.88,1.22,1.92],[.8,.88,1.22,1.92],[1.42,.94,1.18,1.34]],
  spiegel:[1.06,1.5,.75], griff:{x:1.03,y:1.28,z:[-.05,-.95]}, leiste:{x:.86,y:1.54,z:[-.5,.7]},
  dach:[-1.0,.8,1.86,1.98,.8], licht:{x:.6,y:1.02,z:2.4}, rueck:{x:.6,y:1.06,z:-2.42},
  grill:{y:.82,z:2.46,breite:1.2}, rad:{x:1.03,z:[-1.58,1.6],y:.55,r:1.25}
 },
 // Lange Haube, fließendes Heck, flaches Dach weit hinten. 5,1 Meter, breit
 // und niedrig.
 muscle:{
  profil:[[-2.54,.74,.44,.84],[-2.2,1.0,.37,.96],[-1.4,1.02,.35,1.00],[1.0,1.02,.35,1.00],[2.05,.94,.42,.88],[2.54,.76,.48,.76]],
  kabine:[[-1.95,.86,.86,.96],[-1.25,.82,.92,1.42],[.2,.80,.92,1.44],[.8,.88,.88,1.0]],
  spiegel:[1.02,1.14,.8], griff:{x:1.0,y:.94,z:[-.2,-1.0]}, leiste:{x:.82,y:1.2,z:[-.55,.5]},
  dach:[-.8,.7,1.38,1.46,.1], licht:{x:.56,y:.72,z:2.48}, rueck:{x:.56,y:.78,z:-2.5},
  grill:{y:.56,z:2.52,breite:1.15}, rad:{x:1.0,z:[-1.48,1.5],y:.44,r:1.05}
 }
};
function fahrzeugFormen(sparsam,form='limousine'){
 const k=KAROSSERIEN[form]?form:'limousine';
 const schluessel=(sparsam?'sparsam':'voll')+':'+k;
 if(FORMEN[schluessel])return FORMEN[schluessel];
 const M=KAROSSERIEN[k];
 const karosserie=shell(M.profil);
 // Die Höhennormierung gehört zur Form, nicht zum Exemplar: einmal hier,
 // sonst würde sie sich bei jedem Auto erneut anwenden.
 karosserie.scale(1,1/.55,1);
 const lackTeile=[],chromTeile=[],zaehne=[];
 for(const side of [-1,1]){
  lackTeile.push(teil(new T.BoxGeometry(.24,.12,.3),side*M.spiegel[0],M.spiegel[1],M.spiegel[2]));
  for(const z of M.griff.z)chromTeile.push(teil(new T.BoxGeometry(.24,.055,.04),side*M.griff.x,M.griff.y,z));
  for(const z of M.leiste.z)lackTeile.push(teil(new T.BoxGeometry(.05,.49,.06),side*M.leiste.x,M.leiste.y,z));
 }
 lackTeile.push(teil(shell([[M.dach[0],M.dach[1],M.dach[2],M.dach[3]],[M.dach[4],M.dach[1],M.dach[2],M.dach[3]]]),0,0,0));
 const halb=M.grill.breite/2-.07;
 for(let x=-halb;x<=halb+1e-6;x+=M.grill.breite/7)zaehne.push(teil(new T.BoxGeometry(.025,.13,.06),x,M.grill.y,M.grill.z+.03));
 zaehne.push(teil(new T.BoxGeometry(M.grill.breite,.18,.05),0,M.grill.y,M.grill.z));
 const speichen=[];for(let a=0;a<5;a++)speichen.push(teil(new T.BoxGeometry(.04,.45,.045),0,0,0,a*Math.PI/5));
 FORMEN[schluessel]={
  karosserie, masse:M,
  kabine:shell(M.kabine),
  lack:verschmelze(lackTeile), chrom:verschmelze(chromTeile), grill:verschmelze(zaehne),
  speichen:sparsam?null:verschmelze(speichen),
  scheinwerfer:new T.BoxGeometry(M.licht.x,.12,.04), ruecklicht:new T.BoxGeometry(M.rueck.x*1.17,.1,.04),
  // Reifen als kurzer Zylinder statt als Torus: 32 statt 320 Dreiecke.
  reifen:sparsam?new T.CylinderGeometry(.42,.42,.22,8):new T.TorusGeometry(.33,.105,8,20),
  reifenQuer:!sparsam,
  felge:new T.CylinderGeometry(.265,.265,.035,sparsam?8:20),
  balken:new T.BoxGeometry(.48,.14,.3), sparsam
 };
 return FORMEN[schluessel];
}
// Lack und Scheiben wurden pro Fahrzeug neu angelegt: bei 144 Wagen sind das
// 288 Materialien, die nie zusammen gezeichnet werden können. Die Scheibe hat
// ohnehin eine feste Farbe, der Lack kommt aus einer Handvoll Paletten.
//
// Geteilt werden darf beides, weil keines davon pro Fahrzeug verändert wird —
// Bremslicht und Scheinwerfer bleiben deshalb weiterhin eigene Materialien.
// Beim Umlackieren wird das Material **getauscht**, nicht verändert.
const lackCache=new Map();
export function lackMaterial(color){
 if(!lackCache.has(color))lackCache.set(color,wolkenAufsetzen(new T.MeshPhysicalMaterial(
  {color,roughness:.28,metalness:.12,clearcoat:1,clearcoatRoughness:.1})));
 return lackCache.get(color);
}
let scheinwerferStoff=null;
function scheinwerferMaterial(){
 if(!scheinwerferStoff)scheinwerferStoff=new T.MeshStandardMaterial(
  {color:0xf4e4bb,emissive:0xffd6a0,emissiveIntensity:.6});
 return scheinwerferStoff;
}
let scheibe=null;
function scheibenMaterial(){
 if(!scheibe)scheibe=wolkenAufsetzen(new T.MeshPhysicalMaterial(
  {color:0x355563,roughness:.1,metalness:.3,clearcoat:1,side:T.DoubleSide}));
 return scheibe;
}
export function detailedCar(color,police=false,sparsam=false,form='limousine'){const F=fahrzeugFormen(sparsam,form);const M=F.masse;const g=new T.Group();// Autolack ist kein Metall. Physikalisch ist er ein Dielektrikum mit
 // Metallflocken darin und einer Klarlackschicht darüber — bei metalness .65
 // fällt der Diffusanteil auf ein Drittel, und ein dunkler Wagen im Schatten
 // wird schwarz, weil Metall ohne Spiegelung nichts zu zeigen hat. Gemessen
 // an einem dunklen Rumpf um 17:30: Leuchtdichte 0,0147 gegen 0,0498 des
 // Himmels an derselben Stelle. Die Flocken bleiben als kleiner Metallanteil.
 const paint=lackMaterial(color);
 const body=mesh(g,F.karosserie,paint);
 // Base World scales body damage; normalize to the preserved height convention.
 body.scale.y=.55;
 const glass=scheibenMaterial();
 const cabin=mesh(g,F.kabine,glass);
 // Je ein Material für beide Scheinwerfer und beide Rücklichter dieses
 // Wagens. Pro Seite eigene waren zwei Draw Calls zu viel; über mehrere
 // Wagen geteilt werden dürfen sie nicht, weil das Bremslicht am Fahrzeug
 // hängt und sonst alle Autos gleichzeitig aufleuchten.
 // Der Scheinwerfer darf geteilt werden, das Rücklicht nicht: die Helligkeit
 // der Scheinwerfer hängt nur am Nachtanteil und ist für jedes Fahrzeug
 // dieselbe, das Bremslicht hängt am einzelnen Wagen. 144 gleiche Materialien
 // weniger.
 const scheinwerfer=scheinwerferMaterial();
 const ruecklicht=new T.MeshStandardMaterial({color:0xa73833,emissive:0x932622,emissiveIntensity:.35});
 const lights=[],rueck=[];for(const side of [-1,1]){const lamp=mesh(g,F.scheinwerfer,scheinwerfer,side*M.licht.x,M.licht.y,M.licht.z);lights.push(lamp);rueck.push(mesh(g,F.ruecklicht,ruecklicht,side*M.rueck.x,M.rueck.y,M.rueck.z));
 }
 // Lackzubehör steckt in derselben Geometrie wie das Dach: beim Umlackieren
 // bekommt sie dasselbe Material, also darf sie ein Mesh sein.
 const roof=mesh(g,F.lack,paint);
 mesh(g,F.chrom,m(0xb8c2bb,.25,.8));
 const grille=mesh(g,F.grill,m(0x25333c,.4,.5));
 const wheels=[],rims=[];for(const x of [-M.rad.x,M.rad.x])for(const z of M.rad.z){const wheel=new T.Group();wheel.position.set(x,M.rad.y,z);wheel.scale.setScalar(M.rad.r);const tire=mesh(wheel,F.reifen,m(0x20272c,.97));if(F.reifenQuer)tire.rotation.y=Math.PI/2;else tire.rotation.z=Math.PI/2;const rim=mesh(wheel,F.felge,m(0xaeb9b9,.24,.85));rim.rotation.z=Math.PI/2;rims.push(rim);if(F.speichen)mesh(wheel,F.speichen,m(0x52686d,.3,.8));g.add(wheel);wheels.push(wheel);}
 const interior=new T.Group();if(!sparsam)for(const x of [-.4,.4])ellipsoid(interior,x,M.kabine[1][2]+.18,0,.24,.27,.2,m(0x333d3d,.9));g.add(interior);
 const policeLights=[];if(police){for(const side of [-1,1])policeLights.push(mesh(g,F.balken,new T.MeshStandardMaterial({color:side<0?0xef5549:0x4b9bd6,emissive:side<0?0xe64a45:0x3c85de,emissiveIntensity:2}),side*.36,M.kabine[1][3]+.18,0));}
 g.userData={body,wheels,rims,lights:policeLights,headlights:lights,taillights:rueck,glass:cabin,roof,interior,paint,grille};return g;
}
// makeEnvironment ist entfallen: die Umgebungsreflexion kommt jetzt aus sky.js
// und folgt damit dem tatsächlichen Sonnenstand.
// Asphalt bei Tageslicht hat eine Albedo um 0,2 und wirkt mittelgrau, nicht schwarz.
// Die alte Textur war fast schwarz und wurde zusätzlich mit einer dunklen
// Materialfarbe multipliziert — der Boden verschwand komplett.
export function asphaltTexture(){
 const c=document.createElement('canvas');c.width=c.height=512;const ctx=c.getContext('2d');
 const pixels=ctx.createImageData(512,512);let seed=45;
 const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
 for(let y=0;y<512;y++)for(let x=0;x<512;x++){
  const i=(y*512+x)*4;
  // Nur feiner Splitt. Niederfrequente Muster ergaben sichtbare Bänder,
  // weil dieselbe Kachel über hunderte Meter Straße läuft.
  const korn=rnd()*15;
  const v=63+korn;
  pixels.data[i]=v+2;pixels.data[i+1]=v;pixels.data[i+2]=v-3;pixels.data[i+3]=255;
 }
 ctx.putImageData(pixels,0,0);
 // Risse und geflickte Nähte, damit die Fläche nicht wie Filz aussieht.
 // Bewusst nur kurze, schwache Risse: längere Strukturen zieht die Streckung
 // der Fahrbahn zu durchgehenden Streifen aus.
 ctx.lineCap='round';
 for(let n=0;n<70;n++){
  ctx.strokeStyle='rgba(48,52,56,'+(.10+rnd()*.14)+')';ctx.lineWidth=.6+rnd()*1.1;
  let x=rnd()*512,y=rnd()*512;ctx.beginPath();ctx.moveTo(x,y);
  for(let k=0;k<3;k++){x+=(rnd()-.5)*17;y+=(rnd()-.5)*17;ctx.lineTo(x,y);}
  ctx.stroke();
 }
 const t=new T.CanvasTexture(c);t.wrapS=t.wrapT=T.RepeatWrapping;t.repeat.set(12,12);
 t.colorSpace=T.SRGBColorSpace;t.anisotropy=4;return t;}
