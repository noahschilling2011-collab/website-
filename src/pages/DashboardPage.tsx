import { useAuth } from '../auth/AuthProvider'
import { useProfile } from '../auth/useProfile'
import type { Role } from '../types/db'

const ROLE_LABEL: Record<Role, string> = {
  student: 'Schüler:in',
  teacher: 'Lehrer:in',
  admin: 'Admin',
}

// Phase-0-Dashboard: absichtlich leer. Es beweist nur, dass Login + Rolle
// funktionieren. Inhalte kommen ab Phase 1 (Stundenplan).
export function DashboardPage() {
  const { session, signOut } = useAuth()
  const { data: profile, isLoading, error } = useProfile()

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between border-b border-border px-4 py-3">
        <span className="font-semibold">Klassenraum</span>
        <button
          onClick={signOut}
          className="rounded-lg border border-border px-3 py-1.5 text-sm text-muted hover:text-white"
        >
          Abmelden
        </button>
      </header>

      <main className="mx-auto max-w-2xl px-4 py-8">
        {isLoading && <p className="text-muted">Profil lädt…</p>}
        {error && <p className="text-red-300">Profil konnte nicht geladen werden.</p>}

        {profile && (
          <div className="rounded-xl border border-border bg-surface p-6">
            <p className="text-sm text-muted">Angemeldet als</p>
            <p className="mt-1 text-2xl font-semibold">{profile.full_name}</p>
            <span className="mt-3 inline-block rounded-full border border-accent/40 bg-accent/10 px-3 py-1 text-sm text-accent">
              {ROLE_LABEL[profile.role]}
            </span>
            <p className="mt-6 text-sm text-muted">{session?.user.email}</p>

            <p className="mt-8 text-sm text-muted">
              Phase 0 steht. Ab Phase 1 erscheint hier dein Stundenplan.
            </p>
          </div>
        )}
      </main>
    </div>
  )
}
