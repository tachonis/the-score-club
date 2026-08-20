-- Transactional Players Cup (phase 2A) verification against the hosted schema.
-- The fixture builds its own players, matchdays, matches, predictions and
-- Golden Match selections so every scenario controls the field size and the
-- football calendar exactly, and every mutation is rolled back at the end. Run
-- it as the project owner (the Supabase SQL editor session), which is the same
-- requirement as the Phase 1, Golden Match and long-term fixtures.

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
    raise exception 'PLAYERS CUP 2A TEST FAILED: %', p_message;
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

create function pg_temp.cup_add_player(p_index integer)
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
    'players-cup-2a-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzcup' || lpad(p_index::text, 3, '0'))
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

create function pg_temp.cup_matchday_id(p_matchday_number integer)
returns bigint
language sql
stable
as $helper$
  select matchday.id
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number = p_matchday_number;
$helper$;

create function pg_temp.cup_round_id(p_round_number integer)
returns bigint
language sql
stable
as $helper$
  select round.id
  from public.cup_rounds as round
  where round.cup_id = pg_temp.cup_id()
    and round.round_number = p_round_number;
$helper$;

create function pg_temp.cup_participant_id(p_index integer)
returns bigint
language sql
stable
as $helper$
  select participant.id
  from public.cup_participants as participant
  where participant.cup_id = pg_temp.cup_id()
    and participant.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_rank_of(p_index integer)
returns integer
language sql
stable
as $helper$
  select participant.rank_position
  from public.cup_participants as participant
  where participant.cup_id = pg_temp.cup_id()
    and participant.user_id = pg_temp.cup_user_id(p_index);
$helper$;

create function pg_temp.cup_tie(p_round_number integer, p_slot integer)
returns public.cup_ties
language sql
stable
as $helper$
  select tie.*
  from public.cup_ties as tie
  where tie.round_id = pg_temp.cup_round_id(p_round_number)
    and tie.slot = p_slot;
$helper$;

create function pg_temp.cup_round_status(p_round_number integer)
returns text
language sql
stable
as $helper$
  select round.status
  from public.cup_rounds as round
  where round.id = pg_temp.cup_round_id(p_round_number);
$helper$;

-- Semantic state only. updated_at is deliberately excluded so idempotence can
-- be asserted on meaning rather than on write bookkeeping.
create function pg_temp.cup_state()
returns text
language sql
stable
as $helper$
  select string_agg(line, '|' order by line)
  from (
    select format(
      'tie:%s:%s:%s-%s:%s:%s:%s:%s:%s:%s:%s:%s',
      round.round_number,
      tie.slot,
      coalesce(home_participant.rank_position::text, '-'),
      coalesce(away_participant.rank_position::text, '-'),
      tie.outcome,
      coalesce(winner_participant.rank_position::text, '-'),
      coalesce(tie.decided_by_rule, '-'),
      tie.home_points,
      tie.away_points,
      tie.home_exact,
      tie.away_exact,
      tie.home_correct || ':' || tie.away_correct
    ) as line
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    left join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    left join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
    left join public.cup_participants as winner_participant
      on winner_participant.id = tie.winner_participant_id
    where tie.cup_id = pg_temp.cup_id()
    union all
    select format('round:%s:%s', round.round_number, round.status)
    from public.cup_rounds as round
    where round.cup_id = pg_temp.cup_id()
    union all
    select format(
      'award:%s:%s:%s',
      participant.rank_position,
      award.award_type,
      award.points
    )
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    where award.cup_id = pg_temp.cup_id()
    union all
    select format('competition:%s', competition.status)
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) as state;
$helper$;

create function pg_temp.cup_award_fingerprint()
returns text
language sql
stable
as $helper$
  select coalesce(
    string_agg(
      participant.rank_position || ':' || award.award_type || ':' || award.points,
      ',' order by participant.rank_position
    ),
    ''
  )
  from public.cup_awards as award
  join public.cup_participants as participant
    on participant.id = award.participant_id
  where award.cup_id = pg_temp.cup_id();
$helper$;

-- Structural capacities recomputed inside the fixture from the Phase 1
-- template, so a broken players_cup_tie_layout or players_cup_tie_outcome
-- cannot make its own expectations agree with itself.
create function pg_temp.cup_expected_layout(p_participants integer)
returns table (
  round_number integer,
  slot integer,
  home_capacity integer,
  away_capacity integer
)
language sql
stable
as $helper$
  with side as (
    select
      round_series.value as round_number,
      ((slot_template.fold_position - 1) / (1 << round_series.value)) + 1
        as slot,
      (
        ((slot_template.fold_position - 1) % (1 << round_series.value))
        < (1 << (round_series.value - 1))
      ) as is_home,
      slot_template.bracket_position
    from public.players_cup_bracket_slots(64) as slot_template
    cross join generate_series(1, 6) as round_series(value)
  )
  select
    side.round_number::integer,
    side.slot::integer,
    count(*) filter (
      where side.is_home and side.bracket_position <= p_participants
    )::integer,
    count(*) filter (
      where not side.is_home and side.bracket_position <= p_participants
    )::integer
  from side
  group by side.round_number, side.slot;
$helper$;

create function pg_temp.cup_recompute()
returns jsonb
language plpgsql
as $helper$
declare
  v_summary jsonb;
begin
  perform pg_advisory_xact_lock(public.players_cup_lock_key());
  v_summary := public.players_cup_apply(pg_temp.cup_id());
  return v_summary;
end;
$helper$;

-- Points, exact and correct results recomputed straight from the raw
-- predictions, without touching any Phase 2A helper. Only used in scenarios
-- that have no excluded matches.
create function pg_temp.cup_expected_points(
  p_index integer,
  p_matchday_number integer
)
returns integer[]
language sql
stable
as $helper$
  select array[
    coalesce(sum(prediction.points), 0)::integer,
    count(*) filter (where prediction.points in (5, 10))::integer,
    count(*) filter (where prediction.points in (2, 4))::integer
  ]
  from public.predictions as prediction
  join public.matches as match_row
    on match_row.id = prediction.match_id
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where prediction.user_id = pg_temp.cup_user_id(p_index)
    and matchday.stage = 'league_phase'
    and matchday.matchday_number = p_matchday_number;
$helper$;

create function pg_temp.cup_add_matches(
  p_matchday_number integer,
  p_count integer,
  p_kickoff timestamptz
)
returns void
language plpgsql
as $helper$
begin
  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  select
    pg_temp.cup_matchday_id(p_matchday_number),
    current_setting('test.team_a')::bigint,
    current_setting('test.team_b')::bigint,
    p_kickoff + (slot.number || ' minutes')::interval,
    'scheduled'
  from generate_series(1, p_count) as slot(number);
end;
$helper$;

-- Moves a matchday into the recent past so its own matches can be played and,
-- for the previous matchday, so the postponed-match cutoff passes.
create function pg_temp.cup_open_matchday(p_matchday_number integer)
returns void
language plpgsql
as $helper$
begin
  update public.matches as match_row
  set
    kickoff_at = now()
      - ((10 - p_matchday_number) || ' hours')::interval
      + (match_row.id % 30 || ' seconds')::interval,
    updated_at = now()
  where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number);
end;
$helper$;

create function pg_temp.cup_predict_matchday(
  p_matchday_number integer,
  p_from integer,
  p_to integer
)
returns void
language plpgsql
as $helper$
declare
  v_index integer;
  v_match record;
  v_quality integer;
begin
  for v_index in p_from..p_to loop
    for v_match in
      select
        match_row.id,
        row_number() over (order by match_row.id)::integer as position
      from public.matches as match_row
      where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number)
      order by match_row.id
    loop
      -- Result is always 1-0, so quality 0 is an exact score, quality 1 a
      -- correct result and quality 2 a miss. The hash spreads the qualities
      -- unevenly across the field, which is what makes points, exact counts
      -- and correct counts all differ between opponents.
      v_quality := abs(
        hashtext(v_index::text || ':' || v_match.position::text) % 3
      );

      insert into public.predictions (
        user_id,
        match_id,
        predicted_home_score,
        predicted_away_score
      )
      values (
        pg_temp.cup_user_id(v_index),
        v_match.id,
        case v_quality when 0 then 1 when 1 then 2 else 0 end,
        case v_quality when 0 then 0 when 1 then 0 else 1 end
      )
      on conflict (user_id, match_id) do update
      set
        predicted_home_score = excluded.predicted_home_score,
        predicted_away_score = excluded.predicted_away_score;
    end loop;
  end loop;
end;
$helper$;

create function pg_temp.cup_score_matchday(
  p_matchday_number integer,
  p_home_score integer,
  p_away_score integer
)
returns void
language plpgsql
as $helper$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(p_matchday_number)
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, p_home_score, p_away_score);
  end loop;
end;
$helper$;

-- Every invariant the engine must satisfy after any recompute, for any field
-- size and at any point in the season.
create function pg_temp.cup_assert_consistency(p_participants integer)
returns void
language plpgsql
as $helper$
declare
  v_cup_id bigint := pg_temp.cup_id();
begin
  perform pg_temp.cup_assert(
    (select count(*) from public.cup_ties as tie where tie.cup_id = v_cup_id)
      = 63,
    'the 63 tie skeleton is neither extended nor truncated'
  );

  perform pg_temp.cup_assert(
    (select count(*) from public.cup_rounds as round where round.cup_id = v_cup_id)
      = 6,
    'the six rounds survive a recompute'
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from public.cup_participants as participant
      where participant.cup_id = v_cup_id
    ) = p_participants,
    'the frozen entry list survives a recompute'
  );

  -- Structural classification. An empty tie is exactly a tie no player can
  -- ever reach, and a bye is exactly a tie whose far side is unreachable.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join pg_temp.cup_expected_layout(p_participants) as expected
        on expected.round_number = round.round_number
        and expected.slot = tie.slot
      where round.cup_id = v_cup_id
        and (tie.outcome = 'empty')
          <> (expected.home_capacity = 0 and expected.away_capacity = 0)
    ),
    'a tie is empty exactly when neither side can ever be reached'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join pg_temp.cup_expected_layout(p_participants) as expected
        on expected.round_number = round.round_number
        and expected.slot = tie.slot
      where round.cup_id = v_cup_id
        and tie.outcome = 'bye'
        and expected.home_capacity > 0
        and expected.away_capacity > 0
    ),
    'a bye never exists where both sides can produce a player'
  );

  -- The dangerous direction: one participant present against a feeder that can
  -- still deliver an opponent must wait, never advance.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join pg_temp.cup_expected_layout(p_participants) as expected
        on expected.round_number = round.round_number
        and expected.slot = tie.slot
      where round.cup_id = v_cup_id
        and expected.home_capacity > 0
        and expected.away_capacity > 0
        and (
          tie.home_participant_id is null
          or tie.away_participant_id is null
        )
        and tie.winner_participant_id is not null
    ),
    'a half filled contested tie never has a winner'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join pg_temp.cup_expected_layout(p_participants) as expected
        on expected.round_number = round.round_number
        and expected.slot = tie.slot
      where round.cup_id = v_cup_id
        and (expected.home_capacity = 0) <> (expected.away_capacity = 0)
        and (
          tie.home_participant_id is not null
          or tie.away_participant_id is not null
        )
        and tie.outcome <> 'bye'
    ),
    'a reachable player against an unreachable side is always a bye'
  );

  -- Per outcome shape.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      where tie.cup_id = v_cup_id
        and tie.outcome = 'bye'
        and (
          tie.winner_participant_id is distinct from coalesce(
            tie.home_participant_id,
            tie.away_participant_id
          )
          or tie.decided_by_rule is not null
          or tie.home_points <> 0
          or tie.away_points <> 0
          or tie.home_exact <> 0
          or tie.away_exact <> 0
          or tie.home_correct <> 0
          or tie.away_correct <> 0
        )
    ),
    'a bye advances its only participant and scores nothing'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      where tie.cup_id = v_cup_id
        and tie.outcome = 'empty'
        and (
          tie.home_participant_id is not null
          or tie.away_participant_id is not null
          or tie.winner_participant_id is not null
          or tie.home_points <> 0
          or tie.away_points <> 0
        )
    ),
    'an empty tie holds no participant and no score'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      where tie.cup_id = v_cup_id
        and tie.outcome = 'pending'
        and (
          tie.winner_participant_id is not null
          or tie.decided_by_rule is not null
        )
    ),
    'a pending tie never carries a winner or a tie-break rule'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      where tie.cup_id = v_cup_id
        and tie.outcome = 'decided'
        and (
          tie.home_participant_id is null
          or tie.away_participant_id is null
          or tie.winner_participant_id is null
          or tie.decided_by_rule is null
          or tie.winner_participant_id not in (
            tie.home_participant_id,
            tie.away_participant_id
          )
        )
    ),
    'every decided tie has two participants, one winner and one rule'
  );

  -- The tie-break chain, recomputed independently of players_cup_tie_break.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_participants as home_participant
        on home_participant.id = tie.home_participant_id
      join public.cup_participants as away_participant
        on away_participant.id = tie.away_participant_id
      where tie.cup_id = v_cup_id
        and tie.outcome = 'decided'
        and (
          tie.decided_by_rule <> case
            when tie.home_points <> tie.away_points then 'points'
            when tie.home_exact <> tie.away_exact then 'exact'
            when tie.home_correct <> tie.away_correct then 'correct'
            else 'rank_position'
          end
          or tie.winner_participant_id <> case
            when tie.home_points <> tie.away_points then
              case
                when tie.home_points > tie.away_points
                  then tie.home_participant_id
                else tie.away_participant_id
              end
            when tie.home_exact <> tie.away_exact then
              case
                when tie.home_exact > tie.away_exact
                  then tie.home_participant_id
                else tie.away_participant_id
              end
            when tie.home_correct <> tie.away_correct then
              case
                when tie.home_correct > tie.away_correct
                  then tie.home_participant_id
                else tie.away_participant_id
              end
            else
              case
                when home_participant.rank_position
                  < away_participant.rank_position
                  then tie.home_participant_id
                else tie.away_participant_id
              end
          end
        )
    ),
    'every decided tie follows points, exact, correct then rank_position'
  );

  -- Progression. Round 1 comes from the persisted draw, later rounds from the
  -- previous round: odd slot to the home side, even slot to the away side.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join public.cup_rounds as previous_round
        on previous_round.cup_id = round.cup_id
        and previous_round.round_number = round.round_number - 1
      left join public.cup_ties as home_feeder
        on home_feeder.round_id = previous_round.id
        and home_feeder.slot = tie.slot * 2 - 1
      left join public.cup_ties as away_feeder
        on away_feeder.round_id = previous_round.id
        and away_feeder.slot = tie.slot * 2
      where round.cup_id = v_cup_id
        and round.round_number > 1
        and (
          tie.home_participant_id
            is distinct from home_feeder.winner_participant_id
          or tie.away_participant_id
            is distinct from away_feeder.winner_participant_id
        )
    ),
    'each round receives the previous odd slot at home and even slot away'
  );

  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join (
        select
          ((slot_template.fold_position + 1) / 2)::integer as slot,
          max(slot_template.bracket_position)
            filter (where slot_template.fold_position % 2 = 1)
            as home_bracket_position,
          max(slot_template.bracket_position)
            filter (where slot_template.fold_position % 2 = 0)
            as away_bracket_position
        from public.players_cup_bracket_slots(64) as slot_template
        group by ((slot_template.fold_position + 1) / 2)
      ) as pairing
        on pairing.slot = tie.slot
      left join public.cup_participants as home_participant
        on home_participant.cup_id = v_cup_id
        and home_participant.bracket_position = pairing.home_bracket_position
      left join public.cup_participants as away_participant
        on away_participant.cup_id = v_cup_id
        and away_participant.bracket_position = pairing.away_bracket_position
      where round.cup_id = v_cup_id
        and round.round_number = 1
        and (
          tie.home_participant_id is distinct from home_participant.id
          or tie.away_participant_id is distinct from away_participant.id
        )
    ),
    'round 1 always mirrors the persisted bracket positions'
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
    'no participant appears twice in the same round'
  );

  -- Round status is derived from the rebuilt ties, never from the calendar.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_rounds as round
      where round.cup_id = v_cup_id
        and round.status <> (
          select case
            when count(*) filter (
              where tie.home_participant_id is not null
                or tie.away_participant_id is not null
            ) = 0 then 'pending'
            when count(*) filter (where tie.outcome = 'pending') > 0
              then 'in_progress'
            else 'final'
          end
          from public.cup_ties as tie
          where tie.round_id = round.id
        )
    ),
    'round status matches the state of its own ties'
  );

  -- A tie may only be decided once its own matchday is resolvable.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_ties as tie
      join public.cup_rounds as round
        on round.id = tie.round_id
      join public.players_cup_matchday_state(v_cup_id) as state
        on state.round_id = round.id
      where round.cup_id = v_cup_id
        and tie.outcome = 'decided'
        and not state.is_complete
    ),
    'no tie is decided before its matchday is complete'
  );

  -- Awards mirror the bracket, exactly and non-cumulatively.
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_awards as award
      group by award.cup_id, award.participant_id
      having count(*) > 1
    ),
    'a participant never holds more than one Cup award'
  );

  perform pg_temp.cup_assert(
    (
      select count(*)
      from public.cup_awards as award
      where award.cup_id = v_cup_id
    ) = case
      when (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'decided'
        then 4
      else 0
    end,
    'a completed Cup has exactly four awards and an open Cup has none'
  );
end;
$helper$;

-- The frozen entry_round must equal the first round in which a player's own
-- bracket position sits in a tie both of whose sides can produce a player.
create function pg_temp.cup_assert_entry_rounds(p_participants integer)
returns void
language plpgsql
as $helper$
begin
  perform pg_temp.cup_assert(
    not exists (
      select 1
      from public.cup_participants as participant
      left join (
        select
          slot_template.bracket_position,
          min(expected.round_number) as first_contested_round
        from public.players_cup_bracket_slots(64) as slot_template
        cross join generate_series(1, 6) as round_series(value)
        join pg_temp.cup_expected_layout(p_participants) as expected
          on expected.round_number = round_series.value
          and expected.slot =
            ((slot_template.fold_position - 1) / (1 << round_series.value)) + 1
        where expected.home_capacity > 0
          and expected.away_capacity > 0
        group by slot_template.bracket_position
      ) as entry
        on entry.bracket_position = participant.bracket_position
      where participant.cup_id = pg_temp.cup_id()
        and participant.entry_round
          is distinct from entry.first_contested_round
    ),
    'every frozen entry_round equals the first contested round of its position'
  );
end;
$helper$;

-- ---------------------------------------------------------------------------
-- Deterministic fixture
-- ---------------------------------------------------------------------------

insert into public.teams (name, short_name)
values
  ('ZZ Players Cup 2A Test A', 'Z2A'),
  ('ZZ Players Cup 2A Test B', 'Z2B')
on conflict (name) do nothing;

select set_config(
  'test.team_a',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup 2A Test A'
  ),
  true
);
select set_config(
  'test.team_b',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Players Cup 2A Test B'
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

-- The fixture owns every League Phase match, so the ranking inputs and the Cup
-- calendar are both fully known.
delete from public.matches as match_row
using public.matchdays as matchday
where matchday.id = match_row.matchday_id
  and matchday.stage = 'league_phase';

select pg_temp.cup_add_matches(1, 2, now() - interval '30 days');
select pg_temp.cup_add_matches(2, 2, now() - interval '25 days');

-- Matchdays 3 to 8 start in the future, so no postponed-match cutoff has
-- passed. Each scenario opens the matchdays it needs.
select pg_temp.cup_add_matches(3, 3, now() + interval '3 days');
select pg_temp.cup_add_matches(4, 3, now() + interval '6 days');
select pg_temp.cup_add_matches(5, 3, now() + interval '9 days');
select pg_temp.cup_add_matches(6, 3, now() + interval '12 days');
select pg_temp.cup_add_matches(7, 3, now() + interval '15 days');
select pg_temp.cup_add_matches(8, 3, now() + interval '18 days');

-- Only the synthetic players stay active, so every scenario controls N exactly.
update public.profiles as profile
set status = 'disabled'
where profile.status = 'active';

select pg_temp.cup_add_players(1, 40);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.cup_user_id(1);

select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(1)::text,
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- Matchday 1 splits the field in two so the frozen ranking is meaningful and a
-- later Matchday 1 correction would genuinely reorder it.
insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.cup_user_id(player.index),
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  ),
  case when player.index <= 20 then 1 else 0 end,
  case when player.index <= 20 then 0 else 2 end
from generate_series(1, 40) as player(index);

select pg_temp.cup_score_matchday(1, 1, 0);
select pg_temp.cup_score_matchday(2, 1, 0);

select pg_temp.cup_assert(
  (select count(*) from public.cup_competitions) = 0,
  'the fixture starts without a Cup'
);

-- ---------------------------------------------------------------------------
-- 1. Prediction quality classifiers
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  public.prediction_is_exact(null) = false
  and public.prediction_is_exact(0) = false
  and public.prediction_is_exact(2) = false
  and public.prediction_is_exact(4) = false
  and public.prediction_is_exact(5) = true
  and public.prediction_is_exact(10) = true,
  'prediction_is_exact accepts only 5 and 10'
);

select pg_temp.cup_assert(
  public.prediction_is_correct(null) = false
  and public.prediction_is_correct(0) = false
  and public.prediction_is_correct(2) = true
  and public.prediction_is_correct(4) = true
  and public.prediction_is_correct(5) = false
  and public.prediction_is_correct(10) = false,
  'prediction_is_correct accepts only 2 and 4'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(0, 10) as candidate(points)
    where public.prediction_is_exact(candidate.points)
      and public.prediction_is_correct(candidate.points)
  ),
  'no points value is both exact and correct'
);

-- The classifiers must agree with the real meaning of the stored prediction,
-- not merely with themselves.
select pg_temp.cup_assert(
  not exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    where match_row.status = 'finished'
      and (
        public.prediction_is_exact(prediction.points) <> (
          prediction.predicted_home_score = match_row.home_score
          and prediction.predicted_away_score = match_row.away_score
        )
        or public.prediction_is_correct(prediction.points) <> (
          not (
            prediction.predicted_home_score = match_row.home_score
            and prediction.predicted_away_score = match_row.away_score
          )
          and sign(
            prediction.predicted_home_score - prediction.predicted_away_score
          ) = sign(match_row.home_score - match_row.away_score)
        )
      )
  ),
  'the classifiers match the semantic truth of every scored prediction'
);

-- ---------------------------------------------------------------------------
-- 2. Structural tie layout
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  (select count(*) from public.players_cup_tie_layout(40)) = 63,
  'the layout describes all 63 ties'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(8, 64) as field(size)
    cross join lateral public.players_cup_tie_layout(field.size) as layout
    join pg_temp.cup_expected_layout(field.size) as expected
      on expected.round_number = layout.round_number
      and expected.slot = layout.slot
    where layout.home_capacity <> expected.home_capacity
      or layout.away_capacity <> expected.away_capacity
  ),
  'the layout matches the template for every field size from 8 to 64'
);

-- Sibling feeders never differ by more than one player, which is exactly why a
-- structural bye can always be resolved immediately.
select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(8, 64) as field(size)
    cross join lateral public.players_cup_tie_layout(field.size) as layout
    where abs(layout.home_capacity - layout.away_capacity) > 1
  ),
  'sibling feeders never differ by more than one player'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.players_cup_tie_layout(8) as layout
    where layout.round_number = 1
      and layout.home_capacity + layout.away_capacity = 1
  ) = 8
  and (
    select count(*)
    from public.players_cup_tie_layout(8) as layout
    where layout.round_number = 4
      and layout.home_capacity = 1
      and layout.away_capacity = 1
  ) = 4,
  'eight players produce eight opening byes and four contested quarter-finals'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.players_cup_tie_layout(40) as layout
    where layout.round_number = 1
      and layout.home_capacity = 1
      and layout.away_capacity = 1
  ) = 8
  and (
    select count(*)
    from public.players_cup_tie_layout(40) as layout
    where layout.round_number = 1
      and layout.home_capacity + layout.away_capacity = 1
  ) = 24,
  'forty players produce eight contested opening ties and 24 byes'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.players_cup_tie_layout(64) as layout
    where layout.round_number = 1
      and layout.home_capacity = 1
      and layout.away_capacity = 1
  ) = 32,
  'sixty-four players produce no opening bye'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.players_cup_tie_layout(17) as layout
    where layout.round_number = 2
      and layout.home_capacity = 1
      and layout.away_capacity = 1
  ) = 1,
  'seventeen players contest exactly one round 2 tie'
);

-- ---------------------------------------------------------------------------
-- 3. Tie classification and tie-break units
-- ---------------------------------------------------------------------------

select pg_temp.cup_assert(
  public.players_cup_tie_outcome(0, 0, null, null, false) = 'empty'
  and public.players_cup_tie_outcome(1, 0, 10, null, false) = 'bye'
  and public.players_cup_tie_outcome(0, 1, null, 10, false) = 'bye'
  and public.players_cup_tie_outcome(2, 1, 10, null, true) = 'pending'
  and public.players_cup_tie_outcome(1, 1, null, 10, true) = 'pending'
  and public.players_cup_tie_outcome(1, 1, 10, 11, false) = 'pending'
  and public.players_cup_tie_outcome(1, 1, 10, 11, true) = 'decided',
  'tie classification separates empty, bye, waiting and decided'
);

select pg_temp.cup_assert(
  (
    select decided_by_rule || ':' || home_wins
    from public.players_cup_tie_break(9, 4, 0, 0, 0, 0, 1, 2)
  ) = 'points:true'
  and (
    select decided_by_rule || ':' || home_wins
    from public.players_cup_tie_break(10, 10, 1, 0, 0, 5, 2, 1)
  ) = 'exact:true'
  and (
    select decided_by_rule || ':' || home_wins
    from public.players_cup_tie_break(4, 4, 0, 0, 2, 1, 2, 1)
  ) = 'correct:true'
  and (
    select decided_by_rule || ':' || home_wins
    from public.players_cup_tie_break(0, 0, 0, 0, 0, 0, 7, 3)
  ) = 'rank_position:false'
  and (
    select decided_by_rule || ':' || home_wins
    from public.players_cup_tie_break(0, 0, 0, 0, 0, 0, 3, 7)
  ) = 'rank_position:true',
  'the tie-break chain walks points, exact, correct then rank_position'
);

-- ---------------------------------------------------------------------------
-- 4. Recompute before any Cup football has been played
-- ---------------------------------------------------------------------------

set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_assert(
  (
    select competition.participant_count
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 40,
  'the fixture Cup has 40 participants'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(1, 40) as player(index)
    where pg_temp.cup_rank_of(player.index) <> player.index
  ),
  'rank_position follows the player index, so scenarios stay readable'
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (select count(*) from public.cup_ties as tie where tie.outcome = 'bye') = 24
  and (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 1 and tie.outcome = 'pending'
  ) = 8,
  'the opening round starts with 24 byes and 8 contested ties'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_ties as tie where tie.outcome = 'decided')
    = 0,
  'nothing is decided before a single Cup match is played'
);

select pg_temp.cup_assert(
  pg_temp.cup_round_status(1) = 'in_progress'
  and pg_temp.cup_round_status(2) = 'in_progress'
  and pg_temp.cup_round_status(6) = 'pending',
  'rounds without any participant stay pending while reachable rounds run'
);

-- The 24 byes of round 1 must already sit in round 2, waiting rather than
-- advancing again.
select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 2
      and (
        tie.home_participant_id is not null
        or tie.away_participant_id is not null
      )
  ) = 16
  and (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 2 and tie.winner_participant_id is not null
  ) = 0,
  'round 1 byes reach round 2 without winning anything there'
);

-- ---------------------------------------------------------------------------
-- 5. Interim state during an incomplete matchday
-- ---------------------------------------------------------------------------

savepoint interim_tests;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

-- Only the first Matchday 3 match is played.
select public.set_match_result(
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  1,
  0
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  not (
    select state.is_complete
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ),
  'a partly played matchday is not complete'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 1
      and tie.outcome = 'pending'
      and tie.home_points + tie.away_points > 0
  ) > 0,
  'interim Cup scores appear while the matchday is still running'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 1
      and tie.outcome = 'decided'
  ),
  'no round 1 tie is decided while Matchday 3 is incomplete'
);

select pg_temp.cup_assert(
  pg_temp.cup_round_status(1) = 'in_progress',
  'an incomplete round reports in_progress'
);

-- Finishing the matchday resolves the same ties with the same recompute.
select pg_temp.cup_score_matchday(3, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 1 and tie.outcome = 'decided'
  ) = 8
  and pg_temp.cup_round_status(1) = 'final',
  'completing Matchday 3 decides all eight contested opening ties'
);

rollback to savepoint interim_tests;

-- ---------------------------------------------------------------------------
-- 6. Full season, corrections, awards and idempotence
-- ---------------------------------------------------------------------------

savepoint season_tests;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);
select pg_temp.cup_score_matchday(3, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

-- Cup scoring reads exactly the prediction points, for every participant.
select pg_temp.cup_assert(
  not exists (
    select 1
    from generate_series(1, 40) as player(index)
    cross join lateral pg_temp.cup_expected_points(player.index, 3) as expected
    join public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
      on score.participant_id = pg_temp.cup_participant_id(player.index)
    where score.points <> expected[1]
      or score.exact_count <> expected[2]
      or score.correct_count <> expected[3]
  ),
  'Cup matchday scores equal the raw prediction points, exacts and corrects'
);

select set_config(
  'test.round1_state',
  pg_temp.cup_state(),
  true
);

select pg_temp.cup_open_matchday(4);
select pg_temp.cup_predict_matchday(4, 1, 40);
select pg_temp.cup_score_matchday(4, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.round_number = 2 and tie.outcome = 'decided'
  ) = 16
  and pg_temp.cup_round_status(2) = 'final',
  'Matchday 4 decides all sixteen round 2 ties'
);

-- Opening Matchday 4 pushed the Matchday 3 cutoff into the past, but every
-- Matchday 3 match was finished before it, so nothing is excluded.
select pg_temp.cup_assert(
  (select count(*) from public.cup_excluded_matches) = 0,
  'a fully played matchday loses nothing to the cutoff'
);

select pg_temp.cup_open_matchday(5);
select pg_temp.cup_predict_matchday(5, 1, 40);
select pg_temp.cup_score_matchday(5, 1, 0);
select pg_temp.cup_open_matchday(6);
select pg_temp.cup_predict_matchday(6, 1, 40);
select pg_temp.cup_score_matchday(6, 1, 0);
select pg_temp.cup_open_matchday(7);
select pg_temp.cup_predict_matchday(7, 1, 40);
select pg_temp.cup_score_matchday(7, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  pg_temp.cup_round_status(5) = 'final'
  and (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'pending'
  and (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'active',
  'the Final waits for Matchday 8 while the semi-finals are already final'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_awards) = 0,
  'no award exists before the Final is decided'
);

select pg_temp.cup_open_matchday(8);
select pg_temp.cup_predict_matchday(8, 1, 40);
select pg_temp.cup_score_matchday(8, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'decided'
  and pg_temp.cup_round_status(6) = 'final'
  and (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'completed',
  'completing Matchday 8 decides the Final and completes the competition'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.cup_id = pg_temp.cup_id()
      and tie.outcome = 'decided'
  ) = 39
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.cup_id = pg_temp.cup_id()
      and tie.outcome = 'pending'
  ) = 0,
  'a finished 40 player Cup decides 39 contested ties and leaves none pending'
);

-- Exactly one champion, and the whole chain of winners is internally
-- consistent.
select pg_temp.cup_assert(
  (
    select count(distinct tie.winner_participant_id)
    from pg_temp.cup_tie(6, 1) as tie
  ) = 1,
  'the completed Cup produces exactly one champion'
);

-- 6a. Awards
select set_config('test.champion', (
  select participant.rank_position::text
  from pg_temp.cup_tie(6, 1) as tie
  join public.cup_participants as participant
    on participant.id = tie.winner_participant_id
), true);

select pg_temp.cup_assert(
  (
    select award.award_type || ':' || award.points
    from public.cup_awards as award
    join public.cup_participants as participant
      on participant.id = award.participant_id
    where participant.rank_position = current_setting('test.champion')::integer
  ) = 'winner:30',
  'the champion receives the winner award only'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'winner'
  ) = 1
  and (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'finalist'
  ) = 1
  and (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'semi_finalist'
  ) = 2,
  'the honours list is one champion, one finalist and two semi-finalists'
);

select pg_temp.cup_assert(
  (
    select award.award_type
    from public.cup_awards as award
    join pg_temp.cup_tie(6, 1) as tie
      on award.participant_id = case
        when tie.home_participant_id = tie.winner_participant_id
          then tie.away_participant_id
        else tie.home_participant_id
      end
  ) = 'finalist',
  'the losing finalist receives the finalist award'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.cup_id = pg_temp.cup_id()
      and round.round_number = 5
      and not exists (
        select 1
        from public.cup_awards as award
        where award.award_type = 'semi_finalist'
          and award.participant_id = case
            when tie.home_participant_id = tie.winner_participant_id
              then tie.away_participant_id
            else tie.home_participant_id
          end
      )
  ),
  'both beaten semi-finalists receive the semi-finalist award'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_awards as award
    where award.user_id is distinct from (
      select participant.user_id
      from public.cup_participants as participant
      where participant.id = award.participant_id
    )
  ),
  'every award mirrors the participant user reference'
);

-- 6b. Reward reconfiguration takes effect without any code change.
select set_config('test.award_state', pg_temp.cup_award_fingerprint(), true);

update public.cup_competitions as competition
set
  winner_points = 100,
  finalist_points = 60,
  semi_finalist_points = 20
where competition.id = pg_temp.cup_id();

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'winner' and award.points = 100
  ) = 1
  and (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'finalist' and award.points = 60
  ) = 1
  and (
    select count(*)
    from public.cup_awards as award
    where award.award_type = 'semi_finalist' and award.points = 20
  ) = 2,
  'a 100/60/20 reward configuration is applied by the next recompute'
);

update public.cup_competitions as competition
set
  winner_points = 30,
  finalist_points = 20,
  semi_finalist_points = 10
where competition.id = pg_temp.cup_id();

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  pg_temp.cup_award_fingerprint() = current_setting('test.award_state'),
  'restoring the reward configuration restores the original award values'
);

-- 6c. Idempotence
select set_config('test.season_state', pg_temp.cup_state(), true);

select pg_temp.cup_recompute();
select pg_temp.cup_recompute();
select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.season_state'),
  'repeated recomputes leave the Cup semantically identical'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_ties) = 63
  and (select count(*) from public.cup_awards) = 4,
  'repeated recomputes never duplicate a tie or an award'
);

-- 6d. Matchday 1 and 2 corrections must not move the frozen draw.
select set_config(
  'test.participants',
  (
    select string_agg(
      participant.rank_position || '@' || participant.bracket_position
        || '@' || participant.entry_round,
      ',' order by participant.rank_position
    )
    from public.cup_participants as participant
  ),
  true
);

select public.set_match_result(
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  ),
  0,
  2
);
select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select string_agg(
      participant.rank_position || '@' || participant.bracket_position
        || '@' || participant.entry_round,
      ',' order by participant.rank_position
    )
    from public.cup_participants as participant
  ) = current_setting('test.participants'),
  'a Matchday 1 correction never reorders the frozen Cup entry list'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.season_state'),
  'a Matchday 1 correction changes no Cup result'
);

-- 6e. Reopening the Final withdraws the honours again.
update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = (
  select max(inner_match.id)
  from public.matches as inner_match
  where inner_match.matchday_id = pg_temp.cup_matchday_id(8)
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'pending'
  and (select count(*) from public.cup_awards) = 0
  and (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'active',
  'reopening the Final withdraws every award and reactivates the Cup'
);

update public.matches as match_row
set status = 'finished', updated_at = now()
where match_row.matchday_id = pg_temp.cup_matchday_id(8);

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.season_state'),
  'restoring the last result restores the whole completed Cup'
);

-- 6f. A correction that changes the champion rewrites the honours list.
select set_config(
  'test.old_champion_id',
  (select tie.winner_participant_id::text from pg_temp.cup_tie(6, 1) as tie),
  true
);
select set_config(
  'test.old_finalist_id',
  (
    select (
      case
        when tie.home_participant_id = tie.winner_participant_id
          then tie.away_participant_id
        else tie.home_participant_id
      end
    )::text
    from pg_temp.cup_tie(6, 1) as tie
  ),
  true
);
select set_config(
  'test.old_semi_finalists',
  (
    select string_agg(award.participant_id::text, ',' order by award.participant_id)
    from public.cup_awards as award
    where award.award_type = 'semi_finalist'
  ),
  true
);

-- The champion's Matchday 8 predictions are withdrawn and the beaten finalist
-- predicts every result exactly, so the Final must swap.
delete from public.predictions as prediction
using public.matches as match_row
where match_row.id = prediction.match_id
  and match_row.matchday_id = pg_temp.cup_matchday_id(8)
  and prediction.user_id = (
    select participant.user_id
    from public.cup_participants as participant
    where participant.id = current_setting('test.old_champion_id')::bigint
  );

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  (
    select participant.user_id
    from public.cup_participants as participant
    where participant.id = current_setting('test.old_finalist_id')::bigint
  ),
  match_row.id,
  1,
  0
from public.matches as match_row
where match_row.matchday_id = pg_temp.cup_matchday_id(8)
on conflict (user_id, match_id) do update
set predicted_home_score = 1, predicted_away_score = 0;

select pg_temp.cup_score_matchday(8, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (select tie.winner_participant_id from pg_temp.cup_tie(6, 1) as tie)
    = current_setting('test.old_finalist_id')::bigint,
  'a Matchday 8 correction can change the champion'
);

select pg_temp.cup_assert(
  (
    select award.award_type
    from public.cup_awards as award
    where award.participant_id = current_setting('test.old_finalist_id')::bigint
  ) = 'winner'
  and (
    select award.award_type
    from public.cup_awards as award
    where award.participant_id = current_setting('test.old_champion_id')::bigint
  ) = 'finalist'
  and (select count(*) from public.cup_awards) = 4,
  'the new champion takes the winner award and the old one drops to finalist'
);

select pg_temp.cup_assert(
  (
    select string_agg(award.participant_id::text, ',' order by award.participant_id)
    from public.cup_awards as award
    where award.award_type = 'semi_finalist'
  ) = current_setting('test.old_semi_finalists'),
  'an unchanged semi-final leaves its awards untouched'
);

-- 6g. Corrections to an early Cup matchday rebuild everything downstream.
create temporary table cup_round_1_before as
select tie.slot, tie.winner_participant_id
from public.cup_ties as tie
where tie.round_id = pg_temp.cup_round_id(1);

-- Inverting every Matchday 3 result turns exact predictions into misses and
-- misses into exact scores, so round 1 winners genuinely change.
select pg_temp.cup_score_matchday(3, 0, 1);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  exists (
    select 1
    from cup_round_1_before as before
    join public.cup_ties as tie
      on tie.round_id = pg_temp.cup_round_id(1)
      and tie.slot = before.slot
    where tie.winner_participant_id
      is distinct from before.winner_participant_id
  ),
  'correcting Matchday 3 changes at least one round 1 winner'
);

-- Nobody who lost their reopened round 1 tie may survive anywhere downstream.
select pg_temp.cup_assert(
  not exists (
    select 1
    from cup_round_1_before as before
    join public.cup_ties as tie
      on tie.round_id = pg_temp.cup_round_id(1)
      and tie.slot = before.slot
    join public.cup_rounds as later_round
      on later_round.cup_id = pg_temp.cup_id()
      and later_round.round_number > 1
    join public.cup_ties as later_tie
      on later_tie.round_id = later_round.id
    where tie.winner_participant_id
        is distinct from before.winner_participant_id
      and before.winner_participant_id in (
        later_tie.home_participant_id,
        later_tie.away_participant_id
      )
  ),
  'a replaced round 1 winner disappears from the entire downstream bracket'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_awards) = 4,
  'the corrected Cup still has exactly four awards'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_awards as award
    where award.participant_id not in (
      select tie.home_participant_id
      from public.cup_ties as tie
      join public.cup_rounds as round on round.id = tie.round_id
      where round.cup_id = pg_temp.cup_id()
        and round.round_number in (5, 6)
        and tie.home_participant_id is not null
      union
      select tie.away_participant_id
      from public.cup_ties as tie
      join public.cup_rounds as round on round.id = tie.round_id
      where round.cup_id = pg_temp.cup_id()
        and round.round_number in (5, 6)
        and tie.away_participant_id is not null
    )
  ),
  'no stale award survives a correction'
);

select set_config('test.corrected_state', pg_temp.cup_state(), true);
select pg_temp.cup_recompute();
select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.corrected_state'),
  'a repeated recompute after a correction is byte identical'
);

rollback to savepoint season_tests;

-- ---------------------------------------------------------------------------
-- 7. Scoring detail: Golden Match, missing predictions and isolation
-- ---------------------------------------------------------------------------

savepoint scoring_tests;

select pg_temp.cup_open_matchday(3);

-- Player 2 predicts one exact score, player 3 the same exact score as a Golden
-- Match, player 4 a correct result, player 5 a Golden correct result, player 6
-- a miss and player 7 nothing at all.
insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.cup_user_id(player.index),
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  case player.index when 2 then 1 when 3 then 1 when 4 then 2 when 5 then 2 else 0 end,
  case player.index when 6 then 1 else 0 end
from generate_series(2, 6) as player(index);

insert into public.golden_match_selections (user_id, matchday_id, match_id)
select
  pg_temp.cup_user_id(player.index),
  pg_temp.cup_matchday_id(3),
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  )
from generate_series(3, 3) as player(index)
union all
select
  pg_temp.cup_user_id(5),
  pg_temp.cup_matchday_id(3),
  (
    select min(match_row.id)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  );

select pg_temp.cup_score_matchday(3, 1, 0);

-- A long-term award must never leak into a Cup tie.
insert into public.long_term_predictions (user_id, prediction_type, team_id)
values (
  pg_temp.cup_user_id(6),
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
  pg_temp.cup_user_id(6),
  'winner',
  current_setting('test.team_a')::bigint,
  current_setting('test.team_a')::bigint,
  30
);

-- Matchday 4 predictions must not leak into the Matchday 3 Cup round.
select pg_temp.cup_predict_matchday(4, 2, 7);

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(2)
  ) = '5:1:0',
  'a normal exact score is 5 points and one exact'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(3)
  ) = '10:1:0',
  'a Golden Match exact score is 10 points and still only one exact'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(4)
  ) = '2:0:1',
  'a normal correct result is 2 points and one correct'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(5)
  ) = '4:0:1',
  'a Golden Match correct result is 4 points and one correct'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(6)
  ) = '0:0:0',
  'a wrong prediction scores nothing and a long-term award never leaks in'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(7)
  ) = '0:0:0',
  'a participant without any prediction scores 0/0/0'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id in (
      select participant.id
      from public.cup_participants as participant
      where participant.user_id in (
        pg_temp.cup_user_id(8),
        pg_temp.cup_user_id(9)
      )
    )
      and (score.points, score.exact_count, score.correct_count)
        <> (0, 0, 0)
  ),
  'Matchday 4 predictions never leak into the Matchday 3 Cup round'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    )
  ) = 40,
  'the aggregation always returns one row per participant'
);

rollback to savepoint scoring_tests;

-- ---------------------------------------------------------------------------
-- 8. Postponed match cutoff
-- ---------------------------------------------------------------------------

savepoint cutoff_tests;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

-- Everything except the last Matchday 3 match is played.
do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

-- Scenario A: before the next matchday starts, the round simply waits.
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select state.is_complete::text
      || ':' || state.included_count
      || ':' || state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 'false:3:0',
  'before the cutoff a postponed match keeps its Cup round open'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_excluded_matches) = 0,
  'no exclusion is frozen before the cutoff'
);

savepoint cutoff_scenario_d;

-- Scenario D: the postponed match is played before the next matchday begins.
select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);
select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select state.is_complete::text
      || ':' || state.included_count
      || ':' || state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 'true:3:0',
  'a postponed match played before the cutoff counts normally'
);

rollback to savepoint cutoff_scenario_d;

-- Scenario B: the first Matchday 4 match kicks off while it is still unplayed.
select pg_temp.cup_open_matchday(4);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select state.is_complete::text
      || ':' || state.included_count
      || ':' || state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 'true:2:1',
  'the cutoff closes the round without the unfinished match'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_excluded_matches as excluded_match
    where excluded_match.match_id
      = current_setting('test.postponed_match')::bigint
  ) = 1,
  'the exclusion decision is frozen exactly once'
);

select pg_temp.cup_assert(
  pg_temp.cup_round_status(1) = 'final',
  'the closed round is final even though a match was never played'
);

select set_config('test.cutoff_state', pg_temp.cup_state(), true);
select set_config(
  'test.cutoff_scores',
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ),
  true
);

-- Scenario C: the excluded match is played much later and scored anyway.
select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ) = current_setting('test.cutoff_scores'),
  'a late result never adds points to a closed Cup round'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.cutoff_state'),
  'a late result never changes a closed round winner'
);

select pg_temp.cup_assert(
  (
    select state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 1,
  'an excluded match stays excluded once it is finally finished'
);

rollback to savepoint cutoff_tests;

-- Scenario F: the cutoff decision is taken before the late result is entered,
-- which is the only moment the evidence still exists. This is the order Phase
-- 2B will follow inside set_match_result.
select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

select pg_temp.cup_assert(
  public.players_cup_freeze_exclusions(pg_temp.cup_id()) = 0
  and (select count(*) from public.cup_excluded_matches) = 0,
  'freezing before the cutoff excludes nothing'
);

-- The cutoff passes and nobody recomputes the Cup at that moment.
select pg_temp.cup_open_matchday(4);

select set_config('test.pre_freeze_state', pg_temp.cup_state(), true);

select pg_temp.cup_assert(
  public.players_cup_freeze_exclusions(pg_temp.cup_id()) = 1,
  'the freeze helper closes the cutoff on its own, without a recompute'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_excluded_matches as excluded_match
    where excluded_match.cup_id = pg_temp.cup_id()
      and excluded_match.round_id = pg_temp.cup_round_id(1)
      and excluded_match.match_id
        = current_setting('test.postponed_match')::bigint
  ) = 1,
  'the frozen row names the match and the Cup round it missed'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.pre_freeze_state'),
  'freezing exclusions touches no tie, round status or award'
);

-- Repeated freezing must stay a no-op, including the stored decision itself.
select set_config(
  'test.frozen_row',
  (
    select excluded_match.id
      || ':' || excluded_match.round_id
      || ':' || excluded_match.cutoff_at
    from public.cup_excluded_matches as excluded_match
    where excluded_match.match_id
      = current_setting('test.postponed_match')::bigint
  ),
  true
);

select pg_temp.cup_assert(
  public.players_cup_freeze_exclusions(pg_temp.cup_id()) = 0
  and public.players_cup_freeze_exclusions(pg_temp.cup_id()) = 0,
  'a repeated freeze finds nothing new to exclude'
);

select pg_temp.cup_assert(
  (select count(*) from public.cup_excluded_matches) = 1
  and (
    select excluded_match.id
      || ':' || excluded_match.round_id
      || ':' || excluded_match.cutoff_at
    from public.cup_excluded_matches as excluded_match
    where excluded_match.match_id
      = current_setting('test.postponed_match')::bigint
  ) = current_setting('test.frozen_row'),
  'a repeated freeze neither duplicates nor rewrites the decision'
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select set_config('test.frozen_closed_state', pg_temp.cup_state(), true);
select set_config(
  'test.frozen_closed_scores',
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ),
  true
);

-- Days later the match is finally played and scored. Its kickoff was never
-- moved, so nothing in the match row still shows that it missed the cutoff.
select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);

select pg_temp.cup_assert(
  (
    select match_row.status = 'finished'
      and match_row.kickoff_at < round_match.cutoff_at
    from public.matches as match_row
    join public.players_cup_round_matches(pg_temp.cup_id()) as round_match
      on round_match.match_id = match_row.id
    where match_row.id = current_setting('test.postponed_match')::bigint
  ),
  'a late result leaves a finished match with a pre-cutoff kickoff'
);

select pg_temp.cup_assert(
  (
    select round_match.is_excluded and round_match.exclusion_is_frozen
    from public.players_cup_round_matches(pg_temp.cup_id()) as round_match
    where round_match.match_id
      = current_setting('test.postponed_match')::bigint
  ),
  'only the frozen decision still proves the match missed its Cup round'
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select string_agg(
      score.participant_id || ':' || score.points,
      ',' order by score.participant_id
    )
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
  ) = current_setting('test.frozen_closed_scores'),
  'a result entered after a pre-result freeze adds no Cup points'
);

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.frozen_closed_state'),
  'a result entered after a pre-result freeze changes no Round 1 winner'
);

rollback to savepoint cutoff_tests;

-- ---------------------------------------------------------------------------
-- 9. Cutoff without a frozen row, and the Final without a cutoff
-- ---------------------------------------------------------------------------

savepoint cutoff_derivation_tests;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

-- The postponed match is rescheduled after the next matchday starts, and is
-- then played and scored before any recompute ever ran after the cutoff.
select pg_temp.cup_open_matchday(4);

update public.matches as match_row
set
  kickoff_at = now() - interval '30 minutes',
  status = 'postponed',
  updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);

select pg_temp.cup_assert(
  (
    select round_match.is_excluded
    from public.players_cup_round_matches(pg_temp.cup_id()) as round_match
    where round_match.match_id
      = current_setting('test.postponed_match')::bigint
  ),
  'a match rescheduled past the cutoff is excluded without a frozen row'
);

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select state.is_complete::text
      || ':' || state.included_count
      || ':' || state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 'true:2:1',
  'a kickoff after the cutoff proves the match missed its Cup round'
);

-- Scenario E: the Final has no next matchday, so it never closes early.
select pg_temp.cup_assert(
  (
    select state.cutoff_at is null
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 6
  ),
  'the Final has no cutoff'
);

select pg_temp.cup_open_matchday(8);
update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.matchday_id = pg_temp.cup_matchday_id(8)
  and match_row.id = (
    select max(inner_match.id)
    from public.matches as inner_match
    where inner_match.matchday_id = pg_temp.cup_matchday_id(8)
  );

select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  (
    select state.is_complete::text || ':' || state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 6
  ) = 'false:0',
  'an unresolved Matchday 8 match leaves the Final unresolved'
);

select public.players_cup_freeze_exclusions(pg_temp.cup_id());

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_excluded_matches as excluded_match
    join public.matches as match_row
      on match_row.id = excluded_match.match_id
    where match_row.matchday_id = pg_temp.cup_matchday_id(8)
  ),
  'the freeze helper never excludes a Matchday 8 match'
);

select pg_temp.cup_assert(
  (
    select competition.status
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 'active'
  and (select count(*) from public.cup_awards) = 0,
  'an unresolved Final grants no award and keeps the Cup active'
);

rollback to savepoint cutoff_derivation_tests;

-- ---------------------------------------------------------------------------
-- 10. Cup matchday membership immutability
-- ---------------------------------------------------------------------------

savepoint membership_tests;

do $test$
declare
  v_match_id bigint;
begin
  select match_row.id
  into v_match_id
  from public.matches as match_row
  where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  order by match_row.id
  limit 1;

  begin
    update public.matches as match_row
    set matchday_id = pg_temp.cup_matchday_id(4)
    where match_row.id = v_match_id;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a Matchday 3 match moved to Matchday 4';
  exception
    when invalid_parameter_value then
      if sqlerrm <> 'A Players Cup matchday match cannot be moved to another matchday'
      then
        raise;
      end if;
  end;

  begin
    update public.matches as match_row
    set matchday_id = pg_temp.cup_matchday_id(1)
    where match_row.id = v_match_id;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a Cup match moved out of the Cup calendar';
  exception
    when invalid_parameter_value then null;
  end;

  select match_row.id
  into v_match_id
  from public.matches as match_row
  where match_row.matchday_id = pg_temp.cup_matchday_id(4)
  order by match_row.id
  limit 1;

  begin
    update public.matches as match_row
    set matchday_id = pg_temp.cup_matchday_id(5)
    where match_row.id = v_match_id;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a Matchday 4 match moved to Matchday 5';
  exception
    when invalid_parameter_value then null;
  end;

  select match_row.id
  into v_match_id
  from public.matches as match_row
  where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  order by match_row.id
  limit 1;

  begin
    update public.matches as match_row
    set matchday_id = pg_temp.cup_matchday_id(3)
    where match_row.id = v_match_id;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a match moved into the Cup calendar';
  exception
    when invalid_parameter_value then null;
  end;
end;
$test$;

-- Everything except matchday membership stays editable.
do $test$
declare
  v_match_id bigint;
begin
  select match_row.id
  into v_match_id
  from public.matches as match_row
  where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  order by match_row.id
  limit 1;

  update public.matches as match_row
  set kickoff_at = match_row.kickoff_at + interval '1 day', updated_at = now()
  where match_row.id = v_match_id;

  update public.matches as match_row
  set status = 'postponed', updated_at = now()
  where match_row.id = v_match_id;

  update public.matches as match_row
  set matchday_id = match_row.matchday_id, kickoff_at = match_row.kickoff_at
  where match_row.id = v_match_id;

  perform public.set_match_result(v_match_id, 3, 1);
end;
$test$;

select pg_temp.cup_assert(
  (
    select match_row.home_score || ':' || match_row.status
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
    order by match_row.id
    limit 1
  ) = '3:finished',
  'kickoff, status and result updates are never blocked'
);

-- Matchday 1 and 2 are outside the Cup calendar and stay movable.
do $test$
declare
  v_match_id bigint;
begin
  select match_row.id
  into v_match_id
  from public.matches as match_row
  where match_row.matchday_id = pg_temp.cup_matchday_id(1)
  order by match_row.id
  limit 1;

  update public.matches as match_row
  set matchday_id = pg_temp.cup_matchday_id(2)
  where match_row.id = v_match_id;
end;
$test$;

select pg_temp.cup_assert(
  (
    select count(*)
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(2)
  ) = 3,
  'matches outside the Cup calendar can still be moved'
);

rollback to savepoint membership_tests;

-- ---------------------------------------------------------------------------
-- 11. Disabled and deleted participants
-- ---------------------------------------------------------------------------

savepoint deletion_tests;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);
select pg_temp.cup_score_matchday(3, 1, 0);
select pg_temp.cup_recompute();

select set_config(
  'test.deleted_participant',
  pg_temp.cup_participant_id(11)::text,
  true
);
select set_config(
  'test.deleted_snapshot',
  (
    select participant.username_snapshot
    from public.cup_participants as participant
    where participant.id = current_setting('test.deleted_participant')::bigint
  ),
  true
);

-- Disabling a player keeps every point they already earned.
update public.profiles as profile
set status = 'disabled'
where profile.id = pg_temp.cup_user_id(12);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select score.points
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id = pg_temp.cup_participant_id(12)
  ) = (pg_temp.cup_expected_points(12, 3))[1],
  'a disabled participant keeps the points they already earned'
);

-- Deleting the account empties user_id but keeps the bracket intact.
delete from auth.users as account
where account.id = pg_temp.cup_user_id(11);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select participant.user_id is null
      and participant.username_snapshot = current_setting('test.deleted_snapshot')
    from public.cup_participants as participant
    where participant.id = current_setting('test.deleted_participant')::bigint
  ),
  'a deleted account leaves the participant row and its username snapshot'
);

select pg_temp.cup_assert(
  (
    select score.points || ':' || score.exact_count || ':' || score.correct_count
    from public.players_cup_matchday_scores(
      pg_temp.cup_id(),
      pg_temp.cup_matchday_id(3)
    ) as score
    where score.participant_id
      = current_setting('test.deleted_participant')::bigint
  ) = '0:0:0',
  'a deleted participant scores 0/0/0 instead of breaking the aggregation'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.cup_id = pg_temp.cup_id()
      and (
        tie.home_participant_id
          = current_setting('test.deleted_participant')::bigint
        or tie.away_participant_id
          = current_setting('test.deleted_participant')::bigint
      )
  ) > 0,
  'a deleted participant stays in the bracket'
);

-- Two players with no predictions at all fall through to the ranking.
savepoint deletion_rank_fallback;

delete from public.predictions as prediction
using public.matches as match_row
where match_row.id = prediction.match_id
  and match_row.matchday_id = pg_temp.cup_matchday_id(3);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'decided'
      and tie.decided_by_rule <> 'rank_position'
  ),
  'a matchday nobody predicted is decided entirely by rank_position'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as tie
    join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'decided'
      and tie.winner_participant_id <> case
        when home_participant.rank_position < away_participant.rank_position
          then tie.home_participant_id
        else tie.away_participant_id
      end
  ),
  'the better ranking always advances when both players score nothing'
);

rollback to savepoint deletion_rank_fallback;
rollback to savepoint deletion_tests;

-- ---------------------------------------------------------------------------
-- 12. Tie-break rules end to end on an eight player field
-- ---------------------------------------------------------------------------

savepoint tie_break_tests;

delete from public.cup_competitions;

update public.profiles as profile
set status = 'disabled'
where profile.id in (
  select pg_temp.cup_user_id(player.index)
  from generate_series(9, 40) as player(index)
);

set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_assert(
  (
    select competition.participant_count
    from public.cup_competitions as competition
    where competition.id = pg_temp.cup_id()
  ) = 8,
  'the eight player Cup is created'
);

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(8);
select pg_temp.cup_assert_entry_rounds(8);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_ties as tie
    join public.cup_rounds as round on round.id = tie.round_id
    where round.cup_id = pg_temp.cup_id()
      and round.round_number between 1 and 3
      and tie.outcome not in ('bye', 'empty')
  )
  and pg_temp.cup_round_status(1) = 'final'
  and pg_temp.cup_round_status(2) = 'final'
  and pg_temp.cup_round_status(3) = 'final',
  'eight players resolve rounds 1 to 3 structurally, before any Cup football'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_participants as participant
    where participant.cup_id = pg_temp.cup_id()
      and participant.entry_round <> 4
  )
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(4)
      and tie.home_participant_id is not null
      and tie.away_participant_id is not null
  ) = 4,
  'eight players first meet a real opponent in the quarter-final'
);

-- Matchday 6 needs five matches so points can be tied while exact and correct
-- counts differ.
select pg_temp.cup_add_matches(6, 2, now() + interval '12 days');
select pg_temp.cup_open_matchday(6);

do $fixture$
declare
  v_slot integer;
  v_tie public.cup_ties;
  v_home uuid;
  v_away uuid;
  v_matchday_id bigint := pg_temp.cup_matchday_id(6);
  v_matches bigint[];
begin
  select array_agg(match_row.id order by match_row.id)
  into v_matches
  from public.matches as match_row
  where match_row.matchday_id = v_matchday_id;

  for v_slot in 1..4 loop
    select * into v_tie from pg_temp.cup_tie(4, v_slot) as tie;

    select participant.user_id
    into v_home
    from public.cup_participants as participant
    where participant.id = v_tie.home_participant_id;

    select participant.user_id
    into v_away
    from public.cup_participants as participant
    where participant.id = v_tie.away_participant_id;

    if v_slot = 1 then
      -- Points decide: one exact score against nothing at all.
      insert into public.predictions (
        user_id, match_id, predicted_home_score, predicted_away_score
      )
      values (v_home, v_matches[1], 1, 0);
    elsif v_slot = 2 then
      -- Exact scores decide: 10 points from one Golden exact against 10 points
      -- from five correct results.
      insert into public.predictions (
        user_id, match_id, predicted_home_score, predicted_away_score
      )
      values (v_home, v_matches[1], 1, 0);

      insert into public.golden_match_selections (user_id, matchday_id, match_id)
      values (v_home, v_matchday_id, v_matches[1]);

      insert into public.predictions (
        user_id, match_id, predicted_home_score, predicted_away_score
      )
      select v_away, match_id, 2, 0
      from unnest(v_matches) as listed(match_id);
    elsif v_slot = 3 then
      -- Correct results decide: 4 points from two correct results against 4
      -- points from one Golden correct result.
      insert into public.predictions (
        user_id, match_id, predicted_home_score, predicted_away_score
      )
      values (v_home, v_matches[1], 2, 0), (v_home, v_matches[2], 2, 0);

      insert into public.predictions (
        user_id, match_id, predicted_home_score, predicted_away_score
      )
      values (v_away, v_matches[1], 2, 0);

      insert into public.golden_match_selections (user_id, matchday_id, match_id)
      values (v_away, v_matchday_id, v_matches[1]);
    end if;
    -- Slot 4 predicts nothing at all, so only the frozen ranking is left.
  end loop;
end;
$fixture$;

select pg_temp.cup_score_matchday(6, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(8);

select pg_temp.cup_assert(
  (select tie.decided_by_rule from pg_temp.cup_tie(4, 1) as tie) = 'points'
  and (
    select tie.winner_participant_id = tie.home_participant_id
    from pg_temp.cup_tie(4, 1) as tie
  ),
  'more Cup points decide a tie'
);

select pg_temp.cup_assert(
  (select tie.decided_by_rule from pg_temp.cup_tie(4, 2) as tie) = 'exact'
  and (
    select tie.home_points = tie.away_points
      and tie.home_exact > tie.away_exact
      and tie.winner_participant_id = tie.home_participant_id
    from pg_temp.cup_tie(4, 2) as tie
  ),
  'equal points are broken by more exact scores'
);

select pg_temp.cup_assert(
  (select tie.decided_by_rule from pg_temp.cup_tie(4, 3) as tie) = 'correct'
  and (
    select tie.home_points = tie.away_points
      and tie.home_exact = tie.away_exact
      and tie.home_correct > tie.away_correct
      and tie.winner_participant_id = tie.home_participant_id
    from pg_temp.cup_tie(4, 3) as tie
  ),
  'equal points and exact scores are broken by more correct results'
);

select pg_temp.cup_assert(
  (select tie.decided_by_rule from pg_temp.cup_tie(4, 4) as tie)
    = 'rank_position'
  and (
    select tie.home_points = 0
      and tie.away_points = 0
      and tie.winner_participant_id = case
        when home_participant.rank_position < away_participant.rank_position
          then tie.home_participant_id
        else tie.away_participant_id
      end
    from pg_temp.cup_tie(4, 4) as tie
    join public.cup_participants as home_participant
      on home_participant.id = tie.home_participant_id
    join public.cup_participants as away_participant
      on away_participant.id = tie.away_participant_id
  ),
  'a goalless tie is broken by the better frozen ranking'
);

select pg_temp.cup_assert(
  (
    select count(distinct tie.decided_by_rule)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(4)
  ) = 4,
  'all four tie-break rules occur in one quarter-final round'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(4)
      and (
        tie.winner_participant_id is null
        or tie.decided_by_rule is null
        or tie.outcome <> 'decided'
      )
  ) = 0,
  'no contested completed tie is ever left unresolved'
);

select pg_temp.cup_assert(
  (select tie.outcome from pg_temp.cup_tie(5, 1) as tie) = 'pending'
  and (select tie.outcome from pg_temp.cup_tie(6, 1) as tie) = 'pending',
  'the semi-finals and Final wait for their own matchdays'
);

rollback to savepoint tie_break_tests;

-- ---------------------------------------------------------------------------
-- 13. Other structural field sizes
-- ---------------------------------------------------------------------------

savepoint field_size_tests;

delete from public.cup_competitions;

update public.profiles as profile
set status = 'disabled'
where profile.id in (
  select pg_temp.cup_user_id(player.index)
  from generate_series(18, 40) as player(index)
);

set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(17);
select pg_temp.cup_assert_entry_rounds(17);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'bye'
  ) = 17
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(2)
      and tie.home_participant_id is not null
      and tie.away_participant_id is not null
  ) = 1,
  'seventeen players give 17 opening byes and one contested round 2 tie'
);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_participants as participant
    where participant.cup_id = pg_temp.cup_id()
      and participant.entry_round = 2
  ) = 2,
  'only the two players sharing a round 2 tie enter in round 2'
);

rollback to savepoint field_size_tests;

savepoint full_field_tests;

delete from public.cup_competitions;

select pg_temp.cup_add_players(41, 64);

set local role authenticated;
select public.create_players_cup();
reset role;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(64);
select pg_temp.cup_assert_entry_rounds(64);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'bye'
  ) = 0
  and (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.outcome = 'pending'
  ) = 32,
  'sixty-four players contest all 32 opening ties and receive no bye'
);

select pg_temp.cup_assert(
  not exists (
    select 1
    from public.cup_participants as participant
    where participant.cup_id = pg_temp.cup_id()
      and participant.entry_round <> 1
  ),
  'a full field enters in round 1'
);

rollback to savepoint full_field_tests;

-- ---------------------------------------------------------------------------
-- 14. Mutation tests
-- ---------------------------------------------------------------------------

savepoint mutation_tests;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

-- Mutation 1: treat a single known participant as a bye, whatever the bracket
-- structure says. Round 2 currently holds 16 half filled ties.
savepoint mutation_bye;

create or replace function public.players_cup_tie_outcome(
  p_home_capacity integer,
  p_away_capacity integer,
  p_home_participant_id bigint,
  p_away_participant_id bigint,
  p_round_is_complete boolean
)
returns text
language sql
immutable
set search_path = ''
as $mutant$
  -- Empty and decided stay correct on purpose, so only the difference between
  -- a structural bye and a tie that is still waiting is broken.
  select case
    when p_home_capacity = 0 and p_away_capacity = 0 then 'empty'
    when p_home_participant_id is null and p_away_participant_id is null
      then 'pending'
    when p_home_participant_id is null or p_away_participant_id is null
      then 'bye'
    when not p_round_is_complete then 'pending'
    else 'decided'
  end;
$mutant$;

do $test$
begin
  begin
    perform pg_temp.cup_recompute();
    perform pg_temp.cup_assert_consistency(40);
    raise exception
      'PLAYERS CUP 2A TEST FAILED: the waiting-as-bye mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_bye;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

-- Mutation 2: feed the previous even slot into the home side.
savepoint mutation_feeder;

create or replace function public.players_cup_round_entrants(
  p_cup_id bigint,
  p_round_number integer
)
returns table (
  slot integer,
  home_participant_id bigint,
  away_participant_id bigint
)
language sql
stable
security definer
set search_path = ''
as $mutant$
  select
    pairing.slot,
    home_participant.id,
    away_participant.id
  from (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1)
        as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0)
        as away_bracket_position
    from public.players_cup_bracket_slots(64) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ) as pairing
  left join public.cup_participants as home_participant
    on home_participant.cup_id = p_cup_id
    and home_participant.bracket_position = pairing.home_bracket_position
  left join public.cup_participants as away_participant
    on away_participant.cup_id = p_cup_id
    and away_participant.bracket_position = pairing.away_bracket_position
  where p_round_number = 1
  union all
  select
    ((previous_tie.slot + 1) / 2)::integer,
    max(previous_tie.winner_participant_id)
      filter (where previous_tie.slot % 2 = 0),
    max(previous_tie.winner_participant_id)
      filter (where previous_tie.slot % 2 = 1)
  from public.cup_ties as previous_tie
  join public.cup_rounds as previous_round
    on previous_round.id = previous_tie.round_id
  where p_round_number > 1
    and previous_round.cup_id = p_cup_id
    and previous_round.round_number = p_round_number - 1
  group by ((previous_tie.slot + 1) / 2);
$mutant$;

do $test$
begin
  begin
    perform pg_temp.cup_recompute();
    perform pg_temp.cup_assert_consistency(40);
    raise exception
      'PLAYERS CUP 2A TEST FAILED: the swapped feeder mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_feeder;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

-- Mutation 3: reverse the ranking fallback. Matchday 3 is played but nobody
-- predicted, so every contested opening tie falls through to rank_position.
select pg_temp.cup_open_matchday(3);
select pg_temp.cup_score_matchday(3, 1, 0);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select count(*)
    from public.cup_ties as tie
    where tie.round_id = pg_temp.cup_round_id(1)
      and tie.decided_by_rule = 'rank_position'
  ) = 8,
  'an unpredicted matchday leaves the ranking as the only tie-break'
);

savepoint mutation_rank;

create or replace function public.players_cup_tie_break(
  p_home_points integer,
  p_away_points integer,
  p_home_exact integer,
  p_away_exact integer,
  p_home_correct integer,
  p_away_correct integer,
  p_home_rank_position integer,
  p_away_rank_position integer
)
returns table (
  decided_by_rule text,
  home_wins boolean
)
language sql
immutable
set search_path = ''
as $mutant$
  select
    case
      when p_home_points <> p_away_points then 'points'
      when p_home_exact <> p_away_exact then 'exact'
      when p_home_correct <> p_away_correct then 'correct'
      else 'rank_position'
    end,
    case
      when p_home_points <> p_away_points
        then p_home_points > p_away_points
      when p_home_exact <> p_away_exact
        then p_home_exact > p_away_exact
      when p_home_correct <> p_away_correct
        then p_home_correct > p_away_correct
      else p_home_rank_position > p_away_rank_position
    end;
$mutant$;

do $test$
begin
  begin
    perform pg_temp.cup_recompute();
    perform pg_temp.cup_assert_consistency(40);
    raise exception
      'PLAYERS CUP 2A TEST FAILED: the reversed ranking mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_rank;

select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

rollback to savepoint mutation_tests;

-- Mutation 4: let a match that missed its cutoff back into the Cup round once
-- it is finally finished.
savepoint mutation_cutoff_setup;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

select pg_temp.cup_open_matchday(4);
select pg_temp.cup_recompute();

select set_config('test.closed_state', pg_temp.cup_state(), true);

select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);
select pg_temp.cup_recompute();

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.closed_state'),
  'the real implementation keeps the closed round closed'
);

savepoint mutation_cutoff;

create or replace function public.players_cup_round_matches(p_cup_id bigint)
returns table (
  round_number integer,
  round_id bigint,
  matchday_id bigint,
  cutoff_at timestamptz,
  match_id bigint,
  match_status text,
  kickoff_at timestamptz,
  is_excluded boolean,
  exclusion_is_frozen boolean
)
language sql
stable
security definer
set search_path = ''
as $mutant$
  with cup_round as (
    select
      round.round_number,
      round.id as round_id,
      round.matchday_id,
      matchday.matchday_number
    from public.cup_rounds as round
    join public.matchdays as matchday
      on matchday.id = round.matchday_id
    where round.cup_id = p_cup_id
  ),
  round_cutoff as (
    select
      cup_round.round_number,
      cup_round.round_id,
      cup_round.matchday_id,
      case
        when cup_round.round_number <= 5 then (
          select min(next_match.kickoff_at)
          from public.matches as next_match
          join public.matchdays as next_matchday
            on next_matchday.id = next_match.matchday_id
          where next_matchday.stage = 'league_phase'
            and next_matchday.matchday_number = cup_round.matchday_number + 1
        )
      end as cutoff_at
    from cup_round
  )
  select
    round_cutoff.round_number,
    round_cutoff.round_id,
    round_cutoff.matchday_id,
    round_cutoff.cutoff_at,
    match_row.id,
    match_row.status,
    match_row.kickoff_at,
    coalesce(
      round_cutoff.cutoff_at is not null
      and now() >= round_cutoff.cutoff_at
      and match_row.status <> 'finished',
      false
    ),
    false
  from round_cutoff
  left join public.matches as match_row
    on match_row.matchday_id = round_cutoff.matchday_id;
$mutant$;

do $test$
begin
  begin
    perform pg_temp.cup_recompute();

    if pg_temp.cup_state() is distinct from current_setting('test.closed_state')
    then
      raise exception 'PLAYERS CUP 2A MUTATION DETECTED';
    end if;

    if (
      select state.excluded_count
      from public.players_cup_matchday_state(pg_temp.cup_id()) as state
      where state.round_number = 1
    ) <> 1 then
      raise exception 'PLAYERS CUP 2A MUTATION DETECTED';
    end if;

    raise exception
      'PLAYERS CUP 2A TEST FAILED: the reopened cutoff mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_cutoff;

select pg_temp.cup_recompute();
select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.closed_state'),
  'restoring the implementation restores the closed round'
);

rollback to savepoint mutation_cutoff_setup;

-- Mutation 5: stop freezing the cutoff before the football write. Nothing is
-- frozen while the match is still visibly unfinished, so the late result finds
-- a finished match with a pre-cutoff kickoff and walks back into Round 1.
savepoint mutation_freeze_setup;

select pg_temp.cup_open_matchday(3);
select pg_temp.cup_predict_matchday(3, 1, 40);

select set_config(
  'test.postponed_match',
  (
    select max(match_row.id)::text
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
  ),
  true
);

do $fixture$
declare
  v_match_id bigint;
begin
  for v_match_id in
    select match_row.id
    from public.matches as match_row
    where match_row.matchday_id = pg_temp.cup_matchday_id(3)
      and match_row.id <> current_setting('test.postponed_match')::bigint
    order by match_row.id
  loop
    perform public.set_match_result(v_match_id, 1, 0);
  end loop;
end;
$fixture$;

update public.matches as match_row
set status = 'postponed', updated_at = now()
where match_row.id = current_setting('test.postponed_match')::bigint;

-- The cutoff passes with nothing frozen yet, which is the state Phase 2B will
-- find when the admin finally enters the postponed result.
select pg_temp.cup_open_matchday(4);

savepoint mutation_freeze;

create or replace function public.players_cup_freeze_exclusions(p_cup_id bigint)
returns integer
language sql
volatile
security definer
set search_path = ''
as $mutant$
  select 0;
$mutant$;

do $test$
begin
  begin
    perform public.players_cup_freeze_exclusions(pg_temp.cup_id());
    perform public.set_match_result(
      current_setting('test.postponed_match')::bigint,
      1,
      0
    );
    perform pg_temp.cup_recompute();

    if (
      select state.excluded_count
      from public.players_cup_matchday_state(pg_temp.cup_id()) as state
      where state.round_number = 1
    ) <> 1 then
      raise exception 'PLAYERS CUP 2A MUTATION DETECTED';
    end if;

    raise exception
      'PLAYERS CUP 2A TEST FAILED: the skipped freeze mutation was not detected';
  exception
    when others then
      if position('was not detected' in sqlerrm) > 0 then
        raise;
      end if;
  end;
end;
$test$;

rollback to savepoint mutation_freeze;

-- The same sequence with the real helper keeps the round closed.
select public.players_cup_freeze_exclusions(pg_temp.cup_id());
select public.set_match_result(
  current_setting('test.postponed_match')::bigint,
  1,
  0
);
select pg_temp.cup_recompute();
select pg_temp.cup_assert_consistency(40);

select pg_temp.cup_assert(
  (
    select state.excluded_count
    from public.players_cup_matchday_state(pg_temp.cup_id()) as state
    where state.round_number = 1
  ) = 1,
  'restoring the freeze helper keeps the late result out of Round 1'
);

rollback to savepoint mutation_freeze_setup;

-- ---------------------------------------------------------------------------
-- 15. Security
-- ---------------------------------------------------------------------------

savepoint security_tests;

select pg_temp.cup_recompute();

select set_config('test.cup_id', pg_temp.cup_id()::text, true);
select set_config(
  'test.matchday_3',
  pg_temp.cup_matchday_id(3)::text,
  true
);
select set_config('test.security_state', pg_temp.cup_state(), true);

-- A normal player.
select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);

set local role authenticated;

do $test$
begin
  begin
    perform public.recompute_players_cup();
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player recomputed the Cup';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;

  begin
    perform public.players_cup_apply(current_setting('test.cup_id')::bigint);
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player ran the engine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_matchday_scores(
      current_setting('test.cup_id')::bigint,
      current_setting('test.matchday_3')::bigint
    );
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a player read every player''s scores';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_matchday_state(
      current_setting('test.cup_id')::bigint
    );
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player read round readiness';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_tie_layout(40);
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player read the tie layout';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_freeze_exclusions(
      current_setting('test.cup_id')::bigint
    );
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player froze an exclusion';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_round_entrants(
      current_setting('test.cup_id')::bigint,
      2
    );
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player read round entrants';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.prediction_is_exact(5);
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player ran a classifier';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.players_cup_lock_key();
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player read the lock key';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.cup_awards (cup_id, participant_id, award_type, points)
    values (current_setting('test.cup_id')::bigint, 1, 'winner', 999);
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player granted an award';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_awards as award set points = 999;
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player changed an award';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.cup_awards;
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player deleted awards';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_ties as tie
    set winner_participant_id = tie.home_participant_id, outcome = 'decided';
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player decided a tie';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cup_rounds as round set status = 'final';
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player finalised a round';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.cup_excluded_matches (
      cup_id,
      round_id,
      match_id,
      cutoff_at
    )
    values (current_setting('test.cup_id')::bigint, 1, 1, now());
    raise exception 'PLAYERS CUP 2A TEST FAILED: a player excluded a match';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.cup_excluded_matches;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a player reopened a closed round';
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
    perform 1 from public.cup_awards;
    raise exception 'PLAYERS CUP 2A TEST FAILED: anon read Cup awards';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform 1 from public.cup_excluded_matches;
    raise exception
      'PLAYERS CUP 2A TEST FAILED: anon read excluded Cup matches';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.recompute_players_cup();
    raise exception 'PLAYERS CUP 2A TEST FAILED: anon recomputed the Cup';
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

-- A disabled administrator is rejected as well.
update public.profiles as profile
set status = 'disabled'
where profile.id = pg_temp.cup_user_id(1);

set local role authenticated;

do $test$
begin
  begin
    perform public.recompute_players_cup();
    raise exception
      'PLAYERS CUP 2A TEST FAILED: a disabled admin recomputed the Cup';
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

-- The active administrator path runs through the authenticated role, exactly
-- as the browser would use it.
set local role authenticated;
select public.recompute_players_cup();
reset role;

select pg_temp.cup_assert(
  pg_temp.cup_state() = current_setting('test.security_state'),
  'the rejected writes left the Cup untouched'
);

-- Players may still read the Cup honours list.
select set_config(
  'request.jwt.claim.sub',
  pg_temp.cup_user_id(2)::text,
  true
);

set local role authenticated;

do $test$
begin
  perform 1 from public.cup_awards;
  perform 1 from public.cup_excluded_matches;
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
-- 16. Recovery RPC without a Cup
-- ---------------------------------------------------------------------------

savepoint no_cup_tests;

delete from public.cup_competitions;

set local role authenticated;
select set_config(
  'test.no_cup_summary',
  (public.recompute_players_cup())::text,
  true
);
reset role;

select pg_temp.cup_assert(
  (current_setting('test.no_cup_summary')::jsonb ->> 'cup_exists') = 'false',
  'the recovery RPC reports a missing Cup instead of raising'
);

rollback to savepoint no_cup_tests;

reset role;
rollback;

-- Runs after the rollback, so it cannot use the pg_temp helpers.
do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzcup%'
  ) then
    raise exception 'PLAYERS CUP 2A TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'prediction_is_exact_accepts_only_5_and_10',
  'prediction_is_correct_accepts_only_2_and_4',
  'no_points_value_is_both_exact_and_correct',
  'classifiers_match_semantic_prediction_truth',
  'layout_describes_all_63_ties',
  'layout_matches_template_for_every_field_size',
  'sibling_feeders_never_differ_by_more_than_one',
  'eight_players_give_eight_byes_and_four_quarter_finals',
  'forty_players_give_eight_contested_ties_and_24_byes',
  'sixty_four_players_give_no_opening_bye',
  'seventeen_players_contest_one_round_2_tie',
  'tie_outcome_separates_empty_bye_waiting_and_decided',
  'tie_break_walks_points_exact_correct_rank_position',
  'fixture_cup_has_40_participants',
  'rank_position_follows_player_index',
  'opening_round_starts_with_24_byes_and_8_ties',
  'nothing_decided_before_any_cup_match',
  'unreachable_rounds_stay_pending',
  'round_1_byes_reach_round_2_without_winning_there',
  'partly_played_matchday_is_not_complete',
  'interim_scores_appear_while_matchday_runs',
  'no_tie_decided_while_matchday_incomplete',
  'incomplete_round_reports_in_progress',
  'completing_matchday_3_decides_all_opening_ties',
  'cup_scores_equal_raw_prediction_points',
  'matchday_4_decides_all_sixteen_round_2_ties',
  'fully_played_matchday_loses_nothing_to_the_cutoff',
  'final_waits_for_matchday_8',
  'no_award_before_the_final_is_decided',
  'matchday_8_decides_the_final_and_completes_the_cup',
  'finished_cup_decides_39_ties_and_leaves_none_pending',
  'completed_cup_produces_exactly_one_champion',
  'champion_receives_the_winner_award_only',
  'honours_list_is_one_one_and_two',
  'losing_finalist_receives_the_finalist_award',
  'both_beaten_semi_finalists_receive_semi_finalist',
  'awards_mirror_the_participant_user_reference',
  'reward_reconfiguration_applied_by_next_recompute',
  'restored_reward_configuration_restores_award_values',
  'repeated_recomputes_are_semantically_identical',
  'repeated_recomputes_never_duplicate_a_row',
  'matchday_1_correction_never_reorders_the_entry_list',
  'matchday_1_correction_changes_no_cup_result',
  'reopening_the_final_withdraws_every_award',
  'restoring_the_last_result_restores_the_completed_cup',
  'matchday_8_correction_can_change_the_champion',
  'new_champion_takes_over_the_winner_award',
  'unchanged_semi_final_awards_stay_untouched',
  'matchday_3_correction_changes_a_round_1_winner',
  'replaced_winner_disappears_from_downstream_bracket',
  'corrected_cup_still_has_exactly_four_awards',
  'no_stale_award_survives_a_correction',
  'repeated_recompute_after_correction_is_identical',
  'normal_exact_is_5_points_and_one_exact',
  'golden_exact_is_10_points_and_one_exact',
  'normal_correct_is_2_points_and_one_correct',
  'golden_correct_is_4_points_and_one_correct',
  'wrong_prediction_and_long_term_award_score_nothing',
  'participant_without_predictions_scores_zero',
  'other_matchday_predictions_never_leak',
  'aggregation_returns_one_row_per_participant',
  'postponed_match_keeps_its_round_open_before_cutoff',
  'no_exclusion_frozen_before_the_cutoff',
  'postponed_match_played_before_cutoff_counts',
  'cutoff_closes_the_round_without_the_unfinished_match',
  'exclusion_decision_frozen_exactly_once',
  'closed_round_is_final_without_the_missing_match',
  'late_result_adds_no_points_to_a_closed_round',
  'late_result_never_changes_a_closed_round_winner',
  'excluded_match_stays_excluded_once_finished',
  'freezing_before_the_cutoff_excludes_nothing',
  'freeze_helper_closes_the_cutoff_without_a_recompute',
  'frozen_row_names_the_match_and_the_cup_round',
  'freezing_touches_no_tie_round_or_award',
  'repeated_freeze_finds_nothing_new',
  'repeated_freeze_neither_duplicates_nor_rewrites',
  'late_result_leaves_a_pre_cutoff_kickoff',
  'only_the_frozen_decision_still_proves_the_miss',
  'pre_result_freeze_blocks_late_cup_points',
  'pre_result_freeze_protects_the_round_1_winner',
  'kickoff_after_cutoff_excludes_without_a_frozen_row',
  'the_final_has_no_cutoff',
  'unresolved_matchday_8_leaves_the_final_open',
  'freeze_helper_never_excludes_a_matchday_8_match',
  'unresolved_final_grants_no_award',
  'matchday_3_match_cannot_move_to_matchday_4',
  'cup_match_cannot_leave_the_cup_calendar',
  'matchday_4_match_cannot_move_to_matchday_5',
  'match_cannot_move_into_the_cup_calendar',
  'kickoff_status_and_result_updates_are_allowed',
  'matches_outside_the_cup_calendar_stay_movable',
  'disabled_participant_keeps_earned_points',
  'deleted_account_keeps_participant_and_snapshot',
  'deleted_participant_scores_zero',
  'deleted_participant_stays_in_the_bracket',
  'unpredicted_matchday_decided_by_rank_position',
  'better_ranking_advances_when_both_score_nothing',
  'eight_player_cup_is_created',
  'eight_players_resolve_rounds_1_to_3_structurally',
  'eight_players_first_meet_in_the_quarter_final',
  'more_cup_points_decide_a_tie',
  'equal_points_broken_by_more_exact_scores',
  'equal_points_and_exact_broken_by_more_correct',
  'goalless_tie_broken_by_the_better_ranking',
  'all_four_tie_break_rules_occur_in_one_round',
  'no_contested_completed_tie_is_left_unresolved',
  'semi_finals_and_final_wait_for_their_matchdays',
  'seventeen_players_give_17_byes_and_one_round_2_tie',
  'only_two_players_enter_in_round_2',
  'sixty_four_players_contest_all_32_opening_ties',
  'full_field_enters_in_round_1',
  'entry_rounds_match_the_first_contested_round',
  'unpredicted_matchday_leaves_only_the_ranking',
  'mutation_waiting_as_bye_is_detected',
  'mutation_swapped_feeder_side_is_detected',
  'mutation_reversed_ranking_fallback_is_detected',
  'mutation_reopened_cutoff_is_detected',
  'restored_implementation_returns_to_green',
  'mutation_skipped_pre_result_freeze_is_detected',
  'restored_freeze_helper_returns_to_green',
  'player_recompute_rejected',
  'player_engine_execution_rejected',
  'player_score_helper_execution_rejected',
  'player_state_helper_execution_rejected',
  'player_layout_helper_execution_rejected',
  'player_freeze_helper_execution_rejected',
  'player_entrant_helper_execution_rejected',
  'player_classifier_execution_rejected',
  'player_lock_key_execution_rejected',
  'player_award_insert_rejected',
  'player_award_update_rejected',
  'player_award_delete_rejected',
  'player_tie_decision_rejected',
  'player_round_status_write_rejected',
  'player_exclusion_insert_rejected',
  'player_exclusion_delete_rejected',
  'anon_award_read_rejected',
  'anon_exclusion_read_rejected',
  'anon_recompute_rejected',
  'disabled_admin_recompute_rejected',
  'active_admin_recompute_through_authenticated_role',
  'rejected_writes_left_the_cup_untouched',
  'players_can_read_the_cup_honours_list',
  'recovery_rpc_reports_a_missing_cup_safely',
  'all_fixture_changes_rolled_back'
]) as passed_test;
