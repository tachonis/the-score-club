-- Snapshot of public game data into schema prelaunch_backup_20260829.
-- Documents the hosted operation named prelaunch_game_data_backup_20260829.
--
-- Does not modify public data, profiles, auth, push subscriptions, or
-- badge_definitions. Do not db push. Do not repair migration history.
-- Do not apply against hosted Supabase; production already has this schema.

do $$
begin
  if exists (
    select 1
    from pg_namespace
    where nspname = 'prelaunch_backup_20260829'
  ) then
    raise exception
      'Schema prelaunch_backup_20260829 already exists; refusing to overwrite the pre-import backup.';
  end if;
end $$;

create schema prelaunch_backup_20260829;

comment on schema prelaunch_backup_20260829 is
  'Read-only snapshot of The Score Club game data taken 2026-08-29 before the official 2026/27 League Phase import. Public rows were not changed by this migration.';

create table prelaunch_backup_20260829.teams as
  table public.teams;

create table prelaunch_backup_20260829.matchdays as
  table public.matchdays;

create table prelaunch_backup_20260829.matches as
  table public.matches;

create table prelaunch_backup_20260829.predictions as
  table public.predictions;

create table prelaunch_backup_20260829.golden_match_selections as
  table public.golden_match_selections;

create table prelaunch_backup_20260829.long_term_predictions as
  table public.long_term_predictions;

create table prelaunch_backup_20260829.long_term_outcomes as
  table public.long_term_outcomes;

create table prelaunch_backup_20260829.long_term_awards as
  table public.long_term_awards;

create table prelaunch_backup_20260829.badge_awards as
  table public.badge_awards;

create table prelaunch_backup_20260829.cup_competitions as
  table public.cup_competitions;

create table prelaunch_backup_20260829.cup_participants as
  table public.cup_participants;

create table prelaunch_backup_20260829.cup_rounds as
  table public.cup_rounds;

create table prelaunch_backup_20260829.cup_ties as
  table public.cup_ties;

create table prelaunch_backup_20260829.cup_awards as
  table public.cup_awards;

create table prelaunch_backup_20260829.cup_excluded_matches as
  table public.cup_excluded_matches;

-- public.league_phase_standings is a VIEW. Snapshot its current result
-- into a table; do not DELETE FROM or INSERT INTO the view.
create table prelaunch_backup_20260829.league_phase_standings as
  select *
  from public.league_phase_standings;
