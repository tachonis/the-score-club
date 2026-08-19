-- Secure Golden Match selection and deterministic doubled scoring.
-- Existing predictions keep their normal 5/2/0 scoring unless they are
-- referenced by a Golden Match selection.

create unique index if not exists matches_id_matchday_id_uidx
  on public.matches (id, matchday_id);

create table public.golden_match_selections (
  id bigint generated always as identity primary key,
  user_id uuid not null
    constraint golden_match_selections_user_id_fkey
    references auth.users (id) on delete cascade,
  matchday_id bigint not null,
  match_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint golden_match_selections_user_matchday_key
    unique (user_id, matchday_id),
  constraint golden_match_selections_match_matchday_fkey
    foreign key (match_id, matchday_id)
    references public.matches (id, matchday_id)
    on update cascade
    on delete cascade
);

create index golden_match_selections_match_id_idx
  on public.golden_match_selections (match_id);

alter table public.golden_match_selections enable row level security;

create policy "Users can view their own Golden Match selections"
  on public.golden_match_selections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all privileges on table public.golden_match_selections
  from public, anon, authenticated;
grant select on table public.golden_match_selections
  to authenticated;
grant all privileges on table public.golden_match_selections
  to service_role;

revoke all privileges on sequence public.golden_match_selections_id_seq
  from public, anon, authenticated;
grant all privileges on sequence public.golden_match_selections_id_seq
  to service_role;

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
    matchday.matchday_number,
    match_row.kickoff_at,
    match_row.status
  into
    v_matchday_id,
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
is 'Selects or replaces the caller own Golden Match before kickoff. One selection per matchday, available from Matchday 2.';

revoke execute on function public.set_golden_match(bigint)
  from public, anon;
grant execute on function public.set_golden_match(bigint)
  to authenticated, service_role;

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
is 'Admin-only result entry with deterministic idempotent scoring: normal 5/2/0 and selected Golden Match 10/4/0.';

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;
