create or replace function public.set_long_term_outcome(
  p_prediction_type text,
  p_team_id bigint
)
returns table (
  prediction_type text,
  team_id bigint,
  outcome_changed boolean,
  scored_predictions bigint,
  changed_awards bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_matchday_id bigint;
  v_matchday_count bigint;
  v_match_count bigint;
  v_finished_count bigint;
  v_outcome_changed boolean;
  v_scored_predictions bigint;
  v_changed_awards bigint;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
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

  select count(*), min(matchday.id)
  into v_matchday_count, v_matchday_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_matchday_count <> 1 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 configuration is missing or ambiguous';
  end if;

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

  if v_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'Matchday 3 has no configured matches';
  end if;

  if v_finished_count <> v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term outcomes require completed Matchday 3';
  end if;

  with outcome_change as (
    insert into public.long_term_outcomes (
      prediction_type,
      team_id,
      decided_by
    )
    values (
      p_prediction_type,
      p_team_id,
      v_admin_id
    )
    on conflict on constraint long_term_outcomes_pkey do update
    set
      team_id = excluded.team_id,
      decided_by = excluded.decided_by,
      updated_at = now()
    where long_term_outcomes.team_id
      is distinct from excluded.team_id
    returning 1
  ),
  calculated_awards as (
    select
      selection.user_id,
      selection.prediction_type,
      selection.team_id as predicted_team_id,
      p_team_id as outcome_team_id,
      case
        when selection.team_id <> p_team_id then 0
        when p_prediction_type = 'winner' then 30
        when p_prediction_type = 'league_phase_first' then 15
        else 0
      end as points
    from public.long_term_predictions as selection
    where selection.prediction_type = p_prediction_type
  ),
  updated_awards as (
    insert into public.long_term_awards (
      user_id,
      prediction_type,
      predicted_team_id,
      outcome_team_id,
      points
    )
    select
      award.user_id,
      award.prediction_type,
      award.predicted_team_id,
      award.outcome_team_id,
      award.points
    from calculated_awards as award
    on conflict on constraint long_term_awards_pkey do update
    set
      predicted_team_id = excluded.predicted_team_id,
      outcome_team_id = excluded.outcome_team_id,
      points = excluded.points,
      updated_at = now()
    where long_term_awards.predicted_team_id
        is distinct from excluded.predicted_team_id
      or long_term_awards.outcome_team_id
        is distinct from excluded.outcome_team_id
      or long_term_awards.points
        is distinct from excluded.points
    returning 1
  )
  select
    exists (select 1 from outcome_change),
    (select count(*) from calculated_awards),
    (select count(*) from updated_awards)
  into
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;

  return query
  select
    p_prediction_type,
    p_team_id,
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;
end;
$function$;
