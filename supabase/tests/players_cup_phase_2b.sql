-- Transactional Players Cup (phase 2B) verification.
-- Phase 2B does not own scoring, layout or awards: it wires the existing
-- engine into set_match_result and get_leaderboard. The fixture therefore
-- drives those two production functions and never calls players_cup_apply
-- except where a test is explicitly proving recovery/idempotence.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.cup_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'PLAYERS CUP 2B TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.cup_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((1000 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.cup_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.cup_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'players-cup-2b-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzc2b' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.cup_id()
returns bigint
language sql
stable
as $helper$
  select competition.id
  from public.cup_competitions as competition
  where competition.slug = 'players-cup-2026-27';
$helper$;

create function pg_temp.cup_matchday_id(p_matchday_number integer)
returns bigint
language sql
stable
as $helper$
  select matchday.id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = p_matchday_number;
$helper$;

create function pg_temp.cup_round_id(p_round_number integer)
returns bigint
language sql
stable
as $helper$
  select round.id
  from public.cup_rounds as round
  where round.cup_id = pg_temp.cup_id()
    and round.round_number = p_round_number;
$helper$;

create function pg_temp.cup_participant_id(p_index integer)
returns bigint
language sql
stable
as $helper$
  select participant.id
  from public.cup_participants as participant
  where participant.cup_id = pg_temp.cup_id()
    and participant.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_tie(p_round_number integer, p_slot integer)
returns public.cup_ties
language sql
stable
as $helper$
  select tie.*
  from public.cup_ties as tie
  where tie.round_id = pg_temp.cup_round_id(p_round_number)
    and tie.slot = p_slot;
$helper$;

create function pg_temp.cup_state()
returns text
language sql
stable
as $helper$
  select string_agg(line, '|' order by line)
  from (
    select format(
      'tie:%s:%s:%s-%s:%s:%s:%s:%s:%s:%s:%s:%s',
      round.round_number,
      tie.slot,
      coalesce(home_participant.rank_position::text, '-'),
      coalesce(away_participant.rank_position::text, '-'),
      tie.outcome,
      coalesce(winner_participant.rank_position::text, '-'),
      coalesce(tie.decided_by_rule, '-'),
      tie.home_points,
      tie.away_points,
      tie.home_exact,
      tie.away_exact,
      tie.home_correct || ':' || tie.away_correct
    ) as line
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    left join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    left join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
    left join public.cup_participants as winner_participant
      on winner_participant.id = tie.winner_participant_id
    where tie.cup_id = pg_temp.cup_id()
    union all
    select format('round:%s:%s', round.round_number, round.status)
    from public.cup_rounds as round
    where round.cup_id = pg_temp.cup_id()
    union all
    select format(
      'award:%s:%s:%s',
      participant.rank_position,
      award.award_type,
      award.points
    )
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    where award.cup_id = pg_temp.cup_id()
    union all
    select format('competition:%s', competition.status)
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) as state;
$helper$;

create function pg_temp.cup_add_matches(
  p_matchday_number integer,
  p_count integer,
  p_kickoff timestamptz
)
returns void
language plpgsql
as $helper$
begin
  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  select
    pg_temp.cup_matchday_id(p_matchday_number),
    current_setting('test.team_a')::bigint,
    current_setting('test.team_b')::bigint,
    p_kickoff + (slot.number || ' minutes')::interval,
    'scheduled'
  from generate_series(1, p_count) as slot(number);
end;
$helper$;

create function pg_temp.cup_open_matchday(p_matchday_number integer)
returns void
language plpgsql
as $helper$
begin
  update public.matches as match_row
  set
    kickoff_at = now()
      - ((10 - p_matchday_number) || ' hours')::interval
      + (match_row.id % 30 || ' seconds')::interval,
    updated_at = now()
  where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number);
end;
$helper$;

create function pg_temp.cup_predict_matchday(
  p_matchday_number integer,
  p_from integer,
  p_to integer
)
returns void
language plpgsql
as $helper$
declare
  v_index integer;
  v_match record;
  v_quality integer;
begin
  for v_index in p_from..p_to loop
    for v_match in
      select
        match_row.id,
        row_number() over (order by match_row.id)::integer as position
      from public.matches as match_row
      where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number)
      order by match_row.id
    loop
      v_quality := abs(
        hashtext(v_index::text || ':' || v_match.position::text) % 3
      );

      insert into public.predictions (
        user_id,
        match_id,
        predicted_home_score,
        predicted_away_score
      )
      values (
        pg_temp.cup_user_id(v_index),
        v_match.id,
        case v_quality when 0 then 1 when 1 then 2 else 0 end,
        case v_quality when 0 then 0 when 1 then 0 else 1 end
      )
      on conflict (user_id, match_id) do update
      set
        predicted_home_score = excluded.predicted_home_score,
        predicted_away_score = excluded.predicted_away_score;
    end loop;
  end loop;
end;
$helper$;

-- Production path: every football result goes through set_match_result, which
-- is what Phase 2B is integrating. There is no manual apply in this helper.
create function pg_temp.cup_score_matchday(
  p_matchday_number integer,
  p_home_score integer,
  p_away_score integer
)
returns void
language plpgsql
as $helper$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number)
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, p_home_score, p_away_score);
  end loop;
end;
$helper$;

create function pg_temp.cup_prediction_points(p_index integer)
returns bigint
language sql
stable
as $helper$
  select coalesce(sum(prediction.points), 0)::bigint
  from public.predictions as prediction
  where prediction.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_award_points(p_index integer)
returns bigint
language sql
stable
as $helper$
  select coalesce(sum(award.points), 0)::bigint
  from public.cup_awards as award
  where award.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_leaderboard_points(p_index integer)
returns bigint
language sql
stable
as $helper$
  select leaderboard.total_points
  from public.get_leaderboard() as leaderboard
  where leaderboard.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_leaderboard_exact(p_index integer)
returns bigint
language sql
stable
as $helper$
  select leaderboard.exact_scores
  from public.get_leaderboard() as leaderboard
  where leaderboard.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_set_result_source()
returns text
language sql
stable
as $helper$
  select pg_get_functiondef(
    'public.set_match_result(bigint, integer, integer)'::regprocedure
  );
$helper$;

-- ---------------------------------------------------------------------------
-- Deterministic fixture
-- ---------------------------------------------------------------------------

insert into public.teams (name, short_name)
values
  ('ZZ Players Cup 2B Test A', 'Z2B'),
  ('ZZ Players Cup 2B Test B', 'Z2C')
on conflict (name) do nothing;

select set_config(
  'test.team_a',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup 2B Test A'
  ),
  true
);
select set_config(
  'test.team_b',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup 2B Test B'
  ),
  true
);

insert into public.matchdays (stage, matchday_number, name)
select
  'league_phase',
  generated.number,
  generated.number || 'η αγωνιστική'
from generate_series(1, 8) as generated(number)
on conflict (stage, matchday_number) do nothing;

insert into public.matchdays (stage, matchday_number, name)
values ('playoff', 1, 'Play-offs')
on conflict (stage, matchday_number) do nothing;

delete from public.matches as match_row
using public.matchdays as matchday
where matchday.id = match_row.matchday_id
  and matchday.stage in ('league_phase', 'playoff');

select pg_temp.cup_add_matches(1, 2, now() - interval '30 days');
select pg_temp.cup_add_matches(2, 2, now() - interval '25 days');
select pg_temp.cup_add_matches(3, 3, now() + interval '3 days');
select pg_temp.cup_add_matches(4, 3, now() + interval '6 days');
select pg_temp.cup_add_matches(5, 3, now() + interval '9 days');
select pg_temp.cup_add_matches(6, 3, now() + interval '12 days');
select pg_temp.cup_add_matches(7, 3, now() + interval '15 days');
select pg_temp.cup_add_matches(8, 3, now() + interval '18 days');

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status
)
values (
  (
    select matchday.id
    from public.matchdays as matchday
    where matchday.stage = 'playoff'
      and matchday.matchday_number = 1
  ),
  current_setting('test.team_a')::bigint,
  current_setting('test.team_b')::bigint,
  now() + interval '40 days',
  'scheduled'
);

select set_config(
  'test.knockout_match',
  (
    select match_row.id::text
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'playoff'
    order by match_row.id
    limit 1
  ),
  true
);

update public.profiles as profile
set status = 'disabled'
where profile.status = 'active';

do $fixture$
declare
  v_index integer;
begin
  for v_index in 1..40 loop
    perform pg_temp.cup_add_player(v_index);
  end loop;
end;
$fixture$;

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.cup_user_id(1);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.cup_user_id(player.index),
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  ),
  case when player.index <= 20 then 1 else 0 end,
  case when player.index <= 20 then 0 else 2 end
from generate_series(1, 40) as player(index);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.cup_user_id(1),
  current_setting('test.knockout_match')::bigint,
  1,
  0;

-- ---------------------------------------------------------------------------
-- 1. No Cup exists: set_match_result behaves exactly as before
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0,
  'the fixture starts without a Cup'
);

select pg_temp.cup_score_matchday(1, 1, 0);
select pg_temp.cup_score_matchday(2, 1, 0);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
      and prediction.points is not null
  ) = 40,
  'Matchday 1 predictions are scored before any Cup exists'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_awards) = 0
  and (select count(*) from public.cup_excluded_matches) = 0
  and (select count(*) from public.cup_ties) = 0,
  'scoring without a Cup writes no Cup tables'
);

select public.set_match_result(
  current_setting('test.knockout_match')::bigint,
  1,
  0
);

select pg_temp.cup_assert(
  (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = pg_temp.cup_user_id(1)
      and prediction.match_id = current_setting('test.knockout_match')::bigint
  ) = 5
  and (select count(*) from public.cup_competitions) = 0,
  'a knockout result still scores predictions when no Cup exists'
);

-- ---------------------------------------------------------------------------
-- 2. Create the Cup. From here, Cup-round results must recompute themselves.
-- ---------------------------------------------------------------------------

set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_assert(
  (
    select competition.participant_count
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 40,
  'the fixture Cup has 40 participants'
);

select set_config('test.state_after_draw', pg_temp.cup_state(), true);

-- ---------------------------------------------------------------------------
-- 3. Lock order is structural in the production function source
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  position('pg_advisory_xact_lock' in pg_temp.cup_set_result_source()) > 0
  and position('players_cup_freeze_exclusions' in pg_temp.cup_set_result_source())
    > position('pg_advisory_xact_lock' in pg_temp.cup_set_result_source())
  and position('for update' in pg_temp.cup_set_result_source())
    > position('players_cup_freeze_exclusions' in pg_temp.cup_set_result_source())
  and position('players_cup_apply' in pg_temp.cup_set_result_source())
    > position('for update' in pg_temp.cup_set_result_source()),
  'set_match_result takes the Cup lock, freezes exclusions, then locks the match, then applies'
);

select pg_temp.cup_assert(
  position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef('public.players_cup_apply(bigint)'::regprocedure)
  ) = 0
  and position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef(
      'public.players_cup_freeze_exclusions(bigint)'::regprocedure
    )
  ) = 0,
  'apply and freeze still assume the caller already holds the Cup lock'
);

-- ---------------------------------------------------------------------------
-- 4. Classifier centralisation is behaviour-preserving
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  not exists (
    select 1
    from (
      select candidate.points
      from generate_series(0, 12) as candidate(points)
      union all
      select null
    ) as sample
    where public.prediction_is_exact(sample.points)
      is distinct from coalesce(sample.points in (5, 10), false)
      or public.prediction_is_correct(sample.points)
        is distinct from coalesce(sample.points in (2, 4), false)
  ),
  'the classifiers remain equivalent to the previous inline 5/10 and 2/4 filters'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.get_leaderboard() as leaderboard
    where leaderboard.exact_scores is distinct from (
      select count(*)
      from public.predictions as prediction
      where prediction.user_id = leaderboard.user_id
        and prediction.points in (5, 10)
    )
    or leaderboard.correct_results is distinct from (
      select count(*)
      from public.predictions as prediction
      where prediction.user_id = leaderboard.user_id
        and prediction.points in (2, 4)
    )
  ),
  'leaderboard exact and correct counts still match the stored prediction points'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.players_cup_ranking() as ranking
    where ranking.exact_scores is distinct from (
      select count(*)
      from public.predictions as prediction
      join public.matches as match_row
        on match_row.id = prediction.match_id
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where prediction.user_id = ranking.user_id
        and matchday.stage = 'league_phase'
        and matchday.matchday_number between 1 and 2
        and prediction.points in (5, 10)
    )
  ),
  'Cup ranking exact counts still match Matchday 1 and 2 predictions only'
);

-- ---------------------------------------------------------------------------
-- 5. MD1, MD2 and knockout results are Cup no-ops
-- ---------------------------------------------------------------------------

select public.set_match_result(
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  ),
  2,
  0
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_after_draw'),
  'a Matchday 1 correction does not recompute the Cup'
);

select public.set_match_result(
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  ),
  1,
  0
);

select public.set_match_result(
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(2)
  ),
  1,
  0
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_after_draw'),
  'a Matchday 2 result does not recompute the Cup'
);

select public.set_match_result(
  current_setting('test.knockout_match')::bigint,
  2,
  1
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_after_draw')
  and (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = pg_temp.cup_user_id(1)
      and prediction.match_id = current_setting('test.knockout_match')::bigint
  ) = 2,
  'a knockout result does not recompute the Cup and still rescores predictions'
);

select public.set_match_result(
  current_setting('test.knockout_match')::bigint,
  1,
  0
);

-- ---------------------------------------------------------------------------
-- 6. Postponed cutoff through the production result path
-- ---------------------------------------------------------------------------

savepoint cutoff_integration;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

select pg_temp.cup_open_matchday(4);

select pg_temp.cup_assert(
  (select count(*) from public.cup_excluded_matches) = 0
  and (
    select match_row.status
    from public.matches as match_row
    where match_row.id = current_setting('test.postponed_match')::bigint
  ) = 'postponed',
  'the cutoff has passed with nothing frozen and the match still unfinished'
);

select set_config(
  'test.cutoff_scores_before',
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ),
  true
);

savepoint mutation_freeze;

create or replace function public.players_cup_freeze_exclusions(p_cup_id bigint)
returns integer
language sql
volatile
security definer
set search_path = ''
as $mutant$
  select 0;
$mutant$;

do $test$
begin
  begin
    perform public.set_match_result(
      current_setting('test.postponed_match')::bigint,
      1,
      0
    );

    if (
      select state.excluded_count
      from public.players_cup_matchday_state(pg_temp.cup_id()) as state
      where state.round_number = 1
    ) <> 1 then
      raise exception 'PLAYERS CUP 2B MUTATION DETECTED';
    end if;

    raise exception
      'PLAYERS CUP 2B TEST FAILED: the skipped freeze mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_freeze;

select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);

select pg_temp.cup_assert(
  (
    select match_row.status
    from public.matches as match_row
    where match_row.id = current_setting('test.postponed_match')::bigint
  ) = 'finished',
  'the late result still finishes the football match'
);

select pg_temp.cup_assert(
  exists (
    select 1
    from public.predictions as prediction
    where prediction.match_id = current_setting('test.postponed_match')::bigint
      and prediction.points is not null
  ),
  'the late result still scores prediction points for the leaderboard'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_excluded_matches as excluded_match
    where excluded_match.match_id
      = current_setting('test.postponed_match')::bigint
  ) = 1,
  'set_match_result freezes the exclusion before the match is finished'
);

select pg_temp.cup_assert(
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ) = current_setting('test.cutoff_scores_before'),
  'late prediction points do not enter Cup Round 1'
);

select pg_temp.cup_assert(
  (
    select state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 1
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'decided'
  ) = 8,
  'Round 1 closes on the included matches alone'
);

rollback to savepoint cutoff_integration;

-- ---------------------------------------------------------------------------
-- 7. Transaction atomicity: a Cup failure rolls the football result back
-- ---------------------------------------------------------------------------

savepoint atomicity_test;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.atomic_match',
  (
    select min(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);
select set_config('test.atomic_cup_state', pg_temp.cup_state(), true);

create or replace function public.players_cup_apply(p_cup_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $mutant$
begin
  raise exception using
    errcode = 'P0001',
    message = 'forced Cup recompute failure';
end;
$mutant$;

do $test$
begin
  begin
    perform public.set_match_result(
      current_setting('test.atomic_match')::bigint,
      1,
      0
    );
    raise exception
      'PLAYERS CUP 2B TEST FAILED: set_match_result ignored a Cup failure';
  exception
    when others then
      if position('ignored a Cup failure' in sqlerrm) > 0 then
        raise;
      end if;
      if sqlerrm not like '%forced Cup recompute failure%' then
        raise;
      end if;
  end;
end;
$test$;

select pg_temp.cup_assert(
  (
    select match_row.status
    from public.matches as match_row
    where match_row.id = current_setting('test.atomic_match')::bigint
  ) = 'scheduled'
  and (
    select match_row.home_score
    from public.matches as match_row
    where match_row.id = current_setting('test.atomic_match')::bigint
  ) is null,
  'a Cup failure leaves the football result uncommitted'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.predictions as prediction
    where prediction.match_id = current_setting('test.atomic_match')::bigint
      and prediction.points is not null
  ),
  'a Cup failure leaves prediction points uncommitted'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.atomic_cup_state'),
  'a Cup failure leaves the derived Cup state uncommitted'
);

rollback to savepoint atomicity_test;

-- ---------------------------------------------------------------------------
-- 8. Automatic progression through MD3 to MD8, no recovery RPC
-- ---------------------------------------------------------------------------

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.first_md3_match',
  (
    select min(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

select public.set_match_result(
  current_setting('test.first_md3_match')::bigint,
  1,
  0
);

select pg_temp.cup_assert(
  exists (
    select 1
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'pending'
      and tie.winner_participant_id is null
      and tie.decided_by_rule is null
      and (tie.home_points > 0 or tie.away_points > 0)
  )
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(2)
      and (
        tie.home_participant_id is not null
        or tie.away_participant_id is not null
      )
  ) > 0
  and (
    select round.status
    from public.cup_rounds as round
    where round.id = pg_temp.cup_round_id(1)
  ) = 'in_progress',
  'the first Matchday 3 result writes interim Cup scores automatically'
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.first_md3_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'decided'
  ) = 8
  and (
    select round.status
    from public.cup_rounds as round
    where round.id = pg_temp.cup_round_id(1)
  ) = 'final',
  'the last required Matchday 3 result resolves Round 1 automatically'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as round_two
    join public.cup_rounds as round
      on round.id = round_two.round_id
    join public.cup_ties as home_feeder
      on home_feeder.round_id = pg_temp.cup_round_id(1)
      and home_feeder.slot = (round_two.slot * 2) - 1
    join public.cup_ties as away_feeder
      on away_feeder.round_id = pg_temp.cup_round_id(1)
      and away_feeder.slot = round_two.slot * 2
    where round.round_number = 2
      and round.cup_id = pg_temp.cup_id()
      and (
        (
          home_feeder.winner_participant_id is not null
          and round_two.home_participant_id
            is distinct from home_feeder.winner_participant_id
        )
        or (
          away_feeder.winner_participant_id is not null
          and round_two.away_participant_id
            is distinct from away_feeder.winner_participant_id
        )
      )
  ),
  'Round 1 winners propagate automatically into Round 2'
);

select pg_temp.cup_open_matchday(4);
select pg_temp.cup_predict_matchday(4, 1, 40);
select pg_temp.cup_score_matchday(4, 1, 0);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(2)
      and tie.outcome = 'decided'
  ) = 16
  and (
    select round.status
    from public.cup_rounds as round
    where round.id = pg_temp.cup_round_id(2)
  ) = 'final',
  'scoring Matchday 4 resolves Round 2 automatically'
);

select pg_temp.cup_open_matchday(5);
select pg_temp.cup_predict_matchday(5, 1, 40);
select pg_temp.cup_score_matchday(5, 1, 0);
select pg_temp.cup_open_matchday(6);
select pg_temp.cup_predict_matchday(6, 1, 40);
select pg_temp.cup_score_matchday(6, 1, 0);
select pg_temp.cup_open_matchday(7);
select pg_temp.cup_predict_matchday(7, 1, 40);
select pg_temp.cup_score_matchday(7, 1, 0);

select pg_temp.cup_assert(
  (select count(*) from public.cup_awards) = 0
  and (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'active',
  'the Cup stays active and award-free until the Final is decided'
);

select set_config(
  'test.lb_before_awards_1',
  pg_temp.cup_leaderboard_points(1)::text,
  true
);
select set_config(
  'test.exact_before_awards',
  (
    select string_agg(
      leaderboard.user_id::text || ':' || leaderboard.exact_scores
        || ':' || leaderboard.correct_results
        || ':' || leaderboard.knockout_points
        || ':' || leaderboard.missed_predictions,
      ',' order by leaderboard.user_id
    )
    from public.get_leaderboard() as leaderboard
  ),
  true
);

select pg_temp.cup_open_matchday(8);
select pg_temp.cup_predict_matchday(8, 1, 40);
select pg_temp.cup_score_matchday(8, 1, 0);

select pg_temp.cup_assert(
  (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'completed'
  and (select count(*) from public.cup_awards) = 4
  and (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'decided',
  'full Matchday 3 to 8 result entry completes the Cup and writes awards'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_awards as award
    group by award.participant_id
    having count(*) > 1
  ),
  'no participant holds more than one Cup award'
);

-- ---------------------------------------------------------------------------
-- 9. Leaderboard: Cup honours only, never Cup matchday points twice
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  (
    select award.award_type || ':' || award.points
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    where award.award_type = 'winner'
  ) = 'winner:50',
  'the champion award is exactly the configured winner_points'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    where pg_temp.cup_leaderboard_points(
      (
        select player.index
        from generate_series(1, 40) as player(index)
        where pg_temp.cup_user_id(player.index) = participant.user_id
      )
    ) is distinct from (
      pg_temp.cup_prediction_points(
        (
          select player.index
          from generate_series(1, 40) as player(index)
          where pg_temp.cup_user_id(player.index) = participant.user_id
        )
      )
      + award.points
    )
  ),
  'an awarded player total is prediction points plus the honour, nothing else'
);

select pg_temp.cup_assert(
  (
    select pg_temp.cup_leaderboard_points(player.index)
      - pg_temp.cup_prediction_points(player.index)
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'winner'
  ) = 30
  and (
    select pg_temp.cup_leaderboard_points(player.index)
      - pg_temp.cup_prediction_points(player.index)
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'finalist'
  ) = 20
  and (
    select array_agg(
      pg_temp.cup_leaderboard_points(player.index)
        - pg_temp.cup_prediction_points(player.index)
      order by player.index
    )
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'semi_finalist'
  ) = array[10, 10]::bigint[],
  'leaderboard totals rise by exactly winner, finalist and semi-finalist points'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(1, 40) as player(index)
    where pg_temp.cup_award_points(player.index) = 0
      and pg_temp.cup_leaderboard_points(player.index)
        is distinct from pg_temp.cup_prediction_points(player.index)
  ),
  'a player without a Cup honour receives no Cup bonus'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.get_leaderboard() as leaderboard
    where leaderboard.exact_scores is distinct from (
      select count(*)
      from public.predictions as prediction
      where prediction.user_id = leaderboard.user_id
        and prediction.points in (5, 10)
    )
    or leaderboard.correct_results is distinct from (
      select count(*)
      from public.predictions as prediction
      where prediction.user_id = leaderboard.user_id
        and prediction.points in (2, 4)
    )
    or leaderboard.knockout_points is distinct from (
      select coalesce(sum(prediction.points), 0)
      from public.predictions as prediction
      join public.matches as match_row
        on match_row.id = prediction.match_id
      join public.matchdays as matchday
        on matchday.id = match_row.matchday_id
      where prediction.user_id = leaderboard.user_id
        and matchday.stage <> 'league_phase'
    )
  ),
  'Cup honours do not change exact, correct or knockout counts'
);

-- If Cup matchday points were added again, the champion delta would exceed
-- winner_points by the points earned in the ties they actually played.
select pg_temp.cup_assert(
  (
    select pg_temp.cup_leaderboard_points(player.index)
      - pg_temp.cup_prediction_points(player.index)
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'winner'
  ) < (
    select 30
      + coalesce(sum(
        case
          when tie.home_participant_id = award.participant_id
            then tie.home_points
          else tie.away_points
        end
      ), 0)
    from public.cup_awards as award
    join public.cup_ties as tie
      on tie.home_participant_id = award.participant_id
      or tie.away_participant_id = award.participant_id
    where award.award_type = 'winner'
      and tie.outcome in ('decided', 'pending')
  ),
  'Cup matchday prediction points are not added a second time'
);

-- ---------------------------------------------------------------------------
-- 10. Reward reconfiguration reaches the leaderboard without code changes
-- ---------------------------------------------------------------------------

savepoint reward_config;

update public.cup_competitions as competition
set
  winner_points = 100,
  finalist_points = 60,
  semi_finalist_points = 20
where competition.id = pg_temp.cup_id();

set local role authenticated;
select public.recompute_players_cup();
reset role;

select pg_temp.cup_assert(
  (
    select array_agg(award.points order by award.award_type, award.participant_id)
    from public.cup_awards as award
  ) = array[60, 20, 20, 100],
  'recompute copies 100/60/20 out of the Cup configuration'
);

select pg_temp.cup_assert(
  (
    select pg_temp.cup_leaderboard_points(player.index)
      - pg_temp.cup_prediction_points(player.index)
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'winner'
  ) = 100
  and (
    select pg_temp.cup_leaderboard_points(player.index)
      - pg_temp.cup_prediction_points(player.index)
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    join generate_series(1, 40) as player(index)
      on pg_temp.cup_user_id(player.index) = participant.user_id
    where award.award_type = 'finalist'
  ) = 60,
  'the leaderboard reads the live Cup honour values, not hardcoded published defaults'
);

rollback to savepoint reward_config;

-- ---------------------------------------------------------------------------
-- 11. A Matchday 3 correction rebuilds the Cup without the recovery RPC
-- ---------------------------------------------------------------------------

create temporary table cup_round_1_before as
select tie.slot, tie.winner_participant_id, tie.decided_by_rule
from public.cup_ties as tie
where tie.round_id = pg_temp.cup_round_id(1);

select set_config('test.state_before_md3_correction', pg_temp.cup_state(), true);

select pg_temp.cup_score_matchday(3, 0, 1);

select pg_temp.cup_assert(
  exists (
    select 1
    from cup_round_1_before as before
    join public.cup_ties as tie
      on tie.round_id = pg_temp.cup_round_id(1)
      and tie.slot = before.slot
    where tie.winner_participant_id
      is distinct from before.winner_participant_id
  ),
  'correcting Matchday 3 through set_match_result changes a Round 1 winner'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from cup_round_1_before as before
    join public.cup_ties as later
      on later.cup_id = pg_temp.cup_id()
    join public.cup_rounds as round
      on round.id = later.round_id
    where round.round_number > 1
      and before.winner_participant_id is not null
      and (
        later.home_participant_id = before.winner_participant_id
        or later.away_participant_id = before.winner_participant_id
      )
      and not exists (
        select 1
        from public.cup_ties as current_round_1
        where current_round_1.round_id = pg_temp.cup_round_id(1)
          and current_round_1.slot = before.slot
          and current_round_1.winner_participant_id
            = before.winner_participant_id
      )
  ),
  'a replaced Round 1 winner disappears from the downstream bracket'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() is distinct from
    current_setting('test.state_before_md3_correction')
  and (select count(*) from public.cup_ties where cup_id = pg_temp.cup_id()) = 63,
  'the correction rebuilds derived Cup state without touching the skeleton'
);

select set_config('test.state_after_md3_correction', pg_temp.cup_state(), true);

set local role authenticated;
select public.recompute_players_cup();
reset role;

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_after_md3_correction'),
  'the recovery RPC leaves the automatically rebuilt Cup unchanged'
);

-- ---------------------------------------------------------------------------
-- 12. Correcting the Final changes the champion and the leaderboard
-- ---------------------------------------------------------------------------

select set_config(
  'test.old_champion_id',
  (select tie.winner_participant_id::text from pg_temp.cup_tie(6, 1) as tie),
  true
);
select set_config(
  'test.old_finalist_id',
  (
    select (
      case
        when tie.home_participant_id = tie.winner_participant_id
          then tie.away_participant_id
        else tie.home_participant_id
      end
    )::text
    from pg_temp.cup_tie(6, 1) as tie
  ),
  true
);

select set_config(
  'test.old_champion_index',
  (
    select player.index::text
    from generate_series(1, 40) as player(index)
    join public.cup_participants as participant
      on participant.user_id = pg_temp.cup_user_id(player.index)
    where participant.id = current_setting('test.old_champion_id')::bigint
  ),
  true
);
select set_config(
  'test.old_finalist_index',
  (
    select player.index::text
    from generate_series(1, 40) as player(index)
    join public.cup_participants as participant
      on participant.user_id = pg_temp.cup_user_id(player.index)
    where participant.id = current_setting('test.old_finalist_id')::bigint
  ),
  true
);

select set_config(
  'test.old_champion_lb',
  pg_temp.cup_leaderboard_points(
    current_setting('test.old_champion_index')::integer
  )::text,
  true
);
select set_config(
  'test.old_finalist_lb',
  pg_temp.cup_leaderboard_points(
    current_setting('test.old_finalist_index')::integer
  )::text,
  true
);

delete from public.predictions as prediction
using public.matches as match_row
where match_row.id = prediction.match_id
  and match_row.matchday_id = pg_temp.cup_matchday_id(8)
  and prediction.user_id = (
    select participant.user_id
    from public.cup_participants as participant
    where participant.id = current_setting('test.old_champion_id')::bigint
  );

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  (
    select participant.user_id
    from public.cup_participants as participant
    where participant.id = current_setting('test.old_finalist_id')::bigint
  ),
  match_row.id,
  1,
  0
from public.matches as match_row
where match_row.matchday_id = pg_temp.cup_matchday_id(8)
on conflict (user_id, match_id) do update
set predicted_home_score = 1, predicted_away_score = 0;

select pg_temp.cup_score_matchday(8, 1, 0);

select pg_temp.cup_assert(
  (select tie.winner_participant_id from pg_temp.cup_tie(6, 1) as tie)
    = current_setting('test.old_finalist_id')::bigint,
  'correcting Matchday 8 through set_match_result changes the champion'
);

select pg_temp.cup_assert(
  (
    select award.award_type
    from public.cup_awards as award
    where award.participant_id = current_setting('test.old_finalist_id')::bigint
  ) = 'winner'
  and (
    select award.award_type
    from public.cup_awards as award
    where award.participant_id = current_setting('test.old_champion_id')::bigint
  ) = 'finalist'
  and (select count(*) from public.cup_awards) = 4,
  'the new champion takes the winner award without a duplicate honour row'
);

select pg_temp.cup_assert(
  pg_temp.cup_leaderboard_points(
    current_setting('test.old_finalist_index')::integer
  )
    - pg_temp.cup_prediction_points(
      current_setting('test.old_finalist_index')::integer
    )
    = 30
  and pg_temp.cup_leaderboard_points(
    current_setting('test.old_champion_index')::integer
  )
    - pg_temp.cup_prediction_points(
      current_setting('test.old_champion_index')::integer
    )
    = 20
  and pg_temp.cup_leaderboard_points(
    current_setting('test.old_finalist_index')::integer
  )
    is distinct from current_setting('test.old_finalist_lb')::bigint
  and pg_temp.cup_leaderboard_points(
    current_setting('test.old_champion_index')::integer
  )
    is distinct from current_setting('test.old_champion_lb')::bigint,
  'leaderboard totals follow the swapped winner and finalist awards'
);

-- ---------------------------------------------------------------------------
-- 13. Repeated result saves stay idempotent
-- ---------------------------------------------------------------------------

select set_config('test.state_before_repeat', pg_temp.cup_state(), true);

select pg_temp.cup_score_matchday(8, 1, 0);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_before_repeat'),
  'saving the same Matchday 8 results again does not change the Cup'
);

-- ---------------------------------------------------------------------------
-- 14. Mutation tests
-- ---------------------------------------------------------------------------

savepoint mutation_apply;

create or replace function public.players_cup_apply(p_cup_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $mutant$
begin
  return jsonb_build_object('mutated', true);
end;
$mutant$;

do $test$
declare
  v_before text := pg_temp.cup_state();
  v_match_id bigint;
begin
  begin
    select min(match_row.id)
    into v_match_id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(7);

    perform public.set_match_result(v_match_id, 2, 0);

    if pg_temp.cup_state() = v_before then
      raise exception 'PLAYERS CUP 2B MUTATION DETECTED';
    end if;

    raise exception
      'PLAYERS CUP 2B TEST FAILED: the skipped apply mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_apply;

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.state_before_repeat'),
  'restoring the real helpers leaves the completed Cup untouched'
);

-- ---------------------------------------------------------------------------
-- 15. Security
-- ---------------------------------------------------------------------------

select set_config('test.cup_id', pg_temp.cup_id()::text, true);
select set_config('test.security_state', pg_temp.cup_state(), true);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);
set local role authenticated;

do $test$
begin
  begin
    perform public.players_cup_apply(current_setting('test.cup_id')::bigint);
    raise exception 'PLAYERS CUP 2B TEST FAILED: a player ran apply';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_freeze_exclusions(
      current_setting('test.cup_id')::bigint
    );
    raise exception 'PLAYERS CUP 2B TEST FAILED: a player froze exclusions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.set_match_result(
      (
        select min(match_row.id)
        from public.matches as match_row
      ),
      1,
      0
    );
    raise exception 'PLAYERS CUP 2B TEST FAILED: a player entered a result';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);
set local role authenticated;
select set_config(
  'test.lb_readable',
  exists (
    select 1
    from public.get_leaderboard() as leaderboard
    where leaderboard.user_id = pg_temp.cup_user_id(1)
  )::text,
  true
);
reset role;

select pg_temp.cup_assert(
  current_setting('test.lb_readable')::boolean,
  'authenticated players can still read the leaderboard'
);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.security_state'),
  'rejected player writes left the Cup untouched'
);

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzc2b%'
  ) then
    raise exception 'PLAYERS CUP 2B TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'scoring_without_a_cup_writes_no_cup_tables',
  'knockout_scores_before_the_cup_exists',
  'fixture_cup_has_40_participants',
  'set_match_result_lock_order_is_cup_then_match',
  'apply_and_freeze_do_not_take_the_cup_lock',
  'classifiers_match_the_old_inline_filters',
  'leaderboard_exact_correct_match_stored_points',
  'cup_ranking_exact_counts_match_md1_md2',
  'matchday_1_result_does_not_recompute_the_cup',
  'matchday_2_result_does_not_recompute_the_cup',
  'knockout_result_does_not_recompute_the_cup',
  'cutoff_passes_with_nothing_frozen',
  'late_result_finishes_the_football_match',
  'late_result_still_scores_leaderboard_points',
  'set_match_result_freezes_the_exclusion_first',
  'late_points_do_not_enter_round_1',
  'round_1_closes_on_included_matches',
  'cup_failure_rolls_back_the_football_result',
  'cup_failure_rolls_back_prediction_points',
  'cup_failure_rolls_back_cup_state',
  'first_md3_result_writes_interim_scores',
  'last_md3_result_resolves_round_1',
  'round_1_winners_propagate_to_round_2',
  'matchday_4_resolves_round_2',
  'no_awards_before_the_final',
  'md3_to_md8_completes_the_cup_without_recovery_rpc',
  'no_participant_holds_two_cup_awards',
  'champion_award_is_winner_points',
  'awarded_total_is_predictions_plus_honour',
  'leaderboard_deltas_are_30_20_and_10',
  'non_awarded_player_gets_no_cup_bonus',
  'cup_honours_do_not_change_other_leaderboard_columns',
  'cup_matchday_points_are_not_double_counted',
  'reward_reconfiguration_writes_100_60_20',
  'leaderboard_reads_live_honour_values',
  'md3_correction_changes_a_round_1_winner',
  'replaced_winner_leaves_the_downstream_bracket',
  'correction_rebuilds_derived_state',
  'recovery_rpc_is_a_no_op_after_automatic_recompute',
  'md8_correction_changes_the_champion',
  'new_champion_takes_the_winner_award',
  'leaderboard_follows_the_swapped_honours',
  'repeated_result_saves_are_idempotent',
  'skipped_freeze_mutation_is_detected',
  'skipped_apply_mutation_is_detected',
  'restored_helpers_leave_the_cup_untouched',
  'player_cannot_execute_apply',
  'player_cannot_execute_freeze',
  'player_cannot_enter_a_result',
  'players_can_still_read_the_leaderboard',
  'rejected_writes_left_the_cup_untouched',
  'all_fixture_changes_rolled_back'
]) as passed_test;
