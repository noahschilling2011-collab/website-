import * as T from './vendor/three.module.js';
// Nachbearbeitung.
//
// Bisher ging das Bild direkt aus der Szene auf den Bildschirm: ACES im
// Renderer, sonst nichts. Was dabei fehlt, ist alles, was ein Bild nach
// Kamera aussehen lässt statt nach Rasterizer — Überstrahlen heller Flächen,
// eine Farbkurve, Randabdunklung, Korn.
//
// Three.js liefert EffectComposer nur unter examples/jsm, und hier liegt
// bewusst nur three.module.js im vendor-Ordner. Also eine eigene, kurze
// Kette: Szene in ein Ziel, heller Anteil in ein halbes Ziel, zweimal
// getrennt weichzeichnen, am Ende zusammensetzen und dort erst tonwerten.
//
// Wichtig dabei: sobald das Bild durch eigene Ziele läuft, darf der Renderer
// nicht mehr selbst tonwerten. Sonst wird zweimal komprimiert und alles wird
// flach.

const QUAD = new T.PlaneGeometry(2, 2);
const KAMERA = new T.OrthographicCamera(-1, 1, 1, -1, 0, 1);

const DURCHREICHE = `
varying vec2 vUv;
void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

// Heller Anteil. Die Schwelle liegt über Weiß, damit nur wirklich helle
// Flächen strahlen: Sonne, Fenster, Lampen, Gischt — nicht die ganze Straße.
const HELL = `
uniform sampler2D bild;
uniform float schwelle, weich;
varying vec2 vUv;
void main(){
 vec3 c = texture2D(bild, vUv).rgb;
 float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
 float f = smoothstep(schwelle, schwelle + weich, l);
 gl_FragColor = vec4(c * f, 1.0);
}`;

// Getrennter Gauß in neun Abgriffen. Zwei Durchgänge statt einer 9x9-Faltung
// kosten 18 statt 81 Abgriffe.
const WEICH = `
uniform sampler2D bild;
uniform vec2 richtung;
varying vec2 vUv;
// Die Gewichte stehen einzeln statt als Array-Konstruktor: ShaderMaterial
// übersetzt hier GLSL ES 1.00, und float[5](...) gibt es dort nicht.
const float G0 = 0.2270270, G1 = 0.1945946, G2 = 0.1216216, G3 = 0.0540541, G4 = 0.0162162;
vec3 hol(vec2 uv){ return texture2D(bild, uv).rgb; }
void main(){
 vec3 summe = hol(vUv) * G0;
 summe += (hol(vUv + richtung) + hol(vUv - richtung)) * G1;
 summe += (hol(vUv + richtung * 2.0) + hol(vUv - richtung * 2.0)) * G2;
 summe += (hol(vUv + richtung * 3.0) + hol(vUv - richtung * 3.0)) * G3;
 summe += (hol(vUv + richtung * 4.0) + hol(vUv - richtung * 4.0)) * G4;
 gl_FragColor = vec4(summe, 1.0);
}`;

// Umgebungsverdeckung aus der Tiefe.
//
// Die Szene ist flach beleuchtet: eine Sonne, ein Himmelslicht. Wo zwei
// Flächen zusammenstoßen — Bordstein an Fahrbahn, Reifen an Boden, Wand an
// Gehweg — fehlt deshalb die Abdunklung, die jedes echte Foto dort hat, und
// alles wirkt aufgeklebt. Die Tiefe liegt nach dem Szenendurchgang ohnehin
// vor, also kostet das keinen zweiten Durchgang durch die Geometrie.
//
// Die Normale wird aus den Ableitungen der rekonstruierten Position
// gewonnen. Das ist ungenau an Silhouetten, reicht hier aber: die Welt
// besteht fast nur aus achsparallelen Flächen.
const AO = `
uniform sampler2D tiefe;
uniform mat4 projektion, projektionInvers;
uniform vec2 groesse;
uniform float radius, staerke, nah, fern;
varying vec2 vUv;

vec3 sichtPunkt(vec2 uv){
 float d = texture2D(tiefe, uv).x;
 vec4 clip = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
 vec4 p = projektionInvers * clip;
 return p.xyz / p.w;
}

void main(){
 float d = texture2D(tiefe, vUv).x;
 // Himmel: nichts zu verdecken.
 if(d > 0.9999){ gl_FragColor = vec4(1.0); return; }
 vec3 p = sichtPunkt(vUv);
 float abstand = -p.z;
 vec3 n = normalize(cross(dFdx(p), dFdy(p)));

 // Drehwinkel je Bildpunkt, sonst legt das feste Muster Ringe ins Bild.
 float dreh = fract(sin(dot(vUv * groesse, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
 float sichtbar = 0.0;
 const int TASTEN = 16;
 for(int i = 0; i < TASTEN; i++){
  float t = (float(i) + 0.5) / float(TASTEN);
  float a = dreh + t * 6.2831853 * 3.0;
  // Halbkugel um die Normale, angenähert über eine Scheibe im Bildraum.
  vec3 richtung = vec3(cos(a), sin(a), 0.0);
  richtung = normalize(richtung - n * dot(richtung, n) + n * 0.55);
  // Die Tasten liegen quadratisch verteilt: nah am Punkt dichter, weil dort
  // die Verdeckung entsteht, außen dünner.
  vec3 probe = p + richtung * radius * (0.12 + t * t * 0.88);
  vec4 sp = projektion * vec4(probe, 1.0);
  vec2 suv = sp.xy / sp.w * 0.5 + 0.5;
  if(suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0){ sichtbar += 1.0; continue; }
  float tiefeDort = sichtPunkt(suv).z;
  float unterschied = tiefeDort - probe.z;
  // Nur echte Nachbarschaft verdeckt; ein weit davor liegendes Objekt nicht.
  float reichweite = smoothstep(0.0, 1.0, radius / max(0.001, abs(tiefeDort - p.z)));
  // Der Schwellwert muss mit der Entfernung wachsen. Mit festen 1,5 cm hat
  // die Tiefenauflösung ab etwa hundert Metern mehr Rauschen als der
  // Schwellwert breit ist — dann galt die halbe Fahrbahn als verdeckt und
  // das ganze Bild wurde grau.
  float toleranz = 0.02 + abstand * 0.005;
  float verdeckt = smoothstep(toleranz, toleranz * 5.0, unterschied);
  sichtbar += 1.0 - verdeckt * reichweite;
 }
 float ao = sichtbar / float(TASTEN);
 // Jenseits von neunzig Metern trägt Verdeckung nichts mehr bei; dort ist
 // ohnehin Dunst.
 float naehe = 1.0 - smoothstep(35.0, 90.0, abstand);
 gl_FragColor = vec4(vec3(mix(1.0, ao, staerke * naehe)), 1.0);
}`;

// Zusammensetzen. Hier passiert alles, was den Bildeindruck trägt.
const ENDE = `
uniform sampler2D bild, glanz, verdeckung;
uniform float staerke, belichtung, koernung, zeit, vignette, saum, nacht;
uniform vec2 groesse;
varying vec2 vUv;

// ACES in der gebräuchlichen Näherung von Krzysztof Narkowicz.
vec3 aces(vec3 x){
 return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main(){
 // Farbsaum zum Rand hin: eine Linse trennt die Kanäle außen stärker als in
 // der Mitte. Sehr sparsam dosiert, sonst sieht es nach Filter aus.
 vec2 mitte = vUv - 0.5;
 float r2 = dot(mitte, mitte);
 vec2 versatz = mitte * r2 * saum;
 vec3 c;
 c.r = texture2D(bild, vUv - versatz).r;
 c.g = texture2D(bild, vUv).g;
 c.b = texture2D(bild, vUv + versatz).b;

 // Verdeckung wirkt vor dem Überstrahlen: eine Ecke, die dunkel ist, soll
 // auch nicht strahlen.
 c *= texture2D(verdeckung, vUv).r;
 c += texture2D(glanz, vUv).rgb * staerke;
 c *= belichtung;
 c = aces(c);

 // Farbkurve: Schatten leicht ins Blaugrüne, Lichter ins Warme. Der erste
 // Versuch hob die Schatten auf 0.032/0.046/0.062 — das Bild wurde dadurch
 // flacher als ohne Nachbearbeitung, also genau das Gegenteil des Ziels.
 // Jetzt eine knappe Anhebung plus eine Kontrastkurve, die sie wieder
 // hereinholt.
 vec3 schatten = vec3(0.011, 0.016, 0.023) * (1.0 - nacht * 0.35);
 vec3 lichter = vec3(1.020, 1.004, 0.974);
 c = mix(schatten, lichter, c);
 // S-Kurve um die Mitte. Ohne sie wirkt jede Anhebung wie Dunst. Nachts
 // liegt aber fast das ganze Bild unterhalb der Mitte: dieselbe Kurve drückte
 // eine Straße, die vorher lesbar war, ins Schwarze. Also nachts flacher.
 float kontrast = mix(1.11, 1.01, nacht);
 c = clamp((c - 0.5) * kontrast + 0.5, 0.0, 1.0);
 c = c * c * (3.0 - 2.0 * c) * 0.16 + c * 0.84;
 // Sättigung anheben, aber nicht in den Lichtern.
 float grau = dot(c, vec3(0.2126, 0.7152, 0.0722));
 c = mix(vec3(grau), c, 1.08 - 0.10 * grau);

 // Randabdunklung.
 // Randabdunklung nachts halbieren: dort ist der Rand ohnehin dunkel, und
 // die Vignette frisst genau die Neonschilder am Bildrand.
 c *= mix(1.0, 1.0 - vignette * (1.0 - nacht * 0.55), smoothstep(0.16, 0.72, r2));

 // Korn. Ohne Zeit im Hash steht es fest im Bild und wirkt wie Schmutz.
 // Im fast Schwarzen wird es ausgeblendet: dort ist es das einzige Signal
 // und sieht nach Videofehler aus, nicht nach Film. Am stärksten in den
 // Mitteltönen, wo echtes Korn auch sitzt.
 float rauschen = fract(sin(dot(vUv * groesse + zeit, vec2(12.9898, 78.233))) * 43758.5453);
 c += (rauschen - 0.5) * koernung * smoothstep(0.0, 0.16, grau) * (1.0 - grau * 0.55);

 // Zum Schluss von linear nach sRGB. Der Renderer nimmt einem das sonst ab,
 // aber nur für seine eigenen Materialien — ein ShaderMaterial, das direkt
 // gl_FragColor setzt, muss es selbst tun. Ohne diese Zeile kam das ganze
 // Bild etwa zwei Blenden zu dunkel heraus.
 c = clamp(c, 0.0, 1.0);
 c = mix(c * 12.92, 1.055 * pow(c, vec3(0.4166667)) - 0.055, step(vec3(0.0031308), c));
 gl_FragColor = vec4(c, 1.0);
}`;

function stufe(fragmentShader, uniforms) {
 return new T.Mesh(QUAD, new T.ShaderMaterial({uniforms, vertexShader: DURCHREICHE, fragmentShader, depthTest: false, depthWrite: false}));
}

export class Nachbearbeitung {
 constructor(renderer) {
  this.renderer = renderer;
  this.aktiv = true;
  // HalfFloat behält Werte über 1 und damit die Information, welche Fläche
  // wirklich hell ist. Wo das nicht geht, fällt die Kette auf 8 Bit zurück;
  // das Überstrahlen wird dann schwächer, aber nichts bricht.
  const typ = renderer.capabilities.isWebGL2 ? T.HalfFloatType : T.UnsignedByteType;
  const optionen = {type: typ, colorSpace: T.LinearSRGBColorSpace, depthBuffer: true};
  this.szene = new T.WebGLRenderTarget(2, 2, optionen);
  // Tiefe als Textur mitschreiben: die Verdeckung braucht sie, und ein
  // zweiter Durchgang durch die Geometrie wäre die teuerste Art, sie zu
  // bekommen.
  this.szene.depthTexture = new T.DepthTexture(2, 2);
  this.szene.depthTexture.type = T.UnsignedIntType;
  this.a = new T.WebGLRenderTarget(2, 2, {...optionen, depthBuffer: false});
  this.b = new T.WebGLRenderTarget(2, 2, {...optionen, depthBuffer: false});
  // Verdeckung in halber Auflösung, danach weichgezeichnet.
  const grau = {type: T.UnsignedByteType, colorSpace: T.LinearSRGBColorSpace, depthBuffer: false};
  this.ao1 = new T.WebGLRenderTarget(2, 2, grau);
  this.ao2 = new T.WebGLRenderTarget(2, 2, grau);

  this.aoU = {
   tiefe: {value: null}, projektion: {value: new T.Matrix4()},
   projektionInvers: {value: new T.Matrix4()}, groesse: {value: new T.Vector2(1, 1)},
   radius: {value: .6}, staerke: {value: .7}, nah: {value: .45}, fern: {value: 650}
  };
  this.ao = stufe(AO, this.aoU);
  this.hellU = {bild: {value: null}, schwelle: {value: .86}, weich: {value: .55}};
  this.weichU = {bild: {value: null}, richtung: {value: new T.Vector2()}};
  this.endeU = {
   bild: {value: null}, glanz: {value: null}, staerke: {value: .58},
   belichtung: {value: 1.2}, koernung: {value: .035}, zeit: {value: 0},
   vignette: {value: .24}, saum: {value: .0016}, nacht: {value: 0},
   verdeckung: {value: null}, groesse: {value: new T.Vector2(1, 1)}
  };
  this.hell = stufe(HELL, this.hellU);
  this.weich = stufe(WEICH, this.weichU);
  this.ende = stufe(ENDE, this.endeU);
  this.verdeckungAn = true;
  // Ersatztextur, wenn die Verdeckung aus ist: ein weißes Pixel multipliziert
  // nichts weg.
  this.weiss = new T.DataTexture(new Uint8Array([255, 255, 255, 255]), 1, 1);
  this.weiss.needsUpdate = true;
  this.gruppe = new T.Scene();
 }

 groesse(breite, hoehe) {
  const v = this.renderer.getPixelRatio();
  const w = Math.max(2, Math.floor(breite * v)), h = Math.max(2, Math.floor(hoehe * v));
  this.szene.setSize(w, h);
  const hw = Math.max(2, w >> 1), hh = Math.max(2, h >> 1);
  this.a.setSize(hw, hh);
  this.b.setSize(hw, hh);
  this.ao1.setSize(hw, hh);
  this.ao2.setSize(hw, hh);
  this.endeU.groesse.value.set(w, h);
  this.aoU.groesse.value.set(hw, hh);
 }

 zeichne(quad, ziel) {
  this.gruppe.clear();
  this.gruppe.add(quad);
  this.renderer.setRenderTarget(ziel || null);
  this.renderer.render(this.gruppe, KAMERA);
 }

 // Ersetzt renderer.render(scene, camera).
 render(scene, camera, zeit, nacht) {
  const r = this.renderer;
  if (!this.aktiv) {
   r.info.autoReset = true;
   r.toneMapping = T.ACESFilmicToneMapping;
   r.setRenderTarget(null);
   r.render(scene, camera);
   return;
  }
  // Der Renderer selbst tonwertet nicht mehr; das macht die letzte Stufe.
  r.toneMapping = T.NoToneMapping;
  // renderer.info setzt sich bei jedem render() zurück. Mit der Kette wäre
  // der letzte Wert der des Schlussvierecks: ein Draw Call, zwei Dreiecke.
  // Also einmal je Bild selbst zurücksetzen und über alle Durchgänge zählen.
  r.info.autoReset = false;
  r.info.reset();
  r.setRenderTarget(this.szene);
  r.clear();
  r.render(scene, camera);

  // Verdeckung aus der Tiefe, dann zweimal weichzeichnen: die zwölf Tasten
  // rauschen sichtbar, und Rauschen in der Verdeckung sieht aus wie Schmutz.
  if (this.verdeckungAn) {
   this.aoU.tiefe.value = this.szene.depthTexture;
   this.aoU.projektion.value.copy(camera.projectionMatrix);
   this.aoU.projektionInvers.value.copy(camera.projectionMatrixInverse);
   this.zeichne(this.ao, this.ao1);
   const ax = 1 / this.ao1.width, ay = 1 / this.ao1.height;
   this.weichU.bild.value = this.ao1.texture;
   this.weichU.richtung.value.set(ax, 0);
   this.zeichne(this.weich, this.ao2);
   this.weichU.bild.value = this.ao2.texture;
   this.weichU.richtung.value.set(0, ay);
   this.zeichne(this.weich, this.ao1);
   this.endeU.verdeckung.value = this.ao1.texture;
  } else this.endeU.verdeckung.value = this.weiss;

  this.hellU.bild.value = this.szene.texture;
  this.zeichne(this.hell, this.a);

  const bx = 1 / this.a.width, by = 1 / this.a.height;
  this.weichU.bild.value = this.a.texture;
  this.weichU.richtung.value.set(bx * 1.4, 0);
  this.zeichne(this.weich, this.b);
  this.weichU.bild.value = this.b.texture;
  this.weichU.richtung.value.set(0, by * 1.4);
  this.zeichne(this.weich, this.a);

  this.endeU.bild.value = this.szene.texture;
  this.endeU.glanz.value = this.a.texture;
  this.endeU.zeit.value = zeit % 100;
  this.endeU.nacht.value = nacht;
  this.zeichne(this.ende, null);
 }
}
