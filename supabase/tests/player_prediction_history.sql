-- Transactional tests for player profile prediction history.
-- Isolated fixture matchdays/matches only. Production rows are not updated
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
    or coalesce(current_setting('test.admin', true), '') = ''
    or coalesce(current_setting('test.home_team', true), '') = ''
    or coalesce(current_setting('test.away_team', true), '') = ''
  then
    raise exception 'This fixture needs two active players, an admin, and two teams';
  end if;
end;
$test$;

do $fixture$
declare
  v_md_a bigint;
  v_md_b bigint;
  v_md_c bigint;
  v_exact bigint;
  v_correct bigint;
  v_wrong bigint;
  v_upcoming bigint;
  v_live bigint;
  v_no_pred bigint;
  v_correctable bigint;
  v_golden_exact bigint;
  v_golden_correct bigint;
begin
  insert into public.matchdays (stage, matchday_number, name, status)
  values ('playoff', 987671, '__prediction_history_a__', 'active')
  returning id into v_md_a;
  perform set_config('test.md_a', v_md_a::text, true);

  insert into public.matchdays (stage, matchday_number, name, status)
  values ('playoff', 987672, '__prediction_history_b__', 'active')
  returning id into v_md_b;
  perform set_config('test.md_b', v_md_b::text, true);

  insert into public.matchdays (stage, matchday_number, name, status)
  values ('playoff', 987673, '__prediction_history_c__', 'active')
  returning id into v_md_c;
  perform set_config('test.md_c', v_md_c::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '3 days',
    'scheduled'
  )
  returning id into v_exact;
  perform set_config('test.exact', v_exact::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() - interval '3 days 1 hour',
    'scheduled'
  )
  returning id into v_correct;
  perform set_config('test.correct', v_correct::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '3 days 2 hours',
    'scheduled'
  )
  returning id into v_wrong;
  perform set_config('test.wrong', v_wrong::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() + interval '2 days',
    'scheduled'
  )
  returning id into v_upcoming;
  perform set_config('test.upcoming', v_upcoming::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '20 minutes',
    'live'
  )
  returning id into v_live;
  perform set_config('test.live', v_live::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.away_team')::bigint,
    current_setting('test.home_team')::bigint,
    now() - interval '3 days 3 hours',
    'scheduled'
  )
  returning id into v_no_pred;
  perform set_config('test.no_pred', v_no_pred::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_a,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '3 days 4 hours',
    'scheduled'
  )
  returning id into v_correctable;
  perform set_config('test.correctable', v_correctable::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_b,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '2 days',
    'scheduled'
  )
  returning id into v_golden_exact;
  perform set_config('test.golden_exact', v_golden_exact::text, true);

  insert into public.matches (
    matchday_id, home_team_id, away_team_id, kickoff_at, status
  )
  values (
    v_md_c,
    current_setting('test.home_team')::bigint,
    current_setting('test.away_team')::bigint,
    now() - interval '1 day',
    'scheduled'
  )
  returning id into v_golden_correct;
  perform set_config('test.golden_correct', v_golden_correct::text, true);

  insert into public.predictions (
    user_id, match_id, predicted_home_score, predicted_away_score
  )
  values
    (current_setting('test.user_a')::uuid, v_exact, 2, 1),
    (current_setting('test.user_a')::uuid, v_correct, 2, 0),
    (current_setting('test.user_a')::uuid, v_wrong, 0, 1),
    (current_setting('test.user_a')::uuid, v_upcoming, 1, 0),
    (current_setting('test.user_a')::uuid, v_live, 1, 0),
    (current_setting('test.user_a')::uuid, v_correctable, 2, 1),
    (current_setting('test.user_a')::uuid, v_golden_exact, 2, 1),
    (current_setting('test.user_a')::uuid, v_golden_correct, 2, 0),
    (current_setting('test.user_b')::uuid, v_no_pred, 1, 0);

  insert into public.golden_match_selections (
    user_id, matchday_id, match_id
  )
  values
    (
      current_setting('test.user_a')::uuid,
      v_md_b,
      v_golden_exact
    ),
    (
      current_setting('test.user_a')::uuid,
      v_md_c,
      v_golden_correct
    );

  if coalesce(current_setting('test.user_c', true), '') <> '' then
    insert into public.predictions (
      user_id, match_id, predicted_home_score, predicted_away_score
    )
    values (
      current_setting('test.user_c')::uuid,
      v_exact,
      2,
      1
    );
  end if;
end;
$fixture$;

reset role;
select set_config('request.jwt.claim.sub', current_setting('test.admin'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.exact')::bigint, 2, 1);
select public.set_match_result(current_setting('test.correct')::bigint, 3, 0);
select public.set_match_result(current_setting('test.wrong')::bigint, 1, 1);
select public.set_match_result(current_setting('test.no_pred')::bigint, 1, 0);
select public.set_match_result(current_setting('test.correctable')::bigint, 2, 1);
select public.set_match_result(current_setting('test.golden_exact')::bigint, 2, 1);
select public.set_match_result(current_setting('test.golden_correct')::bigint, 2, 1);

reset role;

select set_config('request.jwt.claim.sub', current_setting('test.user_a'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_points integer;
  v_golden boolean;
  v_count integer;
begin
  select history.points, history.is_golden_match
  into v_points, v_golden
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.exact')::bigint;

  if not found or v_points <> 5 or v_golden then
    raise exception 'Completed exact score should appear with 5 points';
  end if;

  select history.points
  into v_points
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.correct')::bigint;

  if not found or v_points <> 2 then
    raise exception 'Completed correct result should appear with 2 points';
  end if;

  select history.points
  into v_points
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.wrong')::bigint;

  if not found or v_points <> 0 then
    raise exception 'Completed wrong prediction should appear with 0 points';
  end if;

  select history.points, history.is_golden_match
  into v_points, v_golden
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.golden_exact')::bigint;

  if not found or v_points <> 10 or v_golden is not true then
    raise exception 'Golden exact should appear with 10 points and Golden flag';
  end if;

  select history.points, history.is_golden_match
  into v_points, v_golden
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.golden_correct')::bigint;

  if not found or v_points <> 4 or v_golden is not true then
    raise exception 'Golden correct result should appear with 4 points';
  end if;

  select count(*)
  into v_count
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
  where match_id in (
    current_setting('test.upcoming')::bigint,
    current_setting('test.live')::bigint,
    current_setting('test.no_pred')::bigint
  );

  if v_count <> 0 then
    raise exception 'Upcoming, live, or missed matches leaked into owner history';
  end if;
end;
$test$;

reset role;

select set_config('request.jwt.claim.sub', current_setting('test.user_b'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_count integer;
  v_points integer;
begin
  select count(*)
  into v_count
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
  where match_id = current_setting('test.exact')::bigint;

  if v_count <> 1 then
    raise exception 'Other authenticated user could not read completed history';
  end if;

  select count(*)
  into v_count
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
  where match_id in (
    current_setting('test.upcoming')::bigint,
    current_setting('test.live')::bigint
  );

  if v_count <> 0 then
    raise exception 'Other user saw unrevealed or live history via RPC';
  end if;

  select count(*)
  into v_count
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
  where match_id = current_setting('test.no_pred')::bigint;

  if v_count <> 0 then
    raise exception 'Completed match without the player prediction appeared';
  end if;

  select history.points
  into v_points
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.correctable')::bigint;

  if not found or v_points <> 5 then
    raise exception 'Correctable match did not start at 5 points';
  end if;
end;
$test$;

reset role;
select set_config('request.jwt.claim.sub', current_setting('test.admin'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.set_match_result(current_setting('test.correctable')::bigint, 0, 1);

reset role;
select set_config('request.jwt.claim.sub', current_setting('test.user_b'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
declare
  v_home integer;
  v_away integer;
  v_points integer;
begin
  select history.home_score, history.away_score, history.points
  into v_home, v_away, v_points
  from public.get_player_prediction_history(current_setting('test.user_a')::uuid)
    as history
  where history.match_id = current_setting('test.correctable')::bigint;

  if not found or v_home <> 0 or v_away <> 1 or v_points <> 0 then
    raise exception 'Result correction did not update history score/points';
  end if;
end;
$test$;

reset role;

do $test$
begin
  if coalesce(current_setting('test.user_c', true), '') = '' then
    return;
  end if;

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
  from public.get_player_prediction_history(current_setting('test.user_c')::uuid);

  if v_count <> 0 then
    raise exception 'Disabled player history was visible to another user';
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
  from public.get_player_prediction_history(current_setting('test.user_c')::uuid)
  where match_id = current_setting('test.exact')::bigint;

  if v_count <> 1 then
    raise exception 'Disabled owner could not read own completed history';
  end if;
end;
$test$;

reset role;
set local role anon;

do $test$
begin
  begin
    perform public.get_player_prediction_history(
      current_setting('test.user_a')::uuid
    );

    raise exception 'Anonymous RPC call was accepted';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;
rollback;

select unnest(array[
  'completed_exact_5',
  'completed_correct_2',
  'completed_wrong_0',
  'golden_exact_10',
  'golden_correct_4',
  'upcoming_hidden',
  'live_without_result_hidden',
  'completed_without_prediction_hidden',
  'result_correction_updates_history',
  'other_user_reads_completed',
  'other_user_blocked_from_unrevealed',
  'disabled_hidden_from_others',
  'disabled_owner_reads_own',
  'anonymous_rpc_rejected',
  'all_fixture_changes_rolled_back'
]) as passed_test;
