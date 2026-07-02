# API-Referenz

Basis-URL: `https://api.nexus.example.com` (lokal `http://localhost:8080`).
Alle Endpunkte außer `/api/auth/*` und `/health` erfordern
`Authorization: Bearer <accessToken>`. Fehlerformat:

```json
{ "error": { "code": "not_found", "message": "Task not found" } }
```

## Auth — `/api/auth`

| Methode | Pfad | Body | Antwort |
|---|---|---|---|
| POST | `/register` | `email, password, displayName` | `201 {user, tokens}` |
| POST | `/login` | `email, password, totpCode?, device?` | `{tokens}` oder `{requiresTotp: true}` |
| POST | `/refresh` | `refreshToken` | `{tokens}` (Rotation: alter Token wird ungültig) |
| POST | `/logout` | `refreshToken` | `204` |
| POST | `/totp/setup` | – | `{secret, otpauthUrl}` |
| POST | `/totp/enable` | `code` | `204` |

## KI — `/api/ai`

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/conversations` | Konversationen des Nutzers |
| POST | `/conversations` | `{title?, provider?: openai\|anthropic\|gemini, model?}` |
| GET | `/conversations/:id/messages` | Verlauf |
| POST | `/conversations/:id/messages` | `{content}` → **SSE-Stream**: `data: {"delta": "…"}`, Ende mit `data: [DONE]` |
| POST | `/summarize/url` | `{url, provider?, language?}` → `{summary}` |
| POST | `/summarize/text` | `{text, …}` → `{summary}` (PDF: Text clientseitig extrahieren oder Datei-Upload nutzen) |
| POST | `/summarize/youtube` | `{url, …}` → `{summary}` |
| POST | `/translate` | `{text, targetLanguage, provider?}` → `{translation}` — 100+ Sprachen |
| POST | `/documents/write` | `{topic, kind, language?, tone?, length?}` → `{document}` (Markdown) |
| POST | `/presentations` | `{topic, slideCount?}` → `{presentation: {title, slides[]}}` |
| POST | `/mindmaps` | `{topic}` → `{mindmap: {label, children[]}}` |
| POST | `/media/image` · `/media/video` · `/media/music` | `{prompt}` → `202 {job}` |
| GET | `/jobs/:id` | Job-Status: `queued → running → done/failed`, `output.url` |

## Produktivität

| Ressource | Endpunkte |
|---|---|
| Aufgaben | `GET/POST /api/tasks`, `PATCH/DELETE /api/tasks/:id` — Felder: `title, description, status, priority(0-4), dueAt, workspaceId, assigneeId` |
| Notizen | `GET/POST /api/notes`, `PATCH/DELETE /api/notes/:id` — `?q=` Volltextsuche; `encrypted: true` für E2EE-Ciphertext |
| Kalender | `GET /api/calendar/events?from&to`, `POST /events`, `PATCH/DELETE /events/:id` — RRULE via `recurrence` |
| Dateien | `GET /api/files?folder=/`, `POST /api/files` (multipart, Feld `file`), `GET /:id/download`, `PATCH /:id` (umbenennen/verschieben), `DELETE /:id` |

## Workspaces — `/api/workspaces`

`GET /` · `POST /` · `GET /:id/members` · `POST /:id/members`
(`{email, role}`) · `DELETE /:id/members/:userId` · `DELETE /:id`.
Rollen: `owner > admin > editor > member > viewer`.

## Nutzer, Analytics, Admin

- `GET/PATCH /api/users/me`, `POST /api/users/me/devices` (Push-Token, FCM)
- `POST /api/analytics/events` — `{name, properties?}`
- Admin (Rolle `admin`): `GET /api/admin/dashboard`, `GET /api/admin/users?q=`,
  `PATCH /api/admin/users/:id/role`, `GET /api/admin/audit`

## GraphQL — `POST /graphql`

Read-Layer über dieselben Daten (Mutationen laufen über REST):

```graphql
query Dashboard {
  me { displayName }
  tasks(status: "open") { id title priority dueAt }
  events(from: "2026-07-01T00:00:00Z") { title startsAt }
  conversations(limit: 5) { title updatedAt }
}
```

## WebSocket — `/ws` (Socket.IO)

Verbindung mit `auth: { token: <accessToken> }`. Events:
`task.created/updated/deleted`, `note.*`, `event.*` (Sync über alle
Geräte); Räume `workspace:join` / `workspace:leave` für Team-Broadcasts.

## Rate-Limits

Auth: 10/min · KI: 60/min · Mediengenerierung: 30/h — Antwort `429 rate_limited`.
