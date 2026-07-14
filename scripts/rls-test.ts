// ============================================================================
// RLS-Test — Pflicht-Deliverable Phase 0.
//
// Beweist mit dem ÖFFENTLICHEN anon key (genau wie der Browser), dass ein
// eingeloggter Schüler NICHT an fremde Daten kommt. Kein service_role hier —
// wir simulieren exakt das, was ein Schüler per fetch() aus der Konsole täte.
//
// Voraussetzung: `npm run seed` wurde ausgeführt.
// Ausführen: `npm run rls-test`  (Exit-Code 0 = grün, 1 = rot)
// ============================================================================
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { DEMO_PASSWORD, STUDENTS } from './seedData'

const url = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  console.error('❌ VITE_SUPABASE_URL und VITE_SUPABASE_ANON_KEY müssen in .env stehen.')
  process.exit(1)
}

let failures = 0
function check(name: string, passed: boolean, detail = '') {
  console.log(`${passed ? '✅' : '❌'} ${name}${detail ? ' — ' + detail : ''}`)
  if (!passed) failures++
}

async function main() {
  const studentA = createClient(url!, anonKey!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  // Als Schüler A einloggen (öffentlicher Weg, wie im Browser).
  const { data: auth, error: authErr } = await studentA.auth.signInWithPassword({
    email: STUDENTS[0].email,
    password: DEMO_PASSWORD,
  })
  if (authErr || !auth.user) {
    console.error('❌ Login als Schüler A fehlgeschlagen. Erst `npm run seed` laufen lassen.')
    process.exit(1)
  }
  const myId = auth.user.id
  console.log(`→ Eingeloggt als ${STUDENTS[0].email}\n`)

  // 1) profiles: Schüler A darf NUR sein eigenes Profil sehen.
  const { data: profiles } = await studentA.from('profiles').select('id, full_name, role')
  const rows = profiles ?? []
  check(
    'profiles: Schüler A sieht ausschließlich sein eigenes Profil',
    rows.length === 1 && rows[0].id === myId,
    `${rows.length} Zeile(n) sichtbar`,
  )

  // 2) Gezielt Schüler B abfragen -> muss LEER sein.
  const { data: other } = await studentA
    .from('profiles')
    .select('id, full_name')
    .neq('id', myId)
  check(
    'profiles: gezielte Abfrage fremder Profile liefert nichts',
    (other?.length ?? 0) === 0,
    `${other?.length ?? 0} fremde Zeile(n)`,
  )

  // 3) class_members: nur die eigene Mitgliedschaft.
  const { data: members } = await studentA.from('class_members').select('student_id')
  const foreignMembers = (members ?? []).filter((m) => m.student_id !== myId)
  check(
    'class_members: keine fremden Mitgliedschaften sichtbar',
    foreignMembers.length === 0,
    `${foreignMembers.length} fremde Zeile(n)`,
  )

  // 4) Schreibversuch: Schüler A darf KEINE Klasse anlegen (nur Admin).
  const { error: insertErr } = await studentA
    .from('classes')
    .insert({ name: 'hack-9z', year: 2026 })
  check(
    'classes: Schüler A kann keine Klasse anlegen (INSERT blockiert)',
    insertErr !== null,
    insertErr ? 'abgelehnt ✓' : 'INSERT ging durch (!!)',
  )

  await studentA.auth.signOut()

  console.log('')
  if (failures === 0) {
    console.log('🟢 RLS-Test GRÜN — Schüler A kommt nicht an fremde Daten.')
    process.exit(0)
  } else {
    console.log(`🔴 RLS-Test ROT — ${failures} Verletzung(en). NICHT deployen!`)
    process.exit(1)
  }
}

main().catch((err) => {
  console.error('❌ RLS-Test-Fehler:', err)
  process.exit(1)
})
