import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY fehlen. .env aus .env.example anlegen.',
  )
}

// Genau EIN Client fürs ganze Frontend. Nur der anon key — der service_role-Key
// darf hier niemals auftauchen (er würde RLS umgehen und läge im Browser offen).
export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true, // Session im localStorage -> Reload bleibt eingeloggt
    autoRefreshToken: true,
  },
})
