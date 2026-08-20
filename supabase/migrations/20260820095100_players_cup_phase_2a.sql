-- Players Cup, Phase 2A: the isolated scoring, progression and award engine.
--
-- Phase 1 froze the entry list, the ranking and the 63 tie skeleton. This
-- migration adds everything that DERIVES from football results:
--   * Cup matchday scores, exact and correct-result counters
--   * the four step tie-break chain
--   * structural byes, and the waiting state that must never be mistaken for one
--   * round progression through the whole bracket
--   * Cup awards
--   * an admin recovery RPC
--   * the postponed-match cutoff, so one unplayed fixture cannot freeze the Cup
--   * matchday membership immutability for Matchdays 3 to 8
--
-- Two deliberate omissions belong to Phase 2B and are NOT part of this file:
--   * public.get_leaderboard() is untouched, so Cup awards do not reach the
--     overall standings yet.
--   * public.set_match_result() is untouched, so nothing recomputes the Cup
--     automatically yet. public.players_cup_lock_key() below already fixes the
--     lock ordering that integration will need.
--
-- Everything here is additive. No existing table, function, policy, grant or
-- row is modified.

-- ---------------------------------------------------------------------------
-- Prediction quality classifiers
-- ---------------------------------------------------------------------------

-- The normal 5/2/0 and Golden Match 10/4/0 scales are already stored in
-- predictions.points, and the whole application infers prediction quality from
-- that single column. The mapping was duplicated in get_leaderboard and
-- players_cup_ranking; these two functions are the one place a future scoring
-- change has to be made.
--
-- An unscored prediction is NULL, which is neither exact nor correct, so both
-- functions are deliberately non-strict and coalesce their own result.
create or replace function public.prediction_is_exact(p_points integer)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(p_points in (5, 10), false);
$function$;

comment on function public.prediction_is_exact(integer)
is 'True when a prediction scored an exact score, normal (5) or Golden Match (10). NULL points count as false.';

-- The two counters partition the scored predictions: an exact score is never
-- also counted as a correct result, which is what the overall leaderboard
-- already does.
create or replace function public.prediction_is_correct(p_points integer)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(p_points in (2, 4), false);
$function$;

comment on function public.prediction_is_correct(integer)
is 'True when a prediction scored a correct result but not an exact score, normal (2) or Golden Match (4). NULL points count as false.';

-- ---------------------------------------------------------------------------
-- Postponed match cutoff
-- ---------------------------------------------------------------------------

-- A postponed match must not freeze a Cup round for ever. For rounds 1 to 5
-- (Matchdays 3 to 7) a match that is still unfinished when the first match of
-- the next League Phase matchday kicks off is dropped from Cup scoring for its
-- own round, permanently.
--
-- Why this needs a row instead of pure derivation: the rule is evaluated at an
-- instant (the cutoff), but the schema only stores current state. Once the
-- postponed match is finally marked 'finished', nothing left in public.matches
-- proves whether that happened before or after the cutoff - matches.updated_at
-- also moves for kickoff edits and later result corrections, so it cannot carry
-- the decision. This table is therefore the smallest auditable record of a
-- decision that was already taken, and a recompute never deletes from it.
--
-- Rows are written only by public.players_cup_freeze_exclusions, which any Cup
-- write path calls while the postponed match is still visibly unfinished.
-- players_cup_round_matches also derives the same exclusion from live state, so
-- a cutoff that passes between two freezes is still caught whenever the match
-- was rescheduled to kick off after it.
create table public.cup_excluded_matches (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_excluded_matches_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_id bigint not null
    constraint cup_excluded_matches_round_id_fkey
    references public.cup_rounds (id) on delete cascade,
  match_id bigint not null
    constraint cup_excluded_matches_match_id_fkey
    references public.matches (id) on delete cascade,
  cutoff_at timestamptz not null,
  excluded_at timestamptz not null default now(),
  constraint cup_excluded_matches_cup_id_match_id_key unique (cup_id, match_id)
);

comment on table public.cup_excluded_matches is
  'Permanent record that a match was still unfinished when the next League Phase matchday began, so it scores no Cup points for its own round. Written once by players_cup_freeze_exclusions and never removed, because a later result must not reopen a closed Cup round.';

create index cup_excluded_matches_round_id_idx
  on public.cup_excluded_matches (round_id);

create index cup_excluded_matches_match_id_idx
  on public.cup_excluded_matches (match_id);

-- ---------------------------------------------------------------------------
-- Cup awards
-- ---------------------------------------------------------------------------

-- Identity is the participant, not the user: a deleted profile empties user_id
-- but must not break the Cup honours list, and the unique constraint is what
-- makes the non-cumulative rule structural rather than procedural.
create table public.cup_awards (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_awards_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  participant_id bigint not null
    constraint cup_awards_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  user_id uuid
    constraint cup_awards_user_id_fkey
    references public.profiles (id) on delete set null,
  award_type text not null,
  points integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_awards_award_type_check check (
    award_type in ('winner', 'finalist', 'semi_finalist')
  ),
  constraint cup_awards_points_check check (points >= 0),
  constraint cup_awards_cup_id_participant_id_key unique (cup_id, participant_id)
);

comment on table public.cup_awards is
  'Derived Cup honours, rebuilt from the bracket on every recompute. One row per qualifying participant enforces the non-cumulative rule: a champion never also holds a finalist or semi-finalist award. Point values are copied from the cup_competitions reward configuration, never hardcoded.';

create index cup_awards_user_id_idx
  on public.cup_awards (user_id);

create index cup_awards_participant_id_idx
  on public.cup_awards (participant_id);

-- ---------------------------------------------------------------------------
-- Locking
-- ---------------------------------------------------------------------------

-- One key for the whole competition. Phase 2B will call players_cup_apply from
-- inside set_match_result, and it must take THIS lock before locking any match
-- row: the reverse order lets two admins scoring two different matches wait on
-- each other. Exposing the key as a function keeps both call sites identical.
create or replace function public.players_cup_lock_key()
returns bigint
language sql
immutable
set search_path = ''
as $function$
  select hashtext('public.players_cup:players-cup-2026-27')::bigint;
$function$;

comment on function public.players_cup_lock_key()
is 'Advisory lock key for every Players Cup write path. Always acquire it before locking match rows, otherwise concurrent result entry can deadlock.';

-- ---------------------------------------------------------------------------
-- Structural tie layout
-- ---------------------------------------------------------------------------

-- For a field of N players the occupied slots of the template are the labels
-- 1..N. Round r merges the fold positions into groups of 2^r, the first half of
-- each group feeding the home side and the second half the away side, so the
-- number of players that can EVER arrive on each side is pure arithmetic on the
-- Phase 1 template.
--
-- This is what separates the two one-sided ties that look identical in the
-- data:
--   capacity 0 on the far side   -> a bye, nobody can ever arrive
--   capacity > 0 on the far side -> waiting, the feeder simply has not resolved
-- Only the first may advance a player.
create or replace function public.players_cup_tie_layout(
  p_participant_count integer
)
returns table (
  round_number integer,
  slot integer,
  home_capacity integer,
  away_capacity integer
)
language sql
immutable
set search_path = ''
as $function$
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
      where side.is_home
        and side.bracket_position <= p_participant_count
    )::integer as home_capacity,
    count(*) filter (
      where not side.is_home
        and side.bracket_position <= p_participant_count
    )::integer as away_capacity
  from side
  group by side.round_number, side.slot;
$function$;

comment on function public.players_cup_tie_layout(integer)
is 'How many players can ever reach each side of every tie, for a field of the given size. Capacity 0 on one side is a structural bye; capacity 0 on both is an empty tie. A side with capacity but no player yet is waiting, never a bye.';

-- ---------------------------------------------------------------------------
-- Round matches and the exclusion decision
-- ---------------------------------------------------------------------------

-- One row per match of every Cup round, plus one row with a null match_id for a
-- round whose matchday has no matches configured yet, so callers always see all
-- six rounds.
--
-- A match is excluded when the cutoff has passed and it either is not finished
-- or was rescheduled to kick off at or after the cutoff. The second clause
-- matters after the fact: a match cannot have been finished before it kicked
-- off, so a kickoff at or after the cutoff proves the match was still open when
-- the round closed, even when a result is entered much later.
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
as $function$
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
      -- Round 6 is the Final: there is no next League Phase matchday, so no
      -- cutoff exists and the Final waits for every match.
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
      frozen.match_id is not null
      or (
        round_cutoff.cutoff_at is not null
        and now() >= round_cutoff.cutoff_at
        and (
          match_row.status <> 'finished'
          or match_row.kickoff_at >= round_cutoff.cutoff_at
        )
      ),
      false
    ),
    frozen.match_id is not null
  from round_cutoff
  left join public.matches as match_row
    on match_row.matchday_id = round_cutoff.matchday_id
  left join public.cup_excluded_matches as frozen
    on frozen.cup_id = p_cup_id
    and frozen.match_id = match_row.id;
$function$;

comment on function public.players_cup_round_matches(bigint)
is 'Every match of every Cup round with its postponed-match exclusion decision. Rounds 1 to 5 close at the first kickoff of the next League Phase matchday; the Final has no cutoff.';

-- Writes down every exclusion the cutoff already implies AT THIS MOMENT, and
-- nothing else. It never reads or writes the bracket, the awards, the
-- predictions or the matches, so it is safe to call at any point in a
-- transaction.
--
-- Why it is separate from the recompute: derivation alone cannot always
-- reconstruct the decision afterwards. Once an admin enters the result of a
-- long-postponed match, the row may read status = 'finished' with its ORIGINAL
-- pre-cutoff kickoff_at, which no longer proves the match was still open when
-- the round closed. The decision therefore has to be captured while the match
-- is still visibly unfinished.
--
-- LOCKING CONTRACT: this function takes no lock of its own. Every caller must
-- already hold pg_advisory_xact_lock(public.players_cup_lock_key()), which is
-- also the first lock in the global ordering:
--
--   1. pg_advisory_xact_lock(public.players_cup_lock_key())
--   2. public.players_cup_freeze_exclusions(cup_id)   <- before the match moves
--   3. select ... from public.matches ... for update
--   4. rescore the predictions of that match
--   5. public.players_cup_apply(cup_id)
--
-- Phase 2B will follow exactly this order inside set_match_result. Taking a
-- second, independent lock here would break that ordering and reintroduce the
-- deadlock the single Cup lock exists to prevent.
create or replace function public.players_cup_freeze_exclusions(p_cup_id bigint)
returns integer
language sql
volatile
security definer
set search_path = ''
as $function$
  with frozen as (
    insert into public.cup_excluded_matches (
      cup_id,
      round_id,
      match_id,
      cutoff_at
    )
    select
      p_cup_id,
      round_match.round_id,
      round_match.match_id,
      round_match.cutoff_at
    from public.players_cup_round_matches(p_cup_id) as round_match
    where round_match.match_id is not null
      -- Null cutoff means the Final, which never closes early.
      and round_match.cutoff_at is not null
      and round_match.is_excluded
      and not round_match.exclusion_is_frozen
    on conflict (cup_id, match_id) do nothing
    returning 1
  )
  select count(*)::integer from frozen;
$function$;

comment on function public.players_cup_freeze_exclusions(bigint)
is 'Persists every postponed-match exclusion the cutoff already implies right now, and returns how many were newly frozen. Insert only: a historical exclusion is never removed or rewritten, so calling it repeatedly is a no-op. Callers must already hold the Cup advisory lock. Phase 2B must call this BEFORE set_match_result touches the match, because a late result hides the evidence the decision was based on.';

-- ---------------------------------------------------------------------------
-- Round readiness
-- ---------------------------------------------------------------------------

-- public.matchdays.status is not maintained anywhere in this project, so
-- readiness is derived from the matches themselves, the same way the long-term
-- prediction lock already does it.
create or replace function public.players_cup_matchday_state(p_cup_id bigint)
returns table (
  round_number integer,
  round_id bigint,
  matchday_id bigint,
  cutoff_at timestamptz,
  configured_count integer,
  excluded_count integer,
  included_count integer,
  finished_included_count integer,
  unscored_prediction_count integer,
  is_complete boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  with round_match as (
    select * from public.players_cup_round_matches(p_cup_id)
  ),
  unscored as (
    select
      round_match.round_id,
      count(*)::integer as unscored_count
    from round_match
    join public.predictions as prediction
      on prediction.match_id = round_match.match_id
    where not round_match.is_excluded
      and prediction.points is null
    group by round_match.round_id
  ),
  aggregated as (
    select
      round_match.round_number,
      round_match.round_id,
      round_match.matchday_id,
      min(round_match.cutoff_at) as cutoff_at,
      count(round_match.match_id)::integer as configured_count,
      count(*) filter (
        where round_match.match_id is not null
          and round_match.is_excluded
      )::integer as excluded_count,
      count(*) filter (
        where round_match.match_id is not null
          and not round_match.is_excluded
      )::integer as included_count,
      count(*) filter (
        where round_match.match_id is not null
          and not round_match.is_excluded
          and round_match.match_status = 'finished'
      )::integer as finished_included_count
    from round_match
    group by
      round_match.round_number,
      round_match.round_id,
      round_match.matchday_id
  )
  select
    aggregated.round_number,
    aggregated.round_id,
    aggregated.matchday_id,
    aggregated.cutoff_at,
    aggregated.configured_count,
    aggregated.excluded_count,
    aggregated.included_count,
    aggregated.finished_included_count,
    coalesce(unscored.unscored_count, 0),
    (
      aggregated.configured_count > 0
      and aggregated.included_count > 0
      and aggregated.finished_included_count = aggregated.included_count
      and coalesce(unscored.unscored_count, 0) = 0
    )
  from aggregated
  left join unscored
    on unscored.round_id = aggregated.round_id;
$function$;

comment on function public.players_cup_matchday_state(bigint)
is 'Per Cup round readiness. A round may resolve once it has at least one included match, every included match is finished and every prediction on those matches is scored. Excluded postponed matches are ignored by all four counters.';

-- ---------------------------------------------------------------------------
-- Cup matchday aggregation
-- ---------------------------------------------------------------------------

-- Participant driven on purpose. A missing prediction is a missing row, a
-- disabled player simply stops producing rows, and a deleted profile leaves
-- user_id null, so all three must fall out of a LEFT JOIN as 0/0/0 instead of
-- disappearing from the result.
create or replace function public.players_cup_matchday_scores(
  p_cup_id bigint,
  p_matchday_id bigint
)
returns table (
  participant_id bigint,
  points integer,
  exact_count integer,
  correct_count integer
)
language sql
stable
security definer
set search_path = ''
as $function$
  with included_match as (
    select round_match.match_id
    from public.players_cup_round_matches(p_cup_id) as round_match
    where round_match.matchday_id = p_matchday_id
      and round_match.match_id is not null
      and not round_match.is_excluded
  ),
  round_prediction as (
    select
      prediction.user_id,
      prediction.points
    from public.predictions as prediction
    join included_match
      on included_match.match_id = prediction.match_id
  )
  select
    participant.id,
    coalesce(sum(round_prediction.points), 0)::integer,
    count(*) filter (
      where public.prediction_is_exact(round_prediction.points)
    )::integer,
    count(*) filter (
      where public.prediction_is_correct(round_prediction.points)
    )::integer
  from public.cup_participants as participant
  left join round_prediction
    on round_prediction.user_id = participant.user_id
  where participant.cup_id = p_cup_id
  group by participant.id;
$function$;

comment on function public.players_cup_matchday_scores(bigint, bigint)
is 'Cup points, exact scores and correct results for every participant in one Cup matchday. Golden Match doubling is already inside predictions.points, long-term awards and other matchdays are structurally excluded, and a participant without predictions scores 0/0/0.';

-- ---------------------------------------------------------------------------
-- Progression sources
-- ---------------------------------------------------------------------------

-- Who currently occupies each side of every tie in one round. Round 1 reads the
-- persisted draw, never the draw function, so a recompute can never reposition
-- a player. Later rounds read the previous round's winners: the odd slot feeds
-- the home side and the even slot the away side.
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
as $function$
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
      filter (where previous_tie.slot % 2 = 1),
    max(previous_tie.winner_participant_id)
      filter (where previous_tie.slot % 2 = 0)
  from public.cup_ties as previous_tie
  join public.cup_rounds as previous_round
    on previous_round.id = previous_tie.round_id
  where p_round_number > 1
    and previous_round.cup_id = p_cup_id
    and previous_round.round_number = p_round_number - 1
  group by ((previous_tie.slot + 1) / 2);
$function$;

comment on function public.players_cup_round_entrants(bigint, integer)
is 'Current occupants of every tie in one Cup round. Round 1 comes from the persisted bracket positions; round r takes the winner of round r-1 slot 2k-1 as home and slot 2k as away.';

-- ---------------------------------------------------------------------------
-- Tie classification and tie-break
-- ---------------------------------------------------------------------------

-- Kept as its own function because the difference between a bye and a tie that
-- is merely waiting is the single most dangerous thing to get wrong: a bye
-- advances a player who has not won anything.
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
as $function$
  select case
    -- Nobody can ever arrive on either side.
    when p_home_capacity = 0 and p_away_capacity = 0 then 'empty'
    -- Structural bye: the far side is incapable of producing a player.
    when p_away_capacity = 0 and p_home_participant_id is not null then 'bye'
    when p_home_capacity = 0 and p_away_participant_id is not null then 'bye'
    -- Waiting. The far side can still produce a player, so a single known
    -- participant must not advance.
    when p_home_participant_id is null or p_away_participant_id is null
      then 'pending'
    when not p_round_is_complete then 'pending'
    else 'decided'
  end;
$function$;

comment on function public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
is 'Classifies one Cup tie as empty, bye, pending or decided. A bye requires the far side to be structurally empty; one known participant against an unresolved feeder is always pending.';

-- Cup points, then exact scores, then correct results, then the better frozen
-- ranking. The chain always terminates because cup_participants.rank_position
-- is unique inside a Cup, so the last comparison can never be a draw.
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
as $function$
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
      -- A lower rank position is the better ranking.
      else p_home_rank_position < p_away_rank_position
    end;
$function$;

comment on function public.players_cup_tie_break(integer, integer, integer, integer, integer, integer, integer, integer)
is 'Resolves a contested Cup tie: Cup points, then exact scores, then correct results, then the lower rank_position. Returns the rule that decided it and whether the home participant won.';

-- ---------------------------------------------------------------------------
-- The recompute engine
-- ---------------------------------------------------------------------------

-- Owns every piece of derived Cup state: tie participants, tie statistics,
-- winners, round statuses, awards and the competition status. Nothing else in
-- the database may write those columns.
--
-- It is a FULL recompute, never an incremental "advance this winner". A
-- corrected football result changes prediction points outside this function,
-- and the next run rebuilds the whole bracket from the frozen Phase 1 entry
-- list, so a changed Round 1 winner cannot leave a stale opponent, score,
-- winner or award anywhere downstream.
--
-- LOCKING: the caller must already hold pg_advisory_xact_lock(
-- public.players_cup_lock_key()). This function only adds the competition row
-- lock, so the advisory lock is always acquired before any match row lock.
create or replace function public.players_cup_apply(p_cup_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_slug text;
  v_participant_count integer;
  v_winner_points integer;
  v_finalist_points integer;
  v_semi_finalist_points integer;
  v_round record;
  v_round_number integer;
  v_round_status text;
  v_final_outcome text;
  v_final_winner_id bigint;
  v_final_home_id bigint;
  v_final_away_id bigint;
  v_status text;
  v_summary jsonb;
begin
  select
    competition.slug,
    competition.participant_count,
    competition.winner_points,
    competition.finalist_points,
    competition.semi_finalist_points
  into
    v_slug,
    v_participant_count,
    v_winner_points,
    v_finalist_points,
    v_semi_finalist_points
  from public.cup_competitions as competition
  where competition.id = p_cup_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Players Cup not found';
  end if;

  -- Freeze today's exclusion decisions before any round state or score is read,
  -- so a result entered for a postponed match later can never reopen the round.
  -- Phase 2B will additionally call this helper before it touches the match, but
  -- the recompute repeats it so the admin recovery RPC remains correct on its
  -- own.
  perform public.players_cup_freeze_exclusions(p_cup_id);

  -- One statement, the whole Cup. The assert_cup_round_participants trigger is
  -- an AFTER STATEMENT check over the bracket, so clearing everything first
  -- guarantees no intermediate statement can see a participant twice in one
  -- round while the rounds are rebuilt one by one below.
  update public.cup_ties as tie
  set
    home_participant_id = null,
    away_participant_id = null,
    home_points = 0,
    away_points = 0,
    home_exact = 0,
    away_exact = 0,
    home_correct = 0,
    away_correct = 0,
    winner_participant_id = null,
    outcome = 'empty',
    decided_by_rule = null,
    updated_at = now()
  where tie.cup_id = p_cup_id
    and (
      tie.outcome <> 'empty'
      or tie.home_participant_id is not null
      or tie.away_participant_id is not null
      or tie.winner_participant_id is not null
      or tie.decided_by_rule is not null
      or tie.home_points <> 0
      or tie.away_points <> 0
      or tie.home_exact <> 0
      or tie.away_exact <> 0
      or tie.home_correct <> 0
      or tie.away_correct <> 0
    );

  -- Every round, every time. Byes need no football, so progression must not
  -- stop at the first incomplete matchday: it stops per feeder instead.
  for v_round in
    select
      state.round_number,
      state.round_id,
      state.matchday_id,
      state.is_complete
    from public.players_cup_matchday_state(p_cup_id) as state
    order by state.round_number
  loop
    v_round_number := v_round.round_number;

    with entrant as (
      select
        round_entrant.slot,
        round_entrant.home_participant_id,
        round_entrant.away_participant_id
      from public.players_cup_round_entrants(p_cup_id, v_round_number)
        as round_entrant
    ),
    resolved as (
      select
        entrant.slot,
        entrant.home_participant_id,
        entrant.away_participant_id,
        layout.home_capacity,
        layout.away_capacity,
        home_participant.rank_position as home_rank_position,
        away_participant.rank_position as away_rank_position,
        -- Statistics belong to a contested tie only. A bye is not played, and a
        -- half filled tie would otherwise display a fictional 18-0.
        (entrant.home_participant_id is not null
          and entrant.away_participant_id is not null) as is_contested,
        coalesce(home_score.points, 0) as home_points,
        coalesce(away_score.points, 0) as away_points,
        coalesce(home_score.exact_count, 0) as home_exact,
        coalesce(away_score.exact_count, 0) as away_exact,
        coalesce(home_score.correct_count, 0) as home_correct,
        coalesce(away_score.correct_count, 0) as away_correct
      from entrant
      join public.players_cup_tie_layout(v_participant_count) as layout
        on layout.round_number = v_round_number
        and layout.slot = entrant.slot
      left join public.cup_participants as home_participant
        on home_participant.id = entrant.home_participant_id
      left join public.cup_participants as away_participant
        on away_participant.id = entrant.away_participant_id
      left join public.players_cup_matchday_scores(
        p_cup_id,
        v_round.matchday_id
      ) as home_score
        on home_score.participant_id = entrant.home_participant_id
      left join public.players_cup_matchday_scores(
        p_cup_id,
        v_round.matchday_id
      ) as away_score
        on away_score.participant_id = entrant.away_participant_id
    ),
    classified as (
      select
        resolved.slot,
        resolved.home_participant_id,
        resolved.away_participant_id,
        case when resolved.is_contested then resolved.home_points else 0 end
          as home_points,
        case when resolved.is_contested then resolved.away_points else 0 end
          as away_points,
        case when resolved.is_contested then resolved.home_exact else 0 end
          as home_exact,
        case when resolved.is_contested then resolved.away_exact else 0 end
          as away_exact,
        case when resolved.is_contested then resolved.home_correct else 0 end
          as home_correct,
        case when resolved.is_contested then resolved.away_correct else 0 end
          as away_correct,
        public.players_cup_tie_outcome(
          resolved.home_capacity,
          resolved.away_capacity,
          resolved.home_participant_id,
          resolved.away_participant_id,
          v_round.is_complete
        ) as outcome,
        tie_break.decided_by_rule,
        tie_break.home_wins
      from resolved
      cross join lateral public.players_cup_tie_break(
        resolved.home_points,
        resolved.away_points,
        resolved.home_exact,
        resolved.away_exact,
        resolved.home_correct,
        resolved.away_correct,
        resolved.home_rank_position,
        resolved.away_rank_position
      ) as tie_break
    )
    update public.cup_ties as tie
    set
      home_participant_id = classified.home_participant_id,
      away_participant_id = classified.away_participant_id,
      home_points = classified.home_points,
      away_points = classified.away_points,
      home_exact = classified.home_exact,
      away_exact = classified.away_exact,
      home_correct = classified.home_correct,
      away_correct = classified.away_correct,
      winner_participant_id = case classified.outcome
        when 'bye' then coalesce(
          classified.home_participant_id,
          classified.away_participant_id
        )
        when 'decided' then case
          when classified.home_wins then classified.home_participant_id
          else classified.away_participant_id
        end
      end,
      outcome = classified.outcome,
      decided_by_rule = case
        when classified.outcome = 'decided' then classified.decided_by_rule
      end,
      updated_at = now()
    from classified
    where tie.round_id = v_round.round_id
      and tie.slot = classified.slot
      -- The clear above already emptied every tie, so only a tie that ends up
      -- holding real state has to be written again.
      and classified.outcome <> 'empty';

    -- Derived from the rebuilt ties, never from matchday completion. A field of
    -- eight players makes rounds 1 to 3 structurally final before a single Cup
    -- match has been played, and that is the truth to show.
    select case
      when count(*) filter (
        where tie.home_participant_id is not null
          or tie.away_participant_id is not null
      ) = 0 then 'pending'
      when count(*) filter (where tie.outcome = 'pending') > 0
        then 'in_progress'
      else 'final'
    end
    into v_round_status
    from public.cup_ties as tie
    where tie.round_id = v_round.round_id;

    update public.cup_rounds as round
    set
      status = v_round_status,
      updated_at = now()
    where round.id = v_round.round_id
      and round.status is distinct from v_round_status;
  end loop;

  select
    tie.outcome,
    tie.winner_participant_id,
    tie.home_participant_id,
    tie.away_participant_id
  into
    v_final_outcome,
    v_final_winner_id,
    v_final_home_id,
    v_final_away_id
  from public.cup_ties as tie
  join public.cup_rounds as round
    on round.id = tie.round_id
  where round.cup_id = p_cup_id
    and round.round_number = 6
    and tie.slot = 1;

  -- Awards are derived state, so the rebuild has to be able to take an award
  -- away again. Reward values come from the competition row, never from a
  -- constant, so 30/20/10 can become 100/60/20 without touching this function.
  with qualifying as (
    select
      v_final_winner_id as participant_id,
      'winner'::text as award_type,
      v_winner_points as points
    where v_final_outcome = 'decided'
    union all
    select
      case
        when v_final_home_id = v_final_winner_id then v_final_away_id
        else v_final_home_id
      end,
      'finalist',
      v_finalist_points
    where v_final_outcome = 'decided'
    union all
    select
      case
        when tie.home_participant_id = tie.winner_participant_id
          then tie.away_participant_id
        else tie.home_participant_id
      end,
      'semi_finalist',
      v_semi_finalist_points
    from public.cup_ties as tie
    join public.cup_rounds as round
      on round.id = tie.round_id
    where v_final_outcome = 'decided'
      and round.cup_id = p_cup_id
      and round.round_number = 5
      and tie.outcome = 'decided'
  ),
  removed as (
    delete from public.cup_awards as award
    where award.cup_id = p_cup_id
      and not exists (
        select 1
        from qualifying
        where qualifying.participant_id = award.participant_id
      )
    returning award.id
  )
  insert into public.cup_awards (
    cup_id,
    participant_id,
    user_id,
    award_type,
    points
  )
  select
    p_cup_id,
    qualifying.participant_id,
    participant.user_id,
    qualifying.award_type,
    qualifying.points
  from qualifying
  join public.cup_participants as participant
    on participant.id = qualifying.participant_id
  on conflict (cup_id, participant_id) do update
  set
    user_id = excluded.user_id,
    award_type = excluded.award_type,
    points = excluded.points,
    updated_at = now()
  where cup_awards.user_id is distinct from excluded.user_id
    or cup_awards.award_type is distinct from excluded.award_type
    or cup_awards.points is distinct from excluded.points;

  v_status := case
    when v_final_outcome = 'decided' then 'completed'
    else 'active'
  end;

  -- A correction that reopens the Final has to reopen the competition too.
  update public.cup_competitions as competition
  set
    status = v_status,
    updated_at = now()
  where competition.id = p_cup_id
    and competition.status is distinct from v_status;

  select jsonb_build_object(
    'cup_id', p_cup_id,
    'slug', v_slug,
    'status', v_status,
    'participant_count', v_participant_count,
    'rounds_pending', count(*) filter (where round.status = 'pending'),
    'rounds_in_progress', count(*) filter (where round.status = 'in_progress'),
    'rounds_final', count(*) filter (where round.status = 'final')
  )
  into v_summary
  from public.cup_rounds as round
  where round.cup_id = p_cup_id;

  select v_summary || jsonb_build_object(
    'ties_decided', count(*) filter (where tie.outcome = 'decided'),
    'ties_pending', count(*) filter (where tie.outcome = 'pending'),
    'ties_bye', count(*) filter (where tie.outcome = 'bye'),
    'ties_empty', count(*) filter (where tie.outcome = 'empty')
  )
  into v_summary
  from public.cup_ties as tie
  where tie.cup_id = p_cup_id;

  select v_summary || jsonb_build_object(
    'awards_count', (
      select count(*)
      from public.cup_awards as award
      where award.cup_id = p_cup_id
    ),
    'excluded_postponed_match_count', (
      select count(*)
      from public.cup_excluded_matches as excluded_match
      where excluded_match.cup_id = p_cup_id
    ),
    'champion_participant_id', case
      when v_final_outcome = 'decided' then v_final_winner_id
    end,
    'rounds', (
      select jsonb_agg(
        jsonb_build_object(
          'round_number', state.round_number,
          'matchday_number', state.round_number + 2,
          'status', round.status,
          'is_complete', state.is_complete,
          'cutoff_at', state.cutoff_at,
          'configured_matches', state.configured_count,
          'included_matches', state.included_count,
          'excluded_matches', state.excluded_count,
          'finished_included_matches', state.finished_included_count,
          'unscored_predictions', state.unscored_prediction_count
        )
        order by state.round_number
      )
      from public.players_cup_matchday_state(p_cup_id) as state
      join public.cup_rounds as round
        on round.id = state.round_id
    ),
    'recomputed_at', now()
  )
  into v_summary;

  return v_summary;
end;
$function$;

comment on function public.players_cup_apply(bigint)
is 'Full deterministic recompute of every derived Players Cup value: tie participants, statistics, winners, round statuses, awards and competition status. Idempotent and correction safe. The caller must already hold the players_cup_lock_key advisory lock.';

-- ---------------------------------------------------------------------------
-- Admin recovery RPC
-- ---------------------------------------------------------------------------

-- Recovery tooling, not an "advance round" button: it only recalculates the
-- current truth and is safe to press at any time, including before the draw.
create or replace function public.recompute_players_cup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  v_cup_id bigint;
begin
  if (select auth.uid()) is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Taken before any row lock. Phase 2B must use the same order inside
  -- set_match_result, otherwise two admins scoring two matches can deadlock.
  perform pg_advisory_xact_lock(public.players_cup_lock_key());

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug;

  -- No draw yet is a normal state, not an error.
  if v_cup_id is null then
    return jsonb_build_object(
      'cup_exists', false,
      'slug', c_slug,
      'recomputed_at', now()
    );
  end if;

  return public.players_cup_apply(v_cup_id)
    || jsonb_build_object('cup_exists', true);
end;
$function$;

comment on function public.recompute_players_cup()
is 'Admin-only Players Cup recalculation. Recomputes every derived value from the current football results and is safe to call repeatedly. Returns a summary instead of raising when no Cup has been drawn yet.';

-- ---------------------------------------------------------------------------
-- Cup matchday membership immutability
-- ---------------------------------------------------------------------------

-- Cup rounds are permanently mapped to Matchdays 3 to 8, so moving a match
-- between matchdays would silently move its prediction points from one Cup
-- round to another. Kickoff time, status and result stay freely editable: the
-- trigger only fires when matchday_id is in the UPDATE target list.
create or replace function public.assert_cup_matchday_membership()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.matchday_id is not distinct from old.matchday_id then
    return new;
  end if;

  if not exists (select 1 from public.cup_competitions) then
    return new;
  end if;

  if exists (
    select 1
    from public.matchdays as matchday
    where matchday.id in (old.matchday_id, new.matchday_id)
      and matchday.stage = 'league_phase'
      and matchday.matchday_number between 3 and 8
  ) then
    raise exception using
      errcode = '22023',
      message = 'A Players Cup matchday match cannot be moved to another matchday';
  end if;

  return new;
end;
$function$;

comment on function public.assert_cup_matchday_membership()
is 'Rejects moving a match into or out of League Phase Matchdays 3 to 8 once a Players Cup exists, because those matchdays are permanently mapped to Cup rounds.';

create trigger matches_cup_matchday_membership
before update of matchday_id
on public.matches
for each row
execute function public.assert_cup_matchday_membership();

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------

alter table public.cup_awards enable row level security;
alter table public.cup_excluded_matches enable row level security;

-- Read-only for players, exactly like the Phase 1 Cup tables. No insert, update
-- or delete policy exists, so the Data API rejects every browser write before
-- column grants are considered.
create policy "Authenticated users can view Cup awards"
  on public.cup_awards
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view excluded Cup matches"
  on public.cup_excluded_matches
  for select
  to authenticated
  using (true);

revoke all privileges on table public.cup_awards
  from public, anon, authenticated;
revoke all privileges on table public.cup_excluded_matches
  from public, anon, authenticated;

grant select on table public.cup_awards to authenticated;
grant select on table public.cup_excluded_matches to authenticated;

grant all privileges on table public.cup_awards to service_role;
grant all privileges on table public.cup_excluded_matches to service_role;

revoke all privileges on sequence public.cup_awards_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_excluded_matches_id_seq
  from public, anon, authenticated;

grant all privileges on sequence public.cup_awards_id_seq to service_role;
grant all privileges on sequence public.cup_excluded_matches_id_seq
  to service_role;

-- The browser may invoke the recovery RPC, but the function rejects every
-- caller who is not an active administrator.
revoke execute on function public.recompute_players_cup()
  from public, anon;
grant execute on function public.recompute_players_cup()
  to authenticated, service_role;

-- Internal helpers. players_cup_matchday_scores aggregates every player's
-- predictions and players_cup_apply writes the bracket, so neither may be
-- reachable from the browser. The classifiers stay internal too: nothing in the
-- client needs them, and exposing them would widen the surface for no gain.
revoke execute on function public.prediction_is_exact(integer)
  from public, anon, authenticated;
grant execute on function public.prediction_is_exact(integer)
  to service_role;

revoke execute on function public.prediction_is_correct(integer)
  from public, anon, authenticated;
grant execute on function public.prediction_is_correct(integer)
  to service_role;

revoke execute on function public.players_cup_lock_key()
  from public, anon, authenticated;
grant execute on function public.players_cup_lock_key()
  to service_role;

revoke execute on function public.players_cup_tie_layout(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_tie_layout(integer)
  to service_role;

revoke execute on function public.players_cup_round_matches(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_round_matches(bigint)
  to service_role;

revoke execute on function public.players_cup_freeze_exclusions(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_freeze_exclusions(bigint)
  to service_role;

revoke execute on function public.players_cup_matchday_state(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_matchday_state(bigint)
  to service_role;

revoke execute on function public.players_cup_matchday_scores(bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_matchday_scores(bigint, bigint)
  to service_role;

revoke execute on function public.players_cup_round_entrants(bigint, integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_round_entrants(bigint, integer)
  to service_role;

revoke execute on function
  public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
  from public, anon, authenticated;
grant execute on function
  public.players_cup_tie_outcome(integer, integer, bigint, bigint, boolean)
  to service_role;

revoke execute on function public.players_cup_tie_break(
  integer, integer, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.players_cup_tie_break(
  integer, integer, integer, integer, integer, integer, integer, integer
) to service_role;

revoke execute on function public.players_cup_apply(bigint)
  from public, anon, authenticated;
grant execute on function public.players_cup_apply(bigint)
  to service_role;

revoke execute on function public.assert_cup_matchday_membership()
  from public, anon, authenticated;
