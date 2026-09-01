-- =============================================================================
-- ENGLISH BOOTSTRAP — DO NOT APPLY TO GREEK PRODUCTION
-- =============================================================================
-- Target: a brand-new EMPTY English Supabase project only (the-score-club.com).
-- NEVER apply this file to www.thescoreclub.gr / project aoprkdbqtibsnlusbbpz.
-- NEVER copy Greek auth.users, profiles, predictions, Cup state, or badges earned.
-- NEVER replay documentary backup/import migrations from supabase/migrations/.
-- NEVER use unscoped `supabase db push`. When the English project exists, pass
-- an explicit English --project-ref.
-- This directory is outside supabase/migrations/ so the CLI will not auto-apply it.
-- =============================================================================
-- English badge_definitions seed.
-- Codes, English titles, image paths, repeatable flags, categories, sort_order,
-- and award criteria are unchanged. Descriptions are translated to English.
-- Apply AFTER 0001_schema.sql and 0002_official_seed.sql.
-- Does not insert badge_awards.

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
    'season_champion',
    'Season Champion',
    'You finished 1st in the overall season standings.',
    '/badges/season-champion.png',
    false,
    'season',
    1
  ),
  (
    'season_runner_up',
    'Season Runner-up',
    'You finished 2nd in the overall season standings.',
    '/badges/season-runner-up.png',
    false,
    'season',
    2
  ),
  (
    'season_top_5',
    'Season Top 5',
    'You finished 3rd to 5th in the overall season standings.',
    '/badges/season-top-5.png',
    false,
    'season',
    3
  ),
  (
    'league_phase_champion',
    'League Phase Champion',
    'You finished 1st after League Phase was completed.',
    '/badges/league-phase-champion.png',
    false,
    'league_phase',
    20
  ),
  (
    'league_phase_runner_up',
    'League Phase Runner-up',
    'You finished 2nd after League Phase was completed.',
    '/badges/league-phase-runner-up.png',
    false,
    'league_phase',
    21
  ),
  (
    'players_cup_champion',
    'Players Cup Champion',
    'You won the Players Cup.',
    '/badges/players-cup-champion.png',
    false,
    'players_cup',
    30
  ),
  (
    'players_cup_finalist',
    'Players Cup Finalist',
    'You reached the Players Cup Final.',
    '/badges/players-cup-finalist.png',
    false,
    'players_cup',
    31
  ),
  (
    'players_cup_semifinalist',
    'Players Cup Semifinalist',
    'You reached the Players Cup Semi-finals.',
    '/badges/players-cup-semifinalist.png',
    false,
    'players_cup',
    32
  ),
  (
    'exact_machine',
    'Exact Machine',
    'You scored 10 exact scores in total.',
    '/badges/exact-machine.png',
    false,
    'performance',
    40
  ),
  (
    'sharp_shooter',
    'Sharp Shooter',
    'You scored 3 exact scores in the same matchday.',
    '/badges/sharp-shooter.png',
    true,
    'performance',
    41
  ),
  (
    'on_fire',
    'On Fire',
    'You scored 20 or more points in a single matchday.',
    '/badges/on-fire.png',
    true,
    'performance',
    42
  ),
  (
    'top_of_the_matchday',
    'Top of the Matchday',
    'You finished 1st on a matchday.',
    '/badges/top-of-the-matchday.png',
    true,
    'matchday',
    43
  ),
  (
    'second_of_the_matchday',
    'Second of the Matchday',
    'You finished 2nd on a matchday.',
    '/badges/second-of-the-matchday.png',
    true,
    'matchday',
    44
  ),
  (
    'third_of_the_matchday',
    'Third of the Matchday',
    'You finished 3rd on a matchday.',
    '/badges/third-of-the-matchday.png',
    true,
    'matchday',
    45
  ),
  (
    'final_boss',
    'Final Boss',
    'You scored the exact score of the Final.',
    '/badges/final-boss.png',
    false,
    'performance',
    46
  ),
  (
    'perfect_matchday',
    'Perfect Matchday',
    'You got at least the correct result on every match of a matchday.',
    '/badges/perfect-matchday.png',
    true,
    'matchday',
    47
  ),
  (
    'leader',
    'Leader',
    'You reached 1st in the overall standings.',
    '/badges/leader.png',
    false,
    'performance',
    48
  )
on conflict (code) do update
set
  title = excluded.title,
  description = excluded.description,
  image_path = excluded.image_path,
  repeatable = excluded.repeatable,
  category = excluded.category,
  sort_order = excluded.sort_order;

do $check$
declare
  v_count integer;
begin
  select count(*) into v_count from public.badge_definitions;

  if v_count is distinct from 17 then
    raise exception
      'English badge seed failed: expected 17 definitions, found %.',
      v_count;
  end if;

  if exists (
    select 1
    from public.badge_definitions
    where description ~ '[Α-ω]'
  ) then
    raise exception
      'English badge seed failed: a description still contains Greek letters.';
  end if;

  if exists (select 1 from public.badge_awards) then
    raise exception
      'English badge seed failed: badge_awards must stay empty.';
  end if;
end
$check$;
