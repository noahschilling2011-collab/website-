import * as T from './vendor/three.module.js';
// Oberflächendetail.
//
// Die Welt besteht aus einfarbigen Kisten. Bei Tageslicht sieht jede Fläche
// aus wie lackierter Karton: kein Korn, kein Fleck, keine Struktur. Genau
// das ist der Abstand zu einem fotografierten Bild, größer als jede Frage
// der Polygonzahl.
//
// Eine Textur pro Material ginge nicht: dieselbe Kistengeometrie wird für
// eine 240 m große Bodenplatte und einen 20 cm großen Poller benutzt, die
// UV-Koordinaten laufen in beiden Fällen von 0 bis 1. Die Struktur muss also
// aus der Weltposition kommen, nicht aus der UV — dreifach projiziert, damit
// sie auf allen drei Achsen stimmt.
//
// Erzeugt wird sie im Shader statt als Bild: eine Textur, die auf allen
// Maßstäben trägt, wäre groß, und die HTML soll eigenständig bleiben.

const EINSATZ = `
// Wertrauschen ohne sin: derselbe Grund wie in water.js — fract(sin(x)*k)
// verliert bei Weltkoordinaten in den Hunderten die Auflösung.
float dHash(vec3 p){
 p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
 p *= 17.0;
 return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float dNoise(vec3 x){
 vec3 i = floor(x), f = fract(x);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(mix(dHash(i + vec3(0,0,0)), dHash(i + vec3(1,0,0)), f.x),
                mix(dHash(i + vec3(0,1,0)), dHash(i + vec3(1,1,0)), f.x), f.y),
            mix(mix(dHash(i + vec3(0,0,1)), dHash(i + vec3(1,0,1)), f.x),
                mix(dHash(i + vec3(0,1,1)), dHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
// Zwei Oktaven: eine grobe für Flecken, eine feine für Korn. Die dritte war
// bei jedem Bildpunkt acht weitere Hashwerte wert und im Bild nicht zu sehen.
float dStruktur(vec3 p){
 return dNoise(p * 0.21) * 0.68 + dNoise(p * 1.35) * 0.32;
}
`;

// Nässe. Ein gemeinsames Uniform für alle Weltmaterialien: bei Regen werden
// waagerechte Flächen dunkler und glatter, senkrechte nicht. Das ist der
// sichtbarste Teil von Regen überhaupt — nasse Fahrbahn spiegelt, nasse
// Hauswand tut fast nichts.
export const NAESSE = {value: 0};

// Hängt sich in ein bestehendes MeshStandardMaterial ein, ohne es zu ersetzen.
// staerke steuert, wie stark Farbe und Rauheit schwanken; relief wie stark die
// Normale gestört wird.
export function detailAufsetzen(material, staerke = .13, relief = .5) {
 if (material.userData.detail) return material;
 material.userData.detail = true;
 material.onBeforeCompile = shader => {
  shader.uniforms.dStaerke = {value: staerke};
  shader.uniforms.dRelief = {value: relief};
  shader.uniforms.dNass = NAESSE;
  shader.vertexShader = shader.vertexShader
   .replace('#include <common>', '#include <common>\nvarying vec3 dWelt;\nvarying vec3 dWNormal;')
   // Die Weltposition muss die Instanzmatrix einschließen. Ohne sie liegt
   // transformed bei jeder Kiste zwischen -0,5 und 0,5, egal wie groß und wo
   // sie steht — die Struktur wäre auf jeder Fläche dieselbe und stünde
   // nicht in der Welt, sondern auf dem Objekt.
   .replace('#include <begin_vertex>', `#include <begin_vertex>
   {
    vec4 dP = vec4(transformed, 1.0);
    mat3 dM = mat3(modelMatrix);
    #ifdef USE_INSTANCING
     dP = instanceMatrix * dP;
     dM = dM * mat3(instanceMatrix);
    #endif
    dWelt = (modelMatrix * dP).xyz;
    dWNormal = normalize(dM * objectNormal);
   }`);
  shader.fragmentShader = shader.fragmentShader
   .replace('#include <common>', '#include <common>\nvarying vec3 dWelt;\nvarying vec3 dWNormal;\nuniform float dStaerke, dRelief, dNass;\n' + EINSATZ)
   // Farbe: helle und dunkle Flecken, wie sie jede echte Fläche hat. Der
   // Wert wird einmal berechnet und unten für die Rauheit wiederverwendet —
   // zwei getrennte Auswertungen sahen gleich aus und kosteten doppelt.
   .replace('#include <color_fragment>', `#include <color_fragment>
   float dWert = dStruktur(dWelt);
   diffuseColor.rgb *= 1.0 + (dWert - 0.5) * dStaerke * 2.0;
   // Nass wird nur, was oben liegt. Pfützen sammeln sich in den Senken der
   // groben Oktave, also dort, wo dWert klein ist.
   float dOben = smoothstep(0.45, 0.85, dWNormal.y);
   float dPfuetze = dNass * dOben * smoothstep(0.62, 0.28, dWert);
   diffuseColor.rgb *= 1.0 - dNass * dOben * 0.30 - dPfuetze * 0.16;`)
   // Rauheit: gleichmäßig glänzende Flächen sind das sicherste Zeichen für
   // ein Rendering. Die Schwankung nimmt dem Bild diesen Zug.
   .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
   roughnessFactor = clamp(roughnessFactor + (dWert - 0.5) * 0.34, 0.05, 1.0);
   roughnessFactor = mix(roughnessFactor, 0.09, clamp(dPfuetze * 1.25 + dNass * dOben * 0.45, 0.0, 0.92));`)
   // metalnessFactor wird erst im nächsten Baustein angelegt; im
   // Rauheitsblock gäbe es dafür einen Übersetzungsfehler.
   .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
   metalnessFactor = mix(metalnessFactor, 0.22, dNass * dOben * 0.7);`)
   // Normale: Vorwärtsdifferenzen einer einzelnen Oktave, und nur in der
   // Nähe. Zentrale Differenzen über beide Oktaven waren sechs volle
   // Auswertungen je Bildpunkt; sichtbar ist der Unterschied nicht.
   .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
   float dNah = 1.0 - smoothstep(45.0, 120.0, length(vViewPosition));
   if(dNah > 0.02){
    float e = 0.16, b = dNoise(dWelt * 1.35);
    vec3 g = vec3(
     dNoise((dWelt + vec3(e,0.0,0.0)) * 1.35) - b,
     dNoise((dWelt + vec3(0.0,e,0.0)) * 1.35) - b,
     dNoise((dWelt + vec3(0.0,0.0,e)) * 1.35) - b);
    normal = normalize(normal + (viewMatrix * vec4(g, 0.0)).xyz * dRelief * dNah * 3.0);
   }`);
 };
 // three schlüsselt kompilierte Programme nach den Materialparametern, nicht
 // nach onBeforeCompile. Ohne eigenen Schlüssel könnte ein Material ohne
 // Struktur das Programm eines Materials mit Struktur wiederverwenden — oder
 // umgekehrt. Der Schlüssel trennt beide Familien sauber.
 material.customProgramCacheKey = () => 'lowtide-detail';
 material.needsUpdate = true;
 return material;
}
