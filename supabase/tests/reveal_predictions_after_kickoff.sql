-- Transactional visibility tests for post-kickoff prediction reveal.
-- Isolated fixture matchday/matches only. Production rows are not updated
-- or deleted. Every mutation is rolled back at the end.

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
  'test.user_c',
  (
    select profile.id::text
    from public.profiles as profile
    where profile.id <> current_setting('test.user_a')::uuid
      and profile.id <> current_setting('test.user_b')::uuid
    order by profile.created_at, profile.id
    limit 1
  ),
  true
);
select set_config(
  'test.home_team',
  (
    select team.id::text
    from public.teams as team
    order by team.id
    limit 1
  ),
  true
);
select set_config(
  'test.away_team',
  (
    select team.id::text
    from public.teams as team
    where team.id <> current_setting('test.home_team')::bigint
    order by team.id
    limit 1
  ),
  true
);

do $test$
begin
  if coalesce(current_setting('test.user_a', true), '') = ''
    or coalesce(current_setting('test.user_b', true), '') = ''
    or coalesce(current_setting('test.home_team', true), '') = ''
    or coalesce(current_setting('test.away_team', true), '') = ''
  then
    raise exception 'This fixture needs two active players and two teams';
  end if;
end;
$test$;

do $fixture$
declare
  v_matchday bigint;
  v_upcoming bigint;
  v_just_kicked_off bigint;
  v_finished bigint;
  v_postponed_future bigint;
  v_postponed_past bigint;
  v_cancelled_future bigint;
  v_empty_predictions bigint;
begin
  insert into public.matchdays (
    stage,
    matchday_number,
    name,
    status
  )
  values (
    'playoff',
    987651,
    '__reveal_predictions_fixture__',
    'upcoming'
  )
  returning id into v_matchday;
  perform set_config('test.matchday', v_matchday::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() + interval '2 hours',
    'scheduled'
  )
  returning id into v_upcoming;
  perform set_config('test.upcoming', v_upcoming::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() - interval '1 second',
    'scheduled'
  )
  returning id into v_just_kicked_off;
  perform set_config('test.just_kicked_off', v_just_kicked_off::text, true);

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
    v_matchday,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '2 hours',
    'finished',
    2,
    1
  )
  returning id into v_finished;
  perform set_config('test.finished', v_finished::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() + interval '3 hours',
    'postponed'
  )
  returning id into v_postponed_future;
  perform set_config('test.postponed_future', v_postponed_future::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '90 minutes',
    'postponed'
  )
  returning id into v_postponed_past;
  perform set_config('test.postponed_past', v_postponed_past::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() + interval '4 hours',
    'cancelled'
  )
  returning id into v_cancelled_future;
  perform set_config('test.cancelled_future', v_cancelled_future::text, true);

  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    v_matchday,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '5 minutes',
    'scheduled'
  )
  returning id into v_empty_predictions;
  perform set_config('test.empty_predictions', v_empty_predictions::text, true);
end;
$fixture$;

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
values
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.upcoming')::bigint,
    1,
    0,
    null
  ),
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.just_kicked_off')::bigint,
    2,
    1,
    null
  ),
  (
    current_setting('test.user_b')::uuid,
    current_setting('test.just_kicked_off')::bigint,
    0,
    0,
    null
  ),
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.finished')::bigint,
    2,
    1,
    5
  ),
  (
    current_setting('test.user_b')::uuid,
    current_setting('test.finished')::bigint,
    1,
    1,
    0
  ),
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.postponed_future')::bigint,
    3,
    0,
    null
  ),
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.postponed_past')::bigint,
    1,
    1,
    null
  ),
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.cancelled_future')::bigint,
    4,
    0,
    null
  );

insert into public.golden_match_selections (
  user_id,
  matchday_id,
  match_id
)
values
  (
    current_setting('test.user_a')::uuid,
    current_setting('test.matchday')::bigint,
    current_setting('test.upcoming')::bigint
  );

select set_config('request.jwt.claim.sub', current_setting('test.user_a'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.predictions as prediction
  where prediction.user_id = current_setting('test.user_a')::uuid
    and prediction.match_id = current_setting('test.upcoming')::bigint;

  if v_count <> 1 then
    raise exception 'Owner could not read own prediction before kickoff';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', current_setting('test.user_b'), true);

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.predictions as prediction
  where prediction.user_id = current_setting('test.user_a')::uuid
    and prediction.match_id = current_setting('test.upcoming')::bigint;

  if v_count <> 0 then
    raise exception 'Other user read a prediction before kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.golden_match_selections as golden
  where golden.user_id = current_setting('test.user_a')::uuid
    and golden.match_id = current_setting('test.upcoming')::bigint;

  if v_count <> 0 then
    raise exception 'Golden Match leaked before kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.get_match_player_predictions(
    array[current_setting('test.upcoming')::bigint]
  );

  if v_count <> 0 then
    raise exception 'RPC returned upcoming-match predictions before kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_home integer;
  v_away integer;
begin
  select
    prediction.predicted_home_score,
    prediction.predicted_away_score
  into v_home, v_away
  from public.predictions as prediction
  where prediction.user_id = current_setting('test.user_a')::uuid
    and prediction.match_id = current_setting('test.just_kicked_off')::bigint;

  if v_home is distinct from 2 or v_away is distinct from 1 then
    raise exception 'Other user could not read prediction after kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.get_match_player_predictions(
    array[current_setting('test.just_kicked_off')::bigint]
  );

  if v_count <> 2 then
    raise exception 'RPC did not return both players after kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.get_match_player_predictions(
    array[current_setting('test.empty_predictions')::bigint]
  );

  if v_count <> 0 then
    raise exception 'Empty kicked-off match should return no prediction rows';
  end if;
end;
$test$;

do $test$
declare
  v_future integer;
  v_past integer;
  v_cancelled integer;
begin
  select count(*)
  into v_future
  from public.predictions as prediction
  where prediction.match_id = current_setting('test.postponed_future')::bigint
    and prediction.user_id = current_setting('test.user_a')::uuid;

  select count(*)
  into v_past
  from public.predictions as prediction
  where prediction.match_id = current_setting('test.postponed_past')::bigint
    and prediction.user_id = current_setting('test.user_a')::uuid;

  select count(*)
  into v_cancelled
  from public.predictions as prediction
  where prediction.match_id = current_setting('test.cancelled_future')::bigint
    and prediction.user_id = current_setting('test.user_a')::uuid;

  if v_future <> 0 then
    raise exception 'Postponed future kickoff prediction was visible';
  end if;
  if v_past <> 1 then
    raise exception 'Postponed past kickoff prediction was hidden';
  end if;
  if v_cancelled <> 0 then
    raise exception 'Cancelled future kickoff prediction was visible';
  end if;
end;
$test$;

reset role;

update public.golden_match_selections
set
  match_id = current_setting('test.just_kicked_off')::bigint,
  updated_at = now()
where user_id = current_setting('test.user_a')::uuid
  and matchday_id = current_setting('test.matchday')::bigint;

select set_config('request.jwt.claim.sub', current_setting('test.user_b'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_count integer;
  v_flag boolean;
begin
  select count(*)
  into v_count
  from public.golden_match_selections as golden
  where golden.user_id = current_setting('test.user_a')::uuid
    and golden.match_id = current_setting('test.just_kicked_off')::bigint;

  if v_count <> 1 then
    raise exception 'Golden Match was not visible after kickoff';
  end if;

  select player.is_golden_match
  into v_flag
  from public.get_match_player_predictions(
    array[current_setting('test.just_kicked_off')::bigint]
  ) as player
  where player.user_id = current_setting('test.user_a')::uuid;

  if v_flag is not true then
    raise exception 'RPC did not mark Golden Match after kickoff';
  end if;
end;
$test$;

do $test$
declare
  v_count integer;
begin
  select count(*)
  into v_count
  from public.get_match_player_predictions(
    array[
      current_setting('test.upcoming')::bigint,
      current_setting('test.just_kicked_off')::bigint
    ]
  ) as player
  where player.match_id = current_setting('test.upcoming')::bigint;

  if v_count <> 0 then
    raise exception 'RPC mixed ids leaked an upcoming prediction';
  end if;
end;
$test$;

reset role;
set local role anon;

do $test$
begin
  begin
    perform 1
    from public.predictions;

    raise exception 'Anonymous SELECT on predictions was accepted';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.get_match_player_predictions(
      array[current_setting('test.just_kicked_off')::bigint]
    );

    raise exception 'Anonymous RPC call was accepted';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

do $test$
begin
  if coalesce(current_setting('test.user_c', true), '') = '' then
    return;
  end if;

  insert into public.predictions (
    user_id,
    match_id,
    predicted_home_score,
    predicted_away_score
  )
  values (
    current_setting('test.user_c')::uuid,
    current_setting('test.just_kicked_off')::bigint,
    9,
    9
  );

  update public.profiles
  set status = 'disabled'
  where id = current_setting('test.user_c')::uuid
    and status = 'active';
end;
$test$;

select set_config('request.jwt.claim.sub', current_setting('test.user_b'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_count integer;
begin
  if coalesce(current_setting('test.user_c', true), '') = '' then
    return;
  end if;

  select count(*)
  into v_count
  from public.predictions as prediction
  where prediction.user_id = current_setting('test.user_c')::uuid
    and prediction.match_id = current_setting('test.just_kicked_off')::bigint;

  if v_count <> 0 then
    raise exception 'Disabled user prediction was visible after kickoff';
  end if;
end;
$test$;

reset role;

do $test$
begin
  if coalesce(current_setting('test.user_c', true), '') = '' then
    return;
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.user_c'),
    true
  );
end;
$test$;

select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_count integer;
begin
  if coalesce(current_setting('test.user_c', true), '') = '' then
    return;
  end if;

  select count(*)
  into v_count
  from public.predictions as prediction
  where prediction.user_id = current_setting('test.user_c')::uuid
    and prediction.match_id = current_setting('test.just_kicked_off')::bigint;

  if v_count <> 1 then
    raise exception 'Disabled owner could not read own prediction';
  end if;
end;
$test$;

reset role;
rollback;

select unnest(array[
  'owner_reads_own_before_kickoff',
  'other_user_blocked_before_kickoff',
  'golden_match_hidden_before_kickoff',
  'rpc_empty_before_kickoff',
  'other_user_reads_after_kickoff',
  'rpc_batch_after_kickoff',
  'empty_match_no_error',
  'postponed_cancelled_follow_kickoff',
  'golden_match_visible_after_kickoff',
  'rpc_does_not_leak_upcoming_in_mixed_ids',
  'anonymous_select_rejected',
  'anonymous_rpc_rejected',
  'disabled_hidden_from_others_after_kickoff',
  'disabled_owner_reads_own',
  'all_fixture_changes_rolled_back'
]) as passed_test;
