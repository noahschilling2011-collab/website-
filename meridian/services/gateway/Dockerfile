# Build-Kontext ist das meridian/ Monorepo-Root (siehe docker-compose.yml).
FROM node:20-alpine

WORKDIR /app

# Workspace-Manifeste zuerst (Layer-Caching)
COPY package.json ./
COPY packages/shared/package.json ./packages/shared/package.json
COPY services/gateway/package.json ./services/gateway/package.json

RUN npm install --workspaces --include-workspace-root

# Quellcode
COPY packages/shared ./packages/shared
COPY services/gateway ./services/gateway

ENV NODE_ENV=production
EXPOSE 8090

# tsx führt TypeScript direkt aus (kein separater Build-Schritt nötig).
CMD ["npx", "tsx", "services/gateway/src/index.ts"]
