-- Transactional favorite-team grant checks.
-- Every fixture mutation is rolled back at the end.
-- Apply supabase/migrations/20260924140000_profile_favorite_team.sql first.

begin;

select set_config(
  'test.user_a',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.status = 'active'
      and profile.role = 'player'
    order by profile.created_at, profile.id
    limit 1
  ),
  true
);
select set_config(
  'test.user_b',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.status = 'active'
      and profile.role = 'player'
      and profile.id <> current_setting('test.user_a')::uuid
    order by profile.created_at, profile.id
    limit 1
  ),
  true
);
select set_config(
  'test.team_id',
  (
    select team.id::text
    from public.teams as team
    order by team.name, team.id
    limit 1
  ),
  true
);
select set_config(
  'test.other_team_id',
  (
    select team.id::text
    from public.teams as team
    where team.id <> current_setting('test.team_id')::bigint
    order by team.name, team.id
    limit 1
  ),
  true
);

do $test$
begin
  if coalesce(current_setting('test.user_a', true), '') = ''
    or coalesce(current_setting('test.user_b', true), '') = ''
    or coalesce(current_setting('test.team_id', true), '') = ''
    or coalesce(current_setting('test.other_team_id', true), '') = ''
  then
    raise exception 'This fixture needs two active players and two teams';
  end if;
end;
$test$;

select set_config(
  'request.jwt.claim.sub',
  current_setting('test.user_a'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 1, 3. Own favorite accepts a real team id.
update public.profiles
set favorite_team_id = current_setting('test.team_id')::bigint
where id = current_setting('test.user_a')::uuid;

do $test$
begin
  if (
    select profile.favorite_team_id
    from public.profiles as profile
    where profile.id = current_setting('test.user_a')::uuid
  ) is distinct from current_setting('test.team_id')::bigint then
    raise exception 'Own favorite_team_id update did not persist';
  end if;
end;
$test$;

-- 8. Existing username update permission remains.
update public.profiles
set username = username
where id = current_setting('test.user_a')::uuid;

-- 2. Another player's row is not updated.
do $test$
declare
  v_count integer;
begin
  update public.profiles
  set favorite_team_id = current_setting('test.other_team_id')::bigint
  where id = current_setting('test.user_b')::uuid;

  get diagnostics v_count = row_count;

  if v_count <> 0 then
    raise exception 'Authenticated user updated another profile';
  end if;
end;
$test$;

-- 4. Invalid team id is rejected by the foreign key.
do $test$
begin
  begin
    update public.profiles
    set favorite_team_id = 9223372036854775806
    where id = current_setting('test.user_a')::uuid;
    raise exception 'Invalid team id should have been rejected';
  exception
    when foreign_key_violation then
      null;
  end;
end;
$test$;

-- 5. NULL clears the favorite.
update public.profiles
set favorite_team_id = null
where id = current_setting('test.user_a')::uuid;

do $test$
begin
  if (
    select profile.favorite_team_id
    from public.profiles as profile
    where profile.id = current_setting('test.user_a')::uuid
  ) is not null then
    raise exception 'Setting favorite_team_id to NULL failed';
  end if;
end;
$test$;

-- 6. Browser role cannot change role.
do $test$
begin
  begin
    update public.profiles
    set role = 'admin'
    where id = current_setting('test.user_a')::uuid;
    raise exception 'role update should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

-- 7. Browser role cannot change status.
do $test$
begin
  begin
    update public.profiles
    set status = 'disabled'
    where id = current_setting('test.user_a')::uuid;
    raise exception 'status update should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

-- 9. Anonymous role cannot modify profiles.
set local role anon;

do $test$
begin
  begin
    update public.profiles
    set favorite_team_id = null
    where id = current_setting('test.user_a')::uuid;
    raise exception 'anon update should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

-- 10. Service role can still write the column.
set local role service_role;

update public.profiles
set favorite_team_id = current_setting('test.team_id')::bigint
where id = current_setting('test.user_a')::uuid;

do $test$
begin
  if (
    select profile.favorite_team_id
    from public.profiles as profile
    where profile.id = current_setting('test.user_a')::uuid
  ) is distinct from current_setting('test.team_id')::bigint then
    raise exception 'service_role could not set favorite_team_id';
  end if;
end;
$test$;

reset role;

-- Leaderboard contract exposes the new column without using it as a rank key.
select favorite_team_id
from public.get_leaderboard()
where user_id = current_setting('test.user_a')::uuid;

rollback;
