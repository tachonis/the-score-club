-- Players Cup, Phase 1: competition configuration, the frozen post-Matchday 2
-- ranking, the protected top 8 seeds, the reproducible draw for everyone else,
-- and the complete bracket skeleton.
--
-- Vocabulary used throughout, because three different numbers are easy to
-- confuse:
--   rank_position     - the frozen strict League Phase ranking after Matchday
--                       2. Every participant has one, and a lower number is a
--                       better ranking. Only rank positions 1 to 8 are
--                       tournament seeds; they are protected.
--   bracket_position  - the persisted slot in the 64 position template a
--                       player occupies in the draw. Protected for the top 8,
--                       drawn for everyone else.
--   entry_round       - the first Cup round in which the participant can face
--                       another player.
--
-- This migration only adds new objects. It does not change or delete any
-- existing table, view, function, policy, grant or row. Cup scoring, round
-- progression and Cup awards are deliberately out of scope: the tables below
-- reserve the columns those phases will fill, but nothing in this migration
-- reads predictions for scoring or writes leaderboard points.

create table public.cup_competitions (
  id bigint generated always as identity primary key,
  slug text not null,
  season_label text not null,
  bracket_size integer not null default 64,
  participant_count integer not null,
  status text not null default 'active',
  -- Permanent part of the Cup record: the draw is reproducible from this seed
  -- plus the frozen ranking. It is not a secret.
  draw_seed uuid not null default gen_random_uuid(),
  winner_points integer not null default 30,
  finalist_points integer not null default 20,
  semi_finalist_points integer not null default 10,
  created_by uuid
    constraint cup_competitions_created_by_fkey
    references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_competitions_slug_key unique (slug),
  constraint cup_competitions_slug_check check (
    char_length(btrim(slug)) between 1 and 100
  ),
  constraint cup_competitions_season_label_check check (
    char_length(btrim(season_label)) between 1 and 100
  ),
  constraint cup_competitions_bracket_size_check check (bracket_size = 64),
  constraint cup_competitions_participant_count_check check (
    participant_count between 8 and 64
  ),
  constraint cup_competitions_status_check check (
    status in ('active', 'completed')
  ),
  -- Reward configuration lives on the row so a future phase can change
  -- 30/20/10 into 100/60/20 without touching bracket or scoring logic.
  constraint cup_competitions_reward_range_check check (
    winner_points >= 0
    and finalist_points >= 0
    and semi_finalist_points >= 0
  ),
  constraint cup_competitions_reward_order_check check (
    winner_points >= finalist_points
    and finalist_points >= semi_finalist_points
  )
);

comment on table public.cup_competitions is
  'One Players Cup per season. Reward values are configuration: every future award calculation must read them from this row instead of hardcoding 30/20/10. draw_seed replays the draw that produced the stored bracket.';

create index cup_competitions_created_by_idx
  on public.cup_competitions (created_by);

create table public.cup_participants (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_participants_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  -- Nullable on purpose: a deleted profile must empty this reference without
  -- removing the participant row, so the bracket keeps its structure.
  user_id uuid
    constraint cup_participants_user_id_fkey
    references public.profiles (id) on delete set null,
  username_snapshot text not null,
  -- Frozen ranking position after Matchday 2, not a bracket slot. Phase 2 uses
  -- it as the final tie-break, so it must never be overwritten by the draw.
  rank_position integer not null,
  -- The slot in the 64 position template this player occupies.
  bracket_position integer not null,
  -- The first round in which this player meets a real opponent. Derived from
  -- the template at creation and frozen, so the entitlement the draw had to
  -- respect stays auditable.
  entry_round integer not null,
  created_at timestamptz not null default now(),
  constraint cup_participants_username_snapshot_check check (
    char_length(btrim(username_snapshot)) between 1 and 100
  ),
  constraint cup_participants_rank_position_check check (
    rank_position between 1 and 64
  ),
  constraint cup_participants_bracket_position_check check (
    bracket_position between 1 and 64
  ),
  constraint cup_participants_entry_round_check check (
    entry_round between 1 and 6
  ),
  constraint cup_participants_cup_id_rank_position_key
    unique (cup_id, rank_position),
  constraint cup_participants_cup_id_bracket_position_key
    unique (cup_id, bracket_position)
);

comment on table public.cup_participants is
  'Frozen Cup entry list. rank_position is the post-Matchday 2 ranking, bracket_position is the drawn or protected slot in the template, and both are decided once at creation so later results or username changes cannot reshuffle the bracket.';

comment on column public.cup_participants.rank_position is
  'Frozen strict League Phase ranking after Matchday 2, 1..64, where a lower number is a better ranking. Rank positions 1 to 8 are the protected tournament seeds; every other participant is drawn.';

comment on column public.cup_participants.bracket_position is
  'Persisted location in the 64 slot Cup draw. Equal to rank_position for the protected top 8, drawn from the matching entry-round group for everyone else.';

comment on column public.cup_participants.entry_round is
  'First Cup round in which this participant can face another player. Rounds 1 to 6 map to Matchdays 3 to 8.';

-- A partial unique index instead of a unique constraint, because user_id
-- becomes null when a profile is deleted and several withdrawn participants
-- may coexist in the same Cup.
create unique index cup_participants_cup_id_user_id_uidx
  on public.cup_participants (cup_id, user_id)
  where user_id is not null;

create index cup_participants_user_id_idx
  on public.cup_participants (user_id);

create table public.cup_rounds (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_rounds_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_number integer not null,
  slot_count integer not null,
  matchday_id bigint not null
    constraint cup_rounds_matchday_id_fkey
    references public.matchdays (id),
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_rounds_round_number_check check (round_number between 1 and 6),
  constraint cup_rounds_slot_count_check check (
    (round_number = 1 and slot_count = 64)
    or (round_number = 2 and slot_count = 32)
    or (round_number = 3 and slot_count = 16)
    or (round_number = 4 and slot_count = 8)
    or (round_number = 5 and slot_count = 4)
    or (round_number = 6 and slot_count = 2)
  ),
  constraint cup_rounds_status_check check (
    status in ('pending', 'in_progress', 'final')
  ),
  constraint cup_rounds_cup_id_round_number_key unique (cup_id, round_number),
  constraint cup_rounds_cup_id_matchday_id_key unique (cup_id, matchday_id)
);

comment on table public.cup_rounds is
  'Cup round to League Phase matchday mapping: round 1 is Matchday 3 and round 6 (the Final) is Matchday 8.';

create index cup_rounds_matchday_id_idx
  on public.cup_rounds (matchday_id);

create table public.cup_ties (
  id bigint generated always as identity primary key,
  cup_id bigint not null
    constraint cup_ties_cup_id_fkey
    references public.cup_competitions (id) on delete cascade,
  round_id bigint not null
    constraint cup_ties_round_id_fkey
    references public.cup_rounds (id) on delete cascade,
  slot integer not null,
  home_participant_id bigint
    constraint cup_ties_home_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  away_participant_id bigint
    constraint cup_ties_away_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  home_points integer not null default 0,
  away_points integer not null default 0,
  home_exact integer not null default 0,
  away_exact integer not null default 0,
  home_correct integer not null default 0,
  away_correct integer not null default 0,
  winner_participant_id bigint
    constraint cup_ties_winner_participant_id_fkey
    references public.cup_participants (id) on delete cascade,
  outcome text not null default 'empty',
  decided_by_rule text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cup_ties_slot_check check (slot between 1 and 32),
  constraint cup_ties_score_check check (
    home_points >= 0
    and away_points >= 0
    and home_exact >= 0
    and away_exact >= 0
    and home_correct >= 0
    and away_correct >= 0
  ),
  constraint cup_ties_distinct_participants_check check (
    home_participant_id is null
    or away_participant_id is null
    or home_participant_id <> away_participant_id
  ),
  constraint cup_ties_outcome_check check (
    outcome in ('empty', 'bye', 'pending', 'decided')
  ),
  -- Reserved for the progression phase: the tie-break chain is Cup points,
  -- exact scores, correct results, then the better ranking, meaning the lower
  -- cup_participants.rank_position.
  constraint cup_ties_decided_by_rule_check check (
    decided_by_rule is null
    or (
      outcome = 'decided'
      and decided_by_rule in ('points', 'exact', 'correct', 'rank_position')
    )
  ),
  -- The sentinel keeps the comparison from evaluating to NULL, which a CHECK
  -- constraint would otherwise accept.
  constraint cup_ties_winner_membership_check check (
    winner_participant_id is null
    or winner_participant_id in (
      coalesce(home_participant_id, -1),
      coalesce(away_participant_id, -1)
    )
  ),
  constraint cup_ties_outcome_state_check check (
    case outcome
      when 'empty' then
        home_participant_id is null
        and away_participant_id is null
        and winner_participant_id is null
      when 'bye' then
        (home_participant_id is null) <> (away_participant_id is null)
        and winner_participant_id is not null
      when 'pending' then
        winner_participant_id is null
      when 'decided' then
        home_participant_id is not null
        and away_participant_id is not null
        and winner_participant_id is not null
      else false
    end
  ),
  constraint cup_ties_cup_id_round_id_slot_key unique (cup_id, round_id, slot)
);

comment on table public.cup_ties is
  'Complete 63-tie bracket skeleton created up front. Round r+1 slot k is fed by round r slots (2k-1) and (2k), so no source-slot metadata is stored and progression never inserts rows.';

comment on column public.cup_ties.decided_by_rule is
  'Reserved for Phase 2. The chain is Cup points, exact scores, correct results, then the better ranking, meaning the lower cup_participants.rank_position.';

create index cup_ties_round_id_slot_idx
  on public.cup_ties (round_id, slot);

create index cup_ties_home_participant_id_idx
  on public.cup_ties (home_participant_id);

create index cup_ties_away_participant_id_idx
  on public.cup_ties (away_participant_id);

create index cup_ties_winner_participant_id_idx
  on public.cup_ties (winner_participant_id);

-- A participant occupies exactly one slot per round. Two partial unique
-- indexes would only catch duplicates within the same column, so the
-- cross-column invariant is enforced by a statement trigger. The table holds
-- 63 rows per Cup, which makes the full check cheaper than transition tables.
create or replace function public.assert_cup_round_participants()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_round_id bigint;
  v_participant_id bigint;
begin
  select side.round_id, side.participant_id
  into v_round_id, v_participant_id
  from (
    select tie.round_id, tie.home_participant_id as participant_id
    from public.cup_ties as tie
    where tie.home_participant_id is not null
    union all
    select tie.round_id, tie.away_participant_id
    from public.cup_ties as tie
    where tie.away_participant_id is not null
  ) as side
  group by side.round_id, side.participant_id
  having count(*) > 1
  limit 1;

  if v_round_id is not null then
    raise exception using
      errcode = '23505',
      message = format(
        'Cup participant %s appears more than once in round %s',
        v_participant_id,
        v_round_id
      );
  end if;

  return null;
end;
$function$;

comment on function public.assert_cup_round_participants()
is 'Rejects any write that would place the same Cup participant in two ties of the same round.';

create trigger cup_ties_unique_round_participants
after insert or update
on public.cup_ties
for each statement
execute function public.assert_cup_round_participants();

-- The classic seeded fold, used purely as a POSITION TEMPLATE. Starting from a
-- single slot the list is doubled by appending each position's mirror label,
-- which yields 1-64, 32-33, 16-49, 17-48 ... for a 64 slot bracket. The labels
-- are bracket positions, not player rankings: only the top 8 ranking positions
-- are mapped onto their matching label, everyone else is drawn.
--
--   fold_position     - physical order down the bracket, 1..64. Fold positions
--                       2k-1 and 2k form round 1 slot k.
--   bracket_position  - the classic label of that slot. Every round 1 pair of
--                       labels sums to bracket_size + 1.
create or replace function public.players_cup_bracket_slots(
  p_bracket_size integer
)
returns table (
  fold_position integer,
  bracket_position integer
)
language sql
immutable
set search_path = ''
as $function$
  with recursive fold as (
    select
      1::integer as size,
      1::integer as fold_position,
      1::integer as bracket_position
    union all
    select
      (fold.size * 2)::integer,
      (fold.fold_position * 2 - (case when mirror.flag then 0 else 1 end))::integer,
      (
        case
          when mirror.flag then fold.size * 2 + 1 - fold.bracket_position
          else fold.bracket_position
        end
      )::integer
    from fold
    cross join (values (false), (true)) as mirror(flag)
    where fold.size < p_bracket_size
  )
  select fold.fold_position, fold.bracket_position
  from fold
  where fold.size = p_bracket_size
  order by fold.fold_position;
$function$;

comment on function public.players_cup_bracket_slots(integer)
is 'Standard bracket position template. Fold positions 2k-1 and 2k form round 1 slot k, and their bracket position labels always sum to bracket_size + 1.';

-- Bye entitlement, derived from the template rather than hardcoded per field
-- size. With N players the occupied slots are the labels 1..N, and a player
-- first meets a real opponent in the earliest round whose merge group already
-- contains another occupied slot. Round r merges the fold positions into
-- groups of 2^r, so this is pure arithmetic on the template.
--
-- Every position sharing an entry round carries the same entitlement, which is
-- the only pool the draw is allowed to shuffle within.
create or replace function public.players_cup_entry_rounds(
  p_participant_count integer
)
returns table (
  bracket_position integer,
  entry_round integer
)
language sql
immutable
set search_path = ''
as $function$
  with occupied as (
    select
      slot_template.bracket_position,
      slot_template.fold_position
    from public.players_cup_bracket_slots(64) as slot_template
    where slot_template.bracket_position <= p_participant_count
  ),
  merge_group as (
    select
      occupied.bracket_position,
      round_number.value as round_number,
      (occupied.fold_position - 1) / (1 << round_number.value) as group_index
    from occupied
    cross join generate_series(1, 6) as round_number(value)
  )
  select
    merge_group.bracket_position,
    min(merge_group.round_number)::integer as entry_round
  from merge_group
  join merge_group as opponent
    on opponent.round_number = merge_group.round_number
    and opponent.group_index = merge_group.group_index
    and opponent.bracket_position <> merge_group.bracket_position
  group by merge_group.bracket_position;
$function$;

comment on function public.players_cup_entry_rounds(integer)
is 'Round in which each occupied bracket position first meets a real opponent, for a field of the given size. Positions sharing an entry round share a bye entitlement.';

-- The draw. Ranking positions 1 to 8 are tournament seeds and are pinned to
-- their protected bracket positions, which the template keeps in eight
-- different eighth-brackets so they cannot meet before the quarter-finals.
-- Everyone else is shuffled, but only inside their own entry-round group, so a
-- draw can never hand a lower-ranked player a better entry round than a higher
-- ranked one.
--
-- The shuffle is a hash of draw_seed and user_id, so the same seed and the same
-- ranking always rebuild exactly the same bracket.
create or replace function public.players_cup_draw(
  p_draw_seed uuid,
  p_participants jsonb
)
returns table (
  rank_position integer,
  user_id uuid,
  bracket_position integer,
  entry_round integer,
  is_protected_seed boolean
)
language plpgsql
stable
set search_path = ''
as $function$
declare
  c_bracket_size constant integer := 64;
  c_protected_seed_count constant integer := 8;
  v_participant_count integer := jsonb_array_length(p_participants);
begin
  if v_participant_count is null
    or v_participant_count < 2
    or v_participant_count > c_bracket_size
  then
    raise exception using
      errcode = '22023',
      message = format(
        'The Cup draw needs between 2 and %s participants',
        c_bracket_size
      );
  end if;

  -- Everything below relies on the template ordering its own positions by
  -- entitlement: position 1 must carry the best entry round and position N the
  -- worst. That makes ranking position r and bracket position r land in the
  -- same entitlement group, which is what lets the top 8 be pinned without
  -- disturbing the tiers.
  if exists (
    select 1
    from (
      select
        entitlement.bracket_position,
        row_number() over (
          order by entitlement.entry_round desc, entitlement.bracket_position
        ) as entitlement_order
      from public.players_cup_entry_rounds(v_participant_count) as entitlement
    ) as ordered
    where ordered.bracket_position <> ordered.entitlement_order
  ) then
    raise exception using
      errcode = '55000',
      message = 'The bracket template does not order entry-round entitlement by position';
  end if;

  return query
  with participant as (
    select
      (ranked.entry->>'rank_position')::integer as rank_position,
      (ranked.entry->>'user_id')::uuid as user_id
    from jsonb_array_elements(p_participants) as ranked(entry)
  ),
  entitlement as (
    select
      grouped.bracket_position,
      grouped.entry_round
    from public.players_cup_entry_rounds(v_participant_count) as grouped
  ),
  protected_placement as (
    select
      participant.rank_position,
      participant.user_id,
      participant.rank_position as bracket_position,
      true as is_protected_seed
    from participant
    where participant.rank_position <= c_protected_seed_count
  ),
  drawn_player as (
    select
      participant.rank_position,
      participant.user_id,
      entitlement.entry_round,
      row_number() over (
        partition by entitlement.entry_round
        order by decode(
          md5(p_draw_seed::text || ':' || participant.user_id::text),
          'hex'
        )
      ) as draw_order
    from participant
    -- Ranking position r belongs to the entitlement group of bracket position
    -- r, which the invariant above guarantees.
    join entitlement
      on entitlement.bracket_position = participant.rank_position
    where participant.rank_position > c_protected_seed_count
  ),
  drawn_position as (
    select
      entitlement.bracket_position,
      entitlement.entry_round,
      row_number() over (
        partition by entitlement.entry_round
        order by entitlement.bracket_position
      ) as position_order
    from entitlement
    where entitlement.bracket_position > c_protected_seed_count
  ),
  drawn_placement as (
    select
      drawn_player.rank_position,
      drawn_player.user_id,
      drawn_position.bracket_position,
      false as is_protected_seed
    from drawn_player
    join drawn_position
      on drawn_position.entry_round = drawn_player.entry_round
      and drawn_position.position_order = drawn_player.draw_order
  ),
  placement as (
    select * from protected_placement
    union all
    select * from drawn_placement
  )
  select
    placement.rank_position,
    placement.user_id,
    placement.bracket_position,
    entitlement.entry_round,
    placement.is_protected_seed
  from placement
  join entitlement
    on entitlement.bracket_position = placement.bracket_position
  order by placement.rank_position;
end;
$function$;

comment on function public.players_cup_draw(uuid, jsonb)
is 'Places the frozen ranking into the 64 position template: ranking positions 1 to 8 keep their protected seed positions, everyone else is shuffled inside their own entry-round group by a hash of draw_seed and user_id.';

-- Strict total order over active players, derived only from League Phase
-- Matchday 1 and 2 results. Long-term awards, Cup points and Matchday 3+
-- results are structurally excluded, and the username/user_id terms guarantee
-- that no two players can share a rank position.
create or replace function public.players_cup_ranking()
returns table (
  rank_position integer,
  user_id uuid,
  username text,
  total_points bigint,
  exact_scores bigint,
  correct_results bigint,
  missed_predictions bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  with ranking_matches as (
    select match_row.id, match_row.status
    from public.matches as match_row
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
  ),
  ranking_predictions as (
    select
      prediction.id,
      prediction.user_id,
      prediction.points,
      ranking_matches.status as match_status
    from public.predictions as prediction
    join ranking_matches
      on ranking_matches.id = prediction.match_id
  ),
  finished_ranking_matches as (
    select count(*)::bigint as finished_count
    from ranking_matches
    where ranking_matches.status = 'finished'
  ),
  player_stats as (
    select
      profile.id as user_id,
      profile.username,
      coalesce(sum(prediction.points), 0)::bigint as total_points,
      count(prediction.id)
        filter (where prediction.points in (5, 10))::bigint as exact_scores,
      count(prediction.id)
        filter (where prediction.points in (2, 4))::bigint as correct_results,
      (
        (select finished_count from finished_ranking_matches)
        - count(prediction.id)
          filter (where prediction.match_status = 'finished')
      )::bigint as missed_predictions
    from public.profiles as profile
    left join ranking_predictions as prediction
      on prediction.user_id = profile.id
    where profile.status = 'active'
    group by profile.id, profile.username
  )
  select
    row_number() over (
      order by
        player_stats.total_points desc,
        player_stats.exact_scores desc,
        player_stats.correct_results desc,
        player_stats.missed_predictions asc,
        lower(player_stats.username) asc,
        player_stats.user_id asc
    )::integer as rank_position,
    player_stats.user_id,
    player_stats.username,
    player_stats.total_points,
    player_stats.exact_scores,
    player_stats.correct_results,
    player_stats.missed_predictions
  from player_stats
  order by rank_position;
$function$;

comment on function public.players_cup_ranking()
is 'Strict Players Cup ranking from League Phase Matchday 1 and 2 only. Never includes long-term awards or Matchday 3+ results. Position 1 is the best ranking.';

create or replace function public.create_players_cup(
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  c_season_label constant text := 'Champions League 2026/27';
  c_bracket_size constant integer := 64;
  c_minimum_participants constant integer := 8;
  c_protected_seed_count constant integer := 8;
  -- Initial reward configuration. Once the row exists it is the only source of
  -- truth; award calculation must never read these constants.
  c_winner_points constant integer := 30;
  c_finalist_points constant integer := 20;
  c_semi_finalist_points constant integer := 10;

  v_admin_id uuid := (select auth.uid());
  v_cup_id bigint;
  v_summary jsonb;
  v_ranking jsonb;
  v_participants jsonb;
  -- One draw seed per call. A dry run returns it as a preview seed and throws
  -- it away; a real creation persists it alongside the bracket it produced.
  v_draw_seed uuid := gen_random_uuid();
  v_draw jsonb;
  v_preview jsonb;
  v_eligible_count integer;
  v_participant_count integer;
  v_matchday_count integer;
  v_ranking_match_count integer;
  v_ranking_finished_count integer;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Serializes concurrent creation attempts. The lock is released at commit or
  -- rollback, so two simultaneous callers converge on one competition instead
  -- of racing on the unique slug.
  perform pg_advisory_xact_lock(
    hashtext('public.create_players_cup:' || c_slug)::bigint
  );

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug
  for update;

  -- The Cup is never regenerated. An existing bracket is reported back
  -- untouched, for a dry run and for a normal call alike.
  if v_cup_id is not null then
    select jsonb_build_object(
      'already_exists', true,
      'created', false,
      'dry_run', p_dry_run,
      'cup_id', competition.id,
      'slug', competition.slug,
      'season_label', competition.season_label,
      'status', competition.status,
      'bracket_size', competition.bracket_size,
      'protected_seed_count', c_protected_seed_count,
      'participant_count', competition.participant_count,
      'draw_seed', competition.draw_seed,
      'draw_is_preview', false,
      'created_at', competition.created_at,
      'rewards', jsonb_build_object(
        'winner_points', competition.winner_points,
        'finalist_points', competition.finalist_points,
        'semi_finalist_points', competition.semi_finalist_points
      ),
      'round_count', (
        select count(*)
        from public.cup_rounds as round
        where round.cup_id = competition.id
      ),
      'tie_count', (
        select count(*)
        from public.cup_ties as tie
        where tie.cup_id = competition.id
      ),
      'round_one', (
        select jsonb_build_object(
          'real_tie_count',
            count(*) filter (where tie.outcome = 'pending'),
          'bye_count',
            count(*) filter (where tie.outcome = 'bye'),
          'empty_tie_count',
            count(*) filter (where tie.outcome = 'empty')
        )
        from public.cup_ties as tie
        join public.cup_rounds as round
          on round.id = tie.round_id
        where round.cup_id = competition.id
          and round.round_number = 1
      )
    )
    into v_summary
    from public.cup_competitions as competition
    where competition.id = v_cup_id;

    return v_summary;
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  if v_matchday_count <> 6 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 3 to 8 must all exist before the Players Cup can be created';
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_matchday_count <> 2 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 are required for a deterministic ranking';
  end if;

  -- Freezes the ranking inputs for the rest of the transaction, so a result
  -- correction cannot land between the preview and the written bracket.
  perform 1
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2
  order by match_row.id
  for share of match_row;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into v_ranking_match_count, v_ranking_finished_count
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_ranking_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 have no configured matches';
  end if;

  if v_ranking_finished_count <> v_ranking_match_count then
    raise exception using
      errcode = '22023',
      message = 'The Cup ranking requires every League Phase Matchday 1 and 2 match to be finished';
  end if;

  if exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
      and prediction.points is null
  ) then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchday 1 and 2 predictions are not fully scored';
  end if;

  -- Single evaluation of the ranking. Everything below reads this snapshot, so
  -- a registration committed mid-call cannot change the written bracket.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank_position', ranking.rank_position,
          'user_id', ranking.user_id,
          'username', ranking.username,
          'total_points', ranking.total_points,
          'exact_scores', ranking.exact_scores,
          'correct_results', ranking.correct_results,
          'missed_predictions', ranking.missed_predictions
        )
        order by ranking.rank_position
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_ranking, v_eligible_count
  from public.players_cup_ranking() as ranking;

  if v_eligible_count < c_minimum_participants then
    raise exception using
      errcode = '22023',
      message = format(
        'The Players Cup needs at least %s active players, found %s',
        c_minimum_participants,
        v_eligible_count
      );
  end if;

  v_participant_count := least(v_eligible_count, c_bracket_size);

  select coalesce(
    jsonb_agg(ranked.entry order by (ranked.entry->>'rank_position')::integer),
    '[]'::jsonb
  )
  into v_participants
  from jsonb_array_elements(v_ranking) as ranked(entry)
  where (ranked.entry->>'rank_position')::integer <= v_participant_count;

  -- Drawn once. The preview and the persisted bracket are built from this one
  -- result, so what an admin sees is exactly what gets written.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank_position', placement.rank_position,
        'user_id', placement.user_id,
        'bracket_position', placement.bracket_position,
        'entry_round', placement.entry_round,
        'is_protected_seed', placement.is_protected_seed
      )
      order by placement.rank_position
    ),
    '[]'::jsonb
  )
  into v_draw
  from public.players_cup_draw(v_draw_seed, v_participants) as placement;

  with ranking_entry as (
    select
      (ranked.entry->>'rank_position')::integer as rank_position,
      (ranked.entry->>'user_id')::uuid as user_id,
      ranked.entry->>'username' as username,
      (ranked.entry->>'total_points')::bigint as total_points,
      (ranked.entry->>'exact_scores')::bigint as exact_scores,
      (ranked.entry->>'correct_results')::bigint as correct_results,
      (ranked.entry->>'missed_predictions')::bigint as missed_predictions
    from jsonb_array_elements(v_ranking) as ranked(entry)
  ),
  placement as (
    select
      (drawn.entry->>'rank_position')::integer as rank_position,
      (drawn.entry->>'bracket_position')::integer as bracket_position,
      (drawn.entry->>'entry_round')::integer as entry_round,
      (drawn.entry->>'is_protected_seed')::boolean as is_protected_seed
    from jsonb_array_elements(v_draw) as drawn(entry)
  ),
  placed_player as (
    select
      placement.rank_position,
      placement.bracket_position,
      placement.entry_round,
      placement.is_protected_seed,
      ranking_entry.user_id,
      ranking_entry.username
    from placement
    join ranking_entry
      on ranking_entry.rank_position = placement.rank_position
  ),
  pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  tie_preview as (
    select
      pairing.slot,
      pairing.home_bracket_position,
      pairing.away_bracket_position,
      home_player.rank_position as home_rank_position,
      away_player.rank_position as away_rank_position,
      home_player.username as home_username,
      away_player.username as away_username,
      case
        when home_player.rank_position is null
          and away_player.rank_position is null then 'empty'
        when home_player.rank_position is null
          or away_player.rank_position is null then 'bye'
        else 'pending'
      end as outcome
    from pairing
    left join placed_player as home_player
      on home_player.bracket_position = pairing.home_bracket_position
    left join placed_player as away_player
      on away_player.bracket_position = pairing.away_bracket_position
  ),
  participant_preview as (
    select
      placed_player.rank_position,
      placed_player.bracket_position,
      placed_player.entry_round,
      placed_player.is_protected_seed,
      placed_player.user_id,
      placed_player.username,
      ranking_entry.total_points,
      ranking_entry.exact_scores,
      ranking_entry.correct_results,
      ranking_entry.missed_predictions,
      tie_preview.slot as round_one_slot,
      tie_preview.outcome as round_one_outcome
    from placed_player
    join ranking_entry
      on ranking_entry.rank_position = placed_player.rank_position
    join tie_preview
      on tie_preview.home_bracket_position = placed_player.bracket_position
      or tie_preview.away_bracket_position = placed_player.bracket_position
  )
  select jsonb_build_object(
    'already_exists', false,
    'dry_run', p_dry_run,
    'slug', c_slug,
    'season_label', c_season_label,
    'status', 'active',
    'bracket_size', c_bracket_size,
    'protected_seed_count', c_protected_seed_count,
    'minimum_participants', c_minimum_participants,
    'eligible_count', v_eligible_count,
    'participant_count', v_participant_count,
    'excluded_count', v_eligible_count - v_participant_count,
    'draw_seed', v_draw_seed,
    -- A dry run seed is thrown away: two previews before creation may differ,
    -- and only the seed stored by the real creation describes the real bracket.
    'draw_is_preview', p_dry_run,
    'rewards', jsonb_build_object(
      'winner_points', c_winner_points,
      'finalist_points', c_finalist_points,
      'semi_finalist_points', c_semi_finalist_points
    ),
    'rounds', (
      select jsonb_agg(
        jsonb_build_object(
          'round_number', matchday.matchday_number - 2,
          'slot_count', case matchday.matchday_number
            when 3 then 64
            when 4 then 32
            when 5 then 16
            when 6 then 8
            when 7 then 4
            else 2
          end,
          'tie_count', case matchday.matchday_number
            when 3 then 32
            when 4 then 16
            when 5 then 8
            when 6 then 4
            when 7 then 2
            else 1
          end,
          'matchday_id', matchday.id,
          'matchday_number', matchday.matchday_number,
          'matchday_name', matchday.name
        )
        order by matchday.matchday_number
      )
      from public.matchdays as matchday
      where matchday.stage = 'league_phase'
        and matchday.matchday_number between 3 and 8
    ),
    'entry_round_entitlement', (
      select jsonb_agg(
        jsonb_build_object(
          'entry_round', tier.entry_round,
          'matchday_number', tier.entry_round + 2,
          'player_count', tier.player_count,
          'first_rank_position', tier.first_rank_position,
          'last_rank_position', tier.last_rank_position
        )
        order by tier.entry_round
      )
      from (
        select
          participant_preview.entry_round,
          count(*) as player_count,
          min(participant_preview.rank_position) as first_rank_position,
          max(participant_preview.rank_position) as last_rank_position
        from participant_preview
        group by participant_preview.entry_round
      ) as tier
    ),
    'top_8_seeded', (
      select jsonb_agg(
        jsonb_build_object(
          'rank_position', participant_preview.rank_position,
          'user_id', participant_preview.user_id,
          'username', participant_preview.username,
          'bracket_position', participant_preview.bracket_position,
          'entry_round', participant_preview.entry_round
        )
        order by participant_preview.rank_position
      )
      from participant_preview
      where participant_preview.is_protected_seed
    ),
    'round_one', jsonb_build_object(
      'real_tie_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'pending'
      ),
      'bye_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'bye'
      ),
      'empty_tie_count', (
        select count(*)
        from tie_preview
        where tie_preview.outcome = 'empty'
      ),
      'ties', (
        select jsonb_agg(
          jsonb_build_object(
            'slot', tie_preview.slot,
            'home_bracket_position', tie_preview.home_bracket_position,
            'away_bracket_position', tie_preview.away_bracket_position,
            'home_rank_position', tie_preview.home_rank_position,
            'away_rank_position', tie_preview.away_rank_position,
            'home_username', tie_preview.home_username,
            'away_username', tie_preview.away_username,
            'outcome', tie_preview.outcome
          )
          order by tie_preview.slot
        )
        from tie_preview
      )
    ),
    'participants', (
      select jsonb_agg(
        jsonb_build_object(
          'rank_position', participant_preview.rank_position,
          'user_id', participant_preview.user_id,
          'username', participant_preview.username,
          'bracket_position', participant_preview.bracket_position,
          'entry_round', participant_preview.entry_round,
          'entry_matchday_number', participant_preview.entry_round + 2,
          'is_protected_seed', participant_preview.is_protected_seed,
          'is_drawn', not participant_preview.is_protected_seed,
          'total_points', participant_preview.total_points,
          'exact_scores', participant_preview.exact_scores,
          'correct_results', participant_preview.correct_results,
          'missed_predictions', participant_preview.missed_predictions,
          'round_one_slot', participant_preview.round_one_slot,
          'round_one_outcome', participant_preview.round_one_outcome
        )
        order by participant_preview.rank_position
      )
      from participant_preview
    ),
    'excluded', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'rank_position', ranking_entry.rank_position,
            'user_id', ranking_entry.user_id,
            'username', ranking_entry.username
          )
          order by ranking_entry.rank_position
        ),
        '[]'::jsonb
      )
      from ranking_entry
      where ranking_entry.rank_position > v_participant_count
    )
  )
  into v_preview;

  if p_dry_run then
    return v_preview || jsonb_build_object(
      'created', false,
      'cup_id', null::bigint
    );
  end if;

  insert into public.cup_competitions (
    slug,
    season_label,
    bracket_size,
    participant_count,
    status,
    draw_seed,
    winner_points,
    finalist_points,
    semi_finalist_points,
    created_by
  )
  values (
    c_slug,
    c_season_label,
    c_bracket_size,
    v_participant_count,
    'active',
    v_draw_seed,
    c_winner_points,
    c_finalist_points,
    c_semi_finalist_points,
    v_admin_id
  )
  returning cup_competitions.id into v_cup_id;

  insert into public.cup_participants (
    cup_id,
    user_id,
    username_snapshot,
    rank_position,
    bracket_position,
    entry_round
  )
  select
    v_cup_id,
    (drawn.entry->>'user_id')::uuid,
    ranked.entry->>'username',
    (drawn.entry->>'rank_position')::integer,
    (drawn.entry->>'bracket_position')::integer,
    (drawn.entry->>'entry_round')::integer
  from jsonb_array_elements(v_draw) as drawn(entry)
  join jsonb_array_elements(v_ranking) as ranked(entry)
    on (ranked.entry->>'rank_position')::integer
      = (drawn.entry->>'rank_position')::integer;

  insert into public.cup_rounds (
    cup_id,
    round_number,
    slot_count,
    matchday_id,
    status
  )
  select
    v_cup_id,
    matchday.matchday_number - 2,
    case matchday.matchday_number
      when 3 then 64
      when 4 then 32
      when 5 then 16
      when 6 then 8
      when 7 then 4
      else 2
    end,
    matchday.id,
    'pending'
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  -- The whole skeleton exists from creation: 32+16+8+4+2+1 ties. Progression
  -- will only ever update these rows.
  insert into public.cup_ties (cup_id, round_id, slot, outcome)
  select v_cup_id, round.id, slot_series.slot, 'empty'
  from public.cup_rounds as round
  cross join lateral generate_series(1, round.slot_count / 2) as slot_series(slot)
  where round.cup_id = v_cup_id;

  with pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  resolved as (
    select
      pairing.slot,
      home_participant.id as home_participant_id,
      away_participant.id as away_participant_id
    from pairing
    left join public.cup_participants as home_participant
      on home_participant.cup_id = v_cup_id
      and home_participant.bracket_position = pairing.home_bracket_position
    left join public.cup_participants as away_participant
      on away_participant.cup_id = v_cup_id
      and away_participant.bracket_position = pairing.away_bracket_position
  )
  update public.cup_ties as tie
  set
    home_participant_id = resolved.home_participant_id,
    away_participant_id = resolved.away_participant_id,
    winner_participant_id = case
      when resolved.home_participant_id is null
        then resolved.away_participant_id
      when resolved.away_participant_id is null
        then resolved.home_participant_id
      else null
    end,
    outcome = case
      when resolved.home_participant_id is null
        and resolved.away_participant_id is null then 'empty'
      when resolved.home_participant_id is null
        or resolved.away_participant_id is null then 'bye'
      else 'pending'
    end,
    updated_at = now()
  from resolved
  join public.cup_rounds as round
    on round.cup_id = v_cup_id
    and round.round_number = 1
  where tie.round_id = round.id
    and tie.slot = resolved.slot;

  return v_preview || jsonb_build_object(
    'created', true,
    'cup_id', v_cup_id
  );
end;
$function$;

comment on function public.create_players_cup(boolean)
is 'Admin-only Players Cup creation. Freezes the Matchday 1-2 ranking, protects the top 8, draws everyone else inside their entry-round group from a persisted draw_seed, writes the full six round and 63 tie skeleton, and never regenerates an existing Cup. Scoring, progression and awards are out of scope.';

alter table public.cup_competitions enable row level security;
alter table public.cup_participants enable row level security;
alter table public.cup_rounds enable row level security;
alter table public.cup_ties enable row level security;

-- Read-only for players. No insert, update or delete policy exists on any Cup
-- table, so the Data API rejects every browser write before column grants are
-- considered.
create policy "Authenticated users can view the Players Cup"
  on public.cup_competitions
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup participants"
  on public.cup_participants
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup rounds"
  on public.cup_rounds
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view Cup ties"
  on public.cup_ties
  for select
  to authenticated
  using (true);

revoke all privileges on table public.cup_competitions
  from public, anon, authenticated;
revoke all privileges on table public.cup_participants
  from public, anon, authenticated;
revoke all privileges on table public.cup_rounds
  from public, anon, authenticated;
revoke all privileges on table public.cup_ties
  from public, anon, authenticated;

grant select on table public.cup_competitions to authenticated;
grant select on table public.cup_participants to authenticated;
grant select on table public.cup_rounds to authenticated;
grant select on table public.cup_ties to authenticated;

grant all privileges on table public.cup_competitions to service_role;
grant all privileges on table public.cup_participants to service_role;
grant all privileges on table public.cup_rounds to service_role;
grant all privileges on table public.cup_ties to service_role;

revoke all privileges on sequence public.cup_competitions_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_participants_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_rounds_id_seq
  from public, anon, authenticated;
revoke all privileges on sequence public.cup_ties_id_seq
  from public, anon, authenticated;

grant all privileges on sequence public.cup_competitions_id_seq to service_role;
grant all privileges on sequence public.cup_participants_id_seq to service_role;
grant all privileges on sequence public.cup_rounds_id_seq to service_role;
grant all privileges on sequence public.cup_ties_id_seq to service_role;

-- The browser may invoke the creation RPC, but the function rejects every
-- caller who is not an active administrator.
revoke execute on function public.create_players_cup(boolean)
  from public, anon;
grant execute on function public.create_players_cup(boolean)
  to authenticated, service_role;

-- Internal helpers. players_cup_ranking aggregates every player's predictions,
-- so it must never be reachable from the browser.
revoke execute on function public.players_cup_ranking()
  from public, anon, authenticated;
grant execute on function public.players_cup_ranking()
  to service_role;

revoke execute on function public.players_cup_bracket_slots(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_bracket_slots(integer)
  to service_role;

revoke execute on function public.players_cup_entry_rounds(integer)
  from public, anon, authenticated;
grant execute on function public.players_cup_entry_rounds(integer)
  to service_role;

revoke execute on function public.players_cup_draw(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.players_cup_draw(uuid, jsonb)
  to service_role;

revoke execute on function public.assert_cup_round_participants()
  from public, anon, authenticated;
