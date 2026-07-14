-- ============================================================================
-- Klassenraum — Phase 0: Fundament
-- profiles, classes, class_members + Rollen-Enum + Signup-Trigger + RLS
-- ============================================================================
-- Ausführen im Supabase SQL-Editor (Dashboard -> SQL Editor -> New query).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Rollen als Enum: die DB lehnt jede ungültige Rolle direkt ab.
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('student', 'teacher', 'admin');

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null,
  role       public.user_role not null default 'student',
  created_at timestamptz not null default now()
);

create table public.classes (
  id    uuid primary key default gen_random_uuid(),
  name  text not null,          -- z.B. '9b'
  year  int  not null
);

create table public.class_members (
  class_id   uuid not null references public.classes (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  primary key (class_id, student_id)
);

-- ---------------------------------------------------------------------------
-- Rollen-Helfer.
-- SECURITY DEFINER => läuft mit den Rechten des Owners und umgeht damit RLS
-- auf profiles. Das MUSS so sein: Eine RLS-Policy auf profiles, die selbst
-- profiles abfragt, würde sonst eine Endlos-Rekursion auslösen.
-- ---------------------------------------------------------------------------
create or replace function public.current_app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

-- ---------------------------------------------------------------------------
-- Signup-Trigger.
-- Supabase legt beim Registrieren nur eine Zeile in auth.users an. Dieser
-- Trigger spiegelt sie automatisch nach public.profiles, damit Rolle + Name
-- garantiert existieren. Rolle/Name kommen aus den Signup-Metadaten.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'Unbekannt'),
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'student')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security — für JEDE Tabelle, ausnahmslos.
-- ---------------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.classes       enable row level security;
alter table public.class_members enable row level security;

-- profiles: jeder liest sein eigenes Profil; Admin liest alle; jeder ändert nur sich.
create policy profiles_select_self
  on public.profiles for select
  using (id = auth.uid());

create policy profiles_select_admin
  on public.profiles for select
  using (public.current_app_role() = 'admin');

create policy profiles_update_self
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- classes: alle Eingeloggten dürfen lesen; nur Admin schreibt.
create policy classes_select_auth
  on public.classes for select
  using (auth.uid() is not null);

create policy classes_admin_write
  on public.classes for all
  using (public.current_app_role() = 'admin')
  with check (public.current_app_role() = 'admin');

-- class_members: Schüler sieht nur eigene Mitgliedschaft; Admin sieht/schreibt alle.
create policy cm_select_self
  on public.class_members for select
  using (student_id = auth.uid());

create policy cm_select_admin
  on public.class_members for select
  using (public.current_app_role() = 'admin');

create policy cm_admin_write
  on public.class_members for all
  using (public.current_app_role() = 'admin')
  with check (public.current_app_role() = 'admin');
