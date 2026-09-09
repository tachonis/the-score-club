-- Player profile prediction history.
--
-- Read-only RPC over the existing scored predictions. Does not change
-- scoring, Golden Match writes, reveal-after-kickoff policies, or
-- leaderboard logic. Rows are returned only for finished matches that
-- already have an official admin score and stored points.
--
-- SECURITY INVOKER keeps RLS as the boundary: other players still cannot
-- read upcoming rows, and disabled owners stay hidden from others via the
-- existing prediction policies. This function additionally excludes
-- live/in-progress and unfinished matches so a manual call cannot use
-- it as a live-prediction feed.
--
-- Do not db push from this file. Do not repair migration history.
-- Apply to hosted Supabase only after review.

create or replace function public.get_player_prediction_history(
  p_user_id uuid
)
returns table (
  match_id bigint,
  matchday_id bigint,
  matchday_stage text,
  matchday_number integer,
  matchday_name text,
  kickoff_at timestamptz,
  home_team_name text,
  home_team_short_name text,
  away_team_name text,
  away_team_short_name text,
  home_score integer,
  away_score integer,
  predicted_home_score integer,
  predicted_away_score integer,
  points integer,
  is_golden_match boolean
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select
    match_row.id as match_id,
    matchday.id as matchday_id,
    matchday.stage as matchday_stage,
    matchday.matchday_number,
    matchday.name as matchday_name,
    match_row.kickoff_at,
    home_team.name as home_team_name,
    home_team.short_name as home_team_short_name,
    away_team.name as away_team_name,
    away_team.short_name as away_team_short_name,
    match_row.home_score,
    match_row.away_score,
    prediction.predicted_home_score,
    prediction.predicted_away_score,
    prediction.points,
    exists (
      select 1
      from public.golden_match_selections as golden
      where golden.user_id = prediction.user_id
        and golden.match_id = prediction.match_id
    ) as is_golden_match
  from public.predictions as prediction
  inner join public.matches as match_row
    on match_row.id = prediction.match_id
  inner join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  inner join public.teams as home_team
    on home_team.id = match_row.home_team_id
  inner join public.teams as away_team
    on away_team.id = match_row.away_team_id
  where p_user_id is not null
    and prediction.user_id = p_user_id
    and prediction.points is not null
    and match_row.status = 'finished'
    and match_row.home_score is not null
    and match_row.away_score is not null
  order by
    match_row.kickoff_at desc,
    match_row.id desc;
$function$;

comment on function public.get_player_prediction_history(uuid)
is 'Completed prediction history for one player. Finished matches with an official score and stored points only. SECURITY INVOKER: RLS still hides other users'' unrevealed rows and disabled owners from others. Does not change scoring or Golden Match writes.';

revoke execute on function public.get_player_prediction_history(uuid)
  from public, anon;
grant execute on function public.get_player_prediction_history(uuid)
  to authenticated, service_role;
