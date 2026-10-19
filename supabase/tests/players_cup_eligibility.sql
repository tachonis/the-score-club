-- Players Cup eligibility: participation in League Phase Matchdays 1 or 2.
-- The fixture is rolled back. Run it as the database owner.

begin;

create function pg_temp.elig_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'PLAYERS CUP ELIGIBILITY TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.elig_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad(p_index::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.elig_add_player(
  p_index integer,
  p_username text
)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.elig_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'players-cup-elig-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', p_username)
  );

  return v_user_id;
end;
$helper$;

insert into public.teams (name, short_name)
values
  ('ZZ Cup Eligibility A', 'ZEA'),
  ('ZZ Cup Eligibility B', 'ZEB')
on conflict (name) do nothing;

select set_config(
  'test.team_a',
  (select team.id::text from public.teams as team where team.name = 'ZZ Cup Eligibility A'),
  true
);
select set_config(
  'test.team_b',
  (select team.id::text from public.teams as team where team.name = 'ZZ Cup Eligibility B'),
  true
);

insert into public.matchdays (stage, matchday_number, name)
select
  'league_phase',
  generated.number,
  generated.number || 'η αγωνιστική'
from generate_series(1, 8) as generated(number)
on conflict (stage, matchday_number) do nothing;

delete from public.matches as match_row
using public.matchdays as matchday
where matchday.id = match_row.matchday_id
  and matchday.stage = 'league_phase'
  and matchday.matchday_number between 1 and 3;

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status,
  home_score,
  away_score
)
select
  matchday.id,
  current_setting('test.team_a')::bigint,
  current_setting('test.team_b')::bigint,
  timestamptz '2026-09-01 18:00+00'
    + ((matchday.matchday_number * 10 + slot.number) || ' hours')::interval,
  'finished',
  1,
  0
from public.matchdays as matchday
cross join lateral generate_series(1, 2) as slot(number)
where matchday.stage = 'league_phase'
  and matchday.matchday_number between 1 and 2;

insert into public.matches (
  matchday_id,
  home_team_id,
  away_team_id,
  kickoff_at,
  status,
  home_score,
  away_score
)
select
  matchday.id,
  current_setting('test.team_a')::bigint,
  current_setting('test.team_b')::bigint,
  timestamptz '2026-10-01 18:00+00',
  'finished',
  2,
  1
from public.matchdays as matchday
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

select set_config('test.match_' || ordered.position::text, ordered.id::text, true)
from (
  select
    match_row.id,
    row_number() over (
      order by matchday.matchday_number, match_row.kickoff_at, match_row.id
    ) as position
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 3
) as ordered;

update public.profiles as profile
set status = 'disabled'
where profile.status = 'active';

-- 1 admin with no Matchday 1-2 prediction: active, but not eligible.
select pg_temp.elig_add_player(1, 'zzadmin');
update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.elig_user_id(1);

-- Eight eligible players. Stats decide ranks 1-6. Ranks 7-8 share every
-- stat and are separated by user_id after a case-insensitive username tie.
select pg_temp.elig_add_player(2, 'zzranka');
select pg_temp.elig_add_player(3, 'zzrankb');
select pg_temp.elig_add_player(4, 'zzrankc');
select pg_temp.elig_add_player(5, 'zzrankd');
select pg_temp.elig_add_player(6, 'zzranke');
select pg_temp.elig_add_player(7, 'zzrankf');
select pg_temp.elig_add_player(8, 'zztie');
select pg_temp.elig_add_player(9, 'ZZTIE');

-- Active, zero Matchday 1-2 predictions.
select pg_temp.elig_add_player(10, 'zzeligzero');

-- Disabled, with a Matchday 1 prediction.
select pg_temp.elig_add_player(11, 'zzeligoff');

-- Active, prediction only on Matchday 3.
select pg_temp.elig_add_player(12, 'zzeligmd3');

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
values
  (pg_temp.elig_user_id(2), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.elig_user_id(2), current_setting('test.match_2')::bigint, 1, 0, 5),
  (pg_temp.elig_user_id(3), current_setting('test.match_1')::bigint, 1, 0, 10),
  (pg_temp.elig_user_id(4), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.elig_user_id(4), current_setting('test.match_2')::bigint, 2, 0, 2),
  (pg_temp.elig_user_id(4), current_setting('test.match_3')::bigint, 2, 0, 2),
  (pg_temp.elig_user_id(5), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.elig_user_id(5), current_setting('test.match_2')::bigint, 2, 0, 4),
  (pg_temp.elig_user_id(6), current_setting('test.match_1')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(6), current_setting('test.match_2')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(6), current_setting('test.match_3')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(6), current_setting('test.match_4')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(7), current_setting('test.match_1')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(8), current_setting('test.match_3')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(9), current_setting('test.match_3')::bigint, 0, 1, 0),
  (pg_temp.elig_user_id(11), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.elig_user_id(12), current_setting('test.match_5')::bigint, 2, 1, 10);

update public.profiles as profile
set status = 'disabled'
where profile.id = pg_temp.elig_user_id(11);

select pg_temp.elig_assert(
  (
    select
      prosecdef
      and provolatile = 's'
      and prolang = (select lang.oid from pg_language as lang where lang.lanname = 'sql')
      and exists (
        select 1
        from unnest(coalesce(routine.proconfig, array[]::text[])) as config_item
        where config_item like 'search_path=%'
          and config_item not like '%public%'
      )
    from pg_proc as routine
    join pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.proname = 'players_cup_ranking'
      and pg_get_function_identity_arguments(routine.oid) = ''
  ),
  'players_cup_ranking stays sql, stable, security definer, search_path empty'
);

select pg_temp.elig_assert(
  has_function_privilege('service_role', 'public.players_cup_ranking()', 'execute')
  and not has_function_privilege('anon', 'public.players_cup_ranking()', 'execute')
  and not has_function_privilege('authenticated', 'public.players_cup_ranking()', 'execute')
  and not has_function_privilege('public', 'public.players_cup_ranking()', 'execute'),
  'execute stays granted only to service_role'
);

select pg_temp.elig_assert(
  position(
    'total_points > 0' in pg_get_functiondef('public.players_cup_ranking()'::regprocedure)
  ) = 0,
  'eligibility is not implemented as total_points > 0'
);

select pg_temp.elig_assert(
  (
    select count(*)
    from public.players_cup_ranking() as ranking
  ) = 8,
  'exactly eight players are eligible'
);

select pg_temp.elig_assert(
  not exists (
    select 1
    from public.players_cup_ranking() as ranking
    where ranking.username in ('zzadmin', 'zzeligzero', 'zzeligoff', 'zzeligmd3')
  ),
  'zero-prediction, disabled and Matchday 3-only players are excluded'
);

select pg_temp.elig_assert(
  (
    select
      array_agg(ranking.username order by ranking.rank_position)
      = array[
        'zzranka',
        'zzrankb',
        'zzrankc',
        'zzrankd',
        'zzranke',
        'zzrankf',
        'zztie',
        'ZZTIE'
      ]
      and array_agg(ranking.rank_position order by ranking.rank_position)
        = array[1, 2, 3, 4, 5, 6, 7, 8]
      and count(distinct ranking.rank_position) = 8
    from public.players_cup_ranking() as ranking
  ),
  'tie-break order is unchanged and ranks are contiguous from 1'
);

select pg_temp.elig_assert(
  (
    select
      ranking.total_points = 0
      and ranking.exact_scores = 0
      and ranking.correct_results = 0
      and ranking.missed_predictions = 3
      and ranking.rank_position = 6
    from public.players_cup_ranking() as ranking
    where ranking.username = 'zzrankf'
  ),
  'one Matchday 1 prediction scored 0 points is still eligible'
);

select pg_temp.elig_assert(
  (
    select ranking.rank_position = 7
    from public.players_cup_ranking() as ranking
    where ranking.username = 'zztie'
  )
  and (
    select
      ranking.total_points = 0
      and ranking.missed_predictions = 3
      and ranking.rank_position = 8
    from public.players_cup_ranking() as ranking
    where ranking.username = 'ZZTIE'
  ),
  'one Matchday 2 prediction is eligible and user_id breaks the username tie'
);

select pg_temp.elig_assert(
  (
    select ranking.missed_predictions = 0 and ranking.total_points = 0
    from public.players_cup_ranking() as ranking
    where ranking.username = 'zzranke'
  ),
  'a player who predicted every Matchday 1-2 match for 0 points stays eligible'
);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.elig_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

set local role authenticated;

select set_config('test.preview', result::text, true)
from public.create_players_cup(true) as result;

select pg_temp.elig_assert(
  (select count(*) from public.cup_competitions) = 0
  and (select count(*) from public.cup_participants) = 0
  and (select count(*) from public.cup_rounds) = 0
  and (select count(*) from public.cup_ties) = 0,
  'the dry run writes nothing'
);

select pg_temp.elig_assert(
  (
    select
      (preview->>'eligible_count')::integer = 8
      and (preview->>'participant_count')::integer = 8
      and (preview->>'dry_run')::boolean
      and jsonb_array_length(preview->'participants') = 8
    from (
      select current_setting('test.preview')::jsonb as preview
    ) as wrapped
  ),
  'the dry run reports eight eligible participants'
);

select pg_temp.elig_assert(
  (
    select
      array_agg((listed.entry->>'user_id')::uuid order by (listed.entry->>'rank_position')::integer)
      = array[
        pg_temp.elig_user_id(2),
        pg_temp.elig_user_id(3),
        pg_temp.elig_user_id(4),
        pg_temp.elig_user_id(5),
        pg_temp.elig_user_id(6),
        pg_temp.elig_user_id(7),
        pg_temp.elig_user_id(8),
        pg_temp.elig_user_id(9)
      ]
      and array_agg((listed.entry->>'rank_position')::integer order by (listed.entry->>'rank_position')::integer)
        = array[1, 2, 3, 4, 5, 6, 7, 8]
      and bool_and(
        (listed.entry->>'bracket_position')::integer
          = (listed.entry->>'rank_position')::integer
      )
      and bool_and((listed.entry->>'is_protected_seed')::boolean)
      and bool_and((listed.entry->>'entry_round')::integer = 4)
    from jsonb_array_elements(
      current_setting('test.preview')::jsonb->'participants'
    ) as listed(entry)
  ),
  'dry-run participants keep contiguous protected ranks'
);

select pg_temp.elig_assert(
  not exists (
    select 1
    from jsonb_array_elements(
      current_setting('test.preview')::jsonb->'participants'
    ) as listed(entry)
    where (listed.entry->>'user_id')::uuid in (
      pg_temp.elig_user_id(1),
      pg_temp.elig_user_id(10),
      pg_temp.elig_user_id(11),
      pg_temp.elig_user_id(12)
    )
  ),
  'excluded players are absent from the dry-run participants'
);

select public.create_players_cup(false);

select pg_temp.elig_assert(
  (
    select count(*)
    from public.cup_participants as participant
  ) = 8
  and (
    select
      min(participant.rank_position) = 1
      and max(participant.rank_position) = 8
      and count(distinct participant.rank_position) = 8
    from public.cup_participants as participant
  )
  and (
    select count(*)
    from public.cup_rounds as round
  ) = 6
  and (
    select count(*)
    from public.cup_ties as tie
  ) = 63
  and (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where round.round_number = 1
      and tie.outcome = 'bye'
  ) = 8
  and not exists (
    select 1
    from public.cup_participants as participant
    where participant.rank_position <= 8
      and participant.bracket_position <> participant.rank_position
  )
  and not exists (
    select 1
    from public.cup_participants as participant
    where participant.username_snapshot in (
      'zzadmin',
      'zzeligzero',
      'zzeligoff',
      'zzeligmd3'
    )
  ),
  'a real creation writes only the eight eligible players into a valid bracket'
);

reset role;
rollback;

do $check$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username in (
      'zzadmin',
      'zzranka',
      'zzrankf',
      'zztie',
      'ZZTIE',
      'zzeligzero',
      'zzeligoff',
      'zzeligmd3'
    )
  ) then
    raise exception 'PLAYERS CUP ELIGIBILITY TEST FAILED: rollback left eligibility profiles behind';
  end if;

  if exists (
    select 1
    from public.cup_participants as participant
    where participant.username_snapshot in ('zzranka', 'zzrankf', 'zztie', 'ZZTIE')
  ) then
    raise exception 'PLAYERS CUP ELIGIBILITY TEST FAILED: rollback left cup participants behind';
  end if;

  if exists (
    select 1
    from public.teams as team
    where team.name in ('ZZ Cup Eligibility A', 'ZZ Cup Eligibility B')
  ) then
    raise exception 'PLAYERS CUP ELIGIBILITY TEST FAILED: rollback left eligibility teams behind';
  end if;
end;
$check$;

select 'players_cup_eligibility_ok' as result;
