-- Badges Phase 5: backfill / recovery tooling.
--
-- Additive. Previous badge migrations are not edited.
-- Creates the master recompute and an admin-only recovery RPC.
-- Does NOT execute a backfill. Operators run admin_recompute_badges()
-- (or service_role recompute_all_badges()) after hosted apply.

-- ---------------------------------------------------------------------------
-- Internal master recompute
-- ---------------------------------------------------------------------------

create or replace function public.recompute_all_badges()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_matchday_id bigint;
  v_matchdays_processed integer := 0;
  v_complete_matchdays integer := 0;
  v_award_count_before bigint;
  v_award_count_after bigint;
  v_leader_count bigint;
begin
  select count(*)
  into v_award_count_before
  from public.badge_awards;

  for v_matchday_id in
    select distinct match_row.matchday_id
    from public.matches as match_row
    order by match_row.matchday_id
  loop
    perform public.recompute_matchday_badges(v_matchday_id);
    v_matchdays_processed := v_matchdays_processed + 1;

    if public.badge_matchday_is_complete(v_matchday_id) then
      v_complete_matchdays := v_complete_matchdays + 1;
    end if;
  end loop;

  perform public.recompute_cumulative_badges();
  perform public.recompute_ranking_badges();

  select count(*)
  into v_award_count_after
  from public.badge_awards;

  select count(*)
  into v_leader_count
  from public.badge_awards as award
  where award.badge_code = 'leader';

  return jsonb_build_object(
    'matchdays_processed', v_matchdays_processed,
    'complete_matchdays', v_complete_matchdays,
    'award_count_before', v_award_count_before,
    'award_count_after', v_award_count_after,
    'leader_count', v_leader_count,
    'recomputed_at', now()
  );
end;
$function$;

comment on function public.recompute_all_badges()
is 'Internal badge rebuild from current persisted data. Walks every matchday that currently has matches (not matchdays.status), then cumulative, then ranking (Leader insert-only, LP, season, Cup mirror). Does not fabricate historical Leaders. Not invoked by this migration.';

-- ---------------------------------------------------------------------------
-- Admin recovery wrapper
-- ---------------------------------------------------------------------------

create or replace function public.admin_recompute_badges()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

  return public.recompute_all_badges();
end;
$function$;

comment on function public.admin_recompute_badges()
is 'Active-admin recovery RPC. Rebuilds badge_awards from current persisted data via recompute_all_badges. Not a player self-service. Same authorization style as set_match_result / recompute_players_cup.';

revoke execute on function public.recompute_all_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_all_badges()
  to service_role;

revoke execute on function public.admin_recompute_badges()
  from public, anon;
grant execute on function public.admin_recompute_badges()
  to authenticated, service_role;
