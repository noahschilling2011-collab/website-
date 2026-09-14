// Deterministic gameplay simulation, independent of WebGL and the DOM.
import {intersections,ampelFrei,onRoad,vehicleTypes} from './content.js';
export const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export const distance=(a,b)=>Math.hypot(a.x-b.x,a.z-b.z);
export const roads=[-100,-40,20,80];
export const places={mara:{x:-27,z:73},door:{x:-69,z:-49},fuse:{x:-52,z:-91},disk:{x:-70,z:-78},safe:{x:-77,z:73},station:{x:80,z:-100}};
export function random(seed=41){return ()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};}
const LEER=[];
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
 addSolid(x,z,w,d,kind='building',h=8){const b={x,z,w,d,kind,h};this.solids.push(b);this.rasterEin(b);return b;}
 // Ortsraster für blocked(). Die Funktion lief über alle Solids: bei 104
 // Stück ging das durch, mit der angemeldeten Einrichtung der acht Räume
 // waren es 211 — und der Simulationsschritt stieg von 0,76 auf 2,16
 // Millisekunden. blocked() ist die meistgerufene Funktion der Simulation:
 // die Wegesuche fragt sie für jeden geprüften Punkt.
 //
 // Jedes Hindernis wird in alle Zellen eingetragen, die es mit 2,2 Metern
 // Rand berührt. Damit genügt für jede Abfrage mit r <= 2,2 die eine Zelle,
 // in der der Punkt liegt.
 rasterEin(b){
  if(!this.raster)this.raster=new Map();
  const rand=2.2,Z=24;
  for(let cx=Math.floor((b.x-b.w/2-rand)/Z);cx<=Math.floor((b.x+b.w/2+rand)/Z);cx++)
   for(let cz=Math.floor((b.z-b.d/2-rand)/Z);cz<=Math.floor((b.z+b.d/2+rand)/Z);cz++){
    const k=cx+'|'+cz;let a=this.raster.get(k);
    if(!a){a=[];this.raster.set(k,a);}
    a.push(b);
   }
 }
 rasterNeu(){this.raster=new Map();for(const b of this.solids)this.rasterEin(b);}
 // Sichtlinie über dasselbe Raster. lineClear() bekommt eine Liste und prüft
 // jeden Punkt der Strecke gegen jedes Hindernis darin — bei 211 Solids und
 // rund vierzig Punkten je Strecke sind das achttausend Vergleiche für eine
 // einzige Sichtprüfung, und die Menge fragt sie für jede Figur.
 sichtFrei(a,b){
  const d=Math.hypot(b.x-a.x,b.z-a.z),n=Math.max(1,Math.ceil(d/.65));
  for(let i=1;i<n;i++){
   const p={x:a.x+(b.x-a.x)*i/n,z:a.z+(b.z-a.z)*i/n};
   const nah=this.nahe(p,0);
   for(let k=0;k<nah.length;k++)if(intersects(p,nah[k],0))return false;
  }
  return true;
 }
 // Die Hindernisse in der Nähe eines Punktes, oder alle, wenn der Radius
 // größer ist als der Rand des Rasters.
 nahe(p,r){
  if(r>2.2||!this.raster)return this.solids;
  return this.raster.get(Math.floor(p.x/24)+'|'+Math.floor(p.z/24))||LEER;
 }
 makeWorld(){
  for(let ix=0;ix<3;ix++)for(let iz=0;iz<3;iz++){const x=roads[ix]+30,z=roads[iz]+30;if(ix===0&&iz===0)continue;for(let j=0;j<2;j++){const b=this.addSolid(x+(j?11:-11),z,18,38,'building',9+Math.floor(this.rng()*32));this.buildings.push(b);}}
  // Warehouse: solid walls with a real 8 m front opening.
  // Das Lagerhaus stand acht Meter zu weit westlich und vier zu weit
  // südlich: die Westwand lag fünfeinhalb Meter tief in der Nord-Süd-Achse
  // bei x = -100, die Südwand streifte die Querstraße bei z = -100. Sieben
  // Meter breite Wand quer über der Fahrbahn, sieben Meter hoch. Zwischen
  // den beiden Achsen bleiben fünfundvierzig Meter frei, das Gebäude ist
  // dreiundvierzig breit und neununddreißig tief. Es passt also, aber knapp:
  // ein halber Meter Luft zur Fahrbahn nach Westen und Osten, drei Meter
  // nach Süden und Norden. Der Gehweg bleibt dabei nicht frei — dafür wäre
  // das Gebäude auf dreißig Meter zu schrumpfen, und das ist der Missionsraum
  // des ersten Akts. Frei ist, worauf gefahren wird. Verschoben wurde alles
  // mit: Wände, Tor, Kisten, Boden, Dach, Schriftzug, Festplatte,
  // Sicherungskasten und die drei Missionspunkte.
  // Der Sicherungskasten hing an der Ostwand, und dort ist zwischen Wand
  // und Fahrbahn jetzt ein halber Meter. Er sitzt deshalb an der Südwand:
  // dort bleiben drei Meter Gehweg zwischen Gebäude und Querstraße, und
  // der Weg um das Haus herum ist der bessere Auftakt als einer über die
  // Fahrspur.
  this.addSolid(-90,-70,1,38,'warehouse',7);this.addSolid(-48,-70,1,38,'warehouse',7);this.addSolid(-69,-89,43,1,'warehouse',7);this.addSolid(-82,-51,17,1,'warehouse',7);this.addSolid(-56,-51,17,1,'warehouse',7);this.gate=this.addSolid(-69,-51,8,1,'gate',5);
  this.addSolid(-79,-74,6,6,'crate',2.8);this.addSolid(-57,-81,7,5,'crate',2.4);this.addSolid(-59,-60,5,5,'crate',2.7);
  const loop=[{x:-31,z:90},{x:-31,z:29},{x:11,z:29},{x:11,z:90}];
  for(let i=0;i<18;i++){const block=i%3;const path=loop.map(p=>({x:p.x+(block===1?60:block===2?-60:0),z:p.z-(i%2?120:0)}));const p=path[i%4];this.npcs.push({id:i,x:p.x,z:p.z,yaw:0,state:'normal',timer:0,health:100,path,target:(i+1)%4,personality:['caller','filmer','coward'][i%3],pace:1.1+this.rng()*.8,report:null});}
  // Elis eigener Wagen stand bei (-34, 75) mitten auf der Fahrbahn: sechs
  // Meter von der Achse der fünfzehn Meter breiten Straße bei x = -40, die
  // Fahrspur des Verkehrs liegt bei -35,7. Vorbeifahrende Wagen streiften ihn
  // — die Überlappungsprüfung hat ihn sechsmal in fünf Minuten erwischt.
  // Der neue Platz ist gesucht, nicht geschätzt: die nächstgelegene Stelle,
  // an der alle vier Ecken der Karosserie und die Mitte mit 1,2 Metern Luft
  // neben jeder Fahrbahn liegen, trocken, eben und frei von Kulisse sind.
  // Der erste Fund acht Meter weiter war gegen Straße, Wasser und Gelände
  // geprüft, aber nicht gegen die Hindernisse der Welt — der Wagen stand in
  // einer Kulisse und ließ sich nicht bewegen. Die Prüfung „Fahrzeug
  // beschleunigt" hat es gemeldet.
  this.cars.push({id:'VOSS-07',x:-29.6,z:91.4,yaw:Math.PI,speed:0,health:100,type:'player',color:0x49a8a4});
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
 // Fußgänger auf der Fahrbahn, alle Zehntelsekunde neu eingesammelt. Der
 // Verkehr sonst gegen alle Figuren zu prüfen wären bei 116 Wagen und 413
 // Figuren achtundvierzigtausend Abstände je Bild; diese Liste ist im
 // Regelfall ein Dutzend lang. Eine Zehntelsekunde sind bei
 // Schrittgeschwindigkeit fünfzehn Zentimeter Versatz — weniger als die
 // Breite, mit der geprüft wird. Die Zeit statt eines Tickzählers, weil
 // tickCount erst in der Kampagne existiert und die Basisklasse allein
 // laufen können muss.
 aufFahrbahn(){
  if(this._aufFahrbahn&&this.time-this._aufFahrbahnZeit<.1)return this._aufFahrbahn;
  this._aufFahrbahnZeit=this.time;
  // Zweieinhalb Meter Rand statt einem: die Liste wird nur alle
  // Zehntelsekunde erneuert, und wer in dieser Zeit vom Bordstein auf die
  // Spur tritt, wäre sonst bis zu sechs Ticks unsichtbar — bei elf Metern
  // je Sekunde legt ein Wagen darin 1,9 Meter zurück. Mit dem größeren Rand
  // steht er schon in der Liste, bevor er die Fahrbahn betritt.
  // _alleNpcs, nicht this.npcs: die Kampagne ersetzt this.npcs während des
  // Ticks durch die Figuren im Umkreis von 180 Metern um den Spieler. Aus
  // dieser gekürzten Liste gebaut, kannte der Verkehr weiter entfernte
  // Fußgänger nicht und fuhr durch sie hindurch.
  return this._aufFahrbahn=(this._alleNpcs||this.npcs).filter(n=>n.health>0&&onRoad(n.x,n.z,2.5));
 }

 // Bremsen für jemanden, der vor einem auf der Straße steht. Ohne das fuhr
 // der Verkehr durch die Menge hindurch: gemessen neunzehn Fälle unter 1,6
 // Metern in zehn Sekunden, engster Abstand 0,70 Meter, und keine einzige
 // Figur nahm dabei Schaden — die Simulation hat es nicht einmal bemerkt.
 fussgaengerVoraus(c){
  const sin=Math.sin(c.yaw),cos=Math.cos(c.yaw);
  for(const n of this.aufFahrbahn()){
   const dx=n.x-c.x,dz=n.z-c.z;
   if(Math.abs(dx)+Math.abs(dz)>10)continue;
   const laengs=dx*sin+dz*cos;
   // Von der Wagenmitte nach vorn, nicht erst ab dreißig Zentimetern: wer
   // seitlich vorn hereinläuft, wurde sonst überfahren. Das Band ist mit
   // 2,4 Metern etwas breiter als der Wagen, damit auch der zählt, der noch
   // einen Schritt vom Kotflügel entfernt ist.
   if(laengs<0||laengs>6.5)continue;
   if(Math.abs(dx*cos-dz*sin)>2.4)continue;
   return true;
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
  // Der Abstand hing an einer festen Zahl: sieben Meter von Mitte zu Mitte,
  // für jedes Fahrzeug gleich. Zwischen zwei Limousinen sind das 2,5 Meter
  // Luft, hinter einem Achtmeterbus nur 0,8 — und ein Bus hinter einem
  // Kleinwagen hätte mit vier Metern Überhang aufgeschlossen. Jetzt zählt die
  // Länge beider: 2,5 Meter Luft plus je die halbe Länge.
  const la=vehicleTypes[c.model]?.laenge||4.5, ba=vehicleTypes[c.model]?.breite||2.2;
  // Der Abstandsfilter steht vor allem anderen. Im ersten Anlauf kamen zuerst
  // zwei Nachschlagewerke und zwei Winkelfunktionen je Paar, danach erst der
  // Filter: bei 144 Fahrzeugen und 103 Aufrufen je Takt sind das
  // fünfzehntausend Sinus- und Kosinusaufrufe, und wagenVoraus kostete 1,674
  // von 2,0 Millisekunden des ganzen Simulationsschritts.
  //
  // 6,5 Meter ist die halbe Länge des längsten Fahrzeugs; weiter kann kein
  // Hindernis in die eigene Richtung reichen.
  const grenze=2.5+la/2+6.5+2;
  for(const o of this.cars){
   if(o===c||o.health<=0)continue;
   const dx=o.x-c.x,dz=o.z-c.z;
   if(Math.abs(dx)+Math.abs(dz)>grenze)continue;
   const lo=vehicleTypes[o.model]?.laenge||4.5, bo=vehicleTypes[o.model]?.breite||2.2;
   // Der andere Wagen steht nicht unbedingt in meiner Richtung. Seine
   // Ausdehnung wird deshalb auf meine Achsen projiziert: ein quer stehender
   // Kleinwagen ist in meiner Fahrtrichtung nur 1,9 Meter tief, quer dazu
   // aber 3,7 — mit einer festen Breite war er unsichtbar. Genau daran hingen
   // zwei Wagen ineinander an der Kreuzung [23,18], wo sich die Runden Raster
   // Ost und Hafenblock überschneiden.
   // sin(o.yaw-c.yaw) aus den schon bekannten Werten statt aus zwei neuen
   // Winkelfunktionen je Paar.
   const so=Math.sin(o.yaw),co=Math.cos(o.yaw);
   const sd=Math.abs(so*cos-co*sin), cd=Math.abs(co*cos+so*sin);
   const tiefe=lo/2*cd+bo/2*sd, quer=lo/2*sd+bo/2*cd;
   const weit=2.5+la/2+tiefe;
   const laengs=dx*sin+dz*cos;
   if(laengs<.4||laengs>weit)continue;
   if(Math.abs(dx*cos-dz*sin)>ba/2+quer+.3)continue;
   // Zwei Wagen, die einander quer sehen, blockierten sich sonst für immer.
   // Nach drei bis gut fünf Sekunden Stillstand fährt einer los; die
   // Staffelung steckt in der Kennung, damit nicht beide gleichzeitig
   // anfahren.
   // Nur, wenn der andere selbst festhängt. Steht er aus einem anderen
   // Grund — der Spieler steht daneben, und dann fährt kein Wagen an —,
   // wäre das kein Patt, sondern ein Auffahren: gemessen zwei Kleinwagen,
   // die sich alle paar Sekunden neu ineinander schoben.
   if(sd>.7&&(c.stau||0)>3+this.rangVon(c)*.7&&(o.stau||0)>2)continue;
   return true;
  }
  return false;
 }
 // Steht der Spieler dem Wagen im Weg? Vorher hielt jeder Wagen an, sobald
 // der Spieler irgendwo in fünf Metern stand — auch neben der Spur auf dem
 // Gehweg. Ein einziger Fußgänger fror damit eine Fahrbahn dauerhaft ein:
 // gemessen 41 von 126 Wagen, die sich in fünfundvierzig Sekunden keine drei
 // Meter bewegten, davon 34 in der Schlange dahinter.
 spielerImWeg(c,p){
  const dx=p.x-c.x,dz=p.z-c.z;
  if(dx*dx+dz*dz>36)return false;
  const vorne=Math.sin(c.yaw)*dx+Math.cos(c.yaw)*dz;
  if(vorne<-1.5)return false;
  return Math.abs(Math.cos(c.yaw)*dx-Math.sin(c.yaw)*dz)<2.4;
 }
 // Figuren, die einander im Weg stehen. Zwei Versuche sind daran gescheitert:
 // auseinanderschieben drückt eine wegegetriebene Menge nur in die Nachbarn
 // (1,0 auf 1,93 Paare, mit stärkerem Schub 5,07), und lenken ohne Kollision
 // schiebt die Figur seitlich in die Bahn der anderen (echte Durchgänge von 3
 // auf 10). Beide waren Zusätze von Bewegung.
 //
 // Dies hier fügt keine Bewegung hinzu, sondern nimmt welche weg: der Anteil
 // eines Schritts, der in einen anderen hineinführt, wird verworfen. Wer
 // vorbeigehen will, geht vorbei; wer hineinliefe, bleibt stehen.
 //
 // Auch für Fliehende. Der erste Anlauf hat sie ausgenommen — Panik darf
 // durcheinandergehen —, und am Ende des Prüflaufs, wenn die halbe
 // Innenstadt vor einer gezogenen Waffe rennt, standen wieder 1,13 Paare
 // ineinander, engster Abstand drei Zentimeter.
 figurRasterBauen(){
  const alle=this._alleNpcs||this.npcs;
  const r=this._figurRaster||(this._figurRaster=new Map());
  r.clear();
  for(const n of alle){
   if(n.health<=0||n.stun>0)continue;
   const k=Math.floor(n.x/2)+'|'+Math.floor(n.z/2);
   let a=r.get(k);if(!a){a=[];r.set(k,a);}a.push(n);
  }
 }
 // Gibt den Schritt zurück, der von der Figur übrig bleibt.
 schrittOhneDurchdringen(n,dx,dz){
  const raster=this._figurRaster;
  if(!raster)return [dx,dz];
  const ABSTAND=.46;
  const zx=n.x+dx,zz=n.z+dz;
  const cx=Math.floor(zx/2),cz=Math.floor(zz/2);
  for(let ex=-1;ex<=1;ex++)for(let ez=-1;ez<=1;ez++){
   const liste=raster.get((cx+ex)+'|'+(cz+ez));
   if(!liste)continue;
   for(const o of liste){
    if(o===n||o.state==='sitzend')continue;
    const ax=zx-o.x,az=zz-o.z;
    const d=Math.hypot(ax,az);
    if(d>=ABSTAND)continue;
    const vx=n.x-o.x,vz=n.z-o.z,vor=Math.hypot(vx,vz);
    // Nur, wenn der Schritt den Abstand verkleinert. Wer sich löst, darf.
    if(d>=vor)continue;
    const l=Math.max(1e-4,vor);
    const hin=(dx*vx+dz*vz)/l;
    if(hin>=0)continue;
    dx-=vx/l*hin;dz-=vz/l*hin;
   }
  }
  return [dx,dz];
 }
 // Wer sich festfährt, geht seitlich vorbei.
 //
 // Der reine Filter hat einen Haken, den erst der volle Prüflauf zeigte: zwei
 // Figuren, die genau aufeinander zulaufen, streichen sich gegenseitig den
 // ganzen Schritt und stehen dann dauerhaft. Bei 491 gehenden Figuren waren
 // das zwei Paare, beide über volle zehn Sekunden auf 0,30 und 0,34 Meter —
 // keine Durchdringung, eine Verklemmung.
 //
 // Der Ausweg ist nicht mehr Kraft, sondern eine andere Richtung: Wer bis auf
 // ein Viertel seines Schritts blockiert ist, versucht es quer dazu und nimmt
 // die Seite, auf der mehr übrig bleibt. Auch der Querschritt läuft durch den
 // Filter, geht also seinerseits in niemanden hinein, und niemand wird
 // geschoben. Der Aufwand fällt nur bei Blockierten an.
 schrittUmGehen(n,dx,dz){
  const gerade=this.schrittOhneDurchdringen(n,dx,dz);
  const soll=Math.hypot(dx,dz);
  if(soll<1e-5||Math.hypot(gerade[0],gerade[1])>soll*.25){n.klemmt=0;return gerade;}
  // Kurz vor jemandem stehenbleiben ist normal und soll so aussehen. Erst wer
  // ein Zehntel Sekunde nicht vom Fleck kommt, sucht seitlich vorbei. Ohne
  // diese Schwelle kostete der Ausweichschritt 0,20 ms je Takt (1,11 gegen
  // 0,91 ohne alles, im selben Lauf gemessen), weil er für jede kurz
  // blockierte Figur zweimal zusätzlich das Ortsraster abfragte.
  if((n.klemmt=(n.klemmt||0)+1)<6)return gerade;
  const rechts=this.schrittOhneDurchdringen(n,dz,-dx),links=this.schrittOhneDurchdringen(n,-dz,dx);
  const lr=Math.hypot(rechts[0],rechts[1]),ll=Math.hypot(links[0],links[1]);
  const beste=lr>=ll?rechts:links,laenge=Math.max(lr,ll);
  return laenge>soll*.25?beste:gerade;
 }
 // Wer in einem Hindernis steht, kommt aus eigener Kraft nie wieder heraus.
 //
 // move() prüft das Ziel eines Schritts, nicht den Standort. Innerhalb eines
 // Körpers ist jedes Ziel blockiert, also wird jeder Schritt verworfen — die
 // Figur steht für den Rest des Spiels da. Genau dieses Bild lieferte der
 // Prüflauf: null Meter in zehn Sekunden bei einem Ziel in 63 bis 266 Metern.
 // Hineingeraten kann sie, ohne sich zu bewegen, weil Hindernisse zur Laufzeit
 // dazukommen — die Einrichtung der Innenräume etwa steht erst danach fest.
 //
 // Die erste Fassung hat im Kreis nach einem freien Platz gesucht, bis 4,2
 // Meter Umkreis. Das reicht nicht: der Körper, in dem die Testfigur stand,
 // misst 18,8 auf 38,8 Meter, und aus dessen Mitte liegt kein freier Punkt
 // innerhalb von vier Metern. Gemessen: weiterhin null Meter in fünfzehn
 // Sekunden.
 //
 // Stattdessen wird über die Kante geschoben, in die nächstliegende Richtung:
 // aus einem Rechteck heraus ist der kürzeste Weg immer die nächste Seite.
 // Dreimal, weil hinter der einen Kante die nächste Kiste stehen kann.
 befreie(n){
  for(let versuch=0;versuch<3;versuch++){
   const koerper=this.nahe(n,.3).filter(b=>intersects(n,b,.3));
   if(!koerper.length)return true;
   let besteStrecke=1e9,zx=n.x,zz=n.z;
   for(const b of koerper){
    const kanten=[[b.x-b.w/2-.34,n.z],[b.x+b.w/2+.34,n.z],[n.x,b.z-b.d/2-.34],[n.x,b.z+b.d/2+.34]];
    for(const [x,z] of kanten){
     const strecke=Math.hypot(x-n.x,z-n.z);
     if(strecke<besteStrecke){besteStrecke=strecke;zx=x;zz=z;}
    }
   }
   n.x=zx;n.z=zz;
  }
  return !this.blocked(n,.3);
 }
 // Wer verkeilt ist, wird ein Stück zur Seite gesetzt.
 //
 // befreie() oben hilft nur, wer **in** einem Körper steht. Der Prüflauf zeigte
 // den anderen Fall: zwei Figuren, beide mit Hindernis direkt voraus, beide
 // 0,0 Meter in zehn Sekunden, 0,12 Meter voneinander entfernt — in einer Ecke
 // eingeklemmt, aber nicht in der Geometrie. Für sie findet freierWegpunkt()
 // keinen sichtbaren Wegpunkt, und das Durchprobieren der Liste ändert nichts,
 // weil von dieser Stelle aus keiner erreichbar ist.
 //
 // Gesucht wird der nächste freie Platz im Umkreis von drei Metern, bevorzugt
 // in Richtung des Ziels. Das ist ein sichtbarer Versatz — die Alternative ist
 // eine Figur, die für den Rest des Spiels in der Ecke steht.
 freiSchieben(n,ziel){
  let bestX=null,bestZ=null,bestWert=1e9;
  for(let r=1;r<=3;r+=1)for(let i=0;i<12;i++){
   const a=i/12*Math.PI*2,x=n.x+Math.sin(a)*r,z=n.z+Math.cos(a)*r;
   if(this.blocked({x,z},.35))continue;
   const wert=ziel?Math.hypot(ziel.x-x,ziel.z-z):r;
   if(wert<bestWert){bestWert=wert;bestX=x;bestZ=z;}
  }
  if(bestX===null)return false;
  n.x=bestX;n.z=bestZ;return true;
 }
 // Der nächste Wegpunkt, den die Figur von hier aus überhaupt sehen kann.
 //
 // "Nimm den nächsten Punkt der Liste" reicht nicht, wenn die Figur an einer
 // Wand hängt: der übernächste liegt oft hinter derselben Wand, und bei 64
 // Wegpunkten dauert das Durchprobieren bei drei Sekunden je Versuch über drei
 // Minuten. Gesucht wird deshalb der nächstgelegene Punkt mit freier
 // Sichtlinie — das ist der, zu dem sie tatsächlich hinlaufen kann.
 freierWegpunkt(n){
  let beste=-1,besteD=1e9;
  for(let i=0;i<n.path.length;i++){
   const k=n.path[i],d=distance(n,k);
   if(d<1.5||d>70||d>=besteD)continue;
   if(!this.sichtFrei(n,k))continue;
   besteD=d;beste=i;
  }
  return beste;
 }
 // Wie tief zwei Fahrzeuge ineinanderstehen, über die Trennachsen der
 // beiden Rechtecke. Null, wenn sie sich nicht berühren.
 ueberlappung(a,b){
  const ta=vehicleTypes[a.model]||{},tb=vehicleTypes[b.model]||{};
  const la=(ta.laenge||4.5)/2,ba=(ta.breite||2.2)/2;
  const lb=(tb.laenge||4.5)/2,bb=(tb.breite||2.2)/2;
  const dx=b.x-a.x,dz=b.z-a.z;
  const sa=Math.sin(a.yaw),ca=Math.cos(a.yaw),sb=Math.sin(b.yaw),cb=Math.cos(b.yaw);
  let tief=Infinity;
  for(const [ux,uz] of [[sa,ca],[ca,-sa],[sb,cb],[cb,-sb]]){
   const d=Math.abs(dx*ux+dz*uz);
   const ra=la*Math.abs(sa*ux+ca*uz)+ba*Math.abs(ca*ux-sa*uz);
   const rb=lb*Math.abs(sb*ux+cb*uz)+bb*Math.abs(cb*ux-sb*uz);
   if(d>ra+rb)return 0;
   tief=Math.min(tief,ra+rb-d);
  }
  return tief;
 }
 // Zwei Wagen, die bereits ineinanderstehen, trennt keine Regel: wagenVoraus
 // verhindert nur, dass sich eine Lücke schließt. Zwei Runden können dieselbe
 // Spur benutzen, und dann stehen ihre Wagen schon beim Aufbau ineinander; an
 // einer roten Ampel bleiben sie es für immer. Gemessen über fünf Minuten:
 // zweihundertzwei Überlappungen an hundertfünfzig Messpunkten.
 //
 // Alle vier Takte weicht der hintere zurück, höchstens einen halben Meter.
 // Auf der eigenen Spur, nicht zur Seite — sonst stünde er im Grün.
 entflechten(){
  const c=this.cars;
  for(let i=0;i<c.length;i++){
   const a=c[i];
   if(a.health<=0||a===this.player.car)continue;
   for(let j=i+1;j<c.length;j++){
    const b=c[j];
    if(b.health<=0||b===this.player.car)continue;
    if(Math.abs(b.x-a.x)+Math.abs(b.z-a.z)>14)continue;
    const tief=this.ueberlappung(a,b);
    if(tief<=0)continue;
    // Bewegt wird, wer fährt. Steht der hintere geparkt — der eigene Wagen
    // des Spielers zum Beispiel —, weicht stattdessen der vordere nach vorn:
    // ein geparkter Wagen in der Spur ist sonst eine Überlappung für immer.
    const vorA=(b.x-a.x)*Math.sin(a.yaw)+(b.z-a.z)*Math.cos(a.yaw);
    let hinten=vorA>0?a:b, vorne=vorA>0?b:a;
    const weg=Math.min(.5,tief+.05);
    if(hinten.type==='traffic'&&hinten!==this.player.car){
     hinten.x-=Math.sin(hinten.yaw)*weg;
     hinten.z-=Math.cos(hinten.yaw)*weg;
    }else if(vorne.type==='traffic'&&vorne!==this.player.car){
     vorne.x+=Math.sin(vorne.yaw)*weg;
     vorne.z+=Math.cos(vorne.yaw)*weg;
    }
   }
  }
 }
 // Stabile kleine Zahl aus der Wagenkennung, 0 bis 3.
 rangVon(c){
  if(c._rang===undefined){let h=0;for(const z of String(c.id||''))h+=z.charCodeAt(0);c._rang=h%4;}
  return c._rang;
 }
 blocked(p,r=.4){return p.x<-119+r||p.x>112-r||p.z<-119+r||p.z>113-r||this.nahe(p,r).some(b=>intersects(p,b,r));}
 move(o,dx,dz,r=.4){let hit=false;const steps=Math.max(1,Math.ceil(Math.hypot(dx,dz)/.25));for(let i=0;i<steps;i++){if(!this.blocked({x:o.x+dx/steps,z:o.z},r))o.x+=dx/steps;else hit=true;if(!this.blocked({x:o.x,z:o.z+dz/steps},r))o.z+=dz/steps;else hit=true;}return hit;}
 openDoor(){this.doorOpen=true;this.solids=this.solids.filter(s=>s!==this.gate);this.rasterNeu();}
 report(severity,pos=this.player,incident=null){if(incident!==null){if(this.reported.has(incident))return;this.reported.add(incident);}this.heat=clamp(this.heat+severity,0,12);this.stars=Math.ceil(this.heat/2);this.lastSeen={x:pos.x,z:pos.z};this.unseen=0;this.description={clothes:this.player.clothes,plate:this.player.car?.id||null};this.notify('Leitstelle: Meldung bestätigt. Einheiten unterwegs.');}
 crime(severity=1){const incident=++this.incident;let witnesses=0;for(const n of this.npcs){if(n.health<=0||distance(n,this.player)>42||!this.sichtFrei(n,this.player))continue;n.report={severity,incident,x:this.player.x,z:this.player.z};n.timer=n.personality==='caller'?4:7;n.state=n.personality==='filmer'?'filmend':'erschrocken';witnesses++;
   if(n.personality==='filmer'&&this.post)this.post('@hafenblick_'+(n.id%90),
    ['Gerade eben am Hafen. Ich habe alles gefilmt.','Leute, hier läuft was komplett aus dem Ruder.',
     'Das war zu nah. Video kommt gleich.','Wer war das? Ich habe das Kennzeichen.'][severity%4]);}if(this.cops.some(c=>c.active&&distance(c,this.player)<55&&this.sichtFrei(c,this.player)))this.report(severity,this.player,incident);else if(witnesses)this.notify(witnesses+' Zeugen reagieren. Die Meldung ist noch nicht raus.');else this.notify('Keine Zeugen in Sicht.');}
 shoot(){const p=this.player;if(!p.armed||p.cooldown>0)return;if(p.ammo<=0){this.notify('Magazin leer. R / Aktion zum Nachladen.');return;}p.ammo--;p.cooldown=.3;this.shots++;const dir={x:Math.sin(p.yaw),z:Math.cos(p.yaw)},end={x:p.x+dir.x*65,z:p.z+dir.z*65};let best=null,dist=65;for(const n of [...this.npcs,...this.cops.filter(c=>c.active)]){const d=distance(n,p);if(n.health<=0||d>dist)continue;const dot=((n.x-p.x)*dir.x+(n.z-p.z)*dir.z)/Math.max(.01,d);if(dot>.987&&this.sichtFrei(p,n)){best=n;dist=d;}}if(best){best.health-=34;best.state=best.health<=0?'verletzt':'flüchtend';best.timer=12;end.x=best.x;end.z=best.z;this.injured++;}else{for(let d=1;d<65;d+=.6){const v={x:p.x+dir.x*d,z:p.z+dir.z*d};if(this.solids.some(b=>intersects(v,b))){end.x=v.x;end.z=v.z;break;}}}this.tracers.push({x:p.x,z:p.z,end,life:.1});this.crime(best?2:1);}
 reload(){const p=this.player;if(p.ammo===12||!p.reserve)return;p.cooldown=1.4;const n=Math.min(12-p.ammo,p.reserve);p.ammo+=n;p.reserve-=n;this.notify('Nachladen …');}
 enterExit(){const p=this.player;if(p.car){if(Math.abs(p.car.speed)>3){this.notify('Zum Aussteigen zuerst bremsen.');return;}for(const side of [1,-1]){const v={x:p.car.x+Math.cos(p.car.yaw)*2.8*side,z:p.car.z-Math.sin(p.car.yaw)*2.8*side};if(!this.blocked(v,.5)){p.x=v.x;p.z=v.z;p.car=null;this.notify('Zu Fuß unterwegs.');return;}}this.notify('Die Türen sind blockiert.');return;}const car=this.cars.find(c=>distance(c,p)<4&&c.health>0);if(car){p.car=car;car.wait=0;car.speed=0;p.armed=false;if(car.type==='traffic'){car.type='stolen';this.crime(2);}this.notify('W/S: Gas & Rückwärts · A/D: Lenken · Leertaste: Handbremse');}}
 objective(){return this.mission===0?places.mara:this.mission===1?places.door:this.mission===2?places.disk:places.safe;}
 action(){const p=this.player;if(p.car){this.enterExit();return null;}if(this.mission===0&&distance(p,places.mara)<4)return 'mara';if(this.mission===1&&distance(p,places.door)<5&&!this.doorOpen)return 'guard';if(this.mission===1&&distance(p,places.fuse)<4&&this.camera){this.camera=false;this.openDoor();this.mission=2;this.notify('Sicherung gezogen. Kamera und Magnetschloss ohne Strom.');return null;}if(this.mission===2&&distance(p,places.disk)<3){this.mission=3;if(this.camera){this.report(2);this.notify('Die Kamera hat dich erfasst. Festplatte gesichert — verschwinde.');}else this.notify('Festplatte gesichert. Mara wartet am alten Bootshaus.');return null;}if(this.mission===3&&distance(p,places.safe)<5){if(this.stars){this.notify('Schüttle die Polizei ab, bevor du Mara kontaktierst.');return null;}return 'ending';}if(this.mission>=1&&distance(p,{x:-109,z:66})<4){p.clothes=p.clothes==='orange'?'blue':'orange';this.notify('Jacke gewechselt. Hilft nur außerhalb der Polizeisicht.');return null;}if(p.armed&&p.ammo<12){this.reload();return null;}this.enterExit();return null;}
 choose(choice){if(choice==='accept'){this.mission=1;this.notify('Caldera-Lager: Haupteingang oder Sicherung an der Ostwand.');}if(choice==='bribe'){if(this.player.money<150){this.notify('Du brauchst $150.');return;}this.player.money-=150;this.openDoor();this.mission=2;this.notify('Der Wachmann sieht weg. Die Kamera läuft weiter.');}if(choice==='force'){this.openDoor();this.mission=2;this.report(3);this.notify('Stiller Alarm. Die Wache wurde verständigt.');}if(choice==='leak'||choice==='sell'){this.ending=choice;this.mission=4;this.player.money+=choice==='leak'?800:2000;this.notify(choice==='leak'?'Beweise veröffentlicht. Mara vertraut dir.':'Caldera zahlt. Mara bricht den Kontakt ab.');}}
 tick(dt,input={}){if(this.paused)return;dt=Math.min(.05,dt);this.time+=dt;this.hour=(this.hour+dt/80)%24;this.weatherTimer-=dt;if(this.weatherTimer<=0){this.weather=this.weather==='clear'?'rain':'clear';this.weatherTimer=80;this.post?.('@solvara_wetter',this.weather==='rain'?'Regenband über Port Mercy. Fahrt vorsichtig.':'Aufklarung über der Küste.');this.notify(this.weather==='rain'?'Eine Regenfront zieht über den Hafen. Weniger Grip auf den Straßen.':'Der Regen lässt nach.');}const p=this.player;p.cooldown=Math.max(0,p.cooldown-dt);this.tracers=this.tracers.filter(t=>(t.life-=dt)>0);p.sneak=!!input.sneak;
  if(p.car&&this.driveVehicle){this.driveVehicle(dt,input);}else if(p.car){const c=p.car;const accel=input.forward||0,turn=input.turn||0;const grip=this.weather==='rain'?.68:1;c.speed+=accel*12*dt;if(!accel)c.speed*=Math.pow(.97,dt*60);if(input.brake)c.speed*=Math.pow(.90,dt*60);c.speed=clamp(c.speed,-8,26*Math.max(.25,c.health/100));if(Math.abs(c.speed)>.15)c.yaw-=turn*dt*1.5*clamp(c.speed/7,-1,1)*(input.brake?1.6:grip);const hit=this.move(c,Math.sin(c.yaw)*c.speed*dt,Math.cos(c.yaw)*c.speed*dt,1.45);if(hit&&Math.abs(c.speed)>2){c.health=clamp(c.health-Math.abs(c.speed)*.9,0,100);c.speed*=-.2;this.collisions++;if(c.health===0){p.health-=10;this.notify('Motor ausgefallen. Steig aus und suche ein anderes Auto.');}}p.x=c.x;p.z=c.z;p.yaw=c.yaw;for(const n of this.npcs){if(n.health>0&&distance(c,n)<1.8&&Math.abs(c.speed)>4){n.health=0;n.state='verletzt';this.injured++;c.speed*=.75;this.crime(3);}}for(const other of this.cars){if(other!==c&&distance(c,other)<3&&Math.abs(c.speed)>3){other.wait=5;other.health-=8;c.health=Math.max(0,c.health-5);c.speed*=-.2;this.collisions++;this.crime(1);}}}
  else{const f=input.forward||0,t=input.turn||0,yaw=input.yaw??p.yaw;const speed=p.sneak?2:input.sprint?8:4.5;const len=Math.max(1,Math.hypot(f,t));const dx=(Math.sin(yaw)*f-Math.cos(yaw)*t)*speed*dt/len,dz=(Math.cos(yaw)*f+Math.sin(yaw)*t)*speed*dt/len;this.move(p,dx,dz,.42);if(p.armed)p.yaw=yaw;else if(f||t)p.yaw=Math.atan2(dx,dz);}
  // Gelenkt wird mit begrenzter Rate. Vorher stand hier die Zuweisung der
  // Zielrichtung, und am Wegpunkt sprang die Fahrtrichtung in einem einzigen
  // Takt um bis zu 102 Grad: gemessen 508 Sprünge in neunzig Sekunden, jeder
  // einzelne über 45 Grad. Ein Fahrzeug drehte sich auf der Stelle.
  //
  // Drei Teile gehören zusammen. Eine Lenkrate, die mit der Fahrzeuglänge
  // sinkt: 2,4 rad/s bei 4,5 Metern, 1,35 beim Achtmeterbus. Langsamfahrt in
  // der Kurve, weil der Halbmesser der Bahn v/ω ist — mit vollem Tempo wären
  // es sechs Meter, und der Wagen läge im Grün. Und ein Zielpunkt, der auf
  // der Strecke liegt und nicht am Wegpunkt: der Wagen zielt auf einen Punkt
  // zweieinhalb Meter plus fünfundfünfzig Prozent seiner Länge weiter auf der
  // eigenen Bahn.
  //
  // Gewechselt wird nur, wenn der Wagen auch in der Nähe des Wegpunkts ist.
  // Ohne diese Bedingung sprang der Index bei einem Wagen, der aus der Spur
  // geraten war, gleich mehrere Kanten weiter — ein Bus fuhr daraufhin quer
  // über den Block, statt auf seine Strecke zurückzukehren.
  //
  // Der Wegpunktwechsel darf den Takt nicht kosten. Im ersten Anlauf stand
  // hinter ihm ein continue; ein Wagen, der an einer Kreuzung zweier Runden
  // so stand, dass er hinter jedem der vier Wegpunkte lag, wechselte deshalb
  // den Index in jedem Takt und fuhr nie — zwei Kleinwagen hingen dauerhaft
  // ineinander. Jetzt wird in derselben Runde weitergesucht.
  //
  // Der erste Anlauf wechselte stattdessen den Wegpunkt früher, damit die
  // Kurve vor der Ecke beginnt. Das schneidet die Ecke nicht nur ab, es
  // verschiebt die ganze folgende Gerade um denselben Betrag: gemessen
  // verließen danach alle sieben Modelle die Fahrbahn, Pick-up und Muscle Car
  // um 3,5 Meter. Vorher war es ein einziges Modell mit 25 Zentimetern.
  for(const c of this.cars){if(c===p.car||c.type!=='traffic')continue;c.wait=Math.max(0,c.wait-dt);if(c.wait||c.health<=0)continue;const lang=vehicleTypes[c.model]?.laenge||4.5;const n=c.route.length;let a,b,vx,vz,len,t,schritte=0;do{a=c.route[(c.target-1+n)%n];b=c.route[c.target];vx=b.x-a.x;vz=b.z-a.z;len=Math.hypot(vx,vz)||1;t=((c.x-a.x)*vx+(c.z-a.z)*vz)/(len*len);if(t<1||Math.hypot(c.x-b.x,c.z-b.z)>12)break;c.target=(c.target+1)%n;}while(++schritte<n);t=Math.max(0,Math.min(1,t));const Lp=Math.min(6.5,2.5+lang*.55),uebrig=len*(1-t);let zx,zz;if(uebrig>=Lp){zx=a.x+vx*(t+Lp/len);zz=a.z+vz*(t+Lp/len);}else{const e=c.route[(c.target+1)%n],wx=e.x-b.x,wz=e.z-b.z,wl=Math.hypot(wx,wz)||1,u=(Lp-uebrig)/wl;zx=b.x+wx*u;zz=b.z+wz*u;}const ziel=Math.atan2(zx-c.x,zz-c.z);let ab=((ziel-c.yaw+Math.PI*3)%(Math.PI*2))-Math.PI;const rate=2.4*4.5/lang*dt;if(Math.abs(ab)>rate)ab=Math.sign(ab)*rate;c.yaw+=ab;if(!p.car&&this.spielerImWeg(c,p))continue;if(this.haeltVorAmpel(c))continue;if(this.wagenVoraus(c)||this.fussgaengerVoraus(c)){c.stau=(c.stau||0)+dt;continue;}c.stau=0;const rest=Math.abs(((ziel-c.yaw+Math.PI*3)%(Math.PI*2))-Math.PI);const tempo=c.speed*(1-.62*Math.min(1,rest/.7));c.x+=Math.sin(c.yaw)*tempo*dt;c.z+=Math.cos(c.yaw)*tempo*dt;}
  this.figurRasterBauen();
  for(const n of this.npcs){if(n.health<=0||n.state==='tanzend')continue;n.timer-=dt;if(n.report&&n.timer<=0){this.report(n.report.severity,n.report,n.report.incident);n.report=null;n.state='flüchtend';n.timer=9;}if(p.armed&&distance(n,p)<17&&this.sichtFrei(n,p)&&(n.state==='normal'||n.state==='sitzend')){n.state='aufmerksam';n.timer=1.4;}if(n.state==='aufmerksam'&&n.timer<=0){n.state='flüchtend';n.timer=6;}if(n.state==='erschrocken'&&n.timer<3)n.state='Polizei rufend';if(n.state==='filmend'||n.state==='Polizei rufend'||n.state==='erschrocken'){n.yaw=Math.atan2(p.x-n.x,p.z-n.z);continue;}// Wer sitzt, nimmt am Zustandswechsel oben teil — sonst bemerkt er eine
   // gezogene Waffe nicht —, bewegt sich aber nicht. Der erste Anlauf ließ ihn
   // ganz oben aus der Schleife springen; damit blieb er blind für alles.
   if(n.state==='sitzend')continue;
   if(n.state==='flüchtend'){n.yaw=Math.atan2(n.x-p.x,n.z-p.z);const [fx,fz]=this.schrittUmGehen(n,Math.sin(n.yaw)*3*dt,Math.cos(n.yaw)*3*dt);this.move(n,fx,fz,.3);if(n.timer<=0){n.state='normal';n.target=(n.target+1)%n.path.length;}}else{
    // Begleitung: derselbe Weg, derselbe Wegpunkt, nur um 85 Zentimeter quer
    // versetzt. Der erste Anlauf ließ die Begleitung der Position des anderen
    // folgen; von 42 Paaren blieb nach dreißig Sekunden eines zusammen, weil
    // ein einmal verlorener Anschluss nie wieder aufgeholt wird.
    // Auch den Weg übernehmen, nicht nur den Wegpunkt: updateRoutines ersetzt
    // morgens und abends den ganzen Weg der Figur. Wer nur den Index kopierte,
    // griff danach in die alte, kürzere Liste — "Cannot read properties of
    // undefined", und das Spiel blieb stehen.
    const fuehrer=n.imPaar?this._paare?.get(n.id):null;
    if(fuehrer&&fuehrer.health>0&&fuehrer.path?.length){n.path=fuehrer.path;n.target=fuehrer.target;}
    const roh=n.path[n.target]||n.path[0];
    if(!roh)continue;
    let dest=roh,tempo=1;
    if(fuehrer){
     const ri=Math.atan2(roh.x-n.x,roh.z-n.z);
     dest={x:roh.x+Math.cos(ri)*n.seite*.85,z:roh.z-Math.sin(ri)*n.seite*.85};
     // Anschluss halten. Derselbe Weg allein reicht nicht: eine Begleitung,
     // die an einer Kiste hängen bleibt, während der andere weitergeht, ist
     // danach für immer zwanzig Meter zurück. Ab drei Metern läuft sie
     // deshalb direkt auf den anderen zu und darf dabei schneller gehen —
     // gemessen blieben ohne diese Regel von 42 Paaren 20 bis 28 zusammen,
     // einzelne standen 32 Meter weit weg.
     const abstand=distance(n,fuehrer);
     // Hier stand ein Versuch, verlorene Paare ab zwölf Metern aufzulösen —
     // die Vermutung war, dass die geradlinige Aufholjagd die Begleitung an
     // den Überwegen vorbeiführt. Gemessen nach einer Panikphase hat das die
     // Quote um **null** Prozentpunkte bewegt (43,5 vor und nach der Regel),
     // also ist sie wieder draußen. Die Paare queren nach Panik quer verteilt
     // (Median 4,4 m, oberes Viertel 15 m), nicht knapp am Überweg vorbei.
     if(abstand>3){dest={x:fuehrer.x,z:fuehrer.z};tempo=Math.min(2.2,1+abstand*.12);}
    }
    const d=distance(n,dest);if(d<1&&!fuehrer){n.target=(n.target+1)%n.path.length;n.messZeit=0;n.messAbstand=undefined;}else if(d>=.35){n.yaw=Math.atan2(dest.x-n.x,dest.z-n.z);const v=n.pace*tempo*(this.weather==='rain'?1.5:1)*dt;const [sx,sz]=this.schrittUmGehen(n,Math.sin(n.yaw)*v,Math.cos(n.yaw)*v);this.move(n,sx,sz,.3);
    // Wer eine Sekunde lang nicht vorankommt, nimmt den nächsten Wegpunkt.
    //
    // Im Prüflauf standen Figuren zehn Sekunden auf derselben Stelle, obwohl
    // ihr nächstes Ziel 63 bis 266 Meter entfernt war und sie 1,2 bis 1,6 m/s
    // gehen: null bis 1,2 Meter zurückgelegt, wo zwölf hingehörten. Zwei
    // Ursachen kommen dafür infrage — Geometrie genau auf der Sichtlinie zum
    // Wegpunkt, oder ein Pulk, aus dem keine Richtung mehr frei ist. Diese
    // Regel hilft gegen beide, weil sie nicht an der Ursache ansetzt, sondern
    // am Ergebnis: Ziel unerreichbar, also das nächste nehmen. Eine Sekunde
    // ist lang genug, dass normales Warten in einer Schlange nicht zählt.
    // Fortschritt heißt, dem Ziel näher zu kommen — nicht, sich zu bewegen.
    // Die erste Fassung maß die zurückgelegte Strecke, und damit entging ihr
    // der häufigste Fall: an einer Wand entlangschrammen. move() zerlegt den
    // Schritt in x und z und lässt die freie Achse zu, also läuft die Figur
    // seitwärts weiter (gemessen 5,87 Meter in fünfzehn Sekunden) und gilt als
    // in Bewegung, während der Abstand zum Wegpunkt gleich bleibt. Im letzten
    // Prüflauf blieb genau so ein Paar übrig: 0,6 und 1,6 Meter Weg in zehn
    // Sekunden, beide mit Hindernis direkt voraus.
    //
    // Drei Sekunden ohne Annäherung, nicht eine: kurz hinter jemandem
    // herzugehen oder an einer Ampel zu warten ist kein Festsitzen.
    // Gemessen wird gegen das eigene Tempo, nicht gegen "irgendeine
    // Annäherung". Die erste Fassung galt als zufrieden, sobald der Abstand
    // um fünf Zentimeter fiel — und genau das tut eine Figur, die seitwärts an
    // einer Wand entlangschrammt, immer weiter: sie kommt dem Wegpunkt
    // millimeterweise näher und setzte den Zähler dabei ständig zurück. In
    // drei Sekunden gehört bei Tempo 1,4 ein Viertelmeter Annäherung zum
    // Mindesten (ein Fünftel der Strecke), sonst steht sie fest.
    const rest=distance(n,dest);
    n.messZeit=(n.messZeit||0)+dt*(n.grobFaktor||1);
    if(n.messZeit>=3){
     const gewonnen=(n.messAbstand??rest)-rest;
     // Grundtempo, nicht das im Grobtakt aufgeblasene: dort steht in n.pace
     // das Zwölffache, und mit dem als Erwartung galt fast jede ferne Figur
     // als festgefahren. Sie sprang dann dauernd zum nächsten Wegpunkt, und
     // die mittlere Strecke je Figur fiel von 9,75 auf 4,81 Meter.
     if(gewonnen<n.pace/(n.grobFaktor||1)*n.messZeit*.2){
      if(this.blocked(n,.3))this.befreie(n);
      else{
       const i=this.freierWegpunkt(n);
       if(i>=0){n.target=i;n.festRunden=0;}
       // Zweimal hintereinander ohne sichtbaren Wegpunkt heißt: die Stelle
       // selbst ist die Falle, nicht die Wahl des Ziels.
       else if((n.festRunden=(n.festRunden||0)+1)>1){this.freiSchieben(n,dest);n.festRunden=0;}
       else n.target=(n.target+1)%n.path.length;
      }
     }else n.festRunden=0;
     n.messZeit=0;n.messAbstand=undefined;
    }
    if(n.messAbstand===undefined)n.messAbstand=rest;}}}
  if(((this._entflecht=(this._entflecht||0)+1)%4)===0)this.entflechten();
  this.updatePolice(dt);this.eventTimer-=dt;if(this.eventTimer<=0){this.eventTimer=55;const c=this.cars.find(c=>c.type==='traffic'&&c!==p.car);if(c){c.wait=14;this.notify('Verkehrsfunk: Pannenfahrzeug auf der Harbor Avenue.');}}
  if(p.health<=0){p.health=0;this.paused=true;this.notify('Festgenommen. Starte den Auftrag erneut.');}
 }
 updatePolice(dt){const p=this.player;this.spotted=false;if(this.stars===0){for(const c of this.cops){if(c.active){c.route=route(c,places.station);c.target=0;c.active=false;}const target=c.route[c.target];if(target){if(distance(c,target)<1.5)c.target++;else{c.yaw=Math.atan2(target.x-c.x,target.z-c.z);this.move(c,Math.sin(c.yaw)*9*dt,Math.cos(c.yaw)*9*dt,1.2);}}}return;}this.dispatchTimer-=dt;const desired=Math.min(6,this.stars+1);if(this.dispatchTimer<=0&&this.cops.filter(c=>c.active&&c.health>0).length<desired){const c=this.cops.find(c=>!c.active&&c.health>0);if(c){c.active=true;c.repath=0;c.route=[];this.dispatchTimer=3;}}
  for(const c of this.cops){if(!c.active||c.health<=0)continue;const d=distance(c,p);const identified=p.car?this.description?.plate===p.car.id:this.description?.clothes===p.clothes;const sees=d<(p.sneak?23:48)&&this.sichtFrei(c,p)&&(identified||d<11||p.armed);if(sees){this.spotted=true;this.lastSeen={x:p.x,z:p.z};this.description={clothes:p.clothes,plate:p.car?.id||null};}c.repath-=dt;if(c.repath<=0){const target=sees?p:this.lastSeen;if(target){c.route=this.sichtFrei(c,target)?[{x:target.x,z:target.z}]:route(c,target);c.target=0;}c.repath=sees?1:4;}
   const target=c.route[c.target];if(target){const td=distance(c,target);if(td<2)c.target++;else{c.yaw=Math.atan2(target.x-c.x,target.z-c.z);const speed=sees&&d<7?0:10+this.stars*1.4;this.move(c,Math.sin(c.yaw)*speed*dt,Math.cos(c.yaw)*speed*dt,1.2);}}
   c.shot-=dt;if(sees&&d<23&&c.shot<=0){c.shot=1.5;if(this.stars>=2){p.health-=p.car?3:7;this.tracers.push({x:c.x,z:c.z,end:{x:p.x,z:p.z},life:.1});}else if(d<5){p.health-=10;this.notify('Polizei: Stehen bleiben!');}}
  }
  if(this.spotted)this.unseen=0;else this.unseen+=dt;if(this.unseen>18+this.stars*4&&this.lastSeen&&distance(p,this.lastSeen)>28){this.heat=0;this.stars=0;this.lastSeen=null;this.description=null;this.notify('Fahndung beendet. Du bist entkommen.');}
 }
}
