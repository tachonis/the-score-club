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
