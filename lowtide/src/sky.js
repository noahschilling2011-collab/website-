import * as T from './vendor/three.module.js';
// Sonnenstand, Himmelskuppel und Belichtung für Solvara.
// Die Sonne stand vorher fest über der Stadt; Schatten haben sich nie bewegt.
// Hier läuft sie eine subtropische Bahn ab, und Himmel, Nebel, Umgebungslicht
// und Belichtung werden alle aus derselben Sonnenrichtung abgeleitet.

// Solvara liegt in den Subtropen: die Bahn ist nach Süden geneigt, nicht senkrecht,
// und der Tag ist mit dreizehn Stunden länger als zwölf. Mit der alten Zwölf-Stunden-
// Bahn ging die Sonne exakt um 18:00 unter und der Abend war schlagartig Nacht.
const BAHNNEIGUNG = .42, SONNENAUFGANG = 6.3, TAGLAENGE = 13;

export function sunDirection(hour, out = new T.Vector3()) {
 const t = (hour - SONNENAUFGANG) / TAGLAENGE * Math.PI; // 0 = Aufgang, π = Untergang
 return out.set(-Math.cos(t), Math.sin(t), BAHNNEIGUNG * Math.cos(t) + .3).normalize();
}

// Stützstellen über den Tag. Zwischen ihnen wird linear in RGB gemischt —
// gut genug, weil die Abstände klein sind und die Farben nah beieinander liegen.
// [Stunde, Zenit, Horizont, Sonnenfarbe, Sonnenstärke, Himmelslicht, Belichtung]
const STUeTZSTELLEN = [
 [0.0, 0x050a16, 0x0b1420, 0x3c4f78, 0.06, 0.20, 1.45],
 [4.6, 0x0a1428, 0x1d2436, 0x6b5a78, 0.10, 0.26, 1.40],
 [6.4, 0x28406a, 0x7d5a56, 0xff8f52, 0.85, 0.52, 1.20],
 [7.2, 0x2b5f9e, 0x9fb0b4, 0xffc48c, 1.75, 0.60, 1.00],
 [10.0, 0x2a72c0, 0xc2d2d0, 0xffeecb, 2.45, 0.74, 0.94],
 [13.0, 0x2578cc, 0xcedcd6, 0xfff2d8, 2.70, 0.80, 0.90],
 [16.3, 0x2f70b8, 0xcbcdbe, 0xffdea2, 2.15, 0.72, 0.96],
 [18.4, 0x3a5c92, 0xd8996a, 0xff9450, 1.45, 0.64, 1.02],
 [19.4, 0x1d3560, 0x8a5566, 0xd6684e, 0.45, 0.38, 1.28],
 [20.6, 0x0a1730, 0x2a2740, 0x6a4a66, 0.12, 0.24, 1.45],
 [24.0, 0x050a16, 0x0b1420, 0x3c4f78, 0.06, 0.20, 1.45]
];

const mischFarbe = new T.Color(), zweiteFarbe = new T.Color();
function mische(a, b, t, ziel) { ziel.setHex(a); zweiteFarbe.setHex(b); return ziel.lerp(zweiteFarbe, t); }

// Wetterlagen dämpfen Sonne und Sättigung und heben den Dunst an.
const WETTER = {
 clear: {sonne: 1, dunst: .12, wolken: .18, nebel: .0022, graustich: 0, streuung: 1},
 rain: {sonne: .38, dunst: .62, wolken: .88, nebel: .0075, graustich: .55, streuung: 1.5},
 fog: {sonne: .30, dunst: .95, wolken: .55, nebel: .0135, graustich: .62, streuung: 1.7},
 storm: {sonne: .22, dunst: .70, wolken: .97, nebel: .0090, graustich: .68, streuung: 1.3}
};

const zustand = {
 zenith: new T.Color(), horizon: new T.Color(), sun: new T.Color(),
 boden: new T.Color(), nebel: new T.Color(),
 sonnenStaerke: 0, himmelStaerke: 0, belichtung: 1, nacht: 0, nebelDichte: .003,
 richtung: new T.Vector3()
};

export function skyState(hour, weather = 'clear') {
 const h = ((hour % 24) + 24) % 24;
 let i = 0;
 while (i < STUeTZSTELLEN.length - 2 && STUeTZSTELLEN[i + 1][0] <= h) i++;
 const a = STUeTZSTELLEN[i], b = STUeTZSTELLEN[i + 1];
 const t = (h - a[0]) / Math.max(.001, b[0] - a[0]);
 const w = WETTER[weather] || WETTER.clear;

 mische(a[1], b[1], t, zustand.zenith);
 mische(a[2], b[2], t, zustand.horizon);
 mische(a[3], b[3], t, zustand.sun);
 zustand.sonnenStaerke = (a[4] + (b[4] - a[4]) * t) * w.sonne;
 // Unter einer geschlossenen Decke kommt weniger direktes, aber mehr
 // gestreutes Licht an — sonst wirkt jedes Schlechtwetter wie Nacht.
 zustand.himmelStaerke = (a[5] + (b[5] - a[5]) * t) * w.streuung;
 zustand.belichtung = a[6] + (b[6] - a[6]) * t;

 // Bei schlechtem Wetter zieht alles Richtung Blaugrau, aber nie ganz.
 if (w.graustich) {
  const grau = mischFarbe.setHex(0x6f8089).multiplyScalar(.35 + zustand.himmelStaerke * .45);
  zustand.zenith.lerp(grau, w.graustich * .85);
  zustand.horizon.lerp(grau, w.graustich * .7);
  zustand.sun.lerp(grau, w.graustich * .5);
 }
 sunDirection(h, zustand.richtung);
 zustand.nacht = 1 - Math.min(1, Math.max(0, zustand.richtung.y + .12) * 4.5);
 // Der Nebel nimmt die Horizontfarbe an, sonst steht ferne Geometrie als
 // fremdfarbiges Band vor dem Himmel.
 zustand.nebel.copy(zustand.horizon).multiplyScalar(1.08);
 zustand.nebelDichte = w.nebel;
 zustand.boden.copy(zustand.horizon).multiplyScalar(.42).lerp(mischFarbe.setHex(0x2c3730), .5);
 zustand.dunst = w.dunst;
 zustand.wolken = w.wolken;
 return zustand;
}

const HIMMEL_VERTEX = `
varying vec3 vDir;
void main(){ vDir = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`;

const HIMMEL_FRAGMENT = `
uniform vec3 zenith, horizon, ground, sunColor, sunDir;
uniform float dunst, wolken, nacht, zeit;
varying vec3 vDir;

// Gleicher Grund wie in water.js: der sin-Hash bandet bei großen Werten.
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
float fbm(vec2 p){
 float v = 0.0, a = 0.5;
 for (int k = 0; k < 4; k++){ v += a * noise(p); p *= 2.07; a *= 0.5; }
 return v;
}

void main(){
 vec3 d = normalize(vDir);
 float up = d.y;
 float sonne = max(dot(d, sunDir), 0.0);

 // Grundverlauf: der Horizont bleibt breiter, je diesiger es ist.
 float t = pow(1.0 - clamp(up, 0.0, 1.0), mix(3.4, 1.5, dunst));
 vec3 farbe = mix(zenith, horizon, t);

 // Mie-artige Vorwärtsstreuung: der helle Hof um die Sonne.
 farbe += sunColor * pow(sonne, 7.0) * 0.55 * (1.0 - nacht);
 farbe += sunColor * pow(sonne, 1.6) * 0.13 * t * (1.0 - nacht);

 // Wolkenband. Die Projektion auf y drückt es zum Horizont hin zusammen,
 // sonst schwimmt es als Scheibe über dem Kopf.
 float hoehe = max(up, 0.03);
 vec2 wp = d.xz / hoehe * 0.55 + vec2(zeit * 0.004, zeit * 0.0016);
 float decke = fbm(wp) * 0.62 + fbm(wp * 2.6 + 11.0) * 0.38;
 float maske = smoothstep(0.62 - wolken * 0.42, 0.92 - wolken * 0.28, decke)
             * smoothstep(0.0, 0.16, up) * (0.25 + wolken * 0.75);
 vec3 wolkenFarbe = mix(horizon * 1.22, sunColor * 0.9 + horizon * 0.4, pow(sonne, 3.0) * 0.7);
 wolkenFarbe = mix(wolkenFarbe * 0.55, wolkenFarbe, 1.0 - nacht * 0.8);
 farbe = mix(farbe, wolkenFarbe, maske);

 // Sonnenscheibe. Der weiche Rand verhindert das Aliasing-Flimmern.
 farbe += sunColor * smoothstep(0.99955, 0.99988, sonne) * 7.0 * (1.0 - dunst * 0.8);

 // Sterne nur nachts und nur oberhalb des Dunstes.
 if (nacht > 0.05){
  vec2 sp = floor(d.xz / max(abs(up), 0.05) * 92.0);
  float stern = step(0.9965, hash(sp)) * smoothstep(0.05, 0.35, up);
  float funkeln = 0.55 + 0.45 * sin(zeit * 2.3 + hash(sp + 3.0) * 40.0);
  farbe += vec3(0.85, 0.9, 1.0) * stern * funkeln * nacht * (1.0 - maske) * (1.0 - dunst * 0.9);
 }

 // Unterhalb des Horizonts steht die Gelände-/Wasserebene; ein weicher
 // Übergang verhindert die harte Kante bei tiefer Kamera.
 farbe = mix(ground, farbe, smoothstep(-0.10, 0.015, up));
 gl_FragColor = vec4(farbe, 1.0);
}`;

export class Sky {
 constructor(renderer) {
  this.renderer = renderer;
  this.uniforms = {
   zenith: {value: new T.Color()}, horizon: {value: new T.Color()},
   ground: {value: new T.Color()}, sunColor: {value: new T.Color()},
   sunDir: {value: new T.Vector3(0, 1, 0)},
   dunst: {value: .12}, wolken: {value: .2}, nacht: {value: 0}, zeit: {value: 0}
  };
  this.material = new T.ShaderMaterial({
   uniforms: this.uniforms, vertexShader: HIMMEL_VERTEX, fragmentShader: HIMMEL_FRAGMENT,
   side: T.BackSide, depthWrite: false, fog: false
  });
  this.mesh = new T.Mesh(new T.SphereGeometry(600, 32, 20), this.material);
  this.mesh.frustumCulled = false;
  this.mesh.renderOrder = -1;

  // Eigene Szene nur für die Kuppel: daraus entsteht die Umgebungsreflexion,
  // ohne dass Stadtgeometrie in die Environment-Map gerät.
  this.envScene = new T.Scene();
  this.envMesh = new T.Mesh(this.mesh.geometry, this.material);
  this.envMesh.frustumCulled = false;
  this.envScene.add(this.envMesh);
  this.pmrem = new T.PMREMGenerator(renderer);
  this.pmrem.compileEquirectangularShader();
  this.envTarget = null;
  this.envStempel = null;
 }

 // Liefert den aktuellen Zustand und aktualisiert die Kuppel.
 update(hour, weather, kameraPosition, zeit) {
  const s = skyState(hour, weather);
  const u = this.uniforms;
  u.zenith.value.copy(s.zenith);
  u.horizon.value.copy(s.horizon);
  u.ground.value.copy(s.boden);
  u.sunColor.value.copy(s.sun);
  u.sunDir.value.copy(s.richtung);
  u.dunst.value = s.dunst;
  u.wolken.value = s.wolken;
  u.nacht.value = s.nacht;
  u.zeit.value = zeit;
  if (kameraPosition) this.mesh.position.copy(kameraPosition);
  return s;
 }

 // Die Environment-Map ist teuer. Sie wird nur neu gerechnet, wenn sich
 // Sonnenstand oder Wetter merklich geändert haben — im Spiel etwa alle
 // zwölf Spielminuten, nicht pro Frame.
 refreshEnvironment(hour, weather) {
  const stempel = weather + ':' + Math.round(hour * 5);
  if (stempel === this.envStempel) return null;
  this.envStempel = stempel;
  const alt = this.envTarget;
  this.envTarget = this.pmrem.fromScene(this.envScene, 0, 1, 1200);
  alt?.dispose();
  return this.envTarget.texture;
 }

 dispose() {
  this.mesh.geometry.dispose();
  this.material.dispose();
  this.envTarget?.dispose();
  this.pmrem.dispose();
 }
}
