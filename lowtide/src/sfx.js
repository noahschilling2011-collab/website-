// Klang.
// Die Welt hatte zwei Geräusche: den Motor-Oszillator und einen Schuss. Dazu
// das Radio, das nur im Wagen läuft. Wer zu Fuß durch Port Mercy ging, hörte
// nichts — kein Schritt, kein Wind, keine Brandung, keine Sirene, obwohl
// Wetter, Wasser und Fahndungsstufe alle im Zustand stehen und abgefragt
// werden könnten.
//
// Alles hier ist erzeugt, keine Datei: ein Rauschpuffer und ein paar
// Oszillatoren, dieselbe Bauweise wie das Radio. Drei Dauerquellen (Wind,
// Regen, Brandung) hängen an einem Regler und werden nur lauter und leiser;
// die Einmaligen (Schritt, Aufprall, Nachladen) bauen ihre Knoten je Anlass
// und trennen sie in onended wieder ab, damit nichts anwächst.

const KLEMME = (v, a, b) => Math.max(a, Math.min(b, v));

// Wetterabhängige Pegel. Nebel ist nicht still — er dämpft die Ferne und
// lässt die Nähe lauter wirken; deshalb mehr Wind als bei klarem Himmel.
const WIND = {clear: .010, fog: .019, rain: .026, storm: .062};
const REGEN = {clear: 0, fog: 0, rain: .034, storm: .080};

export class Klang {
 constructor(ctx) {
  this.ctx = ctx;
  this.an = true;
  this.summe = ctx.createGain();
  this.summe.gain.value = 1;
  this.summe.connect(ctx.destination);

  // Ein Rauschpuffer für alles: zwei Sekunden, in Schleife. Ein eigener
  // Puffer je Quelle wäre dieselbe Zahl viermal im Speicher.
  const laenge = ctx.sampleRate * 2;
  this.rauschen = ctx.createBuffer(1, laenge, ctx.sampleRate);
  const d = this.rauschen.getChannelData(0);
  let s = 22222;
  for (let i = 0; i < laenge; i++) {s = (s * 1664525 + 1013904223) >>> 0; d[i] = s / 2147483648 - 1;}

  this.wind = this.dauerquelle(420, 'lowpass', .9);
  this.regen = this.dauerquelle(1400, 'highpass', .7);
  this.brandung = this.dauerquelle(520, 'bandpass', 1.1);
  // Die Brandung atmet: ein sehr langsamer Oszillator auf ihrem Regler.
  this.welle = ctx.createOscillator();
  this.welle.frequency.value = .13;
  this.welleTiefe = ctx.createGain();
  this.welleTiefe.gain.value = 0;
  this.welle.connect(this.welleTiefe).connect(this.brandung.regler.gain);
  this.welle.start();

  // Sirene: zwei Töne im Wechsel, nicht ein Sägezahn. Der Wechsel steckt in
  // einem Rechteck-Oszillator auf der Frequenz.
  this.sirene = ctx.createOscillator();
  this.sirene.type = 'square';
  this.sirene.frequency.value = 640;
  this.sirenenRegler = ctx.createGain();
  this.sirenenRegler.gain.value = 0;
  this.sirenenWechsel = ctx.createOscillator();
  this.sirenenWechsel.type = 'square';
  this.sirenenWechsel.frequency.value = 1.6;
  this.sirenenHub = ctx.createGain();
  this.sirenenHub.gain.value = 190;
  this.sirenenWechsel.connect(this.sirenenHub).connect(this.sirene.frequency);
  this.sirene.connect(this.sirenenRegler).connect(this.summe);
  this.sirene.start(); this.sirenenWechsel.start();

  this.schrittWeg = 0;
  // Buchführung über die einmaligen Klänge. Der erste Anlauf zählte mit einem
  // Zähler hoch und in onended wieder herunter — und stand im Regressionslauf
  // bei **minus vierzig**. Ein Zähler, der negativ werden kann, ist als
  // Nachweis gegen ein Leck wertlos: er kann ein Leck genauso gut verdecken.
  // Eine Menge lebender Knoten kann das nicht. Doppeltes onended entfernt
  // denselben Eintrag zweimal und bleibt dabei richtig.
  this.lebend = new Set();
  this.gebaut = 0;
 }

 // Eine Dauerquelle: Rauschen in Schleife durch ein Filter auf einen Regler.
 dauerquelle(frequenz, art, guete) {
  const q = this.ctx.createBufferSource();
  q.buffer = this.rauschen; q.loop = true;
  const f = this.ctx.createBiquadFilter();
  f.type = art; f.frequency.value = frequenz; f.Q.value = guete;
  const regler = this.ctx.createGain();
  regler.gain.value = 0;
  q.connect(f).connect(regler).connect(this.summe);
  q.start();
  return {quelle: q, filter: f, regler};
 }

 // Weich nachziehen, damit ein Wetterwechsel nicht klickt.
 ziehe(regler, ziel, dt, zeit = .8) {
  const g = regler.gain;
  g.value += (ziel - g.value) * KLEMME(dt / zeit, 0, 1);
 }

 // Ein einmaliger Klang aus Rauschen. Die Knoten trennen sich selbst ab.
 stoss(frequenz, art, guete, pegel, dauer) {
  if (!this.an) return;
  const t = this.ctx.currentTime;
  const q = this.ctx.createBufferSource();
  q.buffer = this.rauschen;
  q.playbackRate.value = .8 + Math.random() * .5;
  const f = this.ctx.createBiquadFilter();
  f.type = art; f.frequency.value = frequenz; f.Q.value = guete;
  const g = this.ctx.createGain();
  g.gain.setValueAtTime(pegel, t);
  g.gain.exponentialRampToValueAtTime(.0001, t + dauer);
  q.connect(f).connect(g).connect(this.summe);
  q.start(t); q.stop(t + dauer);
  this.gebaut++;
  this.lebend.add(q);
  q.onended = () => {q.disconnect(); f.disconnect(); g.disconnect(); this.lebend.delete(q);};
 }

 // Ein einmaliger Ton, der abfällt — für den dumpfen Teil eines Aufpralls.
 schlag(von, nach, pegel, dauer, art = 'sine') {
  if (!this.an) return;
  const t = this.ctx.currentTime;
  const o = this.ctx.createOscillator(), g = this.ctx.createGain();
  o.type = art;
  o.frequency.setValueAtTime(von, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(20, nach), t + dauer);
  g.gain.setValueAtTime(pegel, t);
  g.gain.exponentialRampToValueAtTime(.0001, t + dauer);
  o.connect(g).connect(this.summe);
  o.start(t); o.stop(t + dauer);
  this.gebaut++;
  this.lebend.add(o);
  o.onended = () => {o.disconnect(); g.disconnect(); this.lebend.delete(o);};
 }

 schritt(geduckt, rennt) {
  this.stoss(geduckt ? 900 : 1500, 'bandpass', geduckt ? 1.6 : .9,
   geduckt ? .012 : rennt ? .055 : .032, geduckt ? .05 : .09);
 }

 aufprall(staerke) {
  const s = KLEMME(staerke / 14, .12, 1);
  this.schlag(120 * (1.2 - s * .4), 42, .10 * s, .22 + s * .2);
  this.stoss(1800, 'bandpass', .7, .07 * s, .12 + s * .1);
 }

 nachladen() {
  this.stoss(2600, 'bandpass', 2.2, .05, .04);
  setTimeout(() => this.stoss(1800, 'bandpass', 2.4, .045, .05), 110);
 }

 tuer() {this.stoss(1100, 'bandpass', 1.4, .05, .07);}

 // zustand: {wetter, tempo, geduckt, rennt, imWagen, wasserAbstand, sterne,
 //           polizeiAbstand, pausiert}
 update(dt, zustand) {
  if (!this.an || !dt) return;
  const drin = zustand.imWagen ? .35 : 1;      // im Wagen ist alles gedämpft
  this.ziehe(this.wind.regler, (WIND[zustand.wetter] ?? WIND.clear) * drin, dt, 1.6);
  this.ziehe(this.regen.regler, (REGEN[zustand.wetter] ?? 0) * drin, dt, 1.1);

  // Brandung: hörbar bis sechzig Meter, dahinter nichts.
  const nah = KLEMME(1 - zustand.wasserAbstand / 60, 0, 1);
  const brandung = nah * nah * .05 * drin;
  this.ziehe(this.brandung.regler, brandung, dt, 1.2);
  this.welleTiefe.gain.value = brandung * .55;

  // Sirene: nur bei Fahndung, und leiser, je weiter die nächste Streife weg
  // ist. Ohne die Entfernung heult es auch dann, wenn niemand in der Nähe ist.
  const sirene = zustand.sterne > 0
   ? KLEMME(1 - zustand.polizeiAbstand / 220, 0, 1) * .020 * KLEMME(zustand.sterne / 2, .5, 1)
   : 0;
  this.ziehe(this.sirenenRegler, sirene, dt, .5);

  // Schritte nach zurückgelegtem Weg, nicht nach der Uhr: wer schleicht,
  // macht seltener einen Schritt, und im Stand ist es still.
  if (!zustand.imWagen && !zustand.pausiert && zustand.tempo > .2) {
   this.schrittWeg += zustand.tempo * dt;
   const laenge = zustand.geduckt ? 1.1 : zustand.rennt ? 1.9 : 1.45;
   if (this.schrittWeg >= laenge) {
    this.schrittWeg = 0;
    this.schritt(zustand.geduckt, zustand.rennt);
   }
  } else this.schrittWeg = 0;
 }

 // Wie viele einmalige Klänge gerade laufen. Für die Prüfung auf ein Leck.
 get offen() {return this.lebend.size;}

 stumm(aus) {
  this.an = !aus;
  this.summe.gain.value = aus ? 0 : 1;
 }
}
