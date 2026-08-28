-- Leader eligibility: first League Phase matchday must be complete.
--
-- Additive. Replaces only public.award_leader_if_applicable().
-- Previous badge migrations are not edited. No backfill is executed.

create or replace function public.award_leader_if_applicable()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  v_matchday_1_count integer;
  v_matchday_1_id bigint;
begin
  select count(*)
  into v_matchday_1_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 1;

  if v_matchday_1_count is distinct from 1 then
    return;
  end if;

  select matchday.id
  into v_matchday_1_id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 1;

  if not public.badge_matchday_is_complete(v_matchday_1_id) then
    return;
  end if;

  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    context
  )
  select
    standing.user_id,
    'leader',
    'season',
    c_season_label,
    jsonb_build_object(
      'rank', standing.rank_position,
      'total_points', standing.total_points,
      'exact_scores', standing.exact_scores,
      'correct_results', standing.correct_results,
      'knockout_points', standing.knockout_points,
      'missed_predictions', standing.missed_predictions
    )
  from public.get_leaderboard() as standing
  where standing.rank_position = 1
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;
end;
$function$;

comment on function public.award_leader_if_applicable()
is 'Inserts Leader for every current get_leaderboard() rank 1 after the unique League Phase Matchday 1 is complete (badge_matchday_is_complete). Missing or ambiguous Matchday 1, or an incomplete Matchday 1, awards nothing. Never deletes. ON CONFLICT DO NOTHING preserves the first earned_at. Inactive users are absent from get_leaderboard so they cannot newly earn Leader.';
