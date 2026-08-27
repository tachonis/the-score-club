-- Transactional Badges matchday/cumulative engine verification.
-- Every fixture mutation is rolled back. Do not run against hosted Supabase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.eng_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'BADGES ENGINE TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.eng_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9920 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.eng_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.eng_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'badges-engine-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzbeng' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.eng_add_matchday(p_stage text, p_min_number integer default 1)
returns bigint
language plpgsql
as $helper$
declare
  v_number integer;
  v_id bigint;
begin
  select greatest(coalesce(max(matchday.matchday_number), 0) + 1, p_min_number)
  into v_number
  from public.matchdays as matchday
  where matchday.stage = p_stage;

  insert into public.matchdays (stage, matchday_number, name)
  values (
    p_stage,
    v_number,
    'zz-badge-engine-' || p_stage || '-' || v_number::text
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.eng_add_match(p_matchday_id bigint, p_kickoff timestamptz)
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

create function pg_temp.eng_predict(
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
    pg_temp.eng_user_id(p_index),
    p_match_id,
    p_home,
    p_away
  );
$helper$;

create function pg_temp.eng_award_count(
  p_index integer,
  p_code text,
  p_matchday_id bigint default null
)
returns bigint
language sql
stable
as $helper$
  select count(*)
  from public.badge_awards as award
  where award.user_id = pg_temp.eng_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.eng_points(p_index integer, p_match_id bigint)
returns integer
language sql
stable
as $helper$
  select prediction.points
  from public.predictions as prediction
  where prediction.user_id = pg_temp.eng_user_id(p_index)
    and prediction.match_id = p_match_id;
$helper$;

create function pg_temp.eng_source()
returns text
language sql
stable
as $helper$
  select pg_get_functiondef(
    'public.set_match_result(bigint, integer, integer)'::regprocedure
  );
$helper$;

create table pg_temp.eng_em_matches (
  ordinal integer primary key,
  match_id bigint not null,
  matchday_id bigint not null
);

-- ---------------------------------------------------------------------------
-- Fixture people and teams
-- ---------------------------------------------------------------------------

select pg_temp.eng_add_player(1);
select pg_temp.eng_add_player(2);
select pg_temp.eng_add_player(3);
select pg_temp.eng_add_player(4);
select pg_temp.eng_add_player(5);
select pg_temp.eng_add_player(6);
select pg_temp.eng_add_player(7);
select pg_temp.eng_add_player(8);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.eng_user_id(1);

insert into public.teams (name, short_name)
values
  ('ZZ Badge Engine Home', 'ZBH'),
  ('ZZ Badge Engine Away', 'ZBA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Engine Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Engine Away'
  ),
  true
);

-- ---------------------------------------------------------------------------
-- F. Completion helper (owner path, isolated matchdays)
-- ---------------------------------------------------------------------------

select set_config('test.md_empty', pg_temp.eng_add_matchday('league_phase')::text, true);

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_empty')::bigint) = false,
  'zero matches -> incomplete'
);

select set_config('test.md_status', pg_temp.eng_add_matchday('league_phase')::text, true);
select set_config(
  'test.m_scheduled',
  pg_temp.eng_add_match(
    current_setting('test.md_status')::bigint,
    now() + interval '30 days'
  )::text,
  true
);

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_status')::bigint) = false,
  'scheduled match -> incomplete'
);

update public.matches
set status = 'live'
where id = current_setting('test.m_scheduled')::bigint;

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_status')::bigint) = false,
  'live match -> incomplete'
);

update public.matches
set status = 'postponed'
where id = current_setting('test.m_scheduled')::bigint;

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_status')::bigint) = false,
  'postponed match -> incomplete'
);

update public.matches
set status = 'cancelled'
where id = current_setting('test.m_scheduled')::bigint;

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_status')::bigint) = false,
  'cancelled match -> incomplete'
);

select set_config('test.md_unscored', pg_temp.eng_add_matchday('league_phase')::text, true);
select set_config(
  'test.m_unscored',
  pg_temp.eng_add_match(
    current_setting('test.md_unscored')::bigint,
    now() + interval '31 days'
  )::text,
  true
);

update public.matches
set
  status = 'finished',
  home_score = 1,
  away_score = 0
where id = current_setting('test.m_unscored')::bigint;

select pg_temp.eng_predict(2, current_setting('test.m_unscored')::bigint, 1, 0);

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_unscored')::bigint) = false,
  'finished but unscored prediction -> incomplete'
);

update public.predictions
set points = 5
where match_id = current_setting('test.m_unscored')::bigint
  and user_id = pg_temp.eng_user_id(2);

select pg_temp.eng_assert(
  public.badge_matchday_is_complete(current_setting('test.md_unscored')::bigint) = true,
  'all finished and scored -> complete'
);

-- ---------------------------------------------------------------------------
-- Scenario matchdays (isolated numbers, rolled back)
-- ---------------------------------------------------------------------------

insert into pg_temp.eng_em_matches (ordinal, matchday_id, match_id)
select
  ordinal.n,
  matchday_row.id,
  pg_temp.eng_add_match(matchday_row.id, now() + (ordinal.n || ' hours')::interval)
from generate_series(1, 10) as ordinal(n)
cross join lateral (
  select pg_temp.eng_add_matchday('league_phase') as id
) as matchday_row;

select pg_temp.eng_predict(2, match_row.match_id, 2, 1)
from pg_temp.eng_em_matches as match_row;

select set_config('test.ss_a', pg_temp.eng_add_matchday('playoff')::text, true);
select set_config(
  'test.ss_a1',
  pg_temp.eng_add_match(current_setting('test.ss_a')::bigint, now() + interval '40 days')::text,
  true
);
select set_config(
  'test.ss_a2',
  pg_temp.eng_add_match(current_setting('test.ss_a')::bigint, now() + interval '40 days 1 hour')::text,
  true
);
select set_config(
  'test.ss_a3',
  pg_temp.eng_add_match(current_setting('test.ss_a')::bigint, now() + interval '40 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(3, current_setting('test.ss_a1')::bigint, 2, 1);
select pg_temp.eng_predict(3, current_setting('test.ss_a2')::bigint, 2, 1);
select pg_temp.eng_predict(3, current_setting('test.ss_a3')::bigint, 2, 1);

select set_config('test.ss_b', pg_temp.eng_add_matchday('round_of_16')::text, true);
select set_config(
  'test.ss_b1',
  pg_temp.eng_add_match(current_setting('test.ss_b')::bigint, now() + interval '41 days')::text,
  true
);
select set_config(
  'test.ss_b2',
  pg_temp.eng_add_match(current_setting('test.ss_b')::bigint, now() + interval '41 days 1 hour')::text,
  true
);
select set_config(
  'test.ss_b3',
  pg_temp.eng_add_match(current_setting('test.ss_b')::bigint, now() + interval '41 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(3, current_setting('test.ss_b1')::bigint, 2, 1);
select pg_temp.eng_predict(3, current_setting('test.ss_b2')::bigint, 2, 1);
select pg_temp.eng_predict(3, current_setting('test.ss_b3')::bigint, 2, 1);

select set_config('test.of_19', pg_temp.eng_add_matchday('league_phase')::text, true);
select set_config(
  'test.of_19a',
  pg_temp.eng_add_match(current_setting('test.of_19')::bigint, now() + interval '42 days')::text,
  true
);
select set_config(
  'test.of_19b',
  pg_temp.eng_add_match(current_setting('test.of_19')::bigint, now() + interval '42 days 1 hour')::text,
  true
);
select set_config(
  'test.of_19c',
  pg_temp.eng_add_match(current_setting('test.of_19')::bigint, now() + interval '42 days 2 hours')::text,
  true
);
select set_config(
  'test.of_19d',
  pg_temp.eng_add_match(current_setting('test.of_19')::bigint, now() + interval '42 days 3 hours')::text,
  true
);
select set_config(
  'test.of_19e',
  pg_temp.eng_add_match(current_setting('test.of_19')::bigint, now() + interval '42 days 4 hours')::text,
  true
);
select pg_temp.eng_predict(4, current_setting('test.of_19a')::bigint, 2, 1);
select pg_temp.eng_predict(4, current_setting('test.of_19b')::bigint, 2, 1);
select pg_temp.eng_predict(4, current_setting('test.of_19c')::bigint, 2, 1);
select pg_temp.eng_predict(4, current_setting('test.of_19d')::bigint, 1, 0);
select pg_temp.eng_predict(4, current_setting('test.of_19e')::bigint, 1, 0);

select set_config(
  'test.of_gm',
  pg_temp.eng_add_matchday('league_phase', 2)::text,
  true
);
select set_config(
  'test.of_gm1',
  pg_temp.eng_add_match(current_setting('test.of_gm')::bigint, now() + interval '43 days')::text,
  true
);
select set_config(
  'test.of_gm2',
  pg_temp.eng_add_match(current_setting('test.of_gm')::bigint, now() + interval '43 days 1 hour')::text,
  true
);
select set_config(
  'test.of_gm3',
  pg_temp.eng_add_match(current_setting('test.of_gm')::bigint, now() + interval '43 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(4, current_setting('test.of_gm1')::bigint, 2, 1);
select pg_temp.eng_predict(4, current_setting('test.of_gm2')::bigint, 2, 1);
select pg_temp.eng_predict(4, current_setting('test.of_gm3')::bigint, 2, 1);

select set_config('test.pf_correct', pg_temp.eng_add_matchday('quarter_final')::text, true);
select set_config(
  'test.pf_c1',
  pg_temp.eng_add_match(current_setting('test.pf_correct')::bigint, now() + interval '44 days')::text,
  true
);
select set_config(
  'test.pf_c2',
  pg_temp.eng_add_match(current_setting('test.pf_correct')::bigint, now() + interval '44 days 1 hour')::text,
  true
);
select set_config(
  'test.pf_c3',
  pg_temp.eng_add_match(current_setting('test.pf_correct')::bigint, now() + interval '44 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(5, current_setting('test.pf_c1')::bigint, 1, 0);
select pg_temp.eng_predict(5, current_setting('test.pf_c2')::bigint, 1, 0);
select pg_temp.eng_predict(5, current_setting('test.pf_c3')::bigint, 1, 0);

select set_config('test.pf_exact', pg_temp.eng_add_matchday('semi_final')::text, true);
select set_config(
  'test.pf_e1',
  pg_temp.eng_add_match(current_setting('test.pf_exact')::bigint, now() + interval '45 days')::text,
  true
);
select set_config(
  'test.pf_e2',
  pg_temp.eng_add_match(current_setting('test.pf_exact')::bigint, now() + interval '45 days 1 hour')::text,
  true
);
select set_config(
  'test.pf_e3',
  pg_temp.eng_add_match(current_setting('test.pf_exact')::bigint, now() + interval '45 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(5, current_setting('test.pf_e1')::bigint, 2, 1);
select pg_temp.eng_predict(5, current_setting('test.pf_e2')::bigint, 2, 1);
select pg_temp.eng_predict(5, current_setting('test.pf_e3')::bigint, 2, 1);

select set_config('test.pf_wrong', pg_temp.eng_add_matchday('playoff')::text, true);
select set_config(
  'test.pf_w1',
  pg_temp.eng_add_match(current_setting('test.pf_wrong')::bigint, now() + interval '46 days')::text,
  true
);
select set_config(
  'test.pf_w2',
  pg_temp.eng_add_match(current_setting('test.pf_wrong')::bigint, now() + interval '46 days 1 hour')::text,
  true
);
select set_config(
  'test.pf_w3',
  pg_temp.eng_add_match(current_setting('test.pf_wrong')::bigint, now() + interval '46 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(5, current_setting('test.pf_w1')::bigint, 2, 1);
select pg_temp.eng_predict(5, current_setting('test.pf_w2')::bigint, 2, 1);
select pg_temp.eng_predict(5, current_setting('test.pf_w3')::bigint, 2, 1);

select set_config('test.pf_miss', pg_temp.eng_add_matchday('playoff')::text, true);
select set_config(
  'test.pf_m1',
  pg_temp.eng_add_match(current_setting('test.pf_miss')::bigint, now() + interval '47 days')::text,
  true
);
select set_config(
  'test.pf_m2',
  pg_temp.eng_add_match(current_setting('test.pf_miss')::bigint, now() + interval '47 days 1 hour')::text,
  true
);
select set_config(
  'test.pf_m3',
  pg_temp.eng_add_match(current_setting('test.pf_miss')::bigint, now() + interval '47 days 2 hours')::text,
  true
);
select pg_temp.eng_predict(5, current_setting('test.pf_m1')::bigint, 2, 1);
select pg_temp.eng_predict(5, current_setting('test.pf_m2')::bigint, 2, 1);

select set_config('test.final_md', pg_temp.eng_add_matchday('final')::text, true);
select set_config(
  'test.final_m',
  pg_temp.eng_add_match(current_setting('test.final_md')::bigint, now() + interval '50 days')::text,
  true
);
select pg_temp.eng_predict(6, current_setting('test.final_m')::bigint, 2, 1);
select pg_temp.eng_predict(7, current_setting('test.final_m')::bigint, 3, 1);

select set_config(
  'test.gm_only',
  pg_temp.eng_add_matchday('league_phase', 2)::text,
  true
);
select set_config(
  'test.gm_only_m',
  pg_temp.eng_add_match(current_setting('test.gm_only')::bigint, now() + interval '51 days')::text,
  true
);
select pg_temp.eng_predict(8, current_setting('test.gm_only_m')::bigint, 2, 1);

-- Cup honour and long-term award for player 4: must not feed On Fire.
insert into public.cup_competitions (
  slug,
  season_label,
  participant_count,
  status
)
values (
  'zz-badge-engine-cup',
  'Champions League 2026/27',
  8,
  'active'
);

insert into public.cup_participants (
  cup_id,
  user_id,
  username_snapshot,
  rank_position,
  bracket_position,
  entry_round
)
select
  competition.id,
  pg_temp.eng_user_id(4),
  'zzbeng004',
  1,
  1,
  1
from public.cup_competitions as competition
where competition.slug = 'zz-badge-engine-cup';

insert into public.cup_awards (
  cup_id,
  participant_id,
  user_id,
  award_type,
  points
)
select
  participant.cup_id,
  participant.id,
  participant.user_id,
  'winner',
  50
from public.cup_participants as participant
join public.cup_competitions as competition
  on competition.id = participant.cup_id
where competition.slug = 'zz-badge-engine-cup';

insert into public.long_term_predictions (
  user_id,
  prediction_type,
  team_id
)
values (
  pg_temp.eng_user_id(4),
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
  pg_temp.eng_user_id(4),
  'winner',
  current_setting('test.team_home')::bigint,
  current_setting('test.team_home')::bigint,
  30
);

-- ---------------------------------------------------------------------------
-- H / I. Function body still has Cup then badges; Final/GM scoring unchanged
-- ---------------------------------------------------------------------------

select pg_temp.eng_assert(
  position('players_cup_lock_key' in pg_temp.eng_source()) > 0
  and position('players_cup_freeze_exclusions' in pg_temp.eng_source()) > 0
  and position('players_cup_apply' in pg_temp.eng_source()) > 0
  and position('recompute_matchday_badges' in pg_temp.eng_source()) > 0
  and position('recompute_cumulative_badges' in pg_temp.eng_source()) > 0
  and position('players_cup_apply' in pg_temp.eng_source())
    < position('recompute_matchday_badges' in pg_temp.eng_source())
  and position('when v_stage = ''final'' then 10' in pg_temp.eng_source()) > 0
  and position('when v_stage = ''final'' then 4' in pg_temp.eng_source()) > 0,
  'set_match_result still freezes/applies Cup then recomputes badges; Final 10/4 remains'
);

-- ---------------------------------------------------------------------------
-- Scoring as admin
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- A. Exact Machine: 9 exact, then 10, idempotent, revoke to 9
do $test$
declare
  v_row pg_temp.eng_em_matches;
begin
  for v_row in
    select *
    from pg_temp.eng_em_matches
    where ordinal <= 9
    order by ordinal
  loop
    perform public.set_match_result(v_row.match_id, 2, 1);
  end loop;
end;
$test$;

select pg_temp.eng_assert(
  pg_temp.eng_award_count(2, 'exact_machine') = 0,
  '9 exact -> no Exact Machine'
);

select public.set_match_result(
  (select match_id from pg_temp.eng_em_matches where ordinal = 10),
  2,
  1
);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(2, 'exact_machine') = 1,
  '10 exact -> Exact Machine'
);

select set_config(
  'test.em_id',
  (
    select award.id::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(2)
      and award.badge_code = 'exact_machine'
  ),
  true
);
select set_config(
  'test.em_earned',
  (
    select award.earned_at::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(2)
      and award.badge_code = 'exact_machine'
  ),
  true
);

select public.set_match_result(
  (select match_id from pg_temp.eng_em_matches where ordinal = 10),
  2,
  1
);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(2, 'exact_machine') = 1
  and (
    select award.id::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(2)
      and award.badge_code = 'exact_machine'
  ) = current_setting('test.em_id')
  and (
    select award.earned_at::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(2)
      and award.badge_code = 'exact_machine'
  ) = current_setting('test.em_earned'),
  'repeated recompute does not duplicate Exact Machine or reset earned_at'
);

select public.set_match_result(
  (select match_id from pg_temp.eng_em_matches where ordinal = 10),
  0,
  0
);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(2, 'exact_machine') = 0,
  'correction to 9 exact -> Exact Machine revoked'
);

select public.set_match_result(
  (select match_id from pg_temp.eng_em_matches where ordinal = 10),
  2,
  1
);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(2, 'exact_machine') = 1,
  're-earned Exact Machine after revocation is allowed'
);

-- B. Sharp Shooter
select public.set_match_result(current_setting('test.ss_a1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.ss_a2')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter', current_setting('test.ss_a')::bigint) = 0,
  'incomplete matchday -> no Sharp Shooter'
);

-- Two finished exacts, third still scheduled: even a forced recompute
-- (already done by set_match_result) must not award. Score a non-exact
-- on match 3 first so the round is complete with only 2 exacts.
select public.set_match_result(current_setting('test.ss_a3')::bigint, 0, 0);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter', current_setting('test.ss_a')::bigint) = 0,
  'complete with 2 exact -> no Sharp Shooter'
);

select public.set_match_result(current_setting('test.ss_a3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter', current_setting('test.ss_a')::bigint) = 1,
  'complete with 3 exact -> Sharp Shooter'
);

select public.set_match_result(current_setting('test.ss_a3')::bigint, 0, 0);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter', current_setting('test.ss_a')::bigint) = 0,
  'correction to 2 exact -> Sharp Shooter revoked'
);

select public.set_match_result(current_setting('test.ss_b1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.ss_b2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.ss_b3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter', current_setting('test.ss_b')::bigint) = 1
  and pg_temp.eng_award_count(3, 'sharp_shooter') = 1,
  'same user can earn Sharp Shooter on another matchday'
);

-- Restore ss_a to 3 exact so player 3 has two instances for the count check.
select public.set_match_result(current_setting('test.ss_a3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(3, 'sharp_shooter') = 2,
  'two Sharp Shooter instances across two matchdays'
);

-- C. On Fire
select public.set_match_result(current_setting('test.of_19a')::bigint, 2, 1);
select public.set_match_result(current_setting('test.of_19b')::bigint, 2, 1);
select public.set_match_result(current_setting('test.of_19c')::bigint, 2, 1);
select public.set_match_result(current_setting('test.of_19d')::bigint, 2, 0);
select public.set_match_result(current_setting('test.of_19e')::bigint, 2, 0);

select pg_temp.eng_assert(
  pg_temp.eng_points(4, current_setting('test.of_19a')::bigint)
    + pg_temp.eng_points(4, current_setting('test.of_19b')::bigint)
    + pg_temp.eng_points(4, current_setting('test.of_19c')::bigint)
    + pg_temp.eng_points(4, current_setting('test.of_19d')::bigint)
    + pg_temp.eng_points(4, current_setting('test.of_19e')::bigint)
    = 19
  and pg_temp.eng_award_count(4, 'on_fire', current_setting('test.of_19')::bigint) = 0,
  '19 prediction points -> no On Fire'
);

reset role;

select pg_temp.eng_assert(
  (
    select player_stats.points
    from public.badge_matchday_player_stats(
      current_setting('test.of_19')::bigint
    ) as player_stats
    where player_stats.user_id = pg_temp.eng_user_id(4)
  ) = 19
  and exists (
    select 1
    from public.cup_awards as award
    where award.user_id = pg_temp.eng_user_id(4)
      and award.points = 50
  )
  and exists (
    select 1
    from public.long_term_awards as award
    where award.user_id = pg_temp.eng_user_id(4)
      and award.points = 30
  ),
  'matchday stats are prediction points only; Cup and long-term awards exist but do not count'
);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.of_19d')::bigint, 1, 0);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(4, 'on_fire', current_setting('test.of_19')::bigint) = 1,
  '20 prediction points -> On Fire'
);

select public.set_match_result(current_setting('test.of_19d')::bigint, 2, 0);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(4, 'on_fire', current_setting('test.of_19')::bigint) = 0,
  'correction below 20 -> On Fire revoked'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(4)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_golden_match(current_setting('test.of_gm1')::bigint);

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.of_gm1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.of_gm2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.of_gm3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_points(4, current_setting('test.of_gm1')::bigint) = 10
  and pg_temp.eng_points(4, current_setting('test.of_gm2')::bigint) = 5
  and pg_temp.eng_points(4, current_setting('test.of_gm3')::bigint) = 5
  and pg_temp.eng_award_count(4, 'on_fire', current_setting('test.of_gm')::bigint) = 1,
  'Golden Match 10/4 points count toward On Fire'
);

-- D. Perfect Matchday
select public.set_match_result(current_setting('test.pf_c1')::bigint, 2, 0);
select public.set_match_result(current_setting('test.pf_c2')::bigint, 2, 0);
select public.set_match_result(current_setting('test.pf_c3')::bigint, 2, 0);

select pg_temp.eng_assert(
  pg_temp.eng_points(5, current_setting('test.pf_c1')::bigint) = 2
  and pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_correct')::bigint) = 1,
  'all matches at least correct 1-X-2 -> Perfect Matchday'
);

select public.set_match_result(current_setting('test.pf_e1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_e2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_e3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_exact')::bigint) = 1,
  'exact scores qualify for Perfect Matchday'
);

select public.set_match_result(current_setting('test.pf_w1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_w2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_w3')::bigint, 0, 0);

select pg_temp.eng_assert(
  pg_temp.eng_points(5, current_setting('test.pf_w3')::bigint) = 0
  and pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_wrong')::bigint) = 0,
  'one wrong prediction -> no Perfect Matchday'
);

select public.set_match_result(current_setting('test.pf_m1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_m2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pf_m3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_miss')::bigint) = 0,
  'one missing prediction -> no Perfect Matchday'
);

select public.set_match_result(current_setting('test.pf_w3')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_wrong')::bigint) = 1,
  'correction that makes every match exact/correct awards Perfect Matchday'
);

select public.set_match_result(current_setting('test.pf_w3')::bigint, 0, 0);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(5, 'perfect_matchday', current_setting('test.pf_wrong')::bigint) = 0,
  'correction that introduces a wrong prediction revokes Perfect Matchday'
);

-- E / I. Final Boss and Final 10/4/0
select public.set_match_result(current_setting('test.final_m')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_points(6, current_setting('test.final_m')::bigint) = 10
  and pg_temp.eng_points(7, current_setting('test.final_m')::bigint) = 4
  and pg_temp.eng_award_count(6, 'final_boss') = 1
  and pg_temp.eng_award_count(7, 'final_boss') = 0,
  'Final exact -> Final Boss and 10 points; Final correct-only -> 4 points, no badge'
);

select set_config(
  'test.fb_id',
  (
    select award.id::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(6)
      and award.badge_code = 'final_boss'
  ),
  true
);

select public.set_match_result(current_setting('test.final_m')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_award_count(6, 'final_boss') = 1
  and (
    select award.id::text
    from public.badge_awards as award
    where award.user_id = pg_temp.eng_user_id(6)
      and award.badge_code = 'final_boss'
  ) = current_setting('test.fb_id'),
  'same set_match_result twice does not duplicate Final Boss'
);

reset role;

insert into public.golden_match_selections (
  user_id,
  matchday_id,
  match_id
)
values (
  pg_temp.eng_user_id(6),
  current_setting('test.final_md')::bigint,
  current_setting('test.final_m')::bigint
);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.final_m')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_points(6, current_setting('test.final_m')::bigint) = 10,
  'planted Final Golden Match still scores exact 10, never 20'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(8)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_golden_match(current_setting('test.gm_only_m')::bigint);

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.gm_only_m')::bigint, 2, 1);

select pg_temp.eng_assert(
  pg_temp.eng_points(8, current_setting('test.gm_only_m')::bigint) = 10
  and pg_temp.eng_award_count(8, 'final_boss') = 0,
  'Golden Match exact elsewhere does not award Final Boss'
);

select public.set_match_result(current_setting('test.final_m')::bigint, 0, 0);

select pg_temp.eng_assert(
  pg_temp.eng_points(6, current_setting('test.final_m')::bigint) = 0
  and pg_temp.eng_award_count(6, 'final_boss') = 0,
  'correction that removes Final exactness revokes Final Boss'
);

-- J. Security: a player cannot self-award or call internal helpers
reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.eng_user_id(2)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
begin
  begin
    insert into public.badge_awards (
      user_id,
      badge_code,
      award_scope
    )
    values (
      pg_temp.eng_user_id(2),
      'exact_machine',
      'season'
    );
    raise exception 'BADGES ENGINE TEST FAILED: player inserted an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    update public.badge_awards
    set context = '{"forged": true}'::jsonb
    where user_id = pg_temp.eng_user_id(2);
    raise exception 'BADGES ENGINE TEST FAILED: player updated an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    delete from public.badge_awards
    where user_id = pg_temp.eng_user_id(2);
    raise exception 'BADGES ENGINE TEST FAILED: player deleted an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_matchday_badges(
      current_setting('test.ss_a')::bigint
    );
    raise exception 'BADGES ENGINE TEST FAILED: player executed recompute_matchday_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_cumulative_badges();
    raise exception 'BADGES ENGINE TEST FAILED: player executed recompute_cumulative_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_matchday_is_complete(
      current_setting('test.ss_a')::bigint
    );
    raise exception 'BADGES ENGINE TEST FAILED: player executed badge_matchday_is_complete';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_matchday_player_stats(
      current_setting('test.ss_a')::bigint
    );
    raise exception 'BADGES ENGINE TEST FAILED: player executed badge_matchday_player_stats';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzbeng%'
  ) then
    raise exception 'BADGES ENGINE TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'matchday_completion_zero_matches',
  'matchday_completion_unfinished_statuses',
  'matchday_completion_unscored_prediction',
  'matchday_completion_finished_scored',
  'exact_machine_9_no_award',
  'exact_machine_10_award',
  'exact_machine_idempotent',
  'exact_machine_revoke_on_correction',
  'sharp_shooter_incomplete_and_two_exact',
  'sharp_shooter_three_exact_and_revoke',
  'sharp_shooter_second_matchday',
  'on_fire_19_and_cup_long_term_ignored',
  'on_fire_20_and_revoke',
  'on_fire_golden_match_counts',
  'perfect_matchday_correct_and_exact',
  'perfect_matchday_wrong_and_missed',
  'perfect_matchday_correction',
  'final_boss_exact_not_correct',
  'final_boss_not_from_golden_match',
  'final_boss_revoke',
  'final_10_4_no_golden_stack',
  'set_match_result_cup_then_badges',
  'player_cannot_self_award_or_recompute',
  'all_fixture_changes_rolled_back'
]) as passed_test;
