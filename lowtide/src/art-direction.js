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
function fahrzeugFormen(sparsam){
 const schluessel=sparsam?'sparsam':'voll';
 if(FORMEN[schluessel])return FORMEN[schluessel];
 const karosserie=shell([[-2.2,.68,.48,.88],[-1.9,.91,.39,1.04],[-1.25,.99,.36,1.08],[.75,.99,.36,1.07],[1.7,.9,.43,.91],[2.2,.72,.5,.77]]);
 // Die Höhennormierung gehört zur Form, nicht zum Exemplar: einmal hier,
 // sonst würde sie sich bei jedem Auto erneut anwenden.
 karosserie.scale(1,1/.55,1);
 const lackTeile=[],chromTeile=[],zaehne=[];
 for(const side of [-1,1]){
  lackTeile.push(teil(new T.BoxGeometry(.24,.12,.3),side*.99,1.22,.69));
  chromTeile.push(teil(new T.BoxGeometry(.24,.055,.04),side*.965,1.01,-.05),
   teil(new T.BoxGeometry(.24,.055,.04),side*.965,1.01,-.85));
  for(const z of [-.48,.63])lackTeile.push(teil(new T.BoxGeometry(.05,.49,.06),side*.77,1.28,z));
 }
 lackTeile.push(teil(shell([[-.9,.73,1.49,1.6],[.48,.73,1.49,1.6]]),0,0,0));
 for(let x=-.45;x<=.45;x+=.15)zaehne.push(teil(new T.BoxGeometry(.025,.13,.06),x,.56,2.23));
 zaehne.push(teil(new T.BoxGeometry(1.05,.18,.05),0,.56,2.2));
 const speichen=[];for(let a=0;a<5;a++)speichen.push(teil(new T.BoxGeometry(.04,.45,.045),0,0,0,a*Math.PI/5));
 FORMEN[schluessel]={
  karosserie,
  kabine:shell([[-1.45,.82,.88,1.0],[-.85,.76,.94,1.58],[.5,.75,.94,1.58],[1.15,.84,.9,1.03]]),
  lack:verschmelze(lackTeile), chrom:verschmelze(chromTeile), grill:verschmelze(zaehne),
  speichen:sparsam?null:verschmelze(speichen),
  scheinwerfer:new T.BoxGeometry(.54,.12,.04), ruecklicht:new T.BoxGeometry(.63,.1,.04),
  // Reifen als kurzer Zylinder statt als Torus: 32 statt 320 Dreiecke.
  reifen:sparsam?new T.CylinderGeometry(.42,.42,.22,8):new T.TorusGeometry(.33,.105,8,20),
  reifenQuer:!sparsam,
  felge:new T.CylinderGeometry(.265,.265,.035,sparsam?8:20),
  balken:new T.BoxGeometry(.48,.14,.3), sparsam
 };
 return FORMEN[schluessel];
}

export function detailedCar(color,police=false,sparsam=false){const F=fahrzeugFormen(sparsam);const g=new T.Group();const paint=wolkenAufsetzen(new T.MeshPhysicalMaterial({color,roughness:.24,metalness:.65,clearcoat:1,clearcoatRoughness:.12}));
 const body=mesh(g,F.karosserie,paint);
 // Base World scales body damage; normalize to the preserved height convention.
 body.scale.y=.55;
 const glass=wolkenAufsetzen(new T.MeshPhysicalMaterial({color:0x355563,roughness:.1,metalness:.3,clearcoat:1,side:T.DoubleSide}));
 const cabin=mesh(g,F.kabine,glass);
 // Je ein Material für beide Scheinwerfer und beide Rücklichter dieses
 // Wagens. Pro Seite eigene waren zwei Draw Calls zu viel; über mehrere
 // Wagen geteilt werden dürfen sie nicht, weil das Bremslicht am Fahrzeug
 // hängt und sonst alle Autos gleichzeitig aufleuchten.
 const scheinwerfer=new T.MeshStandardMaterial({color:0xf4e4bb,emissive:0xffd6a0,emissiveIntensity:.6});
 const ruecklicht=new T.MeshStandardMaterial({color:0xa73833,emissive:0x932622,emissiveIntensity:.35});
 const lights=[],rueck=[];for(const side of [-1,1]){const lamp=mesh(g,F.scheinwerfer,scheinwerfer,side*.54,.76,2.14);lights.push(lamp);rueck.push(mesh(g,F.ruecklicht,ruecklicht,side*.54,.81,-2.16));
 }
 // Lackzubehör steckt in derselben Geometrie wie das Dach: beim Umlackieren
 // bekommt sie dasselbe Material, also darf sie ein Mesh sein.
 const roof=mesh(g,F.lack,paint);
 mesh(g,F.chrom,m(0xb8c2bb,.25,.8));
 const grille=mesh(g,F.grill,m(0x25333c,.4,.5));
 const wheels=[],rims=[];for(const x of [-.96,.96])for(const z of [-1.35,1.37]){const wheel=new T.Group();wheel.position.set(x,.44,z);const tire=mesh(wheel,F.reifen,m(0x20272c,.97));if(F.reifenQuer)tire.rotation.y=Math.PI/2;else tire.rotation.z=Math.PI/2;const rim=mesh(wheel,F.felge,m(0xaeb9b9,.24,.85));rim.rotation.z=Math.PI/2;rims.push(rim);if(F.speichen)mesh(wheel,F.speichen,m(0x52686d,.3,.8));g.add(wheel);wheels.push(wheel);}
 const interior=new T.Group();if(!sparsam)for(const x of [-.4,.4])ellipsoid(interior,x,1.12,0,.24,.27,.2,m(0x333d3d,.9));g.add(interior);
 const policeLights=[];if(police){for(const side of [-1,1])policeLights.push(mesh(g,F.balken,new T.MeshStandardMaterial({color:side<0?0xef5549:0x4b9bd6,emissive:side<0?0xe64a45:0x3c85de,emissiveIntensity:2}),side*.36,1.76,0));}
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
