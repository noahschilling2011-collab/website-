# Architektur

## Überblick

```
┌─────────────────────────────────────────────────────┐
│  Flutter-App (iOS / Android / Web)                   │
│  Clean Architecture + MVVM (Riverpod-Notifier)       │
│  UI ──► Controller (ViewModel) ──► Repository/API    │
│  Offline-Cache + Sync-Queue (LocalStore)             │
└──────────────┬───────────────────────────┬──────────┘
               │ REST + SSE                │ WebSocket (Socket.IO)
┌──────────────▼───────────────────────────▼──────────┐
│  Node.js API (Express, TypeScript, Clean Modules)    │
│  /api/auth /api/ai /api/tasks /api/notes ...         │
│  /graphql (Read-Layer, graphql-yoga)                 │
│  Middleware: Auth (JWT) · RBAC · Zod · Rate-Limit    │
└───────┬──────────────┬──────────────┬───────────────┘
        │              │              │
┌───────▼────┐  ┌──────▼─────┐  ┌────▼──────────────────────┐
│ PostgreSQL │  │   Redis    │  │ KI-Provider (HTTP)         │
│ (Daten)    │  │ (RateLimit,│  │ OpenAI · Anthropic · Gemini│
│            │  │  Cache,    │  │ Replicate (Video/Musik)    │
│            │  │  Pub/Sub)  │  └───────────────────────────┘
└────────────┘  └────────────┘
```

## Backend — Schichtenmodell

Jedes Modul unter `backend/src/modules/<name>/` folgt demselben Schnitt:

| Schicht | Datei | Verantwortung |
|---|---|---|
| Routes | `*.routes.ts` | HTTP-Verdrahtung, Validierung (Zod), Statuscodes |
| Service | `*.service.ts` | Geschäftslogik, Transaktionen, Provider-Aufrufe |
| Datenzugriff | `db/pool.ts` | Parametrisierte SQL-Queries (kein ORM — volle Kontrolle, weniger Overhead) |

Querschnittsthemen liegen in `middleware/` (Auth, Fehler, Rate-Limit) und
`utils/` (Logger, typisierte Fehler, Async-Wrapper).

### Fehlerbehandlung

Alle Fehler laufen zentral durch `middleware/errorHandler.ts`:

- `AppError` → definierter Status + stabiler `code` (maschinenlesbar für die App)
- `ZodError` → 400 mit Felddetails
- Unbekannte Fehler → 500, in Produktion ohne interne Details, immer mit Log

### Echtzeit & Sync

`ws/gateway.ts` authentifiziert Sockets per Access-Token und legt jeden
Client in einen `user:<id>`-Raum. CRUD-Services publizieren
`task.created`, `note.updated` usw. — alle Geräte eines Nutzers bleiben
synchron. Für Multi-Pod-Betrieb wird der Redis-Adapter eingehängt
(`@socket.io/redis-adapter`).

### KI-Provider-Abstraktion

`modules/ai/providers/` definiert ein Interface (`complete` + `stream`),
implementiert für OpenAI, Anthropic und Gemini. Die Auswahl erfolgt pro
Konversation. Streaming läuft als SSE bis zum Client durch — die App
rendert Token für Token.

## App — Clean Architecture + MVVM

```
lib/
├── core/          # Framework-nahe Basis: Theme, Router, Netzwerk, Storage
│   ├── theme/     # Design-Tokens + Material-3-Theme (hell/dunkel)
│   ├── router/    # go_router, Auth-Redirects, StatefulShellRoute
│   ├── network/   # ApiClient (REST + SSE), Fehler-Mapping
│   └── storage/   # LocalStore: Cache + Offline-Mutations-Queue
└── features/      # Ein Ordner pro Feature
    └── <feature>/
        ├── *_controller.dart   # ViewModel (Riverpod Notifier) — Zustand + Logik
        └── *_screen.dart       # View — reine Darstellung, keine Logik
```

- **State-Management:** Riverpod `Notifier`/`AsyncNotifier` als ViewModels.
- **Offline-Modus:** Lesepfad cache-first (`TasksController.build()` liefert
  sofort den Cache und aktualisiert im Hintergrund); Schreibpfad mit Queue,
  die beim nächsten erfolgreichen Sync abgespielt wird.
- **Design:** Material 3 mit Cupertino-Page-Transitions auf Apple-Plattformen,
  adaptives Layout (BottomNav ↔ NavigationRail ab 800 px).

## Sicherheit

- **Auth:** kurzlebige JWT-Access-Tokens (15 min) + rotierende Refresh-Tokens
  (Hash in DB, Widerruf möglich).
- **2FA:** TOTP (otplib), Enrollment mit Bestätigungscode.
- **Biometrie:** entsperrt nur eine vorhandene lokale Session (local_auth) —
  kein Ersatz für Server-Auth.
- **E2EE:** Notizen können clientseitig verschlüsselt gespeichert werden
  (`encrypted`-Flag; Server sieht nur Ciphertext, öffentlicher Schlüssel des
  Nutzers in `users.e2ee_public_key`).
- **RBAC:** global (`user`/`admin`) + Workspace-Rollen
  (`owner > admin > editor > member > viewer`), zentral geprüft in
  `requireWorkspaceRole()`.
- Helmet, CORS-Whitelist, Rate-Limits (Redis), parametrisiertes SQL.

## Beobachtbarkeit

- **Logging:** pino (strukturierte JSON-Logs), Request-Logging via pino-http,
  Redaction für Tokens/Passwörter.
- **Health:** `/health` für LB-/K8s-Probes.
- **Analytics:** Event-Ingestion (`/api/analytics/events`) + Admin-Dashboard
  (`/api/admin/dashboard`) mit Aggregaten.
- Produktion: Logs → CloudWatch/Loki, Metriken → Prometheus + Grafana,
  Tracing → OpenTelemetry (siehe docs/SCALING.md).
