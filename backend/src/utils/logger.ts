import { pino } from 'pino';
import { isProduction } from '../config/index.js';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? (isProduction ? 'info' : 'debug'),
  redact: ['req.headers.authorization', '*.password', '*.token'],
  base: { service: 'nexus-api' },
});
