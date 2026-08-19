-- Transactional Push Notifications v1 verification against the hosted schema.
-- Every fixture mutation is rolled back at the end.

begin;

select set_config(
  'test.user_a',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.status = 'active'
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
      and profile.id <> current_setting('test.user_a')::uuid
    order by profile.created_at, profile.id
    limit 1
  ),
  true
);

do $test$
begin
  if coalesce(current_setting('test.user_a', true), '') = ''
    or coalesce(current_setting('test.user_b', true), '') = ''
  then
    raise exception 'This fixture needs at least two active profiles';
  end if;
end;
$test$;

select set_config(
  'request.jwt.claim.sub',
  current_setting('test.user_a'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- A second device that already belongs to another player.
insert into public.push_subscriptions (
  user_id,
  endpoint,
  p256dh,
  auth
)
values (
  current_setting('test.user_b')::uuid,
  'https://fixture.push.example/other-player-device',
  'fixture-p256dh-other',
  'fixture-auth-other'
);

set local role authenticated;

do $test$
begin
  perform public.upsert_my_push_subscription(
    'https://fixture.push.example/device-one',
    'fixture-p256dh-one',
    'fixture-auth-one',
    'Fixture Browser 1.0'
  );

  if not exists (
    select 1
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/device-one'
      and subscription.user_id = current_setting('test.user_a')::uuid
  ) then
    raise exception 'Own subscription was not stored';
  end if;
end;
$test$;

do $test$
begin
  perform public.upsert_my_push_subscription(
    'https://fixture.push.example/device-one',
    'fixture-p256dh-rotated',
    'fixture-auth-rotated',
    'Fixture Browser 2.0'
  );

  if (
    select count(*)
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/device-one'
  ) <> 1 then
    raise exception 'Repeated opt-in created a duplicate device row';
  end if;

  if (
    select subscription.p256dh
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/device-one'
  ) <> 'fixture-p256dh-rotated' then
    raise exception 'Repeated opt-in did not refresh the encryption keys';
  end if;
end;
$test$;

do $test$
begin
  perform public.upsert_my_push_subscription(
    'https://fixture.push.example/device-two',
    'fixture-p256dh-two',
    'fixture-auth-two',
    null
  );

  if (
    select count(*)
    from public.push_subscriptions as subscription
    where subscription.user_id = current_setting('test.user_a')::uuid
  ) <> 2 then
    raise exception 'A second device was not stored separately';
  end if;
end;
$test$;

do $test$
begin
  if (
    select count(*)
    from public.push_subscriptions
  ) <> 2 then
    raise exception 'Row level security exposed another player device';
  end if;
end;
$test$;

do $test$
begin
  perform public.delete_my_push_subscription(
    'https://fixture.push.example/other-player-device'
  );
end;
$test$;

do $test$
begin
  begin
    insert into public.push_subscriptions (
      user_id,
      endpoint,
      p256dh,
      auth
    )
    values (
      current_setting('test.user_b')::uuid,
      'https://fixture.push.example/forged-device',
      'fixture-p256dh-forged',
      'fixture-auth-forged'
    );
    raise exception 'Player bypassed the push subscription RPC';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

do $test$
begin
  begin
    insert into public.push_broadcasts (
      title,
      body,
      destination
    )
    values (
      'Forged',
      'Forged broadcast',
      'predictions'
    );
    raise exception 'Player wrote to the broadcast audit trail';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.get_active_push_subscriptions();
    raise exception 'Player read every stored push endpoint';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

-- The same browser signing in as another player re-binds the device instead
-- of leaving it attached to the previous account.
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.user_b'),
  true
);

do $test$
begin
  perform public.upsert_my_push_subscription(
    'https://fixture.push.example/device-one',
    'fixture-p256dh-rebound',
    'fixture-auth-rebound',
    'Fixture Browser 2.0'
  );

  if (
    select count(*)
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/device-one'
  ) <> 1 then
    raise exception 'Re-binding duplicated the device row';
  end if;

  if (
    select subscription.user_id
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/device-one'
  ) <> current_setting('test.user_b')::uuid then
    raise exception 'Device stayed bound to the previous account';
  end if;
end;
$test$;

reset role;
set local role anon;

do $test$
begin
  begin
    perform public.upsert_my_push_subscription(
      'https://fixture.push.example/anonymous-device',
      'fixture-p256dh-anon',
      'fixture-auth-anon',
      null
    );
    raise exception 'Anonymous subscription RPC call was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform 1
    from public.push_subscriptions;
    raise exception 'Anonymous read of push subscriptions was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

do $test$
begin
  if not exists (
    select 1
    from public.push_subscriptions as subscription
    where subscription.endpoint =
      'https://fixture.push.example/other-player-device'
  ) then
    raise exception 'Cross-user delete removed another player device';
  end if;
end;
$test$;

-- Disabled accounts are never sent a broadcast.
update public.profiles as profile
set status = 'disabled'
where profile.id = current_setting('test.user_b')::uuid;

do $test$
begin
  if exists (
    select 1
    from public.get_active_push_subscriptions() as active
    where active.endpoint = 'https://fixture.push.example/device-one'
  ) then
    raise exception 'Disabled player was included in the send list';
  end if;
end;
$test$;

rollback;

select unnest(array[
  'own_subscription_stored',
  'repeat_opt_in_updates_single_row',
  'second_device_stored_separately',
  'rls_hides_other_player_devices',
  'cross_user_delete_ignored',
  'direct_subscription_write_rejected',
  'broadcast_audit_write_rejected',
  'send_list_hidden_from_players',
  'endpoint_rebinds_to_current_user',
  'anonymous_rpc_rejected',
  'anonymous_read_rejected',
  'disabled_player_excluded_from_send',
  'all_fixture_changes_rolled_back'
]) as passed_test;
