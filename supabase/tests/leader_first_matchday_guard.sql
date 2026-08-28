-- Transactional Leader first-matchday guard verification.
-- Every fixture mutation is rolled back. Do not run against hosted Supabase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.lg_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'LEADER FIRST MATCHDAY GUARD TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.lg_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9950 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.lg_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.lg_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'leader-guard-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzldgrd' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.lg_award_count(p_index integer)
returns bigint
language sql
stable
as $helper$
  select count(*)
  from public.badge_awards as award
  where award.user_id = pg_temp.lg_user_id(p_index)
    and award.badge_code = 'leader';
$helper$;

create function pg_temp.lg_earned_at(p_index integer)
returns timestamptz
language sql
stable
as $helper$
  select award.earned_at
  from public.badge_awards as award
  where award.user_id = pg_temp.lg_user_id(p_index)
    and award.badge_code = 'leader';
$helper$;

create function pg_temp.lg_source(p_signature text)
returns text
language sql
stable
as $helper$
  select pg_get_functiondef(p_signature::regprocedure);
$helper$;

create function pg_temp.lg_add_match(p_matchday_id bigint, p_kickoff timestamptz)
returns bigint
language plpgsql
as $helper$
declare
  v_id bigint;
begin
  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    p_matchday_id,
    current_setting('test.team_home')::bigint,
    current_setting('test.team_away')::bigint,
    p_kickoff,
    'scheduled'
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.lg_predict(
  p_index integer,
  p_match_id bigint,
  p_home integer,
  p_away integer
)
returns void
language sql
as $helper$
  insert into public.predictions (
    user_id,
    match_id,
    predicted_home_score,
    predicted_away_score
  )
  values (
    pg_temp.lg_user_id(p_index),
    p_match_id,
    p_home,
    p_away
  )
  on conflict (user_id, match_id) do update
  set
    predicted_home_score = excluded.predicted_home_score,
    predicted_away_score = excluded.predicted_away_score,
    points = null,
    updated_at = now();
$helper$;

create function pg_temp.lg_schedule_md1()
returns void
language sql
as $helper$
  update public.matches as match_row
  set
    status = 'scheduled',
    updated_at = now()
  where match_row.matchday_id = current_setting('test.md1')::bigint;
$helper$;

create function pg_temp.lg_finish_one_md1_match()
returns void
language plpgsql
as $helper$
declare
  v_first_id bigint;
begin
  perform pg_temp.lg_schedule_md1();

  select min(match_row.id)
  into v_first_id
  from public.matches as match_row
  where match_row.matchday_id = current_setting('test.md1')::bigint;

  update public.matches
  set
    status = 'finished',
    home_score = coalesce(home_score, 0),
    away_score = coalesce(away_score, 0),
    updated_at = now()
  where id = v_first_id;

  update public.predictions
  set
    points = coalesce(points, 0),
    updated_at = now()
  where match_id = v_first_id
    and points is null;
end;
$helper$;

create function pg_temp.lg_finish_all_md1()
returns void
language plpgsql
as $helper$
begin
  update public.matches as match_row
  set
    status = 'finished',
    home_score = coalesce(match_row.home_score, 0),
    away_score = coalesce(match_row.away_score, 0),
    updated_at = now()
  where match_row.matchday_id = current_setting('test.md1')::bigint;

  update public.predictions as prediction
  set
    points = 0,
    updated_at = now()
  where prediction.points is null
    and prediction.match_id in (
      select match_row.id
      from public.matches as match_row
      where match_row.matchday_id = current_setting('test.md1')::bigint
    );
end;
$helper$;

-- ---------------------------------------------------------------------------
-- Fixture people, teams, canonical Matchday 1
-- ---------------------------------------------------------------------------

select pg_temp.lg_add_player(1);
select pg_temp.lg_add_player(2);
select pg_temp.lg_add_player(3);
select pg_temp.lg_add_player(4);
select pg_temp.lg_add_player(5);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.lg_user_id(1);

update public.profiles as profile
set status = 'disabled'
where profile.status = 'active'
  and profile.id not in (
    select pg_temp.lg_user_id(index.n)
    from generate_series(1, 5) as index(n)
  );

insert into public.teams (name, short_name)
values
  ('ZZ Leader Guard Home', 'ZLH'),
  ('ZZ Leader Guard Away', 'ZLA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Leader Guard Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Leader Guard Away'
  ),
  true
);

insert into public.matchdays (stage, matchday_number, name)
values ('league_phase', 1, 'zz-leader-guard-lp-1')
on conflict (stage, matchday_number) do nothing;

select set_config(
  'test.md1',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 1
  ),
  true
);

select pg_temp.lg_assert(
  (
    select count(*)
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 1
  ) = 1
  and current_setting('test.md1') is not null,
  'canonical League Phase Matchday 1 is unique'
);

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status
)
select
  current_setting('test.md1')::bigint,
  current_setting('test.team_home')::bigint,
  current_setting('test.team_away')::bigint,
  now() + (slot.n || ' hours')::interval,
  'scheduled'
from generate_series(1, 2) as slot(n)
where (
  select count(*)
  from public.matches as match_row
  where match_row.matchday_id = current_setting('test.md1')::bigint
) < 2;

select pg_temp.lg_assert(
  (
    select count(*)
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md1')::bigint
  ) >= 2,
  'Matchday 1 has at least two matches'
);

delete from public.badge_awards
where badge_code = 'leader';

-- ---------------------------------------------------------------------------
-- 1. Preseason: Matchday 1 exists, no matches finished, rank #1 exists
-- ---------------------------------------------------------------------------

select pg_temp.lg_schedule_md1();

select pg_temp.lg_assert(
  exists (
    select 1
    from public.get_leaderboard() as standing
    where standing.rank_position = 1
  )
  and not exists (
    select 1
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md1')::bigint
      and match_row.status = 'finished'
  )
  and public.badge_matchday_is_complete(current_setting('test.md1')::bigint) = false,
  'preseason has a rank #1 while Matchday 1 is unfinished'
);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'leader'
  ),
  'preseason does not award Leader'
);

-- ---------------------------------------------------------------------------
-- 2. First match finished only
-- ---------------------------------------------------------------------------

select pg_temp.lg_finish_one_md1_match();

select pg_temp.lg_assert(
  (
    select count(*)
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md1')::bigint
      and match_row.status = 'finished'
  ) = 1
  and public.badge_matchday_is_complete(current_setting('test.md1')::bigint) = false,
  'Matchday 1 is only partially finished'
);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'leader'
  ),
  'partial Matchday 1 does not award Leader'
);

-- ---------------------------------------------------------------------------
-- 3. All matches finished, one prediction still NULL
-- ---------------------------------------------------------------------------

select pg_temp.lg_finish_all_md1();

select set_config(
  'test.null_m',
  (
    select min(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.md1')::bigint
  ),
  true
);

select pg_temp.lg_predict(5, current_setting('test.null_m')::bigint, 1, 0);

select pg_temp.lg_assert(
  exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    where match_row.matchday_id = current_setting('test.md1')::bigint
      and prediction.points is null
  )
  and public.badge_matchday_is_complete(current_setting('test.md1')::bigint) = false,
  'finished Matchday 1 with a NULL prediction is incomplete'
);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'leader'
  ),
  'NULL prediction on Matchday 1 blocks Leader'
);

-- ---------------------------------------------------------------------------
-- 9 (setup). Later incomplete matchday must not block once MD1 is complete
-- ---------------------------------------------------------------------------

insert into public.matchdays (stage, matchday_number, name)
values (
  'playoff',
  (
    select coalesce(max(matchday.matchday_number), 0) + 1
    from public.matchdays as matchday
    where matchday.stage = 'playoff'
  ),
  'zz-leader-guard-later'
);

select pg_temp.lg_add_match(
  (
    select matchday.id
    from public.matchdays as matchday
    where matchday.name = 'zz-leader-guard-later'
  ),
  now() + interval '20 days'
);

-- ---------------------------------------------------------------------------
-- 4 / 10. Fully complete Matchday 1, including 0-point rank #1
-- ---------------------------------------------------------------------------

-- Keep player 4 inactive until the dedicated inactivity test so they cannot
-- already hold Leader from the 0-point shared #1 board.
update public.profiles
set status = 'disabled'
where id = pg_temp.lg_user_id(4);

update public.predictions
set
  points = 0,
  updated_at = now()
where user_id = pg_temp.lg_user_id(5)
  and match_id = current_setting('test.null_m')::bigint
  and points is null;

select pg_temp.lg_assert(
  public.badge_matchday_is_complete(current_setting('test.md1')::bigint) = true
  and exists (
    select 1
    from public.matches as match_row
    where match_row.matchday_id = (
      select matchday.id
      from public.matchdays as matchday
      where matchday.name = 'zz-leader-guard-later'
    )
      and match_row.status is distinct from 'finished'
  ),
  'Matchday 1 is complete while a later matchday is not'
);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  exists (
    select 1
    from public.get_leaderboard() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'leader'
    where standing.rank_position = 1
      and standing.total_points = 0
  )
  and pg_temp.lg_award_count(2) = 1,
  'current rank #1 at 0 points earns Leader after Matchday 1 is complete'
);

-- ---------------------------------------------------------------------------
-- 5. Shared rank #1 all earn
-- ---------------------------------------------------------------------------

select pg_temp.lg_assert(
  (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position = 1
  ) = (
    select count(*)
    from public.badge_awards as award
    join public.get_leaderboard() as standing
      on standing.user_id = award.user_id
    where award.badge_code = 'leader'
      and standing.rank_position = 1
  )
  and pg_temp.lg_award_count(2) = 1
  and pg_temp.lg_award_count(3) = 1,
  'every shared current #1 earns Leader'
);

-- ---------------------------------------------------------------------------
-- 7. Repeated call does not duplicate or move earned_at
-- ---------------------------------------------------------------------------

select set_config('test.p2_earned', pg_temp.lg_earned_at(2)::text, true);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  pg_temp.lg_award_count(2) = 1
  and pg_temp.lg_earned_at(2) = current_setting('test.p2_earned')::timestamptz
  and (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'leader'
      and award.user_id = pg_temp.lg_user_id(2)
  ) = 1,
  'repeated Leader check does not duplicate or move earned_at'
);

-- ---------------------------------------------------------------------------
-- 6. Existing Leader survives a later ranking change
-- ---------------------------------------------------------------------------

select set_config(
  'test.overtake_md',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.name = 'zz-leader-guard-later'
  ),
  true
);
select set_config(
  'test.overtake_m',
  (
    select match_row.id::text
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.overtake_md')::bigint
    limit 1
  ),
  true
);

select pg_temp.lg_predict(3, current_setting('test.overtake_m')::bigint, 2, 1);

update public.matches
set
  status = 'finished',
  home_score = 2,
  away_score = 1,
  updated_at = now()
where id = current_setting('test.overtake_m')::bigint;

update public.predictions
set
  points = 5,
  updated_at = now()
where user_id = pg_temp.lg_user_id(3)
  and match_id = current_setting('test.overtake_m')::bigint;

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.lg_user_id(2)
  ) > 1
  and (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.lg_user_id(3)
  ) = 1
  and pg_temp.lg_award_count(2) = 1
  and pg_temp.lg_award_count(3) = 1
  and pg_temp.lg_earned_at(2) = current_setting('test.p2_earned')::timestamptz,
  'falling from #1 does not remove Leader; the new #1 also earns'
);

-- ---------------------------------------------------------------------------
-- 8. Inactive user cannot newly earn Leader
-- ---------------------------------------------------------------------------

insert into public.matchdays (stage, matchday_number, name)
values (
  'playoff',
  (
    select coalesce(max(matchday.matchday_number), 0) + 1
    from public.matchdays as matchday
    where matchday.stage = 'playoff'
  ),
  'zz-leader-guard-inact'
);

select set_config(
  'test.inact_md',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.name = 'zz-leader-guard-inact'
  ),
  true
);
select set_config(
  'test.inact_m',
  pg_temp.lg_add_match(
    current_setting('test.inact_md')::bigint,
    now() + interval '21 days'
  )::text,
  true
);

select pg_temp.lg_predict(4, current_setting('test.inact_m')::bigint, 2, 1);

update public.profiles
set status = 'disabled'
where id = pg_temp.lg_user_id(4);

update public.matches
set
  status = 'finished',
  home_score = 2,
  away_score = 1,
  updated_at = now()
where id = current_setting('test.inact_m')::bigint;

update public.predictions
set
  points = 5,
  updated_at = now()
where user_id = pg_temp.lg_user_id(4)
  and match_id = current_setting('test.inact_m')::bigint;

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  pg_temp.lg_award_count(4) = 0
  and not exists (
    select 1
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.lg_user_id(4)
  ),
  'inactive user does not newly earn Leader'
);

update public.profiles
set status = 'active'
where id = pg_temp.lg_user_id(4);

select public.award_leader_if_applicable();

select pg_temp.lg_assert(
  pg_temp.lg_award_count(4) = 1
  and (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.lg_user_id(4)
  ) = 1,
  'once active, current #1 can earn Leader after Matchday 1 is complete'
);

-- ---------------------------------------------------------------------------
-- Call-path coverage: guard lives only in award_leader_if_applicable
-- ---------------------------------------------------------------------------

select pg_temp.lg_assert(
  position(
    'league_phase' in pg_temp.lg_source('public.award_leader_if_applicable()')
  ) > 0
  and position(
    'matchday_number = 1' in pg_temp.lg_source('public.award_leader_if_applicable()')
  ) > 0
  and position(
    'badge_matchday_is_complete'
      in pg_temp.lg_source('public.award_leader_if_applicable()')
  ) > 0
  and position(
    'do nothing' in pg_temp.lg_source('public.award_leader_if_applicable()')
  ) > 0
  and position(
    'delete' in pg_temp.lg_source('public.award_leader_if_applicable()')
  ) = 0,
  'Leader gate is inside award_leader_if_applicable and remains insert-only'
);

select pg_temp.lg_assert(
  position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.recompute_ranking_badges()')
  ) > 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.lg_source('public.recompute_all_badges()')
  ) > 0
  and position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.recompute_all_badges()')
  ) = 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.lg_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.set_match_result(bigint, integer, integer)')
  ) = 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.lg_source('public.set_long_term_outcome(text, bigint)')
  ) > 0
  and position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.set_long_term_outcome(text, bigint)')
  ) = 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.lg_source('public.recompute_players_cup()')
  ) > 0
  and position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.recompute_players_cup()')
  ) = 0,
  'existing callers keep using award_leader_if_applicable with no extra Leader gates'
);

-- The ranking orchestrator body also mentions league_phase via
-- recompute_league_phase_badges. The award_leader call is still first and
-- has no Matchday 1 condition of its own.
select pg_temp.lg_assert(
  position(
    'award_leader_if_applicable'
      in pg_temp.lg_source('public.recompute_ranking_badges()')
  )
    < position(
      'recompute_league_phase_badges'
        in pg_temp.lg_source('public.recompute_ranking_badges()')
    ),
  'recompute_ranking_badges still delegates Leader to award_leader_if_applicable first'
);

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzldgrd%'
  ) then
    raise exception 'LEADER FIRST MATCHDAY GUARD TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'preseason_blocked',
  'partial_matchday_1_blocked',
  'null_prediction_blocked',
  'complete_matchday_1_awards_zero_point_rank1',
  'shared_rank1_all_earn',
  'repeated_call_stable',
  'existing_leader_survives_ranking_change',
  'inactive_user_cannot_newly_earn',
  'later_incomplete_matchday_does_not_block',
  'callers_delegate_to_award_leader_if_applicable',
  'all_fixture_changes_rolled_back'
]) as passed_test;
