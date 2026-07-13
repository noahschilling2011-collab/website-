import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // Gateway-Aufrufe im Dev auf :8090 weiterleiten.
      '/v1': 'http://localhost:8090',
    },
  },
});
