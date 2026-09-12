import {Simulation,places,distance,clamp} from './simulation.js';
import {Campaign} from './campaign.js';
import {ExpandedWorld} from './expanded-world.js';
import {locations,regions,roadSegments,vehicleTypes,weapons,regionAt,waterAt,bounds,groundAt} from './content.js';
import {Radio,SENDER} from './radio.js';
const $=id=>document.getElementById(id),sim=new Campaign();let world,started=false,last=0,yaw=Math.PI,pitch=.15,stick={x:0,y:0},drag=null,muted=false,audio=null,engine=null,engineGain=null,toastTime=0,hudTime=0,failedShown=false;
const keys=new Set();$('startBtn').disabled=true;
const debug={sichtbar:false,frames:0,fps:0,fenster:0,zeit:0};
// setPointerCapture wirft, wenn der Zeiger zwischen Ereignis und Handler
// schon losgelassen wurde. Das darf die Eingabe nicht abbrechen.
const fange=(el,id)=>{try{el.setPointerCapture(id);}catch{}};
window.LOWTIDE={sim,get world(){return world;},get frames(){return debug.frames;},debug,
 get radio(){return radio;},get sender(){return SENDER;},
 // Nur fürs Prüfen: setzt Figur und Kamera an eine feste Stelle.
 // hoehe>0 pausiert die Simulation und hebt die Kamera für Übersichtsbilder an.
 view(x,z,blick=yaw,neigung=pitch,hoehe=0){const p=sim.player;p.car=null;p.x=x;p.z=z;p.y=hoehe;p.vy=0;
  yaw=blick;pitch=neigung;p.yaw=blick;sim.paused=hoehe>0;if(world){world.freieKamera=false;world.nebelFaktor=1;world.kameraSofort=true;}},
 // Freie Kamera für Luftbilder: Standort, Blickziel, Simulation läuft weiter.
 luftbild(x,y,z,zx,zy,zz){if(!world)return;world.freieKamera=true;world.nebelFaktor=.06;
  world.camera.position.set(x,y,z);world.camera.lookAt(zx,zy,zz);
  world.camera.far=2600;world.camera.updateProjectionMatrix();
  sim.player.x=x;sim.player.z=z;}};
try{let saved=null;try{saved=localStorage.getItem('lowtide-v2');}catch{}if(saved){try{sim.restore(JSON.parse(saved));}catch(e){console.warn('Spielstand konnte nicht geladen werden',e);}}world=new ExpandedWorld($('game'),sim);$('loadState').textContent='Port Mercy ist bereit.';$('startBtn').disabled=false;}catch(error){$('loadState').textContent='3D konnte nicht starten. Verwende einen Browser mit WebGL 2 (Safari, Chrome oder Firefox).';console.error(error);}
let radio=null;
function initAudio(){try{audio=new (window.AudioContext||window.webkitAudioContext)();engine=audio.createOscillator();engine.type='sawtooth';engineGain=audio.createGain();engineGain.gain.value=0;engine.connect(engineGain).connect(audio.destination);engine.start();
 // Radio erst nach der Nutzergeste: vorher gibt es keinen Audiokontext.
 radio=new Radio(audio);radio.waehle(1);
}catch{muted=true;}}
function tone(freq,duration,volume=.04,type='sine'){if(!audio||muted)return;const o=audio.createOscillator(),g=audio.createGain();o.type=type;o.frequency.setValueAtTime(freq,audio.currentTime);o.frequency.exponentialRampToValueAtTime(Math.max(30,freq*.4),audio.currentTime+duration);g.gain.setValueAtTime(volume,audio.currentTime);g.gain.exponentialRampToValueAtTime(.001,audio.currentTime+duration);o.connect(g).connect(audio.destination);o.start();o.stop(audio.currentTime+duration);}
function toast(message){$('toast').textContent=message;$('toast').style.opacity='1';toastTime=5;}
function dialog(speaker,title,text,choices){sim.paused=true;keys.clear();stick={x:0,y:0};$('speaker').textContent=speaker;$('dialogTitle').textContent=title;$('dialogText').textContent=text;$('choices').replaceChildren();for(const [label,fn] of choices){const b=document.createElement('button');b.textContent=label;b.onclick=()=>{$('dialog').close();sim.paused=false;fn();};$('choices').append(b);}$('dialog').showModal();}
function interact(){const a=sim.action();if(a?.startsWith('place:')){showPlace(a.split(':')[1]);return;}if(a==='chapter2'){dialog('MARA QUINN','Ein zweiter Name.','Die Ratsakte führt zu Nadia, einer Zeugin auf Isla Serena. Mara muss zuerst das Relais abschalten, Eli kann danach mit seiner Karte ins Stadtarchiv. Wache und Kamera reagieren auf auffälliges Verhalten.',[['Auftrag annehmen',()=>{sim.campaign.stage=1;toast('Tab / Figuren: Wechsel zu Mara. Relais auf der Karte.');}],['Später',()=>{}]]);return;}if(a==='finale'){dialog('ELI & MARA','Alles auf den Tisch.','Nadia ist sicher. Ihr habt nun die vollständige Akte. Veröffentlichung beendet Calderas Einfluss; ein Deal kauft euch Freiheit und lässt die Verantwortlichen davonkommen.',[['Alles veröffentlichen',()=>{sim.campaign.stage=4;sim.relationship=Math.min(100,sim.relationship+20);sim.award(1800);saveGame();toast('Port Mercy kennt die Wahrheit. Kampagne abgeschlossen.');}],['Einen Deal schließen',()=>{sim.campaign.stage=4;sim.relationship=Math.max(0,sim.relationship-25);sim.award(3000);saveGame();toast('Der Deal ist durch. Kampagne abgeschlossen.');}]]);return;}if(a==='mara')dialog('MARA QUINN','Ein einfacher Auftrag.','Caldera schickt nachts Tanker ohne Ladungspapiere raus. Im Lager liegt eine Festplatte. Hol sie mir. Du kannst den Wachmann bezahlen, die Sicherung an der Ostwand ziehen oder den Eingang aufbrechen.',['accept'].map(()=>['Ich hole die Festplatte.',()=>sim.choose('accept')]).concat([['Noch nicht.',()=>{}]]));if(a==='guard')dialog('CALDERA · NACHTWACHE','Hier gibt es nichts zu sehen.','Der Wachmann mustert dich. Hinter ihm läuft eine Überwachungskamera. An der rechten Außenwand findest du den Stromkasten.',[['$150 anbieten — der Wachmann lässt dich durch',()=>sim.choose('bribe')],['Schloss aufbrechen — löst Alarm aus',()=>sim.choose('force')],['Zurück. Ich suche die Sicherung.',()=>{}]]);if(a==='ending')dialog('MARA QUINN','Was soll mit der Wahrheit passieren?','Die Daten belegen: Caldera verklappt Chemikalien vor der Küste. Ein Stadtrat kassiert mit. Mara will die Beweise veröffentlichen. Caldera bietet dir Geld fürs Schweigen.',[['Veröffentlichen · $800 · Maras Vertrauen',()=>finish('leak')],['An Caldera verkaufen · $2.000 · Mara verlieren',()=>finish('sell')]]);}
function finish(choice){sim.choose(choice);dialog('AUFTRAG ABGESCHLOSSEN',choice==='leak'?'Die Flut bringt alles zurück.':'Der Preis des Schweigens.',choice==='leak'?'Die Presse veröffentlicht die Dokumente. Der Hafen steht still. Mara schickt dir eine Nachricht: „Das war erst der Anfang.“ Du kannst Port Mercy weiter erkunden.':'Caldera überweist das Geld. Maras Nummer ist nicht mehr erreichbar. Draußen am Hafen gehen die Lichter wieder an. Du kannst Port Mercy weiter erkunden.',[['Zurück in die Stadt',()=>{}],['Nächster Auftrag',()=>{sim.campaign.stage=1;toast('Mara muss das Relais abschalten. Tab / Figuren zum Wechseln.');}]]);}
function fire(){if(sim.paused)return;const before=sim.shots;sim.shoot();if(sim.shots>before)tone(125,.14,.11,'sawtooth');}
function pause(){if(!started||$('dialog').open||$('bigMap').open)return;$('phone').hidden=true;sim.paused=true;keys.clear();stick={x:0,y:0};$('pause').showModal();}
function resume(){if(sim.player.health<=0)return;$('pause').close();sim.paused=false;}
function map(){if(!started||$('dialog').open||$('pause').open||phoneOffen())return;sim.paused=true;keys.clear();drawMap($('fullMap'),true);$('bigMap').showModal();}
function keyAction(key){if(!started)return;if(key==='escape'){if($('pause').open)resume();else pause();return;}if(key==='p'){phoneUmschalten();return;}if(sim.paused)return;if(key==='e')interact();if(key==='q'){if(!sim.player.car){sim.player.armed=!sim.player.armed;tone(320,.06);}}if(key==='r')sim.reload();if(key==='fire')fire();if(key==='m')map();if(key==='tab'){sim.switchCharacter();yaw=sim.player.yaw;}if(key==='x')sim.cycleWeapon();if(key==='f')sim.melee();if(key==='g')sim.grapple();if(key==='v')sim.cover();if(key==='alt')sim.dodge();if(key===' '&&!sim.player.car)sim.jump();if(key==='h')showActions();if(key==='n')senderWechseln();if(key==='f3'){debug.sichtbar=!debug.sichtbar;$('debug').hidden=!debug.sichtbar;}}
$('startBtn').onclick=()=>{started=true;sim.paused=false;document.body.classList.add('playing');initAudio();toast('Sprich mit Mara am goldenen Marker. E / Aktion.');};$('pauseBtn').onclick=pause;$('resume').onclick=resume;$('restartBtn').onclick=()=>{$('pause').close();dialog('SPIELSTAND','Neu beginnen?','Dadurch wird der lokale Spielstand gelöscht.',[['Neues Spiel',()=>{localStorage.removeItem('lowtide-v2');location.reload();}],['Abbrechen',()=>{}]]);};$('mapBtn').onclick=map;$('closeMap').onclick=()=>{$('bigMap').close();sim.paused=false;};$('soundBtn').onclick=()=>{muted=!muted;$('soundBtn').textContent='Ton: '+(muted?'aus':'an');};let low=false;$('qualityBtn').onclick=()=>{low=!low;world.renderer.setPixelRatio(low?1:Math.min(devicePixelRatio,1.5));world.renderer.shadowMap.enabled=!low;world.resize();$('qualityBtn').textContent='Grafik: '+(low?'sparsam':'normal');};
for(const id of ['dialog','pause','bigMap'])$(id).addEventListener('cancel',e=>{e.preventDefault();if(id==='pause')resume();else if(id==='bigMap'){$(id).close();sim.paused=false;}});
window.addEventListener('keydown',e=>{if([' ','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Tab','F3','Escape'].includes(e.key))e.preventDefault();const k=e.key.toLowerCase();if(!e.repeat)keyAction(k);keys.add(k);});window.addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));window.addEventListener('blur',()=>{keys.clear();stick={x:0,y:0};if(started&&!sim.paused)pause();});document.addEventListener('visibilitychange',()=>{if(document.hidden&&started&&!sim.paused)pause();});window.addEventListener('resize',()=>world?.resize());
$('game').addEventListener('contextmenu',e=>e.preventDefault());$('game').addEventListener('pointerdown',e=>{if(!started||sim.paused)return;drag={id:e.pointerId,x:e.clientX,y:e.clientY,startX:e.clientX,startY:e.clientY,time:performance.now()};fange($('game'),e.pointerId);});$('game').addEventListener('pointermove',e=>{if(!drag||drag.id!==e.pointerId)return;yaw-=(e.clientX-drag.x)*.006;pitch=clamp(pitch+(e.clientY-drag.y)*.003,-.2,.8);drag.x=e.clientX;drag.y=e.clientY;});$('game').addEventListener('pointerup',e=>{if(drag&&Math.hypot(e.clientX-drag.startX,e.clientY-drag.startY)<6&&performance.now()-drag.time<300)fire();drag=null;});$('game').addEventListener('pointercancel',()=>drag=null);
let stickId=null;function moveStick(e){const r=$('stick').getBoundingClientRect(),x=e.clientX-r.left-r.width/2,y=e.clientY-r.top-r.height/2,len=Math.max(40,Math.hypot(x,y));stick={x:x/len,y:y/len};$('knob').style.transform=`translate(${stick.x*34}px,${stick.y*34}px)`;}$('stick').onpointerdown=e=>{stickId=e.pointerId;fange($('stick'),e.pointerId);moveStick(e);};$('stick').onpointermove=e=>{if(e.pointerId===stickId)moveStick(e);};const releaseStick=()=>{stickId=null;stick={x:0,y:0};$('knob').style.transform='';};$('stick').onpointerup=releaseStick;$('stick').onpointercancel=releaseStick;for(const b of document.querySelectorAll('[data-key]')){b.onpointerdown=e=>{e.preventDefault();fange(b,e.pointerId);const key=b.dataset.key;keys.add(key);keyAction(key);};b.onpointerup=()=>keys.delete(b.dataset.key);b.onpointercancel=()=>keys.delete(b.dataset.key);}
// Karte von Solvara.
// Die statische Ebene — Wasser, Gelände, Straßen, Gebäude — wird einmal für
// die ganze Welt in ein Offscreen-Canvas gezeichnet. Vorher lief jede
// Minimap-Aktualisierung, achtmal pro Sekunde, über sämtliche
// Kollisionskörper und zeichnete jede Straße neu.
const KARTE_PX_PRO_M=1.5;
let karteStatisch=null;

function karteBauen(){
 const w=Math.round((bounds.right-bounds.left)*KARTE_PX_PRO_M);
 const h=Math.round((bounds.bottom-bounds.top)*KARTE_PX_PRO_M);
 const c=document.createElement('canvas');c.width=w;c.height=h;
 const g=c.getContext('2d');
 const X=x=>(x-bounds.left)*KARTE_PX_PRO_M,Z=z=>(z-bounds.top)*KARTE_PX_PRO_M,S=m=>m*KARTE_PX_PRO_M;

 g.fillStyle='#3f4a35';g.fillRect(0,0,w,h);
 // Wasser aus derselben Funktion, die auch das Gelände formt — so kann die
 // Küstenlinie auf der Karte nicht von der in der Welt abweichen.
 const raster=4;
 g.fillStyle='#17414d';
 for(let x=bounds.left;x<bounds.right;x+=raster)for(let z=bounds.top;z<bounds.bottom;z+=raster)
  if(waterAt(x+raster/2,z+raster/2))g.fillRect(X(x),Z(z),S(raster)+1,S(raster)+1);
 // Flachwassersaum entlang der Küste.
 g.fillStyle='#2a6a70';
 for(let z=bounds.top;z<bounds.bottom;z+=raster)
  if(waterAt(122,z))g.fillRect(X(119),Z(z),S(9),S(raster)+1);

 // Geländezonen: Hügelwald, Strand, Felder, Rollbahn.
 // Bewaldeter Hang: alles, was messbar über der Ebene liegt.
 for(let x=bounds.left;x<-370;x+=raster)for(let z=bounds.top;z<-235;z+=raster){
  const hoehe=groundAt(x+raster/2,z+raster/2);
  if(hoehe<=.3)continue;
  g.fillStyle=hoehe>22?'#22351f':hoehe>7?'#2b4128':'#354c31';
  g.fillRect(X(x),Z(z),S(raster)+1,S(raster)+1);
 }
 g.fillStyle='#9c8a63';g.fillRect(X(94),Z(130),S(25),S(300));
 g.fillStyle='#66714f';g.fillRect(X(235),Z(150),S(125),S(145));
 g.fillStyle='#9c8a63';g.fillRect(X(236),Z(150),S(123),S(15));
 g.fillRect(X(236),Z(281),S(123),S(14));
 for(const [fx,fz,fw,fd] of [[-443,-276,86,56],[-394,-400,72,58],[-457,-284,46,62],[-393,-243,42,36]])
  {g.fillStyle='#5c6a3c';g.fillRect(X(fx),Z(fz),S(fw),S(fd));}
 g.fillStyle='#39424a';g.fillRect(X(-328),Z(238),S(26),S(154));

 // Straßen mit Hierarchie: dunkle Einfassung, hellerer Kern.
 const strassen=(farbe,zugabe)=>{g.fillStyle=farbe;for(const r of roadSegments){
  const bx=Math.min(r.x1,r.x2)-r.w/2-zugabe,bz=Math.min(r.z1,r.z2)-r.w/2-zugabe;
  g.fillRect(X(bx),Z(bz),S(Math.abs(r.x2-r.x1)+r.w+zugabe*2),S(Math.abs(r.z2-r.z1)+r.w+zugabe*2));}};
 strassen('#23292c',1.6);
 strassen('#5d666a',0);
 g.fillStyle='#4b5457';
 for(const z of [-260,-305,-350,-395])g.fillRect(X(-130),Z(z-4),S(210),S(8));

 // Bebautes Gebiet: jedes Gebäude stempelt einen weichen Hof, die Überlagerung
 // ergibt von selbst die Silhouette der Stadt.
 g.globalAlpha=.10;g.fillStyle='#b9c2ae';
 for(const b of sim.solids){
  if(!['building','newbuilding','house','warehouse'].includes(b.kind))continue;
  g.fillRect(X(b.x-b.w/2-26),Z(b.z-b.d/2-26),S(b.w+52),S(b.d+52));
 }
 g.globalAlpha=1;
 // Damm nach Isla Serena.
 g.fillStyle='#5d666a';g.fillRect(X(119),Z(194),S(140),S(12));
 // Gebäude.
 g.fillStyle='#8f9a92';
 for(const b of sim.solids){
  if(!['building','newbuilding','house','warehouse','room'].includes(b.kind))continue;
  g.fillRect(X(b.x-b.w/2),Z(b.z-b.d/2),Math.max(2,S(b.w)),Math.max(2,S(b.d)));
 }
 karteStatisch={canvas:c,X,Z};
}

function drawMap(canvas,full=false){
 if(!karteStatisch)karteBauen();
 const ctx=canvas.getContext('2d'),w=canvas.width,p=sim.player,K=karteStatisch;
 const spanne=full?Math.max(bounds.right-bounds.left,bounds.bottom-bounds.top)+30:180;
 const cx=full?(bounds.left+bounds.right)/2:p.x,cz=full?(bounds.top+bounds.bottom)/2:p.z;
 const px=w/spanne,tx=x=>(x-cx)*px+w/2,tz=z=>(z-cz)*px+w/2;
 ctx.fillStyle='#0d1b22';ctx.fillRect(0,0,w,w);
 ctx.drawImage(K.canvas,K.X(cx-spanne/2),K.Z(cz-spanne/2),spanne*KARTE_PX_PRO_M,spanne*KARTE_PX_PRO_M,0,0,w,w);

 const punkt=(x,z,r,farbe)=>{ctx.beginPath();ctx.arc(tx(x),tz(z),r,0,Math.PI*2);ctx.fillStyle=farbe;ctx.fill();};
 const beschriftung=(text,x,y,farbe,groesse)=>{
  ctx.font='bold '+groesse+'px Arial';ctx.lineWidth=3;ctx.lineJoin='round';
  ctx.strokeStyle='rgba(6,14,18,.85)';ctx.strokeText(text,x,y);ctx.fillStyle=farbe;ctx.fillText(text,x,y);
 };
 if(sim.lastSeen){ctx.beginPath();ctx.arc(tx(sim.lastSeen.x),tz(sim.lastSeen.z),35*px,0,Math.PI*2);
  ctx.fillStyle='#d9768133';ctx.fill();ctx.strokeStyle='#d97681aa';ctx.lineWidth=1.5;ctx.stroke();}
 for(const c of sim.cars)if(c.type!=='parked')punkt(c.x,c.z,full?1.8:2.5,'#83abbe');
 for(const c of sim.cops)if(c.active)punkt(c.x,c.z,3,'#ef7b76');
 if(full){
  ctx.textAlign='left';
  for(const [id,l] of Object.entries(locations)){punkt(l.x,l.z,2.6,'#91d9bb');beschriftung(l.name,tx(l.x)+5,tz(l.z)+3,'#cfe4d2',10);}
  for(const r of regions)beschriftung(r.name,tx(r.x)-24,tz(r.z)-13,'#e8dcae',11);
  // Maßstab.
  const meter=200,laenge=meter*px;
  ctx.fillStyle='#e0e6dc';ctx.fillRect(w-laenge-18,w-24,laenge,3);
  for(const e of [0,laenge])ctx.fillRect(w-laenge-18+e,w-29,2,13);
  ctx.textAlign='center';beschriftung(meter+' m',w-laenge/2-18,w-32,'#e0e6dc',10);
  ctx.textAlign='left';
 }
 const goal=sim.objective();punkt(goal.x,goal.z,full?4:5,'#efca88');
 const andere=sim.characters[1-sim.active];punkt(andere.x,andere.z,full?3:4,'#c3a5d8');
 ctx.save();ctx.translate(tx(p.x),tz(p.z));ctx.rotate(-p.yaw);
 ctx.beginPath();ctx.moveTo(0,8);ctx.lineTo(-5.5,-5.5);ctx.lineTo(0,-2.5);ctx.lineTo(5.5,-5.5);ctx.closePath();
 ctx.fillStyle='#a2f0db';ctx.fill();ctx.strokeStyle='#0d1b22';ctx.lineWidth=1.2;ctx.stroke();ctx.restore();
 ctx.textAlign='left';beschriftung('N',w-16,16,'#d0dcd1',11);
}
// Telefon. Karte, Nachrichten, TIDELINE, Bank, Wetter, Kamera, Kontakte und
// Aufträge — die Apps lesen den Spielzustand, sie halten keinen eigenen.
const APPS = [
 ['karte', '▣', 'KARTE'], ['nachrichten', '✉', 'NACHRICHTEN'], ['tideline', '◍', 'TIDELINE'],
 ['bank', '$', 'BANK'], ['wetter', '☁', 'WETTER'], ['kamera', '◉', 'KAMERA'],
 ['kontakte', '☏', 'KONTAKTE'], ['auftraege', '★', 'AUFTRÄGE'], ['galerie', '▤', 'GALERIE'],
 ['radio', '◎', 'RADIO']
];
let phoneApp = 'home';

function phoneOffen(){return !$('phone').hidden;}
function phoneUmschalten(){
 if(!started||$('dialog').open||$('pause').open||$('bigMap').open)return;
 // Beim Schließen darf die Pause nicht aufgehoben werden, wenn die Figur
 // am Boden liegt — sonst läuft die Welt hinter dem Festnahme-Dialog weiter.
 if(phoneOffen()){$('phone').hidden=true;sim.paused=sim.player.health<=0;return;}
 if(sim.player.health<=0)return;
 sim.paused=true;keys.clear();stick={x:0,y:0};phoneApp='home';
 $('phone').hidden=false;phoneZeichnen();
}
const uhrzeit=h=>String(Math.floor(h)).padStart(2,'0')+':'+String(Math.floor(h%1*60)).padStart(2,'0');

function phoneZeichnen(){
 const inhalt=$('phoneInhalt'),p=sim.player;
 $('phoneUhr').textContent=uhrzeit(sim.hour);
 $('phoneNetz').textContent=regionAt(p).slice(0,18);
 $('phoneAkku').textContent=Math.max(12,100-Math.floor(sim.time/90))+'%';
 inhalt.replaceChildren();
 const el=(tag,klasse,text)=>{const e=document.createElement(tag);if(klasse)e.className=klasse;if(text!=null)e.textContent=text;inhalt.append(e);return e;};
 const titel=t=>el('h4',null,t);
 const zeile=(wer,text,wann,klasse)=>{
  const z=el('div','zeile');
  if(wann){const w=document.createElement('span');w.className='wann';w.textContent=wann;z.append(w);}
  if(wer){const a=document.createElement('div');a.className='wer';a.textContent=wer;z.append(a);}
  const b=document.createElement('div');if(klasse)b.className=klasse;b.textContent=text;z.append(b);
  return z;
 };

 if(phoneApp==='home'){
  const gitter=el('div');gitter.id='phoneKacheln';
  for(const [id,zeichen,name] of APPS){
   const b=document.createElement('button');
   const i=document.createElement('b');i.textContent=zeichen;
   b.append(i,document.createTextNode(name));
   b.onclick=()=>{phoneApp=id;phoneZeichnen();};
   gitter.append(b);
  }
  const fuss=el('div','zeile');
  fuss.textContent=p.name+' · $ '+p.money.toLocaleString('de-DE')+' · Vertrauen '+sim.relationship+'/100';
  return;
 }

 if(phoneApp==='karte'){
  titel('PORT MERCY');
  const c=document.createElement('canvas');c.width=c.height=520;inhalt.append(c);
  drawMap(c,true);
  el('div','zeile','Türkis: du · Gold: Ziel · Rot: Polizei · Violett: zweite Figur');
  return;
 }

 if(phoneApp==='nachrichten'){
  titel('NACHRICHTEN');
  const stufe=sim.campaign.stage;
  const verlauf=[['MARA','Der Umschlag liegt am Pier. Komm allein.']];
  if(sim.mission>=1)verlauf.push(['MARA','Caldera-Lager. Wachmann, Kamera, Sicherung an der Ostwand. Deine Wahl.']);
  if(sim.mission>=3)verlauf.push(['MARA','Du hast sie. Bootshaus, so schnell du kannst.']);
  if(stufe>=1)verlauf.push(['MARA','Das Relais nehme ich. Du kommst mit deiner Karte ins Archiv.']);
  if(sim.campaign.relay)verlauf.push(['MARA','Signal ist aus. Jetzt du.']);
  if(stufe>=2)verlauf.push(['ELI','Nadia sitzt auf Isla Serena fest. Ich brauche ein Auto.']);
  if(sim.campaign.witness)verlauf.push(['NADIA','Ich steige nur aus, wenn keine Streife hinter uns ist.']);
  if(stufe>=3)verlauf.push(['MARA','Alles liegt auf dem Tisch. Entscheide zu Hause.']);
  if(stufe>=4)verlauf.push(['MARA',sim.relationship>=50?'Du hast das Richtige getan. Das war erst der Anfang.':'Ruf mich nicht mehr an.']);
  if(sim.stars)verlauf.push(['UNBEKANNT','Halt dich raus, bis die Streifen weg sind.']);
  for(const [wer,text] of verlauf.slice(-9))zeile(wer,text);
  return;
 }

 if(phoneApp==='tideline'){
  titel('TIDELINE');
  const feed=sim.feed||[];
  if(!feed.length)el('div','zeile','Noch nichts los in Port Mercy.');
  for(const e of feed.slice(0,14))zeile(e.autor,e.text,uhrzeit(e.stunde));
  return;
 }

 if(phoneApp==='bank'){
  titel('SOLVARA FIRST');
  zeile(p.name,'Kontostand $ '+p.money.toLocaleString('de-DE'));
  zeile(null,'Verdient in dieser Sitzung: $ '+(sim.moneyEarned||0).toLocaleString('de-DE'));
  const konto=sim.konto||[];
  if(!konto.length)el('div','zeile','Keine Bewegungen.');
  for(const b of konto.slice(0,12))
   zeile(null,b.text+'   '+(b.betrag>0?'+':'−')+' $ '+Math.abs(b.betrag).toLocaleString('de-DE'),
    uhrzeit(b.stunde),b.betrag>0?'plus':'minus');
  return;
 }

 if(phoneApp==='wetter'){
  titel('SOLVARA WETTER');
  const namen={clear:'Klar',rain:'Regen',fog:'Nebel',storm:'Gewitter'};
  const folge=['clear','rain','fog','storm'];
  zeile('JETZT',namen[sim.weather]+' · '+regionAt(p),uhrzeit(sim.hour));
  for(let i=1;i<=3;i++){
   const k=folge[((sim.weatherIndex||0)+i)%4];
   zeile(null,namen[k],uhrzeit((sim.hour+i*1.4)%24));
  }
  zeile(null,sim.weather==='rain'||sim.weather==='storm'
   ?'Nasse Fahrbahn. Weniger Grip, längerer Bremsweg.'
   :'Trockene Fahrbahn.');
  return;
 }

 if(phoneApp==='kamera'){
  titel('KAMERA');
  const b=document.createElement('button');b.textContent='Aufnehmen';b.style.width='100%';
  b.onclick=()=>{foto();phoneApp='galerie';phoneZeichnen();};
  inhalt.append(b);
  el('div','zeile','Die Aufnahme zeigt den Ausschnitt hinter dem Telefon. Fotos bleiben in dieser Sitzung.');
  return;
 }

 if(phoneApp==='galerie'){
  titel('GALERIE');
  const fotos=sim.fotos||[];
  if(!fotos.length)el('div','zeile','Noch keine Aufnahmen.');
  fotos.slice(0,6).forEach((f,i)=>{
   const z=el('div','zeile');
   const bild=document.createElement('img');bild.src=f.daten;bild.alt='Aufnahme '+(i+1);z.append(bild);
   const u=document.createElement('div');u.className='wer';u.textContent=f.ort+' · '+uhrzeit(f.stunde);z.append(u);
   if(!f.gepostet){
    const b=document.createElement('button');b.textContent='Auf TIDELINE stellen';b.style.marginTop='6px';
    b.onclick=()=>{f.gepostet=true;sim.post('@'+sim.player.name.split(' ')[0].toLowerCase(),
     'Aufnahme aus '+f.ort+'.');phoneApp='tideline';phoneZeichnen();};
    z.append(b);
   }
  });
  return;
 }

 if(phoneApp==='radio'){
  titel('AUTORADIO');
  if(!radio){el('div','zeile','Ton ist aus.');return;}
  el('div','zeile','Zu hören im Fahrzeug. Taste N schaltet weiter.');
  SENDER.forEach((s,i)=>{
   const z=zeile(s.name,s.kennung||'Stille');
   if(i===radio.index){z.style.borderLeft='2px solid #e5bd71';z.style.paddingLeft='8px';}
   const b=document.createElement('button');b.textContent=i===radio.index?'Läuft':'Einschalten';
   b.style.marginTop='6px';b.disabled=i===radio.index;
   b.onclick=()=>{radio.waehle(i);phoneZeichnen();};
   z.append(b);
  });
  if(radio.sender.wort){
   const beitrag=(sim.feed||[])[0];
   zeile('IM PROGRAMM',beitrag?beitrag.autor+': '+beitrag.text:'Verkehrsfunk und Lokales.');
  }
  return;
 }
 if(phoneApp==='kontakte'){
  titel('KONTAKTE');
  const andere=sim.characters[1-sim.active];
  const eintrag=(name,hinweis,fn)=>{
   const z=zeile(name,hinweis);
   const b=document.createElement('button');b.textContent='Anrufen';b.style.marginTop='6px';b.onclick=fn;z.append(b);
  };
  eintrag(andere.name,'Übernehmen und weiterspielen',()=>{
   if(sim.switchCharacter())yaw=sim.player.yaw;phoneZeichnen();});
  eintrag('PIKE CUSTOMS','Werkstatt am West Loop markieren',()=>{
   toast('Pike Customs auf der Karte markiert.');phoneApp='karte';phoneZeichnen();});
  eintrag('NORA’S DINER','Essen und Ausruhen',()=>{
   toast('Nora’s Diner: '+Math.round(distance(sim.player,locations.diner))+' m entfernt.');});
  eintrag('LEITSTELLE','Nur im Notfall',()=>{
   toast(sim.stars?'Die suchen dich bereits.':'Aufgelegt.');});
  return;
 }

 if(phoneApp==='auftraege'){
  titel('AUFTRÄGE');
  zeile('AKTUELL',sim.missionTitle());
  const ziel=sim.objective();
  zeile(null,'Entfernung: '+Math.round(distance(p,ziel))+' m');
  zeile(null,'Kapitel: '+(sim.campaign.stage?'02–03 · Die Ratsakte':'01 · Die schwarze Flut'));
  if(sim.activity)zeile('AKTIVITÄT',sim.activity.label);
  const hs=sim.highScores||{};
  for(const [k,v] of Object.entries(hs))
   zeile(null,{race:'West Loop Bestzeit',gym:'Training',basketball:'Basketball',club:'Undertow'}[k]||k+': '
    +(k==='race'?v.toFixed(1)+' s':v+'/5'));
  return;
 }
}

// Ein Bild wird auf Anforderung neu gerendert und sofort ausgelesen; ohne das
// wäre der Zeichenpuffer nach dem letzten Frame bereits verworfen.
function foto(){
 try{
  world.renderer.render(world.scene,world.camera);
  const daten=world.renderer.domElement.toDataURL('image/jpeg',.68);
  (sim.fotos||=[]).unshift({daten,ort:regionAt(sim.player),stunde:sim.hour,gepostet:false});
  if(sim.fotos.length>6)sim.fotos.pop();
 }catch(e){toast('Aufnahme nicht möglich.');console.warn(e);}
}

$('phoneBtn').onclick=phoneUmschalten;
$('phoneZu').onclick=phoneUmschalten;
$('phoneHome').onclick=()=>{phoneApp='home';phoneZeichnen();};

function updateHUD(){const p=sim.player;$('clock').textContent=String(Math.floor(sim.hour)).padStart(2,'0')+':'+String(Math.floor(sim.hour%1*60)).padStart(2,'0')+' · '+({clear:'Klar',rain:'Regen',fog:'Nebel',storm:'Gewitter'}[sim.weather]);$('district').textContent=regionAt(p);$('actor').textContent=p.name;$('stars').textContent='★'.repeat(sim.stars)+'☆'.repeat(6-sim.stars);$('police').textContent=sim.stars?(sim.spotted?'Sichtkontakt':'Suche · '+Math.floor(sim.unseen)+' s außer Sicht'):'Keine Fahndung';$('health').style.width=p.health+'%';$('money').textContent='$ '+p.money.toLocaleString('de-DE');$('equipment').textContent=p.car?vehicleTypes[p.car.model].name+' · '+Math.ceil(p.car.health)+'% · Tank '+Math.ceil(p.car.fuel)+'%'+(radio&&radio.sender.bpm!==0?' · '+radio.sender.name:radio&&radio.sender.wort?' · '+radio.sender.name:''):p.armed?weapons[p.weapon].name+' · '+p.ammo+' / '+p.reserve:p.cover?'In Deckung':p.sneak?'Schleichend':'Ausdauer '+Math.round(p.stamina)+'%';$('speed').textContent=p.car?Math.round(Math.abs(p.car.speed)*3.6)+' km/h'+(p.car.alt>2?' · '+Math.round(p.car.alt)+' m':''):p.y<-.5?'Luft '+Math.round(p.air)+'%':'';$('reticle').style.display=p.armed?'block':'none';$('goal').textContent=sim.missionTitle();$('subgoal').textContent=sim.stars?'Verliere Sichtkontakt und verlasse das Suchgebiet.':sim.campaign.stage?'Goldener Marker auf der Karte · Tab / Figuren zum Wechseln':sim.mission===4?'Mara am Bootshaus oder direkt den nächsten Auftrag starten.':'E / Aktion am goldenen Marker';$('chapter').textContent=sim.campaign.stage?'02–03 / DIE RATS AKTE'.replace('RATS AKTE','RATSAKTE'):'01 / DIE SCHWARZE FLUT';let prompt='';if(sim.unlock)prompt='E / Aktion halten · '+Math.ceil(sim.unlock.remaining)+' s';else if(sim.activity)prompt=sim.activity.kind==='race'?'Kontrollpunkt '+(sim.activity.index+1)+' / '+sim.activity.points.length:sim.activity.kind==='diving'?'C halten: tauchen · E beim Wrackfund':'E / Aktion im richtigen Moment';else if(p.car)prompt='E aussteigen · H / Mehr für Werkstatt & Aktivitäten';else{const l=Object.values(locations).find(l=>distance(l,p)<4.5);if(l)prompt='E / Aktion · '+l.name;else if(distance(p,sim.objective())<5)prompt='E / Aktion · Missionsziel';else if(sim.cars.some(c=>distance(c,p)<5&&c.health>0))prompt='E / Aktion · Einsteigen (bei Schloss halten)';}$('prompt').textContent=prompt;const a=sim.activity;$('activityHud').hidden=!a;if(a){$('activityName').textContent=a.label;$('activityPointer').style.left=((a.phase||0)*100)+'%';$('activityScore').textContent=a.kind==='race'?a.time.toFixed(1)+' s':a.kind==='fishing'?(a.time>=a.biteAt?'BISS! JETZT DRÜCKEN':'Warte auf den Biss …'):a.kind==='diving'?'Zum Wrack schwimmen und abtauchen':(a.score||0)+' Treffer / '+(a.round||0)+' Versuche';$('timingBar').hidden=['race','diving','fishing'].includes(a.kind);}drawMap($('map'));}
function messwerte(dt){debug.frames++;debug.fenster++;debug.zeit+=dt;if(debug.zeit>=.5){debug.fps=debug.fenster/debug.zeit;debug.fenster=0;debug.zeit=0;}if(!debug.sichtbar||!world)return;const info=world.renderer.info;
 $('debug').textContent=['FPS          '+debug.fps.toFixed(0),'Draw Calls   '+info.render.calls,'Dreiecke     '+info.render.triangles.toLocaleString('de-DE'),'Geometrien   '+info.memory.geometries,'Texturen     '+info.memory.textures,'NPCs         '+sim.npcs.length,'Fahrzeuge    '+sim.cars.length,'Polizei aktiv '+sim.cops.filter(c=>c.active).length,'Uhrzeit      '+sim.hour.toFixed(2),'Wetter       '+sim.weather,'Position     '+Math.round(sim.player.x)+' / '+Math.round(sim.player.z)].join('\n');}
function frame(ms){const dt=Math.min(.05,(ms-last)/1000||.016);last=ms;messwerte(dt);if(world){if(started&&!sim.paused){if(keys.has('arrowleft'))yaw+=dt*1.8;if(keys.has('arrowright'))yaw-=dt*1.8;const forward=(keys.has('w')||keys.has('arrowup')?1:0)-(keys.has('s')||keys.has('arrowdown')?1:0)-stick.y,turn=(keys.has('d')?1:0)-(keys.has('a')?1:0)+stick.x;sim.tick(dt,{forward:clamp(forward,-1,1),turn:clamp(turn,-1,1),yaw,sprint:keys.has('shift'),sneak:keys.has('c'),brake:keys.has(' '),jump:keys.has(' '),interact:keys.has('e')});if(sim.player.car&&!drag)yaw+=Math.atan2(Math.sin(sim.player.yaw-yaw),Math.cos(sim.player.yaw-yaw))*Math.min(1,dt*3);if(keys.has('fire'))fire();if(radio)radio.lautstaerke(!muted&&sim.player.car&&sim.player.car.health>0?.6:0);
     if(engineGain){engineGain.gain.setTargetAtTime(!muted&&sim.player.car?.health>0?.017:0,audio.currentTime,.1);engine.frequency.setTargetAtTime((vehicleTypes[sim.player.car?.model]?.sound||45)+Math.abs(sim.player.car?.speed||0)*3,audio.currentTime,.1);}}else{if(engineGain)engineGain.gain.setTargetAtTime(0,audio.currentTime,.1);if(radio)radio.lautstaerke(0);}
  radio?.tick();world.update(dt,yaw,pitch,started);if(sim.events.length)toast(sim.events.pop()),sim.events.length=0;toastTime-=dt;if(toastTime<=0)$('toast').style.opacity='0';hudTime-=dt;if(hudTime<=0){updateHUD();if(phoneOffen())$('phoneUhr').textContent=uhrzeit(sim.hour);hudTime=.12;}if(sim.player.health<=0&&!failedShown){failedShown=true;dialog('PORT MERCY POLICE','Festgenommen.','Der Auftrag ist gescheitert. Verliere beim nächsten Versuch zuerst den Sichtkontakt, wechsle bei Bedarf das Fahrzeug und verlasse das markierte Suchgebiet.',[['An der Klinik weiterspielen',()=>{const p=sim.player;p.health=100;p.money=Math.max(0,p.money-100);p.x=locations.clinic.x;p.z=locations.clinic.z+7;p.y=0;p.car=null;sim.stars=0;sim.heat=0;sim.lastSeen=null;sim.description=null;sim.activity=null;failedShown=false;saveGame();}]]);}}requestAnimationFrame(frame);}requestAnimationFrame(frame);

function saveGame(){try{localStorage.setItem('lowtide-v2',JSON.stringify(sim.snapshot()));toast('Spielstand gespeichert.');}catch(e){toast('Spielstand konnte auf diesem Gerät nicht gespeichert werden.');}}
function showPlace(id){const l=locations[id];sim.serviceLocation=id;const buy=(label,item)=>[label,()=>{sim.buy(item);saveGame();}];let options=[];
 if(id==='garage')options=[buy('Reparatur · $150','car:repair'),buy('Lack wechseln · $120','car:paint'),buy('Motor-Upgrade · $400 (max. 3)','car:engine'),buy('Sportreifen · $100','car:tires'),buy('Fahrwerk · $100','car:suspension'),buy('Felgen · $100','car:rims'),buy('Auspuff · $100','car:exhaust'),buy('Innenraum · $100','car:interior'),buy('Beleuchtung · $100','car:lights'),buy('Karosserie-Kit · $100','car:body')];
 if(id==='shop')options=[buy('Karabiner · $650','weapon:rifle'),buy('Schrotflinte · $500','weapon:shotgun'),buy('Taser · $180','weapon:taser'),buy('Munition · $60','ammo'),buy('Kleidung · $80','clothes'),buy('Haarschnitt · $35','hair'),buy('Tattoo · $90','tattoo')];
 if(id==='clinic')options=[buy('Behandlung · $50','heal')];if(id==='diner')options=[buy('Essen & Erholung · $18','food')];if(id==='fuel')options=[buy('Volltanken · $35','fuel')];if(id==='home')options=[buy('Sechs Stunden ausruhen','rest'),['Spiel speichern',saveGame]];if(id==='motel')options=[buy('Ausruhen · $60 / als Eigentümer gratis','rest'),buy('Zimmer dauerhaft erwerben · $900','motel')];
 if(['court','gym','fish','club','dive','race','skydive'].includes(id))options=[[id==='race'?'Rennen starten (im Fahrzeug)':'Aktivität starten',()=>sim.startActivity(l.kind)]];
 if(!options.length)options=[['Zurück in die Welt',()=>{}]];options.push(['Schließen',()=>{}]);dialog(l.name.toUpperCase(),l.name,id==='garage'?'Bring dein Fahrzeug bis an die offene Werkstatt. Käufe verändern dieses Fahrzeug.':id==='shop'?'Waffenwechsel: X. Geld und Inventar gehören der aktiven Figur.':'Erkunde Solvara. Dein Fortschritt wird auf diesem Gerät gespeichert.',options);}
function showActions(){dialog('LOWTIDE','Aktionen',sim.player.name+' · Vertrauen '+sim.relationship+'/100',[[sim.characters[1-sim.active].name+' übernehmen',()=>{sim.switchCharacter();yaw=sim.player.yaw;}],['Waffe wechseln',()=>sim.cycleWeapon()],['Nachladen',()=>sim.reload()],['Nahkampf / leiser Takedown',()=>sim.melee()],['Gegner festsetzen',()=>sim.grapple()],['Deckung',()=>sim.cover()],['Ausweichen',()=>sim.dodge()],['Rennen starten (beim West Loop)',()=>{if(distance(sim.player,locations.race)<12)sim.startActivity('race');else toast('Fahre zum West Loop: Marker auf der Karte.');}],['Aktivität abbrechen',()=>sim.cancelActivity()],['Spiel speichern',saveGame],['Zurück',()=>{}]]);}
function senderWechseln(){
 if(!radio){toast('Ton ist aus.');return;}
 const s=radio.weiter();
 toast(s.id==='aus'?'Radio aus.':s.name+' · '+s.kennung);
 if(phoneOffen()&&phoneApp==='radio')phoneZeichnen();
}
$('moreBtn').onclick=showActions;$('switchBtn').onclick=()=>{if(!sim.paused){sim.switchCharacter();yaw=sim.player.yaw;}};$('saveBtn').onclick=saveGame;$('activityTap').onclick=()=>sim.activity?.kind==='diving'?sim.action():sim.activityTap();$('activityCancel').onclick=()=>sim.cancelActivity();
let saveCounter=0;setInterval(()=>{if(started&&!sim.paused&&sim.player.health>0){try{localStorage.setItem('lowtide-v2',JSON.stringify(sim.snapshot()));}catch{}}},15000);
