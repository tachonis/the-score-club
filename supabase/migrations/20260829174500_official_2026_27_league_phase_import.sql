-- Official UEFA Champions League 2026/27 League Phase import.
-- Documents the hosted operation official_2026_27_league_phase_import_v2.
--
-- public.league_phase_standings is a VIEW derived from public.teams and
-- finished League Phase matches. This migration does not DELETE FROM or
-- INSERT INTO that view; it repopulates naturally after teams and scheduled
-- fixtures are replaced.
--
-- Does not touch profiles, auth, push subscriptions, or badge_definitions.
-- Temporary datasets use ON COMMIT DROP, so this file must run as one
-- transaction. Do not db push. Do not repair migration history. Do not
-- apply against hosted Supabase; production already holds this dataset.

create temporary table official_import_meta (
  profile_count bigint not null
) on commit drop;

insert into official_import_meta (profile_count)
select count(*)
from public.profiles;

do $guard$
declare
  v_placeholder_missing text;
  v_team_count integer;
  v_matchday_count integer;
  v_match_count integer;
  v_bad_matchdays integer;
begin
  select count(*)
  into v_team_count
  from public.teams;

  select count(*)
  into v_matchday_count
  from public.matchdays
  where stage = 'league_phase'
    and matchday_number between 1 and 8;

  select count(*)
  into v_match_count
  from public.matches;

  if v_team_count is distinct from 36 then
    raise exception
      'Official import aborted: expected 36 preseason teams, found %.',
      v_team_count;
  end if;

  if v_matchday_count is distinct from 8 then
    raise exception
      'Official import aborted: expected 8 League Phase matchdays, found %.',
      v_matchday_count;
  end if;

  if exists (
    select 1
    from public.matchdays
    where stage is distinct from 'league_phase'
       or matchday_number is null
       or matchday_number not between 1 and 8
  ) then
    raise exception
      'Official import aborted: non-League-Phase matchdays are present.';
  end if;

  if v_match_count is distinct from 144 then
    raise exception
      'Official import aborted: expected 144 preseason matches, found %.',
      v_match_count;
  end if;

  select count(*)
  into v_bad_matchdays
  from (
    select matchday.matchday_number
    from public.matches as match
    join public.matchdays as matchday
      on matchday.id = match.matchday_id
    group by matchday.matchday_number
    having count(*) is distinct from 18
  ) as uneven;

  if v_bad_matchdays is distinct from 0 then
    raise exception
      'Official import aborted: preseason matchdays are not 18 fixtures each.';
  end if;

  select string_agg(expected.name, ', ' order by expected.name)
  into v_placeholder_missing
  from (
    values
      ('Athletic Bilbao'),
      ('Arsenal'),
      ('PSV Eindhoven'),
      ('Union Saint-Gilloise'),
      ('Juventus'),
      ('Borussia Dortmund'),
      ('Real Madrid'),
      ('Marseille'),
      ('Benfica'),
      ('Qarabağ'),
      ('Tottenham Hotspur'),
      ('Villarreal'),
      ('Olympiacos'),
      ('Pafos'),
      ('Slavia Prague'),
      ('Bodø/Glimt'),
      ('Ajax'),
      ('Inter Milan'),
      ('Bayern Munich'),
      ('Chelsea'),
      ('Liverpool'),
      ('Atlético Madrid'),
      ('Paris Saint-Germain'),
      ('Atalanta'),
      ('Club Brugge'),
      ('Monaco'),
      ('Copenhagen'),
      ('Bayer Leverkusen'),
      ('Eintracht Frankfurt'),
      ('Galatasaray'),
      ('Manchester City'),
      ('Napoli'),
      ('Newcastle United'),
      ('Barcelona'),
      ('Sporting CP'),
      ('Kairat')
  ) as expected(name)
  left join public.teams as team
    on team.name = expected.name
  where team.id is null;

  if v_placeholder_missing is not null then
    raise exception
      'Official import aborted: missing preseason placeholder teams: %.',
      v_placeholder_missing;
  end if;

  if exists (
    select 1
    from public.teams
    where name in ('AEK Athens', 'Como 1907', 'Sabah', 'LASK', 'Viking')
  ) then
    raise exception
      'Official import aborted: official 2026/27 teams are already present.';
  end if;
end
$guard$;

create temporary table official_2026_27_teams (
  name text primary key,
  short_name text not null,
  country text not null
) on commit drop;

insert into official_2026_27_teams (name, short_name, country)
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

create temporary table official_2026_27_fixtures (
  matchday_number integer not null,
  home_team_name text not null,
  away_team_name text not null,
  kickoff_at timestamptz not null,
  primary key (matchday_number, home_team_name, away_team_name)
) on commit drop;

insert into official_2026_27_fixtures (
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

do $validate$
declare
  v_team_count integer;
  v_fixture_count integer;
begin
  select count(*)
  into v_team_count
  from official_2026_27_teams;

  select count(*)
  into v_fixture_count
  from official_2026_27_fixtures;

  if v_team_count is distinct from 36 then
    raise exception
      'Official import aborted: official team dataset has % rows, expected 36.',
      v_team_count;
  end if;

  if v_fixture_count is distinct from 144 then
    raise exception
      'Official import aborted: official fixture dataset has % rows, expected 144.',
      v_fixture_count;
  end if;

  if exists (
    select 1
    from official_2026_27_fixtures
    group by matchday_number
    having count(*) is distinct from 18
  ) then
    raise exception
      'Official import aborted: official fixtures are not 18 per matchday.';
  end if;

  if exists (
    select 1
    from (
      select team.name, count(*) as games
      from official_2026_27_teams as team
      join official_2026_27_fixtures as fixture
        on fixture.home_team_name = team.name
        or fixture.away_team_name = team.name
      group by team.name
    ) as load
    where load.games is distinct from 8
  ) then
    raise exception
      'Official import aborted: a team does not have exactly 8 official fixtures.';
  end if;

  if exists (
    select 1
    from official_2026_27_teams as team
    cross join lateral (
      select
        count(*) filter (where fixture.home_team_name = team.name) as home_games,
        count(*) filter (where fixture.away_team_name = team.name) as away_games
      from official_2026_27_fixtures as fixture
    ) as split
    where split.home_games is distinct from 4
       or split.away_games is distinct from 4
  ) then
    raise exception
      'Official import aborted: a team does not have exactly 4 home and 4 away fixtures.';
  end if;

  if exists (
    select 1
    from official_2026_27_fixtures as fixture
    cross join lateral (
      values
        (fixture.home_team_name),
        (fixture.away_team_name)
    ) as appearance(team_name)
    group by fixture.matchday_number, appearance.team_name
    having count(*) is distinct from 1
  ) then
    raise exception
      'Official import aborted: a team appears more than once on a matchday.';
  end if;
end
$validate$;

delete from public.golden_match_selections;
delete from public.predictions;
delete from public.long_term_awards;
delete from public.long_term_outcomes;
delete from public.long_term_predictions;
delete from public.matches;
delete from public.teams;

update public.matchdays as matchday
set
  name = case
      when matchday_number = 1 then 'League Phase – 1η αγωνιστική'
      when matchday_number = 2 then 'League Phase – 2η αγωνιστική'
      when matchday_number = 3 then 'League Phase – 3η αγωνιστική'
      when matchday_number = 4 then 'League Phase – 4η αγωνιστική'
      when matchday_number = 5 then 'League Phase – 5η αγωνιστική'
      when matchday_number = 6 then 'League Phase – 6η αγωνιστική'
      when matchday_number = 7 then 'League Phase – 7η αγωνιστική'
      when matchday_number = 8 then 'League Phase – 8η αγωνιστική'
  end,
  starts_at = case
      when matchday_number = 1 then timestamptz '2026-09-08 16:45:00+00'
      when matchday_number = 2 then timestamptz '2026-10-13 16:45:00+00'
      when matchday_number = 3 then timestamptz '2026-10-20 16:45:00+00'
      when matchday_number = 4 then timestamptz '2026-11-03 17:45:00+00'
      when matchday_number = 5 then timestamptz '2026-11-24 17:45:00+00'
      when matchday_number = 6 then timestamptz '2026-12-08 17:45:00+00'
      when matchday_number = 7 then timestamptz '2027-01-19 17:45:00+00'
      when matchday_number = 8 then timestamptz '2027-01-27 20:00:00+00'
  end,
  ends_at = case
      when matchday_number = 1 then timestamptz '2026-09-10 21:00:00+00'
      when matchday_number = 2 then timestamptz '2026-10-14 21:00:00+00'
      when matchday_number = 3 then timestamptz '2026-10-21 21:00:00+00'
      when matchday_number = 4 then timestamptz '2026-11-04 22:00:00+00'
      when matchday_number = 5 then timestamptz '2026-11-25 22:00:00+00'
      when matchday_number = 6 then timestamptz '2026-12-09 22:00:00+00'
      when matchday_number = 7 then timestamptz '2027-01-20 22:00:00+00'
      when matchday_number = 8 then timestamptz '2027-01-27 22:00:00+00'
  end,
  status = 'upcoming'
where matchday.stage = 'league_phase'
  and matchday.matchday_number between 1 and 8;

do $matchdays$
begin
  if (select count(*) from public.matchdays) is distinct from 8 then
    raise exception
      'Official import aborted: League Phase matchday rows were not preserved.';
  end if;
end
$matchdays$;

insert into public.teams (name, short_name, country)
select
  team.name,
  team.short_name,
  team.country
from official_2026_27_teams as team
order by team.name;

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
from official_2026_27_fixtures as fixture
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
  v_match_count integer;
  v_bad_team_load integer;
  v_standings_count integer;
begin
  -- league_phase_standings is a view: select only, never write.
  select count(*)
  into v_team_count
  from public.teams;

  select count(*)
  into v_match_count
  from public.matches;

  select count(*)
  into v_standings_count
  from public.league_phase_standings;

  if v_team_count is distinct from 36 then
    raise exception 'Official import post-check failed: team count is %.', v_team_count;
  end if;

  if v_match_count is distinct from 144 then
    raise exception
      'Official import post-check failed: match count is %.',
      v_match_count;
  end if;

  if exists (
    select 1
    from (
      values
        ('AEK Athens'),
      ('LASK'),
      ('Club Brugge'),
      ('Aston Villa'),
      ('Borussia Dortmund'),
      ('Villarreal'),
      ('Porto'),
      ('Manchester City'),
      ('Lille'),
      ('Real Betis'),
      ('Real Madrid'),
      ('Inter Milan'),
      ('Barcelona'),
      ('Feyenoord'),
      ('Stuttgart'),
      ('Viking'),
      ('Liverpool'),
      ('Atlético Madrid'),
      ('Paris Saint-Germain'),
      ('Slovan Bratislava'),
      ('Sporting CP'),
      ('Galatasaray'),
      ('Napoli'),
      ('Arsenal'),
      ('Fenerbahçe'),
      ('Roma'),
      ('PSV Eindhoven'),
      ('Shakhtar Donetsk'),
      ('Como 1907'),
      ('RB Leipzig'),
      ('Bayern Munich'),
      ('Bodø/Glimt'),
      ('Manchester United'),
      ('Sabah'),
      ('Slavia Prague'),
      ('Lens')
    ) as expected(name)
    left join public.teams as team
      on team.name = expected.name
    where team.id is null
  ) then
    raise exception
      'Official import post-check failed: an official team name is missing.';
  end if;

  if exists (
    select 1
    from public.matchdays as matchday
    left join public.matches as match
      on match.matchday_id = matchday.id
    group by matchday.id
    having count(match.id) is distinct from 18
  ) then
    raise exception
      'Official import post-check failed: a matchday does not have 18 fixtures.';
  end if;

  select count(*)
  into v_bad_team_load
  from (
    select
      team.id,
      count(*) as games,
      count(*) filter (where match.home_team_id = team.id) as home_games,
      count(*) filter (where match.away_team_id = team.id) as away_games
    from public.teams as team
    join public.matches as match
      on match.home_team_id = team.id
      or match.away_team_id = team.id
    group by team.id
  ) as load
  where load.games is distinct from 8
     or load.home_games is distinct from 4
     or load.away_games is distinct from 4;

  if v_bad_team_load is distinct from 0 then
    raise exception
      'Official import post-check failed: home/away load is not 4/4 with 8 games.';
  end if;

  if exists (
    select 1
    from public.matches as match
    join public.matchdays as matchday
      on matchday.id = match.matchday_id
    cross join lateral (
      values
        (match.home_team_id),
        (match.away_team_id)
    ) as appearance(team_id)
    group by matchday.matchday_number, appearance.team_id
    having count(*) is distinct from 1
  ) then
    raise exception
      'Official import post-check failed: a team appears twice on one matchday.';
  end if;

  if exists (
    select 1
    from public.matches
    where status is distinct from 'scheduled'
       or home_score is not null
       or away_score is not null
  ) then
    raise exception
      'Official import post-check failed: imported matches are not all scheduled.';
  end if;

  if v_standings_count is distinct from 36 then
    raise exception
      'Official import post-check failed: league_phase_standings view has % rows.',
      v_standings_count;
  end if;

  if exists (
    select 1
    from public.league_phase_standings
    where played is distinct from 0
       or points is distinct from 0
  ) then
    raise exception
      'Official import post-check failed: standings view is not an empty League Phase table.';
  end if;

  if exists (select 1 from public.predictions)
     or exists (select 1 from public.golden_match_selections)
     or exists (select 1 from public.long_term_predictions)
     or exists (select 1 from public.long_term_outcomes)
     or exists (select 1 from public.long_term_awards)
     or exists (select 1 from public.badge_awards)
     or exists (select 1 from public.cup_competitions) then
    raise exception
      'Official import post-check failed: predictions, awards or Cup state remain.';
  end if;

  if (
    select count(*)
    from public.profiles
  ) is distinct from (
    select meta.profile_count
    from official_import_meta as meta
  ) then
    raise exception
      'Official import post-check failed: profiles were modified.';
  end if;
end
$post$;
