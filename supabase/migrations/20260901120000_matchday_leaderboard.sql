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
