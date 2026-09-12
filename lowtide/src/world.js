import * as T from './vendor/three.module.js';
import {roads,places,random} from './simulation.js';
import {Sky} from './sky.js';
import {createWater,updateWater} from './water.js';
import {Nachbearbeitung} from './post.js';
import {detailAufsetzen,NAESSE} from './detail.js';
const MONDLICHT=new T.Color(0x9db6d8),NEUTRAL=new T.Color(0xfff4e4);
// Fünf Hemdfarben über eine Hose waren als Menge erkennbar: dieselben fünf
// Leute, immer wieder. Zwölf mal sieben ergeben genug Kombinationen, dass
// eine Straße nicht mehr nach Belegschaft aussieht.
const HEMDEN=[0xb8bf9f,0x708ba9,0xe2c49c,0xaf6276,0x546a64,0xd8d2c4,0x8a6f9c,0xc47a55,
 0x4f7a68,0xbfae86,0x9aa8b4,0x6d5f52];
const HOSEN=[0x303a48,0x4a4137,0x2c3a34,0x5a5148,0x38424e,0x6a6155,0x25303a];
const cube=new T.BoxGeometry(1,1,1);
const mats=new Map();
// Alle leuchtenden Materialien an einer Stelle, damit die Nacht sie zentral schalten kann.
export const leuchtMaterialien=[];
function mat(color,emissive=false){const key=color+':'+emissive;if(!mats.has(key)){const m=new T.MeshStandardMaterial({color,roughness:.78,metalness:.08,emissive:emissive?color:0,emissiveIntensity:emissive?.9:0});
 // Leuchtflächen bleiben glatt — ein Fenster, das von innen leuchtet, hat
 // keine Körnung. Alles andere bekommt Struktur aus der Weltposition.
 if(!emissive)detailAufsetzen(m);
 mats.set(key,m);if(emissive)leuchtMaterialien.push(m);}return mats.get(key);}
export class World{
 constructor(canvas,sim){this.sim=sim;this.scene=new T.Scene();this.scene.fog=new T.FogExp2(0xc6a7a0,.0038);this.renderer=new T.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});this.renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));this.renderer.shadowMap.enabled=true;this.renderer.shadowMap.type=T.PCFShadowMap;this.renderer.outputColorSpace=T.SRGBColorSpace;this.renderer.toneMapping=T.ACESFilmicToneMapping;this.renderer.toneMappingExposure=1.2;this.sky=new Sky(this.renderer);this.scene.add(this.sky.mesh);this.sonnenRichtung=new T.Vector3();this.blitz=0;this.camera=new T.PerspectiveCamera(58,innerWidth/innerHeight,.45,650);this.camera.position.set(-14,12,98);this.camera.lookAt(-40,3,15);this.groups=new Map();this.rng=random(78);this.hemi=new T.HemisphereLight(0xc4dceb,0x51443e,2.1);this.scene.add(this.hemi);this.sun=new T.DirectionalLight(0xffc995,3);this.sun.position.set(-80,110,20);this.sun.castShadow=true;Object.assign(this.sun.shadow.camera,{left:-130,right:130,top:130,bottom:-130,near:1,far:1500});this.sun.shadow.mapSize.set(2048,2048);this.sun.shadow.bias=-.0006;this.sun.shadow.normalBias=.035;this.scene.add(this.sun);this.scene.add(this.sun.target);this.build();this.flush();this.player=this.human(0xe2a062,0x253442);this.scene.add(this.player);this.npcs=sim.npcs.map((n,i)=>{const m=this.human(HEMDEN[i%HEMDEN.length],HOSEN[(i*3+i%7)%HOSEN.length],false);this.scene.add(m);return m;});this.cars=sim.cars.map(c=>{const m=this.car(c.color,false,c);this.scene.add(m);return m;});this.cops=sim.cops.map(()=>{const m=this.car(0xe4e7df,true);this.scene.add(m);return m;});this.contact=this.human(0xd4d2c9,0x242e3c);this.contact.position.set(places.mara.x,0,places.mara.z);this.scene.add(this.contact);this.guard=this.human(0x425164,0x26303c);this.guard.position.set(-73,0,-52);this.scene.add(this.guard);this.marker=new T.Mesh(new T.OctahedronGeometry(.7),new T.MeshBasicMaterial({color:0xeccb80}));this.scene.add(this.marker);this.ring=new T.Mesh(new T.RingGeometry(1.8,2,40),new T.MeshBasicMaterial({color:0xeccb80,side:T.DoubleSide,transparent:true,opacity:.75}));this.ring.rotation.x=-Math.PI/2;this.scene.add(this.ring);this.bulletMeshes=[];this.setupRain();
  // Nachbearbeitung: Überstrahlen, Farbkurve, Randabdunklung, Korn. Ab hier
  // tonwertet die letzte Stufe, nicht mehr der Renderer.
  this.post=new Nachbearbeitung(this.renderer);
  this.resize();}
 // nx und nz neigen den Quader um die x- und z-Achse. Ohne sie gäbe es
 // keine Satteldächer, Rampen, Steilhänge oder umgestürzten Stämme.
 box(x,y,z,w,h,d,color=0x999999,rot=0,emissive=false,nx=0,nz=0){const key=color+':'+emissive+':'+Math.floor(x/100)+':'+Math.floor(z/100);let g=this.groups.get(key);if(!g){g={material:mat(color,emissive),items:[]};this.groups.set(key,g);}g.items.push({x,y,z,w,h,d,rot,nx,nz});}
 flush(){const o=new T.Object3D();for(const g of this.groups.values()){const mesh=new T.InstancedMesh(cube,g.material,g.items.length);for(let i=0;i<g.items.length;i++){const a=g.items[i];o.position.set(a.x,a.y,a.z);o.scale.set(a.w,a.h,a.d);o.rotation.set(a.nx||0,a.rot,a.nz||0);o.updateMatrix();mesh.setMatrixAt(i,o.matrix);}mesh.castShadow=true;mesh.receiveShadow=true;mesh.computeBoundingSphere();this.scene.add(mesh);(this.bloecke||=[]).push(mesh);}this.groups.clear();}
 dynbox(g,x,y,z,w,h,d,color){const m=new T.Mesh(cube,mat(color));m.position.set(x,y,z);m.scale.set(w,h,d);m.castShadow=true;m.receiveShadow=true;g.add(m);return m;}
 // Beschriftung ohne Trägerplatte. Vorher standen hier 13-19 m breite,
 // undurchsichtige Tafeln quer in der Stadt, von hinten spiegelverkehrt.
 text(label,x,y,z,width=12,color='#f3d9ad',rotation=0){const c=document.createElement('canvas');c.width=512;c.height=128;const ctx=c.getContext('2d');ctx.clearRect(0,0,512,128);ctx.font='bold 60px Arial';ctx.textAlign='center';ctx.textBaseline='middle';ctx.lineJoin='round';ctx.lineWidth=11;ctx.strokeStyle='rgba(8,16,22,.78)';ctx.strokeText(label,256,68,470);ctx.fillStyle=color;ctx.fillText(label,256,68,470);const texture=new T.CanvasTexture(c);texture.colorSpace=T.SRGBColorSpace;const m=new T.Mesh(new T.PlaneGeometry(width,width/4),new T.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false,side:T.FrontSide,toneMapped:false}));m.renderOrder=2;m.position.set(x,y,z);m.rotation.y=rotation;this.scene.add(m);return m;}
 build(){
  this.box(0,-.6,0,240,1,240,0x857d6f);this.box(158,-4.2,0,85,1,800,0x2b4a4c);this.box(109,-.12,0,9,.2,240,0x9d9583);this.box(114,.45,0,.7,1,240,0xa39d88);
  for(const r of roads){this.box(r,-.04,-2,15,.12,235,0x333d45);this.box(-2,-.035,r,235,.12,15,0x333d45);for(let j=-115;j<113;j+=8){if(!roads.some(v=>Math.abs(j-v)<11)){this.box(r,.035,j,.15,.025,3,0xc9b98e);this.box(j,.035,r,3,.025,.15,0xc9b98e);}}for(const side of [-1,1]){this.box(r+side*8,.075,-2,1,.18,235,0x8e8b7f);this.box(-2,.075,r+side*8,235,.18,1,0x8e8b7f);}}
  for(const x of roads)for(const z of roads)for(let n=-5;n<=5;n+=2){this.box(x+n,.055,z+10,1,.03,3,0xc3c4b1);this.box(x+10,.055,z+n,3,.03,1,0xc3c4b1);}
  const colors=[0xaaa69b,0x8e9a9b,0xc0b29b,0x8e9296,0xabc2bc,0xc4ad9d];
  this.sim.buildings.forEach((b,i)=>{const co=colors[i%colors.length];this.box(b.x,b.h/2,b.z,b.w,b.h,b.d,co);this.box(b.x,b.h+.35,b.z,b.w+1,.7,b.d+1,0x515b61);this.box(b.x,b.h+1.4,b.z,5,2.1,6,0x738083);this.box(b.x,1.8,b.z+b.d/2+.1,b.w,3.6,.2,0x2c4d52);for(let y=5;y<b.h-1;y+=3.7)for(let u=-6;u<=6;u+=4){for(const side of [-1,1]){this.box(b.x+u,y,b.z+side*(b.d/2+.015),2,1.9,.06,(i+u+y)%3>1?0xd9bc85:0x3c5a69,0,(i+u+y)%3>1);}}for(let y=5;y<b.h-1;y+=3.7)for(let u=-15;u<=15;u+=5)for(const side of [-1,1])this.box(b.x+side*(b.w/2+.015),y,b.z+u,.06,1.9,2,0x486673);if(i%3===0){this.box(b.x,3.7,b.z+20,17,.25,2.5,0xa87364);this.text(['TIDELINE MOTEL','PELICAN MARKET','MERCY RECORDS','SOLACE STUDIO','NORTH STAR'][i%5],b.x,2.6,b.z+19.3,13);}});
  for(const s of this.sim.solids.filter(b=>['warehouse','crate'].includes(b.kind))){this.box(s.x,s.h/2,s.z,s.w,s.h,s.d,s.kind==='crate'?0x9d7851:0x78948f);if(s.kind==='crate')for(const z of [-1,1])this.box(s.x,s.h/2,s.z+z*s.d/2,s.w+.1,.15,.08,0x423f32);}
  // Cutaway industrial interior: roof trusses keep the interior readable.
  this.box(-77,.02,-74,41,.1,37,0x758181);for(let z=-91;z<-55;z+=9){this.box(-77,7,z,42,.3,.35,0x3c565e);this.box(-77,6.8,z,8,.15,.25,0xd9e5cd,0,true);}this.text('CALDERA SHIPPING',-77,5.8,-54.4,19,'#bbdcce');this.gateMesh=new T.Group();this.dynbox(this.gateMesh,-77,2.4,-55,8,4.8,.3,0x4b6770);this.scene.add(this.gateMesh);this.disk=new T.Group();this.dynbox(this.disk,-78,.8,-82,3.6,1.5,1.8,0x253c46);this.dynbox(this.disk,-78,1.65,-82,.9,.15,.6,0xe9bd72);this.scene.add(this.disk);this.box(-55.2,1.6,-81,1,1.3,.7,0xdac9a0);this.box(-54.6,1.8,-81,.1,.12,.2,0xe2a467,0,true);this.text('GRID 04',-54.45,2.5,-81,2.2,'#e7c688',Math.PI/2);
  this.text('HARBOR AVENUE',-40,4,81,9);this.text('PORT MERCY',106,6,-102,17,'#b7e7d9',-Math.PI/2);this.text('JACKET EXCHANGE',-111,2.8,66,6,'#c9cde0',Math.PI/2);this.box(-111,1.2,66,1.3,2.4,4,0x56657b);
  for(let z=-100;z<113;z+=20){this.palm(104,z,7+this.rng()*3);this.lamp(90,z);this.box(101,.7,z+6,1.2,1.4,3.2,0x666658);this.box(101,1.5,z+6,.25,.5,3.2,0x685644);}
  for(let x=-108;x<100;x+=30){this.palm(x,105,6+this.rng()*3);for(const z of [-109,10])this.lamp(x,z);}
  for(const z of [-43,16,77])for(let x=-90;x<80;x+=30){this.box(x,.35,z,1.1,.7,1.1,0x566b68);this.box(x,1.05,z,.8,.9,.8,0x486b59);}
  for(let i=0;i<12;i++){const x=123+(i%3)*9,z=-75+Math.floor(i/3)*13;this.box(x,1.8,z,7,3.4,11,[0x4a797d,0x935e57,0xb8955d][i%3]);for(let u=-4;u<=4;u+=2)this.box(x+3.51,1.8,z+u,.12,3.3,.13,0x3f5b60);}
  // Original harbor crane and moored cargo hull.
  this.box(145,14,-94,1.5,28,1.5,0xbc895e);this.box(145,27,-77,2,2,40,0xbc895e);this.box(145,16,-60,.2,21,.2,0x293c43);this.box(160,.8,-48,18,4,56,0x293f49);this.box(160,4,-66,15,5,9,0xc7c6b6);this.box(160,8,-66,9,3,8,0xd6d2bf);
  // Beyond the playable district: skyline and islands, explicitly scenery.
  for(let i=0;i<(this.sim.worldBuildings?0:36);i++){const x=-170+this.rng()*270,z=-150-this.rng()*70,h=20+this.rng()*85;this.box(x,h/2,z,12+this.rng()*14,h,10+this.rng()*15,0x687983);}
  
  const wasser=createWater('ozean');this.waterUniforms=wasser.uniforms;
  this.water=new T.Mesh(new T.PlaneGeometry(1800,2600,150,200),wasser.material);
  this.water.rotation.x=-Math.PI/2;this.water.position.set(1000,-.55,0);this.scene.add(this.water);
  // Der Salzsumpf im Westen war bisher nur eine eingefärbte Geländefläche.
  const sumpf=createWater('sumpf');this.marshUniforms=sumpf.uniforms;
  this.marsh=new T.Mesh(new T.PlaneGeometry(150,155,30,32),sumpf.material);
  this.marsh.rotation.x=-Math.PI/2;this.marsh.position.set(-472,-.62,55);this.scene.add(this.marsh);
 }
 palm(x,z,h){this.box(x,h/2,z,.45,h,.45,0x8e7b59,.06);for(let i=0;i<7;i++){const a=i*Math.PI*2/7;this.box(x+Math.sin(a)*2,h,z+Math.cos(a)*2,1,.18,5,0x426c5b,a);}}
 lamp(x,z){this.box(x,3.3,z,.15,6.6,.15,0x3a4a50);this.box(x+.6,6.5,z,1.4,.15,.3,0x3a4a50);this.box(x+1,6.4,z,.5,.08,.3,0xffe2a4,0,true);(this.lampen||=[]).push({x:x+1,y:6.2,z});}
 human(color,pants){const g=new T.Group();this.dynbox(g,0,1.18,0,.57,.72,.33,color);this.dynbox(g,0,1.79,0,.34,.38,.33,0xb68c6e);this.dynbox(g,0,2,0,.37,.1,.35,0x302e2b);const legs=[];for(const s of [-1,1]){const leg=new T.Group();leg.position.set(s*.16,.86,0);this.dynbox(leg,0,-.37,0,.23,.75,.26,pants);this.dynbox(leg,0,-.77,.09,.25,.13,.4,0x1d2b31);g.add(leg);legs.push(leg);}const arms=[];for(const s of [-1,1]){const arm=new T.Group();arm.position.set(s*.4,1.45,0);this.dynbox(arm,0,-.24,0,.19,.5,.24,color);this.dynbox(arm,0,-.55,0,.17,.17,.19,0xb68c6e);g.add(arm);arms.push(arm);}g.userData={legs,arms,body:g.children[0]};return g;}
 car(color,police=false){const g=new T.Group();const body=this.dynbox(g,0,.85,0,1.95,.55,4.3,color);this.dynbox(g,0,1.35,-.15,1.68,.62,2.15,0x283e48);this.dynbox(g,0,1.7,-.2,1.7,.15,2.2,police?0x203243:color);this.dynbox(g,0,.77,2.2,1.8,.2,.12,0xb8beb2);this.dynbox(g,0,.7,-2.2,1.8,.18,.1,0x353e43);for(const x of [-.65,.65]){this.dynbox(g,x,1,2.17,.5,.22,.06,0xffe2a4);this.dynbox(g,x,1,-2.17,.5,.18,.06,0xb75049);}const wheels=[];for(const x of [-1,1])for(const z of [-1.35,1.35]){const w=new T.Mesh(new T.CylinderGeometry(.42,.42,.24,12),mat(0x20262c));w.rotation.z=Math.PI/2;w.position.set(x,.46,z);g.add(w);wheels.push(w);this.dynbox(g,x*1.13,.46,z,.02,.32,.32,0xa5b2b5);}let lights=[];if(police){this.dynbox(g,0,1.88,0,1.4,.13,.4,0x263139);lights=[this.dynbox(g,-.44,2,0,.5,.16,.35,0xce5056),this.dynbox(g,.44,2,0,.5,.16,.35,0x3a8ac8)];}g.userData={body,wheels,lights};return g;}
 setupRain(){this.gun=new T.Group();this.dynbox(this.gun,0,0,.18,.12,.16,.43,0x263138);this.dynbox(this.gun,0,-.12,.04,.11,.2,.12,0x353a3c);this.player.userData.arms[1].add(this.gun);this.gun.position.set(0,-.59,0);this.gun.rotation.x=1.2;// Tropfen als kurze Striche. Als Points waren es bildschirmparallele Quadrate,
  // die eher nach Hagel aussahen als nach Regen.
  const tropfen=1900,a=new Float32Array(tropfen*6);
  for(let i=0;i<tropfen;i++){const x=(this.rng()-.5)*74,y=this.rng()*38,z=(this.rng()-.5)*74,l=.7+this.rng()*.5;
   a.set([x,y,z,x+.16,y+l,z+.1],i*6);}
  const geo=new T.BufferGeometry();geo.setAttribute('position',new T.BufferAttribute(a,3));
  this.rain=new T.LineSegments(geo,new T.LineBasicMaterial({color:0xcfe0e6,transparent:true,opacity:.42,depthWrite:false}));
  this.rainHoehe=38;this.scene.add(this.rain);}
 resize(){this.renderer.setSize(innerWidth,innerHeight);this.camera.aspect=innerWidth/innerHeight;this.camera.updateProjectionMatrix();this.post?.groesse(innerWidth,innerHeight);}
 update(dt,camYaw,camPitch,playing){const s=this.sim,p=s.player,t=s.time;const himmelJetzt=this.applySky(dt);updateWater(this.waterUniforms,himmelJetzt,t,this.camera);updateWater(this.marshUniforms,himmelJetzt,t,this.camera);this.rain.visible=s.weather==='rain'||s.weather==='storm';this.rain.material.opacity=s.weather==='storm'?.6:.4;if(this.rain.visible){this.rain.position.set(p.x,0,p.z);const a=this.rain.geometry.attributes.position,fall=dt*(s.weather==='storm'?36:26),h=this.rainHoehe;for(let i=0;i<a.count;i++)a.setY(i,(a.getY(i)-fall+h)%h);a.needsUpdate=true;}
  this.player.position.set(p.x,p.sneak?-.35:0,p.z);this.player.rotation.y=p.yaw;this.player.visible=!p.car;this.gun.visible=p.armed;this.player.userData.body.material=mat(p.clothes==='orange'?0xe2a062:0x557da3);this.animateHuman(this.player,t,(s.paused?0:distance2(this.prev,p)>0.001?1:0),p.armed);this.prev={x:p.x,z:p.z};s.npcs.forEach((n,i)=>{const m=this.npcs[i];m.position.set(n.x,n.health<=0?.25:0,n.z);m.rotation.set(n.health<=0?Math.PI/2:0,n.yaw,0);this.animateHuman(m,t+n.id,n.state==='normal'?1:n.state==='flüchtend'?2:0,n.state==='filmend');});s.cars.forEach((c,i)=>{const m=this.cars[i];m.position.set(c.x,0,c.z);m.rotation.y=c.yaw;m.userData.body.scale.y=.55*(.65+.35*c.health/100);m.userData.body.rotation.z=c.health<40?.05:0;});s.cops.forEach((c,i)=>{const m=this.cops[i];m.position.set(c.x,0,c.z);m.rotation.y=c.yaw;for(let j=0;j<2;j++)m.userData.lights[j].visible=c.active&&(Math.floor(t*8)+j)%2===0;});this.contact.position.set(s.mission>=3?places.safe.x:places.mara.x,0,s.mission>=3?places.safe.z:places.mara.z);this.gateMesh.visible=!s.doorOpen;this.disk.visible=s.mission<3;const goal=s.objective();this.marker.position.set(goal.x,4+Math.sin(t*2)*.3,goal.z);this.marker.rotation.y=t;this.marker.visible=s.mission<4;this.ring.position.set(goal.x,.15,goal.z);this.ring.visible=s.mission<4;
  for(const m of this.bulletMeshes){this.scene.remove(m);m.geometry.dispose();m.material.dispose();}this.bulletMeshes=[];for(const tr of s.tracers){const geo=new T.BufferGeometry().setFromPoints([new T.Vector3(tr.x,1.5,tr.z),new T.Vector3(tr.end.x,1.3,tr.end.z)]);const l=new T.Line(geo,new T.LineBasicMaterial({color:0xffe3a3}));this.scene.add(l);this.bulletMeshes.push(l);}
  // freieKamera hängt die Verfolgerkamera aus — für Luftbilder und Prüfläufe.
  if(playing&&!this.freieKamera){const dist=p.car?10:6.5;let target=new T.Vector3(p.x,1.6,p.z);let desired=new T.Vector3(p.x-Math.sin(camYaw)*dist,3.7+camPitch*6+(p.car?1.5:0),p.z-Math.cos(camYaw)*dist); // Camera collision against the same world solids.
   for(let a=.15;a<1;a+=.06){const x=target.x+(desired.x-target.x)*a,z=target.z+(desired.z-target.z)*a,y=target.y+(desired.y-target.y)*a;if(s.solids.some(b=>Math.abs(x-b.x)<b.w/2+.15&&Math.abs(z-b.z)<b.d/2+.15&&y<b.h+.2)){desired.lerpVectors(target,desired,Math.max(.13,a-.07));break;}}const elevation=(this.sim.ground?.(p)||0)+(p.y||0);desired.y+=elevation;this.camera.position.lerp(desired,this.kameraSofort?1:1-Math.exp(-dt*10));this.kameraSofort=false;this.camera.lookAt(p.x,1.5+elevation,p.z);
  }this.updateExtras?.(dt,camYaw,camPitch,playing);this.sky.mesh.position.copy(this.camera.position);this.zeichne();
 }
 // Ein Bild ausgeben. Steht als eigene Methode da, weil auch die Kamera-App
 // im Telefon rendert und dasselbe Bild bekommen soll wie der Bildschirm.
 zeichne(){
  const nacht=this.sky?.uniforms?.nacht?.value??0;
  if(this.post)this.post.render(this.scene,this.camera,this.sim.time,nacht);
  else this.renderer.render(this.scene,this.camera);
 }
 // Sonnenstand, Himmel, Nebel, Umgebungslicht und Belichtung aus einer Quelle.
 // Die Welt liegt in Blöcken zu 100 m je Farbe vor. Three.js verwirft sie
 // außerhalb des Sichtkegels, aber nicht nach Entfernung: aus der Innenstadt
 // heraus wurden Flugfeld und Insel weiter gezeichnet, obwohl sie hinter drei
 // Dunstschichten liegen. Die Grenze folgt der Nebeldichte — beim Luftbild
 // (nebelFaktor .06) reicht sie dadurch über die ganze Karte.
 bloeckeSichten(dichte){
  if(!this.bloecke)return;
  // exp2-Nebel: bei d*x = 2.6 bleiben unter 0.1 % Restsicht.
  const weite=Math.min(2600,Math.max(320,2.6/Math.max(1e-5,dichte)));
  const k=this.camera.position;
  for(const m of this.bloecke){
   const s=m.boundingSphere;
   if(!s)continue;
   m.visible=k.distanceTo(s.center)-s.radius<weite;
  }
 }
 applySky(dt){
  const s=this.sim,p=s.player;
  const himmel=this.sky.update(s.hour,s.weather,this.camera.position,s.time);
  this.scene.fog.color.copy(himmel.nebel);
  // nebelFaktor senkt den Dunst für Luftbilder; aus 900 m wäre die Karte
  // sonst eine weiße Fläche.
  this.scene.fog.density=himmel.nebelDichte*(this.nebelFaktor??1);
  this.bloeckeSichten(himmel.nebelDichte*(this.nebelFaktor??1));
  // Steht die Sonne unter dem Horizont, übernimmt der Mond dieselbe Bahn
  // gespiegelt — sonst wäre die Nacht eine schattenlose graue Fläche.
  const unterHorizont=himmel.richtung.y<0,richtung=this.sonnenRichtung.copy(himmel.richtung);
  if(unterHorizont)richtung.negate();
  const weite=this.freieKamera?520:130;
  if(this.sun.shadow.camera.right!==weite){Object.assign(this.sun.shadow.camera,{left:-weite,right:weite,top:weite,bottom:-weite});this.sun.shadow.camera.updateProjectionMatrix();}
  const abstand=this.freieKamera?700:190;
  this.sun.position.set(p.x+richtung.x*abstand,Math.max(6,richtung.y*abstand),p.z+richtung.z*abstand);
  this.sun.target.position.set(p.x,0,p.z);
  this.sun.color.copy(unterHorizont?MONDLICHT:himmel.sun);
  this.sun.intensity=unterHorizont?.30*(1-himmel.dunst*.7):himmel.sonnenStaerke;
  // Reines Zenitblau als Himmelslicht färbt die ganze Stadt violett; der
  // Horizontanteil entspricht eher dem, was tatsächlich auf Straßenhöhe ankommt.
  this.hemi.color.copy(himmel.zenith).lerp(himmel.horizon,.66).lerp(NEUTRAL,.38).multiplyScalar(1.28);
  this.hemi.groundColor.copy(himmel.boden);
  this.hemi.intensity=himmel.himmelStaerke+.14;
  this.blitz=Math.max(0,this.blitz-dt*4.2);
  if(s.weather==='storm'&&Math.random()<dt*.14)this.blitz=1;
  if(this.blitz>0){const f=this.blitz*this.blitz;this.hemi.intensity+=f*6;this.sun.intensity+=f*2.5;}
  // Die Belichtung geht jetzt an die Nachbearbeitung: der Renderer tonwertet
  // nicht mehr selbst, toneMappingExposure liefe dort ins Leere.
  // Nässe folgt dem Wetter mit Nachlauf: der Asphalt trocknet nicht in dem
  // Moment, in dem der Regen aufhört.
  const nassZiel=s.weather==='storm'?1:s.weather==='rain'?.82:0;
  NAESSE.value+=(nassZiel-NAESSE.value)*Math.min(1,dt*(nassZiel>NAESSE.value?.5:.12));
  const belichtung=himmel.belichtung*(1+this.blitz*.3);
  this.renderer.toneMappingExposure=belichtung;
  if(this.post){
   this.post.endeU.belichtung.value=belichtung;
   // Nachts strahlen Lampen und Fenster stärker über, tagsüber würde
   // dieselbe Stärke die Fassaden ausbrennen.
   this.post.endeU.staerke.value=.42+himmel.nacht*.55;
   this.post.endeU.schwelle=this.post.hellU.schwelle;
   this.post.hellU.schwelle.value=.92-himmel.nacht*.34;
   // Korn nachts nur leicht anheben. Mit .054 lag über der ganzen Nachtstadt
   // ein Rauschteppich, der wie ein Videofehler aussah.
   this.post.endeU.koernung.value=.021+himmel.nacht*.011;
   // Verdeckung nachts zurücknehmen: es gibt kaum Umgebungslicht, das sie
   // wegnehmen könnte, und die Kanten wurden dadurch tiefschwarz.
   this.post.aoU.staerke.value=.7*(1-himmel.nacht*.55);
  }
  const nachtAnteil=Math.min(1,himmel.nacht*1.25);
  for(const m of leuchtMaterialien)m.emissiveIntensity=.06+nachtAnteil*1.45;
  this.updateStrassenlicht?.(nachtAnteil,p);
  const env=this.sky.refreshEnvironment(s.hour,s.weather);
  if(env)this.scene.environment=env;
  return himmel;
 }
 animateHuman(m,t,moving,armed){const {legs,arms}=m.userData;legs.forEach((l,i)=>l.rotation.x=Math.sin(t*8* Math.max(1,moving)+i*Math.PI)*.5*Math.min(1,moving));arms.forEach((a,i)=>a.rotation.x=armed?-1.2:-Math.sin(t*8+i*Math.PI)*.35*Math.min(1,moving));}
}
function distance2(a,b){return a?Math.hypot(a.x-b.x,a.z-b.z):0;}
