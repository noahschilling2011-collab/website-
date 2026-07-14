# Klassenraum — Projekt-Spec (CLAUDE.md)

> Arbeitstitel: **Klassenraum**. Nicht "EduPage" nennen (Markenname).

## Ziel
Eine Web-App, in der eine Schule Stundenplan, Noten, Hausaufgaben, Nachrichten und
Fehlzeiten verwaltet. Rollen: **Schüler**, **Lehrer**, **Admin**.

## Nicht-Ziele (explizit AUSGESCHLOSSEN)
Wenn eine dieser Ideen aufkommt: ablehnen und hier notieren, nicht bauen.
- Multi-Schule / Mandantenfähigkeit
- Eltern-Rolle
- Automatischer Stundenplan-Generator (NP-hartes Problem)
- Push-Notifications, native App, Kantinen-Bestellung, Schulbus, Vertretungsplan-Automatik
- Import aus EduPage/Schulmanager (kein öffentliches API — geht nicht)
- KI-Features jeder Art

## Stack (nicht diskutieren, nicht wechseln)
| Ebene | Wahl | Warum |
|---|---|---|
| Frontend | Vite + React + TypeScript + Tailwind | bekannt |
| Backend/DB | **Supabase** (Postgres + Auth + Row Level Security) | echter Login + DB ohne eigenen Server |
| Deploy | Netlify | bekannt |
| State | React Query (`@tanstack/react-query`) | kein Redux, kein Zustand |

## Design
Dunkles, ruhiges UI. Klar lesbar, hohe Informationsdichte, keine verspielten Animationen.
Mobile-first. Stundenplan-Grid und Notenübersicht müssen auf dem Handy gut lesbar sein.

## Datenmodell (Zielzustand)
```
profiles        id (=auth.uid), full_name, role ('student'|'teacher'|'admin')
classes         id, name ('9b'), year
class_members   class_id, student_id
subjects        id, name ('Mathe'), short ('M')
lessons         id, class_id, subject_id, teacher_id
timetable_slots id, lesson_id, weekday(1-5), period(1-10), room
grades          id, student_id, lesson_id, value(1-6), weight, title, date, created_by
homework        id, lesson_id, title, description, due_date, created_by
absences        id, student_id, date, status('open'|'excused'|'unexcused'), reason
messages        id, sender_id, recipient_id, body, created_at, read_at
```

## DAS KRITISCHE STÜCK: Row Level Security
Ohne RLS kann jeder Nutzer mit der Browser-Konsole **alle Noten der ganzen Schule** auslesen.
Der `anon key` ist öffentlich — das ist by design. Die Sicherheit liegt AUSSCHLIESSLICH in den
Policies in der Datenbank.

- Jede Tabelle: `ALTER TABLE x ENABLE ROW LEVEL SECURITY;` — ohne Ausnahme.
- `grades`: SELECT nur wenn `student_id = auth.uid()` ODER User ist Lehrer der `lesson`.
- `grades`: INSERT/UPDATE/DELETE nur für den Lehrer der `lesson`.
- `messages`: SELECT nur wenn `sender_id = auth.uid()` OR `recipient_id = auth.uid()`.
- `absences`: Schüler sieht/erstellt eigene, Lehrer sieht die seiner Klassen, nur Lehrer setzt `status`.
- Rolle NIEMALS aus dem Frontend lesen und der DB glauben — immer serverseitig über `profiles` prüfen.

**Jede Phase hat einen RLS-Test als Pflicht-Deliverable.** Phase gilt ohne diesen Test als nicht fertig.

## Phasen

**Phase 0 — Fundament** ← AKTUELL
- Vite/React/TS/Tailwind Setup, Supabase-Projekt, Env-Vars.
- Auth: E-Mail + Passwort, Login/Logout, Session-Persistenz.
- `profiles` mit Rolle, Trigger der bei Signup automatisch ein Profil anlegt.
- Geschütztes Routing: eingeloggt → Dashboard, sonst → Login.
- Leeres Dashboard, das die Rolle anzeigt.
- Seed-Script: 1 Admin, 2 Lehrer, 10 Demo-Schüler, 1 Klasse.
- Deploy auf Netlify.
- **DoD:** Live-URL-Login als Schüler UND Lehrer → unterschiedliche Dashboards. RLS-Test grün.

**Phase 1 — Stundenplan** — `subjects`, `lessons`, `timetable_slots`. Wochenansicht. Admin-Formular.
**Phase 2 — Noten** — Lehrer trägt ein, Schüler sieht eigene + Schnitt. Schüler A ≠ B (Test!).
**Phase 3 — Hausaufgaben** — Lehrer legt an, Schüler hakt lokal ab.
**Phase 4 — Nachrichten** — 1:1 Schüler↔Lehrer, Ungelesen-Zähler, Polling.
**Phase 5 — Fehlzeiten** — Schüler meldet krank, Lehrer entschuldigt.

Danach: **Stop.**

## Regeln für Claude Code
1. **Immer nur eine Phase.** Kein Feature aus Phase N+1 vorziehen, auch nicht "kurz".
2. Nach jeder Phase: `STATUS.md` aktualisieren.
3. Nie `service_role`-Key ins Frontend. Nie.
4. Keine echten Namen/Noten von echten Mitschülern in DB oder Git.
5. Wenn eine Anforderung unklar ist: fragen, nicht raten.
6. Kein neues Package ohne Begründung in einem Satz.
7. Bei jedem DB-Zugriff: "Was passiert, wenn ein Schüler das direkt per fetch() aufruft?"
