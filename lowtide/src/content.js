// Original LOWTIDE content. Dimensions are game metres; handling is arcade physics.
// Die Karte war 970 auf 1000 Meter — knapp ein Quadratkilometer. Das ist der
// eigentliche Abstand zu einer Open World dieser Art, nicht die Grundrissform.
// Nach Westen und Süden verdoppelt: das Meer im Osten bleibt die Grenze, die
// Innenstadt bleibt, wo sie war, und der neue Raum trägt eine zweite Stadt,
// einen Stausee und das Hinterland dazwischen.
export const bounds={left:-1100,right:390,top:-540,bottom:900};
// Die acht Servicegebäude sind keine Punkte, sondern Räume: sechzehn Meter
// breit und sechzehn tief (die Werkstatt zweiundzwanzig), von der Rückwand
// bei z-12 bis zur offenen Front bei z+4. Der Marker steht an der Front.
//
// Vier davon standen an Kreuzungen mitten auf der Fahrbahn — Pike Customs,
// Supply & Style, die Klinik und die Wohnung lagen drei Meter nördlich der
// Querstraßen bei z = 80, 20, -40 und -100 und fünf Meter östlich der
// Nord-Süd-Achse bei x = -160. Bei sechzehn Metern Raumtiefe heißt das:
// beide Fahrbahnen liefen mitten durch das Gebäude. Auf dem Luftbild steht
// der Laden als weißer Klotz zwischen zwei Fahrspuren, links und rechts
// davon fährt Verkehr. Zusammen mit Club, Diner, Motel und Archiv waren es
// fünfundzwanzig Wandstücke, die eine Fahrbahn schnitten.
//
// Die neuen Plätze sind nicht geschätzt, sondern gesucht: für jeden Raum
// alle Punkte im Umkreis von sechzig Metern, die mit zweieinhalb Metern Luft
// jede Fahrbahn freilassen, sechs Meter offenen Vorplatz haben, kein anderes
// registriertes Hindernis berühren und auf ebenem, trockenem Grund liegen —
// davon der nächstgelegene. Vierzehn bis dreißig Meter Versatz, und in
// keinem der acht Rechtecke steht danach noch stehende Kulisse. Die vier
// Innenstadthäuser bilden weiterhin eine Reihe, jetzt an der Südseite ihrer
// Querstraße statt darin.
export const locations={
 garage:{x:-138,z:62,name:'Pike Customs',kind:'garage'},
 shop:{x:-137,z:-1,name:'Supply & Style',kind:'shop'},
 clinic:{x:-140,z:-58,name:'Mercy Clinic',kind:'clinic'},
 home:{x:-139,z:-118,name:'Voss Apartment',kind:'home'},
 court:{x:-210,z:125,name:'Basketball',kind:'basketball'},
 gym:{x:-147,z:119,name:'Iron Tide Gym',kind:'gym'},
 fish:{x:108,z:143,name:'Angelpier',kind:'fishing'},
 dive:{x:158,z:170,name:'Wracktauchen',kind:'diving'},
 club:{x:-202,z:2,name:'Club Undertow',kind:'club'},
 diner:{x:-261,z:116,name:'Nora’s Diner',kind:'diner'},
 race:{x:-280,z:80,name:'West Loop',kind:'race'},
 skydive:{x:-360,z:300,name:'Mercy Airfield',kind:'skydive'},
 ranger:{x:-450,z:-370,name:'Cypress Nationalpark',kind:'ranger'},
 farm:{x:-365,z:-265,name:'Bellweather Farm',kind:'farm'},
 motel:{x:-360,z:155,name:'Last Light Motel',kind:'motel'},
 fuel:{x:-124,z:136,name:'Northstar Fuel',kind:'fuel'},
 tower:{x:-270,z:-148,name:'Relaisstation',kind:'tower'},
 records:{x:-319,z:-75,name:'Stadtarchiv',kind:'records'},
 ferry:{x:243,z:172,name:'Isla Serena',kind:'ferry'},
 aircargo:{x:-389,z:270,name:'Luftfracht',kind:'aircargo'},
 drag:{x:-315,z:250,name:'Mercy Dragstrip',kind:'race:drag'},
 moto:{x:-402,z:-248,name:'Cypress Enduro',kind:'race:moto'},
 boat:{x:237,z:238,name:'Serena Regatta',kind:'race:boot'},
 jet:{x:127,z:158,name:'Ripple Sprint',kind:'race:jet'},
 darts:{x:-268,z:120,name:'Dartscheibe',kind:'darts'},
 pool:{x:-206,z:16,name:'Billardtisch',kind:'pool'},
 range:{x:-146,z:16,name:'Schießstand',kind:'range'},
 schatz:{x:-450,z:-330,name:'Bergungsauftrag',kind:'treasure'},
 // Solvara Motors. Der Platz ist gesucht, nicht gesetzt: das nächstgelegene
 // freie Rechteck von 38 mal 30 Metern zur Werkstatt, ohne Gebäude, ohne
 // stehende Kulisse, mit zwei Metern Abstand zu jeder Fahrbahn und einer
 // Straße in höchstens zehn Metern — und mindestens vierzehn Meter von jedem
 // anderen Ort entfernt. Ohne die letzte Regel lag der beste Treffer einen
 // Meter neben dem Basketballplatz. Von 127 gültigen Flächen ist das die
 // nächste, 106 Meter von Pike Customs. Der Marker steht auf dem Hof vor der
 // Glasfront, nicht im Gebäude.
 autohaus:{x:-176,z:154,name:'Solvara Motors',kind:'autohaus'},
 // Zwei weitere Unterkünfte. Bis hierher gab es genau ein Motel auf 2,15 km²,
 // und es lag in der Innenstadt — wer im Westen oder auf den Keys unterwegs
 // war, hatte keinen Ort zum Einchecken. Beide Grundstücke sind gesucht wie
 // das Autohaus: freies Rechteck von 20 mal 14 Metern, alle vier Ecken auf
 // trockenem, ebenem Land, Straße in Reichweite. Die Eckenprüfung ist nicht
 // kosmetisch — ohne sie lag der beste Treffer auf den Keys mit einer Ecke
 // sechs Meter über offenem Wasser.
 hotelwest:{x:-884,z:265,name:'Rosalind Rooms',kind:'motel'},
 hotelkeys:{x:268,z:394,name:'Halcyon Cabins',kind:'motel'}
};
// Was eine Nacht kostet. Das Last Light Motel bleibt bei sechzig; wer dort
// das Zimmer gekauft hat, zahlt dort nichts mehr.
export const UNTERKUNFT_PREIS={motel:60,hotelwest:45,hotelkeys:80};
// Was auf dem Hof steht und was es kostet. Nur Landfahrzeuge: ein Boot am
// Straßenrand wäre ein Witz, und für Flugzeuge gibt es das Flugfeld.
// Die Reihenfolge ist die Anzeigereihenfolge im Menü.
export const AUTOHAUS=[
 ['compact',1400],['sedan',2600],['pickup',3400],['suv',4200],
 ['motorcycle',5200],['muscle',7800],['super',18500]
];
// Die Stellplätze auf dem Hof, zwei Reihen zu vier. Die fünfte Reihe im
// Norden gehört dem Ausstellungspodest. Sie sind dieselben
// Buchten, die auf dem Belag aufgemalt sind — der erste Anlauf setzte jeden
// weiteren Wagen einfach 5,4 Meter weiter nach Süden, und ab dem dritten
// standen sie neben dem Grundstück auf fremdem Land.
//
// Acht Plätze sind auch die Obergrenze: ist der Hof voll, verkauft Solvara
// Motors nichts mehr, bis einer weggefahren ist. Ohne eine solche Grenze
// wächst die Fahrzeugliste unbegrenzt, und die Fernstufe hat nur Reserve
// für sechzehn zusätzliche Wagen.
export const AUTOHAUS_BUCHTEN=[-182,-174].flatMap(x=>
 [143.2,148.6,154,159.4].map(z=>({x,z,yaw:Math.PI/2})));
// Die Regatta war nicht zu starten. Ein Bootsrennen verlangt, dass die Figur
// in einem Boot sitzt (startActivity prüft das Medium), und ein Boot bewegt
// sich nur über Wasser. Der Marker lag achtzehn Meter landeinwärts — näher
// als neun Meter kam man mit einem Boot nie heran. Er steht jetzt am Kopf
// des Marina-Landgangs, zwei Meter hinter der Wasserlinie; ein Boot davor
// liegt vier Meter entfernt. Dasselbe für den Liegeplatz.

// Drei Orte hatten einen Namen und kein Bauwerk: Fähranleger, Luftfracht und
// Gym. Der Fähranleger lag dazu vierzig Meter im Landesinneren — Isla Serena
// ist das Rechteck 235 bis 360, die Westküste eine gerade Linie bei x = 235,
// und der Marker stand bei x = 275 mitten auf der Insel. Der erste Versuch
// bei z = 215 setzte die festgemachte Fähre quer über den Damm bei z = 200;
// sichtbar wurde das erst auf dem Bild, auf dem Autos neben dem Schiffsrumpf
// fuhren. Gesucht wurde deshalb: die z-Lage entlang der Westküste, an der
// Landseite (x 234–258) und Wasserseite (x 214–236) je drei Meter Abstand zu
// jeder Fahrbahn haben, die Landseite trocken und die Wasserseite nass ist
// und keine vorhandene Kulisse im Weg steht. Von 121 geprüften Lagen bleiben
// drei übrig, alle bei z ≈ 171 — der Rest der Küste ist Palmen und Marina.
//
// Alle drei Marker stehen hier und nicht in regions.js: die Kulisse rechnet
// sich aus dem Marker, nicht umgekehrt.

// Northstar Fuel war ein Name auf einem schwebenden Marker, neun Meter tief
// im achtzehn Meter breiten Boulevard bei x = -100. Tanken funktionierte —
// man stand dabei auf der Fahrspur, und ein Bauwerk gab es nicht: fünf
// stehende Instanzen im Umkreis von achtzehn Metern, und die gehörten zum
// Nachbarhaus. Der Platz ist gesucht wie bei den Läden: das nächstgelegene
// freie Rechteck von 34 mal 28 Metern mit zwei Metern Abstand zur Fahrbahn,
// höchstens acht Meter von einer entfernt, ohne stehende Kulisse darin.
// Achtundzwanzig Meter westlich. Der Grundriss steht hier, damit Hindernis
// und Kulisse nicht auseinanderlaufen — beim Lagerhaus liegen sie in zwei
// Dateien, und genau das musste beim Umzug von Hand nachgezogen werden.
export const TANKSTELLE={
 get x(){return locations.fuel.x;}, get z(){return locations.fuel.z;},
 dach:{breite:22,tiefe:14,hoehe:5.4},   // Vordach über den Zapfsäulen
 hof:{versatzX:-4,versatzZ:2,breite:34,tiefe:28},
 kiosk:{versatzX:-14,versatzZ:12,breite:12,tiefe:8,hoehe:4.2},
 insel:{versatzX:6,breite:6,tiefe:3.4}  // zwei, gespiegelt um die Mitte
};

// Dartscheibe und Billardtisch stehen in ihren Räumen, sieben Meter hinter
// der Front; der Schießstand liegt im Freien östlich neben dem Laden. Als
// eigene Koordinaten blieben alle drei beim Umzug der Gebäude stehen — der
// Schießstand lag ohnehin schon in der Querstraße bei z = 20. Deshalb sind
// sie an ihren Wirt gebunden statt selbst eingetragen.
for(const [ziel,wirt,dx,dz] of [['darts','diner',2,-7],['pool','club',7,-7],['range','shop',13,-7]]){
 locations[ziel].x=locations[wirt].x+dx;locations[ziel].z=locations[wirt].z+dz;
}
// Kaufbare Objekte. Jedes wirft täglich etwas ab und dient als Ruhepunkt;
// teurere Objekte tragen sich langsamer ab, lohnen sich aber auf Dauer.
export const immobilien={
 loft:{name:'Harbor Loft',x:-44,z:44,preis:2400,ertrag:110,art:'Wohnung',
  text:'Zwei Zimmer über dem Hafenbecken. Laut, aber niemand fragt nach.'},
 motel:{name:'Last Light Motel',x:locations.motel.x,z:locations.motel.z,preis:900,ertrag:60,art:'Betrieb',
  text:'Vierzehn Zimmer an der Ausfallstraße. Die Hälfte steht leer.'},
 werkstatt:{name:'Anteil Pike Customs',x:locations.garage.x,z:locations.garage.z,preis:3200,ertrag:170,art:'Betrieb',
  text:'Ein Drittel der Werkstatt. Reparaturen kosten dich danach nichts mehr.'},
 diner:{name:'Anteil Nora’s Diner',x:locations.diner.x,z:locations.diner.z,preis:1800,ertrag:95,art:'Betrieb',
  text:'Nora will sich zurückziehen und sucht jemanden für die Nachtschicht.'},
 liegeplatz:{name:'Liegeplatz Serena',x:237,z:252,preis:1500,ertrag:70,art:'Stellplatz',
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
 {name:'SOUTH BEACH',x:100,z:295},
 {name:'THE LOWER KEYS',x:230,z:400},{name:'OUTER KEYS',x:270,z:-60},
 {name:'ROSALIND',x:-870,z:340},{name:'TALON RIDGE',x:-880,z:-160},
 {name:'CANE HOLLOW',x:-640,z:640},{name:'MERCY RESERVOIR',x:-700,z:80}
];
// laenge und breite sind an den gebauten Meshes gemessen, im Eigensystem des
// Fahrzeugs und nicht in Weltachsen — mit gedrehtem Wagen mischen sich beide.
// Der Verkehr braucht sie, um Abstand zu halten: vorher standen dort sieben
// Meter für jeden, vom Motorrad bis zum Achtmeterbus.
export const vehicleTypes={
 compact:{name:'Finch',mass:950,max:25,accel:11,brake:22,turn:1.8,grip:1,shape:'car',scale:[.85,.9,.82],sound:70,security:1,laenge:3.72,breite:1.96},
 sedan:{name:'Kestrel S',mass:1500,max:30,accel:12,brake:23,turn:1.4,grip:1,shape:'car',scale:[1,1,1],sound:48,security:2,laenge:4.46,breite:2.22},
 suv:{name:'Ridgeline',mass:2200,max:28,accel:9,brake:19,turn:1.2,grip:.9,shape:'car',scale:[1.15,1.4,1.1],sound:43,security:3,laenge:4.97,breite:2.36},
 super:{name:'Vesper R',mass:1400,max:49,accel:19,brake:30,turn:1.7,grip:1.3,shape:'car',scale:[1.05,.7,1.12],sound:100,security:6,laenge:5.00,breite:2.33},
 muscle:{name:'Banshee 68',mass:1800,max:37,accel:16,brake:19,turn:1.2,grip:.75,shape:'car',scale:[1.1,.9,1.14],sound:35,security:1,laenge:5.12,breite:2.28},
 // shape bleibt 'pickup', auch wenn die Pritsche jetzt aus der Karosserieform
 // kommt statt aus einem aufgesetzten Klotz: die Prüfung "Der Verkehr zeigt
 // mehr als zwei Karosserieformen" zählt die shape-Kategorien, und mit 'car'
 // fiel der Verkehr von fünf auf vier.
 pickup:{name:'Mason',mass:2300,max:29,accel:9,brake:18,turn:1.15,grip:.95,shape:'pickup',sound:39,security:2,laenge:4.95,breite:2.40},
 // Zwei Formen, die dem Verkehr bisher fehlten. Der Kastenwagen ist die
 // höchste Silhouette unter den Autos, das Taxi die einzige mit Dachschild —
 // beide aus hundert Metern zu erkennen, und genau darum geht es.
 van:{name:'Halcyon Cargo',mass:2600,max:26,accel:8,brake:17,turn:1.05,grip:.92,shape:'car',sound:36,security:2,laenge:5.00,breite:2.36},
 taxi:{name:'Kestrel Kab',mass:1550,max:29,accel:11.5,brake:22,turn:1.4,grip:1,shape:'car',sound:50,security:1,laenge:4.46,breite:2.22},
 motorcycle:{name:'Wraith',mass:210,max:42,accel:19,brake:26,turn:2.2,grip:1.05,shape:'bike',scale:[1,1,1],sound:110,security:2,laenge:2.70,breite:1.00},
 dirtbike:{name:'Thistle',mass:130,max:29,accel:15,brake:22,turn:2.5,grip:1.2,shape:'bike',scale:[.8,1.15,.9],sound:95,security:1,laenge:2.70,breite:1.00},
 quad:{name:'Bog Runner',mass:350,max:23,accel:11,brake:20,turn:2,grip:1.2,shape:'quad',scale:[1,1,1],sound:75,security:1,laenge:2.70,breite:1.52},
 truck:{name:'Atlas Hauler',mass:9000,max:23,accel:5,brake:12,turn:.7,grip:.85,shape:'truck',scale:[1.3,1.4,1.6],sound:24,security:2,laenge:7.00,breite:2.70},
 bus:{name:'Mercy Transit',mass:11000,max:22,accel:4.5,brake:13,turn:.65,grip:.95,shape:'bus',scale:[1.25,1.4,2],sound:28,security:2,laenge:8.00,breite:2.70},
 boat:{name:'Skimmer',mass:1700,max:28,accel:8,brake:4,turn:.85,grip:.5,shape:'boat',medium:'water',sound:55,security:0,laenge:5.00,breite:2.40},
 jetski:{name:'Ripple',mass:320,max:33,accel:14,brake:7,turn:1.7,grip:.7,shape:'jetski',medium:'water',sound:100,security:0,laenge:2.50,breite:1.00},
 helicopter:{name:'Osprey H2',mass:1900,max:40,accel:8,brake:9,turn:1.2,grip:1,shape:'helicopter',medium:'air',sound:18,security:0,laenge:9.26,breite:8.53},
 plane:{name:'Cormorant',mass:2100,max:65,accel:9,brake:12,turn:.7,grip:1,shape:'plane',medium:'air',sound:38,security:0,laenge:7.15,breite:13.00}
};
export const weapons={
 pistol:{name:'Pistole',damage:34,range:65,cone:.987,capacity:12,delay:.3,reload:1.4,price:0},
 rifle:{name:'Karabiner',damage:27,range:110,cone:.996,capacity:30,delay:.12,reload:2.1,price:650},
 shotgun:{name:'Schrotflinte',damage:80,range:23,cone:.94,capacity:6,delay:.8,reload:2.4,price:500},
 taser:{name:'Taser',damage:0,range:12,cone:.98,capacity:2,delay:1.2,reload:2,price:180}
};
// Land im Meer. Vorher war östlich der Küste nur die eine Insel und der
// Damm dorthin; dreißig 100-Meter-Zellen der Karte bestanden aus nichts als
// Wasser. Die Rechtecke stehen hier zentral, weil vier Stellen sie brauchen:
// waterAt, das Gelände, die Karte im Telefon und der Wassershader, der um
// jede Küste Brandung legt.
// x1,z1,x2,z2 in Weltmetern.
export const INSELN=[
 {name:'Isla Serena',   x1:235,z1:150,x2:360,z2:295},
 {name:'Pelican Key',   x1:150,z1:373,x2:206,z2:427},
 {name:'Halcyon Key',   x1:238,z1:376,x2:296,z2:430},
 {name:'Sable Key',     x1:310,z1:370,x2:364,z2:424},
 {name:'Windward Key',  x1:204,z1:-126,x2:246,z2:-74},
 {name:'Bone Key',      x1:286,z1:-36,x2:332,z2:16},
 {name:'Anchor Bank',   x1:148,z1:38,x2:184,z2:72}
];
// Fahrbare Dämme. Sie zählen als Land, sonst bricht driveVehicle beim ersten
// Meter ab und groundAt liefert Wassertiefe statt Fahrbahnhöhe.
export const DAEMME=[
 {x1:119,z1:195,x2:260,z2:205},   // zur Insel
 {x1:119,z1:392,x2:366,z2:408},   // Keys Highway
 // Der Bay Skyway zählt als Land, obwohl er über dem Wasser liegt. Ohne das
 // käme kein Fahrzeug einen Meter weit: driveVehicle bricht ab, sobald der
 // nächste Schritt auf Wasser fällt, und die Trasse wäre eine Brücke, die
 // niemand befahren kann.
 // Das Deck ist breiter als die Fahrbahn: zwanzig Meter Bauwerk für fünfzehn
 // Meter Spur. Die zweieinhalb Meter Kappe an jeder Seite tragen Leitplanke
 // und Lichtmasten — ohne sie stünden beide in der Fahrspur, und genau das
 // hat die Prüfung "Keine Kulisse steht in einer Fahrbahn" gemeldet.
 {x1:124,z1:200,x2:144,z2:400}
];
// Der Bay Skyway. Eine Hochstraße ist in dieser Welt nur dort möglich, wo sie
// keine bestehende Fahrbahn kreuzt: groundAt liefert genau eine Höhe je Punkt,
// eine Straße über einer Straße gibt es nicht — wer unter einer Hochstraße
// durchführe, spränge auf sie hinauf. Deshalb verbindet sie die beiden
// vorhandenen Dämme über offenem Wasser und endet auf ihnen, statt sie zu
// überqueren: von der Inselzufahrt bei z = 200 hinauf auf acht Meter, sechzig
// Meter Deck, wieder hinunter auf den Keys Highway bei z = 400.
//
// Die Steigung ist gerechnet, nicht geschätzt: acht Meter auf siebzig sind
// 11,4 Prozent. Steiler als eine echte Autobahnrampe, flach genug, dass ein
// Kleinwagen sie mit Anlauf nimmt.
export const HOCHSTRASSEN=[{
 name:'Bay Skyway',x1:124,x2:144,
 // z-Marke und Höhe. Dazwischen wird linear interpoliert.
 // Anfang und Ende liegen auf den Dämmen, nicht auf den Querstraßen: bei
 // z = 200 und z = 400 laufen die Fahrbahnen zur Insel und über die Keys,
 // und eine Rampe, die dort schon Höhe hat, wäre eine Schwelle quer durch
 // eine fremde Straße. Steigung damit 8 m auf 67 bzw. 63 — 12 bzw. 12,7 %.
 punkte:[[205,0],[272,8],[330,8],[393,0]]
}];
export function hochstrasseHoehe(x,z){
 for(const h of HOCHSTRASSEN){
  if(x<h.x1||x>h.x2)continue;
  const p=h.punkte;
  if(z<p[0][0]||z>p[p.length-1][0])continue;
  for(let i=0;i<p.length-1;i++){
   const [za,ya]=p[i],[zb,yb]=p[i+1];
   if(z>=za&&z<=zb)return ya+(yb-ya)*(z-za)/(zb-za);
  }
 }
 return null;
}
const imRechteck=(x,z,r)=>x>r.x1&&x<r.x2&&z>r.z1&&z<r.z2;
// Binnengewässer. Der Stausee war bisher eine bemalte Platte: er sah aus wie
// Wasser und war für jede Abfrage trockener Boden — man lief darüber. Als
// Ellipse, weil sein Ufer als Ellipse gebaut ist; ein Rechteck ragte an den
// Diagonalen über die Böschung hinaus.
// Der Stausee reichte mit seiner Westspitze bis x = -818. Der Ridge Highway
// liegt bei x = -820 und ist siebzehn Meter breit, seine Ostkante also bei
// -811,5 — der See lag sechseinhalb Meter unter der Fahrbahn. Gemessen an
// den fahrenden Wagen: vier von 1905 Proben standen im Wasser, alle bei
// x = -815. Halbachse von 118 auf 106; die Uferböschung in regions.js zieht
// mit, sonst bliebe zwischen Wasserkante und Böschung ein trockener Ring.
export const SEEN=[{x:-700,z:80,rx:106,rz:88}];
export function imSee(x,z){
 for(const s of SEEN)if(Math.hypot((x-s.x)/s.rx,(z-s.z)/s.rz)<1)return true;
 return false;
}
// Dämme im Westen. Drei Straßen liefen quer durch den Salzsumpf — zwei
// Nord-Süd-Achsen mit je 146 Metern und eine Querstraße mit 82, zusammen 374
// Meter Fahrbahn über offenem Wasser. Sichtbar war davon nichts: groundAt
// liefert über Wasser -1,2, die Fahrbahn lag damit unter der Sumpffläche.
// Geblockt hat sie trotzdem — der Bewuchs mied einen Streifen, auf dem
// nichts lag, und der Verkehr fuhr über das Wasser.
//
// Statt die Straßen zu verlegen bekommen sie einen Damm: die Rechtecke sind
// zwei Meter breiter als die Fahrbahn und nehmen dem Sumpf diesen Streifen.
export const WEST_DAEMME=[
 {x1:-472.5,z1:-25,x2:-451.5,z2:135},
 {x1:-412.5,z1:-25,x2:-391.5,z2:135},
 {x1:-548,z1:53,x2:-346,z2:71}
];
export function waterAt(x,z){
 if(x>119){
  for(const r of INSELN)if(imRechteck(x,z,r))return false;
  for(const d of DAEMME)if(imRechteck(x,z,d))return false;
  return true;
 }
 if(imSee(x,z))return true;
 for(const d of WEST_DAEMME)if(imRechteck(x,z,d))return false;
 return x<-400&&x>-545&&z>-20&&z<130;
}
export function groundAt(x,z){
 // Vor allem anderen: liegt hier eine Hochstraße, gilt deren Höhe.
 const hoch=hochstrasseHoehe(x,z);
 if(hoch!==null)return hoch;
 if(waterAt(x,z))return -1.2;
 // Cypress-Hügel im Nordwesten.
 if(x<-380&&x>-700&&z<-240){const a=Math.max(0,1-((x+490)/155)**2-((z+420)/195)**2);return a*a*62;}
 // Talon Ridge: ein langer Rücken im neuen Westen. Ohne Höhe wäre die
 // doppelte Fläche eine doppelt so große Ebene.
 if(x<-680&&z<80){
  const a=Math.max(0,1-((x+900)/230)**2-((z+160)/300)**2);
  return a*a*88;
 }
 return 0;
}
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
 {x1:-340,z1:200,x2:280,z2:200,w:12},{x1:-340,z1:400,x2:100,z2:400,w:16},
 // Erschließung des Westens und Südens. Zwei Fernstraßen und das Raster von
 // Rosalind; ohne sie wäre der neue Raum nur mit dem Hubschrauber erreichbar.
 {x1:-1060,z1:200,x2:-340,z2:200,w:17},   // Westumgehung
 {x1:-1060,z1:620,x2:100,z2:620,w:16},    // Südtangente
 {x1:-820,z1:-460,x2:-820,z2:860,w:17},   // Ridge Highway
 {x1:-560,z1:-180,x2:-560,z2:860,w:16},   // Hollow Road
 {x1:-1060,z1:-160,x2:-560,z2:-160,w:15}, // Talon Ridge Zufahrt
 {x1:-960,z1:260,x2:-960,z2:440,w:13},{x1:-900,z1:260,x2:-900,z2:440,w:13},
 {x1:-1000,z1:300,x2:-760,z2:300,w:13},{x1:-1000,z1:380,x2:-760,z2:380,w:13},
 {x1:-1030,z1:340,x2:-720,z2:340,w:16},  // Rosalind Main Street
 // Erschließung der neuen Stadtteile. Die Lage ist nicht frei gewählt: der
 // Nordring muss zwischen die Vorortzeile bei z = -260 und die vorhandene
 // Querstraße bei z = -180 passen, und die beiden Querachsen des Wohnviertels
 // enden bei x = -348, weil dort die Innenstadt anfängt.
 {x1:-480,z1:-228,x2:100,z2:-228,w:16},
 {x1:-462,z1:-228,x2:-462,z2:150,w:15},
 {x1:-402,z1:-228,x2:-402,z2:150,w:15},
 {x1:-480,z1:-62,x2:-348,z2:-62,w:14},
 {x1:-480,z1:62,x2:-348,z2:62,w:14},
 // Keys Highway: über den Damm bis zur letzten Insel.
 {x1:100,z1:400,x2:360,z2:400,w:14},
 // Bay Skyway. Als gewöhnliches Straßenstück angemeldet: der Straßenbau in
 // expanded-world.js folgt ohnehin groundAt, also entstehen Decke, Rand und
 // Mittelstreifen auf acht Metern Höhe, ohne dass dafür eine Zeile nötig wäre.
 //
 // Das Stück endet sechs Meter vor den beiden Querstraßen und nicht auf
 // ihnen. Sonst entstehen zwei neue Kreuzungen — und mit ihnen zwei Ampeln
 // und eine Sperrstelle für die Polizei mitten auf dem Damm. Gemessen: die
 // Streife auf den Keys bekam den Auftrag, 96 Meter nach Westen zu fahren,
 // blieb acht Meter neben dem Spieler stehen, weil Verfolgung vor Sperre
 // geht, und baute nie eine Sperre auf. Die Lücke ist gedeckt: die Fahrbahn
 // bei z = 200 ist zwölf Meter breit, die bei z = 400 vierzehn.
 {x1:134,z1:206,x2:134,z2:394,w:15}
];

// Bebautes Gebiet. Auf dem Land trug jede Straße den vollen Stadtausbau:
// Bordstein, vier Meter Gehweg, Laternen alle vierzig Meter, Hydranten,
// Mülltonnen, Zeitungskästen, Gullis — und beidseitig geparkte Wagen bis zum
// Horizont. Gemessen: 306 von 503 Parkplätzen lagen weiter als 45 Meter vom
// nächsten Gebäude entfernt, 67 davon allein in Cane Hollow. Auf dem Bild
// ist es eine Landstraße durch Ackerland mit zwei durchgehenden Parkreihen.
//
// Rechtecke statt Radien, weil die bebauten Flächen rechteckig sind — es
// sind die Straßenraster selbst. Wer ein Raster ergänzt, muss das Rechteck
// mitziehen; die Prüfung meldet es, wenn ein Gehweg im Nirgendwo endet.
export const STADTGEBIETE=[
 {x1:-360,z1:-140,x2:130,z2:185},    // Port Mercy: Innenstadt und Hafen
 {x1:-500,z1:-250,x2:130,z2:-140},   // Nordquartier bis zur Vorortzeile
 {x1:-500,z1:-140,x2:-340,z2:170},   // Westviertel
 {x1:-200,z1:-380,x2:60,z2:-250},    // Sunset Suburbs
 {x1:-1045,z1:245,x2:-700,z2:400},   // Rosalind
 {x1:235,z1:150,x2:360,z2:295},      // Isla Serena, Ringstraße und Marina
 {x1:60,z1:250,x2:190,z2:340}        // South Beach, Promenade
];
export const imStadtgebiet=(x,z)=>STADTGEBIETE.some(g=>x>=g.x1&&x<=g.x2&&z>=g.z1&&z<=g.z2);

// Kreuzungen des Straßenrasters. Achsparallele Segmente schneiden sich, wenn
// ihre Spannen überlappen — Diagonalen gibt es in Port Mercy nicht.
//
// Dieselbe Achse besteht stellenweise aus zwei Segmenten: bei x = -100 und
// x = -340 liegt neben der kurzen Rasterstraße der lange Boulevard, bei
// z = 200 und z = 400 stoßen Uferstraße und Keys Highway aneinander. Jedes
// der beiden Teilstücke traf dieselbe Querstraße, und damit stand die
// Kreuzung zweimal in der Liste. Gemessen im laufenden Spiel: 76 gebaute
// Kreuzungen auf 66 Plätzen. Zehnmal steckten vier Masten, vier Ausleger,
// vier Gehäuse und zwölf Lichtlinsen deckungsgleich ineinander — sichtbar
// als Flimmern an den Gehäuseflächen, dazu 240 Instanzen umsonst.
// Deshalb nach Position zusammengefasst, mit der größeren der beiden
// Fahrbahnbreiten: die Masten stehen sonst zu eng an der breiteren Straße.
export const intersections=(()=>{
 const laengs=r=>Math.abs(r.z2-r.z1)>=Math.abs(r.x2-r.x1);
 const senkrecht=roadSegments.filter(laengs),waagerecht=roadSegments.filter(r=>!laengs(r)),treffer=new Map();
 for(const v of senkrecht)for(const h of waagerecht){
  const x=v.x1,z=h.z1;
  if(x<Math.min(h.x1,h.x2)-1||x>Math.max(h.x1,h.x2)+1)continue;
  if(z<Math.min(v.z1,v.z2)-1||z>Math.max(v.z1,v.z2)+1)continue;
  const schluessel=x+'|'+z,breite=Math.max(v.w,h.w),da=treffer.get(schluessel);
  if(da)da.breite=Math.max(da.breite,breite);
  else treffer.set(schluessel,{x,z,breite});
 }
 return [...treffer.values()];
})();
// Fußgängerüberwege. Fünfzehneinhalb Kilometer Fahrbahn trugen genau eine
// Markierung: einen gestrichelten Mittelstreifen alle sechzehn Meter. Keine
// Randlinie, kein Überweg — und Fußgänger querten die fünfzehn Meter breiten
// Straßen an beliebiger Stelle.
//
// Je Kreuzung bis zu vier Überwege, knapp außerhalb der Kreuzungsfläche.
// Gebaut wird nur, was auch auf einer Fahrbahn liegt: an einer Kreuzung am
// Ende einer Straße fällt die Hälfte weg.
export const UEBERWEGE=(()=>{
 const laengs=r=>Math.abs(r.z2-r.z1)>=Math.abs(r.x2-r.x1);
 // Die Fahrbahn, die an dieser Stelle in der gesuchten Richtung verläuft.
 const strasseAn=(x,z,nordSued)=>roadSegments.find(r=>laengs(r)===nordSued&&
  x>Math.min(r.x1,r.x2)-r.w/2&&x<Math.max(r.x1,r.x2)+r.w/2&&
  z>Math.min(r.z1,r.z2)-r.w/2&&z<Math.max(r.z1,r.z2)+r.w/2);
 const aus=[];
 for(const k of intersections){
  const ab=k.breite/2+2.8;
  // nordSued=true: der Überweg quert die Nord-Süd-Fahrbahn und liegt
  // nördlich oder südlich der Kreuzung; seine Streifen liegen quer zu x.
  for(const nordSued of [true,false])for(const seite of [-1,1]){
   const x=k.x+(nordSued?0:seite*ab),z=k.z+(nordSued?seite*ab:0);
   const r=strasseAn(x,z,nordSued);
   if(!r||!onRoad(x,z,0))continue;
   aus.push({x,z,nordSued,breite:r.w});
  }
 }
 return aus;
})();
// Rasterabfrage für die Wegesuche: liegt dieser Punkt in einem Überweg? Die
// Wegesuche geht in Vier-Meter-Schritten, das Raster hat dieselbe Weite.
const UEBERWEG_RASTER=(()=>{
 const m=new Set();
 for(const u of UEBERWEGE){
  const halb=u.breite/2+1;
  for(let q=-halb;q<=halb;q+=1.5)for(let l=-2.5;l<=2.5;l+=1.5){
   const x=u.x+(u.nordSued?q:l),z=u.z+(u.nordSued?l:q);
   m.add(Math.round(x/4)+'|'+Math.round(z/4));
  }
 }
 return m;
})();
export function amUeberweg(x,z){return UEBERWEG_RASTER.has(Math.round(x/4)+'|'+Math.round(z/4));}

// Rennstrecken. Alle laufen über dieselbe Kontrollpunkt-Mechanik; sie
// unterscheiden sich in Kurs, verlangtem Fahrzeug und Preisgeld.
export const rennen={
 west:{name:'WEST LOOP',medium:'land',preis:500,ziel:100,punkte:[
  {x:-280,z:-100},{x:-100,z:-100},{x:-100,z:200},{x:-340,z:200},{x:-340,z:80},{x:-280,z:80}]},
 drag:{name:'MERCY DRAGSTRIP',medium:'land',preis:300,ziel:22,punkte:[
  {x:-315,z:262},{x:-315,z:310},{x:-315,z:360},{x:-315,z:386}]},
 moto:{name:'CYPRESS ENDURO',medium:'land',form:'bike',preis:650,ziel:95,punkte:[
  {x:-418,z:-262},{x:-452,z:-300},{x:-486,z:-352},{x:-520,z:-410},{x:-470,z:-448},
  {x:-424,z:-396},{x:-402,z:-310},{x:-402,z:-248}]},
 // Die Regatta umrundete Isla Serena und kreuzte dabei den Damm bei z = 200:
 // der ist Land, ein Boot kommt dort nicht durch. Aufgefallen ist es nicht
 // beim Fahren, sondern beim Abtasten der Strecke alle acht Meter — zwei von
 // dreiundneunzig Proben lagen an Land, die eine auf dem Damm, die andere an
 // der Südostecke der Insel. Beides ist erst mit dem Kartenausbau entstanden.
 //
 // Eine Umrundung ist damit nicht mehr möglich: nördlich und südlich der
 // Insel liegt Wasser, aber zwischen beiden gibt es keinen Durchlass. Der
 // Kurs liegt jetzt ganz im nördlichen Becken. Er ist mit 530 statt 743
 // Metern kürzer, die Zielzeit entsprechend von 120 auf 86 Sekunden.
 boot:{name:'SERENA REGATTA',medium:'water',preis:600,ziel:86,punkte:[
  {x:158,z:306},{x:160,z:348},{x:300,z:352},{x:384,z:334},{x:388,z:302},{x:250,z:302}]},
 // Kontrollpunkt zwei lag auf 170/60 und damit auf der Anchor Bank, einer
 // Sandbank aus dem Kartenausbau. Ein Jetski erreicht ihn nicht. Jetzt
 // westlich davon, im Kanal zwischen Küste und Bank.
 jet:{name:'RIPPLE SPRINT',medium:'water',preis:420,ziel:70,punkte:[
  {x:140,z:120},{x:138,z:60},{x:150,z:-10},{x:180,z:-70},{x:145,z:-120},{x:132,z:-40},{x:130,z:110}]}
};

// Bergungsauftrag: sechs Fundstellen, eine nach der anderen.
// Fundstellen der Schatzsuche. Sie werden der Reihe nach geborgen, und
// geborgen wird bei einem Abstand unter fünf Metern — eine Stelle, an die man
// nicht nah genug herankommt, bricht die ganze Kette ab.
//
// Die vierte lag auf -360/352 und damit in einem Haus von 33 mal 25 Metern.
// Der nächste Punkt, an dem man überhaupt stehen kann, war exakt fünf Meter
// entfernt: knapp zu weit. Jetzt auf -351/352, mit freiem Ring von zweieinhalb
// Metern ringsum.
export const schatzOrte=[
 {x:-452,z:-338},{x:-97,z:-286},{x:163,z:212},{x:-351,z:352},{x:-486,z:70},{x:-268,z:-102}
];
