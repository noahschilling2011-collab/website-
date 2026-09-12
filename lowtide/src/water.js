import * as T from './vendor/three.module.js';
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
 return sin(p.x * 0.085 + t * 0.9) * 0.30
      + sin(p.y * 0.062 - t * 0.7) * 0.24
      + sin((p.x + p.y) * 0.041 + t * 1.35) * 0.16;
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
uniform float zeit, nacht, kuesteX, dunst;
uniform vec3 zenith, horizon, sunColor, sunDir, tief, flach;
uniform vec4 insel;          // xz-Rechteck der Insel: minX, minZ, maxX, maxZ
uniform vec3 kameraPos;
varying vec3 vWelt;
varying vec2 vEbene;

float hash(vec2 p){ return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
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
 return normalize(vec3((h - hx) * 1.5, 1.0, (h - hz) * 1.5));
}

// Abstand zur nächsten Küstenlinie: die gerade Uferkante im Westen und das
// Inselrechteck im Süden. Mehr Küste hat Solvara im Wasserbereich nicht.
float kuestenAbstand(vec2 p){
 float ufer = abs(p.x - kuesteX);
 vec2 mitte = (insel.xy + insel.zw) * 0.5, halb = (insel.zw - insel.xy) * 0.5;
 vec2 d = abs(p - mitte) - halb;
 float zurInsel = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
 return min(ufer, abs(zurInsel));
}

void main(){
 vec2 p = vWelt.xz;
 float rand = kuestenAbstand(p);
 vec3 n = kraeuselung(p, zeit);
 vec3 blick = normalize(kameraPos - vWelt);
 float fresnel = pow(1.0 - clamp(dot(n, blick), 0.0, 1.0), 4.0);
 fresnel = mix(0.03, 1.0, fresnel);

 // Die Spiegelung wird analytisch aus denselben Himmelsfarben gemischt, mit
 // denen die Kuppel gezeichnet wird — eine echte Reflexionssonde wäre für
 // eine Fläche dieser Größe zu teuer.
 vec3 spiegel = reflect(-blick, n);
 vec3 himmel = mix(horizon, zenith, clamp(spiegel.y * 1.6, 0.0, 1.0));
 float glanz = pow(max(dot(spiegel, sunDir), 0.0), 220.0);
 float schimmer = pow(max(dot(spiegel, sunDir), 0.0), 9.0);

 vec3 koerper = mix(flach, tief, smoothstep(0.0, 55.0, rand));
 vec3 farbe = mix(koerper, himmel, fresnel * 0.86);
 farbe += sunColor * glanz * 3.4 * (1.0 - nacht);
 farbe += sunColor * schimmer * 0.28 * (1.0 - nacht);

 // Brandung: ein pulsierendes Band am Ufer plus Gischtflecken davor.
 float brandung = smoothstep(7.5, 0.0, rand) * (0.55 + 0.45 * sin(rand * 1.7 - zeit * 2.2));
 float gischt = smoothstep(0.55, 0.95, noise(p * 0.6 + zeit * 0.5)) * smoothstep(26.0, 4.0, rand);
 farbe = mix(farbe, vec3(0.86, 0.90, 0.88) * (0.35 + 0.65 * (1.0 - nacht)), clamp(brandung * 0.75 + gischt * 0.4, 0.0, 0.92));
 farbe = mix(farbe, horizon, dunst * 0.25);

 gl_FragColor = vec4(farbe, 1.0);
}`;

export function createWater() {
 const uniforms = {
  zeit: {value: 0}, nacht: {value: 0}, dunst: {value: .12},
  kuesteX: {value: 119}, insel: {value: new T.Vector4(235, 150, 360, 295)},
  zenith: {value: new T.Color(0x2578cc)}, horizon: {value: new T.Color(0xc9dde2)},
  sunColor: {value: new T.Color(0xfff6e6)}, sunDir: {value: new T.Vector3(0, 1, 0)},
  tief: {value: new T.Color(0x0b3040)}, flach: {value: new T.Color(0x2f8f92)},
  kameraPos: {value: new T.Vector3()}
 };
 const material = new T.ShaderMaterial({uniforms, vertexShader: VERTEX, fragmentShader: FRAGMENT, side: T.DoubleSide});
 return {material, uniforms};
}

// Übernimmt Himmelsfarben und Sonnenstand, damit Wasser und Himmel nie
// auseinanderlaufen.
export function updateWater(uniforms, himmel, zeit, kamera) {
 uniforms.zeit.value = zeit;
 uniforms.nacht.value = himmel.nacht;
 uniforms.dunst.value = himmel.dunst;
 uniforms.zenith.value.copy(himmel.zenith);
 uniforms.horizon.value.copy(himmel.horizon);
 uniforms.sunColor.value.copy(himmel.sun);
 uniforms.sunDir.value.copy(himmel.richtung);
 // Nachts bleibt das Wasser dunkel, aber nicht schwarz — Stadtlicht am Ufer.
 uniforms.tief.value.setHex(0x0b3040).multiplyScalar(1 - himmel.nacht * .72);
 uniforms.flach.value.setHex(0x2f8f92).multiplyScalar(1 - himmel.nacht * .68);
 uniforms.kameraPos.value.copy(kamera.position);
}
