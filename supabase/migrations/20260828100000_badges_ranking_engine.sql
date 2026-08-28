-- Badges Phase 3: ranking, Leader, League Phase, season and Players Cup awards.
--
-- Additive except for surgical replacements of:
--   public.recompute_matchday_badges(bigint)
--   public.set_match_result(bigint, integer, integer)
--   public.set_long_term_outcome(text, bigint)
--   public.recompute_players_cup()
-- Previous badge migrations are not edited. Profile UI is out of scope.
--
-- HOSTED DRIFT: hosted currently has the Phase 2 bodies of set_match_result
-- and recompute_matchday_badges, and the Phase 2A/long-term bodies of
-- set_long_term_outcome, recompute_players_cup and players_cup_apply. Compare
-- pg_get_functiondef of those five before a future apply. Do not db push.
-- players_cup_apply is intentionally not replaced; Cup badge sync runs from
-- recompute_ranking_badges after every write path that can change cup_awards.

-- ---------------------------------------------------------------------------
-- Matchday podium (extends Phase 2 recompute)
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
    'perfect_matchday',
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday'
  ];
  c_podium_badges constant text[] := array[
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday'
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
  ranked as (
    select
      stats.*,
      rank() over (
        order by
          stats.points desc,
          stats.exact_count desc,
          stats.correct_count desc,
          stats.missed_count asc
      ) as rank_position
    from stats
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
    union all
    select
      ranked.user_id,
      case ranked.rank_position
        when 1 then 'top_of_the_matchday'
        when 2 then 'second_of_the_matchday'
        when 3 then 'third_of_the_matchday'
      end,
      jsonb_build_object(
        'rank', ranked.rank_position,
        'points', ranked.points,
        'exact_count', ranked.exact_count,
        'correct_count', ranked.correct_count,
        'missed_count', ranked.missed_count
      )
    from ranked
    where ranked.rank_position in (1, 2, 3)
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
  do update
  set context = excluded.context
  where excluded.badge_code = any (c_podium_badges)
    and public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_matchday_badges(bigint)
is 'Idempotent Sharp Shooter / On Fire / Perfect Matchday / podium recompute for one UEFA matchday. Awards only when the matchday is complete. Invalid rows are deleted; rows that remain valid keep earned_at. Podium uses RANK() on points, exact, correct, fewer missed; shared ranks skip medals. Performance-badge conflict handling is still insert-only.';

-- ---------------------------------------------------------------------------
-- Leader
-- ---------------------------------------------------------------------------

create or replace function public.award_leader_if_applicable()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
begin
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
is 'Inserts Leader for every current get_leaderboard() rank 1. Never deletes. ON CONFLICT DO NOTHING preserves the first earned_at. Inactive users are absent from get_leaderboard so they cannot newly earn Leader.';

-- ---------------------------------------------------------------------------
-- Players Cup badge sync
-- ---------------------------------------------------------------------------

create or replace function public.sync_players_cup_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_cup_badges constant text[] := array[
    'players_cup_champion',
    'players_cup_finalist',
    'players_cup_semifinalist'
  ];
begin
  with qualifying as (
    select
      award.user_id,
      case award.award_type
        when 'winner' then 'players_cup_champion'
        when 'finalist' then 'players_cup_finalist'
        when 'semi_finalist' then 'players_cup_semifinalist'
      end as badge_code,
      award.cup_id,
      jsonb_build_object(
        'award_type', award.award_type,
        'points', award.points
      ) as context
    from public.cup_awards as award
    join public.cup_competitions as competition
      on competition.id = award.cup_id
    where competition.season_label = c_season_label
      and award.user_id is not null
      and award.award_type in ('winner', 'finalist', 'semi_finalist')
  ),
  removed as (
    delete from public.badge_awards as badge
    where badge.badge_code = any (c_cup_badges)
      and badge.award_scope = 'season'
      and badge.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = badge.user_id
          and qualifying.badge_code = badge.badge_code
      )
    returning badge.id
  )
  insert into public.badge_awards (
    user_id,
    badge_code,
    award_scope,
    season_label,
    cup_id,
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.cup_id,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set
    cup_id = excluded.cup_id,
    context = excluded.context
  where public.badge_awards.cup_id is distinct from excluded.cup_id
    or public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.sync_players_cup_badges()
is 'Mirrors persisted cup_awards into Players Cup badges for Champions League 2026/27. Does not inspect the bracket. Stale honours are deleted; unchanged honours keep earned_at. cup_awards rows with a null user_id are skipped.';

-- ---------------------------------------------------------------------------
-- League Phase completion and snapshot
-- ---------------------------------------------------------------------------

create or replace function public.badge_players_cup_is_complete()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.cup_competitions as competition
    where competition.slug = 'players-cup-2026-27'
      and competition.status = 'completed'
  );
$function$;

comment on function public.badge_players_cup_is_complete()
is 'True when the canonical Players Cup (slug players-cup-2026-27) exists and status is completed. That status is written by players_cup_apply only after the Final is decided and cup_awards are rebuilt.';

create or replace function public.badge_league_phase_is_complete()
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
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
    )
    and not exists (
      select 1
      from public.matches as match_row
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
        and match_row.status is distinct from 'finished'
    )
    and not exists (
      select 1
      from public.predictions as prediction
      join public.matches as match_row
        on match_row.id = prediction.match_id
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'league_phase'
        and prediction.points is null
    )
    and public.badge_players_cup_is_complete()
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'league_phase_first'
    );
$function$;

comment on function public.badge_league_phase_is_complete()
is 'League Phase badge gate: at least one LP match, every LP match finished, every LP prediction scored, canonical Players Cup completed, league_phase_first outcome decided. Ignores matchdays.status.';

create or replace function public.badge_league_phase_ranking_for(p_extra_user_ids uuid[])
returns table (
  user_id uuid,
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
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
      (
        coalesce(
          sum(prediction.points) filter (where matchday.stage = 'league_phase'),
          0
        )
        + coalesce((
          select sum(award.points)
          from public.long_term_awards as award
          where award.user_id = profile.id
            and award.prediction_type = 'league_phase_first'
        ), 0)
        + coalesce((
          select sum(cup_award.points)
          from public.cup_awards as cup_award
          where cup_award.user_id = profile.id
        ), 0)
      )::bigint as total_points,
      count(prediction.id)
        filter (
          where matchday.stage = 'league_phase'
            and public.prediction_is_exact(prediction.points)
        )::bigint as exact_scores,
      count(prediction.id)
        filter (
          where matchday.stage = 'league_phase'
            and public.prediction_is_correct(prediction.points)
        )::bigint as correct_results,
      (
        (
          select count(*)
          from public.matches as finished_match
          join public.matchdays as finished_matchday
            on finished_matchday.id = finished_match.matchday_id
          where finished_matchday.stage = 'league_phase'
            and finished_match.status = 'finished'
        )
        - count(prediction.id)
          filter (
            where matchday.stage = 'league_phase'
              and match_row.status = 'finished'
          )::bigint
      ) as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      or profile.id = any (coalesce(p_extra_user_ids, '{}'::uuid[]))
    group by profile.id
  )
  select
    ranked.user_id,
    ranked.rank_position,
    ranked.total_points,
    ranked.exact_scores,
    ranked.correct_results,
    ranked.missed_predictions
  from (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc,
          player_stats.missed_predictions asc
      ) as rank_position,
      player_stats.user_id,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.missed_predictions
    from player_stats
  ) as ranked;
$function$;

comment on function public.badge_league_phase_ranking_for(uuid[])
is 'League Phase ranking for active users plus optional extra user ids. Extra ids exist so already-earned inactive holders can be revalidated after a data correction without letting them newly earn badges.';

create or replace function public.badge_league_phase_ranking()
returns table (
  user_id uuid,
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    standing.user_id,
    standing.rank_position,
    standing.total_points,
    standing.exact_scores,
    standing.correct_results,
    standing.missed_predictions
  from public.badge_league_phase_ranking_for('{}'::uuid[]) as standing;
$function$;

comment on function public.badge_league_phase_ranking()
is 'Player-game ranking at League Phase end for active users: LP prediction points plus persisted cup_awards plus league_phase_first long-term awards. Excludes knockout/Final prediction points and the winner +30. exact/correct/missed are LP-only. get_leaderboard knockout_points is inapplicable here (always conceptually 0) so the remaining RANK() keys match overall standings.';

create or replace function public.recompute_league_phase_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_lp_badges constant text[] := array[
    'league_phase_champion',
    'league_phase_runner_up'
  ];
  v_holders uuid[];
begin
  if not public.badge_league_phase_is_complete() then
    delete from public.badge_awards as award
    where award.badge_code = any (c_lp_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label;
    return;
  end if;

  select coalesce(array_agg(distinct award.user_id), '{}'::uuid[])
  into v_holders
  from public.badge_awards as award
  where award.badge_code = any (c_lp_badges)
    and award.award_scope = 'season'
    and award.season_label = c_season_label;

  with ranking as (
    select *
    from public.badge_league_phase_ranking_for(v_holders) as standing
  ),
  qualifying as (
    select
      ranking.user_id,
      case ranking.rank_position
        when 1 then 'league_phase_champion'
        when 2 then 'league_phase_runner_up'
      end as badge_code,
      jsonb_build_object(
        'rank', ranking.rank_position,
        'total_points', ranking.total_points,
        'exact_scores', ranking.exact_scores,
        'correct_results', ranking.correct_results,
        'missed_predictions', ranking.missed_predictions
      ) as context
    from ranking
    where ranking.rank_position in (1, 2)
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = any (c_lp_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label
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
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  join public.profiles as profile
    on profile.id = qualifying.user_id
  where profile.status = 'active'
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set context = excluded.context
  where public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_league_phase_badges()
is 'Correction-safe League Phase Champion / Runner-up. Ranking set is active users plus existing holders, so inactivity alone does not revoke, but a score/outcome correction can. New awards insert only for active users. Shared RANK() 1 awards every co-leader and skips runner-up. Incomplete LP deletes both badges.';

-- ---------------------------------------------------------------------------
-- Season completion and ranking badges
-- ---------------------------------------------------------------------------

create or replace function public.badge_season_is_complete()
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
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where matchday.stage = 'final'
    )
    and not exists (
      select 1
      from public.matches as match_row
      where match_row.status is distinct from 'finished'
    )
    and not exists (
      select 1
      from public.predictions as prediction
      where prediction.points is null
    )
    and public.badge_players_cup_is_complete()
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'winner'
    )
    and exists (
      select 1
      from public.long_term_outcomes as outcome
      where outcome.prediction_type = 'league_phase_first'
    );
$function$;

comment on function public.badge_season_is_complete()
is 'Season badge gate: at least one Final match exists; every row currently in public.matches is finished; every prediction on those matches is scored; canonical Players Cup completed; winner and league_phase_first outcomes decided. Ignores matchdays.status and does not require nonexistent future matchdays.';

create or replace function public.badge_season_ranking_for(p_extra_user_ids uuid[])
returns table (
  user_id uuid,
  rank_position bigint,
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
        as missed_predictions
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    left join public.matches as match_row
      on match_row.id = prediction.match_id
    left join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      or profile.id = any (coalesce(p_extra_user_ids, '{}'::uuid[]))
    group by profile.id
  )
  select
    ranked.user_id,
    ranked.rank_position,
    ranked.total_points,
    ranked.exact_scores,
    ranked.correct_results,
    ranked.knockout_points,
    ranked.missed_predictions
  from (
    select
      rank() over (
        order by
          player_stats.total_points desc,
          player_stats.exact_scores desc,
          player_stats.correct_results desc,
          player_stats.knockout_points desc,
          player_stats.missed_predictions asc
      ) as rank_position,
      player_stats.user_id,
      player_stats.total_points,
      player_stats.exact_scores,
      player_stats.correct_results,
      player_stats.knockout_points,
      player_stats.missed_predictions
    from player_stats
  ) as ranked;
$function$;

comment on function public.badge_season_ranking_for(uuid[])
is 'Overall ranking identical to get_leaderboard() keys, for active users plus optional extra user ids. Extra ids revalidate already-earned inactive holders after a data correction. get_leaderboard() itself is unchanged.';

create or replace function public.recompute_season_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_season_badges constant text[] := array[
    'season_champion',
    'season_runner_up',
    'season_top_5'
  ];
  v_holders uuid[];
begin
  if not public.badge_season_is_complete() then
    delete from public.badge_awards as award
    where award.badge_code = any (c_season_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label;
    return;
  end if;

  select coalesce(array_agg(distinct award.user_id), '{}'::uuid[])
  into v_holders
  from public.badge_awards as award
  where award.badge_code = any (c_season_badges)
    and award.award_scope = 'season'
    and award.season_label = c_season_label;

  with ranking as (
    select *
    from public.badge_season_ranking_for(v_holders) as standing
  ),
  qualifying as (
    select
      ranking.user_id,
      case
        when ranking.rank_position = 1 then 'season_champion'
        when ranking.rank_position = 2 then 'season_runner_up'
        when ranking.rank_position in (3, 4, 5) then 'season_top_5'
      end as badge_code,
      jsonb_build_object(
        'rank', ranking.rank_position,
        'total_points', ranking.total_points,
        'exact_scores', ranking.exact_scores,
        'correct_results', ranking.correct_results,
        'knockout_points', ranking.knockout_points,
        'missed_predictions', ranking.missed_predictions
      ) as context
    from ranking
    where ranking.rank_position in (1, 2, 3, 4, 5)
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = any (c_season_badges)
      and award.award_scope = 'season'
      and award.season_label = c_season_label
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
    context
  )
  select
    qualifying.user_id,
    qualifying.badge_code,
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  join public.profiles as profile
    on profile.id = qualifying.user_id
  where profile.status = 'active'
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do update
  set context = excluded.context
  where public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_season_badges()
is 'Correction-safe Season Champion / Runner-up / Top 5. Ranking set is active users plus existing holders, so inactivity alone does not revoke, but a score/outcome correction can. New awards insert only for active users. Shared RANK() values are used as-is; Top 5 is only ranks 3/4/5. Incomplete season deletes all three. Point keys match get_leaderboard(); get_leaderboard() itself is unchanged.';

-- ---------------------------------------------------------------------------
-- Orchestrator
-- ---------------------------------------------------------------------------

create or replace function public.recompute_ranking_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.award_leader_if_applicable();
  perform public.recompute_league_phase_badges();
  perform public.recompute_season_badges();
  perform public.sync_players_cup_badges();
end;
$function$;

comment on function public.recompute_ranking_badges()
is 'Leader insert, League Phase recompute, season recompute and Players Cup badge sync. Ranking functions read cup_awards / predictions / long_term_awards, never Cup badge rows, so Cup sync can stay last. Does not walk every matchday podium; that stays on recompute_matchday_badges.';

-- ---------------------------------------------------------------------------
-- set_match_result: Phase 2 body plus ranking orchestrator
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
  perform public.recompute_ranking_badges();

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
is 'Admin-only result entry with deterministic idempotent 90-minute scoring: normal 5/2/0, selected Golden Match 10/4/0, Final 10/4/0. Final and Golden Match never stack. A result belonging to a Players Cup round also freezes any crossed postponed-match cutoff and recomputes the Cup in the same transaction. After points are final, matchday, cumulative and ranking badge awards are recomputed in the same transaction.';

-- ---------------------------------------------------------------------------
-- set_long_term_outcome: existing semantics plus ranking recompute
-- ---------------------------------------------------------------------------

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

  perform public.recompute_ranking_badges();

  return query
  select
    p_prediction_type,
    p_team_id,
    v_outcome_changed,
    v_scored_predictions,
    v_changed_awards;
end;
$function$;

comment on function public.set_long_term_outcome(text, bigint)
is 'Admin-only long-term outcome entry. After awards are written, ranking badges (Leader, League Phase, season, Players Cup sync) are recomputed in the same transaction.';

-- ---------------------------------------------------------------------------
-- recompute_players_cup: existing apply plus ranking orchestrator
-- ---------------------------------------------------------------------------

create or replace function public.recompute_players_cup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  v_cup_id bigint;
  v_summary jsonb;
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

  -- Taken before any row lock. Phase 2B must use the same order inside
  -- set_match_result, otherwise two admins scoring two matches can deadlock.
  perform pg_advisory_xact_lock(public.players_cup_lock_key());

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug;

  -- No draw yet is a normal state, not an error.
  if v_cup_id is null then
    perform public.recompute_ranking_badges();
    return jsonb_build_object(
      'cup_exists', false,
      'slug', c_slug,
      'recomputed_at', now()
    );
  end if;

  v_summary := public.players_cup_apply(v_cup_id)
    || jsonb_build_object('cup_exists', true);
  perform public.recompute_ranking_badges();
  return v_summary;
end;
$function$;

comment on function public.recompute_players_cup()
is 'Admin-only Players Cup recalculation. Recomputes every derived value from the current football results, then syncs ranking badges. Returns a summary instead of raising when no Cup has been drawn yet.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function public.set_match_result(bigint, integer, integer)
  from public, anon;
grant execute on function public.set_match_result(bigint, integer, integer)
  to authenticated, service_role;

revoke execute on function public.set_long_term_outcome(text, bigint)
  from public, anon;
grant execute on function public.set_long_term_outcome(text, bigint)
  to authenticated, service_role;

revoke execute on function public.recompute_players_cup()
  from public, anon;
grant execute on function public.recompute_players_cup()
  to authenticated, service_role;

revoke execute on function public.recompute_matchday_badges(bigint)
  from public, anon, authenticated;
grant execute on function public.recompute_matchday_badges(bigint)
  to service_role;

revoke execute on function public.award_leader_if_applicable()
  from public, anon, authenticated;
grant execute on function public.award_leader_if_applicable()
  to service_role;

revoke execute on function public.sync_players_cup_badges()
  from public, anon, authenticated;
grant execute on function public.sync_players_cup_badges()
  to service_role;

revoke execute on function public.badge_players_cup_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_players_cup_is_complete()
  to service_role;

revoke execute on function public.badge_league_phase_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_is_complete()
  to service_role;

revoke execute on function public.badge_league_phase_ranking()
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_ranking()
  to service_role;

revoke execute on function public.badge_league_phase_ranking_for(uuid[])
  from public, anon, authenticated;
grant execute on function public.badge_league_phase_ranking_for(uuid[])
  to service_role;

revoke execute on function public.badge_season_ranking_for(uuid[])
  from public, anon, authenticated;
grant execute on function public.badge_season_ranking_for(uuid[])
  to service_role;

revoke execute on function public.recompute_league_phase_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_league_phase_badges()
  to service_role;

revoke execute on function public.badge_season_is_complete()
  from public, anon, authenticated;
grant execute on function public.badge_season_is_complete()
  to service_role;

revoke execute on function public.recompute_season_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_season_badges()
  to service_role;

revoke execute on function public.recompute_ranking_badges()
  from public, anon, authenticated;
grant execute on function public.recompute_ranking_badges()
  to service_role;
