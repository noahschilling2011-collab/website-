import {Simulation,clamp,distance,intersects,lineClear,places} from './simulation.js';
import {bounds,locations,vehicleTypes,weapons,waterAt,groundAt,roadSegments,immobilien,rennen,schatzOrte} from './content.js';
import {findPath} from './navigation.js';
import {storyAufbau,storyZiel,storyTitel,storyAktion,storyTick,konvoiRammen,starteAkt,beendeKampagne,storyReparieren} from './story.js';
export class Campaign extends Simulation{
 constructor(){
  super();this.active=0;Object.assign(this.player,{id:'eli',name:'ELI VOSS',stamina:100,fitness:0,y:0,vy:0,weapon:'pistol',inventory:{pistol:{ammo:12,reserve:72}},cover:false,hair:0,tattoo:false,air:100,parachute:false,fish:0});
  this.characters=[this.player,{...this.player,id:'mara',name:'MARA QUINN',x:-25,z:73,money:600,clothes:'blue',inventory:{pistol:{ammo:12,reserve:48},taser:{ammo:2,reserve:12}},weapon:'taser',car:null}];
  this.relationship=50;this.campaign={stage:0,choice:null,relay:false,archive:false,witness:false,delivered:false};this.activity=null;this.unlock=null;this.reloadJob=null;this.dodgeTime=0;this.meleeTime=0;this.tickCount=0;this.weatherIndex=0;this.currentEvent=null;this.nextEvent=25;this.policeHeli={x:-360,z:305,alt:0,yaw:0};this.checkpoints=[];this.barriers=[];this.cameras=[];this.navRevision=0;this.homeOwned=true;this.motelOwned=false;this.highScores={};this.worldBuildings=[];this.roomWalls=[];this.moneyEarned=0;this.feed=[];this.konto=[];this.fotos=[];this.besitz={};this.letzterZahltag=0;
  this.expandWorld();
 }
 expandWorld(){
  // Eight new downtown blocks, separated by the existing streets extended west.
  for(const x of [-310,-250,-190])for(const z of [-130,-70,-10,50]){if(x===-190||x===-250&&z===-10||x===-310&&z===-70)continue;const b=this.addSolid(x,z,35,34,'newbuilding',30+Math.floor(this.rng()*45));this.worldBuildings.push(b);}
  // Small houses and farms are solid, while service buildings are cutaway interiors.
  for(const x of [-65,-10,45])for(const z of [-260,-365])this.worldBuildings.push(this.addSolid(x,z,22,24,'house',7));
  for(const [x,z,w,d,h] of [[-375,-285,28,22,9],[-360,355,33,25,12],[-405,355,32,24,9],[285,170,30,22,12],[315,265,28,25,9]])this.worldBuildings.push(this.addSolid(x,z,w,d,'house',h));
  for(const id of ['garage','shop','clinic','home','club','diner','motel','records']){const l=locations[id],w=id==='garage'?22:16,d=16;for(const wall of [{x:l.x-w/2,z:l.z-4,w:1,d},{x:l.x+w/2,z:l.z-4,w:1,d},{x:l.x,z:l.z-12,w:w+1,d:1}])this.roomWalls.push(this.addSolid(wall.x,wall.z,wall.w,wall.d,'room',5));}
  const entries=[['compact',-148,101],['suv',-160,107],['super',-280,98],['muscle',-220,97],['pickup',-340,-240],['motorcycle',-140,102],['dirtbike',-455,-355],['quad',-390,36],['truck',-355,265],['bus',-162,157],['boat',123,136],['jetski',127,155],['helicopter',-360,305],['plane',-315,325]];
  this.cars.forEach((c,i)=>Object.assign(c,{model:i===0?'sedan':['compact','sedan','suv','muscle'][i%4],fuel:100,upgrades:{},owner:i===0?'eli':null,alt:0,tires:100,glass:100,lights:100}));
  entries.forEach(([model,x,z],i)=>this.cars.push({id:'LM-'+(700+i),model,x,z,yaw:Math.PI,speed:0,health:100,fuel:100,tires:100,glass:100,lights:100,alt:0,type:'parked',color:[0x568a89,0xc09b62,0x99635d,0x667ca5][i%4],upgrades:{},owner:['motorcycle','boat'].includes(model)?'mara':null}));
  for(let i=18;i<54;i++){const x=i<36?-151-(i%3)*60:-89+(i%3)*54,z=i<36?-152+Math.floor((i-18)/3)*48:-295;const path=[{x,z},{x:x+20,z},{x:x+20,z:z+18},{x,z:z+18}];this.npcs.push({id:i,x,z,yaw:0,state:'normal',timer:0,health:100,path,target:1,personality:['caller','filmer','coward','aggressive'][i%4],pace:1.1+this.rng()*.6,report:null});}
  this.npcs.forEach(n=>{n.home={...n.path[0]};n.work={...n.path[2]};n.originalPath=n.path.map(p=>({...p}));n.schedule='street';n.stun=0;});
  for(let i=6;i<12;i++)this.cops.push({id:i,x:-280+(i-6)*4,z:-180,yaw:0,active:false,health:100,route:[],target:0,repath:0,shot:0});
  this.cops.forEach(c=>{c.base={x:c.x,z:c.z};c.role=c.id>=6?'tactical':'patrol';c.stun=0;});
  this.cameras=[{x:-54,z:-61,yaw:-Math.PI/2,range:24},{x:-225,z:30,yaw:Math.PI,range:26},{x:-100,z:200,yaw:0,range:28}];
  for(let i=0;i<3;i++){const x=-327+i*7,z=-105;this.npcs.push({id:54+i,x,z,yaw:0,state:'normal',timer:0,health:100,path:[{x,z},{x,z:z+12}],target:1,personality:'guard',pace:1.8,report:null,stun:0,guard:true,home:{x,z},work:{x,z},shot:0});}
  // Leben außerhalb der Innenstadt. Mercy Beach, die Promenade, der
  // Vorortpark und die Marina waren menschenleer.
  const aussen=[];
  for(let i=0;i<12;i++){const x=100+(i%3)*6,z=150+i*22;aussen.push([x,z,[{x,z},{x:x+9,z:z+7},{x:x-7,z:z+13},{x,z}]]);}
  for(let i=0;i<5;i++){const x=96,z=170+i*46;aussen.push([x,z,[{x,z},{x,z:z+34}]]);}
  for(let i=0;i<4;i++){const x=-95+(i%2)*8,z=-327+i*5;aussen.push([x,z,[{x,z},{x:x+14,z},{x:x+14,z:z+11},{x,z:z+11}]]);}
  for(let i=0;i<4;i++){const x=250-i*3,z=228+i*11;aussen.push([x,z,[{x,z},{x,z:z+16}]]);}
  // home, work und originalPath werden weiter oben für alle bisherigen NPCs
  // gesetzt; diese hier kommen danach und brauchen sie selbst. work greift
  // auf path[2] zu, das kurze Wege nicht haben.
  aussen.forEach(([x,z,path],k)=>this.npcs.push({id:57+k,x,z,yaw:0,state:'normal',timer:0,health:100,
   path,target:1,personality:['caller','filmer','coward','aggressive'][k%4],pace:.9+(k%5)*.16,
   report:null,stun:0,schedule:'street',home:{...path[0]},work:{...(path[2]||path[path.length-1])},
   originalPath:path.map(q=>({...q}))}));
  // Transport, Fluchtboot und die vier Aktwachen. Sie entstehen hier und
  // nicht erst beim Missionsstart, weil die Meshes einmalig nach Index
  // angelegt werden — später eingefügte Fahrzeuge blieben unsichtbar.
  storyAufbau(this);
 }
 blocked(p,r=.4){return p.x<bounds.left+r||p.x>bounds.right-r||p.z<bounds.top+r||p.z>bounds.bottom-r||(this.solids||[]).some(b=>intersects(p,b,r));}
 ground(p){return groundAt(p.x,p.z);}
 crime(severity=1){super.crime(severity);for(const n of this.npcs)if(n.report&&!n.report.description)n.report.description={clothes:this.player.clothes,plate:this.player.car?.id||null};}
 report(severity,pos=this.player,incident=null){
  const vorher=this.stars;super.report(severity,pos,incident);
  if(pos.description)this.description={...pos.description};
  if(this.stars>vorher)this.post('@pm_funkverkehr',
   'Fahndungsstufe '+this.stars+'. Einheiten Richtung '+Math.round(pos.x)+' / '+Math.round(pos.z)+'.');
 }
 switchCharacter(){if(this.stars||this.activity||this.unlock||this.player.y>2||this.player.car&&Math.abs(this.player.car.speed)>1){this.notify('Wechsel erst ohne Fahndung, Aktivität und im Stillstand.');return false;}this.saveWeapon();this.player.cover=false;this.active=1-this.active;this.player=this.characters[this.active];this.loadWeapon();this.notify(this.player.name+' · '+(this.active?'leiser unterwegs, schneller an Sicherungen':'besseres Handling und Sprinten'));return true;}
 saveWeapon(){const p=this.player;p.inventory[p.weapon]={ammo:p.ammo,reserve:p.reserve};}
 loadWeapon(){const p=this.player;const w=p.inventory[p.weapon];p.ammo=w.ammo;p.reserve=w.reserve;}
 cycleWeapon(){if(this.player.car||this.reloadJob)return;this.saveWeapon();const list=Object.keys(this.player.inventory),i=list.indexOf(this.player.weapon);this.player.weapon=list[(i+1)%list.length];this.loadWeapon();this.player.armed=true;this.notify(weapons[this.player.weapon].name);}
 // Zugänge für game.js: die Aktlogik liegt in story.js, die Dialoge im UI.
 starteAkt(nr){starteAkt(this,nr);}
 beendeKampagne(welcher){return beendeKampagne(this,welcher);}
 choose(choice){super.choose(choice);if(choice==='leak')this.relationship=80;if(choice==='sell')this.relationship=20;}
 objective(){const storyPunkt=storyZiel(this);if(storyPunkt&&!this.activity)return storyPunkt;
  if(this.activity?.kind==='treasure')return schatzOrte[this.schatzIndex||0]||locations.schatz;
  if(this.activity?.kind==='race')return this.activity.points[this.activity.index]||locations.race;if(this.activity?.kind==='diving')return {x:178,z:190};if(this.campaign?.stage===1)return !this.campaign.relay?locations.tower:locations.records;if(this.campaign?.stage===2)return this.campaign.witness?locations.aircargo:locations.ferry;if(this.campaign?.stage===3)return locations.home;return super.objective();}
 missionTitle(){if(this.activity)return this.activity.label;const storyText=storyTitel(this);if(storyText)return storyText;if(this.campaign.stage===1)return this.campaign.relay?'Hole die Ratsakte aus dem Archiv':'Mara: Relais abschalten';if(this.campaign.stage===2)return this.campaign.witness?'Bring die Zeugin zum Flughafen':'Finde die Zeugin auf Isla Serena';if(this.campaign.stage===3)return 'Zurück zur Wohnung — entscheide';if(this.campaign.stage===4)return 'Kampagne abgeschlossen';return ['Sprich mit Mara am Pier','Betritt das Caldera-Lager','Sichere die Festplatte','Bring die Beweise zu Mara','Ein zweiter Name in den Akten'][this.mission];}
 action(){const p=this.player;if(this.activity){
  if(this.activity.kind==='treasure'){
   const ziel=schatzOrte[this.schatzIndex||0];
   if(ziel&&distance(p,ziel)<5){
    this.schatzIndex=(this.schatzIndex||0)+1;
    const lohn=180+this.schatzIndex*60;this.award(lohn);
    this.notify('Fundstelle geborgen. $'+lohn+'.');
    if(this.schatzIndex>=schatzOrte.length){this.activity=null;this.award(900);
     this.notify('Alle sechs geborgen. Prämie $900.');
     this.post('@tideline_lokal','Jemand hat die alten Bergungsmarken abgeräumt. Alle sechs.');}
    else this.activity.label='BERGUNG · Fundstelle '+(this.schatzIndex+1)+' von '+schatzOrte.length;
   }else this.notify('Folge dem goldenen Marker.');
   return null;
  }
  if(this.activity.kind==='diving'){if(distance(p,{x:178,z:190})<5&&p.y<-1.5){this.award(220);this.activity=null;this.notify('Wrackfund gesichert. $220.');}else this.notify('Schwimme zum Marker und halte C zum Tauchen.');}else this.activityTap();return null;}const storySchluessel=storyAktion(this);if(storySchluessel)return storySchluessel;if(!p.car){if(this.campaign.stage===1&&distance(p,locations.tower)<5){if(this.active!==1){this.notify('Mara kennt das Relais. Wechsle mit Tab / Figuren.');return null;}this.campaign.relay=true;this.notify('Mara: Signal aus. Eli kann jetzt ins Archiv.');return null;}if(this.campaign.stage===1&&distance(p,locations.records)<5){if(!this.campaign.relay){this.notify('Zuerst muss Mara das Relais abschalten.');return null;}if(this.active!==0){this.notify('Eli besitzt die Zugangskarte. Wechsle die Figur.');return null;}this.campaign.archive=true;this.campaign.stage=2;this.award(400);this.notify('Die Akte nennt eine Zeugin auf Isla Serena.');return null;}if(this.campaign.stage===2&&!this.campaign.witness&&distance(p,locations.ferry)<5){this.campaign.witness=true;this.notify('Nadia folgt dir. Besorge ein Auto und bring sie zur Luftfracht.');return null;}if(this.campaign.stage===2&&this.campaign.witness&&distance(p,locations.aircargo)<6){if(this.stars){this.notify('Nadia steigt erst aus, wenn du die Fahndung verloren hast.');return null;}this.campaign.stage=3;this.award(700);this.notify('Nadia ist sicher. Entscheide zu Hause über die vollständige Akte.');return null;}if(this.campaign.stage===3&&distance(p,locations.home)<5)return 'finale';if(this.mission===4&&this.campaign.stage===0&&distance(p,places.safe)<5)return 'chapter2';}
  const near=Object.entries(locations).find(([id,l])=>distance(p,l)<(p.car?9:4.5)&&(!p.car||['garage','fuel'].includes(id)));if(near)return 'place:'+near[0];
  return super.action();
 }
 enterExit(){const p=this.player;if(p.car){const c=p.car,def=vehicleTypes[c.model];if(def.medium==='air'&&c.alt>5){p.car=null;p.y=c.alt;p.vy=-2;p.parachute=false;p.x=c.x+3;p.z=c.z;this.notify('Freier Fall — Leertaste / Sprung öffnet den Fallschirm.');return;}if(Math.abs(c.speed)>3){this.notify('Zuerst abbremsen.');return;}for(const side of [1,-1]){const v={x:c.x+Math.cos(c.yaw)*3.2*side,z:c.z-Math.sin(c.yaw)*3.2*side};if(!this.blocked(v,.4)){p.x=v.x;p.z=v.z;p.car=null;p.y=waterAt(p.x,p.z)?-.5:0;return;}}this.notify('Tür blockiert.');return;}const c=this.cars.find(c=>distance(c,p)<5&&c.health>0);if(!c)return;const def=vehicleTypes[c.model];if(c.owner===p.id||c.unlocked||def.security===0){this.board(c);return;}if(!this.unlock){this.unlock={id:c.id,remaining:def.security*(this.active===1?.7:1),total:def.security};this.notify('E / Aktion halten: Fahrzeug öffnen. Bewegung bricht ab.');}}
 board(c){if(this.characters.some(p=>p!==this.player&&p.car===c)){this.notify('Die andere Figur sitzt in diesem Fahrzeug.');return;}this.player.car=c;this.player.armed=false;this.player.cover=false;this.player.y=0;c.speed=0;if(c.type==='traffic'||!c.owner&&vehicleTypes[c.model].security>0){c.type='stolen';this.crime(2);}this.player.x=c.x;this.player.z=c.z;this.notify(vehicleTypes[c.model].name+' · '+(vehicleTypes[c.model].medium==='air'?'W Gas · Sprung steigen · C sinken':'W/S Gas · Leertaste bremsen'));}
 driveVehicle(dt,input){this.bremst=!!input.brake;const p=this.player,c=p.car,d=vehicleTypes[c.model],wet=this.weather==='rain'||this.weather==='storm',upgrade=1+(c.upgrades.engine||0)*.14;const f=c.health>0&&c.fuel>0?(input.forward||0):0;c.speed+=f*d.accel*upgrade*dt;c.speed*=Math.exp(-dt*(input.brake&&d.medium!=='air'?d.brake/5:!f?.65:.04));c.speed=clamp(c.speed,-Math.min(10,d.max/3),d.max*upgrade*Math.max(.2,c.health/100));const tireGrip=Math.max(.45,c.tires/100);c.yaw-=(input.turn||0)*dt*d.turn*clamp(c.speed/6,-1,1)*(wet?.72:1)*tireGrip*d.grip*(1+(c.upgrades.tires||0)*.03)*(input.brake?1.45:1)*(this.active===0?1.08:1);
  c.fuel=Math.max(0,c.fuel-dt*(.012+Math.abs(c.speed)*.002));let alt=c.alt||0;
  if(d.medium==='air'){if(d.shape==='helicopter'||Math.abs(c.speed)>22)alt+=((input.jump?1:0)-(input.sneak?1:0))*dt*12;if(c.fuel<=0||c.health<=0)alt-=dt*12;if(d.shape==='plane'&&Math.abs(c.speed)<19&&alt>0)alt-=dt*8;c.alt=clamp(alt,0,170);}
  // Querbewegung. Bisher fuhr jedes Fahrzeug exakt dorthin, wohin es zeigte:
  // kein Untersteuern, kein Ausbrechen, keine Wirkung der Handbremse außer
  // Bremsen. Der Schlupf baut sich mit der Fliehkraft auf und klingt mit dem
  // Grip wieder ab.
  const griff=tireGrip*d.grip*(wet?.66:1)*(input.brake?.45:1)
   *(wet&&Math.abs(c.speed)>d.max*.62?.55:1);   // Aquaplaning bei hohem Tempo
  const fliehkraft=Math.abs(c.speed)*(input.turn||0)*d.turn*.085*Math.sign(c.speed||1);
  c.slip=(c.slip||0)+((fliehkraft/Math.max(.35,griff))-(c.slip||0))*Math.min(1,dt*5);
  c.slip=clamp(c.slip,-7,7);
  if(d.medium==='air')c.slip=0;
  const quer=Math.cos(c.yaw)*c.slip*dt,querZ=-Math.sin(c.yaw)*c.slip*dt;
  const dx=Math.sin(c.yaw)*c.speed*dt+quer,dz=Math.cos(c.yaw)*c.speed*dt+querZ,next={x:c.x+dx,z:c.z+dz};let hit=false;
  if(d.medium==='water'){if(waterAt(next.x,next.z)&&!this.blocked(next,.8)){c.x=next.x;c.z=next.z;}else hit=true;}
  else if(d.medium==='air'&&c.alt>2){if(this.blockedAir(next,c.alt)){hit=true;}else{c.x=next.x;c.z=next.z;}}
  else{if(waterAt(next.x,next.z)){hit=true;c.health-=dt*3;}else hit=this.move(c,dx,dz,['bike','quad'].includes(d.shape)?.65:d.shape==='truck'||d.shape==='bus'?1.7:1.15);}
  if(Math.abs(c.slip||0)>2.2)c.tires=Math.max(20,c.tires-dt*Math.abs(c.slip)*.5);
  if(hit&&Math.abs(c.speed)>1){const impact=Math.abs(c.speed);c.health=clamp(c.health-impact*.65,0,100);c.glass=Math.max(0,c.glass-impact*2);c.lights=Math.max(0,c.lights-impact);c.tires=Math.max(0,c.tires-impact*.15);c.speed*=-.15;this.collisions++;}
  for(const other of this.cars){if(other===c||distance(other,c)>3.6||(c.alt||0)>3||(other.alt||0)>3)continue;if(Math.abs(c.speed)>4){
   // Der Transport aus Akt 3 ist das Ziel des Auftrags: er nimmt mehr Schaden
   // als ein Zivilfahrzeug, und das Rammen gilt nicht als Straftat.
   if(other.type==='konvoi'){konvoiRammen(this,Math.abs(c.speed));c.health=Math.max(0,c.health-4);c.speed*=-.25;continue;}
   other.wait=5;other.health=Math.max(0,other.health-6);c.health=Math.max(0,c.health-3);c.speed*=-.2;this.crime(1);}}
  for(const n of this.npcs){if(n.health>0&&c.alt<2&&distance(c,n)<1.6&&Math.abs(c.speed)>5){n.health=0;n.state='verletzt';c.speed*=.6;this.crime(3);}}
  p.x=c.x;p.z=c.z;p.yaw=c.yaw;p.y=c.alt;
 }
 blockedAir(p,alt){return p.x<bounds.left||p.x>bounds.right||p.z<bounds.top||p.z>bounds.bottom||this.solids.some(b=>intersects(p,b,1.2)&&groundAt(b.x,b.z)+b.h>alt);}
 shoot(){const p=this.player,w=weapons[p.weapon];if(!p.armed||p.cooldown>0||this.reloadJob||p.car)return;if(p.ammo<=0){this.notify('Leer. R / Nachladen.');return;}p.ammo--;p.cooldown=w.delay;this.shots++;let hit=null,nearest=w.range;const dir={x:Math.sin(p.yaw),z:Math.cos(p.yaw)};for(const n of [...this.npcs,...this.cops.filter(c=>c.active)]){const d=distance(p,n);if(n.health<=0||d>nearest||d<.01)continue;const dot=((n.x-p.x)*dir.x+(n.z-p.z)*dir.z)/d;if(dot>w.cone&&lineClear(p,n,this.solids)){nearest=d;hit=n;}}let end={x:p.x+dir.x*w.range,z:p.z+dir.z*w.range};if(hit){if(p.weapon==='taser')hit.stun=12;else hit.health=Math.max(0,hit.health-w.damage*(p.weapon==='shotgun'?Math.max(.3,1-nearest/35):1));hit.state=hit.health<=0?'verletzt':'flüchtend';hit.timer=12;end={x:hit.x,z:hit.z};}else{for(let d=1;d<w.range;d+=.5){const v={x:p.x+dir.x*d,z:p.z+dir.z*d};if(this.solids.some(b=>intersects(v,b))){end=v;break;}}}this.tracers.push({x:p.x,z:p.z,end,life:.12});this.crime(hit?2:1);this.saveWeapon();}
 reload(){const p=this.player,w=weapons[p.weapon];if(this.reloadJob||p.ammo>=w.capacity||!p.reserve)return;this.reloadJob={remaining:w.reload};p.cooldown=w.reload;this.notify('Nachladen …');}
 melee(){const p=this.player;if(p.car||p.cooldown>0)return;const target=this.npcs.filter(n=>n.health>0&&distance(n,p)<2.6&&lineClear(p,n,this.solids)).sort((a,b)=>distance(a,p)-distance(b,p))[0];p.cooldown=.7;this.meleeTime=.4;if(!target)return;const facing=(Math.sin(target.yaw)*(p.x-target.x)+Math.cos(target.yaw)*(p.z-target.z))/Math.max(.1,distance(p,target));if(p.sneak&&facing<-.2){target.stun=30;this.notify('Leiser Takedown.');}else{target.health=Math.max(0,target.health-25);target.stun=1;target.state='aggressiv';this.crime(1);}}
 grapple(){const n=this.npcs.find(n=>n.health>0&&distance(n,this.player)<2&&lineClear(n,this.player,this.solids));if(!n||this.player.cooldown>0)return;n.stun=4;this.player.cooldown=2;this.meleeTime=.8;this.crime(1);this.notify('Gegner kurz festgesetzt.');}
 cover(){if(this.player.car)return;this.player.cover=!this.player.cover&&this.solids.some(b=>distance(this.player,b)<Math.hypot(b.w,b.d)/2+1.5);this.notify(this.player.cover?'In Deckung. Bewegung verlässt die Deckung.':'Keine Deckung / Deckung verlassen.');}
 jump(){const p=this.player;if(p.car)return;if(p.y>4){p.parachute=true;this.notify('Fallschirm geöffnet. Steuere mit WASD / Stick.');}else if(p.y>=0&&p.y<.2){p.vy=6.5;}}
 dodge(){const p=this.player;if(p.stamina<20||p.car)return;p.stamina-=20;this.dodgeTime=.45;this.move(p,-Math.cos(p.yaw)*2.5,Math.sin(p.yaw)*2.5);}
 award(n){this.player.money+=n;this.moneyEarned+=n;this.buchung('Eingang',n);}
 // Eigentum. Der Ertrag fällt einmal je Spieltag an, unabhängig davon, wo
 // sich die Figur gerade aufhält.
 kaufeImmobilie(id){
  const o=immobilien[id];if(!o)return false;
  if(this.besitz[id]){this.notify('Gehört dir bereits.');return false;}
  if(this.player.money<o.preis){this.notify('Du brauchst $'+o.preis.toLocaleString('de-DE')+'.');return false;}
  this.player.money-=o.preis;this.buchung('Kauf '+o.name,-o.preis);
  this.besitz[id]={seit:this.time,gekauftVon:this.player.id};
  if(id==='motel')this.motelOwned=true;
  this.notify(o.name+' gehört jetzt dir. Ertrag $'+o.ertrag+' pro Tag.');
  this.post('@tideline_lokal','Neuer Eigentümer für '+o.name+'. Niemand kennt den Namen.');
  return true;
 }
 ertraege(){return Object.keys(this.besitz).reduce((s,id)=>s+(immobilien[id]?.ertrag||0),0);}
 zahltag(){
  const tag=Math.floor(this.time/1440*60);   // ein Spieltag sind 1920 s Echtzeit
  if(tag<=this.letzterZahltag)return;
  this.letzterZahltag=tag;
  const summe=this.ertraege();if(!summe)return;
  this.player.money+=summe;this.moneyEarned+=summe;
  this.buchung('Mieten und Anteile',summe);
  this.notify('Tageseinnahmen aus Eigentum: $'+summe.toLocaleString('de-DE'));
 }
 buy(item){const p=this.player,l=this.serviceLocation;if(!l||distance(p,locations[l])>10)return false;let price=0,apply=()=>{};
  if(item.startsWith('weapon:')){const id=item.split(':')[1];if(!weapons[id]||p.inventory[id])return false;price=weapons[id].price;apply=()=>p.inventory[id]={ammo:weapons[id].capacity,reserve:weapons[id].capacity*4};}
  else if(item==='ammo'){price=60;apply=()=>{p.reserve+=weapons[p.weapon].capacity*4;this.saveWeapon();};}
  else if(item==='clothes'){price=80;apply=()=>p.clothes=p.clothes==='orange'?'blue':p.clothes==='blue'?'green':'orange';}
  else if(item==='hair'){price=35;apply=()=>p.hair=(p.hair+1)%3;}
  else if(item==='tattoo'){price=90;apply=()=>p.tattoo=!p.tattoo;}
  else if(item==='heal'){price=50;apply=()=>p.health=100;}
  else if(item==='food'){price=18;apply=()=>{p.health=Math.min(100,p.health+25);p.stamina=100;};}
  else if(item==='motel'){if(this.motelOwned)return false;price=900;apply=()=>this.motelOwned=true;}
  else if(item==='rest'){if(this.stars){this.notify('Während einer Fahndung kein Ausruhen.');return false;}price=l==='motel'&&!this.motelOwned?60:0;apply=()=>{p.health=100;p.stamina=100;this.hour=(this.hour+6)%24;};}
  else if(item==='fuel'){const c=p.car||this.cars.find(c=>distance(c,p)<9);if(!c)return false;price=35;apply=()=>c.fuel=100;}
  else if(item.startsWith('car:')){const c=p.car||this.cars.find(c=>distance(c,p)<12);if(!c){this.notify('Bring ein Fahrzeug in die Werkstatt.');return false;}const id=item.split(':')[1];price=id==='repair'?150:id==='paint'?120:id==='engine'?400:100;
   // Ein Anteil an Pike Customs drückt den Werkstattpreis.
   if(this.besitz.werkstatt)price=Math.round(price*.35);if(id==='engine'&&(c.upgrades.engine||0)>=3)return false;apply=()=>{if(id==='repair'){c.health=100;c.tires=100;c.glass=100;c.lights=100;}else if(id==='paint')c.color=[0x548d88,0x9b546b,0xdfb35f,0x324a6b][((c.upgrades.paint||0)+1)%4];if(id==='tires')c.tires=100;c.upgrades[id]=(c.upgrades[id]||0)+1;};}
  else return false;if(p.money<price){this.notify('Nicht genug Geld.');return false;}p.money-=price;apply();
  if(price)this.buchung(locations[l]?.name||'Ausgabe',-price);
  this.notify('Erledigt · $'+price);return true;
 }
 startActivity(kind){if(this.stars){this.notify('Zuerst die Fahndung verlieren.');return;}
  // Alle Rennen laufen über dieselbe Mechanik; sie unterscheiden sich in
  // Kurs, verlangtem Fahrzeug und Preisgeld.
  if(kind==='race'||kind.startsWith('race:')){
   const id=kind.includes(':')?kind.split(':')[1]:'west',k=rennen[id];
   if(!k){this.notify('Diese Strecke gibt es nicht.');return;}
   const c=this.player.car;
   if(!c){this.notify(k.name+': Du brauchst ein Fahrzeug.');return;}
   const d=vehicleTypes[c.model];
   const medium=d.medium==='water'?'water':d.medium==='air'?'air':'land';
   if(medium!==k.medium){this.notify(k.name+': '+(k.medium==='water'?'Boot oder Jetski nötig.':'Landfahrzeug nötig.'));return;}
   if(k.form&&d.shape!==k.form){this.notify(k.name+': nur mit dem Motorrad.');return;}
   this.activity={kind:'race',kurs:id,label:k.name+' · Kontrollpunkte',time:0,index:0,points:k.punkte};
   this.notify(k.name+': '+k.punkte.length+' Kontrollpunkte, Richtzeit '+k.ziel+' s.');
   return;
  }
  // Bergungsauftrag: sechs Fundstellen, eine nach der anderen.
  if(kind==='treasure'){
   this.schatzIndex=this.schatzIndex||0;
   if(this.schatzIndex>=schatzOrte.length){this.notify('Alle Fundstellen sind geborgen.');return;}
   this.activity={kind,label:'BERGUNG · Fundstelle '+(this.schatzIndex+1)+' von '+schatzOrte.length,time:0};
   this.notify('Marker gesetzt. E an der Fundstelle.');
   return;
  }
  if(kind==='diving'){this.activity={kind,label:'TAUCHGANG · Wrackfund',time:0};return;}
  if(kind==='range'&&!this.player.armed){this.notify('Waffe ziehen: Q.');return;}
  if(kind==='skydive'){this.notify('Nimm den Hubschrauber oder das Flugzeug. Steige über 40 m, E zum Absprung und Leertaste für den Schirm.');return;}
  this.activity={kind,label:{basketball:'BASKETBALL · Triff das Wurffenster',gym:'TRAINING · Halte den Rhythmus',fishing:'ANGELN · Warte auf den Biss',club:'UNDERTOW · Folge dem Beat',darts:'DARTS · Triff das schmale Feld',pool:'BILLARD · Stoß im richtigen Moment',range:'SCHIESSSTAND · Fünf Scheiben'}[kind]||'AKTIVITÄT',time:0,round:0,score:0,phase:0,biteAt:2+this.rng()*4,result:''};
 }
 activityTap(){const a=this.activity;if(!a)return;if(a.kind==='race'){this.notify('Fahre durch den goldenen Kontrollpunkt.');return;}if(a.kind==='fishing'){if(a.time>=a.biteAt&&a.time<a.biteAt+1){this.player.fish++;this.award(45);this.notify('Gefangen! $45.');}else this.notify('Kein Fang. Beim Biss reagieren.');this.activity=null;return;}if(['gym','basketball','club','darts','pool','range'].includes(a.kind)){
   const fenster={basketball:.13,gym:.17,club:.17,darts:.075,pool:.11,range:.09}[a.kind];
   const hit=Math.abs(a.phase-.5)<fenster;a.round++;if(hit)a.score++;a.result=hit?'Treffer':'Daneben';a.time+=.31;if(a.round>=5){const score=a.score;if(a.kind==='gym'){this.player.fitness=Math.min(10,this.player.fitness+score);this.player.stamina=100;}
    else this.award(score*{basketball:30,club:15,darts:45,pool:55,range:60}[a.kind]||15);this.highScores[a.kind]=Math.max(this.highScores[a.kind]||0,score);this.notify(a.label.split(' · ')[0]+': '+score+'/5 erfolgreich.');this.activity=null;}}}
 cancelActivity(){this.activity=null;this.notify('Aktivität beendet.');}
 tick(dt,input={}){if(this.paused)return;const p=this.player;dt=Math.min(.05,dt);this.tickCount++;if(this.unlock){const c=this.cars.find(c=>c.id===this.unlock.id);if(!input.interact||!c||distance(c,p)>5||input.forward||input.turn){this.unlock=null;}else{this.unlock.remaining-=dt;if(this.unlock.remaining<=0){c.unlocked=true;this.unlock=null;this.board(c);}}}
  if(this.reloadJob){this.reloadJob.remaining-=dt;if(this.reloadJob.remaining<=0){const w=weapons[p.weapon],n=Math.min(w.capacity-p.ammo,p.reserve);p.ammo+=n;p.reserve-=n;this.reloadJob=null;this.saveWeapon();}}
  this.dodgeTime=Math.max(0,this.dodgeTime-dt);this.meleeTime=Math.max(0,this.meleeTime-dt);
  if(input.forward||input.turn)p.cover=false;if(input.sprint&&!p.car){p.stamina=Math.max(0,p.stamina-dt*12/(1+p.fitness*.04));}else p.stamina=Math.min(100,p.stamina+dt*9);
  const oldWeatherTimer=this.weatherTimer;const all=this.npcs;const stunned=new Map();for(const n of [...all,...this.cops]){n.stun=Math.max(0,(n.stun||0)-dt);if(n.stun>0){stunned.set(n,n.health);n.health=0;}}
  // Distant civilians receive coarse updates; pending witness calls stay active.
  this.npcs=all.filter(n=>distance(n,p)<180||n.report||this.tickCount%12===0);
  super.tick(dt,{...input,sprint:input.sprint&&p.stamina>0,sneak:input.sneak||p.cover});this.npcs=all;for(const [n,h] of stunned)n.health=h;
  if(oldWeatherTimer<=dt){this.weatherIndex=(this.weatherIndex+1)%4;this.weather=['clear','rain','fog','storm'][this.weatherIndex];this.notify('Wetterwechsel: '+this.weather);}
  if(!p.car){if(waterAt(p.x,p.z)&&p.y<=0){p.y=input.sneak?Math.max(-3.5,p.y-dt*1.5):Math.min(-.5,p.y+dt*2);p.air=clamp(p.air+(p.y<-1.5?-dt*10:dt*25),0,100);if(!p.air)p.health=Math.max(0,p.health-dt*8);}else{p.vy-=dt*(p.parachute?2:16);p.vy=Math.max(p.parachute?-3:-35,p.vy);p.y+=p.vy*dt;if(p.y<=0){if(p.vy<-13)p.health=Math.max(0,p.health-(-p.vy-13)*3);p.y=0;p.vy=0;if(p.parachute){this.award(60);this.notify('Sicher gelandet. $60.');}p.parachute=false;}}}
  if(this.activity){const a=this.activity;a.time+=dt;a.phase=(Math.sin(a.time*(a.kind==='club'?5:a.kind==='gym'?3:2.5))+1)/2;if(a.kind==='race'&&distance(p,a.points[a.index])<10){a.index++;if(a.index===a.points.length){
    const k=rennen[a.kurs||'west'],schluessel='race:'+(a.kurs||'west');
    this.highScores[schluessel]=Math.min(this.highScores[schluessel]||99999,a.time);
    const preis=a.time<k.ziel?k.preis:Math.round(k.preis*.45);
    this.award(preis);
    this.notify(k.name+' beendet: '+a.time.toFixed(1)+' s · $'+preis);
    this.post('@tideline_lokal',k.name+': neue Zeit '+a.time.toFixed(1)+' Sekunden.');
    this.activity=null;}}if(a.kind==='fishing'&&a.time>a.biteAt+1){this.notify('Der Fisch ist entkommen.');this.activity=null;}}
  this.zahltag();storyTick(this,dt);this.updateRoutines(dt);this.updateGuards(dt);this.updateEvents(dt);if(this.campaign.witness&&this.campaign.stage===2){if(!this.witness)this.witness={x:p.x-2,z:p.z-2};const d=distance(this.witness,p);if(p.car){this.witness.x=p.x;this.witness.z=p.z;}else if(d>2){this.witness.x+=(p.x-this.witness.x)/d*dt*5;this.witness.z+=(p.z-this.witness.z)/d*dt*5;}}
 }
 updateRoutines(dt){if(this.tickCount%30)return;for(const n of this.npcs){if(n.guard||n.report||n.health<=0||n.state!=='normal')continue;const mode=this.hour>=8&&this.hour<17?'Arbeit':this.hour>=20||this.hour<6?'Zuhause':'Freizeit';if(n.schedule!==mode){n.schedule=mode;const goal=mode==='Zuhause'?n.home:n.work;n.path=mode==='Freizeit'?n.originalPath.map(p=>({...p})):[...findPath(n,goal,p=>this.blocked(p,.3),2,2500),goal];n.target=0;}n.pace=this.weather==='storm'?2:1.1+(n.id%5)*.13;}}
 updateGuards(dt){for(const n of this.npcs.filter(n=>n.guard&&!n.aktWache)){if(n.health<=0||n.stun>0)continue;n.shot=(n.shot||0)-dt;const p=this.player;const suspicious=this.campaign.stage===1&&!this.campaign.relay||p.armed||this.stars;const sees=distance(n,p)<25&&lineClear(n,p,this.solids);if(suspicious&&sees&&n.shot<=0){n.shot=2.5;if(!this.campaign.relay){this.report(1);this.notify('Archivwache hat dich erkannt.');}if(this.stars>=2&&this.dodgeTime===0)p.health-=p.cover?2:7;}}}
 updateEvents(dt){for(const n of this.npcs){if(n.state==='tanzend'&&this.time>n.danceUntil)n.state='normal';if(n.state==='aggressiv'&&n.health>0&&n.stun<=0){const target=this.npcs.find(v=>v!==n&&v.health>0&&distance(v,n)<8);if(target){const d=distance(n,target);if(d>1.5)this.move(n,(target.x-n.x)/d*dt*2,(target.z-n.z)/d*dt*2,.3);else{target.health=Math.max(0,target.health-dt*4);target.state='flüchtend';target.timer=4;}}if(this.time>n.aggressiveUntil)n.state='normal';}}this.nextEvent-=dt;if(this.currentEvent){this.currentEvent.ttl-=dt;if(this.currentEvent.ttl<=0)this.currentEvent=null;}if(this.nextEvent>0)return;this.nextEvent=50;const kinds=['Panne','Streit','Straßenrennen','Überfall','Party'];const kind=kinds[Math.floor(this.time/50)%kinds.length];const n=this.npcs.find(n=>!n.guard&&n.health>0&&distance(n,this.player)<60);this.currentEvent={kind,x:n?.x||-160,z:n?.z||80,ttl:25,npcId:n?.id};if(kind==='Streit'||kind==='Überfall'){if(n){n.state='aggressiv';n.aggressiveUntil=this.time+15;}}if(kind==='Straßenrennen'){const c=this.cars.find(c=>c.type==='traffic');if(c)c.speed=22;}if(kind==='Party'&&n){n.state='tanzend';n.danceUntil=this.time+20;}if(kind==='Panne'){const c=this.cars.find(c=>c.type==='traffic');if(c)c.wait=20;}this.notify('In der Nähe: '+kind);
  this.post('@tideline_lokal',{Panne:'Liegengebliebener Wagen blockiert eine Spur.',
   'Streit':'Streit auf offener Straße. Bitte Abstand halten.',
   'Straßenrennen':'Schon wieder Rennen auf der Harbor Avenue. Jede Nacht dasselbe.',
   'Überfall':'Überfall gemeldet. Bereich weiträumig meiden.',
   'Party':'Irgendwo läuft eine Party und niemand weiß, wo genau.'}[kind]||('Vorfall: '+kind));}
 updatePolice(dt){if(!this.campaign){super.updatePolice(dt);return;}const p=this.player;this.spotted=false;const nowWanted=this.stars>0;
  for(const camera of this.cameras){if(!nowWanted||this.time<(camera.next||0))continue;const d=distance(p,camera),dot=(Math.sin(camera.yaw)*(p.x-camera.x)+Math.cos(camera.yaw)*(p.z-camera.z))/Math.max(1,d);if(d<camera.range&&dot>.2&&lineClear(camera,p,this.solids)&&p.y<5){camera.next=this.time+5;this.lastSeen={x:p.x,z:p.z};this.spotted=true;}}
  this.dispatchTimer-=dt;const desired=Math.min(12,this.stars*2);if(nowWanted&&this.dispatchTimer<=0){const n=this.cops.filter(c=>c.active&&c.health>0).length;if(n<desired){const c=this.cops.find(c=>!c.active&&c.health>0);if(c){c.active=true;c.repath=0;this.dispatchTimer=2.5;}}}
  for(const c of this.cops){if(c.health<=0||c.stun>0)continue;if(!nowWanted&&!c.active&&distance(c,c.base)<2)continue;const d=distance(c,p),known=p.car?this.description?.plate===p.car.id:this.description?.clothes===p.clothes;const sees=nowWanted&&p.y<12&&d<(p.sneak||this.active===1?26:52)&&lineClear(c,p,this.solids)&&(known||d<10||p.armed);if(sees){this.spotted=true;this.lastSeen={x:p.x,z:p.z};this.description={clothes:p.clothes,plate:p.car?.id||null};}
   if(!nowWanted&&c.active){c.active=false;c.repath=0;}c.repath-=dt;if(c.repath<=0){let target=nowWanted&&c.active?(sees?p:this.lastSeen):c.base;if(!target)continue;if(nowWanted&&c.id===2&&this.stars>=3){if(!c.blockTarget)c.blockTarget=[{x:-100,z:80},{x:-40,z:-100},{x:-280,z:80},{x:-100,z:200}].filter(v=>distance(v,p)>30).sort((a,b)=>distance(a,p)-distance(b,p))[0];target=c.blockTarget;}else if(nowWanted&&c.id%3===2&&this.stars>=3)target={x:target.x+Math.sin(p.yaw)*16,z:target.z+Math.cos(p.yaw)*16};c.route=findPath(c,target,v=>this.blocked(v,1.15)||waterAt(v.x,v.z));c.target=0;c.repath=sees?2.5:6;}
   const target=c.route[c.target];if(target&&!(sees&&d<8)){const td=distance(c,target);if(td<1.1)c.target++;else{c.yaw=Math.atan2(target.x-c.x,target.z-c.z);const speed=nowWanted?10+this.stars*1.4:8;this.move(c,Math.sin(c.yaw)*Math.min(td,speed*dt),Math.cos(c.yaw)*Math.min(td,speed*dt),1.15);}}
   if(nowWanted&&c.blockTarget&&distance(c,c.blockTarget)<4&&!c.blocking){c.blocking=true;const b=this.addSolid(c.x+4,c.z,5,1.2,'barrier',1);this.barriers.push(b);}if(!nowWanted){c.blockTarget=null;c.blocking=false;}c.shot-=dt;if(sees&&d<28&&c.shot<=0){c.shot=c.role==='tactical'?1:1.8;if(this.stars>=2&&this.dodgeTime<=0){p.health-=p.cover?1:p.car?2:c.role==='tactical'?8:5;this.tracers.push({x:c.x,z:c.z,end:{x:p.x,z:p.z},life:.1});}else if(d<4&&this.dodgeTime<=0)p.health-=5;}
  }
  if(!nowWanted&&this.barriers.length){this.solids=this.solids.filter(b=>!this.barriers.includes(b));this.barriers=[];}const heli=this.policeHeli;if(heli){const target=this.stars>=5?(this.lastSeen||p):{x:-360,z:305};const d=distance(heli,target);heli.alt=Math.min(45,heli.alt+dt*8);if(d>4){heli.yaw=Math.atan2(target.x-heli.x,target.z-heli.z);heli.x+=Math.sin(heli.yaw)*dt*30;heli.z+=Math.cos(heli.yaw)*dt*30;}else if(this.stars<5)heli.alt=Math.max(0,heli.alt-dt*16);if(this.stars>=5&&d<45&&p.y>=0&&lineClear(heli,p,this.solids)){this.spotted=true;this.lastSeen={x:p.x,z:p.z};}}if(nowWanted){if(this.spotted)this.unseen=0;else this.unseen+=dt;if(this.unseen>20+this.stars*4&&this.lastSeen&&distance(p,this.lastSeen)>35){this.stars=0;this.heat=0;this.description=null;this.lastSeen=null;this.notify('Fahndung beendet.');}}
 }
 snapshot(){this.saveWeapon();return {version:2,time:this.time,hour:this.hour,active:this.active,characters:this.characters.map(p=>({...p,car:null,carId:p.car?.id||null})),cars:this.cars,mission:this.mission,doorOpen:this.doorOpen,camera:this.camera,ending:this.ending,campaign:this.campaign,relationship:this.relationship,weather:this.weather,weatherIndex:this.weatherIndex,stars:this.stars,heat:this.heat,lastSeen:this.lastSeen,description:this.description,unseen:this.unseen,cops:this.cops,npcs:this.npcs,motelOwned:this.motelOwned,highScores:this.highScores,feed:this.feed,konto:this.konto,besitz:this.besitz,letzterZahltag:this.letzterZahltag,schatzIndex:this.schatzIndex||0};}
 restore(data){if(data?.version!==2||!Array.isArray(data.characters)||data.characters.length!==2||!Array.isArray(data.cars))throw new Error('Inkompatibler Spielstand');for(const p of data.characters)if(!Number.isFinite(p.x)||!Number.isFinite(p.z)||!p.inventory?.[p.weapon])throw new Error('Ungültiger Spielstand');for(const key of ['time','hour','active','characters','cars','mission','camera','ending','campaign','relationship','weather','weatherIndex','stars','heat','lastSeen','description','unseen','cops','npcs','motelOwned','highScores','feed','konto','besitz','letzterZahltag','schatzIndex'])if(data[key]!==undefined)this[key]=data[key];for(const p of this.characters){p.car=this.cars.find(c=>c.id===p.carId)||null;p.cover=false;}this.player=this.characters[this.active];storyReparieren(this);for(const c of this.cops){c.blocking=false;c.blockTarget=null;}if(data.doorOpen)this.openDoor();this.loadWeapon();this.paused=true;}
}
