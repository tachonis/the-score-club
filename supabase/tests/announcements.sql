-- Transactional Announcements v1 verification against the hosted schema.
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

do $test$
declare
  v_published uuid;
  v_draft uuid;
begin
  insert into public.announcements (
    title,
    body,
    category,
    is_published
  )
  values (
    'Published fixture',
    'A published announcement for player read tests.',
    'general',
    true
  )
  returning id into v_published;

  insert into public.announcements (
    title,
    body,
    category,
    is_published
  )
  values (
    'Draft fixture',
    'An unpublished announcement that players must not see.',
    'general',
    false
  )
  returning id into v_draft;

  perform set_config('test.published_id', v_published::text, true);
  perform set_config('test.draft_id', v_draft::text, true);
end;
$test$;

-- Authenticated player A: published visible, draft hidden, writes rejected.
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.user_a'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

set local role authenticated;

do $test$
begin
  if not exists (
    select 1
    from public.announcements as announcement
    where announcement.id = current_setting('test.published_id')::uuid
  ) then
    raise exception 'Authenticated user could not read a published announcement';
  end if;
end;
$test$;

do $test$
begin
  if exists (
    select 1
    from public.announcements as announcement
    where announcement.id = current_setting('test.draft_id')::uuid
  ) then
    raise exception 'Unpublished announcement was visible to a normal user';
  end if;
end;
$test$;

do $test$
begin
  begin
    insert into public.announcements (title, body, is_published)
    values ('Forged', 'Player must not create announcements', false);
    raise exception 'Player created an announcement';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  update public.announcements
  set title = 'Hijacked'
  where id = current_setting('test.published_id')::uuid;

  if found then
    raise exception 'Player updated an announcement';
  end if;
end;
$test$;

do $test$
begin
  delete from public.announcements
  where id = current_setting('test.published_id')::uuid;

  if found then
    raise exception 'Player deleted an announcement';
  end if;
end;
$test$;

do $test$
declare
  v_unread integer;
  v_again integer;
begin
  select public.count_unread_announcements() into v_unread;

  if v_unread < 1 then
    raise exception 'New published announcement was not unread';
  end if;

  perform public.mark_announcement_read(
    current_setting('test.published_id')::uuid
  );
  perform public.mark_announcement_read(
    current_setting('test.published_id')::uuid
  );

  if (
    select count(*)
    from public.announcement_reads as read_row
    where read_row.announcement_id = current_setting('test.published_id')::uuid
      and read_row.user_id = current_setting('test.user_a')::uuid
  ) <> 1 then
    raise exception 'Reopening duplicated the read row';
  end if;

  select public.count_unread_announcements() into v_again;

  if v_again <> v_unread - 1 then
    raise exception 'Unread count did not decrease after opening the announcement';
  end if;
end;
$test$;

do $test$
begin
  begin
    insert into public.announcement_reads (
      announcement_id,
      user_id
    )
    values (
      current_setting('test.published_id')::uuid,
      current_setting('test.user_b')::uuid
    );
    raise exception 'Player marked a read for another user';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  if exists (
    select 1
    from public.announcement_reads as read_row
    where read_row.user_id = current_setting('test.user_b')::uuid
  ) then
    raise exception 'Player A could read another user read state';
  end if;
end;
$test$;

-- Player B still sees the same announcement as unread.
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.user_b'),
  true
);

do $test$
begin
  if exists (
    select 1
    from public.announcement_reads as read_row
    where read_row.announcement_id = current_setting('test.published_id')::uuid
      and read_row.user_id = current_setting('test.user_a')::uuid
  ) then
    raise exception 'Player B could see another user read row';
  end if;

  if public.count_unread_announcements() < 1 then
    raise exception 'Player B did not see the announcement as unread';
  end if;
end;
$test$;

-- Anon cannot access tables or RPCs.
reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);

do $test$
begin
  begin
    perform 1 from public.announcements;
    raise exception 'Anonymous role read announcements';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.count_unread_announcements();
    raise exception 'Anonymous role counted unread announcements';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.mark_announcement_read(
      current_setting('test.published_id')::uuid
    );
    raise exception 'Anonymous role marked an announcement as read';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

-- Admin can create, edit, publish, and delete.
reset role;
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.admin'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_id uuid;
begin
  if not exists (
    select 1
    from public.announcements as announcement
    where announcement.id = current_setting('test.draft_id')::uuid
      and announcement.is_published = false
  ) then
    raise exception 'Admin could not read an unpublished announcement';
  end if;

  insert into public.announcements (
    title,
    body,
    category,
    is_published,
    created_by
  )
  values (
    'Admin draft',
    'Created by the administrator.',
    'rules',
    false,
    current_setting('test.admin')::uuid
  )
  returning id into v_id;

  update public.announcements
  set
    title = 'Admin published',
    is_published = true
  where id = v_id;

  if not exists (
    select 1
    from public.announcements as announcement
    where announcement.id = v_id
      and announcement.is_published = true
      and announcement.published_at is not null
      and announcement.title = 'Admin published'
  ) then
    raise exception 'Admin publish did not persist';
  end if;

  delete from public.announcements
  where id = v_id;

  if exists (
    select 1
    from public.announcements as announcement
    where announcement.id = v_id
  ) then
    raise exception 'Admin delete did not persist';
  end if;
end;
$test$;

-- Announcement push destinations are accepted without dropping existing ones.
reset role;

do $test$
begin
  insert into public.push_broadcasts (
    title,
    body,
    destination
  )
  values (
    'Announcement deep link',
    'Open the notice',
    'announcements/' || current_setting('test.published_id')
  );

  insert into public.push_broadcasts (
    title,
    body,
    destination
  )
  values (
    'Existing destination',
    'Open predictions',
    'predictions'
  );
end;
$test$;

rollback;
