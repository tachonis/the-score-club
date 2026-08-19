-- Transactional Golden Match verification against the hosted schema.
-- Every fixture mutation is rolled back at the end.

begin;

select set_config(
  'request.jwt.claim.sub',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.role = 'admin'
      and profile.status = 'active'
    order by profile.created_at
    limit 1
  ),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select set_config(
  'test.md1_match',
  (
    select match_row.id::text
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.matchday_number = 1
    order by match_row.kickoff_at, match_row.id
    limit 1
  ),
  true
);
select set_config(
  'test.golden_match_a',
  (
    select match_row.id::text
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.matchday_number = 2
    order by match_row.kickoff_at, match_row.id
    limit 1
  ),
  true
);
select set_config(
  'test.golden_match_b',
  (
    select match_row.id::text
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.matchday_number = 2
    order by match_row.kickoff_at, match_row.id
    offset 1
    limit 1
  ),
  true
);
select set_config(
  'test.normal_match',
  (
    select match_row.id::text
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.matchday_number = 2
    order by match_row.kickoff_at, match_row.id
    offset 2
    limit 1
  ),
  true
);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points,
  updated_at
)
values
  (
    current_setting('request.jwt.claim.sub')::uuid,
    current_setting('test.golden_match_b')::bigint,
    2,
    1,
    null,
    now()
  ),
  (
    current_setting('request.jwt.claim.sub')::uuid,
    current_setting('test.normal_match')::bigint,
    2,
    1,
    null,
    now()
  )
on conflict (user_id, match_id) do update
set
  predicted_home_score = excluded.predicted_home_score,
  predicted_away_score = excluded.predicted_away_score,
  points = null,
  updated_at = excluded.updated_at;

set local role authenticated;

do $test$
begin
  begin
    perform public.set_golden_match(
      current_setting('test.md1_match')::bigint
    );
    raise exception 'Matchday 1 Golden Match selection was accepted';
  exception
    when sqlstate '22023' then
      if sqlerrm <> 'Golden Match is available from Matchday 2' then
        raise;
      end if;
  end;
end;
$test$;

select *
from public.set_golden_match(
  current_setting('test.golden_match_a')::bigint
);

do $test$
begin
  if (
    select count(*)
    from public.golden_match_selections as selection
    where selection.user_id = (select auth.uid())
  ) <> 1 then
    raise exception 'First Golden Match selection did not create one row';
  end if;
end;
$test$;

select *
from public.set_golden_match(
  current_setting('test.golden_match_b')::bigint
);

do $test$
begin
  if (
    select count(*)
    from public.golden_match_selections as selection
    where selection.user_id = (select auth.uid())
  ) <> 1
  or not exists (
    select 1
    from public.golden_match_selections as selection
    where selection.user_id = (select auth.uid())
      and selection.match_id =
        current_setting('test.golden_match_b')::bigint
  ) then
    raise exception 'Replacement did not preserve exactly one selection';
  end if;
end;
$test$;

reset role;

do $test$
begin
  begin
    insert into public.golden_match_selections (
      user_id,
      matchday_id,
      match_id
    )
    select
      current_setting('request.jwt.claim.sub')::uuid,
      match_row.matchday_id,
      match_row.id
    from public.matches as match_row
    where match_row.id =
      current_setting('test.golden_match_a')::bigint;

    raise exception 'Unique matchday constraint accepted a second row';
  exception
    when unique_violation then null;
  end;
end;
$test$;

update public.matches as match_row
set kickoff_at = now() - interval '1 minute'
where match_row.id = current_setting('test.golden_match_b')::bigint;

set local role authenticated;

do $test$
begin
  begin
    perform public.set_golden_match(
      current_setting('test.golden_match_a')::bigint
    );
    raise exception 'Locked Golden Match was replaced after kickoff';
  exception
    when sqlstate '22023' then
      if sqlerrm <> 'Golden Match is locked after its kickoff' then
        raise;
      end if;
  end;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.golden_match_b')::bigint,
  2,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.golden_match_b')::bigint
  ) <> 10 then
    raise exception 'Golden exact score did not award 10 points';
  end if;
end;
$test$;

do $test$
declare
  v_changed bigint;
begin
  select result.changed_predictions
  into v_changed
  from public.set_match_result(
    current_setting('test.golden_match_b')::bigint,
    2,
    1
  ) as result;

  if v_changed <> 0 then
    raise exception 'Repeated result scoring was not idempotent';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.golden_match_b')::bigint,
  3,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.golden_match_b')::bigint
  ) <> 4 then
    raise exception 'Golden correct result did not award 4 points';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.golden_match_b')::bigint,
  1,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.golden_match_b')::bigint
  ) <> 0 then
    raise exception 'Wrong Golden prediction did not award 0 points';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.golden_match_b')::bigint,
  2,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.golden_match_b')::bigint
  ) <> 10 then
    raise exception 'Result correction did not restore 10 Golden points';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.normal_match')::bigint,
  2,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.normal_match')::bigint
  ) <> 5 then
    raise exception 'Normal exact score no longer awards 5 points';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.normal_match')::bigint,
  3,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.normal_match')::bigint
  ) <> 2 then
    raise exception 'Normal correct result no longer awards 2 points';
  end if;
end;
$test$;

select *
from public.set_match_result(
  current_setting('test.normal_match')::bigint,
  1,
  1
);

do $test$
begin
  if (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = (select auth.uid())
      and prediction.match_id =
        current_setting('test.normal_match')::bigint
  ) <> 0 then
    raise exception 'Wrong normal prediction no longer awards 0 points';
  end if;
end;
$test$;

reset role;

update public.profiles as profile
set role = 'player'
where profile.id = current_setting('request.jwt.claim.sub')::uuid;

set local role authenticated;

do $test$
begin
  begin
    perform public.set_match_result(
      current_setting('test.normal_match')::bigint,
      2,
      1
    );
    raise exception 'Non-admin result RPC call was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

do $test$
begin
  begin
    update public.predictions as prediction
    set points = 10
    where prediction.user_id = (select auth.uid());
    raise exception 'Player directly updated prediction points';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

do $test$
begin
  begin
    insert into public.golden_match_selections (
      user_id,
      matchday_id,
      match_id
    )
    select
      (select auth.uid()),
      match_row.matchday_id,
      match_row.id
    from public.matches as match_row
    where match_row.id = current_setting('test.normal_match')::bigint;
    raise exception 'Player bypassed the Golden Match RPC';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;
set local role anon;

do $test$
begin
  begin
    perform public.set_golden_match(
      current_setting('test.golden_match_a')::bigint
    );
    raise exception 'Anonymous Golden Match RPC call was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;
rollback;

select unnest(array[
  'matchday_1_rejected',
  'first_selection',
  'replacement_before_kickoff',
  'one_row_unique_constraint',
  'replacement_after_kickoff_rejected',
  'golden_exact_10',
  'idempotent_repeat',
  'golden_correct_4',
  'golden_wrong_0',
  'result_correction',
  'normal_scoring_5_2_0_preserved',
  'non_admin_result_rejected',
  'direct_points_write_rejected',
  'direct_selection_write_rejected',
  'anonymous_rpc_rejected',
  'all_fixture_changes_rolled_back'
]) as passed_test;
