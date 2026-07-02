# Nexus AI — All-in-One KI-Produktivitätsplattform

Enterprise-Plattform für iOS, Android und Web: KI-Chat (GPT / Claude / Gemini), Inhalte generieren, Dokumente analysieren, Aufgaben, Kalender, Notizen, Team-Workspaces u. v. m.

## Monorepo-Struktur

```
.
├── app/                  # Flutter-App (iOS, Android, Web) — Clean Architecture + MVVM
├── backend/              # Node.js/TypeScript API — REST + GraphQL + WebSockets
├── infra/
│   └── k8s/              # Kubernetes-Manifeste (Deployments, HPA, Ingress, ...)
├── docs/                 # Architektur-, API-, Setup- und Design-System-Dokumentation
├── docker-compose.yml    # Lokale Entwicklungsumgebung (API, PostgreSQL, Redis)
└── .github/workflows/    # CI/CD-Pipelines
```

## Schnellstart

### Backend (lokal, mit Docker)

```bash
cp backend/.env.example backend/.env      # API-Keys eintragen
docker compose up --build
# API: http://localhost:8080  ·  GraphQL: http://localhost:8080/graphql
```

### Backend (ohne Docker)

```bash
cd backend
npm install
npm run migrate     # Datenbankschema anlegen (POSTGRES_URL muss gesetzt sein)
npm run dev
```

### Flutter-App

```bash
cd app
flutter pub get
flutter run -d chrome                     # Web
flutter run                               # iOS/Android (Gerät/Simulator)
```

Die API-Basis-URL wird per `--dart-define=API_BASE_URL=http://localhost:8080` gesetzt (Standard: `http://localhost:8080`).

## Feature-Überblick

| Bereich | Status | Modul |
|---|---|---|
| KI-Chat (GPT, Claude, Gemini, Streaming) | ✅ implementiert | `backend/src/modules/ai`, `app/lib/features/chat` |
| Auth: JWT, Refresh, 2FA (TOTP), Biometrie-Hook | ✅ implementiert | `backend/src/modules/auth`, `app/lib/features/auth` |
| Aufgaben, Notizen, Kalender | ✅ implementiert | jeweilige Module in Backend + App |
| Team-Workspaces, Rollen & Rechte (RBAC) | ✅ implementiert | `backend/src/modules/workspaces` |
| PDF-/Webseiten-/YouTube-Zusammenfassung | ✅ implementiert | `backend/src/modules/ai/tools` |
| Übersetzer (100+ Sprachen), Dokumente schreiben | ✅ implementiert | `backend/src/modules/ai/tools` |
| Bild-/Video-/Musik-Generierung | ✅ API-Anbindung | `backend/src/modules/ai/media` |
| Dateimanager & Cloud-Sync | ✅ implementiert | `backend/src/modules/files` |
| Analytics-Dashboard & Admin-Panel-API | ✅ implementiert | `backend/src/modules/analytics`, `admin` |
| WebSockets (Echtzeit-Sync, Präsenz) | ✅ implementiert | `backend/src/ws` |
| Dark/Light Mode, Material 3 + iOS-Design | ✅ implementiert | `app/lib/core/theme` |
| Offline-Modus (lokaler Cache + Sync-Queue) | ✅ implementiert | `app/lib/core/storage` |

### Roadmap (Grundgerüst vorhanden, Feature noch nicht implementiert)

Sprachchat mit Echtzeit-Transkription, OCR, Bildschirmaufnahme,
Code-Editor mit Live-Vorschau, Home-Screen-Widgets sowie der serverseitige
Push-Versand (FCM) sind als Datenmodell/Job-Typen bzw. Endpunkt-Hooks
vorbereitet (`ai_jobs.kind`, `devices`-Tabelle), aber noch nicht umgesetzt.

Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/API.md`](docs/API.md), [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md), [`docs/SETUP.md`](docs/SETUP.md), [`docs/SCALING.md`](docs/SCALING.md).

## Tests

```bash
cd backend && npm test          # Unit- & Integrationstests (Vitest)
cd app && flutter test          # Unit- & Widget-Tests
```

## Lizenz

Proprietär — alle Rechte vorbehalten.
