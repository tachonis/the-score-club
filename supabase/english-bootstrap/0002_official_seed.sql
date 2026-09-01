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

-- Official UEFA Champions League 2026/27 League Phase seed for a FRESH English
-- database. INSERT only. No DELETE. No swap. No finished scores.
--
-- Matchday titles are English. Kickoff timestamps are UTC.
-- ends_at = last kickoff of that matchday + 2 hours.
-- Apply AFTER 0001_schema.sql and BEFORE 0003_english_badges.sql.
--
-- This file must run as one transaction because the fixture staging table
-- uses ON COMMIT DROP.

begin;

insert into public.teams (name, short_name, country)
values
  ('AEK Athens', 'AEK', 'Greece'),
  ('LASK', 'LAS', 'Austria'),
  ('Club Brugge', 'BRU', 'Belgium'),
  ('Aston Villa', 'AVL', 'England'),
  ('Borussia Dortmund', 'BVB', 'Germany'),
  ('Villarreal', 'VIL', 'Spain'),
  ('Porto', 'POR', 'Portugal'),
  ('Manchester City', 'MCI', 'England'),
  ('Lille', 'LIL', 'France'),
  ('Real Betis', 'BET', 'Spain'),
  ('Real Madrid', 'RMA', 'Spain'),
  ('Inter Milan', 'INT', 'Italy'),
  ('Barcelona', 'BAR', 'Spain'),
  ('Feyenoord', 'FEY', 'Netherlands'),
  ('Stuttgart', 'STU', 'Germany'),
  ('Viking', 'VIK', 'Norway'),
  ('Liverpool', 'LIV', 'England'),
  ('Atlético Madrid', 'ATM', 'Spain'),
  ('Paris Saint-Germain', 'PSG', 'France'),
  ('Slovan Bratislava', 'SLO', 'Slovakia'),
  ('Sporting CP', 'SCP', 'Portugal'),
  ('Galatasaray', 'GAL', 'Turkey'),
  ('Napoli', 'NAP', 'Italy'),
  ('Arsenal', 'ARS', 'England'),
  ('Fenerbahçe', 'FEN', 'Turkey'),
  ('Roma', 'ROM', 'Italy'),
  ('PSV Eindhoven', 'PSV', 'Netherlands'),
  ('Shakhtar Donetsk', 'SHK', 'Ukraine'),
  ('Como 1907', 'COM', 'Italy'),
  ('RB Leipzig', 'RBL', 'Germany'),
  ('Bayern Munich', 'BAY', 'Germany'),
  ('Bodø/Glimt', 'BOD', 'Norway'),
  ('Manchester United', 'MUN', 'England'),
  ('Sabah', 'SAB', 'Azerbaijan'),
  ('Slavia Prague', 'SLA', 'Czechia'),
  ('Lens', 'LEN', 'France');

insert into public.matchdays (
  stage,
  matchday_number,
  name,
  starts_at,
  ends_at,
  status
)
values
  (
    'league_phase',
    1,
    'League Phase — Matchday 1',
    timestamptz '2026-09-08 16:45:00+00',
    timestamptz '2026-09-10 21:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    2,
    'League Phase — Matchday 2',
    timestamptz '2026-10-13 16:45:00+00',
    timestamptz '2026-10-14 21:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    3,
    'League Phase — Matchday 3',
    timestamptz '2026-10-20 16:45:00+00',
    timestamptz '2026-10-21 21:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    4,
    'League Phase — Matchday 4',
    timestamptz '2026-11-03 17:45:00+00',
    timestamptz '2026-11-04 22:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    5,
    'League Phase — Matchday 5',
    timestamptz '2026-11-24 17:45:00+00',
    timestamptz '2026-11-25 22:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    6,
    'League Phase — Matchday 6',
    timestamptz '2026-12-08 17:45:00+00',
    timestamptz '2026-12-09 22:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    7,
    'League Phase — Matchday 7',
    timestamptz '2027-01-19 17:45:00+00',
    timestamptz '2027-01-20 22:00:00+00',
    'upcoming'
  ),
  (
    'league_phase',
    8,
    'League Phase — Matchday 8',
    timestamptz '2027-01-27 20:00:00+00',
    timestamptz '2027-01-27 22:00:00+00',
    'upcoming'
  );

create temporary table english_official_fixtures (
  matchday_number integer not null,
  home_team_name text not null,
  away_team_name text not null,
  kickoff_at timestamptz not null,
  primary key (matchday_number, home_team_name, away_team_name)
) on commit drop;

insert into english_official_fixtures (
  matchday_number,
  home_team_name,
  away_team_name,
  kickoff_at
)
values
  (1, 'AEK Athens', 'LASK', timestamptz '2026-09-08 16:45:00+00'),
  (1, 'Club Brugge', 'Aston Villa', timestamptz '2026-09-08 16:45:00+00'),
  (1, 'Borussia Dortmund', 'Villarreal', timestamptz '2026-09-08 19:00:00+00'),
  (1, 'Porto', 'Manchester City', timestamptz '2026-09-08 19:00:00+00'),
  (1, 'Lille', 'Real Betis', timestamptz '2026-09-08 19:00:00+00'),
  (1, 'Real Madrid', 'Inter Milan', timestamptz '2026-09-08 19:00:00+00'),
  (1, 'Barcelona', 'Feyenoord', timestamptz '2026-09-09 16:45:00+00'),
  (1, 'Stuttgart', 'Viking', timestamptz '2026-09-09 16:45:00+00'),
  (1, 'Liverpool', 'Atlético Madrid', timestamptz '2026-09-09 19:00:00+00'),
  (1, 'Paris Saint-Germain', 'Slovan Bratislava', timestamptz '2026-09-09 19:00:00+00'),
  (1, 'Sporting CP', 'Galatasaray', timestamptz '2026-09-09 19:00:00+00'),
  (1, 'Napoli', 'Arsenal', timestamptz '2026-09-09 19:00:00+00'),
  (1, 'Fenerbahçe', 'Roma', timestamptz '2026-09-10 16:45:00+00'),
  (1, 'PSV Eindhoven', 'Shakhtar Donetsk', timestamptz '2026-09-10 16:45:00+00'),
  (1, 'Como 1907', 'RB Leipzig', timestamptz '2026-09-10 19:00:00+00'),
  (1, 'Bayern Munich', 'Bodø/Glimt', timestamptz '2026-09-10 19:00:00+00'),
  (1, 'Manchester United', 'Sabah', timestamptz '2026-09-10 19:00:00+00'),
  (1, 'Slavia Prague', 'Lens', timestamptz '2026-09-10 19:00:00+00'),
  (2, 'Lens', 'Sporting CP', timestamptz '2026-10-13 16:45:00+00'),
  (2, 'Sabah', 'Slavia Prague', timestamptz '2026-10-13 16:45:00+00'),
  (2, 'Arsenal', 'Lille', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Atlético Madrid', 'Manchester United', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Inter Milan', 'Club Brugge', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Galatasaray', 'Barcelona', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'RB Leipzig', 'PSV Eindhoven', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Viking', 'Bayern Munich', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Villarreal', 'Napoli', timestamptz '2026-10-13 19:00:00+00'),
  (2, 'Feyenoord', 'Como 1907', timestamptz '2026-10-14 16:45:00+00'),
  (2, 'LASK', 'Liverpool', timestamptz '2026-10-14 16:45:00+00'),
  (2, 'Roma', 'Real Madrid', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Aston Villa', 'Fenerbahçe', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Shakhtar Donetsk', 'AEK Athens', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Bodø/Glimt', 'Borussia Dortmund', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Manchester City', 'Paris Saint-Germain', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Real Betis', 'Porto', timestamptz '2026-10-14 19:00:00+00'),
  (2, 'Slovan Bratislava', 'Stuttgart', timestamptz '2026-10-14 19:00:00+00'),
  (3, 'Fenerbahçe', 'Slavia Prague', timestamptz '2026-10-20 16:45:00+00'),
  (3, 'Sabah', 'Borussia Dortmund', timestamptz '2026-10-20 16:45:00+00'),
  (3, 'Roma', 'Slovan Bratislava', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Porto', 'PSV Eindhoven', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Liverpool', 'Villarreal', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Manchester City', 'AEK Athens', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Paris Saint-Germain', 'Barcelona', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Napoli', 'Bodø/Glimt', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Stuttgart', 'Atlético Madrid', timestamptz '2026-10-20 19:00:00+00'),
  (3, 'Como 1907', 'Manchester United', timestamptz '2026-10-21 16:45:00+00'),
  (3, 'Lille', 'Galatasaray', timestamptz '2026-10-21 16:45:00+00'),
  (3, 'Aston Villa', 'Viking', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Club Brugge', 'Lens', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Bayern Munich', 'Arsenal', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Inter Milan', 'Shakhtar Donetsk', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Real Madrid', 'RB Leipzig', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Real Betis', 'Feyenoord', timestamptz '2026-10-21 19:00:00+00'),
  (3, 'Sporting CP', 'LASK', timestamptz '2026-10-21 19:00:00+00'),
  (4, 'Shakhtar Donetsk', 'Sporting CP', timestamptz '2026-11-03 17:45:00+00'),
  (4, 'Galatasaray', 'Stuttgart', timestamptz '2026-11-03 17:45:00+00'),
  (4, 'Atlético Madrid', 'Bayern Munich', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'Barcelona', 'Aston Villa', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'Feyenoord', 'Inter Milan', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'Bodø/Glimt', 'Lille', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'LASK', 'Slovan Bratislava', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'Manchester United', 'Roma', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'Villarreal', 'Paris Saint-Germain', timestamptz '2026-11-03 20:00:00+00'),
  (4, 'AEK Athens', 'Real Madrid', timestamptz '2026-11-04 17:45:00+00'),
  (4, 'Fenerbahçe', 'Liverpool', timestamptz '2026-11-04 17:45:00+00'),
  (4, 'Borussia Dortmund', 'Real Betis', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'Porto', 'Napoli', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'PSV Eindhoven', 'Club Brugge', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'RB Leipzig', 'Manchester City', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'Lens', 'Como 1907', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'Slavia Prague', 'Arsenal', timestamptz '2026-11-04 20:00:00+00'),
  (4, 'Viking', 'Sabah', timestamptz '2026-11-04 20:00:00+00'),
  (5, 'Bodø/Glimt', 'LASK', timestamptz '2026-11-24 17:45:00+00'),
  (5, 'Galatasaray', 'Aston Villa', timestamptz '2026-11-24 17:45:00+00'),
  (5, 'Arsenal', 'Borussia Dortmund', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Como 1907', 'AEK Athens', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Feyenoord', 'Porto', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Manchester City', 'Napoli', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'RB Leipzig', 'Lens', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Real Madrid', 'PSV Eindhoven', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Slovan Bratislava', 'Real Betis', timestamptz '2026-11-24 20:00:00+00'),
  (5, 'Sabah', 'Barcelona', timestamptz '2026-11-25 17:45:00+00'),
  (5, 'Slavia Prague', 'Villarreal', timestamptz '2026-11-25 17:45:00+00'),
  (5, 'Atlético Madrid', 'Viking', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Club Brugge', 'Liverpool', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Inter Milan', 'Stuttgart', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Shakhtar Donetsk', 'Fenerbahçe', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Lille', 'Bayern Munich', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Paris Saint-Germain', 'Roma', timestamptz '2026-11-25 20:00:00+00'),
  (5, 'Sporting CP', 'Manchester United', timestamptz '2026-11-25 20:00:00+00'),
  (6, 'Viking', 'Feyenoord', timestamptz '2026-12-08 17:45:00+00'),
  (6, 'Villarreal', 'Sabah', timestamptz '2026-12-08 17:45:00+00'),
  (6, 'AEK Athens', 'Galatasaray', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Roma', 'Sporting CP', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Aston Villa', 'Paris Saint-Germain', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Barcelona', 'Manchester City', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Bayern Munich', 'Slavia Prague', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Manchester United', 'RB Leipzig', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Napoli', 'Club Brugge', timestamptz '2026-12-08 20:00:00+00'),
  (6, 'Real Betis', 'Como 1907', timestamptz '2026-12-09 17:45:00+00'),
  (6, 'Slovan Bratislava', 'Shakhtar Donetsk', timestamptz '2026-12-09 17:45:00+00'),
  (6, 'Arsenal', 'Real Madrid', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'Borussia Dortmund', 'Inter Milan', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'LASK', 'Fenerbahçe', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'Liverpool', 'Porto', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'PSV Eindhoven', 'Atlético Madrid', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'Lens', 'Bodø/Glimt', timestamptz '2026-12-09 20:00:00+00'),
  (6, 'Stuttgart', 'Lille', timestamptz '2026-12-09 20:00:00+00'),
  (7, 'Bodø/Glimt', 'Atlético Madrid', timestamptz '2027-01-19 17:45:00+00'),
  (7, 'Galatasaray', 'Feyenoord', timestamptz '2027-01-19 17:45:00+00'),
  (7, 'AEK Athens', 'Roma', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Aston Villa', 'Borussia Dortmund', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Inter Milan', 'Liverpool', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Porto', 'Slavia Prague', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Lille', 'Slovan Bratislava', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Real Madrid', 'LASK', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Stuttgart', 'Club Brugge', timestamptz '2027-01-19 20:00:00+00'),
  (7, 'Fenerbahçe', 'Villarreal', timestamptz '2027-01-20 17:45:00+00'),
  (7, 'Sabah', 'Napoli', timestamptz '2027-01-20 17:45:00+00'),
  (7, 'Como 1907', 'Paris Saint-Germain', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'Manchester United', 'Bayern Munich', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'RB Leipzig', 'Shakhtar Donetsk', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'Lens', 'Manchester City', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'Real Betis', 'Arsenal', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'Sporting CP', 'Barcelona', timestamptz '2027-01-20 20:00:00+00'),
  (7, 'Viking', 'PSV Eindhoven', timestamptz '2027-01-20 20:00:00+00'),
  (8, 'Arsenal', 'Sabah', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Roma', 'Lille', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Atlético Madrid', 'Fenerbahçe', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Borussia Dortmund', 'AEK Athens', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Club Brugge', 'Bodø/Glimt', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Bayern Munich', 'Real Betis', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Barcelona', 'Como 1907', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Shakhtar Donetsk', 'Real Madrid', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Feyenoord', 'RB Leipzig', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'LASK', 'Porto', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Liverpool', 'Lens', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Manchester City', 'Sporting CP', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Paris Saint-Germain', 'Galatasaray', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'PSV Eindhoven', 'Stuttgart', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Slavia Prague', 'Aston Villa', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Napoli', 'Viking', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Villarreal', 'Manchester United', timestamptz '2027-01-27 20:00:00+00'),
  (8, 'Slovan Bratislava', 'Inter Milan', timestamptz '2027-01-27 20:00:00+00');

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status
)
select
  matchday.id,
  home_team.id,
  away_team.id,
  fixture.kickoff_at,
  'scheduled'
from english_official_fixtures as fixture
join public.matchdays as matchday
  on matchday.stage = 'league_phase'
 and matchday.matchday_number = fixture.matchday_number
join public.teams as home_team
  on home_team.name = fixture.home_team_name
join public.teams as away_team
  on away_team.name = fixture.away_team_name;

do $post$
declare
  v_team_count integer;
  v_matchday_count integer;
  v_match_count integer;
  v_uneven integer;
  v_bad_load integer;
  v_bad_split integer;
  v_unscheduled integer;
  v_scored integer;
begin
  select count(*) into v_team_count from public.teams;
  select count(*) into v_matchday_count from public.matchdays;
  select count(*) into v_match_count from public.matches;

  if v_team_count is distinct from 36 then
    raise exception 'English seed failed: expected 36 teams, found %.', v_team_count;
  end if;

  if v_matchday_count is distinct from 8 then
    raise exception 'English seed failed: expected 8 matchdays, found %.', v_matchday_count;
  end if;

  if v_match_count is distinct from 144 then
    raise exception 'English seed failed: expected 144 matches, found %.', v_match_count;
  end if;

  select count(*)
  into v_uneven
  from (
    select matchday.matchday_number
    from public.matches as match
    join public.matchdays as matchday
      on matchday.id = match.matchday_id
    group by matchday.matchday_number
    having count(*) is distinct from 18
  ) as uneven;

  if v_uneven is distinct from 0 then
    raise exception 'English seed failed: a matchday does not have 18 fixtures.';
  end if;

  select count(*)
  into v_bad_load
  from (
    select team.name, count(*) as games
    from public.teams as team
    join public.matches as match
      on match.home_team_id = team.id
      or match.away_team_id = team.id
    group by team.name
  ) as load
  where load.games is distinct from 8;

  if v_bad_load is distinct from 0 then
    raise exception 'English seed failed: a team does not have exactly 8 fixtures.';
  end if;

  select count(*)
  into v_bad_split
  from public.teams as team
  cross join lateral (
    select
      count(*) filter (where match.home_team_id = team.id) as home_games,
      count(*) filter (where match.away_team_id = team.id) as away_games
    from public.matches as match
  ) as split
  where split.home_games is distinct from 4
     or split.away_games is distinct from 4;

  if v_bad_split is distinct from 0 then
    raise exception 'English seed failed: a team is not 4 home / 4 away.';
  end if;

  select count(*)
  into v_unscheduled
  from public.matches
  where status is distinct from 'scheduled'
     or home_score is not null
     or away_score is not null;

  if v_unscheduled is distinct from 0 then
    raise exception 'English seed failed: matches must all be scheduled with null scores.';
  end if;

  select count(*)
  into v_scored
  from public.matches
  where home_score is not null or away_score is not null;

  if v_scored is distinct from 0 then
    raise exception 'English seed failed: finished scores must not be seeded.';
  end if;

  if exists (
    select 1
    from public.matchdays
    where name !~ '^League Phase — Matchday [1-8]$'
       or stage is distinct from 'league_phase'
       or status is distinct from 'upcoming'
  ) then
    raise exception 'English seed failed: matchday names/status are not the English baseline.';
  end if;

  if exists (
    select 1
    from public.matchdays as matchday
    join lateral (
      select max(match.kickoff_at) as last_kickoff
      from public.matches as match
      where match.matchday_id = matchday.id
    ) as kickoff_window on true
    where matchday.starts_at is distinct from (
            select min(match.kickoff_at)
            from public.matches as match
            where match.matchday_id = matchday.id
          )
       or matchday.ends_at is distinct from kickoff_window.last_kickoff + interval '2 hours'
  ) then
    raise exception 'English seed failed: starts_at/ends_at do not match kickoff window.';
  end if;
end
$post$;

commit;
