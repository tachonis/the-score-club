-- Transactional verification of the six additive badge tiers.
-- Every fixture mutation is rolled back. Do not run against hosted Supabase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.xt_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.xt_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9940 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.xt_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.xt_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'badges-extended-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzext' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.xt_add_matchday(p_stage text)
returns bigint
language plpgsql
as $helper$
declare
  v_number integer;
  v_id bigint;
begin
  select coalesce(max(matchday.matchday_number), 0) + 1
  into v_number
  from public.matchdays as matchday
  where matchday.stage = p_stage;

  insert into public.matchdays (stage, matchday_number, name)
  values (
    p_stage,
    v_number,
    'zz-badge-ext-' || p_stage || '-' || v_number::text
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.xt_add_match(p_matchday_id bigint, p_kickoff timestamptz)
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

create table pg_temp.xt_matches (
  matchday_key text not null,
  ordinal integer not null,
  match_id bigint not null,
  primary key (matchday_key, ordinal)
);

grant select on pg_temp.xt_matches to authenticated;

create function pg_temp.xt_fill_matchday(
  p_key text,
  p_matchday_id bigint,
  p_count integer,
  p_kickoff timestamptz
)
returns void
language plpgsql
as $helper$
declare
  v_n integer;
begin
  for v_n in 1..p_count loop
    insert into pg_temp.xt_matches (matchday_key, ordinal, match_id)
    values (
      p_key,
      v_n,
      pg_temp.xt_add_match(
        p_matchday_id,
        p_kickoff + ((v_n - 1) || ' hours')::interval
      )
    );
  end loop;
end;
$helper$;

create function pg_temp.xt_predict(
  p_index integer,
  p_key text,
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
  select
    pg_temp.xt_user_id(p_index),
    match_row.match_id,
    p_home,
    p_away
  from pg_temp.xt_matches as match_row
  where match_row.matchday_key = p_key;
$helper$;

create function pg_temp.xt_match(p_key text, p_ordinal integer)
returns bigint
language sql
stable
as $helper$
  select match_row.match_id
  from pg_temp.xt_matches as match_row
  where match_row.matchday_key = p_key
    and match_row.ordinal = p_ordinal;
$helper$;

create function pg_temp.xt_score(p_key text, p_ordinal integer, p_home integer, p_away integer)
returns void
language plpgsql
as $helper$
begin
  perform public.set_match_result(
    pg_temp.xt_match(p_key, p_ordinal),
    p_home,
    p_away
  );
end;
$helper$;

create function pg_temp.xt_score_range(
  p_key text,
  p_from integer,
  p_to integer,
  p_home integer,
  p_away integer
)
returns void
language plpgsql
as $helper$
declare
  v_n integer;
begin
  for v_n in p_from..p_to loop
    perform pg_temp.xt_score(p_key, v_n, p_home, p_away);
  end loop;
end;
$helper$;

create function pg_temp.xt_award_count(
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
  where award.user_id = pg_temp.xt_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.xt_points(p_index integer, p_matchday_id bigint)
returns bigint
language sql
stable
as $helper$
  select coalesce(sum(prediction.points), 0)::bigint
  from public.predictions as prediction
  join public.matches as match_row
    on match_row.id = prediction.match_id
  where prediction.user_id = pg_temp.xt_user_id(p_index)
    and match_row.matchday_id = p_matchday_id;
$helper$;

-- ---------------------------------------------------------------------------
-- Definitions
-- ---------------------------------------------------------------------------

select pg_temp.xt_assert(
  (
    select count(*)
    from public.badge_definitions as definition
    where definition.code in (
      'blazing',
      'inferno',
      'deadeye',
      'exact_master',
      'exact_legend',
      'matchday_monster'
    )
  ) = 6,
  'six new badge definitions exist'
);

select pg_temp.xt_assert(
  (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'blazing'
  )
  and (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'inferno'
  )
  and (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'deadeye'
  )
  and (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'matchday_monster'
  )
  and not (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'exact_master'
  )
  and not (
    select definition.repeatable
    from public.badge_definitions as definition
    where definition.code = 'exact_legend'
  )
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'blazing'
  ) = 'performance'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'deadeye'
  ) = 'performance'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'exact_master'
  ) = 'performance'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'matchday_monster'
  ) = 'matchday'
  and (
    select definition.image_path
    from public.badge_definitions as definition
    where definition.code = 'exact_master'
  ) = '/badges/exact-master.png'
  and (
    select definition.image_path
    from public.badge_definitions as definition
    where definition.code = 'matchday_monster'
  ) = '/badges/matchday-monster.png',
  'new badge metadata matches product flags'
);

-- ---------------------------------------------------------------------------
-- People, teams, matchdays
-- ---------------------------------------------------------------------------

select pg_temp.xt_add_player(1);
select pg_temp.xt_add_player(2);
select pg_temp.xt_add_player(3);
select pg_temp.xt_add_player(4);
select pg_temp.xt_add_player(5);
select pg_temp.xt_add_player(6);
select pg_temp.xt_add_player(7);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.xt_user_id(1);

insert into public.teams (name, short_name)
values
  ('ZZ Badge Ext Home', 'ZEH'),
  ('ZZ Badge Ext Away', 'ZEA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Ext Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Ext Away'
  ),
  true
);

select set_config('test.md_pts', pg_temp.xt_add_matchday('league_phase')::text, true);
select pg_temp.xt_fill_matchday(
  'pts',
  current_setting('test.md_pts')::bigint,
  9,
  now() + interval '60 days'
);
select pg_temp.xt_predict(2, 'pts', 2, 1);

select set_config('test.md_de', pg_temp.xt_add_matchday('playoff')::text, true);
select pg_temp.xt_fill_matchday(
  'de',
  current_setting('test.md_de')::bigint,
  6,
  now() + interval '61 days'
);
select pg_temp.xt_predict(3, 'de', 2, 1);

select set_config('test.md_ex', pg_temp.xt_add_matchday('league_phase')::text, true);
select pg_temp.xt_fill_matchday(
  'ex',
  current_setting('test.md_ex')::bigint,
  30,
  now() + interval '62 days'
);
select pg_temp.xt_predict(4, 'ex', 2, 1);

select set_config('test.md_mm29', pg_temp.xt_add_matchday('playoff')::text, true);
select pg_temp.xt_fill_matchday(
  'mm29',
  current_setting('test.md_mm29')::bigint,
  7,
  now() + interval '70 days'
);
select pg_temp.xt_predict(5, 'mm29', 2, 1);
select pg_temp.xt_predict(6, 'mm29', 0, 0);

select set_config('test.md_mm30', pg_temp.xt_add_matchday('playoff')::text, true);
select pg_temp.xt_fill_matchday(
  'mm30',
  current_setting('test.md_mm30')::bigint,
  6,
  now() + interval '71 days'
);
select pg_temp.xt_predict(5, 'mm30', 2, 1);
select pg_temp.xt_predict(6, 'mm30', 0, 0);

select set_config('test.md_mm_r2', pg_temp.xt_add_matchday('round_of_16')::text, true);
select pg_temp.xt_fill_matchday(
  'mmr2',
  current_setting('test.md_mm_r2')::bigint,
  8,
  now() + interval '72 days'
);
select pg_temp.xt_predict(5, 'mmr2', 2, 1);
update public.predictions
set predicted_home_score = 0, predicted_away_score = 0
where user_id = pg_temp.xt_user_id(5)
  and match_id = pg_temp.xt_match('mmr2', 8);
select pg_temp.xt_predict(6, 'mmr2', 2, 1);

select set_config('test.md_mm40', pg_temp.xt_add_matchday('quarter_final')::text, true);
select pg_temp.xt_fill_matchday(
  'mm40',
  current_setting('test.md_mm40')::bigint,
  8,
  now() + interval '73 days'
);
select pg_temp.xt_predict(5, 'mm40', 2, 1);
select pg_temp.xt_predict(6, 'mm40', 0, 0);

select set_config('test.md_corr_pts', pg_temp.xt_add_matchday('semi_final')::text, true);
select pg_temp.xt_fill_matchday(
  'corrpts',
  current_setting('test.md_corr_pts')::bigint,
  10,
  now() + interval '74 days'
);
select pg_temp.xt_predict(2, 'corrpts', 2, 1);

select set_config('test.md_corr_rank', pg_temp.xt_add_matchday('playoff')::text, true);
select pg_temp.xt_fill_matchday(
  'corrrank',
  current_setting('test.md_corr_rank')::bigint,
  6,
  now() + interval '75 days'
);
select pg_temp.xt_predict(5, 'corrrank', 2, 1);
select pg_temp.xt_predict(6, 'corrrank', 1, 0);

select set_config('test.md_incomplete', pg_temp.xt_add_matchday('playoff')::text, true);
select pg_temp.xt_fill_matchday(
  'inc',
  current_setting('test.md_incomplete')::bigint,
  8,
  now() + interval '76 days'
);
select pg_temp.xt_predict(5, 'inc', 2, 1);

-- ---------------------------------------------------------------------------
-- Score as admin
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.xt_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 1-4. Blazing: 29 no, 30 yes, 39 yes without Inferno, rerun no duplicate
select pg_temp.xt_score_range('pts', 1, 5, 2, 1);
select pg_temp.xt_score_range('pts', 6, 7, 2, 0);
select pg_temp.xt_score_range('pts', 8, 9, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_pts')::bigint) = 29
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 0
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 0
  and pg_temp.xt_award_count(2, 'on_fire', current_setting('test.md_pts')::bigint) = 1,
  '29 points -> On Fire, no Blazing, no Inferno'
);

select pg_temp.xt_score_range('pts', 1, 6, 2, 1);
select pg_temp.xt_score_range('pts', 7, 9, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_pts')::bigint) = 30
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 0
  and pg_temp.xt_award_count(2, 'on_fire', current_setting('test.md_pts')::bigint) = 1,
  '30 points -> Blazing, no Inferno'
);

select pg_temp.xt_score_range('pts', 1, 7, 2, 1);
select pg_temp.xt_score_range('pts', 8, 9, 2, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_pts')::bigint) = 39
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 0,
  '39 points -> Blazing, no Inferno'
);

reset role;
select public.recompute_matchday_badges(current_setting('test.md_pts')::bigint);
select public.recompute_matchday_badges(current_setting('test.md_pts')::bigint);
select set_config('request.jwt.claim.sub', pg_temp.xt_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select pg_temp.xt_assert(
  pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1,
  'Blazing rerun -> no duplicate'
);

-- 5-7. Inferno: 40 and 45 award both, rerun no duplicates
select pg_temp.xt_score_range('pts', 1, 8, 2, 1);
select pg_temp.xt_score('pts', 9, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_pts')::bigint) = 40
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'on_fire', current_setting('test.md_pts')::bigint) = 1,
  '40 points -> Blazing + Inferno'
);

select pg_temp.xt_score_range('pts', 1, 9, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_pts')::bigint) = 45
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 1,
  '45 points -> Blazing + Inferno'
);

reset role;
select public.recompute_matchday_badges(current_setting('test.md_pts')::bigint);
select set_config('request.jwt.claim.sub', pg_temp.xt_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select pg_temp.xt_assert(
  pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'on_fire', current_setting('test.md_pts')::bigint) = 1,
  'Inferno rerun -> no duplicates'
);

-- 8-10. Deadeye
select pg_temp.xt_score_range('de', 1, 4, 2, 1);
select pg_temp.xt_score_range('de', 5, 6, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(3, 'deadeye', current_setting('test.md_de')::bigint) = 0
  and pg_temp.xt_award_count(3, 'sharp_shooter', current_setting('test.md_de')::bigint) = 1,
  '4 exact -> Sharp Shooter, no Deadeye'
);

select pg_temp.xt_score_range('de', 1, 5, 2, 1);
select pg_temp.xt_score('de', 6, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(3, 'deadeye', current_setting('test.md_de')::bigint) = 1
  and pg_temp.xt_award_count(3, 'sharp_shooter', current_setting('test.md_de')::bigint) = 1,
  '5 exact -> Sharp Shooter + Deadeye'
);

select pg_temp.xt_score_range('de', 1, 6, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(3, 'deadeye', current_setting('test.md_de')::bigint) = 1
  and pg_temp.xt_award_count(3, 'deadeye') = 1,
  '6 exact -> Deadeye only once for the matchday'
);

-- 11-16. Exact Master / Exact Legend
select pg_temp.xt_score_range('ex', 1, 19, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_machine') = 1
  and pg_temp.xt_award_count(4, 'exact_master') = 0
  and pg_temp.xt_award_count(4, 'exact_legend') = 0,
  '19 cumulative exact -> Exact Machine, no Master, no Legend'
);

select pg_temp.xt_score('ex', 20, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_master') = 1
  and pg_temp.xt_award_count(4, 'exact_legend') = 0,
  '20 cumulative exact -> Exact Master'
);

select pg_temp.xt_score('ex', 21, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_master') = 1,
  '21+ cumulative exact does not re-award Exact Master'
);

select pg_temp.xt_score_range('ex', 22, 29, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_master') = 1
  and pg_temp.xt_award_count(4, 'exact_legend') = 0,
  '29 cumulative exact -> no Exact Legend'
);

select pg_temp.xt_score('ex', 30, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_machine') = 1
  and pg_temp.xt_award_count(4, 'exact_master') = 1
  and pg_temp.xt_award_count(4, 'exact_legend') = 1,
  '30 cumulative exact -> Exact Master + Exact Legend'
);

reset role;
select public.recompute_cumulative_badges();
select public.recompute_cumulative_badges();
select set_config('request.jwt.claim.sub', pg_temp.xt_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_machine') = 1
  and pg_temp.xt_award_count(4, 'exact_master') = 1
  and pg_temp.xt_award_count(4, 'exact_legend') = 1,
  'Exact Legend rerun -> no duplicate'
);

-- 17. rank 1 + 29 -> no Matchday Monster
select pg_temp.xt_score_range('mm29', 1, 5, 2, 1);
select pg_temp.xt_score_range('mm29', 6, 7, 2, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(5, current_setting('test.md_mm29')::bigint) = 29
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_mm29')::bigint) = 1
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_mm29')::bigint) = 0
  and pg_temp.xt_award_count(5, 'blazing', current_setting('test.md_mm29')::bigint) = 0,
  'rank 1 + 29 points -> Top of the Matchday, no Matchday Monster'
);

-- Incomplete matchday must not award Monster / Blazing
select pg_temp.xt_score_range('inc', 1, 6, 2, 1);

reset role;
select pg_temp.xt_assert(
  public.badge_matchday_is_complete(current_setting('test.md_incomplete')::bigint) = false
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_incomplete')::bigint) = 0
  and pg_temp.xt_award_count(5, 'blazing', current_setting('test.md_incomplete')::bigint) = 0
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_incomplete')::bigint) = 0,
  'incomplete matchday -> no matchday / ranking badges'
);
select set_config('request.jwt.claim.sub', pg_temp.xt_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 18. rank 1 + 30 -> Matchday Monster
select pg_temp.xt_score_range('mm30', 1, 6, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_points(5, current_setting('test.md_mm30')::bigint) = 30
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_mm30')::bigint) = 1
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_mm30')::bigint) = 1
  and pg_temp.xt_award_count(5, 'blazing', current_setting('test.md_mm30')::bigint) = 1
  and pg_temp.xt_award_count(6, 'matchday_monster', current_setting('test.md_mm30')::bigint) = 0,
  'rank 1 + 30 points -> Matchday Monster'
);

-- 19. rank 2 + 35 -> no Matchday Monster
select pg_temp.xt_score_range('mmr2', 1, 8, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_points(5, current_setting('test.md_mm_r2')::bigint) = 35
  and pg_temp.xt_points(6, current_setting('test.md_mm_r2')::bigint) = 40
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_mm_r2')::bigint) = 0
  and pg_temp.xt_award_count(5, 'second_of_the_matchday', current_setting('test.md_mm_r2')::bigint) = 1
  and pg_temp.xt_award_count(6, 'matchday_monster', current_setting('test.md_mm_r2')::bigint) = 1
  and pg_temp.xt_award_count(6, 'top_of_the_matchday', current_setting('test.md_mm_r2')::bigint) = 1,
  'rank 2 + 35 points -> no Matchday Monster'
);

-- 20. rank 1 + 40 stack
select pg_temp.xt_score_range('mm40', 1, 8, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_points(5, current_setting('test.md_mm40')::bigint) = 40
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_mm40')::bigint) = 1
  and pg_temp.xt_award_count(5, 'on_fire', current_setting('test.md_mm40')::bigint) = 1
  and pg_temp.xt_award_count(5, 'blazing', current_setting('test.md_mm40')::bigint) = 1
  and pg_temp.xt_award_count(5, 'inferno', current_setting('test.md_mm40')::bigint) = 1
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_mm40')::bigint) = 1,
  'rank 1 + 40 points -> Top + On Fire + Blazing + Inferno + Matchday Monster'
);

-- 21. points correction drops Inferno, keeps Blazing
select pg_temp.xt_score_range('corrpts', 1, 8, 2, 1);
select pg_temp.xt_score_range('corrpts', 9, 10, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_corr_pts')::bigint) = 40
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_corr_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_corr_pts')::bigint) = 1,
  'correction fixture starts at 40 -> Inferno'
);

select pg_temp.xt_score_range('corrpts', 1, 6, 2, 1);
select pg_temp.xt_score_range('corrpts', 7, 10, 2, 0);

select pg_temp.xt_assert(
  pg_temp.xt_points(2, current_setting('test.md_corr_pts')::bigint) = 38
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_corr_pts')::bigint) = 0
  and pg_temp.xt_award_count(2, 'blazing', current_setting('test.md_corr_pts')::bigint) = 1
  and pg_temp.xt_award_count(2, 'on_fire', current_setting('test.md_corr_pts')::bigint) = 1,
  'correction 40 -> 38 revokes Inferno and keeps Blazing'
);

-- 22. exact count correction 6 -> 4
select pg_temp.xt_score('de', 5, 0, 0);
select pg_temp.xt_score('de', 6, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(3, 'deadeye', current_setting('test.md_de')::bigint) = 0
  and pg_temp.xt_award_count(3, 'sharp_shooter', current_setting('test.md_de')::bigint) = 1,
  'exact count 6 -> 4 revokes Deadeye and keeps Sharp Shooter'
);

-- 23. ranking correction swaps first place
select pg_temp.xt_score_range('corrrank', 1, 6, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_corr_rank')::bigint) = 1
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_corr_rank')::bigint) = 1
  and pg_temp.xt_award_count(6, 'matchday_monster', current_setting('test.md_corr_rank')::bigint) = 0,
  'ranking fixture: player 5 is first with Matchday Monster'
);

select pg_temp.xt_score_range('corrrank', 1, 6, 1, 0);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_corr_rank')::bigint) = 0
  and pg_temp.xt_award_count(5, 'top_of_the_matchday', current_setting('test.md_corr_rank')::bigint) = 0
  and pg_temp.xt_award_count(6, 'matchday_monster', current_setting('test.md_corr_rank')::bigint) = 1
  and pg_temp.xt_award_count(6, 'top_of_the_matchday', current_setting('test.md_corr_rank')::bigint) = 1,
  'ranking correction moves Matchday Monster to the new rank 1'
);

-- Season exact correction 30 -> 19
select pg_temp.xt_score_range('ex', 20, 30, 0, 0);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_master') = 0
  and pg_temp.xt_award_count(4, 'exact_legend') = 0
  and pg_temp.xt_award_count(4, 'exact_machine') = 1,
  'season exact 30 -> 19 revokes Master and Legend and keeps Exact Machine'
);

select pg_temp.xt_score_range('ex', 20, 30, 2, 1);

select pg_temp.xt_assert(
  pg_temp.xt_award_count(4, 'exact_master') = 1
  and pg_temp.xt_award_count(4, 'exact_legend') = 1,
  'restoring the exacts re-awards Exact Master and Exact Legend'
);

-- 24-25. deterministic / idempotent recovery
reset role;

select set_config(
  'test.award_before',
  (
    select count(*)::text
    from public.badge_awards as award
    where award.user_id in (
      pg_temp.xt_user_id(2),
      pg_temp.xt_user_id(3),
      pg_temp.xt_user_id(4),
      pg_temp.xt_user_id(5),
      pg_temp.xt_user_id(6)
    )
  ),
  true
);

select public.recompute_all_badges();
select public.recompute_all_badges();

select pg_temp.xt_assert(
  (
    select count(*)
    from public.badge_awards as award
    where award.user_id in (
      pg_temp.xt_user_id(2),
      pg_temp.xt_user_id(3),
      pg_temp.xt_user_id(4),
      pg_temp.xt_user_id(5),
      pg_temp.xt_user_id(6)
    )
  ) = current_setting('test.award_before')::bigint
  and pg_temp.xt_award_count(2, 'inferno', current_setting('test.md_pts')::bigint) = 1
  and pg_temp.xt_award_count(3, 'deadeye', current_setting('test.md_de')::bigint) = 0
  and pg_temp.xt_award_count(4, 'exact_legend') = 1
  and pg_temp.xt_award_count(5, 'matchday_monster', current_setting('test.md_mm40')::bigint) = 1
  and pg_temp.xt_award_count(6, 'matchday_monster', current_setting('test.md_corr_rank')::bigint) = 1,
  'repeated recovery is deterministic and idempotent'
);

-- 26-28. Security
select set_config(
  'request.jwt.claim.sub',
  pg_temp.xt_user_id(7)::text,
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
      award_scope,
      matchday_id
    )
    values (
      pg_temp.xt_user_id(7),
      'blazing',
      'matchday',
      current_setting('test.md_pts')::bigint
    );
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: authenticated inserted an award';
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
    where user_id = pg_temp.xt_user_id(2);
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: authenticated updated an award';
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
    where user_id = pg_temp.xt_user_id(2);
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: authenticated deleted an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;
set local role anon;

do $test$
begin
  begin
    insert into public.badge_awards (
      user_id,
      badge_code,
      award_scope
    )
    values (
      pg_temp.xt_user_id(7),
      'exact_master',
      'season'
    );
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: anon inserted an award';
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
      current_setting('test.md_pts')::bigint
    );
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: anon executed recompute_matchday_badges';
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
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: anon executed recompute_cumulative_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_all_badges();
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: anon executed recompute_all_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

select pg_temp.xt_assert(
  has_table_privilege('service_role', 'public.badge_awards', 'INSERT')
  and has_table_privilege('service_role', 'public.badge_awards', 'UPDATE')
  and has_function_privilege(
    'service_role',
    'public.recompute_all_badges()',
    'EXECUTE'
  )
  and not has_table_privilege('anon', 'public.badge_awards', 'INSERT')
  and not has_table_privilege('authenticated', 'public.badge_awards', 'INSERT'),
  'service/admin grants remain; anon and authenticated still cannot write awards'
);

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzext%'
  ) then
    raise exception 'BADGES EXTENDED TIERS TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'definitions_seeded',
  'blazing_29_no_award',
  'blazing_30_award',
  'blazing_39_no_inferno',
  'blazing_rerun_no_duplicate',
  'inferno_40_with_blazing',
  'inferno_45_with_blazing',
  'inferno_rerun_no_duplicate',
  'deadeye_4_no_award',
  'deadeye_5_with_sharp_shooter',
  'deadeye_6_once_per_matchday',
  'exact_master_19_no_award',
  'exact_master_20_award',
  'exact_master_21_no_duplicate',
  'exact_legend_29_no_award',
  'exact_legend_30_with_master',
  'exact_legend_rerun_no_duplicate',
  'matchday_monster_rank1_29_no',
  'incomplete_matchday_no_awards',
  'matchday_monster_rank1_30_yes',
  'matchday_monster_rank2_35_no',
  'matchday_monster_rank1_40_stack',
  'correction_points_threshold',
  'correction_exact_count',
  'correction_matchday_ranking',
  'correction_season_exact',
  'recovery_idempotent',
  'authenticated_cannot_write_awards',
  'anon_no_extra_access',
  'service_grants_unchanged',
  'all_fixture_changes_rolled_back'
]) as passed_test;
