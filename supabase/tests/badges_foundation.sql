-- Transactional Badges foundation verification.
-- Every fixture mutation is rolled back at the end. Run it as the project
-- owner after the badges_foundation migration is applied locally. Do not run
-- this against hosted Supabase from this phase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.badge_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'BADGES FOUNDATION TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.badge_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9910 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.badge_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.badge_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'badges-foundation-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzbdg' || lpad(p_index::text, 3, '0'))
  );

  return v_user_id;
end;
$helper$;

create function pg_temp.badge_scope(p_code text)
returns text
language sql
stable
as $helper$
  select definition.award_scope
  from public.badge_definitions as definition
  where definition.code = p_code;
$helper$;

-- Two distinct matchday ids, for FK-only uniqueness tests. Prefer rows that
-- already exist. Insert only the deficit, with league_phase numbers above the
-- current max, so unique (stage, matchday_number) cannot collide.
create function pg_temp.badge_bind_matchday_pair()
returns void
language plpgsql
as $helper$
declare
  v_ids bigint[] := '{}';
  v_next_number integer;
  v_new_id bigint;
begin
  select coalesce(array_agg(matchday.id order by matchday.id), '{}')
  into v_ids
  from (
    select matchday.id
    from public.matchdays as matchday
    order by matchday.id
    limit 2
  ) as matchday;

  while coalesce(array_length(v_ids, 1), 0) < 2 loop
    select coalesce(max(matchday.matchday_number), 0) + 1
    into v_next_number
    from public.matchdays as matchday
    where matchday.stage = 'league_phase';

    insert into public.matchdays (stage, matchday_number, name)
    values (
      'league_phase',
      v_next_number,
      'zz-badges-foundation-' || (coalesce(array_length(v_ids, 1), 0) + 1)::text
    )
    returning id into v_new_id;

    v_ids := v_ids || v_new_id;
  end loop;

  perform set_config('test.md_a', v_ids[1]::text, true);
  perform set_config('test.md_b', v_ids[2]::text, true);
end;
$helper$;

-- ---------------------------------------------------------------------------
-- 1-5, 17. Seeded definitions, no seeded awards
-- ---------------------------------------------------------------------------

select pg_temp.badge_assert(
  (select count(*) from public.badge_definitions) = 17,
  'exactly 17 definitions exist'
);

select pg_temp.badge_assert(
  (
    select array_agg(definition.code order by definition.code)
    from public.badge_definitions as definition
  ) = array[
    'exact_machine',
    'final_boss',
    'leader',
    'league_phase_champion',
    'league_phase_runner_up',
    'on_fire',
    'perfect_matchday',
    'players_cup_champion',
    'players_cup_finalist',
    'players_cup_semifinalist',
    'season_champion',
    'season_runner_up',
    'season_top_5',
    'second_of_the_matchday',
    'sharp_shooter',
    'third_of_the_matchday',
    'top_of_the_matchday'
  ]::text[],
  'all expected badge codes exist'
);

select pg_temp.badge_assert(
  (
    select array_agg(definition.code order by definition.code)
    from public.badge_definitions as definition
    where definition.repeatable
  ) = array[
    'on_fire',
    'perfect_matchday',
    'second_of_the_matchday',
    'sharp_shooter',
    'third_of_the_matchday',
    'top_of_the_matchday'
  ]::text[],
  'repeatable flags match product rules'
);

select pg_temp.badge_assert(
  (
    select bool_and(definition.award_scope = 'matchday')
    from public.badge_definitions as definition
    where definition.repeatable
  )
  and (
    select bool_and(definition.award_scope = 'season')
    from public.badge_definitions as definition
    where not definition.repeatable
  ),
  'generated award_scope matches repeatable'
);

select pg_temp.badge_assert(
  not exists (
    select 1
    from public.badge_definitions as definition
    where definition.category not in (
      'season',
      'league_phase',
      'players_cup',
      'performance',
      'matchday'
    )
  )
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'season_champion'
  ) = 'season'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'league_phase_champion'
  ) = 'league_phase'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'players_cup_champion'
  ) = 'players_cup'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'exact_machine'
  ) = 'performance'
  and (
    select definition.category
    from public.badge_definitions as definition
    where definition.code = 'top_of_the_matchday'
  ) = 'matchday',
  'categories match expected values'
);

select pg_temp.badge_assert(
  not exists (
    select 1
    from public.badge_definitions as definition
    where definition.image_path is null
      or definition.image_path !~ '^/badges/[a-z0-9-]+\.png$'
  )
  and (
    select definition.image_path
    from public.badge_definitions as definition
    where definition.code = 'exact_machine'
  ) = '/badges/exact-machine.png'
  and (
    select definition.image_path
    from public.badge_definitions as definition
    where definition.code = 'players_cup_semifinalist'
  ) = '/badges/players-cup-semifinalist.png',
  'image paths are non-null and the expected public PNG paths'
);

select pg_temp.badge_assert(
  (select count(*) from public.badge_awards) = 0,
  'no awards are seeded by the foundation migration'
);

-- ---------------------------------------------------------------------------
-- Fixture users, matchdays and a Cup row (rolled back)
-- ---------------------------------------------------------------------------

select pg_temp.badge_add_player(1);
select pg_temp.badge_add_player(2);
select pg_temp.badge_bind_matchday_pair();

insert into public.cup_competitions (
  slug,
  season_label,
  participant_count,
  status
)
values (
  'zz-badges-foundation-cup',
  'Champions League 2026/27',
  8,
  'active'
);

select set_config(
  'test.cup_id',
  (
    select competition.id::text
    from public.cup_competitions as competition
    where competition.slug = 'zz-badges-foundation-cup'
  ),
  true
);

select pg_temp.badge_assert(
  current_setting('test.md_a') <> ''
  and current_setting('test.md_b') <> ''
  and current_setting('test.md_a') is distinct from current_setting('test.md_b')
  and current_setting('test.cup_id') <> '',
  'fixture matchdays and cup exist'
);

-- ---------------------------------------------------------------------------
-- 11-16. Owner-path integrity (future award engine, not the browser)
-- ---------------------------------------------------------------------------

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label
)
values (
  pg_temp.badge_user_id(1),
  'exact_machine',
  pg_temp.badge_scope('exact_machine'),
  'Champions League 2026/27'
);

do $test$
begin
  begin
    insert into public.badge_awards (
      user_id,
      badge_code,
      award_scope,
      season_label
    )
    values (
      pg_temp.badge_user_id(1),
      'exact_machine',
      pg_temp.badge_scope('exact_machine'),
      'Champions League 2026/27'
    );
    raise exception 'BADGES FOUNDATION TEST FAILED: duplicate unique-season award was accepted';
  exception
    when unique_violation then
      null;
  end;
end;
$test$;

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label
)
values (
  pg_temp.badge_user_id(1),
  'exact_machine',
  pg_temp.badge_scope('exact_machine'),
  'Champions League 2027/28'
);

select pg_temp.badge_assert(
  (
    select count(*)
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(1)
      and award.badge_code = 'exact_machine'
  ) = 2,
  'season_label separates unique badge awards across seasons'
);

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  matchday_id
)
values (
  pg_temp.badge_user_id(1),
  'sharp_shooter',
  pg_temp.badge_scope('sharp_shooter'),
  current_setting('test.md_a')::bigint
);

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
      pg_temp.badge_user_id(1),
      'sharp_shooter',
      pg_temp.badge_scope('sharp_shooter'),
      current_setting('test.md_a')::bigint
    );
    raise exception 'BADGES FOUNDATION TEST FAILED: duplicate repeatable same-matchday award was accepted';
  exception
    when unique_violation then
      null;
  end;
end;
$test$;

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  matchday_id
)
values (
  pg_temp.badge_user_id(1),
  'sharp_shooter',
  pg_temp.badge_scope('sharp_shooter'),
  current_setting('test.md_b')::bigint
);

select pg_temp.badge_assert(
  (
    select count(*)
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(1)
      and award.badge_code = 'sharp_shooter'
  ) = 2,
  'same repeatable badge can exist for different matchday_id'
);

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  cup_id
)
values (
  pg_temp.badge_user_id(1),
  'players_cup_champion',
  pg_temp.badge_scope('players_cup_champion'),
  current_setting('test.cup_id')::bigint
);

select pg_temp.badge_assert(
  (
    select award.cup_id
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(1)
      and award.badge_code = 'players_cup_champion'
      and award.season_label = 'Champions League 2026/27'
  ) = current_setting('test.cup_id')::bigint
  and (
    select award.award_scope
    from public.badge_awards as award
    where award.badge_code = 'players_cup_champion'
      and award.user_id = pg_temp.badge_user_id(1)
  ) = 'season',
  'cup_id can be attached to unique-per-season Cup badges'
);

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope
)
values (
  pg_temp.badge_user_id(2),
  'leader',
  pg_temp.badge_scope('leader')
);

select pg_temp.badge_assert(
  (
    select award.context
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(2)
      and award.badge_code = 'leader'
  ) = '{}'::jsonb
  and (
    select award.season_label
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(2)
      and award.badge_code = 'leader'
  ) = 'Champions League 2026/27',
  'context defaults to {} and season_label defaults to Champions League 2026/27'
);

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
      pg_temp.badge_user_id(1),
      'exact_machine',
      'matchday',
      current_setting('test.md_a')::bigint
    );
    raise exception 'BADGES FOUNDATION TEST FAILED: unique badge accepted a matchday award_scope';
  exception
    when foreign_key_violation then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    insert into public.badge_awards (
      user_id,
      badge_code,
      award_scope
    )
    values (
      pg_temp.badge_user_id(1),
      'sharp_shooter',
      'matchday'
    );
    raise exception 'BADGES FOUNDATION TEST FAILED: matchday award without matchday_id was accepted';
  exception
    when check_violation then
      null;
  end;
end;
$test$;

-- ---------------------------------------------------------------------------
-- 6-10. Authenticated read, no self-award
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claim.sub',
  pg_temp.badge_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select pg_temp.badge_assert(
  (select count(*) from public.badge_definitions) = 17,
  'authenticated can SELECT definitions'
);

select pg_temp.badge_assert(
  (
    select count(*)
    from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(2)
      and award.badge_code = 'leader'
  ) = 1
  and (select count(*) from public.badge_awards) >= 1,
  'authenticated can SELECT awards, including another player'
);

do $test$
begin
  begin
    insert into public.badge_awards (
      user_id,
      badge_code,
      award_scope
    )
    values (
      pg_temp.badge_user_id(1),
      'final_boss',
      'season'
    );
    raise exception 'BADGES FOUNDATION TEST FAILED: authenticated inserted an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    update public.badge_awards as award
    set context = '{"rank": 1}'::jsonb
    where award.user_id = pg_temp.badge_user_id(1);
    raise exception 'BADGES FOUNDATION TEST FAILED: authenticated updated an award';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    delete from public.badge_awards as award
    where award.user_id = pg_temp.badge_user_id(1);
    raise exception 'BADGES FOUNDATION TEST FAILED: authenticated deleted an award';
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
    where profile.username like 'zzbdg%'
  ) then
    raise exception 'BADGES FOUNDATION TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'exactly_17_definitions',
  'all_expected_badge_codes',
  'repeatable_flags',
  'categories',
  'image_paths',
  'no_awards_seeded',
  'authenticated_select_definitions',
  'authenticated_select_awards',
  'authenticated_cannot_insert_awards',
  'authenticated_cannot_update_awards',
  'authenticated_cannot_delete_awards',
  'duplicate_unique_season_blocked',
  'duplicate_repeatable_matchday_blocked',
  'repeatable_across_matchdays_allowed',
  'season_label_separates_unique_awards',
  'cup_id_on_cup_badges',
  'context_defaults_to_empty_object',
  'award_scope_must_match_definition',
  'all_fixture_changes_rolled_back'
]) as passed_test;
