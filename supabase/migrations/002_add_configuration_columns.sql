-- ============================================================
-- Migration 002 — Ajout des colonnes manquantes dans configurations
-- Le modèle Flutter attend base_weekly_cents, weekly_max_cents,
-- daily_max_cents. Le schéma initial n'avait que hourly_rate_cents
-- et monthly_max_cents.
-- ============================================================

alter table configurations
  add column if not exists base_weekly_cents  integer not null default 1000 check (base_weekly_cents >= 0),
  add column if not exists weekly_max_cents   integer not null default 2100 check (weekly_max_cents >= 0),
  add column if not exists daily_max_cents    integer not null default 300  check (daily_max_cents >= 0);

-- Remplir les lignes existantes avec des valeurs cohérentes
-- (daily_max = weekly_max / 7, weekly_max conservé depuis monthly_max_cents / 4)
update configurations
set
  weekly_max_cents = least(monthly_max_cents / 4, 5000),
  daily_max_cents  = least(monthly_max_cents / 28, 300)
where weekly_max_cents = 2100; -- uniquement les lignes avec la valeur par défaut

-- Le trigger de calcul des gains doit aussi respecter daily_max_cents.
-- On remplace la fonction calculate_earnings_from_session.
create or replace function calculate_earnings_from_session()
returns trigger language plpgsql security definer as $$
declare
  v_config       configurations%rowtype;
  v_earned_cents integer;
  v_day_total    integer;
  v_month_total  integer;
begin
  select * into v_config from configurations where child_id = new.child_id;
  if not found then return new; end if;

  -- Calcule le gain brut pour cette session
  v_earned_cents := floor(new.duration_seconds::float / 3600.0 * v_config.hourly_rate_cents)::integer;
  if v_earned_cents <= 0 then return new; end if;

  -- Plafond journalier (daily_max_cents)
  select coalesce(sum(amount_cents), 0) into v_day_total
  from earnings
  where child_id = new.child_id
    and date_trunc('day', created_at) = date_trunc('day', now());

  if v_day_total >= v_config.daily_max_cents then return new; end if;
  v_earned_cents := least(v_earned_cents, v_config.daily_max_cents - v_day_total);

  -- Plafond mensuel (monthly_max_cents)
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

-- Fonction RPC pour les stats hebdomadaires (appelée par getWeeklyStats)
create or replace function get_weekly_stats(p_child_id uuid)
returns table(day_date date, duration_minutes int, earned_cents int)
language sql stable security definer as $$
  with days as (
    select generate_series(
      date_trunc('week', now())::date,
      date_trunc('week', now())::date + 6,
      '1 day'::interval
    )::date as day
  ),
  sessions as (
    select
      date_trunc('day', start_at)::date as day,
      coalesce(sum(duration_seconds) / 60, 0)::int as duration_minutes
    from screen_sessions
    where child_id = p_child_id
      and start_at >= date_trunc('week', now())
    group by 1
  ),
  gains as (
    select
      date_trunc('day', created_at)::date as day,
      coalesce(sum(amount_cents), 0)::int as earned_cents
    from earnings
    where child_id = p_child_id
      and created_at >= date_trunc('week', now())
    group by 1
  )
  select
    d.day                                          as day_date,
    coalesce(s.duration_minutes, 0)::int           as duration_minutes,
    coalesce(g.earned_cents, 0)::int               as earned_cents
  from days d
  left join sessions s on s.day = d.day
  left join gains    g on g.day = d.day
  order by d.day;
$$;
