import * as T from './vendor/three.module.js';
import {wolkenAufsetzen} from './detail.js';
import {World} from './world.js';
import {naturalHuman,animateNaturalHuman} from './human-model.js';
import {detailedHuman,detailedCar,asphaltTexture} from './art-direction.js';
import {locations,vehicleTypes,roadSegments,groundAt,waterAt,bounds,immobilien} from './content.js';
import {distance} from './simulation.js';
import {Street} from './street.js';
import {dressBuildings} from './facades.js';
import {dressRegions} from './regions.js';
import {dressInteriors} from './interiors.js';
import {Fernstufe,grobesAuto,grobeFigur} from './lod.js';
import {Tierwelt} from './wildlife.js';
import {Grasfeld} from './grass.js';
import {Laubwerk} from './foliage.js';
const STRASSEN_HEX=[0x333d45,0x3d494f,0x445155];
const GLAS_HEX=[0x3c5a69,0x486673,0x51737b,0x2c4d52];
const material=c=>new T.MeshStandardMaterial({color:c,roughness:.7});
export class ExpandedWorld extends World{
 constructor(canvas,sim){super(canvas,sim);const asphalt=asphaltTexture();
  this.strassenMaterialien=[];this.nassheit=0;
  this.scene.traverse(o=>{if(!o.isInstancedMesh||!o.material?.color)return;const hex=o.material.color.getHex();
   if(STRASSEN_HEX.includes(hex)){
    // Die Textur trägt die Helligkeit; die Materialfarbe darf sie nicht mehr abdunkeln.
    o.material.map=asphalt;o.material.color.setHex(0xffffff);o.material.roughness=.93;
    o.material.metalness=.03;o.material.envMapIntensity=.5;o.material.needsUpdate=true;
    this.strassenMaterialien.push(o.material);
   }
   if(GLAS_HEX.includes(hex)){o.material.metalness=.72;o.material.roughness=.16;o.material.envMapIntensity=1.5;}
  });
  this.setupStrassenlicht();this.setupInnenlicht();this.setupFahrlicht();this.setupFernstufen(sim);this.tiere=new Tierwelt(this.scene);
  // Bewuchs im Ring um den Spieler: ein Draw Call, feste Speichergröße.
  this.gras=new Grasfeld(this.scene,sim);
  // Suchscheinwerfer des Hubschraubers. Ab fünf Sternen kreist er über der
  // letzten bekannten Position; vorher war er nur ein stummes Modell.
  this.suchlicht=new T.SpotLight(0xdfe9ff,0,220,.16,.4,1);
  this.suchlicht.visible=false;this.scene.add(this.suchlicht);this.scene.add(this.suchlicht.target);
  this.suchfleck=new T.Mesh(new T.RingGeometry(4.4,9.5,32),
   new T.MeshBasicMaterial({color:0xcfe0ff,transparent:true,opacity:.28,side:T.DoubleSide,depthWrite:false}));
  this.suchfleck.rotation.x=-Math.PI/2;this.suchfleck.visible=false;this.scene.add(this.suchfleck);}

 // Acht Punktlichter wandern zu den nächstgelegenen Laternen. Mehr wäre auf
 // schwacher Hardware nicht tragbar, weniger liest sich nachts nicht als Stadt.
 setupStrassenlicht(){
  this.strassenLichter=[];
  for(let i=0;i<8;i++){const l=new T.PointLight(0xffd7a0,0,26,1.7);l.visible=false;this.scene.add(l);this.strassenLichter.push(l);}
  this.lichtWechsel=0;
 }
 // Innenraumlicht: fünf Punktlichter wandern zum nächstgelegenen Raum.
 // Innen brennt Licht auch bei Tag, sonst ist jeder Laden eine Höhle.
 // Ab welcher Entfernung die grobe Stufe übernimmt. Vierzig Meter sind der
 // Punkt, ab dem Finger, Sitze und Scheinwerferlinsen ohnehin verschwinden.
 setupFernstufen(sim){
  this.autoFern=new Fernstufe(this.scene,grobesAuto(),sim.cars.length+sim.cops.length+4);
  this.figurFern=new Fernstufe(this.scene,grobeFigur(),sim.npcs.length+8);
 }
 setupInnenlicht(){
  this.innenLichter=[];
  for(let i=0;i<5;i++){const l=new T.PointLight(0xffdcae,0,21,1.45);l.visible=false;this.scene.add(l);this.innenLichter.push(l);}
  this.innenWechsel=0;
 }
 updateInnenlicht(p){
  const lampen=this.innenLampen;if(!lampen?.length||!this.innenLichter)return;
  // Neu zuordnen im halben Sekundentakt — oder sofort, wenn sich die Figur
  // seit der letzten Zuordnung deutlich bewegt hat. Sonst bliebe der Laden
  // beim Betreten einen Moment dunkel.
  const gesprungen=!this.innenBezug||Math.hypot(p.x-this.innenBezug.x,p.z-this.innenBezug.z)>7;
  if(this.sim.time>this.innenWechsel||gesprungen){
   this.innenWechsel=this.sim.time+.5;this.innenBezug={x:p.x,z:p.z};
   this.naheInnen=lampen
    .filter(l=>Math.abs(l.x-p.x)<20&&Math.abs(l.z-p.z)<20)
    .sort((a,b)=>((a.x-p.x)**2+(a.z-p.z)**2)-((b.x-p.x)**2+(b.z-p.z)**2))
    .slice(0,5);
  }
  this.innenLichter.forEach((licht,i)=>{
   const lampe=this.naheInnen?.[i];
   // Zusätzlich jedes Bild prüfen: die Zuordnung oben läuft nur alle halbe
   // Sekunde, ein Sprung aus dem Raum soll aber sofort wirken.
   const nah=lampe&&Math.abs(lampe.x-p.x)<24&&Math.abs(lampe.z-p.z)<24;
   licht.visible=!!nah;
   if(nah){licht.position.set(lampe.x,lampe.y,lampe.z);licht.color.setHex(lampe.farbe);licht.intensity=lampe.staerke||70;}
  });
 }
 setupFahrlicht(){
  // Zwei Kegel reichen: mehr Lichter mit Reichweite kosten auf schwacher
  // Hardware mehr, als sie zeigen.
  this.fahrlicht=[0,1].map(()=>{
   const l=new T.SpotLight(0xfff0c8,0,80,.5,.5,1.2);l.visible=false;
   this.scene.add(l);this.scene.add(l.target);return l;});
 }
 updateFahrlicht(nacht){
  const c=this.sim.player.car,d=c&&vehicleTypes[c.model];
  const an=!!c&&c.lights>15&&c.health>0&&nacht>.15&&d.medium!=='water';
  const y=c?groundAt(c.x,c.z)+(c.alt||0):0;
  this.fahrlicht.forEach((l,i)=>{
   l.visible=an;if(!an)return;
   const seite=(i?1:-1)*.8;
   l.position.set(c.x+Math.sin(c.yaw)*2.1+Math.cos(c.yaw)*seite,y+.85,
                  c.z+Math.cos(c.yaw)*2.1-Math.sin(c.yaw)*seite);
   l.target.position.set(c.x+Math.sin(c.yaw)*42,y-2,c.z+Math.cos(c.yaw)*42);
   l.target.updateMatrixWorld();
   l.intensity=nacht*220;
  });
 }
 updateStrassenlicht(nacht,p){
  const lampen=this.lampen;if(!lampen||!this.strassenLichter)return;
  if(nacht<.08){for(const l of this.strassenLichter)l.visible=false;return;}
  // Die Zuordnung ist teuer genug, um sie nicht jedes Bild zu machen.
  const weit=!this.lichtBezug||Math.hypot(p.x-this.lichtBezug.x,p.z-this.lichtBezug.z)>12;
  if(this.sim.time>this.lichtWechsel||weit){
   this.lichtWechsel=this.sim.time+.6;this.lichtBezug={x:p.x,z:p.z};
   this.naheLampen=lampen
    .filter(l=>Math.abs(l.x-p.x)<46&&Math.abs(l.z-p.z)<46)
    .sort((a,b)=>((a.x-p.x)**2+(a.z-p.z)**2)-((b.x-p.x)**2+(b.z-p.z)**2))
    .slice(0,8);
  }
  this.strassenLichter.forEach((licht,i)=>{
   const lampe=this.naheLampen?.[i];
   licht.visible=!!lampe;
   if(lampe){licht.position.set(lampe.x,lampe.y,lampe.z);licht.intensity=nacht*34;}
  });
 }
 human(color,pants,nah=true){return naturalHuman(color,pants,nah);}
 // Die Bodenneigung unter der Figur, gemessen einen halben Meter vor und
 // hinter ihr. Auf der Ebene ist sie null; erst am Hang im Cypress-Park
 // stellt sie die Sohlen sichtbar in den Anstieg.
 bodenNeigung(model){
  const x=model.position.x,z=model.position.z,y=model.rotation.y,d=.5;
  const vx=Math.sin(y)*d,vz=Math.cos(y)*d;
  const vorne=groundAt(x+vx,z+vz),hinten=groundAt(x-vx,z-vz);
  return Math.max(-.7,Math.min(.7,Math.atan2(vorne-hinten,d*2)));
 }
 animateHuman(model,time,moving,armed){if(model.userData.rig)animateNaturalHuman(model,time,moving,armed,this.bodenNeigung(model));else super.animateHuman(model,time,moving,armed);}
 palm(x,z,h){(this.palmen||=[]).push({x,z,h});}
 // Bäume sammeln statt sie als Kisten zu setzen; gebaut wird einmal am Ende.
 baum(x,z,hoehe,art,farbe){(this.laubwerk||=new Laubwerk(this.scene)).hinzu(x,z,hoehe,art,farbe);}
 // Eine Krone, einmal erzeugt, danach nur noch Matrizen.
 palmenGeometrie(){const positions=[];for(let k=0;k<9;k++){const a=k*Math.PI*2/9;for(let j=0;j<7;j++){const point=(t,side)=>{const len=t*4.4,w=Math.sin(t*Math.PI)*.52;return [Math.sin(a)*len+Math.cos(a)*w*side,Math.sin(t*Math.PI)*.9-t*t*1.7,Math.cos(a)*len-Math.sin(a)*w*side];};const a0=point(j/7,-1),b0=point(j/7,1),c0=point((j+1)/7,-1),d0=point((j+1)/7,1);positions.push(...a0,...b0,...c0,...b0,...d0,...c0);}}const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(positions,3));geo.computeVertexNormals();return geo;}
 palmenBauen(){const liste=this.palmen;if(!liste?.length)return;
  const stamm=new T.CylinderGeometry(.12,.27,1,8,3);stamm.translate(0,.5,0);
  this.palmStaemme=new T.InstancedMesh(stamm,new T.MeshStandardMaterial({color:0x8a7958,roughness:1}),liste.length);
  this.palmKronen=new T.InstancedMesh(this.palmenGeometrie(),new T.MeshStandardMaterial({color:0x3f7250,roughness:.8,side:T.DoubleSide}),liste.length);
  for(const netz of [this.palmStaemme,this.palmKronen]){netz.castShadow=true;netz.receiveShadow=true;netz.frustumCulled=false;this.scene.add(netz);}
  this.palmHilfe=new T.Object3D();this.palmenSetzen(0);}
 // Wind: die Kronen neigen sich, der Stamm bleibt stehen.
 palmenSetzen(zeit,staerke=1){const liste=this.palmen,o=this.palmHilfe;if(!liste)return;
  liste.forEach((p,i)=>{const y=groundAt(p.x,p.z);
   o.position.set(p.x,y,p.z);o.rotation.set(0,0,.045);o.scale.set(1,p.h,1);o.updateMatrix();
   this.palmStaemme.setMatrixAt(i,o.matrix);
   o.position.set(p.x-.3,y+p.h,p.z);o.scale.set(1,1,1);
   o.rotation.set(Math.cos(zeit*.7+p.z*.11)*.02*staerke,p.x*.7,Math.sin(zeit*.8+p.x*.13)*.03*staerke);
   o.updateMatrix();this.palmKronen.setMatrixAt(i,o.matrix);});
  this.palmStaemme.instanceMatrix.needsUpdate=true;this.palmKronen.instanceMatrix.needsUpdate=true;
  this.palmStaemme.computeBoundingSphere();this.palmKronen.computeBoundingSphere();}

 build(){super.build();const s=this.sim;
  for(const [i,b] of [...s.buildings,...s.worldBuildings].entries()){if(b.kind==='house')continue;for(let y=5;y<Math.min(b.h,24);y+=5){this.box(b.x,y,b.z+b.d/2+1,b.w*.82,.18,2,0xb4b8ac);this.box(b.x,y+.9,b.z+b.d/2+1.9,b.w*.82,.07,.08,0x61797a);for(let x=-b.w*.38;x<=b.w*.38;x+=3)this.box(b.x+x,y+.45,b.z+b.d/2+1.9,.05,.9,.05,0x61797a);}this.box(b.x+b.w/2-2,2.8,b.z+b.d/2+.7,1.4,.8,1.2,0xa1afa6);this.box(b.x,3.5,b.z+b.d/2+1,Math.min(12,b.w),.12,2,[0x779994,0xb58882,0xcbb783][i%3]);for(let stripe=-5;stripe<5;stripe+=2)this.box(b.x+stripe,3.58,b.z+b.d/2+1,1,.025,2,0xd7d6bc);}
  // Spatially chunked terrain, with actual height beneath vehicles and characters.
  // Das Gelände endete bei x = 120, also an der Küste. Unter den Keys lag
  // damit nichts als die Wasserebene; die Inseln schwammen auf ihren eigenen
  // Sandplatten. Jetzt reicht das Raster bis an den Kartenrand.
  // Dazu ein Sandsaum: wer nicht im Wasser steht, aber zehn Meter daneben,
  // bekommt Strandfarbe statt Wiese. Ohne den stieß Gras direkt ans Meer.
  const amWasser=(px,pz)=>waterAt(px+10,pz)||waterAt(px-10,pz)||waterAt(px,pz+10)||waterAt(px,pz-10);
  this.terrain=[];for(let x=bounds.left;x<bounds.right;x+=100)for(let z=bounds.top;z<bounds.bottom;z+=100){const g=new T.PlaneGeometry(100,100,12,12);g.rotateX(-Math.PI/2);const a=g.attributes.position,colors=[];for(let i=0;i<a.count;i++){const px=x+50+a.getX(i),pz=z+50+a.getZ(i);a.setY(i,waterAt(px,pz)?-3.4:groundAt(px,pz)-.12);const c=new T.Color(waterAt(px,pz)?0x2f5450:amWasser(px,pz)?0x9a8a63:px<-380&&pz<-240?0x4f5c43:pz<-230?0x5a6249:px<-390?0x4f5d47:0x6c6d58);colors.push(c.r,c.g,c.b);}g.setAttribute('color',new T.Float32BufferAttribute(colors,3));g.computeVertexNormals();const m=new T.Mesh(g,new T.MeshStandardMaterial({vertexColors:true,roughness:1}));m.position.set(x+50,0,z+50);m.receiveShadow=true;
   // Kacheln, die ganz unter Wasser liegen, sieht man nie: der Wassershader
   // ist undurchsichtig. Sie werden nur beim Tauchen eingeblendet. Ohne das
   // kosteten allein die dreißig neuen Meereskacheln im Osten am Strand über
   // vierhundert Draw Calls für nichts.
   m.userData.nurWasser=[[0,0],[100,0],[0,100],[100,100],[50,50],[25,75],[75,25]]
    .every(([ox,oz])=>waterAt(x+ox,z+oz));
   this.scene.add(m);this.terrain.push(m);}
  const umland=new T.Mesh(new T.PlaneGeometry(3800,3800,16,16),new T.MeshStandardMaterial({color:0x3a4636,roughness:1}));
  umland.rotation.x=-Math.PI/2;umland.position.set(-230,-2.4,-40);umland.renderOrder=-1;this.scene.add(umland);
  this.box(297,-.3,222,125,.5,145,0x66714f);this.box(185,.08,200,152,.5,10,0x5b6c70);for(let x=121;x<254;x+=14){this.box(x,1.1,195,.2,2,.2,0xbebc9d);this.box(x,1.1,205,.2,2,.2,0xbebc9d);}this.box(106,-.05,280,24,.12,300,0x9c8e6b);
  // Fahrbahnen folgen dem Gelände. Vorher lag jedes Segment als ein Quader
  // auf y = 0,03 — auf ebener Karte richtig, auf dem Talon Ridge nicht: die
  // Zufahrt bei z = -160 lag damit sechsundachtzig Meter unter der Kuppe.
  // Sichtbar war dort keine Straße, blockiert hat sie trotzdem: aufStrasse()
  // rechnet in der Ebene und hielt den Bewuchs von einem Streifen fern, auf
  // dem gar nichts lag. Gefunden über tools/schwachstellen.mjs, das TALON
  // RIDGE als flachste Gegend auswies, und von dort rückwärts.
  for(const r of roadSegments){
   const laenge=Math.hypot(r.x2-r.x1,r.z2-r.z1);
   const nordSued=r.x1===r.x2;
   // Zwölf Meter je Stück: kürzer bringt nichts, weil groundAt so glatt ist,
   // länger setzt auf dem Rücken sichtbare Stufen.
   const stuecke=Math.max(1,Math.round(laenge/12));
   for(let k=0;k<stuecke;k++){
    const t=(k+.5)/stuecke;
    const mx=r.x1+(r.x2-r.x1)*t,mz=r.z1+(r.z2-r.z1)*t;
    const l=laenge/stuecke+.4;
    const y=groundAt(mx,mz);
    // Am Hang bekommt die Fahrbahn eine Berme: eine Straße, die sich in
    // einen Rücken schneidet, hört nicht an der Kante der Decke auf. In der
    // Ebene entfällt sie, dort gibt es keinen Ein- oder Anschnitt.
    if(y>2){
     this.box(mx,y-.06,mz,nordSued?r.w+5.5:l,.16,nordSued?l:r.w+5.5,0x6f6a5c);
     this.box(mx,y-.34,mz,nordSued?r.w+9:l,.5,nordSued?l:r.w+9,0x5c6350);
    }
    // Leitplanke, wo es neben der Fahrbahn hinuntergeht. Eine siebzehn Meter
    // breite Straße quer über einen achtundachtzig Meter hohen Rücken hatte
    // bisher nichts am Rand. Gesetzt wird sie nur dort, wo der Boden zehn
    // Meter neben der Achse mehr als anderthalb Meter tiefer liegt — in der
    // Ebene entsteht dadurch keine einzige Kiste.
    for(const seite of [-1,1]){
     const rx=mx+(nordSued?seite*(r.w/2+1.6):0),rz=mz+(nordSued?0:seite*(r.w/2+1.6));
     const ax=mx+(nordSued?seite*(r.w/2+10):0),az=mz+(nordSued?0:seite*(r.w/2+10));
     if(y-groundAt(ax,az)<1.5)continue;
     this.box(rx,y+.62,rz,nordSued?.14:l,.34,nordSued?l:.14,0xb9bcb4);
     for(let q=-l/2+1;q<l/2;q+=3)
      this.box(rx+(nordSued?0:q),y+.36,rz+(nordSued?q:0),.16,.72,.16,0x8b8f88);
    }
    this.box(mx,y+.03,mz,nordSued?r.w:l,.08,nordSued?l:r.w,0x3d494f);
   }
   for(let i=0;i<laenge;i+=16){
    const t=i/laenge,mx=r.x1+(r.x2-r.x1)*t,mz=r.z1+(r.z2-r.z1)*t;
    this.box(mx,groundAt(mx,mz)+.08,mz,nordSued?.16:5,.02,nordSued?5:.16,0xc4bb97);
   }
  }
  for(const b of s.worldBuildings){const base=groundAt(b.x,b.z),co=b.kind==='house'?0xb5a78f:0x869c9c;this.box(b.x,base+b.h/2,b.z,b.w,b.h,b.d,co);this.box(b.x,base+b.h+.3,b.z,b.w+1,.6,b.d+1,0x3e555a);
   // Hochhäuser bekommen Rücksprünge, eine Krone und ein Blinkfeuer. Ein
   // Turm ohne Absatz ist aus der Ferne nur ein längerer Quader.
   if(b.turm){
    const oben=base+b.h;
    this.box(b.x,oben+5,b.z,b.w*.74,10,b.d*.74,co);
    this.box(b.x,oben+10.4,b.z,b.w*.78,.8,b.d*.78,0x3e555a);
    this.box(b.x,oben+15,b.z,b.w*.46,9,b.d*.46,co);
    this.box(b.x,oben+20,b.z,b.w*.5,.7,b.d*.5,0x3e555a);
    this.box(b.x,oben+26,b.z,1.1,12,1.1,0x6b7378);
    this.box(b.x,oben+32.4,b.z,.9,.9,.9,0xff5a4a,0,true);
    for(const e of [-1,1]){
     this.box(b.x+e*b.w*.3,oben+3,b.z,1.6,6,1.6,0x76858a);
     this.box(b.x,oben+3,b.z+e*b.d*.3,1.6,6,1.6,0x76858a);
    }
   }for(let y=3;y<b.h;y+=4)for(let x=-b.w/2+4;x<b.w/2;x+=5)this.box(b.x+x,base+y,b.z+b.d/2+.05,2,2,.1,0x51737b);}
  for(const b of s.roomWalls)this.box(b.x,b.h/2,b.z,b.w,b.h,b.d,0x879e96);
  for(const [id,l] of Object.entries(locations)){this.text(l.name.toUpperCase(),l.x,4.1+groundAt(l.x,l.z),l.z-10,Math.min(18,l.name.length*.8),'#c6dbc3',Math.PI);if(['garage','shop','clinic','home','club','diner','motel','records'].includes(id))this.box(l.x,.04,l.z-4,17,.1,17,0x5a625e);}
  // Court with visible basket and an animated ball.
  const court=locations.court;this.box(court.x,.05,court.z,20,.15,28,0x668b7c);this.box(court.x,.14,court.z-11,15,.04,.15,0xe9d9b1);this.box(court.x,2,court.z-12,.2,4,.2,0x405059);this.box(court.x,3.6,court.z-12,2.4,1.5,.15,0xd5d2bd);const hoop=new T.Mesh(new T.TorusGeometry(.5,.05,6,18),material(0xc28d58));hoop.rotation.x=Math.PI/2;hoop.position.set(court.x,3.1,court.z-11.3);this.scene.add(hoop);this.ball=new T.Mesh(new T.SphereGeometry(.28,12,8),material(0xd79b54));this.scene.add(this.ball);
  // Airport runway, ocean piers, fields and farm rows.
  this.box(-315,.09,315,25,.15,155,0x445155);for(let z=250;z<390;z+=16)this.box(-315,.18,z,1,.02,8,0xd2d0af);this.box(114,.2,145,22,.5,6,0x776d58);this.box(-393,-.01,-225,42,.12,36,0x7a6a48);for(let x=-411;x<-374;x+=4)this.box(x,.25,-225,.5,.5,32,0x5d7750);
  for(let i=0;i<155;i++){const x=-575+this.rng()*182,z=-530+this.rng()*286;const y=groundAt(x,z),h=4+this.rng()*5;this.box(x,y+h/2,z,.5,h,.5,0x746b51);this.box(x,y+h,z,4,4,4,0x4a715b);}
  for(let i=0;i<45;i++){const x=-535+this.rng()*125,z=this.rng()*110;this.box(x,2.2,z,.4,5,.4,0x697458);this.box(x,5,z,4,1,4,0x668269);}
  for(let z=140;z<435;z+=17)this.palm(91.5,z,7+((z*7)%5));
  for(let z=150;z<430;z+=23)this.palm(101,z,6+((z*3)%4));this.camera.far=1100;this.camera.updateProjectionMatrix();
  // Straßenmöblierung zuletzt, damit sie freie Flächen kennt und noch in den
  // gemeinsamen Instanz-Sammler von World.flush läuft.
  // Verkaufsschilder: ohne Marke in der Welt findet niemand die Objekte.
  for(const o of Object.values(immobilien)){
   const y=groundAt(o.x,o.z);
   this.box(o.x,y+1.3,o.z,.12,2.6,.12,0x6b5c44);
   this.box(o.x+.9,y+1.3,o.z,.12,2.6,.12,0x6b5c44);
   this.box(o.x+.45,y+2.35,o.z,1.5,1,.1,0xdcd2b4);
   this.text('ZU VERKAUFEN',o.x+.45,y+2.35,o.z-.09,1.9,'#3c4a52',Math.PI);
  }
  this.street=new Street(this);this.street.bauen();this.street.strandBauen();this.street.parkendeAutosBauen();
  dressBuildings(this,[...s.buildings,...s.worldBuildings].filter(b=>b.kind!=='house'));
  // Der Rest der Karte: Vororte, Farmland, Nationalpark, Sumpf, Flugfeld,
  // Insel, Industriegürtel und die Baulücken der Innenstadt.
  dressRegions(this);
  this.innenLampen=dressInteriors(this);
  this.palmenBauen();
  this.laubwerk?.bauen();
 }
 car(color,police=false,c=null){if(!c)return detailedCar(color,police);const d=vehicleTypes[c.model],g=new T.Group();if(['car','pickup'].includes(d.shape)){const m=detailedCar(color);m.scale.set(...d.scale);if(d.shape==='pickup')this.dynbox(m,0,1.2,-1.3,1.9,.2,1.5,color);m.userData.def=d;return m;}const body=this.dynbox(g,0,.8,0,1.4,.5,3,color);let wheels=[],rotor=null;
  if(['bike','quad'].includes(d.shape)){body.scale.set(d.shape==='bike'?.35:1.2,.5,1.5);this.dynbox(g,0,1.4,.8,1,.1,.15,0x263c40);for(const z of [-.9,.9])for(const x of d.shape==='bike'?[0]:[-.65,.65]){const wheel=new T.Mesh(new T.CylinderGeometry(.45,.45,.22,10),material(0x26343a));wheel.rotation.z=Math.PI/2;wheel.position.set(x,.45,z);g.add(wheel);wheels.push(wheel);}this.dynbox(g,0,1.05,-.25,.45,.2,.8,0x394149);}
  if(['truck','bus'].includes(d.shape)){body.scale.set(2.5,2.6,d.shape==='bus'?8:7);body.position.y=1.8;this.dynbox(g,0,2.2,3.1,2.3,1.1,.15,0x304951);for(const x of [-1.2,1.2])for(const z of [-2.4,2.4]){const w=new T.Mesh(new T.CylinderGeometry(.65,.65,.3,12),material(0x25343c));w.rotation.z=Math.PI/2;w.position.set(x,.6,z);g.add(w);wheels.push(w);}if(d.shape==='bus')for(let z=-3;z<3;z+=1.1){this.dynbox(g,1.26,2.4,z,.04,.8,.7,0x355b65);this.dynbox(g,-1.26,2.4,z,.04,.8,.7,0x355b65);}}
  if(['boat','jetski'].includes(d.shape)){body.scale.set(d.shape==='boat'?2.4:1,.7,d.shape==='boat'?5:2.5);this.dynbox(g,0,1.2,0,d.shape==='boat'?1.6:.5,.5,1.8,0xd0d2be);this.dynbox(g,0,1.55,.5,1,.5,.1,0x395969);}
  if(d.shape==='helicopter'){body.scale.set(2,1.5,4);body.position.y=1.8;this.dynbox(g,0,2,1.8,1.7,1.1,.1,0x355567);this.dynbox(g,0,2,-3,.35,.45,4,color);rotor=new T.Group();rotor.position.set(0,3,0);this.dynbox(rotor,0,0,0,.18,.08,11,0x2d4048);this.dynbox(rotor,0,0,0,11,.08,.18,0x2d4048);g.add(rotor);for(const x of [-1.2,1.2])this.dynbox(g,x,.5,0,.12,.12,4,0x455962);}
  if(d.shape==='plane'){body.scale.set(1.3,1.3,7);body.position.y=1.6;this.dynbox(g,0,1.6,0,13,.2,1.4,color);this.dynbox(g,0,2,-3,4,.15,.8,color);this.dynbox(g,0,2.5,-3,.15,1.5,.8,color);this.dynbox(g,0,2.2,1,.9,.5,1,0x35596b);rotor=new T.Group();rotor.position.set(0,1.6,3.6);this.dynbox(rotor,0,0,0,3.4,.13,.1,0x354753);g.add(rotor);}
  g.userData={body,wheels,lights:[],rotor,def:d,bodyHeight:body.scale.y};return g;
 }
 applyUpgrades(m,c){const signature=JSON.stringify(c.upgrades);if(signature===m.userData.upgradeSignature)return;m.userData.upgradeSignature=signature;if(m.userData.kit)m.remove(m.userData.kit);const kit=new T.Group();m.add(kit);m.userData.kit=kit;const u=c.upgrades;if(u.body){this.dynbox(kit,0,1.15,-1.8,2.1,.1,.4,c.color);for(const x of [-.75,.75])this.dynbox(kit,x,.98,-1.8,.08,.35,.08,0x35464b);for(const x of [-1,1])this.dynbox(kit,x,.35,0,.12,.14,2.8,c.color);}if(u.exhaust){for(const x of [-.7,.7]){const pipe=new T.Mesh(new T.CylinderGeometry(.09,.09,.5,12),new T.MeshStandardMaterial({color:0x9caaa6,metalness:.85,roughness:.2}));pipe.rotation.x=Math.PI/2;pipe.position.set(x,.45,-2.22);kit.add(pipe);}}if(u.rims)for(const rim of m.userData.rims||[])rim.material=new T.MeshStandardMaterial({color:u.rims%2?0xbfa66e:0x35434a,metalness:.8,roughness:.2});if(u.interior&&m.userData.interior)m.userData.interior.traverse(o=>{if(o.isMesh)o.material=new T.MeshStandardMaterial({color:u.interior%2?0xad8a66:0x3a515d,roughness:.9});});if(u.lights){const strip=this.dynbox(kit,0,.23,0,1.6,.025,3,0x729dbc);strip.material=new T.MeshStandardMaterial({color:0x63bdd1,emissive:0x63bdd1,emissiveIntensity:2});} }
 updateExtras(dt,camYaw,camPitch,playing){const s=this.sim,p=s.player,t=s.time;
  // Licht, Himmel und Belichtung kommen aus World.applySky.
  // Nasser Asphalt: dunkler, viel glatter, spiegelt Himmel und Lichter.
  // Er trocknet deutlich langsamer, als der Regen aufhört.
  const regnet=s.weather==='rain'||s.weather==='storm'?1:0;
  this.nassheit+=(regnet-this.nassheit)*Math.min(1,dt*(regnet?.35:.06));
  if(Math.abs(this.nassheit-(this.nassheitZuletzt??-1))>.004){
   this.nassheitZuletzt=this.nassheit;const n=this.nassheit;
   for(const m of this.strassenMaterialien){
    m.roughness=.93-n*.72;m.metalness=.03+n*.30;
    m.color.setScalar(1-n*.46);m.envMapIntensity=.5+n*1.6;
   }
  }
  this.gun.scale.z=p.weapon==='rifle'?2.4:p.weapon==='shotgun'?2.1:1;this.gun.scale.x=p.weapon==='taser'?1.3:1;this.player.position.y=groundAt(p.x,p.z)+(p.y||0)-(p.sneak?.35:0)+(this.player.userData.bob||0);
  this.player.rotation.x=this.player.userData.vorlage||0;this.player.scale.set(1,s.active===1?.96:1,1);this.player.rotation.z=s.dodgeTime>0?.65:(this.player.userData.neigung||0);this.player.userData.arms[0].rotation.x=s.meleeTime>0?-1.5:this.player.userData.arms[0].rotation.x;this.player.userData.hair.scale.y=p.hair===1?1.35:p.hair===2?.4:1.08;this.player.userData.tattoo.visible=p.tattoo;for(const part of this.player.userData.garments||[])part.material=this.player.userData.body.material;this.player.userData.body.material.color.setHex(p.clothes==='orange'?0xe2a062:p.clothes==='blue'?0x557da3:0x6b8b70);
  this.autoFern.beginn();
  s.cars.forEach((c,i)=>{const m=this.cars[i],d=vehicleTypes[c.model];if(!m)return;
   const weg=distance(c,p),grob=weg>52&&['car','pickup'].includes(d.shape)&&c!==p.car;
   if(grob&&weg<330){this.autoFern.hinzu(c.x,groundAt(c.x,c.z)+(c.alt||0),c.z,c.yaw,
    Math.max(d.scale?.[0]||1,d.scale?.[2]||1));m.visible=false;return;}
   m.visible=weg<320;const water=d.medium==='water';m.position.y=water?Math.sin(t*1.8+c.x)*.15-.4:groundAt(c.x,c.z)+(c.alt||0);if(m.userData.rotor)m.userData.rotor.rotation[d.shape==='plane'?'z':'y']+=dt*(c===p.car?35:2);if(m.userData.bodyHeight)m.userData.body.scale.y=m.userData.bodyHeight*(.6+.4*c.health/100);if(!m.userData.paint||m.userData.paint!==c.color){m.userData.body.material=wolkenAufsetzen(new T.MeshPhysicalMaterial({color:c.color,roughness:.28,metalness:.12,clearcoat:1,clearcoatRoughness:.1}));if(m.userData.roof)m.userData.roof.material=m.userData.body.material;m.userData.paint=c.color;}m.rotation.z=['bike','jetski'].includes(d.shape)?Math.sin(t*3)*.015*Math.abs(c.speed):Math.sin(t*6)*.006*Math.min(3,Math.abs(c.speed));if(c.upgrades.suspension)m.position.y-=.12;this.applyUpgrades(m,c);if(m.userData.glass)m.userData.glass.visible=c.glass>20;const nachtAnteil=Math.min(1,this.sky.uniforms.nacht.value*1.25);
   if(m.userData.headlights)for(const l of m.userData.headlights){l.visible=c.lights>15;l.material.emissiveIntensity=.12+nachtAnteil*3.6;}
   this.autoFern?.leuchten(nachtAnteil);
   // Rücklichter glimmen und leuchten beim Bremsen deutlich auf.
   if(m.userData.taillights){const bremst=c===p.car&&(s.bremst||c.speed<-.3);
    for(const l of m.userData.taillights){l.visible=c.lights>15;l.material.emissiveIntensity=(bremst?2.6:.2)+nachtAnteil*1.1;}}if(m.userData.wheels)for(const w of m.userData.wheels)w.rotation.x+=dt*c.speed;});
  s.cops.forEach((c,i)=>{const m=this.cops[i],weg=distance(c,p);
   if(weg>52&&weg<330){this.autoFern.hinzu(c.x,groundAt(c.x,c.z),c.z,c.yaw);m.visible=false;}});
  this.autoFern.ende();
  this.figurFern.beginn();
  s.npcs.forEach((n,i)=>{const m=this.npcs[i],weg=distance(n,p);
   // Umschaltweite von 42 auf 34 m. Eine Figur aus 42 m ist bei 58° Blickfeld
   // gut zwanzig Bildpunkte hoch; 34 Meshes dafür sind nicht zu rechtfertigen.
   // Am Strand mit dreißig Leuten in Sichtweite kostete das über
   // vierhundert Draw Calls.
   const nah=weg<34;m.visible=nah&&weg<150;
   if(!nah&&weg<165&&n.health>0&&n.stun<=0)this.figurFern.hinzu(n.x,groundAt(n.x,n.z),n.z,n.yaw);
   if(!nah)return;
   m.position.y=groundAt(n.x,n.z)+(n.health<=0||n.stun>0?.2:(m.userData.bob||0));
  if(n.health>0&&n.stun<=0){m.rotation.z=m.userData.neigung||0;m.rotation.x=m.userData.vorlage||0;}if(n.stun>0)m.rotation.x=Math.PI/2;if(n.state==='tanzend'){m.rotation.z=Math.sin(t*5)*.1;m.userData.arms.forEach((a,i)=>a.rotation.x=-1+Math.sin(t*5+i)*.6);}});
  this.figurFern.ende();s.cops.forEach((c,i)=>{const m=this.cops[i];const weg=distance(c,p);if(weg<=52)m.visible=weg<230;m.position.y=groundAt(c.x,c.z);});
  const other=s.characters[1-s.active];this.contact.position.set(other.x,groundAt(other.x,other.z),other.z);if(s.mission===3&&s.campaign.stage===0)this.contact.position.set(-77,0,73);this.contact.visible=!other.car&&distance(other,p)<150;
  const goal=s.objective();this.marker.visible=s.mission<4||s.campaign.stage>0&&s.campaign.stage<4||!!s.activity;this.ring.visible=this.marker.visible;this.marker.position.set(goal.x,groundAt(goal.x,goal.z)+4+Math.sin(t*2)*.3,goal.z);this.ring.position.set(goal.x,groundAt(goal.x,goal.z)+.12,goal.z);
  if(!this.chute){this.chute=new T.Mesh(new T.SphereGeometry(2.8,16,8,0,Math.PI*2,0,Math.PI/2),new T.MeshStandardMaterial({color:0xd3b96f,side:T.DoubleSide}));this.scene.add(this.chute);}this.chute.visible=p.parachute;this.chute.position.set(p.x,this.player.position.y+4,p.z);
  if(s.witness){if(!this.witness){this.witness=this.human(0x879b83,0x303e4c);this.scene.add(this.witness);}this.witness.visible=s.campaign.stage===2&&!p.car;this.witness.position.set(s.witness.x,groundAt(s.witness.x,s.witness.z),s.witness.z);this.animateHuman(this.witness,t,1,false);}
  const c=locations.court;this.ball.position.set(c.x+.8,.6+Math.abs(Math.sin(t*4))*.8,c.z);if(s.activity?.kind==='basketball')this.ball.position.set(c.x,1+Math.sin(s.activity.phase*Math.PI)*5,c.z-s.activity.phase*11);
  this.street?.update(t,Math.min(1,this.sky.uniforms.nacht.value*1.25));
  this.updateFahrlicht(Math.min(1,this.sky.uniforms.nacht.value*1.25));
  this.updateInnenlicht(p);
  // Schüsse schrecken die Tiere auf.
  if(this.letzteSchuesse!==s.shots){this.letzteSchuesse=s.shots;this.tiere.aufschrecken();}
  this.tiere.update(dt,t,p);
  // Wind aus dem Wetter: bei Sturm wogt es deutlich, bei klarem Himmel kaum.
  this.gras.update(dt,t,p,s.weather==='storm'?1:s.weather==='rain'?.6:.25);
  this.palmenSetzen(t,s.weather==='storm'?3.4:s.weather==='rain'?1.8:1);
  this.laubwerk?.update(t,s.weather==='storm'?1:s.weather==='rain'?.6:.28);const unterWasser=(p.y||0)<-.2;
  for(const m of this.terrain)m.visible=(!m.userData.nurWasser||unterWasser)&&Math.hypot(m.position.x-p.x,m.position.z-p.z)<650;
  if(!this.barrierMeshes)this.barrierMeshes=[];while(this.barrierMeshes.length<s.barriers.length){const m=new T.Mesh(new T.BoxGeometry(5,1,1.2),new T.MeshStandardMaterial({color:0xe3c485}));this.scene.add(m);this.barrierMeshes.push(m);}this.barrierMeshes.forEach((m,i)=>{const b=s.barriers[i];m.visible=!!b;if(b)m.position.set(b.x,.5,b.z);});if(!this.policeHelicopter){this.policeHelicopter=this.car(0x4b6169,false,{model:'helicopter'});this.scene.add(this.policeHelicopter);}const h=s.policeHeli;this.policeHelicopter.position.set(h.x,h.alt,h.z);this.policeHelicopter.rotation.y=h.yaw;this.policeHelicopter.visible=distance(h,p)<400;if(h.alt>0)this.policeHelicopter.userData.rotor.rotation.y+=dt*40;
  const suchtAktiv=s.stars>=5&&h.alt>8;
  this.suchlicht.visible=suchtAktiv;this.suchfleck.visible=suchtAktiv;
  if(suchtAktiv){
   const ziel=s.lastSeen||p, wackeln=Math.sin(t*.9)*11, wackelnZ=Math.cos(t*1.3)*9;
   const zx=ziel.x+wackeln, zz=ziel.z+wackelnZ, zy=groundAt(zx,zz);
   this.suchlicht.position.set(h.x,h.alt-1.5,h.z);
   this.suchlicht.target.position.set(zx,zy,zz);this.suchlicht.target.updateMatrixWorld();
   this.suchlicht.intensity=430;
   this.suchfleck.position.set(zx,zy+.14,zz);
   this.suchfleck.material.opacity=.10+Math.min(1,this.sky.uniforms.nacht.value)*.16;
  }
  if(!this.placeMarkers){this.placeMarkers=[];for(const l of Object.values(locations)){const m=new T.Mesh(new T.OctahedronGeometry(.35),new T.MeshBasicMaterial({color:0x8bd4c1}));m.position.set(l.x,groundAt(l.x,l.z)+2.6,l.z);this.scene.add(m);this.placeMarkers.push(m);}}for(const m of this.placeMarkers){m.visible=Math.hypot(m.position.x-p.x,m.position.z-p.z)<65;m.rotation.y=t;}
 }
}
