// Startet Gateway (:8090) und Web-App (:5173) mit einem Befehl.
// Setzt Dev-Standardwerte für echte Such-/Routing-/Wetterdaten (öffentliche
// Instanzen, nur für Entwicklung/Test — keine Produktion). Vorhandene ENV
// werden nicht überschrieben. Kein Docker, keine DB nötig.
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const devEnv = {
  ...process.env,
  PORT: process.env.PORT ?? '8090',
  CORS_ORIGINS: process.env.CORS_ORIGINS ?? 'http://localhost:5173',
  // Öffentliche Dev-Instanzen (Fair-Use). Leeren = deterministischer Fallback.
  PHOTON_URL: process.env.PHOTON_URL ?? 'https://photon.komoot.io',
  VALHALLA_URL: process.env.VALHALLA_URL ?? 'https://valhalla1.openstreetmap.de',
  OPEN_METEO_URL: process.env.OPEN_METEO_URL ?? 'https://api.open-meteo.com/v1/forecast',
};

const procs = [];
function run(name, cmd, args, cwd, env) {
  const p = spawn(cmd, args, { cwd, env, shell: true });
  const tag = `\x1b[36m[${name}]\x1b[0m`;
  p.stdout.on('data', (d) => process.stdout.write(prefix(tag, d)));
  p.stderr.on('data', (d) => process.stderr.write(prefix(tag, d)));
  p.on('exit', (code) => {
    console.log(`${tag} beendet (code ${code})`);
    shutdown();
  });
  procs.push(p);
}
function prefix(tag, buf) {
  return String(buf)
    .split('\n')
    .filter(Boolean)
    .map((l) => `${tag} ${l}\n`)
    .join('');
}
function shutdown() {
  for (const p of procs) {
    try {
      p.kill();
    } catch {
      /* ignore */
    }
  }
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

console.log('\n🌍  Meridian startet …  Gateway :8090   Web http://localhost:5173\n');
run('gateway', 'npx', ['tsx', 'services/gateway/src/index.ts'], root, devEnv);
run('web', 'npx', ['vite', '--port', '5173'], resolve(root, 'apps/web'), process.env);
