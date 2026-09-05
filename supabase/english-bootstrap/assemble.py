"""Rebuild 0001_schema.sql and 0002_official_seed.sql from classified sources.

NEVER point this at Greek hosted Supabase.
NEVER copy the output into supabase/migrations/.
This directory is intentionally outside the CLI migrations path.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations"
OUT = Path(__file__).resolve().parent

UNSAFE = {
    "20260829173000_prelaunch_game_data_backup_20260829.sql",
    "20260829174500_official_2026_27_league_phase_import.sql",
}

# Additive files kept out of 0001. Apply them after 0001 on empty English DBs,
# and as the only schema change on the existing English production project.
POST_SCHEMA = {
    "20260906120000_feedback_messages.sql",
}

SAFETY = """-- =============================================================================
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
"""


def strip_badge_seed(text: str) -> str:
    start = text.find("insert into public.badge_definitions")
    end = text.find("alter table public.badge_definitions enable row level security")
    if start < 0 or end < 0 or end <= start:
        raise SystemExit("Could not locate badge_definitions seed block to strip")
    return (
        text[:start]
        + "-- Greek badge_definitions copy omitted.\n"
        + "-- English rows are inserted by 0003_english_badges.sql.\n\n"
        + text[end:]
    )


def write_schema() -> None:
    files = sorted(
        path
        for path in MIGRATIONS.glob("*.sql")
        if path.name not in UNSAFE and path.name not in POST_SCHEMA
    )
    if len(files) != 26:
        raise SystemExit(f"Expected 26 safe schema files, found {len(files)}")

    parts = [
        SAFETY,
        "-- Clean English schema/logic baseline.\n",
        "-- Concatenated in timestamp order from SAFE SCHEMA/LOGIC migrations.\n",
        "-- badge_definitions rows are NOT included here (see 0003).\n",
        "-- Apply to an empty database BEFORE 0002 and 0003.\n\n",
    ]
    for path in files:
        text = path.read_text(encoding="utf-8")
        if path.name == "20260827190000_badges_foundation.sql":
            text = strip_badge_seed(text)
        parts.append(
            "\n\n-- =====================================================================\n"
            f"-- SOURCE: supabase/migrations/{path.name}\n"
            "-- =====================================================================\n\n"
        )
        parts.append(text)
        if not text.endswith("\n"):
            parts.append("\n")

    (OUT / "0001_schema.sql").write_text("".join(parts), encoding="utf-8")
    print(f"wrote 0001_schema.sql from {len(files)} files")


def extract_block(text: str, marker: str, terminator: str) -> str:
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"Missing marker: {marker}")
    values_at = text.find("values", start)
    if values_at < 0:
        raise SystemExit(f"Missing values after {marker}")
    end = text.find(terminator, values_at)
    if end < 0:
        raise SystemExit(f"Missing terminator after {marker}")
    return text[values_at:end].rstrip().rstrip(";")


def write_official_seed() -> None:
    source = (
        MIGRATIONS / "20260829174500_official_2026_27_league_phase_import.sql"
    ).read_text(encoding="utf-8")
    teams_values = extract_block(
        source,
        "insert into official_2026_27_teams",
        "create temporary table official_2026_27_fixtures",
    )
    fixtures_values = extract_block(
        source,
        "insert into official_2026_27_fixtures",
        "do $validate$",
    )

    sql = f"""{SAFETY}
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
{teams_values};

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
{fixtures_values};

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
"""
    (OUT / "0002_official_seed.sql").write_text(sql, encoding="utf-8")
    print("wrote 0002_official_seed.sql")


if __name__ == "__main__":
    write_schema()
    write_official_seed()
