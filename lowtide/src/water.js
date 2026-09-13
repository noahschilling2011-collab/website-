import * as T from './vendor/three.module.js';
import {INSELN, DAEMME} from './content.js';
// Wasser für Solvara.
// Vorher: eine Ebene mit zwei Farben und einer Sinuswelle, ohne Reflexion,
// ohne Schaum, ohne Bezug zum Sonnenstand. Wasser ist in dieser Stadt aber
// fast überall im Bild, also lohnt sich hier mehr als anderswo.

const VERTEX = `
uniform float zeit;
varying vec3 vWelt;
varying vec2 vEbene;

// Drei Wellenzüge unterschiedlicher Richtung und Länge; die Summe bricht das
// Muster auf, das eine einzelne Sinuswelle unweigerlich zeigt.
float welle(vec2 p, float t){
 return sin(p.x * 0.085 + t * 0.9) * 0.22
      + sin(p.y * 0.062 - t * 0.7) * 0.17
      + sin((p.x + p.y) * 0.041 + t * 1.35) * 0.11;
}

void main(){
 vec3 p = position;
 vEbene = p.xy;
 p.z += welle(p.xy, zeit);
 vec4 welt = modelMatrix * vec4(p, 1.0);
 vWelt = welt.xyz;
 gl_Position = projectionMatrix * viewMatrix * welt;
}`;

const FRAGMENT = `
uniform float zeit, nacht, kuesteX, dunst, art;
uniform vec4 seeRect;   // Uferrechteck des Stausees, nur bei art > 1.5
uniform float kraeuselStaerke;
uniform vec3 zenith, horizon, sunColor, sunDir, tief, flach;
#define LANDZAHL __LANDZAHL__
uniform vec4 land[LANDZAHL];  // xz-Rechtecke von Inseln und Dämmen: minX, minZ, maxX, maxZ
uniform vec3 kameraPos;
varying vec3 vWelt;
varying vec2 vEbene;

// Der übliche sin-Hash bricht zusammen, sobald die Koordinaten in die
// Hunderte gehen: fract(sin(x)*43758) hat bei x um 30000 in float32 keine
// Auflösung mehr und liefert statt Rauschen breite Bänder — auf dem Wasser
// waren das dutzende Meter große Flecken. Diese Variante kommt ohne sin aus,
// und der Definitionsbereich wird zusätzlich gefaltet.
float hash(vec2 p){
 p = mod(p, 512.0);
 vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
 q += dot(q, q.yzx + 33.33);
 return fract((q.x + q.y) * q.z);
}
float noise(vec2 p){
 vec2 i = floor(p), f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
            mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

// Feine Kräuselung als Normalenstörung. Die Geometrie ist dafür viel zu grob;
// alles unterhalb der Segmentgröße muss über die Normale kommen.
vec3 kraeuselung(vec2 p, float t){
 float e = 0.6;
 vec2 q = p * 0.5 + vec2(t * 0.35, -t * 0.22);
 float h  = noise(q) + noise(q * 2.3 + 5.0) * 0.5 + noise(q * 5.1 - 3.0) * 0.25;
 float hx = noise(q + vec2(e,0.0)) + noise((q + vec2(e,0.0)) * 2.3 + 5.0) * 0.5 + noise((q + vec2(e,0.0)) * 5.1 - 3.0) * 0.25;
 float hz = noise(q + vec2(0.0,e)) + noise((q + vec2(0.0,e)) * 2.3 + 5.0) * 0.5 + noise((q + vec2(0.0,e)) * 5.1 - 3.0) * 0.25;
 // Der Faktor war fest 1,5 und damit für jedes Gewässer gleich steil. Auf
 // einem Binnensee ergab das eine weiße Decke: die Fresnelzahl springt bei
 // steilen Normalen zwischen 0,03 und 1, und damit wechselt jeder zweite
 // Bildpunkt zwischen Wasserkörper und hellem Himmel. Ein See kräuselt
 // flacher als offene See.
 return normalize(vec3((h - hx) * kraeuselStaerke, 1.0, (h - hz) * kraeuselStaerke));
}

// Abstand zur nächsten Küstenlinie: die gerade Uferkante im Westen und das
// Inselrechteck im Süden. Mehr Küste hat Solvara im Wasserbereich nicht.
float kuestenAbstand(vec2 p){
 // Ein Binnensee hat keine Küstenlinie im Sinne des Ozeans: sein Ufer ist
 // der Rand seines eigenen Rechtecks, von innen gesehen. Ohne diesen Zweig
 // läge die Brandung an einer Geraden irgendwo östlich in der Stadt.
 if(art > 1.5){
  vec2 m = (seeRect.xy + seeRect.zw) * 0.5, h = (seeRect.zw - seeRect.xy) * 0.5;
  vec2 d = abs(p - m) - h;
  return abs(length(max(d, 0.0)) + min(max(d.x, d.y), 0.0));
 }
 float nah = abs(p.x - kuesteX);
 for(int i = 0; i < LANDZAHL; i++){
  vec2 mitte = (land[i].xy + land[i].zw) * 0.5, halb = (land[i].zw - land[i].xy) * 0.5;
  vec2 d = abs(p - mitte) - halb;
  float zum = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
  nah = min(nah, abs(zum));
 }
 return nah;
}

void main(){
 vec2 p = vWelt.xz;
 float rand = kuestenAbstand(p);
 float sicht = length(kameraPos - vWelt);
 // Ab etwa 120 m glättet sich die Normale zur ruhigen Ebene.
 float schaerfe = exp(-sicht * 0.0085);
 vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), kraeuselung(p, zeit), schaerfe));
 vec3 blick = normalize(kameraPos - vWelt);
 float fresnel = pow(1.0 - clamp(dot(n, blick), 0.0, 1.0), 4.0);
 fresnel = mix(0.03, 1.0, fresnel);

 // Die Spiegelung wird analytisch aus denselben Himmelsfarben gemischt, mit
 // denen die Kuppel gezeichnet wird — eine echte Reflexionssonde wäre für
 // eine Fläche dieser Größe zu teuer.
 vec3 spiegel = reflect(-blick, n);
 vec3 himmel = mix(horizon, zenith, clamp(spiegel.y * 1.6, 0.0, 1.0));
 // Der Glitzerpfad. Ohne ihn lag das Sonnenlicht als weiße Decke über der
 // ganzen Fläche: die Kräuselung streut die Spiegelrichtung so weit, dass
 // die enge Sonnenkeule überall irgendwo getroffen wird. Draußen sitzt das
 // Glitzern in einem Band zwischen Auge und Sonne, und außerhalb davon ist
 // Wasser dunkel. Maßgeblich dafür ist die Spiegelrichtung der ruhigen
 // Ebene, nicht die der einzelnen Welle.
 vec3 spiegelEben = reflect(-blick, vec3(0.0, 1.0, 0.0));
 float pfad = pow(max(dot(spiegelEben, sunDir), 0.0), 2.2);
 float glanz = pow(max(dot(spiegel, sunDir), 0.0), 220.0) * pfad;
 float schimmer = pow(max(dot(spiegel, sunDir), 0.0), 9.0) * pfad;

 // Der Übergang von Flach- zu Tiefwasser lag bei 55 m und legte einen
 // türkisen Ring um jede Küste.
 vec3 koerper = mix(flach, tief, smoothstep(0.0, 30.0, rand));
 vec3 farbe = mix(koerper, himmel, fresnel * 0.86);
 farbe += sunColor * glanz * 3.4 * (1.0 - nacht) * schaerfe;
 farbe += sunColor * schimmer * 0.28 * (1.0 - nacht);

 // Brandung: ein pulsierendes Band am Ufer plus Gischtflecken davor.
 float brandung = smoothstep(4.2, 0.0, rand) * (0.45 + 0.4 * sin(rand * 1.9 - zeit * 2.2));
 float gischt = smoothstep(0.55, 0.95, noise(p * 0.6 + zeit * 0.5)) * smoothstep(26.0, 4.0, rand) * schaerfe;
 farbe = mix(farbe, vec3(0.86, 0.90, 0.88) * (0.35 + 0.65 * (1.0 - nacht)), clamp(brandung * 0.62 + gischt * 0.28, 0.0, 0.85));
 farbe = mix(farbe, horizon, dunst * 0.25);

 // Der Alphakanal trägt keine Deckung, sondern eine Marke: 0,5 heißt Wasser.
 // Das Szenenziel wird nur über RGB weitergelesen, also ist der Kanal frei,
 // und die Spiegelung in post.js braucht eine Kennung, die sie nicht raten
 // muss. Über die Höhe ginge es nicht — Kai, Strand und Uferstraße liegen
 // ebenfalls fast auf null. Undurchsichtige Flächen schreiben 1,0, der
 // Himmel auch, gelöscht wird auf 0,0: 0,5 kollidiert mit keinem davon.
 gl_FragColor = vec4(farbe, 0.5);
}`;

// Inseln und Dämme als Vector4 für den Shader. Der Sumpf im Westen hat keine
// Inseln, bekommt aber dieselbe Liste — sein kuesteX liegt weit weg, und die
// Schleife kostet bei sieben Rechtecken nichts.
const LANDRECHTECKE = [...INSELN, ...DAEMME].map(r => new T.Vector4(r.x1, r.z1, r.x2, r.z2));

// art: 'ozean' oder 'sumpf'. Der Sumpf ist flach, trüb und grünbraun;
// mit den Ozeanfarben wurde er zur Tiefsee.
export function createWater(art = 'ozean') {
 const sumpf = art === 'sumpf', see = art === 'see';
 const uniforms = {
  zeit: {value: 0}, nacht: {value: 0}, dunst: {value: .12},
  art: {value: see ? 2 : sumpf ? 1 : 0},
  seeRect: {value: new T.Vector4(-803, 3, -597, 157)},
  kraeuselStaerke: {value: see ? .34 : sumpf ? .6 : .8},
  kuesteX: {value: sumpf ? -400 : 119}, land: {value: LANDRECHTECKE},
  zenith: {value: new T.Color(0x2578cc)}, horizon: {value: new T.Color(0xc9dde2)},
  sunColor: {value: new T.Color(0xfff6e6)}, sunDir: {value: new T.Vector3(0, 1, 0)},
  tief: {value: new T.Color(0x0b3040)}, flach: {value: new T.Color(0x2f8f92)},
  kameraPos: {value: new T.Vector3()}
 };
 const material = new T.ShaderMaterial({uniforms, vertexShader: VERTEX,
  fragmentShader: FRAGMENT.replace('__LANDZAHL__', String(LANDRECHTECKE.length)), side: T.DoubleSide});
 return {material, uniforms, art};
}

// Übernimmt Himmelsfarben und Sonnenstand, damit Wasser und Himmel nie
// auseinanderlaufen.
export function updateWater(uniforms, himmel, zeit, kamera) {
 const sumpf = uniforms.art.value > .5 && uniforms.art.value < 1.5;
 const see = uniforms.art.value > 1.5;
 uniforms.zeit.value = zeit;
 uniforms.nacht.value = himmel.nacht;
 uniforms.dunst.value = himmel.dunst;
 uniforms.zenith.value.copy(himmel.zenith);
 uniforms.horizon.value.copy(himmel.horizon);
 uniforms.sunColor.value.copy(himmel.sun);
 uniforms.sunDir.value.copy(himmel.richtung);
 // Nachts bleibt das Wasser dunkel, aber nicht schwarz — Stadtlicht am Ufer.
 // Süßwasser über Fels ist grüner und weniger türkis als die Küste.
 uniforms.tief.value.setHex(see ? 0x14343a : sumpf ? 0x2c3b2a : 0x0b3040).multiplyScalar(1 - himmel.nacht * .72);
 uniforms.flach.value.setHex(see ? 0x35706a : sumpf ? 0x46543a : 0x2c7a80).multiplyScalar(1 - himmel.nacht * .68);
 uniforms.kameraPos.value.copy(kamera.position);
}
