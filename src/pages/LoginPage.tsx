import { useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'

export function LoginPage() {
  const { session, loading } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  // Schon eingeloggt? Direkt aufs Dashboard.
  if (!loading && session) return <Navigate to="/" replace />

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setSubmitting(false)
    if (error) setError('Login fehlgeschlagen: ' + error.message)
    // Bei Erfolg übernimmt onAuthStateChange -> Redirect oben.
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <form
        onSubmit={onSubmit}
        className="w-full max-w-sm rounded-xl border border-border bg-surface p-6"
      >
        <h1 className="mb-1 text-xl font-semibold">Klassenraum</h1>
        <p className="mb-6 text-sm text-muted">Mit Schul-E-Mail anmelden</p>

        <label className="mb-1 block text-sm text-muted" htmlFor="email">
          E-Mail
        </label>
        <input
          id="email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="mb-4 w-full rounded-lg border border-border bg-bg px-3 py-2 outline-none focus:border-accent"
        />

        <label className="mb-1 block text-sm text-muted" htmlFor="password">
          Passwort
        </label>
        <input
          id="password"
          type="password"
          autoComplete="current-password"
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="mb-4 w-full rounded-lg border border-border bg-bg px-3 py-2 outline-none focus:border-accent"
        />

        {error && (
          <p className="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-300">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded-lg bg-accent px-3 py-2 font-medium text-white disabled:opacity-60"
        >
          {submitting ? 'Anmelden…' : 'Anmelden'}
        </button>
      </form>
    </div>
  )
}
