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
