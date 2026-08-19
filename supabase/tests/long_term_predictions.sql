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
  'test.team_a',
  (select team.id::text from public.teams as team order by team.id limit 1),
  true
);
select set_config(
  'test.team_b',
  (
    select team.id::text
    from public.teams as team
    order by team.id
    offset 1
    limit 1
  ),
  true
);
select set_config(
  'test.team_c',
  (
    select team.id::text
    from public.teams as team
    order by team.id
    offset 2
    limit 1
  ),
  true
);

set local role authenticated;

-- Early-season locking scenarios (Tests 1-2). Rolled back before the main flow.
savepoint early_season_locking_tests;

select set_config(
  'test.md3_id',
  (
    select matchday.id::text
    from public.matchdays as matchday
    where matchday.stage = 'league_phase'
      and matchday.matchday_number = 3
    limit 1
  ),
  true
);

do $test$
begin
  if current_setting('test.md3_id', true) is null then
    raise exception 'Matchday 3 is required for the hosted long-term test fixture';
  end if;
end;
$test$;

delete from public.long_term_predictions as selection
where selection.user_id = (select auth.uid());

delete from public.matches as match_row
where match_row.matchday_id = current_setting('test.md3_id')::bigint;

do $test$
begin
  if (
    select status.is_locked
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Matchday 3 with zero matches should remain unlocked';
  end if;

  if (
    select status.is_configured
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Matchday 3 with zero matches should not be configured';
  end if;
end;
$test$;

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_a')::bigint
);

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_b')::bigint
);

delete from public.matchdays as matchday
where matchday.id = current_setting('test.md3_id')::bigint;

do $test$
begin
  if (
    select status.is_locked
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Missing Matchday 3 should remain unlocked';
  end if;

  if (
    select status.is_configured
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Missing Matchday 3 should not be configured';
  end if;
end;
$test$;

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_a')::bigint
);

select *
from public.set_long_term_prediction(
  'league_phase_first',
  current_setting('test.team_b')::bigint
);

rollback to savepoint early_season_locking_tests;

delete from public.long_term_predictions as selection
where selection.user_id = (select auth.uid());

do $test$
begin
  if (
    select status.is_locked
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Unfinished Matchday 3 should remain unlocked before completion';
  end if;
end;
$test$;

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_a')::bigint
);

do $test$
begin
  if not exists (
    select 1
    from public.long_term_predictions as selection
    where selection.user_id = (select auth.uid())
      and selection.prediction_type = 'winner'
      and selection.team_id = current_setting('test.team_a')::bigint
  ) then
    raise exception 'First long-term prediction was not saved';
  end if;
end;
$test$;

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_b')::bigint
);

select *
from public.set_long_term_prediction(
  'winner',
  current_setting('test.team_a')::bigint
);

select *
from public.set_long_term_prediction(
  'league_phase_first',
  current_setting('test.team_b')::bigint
);

do $test$
begin
  if (
    select count(*)
    from public.long_term_predictions as selection
    where selection.user_id = (select auth.uid())
  ) <> 2 then
    raise exception 'Long-term prediction uniqueness was not preserved';
  end if;
end;
$test$;

do $test$
begin
  begin
    update public.long_term_predictions as selection
    set team_id = current_setting('test.team_c')::bigint
    where selection.user_id = (select auth.uid());
    raise exception 'Player directly updated a long-term selection';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

update public.matches as match_row
set
  status = 'finished',
  home_score = coalesce(match_row.home_score, 0),
  away_score = coalesce(match_row.away_score, 0),
  updated_at = now()
from public.matchdays as matchday
where matchday.id = match_row.matchday_id
  and matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

set local role authenticated;

do $test$
begin
  begin
    perform public.set_long_term_prediction(
      'winner',
      current_setting('test.team_c')::bigint
    );
    raise exception 'Long-term prediction changed after Matchday 3';
  exception
    when sqlstate '22023' then
      if sqlerrm <> 'Long-term predictions are locked after Matchday 3' then
        raise;
      end if;
  end;
end;
$test$;

do $test$
begin
  if not (
    select status.is_locked
    from public.get_long_term_prediction_status() as status
  ) then
    raise exception 'Completed Matchday 3 should report locked status';
  end if;

  if not exists (
    select 1
    from public.long_term_predictions as selection
    where selection.user_id = (select auth.uid())
      and selection.prediction_type = 'winner'
  ) then
    raise exception 'Existing long-term prediction should remain readable after lock';
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
    perform public.set_long_term_outcome(
      'winner',
      current_setting('test.team_a')::bigint
    );
    raise exception 'Non-admin long-term outcome was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

reset role;

update public.profiles as profile
set role = 'admin'
where profile.id = current_setting('request.jwt.claim.sub')::uuid;

set local role authenticated;

select *
from public.set_long_term_outcome(
  'winner',
  current_setting('test.team_a')::bigint
);

do $test$
begin
  if (
    select award.points
    from public.long_term_awards as award
    where award.user_id = (select auth.uid())
      and award.prediction_type = 'winner'
  ) <> 30 then
    raise exception 'Correct Winner prediction did not award 30 points';
  end if;
end;
$test$;

select *
from public.set_long_term_outcome(
  'league_phase_first',
  current_setting('test.team_b')::bigint
);

do $test$
begin
  if (
    select award.points
    from public.long_term_awards as award
    where award.user_id = (select auth.uid())
      and award.prediction_type = 'league_phase_first'
  ) <> 15 then
    raise exception 'Correct League Phase first prediction did not award 15 points';
  end if;
end;
$test$;

select *
from public.set_long_term_outcome(
  'winner',
  current_setting('test.team_c')::bigint
);

select *
from public.set_long_term_outcome(
  'league_phase_first',
  current_setting('test.team_c')::bigint
);

do $test$
begin
  if exists (
    select 1
    from public.long_term_awards as award
    where award.user_id = (select auth.uid())
      and award.points <> 0
  ) then
    raise exception 'Wrong long-term prediction did not award 0 points';
  end if;
end;
$test$;

select *
from public.set_long_term_outcome(
  'winner',
  current_setting('test.team_a')::bigint
);

do $test$
begin
  if (
    select award.points
    from public.long_term_awards as award
    where award.user_id = (select auth.uid())
      and award.prediction_type = 'winner'
  ) <> 30 then
    raise exception 'Outcome correction did not recompute Winner points';
  end if;
end;
$test$;

select *
from public.set_long_term_outcome(
  'league_phase_first',
  current_setting('test.team_b')::bigint
);

do $test$
declare
  v_changed_awards bigint;
begin
  select result.changed_awards
  into v_changed_awards
  from public.set_long_term_outcome(
    'league_phase_first',
    current_setting('test.team_b')::bigint
  ) as result;

  if v_changed_awards <> 0 then
    raise exception 'Repeated long-term scoring was not idempotent';
  end if;
end;
$test$;

do $test$
declare
  v_match_points bigint;
  v_long_term_points bigint;
  v_leaderboard_points bigint;
begin
  select coalesce(sum(prediction.points), 0)::bigint
  into v_match_points
  from public.predictions as prediction
  where prediction.user_id = (select auth.uid());

  select coalesce(sum(award.points), 0)::bigint
  into v_long_term_points
  from public.long_term_awards as award
  where award.user_id = (select auth.uid());

  select leaderboard.total_points
  into v_leaderboard_points
  from public.get_leaderboard() as leaderboard
  where leaderboard.user_id = (select auth.uid());

  if v_long_term_points <> 45
    or v_leaderboard_points <> v_match_points + v_long_term_points
  then
    raise exception 'Leaderboard total does not include long-term points';
  end if;
end;
$test$;

do $test$
begin
  begin
    update public.long_term_awards as award
    set points = 0
    where award.user_id = (select auth.uid());
    raise exception 'Player directly updated long-term awards';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

do $test$
begin
  begin
    insert into public.long_term_outcomes (
      prediction_type,
      team_id,
      decided_by
    )
    values (
      'winner',
      current_setting('test.team_c')::bigint,
      (select auth.uid())
    );
    raise exception 'Admin bypassed the long-term outcome RPC';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;
rollback;

select unnest(array[
  'md3_zero_matches_unlocked',
  'md3_absent_unlocked',
  'unfinished_matchday_3_unlocked',
  'first_save',
  'change_before_lock',
  'one_choice_per_type',
  'direct_selection_write_rejected',
  'lock_after_matchday_3',
  'locked_status_after_completion',
  'existing_prediction_readable_after_lock',
  'non_admin_outcome_rejected',
  'winner_correct_30',
  'league_phase_first_correct_15',
  'wrong_0',
  'outcome_correction',
  'idempotent_repeat',
  'leaderboard_includes_long_term_points',
  'direct_award_write_rejected',
  'direct_outcome_write_rejected',
  'all_fixture_changes_rolled_back'
]) as passed_test;
