-- =============================================================================
-- ENGLISH BOOTSTRAP — DO NOT APPLY TO GREEK PRODUCTION
-- =============================================================================
-- Read-only verification for a future English Supabase project.
-- Safe: SELECT / DO checks only. No writes. No hosted connection implied.
-- Run AFTER 0001_schema.sql, 0002_official_seed.sql, and 0003_english_badges.sql.
-- NEVER run against Greek production (aoprkdbqtibsnlusbbpz).
-- =============================================================================

do $verify$
declare
  v_teams integer;
  v_matchdays integer;
  v_matches integer;
  v_uneven integer;
  v_bad_load integer;
  v_bad_split integer;
  v_unscheduled integer;
  v_profiles integer;
  v_predictions integer;
  v_golden integer;
  v_lt_pred integer;
  v_lt_out integer;
  v_lt_awards integer;
  v_badge_awards integer;
  v_badge_defs integer;
  v_cup_comp integer;
  v_cup_parts integer;
  v_cup_rounds integer;
  v_cup_ties integer;
  v_cup_awards integer;
  v_cup_excl integer;
  v_push_subs integer;
  v_push_bc integer;
  v_auth_users integer;
  v_rls_missing text;
  v_rpc_missing text;
  v_backup_schema boolean;
  v_md_rows integer;
  v_ko_rows integer;
  v_md_id bigint;
begin
  select count(*) into v_teams from public.teams;
  select count(*) into v_matchdays from public.matchdays;
  select count(*) into v_matches from public.matches;

  if v_teams is distinct from 36 then
    raise exception 'Expected 36 teams, found %.', v_teams;
  end if;

  if v_matchdays is distinct from 8 then
    raise exception 'Expected 8 matchdays, found %.', v_matchdays;
  end if;

  if v_matches is distinct from 144 then
    raise exception 'Expected 144 matches, found %.', v_matches;
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
    raise exception 'Expected 18 matches per matchday.';
  end if;

  select count(*)
  into v_bad_load
  from (
    select team.id, count(*) as games
    from public.teams as team
    join public.matches as match
      on match.home_team_id = team.id
      or match.away_team_id = team.id
    group by team.id
  ) as load
  where load.games is distinct from 8;

  if v_bad_load is distinct from 0 then
    raise exception 'Expected 8 matches per team.';
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
    raise exception 'Expected 4 home and 4 away matches per team.';
  end if;

  select count(*)
  into v_unscheduled
  from public.matches
  where status is distinct from 'scheduled'
     or home_score is not null
     or away_score is not null;

  if v_unscheduled is distinct from 0 then
    raise exception 'Expected every match to be scheduled with null scores.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class
    where relnamespace = 'auth'::regnamespace
      and relname = 'users'
      and relkind = 'r'
  ) then
    execute 'select count(*) from auth.users' into v_auth_users;
  else
    v_auth_users := 0;
  end if;

  if v_auth_users is distinct from 0 then
    raise exception 'Expected auth.users to be empty, found %.', v_auth_users;
  end if;

  select count(*) into v_profiles from public.profiles;
  select count(*) into v_predictions from public.predictions;
  select count(*) into v_golden from public.golden_match_selections;
  select count(*) into v_lt_pred from public.long_term_predictions;
  select count(*) into v_lt_out from public.long_term_outcomes;
  select count(*) into v_lt_awards from public.long_term_awards;
  select count(*) into v_badge_awards from public.badge_awards;
  select count(*) into v_cup_comp from public.cup_competitions;
  select count(*) into v_cup_parts from public.cup_participants;
  select count(*) into v_cup_rounds from public.cup_rounds;
  select count(*) into v_cup_ties from public.cup_ties;
  select count(*) into v_cup_awards from public.cup_awards;
  select count(*) into v_cup_excl from public.cup_excluded_matches;
  select count(*) into v_push_subs from public.push_subscriptions;
  select count(*) into v_push_bc from public.push_broadcasts;

  if v_profiles is distinct from 0
     or v_predictions is distinct from 0
     or v_golden is distinct from 0
     or v_lt_pred is distinct from 0
     or v_lt_out is distinct from 0
     or v_lt_awards is distinct from 0
     or v_badge_awards is distinct from 0
     or v_cup_comp is distinct from 0
     or v_cup_parts is distinct from 0
     or v_cup_rounds is distinct from 0
     or v_cup_ties is distinct from 0
     or v_cup_awards is distinct from 0
     or v_cup_excl is distinct from 0
     or v_push_subs is distinct from 0
     or v_push_bc is distinct from 0
  then
    raise exception
      'User-generated tables must be empty. profiles=% predictions=% golden=% lt_pred=% lt_out=% lt_awards=% badge_awards=% cup_comp=% cup_parts=% cup_rounds=% cup_ties=% cup_awards=% cup_excl=% push_subs=% push_bc=%',
      v_profiles, v_predictions, v_golden, v_lt_pred, v_lt_out, v_lt_awards,
      v_badge_awards, v_cup_comp, v_cup_parts, v_cup_rounds, v_cup_ties,
      v_cup_awards, v_cup_excl, v_push_subs, v_push_bc;
  end if;

  select count(*) into v_badge_defs from public.badge_definitions;
  if v_badge_defs is distinct from 17 then
    raise exception 'Expected 17 badge_definitions, found %.', v_badge_defs;
  end if;

  if exists (
    select 1
    from public.badge_definitions
    where description ~ '[Α-ω]'
  ) then
    raise exception 'badge_definitions still contain Greek description text.';
  end if;

  select string_agg(expected.relname, ', ' order by expected.relname)
  into v_rls_missing
  from (
    values
      ('profiles'),
      ('teams'),
      ('matchdays'),
      ('matches'),
      ('predictions'),
      ('golden_match_selections'),
      ('long_term_predictions'),
      ('long_term_outcomes'),
      ('long_term_awards'),
      ('badge_definitions'),
      ('badge_awards'),
      ('cup_competitions'),
      ('cup_participants'),
      ('cup_rounds'),
      ('cup_ties'),
      ('cup_awards'),
      ('cup_excluded_matches'),
      ('push_subscriptions'),
      ('push_broadcasts')
  ) as expected(relname)
  left join pg_catalog.pg_class as cls
    on cls.relname = expected.relname
   and cls.relnamespace = 'public'::regnamespace
   and cls.relkind = 'r'
  where cls.oid is null
     or cls.relrowsecurity is not true;

  if v_rls_missing is not null then
    raise exception 'RLS missing or table absent: %.', v_rls_missing;
  end if;

  select string_agg(expected.proname, ', ' order by expected.proname)
  into v_rpc_missing
  from (
    values
      ('set_match_result'),
      ('get_leaderboard'),
      ('get_matchday_leaderboard'),
      ('get_knockout_leaderboard'),
      ('set_golden_match'),
      ('set_long_term_prediction'),
      ('set_long_term_outcome'),
      ('create_players_cup'),
      ('recompute_players_cup'),
      ('upsert_my_push_subscription'),
      ('get_active_push_subscriptions'),
      ('is_admin'),
      ('handle_new_user'),
      ('admin_recompute_badges')
  ) as expected(proname)
  where not exists (
    select 1
    from pg_catalog.pg_proc as proc
    join pg_catalog.pg_namespace as nsp
      on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = expected.proname
  );

  if v_rpc_missing is not null then
    raise exception 'Missing core RPCs: %.', v_rpc_missing;
  end if;

  select exists (
    select 1
    from pg_catalog.pg_namespace
    where nspname like 'prelaunch_backup%'
  )
  into v_backup_schema;

  if v_backup_schema then
    raise exception 'prelaunch_backup schema must not exist on the English baseline.';
  end if;

  if (select count(*) from public.league_phase_standings) is distinct from 36 then
    raise exception 'Expected 36 league_phase_standings rows on a scheduled-only seed.';
  end if;

  if exists (
    select 1
    from public.league_phase_standings
    where played is distinct from 0
       or points is distinct from 0
  ) then
    raise exception 'league_phase_standings must be 0 played / 0 points after the English seed.';
  end if;

  select id
  into v_md_id
  from public.matchdays
  where stage = 'league_phase'
    and matchday_number = 1;

  select count(*)
  into v_md_rows
  from public.get_matchday_leaderboard(v_md_id);

  select count(*)
  into v_ko_rows
  from public.get_knockout_leaderboard();

  if v_md_rows is distinct from 0 then
    raise exception
      'get_matchday_leaderboard should return 0 rows on an empty user set, found %.',
      v_md_rows;
  end if;

  if v_ko_rows is distinct from 0 then
    raise exception
      'get_knockout_leaderboard should return 0 rows on an empty user set, found %.',
      v_ko_rows;
  end if;

  raise notice 'English bootstrap verification passed.';
end
$verify$;
