// Bündelt src/ zu einer eigenständigen LOWTIDE.html.
// Jedes Modul wird base64-kodiert eingebettet; der Loader in shell.html
// erzeugt daraus zur Laufzeit Blob-URLs und verdrahtet die relativen Imports.
import {readFileSync, writeFileSync, readdirSync, statSync} from 'node:fs';
import {join, relative, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const srcDir = join(root, 'src');

function collect(dir, out = []) {
  for (const entry of readdirSync(dir).sort()) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) collect(full, out);
    else if (entry.endsWith('.js')) out.push(full);
  }
  return out;
}

const files = collect(srcDir);
if (!files.some(f => f.endsWith('game.js'))) throw new Error('src/game.js fehlt — ohne Einstiegspunkt kein Build.');

const modules = {};
for (const file of files) {
  const name = relative(srcDir, file).split(sep).join('/');
  modules[name] = readFileSync(file).toString('base64');
}

const shell = readFileSync(join(root, 'shell.html'), 'utf8');
const marker = '/*__EMBEDDED_MODULES__*/';
if (!shell.includes(marker)) throw new Error('shell.html hat keinen ' + marker + '-Platzhalter.');

const payload = 'const embeddedModules=' + JSON.stringify(modules) + ';';
const html = shell.replace(marker, () => payload);
writeFileSync(join(root, 'LOWTIDE.html'), html);

const kb = n => (n / 1024).toFixed(0).padStart(6) + ' KB';
console.log('LOWTIDE.html geschrieben —', kb(Buffer.byteLength(html)), 'gesamt');
for (const name of Object.keys(modules).sort((a, b) => modules[b].length - modules[a].length))
  console.log('  ', kb(Buffer.from(modules[name], 'base64').length), name);
