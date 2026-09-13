// Deterministic gameplay simulation, independent of WebGL and the DOM.
import {intersections,ampelFrei} from './content.js';
export const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export const distance=(a,b)=>Math.hypot(a.x-b.x,a.z-b.z);
export const roads=[-100,-40,20,80];
export const places={mara:{x:-27,z:73},door:{x:-77,z:-53},fuse:{x:-54,z:-81},disk:{x:-78,z:-82},safe:{x:-77,z:73},station:{x:80,z:-100}};
export function random(seed=41){return ()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};}
export function intersects(a,b,r=0){return a.x>b.x-b.w/2-r&&a.x<b.x+b.w/2+r&&a.z>b.z-b.d/2-r&&a.z<b.z+b.d/2+r;}
export function lineClear(a,b,solids){const d=distance(a,b),n=Math.max(1,Math.ceil(d/.65));for(let i=1;i<n;i++){const p={x:a.x+(b.x-a.x)*i/n,z:a.z+(b.z-a.z)*i/n};if(solids.some(s=>intersects(p,s)))return false;}return true;}
export function route(a,b){const nearest=v=>roads.reduce((p,c)=>Math.abs(c-v)<Math.abs(p-v)?c:p);const ax=nearest(a.x),az=nearest(a.z),bx=nearest(b.x),bz=nearest(b.z);const start=Math.abs(a.x-ax)<Math.abs(a.z-az)?{x:ax,z:a.z}:{x:a.x,z:az};return [start,{x:ax,z:az},{x:bx,z:az},{x:bx,z:bz},{x:b.x,z:bz},{x:b.x,z:b.z}].filter((p,i,arr)=>i===0||distance(p,arr[i-1])>.1);}
export class Simulation{
 constructor(){this.rng=random();this.time=0;this.hour=18.67;this.player={x:-30,z:78,yaw:Math.PI,health:100,money:450,armed:false,ammo:12,reserve:72,sneak:false,car:null,clothes:'orange',cooldown:0};this.solids=[];this.buildings=[];this.events=[];this.npcs=[];this.cars=[];this.cops=[];this.tracers=[];this.heat=0;this.stars=0;this.lastSeen=null;this.unseen=0;this.spotted=false;this.description=null;this.mission=0;this.camera=true;this.doorOpen=false;this.ending=null;this.paused=true;this.weather='clear';this.weatherTimer=65;this.eventTimer=40;this.dispatchTimer=0;this.injured=0;this.shots=0;this.collisions=0;this.incident=0;this.reported=new Set();this.makeWorld();}
 notify(text){this.events.push(text);if(this.events.length>8)this.events.shift();}
 // TIDELINE: der Ticker der Stadt. Beiträge entstehen aus dem, was in der
 // Welt passiert — nicht aus einer Liste vorgeschriebener Meldungen.
 post(autor,text){
  (this.feed||=[]).unshift({autor,text,stunde:this.hour});
  if(this.feed.length>40)this.feed.pop();
 }
 // Kontobewegungen für die Bank-App.
 buchung(text,betrag){
  (this.konto||=[]).unshift({text,betrag,stunde:this.hour});
  if(this.konto.length>30)this.konto.pop();
 }
 addSolid(x,z,w,d,kind='building',h=8){const b={x,z,w,d,kind,h};this.solids.push(b);return b;}
 makeWorld(){
  for(let ix=0;ix<3;ix++)for(let iz=0;iz<3;iz++){const x=roads[ix]+30,z=roads[iz]+30;if(ix===0&&iz===0)continue;for(let j=0;j<2;j++){const b=this.addSolid(x+(j?11:-11),z,18,38,'building',9+Math.floor(this.rng()*32));this.buildings.push(b);}}
  // Warehouse: solid walls with a real 8 m front opening.
  this.addSolid(-98,-74,1,38,'warehouse',7);this.addSolid(-56,-74,1,38,'warehouse',7);this.addSolid(-77,-93,43,1,'warehouse',7);this.addSolid(-90,-55,17,1,'warehouse',7);this.addSolid(-64,-55,17,1,'warehouse',7);this.gate=this.addSolid(-77,-55,8,1,'gate',5);
  this.addSolid(-87,-78,6,6,'crate',2.8);this.addSolid(-65,-85,7,5,'crate',2.4);this.addSolid(-67,-64,5,5,'crate',2.7);
  const loop=[{x:-31,z:90},{x:-31,z:29},{x:11,z:29},{x:11,z:90}];
  for(let i=0;i<18;i++){const block=i%3;const path=loop.map(p=>({x:p.x+(block===1?60:block===2?-60:0),z:p.z-(i%2?120:0)}));const p=path[i%4];this.npcs.push({id:i,x:p.x,z:p.z,yaw:0,state:'normal',timer:0,health:100,path,target:(i+1)%4,personality:['caller','filmer','coward'][i%3],pace:1.1+this.rng()*.8,report:null});}
  this.cars.push({id:'VOSS-07',x:-34,z:75,yaw:Math.PI,speed:0,health:100,type:'player',color:0x49a8a4});
  for(let i=0;i<8;i++){const x=i<4?-100:20,z=-100+(i%4)*48;this.cars.push({id:'PM-'+(400+i),x:x+3,z,yaw:0,speed:8+this.rng()*3,health:100,type:'traffic',color:[0xd9b078,0xcad0c5,0xa75547,0x3c637d][i%4],route:[{x:x+3,z:83},{x:x+63,z:83},{x:x+63,z:-103},{x:x+3,z:-103}],target:0,wait:0});}
  for(let i=0;i<6;i++)this.cops.push({id:i,x:83+i*3,z:-105,yaw:0,speed:0,active:false,route:[],target:0,repath:0,health:100,shot:0});
 }
 // Steht das Fahrzeug vor einer roten Ampel? Die Achse ergibt sich aus der
 // Fahrtrichtung; nur Kreuzungen voraus und in Spurbreite zählen.
 haeltVorAmpel(c){
  const achse=Math.abs(Math.sin(c.yaw))>Math.abs(Math.cos(c.yaw))?1:0;
  if(ampelFrei(this.time,achse))return false;
  const sin=Math.sin(c.yaw),cos=Math.cos(c.yaw);
  for(const k of intersections){
   const dx=k.x-c.x,dz=k.z-c.z;
   const voraus=dx*sin+dz*cos, seitlich=Math.abs(dx*cos-dz*sin);
   if(voraus>1.5&&voraus<15&&seitlich<9)return true;
  }
  return false;
 }
 // Abstand halten. Die Wagen sind einander bis hierher nicht ausgewichen und
 // sind ineinander gefahren, sobald mehrere an derselben Ampel standen. Bei
 // vierundvierzig Fahrzeugen auf der ganzen Karte fiel das kaum auf, bei
 // hundertsechzehn schon: gemessen fünf Paare mit weniger als 3,6 Metern
 // Abstand, bei einer Wagenlänge von 4,4 Metern also echte Durchdringung.
 //
 // Geprüft wird nur, was voraus und in der eigenen Spur liegt: bis sieben
 // Meter nach vorn, gut zwei Meter seitlich. Der Wagen des Spielers zählt
 // mit, sonst schöbe der Verkehr ihn von hinten an.
 wagenVoraus(c){
  const sin=Math.sin(c.yaw),cos=Math.cos(c.yaw);
  for(const o of this.cars){
   if(o===c||o.health<=0)continue;
   const dx=o.x-c.x,dz=o.z-c.z;
   if(Math.abs(dx)+Math.abs(dz)>9)continue;      // billige Vorabschätzung
   const laengs=dx*sin+dz*cos;
   if(laengs<.4||laengs>7)continue;
   if(Math.abs(dx*cos-dz*sin)>2.2)continue;
   return true;
  }
  return false;
 }
 blocked(p,r=.4){return p.x<-119+r||p.x>112-r||p.z<-119+r||p.z>113-r||this.solids.some(b=>intersects(p,b,r));}
 move(o,dx,dz,r=.4){let hit=false;const steps=Math.max(1,Math.ceil(Math.hypot(dx,dz)/.25));for(let i=0;i<steps;i++){if(!this.blocked({x:o.x+dx/steps,z:o.z},r))o.x+=dx/steps;else hit=true;if(!this.blocked({x:o.x,z:o.z+dz/steps},r))o.z+=dz/steps;else hit=true;}return hit;}
 openDoor(){this.doorOpen=true;this.solids=this.solids.filter(s=>s!==this.gate);}
 report(severity,pos=this.player,incident=null){if(incident!==null){if(this.reported.has(incident))return;this.reported.add(incident);}this.heat=clamp(this.heat+severity,0,12);this.stars=Math.ceil(this.heat/2);this.lastSeen={x:pos.x,z:pos.z};this.unseen=0;this.description={clothes:this.player.clothes,plate:this.player.car?.id||null};this.notify('Leitstelle: Meldung bestätigt. Einheiten unterwegs.');}
 crime(severity=1){const incident=++this.incident;let witnesses=0;for(const n of this.npcs){if(n.health<=0||distance(n,this.player)>42||!lineClear(n,this.player,this.solids))continue;n.report={severity,incident,x:this.player.x,z:this.player.z};n.timer=n.personality==='caller'?4:7;n.state=n.personality==='filmer'?'filmend':'erschrocken';witnesses++;
   if(n.personality==='filmer'&&this.post)this.post('@hafenblick_'+(n.id%90),
    ['Gerade eben am Hafen. Ich habe alles gefilmt.','Leute, hier läuft was komplett aus dem Ruder.',
     'Das war zu nah. Video kommt gleich.','Wer war das? Ich habe das Kennzeichen.'][severity%4]);}if(this.cops.some(c=>c.active&&distance(c,this.player)<55&&lineClear(c,this.player,this.solids)))this.report(severity,this.player,incident);else if(witnesses)this.notify(witnesses+' Zeugen reagieren. Die Meldung ist noch nicht raus.');else this.notify('Keine Zeugen in Sicht.');}
 shoot(){const p=this.player;if(!p.armed||p.cooldown>0)return;if(p.ammo<=0){this.notify('Magazin leer. R / Aktion zum Nachladen.');return;}p.ammo--;p.cooldown=.3;this.shots++;const dir={x:Math.sin(p.yaw),z:Math.cos(p.yaw)},end={x:p.x+dir.x*65,z:p.z+dir.z*65};let best=null,dist=65;for(const n of [...this.npcs,...this.cops.filter(c=>c.active)]){const d=distance(n,p);if(n.health<=0||d>dist)continue;const dot=((n.x-p.x)*dir.x+(n.z-p.z)*dir.z)/Math.max(.01,d);if(dot>.987&&lineClear(p,n,this.solids)){best=n;dist=d;}}if(best){best.health-=34;best.state=best.health<=0?'verletzt':'flüchtend';best.timer=12;end.x=best.x;end.z=best.z;this.injured++;}else{for(let d=1;d<65;d+=.6){const v={x:p.x+dir.x*d,z:p.z+dir.z*d};if(this.solids.some(b=>intersects(v,b))){end.x=v.x;end.z=v.z;break;}}}this.tracers.push({x:p.x,z:p.z,end,life:.1});this.crime(best?2:1);}
 reload(){const p=this.player;if(p.ammo===12||!p.reserve)return;p.cooldown=1.4;const n=Math.min(12-p.ammo,p.reserve);p.ammo+=n;p.reserve-=n;this.notify('Nachladen …');}
 enterExit(){const p=this.player;if(p.car){if(Math.abs(p.car.speed)>3){this.notify('Zum Aussteigen zuerst bremsen.');return;}for(const side of [1,-1]){const v={x:p.car.x+Math.cos(p.car.yaw)*2.8*side,z:p.car.z-Math.sin(p.car.yaw)*2.8*side};if(!this.blocked(v,.5)){p.x=v.x;p.z=v.z;p.car=null;this.notify('Zu Fuß unterwegs.');return;}}this.notify('Die Türen sind blockiert.');return;}const car=this.cars.find(c=>distance(c,p)<4&&c.health>0);if(car){p.car=car;car.wait=0;car.speed=0;p.armed=false;if(car.type==='traffic'){car.type='stolen';this.crime(2);}this.notify('W/S: Gas & Rückwärts · A/D: Lenken · Leertaste: Handbremse');}}
 objective(){return this.mission===0?places.mara:this.mission===1?places.door:this.mission===2?places.disk:places.safe;}
 action(){const p=this.player;if(p.car){this.enterExit();return null;}if(this.mission===0&&distance(p,places.mara)<4)return 'mara';if(this.mission===1&&distance(p,places.door)<5&&!this.doorOpen)return 'guard';if(this.mission===1&&distance(p,places.fuse)<4&&this.camera){this.camera=false;this.openDoor();this.mission=2;this.notify('Sicherung gezogen. Kamera und Magnetschloss ohne Strom.');return null;}if(this.mission===2&&distance(p,places.disk)<3){this.mission=3;if(this.camera){this.report(2);this.notify('Die Kamera hat dich erfasst. Festplatte gesichert — verschwinde.');}else this.notify('Festplatte gesichert. Mara wartet am alten Bootshaus.');return null;}if(this.mission===3&&distance(p,places.safe)<5){if(this.stars){this.notify('Schüttle die Polizei ab, bevor du Mara kontaktierst.');return null;}return 'ending';}if(this.mission>=1&&distance(p,{x:-109,z:66})<4){p.clothes=p.clothes==='orange'?'blue':'orange';this.notify('Jacke gewechselt. Hilft nur außerhalb der Polizeisicht.');return null;}if(p.armed&&p.ammo<12){this.reload();return null;}this.enterExit();return null;}
 choose(choice){if(choice==='accept'){this.mission=1;this.notify('Caldera-Lager: Haupteingang oder Sicherung an der Ostwand.');}if(choice==='bribe'){if(this.player.money<150){this.notify('Du brauchst $150.');return;}this.player.money-=150;this.openDoor();this.mission=2;this.notify('Der Wachmann sieht weg. Die Kamera läuft weiter.');}if(choice==='force'){this.openDoor();this.mission=2;this.report(3);this.notify('Stiller Alarm. Die Wache wurde verständigt.');}if(choice==='leak'||choice==='sell'){this.ending=choice;this.mission=4;this.player.money+=choice==='leak'?800:2000;this.notify(choice==='leak'?'Beweise veröffentlicht. Mara vertraut dir.':'Caldera zahlt. Mara bricht den Kontakt ab.');}}
 tick(dt,input={}){if(this.paused)return;dt=Math.min(.05,dt);this.time+=dt;this.hour=(this.hour+dt/80)%24;this.weatherTimer-=dt;if(this.weatherTimer<=0){this.weather=this.weather==='clear'?'rain':'clear';this.weatherTimer=80;this.post?.('@solvara_wetter',this.weather==='rain'?'Regenband über Port Mercy. Fahrt vorsichtig.':'Aufklarung über der Küste.');this.notify(this.weather==='rain'?'Eine Regenfront zieht über den Hafen. Weniger Grip auf den Straßen.':'Der Regen lässt nach.');}const p=this.player;p.cooldown=Math.max(0,p.cooldown-dt);this.tracers=this.tracers.filter(t=>(t.life-=dt)>0);p.sneak=!!input.sneak;
  if(p.car&&this.driveVehicle){this.driveVehicle(dt,input);}else if(p.car){const c=p.car;const accel=input.forward||0,turn=input.turn||0;const grip=this.weather==='rain'?.68:1;c.speed+=accel*12*dt;if(!accel)c.speed*=Math.pow(.97,dt*60);if(input.brake)c.speed*=Math.pow(.90,dt*60);c.speed=clamp(c.speed,-8,26*Math.max(.25,c.health/100));if(Math.abs(c.speed)>.15)c.yaw-=turn*dt*1.5*clamp(c.speed/7,-1,1)*(input.brake?1.6:grip);const hit=this.move(c,Math.sin(c.yaw)*c.speed*dt,Math.cos(c.yaw)*c.speed*dt,1.45);if(hit&&Math.abs(c.speed)>2){c.health=clamp(c.health-Math.abs(c.speed)*.9,0,100);c.speed*=-.2;this.collisions++;if(c.health===0){p.health-=10;this.notify('Motor ausgefallen. Steig aus und suche ein anderes Auto.');}}p.x=c.x;p.z=c.z;p.yaw=c.yaw;for(const n of this.npcs){if(n.health>0&&distance(c,n)<1.8&&Math.abs(c.speed)>4){n.health=0;n.state='verletzt';this.injured++;c.speed*=.75;this.crime(3);}}for(const other of this.cars){if(other!==c&&distance(c,other)<3&&Math.abs(c.speed)>3){other.wait=5;other.health-=8;c.health=Math.max(0,c.health-5);c.speed*=-.2;this.collisions++;this.crime(1);}}}
  else{const f=input.forward||0,t=input.turn||0,yaw=input.yaw??p.yaw;const speed=p.sneak?2:input.sprint?8:4.5;const len=Math.max(1,Math.hypot(f,t));const dx=(Math.sin(yaw)*f-Math.cos(yaw)*t)*speed*dt/len,dz=(Math.cos(yaw)*f+Math.sin(yaw)*t)*speed*dt/len;this.move(p,dx,dz,.42);if(p.armed)p.yaw=yaw;else if(f||t)p.yaw=Math.atan2(dx,dz);}
  for(const c of this.cars){if(c===p.car||c.type!=='traffic')continue;c.wait=Math.max(0,c.wait-dt);if(c.wait||c.health<=0)continue;const next=c.route[c.target],d=distance(c,next);if(d<1.2){c.target=(c.target+1)%c.route.length;continue;}c.yaw=Math.atan2(next.x-c.x,next.z-c.z);if(distance(c,p)<5&&!p.car)continue;if(this.haeltVorAmpel(c))continue;if(this.wagenVoraus(c))continue;c.x+=Math.sin(c.yaw)*c.speed*dt;c.z+=Math.cos(c.yaw)*c.speed*dt;}
  for(const n of this.npcs){if(n.health<=0||n.state==='tanzend')continue;n.timer-=dt;if(n.report&&n.timer<=0){this.report(n.report.severity,n.report,n.report.incident);n.report=null;n.state='flüchtend';n.timer=9;}if(p.armed&&distance(n,p)<17&&lineClear(n,p,this.solids)&&n.state==='normal'){n.state='aufmerksam';n.timer=1.4;}if(n.state==='aufmerksam'&&n.timer<=0){n.state='flüchtend';n.timer=6;}if(n.state==='erschrocken'&&n.timer<3)n.state='Polizei rufend';if(n.state==='filmend'||n.state==='Polizei rufend'||n.state==='erschrocken'){n.yaw=Math.atan2(p.x-n.x,p.z-n.z);continue;}if(n.state==='flüchtend'){n.yaw=Math.atan2(n.x-p.x,n.z-p.z);this.move(n,Math.sin(n.yaw)*3*dt,Math.cos(n.yaw)*3*dt,.3);if(n.timer<=0){n.state='normal';n.target=(n.target+1)%n.path.length;}}else{const dest=n.path[n.target],d=distance(n,dest);if(d<1)n.target=(n.target+1)%n.path.length;else{n.yaw=Math.atan2(dest.x-n.x,dest.z-n.z);this.move(n,Math.sin(n.yaw)*n.pace*(this.weather==='rain'?1.5:1)*dt,Math.cos(n.yaw)*n.pace*(this.weather==='rain'?1.5:1)*dt,.3);}}}
  this.updatePolice(dt);this.eventTimer-=dt;if(this.eventTimer<=0){this.eventTimer=55;const c=this.cars.find(c=>c.type==='traffic'&&c!==p.car);if(c){c.wait=14;this.notify('Verkehrsfunk: Pannenfahrzeug auf der Harbor Avenue.');}}
  if(p.health<=0){p.health=0;this.paused=true;this.notify('Festgenommen. Starte den Auftrag erneut.');}
 }
 updatePolice(dt){const p=this.player;this.spotted=false;if(this.stars===0){for(const c of this.cops){if(c.active){c.route=route(c,places.station);c.target=0;c.active=false;}const target=c.route[c.target];if(target){if(distance(c,target)<1.5)c.target++;else{c.yaw=Math.atan2(target.x-c.x,target.z-c.z);this.move(c,Math.sin(c.yaw)*9*dt,Math.cos(c.yaw)*9*dt,1.2);}}}return;}this.dispatchTimer-=dt;const desired=Math.min(6,this.stars+1);if(this.dispatchTimer<=0&&this.cops.filter(c=>c.active&&c.health>0).length<desired){const c=this.cops.find(c=>!c.active&&c.health>0);if(c){c.active=true;c.repath=0;c.route=[];this.dispatchTimer=3;}}
  for(const c of this.cops){if(!c.active||c.health<=0)continue;const d=distance(c,p);const identified=p.car?this.description?.plate===p.car.id:this.description?.clothes===p.clothes;const sees=d<(p.sneak?23:48)&&lineClear(c,p,this.solids)&&(identified||d<11||p.armed);if(sees){this.spotted=true;this.lastSeen={x:p.x,z:p.z};this.description={clothes:p.clothes,plate:p.car?.id||null};}c.repath-=dt;if(c.repath<=0){const target=sees?p:this.lastSeen;if(target){c.route=lineClear(c,target,this.solids)?[{x:target.x,z:target.z}]:route(c,target);c.target=0;}c.repath=sees?1:4;}
   const target=c.route[c.target];if(target){const td=distance(c,target);if(td<2)c.target++;else{c.yaw=Math.atan2(target.x-c.x,target.z-c.z);const speed=sees&&d<7?0:10+this.stars*1.4;this.move(c,Math.sin(c.yaw)*speed*dt,Math.cos(c.yaw)*speed*dt,1.2);}}
   c.shot-=dt;if(sees&&d<23&&c.shot<=0){c.shot=1.5;if(this.stars>=2){p.health-=p.car?3:7;this.tracers.push({x:c.x,z:c.z,end:{x:p.x,z:p.z},life:.1});}else if(d<5){p.health-=10;this.notify('Polizei: Stehen bleiben!');}}
  }
  if(this.spotted)this.unseen=0;else this.unseen+=dt;if(this.unseen>18+this.stars*4&&this.lastSeen&&distance(p,this.lastSeen)>28){this.heat=0;this.stars=0;this.lastSeen=null;this.description=null;this.notify('Fahndung beendet. Du bist entkommen.');}
 }
}
