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

### Backend + Web-App (lokal, mit Docker)

```bash
cp backend/.env.example backend/.env      # API-Keys eintragen
docker compose up --build
# Web-App:  http://localhost:8080          (Single-File-App, backend/public/index.html)
# API:      http://localhost:8080/api      ·  GraphQL: http://localhost:8080/graphql
```

Die Web-App (`backend/public/index.html`) ist eine einzelne HTML-Datei ohne
Build-Schritt: Login/Registrierung inkl. 2FA, KI-Chat mit Streaming und
Provider-Wahl, KI-Werkzeuge, Aufgaben, Notizen, Kalender — responsive
(Bottom-Navigation auf dem Handy), Dark/Light Mode, automatischer
Token-Refresh. Sie läuft auch von einem anderen Host aus:
`index.html?api=http://<backend-host>:8080` öffnen.

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
| OCR (Bild → Text, inkl. Handschrift) | ✅ implementiert | `backend/src/modules/ai/ocr.service.ts` |
| Audio-Transkription (Whisper, Sprachchat-Basis) | ✅ implementiert | `backend/src/modules/ai/speech.service.ts` |
| PDF-Analyse mit echter Textextraktion | ✅ implementiert | `backend/src/modules/ai/pdf.service.ts` |
| Code-Editor mit Syntax-Highlighting + KI-Assistent | ✅ implementiert | `app/lib/features/code`, `POST /api/ai/code` |
| Push-Benachrichtigungen (FCM HTTP v1) | ✅ implementiert | `backend/src/modules/notifications` |
| Auto-Token-Refresh & Chat-Verlauf in der App | ✅ implementiert | `app/lib/core/network`, `app/lib/features/chat` |
| WebSockets (Echtzeit-Sync, Präsenz) | ✅ implementiert | `backend/src/ws` |
| Dark/Light Mode, Material 3 + iOS-Design | ✅ implementiert | `app/lib/core/theme` |
| Offline-Modus (lokaler Cache + Sync-Queue) | ✅ implementiert | `app/lib/core/storage` |

### Roadmap (noch nicht implementiert)

Audio-*Aufnahme*-UI in der App (die Transkriptions-API ist fertig,
Audiodateien lassen sich bereits hochladen), Bildschirmaufnahme,
Live-Vorschau für HTML/CSS/JS im Code-Editor sowie Home-Screen-Widgets.

Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/API.md`](docs/API.md), [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md), [`docs/SETUP.md`](docs/SETUP.md), [`docs/SCALING.md`](docs/SCALING.md).

## Tests

```bash
cd backend && npm test          # Unit- & Integrationstests (Vitest)
cd app && flutter test          # Unit- & Widget-Tests
```

## Lizenz

Proprietär — alle Rechte vorbehalten.
