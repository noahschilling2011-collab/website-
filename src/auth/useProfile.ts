import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import type { Profile } from '../types/db'
import { useAuth } from './AuthProvider'

// Lädt das eigene Profil (inkl. Rolle) aus der DB.
//
// "Was passiert, wenn ein Schüler das direkt per fetch() aufruft?"
// -> Die RLS-Policy profiles_select_self liefert ausschließlich die eigene
//    Zeile. Die Rolle kommt also aus der DB, nicht aus dem Frontend — sie
//    lässt sich clientseitig nicht fälschen.
export function useProfile() {
  const { session } = useAuth()
  const userId = session?.user.id

  return useQuery<Profile | null>({
    queryKey: ['profile', userId],
    enabled: !!userId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, role, created_at')
        .eq('id', userId!)
        .single()

      if (error) throw error
      return data
    },
  })
}
