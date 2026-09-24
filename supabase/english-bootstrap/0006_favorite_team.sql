-- =============================================================================
-- ENGLISH BOOTSTRAP — DO NOT APPLY TO GREEK PRODUCTION
-- =============================================================================
-- Equivalent of supabase/migrations/20260924140000_profile_favorite_team.sql.
-- Schema parity for a future English database only.
-- NEVER apply this file to www.thescoreclub.gr / project aoprkdbqtibsnlusbbpz.
-- NEVER apply it with an unscoped `supabase db push`.
-- =============================================================================

-- Favorite team on the player's own profile.
-- Additive. Does not rewrite history, seed teams, or open table-level UPDATE.

alter table public.profiles
  add column favorite_team_id bigint;

alter table public.profiles
  add constraint profiles_favorite_team_id_fkey
  foreign key (favorite_team_id)
  references public.teams (id)
  on delete set null;

create index profiles_favorite_team_id_idx
  on public.profiles (favorite_team_id);

comment on column public.profiles.favorite_team_id is
  'Optional favorite team. NULL means no favorite team. Colors are not stored.';

-- Table-level SELECT already exists for authenticated. Restate the new
-- column explicitly so the Data API does not depend on implicit exposure.
-- UPDATE stays column-scoped: username (already granted) and favorite_team_id.
grant select (favorite_team_id) on table public.profiles to authenticated;
grant update (favorite_team_id) on table public.profiles to authenticated;

grant select (favorite_team_id) on table public.profiles to service_role;
grant update (favorite_team_id) on table public.profiles to service_role;

-- Return type cannot change with CREATE OR REPLACE, and badge functions
-- depend on the existing function. Rename, create the additive shape, then
-- rebind the only direct caller so the previous body can be dropped.
alter function public.get_leaderboard()
  rename to get_leaderboard_before_favorite_team;

create function public.get_leaderboard()
returns table (
  rank_position bigint,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint,
  favorite_team_id bigint
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
        as missed_predictions,
      profile.favorite_team_id
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
    group by profile.id, profile.username, profile.favorite_team_id
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
      missed_predictions,
      favorite_team_id
    from player_stats
  )
  select *
  from ranked_players
  order by rank_position asc, username asc;
$function$;

comment on function public.get_leaderboard()
is 'Overall standings. total_points is prediction points plus long-term awards plus Players Cup honours; Cup matchday performance is already inside the prediction points and is never added twice. favorite_team_id is profile identity only and is not a ranking key.';

revoke execute on function public.get_leaderboard() from public, anon;
grant execute on function public.get_leaderboard() to authenticated, service_role;

-- Same body as 20260828140000. Replacing it moves the dependency onto the
-- new get_leaderboard() so the renamed copy can be removed.
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

revoke execute on function public.award_leader_if_applicable()
  from public, anon, authenticated;
grant execute on function public.award_leader_if_applicable()
  to service_role;

drop function public.get_leaderboard_before_favorite_team();
