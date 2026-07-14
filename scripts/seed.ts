// ============================================================================
// Seed-Script — legt Demo-Accounts + 1 Klasse an.
//
// Läuft LOKAL im Terminal (`npm run seed`), NIE im Browser. Es nutzt den
// service_role-Key, der RLS komplett umgeht — deshalb darf dieser Key nur hier
// im Terminal existieren, niemals im Frontend-Bundle.
//
// Idempotent-ish: bereits existierende Accounts werden übersprungen.
// ============================================================================
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { ADMIN, ALL_USERS, DEMO_CLASS, DEMO_PASSWORD, STUDENTS } from './seedData'

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error('❌ VITE_SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY müssen in .env stehen.')
  process.exit(1)
}

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

async function findUserByEmail(email: string): Promise<string | null> {
  // Kleine Nutzerzahl -> eine Seite reicht.
  const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
  if (error) throw error
  return data.users.find((u) => u.email === email)?.id ?? null
}

async function ensureUser(email: string, full_name: string, role: string): Promise<string> {
  const existing = await findUserByEmail(email)
  if (existing) {
    console.log(`  ↺ existiert: ${email}`)
    return existing
  }
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: DEMO_PASSWORD,
    email_confirm: true, // Demo: keine Bestätigungsmail nötig
    user_metadata: { full_name, role }, // -> Signup-Trigger füllt profiles
  })
  if (error) throw error
  console.log(`  ✅ angelegt:  ${email} (${role})`)
  return data.user.id
}

async function main() {
  console.log('→ Demo-Accounts anlegen…')
  for (const u of ALL_USERS) {
    await ensureUser(u.email, u.full_name, u.role)
  }

  console.log(`→ Klasse "${DEMO_CLASS.name}" sicherstellen…`)
  let { data: klasse } = await admin
    .from('classes')
    .select('id')
    .eq('name', DEMO_CLASS.name)
    .maybeSingle()

  if (!klasse) {
    const { data, error } = await admin
      .from('classes')
      .insert(DEMO_CLASS)
      .select('id')
      .single()
    if (error) throw error
    klasse = data
    console.log('  ✅ Klasse angelegt')
  } else {
    console.log('  ↺ Klasse existiert')
  }

  console.log('→ Schüler:innen der Klasse zuordnen…')
  for (const s of STUDENTS) {
    const studentId = await findUserByEmail(s.email)
    if (!studentId) continue
    const { error } = await admin
      .from('class_members')
      .upsert({ class_id: klasse.id, student_id: studentId }, { onConflict: 'class_id,student_id' })
    if (error) throw error
  }
  console.log('  ✅ Zuordnung fertig')

  console.log('\n✔ Seed abgeschlossen.')
  console.log(`  Login-Passwort für alle Demo-Accounts: ${DEMO_PASSWORD}`)
  console.log(`  Beispiel Schüler: ${STUDENTS[0].email}`)
  console.log(`  Beispiel Lehrer:  mueller@klassenraum.test`)
  console.log(`  Admin:            ${ADMIN.email}`)
}

main().catch((err) => {
  console.error('❌ Seed fehlgeschlagen:', err)
  process.exit(1)
})
