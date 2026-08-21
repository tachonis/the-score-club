-- Transactional Players Cup (phase 1) verification against the hosted schema.
-- The fixture builds its own players, matchdays, matches and predictions so the
-- participant count is fully controlled, and every mutation is rolled back at
-- the end. Run it as the project owner (the Supabase SQL editor session), which
-- is the same requirement as the Golden Match and long-term fixtures.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.cup_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'PLAYERS CUP TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.cup_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad(p_index::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.cup_add_player(
  p_index integer,
  p_username text default null
)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.cup_user_id(p_index);
begin
  -- The auth trigger creates the matching active player profile.
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'players-cup-test-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object(
      'username',
      coalesce(p_username, 'zzcup' || lpad(p_index::text, 3, '0'))
    )
  );

  return v_user_id;
end;
$helper$;

create function pg_temp.cup_add_players(p_from integer, p_to integer)
returns integer
language plpgsql
as $helper$
declare
  v_index integer;
begin
  for v_index in p_from..p_to loop
    perform pg_temp.cup_add_player(v_index);
  end loop;

  return p_to - p_from + 1;
end;
$helper$;

create function pg_temp.cup_id()
returns bigint
language sql
stable
as $helper$
  select competition.id
  from public.cup_competitions as competition
  where competition.slug = 'players-cup-2026-27';
$helper$;

create function pg_temp.cup_rank_of(p_index integer)
returns integer
language sql
stable
as $helper$
  select participant.rank_position
  from public.cup_participants as participant
  where participant.user_id = pg_temp.cup_user_id(p_index);
$helper$;

-- Rank position to occupied bracket position, which is what the draw decides
-- for everyone outside the protected top 8.
create function pg_temp.cup_placement_fingerprint()
returns text
language sql
stable
as $helper$
  select string_agg(
    participant.rank_position || '@' || participant.bracket_position,
    ',' order by participant.rank_position
  )
  from public.cup_participants as participant;
$helper$;

create function pg_temp.cup_bracket_fingerprint()
returns text
language sql
stable
as $helper$
  select string_agg(
    format(
      '%s:%s:%s-%s:%s',
      round.round_number,
      tie.slot,
      coalesce(home_participant.rank_position::text, '-'),
      coalesce(away_participant.rank_position::text, '-'),
      tie.outcome
    ),
    '|' order by round.round_number, tie.slot
  )
  from public.cup_ties as tie
  join public.cup_rounds as round
    on round.id = tie.round_id
  left join public.cup_participants as home_participant
    on home_participant.id = tie.home_participant_id
  left join public.cup_participants as away_participant
    on away_participant.id = tie.away_participant_id;
$helper$;

-- The participant payload the RPC hands to the draw, so the draw can be
-- replayed on its own with any draw seed.
create function pg_temp.cup_participants_json(p_count integer)
returns jsonb
language sql
stable
as $helper$
  select jsonb_agg(
    jsonb_build_object(
      'rank_position', ranking.rank_position,
      'user_id', ranking.user_id
    )
    order by ranking.rank_position
  )
  from public.players_cup_ranking() as ranking
  where ranking.rank_position <= p_count;
$helper$;

-- Ranking only, with the drawn placement deliberately left out, so ranking
-- isolation can be checked independently of the draw.
create function pg_temp.cup_preview_ranking(p_preview jsonb)
returns text
language sql
immutable
as $helper$
  select string_agg(
    (listed.entry->>'rank_position') || ':' || (listed.entry->>'username'),
    ',' order by (listed.entry->>'rank_position')::integer
  )
  from jsonb_array_elements(p_preview->'participants') as listed(entry);
$helper$;

create function pg_temp.cup_draw_fingerprint(
  p_draw_seed uuid,
  p_participants jsonb
)
returns text
language sql
stable
as $helper$
  select string_agg(
    placement.rank_position || '@' || placement.bracket_position,
    ',' order by placement.rank_position
  )
  from public.players_cup_draw(p_draw_seed, p_participants) as placement;
$helper$;

-- Structural invariants that must hold for every created bracket, whatever the
-- participant count is.
create function pg_temp.cup_assert_bracket(p_participants integer)
returns void
language plpgsql
as $helper$
declare
  v_cup_id bigint := pg_temp.cup_id();
  v_expected_real integer := greatest(0, p_participants - 32);
  v_expected_bye integer;
  v_expected_empty integer;
begin
  v_expected_bye := p_participants - 2 * v_expected_real;
  v_expected_empty := 32 - v_expected_real - v_expected_bye;

  perform pg_temp.cup_assert(
    v_cup_id is not null,
    'the competition row exists'
  );

  perform pg_temp.cup_assert(
    (
      select competition.participant_count
      from public.cup_competitions as competition
      where competition.id = v_cup_id
    ) = p_participants,
    format('participant_count is %s', p_participants)
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from public.cup_participants as participant
      where participant.cup_id = v_cup_id
    ) = p_participants,
    'one participant row per player'
  );

  perform pg_temp.cup_assert(
    (
      select
        count(distinct participant.rank_position) = p_participants
        and min(participant.rank_position) = 1
        and max(participant.rank_position) = p_participants
      from public.cup_participants as participant
      where participant.cup_id = v_cup_id
    ),
    'rank positions form a strict 1..N sequence without gaps or duplicates'
  );

  perform pg_temp.cup_assert(
    (
      select
        count(distinct participant.bracket_position) = p_participants
        and min(participant.bracket_position) = 1
        and max(participant.bracket_position) = p_participants
      from public.cup_participants as participant
      where participant.cup_id = v_cup_id
    ),
    'bracket positions form a strict 1..N sequence without gaps or duplicates'
  );

  -- Only the top 8 are tournament seeds, and they are pinned.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_participants as participant
      where participant.cup_id = v_cup_id
        and participant.rank_position <= 8
        and participant.bracket_position <> participant.rank_position
    ),
    'rank positions 1 to 8 keep their protected bracket positions'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_participants as participant
      join public.players_cup_entry_rounds(p_participants) as entitlement
        on entitlement.bracket_position = participant.bracket_position
      where participant.cup_id = v_cup_id
        and participant.entry_round <> entitlement.entry_round
    ),
    'the frozen entry round matches the template entitlement of the drawn position'
  );

  -- The draw may shuffle inside an entitlement group but never across one.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_participants as higher
      join public.cup_participants as lower
        on lower.cup_id = higher.cup_id
        and lower.rank_position > higher.rank_position
      where higher.cup_id = v_cup_id
        and lower.entry_round > higher.entry_round
    ),
    'no lower-ranked player enters the Cup later than a higher-ranked player'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_participants as participant
      join public.profiles as profile
        on profile.id = participant.user_id
      where participant.cup_id = v_cup_id
        and participant.username_snapshot <> profile.username
    ),
    'username_snapshot matches the username frozen at creation'
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from public.cup_rounds as round
      where round.cup_id = v_cup_id
    ) = 6,
    'the Cup has exactly six rounds'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_rounds as round
      join public.matchdays as matchday
        on matchday.id = round.matchday_id
      where round.cup_id = v_cup_id
        and (
          matchday.stage <> 'league_phase'
          or matchday.matchday_number <> round.round_number + 2
        )
    ),
    'rounds 1 to 6 map to League Phase Matchdays 3 to 8'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_rounds as round
      where round.cup_id = v_cup_id
        and round.slot_count <> case round.round_number
          when 1 then 64
          when 2 then 32
          when 3 then 16
          when 4 then 8
          when 5 then 4
          else 2
        end
    ),
    'every round carries the expected slot count'
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from public.cup_ties as tie
      where tie.cup_id = v_cup_id
    ) = 63,
    'the bracket skeleton holds all 63 ties'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_rounds as round
      where round.cup_id = v_cup_id
        and (
          select count(*)
          from public.cup_ties as tie
          where tie.round_id = round.id
        ) <> round.slot_count / 2
    ),
    'each round holds slot_count / 2 ties'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      where round.cup_id = v_cup_id
        and (tie.slot < 1 or tie.slot > round.slot_count / 2)
    ),
    'every tie slot stays inside its round'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      where round.cup_id = v_cup_id
        and round.round_number > 1
        and (
          tie.home_participant_id is not null
          or tie.away_participant_id is not null
          or tie.winner_participant_id is not null
          or tie.outcome <> 'empty'
          or tie.decided_by_rule is not null
          or tie.home_points <> 0
          or tie.away_points <> 0
          or tie.home_exact <> 0
          or tie.away_exact <> 0
          or tie.home_correct <> 0
          or tie.away_correct <> 0
        )
    ),
    'rounds 2 to 6 stay unpopulated and unscored in phase 1'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from (
        select tie.round_id, tie.home_participant_id as participant_id
        from public.cup_ties as tie
        where tie.cup_id = v_cup_id
          and tie.home_participant_id is not null
        union all
        select tie.round_id, tie.away_participant_id
        from public.cup_ties as tie
        where tie.cup_id = v_cup_id
          and tie.away_participant_id is not null
      ) as side
      group by side.round_id, side.participant_id
      having count(*) > 1
    ),
    'no participant appears twice inside the same round'
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from (
        select tie.home_participant_id as participant_id
        from public.cup_ties as tie
        join public.cup_rounds as round
          on round.id = tie.round_id
        where round.cup_id = v_cup_id
          and round.round_number = 1
          and tie.home_participant_id is not null
        union all
        select tie.away_participant_id
        from public.cup_ties as tie
        join public.cup_rounds as round
          on round.id = tie.round_id
        where round.cup_id = v_cup_id
          and round.round_number = 1
          and tie.away_participant_id is not null
      ) as placed
    ) = p_participants,
    'every participant occupies exactly one round 1 slot'
  );

  perform pg_temp.cup_assert(
    (
      select
        count(*) filter (where tie.outcome = 'pending') = v_expected_real
        and count(*) filter (where tie.outcome = 'bye') = v_expected_bye
        and count(*) filter (where tie.outcome = 'empty') = v_expected_empty
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      where round.cup_id = v_cup_id
        and round.round_number = 1
    ),
    format(
      'round 1 holds %s real ties, %s byes and %s empty slots',
      v_expected_real,
      v_expected_bye,
      v_expected_empty
    )
  );

  -- The template still decides which positions meet; the draw only decides who
  -- stands in them, so the paired positions still mirror each other.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join public.cup_participants as home_participant
        on home_participant.id = tie.home_participant_id
      join public.cup_participants as away_participant
        on away_participant.id = tie.away_participant_id
      where round.cup_id = v_cup_id
        and round.round_number = 1
        and home_participant.bracket_position
          + away_participant.bracket_position <> 65
    ),
    'round 1 pairs occupy mirrored template positions'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join public.cup_participants as participant
        on participant.id in (tie.home_participant_id, tie.away_participant_id)
      where round.cup_id = v_cup_id
        and round.round_number = 1
        and (
          (tie.outcome = 'pending' and participant.entry_round <> 1)
          or (tie.outcome = 'bye' and participant.entry_round = 1)
        )
    ),
    'only players whose entry round is Matchday 3 contest a real round 1 tie'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      where round.cup_id = v_cup_id
        and round.round_number = 1
        and tie.outcome = 'bye'
        and tie.winner_participant_id is distinct from coalesce(
          tie.home_participant_id,
          tie.away_participant_id
        )
    ),
    'a bye promotes its only participant'
  );

  perform pg_temp.cup_assert(
    coalesce(
      (
        select max(participant.rank_position)
        from public.cup_ties as tie
        join public.cup_rounds as round
          on round.id = tie.round_id
        join public.cup_participants as participant
          on participant.id = tie.winner_participant_id
        where round.cup_id = v_cup_id
          and round.round_number = 1
          and tie.outcome = 'bye'
      ),
      0
    ) = v_expected_bye,
    format('byes go to ranking positions 1 to %s', v_expected_bye)
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      where round.cup_id = v_cup_id
        and round.round_number = 1
        and tie.outcome = 'pending'
        and tie.winner_participant_id is not null
    ),
    'a real round 1 tie has no winner in phase 1'
  );
end;
$helper$;

-- ---------------------------------------------------------------------------
-- Deterministic fixture
-- ---------------------------------------------------------------------------

insert into public.teams (name, short_name)
values
  ('ZZ Players Cup Test A', 'ZCA'),
  ('ZZ Players Cup Test B', 'ZCB')
on conflict (name) do nothing;

select set_config(
  'test.team_a',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup Test A'
  ),
  true
);
select set_config(
  'test.team_b',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup Test B'
  ),
  true
);

insert into public.matchdays (stage, matchday_number, name)
select
  'league_phase',
  generated.number,
  generated.number || 'η αγωνιστική'
from generate_series(1, 8) as generated(number)
on conflict (stage, matchday_number) do nothing;

-- Matchday 1 and 2 hold exactly the six finished matches created below, so the
-- ranking inputs are fully known.
delete from public.matches as match_row
using public.matchdays as matchday
where matchday.id = match_row.matchday_id
  and matchday.stage = 'league_phase'
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
  timestamptz '2026-09-01 20:00+00'
    + (matchday.matchday_number * 24 + slot.number || ' hours')::interval,
  'finished',
  1,
  0
from public.matchdays as matchday
cross join lateral generate_series(
  1,
  case when matchday.matchday_number = 1 then 4 else 2 end
) as slot(number)
where matchday.stage = 'league_phase'
  and matchday.matchday_number between 1 and 2;

select set_config(
  'test.match_' || ordered.position::text,
  ordered.id::text,
  true
)
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
    and matchday.matchday_number between 1 and 2
) as ordered;

-- Only the synthetic players stay active, so every scenario controls N exactly.
update public.profiles as profile
set status = 'disabled'
where profile.status = 'active';

select pg_temp.cup_add_player(1);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.cup_user_id(1);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0,
  'the fixture starts without a Cup'
);

-- ---------------------------------------------------------------------------
-- 1. Position template and entitlement grouping
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  (select count(*) from public.players_cup_bracket_slots(64)) = 64
  and (
    select count(distinct slot_template.bracket_position)
    from public.players_cup_bracket_slots(64) as slot_template
  ) = 64
  and (
    select count(distinct slot_template.fold_position)
    from public.players_cup_bracket_slots(64) as slot_template
  ) = 64,
  'the template returns 64 distinct fold positions and bracket positions'
);

select pg_temp.cup_assert(
  (
    select array_agg(
      slot_template.bracket_position order by slot_template.fold_position
    )
    from public.players_cup_bracket_slots(64) as slot_template
  )[1:8] = array[1, 64, 32, 33, 16, 49, 17, 48],
  'the template opens with positions 1-64, 32-33, 16-49 and 17-48'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.players_cup_bracket_slots(64) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
    having sum(slot_template.bracket_position) <> 65
  ),
  'every round 1 position pair sums to 65'
);

-- Two protected positions must not share a round 3 merge group, which is what
-- keeps the top 8 apart until the quarter-finals.
select pg_temp.cup_assert(
  not exists (
    select 1
    from public.players_cup_bracket_slots(64) as protected_slot
    join public.players_cup_bracket_slots(64) as other_slot
      on other_slot.bracket_position > protected_slot.bracket_position
      and (other_slot.fold_position - 1) / 8
        = (protected_slot.fold_position - 1) / 8
    where protected_slot.bracket_position <= 8
      and other_slot.bracket_position <= 8
  ),
  'no two protected positions can meet before the quarter-finals'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from (
      select (slot_template.fold_position - 1) / 16 as quarter
      from public.players_cup_bracket_slots(64) as slot_template
      where slot_template.bracket_position <= 8
      group by (slot_template.fold_position - 1) / 16
      having count(*) = 2
    ) as quarter_final
  ) = 4,
  'the eight protected positions split into four quarter-final pairs'
);

-- The draw relies on the template ranking its own positions by entitlement:
-- position 1 must always carry the best entry round and position N the worst.
select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(8, 64) as field(size)
    cross join lateral (
      select
        entitlement.bracket_position,
        row_number() over (
          order by entitlement.entry_round desc, entitlement.bracket_position
        ) as entitlement_order
      from public.players_cup_entry_rounds(field.size) as entitlement
    ) as ordered
    where ordered.bracket_position <> ordered.entitlement_order
  ),
  'for every field size from 8 to 64 the template orders entitlement by position'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(8, 64) as field(size)
    where (
      select count(*)
      from public.players_cup_entry_rounds(field.size) as entitlement
    ) <> field.size
  ),
  'every occupied position receives an entry round for every field size'
);

-- ---------------------------------------------------------------------------
-- 2. Security
-- ---------------------------------------------------------------------------

savepoint security_tests;

select pg_temp.cup_add_players(2, 12);

-- The temp schema is not readable by the authenticated or anon roles, so every
-- pg_temp helper runs before the role switch.
select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);

set local role authenticated;

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: a player created the Cup';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

reset role;

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);

set local role anon;

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: anon created the Cup';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

update public.profiles as profile
set status = 'disabled'
where profile.id = pg_temp.cup_user_id(1);

set local role authenticated;

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: a disabled admin created the Cup';
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
set status = 'active'
where profile.id = pg_temp.cup_user_id(1);

-- The successful creation runs through the authenticated role, so the grant
-- path is exercised exactly as the browser would use it.
set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_assert_bracket(12);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);

set local role authenticated;

do $test$
begin
  if (select count(*) from public.cup_competitions) <> 1
    or (select count(*) from public.cup_participants) <> 12
    or (select count(*) from public.cup_rounds) <> 6
    or (select count(*) from public.cup_ties) <> 63
  then
    raise exception 'PLAYERS CUP TEST FAILED: a player cannot read the Cup';
  end if;
end;
$test$;

do $test$
begin
  begin
    insert into public.cup_competitions (
      slug,
      season_label,
      participant_count
    )
    values ('player-made-cup', 'Fake', 12);
    raise exception 'PLAYERS CUP TEST FAILED: a player inserted a competition';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_ties as tie
    set winner_participant_id = tie.home_participant_id;
    raise exception 'PLAYERS CUP TEST FAILED: a player assigned a Cup winner';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_ties as tie
    set outcome = 'decided', home_points = 99;
    raise exception 'PLAYERS CUP TEST FAILED: a player changed Cup scores';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_participants as participant
    set rank_position = 1;
    raise exception 'PLAYERS CUP TEST FAILED: a player changed a rank position';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_competitions as competition
    set winner_points = 500;
    raise exception 'PLAYERS CUP TEST FAILED: a player changed reward config';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.cup_ties;
    raise exception 'PLAYERS CUP TEST FAILED: a player deleted Cup ties';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_ranking();
    raise exception 'PLAYERS CUP TEST FAILED: a player read the Cup ranking';
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
    perform 1 from public.cup_ties;
    raise exception 'PLAYERS CUP TEST FAILED: anon read the Cup bracket';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform 1 from public.cup_competitions;
    raise exception 'PLAYERS CUP TEST FAILED: anon read the Cup competition';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);

rollback to savepoint security_tests;

-- ---------------------------------------------------------------------------
-- 3. Minimum and maximum participants
-- ---------------------------------------------------------------------------

savepoint minimum_tests;

select pg_temp.cup_add_players(2, 7);

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: seven players created a Cup';
  exception
    when invalid_parameter_value then
      if sqlerrm not like 'The Players Cup needs at least 8 active players%' then
        raise;
      end if;
  end;
end;
$test$;

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0,
  'a rejected creation writes nothing'
);

select pg_temp.cup_add_player(8);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(8);

rollback to savepoint minimum_tests;

savepoint maximum_tests;

select pg_temp.cup_add_players(2, 70);
select public.create_players_cup(true);

select pg_temp.cup_assert(
  (
    select (result->>'eligible_count')::integer = 70
      and (result->>'participant_count')::integer = 64
      and (result->>'excluded_count')::integer = 6
      and jsonb_array_length(result->'excluded') = 6
    from public.create_players_cup(true) as result
  ),
  'the dry run reports 70 eligible players, 64 participants and 6 excluded'
);

select public.create_players_cup();
select pg_temp.cup_assert_bracket(64);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_participants as participant
    where participant.username_snapshot in (
      'zzcup065', 'zzcup066', 'zzcup067', 'zzcup068', 'zzcup069', 'zzcup070'
    )
  ) = 0,
  'the six lowest ranked players are excluded deterministically'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_participants as participant
    where participant.rank_position <= 64
      and participant.username_snapshot = 'zzcup' || lpad(participant.rank_position::text, 3, '0')
  ) = 64,
  'the top 64 keep their strict ranking order'
);

rollback to savepoint maximum_tests;

-- ---------------------------------------------------------------------------
-- 4. Strict ranking order
-- ---------------------------------------------------------------------------

savepoint ranking_tests;

select pg_temp.cup_add_players(2, 8);

-- zzcup007: 5 + 5   -> 10 points, 2 exact
-- zzcup008: 10      -> 10 points, 1 exact
-- zzcup006: 5 + 2 + 2 -> 9 points, 1 exact, 2 correct
-- zzcup005: 5 + 4   -> 9 points, 1 exact, 1 correct
-- zzcup004: six wrong predictions -> 0 points, 0 missed
-- zzcup001-003: no predictions at all -> 0 points, 6 missed
insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
values
  (pg_temp.cup_user_id(7), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.cup_user_id(7), current_setting('test.match_2')::bigint, 1, 0, 5),
  (pg_temp.cup_user_id(8), current_setting('test.match_1')::bigint, 1, 0, 10),
  (pg_temp.cup_user_id(6), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.cup_user_id(6), current_setting('test.match_2')::bigint, 2, 0, 2),
  (pg_temp.cup_user_id(6), current_setting('test.match_3')::bigint, 2, 0, 2),
  (pg_temp.cup_user_id(5), current_setting('test.match_1')::bigint, 1, 0, 5),
  (pg_temp.cup_user_id(5), current_setting('test.match_2')::bigint, 2, 0, 4);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
select
  pg_temp.cup_user_id(4),
  current_setting('test.match_' || generated.number::text)::bigint,
  0,
  3,
  0
from generate_series(1, 6) as generated(number);

select public.create_players_cup();

select pg_temp.cup_assert_bracket(8);

select pg_temp.cup_assert(
  (
    select array_agg(participant.username_snapshot order by participant.rank_position)
    from public.cup_participants as participant
  ) = array[
    'zzcup007',
    'zzcup008',
    'zzcup006',
    'zzcup005',
    'zzcup004',
    'zzcup001',
    'zzcup002',
    'zzcup003'
  ],
  'ranking orders by points, exact scores, correct results, then missed predictions'
);

rollback to savepoint ranking_tests;

savepoint ranking_isolation_tests;

select pg_temp.cup_add_players(2, 12);

select set_config(
  'test.baseline_ranking',
  (
    select pg_temp.cup_preview_ranking(result)
    from public.create_players_cup(true) as result
  ),
  true
);

select pg_temp.cup_assert(
  (
    select pg_temp.cup_preview_ranking(result) = current_setting('test.baseline_ranking')
    from public.create_players_cup(true) as result
  ),
  'two identical dry runs produce the identical ranking'
);

-- Preview draws are throwaway by design; only the seed stored by the real
-- creation describes the real bracket.
select pg_temp.cup_assert(
  (select result->>'draw_seed' from public.create_players_cup(true) as result)
  <> (select result->>'draw_seed' from public.create_players_cup(true) as result),
  'each dry run generates its own throwaway preview draw seed'
);

-- Matchday 3 results must not move a rank position.
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
  timestamptz '2026-10-01 20:00+00',
  'finished',
  2,
  1
from public.matchdays as matchday
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
select
  pg_temp.cup_user_id(12),
  match_row.id,
  2,
  1,
  10
from public.matches as match_row
join public.matchdays as matchday
  on matchday.id = match_row.matchday_id
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

select pg_temp.cup_assert(
  (
    select pg_temp.cup_preview_ranking(result) = current_setting('test.baseline_ranking')
    from public.create_players_cup(true) as result
  ),
  'Matchday 3 points do not affect the Cup ranking'
);

-- Long-term awards must not move a rank position either.
insert into public.long_term_predictions (user_id, prediction_type, team_id)
values (
  pg_temp.cup_user_id(12),
  'winner',
  current_setting('test.team_a')::bigint
);

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values (
  pg_temp.cup_user_id(12),
  'winner',
  current_setting('test.team_a')::bigint,
  current_setting('test.team_a')::bigint,
  30
);

select pg_temp.cup_assert(
  (
    select pg_temp.cup_preview_ranking(result) = current_setting('test.baseline_ranking')
    from public.create_players_cup(true) as result
  ),
  'long-term award points do not affect the Cup ranking'
);

rollback to savepoint ranking_isolation_tests;

savepoint ranking_tie_break_tests;

select pg_temp.cup_add_players(2, 8);
select pg_temp.cup_add_player(90, 'zztie');
select pg_temp.cup_add_player(91, 'ZZTIE');

select public.create_players_cup();

select pg_temp.cup_assert(
  pg_temp.cup_rank_of(90) = 9 and pg_temp.cup_rank_of(91) = 10,
  'usernames that differ only by case are ordered by user_id'
);

rollback to savepoint ranking_tie_break_tests;

-- ---------------------------------------------------------------------------
-- 5. Byes across the required participant counts
-- ---------------------------------------------------------------------------

savepoint bye_tests_8;
select pg_temp.cup_add_players(2, 8);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(8);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_participants as participant
    where participant.rank_position <= 8
      and participant.bracket_position = participant.rank_position
  ) = 8,
  'with 8 players every participant is a protected seed in its own position'
);

select pg_temp.cup_assert(
  (
    select count(*) filter (where participant.entry_round = 4)
    from public.cup_participants as participant
  ) = 8,
  'with 8 players the first real Cup round is the Matchday 6 quarter-final'
);

rollback to savepoint bye_tests_8;

savepoint bye_tests_17;
select pg_temp.cup_add_players(2, 17);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(17);

-- The fixed template gives ranks 1 to 15 an extra round of automatic
-- advancement; only the two lowest ranked entrants start at Matchday 4.
select pg_temp.cup_assert(
  (
    select count(*) filter (where participant.rank_position <= 15 and participant.entry_round = 3) = 15
      and count(*) filter (where participant.rank_position > 15 and participant.entry_round = 2) = 2
    from public.cup_participants as participant
  ),
  '17 players split into ranks 1-15 entering at Matchday 5 and ranks 16-17 at Matchday 4'
);

select pg_temp.cup_assert(
  (
    select array_agg(
      participant.bracket_position order by participant.bracket_position
    )
    from public.cup_participants as participant
    where participant.rank_position between 9 and 15
  ) = (select array_agg(generated.number) from generate_series(9, 15) as generated(number))
  and (
    select array_agg(
      participant.bracket_position order by participant.bracket_position
    )
    from public.cup_participants as participant
    where participant.rank_position between 16 and 17
  ) = (select array_agg(generated.number) from generate_series(16, 17) as generated(number)),
  'the 17 player draw never moves a player out of its entitlement group'
);

rollback to savepoint bye_tests_17;

savepoint bye_tests_32;
select pg_temp.cup_add_players(2, 32);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(32);
rollback to savepoint bye_tests_32;

savepoint bye_tests_33;
select pg_temp.cup_add_players(2, 33);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(33);
rollback to savepoint bye_tests_33;

savepoint bye_tests_63;
select pg_temp.cup_add_players(2, 63);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(63);
rollback to savepoint bye_tests_63;

savepoint bye_tests_64;
select pg_temp.cup_add_players(2, 64);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(64);

select pg_temp.cup_assert(
  (
    select count(*) filter (where tie.outcome = 'pending') = 32
      and count(*) filter (where tie.outcome <> 'pending') = 0
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where round.round_number = 1
  )
  and (
    select count(*) filter (where participant.entry_round = 1)
    from public.cup_participants as participant
  ) = 64,
  'a full field of 64 produces 32 real ties and no byes'
);

select pg_temp.cup_assert(
  (
    select array_agg(
      participant.bracket_position order by participant.bracket_position
    )
    from public.cup_participants as participant
    where participant.rank_position > 8
  ) = (select array_agg(generated.number) from generate_series(9, 64) as generated(number)),
  'ranks 9 to 64 are drawn among the 56 unprotected positions'
);

select pg_temp.cup_assert(
  exists (
    select 1
    from public.cup_participants as participant
    where participant.rank_position > 8
      and participant.bracket_position <> participant.rank_position
  ),
  'the 64 player draw actually moves unprotected players'
);

rollback to savepoint bye_tests_64;

-- ---------------------------------------------------------------------------
-- 6. The 40 player example
-- ---------------------------------------------------------------------------

savepoint forty_player_tests;

select pg_temp.cup_add_players(2, 40);
select public.create_players_cup();
select pg_temp.cup_assert_bracket(40);

select pg_temp.cup_assert(
  (
    select
      count(*) filter (where tie.outcome = 'pending') = 8
      and count(*) filter (where tie.outcome = 'bye') = 24
      and count(*) filter (where tie.outcome = 'empty') = 0
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where round.round_number = 1
  ),
  '40 players produce exactly 8 Matchday 3 ties and 24 byes'
);

select pg_temp.cup_assert(
  (
    select array_agg(participant.rank_position order by participant.rank_position)
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    join public.cup_participants as participant
      on participant.id = tie.winner_participant_id
    where round.round_number = 1
      and tie.outcome = 'bye'
  ) = (select array_agg(generated.number) from generate_series(1, 24) as generated(number)),
  'ranking positions 1 to 24 receive the byes'
);

select pg_temp.cup_assert(
  (
    select array_agg(participant.rank_position order by participant.rank_position)
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    join public.cup_participants as participant
      on participant.id in (tie.home_participant_id, tie.away_participant_id)
    where round.round_number = 1
      and tie.outcome = 'pending'
  ) = (select array_agg(generated.number) from generate_series(25, 40) as generated(number)),
  'ranking positions 25 to 40 contest the eight Matchday 3 ties'
);

select pg_temp.cup_assert(
  (
    select array_agg(
      participant.bracket_position order by participant.bracket_position
    )
    from public.cup_participants as participant
    where participant.rank_position between 9 and 24
  ) = (select array_agg(generated.number) from generate_series(9, 24) as generated(number))
  and (
    select array_agg(
      participant.bracket_position order by participant.bracket_position
    )
    from public.cup_participants as participant
    where participant.rank_position between 25 and 40
  ) = (select array_agg(generated.number) from generate_series(25, 40) as generated(number)),
  'ranks 9-24 are drawn among the bye positions and ranks 25-40 among the tie positions'
);

select pg_temp.cup_assert(
  (
    select count(*) filter (where participant.rank_position <= 24 and participant.entry_round = 2) = 24
      and count(*) filter (where participant.rank_position > 24 and participant.entry_round = 1) = 16
    from public.cup_participants as participant
  ),
  'ranks 1-24 enter at Matchday 4 and ranks 25-40 at Matchday 3'
);

select pg_temp.cup_assert(
  exists (
    select 1
    from public.cup_participants as participant
    where participant.rank_position > 8
      and participant.bracket_position <> participant.rank_position
  ),
  'the 40 player draw actually moves unprotected players'
);

rollback to savepoint forty_player_tests;

-- ---------------------------------------------------------------------------
-- 7. Draw reproducibility and fairness under many seeds
-- ---------------------------------------------------------------------------

savepoint draw_tests;

select pg_temp.cup_add_players(2, 40);

select set_config('test.draw_field', pg_temp.cup_participants_json(40)::text, true);

select pg_temp.cup_assert(
  pg_temp.cup_draw_fingerprint(
    '11111111-1111-4111-8111-111111111111',
    current_setting('test.draw_field')::jsonb
  ) = pg_temp.cup_draw_fingerprint(
    '11111111-1111-4111-8111-111111111111',
    current_setting('test.draw_field')::jsonb
  ),
  'the same draw seed and ranking rebuild an identical bracket'
);

select pg_temp.cup_assert(
  (
    select count(distinct pg_temp.cup_draw_fingerprint(
      candidate.draw_seed,
      current_setting('test.draw_field')::jsonb
    ))
    from (values
      ('11111111-1111-4111-8111-111111111111'::uuid),
      ('22222222-2222-4222-8222-222222222222'::uuid),
      ('33333333-3333-4333-8333-333333333333'::uuid),
      ('44444444-4444-4444-8444-444444444444'::uuid),
      ('55555555-5555-4555-8555-555555555555'::uuid)
    ) as candidate(draw_seed)
  ) > 1,
  'different draw seeds produce different draws'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from (values
      ('11111111-1111-4111-8111-111111111111'::uuid),
      ('22222222-2222-4222-8222-222222222222'::uuid),
      ('33333333-3333-4333-8333-333333333333'::uuid),
      ('44444444-4444-4444-8444-444444444444'::uuid),
      ('55555555-5555-4555-8555-555555555555'::uuid)
    ) as candidate(draw_seed)
    cross join lateral public.players_cup_draw(
      candidate.draw_seed,
      current_setting('test.draw_field')::jsonb
    ) as placement
    where placement.rank_position <= 8
      and placement.bracket_position <> placement.rank_position
  ),
  'no draw seed can move a protected top 8 player'
);

-- The entitlement of a rank is the entry round of the position carrying that
-- rank number; a fair draw never lands anyone outside it.
select pg_temp.cup_assert(
  not exists (
    select 1
    from (values
      ('11111111-1111-4111-8111-111111111111'::uuid),
      ('22222222-2222-4222-8222-222222222222'::uuid),
      ('33333333-3333-4333-8333-333333333333'::uuid),
      ('44444444-4444-4444-8444-444444444444'::uuid),
      ('55555555-5555-4555-8555-555555555555'::uuid)
    ) as candidate(draw_seed)
    cross join lateral public.players_cup_draw(
      candidate.draw_seed,
      current_setting('test.draw_field')::jsonb
    ) as placement
    join public.players_cup_entry_rounds(40) as entitled
      on entitled.bracket_position = placement.rank_position
    where placement.entry_round <> entitled.entry_round
  ),
  'no draw seed can move a player out of its entry-round entitlement'
);

select public.create_players_cup();

select pg_temp.cup_assert(
  pg_temp.cup_placement_fingerprint() = pg_temp.cup_draw_fingerprint(
    (select competition.draw_seed from public.cup_competitions as competition),
    current_setting('test.draw_field')::jsonb
  ),
  'the persisted draw_seed replays the persisted placement exactly'
);

select set_config('test.persisted_bracket', pg_temp.cup_bracket_fingerprint(), true);
select set_config(
  'test.persisted_draw_seed',
  (select competition.draw_seed::text from public.cup_competitions as competition),
  true
);

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
  timestamptz '2026-10-01 20:00+00',
  'finished',
  3,
  1
from public.matchdays as matchday
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score,
  points
)
select
  pg_temp.cup_user_id(40),
  match_row.id,
  3,
  1,
  10
from public.matches as match_row
join public.matchdays as matchday
  on matchday.id = match_row.matchday_id
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 3;

update public.profiles as profile
set username = 'aaa_renamed_during_the_cup'
where profile.id = pg_temp.cup_user_id(30);

update public.cup_competitions as competition
set
  winner_points = 100,
  finalist_points = 60,
  semi_finalist_points = 20;

select pg_temp.cup_assert(
  pg_temp.cup_bracket_fingerprint() = current_setting('test.persisted_bracket')
  and (
    select competition.draw_seed::text
    from public.cup_competitions as competition
  ) = current_setting('test.persisted_draw_seed'),
  'Matchday 3 results, renames and reward changes leave the drawn bracket alone'
);

select public.create_players_cup();

select pg_temp.cup_assert(
  pg_temp.cup_bracket_fingerprint() = current_setting('test.persisted_bracket')
  and (
    select competition.draw_seed::text
    from public.cup_competitions as competition
  ) = current_setting('test.persisted_draw_seed'),
  'a repeated creation never redraws the bracket'
);

rollback to savepoint draw_tests;

-- ---------------------------------------------------------------------------
-- 8. Idempotence and regeneration safety
-- ---------------------------------------------------------------------------

savepoint idempotence_tests;

select pg_temp.cup_add_players(2, 20);

select public.create_players_cup(true);
select public.create_players_cup(true);

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0
  and (select count(*) from public.cup_participants) = 0
  and (select count(*) from public.cup_rounds) = 0
  and (select count(*) from public.cup_ties) = 0,
  'a dry run never writes a row'
);

select pg_temp.cup_assert(
  (
    select (result->>'draw_is_preview')::boolean
      and (result->>'draw_seed') is not null
      and jsonb_array_length(result->'top_8_seeded') = 8
      and jsonb_array_length(result->'participants') = 20
      and jsonb_array_length(result->'round_one'->'ties') = 32
    from public.create_players_cup(true) as result
  ),
  'a dry run returns a labelled preview draw seed, the top 8 and the full round 1'
);

select public.create_players_cup();

select set_config(
  'test.first_bracket',
  (
    select string_agg(
      format(
        '%s:%s:%s:%s:%s',
        round.round_number,
        tie.slot,
        coalesce(home_participant.rank_position::text, '-'),
        coalesce(away_participant.rank_position::text, '-'),
        tie.outcome
      ),
      '|' order by round.round_number, tie.slot
    )
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    left join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    left join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
  ),
  true
);

select pg_temp.cup_assert(
  (
    select (result->>'already_exists')::boolean
      and not (result->>'created')::boolean
      and (result->>'cup_id')::bigint = pg_temp.cup_id()
    from public.create_players_cup() as result
  ),
  'a repeated creation reports the existing Cup instead of creating a second one'
);

select pg_temp.cup_assert(
  (
    select (result->>'already_exists')::boolean
      and (result->>'tie_count')::integer = 63
      and not (result->>'draw_is_preview')::boolean
      and (result->>'draw_seed') = (
        select competition.draw_seed::text
        from public.cup_competitions as competition
      )
    from public.create_players_cup(true) as result
  ),
  'a dry run after creation returns the existing Cup and its persisted draw seed'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 1
  and (select count(*) from public.cup_participants) = 20
  and (select count(*) from public.cup_rounds) = 6
  and (select count(*) from public.cup_ties) = 63,
  'repeated calls never duplicate a competition, participant, round or tie'
);

select pg_temp.cup_assert(
  (
    select string_agg(
      format(
        '%s:%s:%s:%s:%s',
        round.round_number,
        tie.slot,
        coalesce(home_participant.rank_position::text, '-'),
        coalesce(away_participant.rank_position::text, '-'),
        tie.outcome
      ),
      '|' order by round.round_number, tie.slot
    )
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    left join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    left join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
  ) = current_setting('test.first_bracket'),
  'the persisted bracket is untouched by repeated calls'
);

-- Concurrent callers are serialized by a transaction advisory lock. Two real
-- sessions cannot be simulated inside one transactional fixture, so the test
-- only proves the lock is taken.
select pg_temp.cup_assert(
  exists (
    select 1
    from pg_locks as lock_row
    where lock_row.locktype = 'advisory'
      and lock_row.pid = pg_backend_pid()
      and lock_row.granted
  ),
  'creation holds a transaction advisory lock'
);

-- A second player registering later cannot join the frozen bracket.
select pg_temp.cup_add_player(21);
select public.create_players_cup();

select pg_temp.cup_assert(
  (select count(*) from public.cup_participants) = 20
  and not exists (
    select 1
    from public.cup_participants as participant
    where participant.user_id = pg_temp.cup_user_id(21)
  ),
  'players registered after creation stay out of the Cup'
);

rollback to savepoint idempotence_tests;

-- ---------------------------------------------------------------------------
-- 9. Reward configuration
-- ---------------------------------------------------------------------------

savepoint reward_tests;

select pg_temp.cup_add_players(2, 12);
select public.create_players_cup();

select pg_temp.cup_assert(
  (
    select competition.winner_points = 50
      and competition.finalist_points = 30
      and competition.semi_finalist_points = 15
    from public.cup_competitions as competition
  ),
  'reward configuration defaults to 50, 30 and 15'
);

do $test$
begin
  begin
    update public.cup_competitions as competition
    set winner_points = -1;
    raise exception 'PLAYERS CUP TEST FAILED: negative rewards were accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.cup_competitions as competition
    set finalist_points = 40;
    raise exception 'PLAYERS CUP TEST FAILED: a finalist out-earned the winner';
  exception
    when check_violation then null;
  end;

  begin
    update public.cup_competitions as competition
    set semi_finalist_points = 25;
    raise exception 'PLAYERS CUP TEST FAILED: a semi-finalist out-earned the finalist';
  exception
    when check_violation then null;
  end;
end;
$test$;

select set_config(
  'test.reward_bracket',
  (
    select string_agg(
      format('%s:%s:%s', round.round_number, tie.slot, tie.outcome),
      '|' order by round.round_number, tie.slot
    )
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
  ),
  true
);

update public.cup_competitions as competition
set
  winner_points = 100,
  finalist_points = 60,
  semi_finalist_points = 20,
  updated_at = now();

select pg_temp.cup_assert(
  (
    select string_agg(
      format('%s:%s:%s', round.round_number, tie.slot, tie.outcome),
      '|' order by round.round_number, tie.slot
    )
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
  ) = current_setting('test.reward_bracket'),
  'reconfiguring rewards to 100, 60 and 20 leaves the bracket untouched'
);

rollback to savepoint reward_tests;

-- ---------------------------------------------------------------------------
-- 10. Deletion safety
-- ---------------------------------------------------------------------------

savepoint deletion_tests;

select pg_temp.cup_add_players(2, 12);
select public.create_players_cup();

select set_config('test.deleted_rank', pg_temp.cup_rank_of(3)::text, true);

delete from auth.users as auth_user
where auth_user.id = pg_temp.cup_user_id(3);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.profiles as profile
    where profile.id = pg_temp.cup_user_id(3)
  ),
  'the profile is gone after the account is deleted'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_participants as participant
  ) = 12
  and (
    select participant.user_id is null
      and participant.username_snapshot = 'zzcup003'
      and participant.rank_position = current_setting('test.deleted_rank')::integer
    from public.cup_participants as participant
    where participant.username_snapshot = 'zzcup003'
  ),
  'a deleted account leaves a frozen participant row behind'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_ties) = 63
  and (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where round.round_number = 1
      and tie.outcome <> 'empty'
  ) = 12,
  'the bracket structure survives the deletion'
);

rollback to savepoint deletion_tests;

-- ---------------------------------------------------------------------------
-- 11. Frozen usernames and ranking preconditions
-- ---------------------------------------------------------------------------

savepoint rename_tests;

select pg_temp.cup_add_players(2, 12);
select public.create_players_cup();

select set_config('test.renamed_rank', pg_temp.cup_rank_of(2)::text, true);

update public.profiles as profile
set username = 'aaa_renamed_after_the_cup'
where profile.id = pg_temp.cup_user_id(2);

select pg_temp.cup_assert(
  (
    select participant.username_snapshot = 'zzcup002'
      and participant.rank_position = current_setting('test.renamed_rank')::integer
    from public.cup_participants as participant
    where participant.user_id = pg_temp.cup_user_id(2)
  ),
  'renaming a player after creation changes neither the snapshot nor the rank position'
);

rollback to savepoint rename_tests;

savepoint precondition_tests;

select pg_temp.cup_add_players(2, 12);

update public.matches as match_row
set status = 'scheduled', home_score = null, away_score = null
where match_row.id = current_setting('test.match_1')::bigint;

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: an unfinished Matchday 1 created a Cup';
  exception
    when invalid_parameter_value then
      if sqlerrm <> 'The Cup ranking requires every League Phase Matchday 1 and 2 match to be finished' then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint precondition_tests;

savepoint missing_matchday_tests;

select pg_temp.cup_add_players(2, 12);

delete from public.matchdays as matchday
where matchday.stage = 'league_phase'
  and matchday.matchday_number = 8;

do $test$
begin
  begin
    perform public.create_players_cup();
    raise exception 'PLAYERS CUP TEST FAILED: a missing Matchday 8 still created a Cup';
  exception
    when object_not_in_prerequisite_state then
      if sqlerrm <> 'League Phase Matchdays 3 to 8 must all exist before the Players Cup can be created' then
        raise;
      end if;
  end;
end;
$test$;

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0,
  'a missing matchday writes nothing'
);

rollback to savepoint missing_matchday_tests;

-- ---------------------------------------------------------------------------
-- 12. Participant and round uniqueness is enforced by the database
-- ---------------------------------------------------------------------------

savepoint uniqueness_tests;

select pg_temp.cup_add_players(2, 40);
select public.create_players_cup();

do $test$
begin
  begin
    update public.cup_participants as participant
    set rank_position = 1
    where participant.rank_position = 2;
    raise exception 'PLAYERS CUP TEST FAILED: two participants shared a rank position';
  exception
    when unique_violation then null;
  end;

  begin
    update public.cup_participants as participant
    set bracket_position = 1
    where participant.bracket_position = 2;
    raise exception 'PLAYERS CUP TEST FAILED: two participants shared a bracket position';
  exception
    when unique_violation then null;
  end;
end;
$test$;

select pg_temp.cup_assert(true, 'duplicate rank_position is rejected');
select pg_temp.cup_assert(true, 'duplicate bracket_position is rejected');

do $test$
declare
  v_participant_id bigint;
  v_tie_id bigint;
begin
  select tie.home_participant_id, other_tie.id
  into v_participant_id, v_tie_id
  from public.cup_ties as tie
  join public.cup_rounds as round
    on round.id = tie.round_id
  join public.cup_ties as other_tie
    on other_tie.round_id = tie.round_id
    and other_tie.id <> tie.id
    and other_tie.outcome = 'bye'
    and other_tie.home_participant_id is not null
    and other_tie.away_participant_id is null
  where round.round_number = 1
    and tie.outcome = 'bye'
    and tie.home_participant_id is not null
  limit 1;

  perform pg_temp.cup_assert(
    v_participant_id is not null and v_tie_id is not null,
    'the fixture found two round 1 byes to collide'
  );

  begin
    -- outcome and winner move with the participants so the row-level state
    -- checks pass and the duplicate is what actually rejects the write.
    update public.cup_ties as tie
    set
      away_participant_id = v_participant_id,
      winner_participant_id = null,
      outcome = 'pending'
    where tie.id = v_tie_id;
    raise exception 'PLAYERS CUP TEST FAILED: a participant entered two ties of one round';
  exception
    when unique_violation then null;
  end;
end;
$test$;

rollback to savepoint uniqueness_tests;

reset role;
rollback;

select unnest(array[
  'template_returns_64_distinct_fold_and_bracket_positions',
  'template_opens_1_64_32_33_16_49_17_48',
  'template_position_pairs_sum_to_65',
  'protected_positions_cannot_meet_before_quarter_finals',
  'protected_positions_split_into_four_quarter_final_pairs',
  'entitlement_ordered_by_position_for_every_field_size',
  'every_occupied_position_has_an_entry_round',
  'non_admin_creation_rejected',
  'anon_creation_rejected',
  'disabled_admin_creation_rejected',
  'admin_creation_through_authenticated_role',
  'player_can_read_cup',
  'player_competition_insert_rejected',
  'player_winner_write_rejected',
  'player_score_write_rejected',
  'player_rank_position_write_rejected',
  'player_reward_write_rejected',
  'player_tie_delete_rejected',
  'player_ranking_execute_rejected',
  'anon_cup_read_rejected',
  'seven_players_rejected',
  'rejected_creation_writes_nothing',
  'eight_players_accepted',
  'sixty_four_players_accepted',
  'more_than_64_keeps_top_64',
  'excluded_players_are_deterministic',
  'strict_rank_order_points_exact_correct_missed',
  'identical_dry_runs_produce_identical_ranking',
  'each_dry_run_uses_a_throwaway_preview_draw_seed',
  'matchday_3_points_do_not_affect_ranking',
  'long_term_awards_do_not_affect_ranking',
  'case_only_username_tie_broken_by_user_id',
  'ranking_positions_1_to_8_keep_protected_positions',
  'frozen_entry_round_matches_template_entitlement',
  'no_lower_ranked_player_enters_later',
  'round_1_pairs_occupy_mirrored_positions',
  'only_entry_round_1_players_contest_round_1_ties',
  'byes_8_players',
  'eight_players_are_all_protected_seeds',
  'eight_players_first_meet_in_the_quarter_final',
  'byes_17_players',
  'seventeen_players_split_matchday_5_and_matchday_4',
  'seventeen_player_draw_stays_inside_entitlement_groups',
  'byes_32_players',
  'byes_33_players',
  'byes_63_players',
  'byes_64_players',
  'sixty_four_players_produce_32_ties_and_no_byes',
  'ranks_9_to_64_drawn_among_unprotected_positions',
  'sixty_four_player_draw_moves_unprotected_players',
  'forty_players_8_ties_24_byes',
  'forty_players_byes_are_ranks_1_to_24',
  'forty_players_ranks_25_to_40_contest_matchday_3',
  'forty_players_draw_stays_inside_entitlement_groups',
  'forty_players_entry_rounds_follow_ranking',
  'forty_player_draw_moves_unprotected_players',
  'same_draw_seed_rebuilds_identical_bracket',
  'different_draw_seeds_produce_different_draws',
  'no_draw_seed_moves_a_protected_player',
  'no_draw_seed_breaks_entry_round_entitlement',
  'persisted_draw_seed_replays_persisted_placement',
  'results_renames_and_rewards_leave_the_draw_alone',
  'repeated_creation_never_redraws',
  'six_rounds_mapped_to_matchdays_3_to_8',
  'sixty_three_tie_skeleton',
  'rounds_2_to_6_unpopulated_in_phase_1',
  'no_participant_twice_in_a_round',
  'bracket_positions_are_unique_and_contiguous',
  'dry_run_writes_nothing',
  'dry_run_returns_preview_seed_top_8_and_round_1',
  'repeated_creation_returns_existing_cup',
  'dry_run_after_creation_returns_persisted_draw_seed',
  'repeated_calls_never_duplicate_rows',
  'persisted_bracket_untouched_by_repeated_calls',
  'creation_holds_advisory_lock',
  'late_registration_stays_out_of_the_cup',
  'reward_defaults_30_20_10',
  'negative_reward_rejected',
  'finalist_above_winner_rejected',
  'semi_finalist_above_finalist_rejected',
  'bracket_independent_of_reward_values',
  'deleted_account_keeps_participant_row',
  'deleted_account_keeps_bracket_structure',
  'rename_after_creation_keeps_snapshot_and_rank_position',
  'unfinished_ranking_matchday_rejected',
  'missing_matchday_8_rejected',
  'duplicate_rank_position_rejected',
  'duplicate_bracket_position_rejected',
  'duplicate_round_participant_rejected',
  'all_fixture_changes_rolled_back'
]) as passed_test;
