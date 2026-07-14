# STATUS

## Phase 0 — Fundament — ✅ Code fertig, wartet auf Deploy durch dich

### Fertig (Code im Repo)
- [x] Vite + React + TypeScript + Tailwind Setup (dunkles, mobile-first Theme)
- [x] Supabase-Client (nur anon key), Session-Persistenz via `AuthProvider`
- [x] Auth: Login (E-Mail + Passwort) + Logout
- [x] `profiles` mit Rollen-Enum + Signup-Trigger (`handle_new_user`)
- [x] `classes`, `class_members` (für den Seed nötig)
- [x] **RLS-Policies auf allen drei Tabellen** + `current_app_role()`-Helfer
- [x] Geschütztes Routing (`ProtectedRoute`): eingeloggt → Dashboard, sonst → /login
- [x] Leeres Dashboard, das Name + Rolle anzeigt
- [x] Seed-Script: 1 Admin, 2 Lehrer, 10 Schüler (Fantasienamen), Klasse `9b`
- [x] **RLS-Test-Script** (`npm run rls-test`): Schüler A ≠ fremde Daten
- [x] Netlify-Config (`netlify.toml`, SPA-Redirect)

### Offen — dein Teil (braucht deine Accounts, s. README)
- [ ] Supabase-Projekt anlegen + Migration einspielen
- [ ] `.env` füllen, `npm install`, `npm run seed`
- [ ] `npm run rls-test` grün sehen
- [ ] Netlify-Deploy + Env-Vars setzen
- [ ] **DoD-Check:** Auf der Live-URL als Schüler UND als Lehrer einloggen →
      unterschiedliche Dashboards

### Kaputt / bekannte Grenzen
- Keine Registrierungs-Seite im UI (Accounts entstehen per Seed/Admin — für
  eine Schule korrekt: Nutzer werden verwaltet, nicht selbst-registriert).
- Passwort-Reset-Flow nicht dabei (nicht Teil von Phase 0).

## Nächste Phase
**Phase 1 — Stundenplan.** Erst starten, wenn Phase-0-DoD live erfüllt +
RLS-Test grün ist. Kein Feature vorziehen (CLAUDE.md, Regel 1).
