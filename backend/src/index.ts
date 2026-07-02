import http from 'node:http';
import { createApp } from './app.js';
import { config } from './config/index.js';
import { logger } from './utils/logger.js';
import { migrate } from './db/migrate.js';
import { pool } from './db/pool.js';
import { redis } from './db/redis.js';
import { initWebSocket } from './ws/gateway.js';

async function main(): Promise<void> {
  await migrate();
  await redis.connect().catch((err) => logger.warn({ err: err.message }, 'Redis unavailable at startup'));

  const app = createApp();
  const server = http.createServer(app);
  initWebSocket(server);

  server.listen(config.port, () => {
    logger.info({ port: config.port, env: config.env }, 'Nexus API listening');
  });

  const shutdown = async (signal: string) => {
    logger.info({ signal }, 'Shutting down');
    server.close();
    await pool.end().catch(() => undefined);
    redis.disconnect();
    process.exit(0);
  };
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  logger.fatal({ err }, 'Fatal startup error');
  process.exit(1);
});
