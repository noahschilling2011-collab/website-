// Handgeschriebene DB-Typen für Phase 0. Später ggf. per `supabase gen types`.
export type Role = 'student' | 'teacher' | 'admin'

export interface Profile {
  id: string
  full_name: string
  role: Role
  created_at: string
}

export interface Klasse {
  id: string
  name: string
  year: number
}
