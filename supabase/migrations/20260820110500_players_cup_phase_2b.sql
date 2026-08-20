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
