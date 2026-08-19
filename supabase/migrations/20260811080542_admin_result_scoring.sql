-- Secure, deterministic normal-time result scoring.
-- Existing rows are not changed by this migration.

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
      from public.profiles
      where id = (select auth.uid())
        and role = 'admin'
        and status = 'active'
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

  select m.home_score, m.away_score, m.status
  into v_current_home_score, v_current_away_score, v_current_status
  from public.matches as m
  where m.id = p_match_id
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
    update public.matches as m
    set
      home_score = p_home_score,
      away_score = p_away_score,
      status = 'finished',
      updated_at = now()
    where m.id = p_match_id;
  end if;

  with calculated_points as (
    select
      pr.id,
      case
        when pr.predicted_home_score = p_home_score
          and pr.predicted_away_score = p_away_score
          then 5
        when (
          pr.predicted_home_score > pr.predicted_away_score
          and p_home_score > p_away_score
        ) or (
          pr.predicted_home_score = pr.predicted_away_score
          and p_home_score = p_away_score
        ) or (
          pr.predicted_home_score < pr.predicted_away_score
          and p_home_score < p_away_score
        )
          then 2
        else 0
      end as new_points
    from public.predictions as pr
    where pr.match_id = p_match_id
  ),
  updated_predictions as (
    update public.predictions as pr
    set
      points = calculated_points.new_points,
      updated_at = now()
    from calculated_points
    where pr.id = calculated_points.id
      and pr.points is distinct from calculated_points.new_points
    returning pr.id
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
is 'Admin-only result entry and idempotent normal scoring. Extend the isolated CASE expression for future match-level multipliers.';

-- Result fields are writable only through set_match_result().
revoke insert, update on table public.matches from authenticated;

grant insert (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  updated_at
) on table public.matches to authenticated;

grant update (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  updated_at
) on table public.matches to authenticated;

-- The browser may invoke the RPC, but the function itself rejects every
-- caller who is not an active admin.
revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;
