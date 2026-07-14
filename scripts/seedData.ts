// Gemeinsame Demo-Daten für seed.ts und rls-test.ts.
// NUR Fantasienamen — niemals echte Mitschüler:innen (CLAUDE.md, Regel 4).
import type { Role } from '../src/types/db'

// Einheitliches Demo-Passwort. Reicht für Fantasie-Accounts; nie echte Daten hier rein.
export const DEMO_PASSWORD = 'klassenraum-demo-2026'

export const DEMO_CLASS = { name: '9b', year: 2026 }

export interface SeedUser {
  email: string
  full_name: string
  role: Role
}

export const ADMIN: SeedUser = {
  email: 'admin@klassenraum.test',
  full_name: 'Rektor Adalbert Ordnung',
  role: 'admin',
}

export const TEACHERS: SeedUser[] = [
  { email: 'mueller@klassenraum.test', full_name: 'Frieda Müller', role: 'teacher' },
  { email: 'schmidt@klassenraum.test', full_name: 'Konrad Schmidt', role: 'teacher' },
]

// 10 Demo-Schüler:innen der Klasse 9b.
export const STUDENTS: SeedUser[] = [
  { email: 'student01@klassenraum.test', full_name: 'Lina Sonnenschein', role: 'student' },
  { email: 'student02@klassenraum.test', full_name: 'Ben Wackelzahn', role: 'student' },
  { email: 'student03@klassenraum.test', full_name: 'Mia Kringel', role: 'student' },
  { email: 'student04@klassenraum.test', full_name: 'Tom Pusteblume', role: 'student' },
  { email: 'student05@klassenraum.test', full_name: 'Emma Wolkig', role: 'student' },
  { email: 'student06@klassenraum.test', full_name: 'Paul Kieselstein', role: 'student' },
  { email: 'student07@klassenraum.test', full_name: 'Ida Löwenzahn', role: 'student' },
  { email: 'student08@klassenraum.test', full_name: 'Noah Silberbach', role: 'student' },
  { email: 'student09@klassenraum.test', full_name: 'Frida Morgentau', role: 'student' },
  { email: 'student10@klassenraum.test', full_name: 'Leo Katzenberg', role: 'student' },
]

export const ALL_USERS: SeedUser[] = [ADMIN, ...TEACHERS, ...STUDENTS]
