-- Transactional matchday / knockout presentation leaderboard verification.
-- Every fixture mutation is rolled back at the end.
-- Requires public.get_matchday_leaderboard(bigint) and
-- public.get_knockout_leaderboard() from 20260901120000_matchday_leaderboard.sql.

begin;

create function pg_temp.mdl_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'MATCHDAY LEADERBOARD TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.mdl_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9100 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.mdl_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.mdl_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'matchday-lb-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzmdl' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.mdl_row(p_matchday_id bigint, p_index integer)
returns table (
  rank_position bigint,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
as $helper$
  select
    board.rank_position,
    board.total_points,
    board.exact_scores,
    board.correct_results,
    board.missed_predictions
  from public.get_matchday_leaderboard(p_matchday_id) as board
  where board.user_id = pg_temp.mdl_user_id(p_index);
$helper$;

select pg_temp.mdl_add_player(1);
select pg_temp.mdl_add_player(2);
select pg_temp.mdl_add_player(3);
select pg_temp.mdl_add_player(4);
select pg_temp.mdl_add_player(5);
select pg_temp.mdl_add_player(6);
select pg_temp.mdl_add_player(7);

insert into public.teams (name, short_name)
values
  ('ZZ Matchday LB Home', 'ZMH'),
  ('ZZ Matchday LB Away', 'ZMA');

select set_config(
  'test.mdl_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Matchday LB Home'
  ),
  true
);
select set_config(
  'test.mdl_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Matchday LB Away'
  ),
  true
);

insert into public.matchdays (stage, matchday_number, name, status)
values
  ('league_phase', 91, 'ZZ MDLB 91η αγωνιστική', 'upcoming'),
  ('league_phase', 92, 'ZZ MDLB 92η αγωνιστική', 'upcoming'),
  ('playoff', 91, 'ZZ MDLB Play-offs', 'upcoming');

select set_config(
  'test.md91',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 91
  ),
  true
);
select set_config(
  'test.md92',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 92
  ),
  true
);
select set_config(
  'test.ko91',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.stage = 'playoff'
      and matchday.matchday_number = 91
  ),
  true
);

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status
)
select
  current_setting('test.md91')::bigint,
  current_setting('test.mdl_home')::bigint,
  current_setting('test.mdl_away')::bigint,
  now() + (ordinal.n::text || ' hours')::interval,
  'scheduled'
from generate_series(1, 3) as ordinal(n)
union all
select
  current_setting('test.md92')::bigint,
  current_setting('test.mdl_home')::bigint,
  current_setting('test.mdl_away')::bigint,
  now() + interval '8 days' + (ordinal.n::text || ' hours')::interval,
  'scheduled'
from generate_series(1, 3) as ordinal(n)
union all
select
  current_setting('test.ko91')::bigint,
  current_setting('test.mdl_home')::bigint,
  current_setting('test.mdl_away')::bigint,
  now() + interval '30 days',
  'scheduled';

select set_config(
  'test.md91_m1',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md91')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 0
    limit 1
  ),
  true
);
select set_config(
  'test.md91_m2',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md91')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 1
    limit 1
  ),
  true
);
select set_config(
  'test.md91_m3',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md91')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 2
    limit 1
  ),
  true
);
select set_config(
  'test.md92_m1',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md92')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 0
    limit 1
  ),
  true
);
select set_config(
  'test.md92_m2',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md92')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 1
    limit 1
  ),
  true
);
select set_config(
  'test.md92_m3',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md92')::bigint
    order by match_row.kickoff_at, match_row.id
    offset 2
    limit 1
  ),
  true
);
select set_config(
  'test.ko91_m1',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.ko91')::bigint
    order by match_row.id
    limit 1
  ),
  true
);

-- ---------------------------------------------------------------------------
-- A. MD91 before any scored prediction → all zeros
-- ---------------------------------------------------------------------------

select pg_temp.mdl_assert(
  (
    select board.total_points = 0
      and board.exact_scores = 0
      and board.correct_results = 0
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 1) as board
  ),
  'A: unscored MD91 is zero for a test player'
);

select pg_temp.mdl_assert(
  not exists (
    select 1
    from public.get_matchday_leaderboard(current_setting('test.md91')::bigint)
      as board
    where board.total_points > 0
  ),
  'A: no player has points on unscored MD91'
);

select pg_temp.mdl_assert(
  not exists (
    select 1
    from public.get_matchday_leaderboard(current_setting('test.ko91')::bigint)
  ),
  'non-league_phase matchday returns no matchday leaderboard rows'
);

select pg_temp.mdl_assert(
  position('long_term_awards' in pg_get_functiondef(
    'public.get_matchday_leaderboard(bigint)'::regprocedure
  )) = 0
  and position('cup_awards' in pg_get_functiondef(
    'public.get_matchday_leaderboard(bigint)'::regprocedure
  )) = 0,
  'H/I: matchday RPC does not read long_term_awards or cup_awards'
);

select pg_temp.mdl_assert(
  position('long_term_awards' in pg_get_functiondef(
    'public.get_knockout_leaderboard()'::regprocedure
  )) = 0
  and position('cup_awards' in pg_get_functiondef(
    'public.get_knockout_leaderboard()'::regprocedure
  )) = 0,
  'H/I: knockout RPC does not read long_term_awards or cup_awards'
);

-- ---------------------------------------------------------------------------
-- B / D / G. Scored MD91
-- p1: 5,5,2 = 12 / 2 exact / 1 correct / 0 missed
-- p3: 5,5,2 = 12 / 2 exact / 1 correct / 0 missed  (full tie with p1)
-- p2: 5,2,0 =  7 / 1 exact / 1 correct / 0 missed
-- p4: 5,0,0 =  5 / 1 exact / 0 correct / 0 missed
-- p6: 5      =  5 / 1 exact / 0 correct / 2 missed (missed matches)
-- p5: 2,2,0 =  4 / 0 exact / 2 correct / 0 missed
-- p7: none   =  0
-- ---------------------------------------------------------------------------

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
values
  (pg_temp.mdl_user_id(1), current_setting('test.md91_m1')::bigint, 2, 1, 5),
  (pg_temp.mdl_user_id(1), current_setting('test.md91_m2')::bigint, 1, 0, 5),
  (pg_temp.mdl_user_id(1), current_setting('test.md91_m3')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(2), current_setting('test.md91_m1')::bigint, 2, 1, 5),
  (pg_temp.mdl_user_id(2), current_setting('test.md91_m2')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(2), current_setting('test.md91_m3')::bigint, 3, 0, 0),
  (pg_temp.mdl_user_id(3), current_setting('test.md91_m1')::bigint, 2, 1, 5),
  (pg_temp.mdl_user_id(3), current_setting('test.md91_m2')::bigint, 1, 0, 5),
  (pg_temp.mdl_user_id(3), current_setting('test.md91_m3')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(4), current_setting('test.md91_m1')::bigint, 2, 1, 5),
  (pg_temp.mdl_user_id(4), current_setting('test.md91_m2')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(4), current_setting('test.md91_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(5), current_setting('test.md91_m1')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(5), current_setting('test.md91_m2')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(5), current_setting('test.md91_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(6), current_setting('test.md91_m1')::bigint, 2, 1, 5);

select pg_temp.mdl_assert(
  (
    select board.total_points = 12
      and board.exact_scores = 2
      and board.correct_results = 1
      and board.missed_predictions = 0
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 1) as board
  ),
  'B: player 1 MD91 totals come from stored prediction points'
);

select pg_temp.mdl_assert(
  (
    select board.total_points = 5
      and board.exact_scores = 1
      and board.missed_predictions = 2
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 6) as board
  ),
  'D: only submitted predictions count; missed matches are ignored for points'
);

select pg_temp.mdl_assert(
  (
    select p1.rank_position < p2.rank_position
      and p2.rank_position < p4.rank_position
      and p4.rank_position < p5.rank_position
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 1) as p1
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 2) as p2
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 4) as p4
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 5) as p5
  ),
  'B: MD91 ranks by matchday points'
);

select pg_temp.mdl_assert(
  (
    select p1.rank_position = p3.rank_position
      and p1.rank_position = 1
      and p2.rank_position = 3
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 1) as p1
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 3) as p3
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 2) as p2
  ),
  'G: full tie shares RANK() 1 and the next player is rank 3'
);

select pg_temp.mdl_assert(
  (
    select p4.total_points = p6.total_points
      and p4.exact_scores = p6.exact_scores
      and p4.correct_results = p6.correct_results
      and p4.missed_predictions < p6.missed_predictions
      and p4.rank_position = p6.rank_position
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 4) as p4
    cross join pg_temp.mdl_row(current_setting('test.md91')::bigint, 6) as p6
  ),
  'open-match gaps are not a live matchday rank key; equal points/exact/correct share RANK()'
);

select pg_temp.mdl_assert(
  (
    select board.total_points = 0
      and board.exact_scores = 0
      and board.correct_results = 0
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 7) as board
  ),
  'active player with zero MD91 predictions still appears at 0'
);

-- ---------------------------------------------------------------------------
-- C / E / F. MD92 Golden Match + exact/correct tie-breaks
-- p2: 5,5,0 = 10 / 2 exact / 0 correct
-- p1: 10,0,0 = 10 / 1 exact / 0 correct   (C: stored Golden Match 10)
-- p3: 2,2,2 = 6 / 0 exact / 3 correct
-- p4: 4,2,0 = 6 / 0 exact / 2 correct
-- p5: 4,2,0 = 6 / 0 exact / 2 correct     (shared with p4)
-- ---------------------------------------------------------------------------

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
values
  (pg_temp.mdl_user_id(1), current_setting('test.md92_m1')::bigint, 2, 1, 10),
  (pg_temp.mdl_user_id(1), current_setting('test.md92_m2')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(1), current_setting('test.md92_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(2), current_setting('test.md92_m1')::bigint, 2, 1, 5),
  (pg_temp.mdl_user_id(2), current_setting('test.md92_m2')::bigint, 1, 0, 5),
  (pg_temp.mdl_user_id(2), current_setting('test.md92_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(3), current_setting('test.md92_m1')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(3), current_setting('test.md92_m2')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(3), current_setting('test.md92_m3')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(4), current_setting('test.md92_m1')::bigint, 1, 0, 4),
  (pg_temp.mdl_user_id(4), current_setting('test.md92_m2')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(4), current_setting('test.md92_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(5), current_setting('test.md92_m1')::bigint, 1, 0, 4),
  (pg_temp.mdl_user_id(5), current_setting('test.md92_m2')::bigint, 1, 1, 2),
  (pg_temp.mdl_user_id(5), current_setting('test.md92_m3')::bigint, 0, 3, 0),
  (pg_temp.mdl_user_id(1), current_setting('test.ko91_m1')::bigint, 2, 1, 5);

select pg_temp.mdl_assert(
  (
    select board.total_points = 10
      and board.exact_scores = 1
      and board.correct_results = 0
    from pg_temp.mdl_row(current_setting('test.md92')::bigint, 1) as board
  ),
  'C: Golden Match stored 10 counts as MD92 points and as an exact'
);

select pg_temp.mdl_assert(
  (
    select p2.total_points = p1.total_points
      and p2.exact_scores > p1.exact_scores
      and p2.rank_position < p1.rank_position
    from pg_temp.mdl_row(current_setting('test.md92')::bigint, 1) as p1
    cross join pg_temp.mdl_row(current_setting('test.md92')::bigint, 2) as p2
  ),
  'E: equal matchday points, more exact scores rank higher'
);

select pg_temp.mdl_assert(
  (
    select p3.total_points = p4.total_points
      and p3.exact_scores = p4.exact_scores
      and p3.correct_results > p4.correct_results
      and p3.rank_position < p4.rank_position
    from pg_temp.mdl_row(current_setting('test.md92')::bigint, 3) as p3
    cross join pg_temp.mdl_row(current_setting('test.md92')::bigint, 4) as p4
  ),
  'F: equal points and exact, more correct results rank higher'
);

select pg_temp.mdl_assert(
  (
    select p4.rank_position = p5.rank_position
    from pg_temp.mdl_row(current_setting('test.md92')::bigint, 4) as p4
    cross join pg_temp.mdl_row(current_setting('test.md92')::bigint, 5) as p5
  ),
  'G: remaining full MD92 tie shares RANK()'
);

select pg_temp.mdl_assert(
  (
    select board.total_points = 12
    from pg_temp.mdl_row(current_setting('test.md91')::bigint, 1) as board
  ),
  'J: knockout prediction points do not change MD91 totals'
);

select pg_temp.mdl_assert(
  (
    select board.total_points = 5
      and board.exact_scores = 1
    from public.get_knockout_leaderboard() as board
    where board.user_id = pg_temp.mdl_user_id(1)
  ),
  'J: knockout RPC includes only knockout/Final prediction points'
);

select pg_temp.mdl_assert(
  (
    select leaderboard.knockout_points = knockout.total_points
    from public.get_leaderboard() as leaderboard
    join public.get_knockout_leaderboard() as knockout
      on knockout.user_id = leaderboard.user_id
    where leaderboard.user_id = pg_temp.mdl_user_id(1)
  ),
  'knockout RPC total matches get_leaderboard().knockout_points'
);

select pg_temp.mdl_assert(
  to_regprocedure('public.get_leaderboard()') is not null,
  'overall get_leaderboard remains available'
);

select pg_temp.mdl_add_player(8);
update public.profiles
set status = 'disabled'
where id = pg_temp.mdl_user_id(8);

select pg_temp.mdl_assert(
  not exists (
    select 1
    from public.get_matchday_leaderboard(current_setting('test.md91')::bigint)
      as board
    where board.user_id = pg_temp.mdl_user_id(8)
  ),
  'disabled profiles are absent from the matchday leaderboard'
);

select pg_temp.mdl_assert(
  position('email' in lower(pg_get_functiondef(
    'public.get_matchday_leaderboard(bigint)'::regprocedure
  ))) = 0,
  'matchday RPC does not select email'
);

rollback;
