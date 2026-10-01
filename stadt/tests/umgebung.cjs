// Gemeinsame Umgebung der Browser-Tests: Playwright, Seitenserver, Three.js, alte Fassungen aus Git, Ausgabeordner, erzeugte Spielstände.
// Nur relative Pfade (Basis: dieser Ordner tests/ und der Ordner stadt/ darüber). Einstellbar per Umgebungsvariable:
//   PORT        Seitenserver, den tests/alle.sh startet (Wurzel = Ordner stadt/); Standard 8716
//   PLAYWRIGHT  Ordner des npm-Pakets playwright; sonst require('playwright') (node_modules über tests/ oder NODE_PATH), sonst `npm root -g`
//   THREE_DIR   Ordner des npm-Pakets three@0.186.0; sonst node_modules/three neben Playwright; sonst aus dem Netz (cdn.jsdelivr.net)
//   STADT_GIT   Git-Arbeitskopie des Repos (für alte Fassungen per git show); sonst die, in der dieser Ordner liegt
//   AUSGABE     Bilder, Logs, erzeugte Spielstände; Standard tests/ausgabe/ (per tests/.gitignore ausgeschlossen)
const path = require('path');
const fs = require('fs');
const os = require('os');
const vm = require('vm');
const { execFileSync } = require('child_process');

const TESTS = __dirname, STADT = path.dirname(TESTS);
const PORT = Number(process.env.PORT || 8716);
const HOST = 'http://localhost:' + PORT;
const LEER = HOST + '/tests/leer.html';                     // Seite derselben Herkunft ohne Stadt (vorher README.md)
const AUSGABE = path.resolve(process.env.AUSGABE || path.join(TESTS, 'ausgabe'));
const ARGS = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];

// Alte Fassungen von stadt/stadt.html in der Git-Geschichte (volle Commit-Namen, dazu der Git-Blob zur Kontrolle)
const FASSUNGEN = {
  v2: ['39c405b78ad623c766537e55f51639aa8d915ad9', '3cbd47c85cc6e84827f1fa586c76cfe9dfd4ad08'],  // letzte Fassung mit Spielstand-Version 2
  v4tech: ['797107a83b96125c98d32f000cc91527cd84ac0c', '2c781267fc332a60c78333d25a79a2176ba1594d'],  // Tech-Firmen (Spielstand-Version 4), Grundlage des Teststands
  v4: ['96f6dc4ca703ecf5f1d93ec7c28ddd70d96acccc', '055fe13a42071af21008689c0893b955c7a8d302'],  // vor der Stadtregierung
  v5: ['414ebab208ae03349a029106da21cd8d8a23ecd5', 'd565cb66f6bae9b872e55b4e3c68f6df8937e0d1'],  // Stadtregierung ohne Schritt 2
  v6: ['bc7247a5d881186d85845db60b84011e0be98426', 'fac39acc344ecdaed9b238ede0663986f37472c6'],  // Schritt 2, feste Karte 96 × 96
  v7: ['ffa1d88b7e91b93f335dd9fcf18c0e2ce69dd68e', '26caf8184c3641a3fe31b9e3ae2f9f7cd822af5d'],  // Karte wächst, Sicherheit, Bund
  v8: ['31ce45210703530551d90e7e76a459f68636c847', '45a9a06d53d914072357efd2e08ec9244a88f4b7'],  // Autos; Vergleichsstand stadt.orig.html
  v9: ['6c1741ec5e4c80cd1cdaca02ee17e574f6545c1d', 'abe1a2f64446a36c20f318065d8afd90a680b494'],  // Version 9 mit KI-Teil (Etappe 1), letzte Fassung vor Version 10
};

function playwrightPfad() {
  if (process.env.PLAYWRIGHT) return path.resolve(process.env.PLAYWRIGHT);
  try { return path.dirname(require.resolve('playwright/package.json')); } catch {}
  try {
    const g = execFileSync('npm', ['root', '-g'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (fs.existsSync(path.join(g, 'playwright', 'package.json'))) return path.join(g, 'playwright');
  } catch {}
  throw new Error('Playwright nicht gefunden: PLAYWRIGHT=<werkzeug>/node_modules/playwright setzen (tests/LIESMICH.md)');
}
const PW = playwrightPfad();
const { chromium } = require(PW);

function threePfad() {
  const d = process.env.THREE_DIR ? path.resolve(process.env.THREE_DIR) : path.join(path.dirname(PW), 'three');
  const pj = path.join(d, 'package.json');
  if (!fs.existsSync(pj)) {
    if (process.env.THREE_DIR) throw new Error('THREE_DIR ohne package.json: ' + d);
    return null;                                              // kein lokales Paket: Three.js kommt aus dem Netz
  }
  const v = JSON.parse(fs.readFileSync(pj, 'utf8')).version;
  if (v !== '0.186.0') throw new Error(`Three.js ${v} in ${d}, das Spiel lädt 0.186.0`);
  return d;
}
const THREE = threePfad();
// Three.js aus der lokalen Kopie unter der CDN-Adresse, die das Spiel lädt (ohne lokale Kopie: keine Route, echtes Netz)
async function three(ctx) {
  if (!THREE) return;
  await ctx.route('https://cdn.jsdelivr.net/npm/three@0.186.0/**', (r) => r.fulfill({ path: path.join(THREE, r.request().url().split('/npm/three@0.186.0/')[1].split('?')[0]),
    contentType: 'text/javascript', headers: { 'Access-Control-Allow-Origin': '*' } }));
}

// Alte Fassung per git show in einen eigenen Temp-Ordner (je Prozess, am Ende gelöscht)
let tmp = null;
function tempOrdner() {
  if (!tmp) { tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'stadt-tests-')); process.on('exit', () => { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {} }); }
  return tmp;
}
let repo = null;
function gitRepo() {
  if (repo) return repo;
  const r = process.env.STADT_GIT || (() => { try { return execFileSync('git', ['-C', STADT, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } })();
  if (!r) throw new Error('Alte Fassungen brauchen die Git-Geschichte: Tests in einer vollständigen Git-Kopie des Repos laufen lassen oder STADT_GIT=<repo> setzen');
  return (repo = r);
}
const gezeigt = {};
function alteFassung(v) {
  if (gezeigt[v]) return gezeigt[v];
  const [commit, blob] = FASSUNGEN[v] || [];
  if (!commit) throw new Error('unbekannte Fassung ' + v);
  const git = (...a) => execFileSync('git', ['-C', gitRepo(), ...a], { maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'pipe'] });
  const ist = git('rev-parse', `${commit}:stadt/stadt.html`).toString().trim();
  if (ist !== blob) throw new Error(`git ${commit}:stadt/stadt.html ist ${ist}, erwartet ${blob}`);
  const f = path.join(tempOrdner(), `stadt_${v}.html`);
  fs.writeFileSync(f, git('show', `${commit}:stadt/stadt.html`));
  return (gezeigt[v] = f);
}
// Alte Fassung unter einer Adresse des Seitenservers (gleiche Herkunft → derselbe Spielstand), Standard stadt.orig.html
async function fassungUnter(ctx, v, adresse = HOST + '/stadt.orig.html*') {
  const f = alteFassung(v);
  await ctx.route(adresse, (r) => r.fulfill({ path: f, contentType: 'text/html; charset=utf-8' }));
}

// Ausgabeordner (wird angelegt), mit Schrägstrich am Ende
function ordner(name) { const d = path.join(AUSGABE, name); fs.mkdirSync(d, { recursive: true }); return d + '/'; }
// Von tests/basis.cjs erzeugter Teststand (Seed 2, Tag 420) in AUSGABE/basis/
function basis(name) {
  const f = path.join(AUSGABE, 'basis', name);
  if (!fs.existsSync(f)) throw new Error(`${f} fehlt: erst „node tests/basis.cjs“ (tests/alle.sh macht das)`);
  return f;
}

// Spielstand von Version 2 (Seed 1, Tag 150 ab 13 Uhr mit Baustelle), in Node aus dem Sim-Block der Fassung v2 gerechnet (wie früher v2save.mjs)
function v2Spielstand() {
  const html = fs.readFileSync(alteFassung('v2'), 'utf8');
  const ctx = vm.createContext({}); vm.runInContext(html.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], ctx);
  const Alt = ctx.StadtSim, S = Alt.neueStadt(1);
  while (S.tag < 150 || S.stunde < 13 || !S.baustellen.length) Alt.stunde(S);
  const d = Alt.exportZustand(S);
  return JSON.stringify({ ...d, arrays: d.arrays.map(a => ({ name: a.name, typ: a.typ, b64: Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength).toString('base64') })),
    zuletztGelaufen: Date.now(), tempo: 1, ui: {} });
}

// Kurzbericht für tests/alle.sh
function bericht() {
  const pv = JSON.parse(fs.readFileSync(path.join(PW, 'package.json'), 'utf8')).version;
  let chrom = '?'; try { chrom = chromium.executablePath(); } catch {}
  let g = '–'; try { g = gitRepo(); } catch (e) { g = 'FEHLT (' + e.message + ')'; }
  console.log(`Playwright ${pv} (${PW}); Chromium ${fs.existsSync(chrom) ? chrom : 'FEHLT: ' + chrom}`);
  console.log(`Three.js: ${THREE ? 'lokal ' + THREE : 'aus dem Netz (cdn.jsdelivr.net), kein lokales Paket'}; Git für alte Fassungen: ${g}; Ausgabe: ${AUSGABE}`);
  if (!fs.existsSync(chrom)) process.exitCode = 1;
}

module.exports = { chromium, ARGS, PORT, HOST, LEER, TESTS, STADT, AUSGABE, THREE, FASSUNGEN, three, alteFassung, fassungUnter, ordner, basis, v2Spielstand, bericht, tempOrdner };
if (require.main === module) bericht();
