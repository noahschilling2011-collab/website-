// Original LOWTIDE content. Dimensions are game metres; handling is arcade physics.
export const bounds={left:-580,right:390,top:-540,bottom:460};
export const locations={
 garage:{x:-153,z:83,name:'Pike Customs',kind:'garage'},
 shop:{x:-155,z:23,name:'Supply & Style',kind:'shop'},
 clinic:{x:-155,z:-37,name:'Mercy Clinic',kind:'clinic'},
 home:{x:-155,z:-97,name:'Voss Apartment',kind:'home'},
 court:{x:-210,z:125,name:'Basketball',kind:'basketball'},
 gym:{x:-145,z:135,name:'Iron Tide Gym',kind:'gym'},
 fish:{x:108,z:143,name:'Angelpier',kind:'fishing'},
 dive:{x:158,z:170,name:'Wracktauchen',kind:'diving'},
 club:{x:-213,z:23,name:'Club Undertow',kind:'club'},
 diner:{x:-270,z:127,name:'Nora’s Diner',kind:'diner'},
 race:{x:-280,z:80,name:'West Loop',kind:'race'},
 skydive:{x:-360,z:300,name:'Mercy Airfield',kind:'skydive'},
 ranger:{x:-450,z:-370,name:'Cypress Nationalpark',kind:'ranger'},
 farm:{x:-365,z:-265,name:'Bellweather Farm',kind:'farm'},
 motel:{x:-355,z:132,name:'Last Light Motel',kind:'motel'},
 fuel:{x:-100,z:140,name:'Northstar Fuel',kind:'fuel'},
 tower:{x:-270,z:-148,name:'Relaisstation',kind:'tower'},
 records:{x:-330,z:-87,name:'Stadtarchiv',kind:'records'},
 ferry:{x:275,z:215,name:'Isla Serena',kind:'ferry'},
 aircargo:{x:-390,z:270,name:'Luftfracht',kind:'aircargo'}
};
// Kaufbare Objekte. Jedes wirft täglich etwas ab und dient als Ruhepunkt;
// teurere Objekte tragen sich langsamer ab, lohnen sich aber auf Dauer.
export const immobilien={
 loft:{name:'Harbor Loft',x:-44,z:44,preis:2400,ertrag:110,art:'Wohnung',
  text:'Zwei Zimmer über dem Hafenbecken. Laut, aber niemand fragt nach.'},
 motel:{name:'Last Light Motel',x:-355,z:132,preis:900,ertrag:60,art:'Betrieb',
  text:'Vierzehn Zimmer an der Ausfallstraße. Die Hälfte steht leer.'},
 werkstatt:{name:'Anteil Pike Customs',x:-153,z:83,preis:3200,ertrag:170,art:'Betrieb',
  text:'Ein Drittel der Werkstatt. Reparaturen kosten dich danach nichts mehr.'},
 diner:{name:'Anteil Nora’s Diner',x:-270,z:127,preis:1800,ertrag:95,art:'Betrieb',
  text:'Nora will sich zurückziehen und sucht jemanden für die Nachtschicht.'},
 liegeplatz:{name:'Liegeplatz Serena',x:250,z:245,preis:1500,ertrag:70,art:'Stellplatz',
  text:'Ein Platz an der Marina. Boote liegen dort sicherer als am Pier.'},
 villa:{name:'Villa Isla Serena',x:268,z:196,preis:9500,ertrag:420,art:'Wohnung',
  text:'Weiß, still, weit weg von Port Mercy. Genau deshalb teuer.'},
 trailer:{name:'Trailer am Park',x:-178,z:258,preis:600,ertrag:35,art:'Wohnung',
  text:'Kein Fundament, kein Papierkram, kein Nachbar, der sich erinnert.'},
 halle:{name:'Lagerhalle Pier 6',x:20,z:296,preis:5200,ertrag:260,art:'Betrieb',
  text:'Vierhundert Quadratmeter am Wasser. Niemand fragt, was drinsteht.'}
};

export const regions=[
 {name:'HARBOR DISTRICT',x:0,z:0}, {name:'DOWNTOWN',x:-250,z:-20},
 {name:'SUNSET SUBURBS',x:-80,z:-310},{name:'BELLWEATHER',x:-355,z:-280},
 {name:'CYPRESS NATIONAL PARK',x:-465,z:-405},{name:'SALT MARSH',x:-460,z:55},
 {name:'MERCY AIRFIELD',x:-360,z:300},{name:'ISLA SERENA',x:290,z:225},
 {name:'SOUTH BEACH',x:100,z:295}
];
export const vehicleTypes={
 compact:{name:'Finch',mass:950,max:25,accel:11,brake:22,turn:1.8,grip:1,shape:'car',scale:[.85,.9,.82],sound:70,security:1},
 sedan:{name:'Kestrel S',mass:1500,max:30,accel:12,brake:23,turn:1.4,grip:1,shape:'car',scale:[1,1,1],sound:48,security:2},
 suv:{name:'Ridgeline',mass:2200,max:28,accel:9,brake:19,turn:1.2,grip:.9,shape:'car',scale:[1.15,1.4,1.1],sound:43,security:3},
 super:{name:'Vesper R',mass:1400,max:49,accel:19,brake:30,turn:1.7,grip:1.3,shape:'car',scale:[1.05,.7,1.12],sound:100,security:6},
 muscle:{name:'Banshee 68',mass:1800,max:37,accel:16,brake:19,turn:1.2,grip:.75,shape:'car',scale:[1.1,.9,1.14],sound:35,security:1},
 pickup:{name:'Mason',mass:2300,max:29,accel:9,brake:18,turn:1.15,grip:.95,shape:'pickup',scale:[1.1,1.2,1.2],sound:39,security:2},
 motorcycle:{name:'Wraith',mass:210,max:42,accel:19,brake:26,turn:2.2,grip:1.05,shape:'bike',scale:[1,1,1],sound:110,security:2},
 dirtbike:{name:'Thistle',mass:130,max:29,accel:15,brake:22,turn:2.5,grip:1.2,shape:'bike',scale:[.8,1.15,.9],sound:95,security:1},
 quad:{name:'Bog Runner',mass:350,max:23,accel:11,brake:20,turn:2,grip:1.2,shape:'quad',scale:[1,1,1],sound:75,security:1},
 truck:{name:'Atlas Hauler',mass:9000,max:23,accel:5,brake:12,turn:.7,grip:.85,shape:'truck',scale:[1.3,1.4,1.6],sound:24,security:2},
 bus:{name:'Mercy Transit',mass:11000,max:22,accel:4.5,brake:13,turn:.65,grip:.95,shape:'bus',scale:[1.25,1.4,2],sound:28,security:2},
 boat:{name:'Skimmer',mass:1700,max:28,accel:8,brake:4,turn:.85,grip:.5,shape:'boat',medium:'water',sound:55,security:0},
 jetski:{name:'Ripple',mass:320,max:33,accel:14,brake:7,turn:1.7,grip:.7,shape:'jetski',medium:'water',sound:100,security:0},
 helicopter:{name:'Osprey H2',mass:1900,max:40,accel:8,brake:9,turn:1.2,grip:1,shape:'helicopter',medium:'air',sound:18,security:0},
 plane:{name:'Cormorant',mass:2100,max:65,accel:9,brake:12,turn:.7,grip:1,shape:'plane',medium:'air',sound:38,security:0}
};
export const weapons={
 pistol:{name:'Pistole',damage:34,range:65,cone:.987,capacity:12,delay:.3,reload:1.4,price:0},
 rifle:{name:'Karabiner',damage:27,range:110,cone:.996,capacity:30,delay:.12,reload:2.1,price:650},
 shotgun:{name:'Schrotflinte',damage:80,range:23,cone:.94,capacity:6,delay:.8,reload:2.4,price:500},
 taser:{name:'Taser',damage:0,range:12,cone:.98,capacity:2,delay:1.2,reload:2,price:180}
};
export function waterAt(x,z){if(x>119){if(x>235&&x<360&&z>150&&z<295)return false;if(z>195&&z<205&&x<260)return false;return true;}return x<-400&&x>-545&&z>-20&&z<130;}
export function groundAt(x,z){if(waterAt(x,z))return -1.2;if(x<-380&&z<-240){const a=Math.max(0,1-((x+490)/155)**2-((z+420)/195)**2);return a*a*62;}return 0;}
// Ampeltakt. Achse 0 regelt den Verkehr in Nord-Süd-Richtung, Achse 1 den
// in Ost-West-Richtung; die zweite ist um den halben Takt versetzt.
// Beleuchtung und Verkehr lesen dieselbe Funktion, sonst hielten Autos bei
// Grün und führen bei Rot.
// Liegt der Punkt auf oder dicht neben einer Fahrbahn? sim.blocked kennt
// nur Gebäude, Straßen sind reine Geometrie.
export function onRoad(x,z,rand=6){
 for(const r of roadSegments){
  if(x>Math.min(r.x1,r.x2)-r.w/2-rand&&x<Math.max(r.x1,r.x2)+r.w/2+rand&&
     z>Math.min(r.z1,r.z2)-r.w/2-rand&&z<Math.max(r.z1,r.z2)+r.w/2+rand)return true;
 }
 return false;
}
export const AMPEL_TAKT=26;
export function ampelFrei(zeit,achse){
 const t=((zeit%AMPEL_TAKT)+AMPEL_TAKT)%AMPEL_TAKT;
 return (achse?(t+AMPEL_TAKT/2)%AMPEL_TAKT:t)<12.5;
}
export function regionAt(p){return [...regions].sort((a,b)=>Math.hypot(a.x-p.x,a.z-p.z)-Math.hypot(b.x-p.x,b.z-p.z))[0].name;}
export const roadSegments=[
 ...[-100,-40,20,80].flatMap(r=>[{x1:r,z1:-120,x2:r,z2:150,w:15},{x1:-340,z1:r,x2:112,z2:r,w:15}]),
 ...[-340,-280,-220,-160].map(x=>({x1:x,z1:-180,x2:x,z2:165,w:15})),
 {x1:-460,z1:-180,x2:100,z2:-180,w:17},{x1:-340,z1:-420,x2:-340,z2:405,w:18},
 {x1:-100,z1:-420,x2:-100,z2:405,w:18},{x1:-340,z1:-320,x2:100,z2:-320,w:14},
 {x1:-340,z1:200,x2:280,z2:200,w:12},{x1:-340,z1:400,x2:100,z2:400,w:16}
];

// Kreuzungen des Straßenrasters. Achsparallele Segmente schneiden sich, wenn
// ihre Spannen überlappen — Diagonalen gibt es in Port Mercy nicht.
export const intersections=(()=>{
 const laengs=r=>Math.abs(r.z2-r.z1)>=Math.abs(r.x2-r.x1);
 const senkrecht=roadSegments.filter(laengs),waagerecht=roadSegments.filter(r=>!laengs(r)),treffer=[];
 for(const v of senkrecht)for(const h of waagerecht){
  const x=v.x1,z=h.z1;
  if(x<Math.min(h.x1,h.x2)-1||x>Math.max(h.x1,h.x2)+1)continue;
  if(z<Math.min(v.z1,v.z2)-1||z>Math.max(v.z1,v.z2)+1)continue;
  treffer.push({x,z,breite:Math.max(v.w,h.w)});
 }
 return treffer;
})();
