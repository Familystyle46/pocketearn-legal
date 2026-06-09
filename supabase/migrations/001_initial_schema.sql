-- ============================================================
-- PocketEarn — Schéma initial
-- À appliquer via : supabase db push
-- ============================================================

-- Extensions
create extension if not exists "pgcrypto";

-- ── Familles ──────────────────────────────────────────────────
create table families (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

-- ── Profils utilisateurs ──────────────────────────────────────
create type user_role as enum ('parent', 'child');

create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  family_id uuid not null references families(id) on delete cascade,
  role user_role not null,
  name text not null,
  avatar_url text,
  invite_code text unique, -- uniquement pour les enfants, 6 caractères
  created_at timestamptz not null default now()
);

-- Index pour recherche par code invitation
create index users_invite_code_idx on users(invite_code) where invite_code is not null;

-- ── Configurations par enfant ─────────────────────────────────
create table configurations (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references users(id) on delete cascade,
  hourly_rate_cents integer not null default 100 check (hourly_rate_cents > 0),
  monthly_max_cents integer not null default 4000 check (monthly_max_cents > 0),
  active_hours_start integer not null default 18 check (active_hours_start between 0 and 23),
  active_hours_end integer not null default 22 check (active_hours_end between 0 and 23),
  daily_target_minutes integer not null default 120 check (daily_target_minutes > 0),
  updated_at timestamptz not null default now(),
  unique(child_id)
);

-- ── Sessions de pause écran ───────────────────────────────────
create table screen_sessions (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references users(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz,
  duration_seconds integer not null default 0,
  verified_at timestamptz, -- null = non vérifié côté serveur
  created_at timestamptz not null default now()
);

create index screen_sessions_child_date_idx on screen_sessions(child_id, start_at desc);

-- ── Gains ─────────────────────────────────────────────────────
create table earnings (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references users(id) on delete cascade,
  session_id uuid references screen_sessions(id) on delete set null,
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default now()
);

create index earnings_child_date_idx on earnings(child_id, created_at desc);

-- ── Demandes de virement ──────────────────────────────────────
create type payout_status as enum ('pending', 'validated', 'paid');

create table payouts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references users(id) on delete cascade,
  parent_id uuid not null references users(id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  status payout_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index payouts_parent_status_idx on payouts(parent_id, status);

-- ── Row Level Security ────────────────────────────────────────

alter table families enable row level security;
alter table users enable row level security;
alter table configurations enable row level security;
alter table screen_sessions enable row level security;
alter table earnings enable row level security;
alter table payouts enable row level security;

-- Fonction helper : récupère le family_id de l'utilisateur connecté
create or replace function current_family_id()
returns uuid language sql security definer stable as $$
  select family_id from users where id = auth.uid()
$$;

-- Fonction helper : récupère le role de l'utilisateur connecté
create or replace function current_user_role()
returns user_role language sql security definer stable as $$
  select role from users where id = auth.uid()
$$;

-- families : lecture seule pour les membres de la famille
create policy "family members can read their family"
  on families for select
  using (id = current_family_id());

-- users : un utilisateur voit les membres de sa famille
create policy "users can read their family members"
  on users for select
  using (family_id = current_family_id());

create policy "users can update their own profile"
  on users for update
  using (id = auth.uid());

-- configurations : le parent lit/écrit la config de ses enfants
--                  l'enfant lit sa propre config
create policy "parent can manage child configurations"
  on configurations for all
  using (
    current_user_role() = 'parent'
    and child_id in (select id from users where family_id = current_family_id())
  );

create policy "child can read own configuration"
  on configurations for select
  using (child_id = auth.uid());

-- screen_sessions : l'enfant insère ses propres sessions, le parent les voit
create policy "child can insert own sessions"
  on screen_sessions for insert
  with check (child_id = auth.uid());

create policy "family can read screen sessions"
  on screen_sessions for select
  using (child_id in (select id from users where family_id = current_family_id()));

-- earnings : lecture pour la famille, insertion uniquement via Edge Function (service role)
create policy "family can read earnings"
  on earnings for select
  using (child_id in (select id from users where family_id = current_family_id()));

-- payouts : le parent gère les virements, l'enfant voit les siens
create policy "child can read and insert own payouts"
  on payouts for select
  using (child_id = auth.uid());

create policy "child can request payout"
  on payouts for insert
  with check (child_id = auth.uid());

create policy "parent can manage payouts in their family"
  on payouts for all
  using (
    current_user_role() = 'parent'
    and child_id in (select id from users where family_id = current_family_id())
  );

-- ── Trigger : créer le profil utilisateur après auth.signup ──
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  v_family_id uuid;
  v_role user_role;
  v_name text;
begin
  v_role := (new.raw_user_meta_data->>'role')::user_role;
  v_name := coalesce(new.raw_user_meta_data->>'name', 'Utilisateur');

  -- Les parents créent une nouvelle famille
  if v_role = 'parent' then
    insert into families default values returning id into v_family_id;
  end if;

  -- Les enfants rejoignent via invite_code (géré par Edge Function séparée)
  -- Ici on ne crée pas encore le profil enfant — c'est la Edge Function create-child qui s'en charge

  if v_role = 'parent' then
    insert into users (id, family_id, role, name)
    values (new.id, v_family_id, v_role, v_name);
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── Trigger : calculer les gains après insertion d'une session ──
create or replace function calculate_earnings_from_session()
returns trigger language plpgsql security definer as $$
declare
  v_config configurations%rowtype;
  v_earned_cents integer;
  v_month_total integer;
begin
  -- Récupère la config de l'enfant
  select * into v_config from configurations where child_id = new.child_id;
  if not found then return new; end if;

  -- Calcule le gain pour cette session
  v_earned_cents := floor(new.duration_seconds::float / 3600.0 * v_config.hourly_rate_cents)::integer;
  if v_earned_cents <= 0 then return new; end if;

  -- Vérifie le plafond mensuel
  select coalesce(sum(amount_cents), 0) into v_month_total
  from earnings
  where child_id = new.child_id
    and date_trunc('month', created_at) = date_trunc('month', now());

  if (v_month_total + v_earned_cents) > v_config.monthly_max_cents then
    v_earned_cents := greatest(0, v_config.monthly_max_cents - v_month_total);
  end if;

  if v_earned_cents > 0 then
    insert into earnings (child_id, session_id, amount_cents)
    values (new.child_id, new.id, v_earned_cents);
  end if;

  return new;
end;
$$;

create trigger on_screen_session_inserted
  after insert on screen_sessions
  for each row
  when (new.verified_at is not null)
  execute function calculate_earnings_from_session();
