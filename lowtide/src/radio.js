// Autoradio für Solvara.
// Das Pflichtenheft verlangt mehrere Sender und ausdrücklich nur eigene oder
// lizenzfreie Musik. Fremde Aufnahmen kommen also nicht in Frage, und
// Audiodateien würden die eigenständige HTML sprengen. Also wird die Musik
// erzeugt: jeder Sender ist ein Satz Regeln über Tempo, Tonart, Akkordfolge
// und Instrumentierung, aus dem der Scheduler Takt für Takt Noten baut.
//
// Der Scheduler arbeitet mit Vorlauf: alle 60 ms werden die nächsten 300 ms
// geplant. Direkt aus dem Bild heraus zu spielen würde bei jedem Ruckler
// hörbar stolpern.

const VORLAUF = .30, TAKTUNG = .06;
const HALBTON = n => 440 * Math.pow(2, n / 12);

// Akkorde als Halbtonabstände zum Grundton.
const MOLL7 = [0, 3, 7, 10], DUR7 = [0, 4, 7, 10], MOLL = [0, 3, 7], DUR = [0, 4, 7];

export const SENDER = [
 {
  id: 'aus', name: 'RADIO AUS', kennung: '', bpm: 0
 },
 {
  id: 'tideline', name: 'TIDELINE FM', kennung: '99.4 · Latin House',
  bpm: 122, grund: -9, folge: [[0, MOLL7], [5, MOLL7], [-4, DUR7], [-2, DUR7]],
  kick: s => s % 4 === 0,
  hut: s => s % 2 === 1,
  stab: s => s % 4 === 2 || s % 8 === 7,
  bass: s => s % 4 === 0 || s % 8 === 6,
  klang: 'sawtooth', helligkeit: 1400
 },
 {
  id: 'salt', name: 'SALT 101', kennung: '101.3 · Synthwave',
  bpm: 104, grund: -12, folge: [[0, MOLL], [3, DUR], [-2, DUR], [-4, MOLL]],
  kick: s => s % 8 === 0 || s % 8 === 6,
  snare: s => s % 8 === 4,
  hut: s => true,
  arp: s => true,
  bass: s => s % 2 === 0,
  klang: 'square', helligkeit: 2100
 },
 {
  id: 'gulf', name: 'GULF ROCK', kennung: '88.1 · Küstenrock',
  bpm: 138, grund: -14, folge: [[0, DUR], [5, DUR], [7, DUR], [5, DUR]],
  kick: s => s % 8 === 0 || s % 8 === 3,
  snare: s => s % 4 === 2,
  hut: s => s % 2 === 0,
  akkord: s => s % 8 === 0 || s % 8 === 4,
  bass: s => s % 2 === 0,
  klang: 'sawtooth', helligkeit: 2600, verzerrung: true
 },
 {
  id: 'lowband', name: 'LOW BAND', kennung: '106.7 · Dub & Downtempo',
  bpm: 78, grund: -16, folge: [[0, MOLL7], [-3, DUR7]],
  kick: s => s % 8 === 0,
  snare: s => s % 16 === 8,
  stab: s => s % 16 === 6 || s % 16 === 14,
  bass: s => s % 8 === 0 || s % 8 === 5,
  klang: 'triangle', helligkeit: 700, echo: true
 },
 {
  id: 'cypress', name: 'K-CYPRESS', kennung: '92.9 · Country',
  bpm: 112, grund: -14, folge: [[0, DUR], [7, DUR], [5, DUR], [0, DUR]],
  kick: s => s % 8 === 0,
  snare: s => s % 8 === 4,
  hut: s => s % 2 === 1,
  akkord: s => s % 4 === 0,
  bass: s => s % 2 === 0, laufbass: true,
  klang: 'triangle', helligkeit: 1900
 },
 {
  id: 'talk', name: 'PORT MERCY TALK', kennung: '540 AM · Wortbeiträge',
  bpm: 0, wort: true
 }
];

export class Radio {
 constructor(ctx) {
  this.ctx = ctx;
  this.index = 0;
  this.schritt = 0;
  this.naechste = 0;
  this.laut = 0;

  // Signalkette: Sender → Bandbegrenzung (Autoradio) → Lautstärke → Ausgang.
  this.summe = ctx.createGain();
  this.summe.gain.value = 0;
  this.band = ctx.createBiquadFilter();
  this.band.type = 'bandpass';
  this.band.frequency.value = 1250;
  this.band.Q.value = .55;
  this.trocken = ctx.createGain();
  this.trocken.gain.value = .72;
  this.summe.connect(this.band).connect(this.trocken).connect(ctx.destination);

  // Echo für die Dub-Schiene.
  this.echo = ctx.createDelay(1);
  this.echo.delayTime.value = .34;
  this.echoWeg = ctx.createGain();
  this.echoWeg.gain.value = 0;
  this.echoZurueck = ctx.createGain();
  this.echoZurueck.gain.value = .34;
  this.band.connect(this.echoWeg).connect(this.echo).connect(this.echoZurueck);
  this.echoZurueck.connect(this.echo);
  this.echo.connect(ctx.destination);

  // Ein Rauschpuffer für Perkussion und Senderrauschen.
  const laenge = Math.floor(ctx.sampleRate * .5);
  this.rauschen = ctx.createBuffer(1, laenge, ctx.sampleRate);
  const daten = this.rauschen.getChannelData(0);
  let z = 12345;
  for (let i = 0; i < laenge; i++) {z = (z * 1664525 + 1013904223) >>> 0; daten[i] = z / 2147483648 - 1;}
 }

 get sender() {return SENDER[this.index];}

 waehle(i) {
  this.index = ((i % SENDER.length) + SENDER.length) % SENDER.length;
  this.schritt = 0;
  this.naechste = this.ctx.currentTime + .05;
  this.echoWeg.gain.value = this.sender.echo ? .34 : 0;
  return this.sender;
 }
 weiter() {return this.waehle(this.index + 1);}

 // 0 im Freien, voll im Fahrzeug. Der Übergang läuft über die Gain-Rampe.
 lautstaerke(v) {
  this.laut = v;
  this.summe.gain.setTargetAtTime(v, this.ctx.currentTime, .12);
 }

 ton(freq, start, dauer, typ, pegel, gleiten) {
  const o = this.ctx.createOscillator(), g = this.ctx.createGain();
  o.type = typ;
  o.frequency.setValueAtTime(freq, start);
  if (gleiten) o.frequency.exponentialRampToValueAtTime(Math.max(20, gleiten), start + dauer);
  g.gain.setValueAtTime(.0001, start);
  g.gain.exponentialRampToValueAtTime(pegel, start + .012);
  g.gain.exponentialRampToValueAtTime(.0001, start + dauer);
  o.connect(g).connect(this.summe);
  o.start(start);
  o.stop(start + dauer + .02);
 }

 schlag(start, dauer, mitte, pegel, q = 1.2) {
  const q1 = this.ctx.createBufferSource(), f = this.ctx.createBiquadFilter(), g = this.ctx.createGain();
  q1.buffer = this.rauschen;
  f.type = 'bandpass'; f.frequency.value = mitte; f.Q.value = q;
  g.gain.setValueAtTime(pegel, start);
  g.gain.exponentialRampToValueAtTime(.0001, start + dauer);
  q1.connect(f).connect(g).connect(this.summe);
  q1.start(start);
  q1.stop(start + dauer + .02);
 }

 // Ein Sechzehntelschritt. Alles, was der Sender vorsieht, wird hier gesetzt.
 baue(s, zeit) {
  const d = this.sender;
  if (d.wort) {
   // Wortbeitrag: gefiltertes Rauschen in Silbenlänge, damit im Wagen etwas
   // läuft. Der Inhalt steht als Text im HUD, nicht als Sprachsynthese.
   if (s % 4 === 0 && Math.random() < .72)
    this.schlag(zeit, .09 + Math.random() * .11, 320 + Math.random() * 520, .05, 4);
   return;
  }
  const takt = Math.floor(s / 16) % d.folge.length;
  const [versatz, akkord] = d.folge[takt];
  const wurzel = d.grund + versatz;

  if (d.kick?.(s)) this.ton(150, zeit, .17, 'sine', .5, 44);
  if (d.snare?.(s)) this.schlag(zeit, .13, 1750, .28, .8);
  if (d.hut?.(s)) this.schlag(zeit, .035, 8200, .075, 2.4);

  if (d.bass?.(s)) {
   const stufe = d.laufbass ? akkord[(s / 2 | 0) % akkord.length] : 0;
   this.ton(HALBTON(wurzel - 12 + stufe), zeit, .19, 'sawtooth', .19, HALBTON(wurzel - 12 + stufe) * .96);
  }
  if (d.stab?.(s)) for (const n of akkord) this.ton(HALBTON(wurzel + n), zeit, .16, d.klang, .055);
  if (d.akkord?.(s)) for (const n of akkord) this.ton(HALBTON(wurzel + n), zeit, .42, d.klang, d.verzerrung ? .07 : .05);
  if (d.arp?.(s)) this.ton(HALBTON(wurzel + akkord[s % akkord.length] + 12), zeit, .11, d.klang, .06);
 }

 // Aus dem Bild heraus aufgerufen. Plant alles, was in den nächsten 300 ms
 // klingen soll, und kehrt sofort zurück.
 tick() {
  const d = this.sender;
  if (!d.bpm && !d.wort) return;
  if (this.laut < .002) {this.naechste = this.ctx.currentTime + .05; return;}
  const proSchritt = d.bpm ? 60 / d.bpm / 4 : .12;
  let wachhund = 0;
  while (this.naechste < this.ctx.currentTime + VORLAUF && wachhund++ < 64) {
   this.baue(this.schritt, Math.max(this.naechste, this.ctx.currentTime + .01));
   this.schritt = (this.schritt + 1) % 1024;
   this.naechste += proSchritt;
  }
  // Nach einer Pause liegt naechste weit in der Vergangenheit; dann neu setzen.
  if (this.naechste < this.ctx.currentTime) this.naechste = this.ctx.currentTime + .05;
 }
}

export const TAKTVORLAUF = {VORLAUF, TAKTUNG};
