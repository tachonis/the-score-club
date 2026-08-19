-- Live League Phase table derived only from finished League Phase matches.
-- This migration changes no existing rows.

create or replace view public.league_phase_standings
with (security_invoker = true)
as
with finished_league_matches as (
  select
    m.id,
    m.home_team_id,
    m.away_team_id,
    m.home_score,
    m.away_score
  from public.matches as m
  join public.matchdays as md
    on md.id = m.matchday_id
  where md.stage = 'league_phase'
    and m.status = 'finished'
    and m.home_score is not null
    and m.away_score is not null
),
team_totals as (
  select
    t.id as team_id,
    t.name as team_name,
    t.short_name,
    t.logo_url,
    t.country,
    count(fm.id)::integer as played,
    count(fm.id) filter (
      where
        (t.id = fm.home_team_id and fm.home_score > fm.away_score)
        or (t.id = fm.away_team_id and fm.away_score > fm.home_score)
    )::integer as wins,
    count(fm.id) filter (
      where fm.home_score = fm.away_score
    )::integer as draws,
    count(fm.id) filter (
      where
        (t.id = fm.home_team_id and fm.home_score < fm.away_score)
        or (t.id = fm.away_team_id and fm.away_score < fm.home_score)
    )::integer as losses,
    coalesce(sum(
      case
        when t.id = fm.home_team_id then fm.home_score
        when t.id = fm.away_team_id then fm.away_score
        else 0
      end
    ), 0)::integer as goals_for,
    coalesce(sum(
      case
        when t.id = fm.home_team_id then fm.away_score
        when t.id = fm.away_team_id then fm.home_score
        else 0
      end
    ), 0)::integer as goals_against
  from public.teams as t
  left join finished_league_matches as fm
    on t.id = fm.home_team_id
    or t.id = fm.away_team_id
  group by
    t.id,
    t.name,
    t.short_name,
    t.logo_url,
    t.country
),
ranked_teams as (
  select
    row_number() over (
      order by
        (wins * 3 + draws) desc,
        (goals_for - goals_against) desc,
        goals_for desc,
        lower(team_name) asc,
        team_id asc
    ) as position,
    team_id,
    team_name,
    short_name,
    logo_url,
    country,
    played,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    goals_for - goals_against as goal_difference,
    wins * 3 + draws as points
  from team_totals
)
select
  position,
  team_id,
  team_name,
  short_name,
  logo_url,
  country,
  played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  goal_difference,
  points
from ranked_teams;

comment on view public.league_phase_standings is
  'Live Champions League phase standings from finished league_phase matches. Ranking: points, goal difference, goals scored, then deterministic team name/id fallback.';

revoke all privileges on table public.league_phase_standings
  from public, anon;
grant select on table public.league_phase_standings
  to authenticated, service_role;
