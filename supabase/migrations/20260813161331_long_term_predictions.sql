create table public.long_term_predictions (
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  prediction_type text not null
    check (prediction_type in ('winner', 'league_phase_first')),
  team_id bigint not null
    references public.teams(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, prediction_type)
);

create index long_term_predictions_team_id_idx
  on public.long_term_predictions (team_id);

create table public.long_term_outcomes (
  prediction_type text primary key
    check (prediction_type in ('winner', 'league_phase_first')),
  team_id bigint not null
    references public.teams(id) on delete restrict,
  decided_by uuid not null
    references public.profiles(id) on delete restrict,
  decided_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index long_term_outcomes_team_id_idx
  on public.long_term_outcomes (team_id);

create table public.long_term_awards (
  user_id uuid not null,
  prediction_type text not null,
  predicted_team_id bigint not null
    references public.teams(id) on delete restrict,
  outcome_team_id bigint not null
    references public.teams(id) on delete restrict,
  points integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, prediction_type),
  foreign key (user_id, prediction_type)
    references public.long_term_predictions(user_id, prediction_type)
    on delete cascade,
  check (
    (prediction_type = 'winner' and points in (0, 30))
    or
    (prediction_type = 'league_phase_first' and points in (0, 15))
  )
);

create index long_term_awards_predicted_team_id_idx
  on public.long_term_awards (predicted_team_id);

create index long_term_awards_outcome_team_id_idx
  on public.long_term_awards (outcome_team_id);

alter table public.long_term_predictions enable row level security;
alter table public.long_term_outcomes enable row level security;
alter table public.long_term_awards enable row level security;

create policy "Players can read own long-term predictions"
on public.long_term_predictions
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Authenticated users can read long-term outcomes"
on public.long_term_outcomes
for select
to authenticated
using (true);

create policy "Players can read own long-term awards"
on public.long_term_awards
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.long_term_predictions
  from public, anon, authenticated;
revoke all on table public.long_term_outcomes
  from public, anon, authenticated;
revoke all on table public.long_term_awards
  from public, anon, authenticated;

grant select on table public.long_term_predictions to authenticated;
grant select on table public.long_term_outcomes to authenticated;
grant select on table public.long_term_awards to authenticated;

grant select, insert, update, delete
  on table public.long_term_predictions to service_role;
grant select, insert, update, delete
  on table public.long_term_outcomes to service_role;
grant select, insert, update, delete
  on table public.long_term_awards to service_role;

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
      state.configured_count <> 1
      or state.match_count = 0
      or state.finished_count = state.match_count
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
  v_matchday_name text;
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

  select
    count(*),
    min(matchday.id),
    min(matchday.name)
  into
    v_matchday_count,
    v_matchday_id,
    v_matchday_name
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

  if v_finished_count = v_match_count then
    raise exception using
      errcode = '22023',
      message = 'Long-term predictions are locked after Matchday 3';
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
  on conflict (user_id, prediction_type) do update
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
    on conflict (prediction_type) do update
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
    on conflict (user_id, prediction_type) do update
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
      )::bigint as total_points,
      count(prediction.id)
        filter (where prediction.points in (5, 10))::bigint
        as exact_scores,
      count(prediction.id)
        filter (where prediction.points in (2, 4))::bigint
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

revoke execute on function
  public.get_long_term_prediction_status()
  from public, anon;
revoke execute on function
  public.set_long_term_prediction(text, bigint)
  from public, anon;
revoke execute on function
  public.set_long_term_outcome(text, bigint)
  from public, anon;

grant execute on function
  public.get_long_term_prediction_status()
  to authenticated, service_role;
grant execute on function
  public.set_long_term_prediction(text, bigint)
  to authenticated, service_role;
grant execute on function
  public.set_long_term_outcome(text, bigint)
  to authenticated, service_role;