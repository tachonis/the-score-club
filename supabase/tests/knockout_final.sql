-- Transactional Knockout & Final scoring verification.
-- Every fixture mutation is rolled back at the end. Admin results supplied to
-- set_match_result are the official 90-minute + stoppage-time score; the
-- schema has no extra-time, penalty or qualifier fields.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.ko_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'KNOCKOUT FINAL TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.ko_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((8800 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.ko_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.ko_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'knockout-final-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzko' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.ko_matchday_id(p_stage text, p_number integer)
returns bigint
language sql
stable
as $helper$
  select matchday.id
  from public.matchdays as matchday
  where matchday.stage = p_stage
    and matchday.matchday_number = p_number;
$helper$;

create function pg_temp.ko_add_match(
  p_stage text,
  p_number integer,
  p_kickoff timestamptz
)
returns bigint
language plpgsql
as $helper$
declare
  v_match_id bigint;
begin
  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    pg_temp.ko_matchday_id(p_stage, p_number),
    current_setting('test.team_home')::bigint,
    current_setting('test.team_away')::bigint,
    p_kickoff,
    'scheduled'
  )
  returning id into v_match_id;

  return v_match_id;
end;
$helper$;

create function pg_temp.ko_points(p_user_index integer, p_match_id bigint)
returns integer
language sql
stable
as $helper$
  select prediction.points
  from public.predictions as prediction
  where prediction.user_id = pg_temp.ko_user_id(p_user_index)
    and prediction.match_id = p_match_id;
$helper$;

create function pg_temp.ko_lb(p_user_index integer)
returns table (
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  knockout_points bigint,
  missed_predictions bigint
)
language sql
stable
as $helper$
  select
    leaderboard.total_points,
    leaderboard.exact_scores,
    leaderboard.correct_results,
    leaderboard.knockout_points,
    leaderboard.missed_predictions
  from public.get_leaderboard() as leaderboard
  where leaderboard.user_id = pg_temp.ko_user_id(p_user_index);
$helper$;

create function pg_temp.ko_lb_total(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select total_points from pg_temp.ko_lb(p_user_index);
$helper$;

create function pg_temp.ko_lb_exact(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select exact_scores from pg_temp.ko_lb(p_user_index);
$helper$;

create function pg_temp.ko_lb_correct(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select correct_results from pg_temp.ko_lb(p_user_index);
$helper$;

create function pg_temp.ko_lb_knockout(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select knockout_points from pg_temp.ko_lb(p_user_index);
$helper$;

create function pg_temp.ko_lb_missed(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select missed_predictions from pg_temp.ko_lb(p_user_index);
$helper$;

create function pg_temp.ko_knockout_prediction_points(p_user_index integer)
returns bigint
language sql
stable
as $helper$
  select coalesce(sum(prediction.points), 0)
  from public.predictions as prediction
  join public.matches as match_row
    on match_row.id = prediction.match_id
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where prediction.user_id = pg_temp.ko_user_id(p_user_index)
    and matchday.stage <> 'league_phase';
$helper$;

create function pg_temp.ko_standings_fingerprint()
returns text
language sql
stable
as $helper$
  select md5(coalesce(string_agg(
    standing.position::text
      || ':' || standing.team_id::text
      || ':' || standing.played::text
      || ':' || standing.points::text
      || ':' || standing.goals_for::text
      || ':' || standing.goals_against::text,
    '|'
    order by standing.position, standing.team_id
  ), ''))
  from public.league_phase_standings as standing;
$helper$;

create function pg_temp.ko_cup_fingerprint()
returns text
language sql
stable
as $helper$
  select md5(coalesce(string_agg(line, '|' order by line), ''))
  from (
    select 'competitions:' || count(*)::text as line
    from public.cup_competitions
    union all
    select 'awards:' || count(*)::text
    from public.cup_awards
    union all
    select 'ties:' || count(*)::text
    from public.cup_ties
    union all
    select 'excluded:' || count(*)::text
    from public.cup_excluded_matches
    union all
    select 'round:' || round.id::text || ':' || round.status
    from public.cup_rounds as round
    union all
    select
      'award:'
      || award.id::text
      || ':'
      || coalesce(award.user_id::text, '-')
      || ':'
      || award.award_type
      || ':'
      || award.points::text
    from public.cup_awards as award
  ) as state;
$helper$;

create function pg_temp.ko_expect_rejected_golden_match(
  p_match_id bigint,
  p_message text
)
returns void
language plpgsql
as $helper$
begin
  begin
    perform public.set_golden_match(p_match_id);
    raise exception
      'KNOCKOUT FINAL TEST FAILED: Golden Match was accepted on a non-League-Phase match';
  exception
    when sqlstate '22023' then
      if sqlerrm <> 'Golden Match is available only during the League Phase' then
        raise exception
          'KNOCKOUT FINAL TEST FAILED: % (got: %)',
          p_message,
          sqlerrm;
      end if;
  end;
end;
$helper$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

select pg_temp.ko_add_player(1);
select pg_temp.ko_add_player(2);
select pg_temp.ko_add_player(3);
select pg_temp.ko_add_player(4);
select pg_temp.ko_add_player(5);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.ko_user_id(1);

insert into public.teams (name, short_name)
values
  ('ZZ Knockout Test Home', 'ZZH'),
  ('ZZ Knockout Test Away', 'ZZA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Knockout Test Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Knockout Test Away'
  ),
  true
);

insert into public.matchdays (stage, matchday_number, name)
values
  ('league_phase', 1, '1η αγωνιστική'),
  ('league_phase', 2, '2η αγωνιστική'),
  ('playoff', 1, 'Play-offs — Πρώτος αγώνας'),
  ('playoff', 2, 'Play-offs — Δεύτερος αγώνας'),
  ('round_of_16', 2, 'Φάση των 16 — Δεύτερος αγώνας'),
  ('quarter_final', 1, 'Προημιτελικά — Πρώτος αγώνας'),
  ('semi_final', 1, 'Ημιτελικά — Πρώτος αγώνας'),
  ('final', 1, 'Τελικός')
on conflict (stage, matchday_number) do nothing;

select pg_temp.ko_assert(
  pg_temp.ko_matchday_id('league_phase', 1) is not null
  and pg_temp.ko_matchday_id('league_phase', 2) is not null
  and pg_temp.ko_matchday_id('playoff', 1) is not null
  and pg_temp.ko_matchday_id('playoff', 2) is not null
  and pg_temp.ko_matchday_id('round_of_16', 2) is not null
  and pg_temp.ko_matchday_id('quarter_final', 1) is not null
  and pg_temp.ko_matchday_id('semi_final', 1) is not null
  and pg_temp.ko_matchday_id('final', 1) is not null,
  'required matchdays exist for the fixture'
);

select set_config(
  'test.playoff_l1',
  pg_temp.ko_add_match('playoff', 1, now() + interval '7 days')::text,
  true
);
select set_config(
  'test.playoff_l2',
  pg_temp.ko_add_match('playoff', 2, now() + interval '14 days')::text,
  true
);
select set_config(
  'test.r16_l2',
  pg_temp.ko_add_match('round_of_16', 2, now() + interval '21 days')::text,
  true
);
select set_config(
  'test.qf_l1',
  pg_temp.ko_add_match('quarter_final', 1, now() + interval '28 days')::text,
  true
);
select set_config(
  'test.sf_l1',
  pg_temp.ko_add_match('semi_final', 1, now() + interval '35 days')::text,
  true
);
select set_config(
  'test.final',
  pg_temp.ko_add_match('final', 1, now() + interval '42 days')::text,
  true
);
select set_config(
  'test.unmatched',
  pg_temp.ko_add_match('playoff', 1, now() + interval '8 days')::text,
  true
);
select set_config(
  'test.league_md1',
  pg_temp.ko_add_match('league_phase', 1, now() + interval '2 days')::text,
  true
);
select set_config(
  'test.league_md2_gm',
  pg_temp.ko_add_match('league_phase', 2, now() + interval '3 days')::text,
  true
);

select pg_temp.ko_assert(
  current_setting('test.playoff_l1')::bigint
    is distinct from current_setting('test.playoff_l2')::bigint,
  'first and second legs are separate matches'
);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
values
  (pg_temp.ko_user_id(2), current_setting('test.playoff_l1')::bigint, 2, 1),
  (pg_temp.ko_user_id(2), current_setting('test.playoff_l2')::bigint, 1, 0),
  (pg_temp.ko_user_id(2), current_setting('test.r16_l2')::bigint, 2, 1),
  (pg_temp.ko_user_id(2), current_setting('test.qf_l1')::bigint, 2, 1),
  (pg_temp.ko_user_id(2), current_setting('test.sf_l1')::bigint, 2, 1),
  (pg_temp.ko_user_id(2), current_setting('test.final')::bigint, 2, 1),
  (pg_temp.ko_user_id(4), current_setting('test.league_md1')::bigint, 2, 1),
  (pg_temp.ko_user_id(5), current_setting('test.league_md2_gm')::bigint, 2, 1);

select set_config('test.standings_before', pg_temp.ko_standings_fingerprint(), true);
select set_config('test.cup_before', pg_temp.ko_cup_fingerprint(), true);

-- ---------------------------------------------------------------------------
-- F. Golden Match isolation
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.ko_user_id(2)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select pg_temp.ko_expect_rejected_golden_match(
  current_setting('test.playoff_l2')::bigint,
  'playoff matchday 2 must reject Golden Match'
);
select pg_temp.ko_expect_rejected_golden_match(
  current_setting('test.r16_l2')::bigint,
  'round_of_16 matchday 2 must reject Golden Match'
);
select pg_temp.ko_expect_rejected_golden_match(
  current_setting('test.final')::bigint,
  'final must reject Golden Match'
);

select pg_temp.ko_assert(
  not exists (
    select 1
    from public.golden_match_selections as selection
    where selection.user_id in (
      pg_temp.ko_user_id(2),
      pg_temp.ko_user_id(3),
      pg_temp.ko_user_id(4),
      pg_temp.ko_user_id(5)
    )
  ),
  'rejected Golden Match calls wrote no selections'
);

reset role;

-- ---------------------------------------------------------------------------
-- Scoring as admin. p_home_score / p_away_score are 90-minute scores.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.ko_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- A. Play-off first leg: 5 / 2 / 0, then leave exact 5
select public.set_match_result(
  current_setting('test.playoff_l1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 5,
  'playoff first-leg exact score awards 5'
);

select public.set_match_result(
  current_setting('test.playoff_l1')::bigint, 3, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 2,
  'playoff first-leg correct result awards 2'
);

select public.set_match_result(
  current_setting('test.playoff_l1')::bigint, 0, 0
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 0,
  'playoff first-leg wrong prediction awards 0'
);

select public.set_match_result(
  current_setting('test.playoff_l1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 5,
  'playoff first-leg correction restores exact 5'
);

-- B. Play-off second leg is independent
select public.set_match_result(
  current_setting('test.playoff_l2')::bigint, 1, 0
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l2')::bigint) = 5
  and pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 5,
  'playoff second-leg exact 5 does not change first-leg points'
);

select public.set_match_result(
  current_setting('test.playoff_l2')::bigint, 2, 0
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l2')::bigint) = 2
  and pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 5,
  'playoff second-leg correct 2 leaves first-leg at 5'
);

select public.set_match_result(
  current_setting('test.playoff_l2')::bigint, 0, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l2')::bigint) = 0
  and pg_temp.ko_points(2, current_setting('test.playoff_l1')::bigint) = 5,
  'playoff second-leg wrong 0 leaves first-leg at 5'
);

select public.set_match_result(
  current_setting('test.playoff_l2')::bigint, 1, 0
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.playoff_l2')::bigint) = 5,
  'playoff second-leg correction restores exact 5'
);

-- E. Non-final knockout correction on the quarter-final
select public.set_match_result(
  current_setting('test.qf_l1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.qf_l1')::bigint) = 5,
  'quarter-final exact score awards 5'
);

select public.set_match_result(
  current_setting('test.qf_l1')::bigint, 4, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.qf_l1')::bigint) = 2,
  'quarter-final correction to a correct result awards 2'
);

select public.set_match_result(
  current_setting('test.qf_l1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.qf_l1')::bigint) = 5,
  'quarter-final correction restores exact 5 without leftover points'
);

-- Remaining knockout stages at exact 5 so knockout_points can include them
select public.set_match_result(
  current_setting('test.r16_l2')::bigint, 2, 1
);
select public.set_match_result(
  current_setting('test.sf_l1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.r16_l2')::bigint) = 5
  and pg_temp.ko_points(2, current_setting('test.sf_l1')::bigint) = 5,
  'round of 16 and semi-final exact scores award 5'
);

-- C / D. Final 10 / 4 / 0 and correction
select public.set_match_result(
  current_setting('test.final')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 10,
  'final exact score awards 10'
);

select public.set_match_result(
  current_setting('test.final')::bigint, 3, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 4,
  'final correct result awards 4'
);

select public.set_match_result(
  current_setting('test.final')::bigint, 0, 2
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 0,
  'final wrong prediction awards 0'
);

select public.set_match_result(
  current_setting('test.final')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 10,
  'final correction restores exact 10'
);

do $test$
declare
  v_changed bigint;
begin
  select result.changed_predictions
  into v_changed
  from public.set_match_result(
    current_setting('test.final')::bigint,
    2,
    1
  ) as result;

  perform pg_temp.ko_assert(
    v_changed = 0
    and pg_temp.ko_points(2, current_setting('test.final')::bigint) = 10,
    'repeating the same final result is idempotent'
  );
end;
$test$;

-- J. Missed prediction: finished knockout match with no prediction row
select set_config(
  'test.missed_before_unmatched',
  pg_temp.ko_lb_missed(3)::text,
  true
);
select set_config(
  'test.scorer_missed_before_unmatched',
  pg_temp.ko_lb_missed(2)::text,
  true
);

select public.set_match_result(
  current_setting('test.unmatched')::bigint, 1, 1
);

select pg_temp.ko_assert(
  pg_temp.ko_lb_missed(3)
    = current_setting('test.missed_before_unmatched')::bigint + 1,
  'a finished knockout match with no prediction increases missed_predictions'
);
select pg_temp.ko_assert(
  pg_temp.ko_lb_missed(2)
    = current_setting('test.scorer_missed_before_unmatched')::bigint + 1,
  'a player who did not predict the unmatched knockout match is also counted missed'
);
select pg_temp.ko_assert(
  not exists (
    select 1
    from public.predictions as prediction
    where prediction.match_id = current_setting('test.unmatched')::bigint
  ),
  'the unmatched knockout match still has no prediction rows'
);

reset role;

-- ---------------------------------------------------------------------------
-- H. Final + Golden Match cannot stack (RPC cannot create the row; scoring
--    still stays 10/4/0 if a selection is planted directly)
-- ---------------------------------------------------------------------------

insert into public.golden_match_selections (
  user_id,
  matchday_id,
  match_id
)
values (
  pg_temp.ko_user_id(2),
  pg_temp.ko_matchday_id('final', 1),
  current_setting('test.final')::bigint
);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.ko_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(
  current_setting('test.final')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 10,
  'a planted Final Golden Match row still scores exact 10, never 20'
);

select public.set_match_result(
  current_setting('test.final')::bigint, 3, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 4,
  'a planted Final Golden Match row still scores correct 4, never 8'
);

select public.set_match_result(
  current_setting('test.final')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(2, current_setting('test.final')::bigint) = 10
  and not exists (
    select 1
    from public.predictions as prediction
    where prediction.user_id = pg_temp.ko_user_id(2)
      and prediction.points in (8, 20)
  ),
  'no prediction was awarded stacked 20 or 8 points'
);

-- K / L. Knockout scoring must not touch Players Cup or League Phase standings
select pg_temp.ko_assert(
  pg_temp.ko_cup_fingerprint() = current_setting('test.cup_before'),
  'scoring knockout matches does not alter Players Cup state'
);
select pg_temp.ko_assert(
  pg_temp.ko_standings_fingerprint() = current_setting('test.standings_before'),
  'knockout results do not change league_phase_standings'
);

-- League Phase points must not enter knockout_points. Scored after the
-- standings fingerprint so this result cannot mask a knockout leak.
select public.set_match_result(
  current_setting('test.league_md1')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(4, current_setting('test.league_md1')::bigint) = 5,
  'league phase exact score still awards 5'
);

-- ---------------------------------------------------------------------------
-- I. Leaderboard knockout_points
-- ---------------------------------------------------------------------------

select pg_temp.ko_assert(
  pg_temp.ko_lb_knockout(2)
    = pg_temp.ko_knockout_prediction_points(2)
  and pg_temp.ko_lb_knockout(2) = 35,
  'knockout_points is 5+5+5+5+5+10 from playoff, R16, QF, SF and Final'
);

select pg_temp.ko_assert(
  pg_temp.ko_lb_total(4) = 5
  and pg_temp.ko_lb_knockout(4) = 0,
  'league phase prediction points are excluded from knockout_points'
);

select pg_temp.ko_assert(
  pg_temp.ko_lb_exact(2) = 6
  and pg_temp.ko_lb_correct(2) = 0,
  'final 10 counts as exact, not as a correct-result tie-break'
);

reset role;

insert into public.long_term_predictions (
  user_id,
  prediction_type,
  team_id
)
values (
  pg_temp.ko_user_id(2),
  'winner',
  current_setting('test.team_home')::bigint
);

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values (
  pg_temp.ko_user_id(2),
  'winner',
  current_setting('test.team_home')::bigint,
  current_setting('test.team_home')::bigint,
  30
);

select pg_temp.ko_assert(
  pg_temp.ko_lb_knockout(2) = 35
  and pg_temp.ko_lb_total(2) = 65
  and not exists (
    select 1
    from public.cup_awards as award
    where award.user_id = pg_temp.ko_user_id(2)
  ),
  'long-term awards raise total_points only; cup_awards stay out of knockout_points'
);

-- ---------------------------------------------------------------------------
-- G. League Phase MD2 Golden Match regression
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.ko_user_id(5)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_golden_match(
  current_setting('test.league_md2_gm')::bigint
);

select pg_temp.ko_assert(
  exists (
    select 1
    from public.golden_match_selections as selection
    where selection.user_id = pg_temp.ko_user_id(5)
      and selection.match_id = current_setting('test.league_md2_gm')::bigint
  ),
  'league phase matchday 2 Golden Match selection still succeeds'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.ko_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(
  current_setting('test.league_md2_gm')::bigint, 2, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(5, current_setting('test.league_md2_gm')::bigint) = 10
  and pg_temp.ko_lb_knockout(5) = 0,
  'league phase Golden Match exact still awards 10 and is not knockout_points'
);

select public.set_match_result(
  current_setting('test.league_md2_gm')::bigint, 3, 1
);
select pg_temp.ko_assert(
  pg_temp.ko_points(5, current_setting('test.league_md2_gm')::bigint) = 4,
  'league phase Golden Match correct result still awards 4'
);

select public.set_match_result(
  current_setting('test.league_md2_gm')::bigint, 0, 0
);
select pg_temp.ko_assert(
  pg_temp.ko_points(5, current_setting('test.league_md2_gm')::bigint) = 0,
  'league phase Golden Match wrong prediction still awards 0'
);

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzko%'
  ) then
    raise exception 'KNOCKOUT FINAL TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'playoff_first_leg_5_2_0',
  'playoff_second_leg_independent_5_2_0',
  'quarter_final_correction_safe',
  'round_of_16_and_semi_final_exact_5',
  'final_exact_10',
  'final_correct_4',
  'final_wrong_0',
  'final_correction_and_idempotence',
  'golden_match_rejected_on_playoff_md2',
  'golden_match_rejected_on_round_of_16_md2',
  'golden_match_rejected_on_final',
  'planted_final_golden_match_does_not_stack',
  'league_phase_md2_golden_match_10_4_0',
  'knockout_points_include_all_knockout_stages',
  'league_phase_excluded_from_knockout_points',
  'long_term_awards_excluded_from_knockout_points',
  'missed_knockout_prediction_increments',
  'players_cup_untouched_by_knockout_results',
  'league_phase_standings_untouched_by_knockout_results',
  'all_fixture_changes_rolled_back'
]) as passed_test;
