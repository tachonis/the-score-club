-- Transactional feedback inbox verification against the hosted schema.
-- Every fixture mutation is rolled back at the end.

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
  'test.admin',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.status = 'active'
      and profile.role = 'admin'
    order by profile.created_at, profile.id
    limit 1
  ),
  true
);

do $test$
begin
  if coalesce(current_setting('test.user_a', true), '') = ''
    or coalesce(current_setting('test.user_b', true), '') = ''
    or coalesce(current_setting('test.admin', true), '') = ''
  then
    raise exception 'This fixture needs two active players and one active admin';
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

do $test$
declare
  v_id uuid;
begin
  v_id := public.submit_feedback(
    'bug',
    'Fixture contact message for player A'
  );

  perform set_config('test.message_id', v_id::text, true);
end;
$test$;

do $test$
begin
  begin
    insert into public.feedback_messages (
      user_id,
      category,
      message
    )
    values (
      current_setting('test.user_b')::uuid,
      'other',
      'Spoofed message'
    );
    raise exception 'Direct insert should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.set_feedback_status(
      current_setting('test.message_id')::uuid,
      'resolved'
    );
    raise exception 'Player status update should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.get_feedback_messages();
    raise exception 'Player inbox read should have been rejected';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

do $test$
begin
  if not exists (
    select 1
    from public.feedback_messages as feedback
    where feedback.id = current_setting('test.message_id')::uuid
      and feedback.user_id = current_setting('test.user_a')::uuid
      and feedback.category = 'bug'
      and feedback.status = 'new'
  ) then
    raise exception 'Own feedback was not stored';
  end if;
end;
$test$;

select set_config(
  'request.jwt.claim.sub',
  current_setting('test.admin'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

set local role authenticated;

do $test$
declare
  v_count integer;
  v_status text;
begin
  select public.count_new_feedback_messages() into v_count;

  if v_count < 1 then
    raise exception 'Admin new-message count was not increased';
  end if;

  if not exists (
    select 1
    from public.get_feedback_messages() as inbox
    where inbox.id = current_setting('test.message_id')::uuid
      and inbox.user_id = current_setting('test.user_a')::uuid
      and inbox.category = 'bug'
  ) then
    raise exception 'Admin inbox did not return the submitted message';
  end if;

  perform public.set_feedback_status(
    current_setting('test.message_id')::uuid,
    'read'
  );
  perform public.set_feedback_status(
    current_setting('test.message_id')::uuid,
    'resolved'
  );
end;
$test$;

reset role;

do $test$
declare
  v_status text;
begin
  select feedback.status
  into v_status
  from public.feedback_messages as feedback
  where feedback.id = current_setting('test.message_id')::uuid;

  if v_status <> 'resolved' then
    raise exception 'Mark as resolved did not persist';
  end if;
end;
$test$;

rollback;

select unnest(array[
  'player_submit_stored',
  'direct_insert_rejected',
  'player_cannot_set_status',
  'player_cannot_read_inbox',
  'admin_can_read_and_update',
  'all_fixture_changes_rolled_back'
]) as passed_test;
