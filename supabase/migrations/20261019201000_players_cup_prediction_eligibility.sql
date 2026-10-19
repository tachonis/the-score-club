-- Players Cup eligibility follows participation, not points.
--
-- An active player is in the Cup ranking only when they have at least one
-- prediction on a League Phase Matchday 1 or 2 match. A scored prediction of
-- 0 points still qualifies. Players with no prediction in those matchdays
-- are omitted, and rank_position is reassigned 1..N with no gap.
--
-- CREATE OR REPLACE keeps the existing execute grants: service_role only.
-- public, anon and authenticated stay revoked.

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
      and exists (
        select 1
        from ranking_predictions as qualifying_prediction
        where qualifying_prediction.user_id = profile.id
      )
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
is 'Strict Players Cup ranking from League Phase Matchday 1 and 2. Includes only active players with at least one prediction in those matchdays. Eligibility is participation, not points. Never includes long-term awards or Matchday 3+ results. Position 1 is the best ranking.';
