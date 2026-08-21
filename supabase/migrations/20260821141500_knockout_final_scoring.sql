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
