-- Transactional Badges ranking engine verification.
-- Every fixture mutation is rolled back. Do not run against hosted Supabase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.rk_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'BADGES RANKING TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.rk_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9930 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.rk_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.rk_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'badges-ranking-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzrnk' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.rk_add_matchday(p_stage text, p_min_number integer default 1)
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
    'zz-badge-rank-' || p_stage || '-' || v_number::text
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.rk_add_match(p_matchday_id bigint, p_kickoff timestamptz)
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

create function pg_temp.rk_predict(
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
    pg_temp.rk_user_id(p_index),
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

create function pg_temp.rk_award_count(
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
  where award.user_id = pg_temp.rk_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.rk_earned_at(
  p_index integer,
  p_code text,
  p_matchday_id bigint default null
)
returns timestamptz
language sql
stable
as $helper$
  select award.earned_at
  from public.badge_awards as award
  where award.user_id = pg_temp.rk_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.rk_points(p_index integer, p_match_id bigint)
returns integer
language sql
stable
as $helper$
  select prediction.points
  from public.predictions as prediction
  where prediction.user_id = pg_temp.rk_user_id(p_index)
    and prediction.match_id = p_match_id;
$helper$;

create function pg_temp.rk_source(p_signature text)
returns text
language sql
stable
as $helper$
  select pg_get_functiondef(p_signature::regprocedure);
$helper$;

create function pg_temp.rk_finish_preexisting_all()
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
  where match_row.id in (
    select preexisting.id from pg_temp.rk_preexisting_matches as preexisting
  )
    and match_row.status is distinct from 'finished';

  update public.predictions as prediction
  set
    points = 0,
    updated_at = now()
  where prediction.match_id in (
    select preexisting.id from pg_temp.rk_preexisting_matches as preexisting
  )
    and prediction.points is null;
end;
$helper$;

create function pg_temp.rk_ensure_cup(p_completed boolean)
returns bigint
language plpgsql
as $helper$
declare
  v_cup_id bigint;
  v_index integer;
  v_rank integer;
begin
  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = 'players-cup-2026-27';

  if v_cup_id is null then
    insert into public.cup_competitions (
      slug,
      season_label,
      participant_count,
      status,
      winner_points,
      finalist_points,
      semi_finalist_points
    )
    values (
      'players-cup-2026-27',
      'Champions League 2026/27',
      8,
      case when p_completed then 'completed' else 'active' end,
      50,
      30,
      15
    )
    returning id into v_cup_id;

    for v_index in 2..9 loop
      insert into public.cup_participants (
        cup_id,
        user_id,
        username_snapshot,
        rank_position,
        bracket_position,
        entry_round
      )
      values (
        v_cup_id,
        pg_temp.rk_user_id(v_index),
        'zzrnk' || lpad(v_index::text, 3, '0'),
        v_index - 1,
        v_index - 1,
        1
      );
    end loop;
  else
    update public.cup_competitions
    set
      status = case when p_completed then 'completed' else 'active' end,
      updated_at = now()
    where id = v_cup_id;

    for v_index in 2..9 loop
      if not exists (
        select 1
        from public.cup_participants as participant
        where participant.cup_id = v_cup_id
          and participant.user_id = pg_temp.rk_user_id(v_index)
      ) then
        select min(slot.n)
        into v_rank
        from generate_series(1, 64) as slot(n)
        where not exists (
          select 1
          from public.cup_participants as participant
          where participant.cup_id = v_cup_id
            and participant.rank_position = slot.n
        )
        and not exists (
          select 1
          from public.cup_participants as participant
          where participant.cup_id = v_cup_id
            and participant.bracket_position = slot.n
        );

        if v_rank is not null then
          insert into public.cup_participants (
            cup_id,
            user_id,
            username_snapshot,
            rank_position,
            bracket_position,
            entry_round
          )
          values (
            v_cup_id,
            pg_temp.rk_user_id(v_index),
            'zzrnk' || lpad(v_index::text, 3, '0'),
            v_rank,
            v_rank,
            1
          );
        end if;
      end if;
    end loop;
  end if;

  return v_cup_id;
end;
$helper$;

create function pg_temp.rk_set_cup_award(
  p_cup_id bigint,
  p_index integer,
  p_type text,
  p_points integer
)
returns void
language plpgsql
as $helper$
declare
  v_participant_id bigint;
begin
  select participant.id
  into v_participant_id
  from public.cup_participants as participant
  where participant.cup_id = p_cup_id
    and participant.user_id = pg_temp.rk_user_id(p_index);

  if v_participant_id is null then
    raise exception 'BADGES RANKING TEST FAILED: no cup participant for index %', p_index;
  end if;

  insert into public.cup_awards (
    cup_id,
    participant_id,
    user_id,
    award_type,
    points
  )
  values (
    p_cup_id,
    v_participant_id,
    pg_temp.rk_user_id(p_index),
    p_type,
    p_points
  )
  on conflict (cup_id, participant_id) do update
  set
    user_id = excluded.user_id,
    award_type = excluded.award_type,
    points = excluded.points,
    updated_at = now();
end;
$helper$;

create table pg_temp.rk_preexisting_matches (
  id bigint primary key
);

insert into pg_temp.rk_preexisting_matches (id)
select match_row.id
from public.matches as match_row;

-- ---------------------------------------------------------------------------
-- Fixture people and teams
-- ---------------------------------------------------------------------------

select pg_temp.rk_add_player(1);
select pg_temp.rk_add_player(2);
select pg_temp.rk_add_player(3);
select pg_temp.rk_add_player(4);
select pg_temp.rk_add_player(5);
select pg_temp.rk_add_player(6);
select pg_temp.rk_add_player(7);
select pg_temp.rk_add_player(8);
select pg_temp.rk_add_player(9);
select pg_temp.rk_add_player(10);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.rk_user_id(1);

update public.profiles as profile
set status = 'disabled'
where profile.status = 'active'
  and profile.id not in (
    select pg_temp.rk_user_id(index.n)
    from generate_series(1, 10) as index(n)
  );

insert into public.teams (name, short_name)
values
  ('ZZ Badge Rank Home', 'ZRH'),
  ('ZZ Badge Rank Away', 'ZRA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Rank Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Rank Away'
  ),
  true
);

select pg_temp.rk_finish_preexisting_all();

delete from public.long_term_awards;
delete from public.long_term_outcomes;

-- ---------------------------------------------------------------------------
-- A. Matchday podium
-- ---------------------------------------------------------------------------

select set_config('test.pod_u', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_u1', pg_temp.rk_add_match(current_setting('test.pod_u')::bigint, now() + interval '50 days')::text, true);
select set_config('test.pod_u2', pg_temp.rk_add_match(current_setting('test.pod_u')::bigint, now() + interval '50 days 1 hour')::text, true);
select set_config('test.pod_u3', pg_temp.rk_add_match(current_setting('test.pod_u')::bigint, now() + interval '50 days 2 hours')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_u1')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_u2')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_u3')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_u1')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_u2')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_u3')::bigint, 1, 0);
select pg_temp.rk_predict(4, current_setting('test.pod_u1')::bigint, 2, 1);
select pg_temp.rk_predict(4, current_setting('test.pod_u2')::bigint, 1, 0);
select pg_temp.rk_predict(4, current_setting('test.pod_u3')::bigint, 1, 0);
select pg_temp.rk_predict(5, current_setting('test.pod_u1')::bigint, 1, 0);
select pg_temp.rk_predict(5, current_setting('test.pod_u2')::bigint, 1, 0);
select pg_temp.rk_predict(5, current_setting('test.pod_u3')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_u1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_u2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_u3')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_u')::bigint) = 1
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_u')::bigint) = 1
  and pg_temp.rk_award_count(4, 'third_of_the_matchday', current_setting('test.pod_u')::bigint) = 1
  and pg_temp.rk_award_count(5, 'top_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(5, 'second_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(5, 'third_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(2, 'sharp_shooter', current_setting('test.pod_u')::bigint) = 1,
  'unique 1/2/3 podium; Phase 2 Sharp Shooter still awards'
);

select set_config(
  'test.pod_u_earned',
  pg_temp.rk_earned_at(2, 'top_of_the_matchday', current_setting('test.pod_u')::bigint)::text,
  true
);

select public.recompute_matchday_badges(current_setting('test.pod_u')::bigint);

select pg_temp.rk_assert(
  pg_temp.rk_earned_at(2, 'top_of_the_matchday', current_setting('test.pod_u')::bigint)
    = current_setting('test.pod_u_earned')::timestamptz,
  'unchanged Top of the Matchday keeps earned_at'
);

-- Tie rank 1: two Tops, no Second, next is Third
select set_config('test.pod_t1', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_t1a', pg_temp.rk_add_match(current_setting('test.pod_t1')::bigint, now() + interval '51 days')::text, true);
select set_config('test.pod_t1b', pg_temp.rk_add_match(current_setting('test.pod_t1')::bigint, now() + interval '51 days 1 hour')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_t1a')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_t1b')::bigint, 2, 1);
select pg_temp.rk_predict(6, current_setting('test.pod_t1a')::bigint, 2, 1);
select pg_temp.rk_predict(6, current_setting('test.pod_t1b')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_t1a')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_t1b')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_t1a')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_t1b')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_t1')::bigint) = 1
  and pg_temp.rk_award_count(6, 'top_of_the_matchday', current_setting('test.pod_t1')::bigint) = 1
  and pg_temp.rk_award_count(2, 'second_of_the_matchday', current_setting('test.pod_t1')::bigint) = 0
  and pg_temp.rk_award_count(6, 'second_of_the_matchday', current_setting('test.pod_t1')::bigint) = 0
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_t1')::bigint) = 0
  and pg_temp.rk_award_count(3, 'third_of_the_matchday', current_setting('test.pod_t1')::bigint) = 1,
  'tie rank 1 => two Top, no Second, next Third'
);

-- Tie rank 2: unique Top, two Seconds, skipped Third
select set_config('test.pod_t2', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_t2a', pg_temp.rk_add_match(current_setting('test.pod_t2')::bigint, now() + interval '52 days')::text, true);
select set_config('test.pod_t2b', pg_temp.rk_add_match(current_setting('test.pod_t2')::bigint, now() + interval '52 days 1 hour')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_t2a')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_t2b')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_t2a')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_t2b')::bigint, 0, 0);
select pg_temp.rk_predict(4, current_setting('test.pod_t2a')::bigint, 2, 1);
select pg_temp.rk_predict(4, current_setting('test.pod_t2b')::bigint, 0, 0);
select pg_temp.rk_predict(5, current_setting('test.pod_t2a')::bigint, 1, 0);
select pg_temp.rk_predict(5, current_setting('test.pod_t2b')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_t2a')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_t2b')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_t2')::bigint) = 1
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_t2')::bigint) = 1
  and pg_temp.rk_award_count(4, 'second_of_the_matchday', current_setting('test.pod_t2')::bigint) = 1
  and pg_temp.rk_award_count(5, 'third_of_the_matchday', current_setting('test.pod_t2')::bigint) = 0
  and pg_temp.rk_award_count(3, 'third_of_the_matchday', current_setting('test.pod_t2')::bigint) = 0,
  'tie rank 2 => multiple Second, skipped Third'
);

-- Exact breaks a points tie: 2 exacts (10) vs 5 corrects (10).
select set_config('test.pod_ex', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_ex1', pg_temp.rk_add_match(current_setting('test.pod_ex')::bigint, now() + interval '53 days')::text, true);
select set_config('test.pod_ex2', pg_temp.rk_add_match(current_setting('test.pod_ex')::bigint, now() + interval '53 days 1 hour')::text, true);
select set_config('test.pod_ex3', pg_temp.rk_add_match(current_setting('test.pod_ex')::bigint, now() + interval '53 days 2 hours')::text, true);
select set_config('test.pod_ex4', pg_temp.rk_add_match(current_setting('test.pod_ex')::bigint, now() + interval '53 days 3 hours')::text, true);
select set_config('test.pod_ex5', pg_temp.rk_add_match(current_setting('test.pod_ex')::bigint, now() + interval '53 days 4 hours')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_ex1')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_ex2')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_ex3')::bigint, 0, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_ex4')::bigint, 0, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_ex5')::bigint, 0, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_ex1')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.pod_ex2')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.pod_ex3')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.pod_ex4')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.pod_ex5')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_ex1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_ex2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_ex3')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_ex4')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_ex5')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_ex')::bigint) = 1
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_ex')::bigint) = 1,
  'equal points: more exacts ranks above more corrects'
);

-- Correct breaks an exact tie. On 5/2/0, equal points and equal exacts imply
-- equal corrects, so this uses one Golden Match (4) against two normal
-- corrects (2+2) with the same exact count.
select set_config('test.pod_cr', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_cr1', pg_temp.rk_add_match(current_setting('test.pod_cr')::bigint, now() + interval '54 days')::text, true);
select set_config('test.pod_cr2', pg_temp.rk_add_match(current_setting('test.pod_cr')::bigint, now() + interval '54 days 1 hour')::text, true);
select set_config('test.pod_cr3', pg_temp.rk_add_match(current_setting('test.pod_cr')::bigint, now() + interval '54 days 2 hours')::text, true);

insert into public.golden_match_selections (user_id, matchday_id, match_id)
values (
  pg_temp.rk_user_id(2),
  current_setting('test.pod_cr')::bigint,
  current_setting('test.pod_cr1')::bigint
);

select pg_temp.rk_predict(2, current_setting('test.pod_cr1')::bigint, 1, 0);
select pg_temp.rk_predict(2, current_setting('test.pod_cr2')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_cr3')::bigint, 0, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_cr1')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_cr2')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.pod_cr3')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_cr1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_cr2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_cr3')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'top_of_the_matchday', current_setting('test.pod_cr')::bigint) = 1
  and pg_temp.rk_award_count(2, 'second_of_the_matchday', current_setting('test.pod_cr')::bigint) = 1,
  'same points and exacts: more corrects ranks higher'
);

-- Missed breaks a correct tie
-- Same points, exact, correct; fewer missed wins.
-- U2: 1 exact on 1 match (no miss)
-- U3: 1 exact on 2 matches (1 miss)
-- Points 5 vs 5, exact 1 vs 1, correct 0 vs 0, missed 0 vs 1.
select set_config('test.pod_ms', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_ms1', pg_temp.rk_add_match(current_setting('test.pod_ms')::bigint, now() + interval '55 days')::text, true);
select set_config('test.pod_ms2', pg_temp.rk_add_match(current_setting('test.pod_ms')::bigint, now() + interval '55 days 1 hour')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_ms1')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.pod_ms2')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_ms1')::bigint, 2, 1);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_ms1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.pod_ms2')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_ms')::bigint) = 1
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_ms')::bigint) = 1,
  'same points/exact/correct: fewer missed ranks higher'
);

-- Username / user_id does not break a true tie
select set_config('test.pod_tt', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.pod_tt1', pg_temp.rk_add_match(current_setting('test.pod_tt')::bigint, now() + interval '56 days')::text, true);

select pg_temp.rk_predict(2, current_setting('test.pod_tt1')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.pod_tt1')::bigint, 2, 1);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_tt1')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_tt')::bigint) = 1
  and pg_temp.rk_award_count(3, 'top_of_the_matchday', current_setting('test.pod_tt')::bigint) = 1
  and pg_temp.rk_award_count(2, 'second_of_the_matchday', current_setting('test.pod_tt')::bigint) = 0
  and pg_temp.rk_award_count(3, 'second_of_the_matchday', current_setting('test.pod_tt')::bigint) = 0,
  'identical stats share rank 1 regardless of username/user_id'
);

-- Correction reassigns medals; incomplete removes podium
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.pod_u3')::bigint, 1, 0);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'top_of_the_matchday', current_setting('test.pod_u')::bigint) = 1
  and pg_temp.rk_award_count(2, 'top_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(2, 'second_of_the_matchday', current_setting('test.pod_u')::bigint) = 1,
  'correction reassigns podium medals'
);

update public.matches
set status = 'scheduled'
where id = current_setting('test.pod_u1')::bigint;

select public.recompute_matchday_badges(current_setting('test.pod_u')::bigint);

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'top_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(2, 'second_of_the_matchday', current_setting('test.pod_u')::bigint) = 0
  and pg_temp.rk_award_count(2, 'sharp_shooter', current_setting('test.pod_u')::bigint) = 0,
  'incomplete round removes podium and Phase 2 matchday badges'
);

update public.matches
set
  status = 'finished',
  home_score = 2,
  away_score = 1
where id = current_setting('test.pod_u1')::bigint;

-- ---------------------------------------------------------------------------
-- B. Leader
-- ---------------------------------------------------------------------------

select set_config('test.lead_md', pg_temp.rk_add_matchday('quarter_final')::text, true);
select set_config('test.lead_m', pg_temp.rk_add_match(current_setting('test.lead_md')::bigint, now() + interval '57 days')::text, true);
select pg_temp.rk_predict(2, current_setting('test.lead_m')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.lead_m')::bigint, 1, 0);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lead_m')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'leader') = 1
  and pg_temp.rk_award_count(3, 'leader') = 0,
  '#1 earns Leader'
);

select set_config('test.lead_earned', pg_temp.rk_earned_at(2, 'leader')::text, true);

select public.award_leader_if_applicable();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'leader') = 1
  and pg_temp.rk_earned_at(2, 'leader') = current_setting('test.lead_earned')::timestamptz,
  'repeated Leader check does not duplicate or move earned_at'
);

-- Shared #1
select set_config('test.lead_m2', pg_temp.rk_add_match(current_setting('test.lead_md')::bigint, now() + interval '57 days 1 hour')::text, true);
select pg_temp.rk_predict(3, current_setting('test.lead_m2')::bigint, 2, 1);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lead_m2')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'leader') = 1
  and pg_temp.rk_award_count(3, 'leader') = 1,
  'shared #1 all earn Leader; previous Leader kept'
);

-- Falling later does not remove
select set_config('test.lead_m3', pg_temp.rk_add_match(current_setting('test.lead_md')::bigint, now() + interval '57 days 2 hours')::text, true);
select pg_temp.rk_predict(3, current_setting('test.lead_m3')::bigint, 2, 1);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lead_m3')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.rk_user_id(2)
  ) > 1
  and pg_temp.rk_award_count(2, 'leader') = 1
  and pg_temp.rk_award_count(3, 'leader') = 1,
  'falling from #1 does not remove Leader'
);

-- Correction does not remove: reverse the last result so 2 is #1 again, then
-- re-score so 3 is #1. User 2 keeps Leader throughout.
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lead_m3')::bigint, 0, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'leader') = 1,
  'correction that changes #1 does not remove previous Leader'
);

-- Inactive user does not newly earn. Three new exacts would be unique #1
-- among the fixtures, but the user is disabled before scoring.
select set_config('test.lead_inact', pg_temp.rk_add_matchday('playoff')::text, true);
select set_config('test.lead_i1', pg_temp.rk_add_match(current_setting('test.lead_inact')::bigint, now() + interval '57 days 3 hours')::text, true);
select set_config('test.lead_i2', pg_temp.rk_add_match(current_setting('test.lead_inact')::bigint, now() + interval '57 days 4 hours')::text, true);
select set_config('test.lead_i3', pg_temp.rk_add_match(current_setting('test.lead_inact')::bigint, now() + interval '57 days 5 hours')::text, true);
select pg_temp.rk_predict(4, current_setting('test.lead_i1')::bigint, 2, 1);
select pg_temp.rk_predict(4, current_setting('test.lead_i2')::bigint, 2, 1);
select pg_temp.rk_predict(4, current_setting('test.lead_i3')::bigint, 2, 1);

update public.profiles
set status = 'disabled'
where id = pg_temp.rk_user_id(4);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lead_i1')::bigint, 2, 1);
select public.set_match_result(current_setting('test.lead_i2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.lead_i3')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_award_count(4, 'leader') = 0,
  'inactive user does not newly earn Leader even with the highest raw points'
);

update public.profiles
set status = 'active'
where id = pg_temp.rk_user_id(4);

select public.award_leader_if_applicable();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(4, 'leader') = 1,
  'once active, current #1 can earn Leader; this is not a fabricated past #1'
);

-- ---------------------------------------------------------------------------
-- C. League Phase
-- ---------------------------------------------------------------------------

select set_config('test.cup_id', pg_temp.rk_ensure_cup(false)::text, true);

select set_config('test.lp_md', pg_temp.rk_add_matchday('league_phase')::text, true);
select set_config('test.lp_m1', pg_temp.rk_add_match(current_setting('test.lp_md')::bigint, now() + interval '58 days')::text, true);
select set_config('test.lp_m2', pg_temp.rk_add_match(current_setting('test.lp_md')::bigint, now() + interval '58 days 1 hour')::text, true);
select set_config('test.ko_md', pg_temp.rk_add_matchday('round_of_16')::text, true);
select set_config('test.ko_m', pg_temp.rk_add_match(current_setting('test.ko_md')::bigint, now() + interval '58 days 2 hours')::text, true);

select pg_temp.rk_predict(2, current_setting('test.lp_m1')::bigint, 2, 1);
select pg_temp.rk_predict(2, current_setting('test.lp_m2')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.lp_m1')::bigint, 1, 0);
select pg_temp.rk_predict(3, current_setting('test.ko_m')::bigint, 2, 1);
select pg_temp.rk_predict(5, current_setting('test.lp_m1')::bigint, 2, 1);
select pg_temp.rk_predict(6, current_setting('test.lp_m1')::bigint, 2, 1);
select pg_temp.rk_predict(6, current_setting('test.lp_m2')::bigint, 1, 0);
select pg_temp.rk_predict(7, current_setting('test.lp_m1')::bigint, 2, 1);
select pg_temp.rk_predict(8, current_setting('test.lp_m1')::bigint, 1, 0);
select pg_temp.rk_predict(8, current_setting('test.lp_m2')::bigint, 1, 0);

select pg_temp.rk_assert(
  public.badge_league_phase_is_complete() = false,
  'LP not complete while new LP matches are unfinished'
);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'league_phase_champion') = 0,
  'LP badges not awarded before all LP matches finished'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lp_m1')::bigint, 2, 1);
reset role;

update public.matches
set
  status = 'finished',
  home_score = 2,
  away_score = 1
where id = current_setting('test.lp_m2')::bigint;

select pg_temp.rk_assert(
  public.badge_league_phase_is_complete() = false,
  'LP not complete with NULL prediction points'
);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'league_phase_champion') = 0,
  'LP badges not awarded with NULL prediction points'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.lp_m2')::bigint, 2, 1);
select public.set_match_result(current_setting('test.ko_m')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  public.badge_league_phase_is_complete() = false,
  'LP not complete before Players Cup completed'
);

select pg_temp.rk_ensure_cup(true);

select pg_temp.rk_assert(
  public.badge_league_phase_is_complete() = false,
  'LP not complete before league_phase_first outcome decided'
);

insert into public.long_term_predictions (user_id, prediction_type, team_id)
values
  (pg_temp.rk_user_id(2), 'league_phase_first', current_setting('test.team_home')::bigint),
  (pg_temp.rk_user_id(3), 'league_phase_first', current_setting('test.team_away')::bigint),
  (pg_temp.rk_user_id(2), 'winner', current_setting('test.team_home')::bigint),
  (pg_temp.rk_user_id(3), 'winner', current_setting('test.team_home')::bigint);

insert into public.long_term_outcomes (prediction_type, team_id, decided_by)
values (
  'league_phase_first',
  current_setting('test.team_home')::bigint,
  pg_temp.rk_user_id(1)
);

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values
  (
    pg_temp.rk_user_id(2),
    'league_phase_first',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    15
  ),
  (
    pg_temp.rk_user_id(3),
    'league_phase_first',
    current_setting('test.team_away')::bigint,
    current_setting('test.team_home')::bigint,
    0
  ),
  (
    pg_temp.rk_user_id(3),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    30
  );

select pg_temp.rk_assert(
  public.badge_league_phase_is_complete() = true,
  'LP complete after matches, Cup and LP-first outcome'
);

select public.recompute_league_phase_badges();

-- User 2: two LP exacts (10) + LP-first 15 = 25, knockout ignored
-- User 3: one LP correct (2) + winner 30 ignored + knockout exact ignored = 2
-- User 5: one LP exact (5)
select pg_temp.rk_assert(
  (
    select standing.total_points
    from public.badge_league_phase_ranking() as standing
    where standing.user_id = pg_temp.rk_user_id(2)
  ) = 25
  and (
    select standing.total_points
    from public.badge_league_phase_ranking() as standing
    where standing.user_id = pg_temp.rk_user_id(3)
  ) = 2
  and pg_temp.rk_award_count(2, 'league_phase_champion') = 1
  and pg_temp.rk_award_count(3, 'league_phase_champion') = 0
  and pg_temp.rk_award_count(5, 'league_phase_runner_up') = 1,
  'LP ranking includes LP points and LP-first, excludes winner and knockout'
);

select pg_temp.rk_set_cup_award(
  current_setting('test.cup_id')::bigint,
  3,
  'winner',
  50
);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  (
    select standing.total_points
    from public.badge_league_phase_ranking() as standing
    where standing.user_id = pg_temp.rk_user_id(3)
  ) = 52
  and pg_temp.rk_award_count(3, 'league_phase_champion') = 1
  and pg_temp.rk_award_count(2, 'league_phase_runner_up') = 1
  and pg_temp.rk_award_count(2, 'league_phase_champion') = 0,
  'LP ranking includes persisted Cup award points; correction reassigns'
);

select set_config(
  'test.lp_earned',
  pg_temp.rk_earned_at(3, 'league_phase_champion')::text,
  true
);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_earned_at(3, 'league_phase_champion')
    = current_setting('test.lp_earned')::timestamptz,
  'unchanged LP Champion keeps earned_at'
);

-- Shared LP rank 1: give user 2 the same 52 via a cup finalist? 25+27 no.
-- Give user 2 a cup award of 27? Better: set user 2 cup to 27 doesn't exist.
-- Set both to winner? Unique participant. Give user 2 50 as well by updating
-- points on a finalist row: insert finalist 27... 25+27=52.
delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;

select pg_temp.rk_set_cup_award(
  current_setting('test.cup_id')::bigint,
  2,
  'winner',
  27
);
select pg_temp.rk_set_cup_award(
  current_setting('test.cup_id')::bigint,
  3,
  'finalist',
  50
);

-- Shared LP rank 1: equalize by dropping cup and long-term points.
delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;
delete from public.long_term_awards;

select public.recompute_league_phase_badges();

-- user2 two exacts 10, user6 exact+correct 7, user5 one exact 5
-- For shared 1: copy user2 predictions onto user 7 — user7 already has one exact.
-- Score user7's second match exact.
select pg_temp.rk_predict(7, current_setting('test.lp_m2')::bigint, 2, 1);
update public.predictions
set points = 5
where user_id = pg_temp.rk_user_id(7)
  and match_id = current_setting('test.lp_m2')::bigint;

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'league_phase_champion') = 1
  and pg_temp.rk_award_count(7, 'league_phase_champion') = 1
  and pg_temp.rk_award_count(2, 'league_phase_runner_up') = 0
  and pg_temp.rk_award_count(7, 'league_phase_runner_up') = 0
  and pg_temp.rk_award_count(6, 'league_phase_runner_up') = 0,
  'shared LP rank 1 => two Champions, no Runner-up'
);

-- Restore LP-first points for later season tests
insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values
  (
    pg_temp.rk_user_id(2),
    'league_phase_first',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    15
  ),
  (
    pg_temp.rk_user_id(3),
    'league_phase_first',
    current_setting('test.team_away')::bigint,
    current_setting('test.team_home')::bigint,
    0
  );

select pg_temp.rk_set_cup_award(
  current_setting('test.cup_id')::bigint,
  3,
  'winner',
  50
);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'league_phase_champion') = 1,
  'user 3 is LP Champion before inactivity test'
);

update public.profiles
set status = 'disabled'
where id = pg_temp.rk_user_id(3);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'league_phase_champion') = 1
  and pg_temp.rk_award_count(2, 'league_phase_champion') = 0,
  'inactivity alone does not revoke LP Champion or let the next active user steal it'
);

delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint
  and user_id = pg_temp.rk_user_id(3);

select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'league_phase_champion') = 0
  and pg_temp.rk_award_count(2, 'league_phase_champion') = 1,
  'LP data correction revokes an inactive holder who is no longer Champion'
);

update public.profiles
set status = 'active'
where id = pg_temp.rk_user_id(3);

select pg_temp.rk_set_cup_award(
  current_setting('test.cup_id')::bigint,
  3,
  'winner',
  50
);

select public.recompute_league_phase_badges();

-- ---------------------------------------------------------------------------
-- D. Season
-- ---------------------------------------------------------------------------

select pg_temp.rk_ensure_cup(false);

select set_config('test.final_md', pg_temp.rk_add_matchday('final')::text, true);
select set_config('test.final_m', pg_temp.rk_add_match(current_setting('test.final_md')::bigint, now() + interval '59 days')::text, true);
select pg_temp.rk_predict(2, current_setting('test.final_m')::bigint, 2, 1);
select pg_temp.rk_predict(3, current_setting('test.final_m')::bigint, 1, 0);
select pg_temp.rk_predict(4, current_setting('test.final_m')::bigint, 2, 1);
select pg_temp.rk_predict(5, current_setting('test.final_m')::bigint, 0, 0);
select pg_temp.rk_predict(6, current_setting('test.final_m')::bigint, 0, 1);

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'season not complete while Final is unfinished'
);

select public.recompute_season_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'season_champion') = 0,
  'Final not complete => no season awards'
);

select pg_temp.rk_ensure_cup(true);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.final_m')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_points(2, current_setting('test.final_m')::bigint) = 10
  and pg_temp.rk_points(3, current_setting('test.final_m')::bigint) = 4
  and pg_temp.rk_award_count(2, 'final_boss') = 1,
  'Final still 10/4/0 and Final Boss still awards'
);

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'Winner long-term not decided => no season awards'
);

insert into public.long_term_outcomes (prediction_type, team_id, decided_by)
values (
  'winner',
  current_setting('test.team_home')::bigint,
  pg_temp.rk_user_id(1)
);

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values
  (
    pg_temp.rk_user_id(2),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    30
  ),
  (
    pg_temp.rk_user_id(3),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    30
  )
on conflict on constraint long_term_awards_pkey do update
set points = excluded.points;

select pg_temp.rk_assert(
  public.badge_season_is_complete() = true,
  'season complete after Final, Cup, winner and LP-first'
);

select set_config('test.sz_ko', pg_temp.rk_add_matchday('round_of_16')::text, true);
select set_config(
  'test.sz_ko_m',
  pg_temp.rk_add_match(current_setting('test.sz_ko')::bigint, now() + interval '59 days 3 hours')::text,
  true
);

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'Final finished but an earlier knockout match unfinished => season incomplete'
);

update public.matches
set
  status = 'finished',
  home_score = 1,
  away_score = 0
where id = current_setting('test.sz_ko_m')::bigint;

select pg_temp.rk_predict(9, current_setting('test.sz_ko_m')::bigint, 1, 0);

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'Final finished but an earlier prediction is NULL => season incomplete'
);

update public.predictions
set points = 5
where user_id = pg_temp.rk_user_id(9)
  and match_id = current_setting('test.sz_ko_m')::bigint;

select pg_temp.rk_assert(
  public.badge_season_is_complete() = true,
  'all existing competition matches finished/scored + other gates => complete'
);

delete from public.long_term_outcomes
where prediction_type = 'league_phase_first';

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'LP-first outcome not decided => no season awards'
);

insert into public.long_term_outcomes (prediction_type, team_id, decided_by)
values (
  'league_phase_first',
  current_setting('test.team_home')::bigint,
  pg_temp.rk_user_id(1)
);

select pg_temp.rk_ensure_cup(false);

select pg_temp.rk_assert(
  public.badge_season_is_complete() = false,
  'Cup not complete => no season awards'
);

select pg_temp.rk_ensure_cup(true);
select public.recompute_season_badges();

-- Canonical leaderboard among fixtures. User 3 has Cup 50 + winner 30 + LP 2
-- + Final correct 4 + knockout exact 5 from ko_m = large. User 2 has LP 10
-- + LP-first 15 + winner 30 + Final exact 10. User 4 has Final exact 10 +
-- Leader matchday points. Assert Top 5 uses actual RANK values.
select pg_temp.rk_assert(
  pg_temp.rk_award_count(3, 'season_champion') = 1
  or pg_temp.rk_award_count(4, 'season_champion') = 1
  or pg_temp.rk_award_count(2, 'season_champion') = 1,
  'completed season awards Champion from get_leaderboard rank 1'
);

select pg_temp.rk_assert(
  not exists (
    select 1
    from public.badge_awards as award
    join public.get_leaderboard() as standing
      on standing.user_id = award.user_id
    where award.badge_code = 'season_champion'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
      and standing.rank_position <> 1
  )
  and not exists (
    select 1
    from public.badge_awards as award
    join public.get_leaderboard() as standing
      on standing.user_id = award.user_id
    where award.badge_code = 'season_runner_up'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
      and standing.rank_position <> 2
  )
  and not exists (
    select 1
    from public.badge_awards as award
    join public.get_leaderboard() as standing
      on standing.user_id = award.user_id
    where award.badge_code = 'season_top_5'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
      and standing.rank_position not in (3, 4, 5)
  ),
  'season badges follow canonical RANK 1 / 2 / 3-5'
);

-- Shared ranks: compare awarded counts to canonical RANK occupancy.
select public.recompute_season_badges();

select pg_temp.rk_assert(
  (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'season_champion'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
  ) = (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position = 1
  )
  and (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'season_runner_up'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
  ) = (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position = 2
  )
  and (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'season_top_5'
      and award.user_id in (
        select pg_temp.rk_user_id(index.n)
        from generate_series(1, 10) as index(n)
      )
  ) = (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position in (3, 4, 5)
  ),
  'shared ranks and skipped ranks are respected; Top 5 is only 3/4/5'
);

select set_config(
  'test.sz_earned',
  (
    select award.earned_at::text
    from public.badge_awards as award
    where award.badge_code = 'season_champion'
    order by award.earned_at
    limit 1
  ),
  true
);

select public.recompute_season_badges();

select pg_temp.rk_assert(
  (
    select min(award.earned_at)
    from public.badge_awards as award
    where award.badge_code = 'season_champion'
  ) = current_setting('test.sz_earned')::timestamptz,
  'unchanged Season Champion keeps earned_at'
);

select set_config(
  'test.sz_champ',
  (
    select award.user_id::text
    from public.badge_awards as award
    where award.badge_code = 'season_champion'
    order by award.earned_at
    limit 1
  ),
  true
);

update public.profiles
set status = 'disabled'
where id = current_setting('test.sz_champ')::uuid;

select public.recompute_season_badges();

select pg_temp.rk_assert(
  exists (
    select 1
    from public.badge_awards as award
    where award.user_id = current_setting('test.sz_champ')::uuid
      and award.badge_code = 'season_champion'
  )
  and not exists (
    select 1
    from public.get_leaderboard() as standing
    where standing.user_id = current_setting('test.sz_champ')::uuid
  ),
  'inactivity alone does not revoke Season Champion'
);

update public.profiles
set status = 'active'
where id = current_setting('test.sz_champ')::uuid;

select public.recompute_season_badges();

-- Correction: remove Cup 50 from user 3 so ranking moves
delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint
  and award_type = 'winner';

select public.recompute_season_badges();
select public.recompute_league_phase_badges();

select pg_temp.rk_assert(
  exists (
    select 1
    from public.get_leaderboard() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'season_champion'
    where standing.rank_position = 1
  ),
  'season correction reassigns Champion to current rank 1'
);

-- ---------------------------------------------------------------------------
-- E. Players Cup badges
-- ---------------------------------------------------------------------------

delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;

select pg_temp.rk_set_cup_award(current_setting('test.cup_id')::bigint, 2, 'winner', 50);
select pg_temp.rk_set_cup_award(current_setting('test.cup_id')::bigint, 3, 'finalist', 30);
select pg_temp.rk_set_cup_award(current_setting('test.cup_id')::bigint, 5, 'semi_finalist', 15);
select pg_temp.rk_set_cup_award(current_setting('test.cup_id')::bigint, 6, 'semi_finalist', 15);

select public.sync_players_cup_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'players_cup_champion') = 1
  and pg_temp.rk_award_count(2, 'players_cup_finalist') = 0
  and pg_temp.rk_award_count(2, 'players_cup_semifinalist') = 0
  and pg_temp.rk_award_count(3, 'players_cup_finalist') = 1
  and pg_temp.rk_award_count(3, 'players_cup_champion') = 0
  and pg_temp.rk_award_count(3, 'players_cup_semifinalist') = 0
  and pg_temp.rk_award_count(5, 'players_cup_semifinalist') = 1
  and pg_temp.rk_award_count(6, 'players_cup_semifinalist') = 1
  and (
    select award.cup_id
    from public.badge_awards as award
    where award.user_id = pg_temp.rk_user_id(2)
      and award.badge_code = 'players_cup_champion'
  ) = current_setting('test.cup_id')::bigint,
  'Cup mapping is non-cumulative and cup_id is attached'
);

select set_config(
  'test.cup_earned',
  pg_temp.rk_earned_at(2, 'players_cup_champion')::text,
  true
);

select public.sync_players_cup_badges();

select pg_temp.rk_assert(
  pg_temp.rk_earned_at(2, 'players_cup_champion')
    = current_setting('test.cup_earned')::timestamptz,
  'unchanged Cup honour keeps earned_at'
);

select pg_temp.rk_set_cup_award(current_setting('test.cup_id')::bigint, 2, 'finalist', 30);
delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint
  and user_id = pg_temp.rk_user_id(3);

select public.sync_players_cup_badges();

select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'players_cup_champion') = 0
  and pg_temp.rk_award_count(2, 'players_cup_finalist') = 1
  and pg_temp.rk_award_count(3, 'players_cup_finalist') = 0,
  'stale Cup badges are removed when cup_awards change'
);

select pg_temp.rk_assert(
  position('cup_ties' in pg_temp.rk_source('public.sync_players_cup_badges()')) = 0
  and position('players_cup_apply' in pg_temp.rk_source('public.sync_players_cup_badges()')) = 0,
  'Cup badge sync does not recalculate the bracket'
);

-- ---------------------------------------------------------------------------
-- F / G. Write paths and scoring regressions
-- ---------------------------------------------------------------------------

select pg_temp.rk_assert(
  position('players_cup_apply' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('recompute_matchday_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('recompute_cumulative_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('recompute_ranking_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('players_cup_apply' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
    < position('recompute_matchday_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
  and position('recompute_matchday_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
    < position('recompute_cumulative_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
  and position('recompute_cumulative_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
    < position('recompute_ranking_badges' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)'))
  and position('when v_stage = ''final'' then 10' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('when v_stage = ''final'' then 4' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('when selection.id is not null then 10' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0
  and position('when selection.id is not null then 4' in pg_temp.rk_source('public.set_match_result(bigint, integer, integer)')) > 0,
  'set_match_result keeps Cup then Phase 2 badges then ranking; Final/GM 10/4 remain'
);

select pg_temp.rk_assert(
  position('award_leader_if_applicable' in pg_temp.rk_source('public.recompute_ranking_badges()')) > 0
  and position('recompute_league_phase_badges' in pg_temp.rk_source('public.recompute_ranking_badges()')) > 0
  and position('recompute_season_badges' in pg_temp.rk_source('public.recompute_ranking_badges()')) > 0
  and position('sync_players_cup_badges' in pg_temp.rk_source('public.recompute_ranking_badges()')) > 0
  and position('recompute_matchday_badges' in pg_temp.rk_source('public.recompute_ranking_badges()')) = 0,
  'orchestrator covers Leader/LP/season/Cup and does not walk matchday podiums'
);

select pg_temp.rk_assert(
  position('recompute_ranking_badges' in pg_temp.rk_source('public.set_long_term_outcome(text, bigint)')) > 0
  and position('recompute_ranking_badges' in pg_temp.rk_source('public.set_long_term_outcome(text, bigint)'))
    > position('long_term_awards' in pg_temp.rk_source('public.set_long_term_outcome(text, bigint)')),
  'set_long_term_outcome recomputes ranking after awards'
);

select pg_temp.rk_assert(
  position('players_cup_apply' in pg_temp.rk_source('public.recompute_players_cup()')) > 0
  and position('recompute_ranking_badges' in pg_temp.rk_source('public.recompute_players_cup()')) > 0
  and position('players_cup_apply' in pg_temp.rk_source('public.recompute_players_cup()'))
    < position('recompute_ranking_badges' in pg_temp.rk_source('public.recompute_players_cup()')),
  'recompute_players_cup applies the Cup then ranking badges'
);

select pg_temp.rk_assert(
  position('recompute_ranking_badges' in pg_temp.rk_source('public.players_cup_apply(bigint)')) = 0
  and position('sync_players_cup_badges' in pg_temp.rk_source('public.players_cup_apply(bigint)')) = 0,
  'players_cup_apply body is unchanged; Cup badges sync from the orchestrator'
);

-- Live long-term write path: complete Matchday 3 if present, then award.
do $test$
declare
  v_md3 bigint;
begin
  select matchday.id
  into v_md3
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = 3;

  if v_md3 is null then
    return;
  end if;

  if not exists (
    select 1
    from public.matches as match_row
    where match_row.matchday_id = v_md3
  ) then
    insert into public.matches (
      matchday_id,
      home_team_id,
      away_team_id,
      kickoff_at,
      status,
      home_score,
      away_score
    )
    values (
      v_md3,
      current_setting('test.team_home')::bigint,
      current_setting('test.team_away')::bigint,
      now() + interval '3 days',
      'finished',
      1,
      0
    );
  else
    update public.matches as match_row
    set
      status = 'finished',
      home_score = coalesce(match_row.home_score, 1),
      away_score = coalesce(match_row.away_score, 0),
      updated_at = now()
    where match_row.matchday_id = v_md3
      and match_row.status is distinct from 'finished';
  end if;

  update public.predictions as prediction
  set points = coalesce(prediction.points, 0)
  from public.matches as match_row
  where match_row.id = prediction.match_id
    and match_row.matchday_id = v_md3
    and prediction.points is null;

  perform set_config(
    'request.jwt.claim.sub',
    pg_temp.rk_user_id(1)::text,
    true
  );
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.set_long_term_outcome(
    'league_phase_first',
    current_setting('test.team_home')::bigint
  );

  perform pg_temp.rk_assert(
    exists (
      select 1
      from public.get_leaderboard() as standing
      join public.badge_awards as award
        on award.user_id = standing.user_id
        and award.badge_code = 'leader'
      where standing.rank_position = 1
    ),
    'set_long_term_outcome awards Leader to current #1'
  );
end;
$test$;

reset role;

do $test$
begin
  if exists (
    select 1
    from public.cup_rounds as round
    join public.cup_competitions as competition
      on competition.id = round.cup_id
    where competition.slug = 'players-cup-2026-27'
  ) then
    perform set_config(
      'request.jwt.claim.sub',
      pg_temp.rk_user_id(1)::text,
      true
    );
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    execute 'set local role authenticated';
    perform public.recompute_players_cup();
  end if;
end;
$test$;

reset role;

select pg_temp.rk_assert(
  exists (
    select 1
    from public.get_leaderboard() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'leader'
    where standing.rank_position = 1
  ),
  'recompute_players_cup still leaves current #1 with Leader'
);

-- Golden Match still 10/4/0 and does not stack on Final (already 10/4 above)
select set_config('test.gm_md', pg_temp.rk_add_matchday('league_phase')::text, true);
select set_config('test.gm_m', pg_temp.rk_add_match(current_setting('test.gm_md')::bigint, now() + interval '61 days')::text, true);
insert into public.golden_match_selections (user_id, matchday_id, match_id)
values (
  pg_temp.rk_user_id(8),
  current_setting('test.gm_md')::bigint,
  current_setting('test.gm_m')::bigint
);
select pg_temp.rk_predict(8, current_setting('test.gm_m')::bigint, 2, 1);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rk_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.set_match_result(current_setting('test.gm_m')::bigint, 2, 1);
reset role;

select pg_temp.rk_assert(
  pg_temp.rk_points(8, current_setting('test.gm_m')::bigint) = 10,
  'Golden Match exact is still 10'
);

-- Adding this LP match made LP incomplete until scored; it is now scored.
-- On Fire / Exact Machine / Perfect still reachable via Phase 2 rules.
select pg_temp.rk_assert(
  pg_temp.rk_award_count(2, 'exact_machine')
    = case when (
      select count(*)
      from public.predictions as prediction
      where prediction.user_id = pg_temp.rk_user_id(2)
        and public.prediction_is_exact(prediction.points)
    ) >= 10 then 1 else 0 end,
  'Exact Machine still follows the Phase 2 threshold'
);

-- ---------------------------------------------------------------------------
-- H. Security
-- ---------------------------------------------------------------------------

reset role;
select set_config(
  'request.jwt.claim.sub',
  pg_temp.rk_user_id(2)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
begin
  begin
    insert into public.badge_awards (user_id, badge_code, award_scope)
    values (pg_temp.rk_user_id(2), 'leader', 'season');
    raise exception 'BADGES RANKING TEST FAILED: player inserted an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.award_leader_if_applicable();
    raise exception 'BADGES RANKING TEST FAILED: player executed award_leader_if_applicable';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_ranking_badges();
    raise exception 'BADGES RANKING TEST FAILED: player executed recompute_ranking_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.sync_players_cup_badges();
    raise exception 'BADGES RANKING TEST FAILED: player executed sync_players_cup_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_league_phase_badges();
    raise exception 'BADGES RANKING TEST FAILED: player executed recompute_league_phase_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_season_badges();
    raise exception 'BADGES RANKING TEST FAILED: player executed recompute_season_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_league_phase_is_complete();
    raise exception 'BADGES RANKING TEST FAILED: player executed badge_league_phase_is_complete';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_season_is_complete();
    raise exception 'BADGES RANKING TEST FAILED: player executed badge_season_is_complete';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_league_phase_ranking_for('{}'::uuid[]);
    raise exception 'BADGES RANKING TEST FAILED: player executed badge_league_phase_ranking_for';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.badge_season_ranking_for('{}'::uuid[]);
    raise exception 'BADGES RANKING TEST FAILED: player executed badge_season_ranking_for';
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
    where profile.username like 'zzrnk%'
  ) then
    raise exception 'BADGES RANKING TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'podium_unique_1_2_3',
  'podium_tie_rank_1',
  'podium_tie_rank_2',
  'podium_exact_breaks_points',
  'podium_correct_breaks_exact',
  'podium_missed_breaks_correct',
  'podium_true_tie_no_username_break',
  'podium_correction_and_incomplete',
  'leader_unique_shared_persist_inactive',
  'league_phase_gates_and_point_rules',
  'league_phase_inactive_holder_correction',
  'season_gates_and_shared_ranks',
  'season_earlier_knockout_and_null_prediction_gates',
  'season_inactive_holder_not_revoked_by_status',
  'players_cup_mapping_and_correction',
  'write_path_bodies_and_scoring',
  'player_cannot_self_award_or_recompute',
  'all_fixture_changes_rolled_back'
]) as passed_test;
