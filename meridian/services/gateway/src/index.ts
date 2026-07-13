import { buildApp } from './app.js';
import { config } from './config.js';

async function main(): Promise<void> {
  const app = await buildApp();
  try {
    await app.listen({ port: config.port, host: '0.0.0.0' });
    app.log.info(`Meridian Gateway läuft auf :${config.port} (env=${config.nodeEnv})`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main();
