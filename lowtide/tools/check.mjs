// Syntaxprüfung aller Spielmodule ohne Browser: jedes Modul wird geparst.
import {readdirSync, readFileSync, statSync} from 'node:fs';
import {join} from 'node:path';
import vm from 'node:vm';
const dir = 'src';
let fehler = 0;
for (const name of readdirSync(dir).sort()) {
  const full = join(dir, name);
  if (statSync(full).isDirectory() || !name.endsWith('.js')) continue;
  try {
    new vm.SourceTextModule(readFileSync(full, 'utf8'), {identifier: full});
    console.log('ok    ', name);
  } catch (e) {
    fehler++;
    console.log('FEHLER', name, '→', e.message);
  }
}
process.exitCode = fehler ? 1 : 0;
