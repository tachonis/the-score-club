-- =============================================================================
-- ENGLISH BOOTSTRAP — DO NOT APPLY TO GREEK PRODUCTION
-- =============================================================================
-- Target: a brand-new EMPTY English Supabase project only (the-score-club.com).
-- NEVER apply this file to www.thescoreclub.gr / project aoprkdbqtibsnlusbbpz.
-- NEVER copy Greek auth.users, profiles, predictions, Cup state, or badges earned.
-- NEVER replay documentary backup/import migrations from supabase/migrations/.
-- NEVER use unscoped `supabase db push`. When the English project exists, pass
-- an explicit English --project-ref.
-- This directory is outside supabase/migrations/ so the CLI will not auto-apply it.
-- =============================================================================
-- Clean English schema/logic baseline.
-- Concatenated in timestamp order from SAFE SCHEMA/LOGIC migrations.
-- badge_definitions rows are NOT included here (see 0003).
-- Apply to an empty database BEFORE 0002 and 0003.



-- =====================================================================
-- SOURCE: supabase/migrations/20260809205123_baseline_current_schema.sql
-- =====================================================================

-- The Score Club database baseline.
-- This migration is intentionally safe to apply to the existing project:
-- it creates missing objects, refreshes functions/policies, and never deletes data.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text,
  role text not null default 'player'
    constraint profiles_role_check check (role in ('player', 'admin')),
  status text not null default 'active'
    constraint profiles_status_check check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.teams (
  id bigint generated always as identity primary key,
  name text not null unique,
  short_name text,
  logo_url text,
  country text,
  created_at timestamptz not null default now()
);

create table if not exists public.matchdays (
  id bigint generated always as identity primary key,
  stage text not null default 'league_phase'
    constraint matchdays_stage_check check (
      stage in (
        'league_phase',
        'playoff',
        'round_of_16',
        'quarter_final',
        'semi_final',
        'final'
      )
    ),
  matchday_number integer,
  name text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'upcoming'
    constraint matchdays_status_check check (
      status in ('upcoming', 'active', 'completed')
    ),
  created_at timestamptz not null default now(),
  constraint matchdays_stage_matchday_number_key
    unique (stage, matchday_number)
);

create table if not exists public.matches (
  id bigint generated always as identity primary key,
  matchday_id bigint not null
    constraint matches_matchday_id_fkey
    references public.matchdays (id) on delete cascade,
  home_team_id bigint not null
    constraint matches_home_team_id_fkey
    references public.teams (id),
  away_team_id bigint not null
    constraint matches_away_team_id_fkey
    references public.teams (id),
  kickoff_at timestamptz not null,
  status text not null default 'scheduled'
    constraint matches_status_check check (
      status in ('scheduled', 'live', 'finished', 'postponed', 'cancelled')
    ),
  home_score integer
    constraint matches_home_score_check check (
      home_score is null or home_score >= 0
    ),
  away_score integer
    constraint matches_away_score_check check (
      away_score is null or away_score >= 0
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint matches_check check (home_team_id <> away_team_id),
  constraint matches_check1 check (
    (
      status = 'finished'
      and home_score is not null
      and away_score is not null
    )
    or status <> 'finished'
  )
);

create table if not exists public.predictions (
  id bigint generated always as identity primary key,
  user_id uuid not null
    constraint predictions_user_id_fkey
    references auth.users (id) on delete cascade,
  match_id bigint not null
    constraint predictions_match_id_fkey
    references public.matches (id) on delete cascade,
  predicted_home_score integer not null
    constraint predictions_predicted_home_score_check check (
      predicted_home_score between 0 and 20
    ),
  predicted_away_score integer not null
    constraint predictions_predicted_away_score_check check (
      predicted_away_score between 0 and 20
    ),
  points integer
    constraint predictions_points_check check (
      points is null or points in (0, 2, 4, 5, 10)
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint predictions_user_id_match_id_key unique (user_id, match_id)
);

create index if not exists matches_kickoff_at_idx
  on public.matches (kickoff_at);

create index if not exists matches_matchday_id_idx
  on public.matches (matchday_id);

create index if not exists predictions_match_id_idx
  on public.predictions (match_id);

create index if not exists predictions_user_id_idx
  on public.predictions (user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.profiles (
    id,
    username,
    display_name
  )
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    new.raw_user_meta_data ->> 'display_name'
  );

  return new;
end;
$function$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'admin'
      and status = 'active'
  );
$function$;

create or replace function public.get_leaderboard()
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      p.id as user_id,
      p.username,
      coalesce(sum(pr.points), 0)::bigint as total_points,
      count(pr.id)
        filter (where pr.points in (5, 10))::bigint as exact_scores,
      count(pr.id)
        filter (where pr.points in (2, 4))::bigint as correct_results,
      coalesce(
        sum(pr.points)
          filter (where md.stage <> 'league_phase'),
        0
      )::bigint as knockout_points,
      (
        select count(*)
        from public.matches fm
        where fm.status = 'finished'
      )
      - count(pr.id)
        filter (where m.status = 'finished')::bigint as missed_predictions
    from public.profiles p
    left join public.predictions pr
      on pr.user_id = p.id
    left join public.matches m
      on m.id = pr.match_id
    left join public.matchdays md
      on md.id = m.matchday_id
    where p.status = 'active'
    group by p.id, p.username
  ),
  ranked_players as (
    select
      rank() over (
        order by
          total_points desc,
          exact_scores desc,
          correct_results desc,
          knockout_points desc,
          missed_predictions asc
      ) as rank_position,
      user_id,
      username,
      total_points,
      exact_scores,
      correct_results,
      knockout_points,
      missed_predictions
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.matchdays enable row level security;
alter table public.matches enable row level security;
alter table public.predictions enable row level security;

drop policy if exists "Authenticated users can view profiles"
  on public.profiles;
create policy "Authenticated users can view profiles"
  on public.profiles
  for select
  to authenticated
  using (true);

drop policy if exists "Users can update their own profile"
  on public.profiles;
create policy "Users can update their own profile"
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "Authenticated users can view teams"
  on public.teams;
create policy "Authenticated users can view teams"
  on public.teams
  for select
  to authenticated
  using (true);

drop policy if exists "Admins can create teams"
  on public.teams;
create policy "Admins can create teams"
  on public.teams
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists "Admins can update teams"
  on public.teams;
create policy "Admins can update teams"
  on public.teams
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "Admins can delete teams"
  on public.teams;
create policy "Admins can delete teams"
  on public.teams
  for delete
  to authenticated
  using ((select public.is_admin()));

drop policy if exists "Authenticated users can view matchdays"
  on public.matchdays;
create policy "Authenticated users can view matchdays"
  on public.matchdays
  for select
  to authenticated
  using (true);

drop policy if exists "Admins can create matchdays"
  on public.matchdays;
create policy "Admins can create matchdays"
  on public.matchdays
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists "Admins can update matchdays"
  on public.matchdays;
create policy "Admins can update matchdays"
  on public.matchdays
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "Admins can delete matchdays"
  on public.matchdays;
create policy "Admins can delete matchdays"
  on public.matchdays
  for delete
  to authenticated
  using ((select public.is_admin()));

drop policy if exists "Authenticated users can view matches"
  on public.matches;
create policy "Authenticated users can view matches"
  on public.matches
  for select
  to authenticated
  using (true);

drop policy if exists "Admins can create matches"
  on public.matches;
create policy "Admins can create matches"
  on public.matches
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists "Admins can update matches"
  on public.matches;
create policy "Admins can update matches"
  on public.matches
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "Admins can delete matches"
  on public.matches;
create policy "Admins can delete matches"
  on public.matches
  for delete
  to authenticated
  using ((select public.is_admin()));

drop policy if exists "Users can view their own predictions"
  on public.predictions;
create policy "Users can view their own predictions"
  on public.predictions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Admins can view all predictions"
  on public.predictions;
create policy "Admins can view all predictions"
  on public.predictions
  for select
  to authenticated
  using ((select public.is_admin()));

drop policy if exists "Users can create their own predictions"
  on public.predictions;
create policy "Users can create their own predictions"
  on public.predictions
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );

drop policy if exists "Users can update their own predictions"
  on public.predictions;
create policy "Users can update their own predictions"
  on public.predictions
  for update
  to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );

drop policy if exists "Admins can update predictions"
  on public.predictions;
create policy "Admins can update predictions"
  on public.predictions
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));


-- =====================================================================
-- SOURCE: supabase/migrations/20260809205214_harden_prediction_points_and_function_access.sql
-- =====================================================================

-- Security hardening for the browser-facing Data API.
-- No rows are updated or deleted by this migration.

create index if not exists matches_home_team_id_idx
  on public.matches (home_team_id);

create index if not exists matches_away_team_id_idx
  on public.matches (away_team_id);

-- The unauthenticated app does not query database tables.
revoke all privileges on all tables in schema public from anon;
revoke all privileges on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- Rebuild the authenticated grants explicitly so replay does not depend
-- on changing Supabase platform defaults.
revoke all privileges on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant update (username) on table public.profiles to authenticated;

revoke all privileges on table public.teams from authenticated;
grant select, insert, update, delete
  on table public.teams
  to authenticated;

revoke all privileges on table public.matchdays from authenticated;
grant select, insert, update, delete
  on table public.matchdays
  to authenticated;

revoke all privileges on table public.matches from authenticated;
grant select, insert, update, delete
  on table public.matches
  to authenticated;

revoke all privileges on table public.predictions from authenticated;
grant select on table public.predictions to authenticated;
grant insert (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  updated_at
) on table public.predictions to authenticated;
grant update (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  updated_at
) on table public.predictions to authenticated;

-- Identity values still need sequence access for permitted inserts.
revoke all privileges on all sequences in schema public from authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- SECURITY DEFINER functions must never inherit public execution.
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.handle_new_user() from authenticated;

revoke execute on function public.is_admin() from public;
revoke execute on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated;

revoke execute on function public.get_leaderboard() from public;
revoke execute on function public.get_leaderboard() from anon;
grant execute on function public.get_leaderboard() to authenticated;

-- Keep the service role usable for trusted maintenance paths.
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Make future public-schema exposure opt-in.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables
  from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences
  from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions
  from public, anon, authenticated;


-- =====================================================================
-- SOURCE: supabase/migrations/20260811080542_admin_result_scoring.sql
-- =====================================================================

-- Secure, deterministic normal-time result scoring.
-- Existing rows are not changed by this migration.

create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles
      where id = (select auth.uid())
        and role = 'admin'
        and status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  select m.home_score, m.away_score, m.status
  into v_current_home_score, v_current_away_score, v_current_status
  from public.matches as m
  where m.id = p_match_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as m
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where m.id = p_match_id;
  end if;

  with calculated_points as (
    select
      pr.id,
      case
        when pr.predicted_home_score = p_home_score
          and pr.predicted_away_score = p_away_score
          then 5
        when (
          pr.predicted_home_score > pr.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          pr.predicted_home_score = pr.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          pr.predicted_home_score < pr.predicted_away_score
          and p_home_score < p_away_score
        )
          then 2
        else 0
      end as new_points
    from public.predictions as pr
    where pr.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as pr
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where pr.id = calculated_points.id
      and pr.points is distinct from calculated_points.new_points
    returning pr.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry and idempotent normal scoring. Extend the isolated CASE expression for future match-level multipliers.';

-- Result fields are writable only through set_match_result().
revoke insert, update on table public.matches from authenticated;

grant insert (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  updated_at
) on table public.matches to authenticated;

grant update (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  updated_at
) on table public.matches to authenticated;

-- The browser may invoke the RPC, but the function itself rejects every
-- caller who is not an active admin.
revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260811081143_qualify_scoring_admin_check.sql
-- =====================================================================

-- Qualify profile columns that can collide with TABLE return names.
create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  select m.home_score, m.away_score, m.status
  into v_current_home_score, v_current_away_score, v_current_status
  from public.matches as m
  where m.id = p_match_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as m
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where m.id = p_match_id;
  end if;

  with calculated_points as (
    select
      pr.id,
      case
        when pr.predicted_home_score = p_home_score
          and pr.predicted_away_score = p_away_score
          then 5
        when (
          pr.predicted_home_score > pr.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          pr.predicted_home_score = pr.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          pr.predicted_home_score < pr.predicted_away_score
          and p_home_score < p_away_score
        )
          then 2
        else 0
      end as new_points
    from public.predictions as pr
    where pr.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as pr
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where pr.id = calculated_points.id
      and pr.points is distinct from calculated_points.new_points
    returning pr.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260811090456_league_phase_standings.sql
-- =====================================================================

-- Live League Phase table derived only from finished League Phase matches.
-- This migration changes no existing rows.

create or replace view public.league_phase_standings
with (security_invoker = true)
as
with finished_league_matches as (
  select
    m.id,
    m.home_team_id,
    m.away_team_id,
    m.home_score,
    m.away_score
  from public.matches as m
  join public.matchdays as md
    on md.id = m.matchday_id
  where md.stage = 'league_phase'
    and m.status = 'finished'
    and m.home_score is not null
    and m.away_score is not null
),
team_totals as (
  select
    t.id as team_id,
    t.name as team_name,
    t.short_name,
    t.logo_url,
    t.country,
    count(fm.id)::integer as played,
    count(fm.id) filter (
      where
        (t.id = fm.home_team_id and fm.home_score > fm.away_score)
        or (t.id = fm.away_team_id and fm.away_score > fm.home_score)
    )::integer as wins,
    count(fm.id) filter (
      where fm.home_score = fm.away_score
    )::integer as draws,
    count(fm.id) filter (
      where
        (t.id = fm.home_team_id and fm.home_score < fm.away_score)
        or (t.id = fm.away_team_id and fm.away_score < fm.home_score)
    )::integer as losses,
    coalesce(sum(
      case
        when t.id = fm.home_team_id then fm.home_score
        when t.id = fm.away_team_id then fm.away_score
        else 0
      end
    ), 0)::integer as goals_for,
    coalesce(sum(
      case
        when t.id = fm.home_team_id then fm.away_score
        when t.id = fm.away_team_id then fm.home_score
        else 0
      end
    ), 0)::integer as goals_against
  from public.teams as t
  left join finished_league_matches as fm
    on t.id = fm.home_team_id
    or t.id = fm.away_team_id
  group by
    t.id,
    t.name,
    t.short_name,
    t.logo_url,
    t.country
),
ranked_teams as (
  select
    row_number() over (
      order by
        (wins * 3 + draws) desc,
        (goals_for - goals_against) desc,
        goals_for desc,
        lower(team_name) asc,
        team_id asc
    ) as position,
    team_id,
    team_name,
    short_name,
    logo_url,
    country,
    played,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    goals_for - goals_against as goal_difference,
    wins * 3 + draws as points
  from team_totals
)
select
  position,
  team_id,
  team_name,
  short_name,
  logo_url,
  country,
  played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  goal_difference,
  points
from ranked_teams;

comment on view public.league_phase_standings is
  'Live Champions League phase standings from finished league_phase matches. Ranking: points, goal difference, goals scored, then deterministic team name/id fallback.';

revoke all privileges on table public.league_phase_standings
  from public, anon;
grant select on table public.league_phase_standings
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260811213426_golden_match.sql
-- =====================================================================

-- Secure Golden Match selection and deterministic doubled scoring.
-- Existing predictions keep their normal 5/2/0 scoring unless they are
-- referenced by a Golden Match selection.

create unique index if not exists matches_id_matchday_id_uidx
  on public.matches (id, matchday_id);

create table public.golden_match_selections (
  id bigint generated always as identity primary key,
  user_id uuid not null
    constraint golden_match_selections_user_id_fkey
    references auth.users (id) on delete cascade,
  matchday_id bigint not null,
  match_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint golden_match_selections_user_matchday_key
    unique (user_id, matchday_id),
  constraint golden_match_selections_match_matchday_fkey
    foreign key (match_id, matchday_id)
    references public.matches (id, matchday_id)
    on update cascade
    on delete cascade
);

create index golden_match_selections_match_id_idx
  on public.golden_match_selections (match_id);

alter table public.golden_match_selections enable row level security;

create policy "Users can view their own Golden Match selections"
  on public.golden_match_selections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all privileges on table public.golden_match_selections
  from public, anon, authenticated;
grant select on table public.golden_match_selections
  to authenticated;
grant all privileges on table public.golden_match_selections
  to service_role;

revoke all privileges on sequence public.golden_match_selections_id_seq
  from public, anon, authenticated;
grant all privileges on sequence public.golden_match_selections_id_seq
  to service_role;

create or replace function public.set_golden_match(
  p_match_id bigint
)
returns table (
  match_id bigint,
  matchday_id bigint,
  replaced_match_id bigint,
  is_locked boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_number integer;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_previous_match_id bigint;
  v_previous_kickoff_at timestamptz;
  v_previous_status text;
  v_updated_at timestamptz;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  -- The profile row is also the per-user transaction lock. It serializes
  -- simultaneous selections so the unique matchday rule is deterministic.
  perform 1
  from public.profiles as profile
  where profile.id = v_user_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'An active player profile is required';
  end if;

  select
    match_row.matchday_id,
    matchday.matchday_number,
    match_row.kickoff_at,
    match_row.status
  into
    v_matchday_id,
    v_matchday_number,
    v_kickoff_at,
    v_match_status
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where match_row.id = p_match_id
  for share of match_row;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_matchday_number is null or v_matchday_number < 2 then
    raise exception using
      errcode = '22023',
      message = 'Golden Match is available from Matchday 2';
  end if;

  select selection.match_id
  into v_previous_match_id
  from public.golden_match_selections as selection
  where selection.user_id = v_user_id
    and selection.matchday_id = v_matchday_id
  for update;

  -- Repeating the same request never mutates the row, including after kickoff.
  if found and v_previous_match_id = p_match_id then
    select selection.updated_at
    into v_updated_at
    from public.golden_match_selections as selection
    where selection.user_id = v_user_id
      and selection.matchday_id = v_matchday_id;

    return query
    select
      p_match_id,
      v_matchday_id,
      null::bigint,
      (v_match_status <> 'scheduled' or now() >= v_kickoff_at),
      v_updated_at;
    return;
  end if;

  if v_match_status <> 'scheduled' or now() >= v_kickoff_at then
    raise exception using
      errcode = '22023',
      message = 'Golden Match must be selected before kickoff';
  end if;

  if v_previous_match_id is not null then
    select match_row.kickoff_at, match_row.status
    into v_previous_kickoff_at, v_previous_status
    from public.matches as match_row
    where match_row.id = v_previous_match_id
    for share;

    if v_previous_status <> 'scheduled'
      or now() >= v_previous_kickoff_at
    then
      raise exception using
        errcode = '22023',
        message = 'Golden Match is locked after its kickoff';
    end if;

    update public.golden_match_selections as selection
    set
      match_id = p_match_id,
      updated_at = now()
    where selection.user_id = v_user_id
      and selection.matchday_id = v_matchday_id
    returning selection.updated_at into v_updated_at;
  else
    insert into public.golden_match_selections (
      user_id,
      matchday_id,
      match_id
    )
    values (
      v_user_id,
      v_matchday_id,
      p_match_id
    )
    returning golden_match_selections.updated_at into v_updated_at;
  end if;

  return query
  select
    p_match_id,
    v_matchday_id,
    v_previous_match_id,
    false,
    v_updated_at;
end;
$function$;

comment on function public.set_golden_match(bigint)
is 'Selects or replaces the caller own Golden Match before kickoff. One selection per matchday, available from Matchday 2.';

revoke execute on function public.set_golden_match(bigint)
  from public, anon;
grant execute on function public.set_golden_match(bigint)
  to authenticated, service_role;

create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  select match_row.home_score, match_row.away_score, match_row.status
  into v_current_home_score, v_current_away_score, v_current_status
  from public.matches as match_row
  where match_row.id = p_match_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as match_row
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where match_row.id = p_match_id;
  end if;

  with calculated_points as (
    select
      prediction.id,
      case
        when prediction.predicted_home_score = p_home_score
          and prediction.predicted_away_score = p_away_score
          then case when selection.id is null then 5 else 10 end
        when (
          prediction.predicted_home_score > prediction.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          prediction.predicted_home_score = prediction.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          prediction.predicted_home_score < prediction.predicted_away_score
          and p_home_score < p_away_score
        )
          then case when selection.id is null then 2 else 4 end
        else 0
      end as new_points
    from public.predictions as prediction
    left join public.golden_match_selections as selection
      on selection.user_id = prediction.user_id
      and selection.match_id = prediction.match_id
    where prediction.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as prediction
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where prediction.id = calculated_points.id
      and prediction.points is distinct from calculated_points.new_points
    returning prediction.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry with deterministic idempotent scoring: normal 5/2/0 and selected Golden Match 10/4/0.';

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260811213819_golden_match_fk_index.sql
-- =====================================================================

create index golden_match_selections_match_matchday_idx
  on public.golden_match_selections (match_id, matchday_id);

drop index if exists public.golden_match_selections_match_id_idx;


-- =====================================================================
-- SOURCE: supabase/migrations/20260813161331_long_term_predictions.sql
-- =====================================================================

create table public.long_term_predictions (
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  prediction_type text not null
    check (prediction_type in ('winner', 'league_phase_first')),
  team_id bigint not null
    references public.teams(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, prediction_type)
);

create index long_term_predictions_team_id_idx
  on public.long_term_predictions (team_id);

create table public.long_term_outcomes (
  prediction_type text primary key
    check (prediction_type in ('winner', 'league_phase_first')),
  team_id bigint not null
    references public.teams(id) on delete restrict,
  decided_by uuid not null
    references public.profiles(id) on delete restrict,
  decided_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index long_term_outcomes_team_id_idx
  on public.long_term_outcomes (team_id);

create table public.long_term_awards (
  user_id uuid not null,
  prediction_type text not null,
  predicted_team_id bigint not null
    references public.teams(id) on delete restrict,
  outcome_team_id bigint not null
    references public.teams(id) on delete restrict,
  points integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, prediction_type),
  foreign key (user_id, prediction_type)
    references public.long_term_predictions(user_id, prediction_type)
    on delete cascade,
  check (
    (prediction_type = 'winner' and points in (0, 30))
    or
    (prediction_type = 'league_phase_first' and points in (0, 15))
  )
);

create index long_term_awards_predicted_team_id_idx
  on public.long_term_awards (predicted_team_id);

create index long_term_awards_outcome_team_id_idx
  on public.long_term_awards (outcome_team_id);

alter table public.long_term_predictions enable row level security;
alter table public.long_term_outcomes enable row level security;
alter table public.long_term_awards enable row level security;

create policy "Players can read own long-term predictions"
on public.long_term_predictions
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Authenticated users can read long-term outcomes"
on public.long_term_outcomes
for select
to authenticated
using (true);

create policy "Players can read own long-term awards"
on public.long_term_awards
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.long_term_predictions
  from public, anon, authenticated;
revoke all on table public.long_term_outcomes
  from public, anon, authenticated;
revoke all on table public.long_term_awards
  from public, anon, authenticated;

grant select on table public.long_term_predictions to authenticated;
grant select on table public.long_term_outcomes to authenticated;
grant select on table public.long_term_awards to authenticated;

grant select, insert, update, delete
  on table public.long_term_predictions to service_role;
grant select, insert, update, delete
  on table public.long_term_outcomes to service_role;
grant select, insert, update, delete
  on table public.long_term_awards to service_role;

create or replace function public.get_long_term_prediction_status()
returns table (
  is_locked boolean,
  is_configured boolean,
  matchday_name text,
  match_count bigint,
  finished_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with matchday_config as (
    select
      count(*) as configured_count,
      min(matchday.id) as matchday_id,
      min(matchday.name) as matchday_name
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 3
  ),
  matchday_state as (
    select
      config.configured_count,
      config.matchday_name,
      count(match_row.id) as match_count,
      count(*) filter (
        where match_row.status = 'finished'
      ) as finished_count
    from matchday_config as config
    left join public.matches as match_row
      on config.configured_count = 1
      and match_row.matchday_id = config.matchday_id
    group by config.configured_count, config.matchday_name
  )
  select
    (
      state.configured_count <> 1
      or state.match_count = 0
      or state.finished_count = state.match_count
    ) as is_locked,
    (
      state.configured_count = 1
      and state.match_count > 0
    ) as is_configured,
    state.matchday_name,
    state.match_count,
    state.finished_count
  from matchday_state as state;
$function$;

create or replace function public.set_long_term_prediction(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  previous_team_id bigint,
  changed boolean,
  is_locked boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_name text;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_previous_team_id bigint;
  v_updated_at timestamptz;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  perform 1
  from public.profiles as profile
  where profile.id = v_user_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'An active player profile is required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select selection.team_id, selection.updated_at
  into v_previous_team_id, v_updated_at
  from public.long_term_predictions as selection
  where selection.user_id = v_user_id
    and selection.prediction_type = p_prediction_type
  for update;

  if found and v_previous_team_id = p_team_id then
    select status.is_locked
    into is_locked
    from public.get_long_term_prediction_status() as status;

    return query
    select
      p_prediction_type,
      p_team_id,
      null::bigint,
      false,
      is_locked,
      v_updated_at;
    return;
  end if;

  select
    count(*),
    min(matchday.id),
    min(matchday.name)
  into
    v_matchday_count,
    v_matchday_id,
    v_matchday_name
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  perform 1
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id
  order by match_row.id
  for share;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into
    v_match_count,
    v_finished_count
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count = v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term predictions are locked after Matchday 3';
  end if;

  insert into public.long_term_predictions (
    user_id,
    prediction_type,
    team_id
  )
  values (
    v_user_id,
    p_prediction_type,
    p_team_id
  )
  on conflict (user_id, prediction_type) do update
  set
    team_id = excluded.team_id,
    updated_at = now()
  returning long_term_predictions.updated_at into v_updated_at;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_previous_team_id,
    true,
    false,
    v_updated_at;
end;
$function$;

create or replace function public.set_long_term_outcome(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  outcome_changed boolean,
  scored_predictions bigint,
  changed_awards bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_outcome_changed boolean;
  v_scored_predictions bigint;
  v_changed_awards bigint;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select count(*), min(matchday.id)
  into v_matchday_count, v_matchday_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  perform 1
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id
  order by match_row.id
  for share;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into
    v_match_count,
    v_finished_count
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count <> v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term outcomes require completed Matchday 3';
  end if;

  with outcome_change as (
    insert into public.long_term_outcomes (
      prediction_type,
      team_id,
      decided_by
    )
    values (
      p_prediction_type,
      p_team_id,
      v_admin_id
    )
    on conflict (prediction_type) do update
    set
      team_id = excluded.team_id,
      decided_by = excluded.decided_by,
      updated_at = now()
    where long_term_outcomes.team_id
      is distinct from excluded.team_id
    returning 1
  ),
  calculated_awards as (
    select
      selection.user_id,
      selection.prediction_type,
      selection.team_id as predicted_team_id,
      p_team_id as outcome_team_id,
      case
        when selection.team_id <> p_team_id then 0
        when p_prediction_type = 'winner' then 30
        when p_prediction_type = 'league_phase_first' then 15
        else 0
      end as points
    from public.long_term_predictions as selection
    where selection.prediction_type = p_prediction_type
  ),
  updated_awards as (
    insert into public.long_term_awards (
      user_id,
      prediction_type,
      predicted_team_id,
      outcome_team_id,
      points
    )
    select
      award.user_id,
      award.prediction_type,
      award.predicted_team_id,
      award.outcome_team_id,
      award.points
    from calculated_awards as award
    on conflict (user_id, prediction_type) do update
    set
      predicted_team_id = excluded.predicted_team_id,
      outcome_team_id = excluded.outcome_team_id,
      points = excluded.points,
      updated_at = now()
    where long_term_awards.predicted_team_id
        is distinct from excluded.predicted_team_id
      or long_term_awards.outcome_team_id
        is distinct from excluded.outcome_team_id
      or long_term_awards.points
        is distinct from excluded.points
    returning 1
  )
  select
    exists (select 1 from outcome_change),
    (select count(*) from calculated_awards),
    (select count(*) from updated_awards)
  into
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;
end;
$function$;

create or replace function public.get_leaderboard()
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      profile.id as user_id,
      profile.username,
      (
        coalesce(sum(prediction.points), 0)
        + coalesce((
          select sum(award.points)
          from public.long_term_awards as award
          where award.user_id = profile.id
        ), 0)
      )::bigint as total_points,
      count(prediction.id)
        filter (where prediction.points in (5, 10))::bigint
        as exact_scores,
      count(prediction.id)
        filter (where prediction.points in (2, 4))::bigint
        as correct_results,
      coalesce(
        sum(prediction.points)
          filter (where matchday.stage <> 'league_phase'),
        0
      )::bigint as knockout_points,
      (
        select count(*)
        from public.matches as finished_match
        where finished_match.status = 'finished'
      )
      - count(prediction.id)
        filter (where match_row.status = 'finished')::bigint
        as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
    group by profile.id, profile.username
  ),
  ranked_players as (
    select
      rank() over (
        order by
          total_points desc,
          exact_scores desc,
          correct_results desc,
          knockout_points desc,
          missed_predictions asc
      ) as rank_position,
      user_id,
      username,
      total_points,
      exact_scores,
      correct_results,
      knockout_points,
      missed_predictions
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

revoke execute on function
  public.get_long_term_prediction_status()
  from public, anon;
revoke execute on function
  public.set_long_term_prediction(text, bigint)
  from public, anon;
revoke execute on function
  public.set_long_term_outcome(text, bigint)
  from public, anon;

grant execute on function
  public.get_long_term_prediction_status()
  to authenticated, service_role;
grant execute on function
  public.set_long_term_prediction(text, bigint)
  to authenticated, service_role;
grant execute on function
  public.set_long_term_outcome(text, bigint)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260813161540_qualify_long_term_prediction_conflict.sql
-- =====================================================================

create or replace function public.set_long_term_prediction(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  previous_team_id bigint,
  changed boolean,
  is_locked boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_name text;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_previous_team_id bigint;
  v_updated_at timestamptz;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  perform 1
  from public.profiles as profile
  where profile.id = v_user_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'An active player profile is required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select selection.team_id, selection.updated_at
  into v_previous_team_id, v_updated_at
  from public.long_term_predictions as selection
  where selection.user_id = v_user_id
    and selection.prediction_type = p_prediction_type
  for update;

  if found and v_previous_team_id = p_team_id then
    select status.is_locked
    into is_locked
    from public.get_long_term_prediction_status() as status;

    return query
    select
      p_prediction_type,
      p_team_id,
      null::bigint,
      false,
      is_locked,
      v_updated_at;
    return;
  end if;

  select
    count(*),
    min(matchday.id),
    min(matchday.name)
  into
    v_matchday_count,
    v_matchday_id,
    v_matchday_name
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  perform 1
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id
  order by match_row.id
  for share;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into
    v_match_count,
    v_finished_count
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count = v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term predictions are locked after Matchday 3';
  end if;

  insert into public.long_term_predictions (
    user_id,
    prediction_type,
    team_id
  )
  values (
    v_user_id,
    p_prediction_type,
    p_team_id
  )
  on conflict on constraint long_term_predictions_pkey do update
  set
    team_id = excluded.team_id,
    updated_at = now()
  returning long_term_predictions.updated_at into v_updated_at;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_previous_team_id,
    true,
    false,
    v_updated_at;
end;
$function$;


-- =====================================================================
-- SOURCE: supabase/migrations/20260813161632_qualify_long_term_outcome_conflicts.sql
-- =====================================================================

create or replace function public.set_long_term_outcome(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  outcome_changed boolean,
  scored_predictions bigint,
  changed_awards bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_outcome_changed boolean;
  v_scored_predictions bigint;
  v_changed_awards bigint;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select count(*), min(matchday.id)
  into v_matchday_count, v_matchday_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  perform 1
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id
  order by match_row.id
  for share;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into
    v_match_count,
    v_finished_count
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count <> v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term outcomes require completed Matchday 3';
  end if;

  with outcome_change as (
    insert into public.long_term_outcomes (
      prediction_type,
      team_id,
      decided_by
    )
    values (
      p_prediction_type,
      p_team_id,
      v_admin_id
    )
    on conflict on constraint long_term_outcomes_pkey do update
    set
      team_id = excluded.team_id,
      decided_by = excluded.decided_by,
      updated_at = now()
    where long_term_outcomes.team_id
      is distinct from excluded.team_id
    returning 1
  ),
  calculated_awards as (
    select
      selection.user_id,
      selection.prediction_type,
      selection.team_id as predicted_team_id,
      p_team_id as outcome_team_id,
      case
        when selection.team_id <> p_team_id then 0
        when p_prediction_type = 'winner' then 30
        when p_prediction_type = 'league_phase_first' then 15
        else 0
      end as points
    from public.long_term_predictions as selection
    where selection.prediction_type = p_prediction_type
  ),
  updated_awards as (
    insert into public.long_term_awards (
      user_id,
      prediction_type,
      predicted_team_id,
      outcome_team_id,
      points
    )
    select
      award.user_id,
      award.prediction_type,
      award.predicted_team_id,
      award.outcome_team_id,
      award.points
    from calculated_awards as award
    on conflict on constraint long_term_awards_pkey do update
    set
      predicted_team_id = excluded.predicted_team_id,
      outcome_team_id = excluded.outcome_team_id,
      points = excluded.points,
      updated_at = now()
    where long_term_awards.predicted_team_id
        is distinct from excluded.predicted_team_id
      or long_term_awards.outcome_team_id
        is distinct from excluded.outcome_team_id
      or long_term_awards.points
        is distinct from excluded.points
    returning 1
  )
  select
    exists (select 1 from outcome_change),
    (select count(*) from calculated_awards),
    (select count(*) from updated_awards)
  into
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;
end;
$function$;


-- =====================================================================
-- SOURCE: supabase/migrations/20260813162111_long_term_outcomes_decided_by_index.sql
-- =====================================================================

create index long_term_outcomes_decided_by_idx
  on public.long_term_outcomes (decided_by);


-- =====================================================================
-- SOURCE: supabase/migrations/20260818191500_fix_long_term_prediction_locking.sql
-- =====================================================================

-- Fix long-term prediction locking to match published rules.
-- Predictions stay open until every configured Matchday 3 match is finished.
-- Missing Matchday 3 or a Matchday 3 with zero matches remains open.
-- Duplicate League Phase matchday_number = 3 rows are prevented by
-- matchdays_stage_matchday_number_key; v_matchday_count > 1 is defensive only.

create or replace function public.get_long_term_prediction_status()
returns table (
  is_locked boolean,
  is_configured boolean,
  matchday_name text,
  match_count bigint,
  finished_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with matchday_config as (
    select
      count(*) as configured_count,
      min(matchday.id) as matchday_id,
      min(matchday.name) as matchday_name
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 3
  ),
  matchday_state as (
    select
      config.configured_count,
      config.matchday_name,
      count(match_row.id) as match_count,
      count(*) filter (
        where match_row.status = 'finished'
      ) as finished_count
    from matchday_config as config
    left join public.matches as match_row
      on config.configured_count = 1
      and match_row.matchday_id = config.matchday_id
    group by config.configured_count, config.matchday_name
  )
  select
    (
      state.configured_count = 1
      and state.match_count > 0
      and state.finished_count = state.match_count
    ) as is_locked,
    (
      state.configured_count = 1
      and state.match_count > 0
    ) as is_configured,
    state.matchday_name,
    state.match_count,
    state.finished_count
  from matchday_state as state;
$function$;

comment on function public.get_long_term_prediction_status()
is 'Long-term predictions lock only after Matchday 3 exists with matches and every match is finished.';

create or replace function public.set_long_term_prediction(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  previous_team_id bigint,
  changed boolean,
  is_locked boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_previous_team_id bigint;
  v_updated_at timestamptz;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  perform 1
  from public.profiles as profile
  where profile.id = v_user_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'An active player profile is required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select selection.team_id, selection.updated_at
  into v_previous_team_id, v_updated_at
  from public.long_term_predictions as selection
  where selection.user_id = v_user_id
    and selection.prediction_type = p_prediction_type
  for update;

  if found and v_previous_team_id = p_team_id then
    select status.is_locked
    into is_locked
    from public.get_long_term_prediction_status() as status;

    return query
    select
      p_prediction_type,
      p_team_id,
      null::bigint,
      false,
      is_locked,
      v_updated_at;
    return;
  end if;

  select count(*), min(matchday.id)
  into v_matchday_count, v_matchday_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count > 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  if v_matchday_count = 1 then
    perform 1
    from public.matches as match_row
    where match_row.matchday_id = v_matchday_id
    order by match_row.id
    for share;

    select
      count(*),
      count(*) filter (where match_row.status = 'finished')
    into
      v_match_count,
      v_finished_count
    from public.matches as match_row
    where match_row.matchday_id = v_matchday_id;

    if v_match_count > 0
      and v_finished_count = v_match_count
    then
      raise exception using
        errcode = '22023',
        message = 'Long-term predictions are locked after Matchday 3';
    end if;
  end if;

  insert into public.long_term_predictions (
    user_id,
    prediction_type,
    team_id
  )
  values (
    v_user_id,
    p_prediction_type,
    p_team_id
  )
  on conflict on constraint long_term_predictions_pkey do update
  set
    team_id = excluded.team_id,
    updated_at = now()
  returning long_term_predictions.updated_at into v_updated_at;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_previous_team_id,
    true,
    false,
    v_updated_at;
end;
$function$;

comment on function public.set_long_term_prediction(text, bigint)
is 'Player long-term selections remain editable until every configured Matchday 3 match is finished.';


-- =====================================================================
-- SOURCE: supabase/migrations/20260819101500_push_notifications.sql
-- =====================================================================

-- Push Notifications v1: per-device Web Push subscriptions and the admin
-- broadcast audit trail.
-- This migration only adds new objects. It does not change or delete any
-- existing table, function, policy, grant or row.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint push_subscriptions_user_id_fkey
    references auth.users (id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscriptions_endpoint_key unique (endpoint),
  constraint push_subscriptions_endpoint_check check (
    endpoint like 'https://%'
    and char_length(endpoint) <= 2048
  ),
  constraint push_subscriptions_p256dh_check check (
    char_length(p256dh) between 1 and 255
  ),
  constraint push_subscriptions_auth_check check (
    char_length(auth) between 1 and 255
  ),
  constraint push_subscriptions_user_agent_check check (
    user_agent is null or char_length(user_agent) <= 400
  )
);

create index if not exists push_subscriptions_user_id_idx
  on public.push_subscriptions (user_id);

create table if not exists public.push_broadcasts (
  id uuid primary key default gen_random_uuid(),
  sent_by uuid
    constraint push_broadcasts_sent_by_fkey
    references public.profiles (id) on delete set null,
  title text not null,
  body text not null,
  destination text not null
    constraint push_broadcasts_destination_check check (
      destination in (
        'home',
        'predictions',
        'standings',
        'league-phase',
        'rules'
      )
    ),
  attempted_count integer not null default 0,
  success_count integer not null default 0,
  gone_count integer not null default 0,
  error_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists push_broadcasts_sent_by_created_at_idx
  on public.push_broadcasts (sent_by, created_at desc);

-- The browser never writes to push_subscriptions directly. These RPCs always
-- bind the row to the caller, so a player cannot store a subscription for
-- another user or read anyone else's endpoint.
create or replace function public.upsert_my_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  if p_endpoint is null
    or p_endpoint not like 'https://%'
    or char_length(p_endpoint) > 2048
  then
    raise exception using
      errcode = '22023',
      message = 'A valid push endpoint is required';
  end if;

  if p_p256dh is null
    or char_length(p_p256dh) not between 1 and 255
    or p_auth is null
    or char_length(p_auth) not between 1 and 255
  then
    raise exception using
      errcode = '22023',
      message = 'Valid push encryption keys are required';
  end if;

  -- A browser that later signs in as another player re-binds the same
  -- endpoint instead of leaving it attached to the previous account.
  insert into public.push_subscriptions (
    user_id,
    endpoint,
    p256dh,
    auth,
    user_agent
  )
  values (
    v_user_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    left(p_user_agent, 400)
  )
  on conflict (endpoint) do update
  set
    user_id = v_user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    updated_at = now();
end;
$function$;

create or replace function public.delete_my_push_subscription(
  p_endpoint text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  delete from public.push_subscriptions
  where endpoint = p_endpoint
    and user_id = v_user_id;
end;
$function$;

create or replace function public.delete_all_my_push_subscriptions()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  delete from public.push_subscriptions
  where user_id = v_user_id;
end;
$function$;

-- Only the sender (service role) may read endpoints, and only for players
-- whose account is still active.
create or replace function public.get_active_push_subscriptions()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth_secret text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    subscription.id,
    subscription.endpoint,
    subscription.p256dh,
    subscription.auth
  from public.push_subscriptions as subscription
  join public.profiles as profile
    on profile.id = subscription.user_id
  where profile.status = 'active'
  order by subscription.created_at;
$function$;

alter table public.push_subscriptions enable row level security;
alter table public.push_broadcasts enable row level security;

drop policy if exists "Users can view their own push subscriptions"
  on public.push_subscriptions;
create policy "Users can view their own push subscriptions"
  on public.push_subscriptions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Admins can view push broadcasts"
  on public.push_broadcasts;
create policy "Admins can view push broadcasts"
  on public.push_broadcasts
  for select
  to authenticated
  using ((select public.is_admin()));

-- No insert, update or delete policy exists for either table, so the Data API
-- rejects every browser write even before column grants are considered.
revoke all privileges on table public.push_subscriptions
  from anon, authenticated;
grant select on table public.push_subscriptions to authenticated;

revoke all privileges on table public.push_broadcasts
  from anon, authenticated;
grant select on table public.push_broadcasts to authenticated;

grant all privileges on table public.push_subscriptions to service_role;
grant all privileges on table public.push_broadcasts to service_role;

revoke execute on function public.upsert_my_push_subscription(
  text, text, text, text
) from public, anon;
grant execute on function public.upsert_my_push_subscription(
  text, text, text, text
) to authenticated, service_role;

revoke execute on function public.delete_my_push_subscription(text)
  from public, anon;
grant execute on function public.delete_my_push_subscription(text)
  to authenticated, service_role;

revoke execute on function public.delete_all_my_push_subscriptions()
  from public, anon;
grant execute on function public.delete_all_my_push_subscriptions()
  to authenticated, service_role;

revoke execute on function public.get_active_push_subscriptions()
  from public, anon, authenticated;
grant execute on function public.get_active_push_subscriptions()
  to service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260819145500_players_cup_bracket.sql
-- =====================================================================

-- Players Cup, Phase 1: competition configuration, the frozen post-Matchday 2
-- ranking, the protected top 8 seeds, the reproducible draw for everyone else,
-- and the complete bracket skeleton.
--
-- Vocabulary used throughout, because three different numbers are easy to
-- confuse:
--   rank_position     - the frozen strict League Phase ranking after Matchday
--                       2. Every participant has one, and a lower number is a
--                       better ranking. Only rank positions 1 to 8 are
--                       tournament seeds; they are protected.
--   bracket_position  - the persisted slot in the 64 position template a
--                       player occupies in the draw. Protected for the top 8,
--                       drawn for everyone else.
--   entry_round       - the first Cup round in which the participant can face
--                       another player.
--
-- This migration only adds new objects. It does not change or delete any
-- existing table, view, function, policy, grant or row. Cup scoring, round
-- progression and Cup awards are deliberately out of scope: the tables below
-- reserve the columns those phases will fill, but nothing in this migration
-- reads predictions for scoring or writes leaderboard points.

create table public.cup_competitions (
  id bigint generated always as identity primary key,
  slug text not null,
  season_label text not null,
  bracket_size integer not null default 64,
  participant_count integer not null,
  status text not null default 'active',
  -- Permanent part of the Cup record: the draw is reproducible from this seed
  -- plus the frozen ranking. It is not a secret.
  draw_seed uuid not null default gen_random_uuid(),
  winner_points integer not null default 30,
  finalist_points integer not null default 20,
  semi_finalist_points integer not null default 10,
  created_by uuid
    constraint cup_competitions_created_by_fkey
    references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_competitions_slug_key unique (slug),
  constraint cup_competitions_slug_check check (
    char_length(btrim(slug)) between 1 and 100
  ),
  constraint cup_competitions_season_label_check check (
    char_length(btrim(season_label)) between 1 and 100
  ),
  constraint cup_competitions_bracket_size_check check (bracket_size = 64),
  constraint cup_competitions_participant_count_check check (
    participant_count between 8 and 64
  ),
  constraint cup_competitions_status_check check (
    status in ('active', 'completed')
  ),
  -- Reward configuration lives on the row so a future phase can change
  -- 30/20/10 into 100/60/20 without touching bracket or scoring logic.
  constraint cup_competitions_reward_range_check check (
    winner_points >= 0
    and finalist_points >= 0
    and semi_finalist_points >= 0
  ),
  constraint cup_competitions_reward_order_check check (
    winner_points >= finalist_points
    and finalist_points >= semi_finalist_points
  )
);

comment on table public.cup_competitions is
  'One Players Cup per season. Reward values are configuration: every future award calculation must read them from this row instead of hardcoding 30/20/10. draw_seed replays the draw that produced the stored bracket.';

create index cup_competitions_created_by_idx
  on public.cup_competitions (created_by);

create table public.cup_participants (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_participants_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  -- Nullable on purpose: a deleted profile must empty this reference without
  -- removing the participant row, so the bracket keeps its structure.
  user_id uuid
    constraint cup_participants_user_id_fkey
    references public.profiles (id) on delete set null,
  username_snapshot text not null,
  -- Frozen ranking position after Matchday 2, not a bracket slot. Phase 2 uses
  -- it as the final tie-break, so it must never be overwritten by the draw.
  rank_position integer not null,
  -- The slot in the 64 position template this player occupies.
  bracket_position integer not null,
  -- The first round in which this player meets a real opponent. Derived from
  -- the template at creation and frozen, so the entitlement the draw had to
  -- respect stays auditable.
  entry_round integer not null,
  created_at timestamptz not null default now(),
  constraint cup_participants_username_snapshot_check check (
    char_length(btrim(username_snapshot)) between 1 and 100
  ),
  constraint cup_participants_rank_position_check check (
    rank_position between 1 and 64
  ),
  constraint cup_participants_bracket_position_check check (
    bracket_position between 1 and 64
  ),
  constraint cup_participants_entry_round_check check (
    entry_round between 1 and 6
  ),
  constraint cup_participants_cup_id_rank_position_key
    unique (cup_id, rank_position),
  constraint cup_participants_cup_id_bracket_position_key
    unique (cup_id, bracket_position)
);

comment on table public.cup_participants is
  'Frozen Cup entry list. rank_position is the post-Matchday 2 ranking, bracket_position is the drawn or protected slot in the template, and both are decided once at creation so later results or username changes cannot reshuffle the bracket.';

comment on column public.cup_participants.rank_position is
  'Frozen strict League Phase ranking after Matchday 2, 1..64, where a lower number is a better ranking. Rank positions 1 to 8 are the protected tournament seeds; every other participant is drawn.';

comment on column public.cup_participants.bracket_position is
  'Persisted location in the 64 slot Cup draw. Equal to rank_position for the protected top 8, drawn from the matching entry-round group for everyone else.';

comment on column public.cup_participants.entry_round is
  'First Cup round in which this participant can face another player. Rounds 1 to 6 map to Matchdays 3 to 8.';

-- A partial unique index instead of a unique constraint, because user_id
-- becomes null when a profile is deleted and several withdrawn participants
-- may coexist in the same Cup.
create unique index cup_participants_cup_id_user_id_uidx
  on public.cup_participants (cup_id, user_id)
  where user_id is not null;

create index cup_participants_user_id_idx
  on public.cup_participants (user_id);

create table public.cup_rounds (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_rounds_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_number integer not null,
  slot_count integer not null,
  matchday_id bigint not null
    constraint cup_rounds_matchday_id_fkey
    references public.matchdays (id),
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_rounds_round_number_check check (round_number between 1 and 6),
  constraint cup_rounds_slot_count_check check (
    (round_number = 1 and slot_count = 64)
    or (round_number = 2 and slot_count = 32)
    or (round_number = 3 and slot_count = 16)
    or (round_number = 4 and slot_count = 8)
    or (round_number = 5 and slot_count = 4)
    or (round_number = 6 and slot_count = 2)
  ),
  constraint cup_rounds_status_check check (
    status in ('pending', 'in_progress', 'final')
  ),
  constraint cup_rounds_cup_id_round_number_key unique (cup_id, round_number),
  constraint cup_rounds_cup_id_matchday_id_key unique (cup_id, matchday_id)
);

comment on table public.cup_rounds is
  'Cup round to League Phase matchday mapping: round 1 is Matchday 3 and round 6 (the Final) is Matchday 8.';

create index cup_rounds_matchday_id_idx
  on public.cup_rounds (matchday_id);

create table public.cup_ties (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_ties_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_id bigint not null
    constraint cup_ties_round_id_fkey
    references public.cup_rounds (id) on delete cascade,
  slot integer not null,
  home_participant_id bigint
    constraint cup_ties_home_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  away_participant_id bigint
    constraint cup_ties_away_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  home_points integer not null default 0,
  away_points integer not null default 0,
  home_exact integer not null default 0,
  away_exact integer not null default 0,
  home_correct integer not null default 0,
  away_correct integer not null default 0,
  winner_participant_id bigint
    constraint cup_ties_winner_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  outcome text not null default 'empty',
  decided_by_rule text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_ties_slot_check check (slot between 1 and 32),
  constraint cup_ties_score_check check (
    home_points >= 0
    and away_points >= 0
    and home_exact >= 0
    and away_exact >= 0
    and home_correct >= 0
    and away_correct >= 0
  ),
  constraint cup_ties_distinct_participants_check check (
    home_participant_id is null
    or away_participant_id is null
    or home_participant_id <> away_participant_id
  ),
  constraint cup_ties_outcome_check check (
    outcome in ('empty', 'bye', 'pending', 'decided')
  ),
  -- Reserved for the progression phase: the tie-break chain is Cup points,
  -- exact scores, correct results, then the better ranking, meaning the lower
  -- cup_participants.rank_position.
  constraint cup_ties_decided_by_rule_check check (
    decided_by_rule is null
    or (
      outcome = 'decided'
      and decided_by_rule in ('points', 'exact', 'correct', 'rank_position')
    )
  ),
  -- The sentinel keeps the comparison from evaluating to NULL, which a CHECK
  -- constraint would otherwise accept.
  constraint cup_ties_winner_membership_check check (
    winner_participant_id is null
    or winner_participant_id in (
      coalesce(home_participant_id, -1),
      coalesce(away_participant_id, -1)
    )
  ),
  constraint cup_ties_outcome_state_check check (
    case outcome
      when 'empty' then
        home_participant_id is null
        and away_participant_id is null
        and winner_participant_id is null
      when 'bye' then
        (home_participant_id is null) <> (away_participant_id is null)
        and winner_participant_id is not null
      when 'pending' then
        winner_participant_id is null
      when 'decided' then
        home_participant_id is not null
        and away_participant_id is not null
        and winner_participant_id is not null
      else false
    end
  ),
  constraint cup_ties_cup_id_round_id_slot_key unique (cup_id, round_id, slot)
);

comment on table public.cup_ties is
  'Complete 63-tie bracket skeleton created up front. Round r+1 slot k is fed by round r slots (2k-1) and (2k), so no source-slot metadata is stored and progression never inserts rows.';

comment on column public.cup_ties.decided_by_rule is
  'Reserved for Phase 2. The chain is Cup points, exact scores, correct results, then the better ranking, meaning the lower cup_participants.rank_position.';

create index cup_ties_round_id_slot_idx
  on public.cup_ties (round_id, slot);

create index cup_ties_home_participant_id_idx
  on public.cup_ties (home_participant_id);

create index cup_ties_away_participant_id_idx
  on public.cup_ties (away_participant_id);

create index cup_ties_winner_participant_id_idx
  on public.cup_ties (winner_participant_id);

-- A participant occupies exactly one slot per round. Two partial unique
-- indexes would only catch duplicates within the same column, so the
-- cross-column invariant is enforced by a statement trigger. The table holds
-- 63 rows per Cup, which makes the full check cheaper than transition tables.
create or replace function public.assert_cup_round_participants()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_round_id bigint;
  v_participant_id bigint;
begin
  select side.round_id, side.participant_id
  into v_round_id, v_participant_id
  from (
    select tie.round_id, tie.home_participant_id as participant_id
    from public.cup_ties as tie
    where tie.home_participant_id is not null
    union all
    select tie.round_id, tie.away_participant_id
    from public.cup_ties as tie
    where tie.away_participant_id is not null
  ) as side
  group by side.round_id, side.participant_id
  having count(*) > 1
  limit 1;

  if v_round_id is not null then
    raise exception using
      errcode = '23505',
      message = format(
        'Cup participant %s appears more than once in round %s',
        v_participant_id,
        v_round_id
      );
  end if;

  return null;
end;
$function$;

comment on function public.assert_cup_round_participants()
is 'Rejects any write that would place the same Cup participant in two ties of the same round.';

create trigger cup_ties_unique_round_participants
after insert or update
on public.cup_ties
for each statement
execute function public.assert_cup_round_participants();

-- The classic seeded fold, used purely as a POSITION TEMPLATE. Starting from a
-- single slot the list is doubled by appending each position's mirror label,
-- which yields 1-64, 32-33, 16-49, 17-48 ... for a 64 slot bracket. The labels
-- are bracket positions, not player rankings: only the top 8 ranking positions
-- are mapped onto their matching label, everyone else is drawn.
--
--   fold_position     - physical order down the bracket, 1..64. Fold positions
--                       2k-1 and 2k form round 1 slot k.
--   bracket_position  - the classic label of that slot. Every round 1 pair of
--                       labels sums to bracket_size + 1.
create or replace function public.players_cup_bracket_slots(
  p_bracket_size integer
)
returns table (
  fold_position integer,
  bracket_position integer
)
language sql
immutable
set search_path = ''
as $function$
  with recursive fold as (
    select
      1::integer as size,
      1::integer as fold_position,
      1::integer as bracket_position
    union all
    select
      (fold.size * 2)::integer,
      (fold.fold_position * 2 - (case when mirror.flag then 0 else 1 end))::integer,
      (
        case
          when mirror.flag then fold.size * 2 + 1 - fold.bracket_position
          else fold.bracket_position
        end
      )::integer
    from fold
    cross join (values (false), (true)) as mirror(flag)
    where fold.size < p_bracket_size
  )
  select fold.fold_position, fold.bracket_position
  from fold
  where fold.size = p_bracket_size
  order by fold.fold_position;
$function$;

comment on function public.players_cup_bracket_slots(integer)
is 'Standard bracket position template. Fold positions 2k-1 and 2k form round 1 slot k, and their bracket position labels always sum to bracket_size + 1.';

-- Bye entitlement, derived from the template rather than hardcoded per field
-- size. With N players the occupied slots are the labels 1..N, and a player
-- first meets a real opponent in the earliest round whose merge group already
-- contains another occupied slot. Round r merges the fold positions into
-- groups of 2^r, so this is pure arithmetic on the template.
--
-- Every position sharing an entry round carries the same entitlement, which is
-- the only pool the draw is allowed to shuffle within.
create or replace function public.players_cup_entry_rounds(
  p_participant_count integer
)
returns table (
  bracket_position integer,
  entry_round integer
)
language sql
immutable
set search_path = ''
as $function$
  with occupied as (
    select
      slot_template.bracket_position,
      slot_template.fold_position
    from public.players_cup_bracket_slots(64) as slot_template
    where slot_template.bracket_position <= p_participant_count
  ),
  merge_group as (
    select
      occupied.bracket_position,
      round_number.value as round_number,
      (occupied.fold_position - 1) / (1 << round_number.value) as group_index
    from occupied
    cross join generate_series(1, 6) as round_number(value)
  )
  select
    merge_group.bracket_position,
    min(merge_group.round_number)::integer as entry_round
  from merge_group
  join merge_group as opponent
    on opponent.round_number = merge_group.round_number
    and opponent.group_index = merge_group.group_index
    and opponent.bracket_position <> merge_group.bracket_position
  group by merge_group.bracket_position;
$function$;

comment on function public.players_cup_entry_rounds(integer)
is 'Round in which each occupied bracket position first meets a real opponent, for a field of the given size. Positions sharing an entry round share a bye entitlement.';

-- The draw. Ranking positions 1 to 8 are tournament seeds and are pinned to
-- their protected bracket positions, which the template keeps in eight
-- different eighth-brackets so they cannot meet before the quarter-finals.
-- Everyone else is shuffled, but only inside their own entry-round group, so a
-- draw can never hand a lower-ranked player a better entry round than a higher
-- ranked one.
--
-- The shuffle is a hash of draw_seed and user_id, so the same seed and the same
-- ranking always rebuild exactly the same bracket.
create or replace function public.players_cup_draw(
  p_draw_seed uuid,
  p_participants jsonb
)
returns table (
  rank_position integer,
  user_id uuid,
  bracket_position integer,
  entry_round integer,
  is_protected_seed boolean
)
language plpgsql
stable
set search_path = ''
as $function$
declare
  c_bracket_size constant integer := 64;
  c_protected_seed_count constant integer := 8;
  v_participant_count integer := jsonb_array_length(p_participants);
begin
  if v_participant_count is null
    or v_participant_count < 2
    or v_participant_count > c_bracket_size
  then
    raise exception using
      errcode = '22023',
      message = format(
        'The Cup draw needs between 2 and %s participants',
        c_bracket_size
      );
  end if;

  -- Everything below relies on the template ordering its own positions by
  -- entitlement: position 1 must carry the best entry round and position N the
  -- worst. That makes ranking position r and bracket position r land in the
  -- same entitlement group, which is what lets the top 8 be pinned without
  -- disturbing the tiers.
  if exists (
    select 1
    from (
      select
        entitlement.bracket_position,
        row_number() over (
          order by entitlement.entry_round desc, entitlement.bracket_position
        ) as entitlement_order
      from public.players_cup_entry_rounds(v_participant_count) as entitlement
    ) as ordered
    where ordered.bracket_position <> ordered.entitlement_order
  ) then
    raise exception using
      errcode = '55000',
      message = 'The bracket template does not order entry-round entitlement by position';
  end if;

  return query
  with participant as (
    select
      (ranked.entry->>'rank_position')::integer as rank_position,
      (ranked.entry->>'user_id')::uuid as user_id
    from jsonb_array_elements(p_participants) as ranked(entry)
  ),
  entitlement as (
    select
      grouped.bracket_position,
      grouped.entry_round
    from public.players_cup_entry_rounds(v_participant_count) as grouped
  ),
  protected_placement as (
    select
      participant.rank_position,
      participant.user_id,
      participant.rank_position as bracket_position,
      true as is_protected_seed
    from participant
    where participant.rank_position <= c_protected_seed_count
  ),
  drawn_player as (
    select
      participant.rank_position,
      participant.user_id,
      entitlement.entry_round,
      row_number() over (
        partition by entitlement.entry_round
        order by decode(
          md5(p_draw_seed::text || ':' || participant.user_id::text),
          'hex'
        )
      ) as draw_order
    from participant
    -- Ranking position r belongs to the entitlement group of bracket position
    -- r, which the invariant above guarantees.
    join entitlement
      on entitlement.bracket_position = participant.rank_position
    where participant.rank_position > c_protected_seed_count
  ),
  drawn_position as (
    select
      entitlement.bracket_position,
      entitlement.entry_round,
      row_number() over (
        partition by entitlement.entry_round
        order by entitlement.bracket_position
      ) as position_order
    from entitlement
    where entitlement.bracket_position > c_protected_seed_count
  ),
  drawn_placement as (
    select
      drawn_player.rank_position,
      drawn_player.user_id,
      drawn_position.bracket_position,
      false as is_protected_seed
    from drawn_player
    join drawn_position
      on drawn_position.entry_round = drawn_player.entry_round
      and drawn_position.position_order = drawn_player.draw_order
  ),
  placement as (
    select * from protected_placement
    union all
    select * from drawn_placement
  )
  select
    placement.rank_position,
    placement.user_id,
    placement.bracket_position,
    entitlement.entry_round,
    placement.is_protected_seed
  from placement
  join entitlement
    on entitlement.bracket_position = placement.bracket_position
  order by placement.rank_position;
end;
$function$;

comment on function public.players_cup_draw(uuid, jsonb)
is 'Places the frozen ranking into the 64 position template: ranking positions 1 to 8 keep their protected seed positions, everyone else is shuffled inside their own entry-round group by a hash of draw_seed and user_id.';

-- Strict total order over active players, derived only from League Phase
-- Matchday 1 and 2 results. Long-term awards, Cup points and Matchday 3+
-- results are structurally excluded, and the username/user_id terms guarantee
-- that no two players can share a rank position.
create or replace function public.players_cup_ranking()
returns table (
  rank_position integer,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with ranking_matches as (
    select match_row.id, match_row.status
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
  ),
  ranking_predictions as (
    select
      prediction.id,
      prediction.user_id,
      prediction.points,
      ranking_matches.status as match_status
    from public.predictions as prediction
    join ranking_matches
      on ranking_matches.id = prediction.match_id
  ),
  finished_ranking_matches as (
    select count(*)::bigint as finished_count
    from ranking_matches
    where ranking_matches.status = 'finished'
  ),
  player_stats as (
    select
      profile.id as user_id,
      profile.username,
      coalesce(sum(prediction.points), 0)::bigint as total_points,
      count(prediction.id)
        filter (where prediction.points in (5, 10))::bigint as exact_scores,
      count(prediction.id)
        filter (where prediction.points in (2, 4))::bigint as correct_results,
      (
        (select finished_count from finished_ranking_matches)
        - count(prediction.id)
          filter (where prediction.match_status = 'finished')
      )::bigint as missed_predictions
    from public.profiles as profile
    left join ranking_predictions as prediction
      on prediction.user_id = profile.id
    where profile.status = 'active'
    group by profile.id, profile.username
  )
  select
    row_number() over (
      order by
        player_stats.total_points desc,
        player_stats.exact_scores desc,
        player_stats.correct_results desc,
        player_stats.missed_predictions asc,
        lower(player_stats.username) asc,
        player_stats.user_id asc
    )::integer as rank_position,
    player_stats.user_id,
    player_stats.username,
    player_stats.total_points,
    player_stats.exact_scores,
    player_stats.correct_results,
    player_stats.missed_predictions
  from player_stats
  order by rank_position;
$function$;

comment on function public.players_cup_ranking()
is 'Strict Players Cup ranking from League Phase Matchday 1 and 2 only. Never includes long-term awards or Matchday 3+ results. Position 1 is the best ranking.';

create or replace function public.create_players_cup(
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  c_season_label constant text := 'Champions League 2026/27';
  c_bracket_size constant integer := 64;
  c_minimum_participants constant integer := 8;
  c_protected_seed_count constant integer := 8;
  -- Initial reward configuration. Once the row exists it is the only source of
  -- truth; award calculation must never read these constants.
  c_winner_points constant integer := 30;
  c_finalist_points constant integer := 20;
  c_semi_finalist_points constant integer := 10;

  v_admin_id uuid := (select auth.uid());
  v_cup_id bigint;
  v_summary jsonb;
  v_ranking jsonb;
  v_participants jsonb;
  -- One draw seed per call. A dry run returns it as a preview seed and throws
  -- it away; a real creation persists it alongside the bracket it produced.
  v_draw_seed uuid := gen_random_uuid();
  v_draw jsonb;
  v_preview jsonb;
  v_eligible_count integer;
  v_participant_count integer;
  v_matchday_count integer;
  v_ranking_match_count integer;
  v_ranking_finished_count integer;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Serializes concurrent creation attempts. The lock is released at commit or
  -- rollback, so two simultaneous callers converge on one competition instead
  -- of racing on the unique slug.
  perform pg_advisory_xact_lock(
    hashtext('public.create_players_cup:' || c_slug)::bigint
  );

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug
  for update;

  -- The Cup is never regenerated. An existing bracket is reported back
  -- untouched, for a dry run and for a normal call alike.
  if v_cup_id is not null then
    select jsonb_build_object(
      'already_exists', true,
      'created', false,
      'dry_run', p_dry_run,
      'cup_id', competition.id,
      'slug', competition.slug,
      'season_label', competition.season_label,
      'status', competition.status,
      'bracket_size', competition.bracket_size,
      'protected_seed_count', c_protected_seed_count,
      'participant_count', competition.participant_count,
      'draw_seed', competition.draw_seed,
      'draw_is_preview', false,
      'created_at', competition.created_at,
      'rewards', jsonb_build_object(
        'winner_points', competition.winner_points,
        'finalist_points', competition.finalist_points,
        'semi_finalist_points', competition.semi_finalist_points
      ),
      'round_count', (
        select count(*)
        from public.cup_rounds as round
        where round.cup_id = competition.id
      ),
      'tie_count', (
        select count(*)
        from public.cup_ties as tie
        where tie.cup_id = competition.id
      ),
      'round_one', (
        select jsonb_build_object(
          'real_tie_count',
            count(*) filter (where tie.outcome = 'pending'),
          'bye_count',
            count(*) filter (where tie.outcome = 'bye'),
          'empty_tie_count',
            count(*) filter (where tie.outcome = 'empty')
        )
        from public.cup_ties as tie
        join public.cup_rounds as round
          on round.id = tie.round_id
        where round.cup_id = competition.id
          and round.round_number = 1
      )
    )
    into v_summary
    from public.cup_competitions as competition
    where competition.id = v_cup_id;

    return v_summary;
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  if v_matchday_count <> 6 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 3 to 8 must all exist before the Players Cup can be created';
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_matchday_count <> 2 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 are required for a deterministic ranking';
  end if;

  -- Freezes the ranking inputs for the rest of the transaction, so a result
  -- correction cannot land between the preview and the written bracket.
  perform 1
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2
  order by match_row.id
  for share of match_row;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into v_ranking_match_count, v_ranking_finished_count
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_ranking_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 have no configured matches';
  end if;

  if v_ranking_finished_count <> v_ranking_match_count then
    raise exception using
      errcode = '22023',
      message = 'The Cup ranking requires every League Phase Matchday 1 and 2 match to be finished';
  end if;

  if exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
      and prediction.points is null
  ) then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchday 1 and 2 predictions are not fully scored';
  end if;

  -- Single evaluation of the ranking. Everything below reads this snapshot, so
  -- a registration committed mid-call cannot change the written bracket.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank_position', ranking.rank_position,
          'user_id', ranking.user_id,
          'username', ranking.username,
          'total_points', ranking.total_points,
          'exact_scores', ranking.exact_scores,
          'correct_results', ranking.correct_results,
          'missed_predictions', ranking.missed_predictions
        )
        order by ranking.rank_position
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_ranking, v_eligible_count
  from public.players_cup_ranking() as ranking;

  if v_eligible_count < c_minimum_participants then
    raise exception using
      errcode = '22023',
      message = format(
        'The Players Cup needs at least %s active players, found %s',
        c_minimum_participants,
        v_eligible_count
      );
  end if;

  v_participant_count := least(v_eligible_count, c_bracket_size);

  select coalesce(
    jsonb_agg(ranked.entry order by (ranked.entry->>'rank_position')::integer),
    '[]'::jsonb
  )
  into v_participants
  from jsonb_array_elements(v_ranking) as ranked(entry)
  where (ranked.entry->>'rank_position')::integer <= v_participant_count;

  -- Drawn once. The preview and the persisted bracket are built from this one
  -- result, so what an admin sees is exactly what gets written.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank_position', placement.rank_position,
        'user_id', placement.user_id,
        'bracket_position', placement.bracket_position,
        'entry_round', placement.entry_round,
        'is_protected_seed', placement.is_protected_seed
      )
      order by placement.rank_position
    ),
    '[]'::jsonb
  )
  into v_draw
  from public.players_cup_draw(v_draw_seed, v_participants) as placement;

  with ranking_entry as (
    select
      (ranked.entry->>'rank_position')::integer as rank_position,
      (ranked.entry->>'user_id')::uuid as user_id,
      ranked.entry->>'username' as username,
      (ranked.entry->>'total_points')::bigint as total_points,
      (ranked.entry->>'exact_scores')::bigint as exact_scores,
      (ranked.entry->>'correct_results')::bigint as correct_results,
      (ranked.entry->>'missed_predictions')::bigint as missed_predictions
    from jsonb_array_elements(v_ranking) as ranked(entry)
  ),
  placement as (
    select
      (drawn.entry->>'rank_position')::integer as rank_position,
      (drawn.entry->>'bracket_position')::integer as bracket_position,
      (drawn.entry->>'entry_round')::integer as entry_round,
      (drawn.entry->>'is_protected_seed')::boolean as is_protected_seed
    from jsonb_array_elements(v_draw) as drawn(entry)
  ),
  placed_player as (
    select
      placement.rank_position,
      placement.bracket_position,
      placement.entry_round,
      placement.is_protected_seed,
      ranking_entry.user_id,
      ranking_entry.username
    from placement
    join ranking_entry
      on ranking_entry.rank_position = placement.rank_position
  ),
  pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  tie_preview as (
    select
      pairing.slot,
      pairing.home_bracket_position,
      pairing.away_bracket_position,
      home_player.rank_position as home_rank_position,
      away_player.rank_position as away_rank_position,
      home_player.username as home_username,
      away_player.username as away_username,
      case
        when home_player.rank_position is null
          and away_player.rank_position is null then 'empty'
        when home_player.rank_position is null
          or away_player.rank_position is null then 'bye'
        else 'pending'
      end as outcome
    from pairing
    left join placed_player as home_player
      on home_player.bracket_position = pairing.home_bracket_position
    left join placed_player as away_player
      on away_player.bracket_position = pairing.away_bracket_position
  ),
  participant_preview as (
    select
      placed_player.rank_position,
      placed_player.bracket_position,
      placed_player.entry_round,
      placed_player.is_protected_seed,
      placed_player.user_id,
      placed_player.username,
      ranking_entry.total_points,
      ranking_entry.exact_scores,
      ranking_entry.correct_results,
      ranking_entry.missed_predictions,
      tie_preview.slot as round_one_slot,
      tie_preview.outcome as round_one_outcome
    from placed_player
    join ranking_entry
      on ranking_entry.rank_position = placed_player.rank_position
    join tie_preview
      on tie_preview.home_bracket_position = placed_player.bracket_position
      or tie_preview.away_bracket_position = placed_player.bracket_position
  )
  select jsonb_build_object(
    'already_exists', false,
    'dry_run', p_dry_run,
    'slug', c_slug,
    'season_label', c_season_label,
    'status', 'active',
    'bracket_size', c_bracket_size,
    'protected_seed_count', c_protected_seed_count,
    'minimum_participants', c_minimum_participants,
    'eligible_count', v_eligible_count,
    'participant_count', v_participant_count,
    'excluded_count', v_eligible_count - v_participant_count,
    'draw_seed', v_draw_seed,
    -- A dry run seed is thrown away: two previews before creation may differ,
    -- and only the seed stored by the real creation describes the real bracket.
    'draw_is_preview', p_dry_run,
    'rewards', jsonb_build_object(
      'winner_points', c_winner_points,
      'finalist_points', c_finalist_points,
      'semi_finalist_points', c_semi_finalist_points
    ),
    'rounds', (
      select jsonb_agg(
        jsonb_build_object(
          'round_number', matchday.matchday_number - 2,
          'slot_count', case matchday.matchday_number
            when 3 then 64
            when 4 then 32
            when 5 then 16
            when 6 then 8
            when 7 then 4
            else 2
          end,
          'tie_count', case matchday.matchday_number
            when 3 then 32
            when 4 then 16
            when 5 then 8
            when 6 then 4
            when 7 then 2
            else 1
          end,
          'matchday_id', matchday.id,
          'matchday_number', matchday.matchday_number,
          'matchday_name', matchday.name
        )
        order by matchday.matchday_number
      )
      from public.matchdays as matchday
      where matchday.stage = 'league_phase'
        and matchday.matchday_number between 3 and 8
    ),
    'entry_round_entitlement', (
      select jsonb_agg(
        jsonb_build_object(
          'entry_round', tier.entry_round,
          'matchday_number', tier.entry_round + 2,
          'player_count', tier.player_count,
          'first_rank_position', tier.first_rank_position,
          'last_rank_position', tier.last_rank_position
        )
        order by tier.entry_round
      )
      from (
        select
          participant_preview.entry_round,
          count(*) as player_count,
          min(participant_preview.rank_position) as first_rank_position,
          max(participant_preview.rank_position) as last_rank_position
        from participant_preview
        group by participant_preview.entry_round
      ) as tier
    ),
    'top_8_seeded', (
      select jsonb_agg(
        jsonb_build_object(
          'rank_position', participant_preview.rank_position,
          'user_id', participant_preview.user_id,
          'username', participant_preview.username,
          'bracket_position', participant_preview.bracket_position,
          'entry_round', participant_preview.entry_round
        )
        order by participant_preview.rank_position
      )
      from participant_preview
      where participant_preview.is_protected_seed
    ),
    'round_one', jsonb_build_object(
      'real_tie_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'pending'
      ),
      'bye_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'bye'
      ),
      'empty_tie_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'empty'
      ),
      'ties', (
        select jsonb_agg(
          jsonb_build_object(
            'slot', tie_preview.slot,
            'home_bracket_position', tie_preview.home_bracket_position,
            'away_bracket_position', tie_preview.away_bracket_position,
            'home_rank_position', tie_preview.home_rank_position,
            'away_rank_position', tie_preview.away_rank_position,
            'home_username', tie_preview.home_username,
            'away_username', tie_preview.away_username,
            'outcome', tie_preview.outcome
          )
          order by tie_preview.slot
        )
        from tie_preview
      )
    ),
    'participants', (
      select jsonb_agg(
        jsonb_build_object(
          'rank_position', participant_preview.rank_position,
          'user_id', participant_preview.user_id,
          'username', participant_preview.username,
          'bracket_position', participant_preview.bracket_position,
          'entry_round', participant_preview.entry_round,
          'entry_matchday_number', participant_preview.entry_round + 2,
          'is_protected_seed', participant_preview.is_protected_seed,
          'is_drawn', not participant_preview.is_protected_seed,
          'total_points', participant_preview.total_points,
          'exact_scores', participant_preview.exact_scores,
          'correct_results', participant_preview.correct_results,
          'missed_predictions', participant_preview.missed_predictions,
          'round_one_slot', participant_preview.round_one_slot,
          'round_one_outcome', participant_preview.round_one_outcome
        )
        order by participant_preview.rank_position
      )
      from participant_preview
    ),
    'excluded', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'rank_position', ranking_entry.rank_position,
            'user_id', ranking_entry.user_id,
            'username', ranking_entry.username
          )
          order by ranking_entry.rank_position
        ),
        '[]'::jsonb
      )
      from ranking_entry
      where ranking_entry.rank_position > v_participant_count
    )
  )
  into v_preview;

  if p_dry_run then
    return v_preview || jsonb_build_object(
      'created', false,
      'cup_id', null::bigint
    );
  end if;

  insert into public.cup_competitions (
    slug,
    season_label,
    bracket_size,
    participant_count,
    status,
    draw_seed,
    winner_points,
    finalist_points,
    semi_finalist_points,
    created_by
  )
  values (
    c_slug,
    c_season_label,
    c_bracket_size,
    v_participant_count,
    'active',
    v_draw_seed,
    c_winner_points,
    c_finalist_points,
    c_semi_finalist_points,
    v_admin_id
  )
  returning cup_competitions.id into v_cup_id;

  insert into public.cup_participants (
    cup_id,
    user_id,
    username_snapshot,
    rank_position,
    bracket_position,
    entry_round
  )
  select
    v_cup_id,
    (drawn.entry->>'user_id')::uuid,
    ranked.entry->>'username',
    (drawn.entry->>'rank_position')::integer,
    (drawn.entry->>'bracket_position')::integer,
    (drawn.entry->>'entry_round')::integer
  from jsonb_array_elements(v_draw) as drawn(entry)
  join jsonb_array_elements(v_ranking) as ranked(entry)
    on (ranked.entry->>'rank_position')::integer
      = (drawn.entry->>'rank_position')::integer;

  insert into public.cup_rounds (
    cup_id,
    round_number,
    slot_count,
    matchday_id,
    status
  )
  select
    v_cup_id,
    matchday.matchday_number - 2,
    case matchday.matchday_number
      when 3 then 64
      when 4 then 32
      when 5 then 16
      when 6 then 8
      when 7 then 4
      else 2
    end,
    matchday.id,
    'pending'
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  -- The whole skeleton exists from creation: 32+16+8+4+2+1 ties. Progression
  -- will only ever update these rows.
  insert into public.cup_ties (cup_id, round_id, slot, outcome)
  select v_cup_id, round.id, slot_series.slot, 'empty'
  from public.cup_rounds as round
  cross join lateral generate_series(1, round.slot_count / 2) as slot_series(slot)
  where round.cup_id = v_cup_id;

  with pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  resolved as (
    select
      pairing.slot,
      home_participant.id as home_participant_id,
      away_participant.id as away_participant_id
    from pairing
    left join public.cup_participants as home_participant
      on home_participant.cup_id = v_cup_id
      and home_participant.bracket_position = pairing.home_bracket_position
    left join public.cup_participants as away_participant
      on away_participant.cup_id = v_cup_id
      and away_participant.bracket_position = pairing.away_bracket_position
  )
  update public.cup_ties as tie
  set
    home_participant_id = resolved.home_participant_id,
    away_participant_id = resolved.away_participant_id,
    winner_participant_id = case
      when resolved.home_participant_id is null
        then resolved.away_participant_id
      when resolved.away_participant_id is null
        then resolved.home_participant_id
      else null
    end,
    outcome = case
      when resolved.home_participant_id is null
        and resolved.away_participant_id is null then 'empty'
      when resolved.home_participant_id is null
        or resolved.away_participant_id is null then 'bye'
      else 'pending'
    end,
    updated_at = now()
  from resolved
  join public.cup_rounds as round
    on round.cup_id = v_cup_id
    and round.round_number = 1
  where tie.round_id = round.id
    and tie.slot = resolved.slot;

  return v_preview || jsonb_build_object(
    'created', true,
    'cup_id', v_cup_id
  );
end;
$function$;

comment on function public.create_players_cup(boolean)
is 'Admin-only Players Cup creation. Freezes the Matchday 1-2 ranking, protects the top 8, draws everyone else inside their entry-round group from a persisted draw_seed, writes the full six round and 63 tie skeleton, and never regenerates an existing Cup. Scoring, progression and awards are out of scope.';

alter table public.cup_competitions enable row level security;
alter table public.cup_participants enable row level security;
alter table public.cup_rounds enable row level security;
alter table public.cup_ties enable row level security;

-- Read-only for players. No insert, update or delete policy exists on any Cup
-- table, so the Data API rejects every browser write before column grants are
-- considered.
create policy "Authenticated users can view the Players Cup"
  on public.cup_competitions
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup participants"
  on public.cup_participants
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup rounds"
  on public.cup_rounds
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup ties"
  on public.cup_ties
  for select
  to authenticated
  using (true);

revoke all privileges on table public.cup_competitions
  from public, anon, authenticated;
revoke all privileges on table public.cup_participants
  from public, anon, authenticated;
revoke all privileges on table public.cup_rounds
  from public, anon, authenticated;
revoke all privileges on table public.cup_ties
  from public, anon, authenticated;

grant select on table public.cup_competitions to authenticated;
grant select on table public.cup_participants to authenticated;
grant select on table public.cup_rounds to authenticated;
grant select on table public.cup_ties to authenticated;

grant all privileges on table public.cup_competitions to service_role;
grant all privileges on table public.cup_participants to service_role;
grant all privileges on table public.cup_rounds to service_role;
grant all privileges on table public.cup_ties to service_role;

revoke all privileges on sequence public.cup_competitions_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_participants_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_rounds_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_ties_id_seq
  from public, anon, authenticated;

grant all privileges on sequence public.cup_competitions_id_seq to service_role;
grant all privileges on sequence public.cup_participants_id_seq to service_role;
grant all privileges on sequence public.cup_rounds_id_seq to service_role;
grant all privileges on sequence public.cup_ties_id_seq to service_role;

-- The browser may invoke the creation RPC, but the function rejects every
-- caller who is not an active administrator.
revoke execute on function public.create_players_cup(boolean)
  from public, anon;
grant execute on function public.create_players_cup(boolean)
  to authenticated, service_role;

-- Internal helpers. players_cup_ranking aggregates every player's predictions,
-- so it must never be reachable from the browser.
revoke execute on function public.players_cup_ranking()
  from public, anon, authenticated;
grant execute on function public.players_cup_ranking()
  to service_role;

revoke execute on function public.players_cup_bracket_slots(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_bracket_slots(integer)
  to service_role;

revoke execute on function public.players_cup_entry_rounds(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_entry_rounds(integer)
  to service_role;

revoke execute on function public.players_cup_draw(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.players_cup_draw(uuid, jsonb)
  to service_role;

revoke execute on function public.assert_cup_round_participants()
  from public, anon, authenticated;


-- =====================================================================
-- SOURCE: supabase/migrations/20260820095100_players_cup_phase_2a.sql
-- =====================================================================

-- Players Cup, Phase 2A: the isolated scoring, progression and award engine.
--
-- Phase 1 froze the entry list, the ranking and the 63 tie skeleton. This
-- migration adds everything that DERIVES from football results:
--   * Cup matchday scores, exact and correct-result counters
--   * the four step tie-break chain
--   * structural byes, and the waiting state that must never be mistaken for one
--   * round progression through the whole bracket
--   * Cup awards
--   * an admin recovery RPC
--   * the postponed-match cutoff, so one unplayed fixture cannot freeze the Cup
--   * matchday membership immutability for Matchdays 3 to 8
--
-- Two deliberate omissions belong to Phase 2B and are NOT part of this file:
--   * public.get_leaderboard() is untouched, so Cup awards do not reach the
--     overall standings yet.
--   * public.set_match_result() is untouched, so nothing recomputes the Cup
--     automatically yet. public.players_cup_lock_key() below already fixes the
--     lock ordering that integration will need.
--
-- Everything here is additive. No existing table, function, policy, grant or
-- row is modified.

-- ---------------------------------------------------------------------------
-- Prediction quality classifiers
-- ---------------------------------------------------------------------------

-- The normal 5/2/0 and Golden Match 10/4/0 scales are already stored in
-- predictions.points, and the whole application infers prediction quality from
-- that single column. The mapping was duplicated in get_leaderboard and
-- players_cup_ranking; these two functions are the one place a future scoring
-- change has to be made.
--
-- An unscored prediction is NULL, which is neither exact nor correct, so both
-- functions are deliberately non-strict and coalesce their own result.
create or replace function public.prediction_is_exact(p_points integer)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(p_points in (5, 10), false);
$function$;

comment on function public.prediction_is_exact(integer)
is 'True when a prediction scored an exact score, normal (5) or Golden Match (10). NULL points count as false.';

-- The two counters partition the scored predictions: an exact score is never
-- also counted as a correct result, which is what the overall leaderboard
-- already does.
create or replace function public.prediction_is_correct(p_points integer)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(p_points in (2, 4), false);
$function$;

comment on function public.prediction_is_correct(integer)
is 'True when a prediction scored a correct result but not an exact score, normal (2) or Golden Match (4). NULL points count as false.';

-- ---------------------------------------------------------------------------
-- Postponed match cutoff
-- ---------------------------------------------------------------------------

-- A postponed match must not freeze a Cup round for ever. For rounds 1 to 5
-- (Matchdays 3 to 7) a match that is still unfinished when the first match of
-- the next League Phase matchday kicks off is dropped from Cup scoring for its
-- own round, permanently.
--
-- Why this needs a row instead of pure derivation: the rule is evaluated at an
-- instant (the cutoff), but the schema only stores current state. Once the
-- postponed match is finally marked 'finished', nothing left in public.matches
-- proves whether that happened before or after the cutoff - matches.updated_at
-- also moves for kickoff edits and later result corrections, so it cannot carry
-- the decision. This table is therefore the smallest auditable record of a
-- decision that was already taken, and a recompute never deletes from it.
--
-- Rows are written only by public.players_cup_freeze_exclusions, which any Cup
-- write path calls while the postponed match is still visibly unfinished.
-- players_cup_round_matches also derives the same exclusion from live state, so
-- a cutoff that passes between two freezes is still caught whenever the match
-- was rescheduled to kick off after it.
create table public.cup_excluded_matches (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_excluded_matches_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_id bigint not null
    constraint cup_excluded_matches_round_id_fkey
    references public.cup_rounds (id) on delete cascade,
  match_id bigint not null
    constraint cup_excluded_matches_match_id_fkey
    references public.matches (id) on delete cascade,
  cutoff_at timestamptz not null,
  excluded_at timestamptz not null default now(),
  constraint cup_excluded_matches_cup_id_match_id_key unique (cup_id, match_id)
);

comment on table public.cup_excluded_matches is
  'Permanent record that a match was still unfinished when the next League Phase matchday began, so it scores no Cup points for its own round. Written once by players_cup_freeze_exclusions and never removed, because a later result must not reopen a closed Cup round.';

create index cup_excluded_matches_round_id_idx
  on public.cup_excluded_matches (round_id);

create index cup_excluded_matches_match_id_idx
  on public.cup_excluded_matches (match_id);

-- ---------------------------------------------------------------------------
-- Cup awards
-- ---------------------------------------------------------------------------

-- Identity is the participant, not the user: a deleted profile empties user_id
-- but must not break the Cup honours list, and the unique constraint is what
-- makes the non-cumulative rule structural rather than procedural.
create table public.cup_awards (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_awards_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  participant_id bigint not null
    constraint cup_awards_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  user_id uuid
    constraint cup_awards_user_id_fkey
    references public.profiles (id) on delete set null,
  award_type text not null,
  points integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_awards_award_type_check check (
    award_type in ('winner', 'finalist', 'semi_finalist')
  ),
  constraint cup_awards_points_check check (points >= 0),
  constraint cup_awards_cup_id_participant_id_key unique (cup_id, participant_id)
);

comment on table public.cup_awards is
  'Derived Cup honours, rebuilt from the bracket on every recompute. One row per qualifying participant enforces the non-cumulative rule: a champion never also holds a finalist or semi-finalist award. Point values are copied from the cup_competitions reward configuration, never hardcoded.';

create index cup_awards_user_id_idx
  on public.cup_awards (user_id);

create index cup_awards_participant_id_idx
  on public.cup_awards (participant_id);

-- ---------------------------------------------------------------------------
-- Locking
-- ---------------------------------------------------------------------------

-- One key for the whole competition. Phase 2B will call players_cup_apply from
-- inside set_match_result, and it must take THIS lock before locking any match
-- row: the reverse order lets two admins scoring two different matches wait on
-- each other. Exposing the key as a function keeps both call sites identical.
create or replace function public.players_cup_lock_key()
returns bigint
language sql
immutable
set search_path = ''
as $function$
  select hashtext('public.players_cup:players-cup-2026-27')::bigint;
$function$;

comment on function public.players_cup_lock_key()
is 'Advisory lock key for every Players Cup write path. Always acquire it before locking match rows, otherwise concurrent result entry can deadlock.';

-- ---------------------------------------------------------------------------
-- Structural tie layout
-- ---------------------------------------------------------------------------

-- For a field of N players the occupied slots of the template are the labels
-- 1..N. Round r merges the fold positions into groups of 2^r, the first half of
-- each group feeding the home side and the second half the away side, so the
-- number of players that can EVER arrive on each side is pure arithmetic on the
-- Phase 1 template.
--
-- This is what separates the two one-sided ties that look identical in the
-- data:
--   capacity 0 on the far side   -> a bye, nobody can ever arrive
--   capacity > 0 on the far side -> waiting, the feeder simply has not resolved
-- Only the first may advance a player.
create or replace function public.players_cup_tie_layout(
  p_participant_count integer
)
returns table (
  round_number integer,
  slot integer,
  home_capacity integer,
  away_capacity integer
)
language sql
immutable
set search_path = ''
as $function$
  with side as (
    select
      round_series.value as round_number,
      ((slot_template.fold_position - 1) / (1 << round_series.value)) + 1
        as slot,
      (
        ((slot_template.fold_position - 1) % (1 << round_series.value))
        < (1 << (round_series.value - 1))
      ) as is_home,
      slot_template.bracket_position
    from public.players_cup_bracket_slots(64) as slot_template
    cross join generate_series(1, 6) as round_series(value)
  )
  select
    side.round_number::integer,
    side.slot::integer,
    count(*) filter (
      where side.is_home
        and side.bracket_position <= p_participant_count
    )::integer as home_capacity,
    count(*) filter (
      where not side.is_home
        and side.bracket_position <= p_participant_count
    )::integer as away_capacity
  from side
  group by side.round_number, side.slot;
$function$;

comment on function public.players_cup_tie_layout(integer)
is 'How many players can ever reach each side of every tie, for a field of the given size. Capacity 0 on one side is a structural bye; capacity 0 on both is an empty tie. A side with capacity but no player yet is waiting, never a bye.';

-- ---------------------------------------------------------------------------
-- Round matches and the exclusion decision
-- ---------------------------------------------------------------------------

-- One row per match of every Cup round, plus one row with a null match_id for a
-- round whose matchday has no matches configured yet, so callers always see all
-- six rounds.
--
-- A match is excluded when the cutoff has passed and it either is not finished
-- or was rescheduled to kick off at or after the cutoff. The second clause
-- matters after the fact: a match cannot have been finished before it kicked
-- off, so a kickoff at or after the cutoff proves the match was still open when
-- the round closed, even when a result is entered much later.
create or replace function public.players_cup_round_matches(p_cup_id bigint)
returns table (
  round_number integer,
  round_id bigint,
  matchday_id bigint,
  cutoff_at timestamptz,
  match_id bigint,
  match_status text,
  kickoff_at timestamptz,
  is_excluded boolean,
  exclusion_is_frozen boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  with cup_round as (
    select
      round.round_number,
      round.id as round_id,
      round.matchday_id,
      matchday.matchday_number
    from public.cup_rounds as round
    join public.matchdays as matchday
      on matchday.id = round.matchday_id
    where round.cup_id = p_cup_id
  ),
  round_cutoff as (
    select
      cup_round.round_number,
      cup_round.round_id,
      cup_round.matchday_id,
      -- Round 6 is the Final: there is no next League Phase matchday, so no
      -- cutoff exists and the Final waits for every match.
      case
        when cup_round.round_number <= 5 then (
          select min(next_match.kickoff_at)
          from public.matches as next_match
          join public.matchdays as next_matchday
            on next_matchday.id = next_match.matchday_id
          where next_matchday.stage = 'league_phase'
            and next_matchday.matchday_number = cup_round.matchday_number + 1
        )
      end as cutoff_at
    from cup_round
  )
  select
    round_cutoff.round_number,
    round_cutoff.round_id,
    round_cutoff.matchday_id,
    round_cutoff.cutoff_at,
    match_row.id,
    match_row.status,
    match_row.kickoff_at,
    coalesce(
      frozen.match_id is not null
      or (
        round_cutoff.cutoff_at is not null
        and now() >= round_cutoff.cutoff_at
        and (
          match_row.status <> 'finished'
          or match_row.kickoff_at >= round_cutoff.cutoff_at
        )
      ),
      false
    ),
    frozen.match_id is not null
  from round_cutoff
  left join public.matches as match_row
    on match_row.matchday_id = round_cutoff.matchday_id
  left join public.cup_excluded_matches as frozen
    on frozen.cup_id = p_cup_id
    and frozen.match_id = match_row.id;
$function$;

comment on function public.players_cup_round_matches(bigint)
is 'Every match of every Cup round with its postponed-match exclusion decision. Rounds 1 to 5 close at the first kickoff of the next League Phase matchday; the Final has no cutoff.';

-- Writes down every exclusion the cutoff already implies AT THIS MOMENT, and
-- nothing else. It never reads or writes the bracket, the awards, the
-- predictions or the matches, so it is safe to call at any point in a
-- transaction.
--
-- Why it is separate from the recompute: derivation alone cannot always
-- reconstruct the decision afterwards. Once an admin enters the result of a
-- long-postponed match, the row may read status = 'finished' with its ORIGINAL
-- pre-cutoff kickoff_at, which no longer proves the match was still open when
-- the round closed. The decision therefore has to be captured while the match
-- is still visibly unfinished.
--
-- LOCKING CONTRACT: this function takes no lock of its own. Every caller must
-- already hold pg_advisory_xact_lock(public.players_cup_lock_key()), which is
-- also the first lock in the global ordering:
--
--   1. pg_advisory_xact_lock(public.players_cup_lock_key())
--   2. public.players_cup_freeze_exclusions(cup_id)   <- before the match moves
--   3. select ... from public.matches ... for update
--   4. rescore the predictions of that match
--   5. public.players_cup_apply(cup_id)
--
-- Phase 2B will follow exactly this order inside set_match_result. Taking a
-- second, independent lock here would break that ordering and reintroduce the
-- deadlock the single Cup lock exists to prevent.
create or replace function public.players_cup_freeze_exclusions(p_cup_id bigint)
returns integer
language sql
volatile
security definer
set search_path = ''
as $function$
  with frozen as (
    insert into public.cup_excluded_matches (
      cup_id,
      round_id,
      match_id,
      cutoff_at
    )
    select
      p_cup_id,
      round_match.round_id,
      round_match.match_id,
      round_match.cutoff_at
    from public.players_cup_round_matches(p_cup_id) as round_match
    where round_match.match_id is not null
      -- Null cutoff means the Final, which never closes early.
      and round_match.cutoff_at is not null
      and round_match.is_excluded
      and not round_match.exclusion_is_frozen
    on conflict (cup_id, match_id) do nothing
    returning 1
  )
  select count(*)::integer from frozen;
$function$;

comment on function public.players_cup_freeze_exclusions(bigint)
is 'Persists every postponed-match exclusion the cutoff already implies right now, and returns how many were newly frozen. Insert only: a historical exclusion is never removed or rewritten, so calling it repeatedly is a no-op. Callers must already hold the Cup advisory lock. Phase 2B must call this BEFORE set_match_result touches the match, because a late result hides the evidence the decision was based on.';

-- ---------------------------------------------------------------------------
-- Round readiness
-- ---------------------------------------------------------------------------

-- public.matchdays.status is not maintained anywhere in this project, so
-- readiness is derived from the matches themselves, the same way the long-term
-- prediction lock already does it.
create or replace function public.players_cup_matchday_state(p_cup_id bigint)
returns table (
  round_number integer,
  round_id bigint,
  matchday_id bigint,
  cutoff_at timestamptz,
  configured_count integer,
  excluded_count integer,
  included_count integer,
  finished_included_count integer,
  unscored_prediction_count integer,
  is_complete boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  with round_match as (
    select * from public.players_cup_round_matches(p_cup_id)
  ),
  unscored as (
    select
      round_match.round_id,
      count(*)::integer as unscored_count
    from round_match
    join public.predictions as prediction
      on prediction.match_id = round_match.match_id
    where not round_match.is_excluded
      and prediction.points is null
    group by round_match.round_id
  ),
  aggregated as (
    select
      round_match.round_number,
      round_match.round_id,
      round_match.matchday_id,
      min(round_match.cutoff_at) as cutoff_at,
      count(round_match.match_id)::integer as configured_count,
      count(*) filter (
        where round_match.match_id is not null
          and round_match.is_excluded
      )::integer as excluded_count,
      count(*) filter (
        where round_match.match_id is not null
          and not round_match.is_excluded
      )::integer as included_count,
      count(*) filter (
        where round_match.match_id is not null
          and not round_match.is_excluded
          and round_match.match_status = 'finished'
      )::integer as finished_included_count
    from round_match
    group by
      round_match.round_number,
      round_match.round_id,
      round_match.matchday_id
  )
  select
    aggregated.round_number,
    aggregated.round_id,
    aggregated.matchday_id,
    aggregated.cutoff_at,
    aggregated.configured_count,
    aggregated.excluded_count,
    aggregated.included_count,
    aggregated.finished_included_count,
    coalesce(unscored.unscored_count, 0),
    (
      aggregated.configured_count > 0
      and aggregated.included_count > 0
      and aggregated.finished_included_count = aggregated.included_count
      and coalesce(unscored.unscored_count, 0) = 0
    )
  from aggregated
  left join unscored
    on unscored.round_id = aggregated.round_id;
$function$;

comment on function public.players_cup_matchday_state(bigint)
is 'Per Cup round readiness. A round may resolve once it has at least one included match, every included match is finished and every prediction on those matches is scored. Excluded postponed matches are ignored by all four counters.';

-- ---------------------------------------------------------------------------
-- Cup matchday aggregation
-- ---------------------------------------------------------------------------

-- Participant driven on purpose. A missing prediction is a missing row, a
-- disabled player simply stops producing rows, and a deleted profile leaves
-- user_id null, so all three must fall out of a LEFT JOIN as 0/0/0 instead of
-- disappearing from the result.
create or replace function public.players_cup_matchday_scores(
  p_cup_id bigint,
  p_matchday_id bigint
)
returns table (
  participant_id bigint,
  points integer,
  exact_count integer,
  correct_count integer
)
language sql
stable
security definer
set search_path = ''
as $function$
  with included_match as (
    select round_match.match_id
    from public.players_cup_round_matches(p_cup_id) as round_match
    where round_match.matchday_id = p_matchday_id
      and round_match.match_id is not null
      and not round_match.is_excluded
  ),
  round_prediction as (
    select
      prediction.user_id,
      prediction.points
    from public.predictions as prediction
    join included_match
      on included_match.match_id = prediction.match_id
  )
  select
    participant.id,
    coalesce(sum(round_prediction.points), 0)::integer,
    count(*) filter (
      where public.prediction_is_exact(round_prediction.points)
    )::integer,
    count(*) filter (
      where public.prediction_is_correct(round_prediction.points)
    )::integer
  from public.cup_participants as participant
  left join round_prediction
    on round_prediction.user_id = participant.user_id
  where participant.cup_id = p_cup_id
  group by participant.id;
$function$;

comment on function public.players_cup_matchday_scores(bigint, bigint)
is 'Cup points, exact scores and correct results for every participant in one Cup matchday. Golden Match doubling is already inside predictions.points, long-term awards and other matchdays are structurally excluded, and a participant without predictions scores 0/0/0.';

-- ---------------------------------------------------------------------------
-- Progression sources
-- ---------------------------------------------------------------------------

-- Who currently occupies each side of every tie in one round. Round 1 reads the
-- persisted draw, never the draw function, so a recompute can never reposition
-- a player. Later rounds read the previous round's winners: the odd slot feeds
-- the home side and the even slot the away side.
create or replace function public.players_cup_round_entrants(
  p_cup_id bigint,
  p_round_number integer
)
returns table (
  slot integer,
  home_participant_id bigint,
  away_participant_id bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    pairing.slot,
    home_participant.id,
    away_participant.id
  from (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1)
        as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0)
        as away_bracket_position
    from public.players_cup_bracket_slots(64) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ) as pairing
  left join public.cup_participants as home_participant
    on home_participant.cup_id = p_cup_id
    and home_participant.bracket_position = pairing.home_bracket_position
  left join public.cup_participants as away_participant
    on away_participant.cup_id = p_cup_id
    and away_participant.bracket_position = pairing.away_bracket_position
  where p_round_number = 1
  union all
  select
    ((previous_tie.slot + 1) / 2)::integer,
    max(previous_tie.winner_participant_id)
      filter (where previous_tie.slot % 2 = 1),
    max(previous_tie.winner_participant_id)
      filter (where previous_tie.slot % 2 = 0)
  from public.cup_ties as previous_tie
  join public.cup_rounds as previous_round
    on previous_round.id = previous_tie.round_id
  where p_round_number > 1
    and previous_round.cup_id = p_cup_id
    and previous_round.round_number = p_round_number - 1
  group by ((previous_tie.slot + 1) / 2);
$function$;

comment on function public.players_cup_round_entrants(bigint, integer)
is 'Current occupants of every tie in one Cup round. Round 1 comes from the persisted bracket positions; round r takes the winner of round r-1 slot 2k-1 as home and slot 2k as away.';

-- ---------------------------------------------------------------------------
-- Tie classification and tie-break
-- ---------------------------------------------------------------------------

-- Kept as its own function because the difference between a bye and a tie that
-- is merely waiting is the single most dangerous thing to get wrong: a bye
-- advances a player who has not won anything.
create or replace function public.players_cup_tie_outcome(
  p_home_capacity integer,
  p_away_capacity integer,
  p_home_participant_id bigint,
  p_away_participant_id bigint,
  p_round_is_complete boolean
)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    -- Nobody can ever arrive on either side.
    when p_home_capacity = 0 and p_away_capacity = 0 then 'empty'
    -- Structural bye: the far side is incapable of producing a player.
    when p_away_capacity = 0 and p_home_participant_id is not null then 'bye'
    when p_home_capacity = 0 and p_away_participant_id is not null then 'bye'
    -- Waiting. The far side can still produce a player, so a single known
    -- participant must not advance.
    when p_home_participant_id is null or p_away_participant_id is null
      then 'pending'
    when not p_round_is_complete then 'pending'
    else 'decided'
  end;
$function$;

comment on function public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
is 'Classifies one Cup tie as empty, bye, pending or decided. A bye requires the far side to be structurally empty; one known participant against an unresolved feeder is always pending.';

-- Cup points, then exact scores, then correct results, then the better frozen
-- ranking. The chain always terminates because cup_participants.rank_position
-- is unique inside a Cup, so the last comparison can never be a draw.
create or replace function public.players_cup_tie_break(
  p_home_points integer,
  p_away_points integer,
  p_home_exact integer,
  p_away_exact integer,
  p_home_correct integer,
  p_away_correct integer,
  p_home_rank_position integer,
  p_away_rank_position integer
)
returns table (
  decided_by_rule text,
  home_wins boolean
)
language sql
immutable
set search_path = ''
as $function$
  select
    case
      when p_home_points <> p_away_points then 'points'
      when p_home_exact <> p_away_exact then 'exact'
      when p_home_correct <> p_away_correct then 'correct'
      else 'rank_position'
    end,
    case
      when p_home_points <> p_away_points
        then p_home_points > p_away_points
      when p_home_exact <> p_away_exact
        then p_home_exact > p_away_exact
      when p_home_correct <> p_away_correct
        then p_home_correct > p_away_correct
      -- A lower rank position is the better ranking.
      else p_home_rank_position < p_away_rank_position
    end;
$function$;

comment on function public.players_cup_tie_break(integer, integer, integer, integer, integer, integer, integer, integer)
is 'Resolves a contested Cup tie: Cup points, then exact scores, then correct results, then the lower rank_position. Returns the rule that decided it and whether the home participant won.';

-- ---------------------------------------------------------------------------
-- The recompute engine
-- ---------------------------------------------------------------------------

-- Owns every piece of derived Cup state: tie participants, tie statistics,
-- winners, round statuses, awards and the competition status. Nothing else in
-- the database may write those columns.
--
-- It is a FULL recompute, never an incremental "advance this winner". A
-- corrected football result changes prediction points outside this function,
-- and the next run rebuilds the whole bracket from the frozen Phase 1 entry
-- list, so a changed Round 1 winner cannot leave a stale opponent, score,
-- winner or award anywhere downstream.
--
-- LOCKING: the caller must already hold pg_advisory_xact_lock(
-- public.players_cup_lock_key()). This function only adds the competition row
-- lock, so the advisory lock is always acquired before any match row lock.
create or replace function public.players_cup_apply(p_cup_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_slug text;
  v_participant_count integer;
  v_winner_points integer;
  v_finalist_points integer;
  v_semi_finalist_points integer;
  v_round record;
  v_round_number integer;
  v_round_status text;
  v_final_outcome text;
  v_final_winner_id bigint;
  v_final_home_id bigint;
  v_final_away_id bigint;
  v_status text;
  v_summary jsonb;
begin
  select
    competition.slug,
    competition.participant_count,
    competition.winner_points,
    competition.finalist_points,
    competition.semi_finalist_points
  into
    v_slug,
    v_participant_count,
    v_winner_points,
    v_finalist_points,
    v_semi_finalist_points
  from public.cup_competitions as competition
  where competition.id = p_cup_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Players Cup not found';
  end if;

  -- Freeze today's exclusion decisions before any round state or score is read,
  -- so a result entered for a postponed match later can never reopen the round.
  -- Phase 2B will additionally call this helper before it touches the match, but
  -- the recompute repeats it so the admin recovery RPC remains correct on its
  -- own.
  perform public.players_cup_freeze_exclusions(p_cup_id);

  -- One statement, the whole Cup. The assert_cup_round_participants trigger is
  -- an AFTER STATEMENT check over the bracket, so clearing everything first
  -- guarantees no intermediate statement can see a participant twice in one
  -- round while the rounds are rebuilt one by one below.
  update public.cup_ties as tie
  set
    home_participant_id = null,
    away_participant_id = null,
    home_points = 0,
    away_points = 0,
    home_exact = 0,
    away_exact = 0,
    home_correct = 0,
    away_correct = 0,
    winner_participant_id = null,
    outcome = 'empty',
    decided_by_rule = null,
    updated_at = now()
  where tie.cup_id = p_cup_id
    and (
      tie.outcome <> 'empty'
      or tie.home_participant_id is not null
      or tie.away_participant_id is not null
      or tie.winner_participant_id is not null
      or tie.decided_by_rule is not null
      or tie.home_points <> 0
      or tie.away_points <> 0
      or tie.home_exact <> 0
      or tie.away_exact <> 0
      or tie.home_correct <> 0
      or tie.away_correct <> 0
    );

  -- Every round, every time. Byes need no football, so progression must not
  -- stop at the first incomplete matchday: it stops per feeder instead.
  for v_round in
    select
      state.round_number,
      state.round_id,
      state.matchday_id,
      state.is_complete
    from public.players_cup_matchday_state(p_cup_id) as state
    order by state.round_number
  loop
    v_round_number := v_round.round_number;

    with entrant as (
      select
        round_entrant.slot,
        round_entrant.home_participant_id,
        round_entrant.away_participant_id
      from public.players_cup_round_entrants(p_cup_id, v_round_number)
        as round_entrant
    ),
    resolved as (
      select
        entrant.slot,
        entrant.home_participant_id,
        entrant.away_participant_id,
        layout.home_capacity,
        layout.away_capacity,
        home_participant.rank_position as home_rank_position,
        away_participant.rank_position as away_rank_position,
        -- Statistics belong to a contested tie only. A bye is not played, and a
        -- half filled tie would otherwise display a fictional 18-0.
        (entrant.home_participant_id is not null
          and entrant.away_participant_id is not null) as is_contested,
        coalesce(home_score.points, 0) as home_points,
        coalesce(away_score.points, 0) as away_points,
        coalesce(home_score.exact_count, 0) as home_exact,
        coalesce(away_score.exact_count, 0) as away_exact,
        coalesce(home_score.correct_count, 0) as home_correct,
        coalesce(away_score.correct_count, 0) as away_correct
      from entrant
      join public.players_cup_tie_layout(v_participant_count) as layout
        on layout.round_number = v_round_number
        and layout.slot = entrant.slot
      left join public.cup_participants as home_participant
        on home_participant.id = entrant.home_participant_id
      left join public.cup_participants as away_participant
        on away_participant.id = entrant.away_participant_id
      left join public.players_cup_matchday_scores(
        p_cup_id,
        v_round.matchday_id
      ) as home_score
        on home_score.participant_id = entrant.home_participant_id
      left join public.players_cup_matchday_scores(
        p_cup_id,
        v_round.matchday_id
      ) as away_score
        on away_score.participant_id = entrant.away_participant_id
    ),
    classified as (
      select
        resolved.slot,
        resolved.home_participant_id,
        resolved.away_participant_id,
        case when resolved.is_contested then resolved.home_points else 0 end
          as home_points,
        case when resolved.is_contested then resolved.away_points else 0 end
          as away_points,
        case when resolved.is_contested then resolved.home_exact else 0 end
          as home_exact,
        case when resolved.is_contested then resolved.away_exact else 0 end
          as away_exact,
        case when resolved.is_contested then resolved.home_correct else 0 end
          as home_correct,
        case when resolved.is_contested then resolved.away_correct else 0 end
          as away_correct,
        public.players_cup_tie_outcome(
          resolved.home_capacity,
          resolved.away_capacity,
          resolved.home_participant_id,
          resolved.away_participant_id,
          v_round.is_complete
        ) as outcome,
        tie_break.decided_by_rule,
        tie_break.home_wins
      from resolved
      cross join lateral public.players_cup_tie_break(
        resolved.home_points,
        resolved.away_points,
        resolved.home_exact,
        resolved.away_exact,
        resolved.home_correct,
        resolved.away_correct,
        resolved.home_rank_position,
        resolved.away_rank_position
      ) as tie_break
    )
    update public.cup_ties as tie
    set
      home_participant_id = classified.home_participant_id,
      away_participant_id = classified.away_participant_id,
      home_points = classified.home_points,
      away_points = classified.away_points,
      home_exact = classified.home_exact,
      away_exact = classified.away_exact,
      home_correct = classified.home_correct,
      away_correct = classified.away_correct,
      winner_participant_id = case classified.outcome
        when 'bye' then coalesce(
          classified.home_participant_id,
          classified.away_participant_id
        )
        when 'decided' then case
          when classified.home_wins then classified.home_participant_id
          else classified.away_participant_id
        end
      end,
      outcome = classified.outcome,
      decided_by_rule = case
        when classified.outcome = 'decided' then classified.decided_by_rule
      end,
      updated_at = now()
    from classified
    where tie.round_id = v_round.round_id
      and tie.slot = classified.slot
      -- The clear above already emptied every tie, so only a tie that ends up
      -- holding real state has to be written again.
      and classified.outcome <> 'empty';

    -- Derived from the rebuilt ties, never from matchday completion. A field of
    -- eight players makes rounds 1 to 3 structurally final before a single Cup
    -- match has been played, and that is the truth to show.
    select case
      when count(*) filter (
        where tie.home_participant_id is not null
          or tie.away_participant_id is not null
      ) = 0 then 'pending'
      when count(*) filter (where tie.outcome = 'pending') > 0
        then 'in_progress'
      else 'final'
    end
    into v_round_status
    from public.cup_ties as tie
    where tie.round_id = v_round.round_id;

    update public.cup_rounds as round
    set
      status = v_round_status,
      updated_at = now()
    where round.id = v_round.round_id
      and round.status is distinct from v_round_status;
  end loop;

  select
    tie.outcome,
    tie.winner_participant_id,
    tie.home_participant_id,
    tie.away_participant_id
  into
    v_final_outcome,
    v_final_winner_id,
    v_final_home_id,
    v_final_away_id
  from public.cup_ties as tie
  join public.cup_rounds as round
    on round.id = tie.round_id
  where round.cup_id = p_cup_id
    and round.round_number = 6
    and tie.slot = 1;

  -- Awards are derived state, so the rebuild has to be able to take an award
  -- away again. Reward values come from the competition row, never from a
  -- constant, so 30/20/10 can become 100/60/20 without touching this function.
  with qualifying as (
    select
      v_final_winner_id as participant_id,
      'winner'::text as award_type,
      v_winner_points as points
    where v_final_outcome = 'decided'
    union all
    select
      case
        when v_final_home_id = v_final_winner_id then v_final_away_id
        else v_final_home_id
      end,
      'finalist',
      v_finalist_points
    where v_final_outcome = 'decided'
    union all
    select
      case
        when tie.home_participant_id = tie.winner_participant_id
          then tie.away_participant_id
        else tie.home_participant_id
      end,
      'semi_finalist',
      v_semi_finalist_points
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where v_final_outcome = 'decided'
      and round.cup_id = p_cup_id
      and round.round_number = 5
      and tie.outcome = 'decided'
  ),
  removed as (
    delete from public.cup_awards as award
    where award.cup_id = p_cup_id
      and not exists (
        select 1
        from qualifying
        where qualifying.participant_id = award.participant_id
      )
    returning award.id
  )
  insert into public.cup_awards (
    cup_id,
    participant_id,
    user_id,
    award_type,
    points
  )
  select
    p_cup_id,
    qualifying.participant_id,
    participant.user_id,
    qualifying.award_type,
    qualifying.points
  from qualifying
  join public.cup_participants as participant
    on participant.id = qualifying.participant_id
  on conflict (cup_id, participant_id) do update
  set
    user_id = excluded.user_id,
    award_type = excluded.award_type,
    points = excluded.points,
    updated_at = now()
  where cup_awards.user_id is distinct from excluded.user_id
    or cup_awards.award_type is distinct from excluded.award_type
    or cup_awards.points is distinct from excluded.points;

  v_status := case
    when v_final_outcome = 'decided' then 'completed'
    else 'active'
  end;

  -- A correction that reopens the Final has to reopen the competition too.
  update public.cup_competitions as competition
  set
    status = v_status,
    updated_at = now()
  where competition.id = p_cup_id
    and competition.status is distinct from v_status;

  select jsonb_build_object(
    'cup_id', p_cup_id,
    'slug', v_slug,
    'status', v_status,
    'participant_count', v_participant_count,
    'rounds_pending', count(*) filter (where round.status = 'pending'),
    'rounds_in_progress', count(*) filter (where round.status = 'in_progress'),
    'rounds_final', count(*) filter (where round.status = 'final')
  )
  into v_summary
  from public.cup_rounds as round
  where round.cup_id = p_cup_id;

  select v_summary || jsonb_build_object(
    'ties_decided', count(*) filter (where tie.outcome = 'decided'),
    'ties_pending', count(*) filter (where tie.outcome = 'pending'),
    'ties_bye', count(*) filter (where tie.outcome = 'bye'),
    'ties_empty', count(*) filter (where tie.outcome = 'empty')
  )
  into v_summary
  from public.cup_ties as tie
  where tie.cup_id = p_cup_id;

  select v_summary || jsonb_build_object(
    'awards_count', (
      select count(*)
      from public.cup_awards as award
      where award.cup_id = p_cup_id
    ),
    'excluded_postponed_match_count', (
      select count(*)
      from public.cup_excluded_matches as excluded_match
      where excluded_match.cup_id = p_cup_id
    ),
    'champion_participant_id', case
      when v_final_outcome = 'decided' then v_final_winner_id
    end,
    'rounds', (
      select jsonb_agg(
        jsonb_build_object(
          'round_number', state.round_number,
          'matchday_number', state.round_number + 2,
          'status', round.status,
          'is_complete', state.is_complete,
          'cutoff_at', state.cutoff_at,
          'configured_matches', state.configured_count,
          'included_matches', state.included_count,
          'excluded_matches', state.excluded_count,
          'finished_included_matches', state.finished_included_count,
          'unscored_predictions', state.unscored_prediction_count
        )
        order by state.round_number
      )
      from public.players_cup_matchday_state(p_cup_id) as state
      join public.cup_rounds as round
        on round.id = state.round_id
    ),
    'recomputed_at', now()
  )
  into v_summary;

  return v_summary;
end;
$function$;

comment on function public.players_cup_apply(bigint)
is 'Full deterministic recompute of every derived Players Cup value: tie participants, statistics, winners, round statuses, awards and competition status. Idempotent and correction safe. The caller must already hold the players_cup_lock_key advisory lock.';

-- ---------------------------------------------------------------------------
-- Admin recovery RPC
-- ---------------------------------------------------------------------------

-- Recovery tooling, not an "advance round" button: it only recalculates the
-- current truth and is safe to press at any time, including before the draw.
create or replace function public.recompute_players_cup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Taken before any row lock. Phase 2B must use the same order inside
  -- set_match_result, otherwise two admins scoring two matches can deadlock.
  perform pg_advisory_xact_lock(public.players_cup_lock_key());

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug;

  -- No draw yet is a normal state, not an error.
  if v_cup_id is null then
    return jsonb_build_object(
      'cup_exists', false,
      'slug', c_slug,
      'recomputed_at', now()
    );
  end if;

  return public.players_cup_apply(v_cup_id)
    || jsonb_build_object('cup_exists', true);
end;
$function$;

comment on function public.recompute_players_cup()
is 'Admin-only Players Cup recalculation. Recomputes every derived value from the current football results and is safe to call repeatedly. Returns a summary instead of raising when no Cup has been drawn yet.';

-- ---------------------------------------------------------------------------
-- Cup matchday membership immutability
-- ---------------------------------------------------------------------------

-- Cup rounds are permanently mapped to Matchdays 3 to 8, so moving a match
-- between matchdays would silently move its prediction points from one Cup
-- round to another. Kickoff time, status and result stay freely editable: the
-- trigger only fires when matchday_id is in the UPDATE target list.
create or replace function public.assert_cup_matchday_membership()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.matchday_id is not distinct from old.matchday_id then
    return new;
  end if;

  if not exists (select 1 from public.cup_competitions) then
    return new;
  end if;

  if exists (
    select 1
    from public.matchdays as matchday
    where matchday.id in (old.matchday_id, new.matchday_id)
      and matchday.stage = 'league_phase'
      and matchday.matchday_number between 3 and 8
  ) then
    raise exception using
      errcode = '22023',
      message = 'A Players Cup matchday match cannot be moved to another matchday';
  end if;

  return new;
end;
$function$;

comment on function public.assert_cup_matchday_membership()
is 'Rejects moving a match into or out of League Phase Matchdays 3 to 8 once a Players Cup exists, because those matchdays are permanently mapped to Cup rounds.';

create trigger matches_cup_matchday_membership
before update of matchday_id
on public.matches
for each row
execute function public.assert_cup_matchday_membership();

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------

alter table public.cup_awards enable row level security;
alter table public.cup_excluded_matches enable row level security;

-- Read-only for players, exactly like the Phase 1 Cup tables. No insert, update
-- or delete policy exists, so the Data API rejects every browser write before
-- column grants are considered.
create policy "Authenticated users can view Cup awards"
  on public.cup_awards
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view excluded Cup matches"
  on public.cup_excluded_matches
  for select
  to authenticated
  using (true);

revoke all privileges on table public.cup_awards
  from public, anon, authenticated;
revoke all privileges on table public.cup_excluded_matches
  from public, anon, authenticated;

grant select on table public.cup_awards to authenticated;
grant select on table public.cup_excluded_matches to authenticated;

grant all privileges on table public.cup_awards to service_role;
grant all privileges on table public.cup_excluded_matches to service_role;

revoke all privileges on sequence public.cup_awards_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_excluded_matches_id_seq
  from public, anon, authenticated;

grant all privileges on sequence public.cup_awards_id_seq to service_role;
grant all privileges on sequence public.cup_excluded_matches_id_seq
  to service_role;

-- The browser may invoke the recovery RPC, but the function rejects every
-- caller who is not an active administrator.
revoke execute on function public.recompute_players_cup()
  from public, anon;
grant execute on function public.recompute_players_cup()
  to authenticated, service_role;

-- Internal helpers. players_cup_matchday_scores aggregates every player's
-- predictions and players_cup_apply writes the bracket, so neither may be
-- reachable from the browser. The classifiers stay internal too: nothing in the
-- client needs them, and exposing them would widen the surface for no gain.
revoke execute on function public.prediction_is_exact(integer)
  from public, anon, authenticated;
grant execute on function public.prediction_is_exact(integer)
  to service_role;

revoke execute on function public.prediction_is_correct(integer)
  from public, anon, authenticated;
grant execute on function public.prediction_is_correct(integer)
  to service_role;

revoke execute on function public.players_cup_lock_key()
  from public, anon, authenticated;
grant execute on function public.players_cup_lock_key()
  to service_role;

revoke execute on function public.players_cup_tie_layout(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_tie_layout(integer)
  to service_role;

revoke execute on function public.players_cup_round_matches(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_round_matches(bigint)
  to service_role;

revoke execute on function public.players_cup_freeze_exclusions(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_freeze_exclusions(bigint)
  to service_role;

revoke execute on function public.players_cup_matchday_state(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_matchday_state(bigint)
  to service_role;

revoke execute on function public.players_cup_matchday_scores(bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_matchday_scores(bigint, bigint)
  to service_role;

revoke execute on function public.players_cup_round_entrants(bigint, integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_round_entrants(bigint, integer)
  to service_role;

revoke execute on function
  public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
  from public, anon, authenticated;
grant execute on function
  public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
  to service_role;

revoke execute on function public.players_cup_tie_break(
  integer, integer, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.players_cup_tie_break(
  integer, integer, integer, integer, integer, integer, integer, integer
) to service_role;

revoke execute on function public.players_cup_apply(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_apply(bigint)
  to service_role;

revoke execute on function public.assert_cup_matchday_membership()
  from public, anon, authenticated;


-- =====================================================================
-- SOURCE: supabase/migrations/20260820110500_players_cup_phase_2b.sql
-- =====================================================================

-- Players Cup phase 2B: production integration.
--
-- Two changes, both to functions that already exist:
--
--   set_match_result  now keeps the Cup in step with football results, in the
--                     same transaction, so a result entry or a correction never
--                     leaves the bracket stale.
--   get_leaderboard   now adds Cup honours to total_points, exactly like the
--                     long-term awards term next to it.
--
-- Phase 1 and phase 2A are untouched. Nothing here changes how a prediction is
-- scored, and no new write path is exposed.

-- ---------------------------------------------------------------------------
-- Prediction classifiers, centralised
-- ---------------------------------------------------------------------------

-- Phase 2A introduced prediction_is_exact/prediction_is_correct so the 5/10 and
-- 2/4 mapping lives in exactly one place. The two remaining copies of that
-- mapping are the two aggregate readers below, and both are replaced here.
-- Semantics are identical: NULL points fall out of both filters either way,
-- because "null in (5, 10)" is null and the classifiers coalesce null to false.
-- Both callers are security definer and run as the owner, so the classifiers
-- stay revoked from every browser role.

create or replace function public.players_cup_ranking()
returns table (
  rank_position integer,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with ranking_matches as (
    select match_row.id, match_row.status
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
  ),
  ranking_predictions as (
    select
      prediction.id,
      prediction.user_id,
      prediction.points,
      ranking_matches.status as match_status
    from public.predictions as prediction
    join ranking_matches
      on ranking_matches.id = prediction.match_id
  ),
  finished_ranking_matches as (
    select count(*)::bigint as finished_count
    from ranking_matches
    where ranking_matches.status = 'finished'
  ),
  player_stats as (
    select
      profile.id as user_id,
      profile.username,
      coalesce(sum(prediction.points), 0)::bigint as total_points,
      count(prediction.id)
        filter (where public.prediction_is_exact(prediction.points))::bigint
        as exact_scores,
      count(prediction.id)
        filter (where public.prediction_is_correct(prediction.points))::bigint
        as correct_results,
      (
        (select finished_count from finished_ranking_matches)
        - count(prediction.id)
          filter (where prediction.match_status = 'finished')
      )::bigint as missed_predictions
    from public.profiles as profile
    left join ranking_predictions as prediction
      on prediction.user_id = profile.id
    where profile.status = 'active'
    group by profile.id, profile.username
  )
  select
    row_number() over (
      order by
        player_stats.total_points desc,
        player_stats.exact_scores desc,
        player_stats.correct_results desc,
        player_stats.missed_predictions asc,
        lower(player_stats.username) asc,
        player_stats.user_id asc
    )::integer as rank_position,
    player_stats.user_id,
    player_stats.username,
    player_stats.total_points,
    player_stats.exact_scores,
    player_stats.correct_results,
    player_stats.missed_predictions
  from player_stats
  order by rank_position;
$function$;

comment on function public.players_cup_ranking()
is 'Strict Players Cup ranking from League Phase Matchday 1 and 2 only. Never includes long-term awards or Matchday 3+ results. Position 1 is the best ranking.';

-- ---------------------------------------------------------------------------
-- Leaderboard: Cup honours count towards the overall total
-- ---------------------------------------------------------------------------

-- Only total_points changes. Cup matchday performance is already inside
-- predictions.points and must NOT be counted a second time, so the single new
-- term reads public.cup_awards and nothing else: a champion gains exactly
-- winner_points on top of the prediction points already earned during
-- Matchdays 3 to 8.
--
-- A deleted profile empties cup_awards.user_id, so the award simply matches no
-- leaderboard row, and a non-active profile is still excluded by the existing
-- profile.status filter. Neither case needs special handling.
create or replace function public.get_leaderboard()
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      profile.id as user_id,
      profile.username,
      (
        coalesce(sum(prediction.points), 0)
        + coalesce((
          select sum(award.points)
          from public.long_term_awards as award
          where award.user_id = profile.id
        ), 0)
        + coalesce((
          select sum(cup_award.points)
          from public.cup_awards as cup_award
          where cup_award.user_id = profile.id
        ), 0)
      )::bigint as total_points,
      count(prediction.id)
        filter (where public.prediction_is_exact(prediction.points))::bigint
        as exact_scores,
      count(prediction.id)
        filter (where public.prediction_is_correct(prediction.points))::bigint
        as correct_results,
      coalesce(
        sum(prediction.points)
          filter (where matchday.stage <> 'league_phase'),
        0
      )::bigint as knockout_points,
      (
        select count(*)
        from public.matches as finished_match
        where finished_match.status = 'finished'
      )
      - count(prediction.id)
        filter (where match_row.status = 'finished')::bigint
        as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
    group by profile.id, profile.username
  ),
  ranked_players as (
    select
      rank() over (
        order by
          total_points desc,
          exact_scores desc,
          correct_results desc,
          knockout_points desc,
          missed_predictions asc
      ) as rank_position,
      user_id,
      username,
      total_points,
      exact_scores,
      correct_results,
      knockout_points,
      missed_predictions
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

comment on function public.get_leaderboard()
is 'Overall standings. total_points is prediction points plus long-term awards plus Players Cup honours; Cup matchday performance is already inside the prediction points and is never added twice.';

-- ---------------------------------------------------------------------------
-- Result entry keeps the Cup in step
-- ---------------------------------------------------------------------------

-- Signature, return shape, admin gate, validation, Golden Match scoring and
-- prediction rescoring are all unchanged. The only addition is that a result
-- belonging to a Cup round now recomputes the Cup in the same transaction.
--
-- LOCK ORDER - this sequence is mandatory and must never be reversed:
--
--   1. work out whether the match belongs to a Cup round (no lock taken)
--   2. pg_advisory_xact_lock(public.players_cup_lock_key())
--   3. public.players_cup_freeze_exclusions(cup_id)
--   4. select ... from public.matches ... for update
--   5. update the match, rescore its predictions
--   6. public.players_cup_apply(cup_id)
--
-- Step 2 before step 4 is what keeps two admins scoring two different Cup
-- matches from deadlocking: every Cup-aware path takes the one advisory lock
-- before it touches any match row, so the two transactions serialise instead of
-- waiting on each other in opposite orders.
--
-- Step 3 before step 4 is what makes a late postponed result safe. Once the
-- next matchday has started, an unfinished match is out of its Cup round for
-- good, but the moment this function marks it 'finished' that fact is no longer
-- visible in the match row. Freezing first records the decision while the
-- evidence still exists.
--
-- Cup errors are deliberately not caught. If the recompute fails, the result
-- entry and the rescored predictions roll back with it, because a committed
-- football result with a stale bracket is the one state the Cup must never
-- reach.
create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
  v_cup_ids bigint[];
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  -- Cup relevance comes from the round mapping itself, never from a hardcoded
  -- matchday range, so a match outside Matchdays 3 to 8 - and every match at
  -- all while no Cup exists - skips the Cup work entirely.
  --
  -- Reading matchday_id without a row lock is safe: once a Cup exists the phase
  -- 2A trigger rejects any attempt to move a Cup match to another matchday, so
  -- the value cannot change underneath this transaction.
  select array_agg(distinct round.cup_id)
  into v_cup_ids
  from public.matches as match_row
  join public.cup_rounds as round
    on round.matchday_id = match_row.matchday_id
  where match_row.id = p_match_id;

  if v_cup_ids is not null then
    -- Step 2. One key for the whole competition, always taken before any match
    -- row lock.
    perform pg_advisory_xact_lock(public.players_cup_lock_key());

    -- Step 3. Still before the match changes.
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_freeze_exclusions(v_cup_id);
    end loop;
  end if;

  -- Step 4. The match row lock.
  select match_row.home_score, match_row.away_score, match_row.status
  into v_current_home_score, v_current_away_score, v_current_status
  from public.matches as match_row
  where match_row.id = p_match_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as match_row
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where match_row.id = p_match_id;
  end if;

  with calculated_points as (
    select
      prediction.id,
      case
        when prediction.predicted_home_score = p_home_score
          and prediction.predicted_away_score = p_away_score
          then case when selection.id is null then 5 else 10 end
        when (
          prediction.predicted_home_score > prediction.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          prediction.predicted_home_score = prediction.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          prediction.predicted_home_score < prediction.predicted_away_score
          and p_home_score < p_away_score
        )
          then case when selection.id is null then 2 else 4 end
        else 0
      end as new_points
    from public.predictions as prediction
    left join public.golden_match_selections as selection
      on selection.user_id = prediction.user_id
      and selection.match_id = prediction.match_id
    where prediction.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as prediction
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where prediction.id = calculated_points.id
      and prediction.points is distinct from calculated_points.new_points
    returning prediction.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  -- Step 6. A full recompute, so a correction rebuilds the whole bracket and
  -- the honours list rather than patching one tie.
  if v_cup_ids is not null then
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_apply(v_cup_id);
    end loop;
  end if;

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry with deterministic idempotent scoring: normal 5/2/0 and selected Golden Match 10/4/0. A result belonging to a Players Cup round also freezes any crossed postponed-match cutoff and recomputes the Cup in the same transaction.';

-- Unchanged access: create or replace keeps the existing privileges, and these
-- are restated so the migration is self-describing.
revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;

revoke execute on function public.get_leaderboard()
  from public, anon;
grant execute on function public.get_leaderboard()
  to authenticated;

revoke execute on function public.players_cup_ranking()
  from public, anon, authenticated;
grant execute on function public.players_cup_ranking()
  to service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260820183000_players_cup_reward_values.sql
-- =====================================================================

-- Players Cup published awards: 50 / 30 / 15.
-- Additive only. Does not rewrite historical Phase 1 / 2A / 2B migrations.
-- Rebases create_players_cup on the current hosted function body. The only
-- intentional behavioural change is the published reward constants.
-- Existing competition rows are not updated; hosted currently has none.

alter table public.cup_competitions
  alter column winner_points set default 50,
  alter column finalist_points set default 30,
  alter column semi_finalist_points set default 15;

create or replace function public.create_players_cup(
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  c_season_label constant text := 'Champions League 2026/27';
  c_bracket_size constant integer := 64;
  c_minimum_participants constant integer := 8;
  c_protected_seed_count constant integer := 8;
  -- Initial reward configuration. Once the row exists it is the only source of
  -- truth; award calculation must never read these constants.
  c_winner_points constant integer := 50;
  c_finalist_points constant integer := 30;
  c_semi_finalist_points constant integer := 15;

  v_admin_id uuid := (select auth.uid());
  v_cup_id bigint;
  v_summary jsonb;
  v_ranking jsonb;
  v_participants jsonb;
  -- One draw seed per call. A dry run returns it as a preview seed and throws
  -- it away; a real creation persists it alongside the bracket it produced.
  v_draw_seed uuid := gen_random_uuid();
  v_draw jsonb;
  v_preview jsonb;
  v_eligible_count integer;
  v_participant_count integer;
  v_matchday_count integer;
  v_ranking_match_count integer;
  v_ranking_finished_count integer;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Serializes concurrent creation attempts. The lock is released at commit or
  -- rollback, so two simultaneous callers converge on one competition instead
  -- of racing on the unique slug.
  perform pg_advisory_xact_lock(
    hashtext('public.create_players_cup:' || c_slug)::bigint
  );

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug
  for update;

  -- The Cup is never regenerated. An existing bracket is reported back
  -- untouched, for a dry run and for a normal call alike.
  if v_cup_id is not null then
    select jsonb_build_object(
      'already_exists', true,
      'created', false,
      'dry_run', p_dry_run,
      'cup_id', competition.id,
      'slug', competition.slug,
      'season_label', competition.season_label,
      'status', competition.status,
      'bracket_size', competition.bracket_size,
      'protected_seed_count', c_protected_seed_count,
      'participant_count', competition.participant_count,
      'draw_seed', competition.draw_seed,
      'draw_is_preview', false,
      'created_at', competition.created_at,
      'rewards', jsonb_build_object(
        'winner_points', competition.winner_points,
        'finalist_points', competition.finalist_points,
        'semi_finalist_points', competition.semi_finalist_points
      ),
      'round_count', (
        select count(*)
        from public.cup_rounds as round
        where round.cup_id = competition.id
      ),
      'tie_count', (
        select count(*)
        from public.cup_ties as tie
        where tie.cup_id = competition.id
      )
    )
    into v_summary
    from public.cup_competitions as competition
    where competition.id = v_cup_id;

    return v_summary;
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  if v_matchday_count <> 6 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 3 to 8 must all exist before the Players Cup can be created';
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_matchday_count <> 2 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 are required for a deterministic ranking';
  end if;

  -- Freezes the ranking inputs for the rest of the transaction, so a result
  -- correction cannot land between the preview and the written bracket.
  perform 1
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2
  order by match_row.id
  for share of match_row;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into v_ranking_match_count, v_ranking_finished_count
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_ranking_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 have no configured matches';
  end if;

  if v_ranking_finished_count <> v_ranking_match_count then
    raise exception using
      errcode = '22023',
      message = 'The Cup ranking requires every League Phase Matchday 1 and 2 match to be finished';
  end if;

  if exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
      and prediction.points is null
  ) then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchday 1 and 2 predictions are not fully scored';
  end if;

  -- Single evaluation of the ranking. Everything below reads this snapshot, so
  -- a registration committed mid-call cannot change the written bracket.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank_position', ranking.rank_position,
          'user_id', ranking.user_id,
          'username', ranking.username,
          'total_points', ranking.total_points,
          'exact_scores', ranking.exact_scores,
          'correct_results', ranking.correct_results,
          'missed_predictions', ranking.missed_predictions
        )
        order by ranking.rank_position
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_ranking, v_eligible_count
  from public.players_cup_ranking() as ranking;

  if v_eligible_count < c_minimum_participants then
    raise exception using
      errcode = '22023',
      message = format(
        'The Players Cup needs at least %s active players, found %s',
        c_minimum_participants,
        v_eligible_count
      );
  end if;

  v_participant_count := least(v_eligible_count, c_bracket_size);

  select coalesce(
    jsonb_agg(ranked.entry order by (ranked.entry->>'rank_position')::integer),
    '[]'::jsonb
  )
  into v_participants
  from jsonb_array_elements(v_ranking) as ranked(entry)
  where (ranked.entry->>'rank_position')::integer <= v_participant_count;

  -- Drawn once. The preview and the persisted bracket are built from this one
  -- result, so what an admin sees is exactly what gets written.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank_position', placement.rank_position,
        'user_id', placement.user_id,
        'bracket_position', placement.bracket_position,
        'entry_round', placement.entry_round,
        'is_protected_seed', placement.is_protected_seed
      )
      order by placement.rank_position
    ),
    '[]'::jsonb
  )
  into v_draw
  from public.players_cup_draw(v_draw_seed, v_participants) as placement;

  v_preview := jsonb_build_object(
    'already_exists', false,
    'dry_run', p_dry_run,
    'slug', c_slug,
    'season_label', c_season_label,
    'status', 'active',
    'bracket_size', c_bracket_size,
    'protected_seed_count', c_protected_seed_count,
    'minimum_participants', c_minimum_participants,
    'eligible_count', v_eligible_count,
    'participant_count', v_participant_count,
    'excluded_count', v_eligible_count - v_participant_count,
    'draw_seed', v_draw_seed,
    -- A dry run seed is thrown away: two previews before creation may differ,
    -- and only the seed stored by the real creation describes the real bracket.
    'draw_is_preview', p_dry_run,
    'rewards', jsonb_build_object(
      'winner_points', c_winner_points,
      'finalist_points', c_finalist_points,
      'semi_finalist_points', c_semi_finalist_points
    ),
    'participants', v_draw
  );

  if p_dry_run then
    return v_preview || jsonb_build_object(
      'created', false,
      'cup_id', null::bigint
    );
  end if;

  insert into public.cup_competitions (
    slug,
    season_label,
    bracket_size,
    participant_count,
    status,
    draw_seed,
    winner_points,
    finalist_points,
    semi_finalist_points,
    created_by
  )
  values (
    c_slug,
    c_season_label,
    c_bracket_size,
    v_participant_count,
    'active',
    v_draw_seed,
    c_winner_points,
    c_finalist_points,
    c_semi_finalist_points,
    v_admin_id
  )
  returning cup_competitions.id into v_cup_id;

  insert into public.cup_participants (
    cup_id,
    user_id,
    username_snapshot,
    rank_position,
    bracket_position,
    entry_round
  )
  select
    v_cup_id,
    (drawn.entry->>'user_id')::uuid,
    ranked.entry->>'username',
    (drawn.entry->>'rank_position')::integer,
    (drawn.entry->>'bracket_position')::integer,
    (drawn.entry->>'entry_round')::integer
  from jsonb_array_elements(v_draw) as drawn(entry)
  join jsonb_array_elements(v_ranking) as ranked(entry)
    on (ranked.entry->>'rank_position')::integer
      = (drawn.entry->>'rank_position')::integer;

  insert into public.cup_rounds (
    cup_id,
    round_number,
    slot_count,
    matchday_id,
    status
  )
  select
    v_cup_id,
    matchday.matchday_number - 2,
    case matchday.matchday_number
      when 3 then 64
      when 4 then 32
      when 5 then 16
      when 6 then 8
      when 7 then 4
      else 2
    end,
    matchday.id,
    'pending'
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  -- The whole skeleton exists from creation: 32+16+8+4+2+1 ties. Progression
  -- will only ever update these rows.
  insert into public.cup_ties (cup_id, round_id, slot, outcome)
  select v_cup_id, round.id, slot_series.slot, 'empty'
  from public.cup_rounds as round
  cross join lateral generate_series(1, round.slot_count / 2) as slot_series(slot)
  where round.cup_id = v_cup_id;

  with pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  resolved as (
    select
      pairing.slot,
      home_participant.id as home_participant_id,
      away_participant.id as away_participant_id
    from pairing
    left join public.cup_participants as home_participant
      on home_participant.cup_id = v_cup_id
      and home_participant.bracket_position = pairing.home_bracket_position
    left join public.cup_participants as away_participant
      on away_participant.cup_id = v_cup_id
      and away_participant.bracket_position = pairing.away_bracket_position
  )
  update public.cup_ties as tie
  set
    home_participant_id = resolved.home_participant_id,
    away_participant_id = resolved.away_participant_id,
    winner_participant_id = case
      when resolved.home_participant_id is null
        then resolved.away_participant_id
      when resolved.away_participant_id is null
        then resolved.home_participant_id
      else null
    end,
    outcome = case
      when resolved.home_participant_id is null
        and resolved.away_participant_id is null then 'empty'
      when resolved.home_participant_id is null
        or resolved.away_participant_id is null then 'bye'
      else 'pending'
    end,
    updated_at = now()
  from resolved
  join public.cup_rounds as round
    on round.cup_id = v_cup_id
    and round.round_number = 1
  where tie.round_id = round.id
    and tie.slot = resolved.slot;

  return v_preview || jsonb_build_object(
    'created', true,
    'cup_id', v_cup_id
  );
end;
$function$;

comment on function public.create_players_cup(boolean)
is 'Admin-only Players Cup creation. Freezes the Matchday 1-2 ranking, protects the top 8, draws everyone else inside their entry-round group from a persisted draw_seed, writes the full six round and 63 tie skeleton, and never regenerates an existing Cup. Scoring, progression and awards are out of scope. New competitions use the published 50/30/15 reward defaults unless the row is later reconfigured.';

comment on column public.cup_competitions.winner_points is
  'Published default 50. Award calculation always reads this row, never hardcoded literals.';

comment on column public.cup_competitions.finalist_points is
  'Published default 30. Award calculation always reads this row, never hardcoded literals.';

comment on column public.cup_competitions.semi_finalist_points is
  'Published default 15. Award calculation always reads this row, never hardcoded literals.';

revoke execute on function public.create_players_cup(boolean)
  from public, anon;
grant execute on function public.create_players_cup(boolean)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260821141500_knockout_final_scoring.sql
-- =====================================================================

-- Knockout & Final scoring foundation.
--
-- Two surgical function replacements:
--   set_match_result   Final matches score 10/4/0 from matchday.stage.
--                      Golden Match still doubles League Phase matches.
--                      The two reasons never stack. Players Cup lock, freeze,
--                      apply, correction and privileges are unchanged.
--   set_golden_match   Golden Match is League Phase only, still from MD2.
--
-- Classifier comments are clarified. Behaviour of prediction_is_exact /
-- prediction_is_correct and get_leaderboard is unchanged: knockout_points
-- already sums prediction points where stage <> 'league_phase', so Final
-- 10/4 points are included and Cup / long-term awards are not.
--
-- Admin result values remain the official 90-minute + stoppage-time score.
-- There are no extra-time, penalty or qualifier columns.

-- ---------------------------------------------------------------------------
-- Classifiers: comments only
-- ---------------------------------------------------------------------------

comment on function public.prediction_is_exact(integer)
is 'True when a prediction scored an exact score. 5 is the normal value; 10 is the doubled value from a Golden Match or the Final. NULL points count as false.';

comment on function public.prediction_is_correct(integer)
is 'True when a prediction scored a correct 1-X-2 result but not an exact score. 2 is the normal value; 4 is the doubled value from a Golden Match or the Final. NULL points count as false.';

-- ---------------------------------------------------------------------------
-- Golden Match: League Phase gate
-- ---------------------------------------------------------------------------

create or replace function public.set_golden_match(
  p_match_id bigint
)
returns table (
  match_id bigint,
  matchday_id bigint,
  replaced_match_id bigint,
  is_locked boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_stage text;
  v_matchday_number integer;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_previous_match_id bigint;
  v_previous_kickoff_at timestamptz;
  v_previous_status text;
  v_updated_at timestamptz;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  -- The profile row is also the per-user transaction lock. It serializes
  -- simultaneous selections so the unique matchday rule is deterministic.
  perform 1
  from public.profiles as profile
  where profile.id = v_user_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'An active player profile is required';
  end if;

  select
    match_row.matchday_id,
    matchday.stage,
    matchday.matchday_number,
    match_row.kickoff_at,
    match_row.status
  into
    v_matchday_id,
    v_stage,
    v_matchday_number,
    v_kickoff_at,
    v_match_status
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where match_row.id = p_match_id
  for share of match_row;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_stage is distinct from 'league_phase' then
    raise exception using
      errcode = '22023',
      message = 'Golden Match is available only during the League Phase';
  end if;

  if v_matchday_number is null or v_matchday_number < 2 then
    raise exception using
      errcode = '22023',
      message = 'Golden Match is available from Matchday 2';
  end if;

  select selection.match_id
  into v_previous_match_id
  from public.golden_match_selections as selection
  where selection.user_id = v_user_id
    and selection.matchday_id = v_matchday_id
  for update;

  -- Repeating the same request never mutates the row, including after kickoff.
  if found and v_previous_match_id = p_match_id then
    select selection.updated_at
    into v_updated_at
    from public.golden_match_selections as selection
    where selection.user_id = v_user_id
      and selection.matchday_id = v_matchday_id;

    return query
    select
      p_match_id,
      v_matchday_id,
      null::bigint,
      (v_match_status <> 'scheduled' or now() >= v_kickoff_at),
      v_updated_at;
    return;
  end if;

  if v_match_status <> 'scheduled' or now() >= v_kickoff_at then
    raise exception using
      errcode = '22023',
      message = 'Golden Match must be selected before kickoff';
  end if;

  if v_previous_match_id is not null then
    select match_row.kickoff_at, match_row.status
    into v_previous_kickoff_at, v_previous_status
    from public.matches as match_row
    where match_row.id = v_previous_match_id
    for share;

    if v_previous_status <> 'scheduled'
      or now() >= v_previous_kickoff_at
    then
      raise exception using
        errcode = '22023',
        message = 'Golden Match is locked after its kickoff';
    end if;

    update public.golden_match_selections as selection
    set
      match_id = p_match_id,
      updated_at = now()
    where selection.user_id = v_user_id
      and selection.matchday_id = v_matchday_id
    returning selection.updated_at into v_updated_at;
  else
    insert into public.golden_match_selections (
      user_id,
      matchday_id,
      match_id
    )
    values (
      v_user_id,
      v_matchday_id,
      p_match_id
    )
    returning golden_match_selections.updated_at into v_updated_at;
  end if;

  return query
  select
    p_match_id,
    v_matchday_id,
    v_previous_match_id,
    false,
    v_updated_at;
end;
$function$;

comment on function public.set_golden_match(bigint)
is 'Selects or replaces the caller own Golden Match before kickoff. League Phase only, one selection per matchday, available from Matchday 2.';

revoke execute on function public.set_golden_match(bigint)
  from public, anon;
grant execute on function public.set_golden_match(bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Result scoring: Final 10/4/0, otherwise Golden Match or normal 5/2/0
-- ---------------------------------------------------------------------------

create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_stage text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
  v_cup_ids bigint[];
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  -- Cup relevance comes from the round mapping itself, never from a hardcoded
  -- matchday range, so a match outside Matchdays 3 to 8 - and every match at
  -- all while no Cup exists - skips the Cup work entirely.
  --
  -- Reading matchday_id without a row lock is safe: once a Cup exists the phase
  -- 2A trigger rejects any attempt to move a Cup match to another matchday, so
  -- the value cannot change underneath this transaction.
  select array_agg(distinct round.cup_id)
  into v_cup_ids
  from public.matches as match_row
  join public.cup_rounds as round
    on round.matchday_id = match_row.matchday_id
  where match_row.id = p_match_id;

  if v_cup_ids is not null then
    -- Step 2. One key for the whole competition, always taken before any match
    -- row lock.
    perform pg_advisory_xact_lock(public.players_cup_lock_key());

    -- Step 3. Still before the match changes.
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_freeze_exclusions(v_cup_id);
    end loop;
  end if;

  -- Step 4. The match row lock. Stage is read here so Final scoring does not
  -- depend on a Golden Match row. p_home_score / p_away_score are the official
  -- 90-minute + stoppage-time score; the schema has no extra-time or penalty
  -- fields.
  select
    match_row.home_score,
    match_row.away_score,
    match_row.status,
    matchday.stage
  into
    v_current_home_score,
    v_current_away_score,
    v_current_status,
    v_stage
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where match_row.id = p_match_id
  for update of match_row;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as match_row
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where match_row.id = p_match_id;
  end if;

  with calculated_points as (
    select
      prediction.id,
      case
        when prediction.predicted_home_score = p_home_score
          and prediction.predicted_away_score = p_away_score
          then case
            when v_stage = 'final' then 10
            when selection.id is not null then 10
            else 5
          end
        when (
          prediction.predicted_home_score > prediction.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          prediction.predicted_home_score = prediction.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          prediction.predicted_home_score < prediction.predicted_away_score
          and p_home_score < p_away_score
        )
          then case
            when v_stage = 'final' then 4
            when selection.id is not null then 4
            else 2
          end
        else 0
      end as new_points
    from public.predictions as prediction
    left join public.golden_match_selections as selection
      on selection.user_id = prediction.user_id
      and selection.match_id = prediction.match_id
    where prediction.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as prediction
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where prediction.id = calculated_points.id
      and prediction.points is distinct from calculated_points.new_points
    returning prediction.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  -- Step 6. A full recompute, so a correction rebuilds the whole bracket and
  -- the honours list rather than patching one tie.
  if v_cup_ids is not null then
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_apply(v_cup_id);
    end loop;
  end if;

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry with deterministic idempotent 90-minute scoring: normal 5/2/0, selected Golden Match 10/4/0, Final 10/4/0. Final and Golden Match never stack. A result belonging to a Players Cup round also freezes any crossed postponed-match cutoff and recomputes the Cup in the same transaction.';

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260827190000_badges_foundation.sql
-- =====================================================================

-- Badges foundation: definitions, earned instances, RLS and grants.
--
-- Additive only. No award engine, no hooks into set_match_result /
-- set_long_term_outcome / players_cup_apply, and no player-profile UI.
-- Authenticated clients may read definitions and awards so a later profile
-- page can join metadata onto earned badges. There is still no catalogue
-- route: database readability is not UI visibility.
--
-- award_scope is the relational duplicate-prevention key. Repeatability
-- lives on badge_definitions; a partial unique index cannot see that table,
-- so definitions expose a generated award_scope and awards reference
-- (code, award_scope). Callers cannot mark Exact Machine as a matchday
-- award, and cannot mark Sharp Shooter as a season award.

create table public.badge_definitions (
  code text primary key,
  title text not null,
  description text not null,
  image_path text not null,
  repeatable boolean not null,
  category text not null,
  sort_order integer not null,
  award_scope text generated always as (
    case
      when repeatable then 'matchday'
      else 'season'
    end
  ) stored,
  created_at timestamptz not null default now(),
  constraint badge_definitions_code_check check (
    code ~ '^[a-z][a-z0-9_]*$'
    and char_length(code) between 1 and 64
  ),
  constraint badge_definitions_title_check check (
    char_length(btrim(title)) between 1 and 100
  ),
  constraint badge_definitions_description_check check (
    char_length(btrim(description)) between 1 and 500
  ),
  constraint badge_definitions_image_path_check check (
    image_path ~ '^/badges/[a-z0-9-]+\.png$'
  ),
  constraint badge_definitions_category_check check (
    category in (
      'season',
      'league_phase',
      'players_cup',
      'performance',
      'matchday'
    )
  ),
  constraint badge_definitions_sort_order_check check (sort_order > 0),
  constraint badge_definitions_code_award_scope_key
    unique (code, award_scope)
);

comment on table public.badge_definitions is
  'Canonical badge metadata. Readable by authenticated users for profile joins; not a public catalogue. award_scope is generated from repeatable so season vs matchday uniqueness cannot drift from the product flags.';

comment on column public.badge_definitions.award_scope is
  'season for unique-per-season badges, matchday for repeatable round badges. Generated from repeatable; referenced by badge_awards.';

comment on column public.badge_definitions.image_path is
  'Public path to the original PNG under /badges/. Optimization to WebP belongs to the profile UI phase.';

create table public.badge_awards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint badge_awards_user_id_fkey
    references public.profiles (id) on delete cascade,
  badge_code text not null,
  award_scope text not null,
  season_label text not null default 'Champions League 2026/27',
  earned_at timestamptz not null default now(),
  matchday_id bigint
    constraint badge_awards_matchday_id_fkey
    references public.matchdays (id) on delete restrict,
  cup_id bigint
    constraint badge_awards_cup_id_fkey
    references public.cup_competitions (id) on delete set null,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint badge_awards_badge_definition_scope_fkey
    foreign key (badge_code, award_scope)
    references public.badge_definitions (code, award_scope),
  constraint badge_awards_award_scope_check check (
    award_scope in ('season', 'matchday')
  ),
  constraint badge_awards_season_label_check check (
    char_length(btrim(season_label)) between 1 and 100
  ),
  constraint badge_awards_matchday_required_check check (
    (award_scope = 'matchday' and matchday_id is not null)
    or award_scope = 'season'
  ),
  constraint badge_awards_context_object_check check (
    jsonb_typeof(context) = 'object'
  )
);

comment on table public.badge_awards is
  'Earned badge instances. Empty after this migration. Future award engines write rows; authenticated users may only read them. Unique-per-season badges use award_scope = season; repeatable round badges use award_scope = matchday with a required matchday_id.';

comment on column public.badge_awards.award_scope is
  'Must match badge_definitions.award_scope via the composite foreign key. Enables partial unique indexes without a trigger.';

comment on column public.badge_awards.season_label is
  'Season identity for unique badges. No seasons table in this milestone. Current default is Champions League 2026/27.';

comment on column public.badge_awards.matchday_id is
  'Required for matchday-scoped awards. bigint, matching public.matchdays.id. ON DELETE RESTRICT because SET NULL would break the matchday-scope NOT NULL check.';

comment on column public.badge_awards.cup_id is
  'Optional context for Players Cup badges. Those badges remain unique per season; cup_id is not part of uniqueness.';

comment on column public.badge_awards.context is
  'Display/support metadata only. Core award truth is the typed columns, not this JSON.';

-- Unique-per-season badges: one row per player, badge and season.
create unique index badge_awards_user_season_uidx
  on public.badge_awards (user_id, badge_code, season_label)
  where award_scope = 'season';

-- Repeatable matchday badges: one row per player, badge and UEFA round.
create unique index badge_awards_user_matchday_uidx
  on public.badge_awards (user_id, badge_code, matchday_id)
  where award_scope = 'matchday';

create index badge_awards_user_id_idx
  on public.badge_awards (user_id);

create index badge_awards_badge_code_idx
  on public.badge_awards (badge_code);

create index badge_awards_matchday_id_idx
  on public.badge_awards (matchday_id);

create index badge_awards_cup_id_idx
  on public.badge_awards (cup_id);

create index badge_awards_season_label_idx
  on public.badge_awards (season_label);

-- Greek badge_definitions copy omitted.
-- English rows are inserted by 0003_english_badges.sql.

alter table public.badge_definitions enable row level security;
alter table public.badge_awards enable row level security;

-- Read-only for players, matching cup_awards. No insert, update or delete
-- policy exists, so the Data API rejects every browser write before column
-- grants are considered.
create policy "Authenticated users can view badge definitions"
  on public.badge_definitions
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view badge awards"
  on public.badge_awards
  for select
  to authenticated
  using (true);

revoke all privileges on table public.badge_definitions
  from public, anon, authenticated;
revoke all privileges on table public.badge_awards
  from public, anon, authenticated;

grant select on table public.badge_definitions to authenticated;
grant select on table public.badge_awards to authenticated;

grant all privileges on table public.badge_definitions to service_role;
grant all privileges on table public.badge_awards to service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260827194500_badges_matchday_engine.sql
-- =====================================================================

-- Badges Phase 2: matchday and cumulative award engine.
--
-- Awards Exact Machine, Sharp Shooter, On Fire, Perfect Matchday and Final
-- Boss. Podium, Leader, League Phase, Season and Players Cup badges are out
-- of scope.
--
-- Additive except for a surgical replacement of set_match_result. The
-- replacement is based on 20260821141500_knockout_final_scoring.sql: Cup
-- lock/freeze/apply, Final 10/4/0 and Golden Match scoring are unchanged.
-- Badge recompute runs after prediction points are final and after any Cup
-- apply, in the same transaction.
--
-- HOSTED DRIFT: compare pg_get_functiondef('public.set_match_result(bigint,
-- integer, integer)') on hosted against this body before apply. Do not db push.

-- ---------------------------------------------------------------------------
-- Completion
-- ---------------------------------------------------------------------------

create or replace function public.badge_matchday_is_complete(p_matchday_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.matches as match_row
      where match_row.matchday_id = p_matchday_id
    )
    and not exists (
      select 1
      from public.matches as match_row
      where match_row.matchday_id = p_matchday_id
        and match_row.status is distinct from 'finished'
    )
    and not exists (
      select 1
      from public.predictions as prediction
      join public.matches as match_row
        on match_row.id = prediction.match_id
      where match_row.matchday_id = p_matchday_id
        and prediction.points is null
    );
$function$;

comment on function public.badge_matchday_is_complete(bigint)
is 'UEFA badge matchday completeness: at least one match, every match finished, every prediction on those matches scored. Ignores matchdays.status and Players Cup postponed exclusions.';

-- ---------------------------------------------------------------------------
-- Per-matchday prediction stats
-- ---------------------------------------------------------------------------

create or replace function public.badge_matchday_player_stats(p_matchday_id bigint)
returns table (
  user_id uuid,
  matchday_id bigint,
  points bigint,
  exact_count bigint,
  correct_count bigint,
  missed_count bigint,
  match_count bigint,
  prediction_count bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with matchday_matches as (
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = p_matchday_id
  ),
  match_totals as (
    select count(*)::bigint as match_count
    from matchday_matches
  )
  select
    profile.id as user_id,
    p_matchday_id as matchday_id,
    coalesce(sum(prediction.points), 0)::bigint as points,
    count(prediction.id)
      filter (where public.prediction_is_exact(prediction.points))::bigint
      as exact_count,
    count(prediction.id)
      filter (where public.prediction_is_correct(prediction.points))::bigint
      as correct_count,
    (
      (select match_count from match_totals)
      - count(prediction.id)
    )::bigint as missed_count,
    (select match_count from match_totals) as match_count,
    count(prediction.id)::bigint as prediction_count
  from public.profiles as profile
  left join public.predictions as prediction
    on prediction.user_id = profile.id
    and prediction.match_id in (select matchday_matches.id from matchday_matches)
  where profile.status = 'active'
  group by profile.id;
$function$;

comment on function public.badge_matchday_player_stats(bigint)
is 'Per active user prediction stats for one UEFA matchday. points/exact/correct come from predictions.points and the canonical classifiers. Cup honours and long-term awards are never included. missed_count is match_count minus submitted predictions.';

-- ---------------------------------------------------------------------------
-- Repeatable matchday awards
-- ---------------------------------------------------------------------------

create or replace function public.recompute_matchday_badges(p_matchday_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_matchday_badges constant text[] := array[
    'sharp_shooter',
    'on_fire',
    'perfect_matchday'
  ];
begin
  if p_matchday_id is null then
    return;
  end if;

  if not public.badge_matchday_is_complete(p_matchday_id) then
    delete from public.badge_awards as award
    where award.matchday_id = p_matchday_id
      and award.award_scope = 'matchday'
      and award.badge_code = any (c_matchday_badges);
    return;
  end if;

  with stats as (
    select *
    from public.badge_matchday_player_stats(p_matchday_id) as player_stats
  ),
  qualifying as (
    select
      stats.user_id,
      'sharp_shooter'::text as badge_code,
      jsonb_build_object('exact_count', stats.exact_count) as context
    from stats
    where stats.exact_count >= 3
    union all
    select
      stats.user_id,
      'on_fire',
      jsonb_build_object('points', stats.points)
    from stats
    where stats.points >= 20
    union all
    select
      stats.user_id,
      'perfect_matchday',
      jsonb_build_object(
        'match_count', stats.match_count,
        'exact_count', stats.exact_count,
        'correct_count', stats.correct_count
      )
    from stats
    where stats.match_count > 0
      and stats.missed_count = 0
      and stats.exact_count + stats.correct_count = stats.match_count
  ),
  removed as (
    delete from public.badge_awards as award
    where award.matchday_id = p_matchday_id
      and award.award_scope = 'matchday'
      and award.badge_code = any (c_matchday_badges)
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
          and qualifying.badge_code = award.badge_code
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    matchday_id,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'matchday',
    c_season_label,
    p_matchday_id,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, matchday_id)
    where award_scope = 'matchday'
  do nothing;
end;
$function$;

comment on function public.recompute_matchday_badges(bigint)
is 'Idempotent Sharp Shooter / On Fire / Perfect Matchday recompute for one UEFA matchday. Awards only when the matchday is complete. Invalid rows are deleted; rows that remain valid keep earned_at. Does not touch podium badges.';

-- ---------------------------------------------------------------------------
-- Cumulative unique awards
-- ---------------------------------------------------------------------------

create or replace function public.recompute_cumulative_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
begin
  with exact_counts as (
    select
      profile.id as user_id,
      count(prediction.id)
        filter (where public.prediction_is_exact(prediction.points))::bigint
        as exact_count
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    where profile.status = 'active'
    group by profile.id
  ),
  qualifying as (
    select
      exact_counts.user_id,
      jsonb_build_object('exact_count', exact_counts.exact_count) as context
    from exact_counts
    where exact_counts.exact_count >= 10
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = 'exact_machine'
      and award.award_scope = 'season'
      and award.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    qualifying.user_id,
    'exact_machine',
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;

  with qualifying as (
    select distinct on (profile.id)
      profile.id as user_id,
      jsonb_build_object(
        'match_id', match_row.id,
        'matchday_id', match_row.matchday_id
      ) as context
    from public.profiles as profile
    join public.predictions as prediction
      on prediction.user_id = profile.id
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      and matchday.stage = 'final'
      and match_row.status = 'finished'
      and public.prediction_is_exact(prediction.points)
    order by profile.id, match_row.id
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = 'final_boss'
      and award.award_scope = 'season'
      and award.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    qualifying.user_id,
    'final_boss',
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;
end;
$function$;

comment on function public.recompute_cumulative_badges()
is 'Idempotent Exact Machine and Final Boss recompute for Champions League 2026/27. Exact Machine uses prediction_is_exact across all scored predictions. Final Boss requires matchdays.stage = final and an exact prediction, never points = 10 alone. Invalid rows are deleted; remaining rows keep earned_at.';

-- ---------------------------------------------------------------------------
-- set_match_result: same Cup/Final path, then badge recompute
-- ---------------------------------------------------------------------------

create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_matchday_id bigint;
  v_stage text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
  v_cup_ids bigint[];
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  -- Cup relevance comes from the round mapping itself, never from a hardcoded
  -- matchday range, so a match outside Matchdays 3 to 8 - and every match at
  -- all while no Cup exists - skips the Cup work entirely.
  --
  -- Reading matchday_id without a row lock is safe: once a Cup exists the phase
  -- 2A trigger rejects any attempt to move a Cup match to another matchday, so
  -- the value cannot change underneath this transaction.
  select array_agg(distinct round.cup_id)
  into v_cup_ids
  from public.matches as match_row
  join public.cup_rounds as round
    on round.matchday_id = match_row.matchday_id
  where match_row.id = p_match_id;

  if v_cup_ids is not null then
    -- Step 2. One key for the whole competition, always taken before any match
    -- row lock.
    perform pg_advisory_xact_lock(public.players_cup_lock_key());

    -- Step 3. Still before the match changes.
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_freeze_exclusions(v_cup_id);
    end loop;
  end if;

  -- Step 4. The match row lock. Stage is read here so Final scoring does not
  -- depend on a Golden Match row. p_home_score / p_away_score are the official
  -- 90-minute + stoppage-time score; the schema has no extra-time or penalty
  -- fields.
  select
    match_row.home_score,
    match_row.away_score,
    match_row.status,
    match_row.matchday_id,
    matchday.stage
  into
    v_current_home_score,
    v_current_away_score,
    v_current_status,
    v_matchday_id,
    v_stage
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where match_row.id = p_match_id
  for update of match_row;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as match_row
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where match_row.id = p_match_id;
  end if;

  with calculated_points as (
    select
      prediction.id,
      case
        when prediction.predicted_home_score = p_home_score
          and prediction.predicted_away_score = p_away_score
          then case
            when v_stage = 'final' then 10
            when selection.id is not null then 10
            else 5
          end
        when (
          prediction.predicted_home_score > prediction.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          prediction.predicted_home_score = prediction.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          prediction.predicted_home_score < prediction.predicted_away_score
          and p_home_score < p_away_score
        )
          then case
            when v_stage = 'final' then 4
            when selection.id is not null then 4
            else 2
          end
        else 0
      end as new_points
    from public.predictions as prediction
    left join public.golden_match_selections as selection
      on selection.user_id = prediction.user_id
      and selection.match_id = prediction.match_id
    where prediction.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as prediction
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where prediction.id = calculated_points.id
      and prediction.points is distinct from calculated_points.new_points
    returning prediction.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  -- Step 6. A full recompute, so a correction rebuilds the whole bracket and
  -- the honours list rather than patching one tie.
  if v_cup_ids is not null then
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_apply(v_cup_id);
    end loop;
  end if;

  -- Step 7. Badge awards read the scored prediction points, never a parallel
  -- calculation. Failure rolls back the football result, same as a Cup failure.
  perform public.recompute_matchday_badges(v_matchday_id);
  perform public.recompute_cumulative_badges();

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry with deterministic idempotent 90-minute scoring: normal 5/2/0, selected Golden Match 10/4/0, Final 10/4/0. Final and Golden Match never stack. A result belonging to a Players Cup round also freezes any crossed postponed-match cutoff and recomputes the Cup in the same transaction. After points are final, matchday and cumulative badge awards are recomputed in the same transaction.';

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;

revoke execute on function public.badge_matchday_is_complete(bigint)
  from public, anon, authenticated;
grant execute on function public.badge_matchday_is_complete(bigint)
  to service_role;

revoke execute on function public.badge_matchday_player_stats(bigint)
  from public, anon, authenticated;
grant execute on function public.badge_matchday_player_stats(bigint)
  to service_role;

revoke execute on function public.recompute_matchday_badges(bigint)
  from public, anon, authenticated;
grant execute on function public.recompute_matchday_badges(bigint)
  to service_role;

revoke execute on function public.recompute_cumulative_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_cumulative_badges()
  to service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260828100000_badges_ranking_engine.sql
-- =====================================================================

-- Badges Phase 3: ranking, Leader, League Phase, season and Players Cup awards.
--
-- Additive except for surgical replacements of:
--   public.recompute_matchday_badges(bigint)
--   public.set_match_result(bigint, integer, integer)
--   public.set_long_term_outcome(text, bigint)
--   public.recompute_players_cup()
-- Previous badge migrations are not edited. Profile UI is out of scope.
--
-- HOSTED DRIFT: hosted currently has the Phase 2 bodies of set_match_result
-- and recompute_matchday_badges, and the Phase 2A/long-term bodies of
-- set_long_term_outcome, recompute_players_cup and players_cup_apply. Compare
-- pg_get_functiondef of those five before a future apply. Do not db push.
-- players_cup_apply is intentionally not replaced; Cup badge sync runs from
-- recompute_ranking_badges after every write path that can change cup_awards.

-- ---------------------------------------------------------------------------
-- Matchday podium (extends Phase 2 recompute)
-- ---------------------------------------------------------------------------

create or replace function public.recompute_matchday_badges(p_matchday_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_matchday_badges constant text[] := array[
    'sharp_shooter',
    'on_fire',
    'perfect_matchday',
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday'
  ];
  c_podium_badges constant text[] := array[
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday'
  ];
begin
  if p_matchday_id is null then
    return;
  end if;

  if not public.badge_matchday_is_complete(p_matchday_id) then
    delete from public.badge_awards as award
    where award.matchday_id = p_matchday_id
      and award.award_scope = 'matchday'
      and award.badge_code = any (c_matchday_badges);
    return;
  end if;

  with stats as (
    select *
    from public.badge_matchday_player_stats(p_matchday_id) as player_stats
  ),
  ranked as (
    select
      stats.*,
      rank() over (
        order by
          stats.points desc,
          stats.exact_count desc,
          stats.correct_count desc,
          stats.missed_count asc
      ) as rank_position
    from stats
  ),
  qualifying as (
    select
      stats.user_id,
      'sharp_shooter'::text as badge_code,
      jsonb_build_object('exact_count', stats.exact_count) as context
    from stats
    where stats.exact_count >= 3
    union all
    select
      stats.user_id,
      'on_fire',
      jsonb_build_object('points', stats.points)
    from stats
    where stats.points >= 20
    union all
    select
      stats.user_id,
      'perfect_matchday',
      jsonb_build_object(
        'match_count', stats.match_count,
        'exact_count', stats.exact_count,
        'correct_count', stats.correct_count
      )
    from stats
    where stats.match_count > 0
      and stats.missed_count = 0
      and stats.exact_count + stats.correct_count = stats.match_count
    union all
    select
      ranked.user_id,
      case ranked.rank_position
        when 1 then 'top_of_the_matchday'
        when 2 then 'second_of_the_matchday'
        when 3 then 'third_of_the_matchday'
      end,
      jsonb_build_object(
        'rank', ranked.rank_position,
        'points', ranked.points,
        'exact_count', ranked.exact_count,
        'correct_count', ranked.correct_count,
        'missed_count', ranked.missed_count
      )
    from ranked
    where ranked.rank_position in (1, 2, 3)
  ),
  removed as (
    delete from public.badge_awards as award
    where award.matchday_id = p_matchday_id
      and award.award_scope = 'matchday'
      and award.badge_code = any (c_matchday_badges)
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
          and qualifying.badge_code = award.badge_code
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    matchday_id,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'matchday',
    c_season_label,
    p_matchday_id,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, matchday_id)
    where award_scope = 'matchday'
  do update
  set context = excluded.context
  where excluded.badge_code = any (c_podium_badges)
    and public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_matchday_badges(bigint)
is 'Idempotent Sharp Shooter / On Fire / Perfect Matchday / podium recompute for one UEFA matchday. Awards only when the matchday is complete. Invalid rows are deleted; rows that remain valid keep earned_at. Podium uses RANK() on points, exact, correct, fewer missed; shared ranks skip medals. Performance-badge conflict handling is still insert-only.';

-- ---------------------------------------------------------------------------
-- Leader
-- ---------------------------------------------------------------------------

create or replace function public.award_leader_if_applicable()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
begin
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    standing.user_id,
    'leader',
    'season',
    c_season_label,
    jsonb_build_object(
      'rank', standing.rank_position,
      'total_points', standing.total_points,
      'exact_scores', standing.exact_scores,
      'correct_results', standing.correct_results,
      'knockout_points', standing.knockout_points,
      'missed_predictions', standing.missed_predictions
    )
  from public.get_leaderboard() as standing
  where standing.rank_position = 1
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;
end;
$function$;

comment on function public.award_leader_if_applicable()
is 'Inserts Leader for every current get_leaderboard() rank 1. Never deletes. ON CONFLICT DO NOTHING preserves the first earned_at. Inactive users are absent from get_leaderboard so they cannot newly earn Leader.';

-- ---------------------------------------------------------------------------
-- Players Cup badge sync
-- ---------------------------------------------------------------------------

create or replace function public.sync_players_cup_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_cup_badges constant text[] := array[
    'players_cup_champion',
    'players_cup_finalist',
    'players_cup_semifinalist'
  ];
begin
  with qualifying as (
    select
      award.user_id,
      case award.award_type
        when 'winner' then 'players_cup_champion'
        when 'finalist' then 'players_cup_finalist'
        when 'semi_finalist' then 'players_cup_semifinalist'
      end as badge_code,
      award.cup_id,
      jsonb_build_object(
        'award_type', award.award_type,
        'points', award.points
      ) as context
    from public.cup_awards as award
    join public.cup_competitions as competition
      on competition.id = award.cup_id
    where competition.season_label = c_season_label
      and award.user_id is not null
      and award.award_type in ('winner', 'finalist', 'semi_finalist')
  ),
  removed as (
    delete from public.badge_awards as badge
    where badge.badge_code = any (c_cup_badges)
      and badge.award_scope = 'season'
      and badge.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = badge.user_id
          and qualifying.badge_code = badge.badge_code
      )
    returning badge.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    cup_id,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.cup_id,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set
    cup_id = excluded.cup_id,
    context = excluded.context
  where public.badge_awards.cup_id is distinct from excluded.cup_id
    or public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.sync_players_cup_badges()
is 'Mirrors persisted cup_awards into Players Cup badges for Champions League 2026/27. Does not inspect the bracket. Stale honours are deleted; unchanged honours keep earned_at. cup_awards rows with a null user_id are skipped.';

-- ---------------------------------------------------------------------------
-- League Phase completion and snapshot
-- ---------------------------------------------------------------------------

create or replace function public.badge_players_cup_is_complete()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.cup_competitions as competition
    where competition.slug = 'players-cup-2026-27'
      and competition.status = 'completed'
  );
$function$;

comment on function public.badge_players_cup_is_complete()
is 'True when the canonical Players Cup (slug players-cup-2026-27) exists and status is completed. That status is written by players_cup_apply only after the Final is decided and cup_awards are rebuilt.';

create or replace function public.badge_league_phase_is_complete()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.matches as match_row
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
    )
    and not exists (
      select 1
      from public.matches as match_row
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
        and match_row.status is distinct from 'finished'
    )
    and not exists (
      select 1
      from public.predictions as prediction
      join public.matches as match_row
        on match_row.id = prediction.match_id
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
        and prediction.points is null
    )
    and public.badge_players_cup_is_complete()
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'league_phase_first'
    );
$function$;

comment on function public.badge_league_phase_is_complete()
is 'League Phase badge gate: at least one LP match, every LP match finished, every LP prediction scored, canonical Players Cup completed, league_phase_first outcome decided. Ignores matchdays.status.';

create or replace function public.badge_league_phase_ranking_for(p_extra_user_ids uuid[])
returns table (
  user_id uuid,
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      profile.id as user_id,
      (
        coalesce(
          sum(prediction.points) filter (where matchday.stage = 'league_phase'),
          0
        )
        + coalesce((
          select sum(award.points)
          from public.long_term_awards as award
          where award.user_id = profile.id
            and award.prediction_type = 'league_phase_first'
        ), 0)
        + coalesce((
          select sum(cup_award.points)
          from public.cup_awards as cup_award
          where cup_award.user_id = profile.id
        ), 0)
      )::bigint as total_points,
      count(prediction.id)
        filter (
          where matchday.stage = 'league_phase'
            and public.prediction_is_exact(prediction.points)
        )::bigint as exact_scores,
      count(prediction.id)
        filter (
          where matchday.stage = 'league_phase'
            and public.prediction_is_correct(prediction.points)
        )::bigint as correct_results,
      (
        (
          select count(*)
          from public.matches as finished_match
          join public.matchdays as finished_matchday
            on finished_matchday.id = finished_match.matchday_id
          where finished_matchday.stage = 'league_phase'
            and finished_match.status = 'finished'
        )
        - count(prediction.id)
          filter (
            where matchday.stage = 'league_phase'
              and match_row.status = 'finished'
          )::bigint
      ) as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      or profile.id = any (coalesce(p_extra_user_ids, '{}'::uuid[]))
    group by profile.id
  )
  select
    ranked.user_id,
    ranked.rank_position,
    ranked.total_points,
    ranked.exact_scores,
    ranked.correct_results,
    ranked.missed_predictions
  from (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc,
          player_stats.missed_predictions asc
      ) as rank_position,
      player_stats.user_id,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.missed_predictions
    from player_stats
  ) as ranked;
$function$;

comment on function public.badge_league_phase_ranking_for(uuid[])
is 'League Phase ranking for active users plus optional extra user ids. Extra ids exist so already-earned inactive holders can be revalidated after a data correction without letting them newly earn badges.';

create or replace function public.badge_league_phase_ranking()
returns table (
  user_id uuid,
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    standing.user_id,
    standing.rank_position,
    standing.total_points,
    standing.exact_scores,
    standing.correct_results,
    standing.missed_predictions
  from public.badge_league_phase_ranking_for('{}'::uuid[]) as standing;
$function$;

comment on function public.badge_league_phase_ranking()
is 'Player-game ranking at League Phase end for active users: LP prediction points plus persisted cup_awards plus league_phase_first long-term awards. Excludes knockout/Final prediction points and the winner +30. exact/correct/missed are LP-only. get_leaderboard knockout_points is inapplicable here (always conceptually 0) so the remaining RANK() keys match overall standings.';

create or replace function public.recompute_league_phase_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_lp_badges constant text[] := array[
    'league_phase_champion',
    'league_phase_runner_up'
  ];
  v_holders uuid[];
begin
  if not public.badge_league_phase_is_complete() then
    delete from public.badge_awards as award
    where award.badge_code = any (c_lp_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label;
    return;
  end if;

  select coalesce(array_agg(distinct award.user_id), '{}'::uuid[])
  into v_holders
  from public.badge_awards as award
  where award.badge_code = any (c_lp_badges)
    and award.award_scope = 'season'
    and award.season_label = c_season_label;

  with ranking as (
    select *
    from public.badge_league_phase_ranking_for(v_holders) as standing
  ),
  qualifying as (
    select
      ranking.user_id,
      case ranking.rank_position
        when 1 then 'league_phase_champion'
        when 2 then 'league_phase_runner_up'
      end as badge_code,
      jsonb_build_object(
        'rank', ranking.rank_position,
        'total_points', ranking.total_points,
        'exact_scores', ranking.exact_scores,
        'correct_results', ranking.correct_results,
        'missed_predictions', ranking.missed_predictions
      ) as context
    from ranking
    where ranking.rank_position in (1, 2)
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = any (c_lp_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
          and qualifying.badge_code = award.badge_code
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  join public.profiles as profile
    on profile.id = qualifying.user_id
  where profile.status = 'active'
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set context = excluded.context
  where public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_league_phase_badges()
is 'Correction-safe League Phase Champion / Runner-up. Ranking set is active users plus existing holders, so inactivity alone does not revoke, but a score/outcome correction can. New awards insert only for active users. Shared RANK() 1 awards every co-leader and skips runner-up. Incomplete LP deletes both badges.';

-- ---------------------------------------------------------------------------
-- Season completion and ranking badges
-- ---------------------------------------------------------------------------

create or replace function public.badge_season_is_complete()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.matches as match_row
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'final'
    )
    and not exists (
      select 1
      from public.matches as match_row
      where match_row.status is distinct from 'finished'
    )
    and not exists (
      select 1
      from public.predictions as prediction
      where prediction.points is null
    )
    and public.badge_players_cup_is_complete()
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'winner'
    )
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'league_phase_first'
    );
$function$;

comment on function public.badge_season_is_complete()
is 'Season badge gate: at least one Final match exists; every row currently in public.matches is finished; every prediction on those matches is scored; canonical Players Cup completed; winner and league_phase_first outcomes decided. Ignores matchdays.status and does not require nonexistent future matchdays.';

create or replace function public.badge_season_ranking_for(p_extra_user_ids uuid[])
returns table (
  user_id uuid,
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      profile.id as user_id,
      (
        coalesce(sum(prediction.points), 0)
        + coalesce((
          select sum(award.points)
          from public.long_term_awards as award
          where award.user_id = profile.id
        ), 0)
        + coalesce((
          select sum(cup_award.points)
          from public.cup_awards as cup_award
          where cup_award.user_id = profile.id
        ), 0)
      )::bigint as total_points,
      count(prediction.id)
        filter (where public.prediction_is_exact(prediction.points))::bigint
        as exact_scores,
      count(prediction.id)
        filter (where public.prediction_is_correct(prediction.points))::bigint
        as correct_results,
      coalesce(
        sum(prediction.points)
          filter (where matchday.stage <> 'league_phase'),
        0
      )::bigint as knockout_points,
      (
        select count(*)
        from public.matches as finished_match
        where finished_match.status = 'finished'
      )
      - count(prediction.id)
        filter (where match_row.status = 'finished')::bigint
        as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      or profile.id = any (coalesce(p_extra_user_ids, '{}'::uuid[]))
    group by profile.id
  )
  select
    ranked.user_id,
    ranked.rank_position,
    ranked.total_points,
    ranked.exact_scores,
    ranked.correct_results,
    ranked.knockout_points,
    ranked.missed_predictions
  from (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc,
          player_stats.knockout_points desc,
          player_stats.missed_predictions asc
      ) as rank_position,
      player_stats.user_id,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.knockout_points,
      player_stats.missed_predictions
    from player_stats
  ) as ranked;
$function$;

comment on function public.badge_season_ranking_for(uuid[])
is 'Overall ranking identical to get_leaderboard() keys, for active users plus optional extra user ids. Extra ids revalidate already-earned inactive holders after a data correction. get_leaderboard() itself is unchanged.';

create or replace function public.recompute_season_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_season_badges constant text[] := array[
    'season_champion',
    'season_runner_up',
    'season_top_5'
  ];
  v_holders uuid[];
begin
  if not public.badge_season_is_complete() then
    delete from public.badge_awards as award
    where award.badge_code = any (c_season_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label;
    return;
  end if;

  select coalesce(array_agg(distinct award.user_id), '{}'::uuid[])
  into v_holders
  from public.badge_awards as award
  where award.badge_code = any (c_season_badges)
    and award.award_scope = 'season'
    and award.season_label = c_season_label;

  with ranking as (
    select *
    from public.badge_season_ranking_for(v_holders) as standing
  ),
  qualifying as (
    select
      ranking.user_id,
      case
        when ranking.rank_position = 1 then 'season_champion'
        when ranking.rank_position = 2 then 'season_runner_up'
        when ranking.rank_position in (3, 4, 5) then 'season_top_5'
      end as badge_code,
      jsonb_build_object(
        'rank', ranking.rank_position,
        'total_points', ranking.total_points,
        'exact_scores', ranking.exact_scores,
        'correct_results', ranking.correct_results,
        'knockout_points', ranking.knockout_points,
        'missed_predictions', ranking.missed_predictions
      ) as context
    from ranking
    where ranking.rank_position in (1, 2, 3, 4, 5)
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = any (c_season_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
          and qualifying.badge_code = award.badge_code
      )
    returning award.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  join public.profiles as profile
    on profile.id = qualifying.user_id
  where profile.status = 'active'
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set context = excluded.context
  where public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_season_badges()
is 'Correction-safe Season Champion / Runner-up / Top 5. Ranking set is active users plus existing holders, so inactivity alone does not revoke, but a score/outcome correction can. New awards insert only for active users. Shared RANK() values are used as-is; Top 5 is only ranks 3/4/5. Incomplete season deletes all three. Point keys match get_leaderboard(); get_leaderboard() itself is unchanged.';

-- ---------------------------------------------------------------------------
-- Orchestrator
-- ---------------------------------------------------------------------------

create or replace function public.recompute_ranking_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.award_leader_if_applicable();
  perform public.recompute_league_phase_badges();
  perform public.recompute_season_badges();
  perform public.sync_players_cup_badges();
end;
$function$;

comment on function public.recompute_ranking_badges()
is 'Leader insert, League Phase recompute, season recompute and Players Cup badge sync. Ranking functions read cup_awards / predictions / long_term_awards, never Cup badge rows, so Cup sync can stay last. Does not walk every matchday podium; that stays on recompute_matchday_badges.';

-- ---------------------------------------------------------------------------
-- set_match_result: Phase 2 body plus ranking orchestrator
-- ---------------------------------------------------------------------------

create or replace function public.set_match_result(
  p_match_id bigint,
  p_home_score integer,
  p_away_score integer
)
returns table (
  match_id bigint,
  home_score integer,
  away_score integer,
  status text,
  scored_predictions bigint,
  changed_predictions bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_home_score integer;
  v_current_away_score integer;
  v_current_status text;
  v_matchday_id bigint;
  v_stage text;
  v_scored_predictions bigint;
  v_changed_predictions bigint;
  v_cup_ids bigint[];
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_home_score is null
    or p_away_score is null
    or p_home_score < 0
    or p_away_score < 0
  then
    raise exception using
      errcode = '22023',
      message = 'Scores must be non-negative integers';
  end if;

  -- Cup relevance comes from the round mapping itself, never from a hardcoded
  -- matchday range, so a match outside Matchdays 3 to 8 - and every match at
  -- all while no Cup exists - skips the Cup work entirely.
  --
  -- Reading matchday_id without a row lock is safe: once a Cup exists the phase
  -- 2A trigger rejects any attempt to move a Cup match to another matchday, so
  -- the value cannot change underneath this transaction.
  select array_agg(distinct round.cup_id)
  into v_cup_ids
  from public.matches as match_row
  join public.cup_rounds as round
    on round.matchday_id = match_row.matchday_id
  where match_row.id = p_match_id;

  if v_cup_ids is not null then
    -- Step 2. One key for the whole competition, always taken before any match
    -- row lock.
    perform pg_advisory_xact_lock(public.players_cup_lock_key());

    -- Step 3. Still before the match changes.
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_freeze_exclusions(v_cup_id);
    end loop;
  end if;

  -- Step 4. The match row lock. Stage is read here so Final scoring does not
  -- depend on a Golden Match row. p_home_score / p_away_score are the official
  -- 90-minute + stoppage-time score; the schema has no extra-time or penalty
  -- fields.
  select
    match_row.home_score,
    match_row.away_score,
    match_row.status,
    match_row.matchday_id,
    matchday.stage
  into
    v_current_home_score,
    v_current_away_score,
    v_current_status,
    v_matchday_id,
    v_stage
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where match_row.id = p_match_id
  for update of match_row;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Match not found';
  end if;

  if v_current_home_score is distinct from p_home_score
    or v_current_away_score is distinct from p_away_score
    or v_current_status is distinct from 'finished'
  then
    update public.matches as match_row
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where match_row.id = p_match_id;
  end if;

  with calculated_points as (
    select
      prediction.id,
      case
        when prediction.predicted_home_score = p_home_score
          and prediction.predicted_away_score = p_away_score
          then case
            when v_stage = 'final' then 10
            when selection.id is not null then 10
            else 5
          end
        when (
          prediction.predicted_home_score > prediction.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          prediction.predicted_home_score = prediction.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          prediction.predicted_home_score < prediction.predicted_away_score
          and p_home_score < p_away_score
        )
          then case
            when v_stage = 'final' then 4
            when selection.id is not null then 4
            else 2
          end
        else 0
      end as new_points
    from public.predictions as prediction
    left join public.golden_match_selections as selection
      on selection.user_id = prediction.user_id
      and selection.match_id = prediction.match_id
    where prediction.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as prediction
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where prediction.id = calculated_points.id
      and prediction.points is distinct from calculated_points.new_points
    returning prediction.id
  )
  select
    (select count(*) from calculated_points),
    (select count(*) from updated_predictions)
  into v_scored_predictions, v_changed_predictions;

  -- Step 6. A full recompute, so a correction rebuilds the whole bracket and
  -- the honours list rather than patching one tie.
  if v_cup_ids is not null then
    foreach v_cup_id in array v_cup_ids loop
      perform public.players_cup_apply(v_cup_id);
    end loop;
  end if;

  -- Step 7. Badge awards read the scored prediction points, never a parallel
  -- calculation. Failure rolls back the football result, same as a Cup failure.
  perform public.recompute_matchday_badges(v_matchday_id);
  perform public.recompute_cumulative_badges();
  perform public.recompute_ranking_badges();

  return query
  select
    p_match_id,
    p_home_score,
    p_away_score,
    'finished'::text,
    v_scored_predictions,
    v_changed_predictions;
end;
$function$;

comment on function public.set_match_result(bigint, integer, integer)
is 'Admin-only result entry with deterministic idempotent 90-minute scoring: normal 5/2/0, selected Golden Match 10/4/0, Final 10/4/0. Final and Golden Match never stack. A result belonging to a Players Cup round also freezes any crossed postponed-match cutoff and recomputes the Cup in the same transaction. After points are final, matchday, cumulative and ranking badge awards are recomputed in the same transaction.';

-- ---------------------------------------------------------------------------
-- set_long_term_outcome: existing semantics plus ranking recompute
-- ---------------------------------------------------------------------------

create or replace function public.set_long_term_outcome(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  outcome_changed boolean,
  scored_predictions bigint,
  changed_awards bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_outcome_changed boolean;
  v_scored_predictions bigint;
  v_changed_awards bigint;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_prediction_type is null
    or p_prediction_type not in ('winner', 'league_phase_first')
  then
    raise exception using
      errcode = '22023',
      message = 'Unknown long-term prediction type';
  end if;

  if not exists (
    select 1
    from public.teams as team
    where team.id = p_team_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'Team not found';
  end if;

  select count(*), min(matchday.id)
  into v_matchday_count, v_matchday_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

  perform 1
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id
  order by match_row.id
  for share;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into
    v_match_count,
    v_finished_count
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count <> v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term outcomes require completed Matchday 3';
  end if;

  with outcome_change as (
    insert into public.long_term_outcomes (
      prediction_type,
      team_id,
      decided_by
    )
    values (
      p_prediction_type,
      p_team_id,
      v_admin_id
    )
    on conflict on constraint long_term_outcomes_pkey do update
    set
      team_id = excluded.team_id,
      decided_by = excluded.decided_by,
      updated_at = now()
    where long_term_outcomes.team_id
      is distinct from excluded.team_id
    returning 1
  ),
  calculated_awards as (
    select
      selection.user_id,
      selection.prediction_type,
      selection.team_id as predicted_team_id,
      p_team_id as outcome_team_id,
      case
        when selection.team_id <> p_team_id then 0
        when p_prediction_type = 'winner' then 30
        when p_prediction_type = 'league_phase_first' then 15
        else 0
      end as points
    from public.long_term_predictions as selection
    where selection.prediction_type = p_prediction_type
  ),
  updated_awards as (
    insert into public.long_term_awards (
      user_id,
      prediction_type,
      predicted_team_id,
      outcome_team_id,
      points
    )
    select
      award.user_id,
      award.prediction_type,
      award.predicted_team_id,
      award.outcome_team_id,
      award.points
    from calculated_awards as award
    on conflict on constraint long_term_awards_pkey do update
    set
      predicted_team_id = excluded.predicted_team_id,
      outcome_team_id = excluded.outcome_team_id,
      points = excluded.points,
      updated_at = now()
    where long_term_awards.predicted_team_id
        is distinct from excluded.predicted_team_id
      or long_term_awards.outcome_team_id
        is distinct from excluded.outcome_team_id
      or long_term_awards.points
        is distinct from excluded.points
    returning 1
  )
  select
    exists (select 1 from outcome_change),
    (select count(*) from calculated_awards),
    (select count(*) from updated_awards)
  into
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;

  perform public.recompute_ranking_badges();

  return query
  select
    p_prediction_type,
    p_team_id,
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;
end;
$function$;

comment on function public.set_long_term_outcome(text, bigint)
is 'Admin-only long-term outcome entry. After awards are written, ranking badges (Leader, League Phase, season, Players Cup sync) are recomputed in the same transaction.';

-- ---------------------------------------------------------------------------
-- recompute_players_cup: existing apply plus ranking orchestrator
-- ---------------------------------------------------------------------------

create or replace function public.recompute_players_cup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  v_cup_id bigint;
  v_summary jsonb;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Taken before any row lock. Phase 2B must use the same order inside
  -- set_match_result, otherwise two admins scoring two matches can deadlock.
  perform pg_advisory_xact_lock(public.players_cup_lock_key());

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug;

  -- No draw yet is a normal state, not an error.
  if v_cup_id is null then
    perform public.recompute_ranking_badges();
    return jsonb_build_object(
      'cup_exists', false,
      'slug', c_slug,
      'recomputed_at', now()
    );
  end if;

  v_summary := public.players_cup_apply(v_cup_id)
    || jsonb_build_object('cup_exists', true);
  perform public.recompute_ranking_badges();
  return v_summary;
end;
$function$;

comment on function public.recompute_players_cup()
is 'Admin-only Players Cup recalculation. Recomputes every derived value from the current football results, then syncs ranking badges. Returns a summary instead of raising when no Cup has been drawn yet.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;

revoke execute on function public.set_long_term_outcome(text, bigint)
  from public, anon;
grant execute on function public.set_long_term_outcome(text, bigint)
  to authenticated, service_role;

revoke execute on function public.recompute_players_cup()
  from public, anon;
grant execute on function public.recompute_players_cup()
  to authenticated, service_role;

revoke execute on function public.recompute_matchday_badges(bigint)
  from public, anon, authenticated;
grant execute on function public.recompute_matchday_badges(bigint)
  to service_role;

revoke execute on function public.award_leader_if_applicable()
  from public, anon, authenticated;
grant execute on function public.award_leader_if_applicable()
  to service_role;

revoke execute on function public.sync_players_cup_badges()
  from public, anon, authenticated;
grant execute on function public.sync_players_cup_badges()
  to service_role;

revoke execute on function public.badge_players_cup_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_players_cup_is_complete()
  to service_role;

revoke execute on function public.badge_league_phase_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_is_complete()
  to service_role;

revoke execute on function public.badge_league_phase_ranking()
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_ranking()
  to service_role;

revoke execute on function public.badge_league_phase_ranking_for(uuid[])
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_ranking_for(uuid[])
  to service_role;

revoke execute on function public.badge_season_ranking_for(uuid[])
  from public, anon, authenticated;
grant execute on function public.badge_season_ranking_for(uuid[])
  to service_role;

revoke execute on function public.recompute_league_phase_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_league_phase_badges()
  to service_role;

revoke execute on function public.badge_season_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_season_is_complete()
  to service_role;

revoke execute on function public.recompute_season_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_season_badges()
  to service_role;

revoke execute on function public.recompute_ranking_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_ranking_badges()
  to service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260828120000_badges_backfill_recovery.sql
-- =====================================================================

-- Badges Phase 5: backfill / recovery tooling.
--
-- Additive. Previous badge migrations are not edited.
-- Creates the master recompute and an admin-only recovery RPC.
-- Does NOT execute a backfill. Operators run admin_recompute_badges()
-- (or service_role recompute_all_badges()) after hosted apply.

-- ---------------------------------------------------------------------------
-- Internal master recompute
-- ---------------------------------------------------------------------------

create or replace function public.recompute_all_badges()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_matchday_id bigint;
  v_matchdays_processed integer := 0;
  v_complete_matchdays integer := 0;
  v_award_count_before bigint;
  v_award_count_after bigint;
  v_leader_count bigint;
begin
  select count(*)
  into v_award_count_before
  from public.badge_awards;

  for v_matchday_id in
    select distinct match_row.matchday_id
    from public.matches as match_row
    order by match_row.matchday_id
  loop
    perform public.recompute_matchday_badges(v_matchday_id);
    v_matchdays_processed := v_matchdays_processed + 1;

    if public.badge_matchday_is_complete(v_matchday_id) then
      v_complete_matchdays := v_complete_matchdays + 1;
    end if;
  end loop;

  perform public.recompute_cumulative_badges();
  perform public.recompute_ranking_badges();

  select count(*)
  into v_award_count_after
  from public.badge_awards;

  select count(*)
  into v_leader_count
  from public.badge_awards as award
  where award.badge_code = 'leader';

  return jsonb_build_object(
    'matchdays_processed', v_matchdays_processed,
    'complete_matchdays', v_complete_matchdays,
    'award_count_before', v_award_count_before,
    'award_count_after', v_award_count_after,
    'leader_count', v_leader_count,
    'recomputed_at', now()
  );
end;
$function$;

comment on function public.recompute_all_badges()
is 'Internal badge rebuild from current persisted data. Walks every matchday that currently has matches (not matchdays.status), then cumulative, then ranking (Leader insert-only, LP, season, Cup mirror). Does not fabricate historical Leaders. Not invoked by this migration.';

-- ---------------------------------------------------------------------------
-- Admin recovery wrapper
-- ---------------------------------------------------------------------------

create or replace function public.admin_recompute_badges()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  return public.recompute_all_badges();
end;
$function$;

comment on function public.admin_recompute_badges()
is 'Active-admin recovery RPC. Rebuilds badge_awards from current persisted data via recompute_all_badges. Not a player self-service. Same authorization style as set_match_result / recompute_players_cup.';

revoke execute on function public.recompute_all_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_all_badges()
  to service_role;

revoke execute on function public.admin_recompute_badges()
  from public, anon;
grant execute on function public.admin_recompute_badges()
  to authenticated, service_role;


-- =====================================================================
-- SOURCE: supabase/migrations/20260828140000_leader_first_matchday_guard.sql
-- =====================================================================

-- Leader eligibility: first League Phase matchday must be complete.
--
-- Additive. Replaces only public.award_leader_if_applicable().
-- Previous badge migrations are not edited. No backfill is executed.

create or replace function public.award_leader_if_applicable()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  v_matchday_1_count integer;
  v_matchday_1_id bigint;
begin
  select count(*)
  into v_matchday_1_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 1;

  if v_matchday_1_count is distinct from 1 then
    return;
  end if;

  select matchday.id
  into v_matchday_1_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 1;

  if not public.badge_matchday_is_complete(v_matchday_1_id) then
    return;
  end if;

  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    standing.user_id,
    'leader',
    'season',
    c_season_label,
    jsonb_build_object(
      'rank', standing.rank_position,
      'total_points', standing.total_points,
      'exact_scores', standing.exact_scores,
      'correct_results', standing.correct_results,
      'knockout_points', standing.knockout_points,
      'missed_predictions', standing.missed_predictions
    )
  from public.get_leaderboard() as standing
  where standing.rank_position = 1
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;
end;
$function$;

comment on function public.award_leader_if_applicable()
is 'Inserts Leader for every current get_leaderboard() rank 1 after the unique League Phase Matchday 1 is complete (badge_matchday_is_complete). Missing or ambiguous Matchday 1, or an incomplete Matchday 1, awards nothing. Never deletes. ON CONFLICT DO NOTHING preserves the first earned_at. Inactive users are absent from get_leaderboard so they cannot newly earn Leader.';


-- =====================================================================
-- SOURCE: supabase/migrations/20260829160000_profiles_username_format.sql
-- =====================================================================

-- Username format for public.profiles.
--
-- Additive CHECK only. Does not modify rows, RLS, grants, or Cup tables.
-- Do not db push. Do not repair migration history. Apply manually after review.
--
-- 30 characters is within cup_participants.username_snapshot (1–100), so
-- create_players_cup cannot fail on username length after this constraint.

do $$
declare
  violating text;
begin
  select string_agg(
    profile.id::text || ' / ' || profile.username,
    E'\n'
    order by profile.username
  )
  into violating
  from public.profiles as profile
  where profile.username is distinct from btrim(profile.username)
     or char_length(profile.username) < 3
     or char_length(profile.username) > 30
     or profile.username !~ '^[A-Za-z0-9_.ΆΈ-ΊΌΎ-ώ-]+$';

  if violating is not null then
    raise exception
      'Cannot add profiles_username_format_check; existing usernames violate the 3–30 policy:%',
      E'\n' || violating;
  end if;
end $$;

alter table public.profiles
  add constraint profiles_username_format_check
  check (
    username = btrim(username)
    and char_length(username) between 3 and 30
    and username ~ '^[A-Za-z0-9_.ΆΈ-ΊΌΎ-ώ-]+$'
  );


-- =====================================================================
-- SOURCE: supabase/migrations/20260829190000_predictions_require_active_profile.sql
-- =====================================================================

-- Prediction writes require an active profile.
--
-- Disabled accounts keep an Auth session until the app signs them out, so
-- INSERT/UPDATE on public.predictions must not rely on the frontend alone.
-- SELECT policies are unchanged: a disabled user may still read their own
-- historical predictions.
--
-- Do not db push from this file. Do not repair migration history.
-- Apply to hosted Supabase only after review.

drop policy if exists "Users can create their own predictions"
  on public.predictions;
create policy "Users can create their own predictions"
  on public.predictions
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );

drop policy if exists "Users can update their own predictions"
  on public.predictions;
create policy "Users can update their own predictions"
  on public.predictions
  for update
  to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );


-- =====================================================================
-- SOURCE: supabase/migrations/20260901120000_matchday_leaderboard.sql
-- =====================================================================

-- Matchday (and Knockout) presentation leaderboards.
--
-- Read-only reporting RPCs derived from existing scored predictions.
-- Does not change scoring, Golden Match, get_leaderboard(), tie-break
-- helpers, Cup awards, long-term awards, or badge award writes.
--
-- Matchday RANK() keys are live-safe and independent of the badge engine:
--   points desc, exact desc, correct desc, then RANK() ties share.
-- badge_matchday_player_stats.missed_count counts ALL matches in the matchday,
-- including still-open ones, so it is returned but must not break live ties.
-- Knockout ranking uses finished-only missed, matching get_leaderboard.
--
-- Do not db push. Do not apply remotely. Local migration only.

-- ---------------------------------------------------------------------------
-- League Phase matchday standings
-- ---------------------------------------------------------------------------

create or replace function public.get_matchday_leaderboard(p_matchday_id bigint)
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with league_matchday as (
    select matchday.id
    from public.matchdays as matchday
    where matchday.id = p_matchday_id
      and matchday.stage = 'league_phase'
  ),
  player_stats as (
    select
      stats.user_id,
      profile.username,
      stats.points as total_points,
      stats.exact_count as exact_scores,
      stats.correct_count as correct_results,
      stats.missed_count as missed_predictions
    from public.badge_matchday_player_stats(p_matchday_id) as stats
    join public.profiles as profile
      on profile.id = stats.user_id
    where exists (select 1 from league_matchday)
  ),
  ranked_players as (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc
      ) as rank_position,
      player_stats.user_id,
      player_stats.username,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.missed_predictions
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

comment on function public.get_matchday_leaderboard(bigint)
is 'League Phase matchday standings for active users. Points/exact/correct come from badge_matchday_player_stats (stored prediction.points, so Golden Match doubling is already included). Long-term awards, Cup honours, knockout/Final points and badges are excluded. Live RANK() keys: points, exact, correct. missed_predictions is returned from badge_matchday_player_stats but is not a rank key, because that helper counts every match in the matchday including still-open fixtures. Non-league_phase ids return no rows. Public columns: rank, user_id, username, and those aggregates only.';

revoke execute on function public.get_matchday_leaderboard(bigint)
  from public, anon;
grant execute on function public.get_matchday_leaderboard(bigint)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Knockout / Final presentation standings
-- ---------------------------------------------------------------------------

create or replace function public.get_knockout_leaderboard()
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with player_stats as (
    select
      profile.id as user_id,
      profile.username,
      coalesce(
        sum(prediction.points)
          filter (where matchday.stage <> 'league_phase'),
        0
      )::bigint as total_points,
      count(prediction.id)
        filter (
          where matchday.stage <> 'league_phase'
            and public.prediction_is_exact(prediction.points)
        )::bigint as exact_scores,
      count(prediction.id)
        filter (
          where matchday.stage <> 'league_phase'
            and public.prediction_is_correct(prediction.points)
        )::bigint as correct_results,
      (
        (
          select count(*)
          from public.matches as finished_match
          join public.matchdays as finished_matchday
            on finished_matchday.id = finished_match.matchday_id
          where finished_matchday.stage <> 'league_phase'
            and finished_match.status = 'finished'
        )
        - count(prediction.id)
          filter (
            where matchday.stage <> 'league_phase'
              and match_row.status = 'finished'
          )::bigint
      ) as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
    group by profile.id, profile.username
  ),
  ranked_players as (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc,
          player_stats.missed_predictions asc
      ) as rank_position,
      player_stats.user_id,
      player_stats.username,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.missed_predictions
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

comment on function public.get_knockout_leaderboard()
is 'Knockout/Final presentation standings for active users. total_points is the same knockout prediction sum as get_leaderboard().knockout_points. Exact/correct/missed are knockout/Final matches only. League Phase, long-term awards and Cup honours are excluded. RANK() keys: points, exact, correct, missed. get_leaderboard() is unchanged.';

revoke execute on function public.get_knockout_leaderboard()
  from public, anon;
grant execute on function public.get_knockout_leaderboard()
  to authenticated;
