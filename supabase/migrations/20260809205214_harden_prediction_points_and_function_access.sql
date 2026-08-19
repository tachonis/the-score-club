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
