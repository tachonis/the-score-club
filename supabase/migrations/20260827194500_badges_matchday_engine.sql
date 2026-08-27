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
