# Klassenraum

Schulverwaltungs-Webapp für **eine** Schule: Stundenplan, Noten, Hausaufgaben,
Nachrichten, Fehlzeiten. Rollen: Schüler, Lehrer, Admin.

Stack: **Vite + React + TypeScript + Tailwind** · **Supabase** (Postgres + Auth + RLS) · **Netlify**.

> Aktueller Stand: **Phase 0 (Fundament)** — Login, Rollen, geschütztes Dashboard.
> Details & nächste Phasen: siehe [`CLAUDE.md`](./CLAUDE.md) und [`STATUS.md`](./STATUS.md).

---

## Setup (einmalig, ~10 Min.)

### 1. Supabase-Projekt anlegen
1. Auf [supabase.com](https://supabase.com) einloggen → **New project**.
2. Projektname z. B. `klassenraum`, Region Europe, DB-Passwort merken.
3. Warten bis das Projekt fertig ist.

### 2. Datenbank-Migration einspielen
1. Supabase-Dashboard → **SQL Editor** → **New query**.
2. Inhalt von [`supabase/migrations/0000_phase0_init.sql`](./supabase/migrations/0000_phase0_init.sql) einfügen → **Run**.
3. Das legt `profiles`, `classes`, `class_members`, den Rollen-Enum, den Signup-Trigger und **alle RLS-Policies** an.

### 3. Keys holen
Supabase-Dashboard → **Project Settings → API**:
- **Project URL** → `VITE_SUPABASE_URL`
- **anon public** key → `VITE_SUPABASE_ANON_KEY`
- **service_role** key → `SUPABASE_SERVICE_ROLE_KEY` (⚠️ nur lokal, s. u.)

### 4. Lokal starten
```bash
cp .env.example .env      # dann die drei Keys eintragen
npm install
npm run dev               # http://localhost:5173
```

### 5. Demo-Daten seeden
Legt 1 Admin, 2 Lehrer, 10 Schüler (Fantasienamen) und die Klasse `9b` an:
```bash
npm run seed
```
Login für alle Demo-Accounts: Passwort `klassenraum-demo-2026`.
- Schüler: `student01@klassenraum.test` … `student10@klassenraum.test`
- Lehrer: `mueller@klassenraum.test`, `schmidt@klassenraum.test`
- Admin: `admin@klassenraum.test`

### 6. RLS-Test (Pflicht vor jedem Deploy)
```bash
npm run rls-test
```
Loggt sich als Schüler A ein und beweist, dass er **keine** fremden Profile /
Mitgliedschaften lesen und **keine** Klasse anlegen kann. Exit-Code 0 = grün.

### 7. Deploy auf Netlify
1. [netlify.com](https://netlify.com) → **Add new site → Import from Git** → dieses Repo.
2. Build wird aus [`netlify.toml`](./netlify.toml) gelesen (`npm run build`, Publish `dist`).
3. **Site settings → Environment variables**: `VITE_SUPABASE_URL` und
   `VITE_SUPABASE_ANON_KEY` eintragen. **Nicht** den service_role-Key!
4. Deploy. Fertig — Login als Schüler und als Lehrer testen.

---

## ⚠️ Sicherheit
- Der **`anon key` ist öffentlich** und landet by design im Browser. Die Sicherheit
  liegt **ausschließlich** in den RLS-Policies der Datenbank.
- Der **`service_role`-Key umgeht RLS** und darf **nie** ins Frontend/Netlify/Git.
  Er wird nur lokal von `seed.ts` benutzt und steht in der (git-ignorierten) `.env`.
- Vor jedem Deploy: `npm run rls-test` muss grün sein.

## Befehle
| Befehl | Zweck |
|---|---|
| `npm run dev` | Dev-Server |
| `npm run build` | Produktions-Build (`dist/`) |
| `npm run typecheck` | TypeScript prüfen |
| `npm run seed` | Demo-Daten anlegen (lokal, service_role) |
| `npm run rls-test` | RLS-Sicherheitstest |
