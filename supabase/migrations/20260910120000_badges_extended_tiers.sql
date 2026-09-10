-- Badges extended tiers: Blazing, Inferno, Deadeye, Exact Master,
-- Exact Legend, Matchday Monster.
--
-- Additive except for surgical replacements of:
--   public.recompute_matchday_badges(bigint)
--   public.recompute_cumulative_badges()
-- Previous badge migrations are not edited. Thresholds of the original 17
-- badges are unchanged. Tiers are cumulative, not mutually exclusive.
--
-- Backfill is not executed here. Operators run admin_recompute_badges()
-- (or service_role recompute_all_badges()) after hosted apply. Incomplete
-- matchdays still cannot receive matchday/ranking badges.
--
-- HOSTED DRIFT: hosted currently has the Phase 3 body of
-- recompute_matchday_badges and the Phase 2 body of
-- recompute_cumulative_badges. Compare pg_get_functiondef before apply.
-- Do not db push.

insert into public.badge_definitions (
  code,
  title,
  description,
  image_path,
  repeatable,
  category,
  sort_order
)
values
  (
    'blazing',
    'Blazing',
    'Συγκέντρωσες 30 ή περισσότερους βαθμούς σε μία αγωνιστική.',
    '/badges/blazing.png',
    true,
    'performance',
    49
  ),
  (
    'inferno',
    'Inferno',
    'Συγκέντρωσες 40 ή περισσότερους βαθμούς σε μία αγωνιστική.',
    '/badges/inferno.png',
    true,
    'performance',
    50
  ),
  (
    'deadeye',
    'Deadeye',
    'Πέτυχες 5 ακριβή σκορ στην ίδια αγωνιστική.',
    '/badges/deadeye.png',
    true,
    'performance',
    51
  ),
  (
    'exact_master',
    'Exact Master',
    'Πέτυχες 20 ακριβή σκορ συνολικά στη σεζόν.',
    '/badges/exact-master.png',
    false,
    'performance',
    52
  ),
  (
    'exact_legend',
    'Exact Legend',
    'Πέτυχες 30 ακριβή σκορ συνολικά στη σεζόν.',
    '/badges/exact-legend.png',
    false,
    'performance',
    53
  ),
  (
    'matchday_monster',
    'Matchday Monster',
    'Τερμάτισες 1ος σε μία αγωνιστική συγκεντρώνοντας τουλάχιστον 30 βαθμούς.',
    '/badges/matchday-monster.png',
    true,
    'matchday',
    54
  )
on conflict (code) do update
set
  title = excluded.title,
  description = excluded.description,
  image_path = excluded.image_path,
  repeatable = excluded.repeatable,
  category = excluded.category,
  sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Matchday engine: Phase 3 body plus cumulative performance / monster tiers
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
    'blazing',
    'inferno',
    'deadeye',
    'perfect_matchday',
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday',
    'matchday_monster'
  ];
  c_context_update_badges constant text[] := array[
    'top_of_the_matchday',
    'second_of_the_matchday',
    'third_of_the_matchday',
    'matchday_monster'
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
      'deadeye',
      jsonb_build_object('exact_count', stats.exact_count)
    from stats
    where stats.exact_count >= 5
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
      'blazing',
      jsonb_build_object('points', stats.points)
    from stats
    where stats.points >= 30
    union all
    select
      stats.user_id,
      'inferno',
      jsonb_build_object('points', stats.points)
    from stats
    where stats.points >= 40
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
    union all
    select
      ranked.user_id,
      'matchday_monster',
      jsonb_build_object(
        'rank', ranked.rank_position,
        'points', ranked.points,
        'exact_count', ranked.exact_count,
        'correct_count', ranked.correct_count,
        'missed_count', ranked.missed_count
      )
    from ranked
    where ranked.rank_position = 1
      and ranked.points >= 30
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
  where excluded.badge_code = any (c_context_update_badges)
    and public.badge_awards.context is distinct from excluded.context;
end;
$function$;

comment on function public.recompute_matchday_badges(bigint)
is 'Idempotent Sharp Shooter / Deadeye / On Fire / Blazing / Inferno / Perfect Matchday / podium / Matchday Monster recompute for one UEFA matchday. Awards only when the matchday is complete. Invalid rows are deleted; rows that remain valid keep earned_at. Podium and Matchday Monster use RANK() on points, exact, correct, fewer missed; shared ranks skip medals. Performance-badge conflict handling is still insert-only.';

-- ---------------------------------------------------------------------------
-- Cumulative unique awards: Exact Machine plus Master / Legend
-- ---------------------------------------------------------------------------

create or replace function public.recompute_cumulative_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_season_label constant text := 'Champions League 2026/27';
  c_exact_badges constant text[] := array[
    'exact_machine',
    'exact_master',
    'exact_legend'
  ];
begin
  with exact_counts as (
    select
      profile.id as user_id,
      count(prediction.id)
        filter (where public.prediction_is_exact(prediction.points))::bigint
        as exact_count
    from public.profiles as profile
    left join public.predictions as prediction
      on prediction.user_id = profile.id
    where profile.status = 'active'
    group by profile.id
  ),
  qualifying as (
    select
      exact_counts.user_id,
      'exact_machine'::text as badge_code,
      jsonb_build_object('exact_count', exact_counts.exact_count) as context
    from exact_counts
    where exact_counts.exact_count >= 10
    union all
    select
      exact_counts.user_id,
      'exact_master',
      jsonb_build_object('exact_count', exact_counts.exact_count)
    from exact_counts
    where exact_counts.exact_count >= 20
    union all
    select
      exact_counts.user_id,
      'exact_legend',
      jsonb_build_object('exact_count', exact_counts.exact_count)
    from exact_counts
    where exact_counts.exact_count >= 30
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = any (c_exact_badges)
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
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;

  with qualifying as (
    select distinct on (profile.id)
      profile.id as user_id,
      jsonb_build_object(
        'match_id', match_row.id,
        'matchday_id', match_row.matchday_id
      ) as context
    from public.profiles as profile
    join public.predictions as prediction
      on prediction.user_id = profile.id
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where profile.status = 'active'
      and matchday.stage = 'final'
      and match_row.status = 'finished'
      and public.prediction_is_exact(prediction.points)
    order by profile.id, match_row.id
  ),
  removed as (
    delete from public.badge_awards as award
    where award.badge_code = 'final_boss'
      and award.award_scope = 'season'
      and award.season_label = c_season_label
      and not exists (
        select 1
        from qualifying
        where qualifying.user_id = award.user_id
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
    'final_boss',
    'season',
    c_season_label,
    qualifying.context
  from qualifying
  on conflict (user_id, badge_code, season_label)
    where award_scope = 'season'
  do nothing;
end;
$function$;

comment on function public.recompute_cumulative_badges()
is 'Idempotent Exact Machine / Exact Master / Exact Legend and Final Boss recompute for Champions League 2026/27. Exact tiers use prediction_is_exact across all scored predictions and are cumulative (10 / 20 / 30). Final Boss requires matchdays.stage = final and an exact prediction, never points = 10 alone. Invalid rows are deleted; remaining rows keep earned_at.';
