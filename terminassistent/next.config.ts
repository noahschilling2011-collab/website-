import type { NextConfig } from 'next';

const config: NextConfig = {
  // node-ical und postal-mime sind Node-Bibliotheken und duerfen nicht
  // in das Client-Bundle gebuendelt werden.
  serverExternalPackages: ['node-ical', 'postal-mime', '@electric-sql/pglite', 'unpdf'],
};

export default config;
