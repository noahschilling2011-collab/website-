import * as T from './vendor/three.module.js';
import {wolkenAufsetzen} from './detail.js';
import {backeImModell} from './bake.js';
// Anatomical, articulated meshes with independent elbows, knees and eyelids.
const ball=new T.SphereGeometry(1,16,12);
const cache=new Map();
const mat=(color,roughness=.8)=>{const k=color+':'+roughness;if(!cache.has(k))cache.set(k,wolkenAufsetzen(new T.MeshStandardMaterial({color,roughness})));return cache.get(k);};
function add(parent,geometry,material,x,y,z){const o=new T.Mesh(geometry,material);o.position.set(x,y,z);o.castShadow=true;o.receiveShadow=true;parent.add(o);return o;}
function oval(p,x,y,z,w,h,d,m){const o=add(p,ball,m,x,y,z);o.scale.set(w,h,d);return o;}
// Jede Figur baute ihre Querschnitte selbst: fünfzehn Geometrien pro Person,
// von denen vierzehn bei jeder Person identisch sind. Bei anderthalbhundert
// Leuten in der Stadt sind das zweitausend gleiche Puffer. Der Schlüssel ist
// die Zeilenliste selbst — unterschiedliche Körper bekämen weiterhin eigene.
const loftCache=new Map();
function loft(rows,segments=24){
 const schluessel=segments+':'+rows.map(r=>r.join(',')).join(';');
 if(loftCache.has(schluessel))return loftCache.get(schluessel);
 const g=loftBauen(rows,segments);
 loftCache.set(schluessel,g);
 return g;
}
function loftBauen(rows,segments=24){const pos=[],uv=[],indices=[];for(let j=0;j<rows.length;j++){const [y,w,front,back,offset=0]=rows[j];for(let i=0;i<=segments;i++){const angle=i/segments*Math.PI*2,c=Math.cos(angle),s=Math.sin(angle);pos.push(w*s,y,offset+c*(c>=0?front:back));uv.push(i/segments,j/(rows.length-1));}}for(let j=0;j<rows.length-1;j++)for(let i=0;i<segments;i++){const a=j*(segments+1)+i,b=a+segments+1;if(rows.at(-1)[0]>rows[0][0])indices.push(a,a+1,b,a+1,b+1,b);else indices.push(a,b,a+1,a+1,b,b+1);}const g=new T.BufferGeometry();g.setAttribute('position',new T.Float32BufferAttribute(pos,3));g.setAttribute('uv',new T.Float32BufferAttribute(uv,2));g.setIndex(indices);g.computeVertexNormals();return g;}
function seam(parent,points,color,radius=.003){const path=new T.CatmullRomCurve3(points.map(p=>new T.Vector3(...p)));return add(parent,new T.TubeGeometry(path,Math.max(5,points.length*3),radius,5,false),mat(color),0,0,0);}
const gesichtCache=new Map();
function gesichtGeometrie(skinTone){
 if(gesichtCache.has(skinTone))return gesichtCache.get(skinTone);
 const g=loftBauen([[1.55,.025,.046,.033,.027],[1.57,.065,.065,.053,.018],[1.62,.081,.078,.067,.009],[1.68,.092,.091,.079],[1.72,.092,.092,.084],[1.76,.087,.087,.085],[1.80,.087,.086,.084],[1.85,.067,.064,.065],[1.88,.02,.023,.022],[1.883,.001,.001,.001]],32);
 const colors=[],base=new T.Color(skinTone),attr=g.attributes.position;
 for(let i=0;i<attr.count;i++){
  const x=attr.getX(i),y=attr.getY(i),z=attr.getZ(i);
  const shade=1+.015*Math.sin(i*23.71);
  const c=base.clone().multiplyScalar(shade);
  // Wangenpartie eine Spur wärmer.
  if(z>.045&&y>1.64&&y<1.71&&Math.abs(x)>.035)c.lerp(new T.Color(0xb87865),.10);
  colors.push(c.r,c.g,c.b);
 }
 g.setAttribute('color',new T.Float32BufferAttribute(colors,3));
 gesichtCache.set(skinTone,g);
 return g;
}
const hautCache=new Map(),gesichtStoffCache=new Map(),kopfCache=new Map(),unterarmCache=new Map();
const hautMaterial=ton=>{
 if(!hautCache.has(ton))hautCache.set(ton,wolkenAufsetzen(new T.MeshPhysicalMaterial(
  {color:ton,roughness:.73,sheen:.14,sheenColor:0xb78d76})));
 return hautCache.get(ton);
};
const gesichtMaterial=ton=>{
 if(!gesichtStoffCache.has(ton)){
  const m=hautMaterial(ton).clone();m.color.setHex(0xffffff);m.vertexColors=true;
  gesichtStoffCache.set(ton,m);
 }
 return gesichtStoffCache.get(ton);
};
let serial=0;
// nah=false lässt alles weg, was erst aus wenigen Metern sichtbar wird.
// kennung: die Figur bekommt ihr Aussehen aus dieser Zahl statt aus der
// Reihenfolge des Bauens. Das ist die Voraussetzung dafür, Körper bei Bedarf
// wegzuwerfen und später **identisch** wieder aufzubauen — ohne sie wechselte
// eine Figur Hautton, Frisur und Jacke, sobald man ihr zu nahe kommt.
export function naturalHuman(color,pants,nah=true,kennung=null){
 const id=kennung??serial++,g=new T.Group();const skinTone=[0xc3987b,0xa67455,0x79513b,0xd4ad8c,0xb68467][id%5];
 // Ein fester Zufall je Figur: dieselbe Kennung ergibt immer dasselbe
 // Aussehen, zwei Figuren nebeneinander trotzdem ein verschiedenes. Derselbe
 // Streuwert trägt weiter unten schon Körperbau und Gangart.
 const streu=k=>{const v=Math.sin((id+1)*k)*43758.5453;return v-Math.floor(v);};
 // Bis hierher trug niemand in dieser Stadt etwas: Hemd, Hose, Haut, Haare,
 // und das war die ganze Garderobe für 530 Menschen. Drei Stücke ändern das,
 // jedes an einer anderen Stelle der Silhouette.
 const traegt={rucksack:streu(3.71)<.26,muetze:streu(9.13)<.18,jacke:streu(5.29)<.34};
 const jackenStoff=traegt.jacke?mat([0x2f3a42,0x3c3630,0x44404c,0x2b3a34,0x51463c][id%5],.90):null;
 // Haut und Gesicht kamen pro Figur neu: zwei Materialien mal 533 Menschen
 // sind **1066 der 1134 Figurenmaterialien**. Es gibt aber nur fünf Hauttöne.
 // Gecacht wird nach Ton, nicht nach Person; das Gesichtsmaterial ist derselbe
 // Stoff mit Scheitelpunktfarben und weißem Grundton.
 const skin=hautMaterial(skinTone),gesichtStoff=gesichtMaterial(skinTone);
 const cloth=mat(color,.94),denim=mat(pants,.96),dark=mat(0x292e31),hairColor=[0x302820,0x554332,0x251f1b,0x6b5238][id%4];
 // Pelvis, waist, rib cage and shoulders have different cross sections.
 const body=add(g,loft([[.86,.14,.095,.10],[.91,.18,.11,.105],[1.02,.145,.09,.10],[1.15,.17,.115,.105],[1.32,.21,.12,.105],[1.43,.23,.10,.085],[1.48,.13,.075,.07],[1.49,.065,.057,.052]],28),cloth,0,0,0);
 // Ab hier beginnt der Kopf. Alles zwischen dieser Marke und dem Ende der
 // Haare wird gleich in eine eigene Gruppe umgehängt, damit er sich drehen
 // kann. Die Teile werden mit absoluten Höhen gebaut; die Gruppe bekommt
 // deshalb den Halsansatz als Ursprung und die Kinder ihre Höhe abzüglich
 // desselben Werts.
 const kopfAb = g.children.length;
 add(g,new T.CylinderGeometry(.057,.065,.12,16),skin,0,1.51,0);
 // Jaw, cheekbones, temple, forehead and cranium; no spherical mask.
 // Das Gesicht trägt seine Farbe in den Eckpunkten. Es darf deshalb nicht
 // aus demselben Puffer kommen wie alle anderen: sonst bekäme die ganze
 // Stadt den Hautton der zuletzt gebauten Person. Es gibt aber nur fünf
 // Töne, also fünf Gesichter statt eines pro Kopf.
 const face=add(g,gesichtGeometrie(skinTone),gesichtStoff,0,0,0);
 const eyes=[],lids=[];for(const side of [-1,1]){
  const eye=oval(g,side*.036,1.737,.082,.022,.0105,.012,mat(0xd4d2c8,.34));eyes.push(eye);
  oval(eye,0,0,.83,.37,.77,.22,mat([0x53614b,0x6d5236,0x506975][id%3],.22));oval(eye,0,0,1,.15,.45,.07,mat(0x192326,.15));
  const lid=oval(g,side*.036,1.737,.087,.023,.011,.005,skin);lid.visible=false;lids.push(lid);
  if(nah){
   seam(g,[[side*.015,1.742,.090],[side*.035,1.749,.091],[side*.058,1.74,.087]],skinTone,.0025);
   seam(g,[[side*.017,1.759,.087],[side*.038,1.765,.088],[side*.060,1.756,.082]],hairColor,.0035);
  }
  oval(g,side*.096,1.707,-.003,.013,.031,.018,skin);oval(g,side*.103,1.707,.008,.004,.017,.009,mat(0x946a55));
 }
 // A continuous bridge with separate nostrils and restrained lips.
 add(g,loft([[1.686,.012,.014,.004,.091],[1.694,.019,.023,.004,.094],[1.709,.011,.025,.005,.091],[1.741,.007,.016,.004,.082],[1.758,.005,.006,.003,.081]],12),skin,0,0,0);
 if(nah){
  for(const side of [-1,1])oval(g,side*.011,1.689,.107,.005,.0025,.0035,mat(0x654b3c));
  seam(g,[[-.024,1.662,.086],[-.01,1.667,.093],[0,1.664,.096],[.01,1.667,.093],[.024,1.662,.086]],0x96675b,.003);
  seam(g,[[-.023,1.661,.086],[0,1.657,.095],[.023,1.661,.086]],0xb27c6a,.004);
 }
 const hair=new T.Group();g.add(hair);hair.position.y=1.78;
 const cap=add(hair,loft([[0,.090,.090,.084],[.025,.088,.087,.083],[.062,.072,.068,.067],[.106,.01,.013,.013]],28),mat(hairColor,.97),0,0,-.005);
 if(nah)for(let i=0;i<8;i++){const x=-.064+i*.018;seam(hair,[[x,.015,.079],[x+.007,.07,.04],[x-.008,.086,-.016],[x-.016,.038,-.073]],i%2?hairColor:0x40382b,.007);}
 // Die Mütze gehört an die Haare und damit in die Kopfgruppe — sonst bliebe
 // sie stehen, wenn die Figur sich umsieht.
 if(traegt.muetze){
  const kappe=mat([0x2c3138,0x53342c,0x394a3f,0x6a6155][id%4],.95);
  add(hair,new T.SphereGeometry(.101,14,9,0,Math.PI*2,0,Math.PI*.54),kappe,0,.004,-.004);
  add(hair,new T.BoxGeometry(.142,.011,.072),kappe,0,-.012,.086);
 }
 // Hier endet der Kopf. Ohne diese Marke nahm das Umhängen weiter unten
 // `slice(kopfAb)` und damit alles, was danach gebaut wird: Kragen,
 // Reißverschluss, Gürtel — und Arme und Beine. Die Figur sah im Stand
 // richtig aus, weil die Höhenverschiebung die Weltlage erhält; sobald der
 // Kopf sich aber drehte, drehten Arme und Beine mit. Gemessen: bei 1,2
 // Radiant Kopfdrehung wanderte der Knöchel um 5,8 Zentimeter.
 const kopfBis = g.children.length;
 // Clothing has a collar, zipper, belt and stitched trouser seams.
 if(nah){
  seam(g,[[0,1.475,.07],[-.058,1.45,.085],[-.064,1.41,.10]],0xc3c5b4,.009);seam(g,[[0,1.475,.07],[.058,1.45,.085],[.064,1.41,.10]],0xc3c5b4,.009);
  seam(g,[[0,1.42,.12],[0,1.20,.119],[0,.99,.10]],0x727b78,.0035);
  add(g,new T.BoxGeometry(.045,.033,.012),mat(0x939b93,.35),0,.926,.111);
 }
 if(traegt.rucksack){
  const stoffRucksack=mat([0x394048,0x4a3b32,0x2f4038,0x5b4a3f][id%4],.90);
  add(g,new T.BoxGeometry(.28,.38,.15),stoffRucksack,0,1.19,-.175);
  add(g,new T.BoxGeometry(.19,.13,.035),mat(0x22272b,.85),0,1.08,-.255);
  if(nah)for(const side of [-1,1])
   seam(g,[[side*.085,1.44,.055],[side*.105,1.30,-.02],[side*.088,1.15,-.095]],0x262b2f,.013);
 }
 // Offene Jacke: zwei Blenden über dem Hemd, dazu die Ärmel in derselben
 // Farbe. Zusammen ist das die zweite Silhouette der Stadt.
 if(traegt.jacke)for(const side of [-1,1])
  add(g,new T.BoxGeometry(.062,.43,.022),jackenStoff,side*.082,1.19,.099);
 const legs=[],arms=[],knees=[],elbows=[],ankles=[];
 for(const side of [-1,1]){
  const leg=new T.Group();leg.position.set(side*.105,.91,0);g.add(leg);legs.push(leg);
  add(leg,loft([[0,.098,.092,.095],[-.13,.085,.085,.087],[-.29,.063,.066,.068],[-.43,.055,.053,.055]],18),denim,0,0,0);
  const knee=new T.Group();knee.position.y=-.41;leg.add(knee);knees.push(knee);
  add(knee,loft([[0,.056,.059,.058],[-.12,.062,.062,.069],[-.28,.045,.04,.043],[-.40,.038,.033,.038]],16),denim,0,0,0);
  // Eigenes Sprunggelenk. Vorher hing der Schuh starr am Unterschenkel und
  // kippte mit ihm mit — beim Ausschreiten zeigte die Sohle nach vorn, beim
  // Aufsetzen nach hinten. Als eigene Gruppe lässt sich die Sohle gegen die
  // Kette zurückdrehen und bleibt parallel zum Boden.
  const ankle=new T.Group();ankle.position.y=-.40;knee.add(ankle);ankles.push(ankle);
  oval(ankle,0,-.016,.06,.055,.046,.13,dark);oval(ankle,0,-.048,.06,.056,.011,.13,mat(0x707572));
  if(nah)seam(leg,[[side*.091,-.04,.01],[side*.080,-.18,.01],[side*.057,-.38,.01]],0x626b68,.002);
  const arm=new T.Group();arm.position.set(side*.235,1.415,0);g.add(arm);arms.push(arm);
  add(arm,loft([[.025,.071,.071,.068],[-.13,.058,.058,.057],[-.28,.046,.048,.046]],16),jackenStoff||cloth,0,0,0);
  const elbow=new T.Group();elbow.position.y=-.275;arm.add(elbow);elbows.push(elbow);
  add(elbow,loft([[.01,.047,.049,.047],[-.10,.045,.043,.043],[-.23,.031,.031,.032]],16),jackenStoff||cloth,0,0,0);
  oval(elbow,0,-.275,.003,.036,.057,.023,skin);
  if(nah){
   for(let f=0;f<4;f++){const finger=oval(elbow,(f-1.5)*.015,-.335+(Math.abs(f-1.5))*.007,.009,.009,.032,.011,skin);finger.rotation.x=.12;}
   const thumb=oval(elbow,-side*.035,-.282,.016,.014,.030,.013,skin);thumb.rotation.z=-side*.45;
  } else {
   // Ersatz für die Hand: ein geschlossener Block statt fünf Fingern.
   oval(elbow,0,-.318,.008,.032,.045,.026,skin);
  }
  // Unterarm und Hand backen. Am Ellbogen hängen in der Nahstufe sieben
  // Meshes: Ärmel, Handfläche, vier Finger, Daumen — und sechs davon teilen
  // sich dasselbe Hautmaterial. Gedreht wird die ganze Gruppe, nichts
  // darin bewegt sich für sich, also bleiben nach dem Backen zwei Meshes.
  // Gemessen zehn Zeichenaufrufe weniger je Figur, beim Spieler zwanzig,
  // weil er auch noch seinen Schatten wirft.
  //
  // Der Schlüssel trägt die Seite: Daumen und Finger stehen gespiegelt.
  // Die Jacke ändert nur das Material des Ärmels, nicht seine Form — die
  // Materialien kommen beim Wiederverwenden ohnehin aus dem Exemplar.
  backeImModell(elbow,[],unterarmCache,'unterarm:'+side+':'+(nah?'nah':'fern'));
 }
 const tattoo=add(arms[0],new T.PlaneGeometry(.055,.09),mat(0x314643),0,-.28,.051);tattoo.visible=false;
 // Kopf umhängen. Reihenfolge und Weltlage bleiben gleich, nur der Elternteil
 // wechselt — ohne das steht jede Figur der Stadt mit starrem Blick geradeaus.
 const HALS = 1.5;
 const kopf = new T.Group();
 kopf.position.set(0, HALS, 0);
 const kopfTeile = g.children.slice(kopfAb, kopfBis);
 for (const o of kopfTeile) {o.position.y -= HALS; kopf.add(o);}
 g.add(kopf);
 // Den Kopf zusammenbacken. Animiert sind an einer Figur nur Rumpf (Atmung),
 // Augen und Lider (Blinzeln) — Hals, Nase, Ohren, Haare und Mütze sind starr
 // und drehen ohnehin gemeinsam mit der Kopfgruppe. Aus zehn bis zwölf Meshes
 // werden vier. Bei 533 Figuren in der Stadt zählt das Mesh für Mesh.
 // Gecacht nach dem, was den Kopf ausmacht: Hautton, Haarfarbe und Mütze.
 // Ohne Cache bekäme jede der 533 Figuren eine eigene Geometrie — dann wäre
 // das Backen kein Gewinn, sondern ein Tausch von Zeichenaufrufen gegen
 // Speicher.
 backeImModell(kopf,[...eyes,...lids],kopfCache,traegt.muetze?'mitMuetze':'ohne');
 // Körperbau. Die Körpergröße skaliert die ganze Figur gleichmäßig — damit
 // blieb jedes Verhältnis für alle 530 Menschen dasselbe: Schulterbreite
 // geteilt durch Größe, Rumpftiefe geteilt durch Größe, Kopfhöhe geteilt
 // durch Größe. Eine Stadt aus einem Menschen in verschiedenen Maßstäben.
 //
 // Zwei Streuwerte aus der Kennung geben Breite und Kopfgröße. Die Arme
 // rücken mit den Schultern nach außen, die Beine mit der Hüfte halb so
 // weit; die Rumpftiefe folgt der Breite zu siebzig Prozent, sonst wäre ein
 // breiter Mensch eine Scheibe.
 const bau=.88+streu(31.17)*.26;
 body.scale.set(bau,1,1+(bau-1)*.7);
 arms.forEach((arm,i)=>{arm.position.x=(i?1:-1)*.235*bau;});
 legs.forEach((leg,i)=>{leg.position.x=(i?1:-1)*.105*(1+(bau-1)*.6);});
 kopf.scale.setScalar(.95+streu(7.31)*.1);
 // Gangart. Im Schrittzyklus stand jede Zahl als Konstante: Ausschlag der
 // Beine .46, des Knies .72, der Arme .30, Auf- und Abbewegung .045. Bei
 // gleichem Tempo lief damit jede Figur der Stadt exakt gleich — und das
 // Tempo selbst kannte nur fünf Werte (1,1 + id%5 * 0,13). Also fünf Gangarten
 // für 530 Menschen.
 const gang={schritt:.85+streu(53.7)*.33,arm:.7+streu(19.3)*.65,
  wiegen:.75+streu(87.1)*.55,vorlage:.8+streu(11.9)*.5};
 const garments=[];g.traverse(o=>{if(o.isMesh&&o.material===cloth)garments.push(o);});g.userData={body,hair,tattoo,legs,arms,knees,elbows,ankles,eyes,lids,face,kopf,id,garments,bau,gang,traegt,rig:'anatomical-v3'};return g;
}
// Ein voller Schrittzyklus deckt diese Strecke ab. Die Schrittphase läuft
// deshalb über den zurückgelegten Weg und nicht über die Uhr — nur so bleibt
// der Fuß beim Aufsetzen stehen, statt über den Boden zu schleifen.
const SCHRITTZYKLUS=1.95;
// steigung: Neigung des Bodens unter der Figur im Bogenmaß, aus der
// Geländehöhe vor und hinter ihr. 0 auf der Ebene, was fast überall gilt.
// Am gebauten Modell gemessen, Standfigur mit Ursprung auf dem Boden:
// Unterkante Becken .86, Kniegelenk .84, Knie->Knöchel .40, Sohle .076 unter
// dem Knöchel. Alles in Modelleinheiten, also vor der Größenskalierung.
const BECKEN=.86,KNIE=.84,SCHIENBEIN=.40,SOHLE=.076;
// Wie hoch der Ursprung der Figur über dem Boden liegen muss, damit das
// Becken auf der Sitzfläche aufliegt. sitzhoehe ist die Höhe der Sitzfläche
// über dem Boden in Metern.
export function sitzVersatz(g,sitzhoehe){return sitzhoehe-BECKEN*(g.scale?.y||1);}
// Sitzhaltung. Oberschenkel waagerecht nach vorn, Rumpf etwas zurück, und der
// Unterschenkel so weit nach vorn geneigt, dass die Sohle den Boden erreicht:
// auf einer .42 hohen Bank sind das 36 Grad, auf einem Barhocker baumeln die
// Beine. Vorher stand hier ein fester Kniewinkel von 1.36 — der Unterschenkel
// hing damit senkrecht und die Sohle blieb bei jeder Sitzhöhe .476 über dem
// Ursprung. Ohne diese Funktion sähe eine besetzte Bank schlechter aus als
// eine leere: eine stehende Figur mitten in der Sitzfläche.
export function setzeSitzhaltung(g,sitzt,sitzhoehe=.42){
 const u=g.userData;
 if(!u.legs)return;
 if(!sitzt){
  if(!u.sitzt)return;
  u.sitzt=false;
  for(const arm of u.arms)arm.rotation.set(0,0,0);
  // Ohne diese Zeile behielt jeder, der aufgestanden ist, den Sitzknick im
  // Rumpf: der Gehzyklus schreibt body.rotation.x nie.
  if(u.body)u.body.rotation.x=0;
  return;
 }
 u.sitzt=true;
 // Sitzhöhe in Modelleinheiten: eine kleine Figur sitzt auf derselben Bank
 // relativ höher und muss die Beine weiter ausstrecken.
 const hoehe=sitzhoehe/(g.scale?.y||1);
 const knie=hoehe-BECKEN+KNIE,rest=knie-SOHLE;
 const winkel=Math.acos(Math.max(.06,Math.min(.998,rest/SCHIENBEIN)));
 u.legs.forEach((leg,i)=>{
  leg.rotation.x=-1.42;
  if(u.knees&&u.knees[i])u.knees[i].rotation.x=1.42-winkel;
  // Der Fuß bleibt waagerecht, sonst gräbt sich die Spitze in den Boden.
  if(u.ankles&&u.ankles[i])u.ankles[i].rotation.x=winkel;
 });
 // Arme locker auf den Oberschenkeln.
 u.arms.forEach((arm,i)=>{arm.rotation.x=-.55;arm.rotation.z=(i?-1:1)*.12;});
 if(u.body)u.body.rotation.x=.12;
}

export function animateNaturalHuman(g,time,moving,armed,steigung=0){
 const u=g.userData;
 const dt=Math.max(.001,Math.min(.25,time-(u.letzteZeit??time-.016)));u.letzteZeit=time;
 const dx=g.position.x-(u.letzteX??g.position.x),dz=g.position.z-(u.letzteZ??g.position.z);
 u.letzteX=g.position.x;u.letzteZ=g.position.z;
 // Ein- und Aussteigen, Figurenwechsel und Wiedereinstieg versetzen die Figur
 // sprunghaft. Ohne diese Grenze dreht der Schrittzyklus dabei durch.
 const roh=Math.hypot(dx,dz),strecke=roh>dt*14?0:roh,tempo=strecke/dt;
 u.strecke=(u.strecke||0)+strecke;
 // moving bleibt der Zustand aus der Simulation; das Tempo bestimmt, wie weit
 // ausgeholt wird. Bei sehr kleinem Tempo klingt die Bewegung aus.
 const amount=Math.min(1.25,Math.max(moving>0?.12:0,tempo/5.2));
 const G=u.gang||{schritt:1,arm:1,wiegen:1,vorlage:1};
 // Der Schrittzyklus hing an einer festen Strecke von 1,95 Metern — eine
 // Figur von 1,55 Metern machte damit dieselben Schritte wie eine von 1,90.
 // Er skaliert jetzt mit der Körpergröße: kürzere Beine, kürzere Schritte,
 // höhere Schrittfrequenz bei gleichem Tempo.
 const zyklus=SCHRITTZYKLUS*(g.scale?.y||1)*G.schritt;
 const phase=u.strecke*(Math.PI*2/zyklus)+(moving>0&&tempo<.2?time*4:0);
 u.legs.forEach((leg,i)=>{
  const step=Math.sin(phase+i*Math.PI);
  leg.rotation.x=step*.46*amount*G.schritt;
  u.knees[i].rotation.x=Math.max(0,-step)*.72*amount*G.schritt+.025;
  // Der Fuß wird nicht animiert, sondern aus der Kette gelöst: die Summe aus
  // Hüft- und Kniewinkel wird zurückgenommen, sodass die Sohle waagerecht
  // bleibt. steigung neigt sie zusätzlich in den Hang. Dazu zwei Zugaben,
  // die echtes Gehen ausmachen: Abrollen über die Zehen beim Abstoßen
  // (step<0, das Bein ist hinten) und Anheben der Fußspitze beim Durchziehen.
  if(u.ankles?.[i]){
   const kette=leg.rotation.x+u.knees[i].rotation.x;
   const abstoss=Math.max(0,-step)*.55*amount;
   const durchzug=Math.max(0,step)*.22*amount;
   u.ankles[i].rotation.x=-kette+steigung+abstoss-durchzug;
  }
 });
 u.arms.forEach((arm,i)=>{
  const gegen=Math.sin(phase+i*Math.PI);
  arm.rotation.x=armed?-1.04:gegen*.3*amount*G.arm;
  arm.rotation.z=(i?1:-1)*(.04+amount*.03);
  u.elbows[i].rotation.x=armed?-.32:-.12-Math.max(0,-gegen)*.22*amount;
 });
 // Auf- und Abbewegung des Körpers, zweimal je Zyklus. Der Aufrufer addiert
 // sie auf die Bodenhöhe, weil die hier nicht bekannt ist.
 u.bob=Math.abs(Math.sin(phase))*.045*Math.min(1,amount)*G.wiegen;
 // Neigung in die Kurve und leichtes Vorlehnen beim Laufen.
 const dreh=Math.atan2(Math.sin(g.rotation.y-(u.letzterYaw??g.rotation.y)),Math.cos(g.rotation.y-(u.letzterYaw??g.rotation.y)));
 u.letzterYaw=g.rotation.y;
 u.neigung=(u.neigung||0)+((-dreh/dt*.055-0)*Math.min(1,amount)-(u.neigung||0))*Math.min(1,dt*6);
 u.neigung=Math.max(-.3,Math.min(.3,u.neigung));
 u.vorlage=amount*.06*G.vorlage;
 // Ruhebewegung. Eine Stadt aus hundertsiebenundfünfzig Leuten, die alle
 // exakt still stehen, sieht aus wie ein Schaufenster. Niemand steht still:
 // das Gewicht wandert von einem Bein aufs andere, der Kopf dreht sich zu
 // dem, was gerade vorbeigeht, die Arme hängen nicht wie angenagelt.
 // Der Anteil geht auf null, sobald die Figur losläuft.
 const ruhe=Math.max(0,1-amount*3.2);
 if(ruhe>.01){
  const eigen=u.id*1.73;
  // Gewichtsverlagerung, etwa alle sieben Sekunden ein Wechsel.
  const wiegen=Math.sin(time*.44+eigen);
  u.body.rotation.z=wiegen*.028*ruhe;
  u.legs[0].rotation.z=wiegen*.035*ruhe;
  u.legs[1].rotation.z=wiegen*.035*ruhe;
  u.knees[Math.sin(time*.44+eigen)>0?0:1].rotation.x+=Math.abs(wiegen)*.10*ruhe;
  // Arme folgen der Verlagerung mit Versatz, sonst wirkt es mechanisch.
  u.arms.forEach((arm,i)=>{arm.rotation.x+=Math.sin(time*.51+eigen+i*.7)*.045*ruhe;});
  // Kopf: langsame Drehung mit einer schnelleren Überlagerung, damit es
  // nicht wie ein Ventilator aussieht.
  if(u.kopf){
   const t2=time*.33+eigen;
   u.kopf.rotation.y=(Math.sin(t2)*.34+Math.sin(t2*2.7)*.07)*ruhe;
   u.kopf.rotation.x=Math.sin(t2*.71+1.3)*.09*ruhe;
   u.kopf.rotation.z=Math.sin(t2*.53)*.05*ruhe;
  }
 } else if(u.kopf){
  // Im Gehen schaut der Kopf leicht in die Kurve, sonst geradeaus.
  u.kopf.rotation.y+=(-(u.neigung||0)*.8-u.kopf.rotation.y)*Math.min(1,dt*5);
  u.kopf.rotation.x+=(0-u.kopf.rotation.x)*Math.min(1,dt*5);
  u.kopf.rotation.z+=(0-u.kopf.rotation.z)*Math.min(1,dt*5);
 }
 const blink=(time+u.id*.39)%4.9<.11;
 u.eyes.forEach(e=>e.visible=!blink);u.lids.forEach(e=>e.visible=blink);
 u.body.scale.z=1+Math.sin(time*1.6+u.id)*.009;
}
