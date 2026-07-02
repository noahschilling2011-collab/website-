# Setup-Anleitung

## Voraussetzungen

- Node.js ≥ 20, Docker + Docker Compose
- Flutter SDK (stable) für die App
- API-Keys: mindestens einen von `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
  `GEMINI_API_KEY`; optional `REPLICATE_API_TOKEN` für Video/Musik

## 1. Backend starten

```bash
cp backend/.env.example backend/.env   # Keys eintragen
docker compose up --build
```

Das startet API (Port 8080), PostgreSQL 16 und Redis 7. Migrationen
laufen beim API-Start automatisch (`schema_migrations`-Tabelle).

Ohne Docker:

```bash
cd backend
npm install
npm run migrate
npm run dev
```

Smoke-Test:

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","password":"passwort123","displayName":"Test"}'
```

## 2. Flutter-App

Die Plattform-Ordner (`android/`, `ios/`, `web/`) werden von Flutter
generiert und sind bewusst nicht eingecheckt:

```bash
cd app
flutter create . --project-name nexus_ai   # einmalig: Plattform-Scaffolding
flutter pub get
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8080
```

Für iOS/Android-Geräte die LAN-IP des Backends als `API_BASE_URL` setzen.

## 3. Tests

```bash
cd backend && npm test        # Vitest (Unit + Integration)
cd app && flutter test        # Unit- + Widget-Tests
```

## 4. Automatische Dokumentation

```bash
cd backend && npm run docs    # TypeDoc → backend/docs-api/
cd app && dart doc            # Dart-API-Doku → app/doc/api/
```

## 5. Produktion (Kubernetes)

```bash
kubectl apply -f infra/k8s/namespace.yaml
# Secrets zuerst (Vorlage anpassen, echte Werte über Secret-Manager!):
kubectl apply -f infra/k8s/secrets.example.yaml
kubectl apply -f infra/k8s/
```

CI (`.github/workflows/ci.yml`) prüft bei jedem Push: Typecheck, Tests
und Build für Backend + App sowie den Docker-Image-Build.

## Ersteinrichtung Admin

Nach der Registrierung den ersten Nutzer zum Admin machen:

```sql
UPDATE users SET role = 'admin' WHERE email = 'deine@mail.de';
```
